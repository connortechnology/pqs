package eprint::Service::Counting;
use strict;

use eprint::project qw(get_quantities);
use eprint::service qw(:common);
use callback;

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    my $status = 'uncalculated';

    # This is just a display field for the docket. The number is the size of
    # the piles to group projects into when counting. 
    $specs->{txtSignatureCount} = int($specs->{txtSignatureCount}) || 1;

    my $make_ready = get_price($log, $dbh, $variable, 'CountingMakeReady');
    my $min_price  = get_price($log, $dbh, $variable, 'CountingMinimumCharge');

    foreach my $i (1 .. 3) {
        my $qty = int $specs->{"txtQuantity$i"}; # From the 

        next unless $qty && $qty > 0;

        my $rate = get_price($log, $dbh, $variable, 'Counting', $qty);

        # Per 1000 item pricing.
        my $mrdy = $make_ready;
        my $price = $qty/1000 * $rate;
        callback::call('service_calc_end', $pid, $sid, \$mrdy, \$price);
        $price = $price + $mrdy;
           $price = $min_price if $min_price && $price < $min_price;

        return 'error' if !$price || $price < 0;

        @$specs{"txtPrice$i", "txtUnitPrice$i"}
            = format_pricing($price, $qty);

        $status = 'calculated';
    }

    return $status;
}

1;
