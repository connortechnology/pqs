package eprint::Service::Scanning;
use strict;
use warnings;
no warnings qw(uninitialized);

use eprint::service qw(:common);
use eprint::equipment qw(:common);
use eprint::project qw(check_for_service);
use eprint::print_project qw(insert_service);
use callback;
use ssi;

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    my ($scanner, $qty, $w_f, $h_f, $w, $h, $percent) = @$specs{qw(
        ddmScanner        txtQuantity
        txtScanWidthFinal txtScanHeightFinal 
        txtScanWidth      txtScanHeight
        txtPercent
    )};

    my $area = ($w_f * $h_f)
            || ($w   * $h   * ($percent/100)); # Output are.

    $qty = int $qty if $qty;     # Can't have partial scans.

# disable safety checks for safeway.
#    return 'uncalculated' unless $area && $qty && $scanner;

    my $make_ready = get_price($log, $dbh, $variable, 'ScanningMakeReady', $qty, $scanner);
    my $rate       = get_price($log, $dbh, $variable, 'Scanning', $area, $scanner);
    
    # Pricing is per sq. inch.
    my $price = $qty * ($rate * $area);
    callback::call('service_calc_end', $pid, $sid, \$make_ready, \$price);
    $price += $make_ready;

    # Format the pricing and store it.
    my ($total, $unit_price) = format_pricing($price, $qty);
    @$specs{"txtPrice$_", "txtUnitPrice$_"} = ($total, $unit_price) for 1..3;

#    return $price && $price > 0 ? 'calculated' : 'uncalculated';
    return 'calculated';
}


sub display {
    my ($log, $dbh, $service_type, $pid, $sid, $specs) = @_;

    my @scanners = map {
        (eprint::equipment::get_id_by_index($log, $dbh, $_), get_name($log, $dbh, $_))
    } valid_equipment($log, $dbh, $service_type);
    
    return { ddmScannerList => ssi::make_drop_down(\@scanners) };
}


sub save {
    my ($log, $dbh, $service_type, $pid, $sid, $specs) = @_;

    # The user requires a proof of the scan.
    if ($specs->{rdbRandomProof} eq 'Yes') {
        # Check to see if there is already a proof service, if not add it.
        my $proofs = check_for_service($log, $dbh, $pid, 'Proofs')
                  || insert_service($log, $dbh, $pid, 'Proofs');

        # Add a scanning proof.
    }
    delete $specs->{rdbRandomProof} if exists $specs->{rdbRandomProof};

    # The user wants an additional item scanned.
    if ($specs->{rdbAdditional}) {
        # Insert another scanning service
        insert_service($log, $dbh, $pid, 'Proofs');
    }
    delete $specs->{rdbAdditional} if exists $specs->{rdbAdditional};

    return;
}

1;
