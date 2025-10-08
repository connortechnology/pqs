# This is really not a service so much as a place to store specifications we
# don't otherwise have anywhere to put.
package eprint::Service::Book;
use strict;
use warnings;


use POSIX qw(ceil);

use eprint::project                      qw(:common);
use eprint::print_project                qw(insert_service delete_service);
use eprint::service                      qw(:common :status);
use eprint::Service::Printing::Constants qw(:spread_types);
use eprint::Service::Printing::Display   qw(template_sizes multiversion);
use eprint::Service::Printing::Price     qw(signatures_of_type);
use PQS::model::materials;
use PQS::model::service;
use Data::Dumper;
require openprint;

sub store {
  my ($log, $dbh, $pid, $sid, $service_type, $specs) = @_;

  # Very, very simple multi-version input processing.
  if ($specs->{is_mv}) {
    my @name  = @{ $specs->{mv_name} };
    my @qty   = @{ $specs->{mv_qty}  };
    my $total = (get_quantities($log, $dbh, $pid))[0];

    #print STDERR "STORE FOR BOOK  Servcie: PID: $pid SID: $sid \n";

    my (@versions, @quantities);

    # For now mirror the JS precisely. Note: Multiple labels of the
    # same name are allowed and treated as different versions.
    for my $i (0 .. $#qty) {
      my $name    = $name[$i];
      my $qty     = int($qty[$i]);

      next unless $qty > 0;

      my $percent = ($qty / $total) * 100;

      if ($name and $percent and ceil($percent) > 0) {
        push @versions,   $name => $percent;
        push @quantities, $name => $qty;
      }
    }
    $specs->{versions}           = join(',', @versions);
    $specs->{version_quantities} = join(',', @quantities); # For UI

    $specs->{s0_black_mv} = 'on' if ref $specs->{s0_black_mv} eq 'ARRAY';
    $specs->{s1_black_mv} = 'on' if ref $specs->{s1_black_mv} eq 'ARRAY';
  }

  return $specs;
}

sub restore {
  my ($dbh, $pid, $sid, $service_type, $specs) = @_;

  # The versions are stored against 1NF as a flattened pair list.
  if ($specs->{version_quantities}) {
    my %versions = split ',', $specs->{version_quantities};

    $specs->{mv_name} = [ keys %versions ];
    $specs->{mv_qty}  = [ values %versions ];
    $specs->{versions} = \%versions;
  }

  #print STDERR "HAVE VERSIONS: ", Dumper($specs->{versions});
  return $specs;
}

sub necessary {
  my ($log, $dbh, $pid, $service_type) = @_;

  return is_multipage($log, $dbh, $pid) && get_type($log, $dbh, $pid) ne 'ScreenItem';
}

sub display {
  my ($log, $dbh, $service_type, $pid, $sid, $specs) = @_;

  my %mv;
  # Get info to recreate version table when editting the service.
  @mv{qw(versions remaining)} = multiversion($log, $dbh, $pid, $specs) if $specs->{mv_name} && $specs->{mv_qty};
  $mv{next_version} = $mv{versions} ? scalar @{$mv{versions}} + 1 : 1;
  map { $mv{$_} = $specs->{$_} if $_ =~ /mv_num_col/; } keys %{$specs};

  #print STDERR "HAVE VERSIONS DATA", Dumper(\%mv);

  # Get the bindery options (radio buttons w/ images).
  my $bindery = $dbh->selectall_arrayref(qq{
    SELECT strid        AS id, 
    strname      AS name, 
    lower(strid) AS img
    FROM tbl_service_types
    WHERE strtype = 'bind'
    AND ysncreatevisible = 'Y'
    ORDER BY lngsort, name
    }, { Slice => {} });

  my $noprintcovers = $dbh->selectall_arrayref("SELECT lngindex, strname FROM tbl_materials WHERE lngtype = 19", { Slice => {} });

  # Corner stitching is only available on digital presses.
  $bindery = [ grep { $_->{id} ne 'CornerStitching' } @$bindery ] unless get_press_type($log, $dbh, $pid) eq 'digital';

  my $project_type = get_type($log, $dbh, $pid);

  # Get the available templates for the project type.
  my $templates = template_sizes($log, $dbh, $project_type, $bindery);

  my @qty = get_quantities($log, $dbh, $pid);

  my $page = { templates => $templates, bindery => $bindery, no_print_covers => $noprintcovers,  txtQuantity1 => $qty[0] };
  map { $page->{$_} = $mv{$_} } keys %mv;

  return $page;
}

sub mp_versions {
  my $specs = shift;
  my $ver;
  map {
    if ( $_ =~ /mv_name-(\d+)/ ) {
      $ver->{$1} = { 
        name => {name => $_, value => $specs->{$_} }, 
        qty  => {name => "mv_qty-$1", value => $specs->{"mv_qty-$1"} } 
      }; 
    }
  } keys %${specs};

  my @versions;

  map { push @versions, $ver->{$_} } sort keys %${ver};

  return @versions;
}

sub munge {
  my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

  if (!defined $specs->{template}) {
    $openprint::log->debug("Undefined template in book in $pid $sid");
    return 1;
  }

  # Make sure the cover spec is set, and correctly when perfect bound. 
  $specs->{rdbCover} = $specs->{template} eq 'PerfectBinding' ? 'DifferentCover' : $specs->{rdbCover} ? $specs->{rdbCover} : 'SelfCover';

  return 1;  
}


sub calc {
  my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

  my $pages            = $specs->{txtTotalPageQuantity} || 0;
  my $pages_per_spread = $specs->{template} =~ /^(loop|saddle)stitching/i ? 4 : 2;

  # Do we want a cover with separate specifications? This is not an option
  # for perfect bound books, all have a separate cover.
  my $cover = $specs->{rdbCover} eq 'DifferentCover' || 0;

  $pages -= 4 if $cover; # Remove the four page cover spread.

  # TODO Spiral projects actually have two two page cover spreads.

  # Calculate the number of spreads based on the bindery type chosen.
  my $spreads = $specs->{rdbGateFold} eq 'Yes' ? $specs->{txtTotalSpreadQuantity} : $pages / $pages_per_spread;

  return 'uncalculated' unless $spreads && ($spreads > 0);

  my @qty = get_quantities($log, $dbh, $pid);
  my $counter = 1;
  foreach my $q (@qty) {
    $q //= 0;
    my $range = ($specs->{final_height} * $specs->{final_width} / 12) * $q;
    my $cost = 0;
    if ($specs->{noprint_front}) {
      my $mat = PQS::model::materials($specs->{noprint_front});
      PQS::model::service::set_material_estimate($range, undef, $sid, $mat->{lngindex}, $q);
      $cost += eprint::material::get_price($log, $dbh, $variable, $specs->{noprint_front}, $range, undef) * $range;
    }
    if ($specs->{noprint_back}) {
      my $mat = PQS::model::materials($specs->{noprint_back});
      PQS::model::service::set_material_estimate($range, undef, $sid, $mat->{lngindex}, $q);
      $cost += eprint::material::get_price($log, $dbh, $variable, $specs->{noprint_back}, $range, undef) * $range;
    }
    @$specs{"txtPrice$counter", "txtUnitPrice$counter"} = format_pricing($cost, $q);
    $counter++;
  }

  my $tabs = $specs->{txtTabsQuantity};

  my $gatefold = $specs->{rdbGateFold} eq 'Yes' 
  ? $specs->{txtGateFoldedSpreadQuantity} || $tabs || 0 : 0;
  my $interior = $spreads - $gatefold;

  # return 'uncalculated' unless $interior && $interior > 0;

  # The (possibly) computed number of spreads.
  $specs->{txtTotalSpreadQuantity} = $spreads + $cover;

  # The number of spreads of each type.
  @$specs{COVER, INTERIOR, GATEFOLD} = ($cover, $interior, $gatefold);

  return 'calculated';
}

# Create the signatures needed for the book type and size.
sub action { 
  my ($log, $dbh, $pid, $sid, $service_type, $specs) = @_;

  #print STDERR "START BOOK ACTION: PID: $pid SID: $sid \n";
  #print STDERR 'specs'.Data::Dumper::Dumper($specs);

  my $project_type = get_type($log, $dbh, $pid);
  my $bind_type    = $specs->{template};

  $openprint::log->error( "No bindery type found for multi-page project!" ) unless ($bind_type || $project_type eq 'ScreenItem');

  # Preserve the information from the first spread if we're editing. TODO
  # Check that we're not saving for the first time.
  my $prev = previous_specs($log, $dbh, $pid);
  #print STDERR 'prev'.Data::Dumper::Dumper($prev);

  # TODO We should be able to only remove all printing services and this will "just work".
  for my $service (qw(Printing Folding)) {
    delete_service($log, $dbh, $pid, $_) for check_for_service($log, $dbh, $pid, $service);
  }

  # Get the stanadard project type defaults for insertion into
  # all of the signature services ( Interior/Cover/GF ).
  # This will get us our bleed & other defaults.
  my $ptd = $dbh->selectall_hashref(q{ SELECT strfieldname as name, strdefaultvalue as value FROM tbl_projecttype_defaults WHERE lngprojecttypeindex IS Null }, 'name');

  my %defaults;
  map { $defaults{$_} = $ptd->{$_}{value} } keys %$ptd;

  # Add a cover spread if needed.
  if ($specs->{ COVER() }) {
    #print STDERR "Have cover?".COVER()."\n";

    my $double = grep { $bind_type eq $_ } qw(SaddleStitching PerfectBinding);
    #print STDERR "IS SINGLE ********* $double - $bind_type ****\n";

    my $cover = insert_service($log, $dbh, $pid, 'Printing', {
        # Perfect binding requires the cover.
        need_level     => $bind_type eq 'PerfectBinding' ? NEEDED 
        : NOT_NEEDED,
        user_requested => 1,
      }, {
        txtSignatureType         => COVER,
        txtServiceDescription    => COVER,
        txtSectionSpreadQuantity => $double ? 1 : 2,
        txtSignatureSize         => $double ? 4 : 2,

        # Currently we default to no fold as covers for perfect binding
        # are folded on the perfect binder. However other incorrect saddle
        # stitching style templates are still offered (See Bug 1746).
        template => ($bind_type =~ /stitching/i ? '4PageSignature' : 'NoFold'),

        txtSpreadWidth  => $double ? $specs->{final_width} * 2 : $specs->{final_width},
        txtSpreadHeight => $specs->{final_height},
      });
    insert_service_spec( $log, $dbh, $pid, $cover, SignatureIndex => $cover);
    insert_service_specs($log, $dbh, $pid, $cover, %defaults);

    $_ = q{SELECT MAX(strValue::integer) FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND strName='Form'};
    my ( $form ) = sql::execute( $log, $dbh, $_, $pid );
    $form  = $form ? $form+1 : 1;
    openprint::service::insert_service_spec( $log, $dbh, $pid, $cover, 'Form', $form );

    # TODO A perfect bound cover's size is dependent on the thickness of
    # the book (spine size). Should we even insert it now?

    # TODO Spiral can have separate front and back covers, though we may
    # want to print them together. In fact the back may just be cut and
    # not printed on at all.

    # Insert previous specs if we're redoing this book.
    if (exists $prev->{COVER()}) {
      while (my ($name, $value) = each %{ $prev->{COVER()} }) {
        #print STDERR "$name => $value\n";
        insert_service_spec(
          $log, $dbh, $pid, $cover, $name => $value, undef, 1
        );
      }
    }
  } #end if different cover

  # Add a gate folded spread if any have been requested.
  if ($specs->{ GATEFOLD() }) {
    my $gatefold = insert_service($log, $dbh, $pid, 'Printing', {
        user_requested => 1
      }, {
        txtSignatureType      => GATEFOLD,
        txtServiceDescription => 'Binder Tabs',
        txtSpreadWidth            => $specs->{flat_width},
        txtSpreadHeight           => $specs->{flat_height},
      });
    insert_service_spec( $log, $dbh, $pid, $gatefold, SignatureIndex => $gatefold);
    insert_service_specs($log, $dbh, $pid, $gatefold, %defaults);

    $_ = q{SELECT MAX(strValue::integer) FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND strName='Form'};
    my ( $form ) = sql::execute( $log, $dbh, $_, $pid );
    $form  = $form ? $form+1 : 1;
    openprint::service::insert_service_spec( $log, $dbh, $pid, $gatefold, 'Form', $form );

    #print STDERR "DO SPREADS *****************", Dumper($prev);

    # Insert previous specs if we're redoing this book.
    if (exists $prev->{GATEFOLD()}) {
      while (my ($name, $value) = each %{ $prev->{GATEFOLD()} }) {
        insert_service_spec(
          $log, $dbh, $pid, $gatefold, $name => $value, undef, 1
        );
      }
    }
  }

  # We now allow GF only jobs.
  # Check to see if there are INTERIORS before adding.
  if (! $specs->{ INTERIOR() }) {
    #print STDERR "Don't have interior because we removed them!".INTERIOR()."\n";
    my $project = new openprint::Project($pid);
    $project->services(undef);
    return 1;
  }

  # Create the first (of possibly many) signature for the interior.
  my $interior = insert_service($log, $dbh, $pid, 'Printing', {
      user_requested => 1,
    }, {
      txtSignatureType          => INTERIOR,
      txtServiceDescription     => INTERIOR . ' 1',
      txtSpreadWidth            => $specs->{flat_width},
      txtSpreadHeight           => $specs->{flat_height},
      txtSignatureSize          => (($bind_type eq 'LoopStitching' or $bind_type eq 'SaddleStitching') ? 4 : 2),
      VERSIONS		  =>  [mp_versions($specs)],
    });
  #print STDERR "Interior index $interior\n";
  insert_service_spec( $log, $dbh, $pid, $interior, SignatureIndex => $interior);
  insert_service_specs($log, $dbh, $pid, $interior, %defaults);
    $_ = q{SELECT MAX(strValue::integer) FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND strName='Form'};
    my ( $form ) = sql::execute( $log, $dbh, $_, $pid );
    $form  = $form ? $form+1 : 1;
    openprint::service::insert_service_spec( $log, $dbh, $pid, $interior, 'Form', $form );

  map { 
    if ( $_ =~ /mv/ || $_ =~ /version/ || /version_quantities/ ) {
      insert_service_spec( $log, $dbh, $pid, $interior, $_ => $specs->{$_}, undef, 1);
    }
  } keys %{$specs};

  # Insert previous specs if we're redoing this book.
  if (exists $prev->{INTERIOR()}) {
    while (my ($name, $value) = each %{ $prev->{INTERIOR()} }) {
      insert_service_spec(
        $log, $dbh, $pid, $interior, $name => $value, undef, 1
      );
    }
  }

  #print STDERR "HAVE SPECS", Dumper($specs);

  # NOTE: The bindery types will take care of themselves.

    my $project = new openprint::Project($pid);
    $project->services(undef);
  return 1;
}

# For each signature type in the old project get the specs of the first
# signature of that type.
sub previous_specs {
  my ($log, $dbh, $pid) = @_;

  my $sigs = signatures_of_type($log, $dbh, $pid);

  for my $type (keys %$sigs) {
    my %specs = @{ $dbh->selectcol_arrayref(q{
    SELECT strname as name, strvalue as value
    FROM tbl_service_specifications 
    WHERE (ui_spec = true OR strname = 'version_quantities' OR strname LIKE 'override%') 
    AND strname NOT IN ( 'substrate', 'spreads_in_group', 'hdnRunStyleCheck' )
    AND lngserviceindex = ?
    }, { Columns => [1,2] }, $sigs->{$type}[0]) };

    # If there are form size overrides make sure we step through the
    # project (but don't re-apply the overrides).
    if ($specs{spreads} || $specs{forms}) {
      $specs{needs_view} = 1;

      #delete @specs{qw(spreads forms)};
    }

    #$specs{override_press} = 1 if $specs{press};

    $sigs->{$type} = \%specs;
  }

  return $sigs;
}


1;
