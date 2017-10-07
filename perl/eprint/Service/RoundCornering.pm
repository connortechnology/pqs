package eprint::Service::RoundCornering;
use strict;
use warnings;

use eprint::project qw(get_quantities get_finished_calliper);
use eprint::service qw(:common);
use POSIX           qw(ceil);
use callback;

# Price all quantities.
sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    # Number of corners per project TODO Change name.
    my $corners  = int $specs->{txtHoleQty};
    my $calliper = $specs->{txtFinishedCalliper}; # TODO Some error checking?

    return 'uncalculated' unless $corners && $corners > 0;

    my $status = 'uncalculated';
    foreach my $i (1..3) {
		my $qty = $specs->{"txtQuantity$i"};
        next unless $qty;

        my $price = calc_price(
            $log, $dbh, $variable, $specs, $pid, $sid, $qty, $corners, $calliper);

        return 'error' unless $price && $price > 0;

        @$specs{"txtPrice$i", "txtUnitPrice$i"}
            = format_pricing($price, $qty);

        $status = 'calculated';
    }

    return $status;
}

sub calc_price {
    my ($log, $dbh, $variable, $specs, $pid, $sid, $qty, $corners, $calliper) = @_;

    die "Invalid calliper." unless $calliper && $calliper > 0;

    my $make_ready = get_price($log, $dbh, $variable, 'RoundCorneringMakeReady');
    my $min_price  = get_price($log, $dbh, $variable, 'RoundCorneringMinimumCharge');


    # BAD! BAD! BAD! See bug 3072.
    my $depth = scalar $dbh->selectrow_array(q{
        SELECT strvalue 
        FROM tbl_equipment_specifications
        WHERE strname = 'Maximum Lift Depth'
          AND lngequipmentindex = (
            SELECT lngindex
            FROM tbl_equipment 
            WHERE strtype = 'roundcornerer'
            LIMIT 1 )
    });

    my $items_per_lift = int ($depth / $calliper);
    my $lifts          = ceil ($qty / $items_per_lift);

    # Volume discounted by lifts.
    my $rate = get_price($log, $dbh, $variable, 'RoundCornering', $lifts);
   
    # Pricing is per operation of the machine, which can process a single
    # corner for each stack.
    my $price = $corners * $lifts * $rate;
    callback::call('service_calc_end', $pid, $sid, \$make_ready, \$price);
    $price += $make_ready;

    $price = $min_price if $min_price && $min_price > $price;

    return $price;
}

sub display {
    my ($log, $dbh ,$service_type, $pid, $sid, $specs) = @_;
    my %page;

    $specs->{txtFinishedCalliper} = get_finished_calliper($log, $dbh, $specs, $pid);

    return \%page;
}   
1;
