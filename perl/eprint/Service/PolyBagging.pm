package eprint::Service::PolyBagging;
use strict;
use warnings;

use eprint::service qw(:common);
use POSIX           qw(ceil);
use callback;

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    return 'uncalculated' unless $specs->{txtBundleQuantity}
                              && $specs->{txtBundleQuantity} > 0;

    my $status = 'uncalculated';
    foreach my $i (1..3) {
        my $qty = int $specs->{"txtQuantity$i"};

        next unless $qty && $qty > 0;

        my ($price, $bags) = calc_price($log, $dbh, $variable, $specs, $pid, $sid, $qty);

        return 'error' unless $price && $price > 0;

        # Unit price is per bag.
        @$specs{"txtPrice$i", "txtUnitPrice$i"}
            = format_pricing($price, $bags);

        $status = 'calculated';
    }

    return $status;
}

sub calc_price {
    my ($log, $dbh, $variable, $specs, $pid, $sid, $qty) = @_;

    my $min_price  = get_price($log, $dbh, $variable, 'PolyBaggingMinimumCharge');
    my $make_ready = get_price($log, $dbh, $variable, 'PolyBaggingMakeReady');
    my $rate       = get_price($log, $dbh, $variable, 'PolyBagging', $qty);
    
    # Fit n items into m bags.
    my $items_per_bag = $specs->{txtBundleQuantity} || 1;
    my $bags          = ceil($qty / $items_per_bag);

    # Pricing is per thousand bags.
    my $price = $bags/1000 * $rate;
    callback::call('service_calc_end', $pid, $sid, \$make_ready, \$price);
    $price += $make_ready;

    return ($price, $bags);
}

1;
