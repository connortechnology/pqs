package eprint::Service::Drilling;
use strict;
use warnings;
no warnings qw(uninitialized);

use POSIX             qw(ceil);
use eprint::service   qw(:common);
use eprint::project   qw(:common);
use eprint::equipment ();
use sql               ();
use callback;

sub display {
	my ($log, $dbh ,$service_type, $pid, $sid, $specs) = @_;
	my %page;

	$specs->{txtFinishedCalliper} = get_finished_calliper($log, $dbh, $specs, $pid);

	return \%page;
}


sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    my $status = 'calculated';
    $specs->{hdnBreakdown} = '';

    my $calliper = get_finished_calliper($log, $dbh, $variable, $pid);

    my $holeSize   = $specs->{txtHoleSize};
    my $holeQty    = $specs->{txtHoleQty};
    my @quantities = @$specs{ qw(txtQuantity1 txtQuantity2 txtQuantity3) };

    return 'uncalculated' unless $holeQty;

    # Can only use the stitcher for scoring if we are stitching.  There are
    # also thickness constraints
    my $stitching = check_for_service($log, $dbh, $pid, 'SaddleStitching')
                 || check_for_service($log, $dbh, $pid, 'LoopStitching');

    my $print = get_print_container($log, $dbh, $pid);
    my $bookSheetQty 
        = get_specifications($log, $dbh, undef, $print, 'txtTotalSpreadQuantity');

    my @all_equipment = valid_equipment($log, $dbh, 'Drilling', $pid);

    for my $i (1..3) {
        my $bestPrice        = 0;
        my $bestServicePrice = 0;
        my $bestEquipment    = '';
        my $bestLift         = 0;

        foreach my $eid (@all_equipment) {
            my $equipment_type =
              eprint::equipment::get_specification($log, $dbh, 'Type', undef,
                                                   $eid);
            
            next if $equipment_type eq 'Stitcher' && !$stitching;

            my $price = 0;

            #change to new standard was ChargeMinimun is MinimumCharge
            my $minPrice = get_price(
                $log, $dbh, $variable, 'DrillingMinimumCharge', undef, $eid);

            my $drillHeads =
              eprint::equipment::get_specification($log, $dbh, 'Drill Heads',
                                                   undef, $eid);
            if ($drillHeads == 0) {
                next;
            }
            my $runs = $holeQty / $drillHeads;
            my $qty  = $quantities[$i - 1];

            #Maximum Lift Depth is now Lift Depth calculates lift depth based on the hole size
            my $lift_depth =
              eprint::equipment::get_specification($log, $dbh, 'Lift Depth',
                                                   $holeSize, $eid);
            if ($lift_depth == 0) {
                $lift_depth = 4
            }    #quick fix to prevent div by 0 when no equipment spec

            if ($runs != int($runs) or int($runs) != 0) {
                $runs = int($runs) + 1;
            }
            else {
                $runs = int($runs);
            }

            $$specs{'hdnBreakdown'} .= "\t\tEquipment: $eid, ";
            $$specs{'hdnBreakdown'} .= "Runs: $runs\n";
            $$specs{'hdnBreakdown'} .= "Qty $qty :";

            if ($qty > 0) {    #and $runs > 0 ) {

                my $run_qty = ceil(($qty * $calliper / $lift_depth) * $runs);

                $$specs{'hdnBreakdown'} .= "Total Project Qty $qty :";

                my $makeReady = get_price(
                    $log, $dbh, $variable, 'DrillingMakeReady', undef, $eid);
                
                my $drillingHeadMakeReady = get_price(
                    $log, $dbh, $variable, 'DrillingHeadMakeReady', $holeQty, $eid) * $holeQty;

                my $servicePrice = get_price(
                    $log, $dbh, $variable, 'Drilling', $run_qty, $eid);

                if (! $servicePrice) {
                    $$specs{'hdnBreakdown'} .=
                      "No Price found for this quantity. ($servicePrice)";
                    next;
                }

                $price = ($servicePrice * $run_qty);
                $makeReady += $drillingHeadMakeReady;

                callback::call('service_calc_end', $pid, $sid, \$makeReady, \$price);

                $price += $makeReady;

                if ($minPrice > 0 and $price < $minPrice) {
                    $price = $minPrice;
                }

                if ($price < $bestPrice or !$bestPrice) {
                    $bestPrice        = $price;
                    $bestServicePrice = $servicePrice;
                    $bestEquipment    = $eid;
                    $bestLift         = $lift_depth;
                }
            }
        }

        next unless $quantities[$i - 1] && $quantities[$i - 1] > 0;

        @$specs{"txtPrice$i", "txtUnitPrice$i"}
            = format_pricing($bestPrice, $quantities[$i - 1]);
    }

    return $status;
}


1;
