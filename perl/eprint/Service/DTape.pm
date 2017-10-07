package eprint::Service::DTape;
use strict;
use warnings;

use eprint::project qw(get_quantities);
use eprint::service qw(:common);
use callback;

# Price all quantities.
sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    # Get the number of tape strips to apply per project. TODO Change name,
    my $strips = int $specs->{txtHoleQty}; 

    return 'uncalculated' unless $strips && $strips > 0;

    my @qty = (undef, get_quantities($log, $dbh, $pid));

    my $status = 'uncalculated';
    foreach my $i (1..3) {
		my $qty = $specs->{"txtQuantity$i"} || $qty[$i];
        next unless $qty[$i] && $qty[$i] > 0;

        my $price = calc_price($log, $dbh, $variable, $specs, $pid, $sid, $qty, $strips);

        return 'error' unless $price && $price > 0;

        @$specs{"txtPrice$i", "txtUnitPrice$i"}
            = format_pricing($price, $qty);

        $status = 'calculated';
    }

    return $status;
}

# Determine the price to tape n projects with m strips each.
sub calc_price {
    my ($log, $dbh, $variable, $specs, $pid, $sid, $qty, $strips) = @_;

    my $min_price  = get_price($log, $dbh, $variable, 'DTapeMinimumCharge');
    my $make_ready = get_price($log, $dbh, $variable, 'DTapeMakeReady');
    my $rate       = get_price($log, $dbh, $variable, 'DTape', $qty * $strips);
   
    # D-taping is changed per strip, with discounting on n-m strips per
    # project.
    my $price = $qty * $strips * $rate;
    callback::call('service_calc_end', $pid, $sid, \$make_ready, \$price);
    $price += $make_ready;
       $price = $min_price if $min_price && $min_price > $price;

    return $price;
}

1;
