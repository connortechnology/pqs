package eprint::Service::Tipping;
use strict;
use warnings;
no warnings qw(uninitialized);

use eprint::print   ();
use eprint::project qw(get_type get_print_container);
use eprint::service qw(:common);
use sql             qw(:common);

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    # The number of glue tags the user has supplied us with.
    my $tags = int $specs->{'txtGlueTagQty'};

    return 'uncalculated' unless $tags && $tags > 0;
    
    my $status = 'uncalculated';
    foreach my $i (1 .. 3) {
        my $qty = int $specs->{"txtQuantity$i"}; 

        next unless $qty && $qty > 0;

        my $price = calc_price($log, $dbh, $variable, $qty, $tags);

		$specs->{"txtPrice$i"} = sprintf("%.2f",int($price));
		$specs->{"txtUnitPrice$i"} = sprintf("%.2f",($price/$qty));

        return 'error' unless $price && $price > 0;

        $status = 'calculated';
    }

    return $status;
}


# Calculate the price for a given project quantity for a given number of glue
# tags when performing the specialty glueing service "Tipping".
sub calc_price {
    my ($log, $dbh, $variable, $qty, $tags) = @_;
   
    # Get the service pricing. TODO Select equipment.
    my $min_price  = get_price($log, $dbh, $variable, 'TippingMinimumCharge');
    my $make_ready = get_price($log, $dbh, $variable, 'TippingMakeReady');
    my $rate       = get_price($log, $dbh, $variable, 'Tipping', $qty);

    # Pricing is per 1000 tags applied. Note: The volume discount is per
    # project processed.
    my $price = $make_ready + ($tags * $qty)/1000 * $rate;
       $price = $min_price if $min_price > $price;

    return $price;
}


1;
