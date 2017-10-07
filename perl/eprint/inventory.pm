package eprint::inventory;
use strict;

use eprint::print    ();
use eprint::project  qw(get_quantities get_weight get_press_type);
use eprint::service  qw(:common service_type); 
use eprint::customer ();
use sql              qw(:common);
use ssi;
use Data::Dumper;

sub show_inventory {
    my ( $r, $log, $dbh, $var ) = @_;
print STDERR "SHOW INVENTORY ********** \n";
	my $data = $dbh->selectall_hashref(q{
		SELECT i.id || '-' || l.id as key,
			   i.id, locationid,name, sum(lngremainingquantity) 
		FROM   tbl_inventory i, inventory_locations l 
		WHERE  i.locationid = l.id 
		AND    lngcustomerid = ?
		GROUP by locationid, i.id, l.name, key order by 1, 2
	},'key', {}, $var->{cust_id} ); 
	print STDERR "SHOW Data" , Dumper($data);
	$var->{data} = $data;
}

sub inventory_list {
    my ( $r, $log, $dbh, $variable ) = @_;

    ssi::get_start_end_dates( $log, $dbh, $variable,
            $r->param('ddmStartYear'),
            $r->param('ddmStartMonth'),
            $r->param('ddmStartDay'),
            $r->param('ddmEndYear'),
            $r->param('ddmEndMonth'),
            $r->param('ddmEndDay') );


	my $status;
	if ( $r->param('ddmStatus') eq 'Closed' ) {
		$status = 'AND lngremainingquantity = 0';
	}else {
		$status = 'AND lngremainingquantity > 0';
	}
	my $data = $dbh->selectall_arrayref(qq{
        SELECT i.lngProjectIndex, i.id as lngInventoryIndex, i.lnginventoryindex as index,
               strDescription,  lngRemainingQuantity, 
               to_char(dtmCheckInDate, 'MM/DD/YYYY') as date,
			   locationid, name, i.id::text || '-' 
							  || i.lngprojectindex::text   || '-' 
                              || name::text as key

        FROM   tbl_Inventory i , inventory_locations l, tbl_projects p
        WHERE  i.lngCustomerID = ? AND i.locationid = l.id
		AND p.lngprojectindex = i.lngprojectindex
        AND    date(dtmCheckInDate) BETWEEN date(?) AND date(?)
		AND p.strstatus = 'Complete'
		AND obsolete IS NOT true
		$status
		ORDER by 2, 1
    },{Slice=>{}} , $variable->{cust_id}, $variable->{StartDate}, $variable->{EndDate});


	my $items;

	map { 
		my ($desc) = $dbh->selectrow_array(q{
			SELECT itemid FROM inventory_specs where id = ?
		}, undef, $_->{lnginventoryindex});

print STDERR "HAVE ITEM DESC: ", Dumper($desc);
		push @{$items->{$desc}{inventory}}, $_;
		$items->{$desc}{total} += $_->{lngremainingquantity};
	} @{$data};

	map { 

		push @{$variable->{INVENTORY}}, 
		{ checkins => $items->{$_}{inventory}, 
		  id => $items->{$_}{lnginventoryindex}, 
		  total    => $items->{$_}{total},
		  itemid => $_
        } 
	} sort {lc($a) cmp lc($b)} keys  %{$items};

	print STDERR "HAVE DATA IN HASH: ", Dumper($variable->{INVENTORY});

	$variable->{OpenSelected} =   'Selected' unless $r->param('ddmStatus') eq 'Closed';
	$variable->{ClosedSelected} = 'Selected'     if $r->param('ddmStatus') eq 'Closed';

    return;
}

sub split_inventory {
	my ( $dbh, $id, $location, $qty ) = @_;

	my $rem = $dbh->selectrow_array(q{
		SELECT lngremainingquantity FROM tbl_inventory WHERE lnginventoryindex = ?
	}, undef, $id);

	return 0  if $qty > $rem;
	
	my $split = $dbh->prepare(q{ 
		UPDATE tbl_inventory SET lngremainingquantity = lngremainingquantity - ? 
		WHERE  lnginventoryindex = ? 
	});
	$split->execute($qty, $id);

	my @data = $dbh->selectrow_array(q{
		SELECT 	*, nextval('lngInventoryIndex_seq') FROM tbl_inventory WHERE lnginventoryindex = ?
	}, undef, $id);

	$data[0] = pop @data;
	$data[6] = $data[7] = $qty;
	$data[8] = $location;

	my $ins = $dbh->prepare(q{
		INSERT INTO tbl_inventory  values ( ?,?,?, ?,?,?, ?,?,?, ?,?,?, ?,?,?, ? )
	});

	$ins->execute(@data);

	return 1;
	

}

sub revise_inventory {
	my ( $dbh, @ids ) = @_;
	my $sth = $dbh->prepare(q{
		UPDATE tbl_inventory SET revised = true WHERE lnginventoryindex = ?
	});
	map { $sth->execute($_) } @ids;
}

sub obsolete_inventory {
	my ( $dbh, @ids ) = @_;
print STDERR "OBS INV *************** \n";
	my $sth = $dbh->prepare(q{
		UPDATE tbl_inventory SET obsolete = true, obsolete_qty = lngremainingquantity, 
					 obsolete_date = now(), lngremainingquantity = 0 
		WHERE lnginventoryindex = ?
	});
		
	map { $sth->execute($_) } @ids;
}


sub inventory_details{
    my ( $r, $log, $dbh, $var ) = @_;


	my $id = $r->param('ID');



	if ( $r->param('split_id') ) {
		return misc::error( $log, $dbh, $var, 'Error', 'Inventory Could not be split')
		unless split_inventory( $dbh, $r->param('split_id'), 
							    $r->param('split_location'),
						        $r->param('split_qty')
		);

	}
	if ( $r->param('revised') ) {
		revise_inventory( $dbh, $r->param('revised') );
	}
	if ( $r->param('obsolete') || $r->param('revised') ) {
		obsolete_inventory( $dbh, $r->param('obsolete'), $r->param('revised') );
	}

	if ( $r->param('ddmInventoryID') ) {
		if ( $r->param('ddmInventoryID') != $r->param('OldID') && $r->param('OldID') ) {

			my $inven    = $dbh->prepare(q{ UPDATE tbl_inventory SET id = ? WHERE id = ?  });
			$inven->execute( $r->param('ddmInventoryID'),  $r->param('OldID') );

			$id = $r->param('ddmInventoryID');

		#	my $specs = $dbh->prepare(q{ UPDATE inventory_specs SET id = ? WHERE id = ?  });
		#	$specs->execute( $r->param('ddmInventoryID'),  $r->param('OldID') );

		} else { 
			$id = $r->param('ddmInventoryID');
print STDERR "UPDATE INVENTORY SPECS: $id \n";
map {
	print STDERR "HAVE SPEC: $_ = ". $r->param($_) . "\n";
} $r->param();

			my $have_specs = $dbh->selectrow_array(q{ 
				SELECT id FROM inventory_specs where id = ?
			}, undef, $id);

			my $sth = $have_specs 
					? $dbh->prepare(q{	
							UPDATE inventory_specs 
							SET itemid = ? , reorder_notify = ?, unit_price = ?,
							reorder_notify_max = ?, notes = ?
							WHERE id = ?
					  })
					: $dbh->prepare(q{ 
							INSERT into inventory_specs 
							( itemid, reorder_notify, unit_price, reorder_notify_max, notes, id) 
							VALUES ( ?,?,?,?,?,?)
					  });

			$sth->execute(	$r->param('ItemID'), 
							$r->param('reorder_notify') || '0',  
						  	$r->param('unit_price')     || 0, 
							$r->param('reorder_notify_max') || 0,
							$r->param('notes'),
							$id
			);
		}

	}


	if ( $r->param('btnFunction') eq 'Submit' ) {
		my $sth = $dbh->prepare(q{ 
			UPDATE tbl_inventory SET unit_price = ? WHERE lnginventoryindex = ?  
		});
		map {
			my $id = substr($_,11);
			my $p = $r->param($_);
			$sth->execute($p, $id);
		} grep { /unit_price/ } $r->param();
	}

	my $sql = qq{SELECT Distinct id, id || ' - ' || strdescription 
				 FROM tbl_inventory
			     WHERE lngcustomerid =  $var->{cust_id} };
	$var->{ddmInventoryID} = ssi::fill_drop_down($log, $dbh, $sql, $id);

	my $locations = qq{SELECT id, name FROM inventory_locations Order By name };

	my $data = $dbh->selectall_hashref(qq{
        SELECT i.lngProjectIndex as pid, lngInventoryIndex as id, 
               lngRemainingQuantity as qty, 
				obsolete, revised, unit_price,
			   locationid, name,    i.lngprojectindex::text   || '-' 
                                 || name::text || '-' 
								 || lnginventoryindex::text as key

        FROM   tbl_Inventory i, inventory_locations l
        WHERE  i.locationid = l.id
		AND    i.id = ?
		AND	   lngremainingquantity > 0
		AND	   complete
    },'key', {} , $id);

	my @sorted;
	my $qty_total;
	map {
			my $a = $_;
			$data->{$a}->{locations} = ssi::fill_drop_down($log, $dbh, $locations,
									   $data->{$a}->{locationid});
			push @sorted, $data->{$a};
			$qty_total += $data->{$a}->{qty};
	} sort keys %{$data};

	$var->{qty_total} = $qty_total;
	$var->{INVENTORY} = \@sorted ;
	$var->{locations} =  ssi::fill_drop_down($log, $dbh, $locations);

	my $specs = $dbh->selectrow_hashref(q{
		SELECT * from inventory_specs WHERE id = ?
	}, {}, $id);

	map {$var->{$_} = $specs->{$_} } keys %{$specs};
	$var->{id} = $id;
#	print STDERR Dumper($var);

		
}

sub checkout_list {
    my ( $r, $log, $dbh, $variable ) = @_;
    my $inventory_index = $r->param('InventoryIndex');
    $_ = "SELECT lngProjectIndex, lngOrderID, lngCheckOutQuantity, 
                 to_char(dtmCheckOutDate, 'MM/DD/YYYY'), 
                 to_char(dtmCheckOutDate, 'MM/DD/YYYY') 
          FROM tbl_Inventory_CheckOut 
          WHERE lngInventoryIndex='$inventory_index'
          ORDER BY lngProjectIndex DESC";
    @{$$variable{'PROJECTS'}} = sql_statement( $log, $dbh, $_ );
    return;
}

sub make_checkout_project {
    my ( $r, $log, $dbh, $cookie, $variable )  = @_;

print STDERR "MAKE CHECKOUT PROJECT \n";

    my $qty             = $r->param('CheckOutQty');


    my $inventory_index = $r->param('InventoryIndex');
	my $itemid;

	if ( $r->param('InventoryID') ) {
		$itemid = $r->param('InventoryID');
		$inventory_index = scalar $dbh->selectrow_array(q{
			SELECT min(lnginventoryindex) FROM tbl_inventory WHERE id = ?
		}, undef, $r->param('InventoryID'));
	}

print STDERR "MAKE CHECKOUT PROJECT -- $inventory_index \n";

    my ($inv_qty, $pid) = $dbh->selectrow_array(q{
        SELECT lngRemainingQuantity, lngProjectIndex 
        FROM tbl_Inventory 
        WHERE lngInventoryIndex = ?
    }, undef, $inventory_index);

print STDERR "CHECK 2 $qty - $inv_qty PID: $pid \n";
    return unless $qty <= $inv_qty or $itemid;

    my $checkout = $dbh->selectrow_array(q{
        SELECT MAX(lngCheckOutIndex)
        FROM tbl_Inventory_CheckOut 
        WHERE lngInventoryIndex = ?
    }, undef, $inventory_index);

	$checkout++;

    my $press_type = get_press_type($log, $dbh, $pid);
	my $ref = $dbh->selectrow_array(q{
		SELECT strprojectreference FROM tbl_projects WHERE lngprojectindex = ?
	}, undef, $pid);

print STDERR "CHECK 3 \n";

	my $projref = "Inventory CheckOut - $ref";
    my $projtype = '74';

    my $new_pid = eprint::print_project::create_process($r, $log, $dbh, $cookie, $variable, [$qty], 
														    undef, $projref, $press_type, $projtype);

    my $co_sid 	= eprint::print_project::insert_service( $log, $dbh, $new_pid, 'InventoryCheckOut');

print STDERR "CHECK 4 \n";
    eprint::service::insert_service_specs( $log, $dbh, $new_pid, $co_sid, 
            txtCheckOutQty       => $qty,
            CheckOutIndex        => $checkout,
            OriginalProjectIndex => $pid,
            InventoryIndex       => $inventory_index,
            InventoryID          => $itemid,
            InventoryLocation    => $r->param('location')
    );

    $variable->{Redirect} = '';
print STDERR "END MAKE CHECKOUT PROJECT -- $inventory_index \n";

    return $new_pid;
}

#delete an inventory item and all checkouts associated with it
sub delete_inventory {
  my ($log, $dbh, $id) = @_;

  $id =~ tr/0-9//cd;

  # die "Invalid order ID." unless $id;
  return unless $id;

  $dbh->do("delete from tbl_inventory_checkout where lnginventoryindex = ?", undef, $id);
  $dbh->do("delete from tbl_inventory where lnginventoryindex = ?", undef, $id);
}

#delete all inventory and checkouts related to a customer
sub delete_by_customer {
  my ($log, $dbh, $id) = @_;

  $id =~ tr/0-9//cd;

  # die "Invalid order ID." unless $id;
  return unless $id;

  my $items = $dbh->selectcol_arrayref("select lnginventoryindex from tbl_inventory where lngcustomerid = ?", undef, $id);

  for my $item (@$items) {
    delete_inventory($log, $dbh, $item);
  }
}

#delete all inventory and checkouts related to a project
sub delete_by_project {
  my ($log, $dbh, $id) = @_;

  $id =~ tr/0-9//cd;

  # die "Invalid order ID." unless $id;
  return unless $id;

  my $items = $dbh->selectcol_arrayref("select lnginventoryindex from tbl_inventory where lngprojectindex = ?", undef, $id);

  for my $item (@$items) {
    delete_inventory($log, $dbh, $item);
  }
  $dbh->do("delete from tbl_inventory_checkout where lngprojectindex = ?", undef, $id);
}

#delete all iventory checkouts related to an order
sub delete_by_order {
  my ($log, $dbh, $id) = @_;

  $id =~ tr/0-9//cd;

  # die "Invalid order ID." unless $id;
  return unless $id;

  $dbh->do("delete from tbl_inventory_checkout where lngorderid = ?", undef, $id);
}

1;
