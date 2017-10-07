package eprint::Service::Eyeletting;
use strict;
use warnings;

use eprint::project qw(get_quantities);
use eprint::service qw(:common);

# Price all quantities.
sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    # Get the number of tape strips to apply per project. TODO Change name,
    my $eyelets = $specs->{txtEyeletQty}; 

    return 'uncalculated' unless $eyelets && $eyelets > 0;

    my @qty = (undef, get_quantities($log, $dbh, $pid));

    my $status = 'uncalculated';
    foreach my $i (1..3) {
	 	my $qty = $specs->{"txtQuantity$i"} || $qty[$i];

        next unless $qty;

        my $price = calc_price($log, $dbh, $variable, $specs, $qty, $eyelets);

        return 'error' unless $price && $price > 0;

        @$specs{"txtPrice$i", "txtUnitPrice$i"}
            = format_pricing($price, $qty);

        $status = 'calculated';
    }

    return $status;
}

# Determine the price to process n projects with m eyelets each.
sub calc_price {
    my ($log, $dbh, $variable, $specs, $qty, $eyelets) = @_;

    my $min_price  = get_price($log, $dbh, $variable, 'EyelettingMinimumCharge');
    my $make_ready = get_price($log, $dbh, $variable, 'EyelettingMakeReady');
    my $rate       = get_price($log, $dbh, $variable, 'Eyeletting', $qty);

    # Eyeletting is per 1000 eyeletts put in.
    my $price = $make_ready + ($eyelets * $qty)/1000   * $rate;
       $price = $min_price if $min_price && $min_price > $price;

    return $price;
}

1;
