package eprint::Service::Scoring;
use strict;
use warnings;
no warnings qw(uninitialized);

use eprint::Config;
use eprint::service qw(:common);
use eprint::project qw(:common :multipage);
use configuration ();
use sql           ();
use ssi           qw(make_drop_down);
use callback;
use PQS::model::materials;
use PQS::model::service;

require eprint::material;
require eprint::imposition;

# The maximum stock calliper that can be folded without needing scoring.
# Stocks above this will crumple and fold poorly if they aren't scored.
use constant MAX_CALLIPER_UNCOATED => eprint::Config->get(Scoring => 'max_calliper_uncoated');;
use constant MAX_CALLIPER_COATED   => eprint::Config->get(Scoring => 'max_calliper_coated');;


# A function that is smart enough to return true if the project needs
# perfing/scoring, and false if it doesn't.
sub necessary {
    my ($log, $dbh, $pid, $service_type) = @_;

    # If the user has specifically stated they only want to print stuff...
    return 0 if has_no_bindery($log, $dbh, $pid);

    # Perforated forms always requires... well... perforation.
    my $print = get_print_container($log, $dbh, $pid);
    my ($template_type) 
        = get_specifications($log, $dbh, $pid, $print, 'template');
    return 1 if $template_type =~ /FormPerf/;

    my $press_type = $dbh->selectrow_array(q{
		SELECT lngpresstype FROM tbl_projects WHERE lngprojectindex = ?
    }, undef, $pid);

    return 0 if $press_type == 1;

    # The only other time we know scoring to be absolutely necessary is when
    # folding a thick stock (exact calliper dependent on stock type).
    if (check_for_service( $log, $dbh, $pid, 'Folding')) {

        # Check each signature's stock.
        for my $sid (get_signature_indices($log, $dbh, $pid)) {
            my %specs = eprint::service::get_specifications_pairs(
                $log, $dbh, undef, $sid, qw(
                    txtSignatureType txtStockCalliper stock_finish
            ));

            # If any signature needs scoring the overall service is needed.
            return 1 if signature_needs($log, $dbh, $pid, \%specs);
        }
    }

    return 0;
}

sub signature_needs {
    my ($log, $dbh, $pid, $specs) = @_;

    # If we're not being folded (or we're a signature -- covers are handled
    # elsewhere) we don't need scoring for folding. TODO What about gate
    # folded speads? The edges are visible (bug 3077)
    return 0 unless check_for_service($log, $dbh, $pid, 'Folding');

	return 0 if $specs->{txtSignatureType} eq 'Cover Spreads' 
             && ! eprint::Config->get(Scoring => 'always_score_covers');

    # TODO Determine coating a better way than some arbitrary string users can
    # change to anything.
    return 1 if $specs->{txtStockCalliper} >= (
        $specs->{stock_finish} eq 'Uncoated' ? MAX_CALLIPER_UNCOATED 
                                             : MAX_CALLIPER_COATED   );

    return 0;
}

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    # To detect status... is very difficult Note: No it's not.
    my $status = 'uncalculated';

	my @qtys = (undef, get_quantities($log, $dbh, $pid));

    if (get_press_type( $log, $dbh, $pid ) eq 'web' ) {
        $status =
          eprint::service::get_inline_web_bindery( $log, $dbh, $pid, $sid,
            $specs, 'Scoring' );
        if ( $status eq 'calculated' ) { return $status }
        else {
            $status = 'uncalculated';
        }    #if we fail here then run scoring on another piece of equipment
    }
    $$specs{'hdnBreakdown'} = '';

    # Can only use the stitcher for scoring if we are stitching.  There are
    # also thickness constraints
    my $stitching = check_for_service($log, $dbh, $pid, 'SaddleStitching')
                 || check_for_service($log, $dbh, $pid, 'LoopStitching');


    # Can only use the folder for scoring if we are folding.  There are also
    # thickness constraints
    my $folding = check_for_service( $log, $dbh, $pid, 'Folding');

    my @all_equipment = valid_equipment( $log, $dbh, 'Scoring', $pid );

    my %supplier = sql::sql_statement(
        $log, $dbh, q{
        SELECT strID, strSupplier FROM tbl_Equipment
    }
    );

    QTY:
    foreach my $qty_index ( 1 .. 3 ) {

        my $qty = $specs->{"txtQuantity$qty_index"} || $qtys[$qty_index];

        # Skip invalid quantities.
        next unless $qty;

        if ( $$specs{'txtPressSheetComboItems'} ) {
            $qty *= $$specs{'txtPressSheetComboItems'};
        }

        my $totalServicePrice  = 0;
        my $totalSetupPrice    = 0;
        my $totalMaterialPrice = 0;
        my $qtyTotal           = 0;

    	my $print = get_print_container($log, $dbh, $pid);

        my ($spread_width, $spread_height) = 
			get_specifications($log, $dbh, undef, $print, qw(
                  flat_width              flat_height
			)
		);

        for my $sig (get_signature_indices($log, $dbh, $pid)) {
            my (
                $imposition,  	  $imp_rows,
                $imp_cols,        $reference,   $sheet_width,
                $sheet_height,    $calliper,    $image_orientation,
                $press,           $image_width, $image_height,
                $grain_direction,
            ) = get_specifications($log, $dbh, undef, $sig, qw(
                  hdnImposition
                  hdnImpositionRows     hdnImpositionColumns
                  txtServiceDescription hdnSheetSizeWidth
                  hdnSheetSizeHeight    txtStockCalliper
                  hdnImageOrientation   hdnPress
                  txtImageWidth         txtImageHeight
                  hdnGrainDirection
            ));

			$imp_rows = 1 unless $imp_rows;
			$imp_cols = 1 unless $imp_cols;


            $specs->{"txtScoreQty-$sig"} = $specs->{'txtScoreQty-0'}
                if exists $specs->{'txtScoreQty-0'} 
                && ( ! defined $specs->{"txtScoreQty-$sig"} 
                    || $specs->{"txtScoreQty-$sig"} < $specs->{'txtScoreQty-0'} );

            $specs->{"txtPerfQty-$sig"} = $specs->{'txtPerfQty-0'}
                if exists $specs->{'txtPerfQty-0'} 
                && ( ! defined $specs->{"txtPerfQty-$sig"} 
                    || $specs->{"txtPerfQty-$sig"} < $specs->{'txtPerfQty-0'} );

            next unless $specs->{"txtScoreQty-$sig"} 
                     || $specs->{"txtPerfQty-$sig"};

            # I moved this down so we can lookup hdnPress in the same query as
            # everything else, and so that if we aren't scoring this
            # signature, none of this will be done 
            my %best_ssp;    #best supplier specific price;

            $qtyTotal += $$specs{"txtScoreQty-$sig"};
            $qtyTotal += $$specs{"txtPerfQty-$sig"};

# If any of the signatures doesn't have an imposition, then we are in an incomplete state.
            if ( !$imposition ) {
                $status = 'uncalculated';
            }

            my $bestPrice         = 0;
            my $bestEquipment     = '';
            my $bestSetupPrice    = 0;
            my $bestMaterialPrice = 0;
            my $bestServicePrice  = 0;
            my $bestImposition    = 0;

            my @equipment;
            if ( $$specs{"chkOverrideEquipment$qty_index-$sig"} eq
                'Y' )
            {
                @equipment =
                  ( $$specs{"ddmEquipment$qty_index-$sig"} );
            }
            else {
                @equipment = @all_equipment;
            }    # endif

            if ( $$specs{"chkOverrideImposition$qty_index-$sig"} eq
                'Y' )
            {
                if ( $$specs{"txtImposition$qty_index-$sig"} >
                       $imposition
                    or $$specs{"txtImposition$qty_index-$sig"} <=
                    0 )
                {
                    $$specs{'alert'} =
                      "The specified imposition is not possible.";
                    last;
                }
            }

            my %imposition;

            my @impositions = ();

                # For Our Dutch Impositions We only allow 1-up die cutting.
                $imposition{'Imposition'} = 1;
                $imposition{'Rows'} = 1;
                $imposition{'Cols'} = 1;
                push @impositions, \%imposition;

            foreach my $imposition (@impositions) {

                my $width;
                my $height;

                if ( $image_orientation eq 'Vertical' ) {
                    $width  = $spread_width * $$imposition{'Cols'};
                    $height = $spread_height * $$imposition{'Rows'};
                }
                else {
                    $width  = $spread_height * $$imposition{'Cols'};
                    $height = $spread_width * $$imposition{'Rows'};
                }
				#$width = $sheet_width;
				#$height = $sheet_height;

              EQUIPMENT:
                foreach my $eid (@equipment) {
                    my $equipment_type = $dbh->selectrow_array(q{
                        SELECT strtype FROM tbl_equipment WHERE lngindex = ?
                    }, undef, $eid);

                    next EQUIPMENT unless eprint::equipment::equipment_fits(
                            $log, $dbh, $eid, $width, $height, $calliper
                    );

                    my $servicePrice = eprint::service::get_price($log, $dbh, $variable, 'ScorePerforating', $qtyTotal, $eid);
                    my $materialPrice = 0;

                    if ( $equipment_type eq 'folder' ) {
                        if ( !$folding ) { 
                            $$specs{'hdnBreakdown'} .= "\tNot being folded.\n";
                            next EQUIPMENT;
                        }

                        my ($max_calliper) =
                          eprint::equipment::get_specification( $log, $dbh,
                            'Maximum Scoring Calliper',
                            undef, $eid );
                        
                        next EQUIPMENT if $max_calliper 
                                       && $calliper > $max_calliper;
                            

						my $run_units = eprint::equipment::get_units( 
								$log, $dbh, 'ScorePerforating', $eid, $variable );

						if ($run_units eq 'Per Hour')  {
                        	my $runSpeed = eprint::equipment::get_specification( $log, $dbh,
                            	'PerfScoreRunSpeed', undef, $eid );
                        	$servicePrice /= $runSpeed if $runSpeed;
						} else {
                        	$servicePrice /= 1000;
						}
                    }
                    elsif ( $equipment_type eq 'letterpress' ) {

                        # service price is a per 1000 charge
                        $servicePrice = $servicePrice / 1000;

                       # Material price is for the steel rule, so it's a one-time charge
                        $materialPrice += eprint::material::get_price(
                            $log,      $dbh, $variable, 'Score',
                            $qtyTotal, undef
                        ) * $qtyTotal;

                    }
                    elsif ( $equipment_type eq 'press' ) {

                        # service price is a per 1000 charge
                        $servicePrice = $servicePrice / 1000;

                       # Material price is for the steel rule, so it's a one-time charge
                        $materialPrice += eprint::material::get_price(
                            $log,      $dbh, $variable, 'Score',
                            $qtyTotal, undef
                        ) * $qtyTotal;
                    }
                    elsif ( $equipment_type eq 'stitcher' ) {
                        if ( !$stitching ) {
                            $$specs{'hdnBreakdown'} .= "\tNot being stiched.\n";
                            next EQUIPMENT;
                        }
                    }

                    # Div by imposition
                    $servicePrice /= $$imposition{'Imposition'}
                      if $$imposition{'Imposition'};

                    my $setupPrice =
                      eprint::service::get_price( $log, $dbh, $variable,
                        'ScorePerforationMakeReady', undef, $eid );
                    my $totalPrice =
                      $setupPrice + $materialPrice + $qty * $servicePrice;

                    # adding in minimum charge
                    my $minimum_charge =
                      eprint::service::get_price( $log, $dbh, $variable,
                        'ScorePerforationMinimumCharge',
                        undef, $eid );
                    if ( int($minimum_charge) > int($totalPrice) ) {

                        # this is cheesy but we are going to just jam the min
                        # price into the setup if total falls below min.
                        # cause it's not worth messing with the rest of the
                        # code right now.
                        $totalPrice    = $minimum_charge;
                        $setupPrice    = $totalPrice;
                        $servicePrice  = 0;
                        $materialPrice = 0;
                    }

                    if (
                        (
                            ( $totalPrice > 0 ) and ( $totalPrice < $bestPrice )
                        )
                        or $bestPrice == 0
                      )
                    {
                        $bestPrice         = $totalPrice;
                        $bestSetupPrice    = $setupPrice;
                        $bestMaterialPrice = $materialPrice;
                        $bestServicePrice  = $servicePrice;
                        $bestEquipment     = $eid;
                        $bestImposition    = $imposition;
                    }

                    #****************
                    if ( $supplier{$eid} eq $supplier{$press} ) {
                        if (   $totalPrice < $best_ssp{'Price'}
                            or $best_ssp{'Price'} == 0 )
                        {
                            $best_ssp{'Price'}          = $totalPrice;
                            $best_ssp{'Setup Price'}    = $setupPrice;
                            $best_ssp{'Material Price'} = $materialPrice;
                            $best_ssp{'Service Price'}  = $servicePrice;
                            $best_ssp{'Equipment'}      = $eid;
                            $best_ssp{'Imposition'}     = $imposition;
                        }
                    }    #  end if

                    #****************

                }
            }

            #****************
            # SO this means our best price for this service is NOT the price
            # that our printing supplier offers What are we supposed to do in
            # this case?  Cuz if we are just going to always use this
            # supplier, then we might as well not even consider the other
            # suppliers.
            if ( $best_ssp{'Price'} > 0 and $best_ssp{'Price'} != $bestPrice ) {
                $bestPrice         = $best_ssp{'Price'};
                $bestSetupPrice    = $best_ssp{'Setup Price'};
                $bestMaterialPrice = $best_ssp{'Material Price'};
                $bestServicePrice  = $best_ssp{'Service Price'};
                $bestEquipment     = $best_ssp{'Equipment'};
                $bestImposition    = $best_ssp{'Imposition'};
            }

            #****************

            $totalSetupPrice    += $bestSetupPrice;
            $totalServicePrice  += $bestServicePrice;
            $totalMaterialPrice += $bestMaterialPrice;

            $$specs{"ddmEquipment$qty_index-$sig"} = $bestEquipment;
            $$specs{"txtImposition$qty_index-$sig"} =
              $bestImposition ? $$bestImposition{'Imposition'} : 0;
            if ( $image_orientation eq 'Vertical' ) {
                $$specs{"txtImageWidth$qty_index-$sig"} =
                    $bestImposition
                  ? $$specs{"flat_width-$sig"} *
                  $$bestImposition{'Cols'}
                  : 0;
                $$specs{"txtImageHeight$qty_index-$sig"} =
                    $bestImposition
                  ? $$specs{"flat_height-$sig"} *
                  $$bestImposition{'Rows'}
                  : 0;
            }
            else {
                $$specs{"txtImageWidth$qty_index-$sig"} =
                    $bestImposition
                  ? $$specs{"flat_width-$sig"} *
                  $$bestImposition{'Rows'}
                  : 0;
                $$specs{"txtImageHeight$qty_index-$sig"} =
                    $bestImposition
                  ? $$specs{"flat_height-$sig"} *
                  $$bestImposition{'Cols'}
                  : 0;
            }

            $$specs{"txtImageWidth$qty_index-$sig"} = $sheet_width;
            $$specs{"txtImageHeight$qty_index-$sig"} = $sheet_height;

            if ( !$bestEquipment ) {
                $status = 'uncalculated';
                if ( $$specs{"chkOverrideEquipment$qty_index-$sig"}
                    eq 'Y' )
                {
                    $$specs{'alert'} =
"The selected equipment can not handle your project.  This may be because the stock is too heavy, or too large.";
                }
                else {
                    $$specs{'alert'} =
"No suitable equipment could be found for your project.  This may be because the stock is too heavy, or too large.";
                }
            }
        }

        next QTY unless $qtyTotal && $qtyTotal > 0;

        my $price = $qty * $totalServicePrice;
        callback::call('service_end_calc', $pid, $sid, \$totalSetupPrice, \$price);
        $price += $totalSetupPrice + $totalMaterialPrice;

# Allow scoring to be free for safeway.
#        return 'error' unless $price && $price > 0;
        my $mat = PQS::model::materials::material_by_strid('Score');
        PQS::model::service::set_material_estimate($qtyTotal, undef, $sid, $mat->{lngindex}, $qty_index);

        @$specs{"txtPrice$qty_index", "txtUnitPrice$qty_index"}
            = format_pricing($price, $qty);

        $status = 'calculated';
    }

    return $status;
}

sub save_perfing_info {
    # if perfing method has changed then we need to mark printing services for re-calc
    my ( $r, $log, $dbh, $variable, $project_index, $service_index ) = @_;
    foreach my $key ( $r->param() ) {

        if ( $key =~ /^rdb/ ) {
            my ( $temp, $index ) = split( '-', $key );
            my $style = $r->param($key);

            my ($check) =
              eprint::service::get_specifications( $log, $dbh, undef, $index,
                'txtInlinePerfScoring' );
            $check = 0 if $check eq '';

            if (   ( $check == 1 and $style eq 'No' )
                or ( $check == 0 and $style eq 'Yes' ) )
            {
                sql::update( $log, $dbh, 'tbl_Project_Contents',
                    "lngServiceIndex='$index' AND strStatus='calculated'",
                    'strStatus', 'modified' );
                $style = $style eq 'Yes' ? 1 : 0;
                eprint::service::insert_service_spec( $log, $dbh,
                    $project_index, $index, 'txtInlinePerfScoring', $style );
            }
        }
    }
}

sub fill_from_printing_service {
    my ($log, $dbh, $pid, $sid) = @_;

    foreach my $sig (get_signature_indices($log, $dbh, $pid)) {

        my ( $template, $width, $height, $flat_width,
            $flat_height, $sig_type, $stock_calliper, $stock_finish)
          = get_specifications(
            $log,             $dbh,
            undef,            $sig,
            'template',
            'txtSpreadWidth',   'txtSpreadHeight',
            'flat_width',       'flat_height',
            'txtSignatureType', 'txtStockCalliper',
            'stock_finish',
          );

        next if $sig_type eq 'Cover Spreads' 
             && ! configuration::get_value($log, $dbh, 'ScoreCover');

             
        my $score_calliper 
            =  $stock_finish eq 'Uncoated' ? MAX_CALLIPER_UNCOATED 
                                           : MAX_CALLIPER_COATED;

        next if $stock_calliper < $score_calliper;


        if ( !$width || !$height ) {
            ( $width, $height ) = ( $flat_width, $flat_height );
        }

        insert_service_spec($log, $dbh, $pid, $sid, "flat_width-$sig", $width);
        insert_service_spec($log, $dbh, $pid, $sid, "flat_height-$sig", $height);
        
        if (   $template =~ '^2PanelFold'
            || $template eq 'BusCardLandscapeFold'
            || $template eq 'BusCardPortraitFold'
            || $template =~ '^FolioLip' 
        ) {
            insert_service_spec($log, $dbh, $pid, $sid, "txtScoreQty-$sig" => 1);
        }
        elsif ($template =~ '^3PanelZ?Fold$') { 
            insert_service_spec($log, $dbh, $pid, $sid, "txtScoreQty-$sig" => 2);
        }
        elsif ($template =~ '^4PanelZFold$') {
            insert_service_spec($log, $dbh, $pid, $sid, "txtScoreQty-$sig" => 3);
        }
        elsif ($template =~ '^5PanelZ?Fold$') {
            insert_service_spec($log, $dbh, $pid, $sid, "txtScoreQty-$sig" => 4);
        }
        elsif ($template =~ '^6PanelZ?Fold$') {
            insert_service_spec($log, $dbh, $pid, $sid, "txtScoreQty-$sig" => 5);
        }
        elsif ( $template eq 'SingleGateFold') {
            insert_service_spec($log, $dbh, $pid, $sid, "txtScoreQty-$sig" => 2);
        }
        elsif ( $template eq 'DoubleGateFold') {
            insert_service_spec($log, $dbh, $pid, $sid, "txtScoreQty-$sig" => 3);
        }
        # General catchall that shouldn't be here.
        else {
            insert_service_spec($log, $dbh, $pid, $sid, "txtScoreQty-$sig" => 1)
        }
    }
}

sub display {
    my ( $log, $dbh, $service_type, $pid, $sid, $specs ) = @_;

    my %var;
    my $variable = \%var;

    $variable->{SignatureGroups} = [];

    my %specs = get_specifications_pairs($log, $dbh, $pid, $sid);

    $$variable{'txtQuantity1'} = $specs{'txtQuantity1'};
    $$variable{'txtQuantity2'} = $specs{'txtQuantity2'};
    $$variable{'txtQuantity3'} = $specs{'txtQuantity3'};

    for my $sig (get_signature_indices( $log, $dbh, $pid))
    {
        my ( $reference ) =
          eprint::service::get_specifications( $log, $dbh, undef,
            $sig, 'txtServiceDescription' );

        my ( $width, $height ) =
          @specs{ "flat_width-$sig", "flat_height-$sig" };
        if ( !$width and !$height ) {

            #populate width and height from signature
            ( $width, $height, my $flat_width, my $flat_height ) =
              eprint::service::get_specifications( $log, $dbh, undef,
                $sig, 'txtSpreadWidth', 'txtSpreadHeight',
                'flat_width', 'flat_height' );
            if ( !$width || !$height ) {
                ( $width, $height ) = ( $flat_width, $flat_height );
            }
        }

        my @equipment_names;

        @equipment_names =
          eprint::service::valid_equipment( $log, $dbh, 'Scoring' );

        @equipment_names =
          get_right_equipment( $log, $dbh, $pid, @equipment_names );
        my $temp1 = $specs{"txtScoreQty-$sig"};
        my $temp2 = $specs{"txtPerfQty-$sig"};
        push @{ $$variable{'SignatureGroups'} },
          (
            $sig,
            $reference,
            $width, $height,
            $specs{"txtScoreQty-$sig"},
            $specs{"txtPerfQty-$sig"},
            $specs{"ddmEquipment1-$sig"},
            $specs{"chkOverrideEquipment1-$sig"} eq 'Y' ? 'CHECKED'
            : '',
            ssi::make_drop_down(
                \@equipment_names, $specs{"ddmEquipment1-$sig"}
            ),
            $specs{"ddmEquipment2-$sig"},
            $specs{"chkOverrideEquipment2-$sig"} eq 'Y' ? 'CHECKED'
            : '',
            ssi::make_drop_down(
                \@equipment_names, $specs{"ddmEquipment2-$sig"}
            ),
            $specs{"ddmEquipment3-$sig"},
            $specs{"chkOverrideEquipment3-$sig"} eq 'Y' ? 'CHECKED'
            : '',
            ssi::make_drop_down(
                \@equipment_names, $specs{"ddmEquipment3-$sig"}
            ),
            $specs{"txtImposition1-$sig"},
            $specs{"chkOverrideImposition1-$sig"} eq 'Y' ? 'CHECKED'
            : '',
            @specs{
                "txtImageWidth1-$sig",
                "txtImageHeight1-$sig"
              },
            $specs{"txtImposition2-$sig"},
            $specs{"chkOverrideImposition2-$sig"} eq 'Y' ? 'CHECKED'
            : '',
            @specs{
                "txtImageWidth2-$sig",
                "txtImageHeight2-$sig"
              },
            $specs{"txtImposition3-$sig"},
            $specs{"chkOverrideImposition3-$sig"} eq 'Y' ? 'CHECKED'
            : '',
            @specs{
                "txtImageWidth3-$sig",
                "txtImageHeight3-$sig"
              }
          );

    }
	return $variable;
}

sub get_right_equipment {
    my ( $log, $dbh, $pid, @equipment ) = @_;
    # Can only use the stitcher for scoring if we are stitching.  There are
    # also thickness constraints
    my $stitching = check_for_service($log, $dbh, $pid, 'SaddleStitching')
                 || check_for_service($log, $dbh, $pid, 'LoopStitching');


    # Can only use the folder for scoring if we are folding.  There are also
    # thickness constraints
    my $folding = check_for_service( $log, $dbh, $pid, 'Folding');

    my @return_equipment;
    my $equip_str;
    my $equip_name;
	my $index;
    foreach my $equip_id (@equipment) {
        my $equip_type = eprint::equipment::get_type( $log, $dbh, $equip_id );
        if (   ( ( $equip_type eq 'stitcher' ) && ($stitching) )
            || ( ( $equip_type eq 'folder' ) && ($folding) )
            || ( ( $equip_type ne 'folder' ) && ( $equip_type ne 'siticher' ) )
          )
        {
            ( $index, $equip_str, $equip_name ) = $dbh->selectrow_array(
                qq{
                SELECT lngindex, strid, strname
                FROM tbl_equipment
                WHERE lngIndex = ?
            }, undef, $equip_id
            );
            $return_equipment[ scalar(@return_equipment) ] = $index;
            $return_equipment[ scalar(@return_equipment) ] = $equip_name;
        }
    }
    return @return_equipment;
}


1;

