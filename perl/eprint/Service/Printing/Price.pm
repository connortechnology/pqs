package eprint::Service::Printing::Price;
use strict;
use warnings;
use utf8;
no warnings qw(uninitialized numeric);

use constant DEBUG=>0;
my $cutters = 0;

use Data::Dumper;

use Compress::LZF         qw(:compress :freeze);
use Storable              qw(freeze);
use List::Util            qw(sum);
use List::MoreUtils       qw(uniq);
use MIME::Base64;
use POSIX                 qw(ceil floor);
use Readonly;

use Apache2::Log;
use Apache2::ServerUtil;

use PQS::Constants;
use PQS::Equipment;
use PQS::Imposition::Node;
use PQS::model::service;
use PQS::model::materials;

use eprint::Config;
use eprint::Service::Printing::Impose qw(impositions wx_colours wx_press_units);
use eprint::Service::Printing::Substrate;
use eprint::Service::Cutting ();

use eprint::imposition;
use eprint::project        qw(:common get_bindery_type get_lf_jobsize mp_versions );
use eprint::service        qw(:common :specs :status get_service_full_price );
use eprint::equipment      ();
use eprint::print_project  qw(:common);
use sql                    ();
use callback;

require configuration;
require misc;
require eprint::material;
require eprint::imposition;
require eprint::paper;
require openprint;
require openprint::Service;
require openprint::Equipment;
require openprint::Estimating::Proofs;
require openprint::Estimating::Cutting;

use vars qw( $r %variable %session %param %config $log $dbh $starttime );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;
my $variable = \%variable;

my $global_iterator;

use base qw(Exporter);
our @EXPORT      = 'calc';
our @EXPORT_OK   = qw(count_completed_spreads signatures_of_type spreads_remaining);
our %EXPORT_TAGS = ( all => \@EXPORT_OK, );

# Press run styles.
use constant RUN_STYLES => qw(SW WT WF PF);

# When creating screens for screen printing material on all four sides of the
# imager is required to stretch around the frame.
use constant SCREEN_LAP => eprint::Config->get(Printing => 'screen_lap'); # inches


# Ink coverage for pricing. No one here is sure what exactly a 'sheet' is or
# what the exact measurement of 'unit' is. These are part of the black magic
# that is currently ink pricing.
use constant SHEETS_PER_UNIT_PANTONE  => eprint::Config->get(Printing => 'sheets_per_unit_pantone');
use constant SHEETS_PER_UNIT_METALLIC => eprint::Config->get(Printing => 'sheets_per_unit_metallic');




# Map the individual bindery types to the class of bindery they belong to.
Readonly my %BINDERY_CLASS => (
  PerfectBinding  => 'Perfect', # Notch, Otabind, etc.

  SaddleStitching => 'Stitching',
  LoopStitching   => 'Stitching',

  Cerlox          => 'Spiral',
  DoubleLoopWire  => 'Spiral',
  PlasticCoil     => 'Spiral',
  MetalCoil       => 'Spiral',
  '3HolePunch'   	=> 'Spiral',
  SingleHole   	=> 'Spiral',
  CornerStitching => 'Spiral',
  Proclick     	=> 'Spiral',
);

# Debug/profiling timings.
our ($ts_req, $te_req, $ts_impose, $te_impose, $ts_price, $te_price, $total_imp);

use constant TIMINGS => 0;

sub calc {
  my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

  my $ac = sql::start_transaction($dbh); # For speed

  my $pricing = get_project_price($pid, $sid, @$specs{qw(spread versions overrides)}, $specs);

  # Keep Version information. Needed for auto-calc.
  delete $specs->{$_} for grep {! $_ =~ /mv/} keys %$specs;

  $specs->{$_} = $pricing->{$_} for keys %$pricing;
  sql::end_transaction($dbh, $ac);
  return exists $specs->{error} ? 'uncalculated' : 'calculated';
}

# Price the spread.
sub get_project_price {
  my ($pid, $sid, $spread, $versions, $overrides, $specs) = @_;

  #HANDLE NEW No PRINT PROJECT TYPE
  my $Project = new openprint::Project($pid);
  my $type = $Project->type();
  return undef if $type eq 'NoPrint';

  eprint::Service::Cutting::init($pid);
  openprint::Estimating::Cutting::init($Project);
  #my $s;
  #return {error =>  'Missing Specs width and height'} unless $spread->{flat}{width} and $spread->{flat}{height};
  # DONE NOPRINT

  return {error => 'Required Specs not found: colour'}
  unless @{$spread->{side}[0]{colours}} || @{$spread->{side}[1]{colours}} ;

  if ($Project->is_presentation_folder() and ! $spread->{template}) {
    return {error => 'Required Specs not found: please select the type of presentation folder'};
  }

  ## MAPPINGS
  #
  # Translate the (better than 40+ params) data structure into some of the
  # older parameters the pricing functions still use. TODO The project
  # structure is an amalgam of old and (and not overly thought out) new.
  # There is a lot of room for improvemnt in the initial structure. TODO
  # Clean up more of these (or rewrite) as time permits.

  my $large_format      = $spread->{large_format};
  my $jig_specifics     = $spread->{screen_jig};   # screen only
  my $additional_plates = $spread->{add_plates};

  my $qtys = [ get_quantities($log, $dbh, $pid) ];

  # If we are making a scratch pad then we simply multiply our qty by the number
  # of sheets per pad. This is one of the last exceptions that was handled by
  # the javascript pre-pricing code.
  if ( $spread->{pad_sheets} > 1 ) {
    for my $i ( 0 .. 2 ) {
      @$qtys[$i] *= $spread->{pad_sheets};
    }
  }

  # COLOURS AND VARNISHES
  #
  # Turn our data structure (which is not great but okay) into the crap
  # get_book_price() needs for now.
  my (@colours, %pms_coverage);
  for my $s ( @{$spread->{side}} ) {
    my @inks;

    for my $c ( @{$s->{colours}} ) {
      # If we're a varnish our name is a concatenation of "(spot|flood)
      # Varnish $type)".
      if ($c->{type} eq 'varnish') {
        # Are we a flood or a spot varnish?
        my $fill = ($c->{coverage} == 100) ? 'Overall' : 'Spot';

        push @inks, "$fill Varnish " . ucfirst($c->{name});
      }
      # Otherwise the colour is just the name.
      else {
        push @inks, ucfirst($c->{name});

        # PMS colours though get another list for themselves. This
        # time a hash of name => coverage flattened into a string.
        if ($c->{type} eq 'pantone') {
          $pms_coverage{$c->{name}} += $c->{coverage};
        }
      }
    }
    push @colours, \@inks;
  }

  # VARNISHES, AQUEOUS AND UV COATINGS
  my $dry_trap = $spread->{side}[0]{dry_trap} + $spread->{side}[1]{dry_trap};

  my $has_aq  = (scalar grep {$_ eq 'aqueous'} map {$spread->{side}[$_]{coating}{type}} 0..1);
  my $has_uv  = (scalar grep {$_ eq 'uv'     } map {$spread->{side}[$_]{coating}{type}} 0..1);
  my $has_softtouch  = (scalar grep {$_ eq 'soft_touch'     } map {$spread->{side}[$_]{coating}{type}} 0..1);
  my $is_spot = (scalar grep {$_             } map {$spread->{side}[$_]{coating}{spot}} 0..1) > 0;

  my $print_container = get_print_container($log, $dbh, $pid);
  my $print_specs = openprint::service::get_specs_ref($Project, $print_container);
  my $pages = $$print_specs{txtTotalSpreadQuantity} || 1;

  my $press_type = get_press_type($log, $dbh, $pid, $sid);
  my $is_multipage = is_multipage($log, $dbh, $pid);
  # PROJECT
  # Create a much more useful project info hash. TODO Hopefully to become a
  # heirarchy of object soon. (Service type info broken from project etc.)
  my $WEB_COLOUR_BAR_SIZE = $openprint::config{web_colour_bar_size} // eprint::Config->get(Imposition => 'web_colour_bar_size');
  my $STD_COLOUR_BAR_SIZE = $openprint::config{std_colour_bar_size} // eprint::Config->get(Imposition => 'std_colour_bar_size');
  my $project = {
    id           => $pid,
    type         => scalar($type),
    is_multipage => $is_multipage,
    press_type   => $press_type,
    quantities   => $qtys,

    image_width  => $spread->{flat}{width},  # -- DEPRECATED
    image_height => $spread->{flat}{height}, # -|
    width        => $spread->{flat}{width},
    height       => $spread->{flat}{height},
    minwidth     => scalar( get_minimum_width($log, $dbh, $pid) ),
    minheight    => scalar( get_minimum_height($log, $dbh, $pid) ),

    template     => $spread->{template},

    colour_bar   => ($spread->{colour_bar} ? $press_type eq 'web' ? $WEB_COLOUR_BAR_SIZE : $STD_COLOUR_BAR_SIZE : 0),

    versions     => $versions,
    colours      => \@colours,
    aqueous      => $has_aq,
    uv           => $has_uv,
    softtouch    => $has_softtouch,

    bleed        => $spread->{bleed},
    grain        => $spread->{grain},

    paper        => $spread->{stock},
    pages        => $pages,
    print_container => $print_container,
    print_specifications => $print_specs,

    override => $overrides,

    wx_press_units => wx_press_units($spread), # Cache a copy

    drytrap => [$spread->{side}[0]{dry_trap}, $spread->{side}[1]{dry_trap}],

    metal_effects => $spread->{metal_effects},
    chem_emboss   => $spread->{chem_emboss},
    rfq_only	  => $spread->{rfq_only},
    product_only  => $spread->{product_only},
    screen_foil   => $spread->{screen_foil},
    underbase     => $spread->{underbase},
  };
  $openprint::log->debug("HAVE PROJECT: ". Dumper($project)) if DEBUG;

	my $services = $Project->services();
	foreach my $service ( 'Folding','Scoring','Perforating','DieCutting','Cutting','Numbering','Proofs' ) {
		if ( $$services{$service} and @{$$services{$service}} ) {
			$$project{'Has'.$service} = $$services{$service}[0];
      $$project{$service.'Service'} = $Project->Service($$services{$service}[0]);
			%{$$project{$service.'Specs'}} = %{openprint::service::get_specs_ref( $Project, $$services{$service}[0] )};
		} # end if	
	} # end foreach

  $openprint::log->debug("HAVE PROJECT: ". Dumper($project)) if DEBUG;
  # Load signature specifications.
  if ($is_multipage) {
    my @fields = qw( txtSignatureType txtSpreadWidth txtSpreadHeight txtSignatureSize );

    my $sig_specs = openprint::service::get_specs_ref($Project, $sid);
    $project->{signature} = {};
    @{ $project->{signature} }{@fields} = @$sig_specs{@fields};

    print STDERR "HAVE PROJECT: ", Dumper($project, $spread) if DEBUG;
    $project->{width}  = $spread->{SpreadWidth} if  $spread->{SpreadWidth};
    $project->{height} = $spread->{SpreadHeight} if $spread->{SpreadHeight};

    # Load the preset spread size if the sizes weren't supplied (interior).
    unless ($project->{width} && $project->{height}) {
      @$project{qw(width height)} = @{ $project->{signature} }{qw(txtSpreadWidth txtSpreadHeight)};

      if ($project->{template} && $project->{template} =~ /^(Single|Double)GateFold$/i ) {
        my $multiplier = $1 eq 'Double' ? 2 : 1;
        $project->{width} += $multiplier * $spread->{gatefold_lip};
      }

      @$project{qw(image_width image_height)} = @$project{qw(width height)};
    }
    my $bind_type = $project->{bind_type} = eprint::project::get_bindery_type($log, $dbh, $pid);
    my $bookid = $$project{bookid} = eprint::project::get_service_index($log, $dbh, $pid, 'Book');
    if ($bookid) {
      #need the number of versions if there aren't more than one this function isn't needed
      my ($num_versions) = eprint::service::get_specifications($log, $dbh, $pid, $bookid, ('num_versions'));
      $$project{num_versions} = $num_versions;
    }

    # If we're multi-page and have a bindery type, find out if we need trim.
    # TODO This should really be stored as at compile-time and only looked up
    # in the imposition code.
    if ($bind_type) {
      if ($BINDERY_CLASS{$bind_type}) {
        $project->{trim} = eprint::Config->get(Imposition => lc "trim_$BINDERY_CLASS{$bind_type}") || 0;
      } else {
        $openprint::log->error("No bindery class for $bind_type");
      }
    }
  } else {
    $project->{trim} = 0;
  } # end if multipage

  if (!($project->{width} && $project->{height})) {
    @$project{qw(width height)} = @$print_specs{'final_width','final_height'};
    if (!$$project{txtSignatureSize}) {
      my $bind_type = $$print_specs{template};
      my $double = grep { $bind_type eq $_ } qw(SaddleStitching PerfectBinding);
      $$project{sigature}{txtSignatureSize} = $double ? 4 : 2;
    }
    $$project{width} *= $$project{sigature}{txtSignatureSize} / 2;
  }

  # SUBSTRATE/STOCK/PAPER
  my %paper = %{ $spread->{stock} };

  # Colour bars and ignoring margins don't mix.
  if ($project->{override}{margin}) { $project->{colour_bar} = 0 }

  # Envelope projects get an image width the same size as the envelope.
  if ($project->{type} eq 'Envelopes') {
    # Even though this could match a number of papers we just take the
    # first and pretend it's the only one.
    @$project{qw(image_width image_height)} = $dbh->selectrow_array(q{
      SELECT dblwidth, dblheight
      FROM tbl_paper
      WHERE strname     = ? AND strfinish   = ?
      AND strcolour   = ? AND strcalliper = ?
      ORDER BY dblwidth DESC
      }, {}, @paper{qw(name finish colour calliper)});

    @$project{qw(width height)} = @$project{qw(image_width image_height)};
    if (!$$project{width}) {
      print STDERR "No dimensions found for ".Data::Dumper::Dumper(\%paper)."\n";
    }

    $project->{grain} = 0; # Image orientation is exactly the paper's.

    # Envelopes don't get a colour bar, bleeds, or any grip as we
    # currently assume you can just print over the entire thing.
    $project->{colour_bar}       = 0;
    $project->{override}{margin} = 1;
    $project->{bleed}            = [0,0,0,0];
  }
  # Screen items override their substrate (currently a kludge to just give
  # it an indentical image size/substrate size).
  elsif ($project->{type} eq 'ScreenItem') {
    $project->{override}{substrate} = 'item';
    $project->{override}{margin}    = 1;
    $project->{bleed}               = [0,0,0,0];
    $project->{colour_bar}          = 0;
  }
  if (!($project->{width} && $project->{height})) {
    return {error => 'Required Specs not found: flat width and/or flat height'};
  }

  if ($project->{width} < $project->{minwidth} || $project->{height} < $project->{minheight}) {
    return {'error' => 'Project must be at least ' . $project->{minwidth} . 'x' . $project->{minheight}};
  }
  if (!($paper{name} and $paper{finish} and $paper{colour} and $paper{weight} and $paper{calliper})) {
    return {
      error => join("\n", 'Stock is not fully specified.',
      ($paper{name} ? () : 'Please specify stock name'),
      ($paper{finish} ? () : 'Please specify stock finish'),
      ($paper{colour} ? () : 'Please specify stock colour'),
      ($paper{weight} ? () : 'Please specify stock weight'),
      ($paper{calliper} ? () : 'Please specify stock calliper')
    )
    };
  }

  $ts_impose = Time::HiRes::time() if TIMINGS;

  # IMPOSITION
  #

  # The number of spreads remaining to be allocated.
  my $spreads_remaining = spreads_remaining($log, $dbh, $pid, $sid);

  # Override Digital Signatures to be 1 spread only.
  #    if ($press_type eq 'digital') {
  #        $project->{override}{spreads} = 1;
  #    }

  # The spreads per form x the number of forms can't exceed the number of
  # spreads remaining to be allocated.
  if ($project->{override}{spreads} && $project->{override}{forms}) {
    return {
      error => "Spreads × forms exceeds remaining spreads ($spreads_remaining). Please adjust your overrides."
    } if $project->{override}{spreads} * $project->{override}{forms} > $spreads_remaining;
  }

  my $desired_size = $project->{is_multipage} && $project->{override}{spreads} ? $project->{override}{spreads} : $spreads_remaining;

  my $impositions = create_impositions($dbh, $project, $desired_size);

  #print STDERR "DONE IMPOSE 4 create_impositions \n" . Data::Dumper::Dumper($impositions);

  $te_impose = Time::HiRes::time() if TIMINGS;

  # If we don't have any valid impositions we can't continue and should tell
  # the client why.
  return ({ error => 'No valid impositions.'.($$project{error} ? "\n".$$project{error} : '') }) unless scalar @$impositions;
  $openprint::log->debug( "IMpositions? " . @$impositions );

  ## PRICING
  #
  $variable->{project_index} = $pid;
  $variable->{service_index} = $sid;

  my $text;              # Debugging var.
  my $price_check = -1;  # Keep track of the best price found.
  my $best_price = {};   # Hashref /w the best overall price.

  # We determine the 'optimal' (Heh) imposition using the first qty.
  my $qty = $project->{QTY1} = @$qtys[0];

  my $print_sides = (@{$colours[1]}) && (@{$colours[0]}) ? 2 : 1;

  my @filtered_colours = wx_colours(@{$colours[0]}, @{$colours[1]});

  my @price_check;
  my %pms_price;
  my $previous_press = '';

  # Put here so we don't have to re-get them constantly.
  my @mixed_colours   = get_mixed_colours($log, $dbh, $pid, $sid);
  my %washed_colours  = get_washed_colours($log, $dbh, $pid, $sid);

  my %special_colours = @{ $dbh->selectcol_arrayref('SELECT strPMSID, strMaterialID FROM tbl_Ink_Colours', { Columns => [ 1, 2 ] }) };

  # CACHES
  #
  # So we don't slaughter the DB with the way we currently get pricing and
  # specs, we'll set up a cache for all pricing lookups dealing with the
  # current press type. TODO Material pricing.

  no warnings qw(once);
  local %eprint::service::cache = eprint::service::load_pricing( $dbh, $variable->{cust_id}, ($project->{press_type}, 'cutter'));
  local %eprint::equipment::cache = eprint::equipment::load_specs($dbh, $project->{press_type});

  my %pms_prices;
  my $imp; # Declare this up here so that we can steal it after the while.

  $ts_price  = Time::HiRes::time()  if TIMINGS;
  $total_imp = scalar @$impositions if TIMINGS;

  foreach $imp (@$impositions) {
    $$imp{specs} = $specs;
    if ( $openprint::r ) {
      $openprint::r->print("");
      if ( $openprint::r->connection()->aborted() ) {
        print STDERR "Aborted\n";
        return {error => 'Aborted'};
        #} else {
        #print STDERR "Not aborted\n";
      } # end if
    } else {
      print STDERR  "No openprint\n";
    } # end if

    my $setup           = $imp->getSetup;
    my $run_style       = $imp->getStyle;
    my $press           = $imp->getPress;
    #print STDERR "press $press runstyle $run_style setup $setup\n";

    # If we're a multipage project, respect the spreads on form and forms
    # (signature groups) overrides.
    if ($project->{is_multipage}) {
      if (!$imp->{spreads}) {
        $openprint::log->error("No spreads in impo");
        next;
      }
      if ($project->{override}{spreads} && ($imp->{spreads} != $project->{override}{spreads})) {
        $openprint::log->debug("spreads $$imp{spreads} != override ".$project->{override}{spreads}) if $openprint::log and DEBUG;
        next;
        #} else {
        #$openprint::log->debug("$$imp{spreads} == ".$project->{override}{spreads}) if $openprint::log;
      }
      $variable->{SignatureQuantity} = $project->{override}{forms} ? $project->{override}{forms} : int($spreads_remaining / $imp->{spreads});
    }
    if ($project->{override}{imposition} and ($setup != $project->{override}{imposition})) {
      #$openprint::log->debug("imposition $setup != ".$project->{override}{imposition}) if $openprint::log;
      next;
    }

    if (! defined $pms_prices{$press} ) {    # Pantone Matching System (PMS)
      $pms_prices{$press} = get_special_colours_price(
        $log, $dbh, $variable, $pid, $sid,
        $project, $press, $print_sides, \%pms_coverage,
        \@mixed_colours, \%washed_colours, \%special_colours
      );
    }

    my $pms_price = $pms_prices{$press};

    die $run_style unless $run_style =~ /^(SW|WT|WF|PF)/;

    my %price = calc_print_price(
      $log,      $dbh,     $variable,
      $pid,      $sid,     $qty,
      $spread,   $project, $press,
      $setup,

      @$project{qw(image_width image_height)},

      $colours[0],        $colours[1],        \@filtered_colours,
      $pms_price,         \%pms_coverage,      $imp->{paper},
      $paper{calliper},   $run_style,
      $has_aq,            $has_uv, $has_softtouch,           $is_spot,
      $dry_trap,          $additional_plates, $project->{versions},
      ($imp->getPaper->{width} * $imp->getPaper->{height}),          # Sheet area
      $paper{supplied}, $imp, $spreads_remaining,
      $project->{override}{overs}{unit},
      $project->{override}{overs}{run},
      $large_format,      $jig_specifics,     $project->{pages}
    );
    $openprint::log->debug("Price after calc_print_price ".Data::Dumper::Dumper(\%price)) if DEBUG;

    $price{forms} = $price{txtSignatureQuantity}       = $variable->{SignatureQuantity};
    $price{hdnInkMixColours}           = $pms_price->{'Mixed Colours'};

    fill_price_hash($project, $imp, \%price);

    # COMPARISON COST ADDITIONS
    #

    my $sig_count = $price{forms} || 1;

    # If the paper needs prepress cutting, we need to factor that into the comparison cost.
    if ($imp->{paper}{cuts}) {
      # For determining the cutting cost we need the original sheet
      # quantity not what we need of the cutdown one.
      my $qty = ceil( $price{hdnGrossSheetCount1}
        / (  ($imp->{paper}{width_factor}  || 1)
          * ($imp->{paper}{height_factor} || 1) ) );

      # Create a new cutting job.
      my $precut = Job->new(
        supplier  => 'House', # TODO Set to press supplier to start.
        signature => $sid,
        width     => $price{hdnSuppliedStockWidth},
        height    => $price{hdnSuppliedStockHeight},
        qty       => $qty,
        calliper  => $paper{calliper},
        cuts      => $imp->{paper}{cuts},
        note      => 'Cutting to fit on press.',
      );

      # Add the job cost to the comparison one.
      $price{'Comparison Cost'} += eprint::Service::Cutting::project_cost($dbh, $pid, $precut);
    }
 
    my $sig_specs = openprint::service::get_specs_ref($pid, $sid);
    my $imposition = new openprint::Imposition();
    $$imposition{Project} = $Project;
    $imposition->load_from_impositionObject($imp);

    if ( 0 and $$project{HasCutting} ) {
      $log->debug("SIG SPECS before cutting:" . Data::Dumper::Dumper($sig_specs));
      $log->debug("SIG SPECS before cutting:" . Data::Dumper::Dumper($imp));
      #$imposition->load($sig_specs, 1, $Project);

      my %cutting_results = openprint::Estimating::Cutting::signature_calc( $Project, $sig_specs, $$project{CuttingSpecs}, 1, $imposition->Paper(), $imposition, $$project{FoldingSpecs}, $project );

      $log->debug(Data::Dumper::Dumper(\%cutting_results));
      if ( $cutting_results{Status} eq 'uncalculated' ) {
        $price{'Cutting Breakdown'} .= "Cutting error: $cutting_results{alert}<br/>";
      } else {
        $price{'Cutting Breakdown'} .= sprintf('Cutting Price: $%.2f<br/>', $cutting_results{price});
        $price{'Cutting Breakdown'} .= $cutting_results{Breakdown};
        #$price{'Cutting Breakdown'} .= ' on '. $cutting_results{Equipment}->name() if $cutting_results{Equipment};
        $price{'Cutting Breakdown'} .= '<br/>';

        #$price{'Cutting Breakdown'} .= $$project{CuttingSpecs}{'hdnBreakdown'.$qty_index}.'<br/>';
        $price{'Comparison Cost'} += $cutting_results{price};
        $price{'Comparison Cost'} += $cutting_results{FoldingPrice};
        #$price{'Comparison Log'} .= "Cutting : $cutting_results{Price} PreFolding: $cutting_results{FoldingPrice} total: $price{ComparisonCost}<br/>" if COMPARISON_LOG;
        $price{'Cutting Overs'} = $cutting_results{overs};
      } # end if
      #} else {
      #$log->debug("Has no cutting") if DEBUG;
    } # end if
        
    if ( 1 and $$project{HasProofs} ) {
      my $Press = new openprint::Equipment($press);
      # Add proof costs.  Proofs only depends on colours, equipment so doesn't need to be part of the rest of calc
      my %Results = openprint::Estimating::Proofs::signature_calc( $Project, $Project->ServiceType($$project{HasProofs}), $$project{ProofsSpecs}, $sig_specs, 1,
        {}, # Indexes
        undef, #Totals,
        $imposition );
      $price{'Comparison Cost'} += $sig_count * $Results{total};
      $openprint::log->debug("Proofs pricing: $Results{total} * $sig_count");
      $openprint::log->error("Proofs alert $Results{alert}") if $Results{alert};
      #$$price{'Comparison Log'} .= 'proofs for ' . $sig_count . 'sigs. '. $sig_count * $Results{Total} . ' total: ' . $$price{ComparisonCost} . '<br/>' if COMPARISON_LOG;
      #$$price{'Proofs Breakdown'} .= $Results{Breakdown};
    } # end if

    # This is large format stitching, not saddle stitching/bindery.
    $price{'Comparison Cost'} += $price{stitching};

    my $mc =  $price{'Comparison Cost'} / ($price{imp}{spreads} || 1);

    my $paper = $price{imp}{paper};
    # COMPARISON TABLE
    my $valid = valid_price(\%price); 
    if (!$valid) {
      $openprint::log->debug("Invalid: ");
    }
    # Keep a log of what we've tried and the price of each.
    push @price_check, [
      # Press, run style, plates.
      $price{press}, $price{imp}{run_style},
      $price{txtPlateQuantity},

      # Imposition info.
      $price{imp}{setup},
      scalar @{ $price{imp}{layout} }, $price{sheet_wastage},

      # Stock info.
      $$paper{width},
      $$paper{height} || $price{imp}{cut_off},
      $price{hdnGrossSheetCount1},

      # Pricing.
      $price{txtPrice1},$price{txtStockPrice},$price{'Comparison Cost'},

      # Ahh the fun of positional based stuff. Tack on the original
      # stock sizes of anything that's been precut.
      $$paper{cuts},
      $price{hdnSuppliedStockWidth}, $price{hdnSuppliedStockHeight},
      0,
      $price{imp}{spreads},
      $mc
    ] if $valid;

    #print STDERR "HAVE COMP: $price{'Comparison Cost'} SETUP: $price{imp}{setup} RS:  $price{imp}{run_style}  SPREADS: $price{imp}{spreads}  MYCOMP: $mc \n", Dumper( $price{imp}  );

    # BEST PRICE
    #
    #Original
    #if (     valid_price(\%price)
    #     && ($price{'Comparison Cost'} < $price_check || $price_check == -1)
    #
    if ($valid && ( $mc < $price_check || $price_check == -1)) {
      # Keep track of the best price we have found so far.
      #$price_check = $price{'Comparison Cost'};

      $price_check = $mc;

      $best_price  = \%price;

      # And remember its place in the price check so we can find it # easily later.
      $price{comparison_idx} = $#price_check;
    }
  }  # end foreach imposition
  #$openprint::log->error(Data::Dumper::Dumper($best_price));

  if ( $price_check == -1 || !keys %$best_price ) {
    return {error => 'Could not price project'};
  }

  # PMS PRICE
  #
  # TODO This should be in pricing not a static charge after the fact.
  my $pms_price = $pms_prices{$best_price->{press}};

  foreach my $key (keys %{ $pms_price->{inkQty} }) {
    $best_price->{ "inkQty$key" } = $pms_price->{inkQty}{$key};
  }

  $te_price = Time::HiRes::time() if TIMINGS;

  # QUANTITY TWO AND THREE
  #
  # Now process the reamining qty's with the "optimal" (Teehee) imposition.
  $imp = $best_price->{imp};

  QTY:
  foreach my $i ( 2, 3 ) {
    last QTY unless $imp->getSetup;

    my $qty = $qtys->[$i - 1];

    my $press        = $imp->{press};
    my $press_sheets = 0;

    next QTY unless $qty;

    my $sheet_area = $best_price->{hdnSheetSizeWidth} * $best_price->{hdnSheetSizeHeight};

    my %price = calc_print_price(
      $log,           $dbh,
      $variable,      $pid,
      $sid,           $qty,
      $spread,        $project,
      $press,

      $imp->getSetup,
      $project->{image_width},      $project->{image_height},

      $colours[0],                  $colours[1],
      \@filtered_colours,           $pms_price,
      \%pms_coverage,               $best_price->{paper},
      $paper{calliper},             $best_price->{runstyle},
      $has_aq,                      $has_uv, $has_softtouch,
      $is_spot,                     $dry_trap,
      $additional_plates,
      $project->{versions},         $sheet_area,
      $paper{supplied},             $imp,
      $spreads_remaining,
      $project->{override}{overs}{unit},
      $project->{override}{overs}{run},
      $large_format,                $jig_specifics,
      $project->{pages},
    );

    my %keys = (
      GrossSheetCount     => 'Gross Sheet Count',
      NetSheetCount       => 'Net Sheet Count',
      SetupOvers          => 'Setup Overs',
      RunningOvers        => 'Running Overs',
      ImpressionQuantity  => 'Impressions',
      TotalRunPrice       => 'Run Price',
      TotalRunCost        => 'Run Cost',
      SpecialRunningPrice => 'PMS Run Price',
      VarnishRunningPrice => 'Varnish Run Price',
      AqueousRunningPrice => 'Aqueous Run Price',
      UVRunningPrice      => 'UV Run Price',
      SoftTouchRunningPrice      => 'SoftTouch Run Price',
      PaperCost           => 'Paper Cost',
      PaperBuyQuantity    => 'Buy Quantity',
      PaperTotal          => 'Paper Price',
      SheetQuantity       => 'Gross Sheet Count',
      RollQty             => 'Roll Qty',
      Equipment           => 'hdnEquipment1',
      SheetPrice          => 'Sheet Price',
      RunTime             => 'hdnRunTime1',
    );

    foreach my $key ( keys %keys ) {
      $best_price->{"hdn$key$i"} = $price{ $keys{$key} };
    }

    my $total_cost = $price{'Total Cost'};

    $best_price->{"txtPrice$i"}      = $total_cost;
    $best_price->{"txtStockPrice$i"} = $price{txtStockPrice};

    if ($imp->getSetup) {
      $best_price->{"txtAdditionalPrice$i"}
      = (($price{'Run Price'} * $print_sides)
        + (1000 * $best_price->{'Sheet Price'}))
      / $imp->getSetup * 1.1;

      if ($project->{press_type} eq 'web' || $large_format->{roll}) {
        $best_price->{"txtAdditionalPrice$i"} = $price{"txtAdditionalPrice$i"};

        my $paper_1000
        = $best_price->{hdnRollQty1}
        * 1000
        / $best_price->{hdnImposition}
        / $best_price->{'Gross Sheet Count'};

        $paper_1000 *= $best_price->{'Sheet Price'};

        $best_price->{"txtAdditionalPrice$i"} = $price{'Run Price'} * $print_sides + $paper_1000;
      }
    } else {
      $best_price->{"txtAdditionalPrice$i"} = '0.00';
    }

    $best_price->{hdnPlateCount} = $price{txtPlateQuantity};
    $best_price->{txtPressSheetQty} .= ", " . $price{'Gross Sheet Count'};
    $best_price->{txtRollQty} .= ", " .
    ceil($price{'Gross Sheet Count'} * $best_price->{txtMWeight} / 1000);
  }

  #material usage estimate recording -- A lot of this is copies of other code where the price is calculated. There isn't time for something more elegant right now.
  #    for my $i (1..3) {
  #      my $qty = $qtys->[$i - 1];
  #      my $mat;
  #      next unless $qty > 0;
  #
  #      #paper usage
  #      PQS::model::service::set_material_estimate($best_price->{"hdnGrossSheetCount$i"}, undef, $sid, $best_price->{paper}{index}, $i);
  #
  #      #ink usage
  #      my %press_units = map { $_->{name} => $_ } @{$project->{wx_press_units}};
  #      foreach my $key (keys %pms_coverage) {
  #        my $sheets_per_ink_unit = SHEETS_PER_UNIT_PANTONE;
  #        $sheets_per_ink_unit = SHEETS_PER_UNIT_METALLIC if $special_colours{$key};
  #        my $ink_estimate = get_ink_coverage($project, $pms_coverage{key}, $sheets_per_ink_unit) / $print_sides;
  #        my $mat = PQS::model::materials::material_by_strid($press_units{$key});
  #        die "Ink mat id not found" unless $mat->{lngindex};
  #        PQS::model::service::set_material_estimate($ink_estimate, undef, $sid, $mat->{lngindex}, $i);
  #      }
  #
  #      #screen usage
  #      my $press = $best_price->{imp}->{press};
  #      if (eprint::equipment::get_type($log, $dbh, $press) eq 'screen') {
  #        my $area = (SCREEN_LAP + $project->{image_width}  + SCREEN_LAP)
  #                 * (SCREEN_LAP + $project->{image_height} + SCREEN_LAP);
  #        my $mat = PQS::model::materials::material_by_strid('Screen');
  #        die "Screen mat id not found" unless $mat->{lngindex};
  #        PQS::model::service::set_material_estimate($area, undef, $sid, $mat->{lngindex}, $i);
  #      }
  #
  #      #plate usage
  #      my ($plate_type) = eprint::equipment::get_specification($log, $dbh, 'Plate Type', '', $press);
  #      my ($plate_size) = eprint::equipment::get_specification($log, $dbh, 'Plate Size', '', $press);
  #      my $design = $dbh->selectrow_array(q{SELECT strdesign FROM tbl_projects WHERE lngprojectindex = ?}, {}, $pid);
  #
  #      $plate_size = 0 if $design eq 'PlatesSupplied';
  #
  #      my $plate_id = "$plate_size-${plate_type}Plate";
  #
  #      my $plate_price_qty = $best_price->{hdnPlateCount};
  #
  #      $mat = PQS::model::materials::material_by_strid($plate_id);
  #
  #  	  if ($mat->{lngindex}) {
  #        PQS::model::service::set_material_estimate($plate_price_qty, undef, $sid, $mat->{lngindex}, $i);
  #	  } else {
  #        warn "Plate material id not found for type: *$plate_id* FRO PRESS: $press";
  #	  }
  #
  #    }


  # SHEET SIZES (DROP-DOWN BOX)
  #
  # Send back a serialized list of sheet sizes for the press. TODO We've
  # already gotten this early, just save it then instead of refetching.
  my $press     = get_equipment($dbh, $best_price->{press});

  my $substrate = $best_price->{paper}{id};
  $$best_price{substrate} = $substrate;

  # Get the substrates for the press, sort them, and serialize the list.
  $best_price->{sheet_sizes} = join q{_} =>
  map  { join q{,} => $_->{id},                                # ID
    (join 'x' => $_->{width}, $_->{height}), # (W x H)
    ($substrate eq $_->{id})                 # Checked
  }
  sort { $a->{width} <=> $b->{width} || $a->{height} <=> $b->{height} }
  map  { fit_to_press($_, $press)                                     }
  @{ get_substrates($dbh, $project) };
  $openprint::log->debug("Sheet sizes: ".Data::Dumper::Dumper($best_price->{sheet_sizes}));

  $best_price->{press} = $press->{id};

  # We want imposition later.
  delete $best_price->{imp}{log}; # Remove the code references.
  delete $best_price->{imp}{dbh};

  # The tree object needs it's own store method called on itself. TODO It
  # doesn't seem to be getting the storable methods.
  $best_price->{imp}{tree} = freeze $best_price->{imp}{tree};

  $best_price->{imp} = encode_base64(sfreeze_c($best_price->{imp}));

  # Mark the best price as 'chosen' in the run style check.
  #push @{ $price_check[ $best_price->{comparison_idx} ] }, 1;
  #
  ${ $price_check[ $best_price->{comparison_idx} ] }[15] = 1;

  # The run style check is for historical comparison of why we chose a given
  # (press, imposition) pair over another. TODO: Move this further up
  # (before Q2-3) and undef @price_check after encoding as it's a mem hog.
  $best_price->{hdnRunStyleCheck} = encode_base64(sfreeze_c(\@price_check));

  @$best_price{ keys %{$project->{signature}} } = values %{$project->{signature}};

  if (TIMINGS) {
    $te_req = Time::HiRes::time();
    _log_timings($log);
  }

  insert_service_spec($log, $dbh, $pid, $sid, "imp", $best_price->{imp});
  $$best_price{colour_bar_size} = $$project{colour_bar};

  return post_process(
    $log, $dbh, $pid, $sid,
    $project->{press_type}, $project, $spreads_remaining, $best_price);
}

# Log the timings we've collected.
sub _log_timings {
  my ($log) = @_;

  my $t_impose = $te_impose - $ts_impose;
  my $t_price  = $te_price  - $ts_price;
  my $t_req    = $te_req    - $ts_req;

  print STDERR sprintf "\nPRINTING IMPOSE elapsed time: %6.3fs impose: %6.3fs (%2d%%) price: %6.3fs (%2d%%) impositions: %3d (p %1.3fs/imp) \n\n\n",
  $t_req,
  $t_impose, ($t_impose / $t_req) * 100,
  $t_price,  ($t_price  / $t_req) * 100,
  $total_imp, $t_price / $total_imp
  ;
}


# Fills the pricing hash with a plethora of stuff from various sources. We
# don't actually know what of it is used or useful.
sub fill_price_hash {
  my ($project, $imp, $price) = @_;

  # Press and run style
  $price->{press}         = $price->{hdnEquipment1} = $price->{hdnPress} = $imp->{press};
  $price->{runstyle}      = $imp->getStyle;

  # Imposition
  $price->{imp}                 = $imp;

  $price->{grain_direction} = $price->{hdnGrainDirection} = $price->{grainDirection} = $imp->{grain_direction};

  $price->{txtImageWidth}       = $imp->{image_width};
  $price->{txtImageHeight}      = $imp->{image_height};
  $price->{hdnImageOrientation} = $imp->{image_orientation};

  $price->{hdnImposition1} = $price->{imposition} = $price->{hdnImposition}       = $imp->getSetup;
  $price->{SpreadRows}          = $imp->{spread_rows};
  $price->{SpreadCols}          = $imp->{spread_cols};

  $price->{hdnImpositionRows}    = $imp->getRows;
  $price->{hdnImpositionColumns} = $imp->getCols;

  # Only multi-page is guaranteed to be non-dutch right now (have r x c).
  if ($project->{is_multipage}) {
    $price->{ShapeRows}            = $imp->{spread_rows} / $imp->{rows} if $imp->{rows};
    $price->{ShapeCols}            = $imp->{spread_cols} / $imp->{cols} if $imp->{cols};
    $price->{spreads} = $price->{ShapeRows} * $price->{ShapeCols};
  } else {
    $price->{spreads} = $imp->{spread_rows} * $imp->{spread_cols};
  }
  $price->{spreads_in_group} = $imp->{spreads} ? $imp->{spreads} : 1;
  $price->{used_spreads} = $price->{spreads} * $price->{forms};

  $price->{LargeFormatTiled} = ($project->{press_type} eq 'inkjetprinter' && $imp->{spreads} > 1) ? 1 : 0;

  # Substrate details and pricing.
  $price->{hdnPaperIndex}          = $imp->{paper}{index};
  $price->{hdnPaperWeight}         = $imp->{paper}{weight};
  $price->{txtMWeight}             = $imp->{paper}{mweight};

  $price->{txtStockCalliper}       = $project->{paper}{calliper};

  $price->{hdnSheetSizeWidth}      = $imp->getPaper->{width};
  $price->{hdnSheetSizeHeight}     = $imp->getPaper->{height}
  || (  $imp->getRotateSheet
    ? $imp->getImageWidth
    : $imp->getImageHeight  );

  $price->{hdnSuppliedStockWidth}  = $imp->{paper}->{start_width} || $imp->{paper}->{width};
  $price->{hdnSuppliedStockHeight} = $imp->{paper}->{start_height} || $imp->{paper}->{height};

  $price->{hdnRollQty1}          = $price->{'Roll Qty'};
  $price->{hdnNetSheetCount1}    = $price->{'Net Sheet Count'};
  $price->{hdnGrossSheetCount1}  = $price->{hdnSheetQuantity1}
  = $price->{txtPressSheetQty}
  = $price->{'Gross Sheet Count'};

  $price->{hdnPaperCost1}        = $price->{'Paper Cost'};
  $price->{hdnPaperTotal1}       = $price->{'Paper Price'};
  $price->{hdnPaperBuyQuantity1} = $price->{'Buy Quantity'};
  $price->{hdnSheetQuantity1}    = $price->{'Gross Sheet Count'};

  # Setup pricing.
  $price->{hdnSetupCost}         = $price->{'Press Setup'};
  $price->{hdnPlateCost}         = $price->{'Plate Cost'};
  $price->{hdnPressCost}         = $price->{'Press Setup Cost'};
  $price->{hdnPlateMaterialID}   = $price->{'Plate Material ID'};
  $price->{hdnImpositionCharge}  = $price->{'Imposition Charge'};
  $price->{hdnWashUpCost}        = $price->{'Press Wash Charge'};
  $price->{hdnInkMixCost}        = $price->{'Ink Mix Charge'};
  $price->{hdnAqueousSetupCost}  = $price->{'Aqueous Setup Charge'};
  $price->{hdnUVSetupCost}       = $price->{'UV Setup Charge'};
  $price->{hdnSoftTouchSetupCost}       = $price->{'SoftTouch Setup Charge'};
  $price->{hdnSheetPrice1}       = $price->{'Sheet Price'};


  # Run pricing.
  $price->{hdnImpressionQuantity1}     = $price->{Impressions};
  $price->{hdnImpressionRange}         = $price->{ImpressionRange};
  $price->{hdnTotalRunPrice1}          = $price->{hdnStandardRunningPrice}
  = $price->{'Run Price'};
  $price->{hdnTotalRunCost1}           = $price->{'Run Cost'};
  $price->{hdnSpecialRunningPrice1}    = $price->{'PMS Run Price'};
  $price->{hdnVarnishRunningPrice1}    = $price->{'Varnish Run Price'};
  $price->{hdnAqueousRunningPrice1}    = $price->{'Aqueous Run Price'};
  $price->{hdnUVRunningPrice1}         = $price->{'UV Run Price'};
  $price->{hdnSoftTouchRunningPrice1}         = $price->{'SoftTouch Run Price'};
  $price->{hdnWorkTurnDryCharge}       = $price->{'WorkTurn Dry Charge'};
  $price->{txtRollQty}                 =
  ceil($price->{hdnSheetQuantity1} * $price->{txtMWeight} / 1000);

  # Total pricing.
  $price->{txtPrice1}      = $price->{'Total Cost'};
  $price->{txtStockPrice1} = $price->{txtStockPrice};

  return $price;
}

sub create_impositions {
  my ($dbh, $project, $desired_size) = @_;

  my $start_time = Time::HiRes::time();
  # Get an iterator that generates imposition possibilities.
  #print STDERR "START IMPOSE $project->{id}\n";

  my $func = $project->{press_type} eq 'inkjetprinter' ? \&lf_imposition : \&convert_to_old;

  my @impositions;
  my $iter = $global_iterator = impositions($dbh, $project, $start_time);
  # For now just flatten the iterator into a list of old 'impositionObjects'.
  while ($iter->isnt_exhausted) {
    #$openprint::log->debug(Data::Dumper::Dumper($iter->value));
    push @impositions, $func->($dbh, $project, @{ $iter->value });
  }

  # MULTI-VERSION TEMP: For now we'll constrain business cards to layout
  # on as few sheets as possible. Note: This equation was just pulled
  # out of "where the sun don't shine". It tends towards laying
  # everything out on one sheet as slots increase above the number of
  # versions.
  if ($project->{type} eq 'BusinessCards' and keys %{ $project->{versions} }) {
    @impositions = map {
      my $d = ($_->{run_style} =~ /^W/) ? 2 : 1;
      my $n = ceil(  (keys %{$project->{versions}}) / ($_->{setup} / ($d*1.8)));

      (@{$_->{layout}} > $n) ? () : $_;
    } @impositions;
  }

  #print STDERR "HAVE IMPOSTIONS BEFORE FILTER  2 " . scalar @impositions . "\n";
  if ($desired_size > 0) {
    my $signature_size = desired_signature_size($desired_size, \@impositions);

    $signature_size = 1 if $signature_size && $project->{press_type} eq 'digital'
    && $project->{bind_type} !~ /^(Loop|Saddle)Stitching$/
    && configuration::get_value(undef, $dbh, 'Digital2PageSignatures');

    #print STDERR "HAVE IMPOSTIONS BEFORE FILTER  3 " . scalar @impositions . "\n";
    # For books with more than one spread in the signature, we need to
    # convert the raw impositions of the single spread dimesions into
    # images of multiple spreads.
    my @converted_impositions;
    my $smallest = $signature_size > 2 ? int($signature_size/3) : 1;
    foreach my $sig_size ($smallest .. $signature_size) {
      #print STDERR "converting to $sig_size\n";
      my @new_impositions = map { convert_to_signature($sig_size, $_->clone(), $project) } @impositions;
      push @converted_impositions, @new_impositions;
      foreach my $imp (@new_impositions) {
        #print STDERR "Imp setup:$$imp{setup} spreads:$$imp{spreads} style:$$imp{run_style}\n";
      }
    }
    @impositions = @converted_impositions;
    #} else {
    #$openprint::log->debug("No desired size: $desired_size");
  }

  #print STDERR "HAVE IMPOS.TIONS BEFORE FILTER 99 " . scalar @impositions . "\n", Dumper(\@impositions);
  #@impositions = grep { $_->{setup} > 0 } @impositions;
  print STDERR "HAVE IMPOSITIONS TOTAL " . scalar @impositions . "\n";

  #$DB::single = 1;

  return \@impositions;
} # end sub create_impositions

sub post_process {
  my ($log, $dbh, $pid, $sid, $press_type, $project, $remaining_spreads, $specs) = @_;

  my $template = $project->{template};

  # If we have an error abort and return the information to the user.
  if (exists $specs->{error}) {
    set_status($log, $dbh, $pid, 'error', $sid);
    return $specs;
  }

  if ($press_type eq 'inkjetprinter') {
    # this is so kludgish, I know.
    # basically, in largeformat, we can print just about anything.  if
    # the customer wants 40x40, and we only have 20x20 sheets, then we
    # stitch 4 of them together.  This hack basically allows the price to
    # stay where it's supposed to, but sets the new quantity of paper
    # being used to the right value so it shows up right in the docket.

    for my $n ( 1 .. 3 ) {
      if ($specs->{spreads_in_group}) {
        $specs->{"hdnGrossSheetCount$n"} *= $specs->{spreads_in_group};
        $specs->{"hdnSheetQuantity$n"} = $specs->{"hdnGrossSheetCount$n"};
      }
    }
  }
  if ( $project->{type} eq 'Envelopes' ) {
    $specs->{flat_width}  = sprintf("%g",$project->{width});
    $specs->{flat_height} = sprintf("%g",$project->{height});
    $specs->{final_width} = $specs->{flat_width};
    $specs->{final_height} = $specs->{flat_height};
  }

  if ($remaining_spreads == 0 || $project->{type} eq 'ScreenItem') {
    #this is a non-book situation so we can return now.
    # adjust price hash will now total paper and printing when needed.
    adjust_price_hash($specs, $press_type, $project);
    return $specs;
  }

  # this is the number of spreads in the signature/image ie: in a 2 out 12pg
  # press sheet this would be 3
  my $spreads = $specs->{spreads_in_group} or die "Invalid spreads for multipage book.";

  # For Cover Spreads we specify a template that will give us our
  # folding type for the cover. So we don't need to go though
  # all of the signature counting.
  if ( $template ) {
    # Here is where we handle the template type specified in the cover
    # spread.
    $specs->{txtSingleGateFolded}  = $template eq 'SingleGateFold' ? 1 : '';
    $specs->{txtDoubleGateFolded}  = $template eq 'DoubleGateFold' ? 1 : '';

    if ($$project{bind_type} ne 'PerfectBinding') {
      $specs->{txtSignatureQty4Page} = $template eq '4PageSignature' ? 1 : '';
    }
  } else {
    # Replace Javascript that fills out signature information
    # to be used by bindery services.
    my %sigs = cut_signatures($pid, $specs, $project);

    foreach my $key ( keys %sigs ) {
      $specs->{'txtSignatureQty'. $key . 'Page'}
      = $sigs{$key} ? $sigs{$key} : '';
    }
  }

  adjust_price_hash($specs, $press_type, $project);

  return $specs;
}


# This section of code is woefully inadequate. We are multiplying the whole
# price by the number of signatures. This means that we are multiplying
# imposition, washup, and everything else in the price of printing the
# signature, when not all of it is necessarilly going to be replicated.  For
# now I will write special code to compensate for "double-billing" of
# imposition charges, but for the rest of it, something will need to be done.
# The best thing would be to use signature quantity in the earlier
# calculations and do everything right once based on that rather than kludging
# it here. - Duke - y'know, cus Duke knew all about kludging. *cough*
sub adjust_price_hash {
  my ($specs, $press_type, $project) = @_;

  my $group = $specs->{txtSignatureQuantity} || 1;

  if ($group > 1) {
    # use hdnImpositionCharge to determine what not to multiply in.
    for my $i (1..3) {
      my $other = $group - 1;
      my $discount = (   $$specs{hdnImpositionCharge}
        + $$specs{hdnInkMixCost}
        + $$specs{hdnWashUpCost}
      );

      $discount += $$specs{hdnPressCost} if $press_type eq 'digital';
      $discount *= $other;

      $$specs{"txtPrice$i"} = ($$specs{"txtPrice$i"} * $group) - ($discount);
      $$specs{"txtStockPrice$i"} = $group * $$specs{"txtStockPrice$i"};
      $$specs{"hdnRunTime$i"} *= $group;
    }

    if ($$project{group_factor}) {
      my $group_offset = $$project{group_factor} * ($group - 1);

      $specs->{txtPrice1}           += $group_offset;
      $specs->{txtPrice2}           += $group_offset;
      $specs->{txtPrice3}           += $group_offset;
      $specs->{hdnImpositionCharge} += $group_offset;
    }
  }

  # A little bit of over kill but this should take care of the rounding issues.
  my @qtys = ( undef, @{$$project{quantities}});

  for my $i (1..3) {
    my $qty = $qtys[$i];

    @$specs{"txtPrice$i", "txtUnitPrice$i"} =
    format_pricing($specs->{"txtPrice$i"}, $qty);

    @$specs{"txtStockPrice$i", "txtStockUnitPrice$i"} =
    format_pricing($specs->{"txtStockPrice$i"}, $qty);

    @$specs{"total_price$i", "unit_price$i"} = format_pricing(
      ($specs->{"txtPrice$i"} + $specs->{"txtStockPrice$i"}), $qty
    );
  }
  $$specs{status_alert} = '';
}

sub calc_print_price {
  my ($log,              $dbh,              $variable,
    $pid,              $sid,              $qty,
    $spread,           $project,          $press,
    $imposition,       $imageWidth,       $imageHeight,
    $side_one_colours, $side_two_colours, $filtered_colours,
    $pms_price,        $pms_coverage,
    $paper,            $paper_calliper,
    $run_style,        $aqueous_sides,    $UV_sides, $softtouch_sides,
    $is_spot_coating,  $dry_trap,         $plate_changes,
    $versions,         $sheet_area,       $paper_supplied,
    $imp,              $spreads_remaining,    $unit_overs_OR,
    $run_overs_OR,     $large_format,     $jig_specifics,
    $pages ) = @_;

  my $project_type   = $project->{type};
  my $press_type     = $project->{press_type};
  my $is_largeformat = ($project_type =~ /^LF/);

  # Instead of passing the run style around two binary flags are used
  # instead. LEGACY.
  my $is_sheetwork  = ($run_style eq 'SW');
  my $is_perfecting = ($run_style eq 'PF');

  die $run_style unless $run_style =~ /^(SW|WT|WF|PF)/;

  die "Invalid run style ($run_style)." . caller
  unless grep { $run_style eq $_ } RUN_STYLES;

  my %price;

  $side_one_colours = [ grep { $_ ne 'undefined'} @$side_one_colours ];
  $side_two_colours = [ grep { $_ ne 'undefined'} @$side_two_colours ];

  my @colours = ($run_style !~ /^W/)
  ? (@$side_one_colours, @$side_two_colours)
  : @$filtered_colours;

  my $print_sides = (@$side_two_colours and @$side_one_colours) ? 2 : 1;

  my $cover;

  if ( $project->{signature}{txtSignatureType} eq 'Cover Spreads' ) {
    my $x = $paper->{width} * $paper->{height};

    my $cover_spec = $dbh->selectrow_hashref(q{
      SELECT  lngindex as index, strmweight as mweight, strname as name,
      sides
      FROM tbl_paper p, cover_specs c
      WHERE p.strname = c.name
      AND p.strcolour = c.colour
      AND p.strfinish = c.finish
      AND p.strWeight = c.Weight
      AND c.pid = ?
      AND p.dblwidth * p.dblheight >= ?
      ORDER BY p.dblwidth * p.dblheight LIMIT 1
      }, undef, $pid, $x);
    if ( $cover_spec->{index} ) {
      map { $cover->{$_} = $cover_spec->{$_} } keys %{$cover_spec};
    }
  }

  my $used_plates = 0;
  my $numRuns     = 1;
  my $waste       = 0;
  my $plate_multiplier = ($run_style =~ /^W/) ? 2 : 1;
  my $forms = scalar @{ $imp->{layout} };

  # icon: I don't know what the following code does.  It seems to be rejecting if more than 1 sig is being used.
  my %vl;
  my %lay_count;
  foreach my $l (@{$imp->{layout}}) {
    my $count = scalar(@{$l});
    $lay_count{$count} = 1;
    map {
    #print STDERR "LAYS: ". Dumper($_) if DEBUG;
      $vl{$_->{label}} = 1;
    } @{$l};
  }
  if (scalar(keys %lay_count) > 1 ) {
    #$price{reject_mv_layout} = 1; #icon disable as it seems to simply reject anything with more than 1 sig
    print STDERR "versions REJECT MV LAYOUT \n", Dumper(\%lay_count);
  } else {
    #print STDERR "versions PASS MV LAYOUT \n";
  }

  my $lay_versions = scalar(keys %vl);

  #print STDERR "HAVE PROJECT : " , Dumper($project, \%lay_count);
  # If we're running multiple versions (and we're not multi-page because we
  # don't handle that yet), calculate plates and paper wastage.
  #if (%$versions and $spreads_remaining <= 1 ) {
  if (%$versions) {
    #if ( $spreads_remaining <= 1 ) {
    # Each layout is a differently imposed press sheet.
    $numRuns = scalar @{ $imp->{layout} };
    #} else {
    #	my $ver =  scalar keys %$versions;
    #	$numRuns =  ceil($ver / ($imposition/$plate_multiplier) );
    #print STDERR "USE MultiPage MV Plate Change,  $ver Versions; \n";
    #}

    # Count the number of plates that vary by version. WT/F look up a
    # pre-cached press unit counts, others count inks per side.
    $plate_changes = scalar grep {$_->{mv_varies}}
    ($run_style =~ /^W/) ? @{$project->{wx_press_units}}
    : map { @{$_->{colours}} } @{$spread->{side}};

    #print STDERR "versions USE STANDART MV Plate Change RUNS: $numRuns PC: $plate_changes FORMS: $forms LV $lay_versions \n" if DEBUG;
    #die(Dumper($imp));

    # Scale the version plates with the number of layouts, the static
    # plates we'll leave as constant.
    if ( $project->{is_multipage} ) {
      $plate_changes *= $lay_versions  - 1;
    } else {
      $plate_changes *= $numRuns  - 1;

    }

    # Waste is the sum of the layout percentages less the required (100%).
    $waste = $price{sheet_wastage} =
    sum(map{ sum(map{$_->{final}}@$_) } @{$imp->{layout}})-100;
  } else {

  }

  #$plate_changes =   $plate_multiplier * $spread->{colour_changes} || 0;

  $price{hdnNumRuns} = $numRuns;

  #print STDERR "HAVE COLOUR CHANGES: multi: $plate_multiplier, Changes: $plate_changes STYLE: $run_style IMP: $imposition Remain: $spreads_remaining \n";
  #print STDERR "HAVE NUM RUNS: $numRuns FORMS: $forms \n", Dumper($versions);

  my $mp_versions = mp_versions($pid);

  my $plate_runs   = 1 * $mp_versions;  # Handled poorly especially when MV.

  #print STDERR "HAVE MP versions: $mp_versions PC FINAL: $plate_changes \n ";

  #$plate_changes  *= $mp_versions if $mp_versions > 1;

  #print STDERR "PRESS SETUP TIME: $press Plate Changes: $plate_changes : VERSIONS: $mp_versions \n";

  my %colour_setup =
  press_setup_cost($log,            $dbh,         $project, $jig_specifics,
    $imageWidth,     $imageHeight, $variable,
    $paper_calliper, $press,       $used_plates,
    $plate_changes,  $sheet_area,  $plate_runs,
    $spread->{colourcritical_make_ready}, @colours); # u

  my %sheet_qty = calc_sheet_qty(
    $log,                         $dbh,          $qty,
    $colour_setup{'Plate Count'}, $press,        $imposition,
    $waste,                       $pid,          $print_sides,
    $unit_overs_OR,               $run_overs_OR, $run_style,
    $paper, $imp, $cover, $spread->{colourcritical_extra_waste}, $variable,
    $project
  );

  my $impressions = $is_largeformat ? $qty : $sheet_qty{'Gross Sheet Count'} * $print_sides;

  # We need to print more impressions when using multisheet forms - we'll
  # acheive this by adding to the gross sheet count, so it should just
  # trickle down to here

  my $max_impressions = eprint::equipment::get_specification($log, $dbh, 'Maximum Plate Impressions', '', $press);
  $max_impressions = 250000 if $max_impressions eq '';

  # For Sheet Work & Perfecting we only use the plate for printing one side
  # of the project.  Work & Turn/Tumble we have to reuse the plate for both
  # sides.
  my $plate_impressions = ($is_sheetwork or $is_perfecting)
  ? $sheet_qty{'Gross Sheet Count'}
  : $impressions;

  if ($plate_impressions > $max_impressions) {
    # If we need more than the spec'd out max impressions total then we
    # need to split the run up into multiple runs with a new set of plates
    # each time.  a complicated way to round up.
    $plate_runs =
    int($plate_impressions / $max_impressions) !=
    ($plate_impressions / $max_impressions)
    ? int(($plate_impressions / $max_impressions) + 1)
    : int($plate_impressions / $max_impressions);
    %colour_setup =
    press_setup_cost($log,            $dbh,         $project, $jig_specifics,
      $imageWidth,     $imageHeight, $variable,
      $paper_calliper, $press,       $used_plates,
      $plate_changes,  $sheet_area,  $plate_runs,
      $spread->{colourcritical_make_ready}, @colours);
    %sheet_qty =
    calc_sheet_qty($log,          $dbh,
      $qty,          $colour_setup{'Plate Count'},
      $press,        $imposition,
      $waste,        $pid,
      $print_sides,  $unit_overs_OR,
      $run_overs_OR, $run_style, $paper,
      $imp,			$cover, $spread->{colourcritical_extra_waste}, $variable);

    $impressions = $sheet_qty{'Gross Sheet Count'} * $print_sides;
  }

  $price{plate_type} = $colour_setup{'Plate Type'};

  #print STDERR "HAVE IMP DATA", Dumper(\%sheet_qty, $imp->{layout} );
  # We treat drying time for W&T/F in a very very simplistic manner. If n
  # running impressions (exclude initial setup overs) are done before we
  # need to re-feed we don't charge it. For multi-version we have to check
  # against each plate set.
  my $workturn_dry_cost = 0;
  unless ($is_sheetwork or $is_perfecting) {
    # If the max. impression setting is NULL we charge every time.
  }

  # Get the number of impressions we can print on the first run before the
  # first sheet is dry
  my $drying_max_impressions = eprint::equipment::get_specification($log, $dbh, 'WT Drying Max Impressions', undef, $press);

  # For W&T, W&F the case that the first press sheet is not dry when the
  # first run completed then we will have to wait for the sheet to dry
  # before we start and 2nd run and therefore need to charge a WT drying
  # cost if the press doesn't specify a valid 'WT Drying Max Impression' (0,
  # negative or blank) we will always charge WT drying cost
  if (($run_style eq 'WT' or $run_style eq 'WF') or $drying_max_impressions <= 0) {
    map {
      my $wt =  get_price($log, $dbh, $variable, 'WTDrying', undef, $press);
      my $q =  $sheet_qty{'Gross Sheet Count'} * $_->[0]->{final} / 100;
      $workturn_dry_cost += $wt if $drying_max_impressions > $q;
    } @{$imp->{layout}}

  }

  # Charge on setting up equipments for perfecting run style.
  my $perfecting_change_over = $is_perfecting
  ? get_price($log, $dbh, $variable, 'PerfectingChangeOver', undef, $press)
  : 0;

  my %run_price = $is_largeformat
  ? get_largeformat_price(
    $log, $dbh, $variable,
    $sheet_qty{'Gross Sheet Count'},
    scalar(@$side_one_colours),
    scalar(@$side_two_colours), $paper_calliper,
    $is_perfecting, $press, $project_type, $imp,
    $large_format, $qty, $project
  )
  : get_run_price(
    $log, $dbh, $variable,
    $sheet_qty{'Gross Sheet Count'},
    scalar @$side_one_colours,
    scalar @$side_two_colours,
    $paper_calliper,
    $is_perfecting,
    $press,
    $project_type,
    $pages,
    $press_type,
    $imp,
    $project->{screen_foil},
    $project->{underbase}
  );

  if (!scalar %run_price) {
    return (error => 'Cannot perform required job!');
  }

  $price{ImpressionRange} = $run_price{ImpressionRange};

  my %aqueous =
  get_coating_price($log,             $dbh,
    $variable,        $sheet_qty{'Gross Sheet Count'},
    $aqueous_sides,   $press,
    $print_sides,     $is_sheetwork,
    $is_spot_coating, $pid,
    $sid, $pages, 'Aqueous');

  my %UV =
  get_coating_price($log,             $dbh,
    $variable,        $sheet_qty{'Gross Sheet Count'},
    $UV_sides,        $press,
    $print_sides,     $is_sheetwork,
    $is_spot_coating, $pid,
    $sid, $pages, 'UV');

  my %SOFTTOUCH =
  get_coating_price($log,             $dbh,
    $variable,        $sheet_qty{'Gross Sheet Count'},
    $softtouch_sides,        $press,
    $print_sides,     $is_sheetwork,
    $is_spot_coating, $pid,
    $sid, $pages, 'SoftTouch');

  my $varnish_run_price =
  get_varnish_run_price($log,         $dbh,
    $variable,    $press,
    $print_sides, $impressions,
    $dry_trap,    @$side_one_colours,
    @$side_two_colours);

  my %washed_colours =
  get_washed_colours($log, $dbh, $pid, $sid);

  # Get the price of washing the varnish units used.
  my $varnish_wash =
  get_varnish_wash_price($log,               $dbh,
    $variable,          $press,
    $run_style,         $print_sides,
    $dry_trap,          \%washed_colours,
    @$side_one_colours, @$side_two_colours);
  my $process_wash =
  get_process_wash_price($log, $dbh, $variable, $press, $run_style,
    $print_sides,       $project->{chem_emboss},
    @$side_one_colours, @$side_two_colours       );
  my $imposition_charge =
  get_imposition_charge($log,              $dbh,
    $variable,         $pid,
    $sid,    $imageHeight,
    $imageWidth,       $press,
    $imposition,       $imp,
    $side_one_colours, $side_two_colours,
    $spreads_remaining, $project->{metal_effects});

  my $setup_cost
  = $is_largeformat ? $run_price{'Largeformat Setup'}
  : $colour_setup{'Total Setup Cost'}
  + $imposition_charge
  + $perfecting_change_over
  + $workturn_dry_cost
  + $aqueous{'Setup Price'}
  + $UV{'Setup Price'}
  + $SOFTTOUCH{'Setup Price'}
  + $pms_price->{'Ink Mix Charge'}
  + $pms_price->{'Press Wash Charge'}
  + $varnish_wash
  + $process_wash;

  $price{hdnTrap} = @$side_one_colours > 1 || @$side_two_colours > 1
  ? 'Yes'
  : 'No';

  @price{ keys %sheet_qty } = values %sheet_qty;

  $price{paper} = $paper;

  # Why do we compare the sheet count then set the form count?
  if ( ! $price{'Buy Quantity'}
    || $price{'Buy Quantity'} <= $price{'Gross Sheet Count'})
  {
    # Changing the buy quantity to get the form count. So that we can
    # price out paper in forms, but price our printing in sheets - Duke
    $price{'Buy Quantity'} = $price{'Gross Form Count'};
  }

  # If the paper we're dealing with has been sheeted into smaller pieces the
  # gross quantities we're dealing with are the sheeted quantities. We need
  # to price the pre-cut stock (rolls will never have these factors).
  if ($paper->{width_factor} || $paper->{height_factor}) {
    my $x = $paper->{width_factor}  || 1;
    my $y = $paper->{height_factor} || 1;

    $price{'Buy Quantity'} = ceil( $price{'Buy Quantity'} / ($x * $y) );
  }
  #if ($paper->{minimum_order} and $price{'Buy Quantity'} < $paper->{minimum_order}) {
  #$price{'Buy Quantity'} = $paper->{minimum_order};
  #}

  my $paper_price;
  my $roll;
  my $id = $paper->{index};
  if ($id) {
    $paper_price = $is_largeformat
    ? eprint::paper::get_lf_price(
      $log, $dbh, $variable, $imp,
      $price{'Buy Quantity'}
    )
    : eprint::paper::get_price(
      $log, $dbh, $variable, $paper, $press,
      $price{'Buy Quantity'}
    );
    #$roll = $dbh->selectrow_array(q{
    #SELECT COUNT(*) > 0 FROM tbl_paper_roll WHERE lngindex = ?
    #}, undef, $id);
  } elsif ($paper->{custom}) {
    $paper_price = $paper->{Price};
    $$paper_price{buy_qty} = $price{'Buy Quantity'};
  }

  if ($press_type eq 'web' || $roll || $paper->{type} eq 'roll') {
    $price{'Roll Qty'} = sprintf('%.2f', eprint::paper::convert_sheets_into_rolls( $log, $dbh, $price{'Buy Quantity'}, $id));
  }

  #$price{'Buy Quantity'} = ceil($paper_price->{buy_qty});
  #$price{'Sheet Price'}  = $paper_price->{Price};

  my $baby_sheets;
  if ($paper->{width} > 0 && $paper->{height} > 0) {
    $baby_sheets = ($paper->{start_width} * $paper->{start_height}) / ($paper->{width} * $paper->{height});
  }

  my ($pack_qty, $break);
  if ($paper->{custom}) {
    ($pack_qty, $break) = ($paper->{sheets_per_package}, (int($paper->{full_packages}) ? 'N' : 'Y'));
    #print STDERR "Have pack_qty $pack_qty and $break $$paper{full_packages} from custom\n";
  } else {
    ($pack_qty, $break) = $dbh->selectrow_array(q{ SELECT lngPackageQty, ysnBreakable FROM tbl_Paper WHERE lngIndex = ?  }, {}, $id) if $id;
    #($pack_qty, $break) = @paper{'sheets_per_package','full_packages'};
  }

  $pack_qty *= $baby_sheets if $baby_sheets > 1;

  if ($break eq 'N' and $pack_qty) {
    $price{'Buy Quantity'} = (int($price{'Buy Quantity'} / $pack_qty) + 1) * $pack_qty if $price{'Buy Quantity'} % $pack_qty;
    print STDERR "Have pack new buy quantity $price{'Buy Quantity'}\n";

    if ($id) {
      # New buy quantity means getting a new dataset.
      $paper_price = eprint::paper::get_price($log, $dbh, $variable, $paper, $press, $price{'Buy Quantity'});
      #my $mod = $price{'Buy Quantity'} % $pack_qty;
    } elsif ($paper->{custom}) {
      $$paper_price{buy_qty} = $price{'Buy Quantity'};
    }
  }
  $price{'Sheet Price'} = $paper_price->{Price};

  if ($is_largeformat) {
    my $is_sqft = $paper_price->{units} eq 'square foot';

    if ($roll && !$is_sqft) {
      return (error => 'That particular selection does not have large format pricing.');
    }

    if ($is_sqft) {
      $price{'Buy Quantity'} = ceil($qty / ($imp->getSetup||1)) * get_lf_jobsize($imp) / 144;
    } else {
      # we're looking at sheet cost -- assuming there is one.
      #$price{'Buy Quantity'} = $imp->getSpreads * $qty;
      $price{'Buy Quantity'} = ceil(($imp->getSpreads * $qty) / ($imp->getSetup || 1));

      # New buy quantity means getting a new dataset.
      $paper_price = eprint::paper::get_price($log, $dbh, $variable, $paper, $press, $price{'Buy Quantity'});
      $price{'Sheet Price'} = $paper_price->{Price};
    }
  }
  # Custom Back Cover Code fro Safeway.
  if ( $project->{signature}{txtSignatureType} eq 'Cover Spreads' ) {
    if ( $cover->{index} ) {
      my $cover_price = eprint::paper::get_price(
        $log, $dbh, $variable, $cover, $press, $price{'Buy Quantity'}
      );
      #print STDERR "OLD PAPER PRICE", Dumper($paper_price) if DEBUG;
      $paper_price->{Price} = ( $paper_price->{Price} + $cover_price->{Price} ) / 2;
      #print STDERR "HAVE COVER SPECS", Dumper($cover, $cover_price, $paper_price) if DEBUG;
    }
  }

  $price{'Paper Cost'} = $price{'Buy Quantity'} * $paper_price->{Cost};

  $project_type = $$project{type};

  if ($project_type eq 'ScreenItem') {
    # If we're printing on an item then we don't use stock.
    $paper_price->{Price} = 0;

    # Rather than clobbering all the stock calculations, lets just make
    # the stock free and not worry about it.
  }

  $price{'Paper Price'}       = $price{'Buy Quantity'} * $paper_price->{Price};
  $price{'Setup Cost'}        = $setup_cost;

  $price{Impressions}       = $impressions;
  $price{'Impression Price'}  = $run_price{'Impression Price'};

  $price{hdnRunSpeed}       = $run_price{'Run Speed'};
  $price{hdnRunTime1}       = sprintf('%.2f',$impressions/$run_price{'Run Speed'}) if $run_price{'Run Speed'};

  $price{'PMS Run Price'}     = $pms_price->{'Total Run Price'} * $imposition;

  $price{'Aqueous Run Price'} = $aqueous{'Run Price'};
  $price{'UV Run Price'}      = $UV{'Run Price'};
  $price{'SoftTouch Run Price'}      = $SOFTTOUCH{'Run Price'};
  $price{'Varnish Run Price'} = $varnish_run_price;

  $price{'Press Setup'}       = $colour_setup{'Total Setup Cost'};
  $price{'Press Setup Cost'}  = $colour_setup{'Press Setup Cost'};
  $price{'Plate Cost'}        = $colour_setup{'Plate Cost'};
  $price{'Plate Material ID'} = $colour_setup{'Plate Material ID'};
  $price{'Film Cost'}         = $colour_setup{'Film Cost'};

  $price{'Run Price'}
  = $price{'Impression Price'}
  + $price{'PMS Run Price'}
  + $price{'Aqueous Run Price'}
  + $price{'SoftTouch Run Price'}
  + $price{'UV Run Price'}
  + $price{'Varnish Run Price'};

  my $run_cost = $price{'Run Price'} * $impressions / 1000;

  my $min_run_cost = eprint::service::get_price(
    $log, $dbh, $variable, 'PressRunMinimumCharge', '', $press
  );

  # Now we are only going to charge the Minimun run if the impressions
  # for all of our signatures in project still does not meet the min run charge.
  # If we do need to use the min run charge then pro-rate it over all of the signatures
  # based on the number of impreesions for each signature.
  my $ir = $run_price{ImpressionRange} * $print_sides;
  # Impression Range is the estimated number of impressions to complete the whole project.
  my $ip = $run_price{'Impression Price'};
  # Impression Price is the cost per 1000 impressions based on the Impression Range.
  if ( $ir && ($ip * $ir / 1000) < $min_run_cost ) {
    $run_cost = $impressions < $ir ? $min_run_cost * ( $impressions / $ir )
    : $min_run_cost;
    # Pro-rate the min_run_charge based on the number of impressions
  }

  $setup_cost -= $colour_setup{'Plate Cost'} if !$is_largeformat;
  callback::call('service_calc_end', $pid, $sid, \$setup_cost, \$run_cost, $press);
  $setup_cost += $colour_setup{'Plate Cost'} if !$is_largeformat;

  my $paper_cost = $paper_supplied ? 0 : $price{'Paper Price'};

  my $total_cost
  = $run_cost + $setup_cost + ($run_price{'Large Format'} * $qty);

  $price{txtStockPrice} = $paper_cost;

  $price{'Total Cost'} = $total_cost;

  $price{'Paper Comp Price'} = $price{paper}{width} * $price{paper}{height} / 10000;

  if ( $project->{override}{chargefor} eq 'PrintingOnly' ) {
    $price{txtStockPrice} = 0;
  } elsif ( $project->{override}{chargefor} eq 'StockOnly') {
    $price{'Total Cost'} = 0;
  } elsif ( $project->{override}{chargefor} eq 'Free') {
    $price{txtStockPrice} = 0;
    $price{'Total Cost'} = 0;
  }
  #print STDERR "HAVE PRICE OVERRIDE: $project->{override}{chargefor} \n", Dumper($project->{override});


  # The paper price must always be added to the comparison cost regardless
  # if paper is supplied by customer or the cost of paper is shown on the
  # interface.
  $price{'Comparison Cost'} =
  + $price{'Total Cost'}
  + $price{'Film Cost'}
  + ($price{'Paper Price'} || $price{'Paper Comp Price'})
  + ($paper_price->{stitch_price} * $qty) ;

  #print STDERR "HAVE PRICE DUMPER \n\n\nn", Dumper(\%price) if DEBUG;

  #print STDERR "HAVE PAPER COMP DUMPER \n\n\nn",
  #			Dumper( $price{'Paper Price'},  $price{'Paper Comp Price'},
  #					$price{paper}{width},   $price{paper}{height},
  #					$price{'Comparison Cost'}, $price{'Total Cost'} ,
  #					$price{paper}
  #			);

  # If the paper is supplied by customer then blank out the Price from the
  # hash this will take care of the hdn Form fields used for the price
  # breakdown.
  $price{'Paper Price'}          = '0.00' if $paper_supplied;

  $price{'Run Cost'}             = $run_cost;
  $price{'Imposition Charge'}    = $imposition_charge;
  $price{'Ink Mix Charge'}       = $pms_price->{'Ink Mix Charge'};
  $price{'Aqueous Setup Charge'} = $aqueous{'Setup Price'};
  $price{'UV Setup Charge'}      = $UV{'Setup Price'};
  $price{'SoftTouch Setup Charge'}      = $SOFTTOUCH{'Setup Price'};

  $price{'Setup Check'}          = $colour_setup{'Total Setup Cost'}
  + $imposition_charge
  + $workturn_dry_cost
  + $perfecting_change_over
  + $aqueous{'Setup Price'}
  + $UV{'Setup Price'}
  + $SOFTTOUCH{'Setup Price'}
  + $pms_price->{'Ink Mix Charge'}
  + $pms_price->{'Press Wash Charge'};

  $price{txtPlateQuantity}     = $colour_setup{'Plate Count'};
  $price{'MultiPass Run'}        = $run_price{'MultiPass Run'};
  $price{'WorkTurn Dry Charge'}  = $workturn_dry_cost;
  $price{'Press Wash Charge'}    = $pms_price->{'Press Wash Charge'}
  + $varnish_wash + $process_wash;
  return %price;
}


sub get_varnish_run_price {
  my ($log, $dbh, $variable,
    $press, $print_sides, $impressions, $dry_trap, @colours) = @_;

  # How many varnishes we have per sheet...
  my $varnish_sides = scalar grep { m/Varnish/ } @colours;

  my $run_price = 0;
  if ($varnish_sides) {
    if ($dry_trap) {
      $run_price = $dry_trap * eprint::service::get_price(
        $log, $dbh, $variable, 'VarnishDryTrap', $impressions, $press
      );
    }
    else {
      $run_price = eprint::service::get_price(
        $log, $dbh, $variable, 'Varnish', $impressions, $press
      );
    }

    $run_price /= 2 if $varnish_sides == 1;
  }

  return $run_price;
}


sub get_mixed_colours {
  my ($log, $dbh, $pid, $sid) = @_;
  my @service_colours = ();

  my @secondarys = @{ $dbh->selectcol_arrayref(q{
  SELECT lngServiceIndex FROM tbl_Service_Specifications
  WHERE strName = 'SecondarySignature' AND lngProjectIndex = ?
  }, {}, $pid) };

  foreach my $sig (eprint::project::get_signature_indices($log, $dbh, $pid)) {
    my $secondary = 0;
    $secondary = 1 if grep { $_ == $sig } @secondarys;

    if (($sig ne $sid and !$secondary)) {
      my ($inkmix) =
      eprint::service::get_specifications($log, $dbh, undef, $sig,
        'hdnInkMixColours');

      push @service_colours, split(';', $inkmix);
    }
  }

  return @service_colours;
}


# NOTE: Kludgey, kludge, kludge. Someone inserted some fun hash tricks in here
# to make it so the washup is only charged on the first (not secondary)
# signatures.
sub get_washed_colours {
  my ($log, $dbh, $pid, $sid) = @_;
  my %service_colours = ();

  my @secondarys = @{ $dbh->selectcol_arrayref(q{ SELECT lngServiceIndex FROM tbl_Service_Specifications WHERE strName = 'SecondarySignature' AND lngProjectIndex = ?  }, {}, $pid) };

  foreach my $sig (eprint::project::get_signature_indices($log, $dbh, $pid)) {
    my $secondary = grep { $_ == $sig } @secondarys;

    if (   ($sig ne $sid && !$secondary) || ($secondary && grep { $_ == $sid } @secondarys) ) {
      my ($wash, $press) =
      eprint::service::get_specifications($log, $dbh, undef, $sig, 'hdnInkMixColours', 'hdnPress');
      foreach my $colour (split(';', $wash)) {
        $service_colours{ $colour . $press } = 'washed';
      }
    }
  }
  return %service_colours;
}

#pass teh project hash and the coverage as an int value between 0-100 and the sheets per ink unit constant SHEETS_PER_UNIT_METALLIC or SHEETS_PER_UNIT_PANTONE
sub get_ink_coverage {
  my ($project, $pms_coverage, $sheets_per_ink_unit) = @_;
  my $area = $project->{image_width} * $project->{image_height};
  my $coverage = $pms_coverage / 100;

  return ( $area * $coverage / $sheets_per_ink_unit * 1000  );
}

# Returns a price per image, which will later need to be multiplied by the imposition
sub get_special_colours_price {
  my ($log,         $dbh,         $variable,      $pid,
    $sid,         $project,  	$press, 		$print_sides,
    $pms_coverage, $mixed_colours, $washed_colours,
    $special_colours)
  = @_;

  my $area = $project->{image_width} * $project->{image_height};
  my %press_units = map { $_->{name} => $_ } @{$project->{wx_press_units}};

  # Here we can get a special ink price penalty if we're doing screen
  # printing using UV ink or any other kind of penalty if there is a price
  # for it.
  my %price = (
    'Total Run Price'   => 0,
    'Ink Mix Charge'    => 0,
    'Press Wash Charge' => 0,
  );

  my $wash_price = eprint::service::get_price($log, $dbh, $variable, 'WashUp', '', $press);

  $price{inkQty}{total} = 0;
  $price{'Mixed Colours'} = '';

  foreach my $key (keys %$pms_coverage) {
    my $coverage            = $pms_coverage->{$key} / 100;
    my $sheets_per_ink_unit = SHEETS_PER_UNIT_PANTONE;

    # set ink material based on user input
    my $ink_mat = $press_units{$key}->{ink};

    my $mix_price = eprint::service::get_price($log, $dbh, $variable, $ink_mat . 'Mix', undef, $press);

    if ($special_colours->{$key}) {
      $sheets_per_ink_unit = SHEETS_PER_UNIT_METALLIC;
    }
    if (! grep { $_ eq $key } @$mixed_colours) {
      $price{'Ink Mix Charge'} += $mix_price;
      $price{'Mixed Colours'} .= ";$key";
    }

    $price{'Press Wash Charge'} += $wash_price
    if not $washed_colours->{ $key . $press };


    my $ink_units = get_ink_coverage($project, $pms_coverage->{$key}, $sheets_per_ink_unit);

    my $ink_price =
    eprint::material::get_price($log, $dbh, $variable, $ink_mat, $ink_units);

    my $run_price =  $ink_units * $ink_price / $print_sides;

    # And what might the magic 200,000 represent?
    $price{inkQty}{$key} = $area * $coverage / 200_000;

    $price{'Total Run Price'} += $run_price;
  }

  return \%price;
}


# Will return the lowest service index for a spread type, indicating the first
# signature in the group.
sub get_primary_signature_service {
  my ($log, $dbh, $pid, $signature_group) = @_;

  my $sth = $dbh->prepare_cached(q{
    SELECT lngserviceindex
    FROM tbl_service_specifications
    WHERE lngprojectindex = ?
    AND strname = ?
    AND strvalue = ?
    ORDER BY lngserviceindex
    LIMIT 1
    });

  return $dbh->selectrow_array($sth, {},
    $pid, 'txtSignatureType', $signature_group
  );
}

sub get_coating_price {
  my ($log,             $dbh,           $variable,    $sheet_qty,
    $coating_sides,   $press,         $print_sides, $is_sheetwork,
    $is_spot_coating, $pid,           $sid, $pages, $type)
  = @_;


  return ('Setup Price' => 0, 'Run Price' => 0)
  unless $coating_sides > 0 && $sid > 0;

  my $make_ready = 0;
  my $run_price  = 0;

  # Only charge a makeready if we are on signature number 0
  my $sth = $dbh->prepare_cached(q{
    SELECT count(*)
    FROM tbl_service_specifications
    WHERE lngprojectindex = ?
    AND strname = 'txtSignatureSize'
    });
  my $single_sig_index =
  ($dbh->selectrow_array($sth, undef, $pid))[0];


  # If we're the first and only signature, or we're the first in our
  # spread group, charge the AQ MakeReady if they've priced it.
  if ($single_sig_index == 0
    || $sid == get_primary_signature_service($log, $dbh, $pid, 'Interior Spreads')
    || $sid == get_primary_signature_service($log, $dbh, $pid, 'GateFolded Spreads')
    || $sid == get_primary_signature_service($log, $dbh, $pid, 'Cover Spreads'))
  {
    $make_ready +=
    eprint::service::get_price($log, $dbh, $variable, $type . 'MakeReady', '', $press);
  }

  $make_ready +=
  eprint::service::get_price($log, $dbh, $variable, $type . 'SignatureMakeReady', '', $press) if $pages > 1;

  if ($is_spot_coating) {
    $make_ready += eprint::service::get_price($log, $dbh, $variable, $type . 'SpotBlanketCut', '', $press);
  }
  elsif ($coating_sides == 1 and !$is_sheetwork) {
    $make_ready += eprint::service::get_price($log, $dbh, $variable, $type . 'BlanketCut', '', $press);
  }

  $run_price +=
  eprint::service::get_price($log, $dbh, $variable, $type,
    $sheet_qty * $coating_sides, $press);
  $run_price *= $coating_sides / $print_sides;

  return ('Setup Price' => $make_ready, 'Run Price' => $run_price);
}

sub get_largeformat_price {
  my ($log,            $dbh,              $variable,
    $press_sheets,   $side_one_colours, $side_two_colours,
    $paper_calliper, $is_perfecting,    $press,
    $project_type,   $imp,              $large_format,
    $qty,  			 $project) = @_;

  my $max_colours = eprint::equipment::get_specification(
    $log, $dbh, 'Number of Colours', q{}, $press
  );

  my $width  = $imp->getImageWidth  + $project->{bleed}[1] + $project->{bleed}[3];
  my $height = $imp->getImageHeight + $project->{bleed}[0] + $project->{bleed}[2];
  my $squarefeet   = $width * $height  /  12 ** 2;

  my %run_price = ( 'Impression Price' => 0 );

  # job is more colours than the printer can print.
  return if grep { $_ > $max_colours } $side_one_colours, $side_two_colours;

  @{ $large_format->{quality} }
  = map { $_ ||= 'High'; $_; } @{ $large_format->{quality} };

  my @sides = (
    { colours  => $side_one_colours,
      quality  => $large_format->{quality}->[0],
      coverage => $large_format->{coverage}->[0],
    },
    { colours  => $side_two_colours,
      quality  => $large_format->{quality}->[1],
      coverage => $large_format->{coverage}->[1],
    },
  );

  my $mount_setup;
  if ($large_format->{mounting}) {
    require eprint::Service::Mounting;
    my $mount_obj = eprint::Service::Mounting->new();
    my @mount_price = $mount_obj->calc(
      $log, $dbh, $variable, $variable->{ProjectIndex}, undef, 'Mounting', {
        ddmMounting => $large_format->{mounting},
        flat_height   => $imp->{image_width},
        flat_width    => $imp->{image_height},
      }
    );

    # Subtract Setup Price from combined price so we have just
    # serivce & material left.
    $mount_setup = $mount_price[3];
    $mount_price[1] = $mount_price[1] - $mount_setup;
    $run_price{'Large Format'} += sprintf '%.2f', $mount_price[1];
    $run_price{'Impression Price'} += sprintf '%.2f', $mount_price[1];
  }

  #    if ( grep { $_ } @{ $large_format->{laminate} } ) {
  #        require eprint::Service::Laminating;
  #        my $laminate_obj = eprint::Service::Laminating->new();
  #        my ($device, $price, $material, $lam_setup) = $laminate_obj->calc_price(
  #            $log, $dbh, $variable, {
  #                s0_laminate => $large_format->{laminate}->[0],
  #                s1_laminate => $large_format->{laminate}->[1],
  #                flat_height          => $imp->getImageHeight,
  #                flat_width           => $imp->getImageWidth,
  #            }
  #        );
  #
  #        $run_price{'Large Format'} += sprintf '%.2f', $price+$material;
  #    }


  SIDES:
  foreach my $side (@sides) {
    next SIDES if !$side->{colours};

    my $quality
    = ucfirst($side->{quality}) . " Quality Multiplier";


    my $multiplier = eprint::equipment::get_specification(
      $log, $dbh, $quality, q{}, $press
    ) || 100;

    $multiplier /= 100;

    my $coverage = $side->{coverage};


    if ($side->{colours}) {
      my $service = $side->{colours} == 4 ? 'LFPrint4Colour'
      :                         'LFPrint1Colour';

      my $ink     = $side->{colours} == 4 ? 'lf4colour'
      :                         'lf1colour';

      $variable->{force_device} = $press;

      my $names = {
        action    => 'Printing',
        service   => $service,
        makeready => 'PressMakeReady',
        mincharge => 'PressRunMinimumCharge',
      };

      my ($device, $full_price, $material_price, $setup)
      = get_service_full_price(
        $log, $dbh, $variable, $names, $squarefeet * $qty, $ink
      );

      $full_price     -= ($material_price + $setup);
      $full_price     *= $multiplier if $multiplier;

      $full_price /= $qty;
      $material_price /= $qty;

      $material_price *= $coverage;

      $run_price{'Largeformat Setup'} = $setup + $mount_setup;

      $run_price{'Impression Price'}
      += sprintf '%.2f', ($full_price + $material_price) * 1000;
    }
  }

  return %run_price;
}


sub get_run_price {
  my ($log,            $dbh,              $variable,
    $press_sheets,   $side_one_colours, $side_two_colours,
    $paper_calliper, $is_perfecting,    $press,
    $project_type,   $pages, $press_type, $imp, $foil, $underbase)
  = @_;


  # $press_sheets is used only for the price lookup range.
  # For Digital multipage projects we are going to look up
  # our impression prices based on a range for printing the whole book.

  # Our number is the Press sheet Count * the number of spreads for the
  # entire book divided by the number spreads in the imposition
  if ( $press_type eq 'digital' && $pages > 1 && $imp->{spreads} ) {
    $press_sheets = $press_sheets * $pages / $imp->{spreads};
    # If printing on both sides then double the lookup range to
    # include printing both sides.
    $press_sheets = $press_sheets * 2 if ( $side_two_colours );
  }
  if ( $press_type eq 'web' ) {
    # We have not Converted the pricing for Web to the Perfecting Format yet.
    # This can be removed once the pricing changeover is completed.
    $is_perfecting = 0;
  }

  my %run_price;
  $run_price{ImpressionRange} = $press_sheets;
  my $running_price = 0;
  my $max_colours   = eprint::equipment::get_specification($log, $dbh, 'Number of Colours', '', $press);

  if (!$max_colours) {
    $log->error( "PRINTING: FATAL ERROR: Could Not Get 'Number of Colours' for Press: $press");
    return %run_price;
  }
  my $impression_service = $is_perfecting ? 'ColourImpressionPerfecting' : 'ColourImpression';
  if ( $press_type ne 'web' && $is_perfecting && $side_two_colours ) {
    my $s = $side_one_colours.'-'.$side_two_colours . $impression_service;
    $running_price = eprint::service::get_price($log, $dbh, $variable,$s, $press_sheets, $press);

    # $log->error("1: Could not Find Impression Price For Service: $s on Press: $press Qty Range: $press_sheets") if ( $running_price == 0 );

    #$running_price /= 2;

  } else {
    if ($side_one_colours) {
      my $full_runs   = int($side_one_colours / $max_colours);
      my $run_colours =
      $side_one_colours > $max_colours ? $max_colours : $side_one_colours;
      my $s = $run_colours . $impression_service;

      if ( $full_runs ) {
        $running_price = eprint::service::get_price($log, $dbh, $variable, $s, $press_sheets, $press) * $full_runs;

        # $log->error("2: Could not Find Impression Price For Service: $s on Press: $press Qty Range: $press_sheets Run Price: $running_price ") if ( $running_price == 0 );
      }

      my $mod_colours = $side_one_colours % $max_colours;
      if ($mod_colours) {
        $s =  $mod_colours . $impression_service;
        my $m_price = eprint::service::get_price($log, $dbh, $variable, $s, $press_sheets, $press);
        # $log->error("3:. Could not Find Impression Price For Service: $s on Press: $press Qty Range: $press_sheets") if ( $m_price == 0 );
        $running_price += $m_price;
      }
      $openprint::log->error("1 Running price = $running_price") if !$running_price;
    }

    if ($side_two_colours) {
      my $full_runs   = int($side_two_colours / $max_colours);
      my $run_colours = $side_two_colours > $max_colours ? $max_colours : $side_two_colours;
      my $side_two_running_price = eprint::service::get_price($log, $dbh, $variable, $run_colours . $impression_service, $press_sheets, $press);
      $running_price += $side_two_running_price * $full_runs;
      if (!$side_two_running_price) {
        $openprint::log->error("No Side 2 running price for $run_colours $impression_service $press_sheets $press = $side_two_running_price");
      } else {
        my $mod_colours = $side_two_colours % $max_colours;
        if ($mod_colours) {
          $running_price += eprint::service::get_price($log, $dbh, $variable, $mod_colours . $impression_service, $press_sheets, $press);
        }
        #$running_price /= 2 if $side_one_colours;
      }
    }
  }

  if ( $foil ) {
    $running_price += (eprint::service::get_price($log, $dbh,
        $variable, 'ScreenFoilGluing', $press_sheets)) * $foil;
  }

  if ( $underbase ) {
    my $sides = $side_one_colours && $side_two_colours ? 2 : 1;
    $running_price += (eprint::service::get_price($log, $dbh,
        $variable, 'DischargeUnderbase', $press_sheets)) * $sides;
  }


  if ($side_one_colours > $max_colours or $side_two_colours > $max_colours) {
    $run_price{'MultiPass Run'} = 1;

  }
  else {
    $run_price{'MultiPass Run'} = 0;
  }

  # Now work out the press run speed.
  my ($std_speed, $run_speed) = (0, 0);
  $std_speed = eprint::equipment::get_specification(
    $log, $dbh, 'Press Standard Run Speed', '', $press
  );

  # There will be no additional runspeed for envelopes at all and they will
  # not use the additional runspeed for non-envelopes.
  if ($project_type eq 'Envelopes') {
    $run_speed = eprint::equipment::get_specification(
      $log, $dbh, 'Envelope Run Speed Override', '', $press
    );
  }
  else {
    $run_speed = eprint::equipment::get_specification(
      $log, $dbh, 'Press Additional Run Speed', $paper_calliper, $press
    );
  }
  if ($std_speed and $run_speed) {

    $running_price *= ($std_speed / $run_speed);

  }
  $run_price{'Impression Price'} = $running_price;
  $run_price{'Run Speed'} = $run_speed ? $run_speed : $std_speed;


  return %run_price;
}


# Returns the number of washes needed for varnish units. Takes a press, run
# style, whether there is any dry trapping or not, and the inks used. This
# _could_ be rolled into special_colours_price but there are some issues with
# that. The number of arguements is ridiculous but there are no data
# structures in use in the main estimation code.
sub get_varnish_wash_price {
  my $log      = shift;
  my $dbh      = shift;
  my $variable = shift;

  my $press       = shift;    # The press ID
  my $run_style   = shift;    # Run style (Perfecting, W&T, etc.)
  my $print_sides = shift;
  my $dry_trap    = shift;    # Whether we're dry trapping
  my $washed      = shift;    # inks alredy washed in this project.
  my @ink         = @_;       # Inks (not differentiated by side)

  my $varnish_wash = 0;

  # Every varnish chosen will use it's own press unit if we're only printing
  # one side, we're running perfecting, or dry trapping was chosen. In the
  # case of dry trapping we dont't currently know which colour or varnish it
  # applies to so we just assume them all.
  if ($print_sides < 2 or $dry_trap or $run_style eq 'Perfecting') {
    $varnish_wash = scalar grep { /Varnish/ } @ink;
  }

  # If we're printing two sides, with Sheetwork we can reuse the press unit
  # from the same type of varnish and just change the plate for the other
  # side. With W&T we only need a press unit per individual type of varnish
  # as it uses the same press unit and plate for both sides.
  else {
    my %uniq;    # Use a hash to filter unique varnish types.

    for (@ink) {
      # Skip non-varnish inks.

      next unless /Varnish/i;
      next if $$washed{ $_ . $press };


      # We don't care if they're Spot or Flood, only if they're Matte,
      # Silk, Gloss, etc.
      s/(Overall|Spot)//g;

      # Filter only unqiue varnish types by using hash keys.
      $uniq{$_}++;
    }
    $varnish_wash = scalar keys %uniq;
  }

  $varnish_wash = $varnish_wash
  * eprint::service::get_price(
    $log, $dbh, $variable, 'WashUp', '', $press)
  if $varnish_wash;

  return $varnish_wash;
}


# Return the Cost of washing all of the Process Press units
# First checks to see if Press requires washing of the Process units.
# this function also needs to be rolled into a common washup funciton.
sub get_process_wash_price {
  my $log      = shift;
  my $dbh      = shift;
  my $variable = shift;

  my $press       = shift;    # The press ID
  my $run_style   = shift;    # Run style (Perfecting, W&T, etc.)
  my $print_sides = shift;
  my $chem_emboss = shift;
  my @ink         = @_;       # Inks (not differentiated by side)

  my @process_colours = qw(Cyan Yellow Magenta Black);

  my $wash = 0;

  my $add_wash = eprint::equipment::get_specification(
    $log, $dbh, 'Process Colour Washup', '', $press
  );

  if ($add_wash eq 'Y' || $chem_emboss) {
    if ($print_sides < 2 or $run_style eq 'Perfecting') {
      foreach my $clr (@ink) {
        # Add a wash for each process colour.
        $wash++ if grep { $_ eq $clr } @process_colours;
      }
    }
    else {
      # Add 1 wash for unique each process colour
      my %uniq; # Use a hash to filter unique varnish types.
      foreach my $clr (@ink) {
        $uniq{$clr}++ if grep { $_ eq $clr } @process_colours;
      }
      $wash = scalar keys %uniq;
    }
  }

  my $wash_price = eprint::service::get_price(
    $log, $dbh, $variable, 'WashUp', '', $press
  );
  my $process_wash = 0;
  $process_wash = $wash * $wash_price if $wash > 0;

  return $process_wash;
}


sub calc_sheet_qty {
  my ($log,         $dbh,           $qty,            $colours,
    $press,       $imposition,    $version_waste,  $pid,
    $print_sides, $unit_overs_OR, $run_overs_OR,   $run_style,
    $paper,		  $imp, $cover, $colourcritical_overs, $variable, $project ) = @_;

  return 0 if !$imposition;

  #print STDERR "CALC SHEETY QTY IMP: $imposition QTY: $qty  SIG $variable->{SignatureQuantity} \n";

  my $net_sheets = 0;
  $net_sheets = ceil($qty / $imposition) if $imposition;

  if ( $imp->{paper}{type} eq 'sheet' && $imp->{stitch_size} ) {
    $net_sheets *= $imp->{spread_rows} * $imp->{spread_cols};
  }
  if ( $cover->{sides} == 2 ) {
    $net_sheets *= 2;
  }


  # MULTI-VERSION: INCORRECT AND OVERLY SIMPLISTIC CODE FOR THE DEMO.
  $net_sheets = ceil($net_sheets * (1 + $version_waste/100))
  if $version_waste > 0;

  my $net_forms = $net_sheets;

  my ($form_multiplier) = 1;
  if ( $$paper{index} and !exists($$paper{multipart})) {
    # We need to adjust the net sheets (and everything downstream from them)
    # here for multipart forms.
    $_ = "SELECT lngmultipart FROM tbl_Paper where lngIndex = '$$paper{index}'";
    @$paper{multipart} = sql::sql_statement( $log, $dbh, $_ );
  }
  if ($$paper{multipart}) {
    my $form_multiplier = $$paper{multipart};
    if ($form_multiplier > 1) {
      $net_sheets *= $form_multiplier
    } else {
      $form_multiplier = 1;
    }
  }

  my $min_overs      = 0;
  my $min_overs_spec =
  eprint::equipment::get_specification($log, $dbh,
    'Press Run Overs Minimum',
    '', $press);
  $min_overs = $min_overs_spec if $min_overs_spec ne '';

  my $setup_overs;

  if ( $unit_overs_OR ne '' ) {
    $setup_overs = $unit_overs_OR
  } else {
    my $overs_per_colour =
    eprint::equipment::get_specification($log, $dbh, 'Press Unit Setup Overs', $colours, $press);

    my $first_unit_overs =
    eprint::equipment::get_specification($log, $dbh, 'First Unit Setup Overs', $colours, $press);

    $first_unit_overs = $overs_per_colour unless $first_unit_overs;

    $setup_overs = $first_unit_overs + ($overs_per_colour * ($colours - 1));
  }

  #multi-page multi-version overs adjustment
  if ($$project{bookid}) {
    #need the number of versions if there aren't more than one this function isn't needed
    my ($num_versions) = $$project{num_versions};
    my ($mv_mp_overs) = eprint::equipment::get_specification($log, $dbh, 'mv_mp_overs', 0, $press);
    $setup_overs += $mv_mp_overs * ($num_versions - 1) * $colours if $num_versions > 1 && $mv_mp_overs > 0;
  }

  # Running waste is sheets that are printed wrong for some reason or
  # another during the press run. The error rate generally decreases with
  # the length of the run.
  # For W/T, W/F, and Perfecting both sides are printed in one press run.
  # This doubles the length of the press run, so we will look up overs accordingly.
  #my $over_range = ( $run_style =~ /^Work/  or $run_style eq 'Perfecting') ? $net_sheets * 2 : $net_sheets;
  # Chris has now reversed his decision. All over ranges will be looked up
  # by the number of press sheets.
  my $over_range = $net_sheets;
  my $over_rate =
  eprint::equipment::get_specification($log, $dbh, 'Press Run Overs',
    $over_range, $press);

  $over_rate = $run_overs_OR if $run_overs_OR ne '';
  my $run_overs = ceil($net_sheets * $over_rate);
  $run_overs = $run_overs * $print_sides if $print_sides > 1;

  # Get the bindery (and other service) overs that we will need to provide
  # extra sheets for.
  # my ($service_setup_overs, $service_run_overs)
  #    = calc_service_overs($log, $dbh, $pid);

  my ($service_setup_overs, $service_run_overs)  = (0,0);


  # Only factor in service setup overs if they exceed press run overs.
  if ($service_setup_overs > $setup_overs) {
    $setup_overs = $service_setup_overs
  }
  $run_overs += ceil($service_run_overs * $net_sheets / 100);

  # Add the colour critical set up overs
  $setup_overs += ($colourcritical_overs * $colours);
  if ( $unit_overs_OR ne '' ) {
    $setup_overs = $unit_overs_OR
  }
  if ( $run_overs_OR ne '' ) {
    $run_overs = ceil($net_sheets * $run_overs_OR);
  } else {
    $run_overs = $min_overs unless $run_overs > $min_overs;
  }

  # The total required overs is the sum of the sheets needed to setup the
  # press and the total running waste. Unless that sum is less than the
  # mininum number of overs wanted for the press (set by user).
  my $overs       = $setup_overs + $run_overs;
  my $gross_forms = ceil(($overs + $net_sheets) / $form_multiplier);
  my %sheet_qty = ('Gross Sheet Count' => $overs + $net_sheets,
    'Net Sheet Count'   => $net_sheets,
    'Setup Overs'       => ($overs == $min_overs)
    ? $min_overs - $run_overs
    : $setup_overs,
    'Running Overs'    => $run_overs,
    'Net Form Count'   => $net_forms,
    'Gross Form Count' => $gross_forms,
    'Unit Setup Override' => $unit_overs_OR,
    'Run Overs Override' => $run_overs_OR,
    'Service/Bindery Setup' => $service_setup_overs,
    'Service/Bindery RUN' => $service_run_overs,
  );


  #print STDERR "HAVE SHEETY QTY: ", Dumper(\%sheet_qty);
  return %sheet_qty;
}


sub press_setup_cost {
  my ($log,              $dbh,        $project, $jig_specifics,
    $width,            $height,     $variable,
    $paper_calliper,   $press,      $used_plates,
    $plate_change_qty, $sheet_area, $plate_runs,
    $colourcritical_make_ready, @colours)
  = @_;

  my ($plate_count, $total_setup, $plate_total);
  # Plate total is the cost of the acutual plate material which does not get
  # included in the printing price.  it is only used to compare cost of
  # different runstyles.

  my $press_unit_price = eprint::service::get_price(
    $log, $dbh, $variable, 'PressUnitMakeReady', $paper_calliper, $press
  );



  #Apply our colour critical markup to the Press Unit setup price
  $press_unit_price *=  1 + ($colourcritical_make_ready / 100.0);


  # Screen printing's equivalent to plates are screen: Screens are wooden
  # frames with a fabric screen stretched over the frame. TODO: Screens wear
  # out and follow the same multi-version rules as plates, treat them in a
  # better manner than just adding them to press unit setup.
  my $screen_total;

  if (eprint::equipment::get_type($log, $dbh, $press) eq 'screen') {

    # Add 6 inches of screen in all directions.
    my $area = (SCREEN_LAP + $width  + SCREEN_LAP)
    * (SCREEN_LAP + $height + SCREEN_LAP);

    my $screen_material = eprint::material::get_price(
      $log, $dbh, $variable, 'Screen', $area, undef
    );
    # TODO: This should be checking on equipment.
    my $screen_service  = eprint::service::get_price(
      $log, $dbh, $variable, 'ScreenMaking', undef, undef
    );

    $screen_total      = ($screen_material * $area) + $screen_service;

    # Screen presses may need jigs to process oddly shaped items.
    my $jig_price = 0;
    if ($jig_specifics eq 'supplied' || $jig_specifics eq 'custom') {
      # Make ready charge.
      $jig_price += eprint::service::get_price(
        $log, $dbh, $variable, 'JigMakeReady', undef, undef
      );

      # Making the jig only applies to custom jobs.
      $jig_price += eprint::service::get_price(
        $log, $dbh, $variable, 'JigMaking', undef, undef
      ) if $jig_specifics eq 'custom';

      $total_setup += $jig_price;
    }
  }

  foreach my $colour (@colours) {
    if ($colour eq 'InlineBinderyNoPlate') {
      # no plate
    }
    elsif ($colour =~ /^Overall Varnish/) {
      $total_setup += $press_unit_price;
    }
    elsif ($colour =~ /^Spot Varnish/) {
      # If we don't already have an overall of the same type then add a
      # plate.
      $plate_count += 1;
      $total_setup += $press_unit_price;
    }
    else {
      $plate_count += 1;
      $total_setup += $press_unit_price;
    }
  }

  my $plate_count_before_changes = $plate_count;
  if ($plate_change_qty > 0) {
    $total_setup += $press_unit_price * $plate_change_qty;
    $plate_count += $plate_change_qty;
  }
  my $plate_price_qty = $plate_count + $used_plates;

  my ($plate_type) =
  eprint::equipment::get_specification(
    $log, $dbh, 'Plate Type', '', $press
  );

  my ($plate_size) = eprint::equipment::get_specification(
    $log, $dbh, 'Plate Size', '', $press
  );

  my $pid = $variable->{project_index};

  my $design = $dbh->selectrow_array(q{
    SELECT strdesign FROM tbl_projects WHERE lngprojectindex = ?
    }, {}, $pid);


  $plate_size = 0 if $design eq 'PlatesSupplied';

  my $plate_id = "$plate_size-${plate_type}Plate";

  # Becuase the material ID for plates is the PlateSetter we do not send the
  # press to get a plate price or it will not find it.
  $plate_price_qty *= $variable->{SignatureQuantity}
  if $variable->{SignatureQuantity} > 1;

  my $plate_price = 0;
  if ($plate_size) {
    $plate_price =
    eprint::material::get_price($log, $dbh, $variable, $plate_id,
      $plate_price_qty, $press);
    $plate_price =
    eprint::material::get_price($log, $dbh, $variable, $plate_id,
      $plate_price_qty)
    if !$plate_price;

    # this code is nolonger factoring in the plate making service price
  }

  my $wash_price =
  eprint::service::get_price($log, $dbh, $variable, 'WashUp', '', $press);

  # if our plates wear out before job is finshed then we will
  # need additional plates.
  if ($plate_runs > 1) {
    $plate_count += $plate_count_before_changes * ($plate_runs - 1);
  }

  $plate_total = $plate_count * $plate_price;

  my $film_cost = 0;

  if ($screen_total) {
    $film_cost = eprint::service::get_price(
      $log, $dbh, $variable, 'Film', $sheet_area * $plate_price_qty, ''
    );
    $film_cost *= $sheet_area * $plate_count;

  }

  # Plate making price is now based
  my $plate_making_price = eprint::service::get_price(
    $log, $dbh, $variable, 'PlateMaking', $plate_count, undef
  );

  $total_setup += $plate_making_price * $plate_count if $plate_price;

  my $press_make_ready = eprint::service::get_price(
    $log, $dbh, $variable, 'PressMakeReady', $paper_calliper, $press
  );
  my $plate_making_make_ready = eprint::service::get_price(
    $log, $dbh, $variable, 'PlateMakingMakeReady', $paper_calliper, undef
  );

  $total_setup += $press_make_ready;

  $plate_total += $plate_making_make_ready if $plate_count;

  if ( $screen_total > 0 ) { $plate_total += ($screen_total * $plate_count) }
  else                     { $plate_total  = 0 unless $plate_price          }

  my $envelope_setup = 0;
  if ($$project{type} eq 'Envelopes') {
    $envelope_setup =
    eprint::service::get_price($log, $dbh, $variable, 'EnvelopeSetup',
      undef, $press);

  }
  $total_setup += $envelope_setup;
  $total_setup += $press_make_ready * ($colourcritical_make_ready / 100.0);

  print STDERR "HAVE PRESS SETUP ", Dumper( {
      'Envelope Setup'  => $envelope_setup,
      'Plate Count'     => $plate_count,
      'Plate Price'             => $plate_price,
      'Plate Material ID'       => $plate_id,
      'Press Unit Setup Price'  => $press_unit_price,
      'Plate Type'              => $plate_type,
      'Film Cost'               => $film_cost,
      'Plate Cost'              => $plate_total,
      'Press Setup Cost'        => $total_setup,

      'Total Setup Cost'  => $total_setup + $plate_total,
    }
  ) if DEBUG;

  return (
    'Envelope Setup'  => $envelope_setup,
    'Plate Count'     => $plate_count,

    'Plate Price'             => $plate_price,
    'Plate Material ID'       => $plate_id,
    'Press Unit Setup Price'  => $press_unit_price,
    'Plate Type'              => $plate_type,
    'Film Cost'               => $film_cost,
    'Plate Cost'              => $plate_total,
    'Press Setup Cost'        => $total_setup,
    'Total Setup Cost'  => $total_setup + $plate_total,
  );
}


sub cut_signatures {
  my ($pid, $specs, $project) = @_;

  $log->debug(Data::Dumper::Dumper($project));
  my $bind_type  = $$project{bind_type};
  my $press_type = $$project{press_type};

  die "No bindery type found for p:$pid" unless $bind_type;

  my $spread_size = $bind_type =~ /^(Loop|Saddle)Stitching$/ ? 4 : 2;

  my ($rows, $cols);
  my $signature_size = $$specs{spreads_in_group};
  my $signature_qty  = $$specs{txtSignatureQuantity};
  my %count;
  $count{$_} = 0 for (2,4,6,8,12,16,24,32,64);

  if ( $press_type eq 'digital' ) {
    my $new_size = $signature_size % 2 ? 1 : 2;
    $count{$spread_size * $new_size} = $signature_qty * ($signature_size / $new_size);
    return %count;
  }

  if ($$specs{SpreadRows} && $$specs{SpreadCols} && ($signature_size != 1)) {
    $rows = $$specs{SpreadRows} / $$specs{hdnImpositionRows};
    $cols = $$specs{SpreadCols} / $$specs{hdnImpositionColumns};
  } else {
    $count{4} = $signature_qty;
    return %count;
  }

  ($cols, $rows) = ($rows, $cols) if ($cols > $rows);

  my $cutting_signatures = $signature_size;

  if ($cutting_signatures && $cutting_signatures != $rows * $cols) {
    my $part_row = $rows - (($rows * $cols) - ($cutting_signatures));
    $cols--;
    my $spreads = $part_row * $spread_size;
    if ( $spreads == 12 ) {
      $count{8}++;
      $count{4}++;
    } else {
      $count{ $part_row * $spread_size } = 1;
    }
    return %count if $part_row == $cutting_signatures;
  }

  my $whole_row_sets = $rows > 4 ? int($rows / 4) : 0;
  my $mod_row_sets   = $rows > 4 ? $rows % 4      : $rows;
  my $whole_col_sets = $cols > 1 ? int($cols / 2) : 0;
  my $mod_col_sets   = $cols > 1 ? $cols % 2      : 1;

  $count{ 8 * $spread_size } += $whole_row_sets * $whole_col_sets;
  $count{ 4 * $spread_size } += $whole_row_sets * $mod_col_sets;
  $count{ $mod_row_sets * 2 * $spread_size } += $whole_col_sets;
  $count{ $mod_row_sets * 1 * $spread_size } += $mod_col_sets;

  foreach my $k (keys %count) {
    $count{$k} *= $$specs{txtSignatureQuantity} if $$specs{txtSignatureQuantity};
  }

  return %count;
}

sub valid_price {
  my $price = shift;

  $$price{'Valid Price'} = 0;

  if ($$price{'Impression Price'} == 0) {
    $openprint::log->debug('Impression price is 0');
    return 0;
  }
  if ( $$price{reject_mv_layout} ) {
    $openprint::log->error('PRICE REJECTED FOR INVALID MV LAYOUT '. Dumper($price));
    return 0;
  }

  $$price{'Valid Price'} = 1;

  return 1;
}

# This subroutine will take in the original and supplied prices of a stock and
# calculate the price of cutting down that stock.  It may be a lot of
# computational work, but it is orders of magnitude smaller than what already
# goes on and this will be accurate, taking the guesswork out of precutting
# that is making it difficult to debug.
#
# TODO: Remove this and have a more approriate routine in the cutting module.
sub get_cutdown_cost {
  my ($log, $dbh, $variable, $new_width, $old_width, $new_height, $old_height, $calliper, $sheetcount) = @_;

  my $total_cuts = ceil($old_width / $new_width) + ceil($old_height / $new_height);

  $cutters = $dbh->selectcol_arrayref(q{ SELECT strid FROM tbl_equipment WHERE strtype = 'cutter' }) if !$cutters;

  my $bestprice = 0;
  foreach my $current_equipment (@$cutters) {
    my $price = eprint::service::get_price($log, $dbh, $variable, 'CuttingMakeReady', undef, $current_equipment);

    my $serviceprice = eprint::service::get_price($log, $dbh, $variable, 'Cutting', $total_cuts, $current_equipment);

    my $lift_depth = eprint::equipment::get_specification($log, $dbh, 'Maximum Lift Depth', $calliper, $current_equipment);

    my $lifts = ceil($calliper * $sheetcount / $lift_depth);

    $price += ($serviceprice * $total_cuts * $lifts);

    if ((!$bestprice) || ($price < $bestprice)) { $bestprice = $price }
  }
  if (!$bestprice) {
    $log->error( "UNABLE TO PRICE PRECUTTING OF STOCK - NO CUTTER WITH VALID PRICING IN SYSTEM");
  }

  return $bestprice;
}


sub get_imposition_charge {
  my ($log,           $dbh,              $variable,
    $pid,           $sid,              $imageHeight,
    $imageWidth,    $press,            $imposition,
    $imp,           $side_one_colours, $side_two_colours,
    $spreads_remaining, $metal_effects)
  = @_;
  my ($imposition_charge, $trapping_make_ready, $trapping_charge);


  # Multi-signature.
  if ($spreads_remaining) {
    my $multisignature_imposition = eprint::service::get_price(
      $log, $dbh, $variable,
      'ImpositionBookMakeReady',
      $imageHeight * $imageWidth,
      $press
    );


    if ($multisignature_imposition eq '' || $multisignature_imposition == 0) {
      # Old standard system for multi-signature, but with ranges
      # possible - this runs when there is no ImpositionBookMakeReady
      # priced.
      $imposition_charge =
      eprint::service::get_price($log, $dbh, $variable,
        'ImpositionMakeReady', $imageHeight * $imageWidth, $press);

      $imposition_charge +=
      eprint::service::get_price($log, $dbh, $variable, 'Imposition',
        $imageHeight * $imageWidth, $press) * $imposition;

      if ((@$side_one_colours > 1) || (@$side_two_colours > 1)) {
        # Only apply trapping charge if we have more than 1 colour on a side.

        $trapping_charge =
        eprint::service::get_price($log, $dbh, $variable, 'Trapping',
          $imageHeight * $imageWidth, $press) * $imposition;

        $trapping_make_ready =
        eprint::service::get_price($log, $dbh, $variable,
          'TrappingMakeReady', $imageHeight * $imageWidth, $press);
      }
    } else {
      $imposition_charge =
      $multisignature_imposition;    #this covers the make-ready
      my $per_page_charge =
      eprint::service::get_price($log, $dbh, $variable,
        'ImpositionBook', $imageHeight * $imageWidth, $press);

      $imposition_charge += $per_page_charge * $$imp{spreads} * 4 * $$imp{setup};    #since we will have 4 pages per spread
      print STDERR "PER PGE: $per_page_charge SPREADS: $$imp{spreads}  SETUP: $$imp{setup} WIDTH: $imageWidth x $imageHeight; TOTA: $imposition_charge \n", Dumper($imp) if DEBUG;

      my $base_trapping;
      if ((@$side_one_colours > 1) || (@$side_two_colours > 1)) {

        # Now do trapping if we have more than one colour
        $base_trapping =
        eprint::service::get_price($log, $dbh, $variable,
          'TrappingBook', $imageHeight * $imageWidth, $press);

        $trapping_charge =
        $base_trapping * $$imp{spreads} * 4 * $$imp{setup};

        $trapping_make_ready =
        eprint::service::get_price($log, $dbh, $variable,
          'TrappingBookMakeReady', $imageHeight * $imageWidth,
          $press);

        $imposition_charge += $trapping_charge if $trapping_charge > 0;
        $imposition_charge += $trapping_make_ready
        if $trapping_make_ready > 0;

        print STDERR "Add Trapping Charge:  $trapping_charge MR: trapping_make_ready IMP CHARGE TOTAl: $imposition_charge   \n" if DEBUG;
      }


      # Shove in group factor here so that we can use it later for price # correction
      my $group_factor =
      ($per_page_charge + $base_trapping) * $$imp{spreads} * 4 * $$imp{setup};    # includes imposition AND trapping
      print STDERR "GROUP FACTOR : $group_factor PPC: $per_page_charge BASE TRAP:  $base_trapping \n" if DEBUG;

      # Wipe out any previous group factors for this signature
      $dbh->do(q{
        DELETE FROM tbl_service_specifications
        WHERE lngserviceindex = ?
        AND strname = 'GroupFactor'
        }, {}, $sid);

      # Put in one group factor for this signature
      $dbh->do(q{
        INSERT INTO tbl_service_specifications
        (lngprojectindex, lngserviceindex, strname, strvalue)
        VALUES (?, ?, 'GroupFactor', ?)
        }, {}, $pid, $sid, $group_factor) if $sid;
    }
  }
  # Single signature.
  else {
    $imposition_charge =
    eprint::service::get_price($log, $dbh, $variable,
      'ImpositionMakeReady',
      $imageHeight * $imageWidth, $press);

    $imposition_charge += ($imposition - 1) *
    eprint::service::get_price($log, $dbh, $variable, 'Imposition',
      $imageHeight * $imageWidth, $press);

    if ((@$side_one_colours > 1) || (@$side_two_colours > 1)) {
      # Only apply trapping charge if we have more than 1 colour on a side.
      $trapping_make_ready =
      eprint::service::get_price($log, $dbh, $variable, 'TrappingMakeReady',
        $imageHeight * $imageWidth, $press);

      $trapping_charge = ($imposition - 1) *
      eprint::service::get_price($log, $dbh, $variable, 'Trapping',
        $imageHeight * $imageWidth, $press);

      $imposition_charge += $trapping_charge     if $trapping_charge > 0;
      $imposition_charge += $trapping_make_ready if $trapping_make_ready > 0;
    }
  }

  # For each set of plate changes repeat the imposition charges.
  my $forms = scalar(@{ $imp->{layout} });
  if ( $forms > 1 ) {
    $imposition_charge *= $forms;
  }

  # Add in the imposition minimum charge on top of trapping and everything.
  my $imposition_minimum =
  eprint::service::get_price($log, $dbh, $variable,
    'ImpositionMinimumCharge', undef, $press);

  if ($imposition_minimum > $imposition_charge) {
    $imposition_charge = $imposition_minimum
  }

  $imposition_charge += eprint::service::get_price($log,
    $dbh, $variable, 'MetalEffectsMakeReady',)
  if $metal_effects;

  #print STDERR "HAVE IMP CHARGE TOTAL: $imposition_charge \n";

  return $imposition_charge;
}

# Returns true if all printing services for the given project are calculated.
sub is_printing_complete {
  my ($log, $dbh, $pid) = @_;

  return $dbh->selectrow_array(q{
    SELECT count(*) = 0
    FROM tbl_project_contents
    WHERE strservicetype IN ('Book', 'Item', 'Printing')
    AND strstatus NOT IN ('In Production', 'Complete', 'calculated')
    AND lngprojectindex = ?
    }, undef, $pid);
}

sub calc_service_overs {
  my ($log,$dbh,$pid) = @_;

  # This will effectively allow us to make extra overs for anything we do -
  # shipping, packing, bindery, manual labour ... just by filling in columns

  # For now, we will assume that all of our setup overs are in whole press
  # sheets For now, the rest of our code won't use setup overs unless they
  # exceed press setup overs (since we'll use press overs to set up our
  # bindery)
  my ($total_setup_overs,$total_running_overs) = (0,0);

  my $sth = $dbh->prepare(q{
    SELECT strid, lngsetupovers, dblrunovers
    FROM tbl_service_types
    WHERE (lngsetupovers IS NOT NULL AND lngsetupovers > 0)
    OR (dblrunovers   IS NOT NULL AND dblrunovers   > 0)
    });
  $sth->execute;

  while (my @current_row = $sth->fetchrow_array) {
    # for every service that we have an over, check to see if we are
    # running the service in this job
    if (check_for_service($log, $dbh, $pid, $current_row[0])) {
      # if we are running the service, factor the overs for it into our
      # running totals
      $total_setup_overs   += $current_row[1];
      $total_running_overs += $current_row[2];
    }
  }

  return ($total_setup_overs, $total_running_overs);
}


# Determine the maximum number of spreads that be in the given signature.
sub spreads_remaining {
  my ($log, $dbh, $pid, $sid) = @_;

  # Spread controls have no relavance to non-multipage projects.
  if (!is_multipage($log, $dbh, $pid)) {
    $openprint::log->debug("Not multipage");
    return 0;
  }

  my $project = new openprint::Project($pid);
  return 1 if $project->type() eq 'ScreenItem';

  my $specs = openprint::service::get_specs_ref($pid, $sid);
  my $type      = $$specs{txtSignatureType};
  if (!$type) {
    $openprint::log->error("No signature type");
  }
  my $book      = get_print_container($log, $dbh, $pid);

  #print STDERR "HAVE SIGNATURE TYPE : $type SID: $sid \n";

  my $total     = get_specifications($log, $dbh, $pid, $book, $type);
  #print STDERR "HAVE TOTAL : $total \n";
  my $completed = count_completed_spreads($log, $dbh, $type, $pid, $sid);
  #print STDERR "HAVE COMPLETED : $completed \n";

  my $needed    = $total - $completed;

  die "Invalid number of finished spreads ($type) for project ($pid)"
  if $completed > $total;

  return $needed;
}

# Returns the total number of spreads of the given type that have been
# accounted for (calculated) so far. Optionally excludes a given signature.
sub count_completed_spreads {
  my ($log, $dbh, $spread_type, $pid, $exclude) = @_;

  print STDERR "No Spread Type\n" unless $spread_type;

  # Get all the other calculated signatures.
  my @signatures_of_type = signatures_of_type($log, $dbh, $pid, $spread_type) if $spread_type;
  print STDERR "Signature of type $spread_type @signatures_of_type\n";
  my @signatures = grep { get_status($log, $dbh, $_) eq 'calculated' } @signatures_of_type if $spread_type;

  # Allow the user to exclude a signature from the count (generally the one being recalculated).
  @signatures = grep { $_ != $exclude } @signatures if $exclude;

  my $count = 0;
  foreach my $sid (@signatures) {
    print STDERR "Getting specs for $pid $sid\n";
    my ($size, $groups) = get_specifications(
      $log, $dbh, $pid, $sid, qw(spreads_in_group txtSignatureQuantity)
    );

    $groups ||= 1;

    $count += $groups * $size;
  }

  return $count;
}

# Return the IDs of the signatures in the project that are of a type. If no
# type is defined return a hash of lists for each type in the project.
# Otherwise return the signature IDs of that type (if any).
sub signatures_of_type {
  my ($log, $dbh, $pid, $spread_type) = @_;

  my %signature;
  for my $sig (check_for_service($log, $dbh, $pid, 'Printing')) {
    my $type = get_specifications($log, $dbh, $pid, $sig, 'txtSignatureType');

    $signature{$type} = [] unless $type and exists $signature{$type};

    push @{ $signature{$type} }, $sig;
  }

  # If we've requested signatures of a specific type, return only those.
  if (defined $spread_type) {
    return undef unless exists $signature{$spread_type};

    return wantarray ? @{$signature{$spread_type}} : $signature{$spread_type}[0];
  }

  return \%signature;
}


1;
__END__
