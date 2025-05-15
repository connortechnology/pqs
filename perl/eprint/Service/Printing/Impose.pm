package eprint::Service::Printing::Impose;
use strict;
use warnings;

use Iterator;
use Iterator::Util;
use Iterator::Misc;
use Readonly;
use Memoize;
use List::Util   qw(min max sum);
use Scalar::Util qw(dualvar);

use PQS::Imposition;
use PQS::Equipment;
use eprint::Service::Printing::Substrate;

use Data::Dumper;

use base qw(Exporter);
our @EXPORT    = qw(impositions);
our @EXPORT_OK = qw(wx_colours wx_press_units);

# TODO Get these press types in a compile time DB fetch.
use constant {
    OFFSET  => dualvar(14, 'press'),
    WEB     => dualvar(43, 'web'),
    DIGITAL => dualvar(41, 'digital'),
    SCREEN  => dualvar( 1, 'screen'),
    INKJET  => dualvar(38, 'inkjetprinter'),
};
use constant COATINGS => qw(aqueous uv softtouch);


# Given project specs. generate the set of possible impositions.
sub impositions {
  my ($dbh, $project, $start_time) = @_;

  my $end =  Time::HiRes::time() - $start_time;
  print STDERR "START Printing \ IMPOSE: $end \n ";

  my %reasons;
  my $presses    = get_presses($dbh, $project, \%reasons); # Potential printers.
  $$project{error} .= join("\n", values %reasons ) if !$presses->isnt_exhausted;

  my $substrates = get_substrates($dbh, $project); # Fits image at least.
  #print STDERR "HAVE NO PAPER \n" unless @{$substrates};
  my $subs = @{$substrates};

  #print STDERR "HAVE PAPER: $subs PRESSES: $presses \n", Dumper($substrates);

  my @styles     = get_runstyles($project);
  $openprint::log->debug("RS: @styles");

  my $empty = Iterator->new(sub { Iterator::is_done });

  # Inkjet printers don't impose the same way as others (due to tiling being
  # allowed) so currently need a number of special exceptions.
  my $is_inkjet = $project->{press_type} eq 'inkjetprinter';

  $end =  Time::HiRes::time() - $start_time;
  print STDERR "START Printing \ IMPOSE 2: $end  \n";

  # Generate all possible impositions for the project (except inkjet).
  my $impositions = !$is_inkjet ? PQS::Imposition->new(project => $project, start => $start_time) : undef;
  #$openprint::log->debug('impositions: '.Data::Dumper::Dumper($impositions));

  $end =  Time::HiRes::time() - $start_time;
  print STDERR "START Printing \ IMPOSE 3: $end  \n";

  # A press run is the set of valid run styles X sheet sizes for that press.
  # Returns [press, sheet, style, node tree, is_rotated]
  my $run = sub {
    my $press = shift;

    print STDERR "HAVE PRESS: ", Dumper($press);

    # Get the run styles we can do and sheet sizes that fit on the press.
    my @r = grep { can_print_style($press, $_, $project) } @styles;
    my @s = map  { fit_to_press   ($_,     $press      ) } @$substrates;
    $openprint::log->debug("HAVE R: ". Dumper(@r). " S: ". Dumper(@s));

    return $empty unless @r && @s;

    # Each (run style, sheet size) combination is a setup to test.
    my $setup = cross_product(\@r, \@s);

    # Inkjet printers have their own imposition generation currently.
    if ($is_inkjet) {
      return imap { [$press, reverse(@$_), undef, undef ] } $setup;
    }

    $openprint::log->debug("HAVE SETUP: ". Dumper($setup));

    # Find the best (if any) imposition for each setup. TODO We try WT/WF
    # that obviously won't work as the image check should be half the
    # sheet size for them.
    my $valid = igrep { $_->[-2] } imap { [$press, $_->[1], $impositions->best_fit($press, @$_)] } $setup;
    $openprint::log->debug("HAVE Valid: ". Dumper($valid));
    return $valid;
  };

  #print STDERR "TIME TO VALIDATE DATA \n";

  # Flatten the press runs into a stream of impositions.
  return igrep { $_ } iflatten ( igrep { $_->isnt_exhausted } imap  { $run->($_)         } $presses );
}

#
# PRESSES
#

# Return an iterator over the set of presses that fit enough specs to attempt
# to run the project.
sub get_presses {
  my ($dbh, $project, $reasons) = @_;

  # If we've been overridden our press is as specified. Otherwise get all
  # for the press type chosen for the project.
  my @ids = $project->{override}{press} || press_ids($dbh, $project->{press_type}, $project->{rfq_only});

  print STDERR "HAVE PRESS LIST: ", Dumper(\@ids);

  return igrep { can_print_project ($dbh, $_, $project, $reasons) } imap { get_equipment($dbh, $_) } ilist (@ids);
}

# Get a list of presses (number ids) of a given press type.
sub press_ids {
  my ($dbh, $press_type, $rfq_only) = @_;

  my $sql  = 'SELECT lngindex FROM tbl_equipment WHERE TRUE';
  $sql .= ' AND strtype=?' if $press_type;
  $sql .= " AND strsupplier <> 'RFQ Required'" unless $rfq_only;
  $openprint::log->error($sql.$press_type);

  # Get a list of all presses of the user chosen type.
  my $presses = $dbh->prepare_cached($sql);

  return @{ $dbh->selectcol_arrayref($presses, {}, $press_type) };
}

# Returns a bool if the press has the correct attributes to print the project.
sub can_print_project {
  my ($dbh, $press, $project, $reasons) = @_;

  #not allowed to use a non variable press if there is variable data
  if (eprint::project::check_for_service(undef, $dbh, $project->{id}, "VariableData") && !grep(/^VariableData$/, @{$press->{services}})) {
    $$reasons{$$press{id}} = $$press{name} . ' does not support variable data';
    return 0;
  }
  print STDERR "Pass Variable Data Test \n";

  #print STDERR "\nCHECK PRESS: $press->{id} - $press->{name} \n";
  # Can we even print the project type?
  if ($project->{type} and !can_print_project_type($press, $project->{type})) {
    $$reasons{$$press{id}} = $$press{name} = ' does not support project type '.$project->{type};
    return 0;
  }

  # Icon: removed because it has nothing to do with press
  # Clause added due to empty string (*sigh*) being possible as paper
  # calliper is stored as a string. TODO Use correct type, check earlier.
  #if (!$project->{paper}{calliper} and $project->{type} ne 'ScreenItem') {
  #$results{$$press{id}} = 'Does not support project type '.$project->{type};
  #}

  print STDERR "Pass Calliper  Test \n";

  # Manual screen 'presses' are exempt from calliper checks. You can place a
  # screen on the side of a bus if you felt like it.
  if (!($press->{type} == SCREEN && $press->{operation} =~ /^Manual/i) && $press->{maximum_calliper} < $project->{paper}{calliper}) {
    $$reasons{$$press{id}} = $$press{name} . ' failed maximum calliper '.$press->{maximum_calliper}.' < '.$project->{paper}{calliper};
    return 0;
  }

  #print STDERR "Pass Max Calliper  Test \n";

  # The project image can't be bigger than the maximum imageable area.
  # Inkjet printers ignore this as they're allowed to tile their images.
  if ($press->{type} != INKJET
    && ($press->{maximum_image_area_length} and
      ( $project->{height} > $press->{maximum_image_area_length} 
        || $project->{width}  > $press->{maximum_image_area_length} )
      && ($press->{maximum_image_area_width} and (
          $project->{width} > $press->{maximum_image_area_width}
          || $project->{height} > $press->{maximum_image_area_width}))
    )) {
    $$reasons{$$press{id}} = $$press{name} . ' failed image area test';
    return 0;
  }

#print STDERR "Pass Project Size Test \n";

  # Check minimum project size for Screen presses.
  if ($press->{type} == SCREEN && defined $press->{minimum_project_size} && $project->{width}  * $project->{height} < $press->{minimum_project_size}) {
    $$reasons{$$press{id}} = $$press{name} .= ' failed minimum project size test';
    return 0;
  }

  print STDERR "Pass Min Project Size Test \n";

  # Check if the press has pricing for the required coatings.
  # return if grep {    ($project->{$_}{side_one} || $project->{$_}{side_two}) 
  if (grep { $project->{$_} && ! can_coat($dbh, $press, $_) } COATINGS) {
    $$reasons{$$press{id}} = $$press{name} .= ' failed coatings test';
    return 0;
  }

  #print STDERR "Pass COATING Test \n";

  # While a varnish is just another ink so shouldn't be a special check, our
  # customer's want a work around to setting up proper wash and varnish
  # costs. So if we have a varnish check for pricing (in any price list).
  if (grep { /Varnish/i } map { @$_ } @{ $project->{colours} }) {
    if (!can_coat($dbh, $press, 'varnish')) {
      $$reasons{$$press{id}} = $$press{name} . ' failed varnish test';
      return 0;
    }
  }

  #print STDERR "Pass Varnish Test \n";
  # We do not support offline Corner Stitching.
  # So we will only allow presses with inline corner stitching.
  if (   $press->{type} == DIGITAL
    && defined $project->{bind_type} 
    && $project->{bind_type} eq 'CornerStitching'
    && ! grep { $_ eq 'CornerStitching' } @{$press->{services}} ) {
    $$reasons{$$press{id}} = $$press{name} .= ' failed corner stitching test';
    return 0;
  }

  #print STDERR "Pass Digital Test \n";

  # If our project has specified Press Quality Requirements only allow the presses
  # that exactly match the quality rating we are looking for.

  if ( (!$project->{product_only}) && $press->{product_only} ) {
    $$reasons{$$press{id}} = $$press{name} .= ' failed product only test';
    return 0;
  }

  print STDERR "\nC PRESS IS VALID: $press->{id} - $press->{name} \n";
  return 1;
}

# Some presses can't print certain project types. TODO Dispatch table for this
# section if it gets bigger.
sub can_print_project_type {
  my ($press, $project_type) = @_;

  # If we're envelopes, can the press print us? Only us?
  if  ($project_type eq 'Envelopes') {
    return unless exists $press->{envelope_ready} && $press->{envelope_ready};
  } else {
    return if exists $press->{envelope_only} && $press->{envelope_only};
  }

  # If we're 'plastics', can the press print us? Only us?
  #   NOTE: This should a substrate type not a project type.
  if  ($project_type eq 'PlasticPrinting') {
    return unless exists $press->{plastics_capable} && $press->{plastics_capable};
  } else {
    return if exists $press->{plastic_only} && $press->{plastic_only};
  }

  # Items can only be printed on manual or semi-auto screen presses.
  return if $project_type eq 'ScreenItem'
  && (   $press->{type}      != SCREEN
    || $press->{operation} =~ /^Auto/i );
  #print STDERR "PRESS $press->{name} PASSED CHECK \n";

  # If we've survived the gauntlet we can at least try this project type.
  return 1;
}


{
  # SW - We need at least enough press units for the side with the most inks.
  # PF - We need a press unit for each colour.
  # Wx - We need a press unit per unique colour (front and back merged).
  Readonly my %ENOUGH_UNITS_FOR => (
    SW => sub { my($n, @c) = @_; $n >= max        (map {scalar @$_} @c) },
    PF => sub { my($n, @c) = @_; $n >= sum        (map {scalar @$_} @c) },
    Wx => sub { my($n, @c) = @_; $n >= wx_colours (map {       @$_} @c) },
  );

  sub can_print_style {
    my ($press, $style, $project) = @_;

    #print STDERR "CHECK CAN PRINT STYLE: $press, $style, $project \n";
    # TODO Multi-pass overrides colour checks?
    # TODO Double hit colours use two press units
    #print STDERR "STEP CAN PRINT STYLE: $press, $style\n ";

    my @s1 = $project->{drytrap}[0] 
    ? grep !/Varnish/,  @{$project->{colours}[0]}
    : @{$project->{colours}[0]}; 

    my @s2 = $project->{drytrap}[1] 
    ? grep !/Varnish/,  @{$project->{colours}[1]}
    : @{$project->{colours}[1]}; 

    #        map {
    #            push @s1, $project->{$_}{side_one} if (    $project->{$_}{side_one}
    #                                                    && !$press->{aqueous_coating} );
    #            push @s2, $project->{$_}{side_two} if (    $project->{$_}{side_two}
    #                                                    && !$press->{aqueous_coating} );
    #        } COATINGS;


    #print STDERR "STEP CAN PRINT STYLE: $press, $style\n ";
    # Are there enough press units to run the project this way?
    return unless $ENOUGH_UNITS_FOR{ $style }->(
      $press->{number_of_colours}, (\@s1, \@s2) );

    #print STDERR "STEP CAN PRINT STYLE: $press, $style\n ";
    # Not all presses of a type that can perfect, do.
    if ($style eq 'PF' &&  $press->{type} != WEB) {

      return unless $press->{perfecting_press};

      # Can the paper fit through the change-over unit?
      return if $project->{paper}{calliper}
      > $press->{maximum_calliper_perfecting};
    }
    #print STDERR "STEP CAN PRINT STYLE: $press, $style\n ";

    #print STDERR "PASS CAN PRINT STYLE: $press->{name}, $style\n ";
    return 1;
  }
}


# Can the press AQ?
sub can_coat {
  my ($dbh, $press, $coating) = @_;

  # If we have aq pricing in any price list then we can_aq
  #return scalar $dbh->selectrow_array(q{
  my @can_coat = $dbh->selectrow_array(qq{
    SELECT count(p.*) > 1 AS can_$coating
    FROM tbl_services s, tbl_service_prices p
    WHERE s.lngindex = p.lngserviceindex
    AND lower(s.strid)    ~ '^$coating'
    AND p.lngequipmentindex = ?
    }, undef, $press->{id});

  return $can_coat[0];
}


#
# RUN STYLES
#
{
  Readonly my %RUN_STLYES_FOR => (
    web           => [qw(        PF)],
    screen        => [qw(SW  Wx    )], # Automatics aren't THAT automatic.
    press         => [qw(SW  Wx  PF)],
    digital       => [qw(SW  Wx  PF)], # Digitals can DUPLEX not perfect.
    inkjetprinter => [qw(SW        )],
  );

  # Get the run styles that are valid for the project TODO Defer the press type
  # mapping until press selection as we'll want to price across press types.
  sub get_runstyles {
    my ($project) = @_;

    my %rs; @rs{ @{ $RUN_STLYES_FOR{$project->{press_type}} } } = ();

    # Web only has PF, for everything else remove invalid styles.
    if ($project->{press_type} ne WEB) {
      # If the paper isn't identical on each side, we can't just flip it and
      # get something identical when printing. TODO Looking a string in
      # the finish is ridiculous.
      delete $rs{Wx} if $project->{paper}{finish} =~ /C(?:oated)?\s*1\s*S(?:ide)?/i;

      # Carbonless forms can only ever have their primary information
      # printing on the first side. TODO Looking a string in the finish
      # is ridiculous.
      delete $rs{Wx} if $project->{paper}{finish} =~ /Carbonless/i;
      delete $rs{Wx} if $project->{paper}{c1sc2s} and $project->{paper}{c1sc2s} eq 'C1S';

      # If we're only printing one side, sheet work is the only option.
      delete @rs{qw(Wx PF)} unless @{ $project->{colours}[0] } && @{ $project->{colours}[1] };
      delete @rs{qw(Wx PF)} if $project->{paper}{doublesided} and ($project->{paper}{doublesided} eq 'N');
    }

    # If the user has overridden the run style, allow it if it's valid.
    if ( my $override = $project->{override}{runstyle} ) {
      # At this stage Work and Turn/Flop are the same thing. We'll
      # revisit the override again at the imposition level.
      if ($override eq 'WT' || $override eq 'WF') { $override = 'Wx' }

      return (exists $rs{$override}) ? $override : ();
    }

    return (sort keys %rs);
  }
}

#
# UTIL
#

# When running W&T/F you print both sides of the final product on a single
# side of the sheet (them spin and run it back through). So the colours you
# load into the press units are the unique set (with some playing with flood
# coatings) of colours for both sides of the project. TODO This operates on
# the original string colours list with a better data structure there's a lot
# of room for improvement for double hit, dry trapping, etc. etc.
# memoize('wx_colours');
sub wx_colours {
  my (@colours) = @_;
  my %uniq;

  # Get a unique list of the colours counting the number of times we see
  # them TODO This doesn't handle double hit colours on a single side.
  $uniq{$_}++ for map { s/Spot Colour//i; $_ } @colours;

  # When running W&T/F, a flood varnish on only one side turns into a spot
  # varnish because both sides are printed at once in those run styles.
  for my $finish (qw(Gloss Matte)) {
    my ($flood, $spot) = map {"$_ Varnish $finish"} qw(Overall Spot);

    # If a flood (overall) varnish exists...
    if ( exists $uniq{ $flood } ) {
      # And it's only on one side...
      if ( $uniq{ $flood } == 1 ) {
        # Delete it and insert a spot as that's means it's only on
        # half a W&T/F sheet which requires a plate.
        delete $uniq{ $flood };
        $uniq{ $spot } = 1;
      }
      # Or if there's already a spot we can just remove the flood
      # listing and use that same plate.
      elsif (exists $uniq{ $spot }) {
        delete $uniq{ $flood };
      }
    }
  }
  my @keys = sort keys %uniq;
  return @keys;
}

# Similar to wx_colours above but using a new data structure. Determines a
# colour -> press unit mapping based on a WT/F run style.
sub wx_press_units {
  my ($spread) = @_;
  no warnings qw(uninitialized);

  my %press_units;

  # Map each sides colours into press units. TODO Handle double hit colours.
  for my $c ( map { @{$_->{colours}} } @{ $spread->{side} } ) {
    my $key = join('-', $c->{type},$c->{name});

    if (my $unit = $press_units{$key}) {
      $unit->{coverage}   = min(100, $unit->{coverage} + $c->{coverage} / 2);
      $unit->{mv_varies} |= $c->{mv_varies};
      $unit->{ink} = $c->{ink};

      # TODO Should we check that flood varnishes haven't gotten the
      # mv_varied bit?
    } else {
      $press_units{$key} = { %$c };        # Copy
      $press_units{$key}->{coverage} /= 2; # Based on one pass.
    }
  }

  return [ values %press_units ];
}

1;
