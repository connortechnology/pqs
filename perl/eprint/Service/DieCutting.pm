package eprint::Service::DieCutting;
use strict;
use warnings;
no warnings qw(uninitialized);

use eprint::project       qw(:common :multipage);
use eprint::service       qw(:common);
use eprint::print         ();
use eprint::print_project ();
use eprint::equipment     ();
use sql                   qw(:common);

sub necessary {
    my ($log, $dbh, $pid, $service_type) = @_;

    # Die cutting is always required for presentation folders.
    return 1 if $service_type eq 'DieCutting'
             && get_type($log, $dbh, $pid) eq 'PresentationFolders';

    return 0;
}

# use constant COMPLEXITIES => qw(Simple Average Complex);
# 
# sub validate {
#     no warnings qw(uninitialized);
#     
#     # Type is one of a given list.
#     my $type = $specs->{rdbDieCutting} 
#              =  (grep { $specs->{rdbDieCutting} eq $_ } (COMPLEXITIES)) 
#              || (COMPLEXITIES)[2];
# 
#     $specs->{rule_length} = abs ceil $specs->{"txtSteelRuleLength$type"};
# 
#     die "Die rule length must be supplied" 
#         if $specs->{rdbSuppliedDie} ne 'Y' && !$specs->{rule_length};
# 
# }


sub calc {
  my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

  my $status = 'calculated';
  $$specs{alert} = '';

  my $project = new openprint::Project($pid);
  my $standard_pf            = $project->is_presentation_folder();

  my $check_failed_equipment = 0;
  my @signature_indices = get_signature_indices( $log, $dbh, $pid );
  my $printing_service_index = shift @signature_indices;

  $specs->{template} ||= get_template($log, $dbh, $pid);


  if ($standard_pf) {
    $specs->{rdbDieCutting} = 'Simple';
  }

  # Return Uncalculated so that we can collect information needed
  # for docket, even though it has no bearing on price.
  if ( $standard_pf && ! defined $specs->{rdbBusinessCardSlot} ) {
    return 'uncalculated';
  }

  $specs->{rdbDieCutting} ||= 'Complex'; # Unknown defaults to complex

  # TODO: This only changes the status when we shouldn't even being allowing
  # calculations unless these conditions are met.

  # The following must all be defined. And one of cuts or bends can be
  # invalid, but not both.
  $status = 'uncalculated' if ! $standard_pf
  && $specs->{rdbSuppliedDie} ne 'Y'
  && (grep { ! defined $specs->{$_} } qw(rdbSuppliedDie rdbDieCutting rdbGlued))
  && (grep { ! defined $specs->{$_} || $specs->{$_} <= 0 } qw(txtDieWidth txtDieHeight))
  && (   $specs->{txtDieCutBends}   <= 0 || $specs->{txtDieCutPunches} <= 0 );

  my $ServiceType = openprint::ServiceType->find_one(name=>$service_type);
  my @possible_equipment = openprint::Equipment->find(useinestimating=>1,
    ($standard_pf ? (Specifications => {'Standard Folder Capable'=>'Y'}) : (
    'servicetype_id @>'=>$ServiceType->id(),
      )),
  );

  my $printing_specs = openprint::service::get_specs_ref($project, $printing_service_index);

  $specs->{flat_width} = $$printing_specs{flat_width} unless $specs->{flat_width};
  $specs->{flat_height} = $$printing_specs{flat_height} unless $specs->{flat_height};


  my @qty = (undef, get_quantities($log, $dbh, $pid));

  #Sherwood only uses qty1
  #No long calculate size for impostions great than 1.
  #User must enter Imp size for processing multi-up.
  #Still compare equipment, validate equipment fits project.

  foreach my $i ( 1 ) {
    my %bestPrice;
    my %bestImposition;

    next unless $qty[$i] && $qty[$i] > 0;

    $specs->{"txtQuantity$i"} ||= $qty[$i];

    my $bestEquipment;
    my @equipment = $specs->{"chkOverrideEquipment$i"} eq 'Y' ? map { $_->id() == $specs->{"ddmEquipment$i"} ? $_ : () } @possible_equipment : @possible_equipment;
    if (!@equipment) {
      $$specs{alert} .= "We have no suitable equipment for die cutting for quantity $i.<br/>";
      next;
    }

    my %imposition;

    my $imp_width  = 0;
    my $imp_height = 0;

    if ( $specs->{chkOverrideImposition1} ) {
      $imposition{'Imposition'} =  $specs->{txtImposition1};
      $imposition{'Rows'} = 1;
      $imposition{'Cols'} = 1;
      $imp_width  = $$specs{"txtImageWidth1"};
      $imp_height = $$specs{"txtImageHeight1"};
    } else {
      # For Our Dutch Impositions We only allow 1-up die cutting.
      $imposition{'Imposition'} = 1;
      $imposition{'Rows'} = 1;
      $imposition{'Cols'} = 1;
      $imp_width  = $$specs{"flat_width"};
      $imp_height = $$specs{"flat_height"};

      $$specs{"txtImageWidth$i"}  = $$specs{"flat_width"};
      $$specs{"txtImageHeight$i"} = $$specs{"flat_height"};
    }

    foreach my $equipment (@equipment) {
      my $equipment_id = $equipment->id();

      if ($standard_pf) {
        next if $imposition{Imposition} > 1;
      }

      if ( !eprint::equipment::equipment_fits( 
          $log, $dbh, $equipment_id, $imp_width, $imp_height)
      ) {
        if ($specs->{"chkOverrideEquipment$i"} eq 'Y') {
          $$specs{alert} .= "EQUIPMENT: $$equipment{name} Does not fit $imp_width x $imp_height<br/>";
        }
        next;
      } else {
        $check_failed_equipment = 1;
        my %price = calc_price( $log, $dbh, $variable, $specs, $equipment, $i, $imposition{'Imposition'}, $standard_pf, $service_type );

        if ( !$bestPrice{'txtPrice'} or $price{'txtPrice'} < $bestPrice{'txtPrice'} ) {
          $bestEquipment  = $equipment_id;
          %bestPrice      = %price;
          %bestImposition = %imposition;
        }
      }
    } # end foreach equiment

    if ( $check_failed_equipment && !$bestPrice{'txtPrice'} ) {
      $$specs{'error'} =
      "The size of your document and die are unable to fit on any of our letterpresses.";
    }
    $$specs{alert} .= $bestPrice{alert};
    $$specs{"hdnBreakdown$i"} .= $bestPrice{breakdown};
    $$specs{"ddmEquipment$i"} = $bestEquipment if $specs->{"chkOverrideEquipment$i"} ne 'Y';
    $$specs{"txtImposition$i"} = $bestImposition{'Imposition'};
    @$specs{"txtPrice$i", "txtUnitPrice$i"} = format_pricing(@bestPrice{qw(txtPrice txtUnitQty)});
    $$specs{"txtCustomDiePrice$i"} = sprintf( '%.2f', $bestPrice{'DiePrice'} ); 
  } # end foreach qty

  # We use 'Complex' when the die is supplied but don't want to return it.
  delete $specs->{rdbDieCutting};
  delete  $specs->{txtImposition1} if $specs->{chkOverrideImposition1};

  unless (   $$specs{'txtPrice1'} > 0 or $$specs{'txtPrice2'} > 0 or $$specs{'txtPrice3'} > 0 ) {
    $status = 'uncalculated';
  }
  if ( $status eq 'uncalculated' ) {
    foreach ( 1..3 ) {
      $specs->{"txtPrice$_"}     = '0.00';
      $specs->{"txtUnitPrice$_"} = '0.00';
    }
  }
  return $status;
} # end sub calc

sub calc_price {
  my ( $log, $dbh, $variable, $specs, $equipment, $qty_index, $imposition, $standard_pf, $service_type ) = @_;

  my %price = (
    breakdown => '',
    txtPrice => 0
  );

  my $qty         = $specs->{"txtQuantity$qty_index"}; # Project quantity
  my $impressions = $qty / $imposition;
  my $eid = $$equipment{id};

  my $make_ready    = eprint::service::get_price($log, $dbh, $variable, 
    "${service_type}$specs->{rdbDieCutting}MakeReady", undef, $eid);

  my $service_price = eprint::service::get_price($log, $dbh, $variable, 
    "DieCutting$specs->{rdbDieCutting}", $impressions, $eid);

  my $minimum_price = eprint::service::get_price($log, $dbh, $variable, 
    "${service_type}MinimumCharge", undef, $eid) || 0;

  # The cost of creating the die (for a single project).
  my $die_price = $specs->{"chkOverrideDiePrice$qty_index"} eq 'Y'
  ? $specs->{"txtCustomDiePrice$qty_index"} 
  : die_price($log, $dbh, $variable, $specs, $equipment, $standard_pf);

  # TODO error handling.
  if (!($specs->{"rdbSuppliedDie"} eq 'Y' || $standard_pf || $die_price)) {
    $price{alert} .= 'Need die price or be set to supplied die.<br/>';
    return %price;
  }

  # Each project in the n-up imposition needs it's own die (or a composite)
  # TODO Should this be in die creation and thee rules, bends, etc. be
  # multiplied to get any volume discounts?
  $die_price *= $imposition unless $specs->{"chkOverrideDiePrice$qty_index"} eq 'Y';

  # Die cutting is priced per thousand impressions.
  my $run_price = $impressions * $service_price / 1000;    

  # Hole clearing is the removal of excess material from a die cut hole.
  if ($specs->{rdbHoleClearing} eq 'Y') {
    my $holes = int $specs->{txtHoleClearingHoles} || 0;
    my $per_hole_rate = eprint::service::get_price($log, $dbh, $variable, 'HoleClearing', $holes * $qty, $eid) / 1000;
    $run_price += $qty * ($holes * $per_hole_rate);
  }

  # The minimum price excludes the making of the die.
  my $subtotal = $make_ready + $run_price;
  $subtotal = $minimum_price if $subtotal && $minimum_price > $subtotal;

  $price{'DiePrice'}       = $die_price;
  $price{'MakeReadyPrice'} = $make_ready;

  $price{'ServicePrice'}   = $run_price;
  $price{'txtPrice'}       = $subtotal + $die_price;
  $price{'txtUnitQty'}     = $qty;
  $price{breakdown} = sprintf('Die Price $%.2f + Make Ready $%.2f + Service Price $%.2f = $%.2f', 
    $die_price, $make_ready, $run_price, $price{'txtPrice'});

  # the above price calculation doesn't take into account gluing &c

  return %price;
}

# The cost to create the die itself (for a single project).
sub die_price {
  my ($log, $dbh, $variable, $specs, $equipment, $standard_pf) = @_;

  # The die is supplied (by printer for standard folders or customer).
  return 0 if $standard_pf || $specs->{rdbSuppliedDie} eq 'Y';

  my $eid = $$equipment{id};

  # Check for a standard die.
  my $die_price = eprint::material::get_price($log, $dbh, $variable, "$specs->{template}Die", '', $eid);
  return $die_price if defined $die_price;

  # Create a custom die.
  my $rule_length  =      $specs->{"txtSteelRuleLength$specs->{rdbDieCutting}"};
  my $bends        = int  $specs->{txtDieCutBends}   || 0;
  my $punches      = int  $specs->{txtDieCutPunches} || 0;

  # die "Rule length must be given." unless $rule_length;
  return undef unless $rule_length;

  my $steel_rule_price 
  = eprint::material::get_price($log, $dbh, $variable, "DieCuttingDieRule$specs->{rdbDieCutting}", $rule_length, $eid);
  $die_price += $steel_rule_price * $rule_length;

  if ($bends) {
    my $bending_price 
    = eprint::service::get_price($log, $dbh, $variable, "DieCutRuleBending$specs->{rdbDieCutting}", '', $eid);
    $die_price += $bending_price * $bends;
  }

  if ($punches) {
    my $punch_price = eprint::material::get_price($log, $dbh, $variable, 'DieCutPunch', $punches, $eid);
    $die_price += $punch_price * $punches;
  }

  return $die_price;
}

sub save {
  my ($log, $dbh, $pid, $sid, $service_type, $specs) = @_;

  # Insert glueing if it's been requested and is not already present.
  eprint::print_project::insert_service($log, $dbh, $pid, 'Gluing')
  if $service_type eq 'DieCutting' 
  && $specs->{rdbGlued} eq 'Y'
  && ! eprint::project::check_for_service($log, $dbh, $pid, 'Gluing');
}

sub display {
  my ($log, $dbh, $service_type, $pid, $sid, $specs) = @_;

  my $project = new openprint::Project($pid);
  my %page;

  my $pc = get_print_container( $log, $dbh, $pid );
  my $ServiceType = openprint::ServiceType->find_one(name=>$service_type);

  # Presentation folders bear no resemblance to normal die cutting.
  if ($project->is_presentation_folder()) {
    my $pocket_size = get_specifications($log, $dbh, $pid, $pc, 'rdbPocketSize');
    %page = ( pocket_size => $pocket_size, is_presentationfolder => 1 );
    $$specs{Equipment} = [ openprint::Equipment->find(order=>'lower(strname)',
        useinestimating=>1,
#'servicetype_id @>'=>$ServiceType->id(),
        Specifications => {'Standard Folder Capable'=>'Y'}
      ) ];
  } else {
    %page = get_specifications_pairs( $log, $dbh, undef, $pc,
      qw( flat_width    flat_height final_width   final_height ));
    map  { $specs->{$_} = $page{$_} } keys %page;

    $page{Glued} = $page{rdbGluedY} ? 'Yes' : 'No';
    $$specs{Equipment} = [ openprint::Equipment->find(order=>'lower(strname)',
        useinestimating=>1, 'servicetype_id @>'=>$ServiceType->id()) ];
  } # end if presentation folder or not

  for my $i (1..3) {
    $page{"ddmEquipmentOptions$i"} = ssi::make_drop_down([map { $_->id(), $_->name() } @{$$specs{Equipment}}]);
  }

  return \%page;
}

1;
__END__
