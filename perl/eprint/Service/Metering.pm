# A generalised n item per quantity (project) service (per 1000 pricing).
package eprint::Service::Metering;
use strict;
use warnings;
no warnings qw(uninitialized);

use Scalar::Util qw(looks_like_number);

use ssi             qw(make_drop_down);
use eprint::service qw(:common);
use eprint::project   qw(get_print_container get_quantities);
use eprint::equipment ();
use Data::Dumper;
use session;

sub display {

	my ($self, $dbh, $service_type, $pid, $sid, $specs) = @_;
	my $log;

	my $project_type = eprint::project::get_type($log, $dbh, $pid);
print STDERR "HAVE PT: $project_type \n";

	my $types = $project_type eq 'Envelopes' ?  q{'Metering', 'Sealing', 'MeteringSeal', 'HandMeter'}
											 :  q{'Metering', 'HandMeter'};
	
	my $data = $dbh->selectcol_arrayref(qq{
        SELECT strid, strname
        FROM tbl_services
        WHERE strid in ($types)
		ORDER by strname
    }, { Columns => [1, 2] });

    return { 
        ddmService => make_drop_down($data),
    }



}

sub fits {
  my ($dbh, $pid, @equipment) = @_;
  my $log = session::log;
  my %temp = {};
  print STDERR "START FITS: @equipment \n";

  # Start be getting the basice specs needed for the pricing.
  my $print = get_print_container($log, $dbh, $pid);

  print STDERR "START FITS 2: @equipment \n";
  my (  $w, $h, $cal ) = get_specifications( $log, $dbh, $pid, $print,
    qw( final_width final_height txtStockCalliper )
  );

  $cal = eprint::project::get_finished_calliper( $log, $dbh, \%temp, $pid);

  my @valid;
  print STDERR "LOOP EQUIPMENT \n";
  foreach my $e (@equipment) {
    print STDERR "CHECK FITS: $e, $w, $h, $cal \n";
    next unless eprint::equipment::equipment_fits($log, $dbh, $e, $w, $h, $cal);
    print STDERR "PASS CHECK FITS: $e \n";
    push @valid, $e
  }
  return @valid;
}

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;


# Get the equipment that can process us.
#    my @equipment = valid_equipment(undef, $dbh, $service_type);
    my @equipment = fits($dbh, $pid, valid_equipment(undef, $dbh, $service_type));

    die "No equipment for $service_type." unless @equipment;

    my %best; # Best price for the given quantity.

	my @qtys = (undef, get_quantities($log, $dbh, $pid));


	my $service = $specs->{ddmService};

	return 'uncalculated' unless $service;

print STDERR "PRICE SERVICE: $service \n";

    for my $i (1..3) {

		my $qty = $specs->{"txtQuantity$i"} || $qtys[$i];
    	for my $eid (@equipment) {
        	my $price = calc_price(
            	$log, $dbh, $variable, $service, $eid, $qty);

        	%best = (equip => $eid, "price$i" => $price) 
            	if !exists $best{"price$i"} || $price < $best{"price$i"};
    	}

        # Store the best price for the quantity.
        $specs->{"hdnEquipment$i"} = $best{equip};
		$specs->{"txtQuantity$i"} = $qty;
        @$specs{"txtPrice$i", "txtUnitPrice$i"} 
			= format_pricing($best{"price$i"}, $qty);
    }

    return 'calculated';
}


# Calculate a generalised n item per quantity (project) charge.
sub calc_price {
    my ($log, $dbh, $var, $service, $eid, $items) = @_;
   

    # Get the service pricing.
    my $min_price  = get_price($log, $dbh, $var, "MeteringMinimumCharge", undef, $eid) || 0;
    my $make_ready = get_price($log, $dbh, $var, "MeteringMakeReady",     undef, $eid) || 0;
    my $rate       = get_price($log, $dbh, $var, $service,                 $items, $eid);

    # Pricing is per 1000 items (potentially with per project volume
    # discounting).
    my $price = $make_ready + ($items / 1000 * $rate);
       $price = $min_price if $min_price > $price;

    return $price;
}

1;
