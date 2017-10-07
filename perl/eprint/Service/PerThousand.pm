# A generalised n item per quantity (project) service (per 1000 pricing).
package eprint::Service::PerThousand;
use strict;
use warnings;
no warnings qw(uninitialized);

use Scalar::Util qw(looks_like_number);

use eprint::service qw(:common);
use eprint::project qw(get_quantities);
use ssi             qw( make_drop_down material_drop_down);
use PQS::model::materials;
use PQS::model::service;

sub necessary {
    my ($log, $dbh, $pid, $service_type) = @_;

	if ( $service_type eq 'SlipSheets' ) {
		my $book = eprint::project::get_print_container($log, $dbh, $pid);

		return eprint::service::get_specifications($log, $dbh, $pid, $book, qw(SlipSheets));
	} else {
		return 0;
	}

}




sub display {
	my ($self,  $dbh, $service_type, $pid, $sid, $specs) = @_;

    return {
		ddmCover => material_drop_down(undef, $dbh, 'Cover') 
	}

}

sub calc {
  my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

  # Get the equipment that can process us.
  my @equipment = valid_equipment(undef, $dbh, $service_type);

  die "No equipment for $service_type." unless @equipment;

  my %best; # Best price for the given quantity.

    my @qtys = (undef, get_quantities($log, $dbh, $pid));


  for my $i (1..3) {
    my $qty = $specs->{"txtQuantity$i"} || $qtys[$i];
    for my $eid (@equipment) {
      my $price = calc_price(
            $log, $dbh, $variable, $service_type, $eid, $qty, $specs);

      %best = (equip => $eid, "price$i" => $price)
            if !exists $best{"price$i"} || $price < $best{"price$i"};
    }

    if (my $fc = $specs->{ddmFrontCover}) {
      my $mat = PQS::model::materials::material_by_strid($fc);
      PQS::model::service::set_material_estimate($qty, undef, $sid, $mat->{lngindex}, $i);
    }

    if (my $bc = $specs->{ddmBackCover}) {
      my $mat = PQS::model::materials::material_by_strid($bc);
      PQS::model::service::set_material_estimate($qty, undef, $sid, $mat->{lngindex}, $i);
    }

    # Store the best price for the quantity.
    $specs->{"hdnEquipment$i"} = $best{equip};
    $specs->{"txtQuantity$i"}  = $qty;
    @$specs{"txtPrice$i", "txtUnitPrice$i"} = format_pricing($best{"price$i"}, $qty);
  }

  return 'calculated';
}


# Calculate a generalised n item per quantity (project) charge.
sub calc_price {
    my ($log, $dbh, $var, $service_type, $eid, $items, $specs) = @_;
   
    # Get the service pricing.
    my $min_price  = get_price($log, $dbh, $var, "${service_type}MinimumCharge", undef, $eid) || 0;
    my $make_ready = get_price($log, $dbh, $var, "${service_type}MakeReady",     undef, $eid) || 0;
    my $rate       = get_price($log, $dbh, $var, $service_type,                 $items, $eid);

	my $fc = $specs->{ddmFrontCover} || undef;
	my $bc = $specs->{ddmBackCover}  || undef;
	my $mat_price =  $fc ? eprint::material::get_price( $log, $dbh, $var, $fc, $items ) : 0;
	$mat_price +=    $bc ? eprint::material::get_price( $log, $dbh, $var, $bc, $items ) : 0;

    # Pricing is per 1000 items (potentially with per project volume
    # discounting).
    my $price = $make_ready + ($items / 1000 * $rate);
	   $price += $mat_price * $items;
       $price = $min_price if $min_price > $price;

    return $price;
}

1;
