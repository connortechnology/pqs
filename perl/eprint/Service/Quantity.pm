# A generalised n item per quantity (project) service (per 1000 pricing).
package eprint::Service::Quantity;
use strict;
use warnings;
no warnings qw(uninitialized);

use Scalar::Util qw(looks_like_number);

use eprint::service qw(:common);
use eprint::project qw(get_quantities);
use callback;

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;


    # The number of items per project.
    my $items = int $specs->{txtQuantity} || $specs->{txtHours} || 0;

    $log->debug("PRICING $service_type PID: $pid SID: $sid UNITS: $items TYPE: $service_type \n");

print STDERR "HAVE PRICING $service_type PID: $pid SID: $sid UNITS: $items TYPE: $service_type \n";


    return 'uncalculated' unless $items 
                              && looks_like_number($items) 
                              && $items > 0;

    # Get the equipment that can process us.
    my @equipment = valid_equipment(undef, $dbh, $service_type, $pid);

    die "No equipment for $service_type." unless @equipment;

    my %best; # Best price for the given quantity.

    for my $eid (@equipment) {
        my $price = calc_price(
            $log, $dbh, $variable, $service_type, $pid, $sid, $eid, $items);

        %best = (equip => $eid, price => $price) 
            if !exists $best{price} || $price < $best{price};
    }

    return 'error' unless $best{price} > 0;

    for my $i (1..3) {
        # Store the best price for the quantity.
        $specs->{"hdnEquipment$i"} = $best{equip};
        @$specs{"txtPrice$i", "txtUnitPrice$i"} 
            = format_pricing($best{price}, $items);
    }

    return 'calculated';
}


# Calculate a generalised n item per quantity (project) charge.
sub calc_price {
    my ($log, $dbh, $var, $service_type, $pid, $sid, $eid, $items) = @_;
   
    # Get the service pricing.
    my $min_price  = get_price($log, $dbh, $var, "${service_type}MinimumCharge", undef, $eid) || 0;
    my $make_ready = get_price($log, $dbh, $var, "${service_type}MakeReady",     undef, $eid) || 0;
    my $rate       = get_price($log, $dbh, $var, $service_type,                 $items, $eid);
$log->debug(" Prices MIN: $min_price MR: $make_ready RATE: $rate ");

    # Pricing is per 1000 items (potentially with per project volume
    # discounting).
    my $price = $make_ready + $items * $rate;
    callback::call('service_calc_end', $pid, $sid, \$make_ready, \$price);
    $price = $price + $make_ready;
       $price = $min_price if $min_price > $price;

    return $price;
}

1;
