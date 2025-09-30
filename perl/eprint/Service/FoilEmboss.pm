package eprint::Service::FoilEmboss;
use strict;

use eprint::project;
use eprint::equipment;
use eprint::print;
use eprint::imposition;
use eprint::service 	qw( :common );
use sql                 qw(:common);
use PQS::model::materials;
use PQS::model::service;

sub fill_from_printing_service {
    my ( $log, $dbh, $pid, $sid ) = @_;
    my @signature_indices =
      eprint::project::get_signature_indices( $log, $dbh, $pid );
    my $printing_service_index = shift @signature_indices;
    eprint::service::insert_service_specs(
        $log, $dbh,
        $pid,
        $sid,
        eprint::service::get_specifications_pairs(
            $log,                  $dbh,
            undef,                 $printing_service_index,
            'hdnGrossSheetCount1', 'hdnGrossSheetCount2',
            'hdnGrossSheetCount3', 'hdnNetSheetCount1',
            'hdnNetSheetCount2',   'hdnNetSheetCount3',
            'hdnSheetSizeWidth',   'hdnSheetSizeHeight',
        )
    );
}

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    my $valid_equip  = 0;
    my $status       = 'calculated';
    my @signature_indices =
      eprint::project::get_signature_indices( $log, $dbh, $pid );
    my $printing_service_index = shift @signature_indices;
    my %printing_specs;
    @printing_specs{
        'txtStockCalliper', 'hdnImposition',
        'hdnImpositionRows',        'hdnImpositionColumns',
        'hdnImageOrientation',		'hdnGrainDirection',
      }
      = eprint::service::get_specifications(
        $log,                       $dbh,
        undef,                      $printing_service_index,
        'txtStockCalliper', 'hdnImposition',
        'hdnImpositionRows',        'hdnImpositionColumns',
        'hdnImageOrientation',		'hdnGrainDirection',
      );
    my $signature_index;

    # add in defaults for die type and foil type
    if ( $specs->{rdbDieType} eq '' ) {
        $specs->{rdbDieType} = 'Simple';
    }
    if ( $specs->{rdbMaterialType} eq '' ) {
        $specs->{rdbMaterialType} = 'Standard';
    }
    if (   !$specs->{txtDieWidth}
        or !$specs->{txtDieHeight}
        or $specs->{rdbDieType} eq '' )
    {
        $status = 'uncalculated';
    }
    if (   ( $specs->{txtDieHeight} > $specs->{flat_height} )
        or ( $specs->{txtDieWidth} > $specs->{flat_width} ) )
    {
        $log->debug("Die is way too large. ");
        $status = 'uncalculated';
        $specs->{error} =
'The size of the die can not exceed the Flat dimensions of the project';
        return $status;
    }
    else {
        $log->debug("Die SIZE is Valid ");
    }
    $specs->{hdnBreakdown} = '';

  my $ServiceType = openprint::ServiceType->find_one(name=>$service_type);
  my @possible_equipment = openprint::Equipment->find(useinestimating=>1,'servicetype_id @>'=>$ServiceType->id());
  #eprint::service::valid_equipment( $log, $dbh, $service_type );
    $log->debug("FOIL STAMPING: calc got equipment @possible_equipment");
    foreach my $qty_index ( 1 .. 3 ) {
        my %bestPrice;
        my %bestImposition;
        if ( $specs->{"txtQuantity$qty_index"} ) {
            my $bestEquipment;
            my @equipment = ();
            if ( $specs->{"chkOverrideEquipment$qty_index"} eq 'Y' ) {
                @equipment = map { $_->id() == $specs->{"ddmEquipment$qty_index"} ? $_ : () } @possible_equipment;
            }
            else {
                @equipment = @possible_equipment;
            }

            my %imposition;
            my @impositions = ();

			$imposition{Imposition} = 1;
			$imposition{Rows} = 1;
			$imposition{Cols} = 1;


			push @impositions, \%imposition;


            foreach my $imposition (@impositions) {

                my $imp_width  = 0;
                my $imp_height = 0;

                $imp_width = $specs->{"flat_width"};
                $imp_height = $specs->{"flat_height"};
                

                foreach my $equipment (@equipment) {

                    # First, find out if it fits
                    if (
                        (
                            !eprint::equipment::equipment_fits(
                                $log,
                                $dbh,
                                $$equipment{id},
                                $imp_width,
                                $imp_height,
                                $printing_specs{txtStockCalliper}
                            )
                        )
                      )
                    {
                        $specs->{hdnBreakdown} .= "doesn't fit.\n";
                    }
                    else {
                        $valid_equip = 1;
                        my %price = calc_price(
                            $log, $dbh,
                            $variable,
                            $service_type,
                            $specs,
                            $$equipment{id},
                            $qty_index,
                            $$imposition{Imposition}
                        );
                        if ( !$bestPrice{txtPrice}
                            or $price{txtPrice} < $bestPrice{txtPrice} )
                        {
                            $bestEquipment  = $$equipment{id};
                            %bestPrice      = %price;
                            %bestImposition = %$imposition;
                        }
                        $specs->{hdnBreakdown} .= 
                                'Quantity: '    . $specs->{"txtQuantity$qty_index"}
                            . ', Equipment: '   . $$equipment{name}
                            . ', Imposition: '  . $imposition->{Imposition}
                            . ', Impressions: ' . $price{Impressions}
                            . ', MakeReady: $'  . sprintf( '%.2f', $price{MakeReadyPrice} )
                            . ', Materials: $'  . sprintf( '%.2f', $price{MaterialPrice} )
                            . ', Service: $'    . sprintf( '%.2f', $price{ServicePrice} )
                            . ', DiePrice: $'   . sprintf( '%.2f', $price{DiePrice} )
                            . ', Total: $'      . sprintf( '%.2f', int( $price{txtPrice} ) ) 
                            . "\n";
                    }
                }
            }

            $specs->{"ddmEquipment$qty_index"} = $bestEquipment;
        }
        $specs->{hdnBreakdown} = ''; 
        $specs->{"txtImposition$qty_index"} =
          $bestImposition{Imposition};
        
        @$specs{"txtPrice$qty_index", "txtUnitPrice$qty_index"}
            = format_pricing(@bestPrice{qw(txtPrice txtUnitQty)});

        $specs->{"txtCustomDiePrice$qty_index"} =
          sprintf( '%.2f', $bestPrice{DiePrice} ) unless $specs->{"chkOverrideDiePrice$qty_index"} eq 'Y';
        $specs->{error} =
          configuration::get_value( $log, $dbh, 'StandardErrorMessage' )
          if !$valid_equip;
        if ( $printing_specs{hdnImageOrientation} eq 'Vertical' ) {
            $specs->{"txtImageWidth$qty_index"} =
              $specs->{"flat_width"} * $bestImposition{Cols};
            $specs->{"txtImageHeight$qty_index"} =
              $specs->{"flat_height"} * $bestImposition{Rows};
        }
        else {
            $specs->{"txtImageWidth$qty_index"} =
              $specs->{"flat_width"} * $bestImposition{Rows};
            $specs->{"txtImageHeight$qty_index"} =
              $specs->{"flat_height"} * $bestImposition{Cols};
        }

        my $area = $specs->{txtDieWidth} * $specs->{txtDieHeight};
        $area *= $bestImposition{Imposition} if $bestImposition{Imposition} > 1;
        if ($specs->{rdbSuppliedDie} ne 'No') {
          my $mat = PQS::model::materials::material_by_strid('Die');
          PQS::model::service::set_material_estimate($area, undef, $sid, $mat->{lngindex}, $qty_index) if $mat->{lngindex};
        }
        if ($service_type eq 'FoilStamping') {
          my $mat = PQS::model::materials::material_by_strid('Foil');
          PQS::model::service::set_material_estimate($area, undef, $sid, $mat->{lngindex}, $qty_index) if $mat->{lngindex};
        }
    }
    if (   ( $specs->{txtPrice1} eq 0 )
        && ( $specs->{txtPrice2} eq 0 )
        && ( $specs->{txtPrice3} eq 0 ) )
    {
        $status = 'uncalculated';
    }
    return $status;
}

sub calc_price {
    my ($log, $dbh, $variable, $service_type, $specs, $equipment_id, $qty_index, $imposition ) = @_;

    my $area = $specs->{txtDieWidth} * $specs->{txtDieHeight};
    if ( $area == 0 ) {
        $log->debug("Can not Calc price, Die area not supplied ");
        return ( 'error', 'Please Supply the area of the die image' );
    }
    if (
        $area > ( $specs->{flat_width} * $specs->{flat_height} ) )
    {
        $log->debug("Die is too large. ");
        return ( 'error',
'The size of the die can not exceed the Flat dimensions of the project'
        );
    }
    $area *= $imposition if $imposition > 1;
    my $makeReadyPrice =
      eprint::service::get_price( $log, $dbh, $variable,
        $service_type . $specs->{rdbDieType} . 'MakeReady',
        undef, $equipment_id );
    my $diePrice = 0;
	my $custom;
    if ( $specs->{rdbSuppliedDie} ne 'Yes' ) {
        if ( $specs->{"chkOverrideDiePrice$qty_index"} eq 'Y' ) {
            $diePrice = $specs->{"txtCustomDiePrice$qty_index"};
			$custom = 1;
        }
        else {
            $diePrice =
              eprint::material::get_price( $log, $dbh, $variable,
                $service_type . 'Die',
                $area, undef );
        }
    }
    my $impressions =
      $specs->{ 'txtQuantity' . $qty_index } / $imposition
      if $imposition;
    my $servicePrice =
      eprint::service::get_price( $log, $dbh, $variable,
        $service_type . $specs->{rdbDieType},
        $impressions, $equipment_id );
    $servicePrice *= $impressions / 1000;
    my $materialPrice;
    if ( $service_type eq 'FoilStamping' ) {
        $materialPrice = eprint::material::get_price(
            $log, $dbh, $variable,
            $specs->{rdbMaterialType} . 'Foil',
            $area * $impressions, undef
        );
        $materialPrice *= $area * $impressions;
    }
    $diePrice *= $area unless $custom;
    my $price = $servicePrice + $materialPrice + $makeReadyPrice + $diePrice;
    my $minCharge =
      eprint::service::get_price( $log, $dbh, $variable,
        $service_type . 'MinimumCharge',
        undef, $equipment_id );
    if ( $minCharge and $price < $minCharge ) {
        $price = $minCharge;
    }
    my %price;
    $price{Impressions}    = $impressions;
    $price{DiePrice}       = $diePrice;
    $price{MakeReadyPrice} = $makeReadyPrice;
    $price{MaterialPrice}  = $materialPrice;
    $price{ServicePrice}   = $servicePrice;
    $price{txtPrice}       = $price;
    $price{txtUnitQty}     = $specs->{"txtQuantity$qty_index"};

    return %price;
}



sub display {
  my ($log, $dbh, $service_type, $pid, $sid, $specs ) = @_;

  my $pc = eprint::project::get_print_container( $log, $dbh, $pid );

  my %page = eprint::service::get_specifications_pairs(
    $log,            $dbh,
    undef,           $pc,
    'flat_width',    'flat_height',
    'final_width',   'final_height',
  );

  # Todo: stop putting dims into specs and remove
  # form fields from page.
  @$specs{keys %page} = values %page;
  #map  { $specs->{$_} = $page{$_} } keys %page;

  my $ServiceType = openprint::ServiceType->find_one(name=>$service_type);
  $$specs{Equipment} = [ openprint::Equipment->find(order=>'lower(strname)',
      useinestimating=>1,'servicetype_id @>'=>$ServiceType->id() ) ];
  for my $i (1..3) {
    $page{"ddmEquipmentOptions$i"} = ssi::make_drop_down([map { $_->id(), $_->name() } @{$$specs{Equipment}}]);
    #eprint::service::valid_equipment_dropdown($dbh, $service_type);
  }

  return \%page;
}

1;
