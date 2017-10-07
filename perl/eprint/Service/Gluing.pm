package eprint::Service::Gluing;
use strict;
use warnings;

use eprint::project qw(get_press_type);
use eprint::service qw(:common);
use sql             qw(:common);
use callback;

# The known gluing "types".
use constant GLUE_TYPES => qw(Simple Average Complex);


sub calc {
	my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    # If we're printing on a web press, try gluing on it first.
    if (get_press_type($log, $dbh, $pid) eq 'web') {
        my $status = eprint::service::get_inline_web_bindery(
            $log, $dbh, $pid, $sid, $specs, 'Gluing');

        # If we're successful, great. Otherwise try the offline stuff.
        return $status if $status eq 'calculated';
    }

    # We need to know the gluing type.
    return 'uncalculated' unless 
        grep { $specs->{rdbGluingType} eq $_ } GLUE_TYPES;

	my $make_ready = get_price($log, $dbh, $variable, 'GluingMakeReady');
	my $min_price  = get_price($log, $dbh, $variable, 'GluingMinimumCharge');
	
    my $status = 'uncalculated';
    for my $i (1..3) {
        my $qty = int $specs->{"txtQuantity$i"};

        next unless $qty && $qty > 0;

        my $rate = get_price(
            $log, $dbh, $variable, "Gluing$specs->{rdbGluingType}", $qty);

        # Pricing is per 1000 based on the gluing type.
        my $price = $qty/1000 * $rate;
        my $mrdy = $make_ready;
        callback::call('service_calc_end', $pid, $sid, \$mrdy, \$price);
        $price += $mrdy;
           $price = $min_price if $min_price && $min_price > $price;

        return 'error' unless $price && $price > 0;

        @$specs{"txtPrice$i", "txtUnitPrice$i"}
            = format_pricing($price, $qty);

        $status = 'calculated';
	}

	return $status;
}

1;
