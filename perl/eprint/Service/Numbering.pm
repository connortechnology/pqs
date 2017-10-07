package eprint::Service::Numbering;
use strict;
use warnings;
no warnings qw(uninitialized);

use eprint::service qw(:common);
use eprint::project qw(:common);
use eprint::equipment qw(get_index_by_id);
use sql             qw(:common);
use ssi             ();
use POSIX           qw(floor ceil);

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    my $status = 'uncalculated';

	my @equipment = valid_equipment(undef, $dbh, 'Numbering');

    my @overrides = ($$specs{'chkOverrideEquipment1'},
                     $$specs{'chkOverrideEquipment2'},
                     $$specs{'chkOverrideEquipment3'});
    my %bestrun;
    foreach my $numberer (@equipment) {
        my $heads_used = $$specs{'rdbSetsOfNumbers'};
		my $equipment_heads = eprint::equipment::get_specifications(
								$log, $dbh, $numberer, 'Numbering Heads');

        $heads_used = $equipment_heads
          if $equipment_heads < $heads_used;

        my $number_of_runs =
          ceil($$specs{'rdbSetsOfNumbers'} / $equipment_heads);
        return $status unless $number_of_runs;
        my $last_run = $$specs{'rdbSetsOfNumbers'} % $equipment_heads;
        if ($number_of_runs eq 1 && $last_run eq 0) {
            $last_run =
              $equipment_heads;  # correct for x mod x = 0 when our last run is our only run
        }

        my $makeready        = get_price($log, $dbh, $variable, 'NumberingMakeReady', undef, $numberer);
        my $headmakeready    = get_price($log, $dbh, $variable, 'NumberingHeadMakeReady', undef, $numberer);
        my $minimumcharge    = get_price($log, $dbh, $variable, 'NumberingMinimumCharge', undef, $numberer);
        my $serviceprice     = get_price($log, $dbh, $variable, 'Numbering', $heads_used, $numberer); 
        my $lastserviceprice = get_price($log, $dbh, $variable, 'Numbering',$last_run, $numberer);

        my @runprice;
        my @qtys = (undef, get_quantities($log, $dbh, $pid));

        for my $i (1..3) {
            next unless $qtys[$i] && $qtys[$i] > 0;

            if (   (!($overrides[$i - 1] eq 'Y'))
                || ($numberer eq $$specs{"ddmEquipment$i"}))
            {
                $runprice[$i - 1] = (
                    ( (  $makeready 
                       + ($heads_used * $headmakeready) 
                       + ($qtys[$i] * $serviceprice / 1000)
                      ) * ($number_of_runs - 1) ) 
                    + (   $makeready 
                        + ($last_run * $headmakeready) 
                        + ($$specs{"txtQuantity$i"} * $lastserviceprice / 1000) )
                );

                $runprice[$i - 1] = $minimumcharge if $runprice[$i - 1] < $minimumcharge;

                if ((   ($runprice[$i - 1])
                     && ($runprice[$i - 1] < $bestrun{"txtPrice$i"}))
                    || ($bestrun{"txtPrice$i"} == 0))
                {
                    $bestrun{"txtPrice$i"}    = $runprice[$i - 1];
                    $specs->{"ddmEquipment$i"} = $numberer;
                    $specs->{"txtPrice$i"}     = sprintf("%.2f", floor($runprice[$i - 1]));
                    $specs->{"txtUnitPrice$i"} = sprintf("%.2f", $runprice[$i - 1] / $qtys[$i]);
                    $status = 'calculated';
                }
            }
        }

    }
    return $status;
}

sub display {
    my ($log, $dbh, $service_type, $pid, $sid, $specs) = @_;
	my %page;

	my $equipment = eprint::service::valid_equipment_dropdown($dbh,$service_type);
    for my $i (1..3) {
        $page{"ddmEquipmentOptions$i"} = $equipment;
    }

	return \%page;
}

1;
