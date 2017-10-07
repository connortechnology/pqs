package eprint::Service::Inventory;
use strict;

use eprint::print    ();
use eprint::project  qw(get_quantities get_weight get_press_type);
use eprint::service  qw(:common service_type); 
use eprint::customer ();
use sql              qw(:common);
use ssi;
use callback;

sub display {
 	my ($log, $dbh, $service_type, $pid, $sid, $specs, $var) = @_;

	if (  $service_type =~ /CheckOut$/i ) {
		return {}
	} else {
		my @qty = (undef, get_quantities($log, $dbh, $pid));

		foreach my $i (1..3) {
			next unless defined $qty[$i] and $qty[$i] > 0;
			$var->{"txtInventoryQty$i"} = $specs->{"txtInventoryQty.$i"} || $qty[$i];
		}

			my $sql = qq{SELECT Distinct id, id || ' - ' || strdescription 
				 FROM tbl_inventory
			     WHERE lngcustomerid =  $var->{cust_id} };
			$var->{OPTIONS_ItemID} = ssi::fill_drop_down($log, $dbh, $sql, $specs->{ItemID});

		return {};
	}
}

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    my $func = $service_type =~ /CheckOut$/i 
        ? \&calc_checkout 
        : \&calc_checkin;

    return $func->(@_);
}

sub calc_checkin {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;
    
    my $unit_weight = get_weight($log, $dbh, $pid);
    
    # we need to store the weight in the new project so that we know how heavy
    # it is when we check it out.  if we change get_weight to store the weight
    # whenever it gets one, then we'll only have to look the weight up when we
    # make a new checkout.
    my $make_ready = get_price($log, $dbh, $variable, 'InventoryCheckInMakeReady', undef, undef);

	my $status = 'uncalculated';
    
    my @qty = (undef, get_quantities($log, $dbh, $pid));
    foreach my $i (1..3) {
        next unless defined $qty[$i] and $qty[$i] > 0;

        # If the user hasn't yet defined a partial quantity they want to
        # inventory, we'll assume the entire project quantity.
       #my $qty = $$specs{"txtInventoryQty$i"} = $$specs{"txtInventoryQty$i"} || $qty[$i];
       my $qty = $$specs{"txtInventoryQty$i"};


		$status = 'calculated' if $qty;

print STDERR "QTY FOR $i: $qty \n";
        
        # The total weight we'll be storing.
        my $weight = $unit_weight * $qty;
        
        # The storage rate is volume discounted by weight.
        my $storage_rate = get_price($log, $dbh, $variable, 'InventoryCheckInCharge', $weight, undef);
        my $price = ($weight * $storage_rate);
        my $mkrdy = $make_ready;
        callback::call('service_calc_end', $pid, $sid, \$mkrdy, \$price);
        $price += $mkrdy;

        @$specs{"txtPrice$i", "txtUnitPrice$i"}
            = format_pricing($price, $qty);
    }

	$specs->{txtProjectWeight} = $unit_weight;
    $specs->{txtPrice}     = $specs->{txtPrice1};
    $specs->{txtUnitPrice} = $specs->{txtUnitPrice1};

use Data::Dumper;
print STDERR "Inventory Specs " ,  Dumper($specs, $status);

#    return $specs->{ItemID} ? 'calculated' : 'uncalculated'; # TODO: We should not just assume this.

    return $status;
}

sub calc_checkout {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    my ( $weight, $inv_qty, $storage_days, $itemid ) =
        $dbh->selectrow_array(q{
            SELECT dblProjectWeight, lngRemainingquantity, date(NOW())-date(dtmCheckInDate), id
            FROM tbl_Inventory 
            WHERE lngInventoryIndex = ?
        }, {}, $specs->{InventoryIndex});

	my $id = $specs->{InventoryIndex};

	my $unit_price = $dbh->selectrow_array(q{
		SELECT s.unit_price FROM inventory_specs s, tbl_inventory i WHERE i.lnginventoryindex = ? and i.id = s.id
	}, undef, $specs->{InventoryIndex});

print STDERR "CALC CHECKOUT UP: $unit_price FOR: $id \n";

	my $price;
	my $qty = $$specs{'txtCheckOutQty'};

	if ( $unit_price ) {
		$price = $unit_price * $qty;
	} else {
			$storage_days = 1 unless $storage_days;

			if ( $specs->{InventoryID} ) {
				$inv_qty = $dbh->selectrow_array(q{
					SELECT SUM(lngremainingquantity) FROM tbl_inventory WHERE id = ? AND locationid = ?
				}, undef, $specs->{InventoryID}, $specs->{InventoryLocation});
			}

			if ( $qty > $inv_qty ) {
				$specs->{error} = "Checkout Quantity exceeds Quantity Available ( $inv_qty ) ";
				return 'uncalculated';
			}

			my $make_ready   = get_price($log, $dbh, $variable, 'InventoryMakeReady');
			my $storage_rate = get_price($log, $dbh, $variable, 'InventoryStorageCharge', $weight * $qty);

			$price = $make_ready + ($weight * $qty * $storage_rate * $storage_days );
	}
    
    @$specs{"txtPrice", "txtUnitPrice"} = format_pricing($price, $qty);

	$specs->{InventoryID} = $itemid;

    $specs->{txtPrice1}     = $specs->{txtPrice};
    $specs->{txtUnitPrice1} = $specs->{txtUnitPrice};

    return 'calculated';
}




1;
