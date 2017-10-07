package eprint::Service::Inserting;
use strict;
use Class::Struct;

use eprint::project   qw(get_print_container);
use eprint::service   qw(:common);
use eprint::equipment ();
use sql               qw(:common);
use POSIX             qw(floor);
use Data::Dumper;
use callback;

sub calc {
    my ($log, $dbh, $var, $pid, $sid, $service_type, $specs) = @_;

    my $inserts = int($$specs{'txtInsertQty'});

	# Why come up with your own ideas when you can
	# steal raymonds. Lets wrap some of the older functions
	# into nice little packages.
	local *price = sub {
        my ($equip, $service, $qty) = @_;
        get_price($log, $dbh, $var, $service, $qty, $equip);
    };
	local *fits = sub {
        my ($j, $e) = @_;
		return 1 if $j->width == 1 and $j->height == 1;
        eprint::equipment::equipment_fits(
			$log, $dbh, $e->{id}, $j->width, $j->height, $j->calliper);
    };

	local *run_price = sub {
		my $service = shift; # Number of pockets used.
		my $pockets = shift; # Number of pockets used.
		my $equip = shift; # Number of pockets used.
		my $qty = shift; # Number of pockets used.

		my $speed;

		# Does this equipment price by hour or per 1000? If no units
		# we assume per 1000.
		my $units = eprint::equipment::get_units( $log, $dbh,
			$service, $equip, $var
		);

		# Unit per hour.
		if ($units eq 'Per Hour') {
			$speed = eprint::equipment::get_specification( $log, $dbh, 
				'Run Speed', $pockets, $equip
			);
		}
		# Per thousand.
		else { $speed = 1000; }

		# Complain if we don't have a valid speed.
		die "Invalid run speed ($speed) for equipment ($equip).\n" 
			unless $speed;

		# The price per $speed of a run.
		my $rate = get_price( $log, $dbh, $var, 
			$service, $pockets, $equip
		);

		$log->debug("        BIND: Equip: $equip Pockets: $pockets Speed: $speed($units) Rate: $rate Qty: $qty");

		# The price for the run.
		return $rate * ($qty / $speed);
	};

	# Start be getting the basice specs needed for the pricing.
	my $print = get_print_container($log, $dbh, $pid);
		

	#now make a price for each quantity.
	foreach my $i ( 1 .. 3 ) {
		if ( $$specs{'txtQuantity'.$i} ) {
			my ( $p ) = get_specifications(
				$log, $dbh, $pid, $print, "hdnEquipment$i");

			my $s = $dbh->selectrow_array(q{
            		SELECT strsupplier FROM tbl_equipment WHERE strid = ?
        		}, undef, $p);

			my $qty = $$specs{'txtQuantity'.$i};


			my @jobs;
			my $j = INSERT_Job->new(
				supplier => $s,
				press    => $p,
				inserts  => $inserts,
				qty  	 => $qty,
				pid => $pid,
				sid => $sid
				);

			push @jobs, $j;

			my $total;
			foreach my $j ( @jobs ) {
				my $price = price_job( $dbh, $j, $pid);
				$total += $price->{cost};
			}
            @$specs{"txtPrice$i", "txtUnitPrice$i"}
                = format_pricing($total, $qty);
		}
	}

    return ($specs->{txtPrice1} > 0) ? 'calculated' : 'uncalculated';
}

sub price_job {
	my ($dbh, $j, $pid ) = @_;

	my @eids = map { insert_station($dbh, $_) }
					 eprint::service::valid_equipment(undef, $dbh, 'Inserting', $pid);

	# If our print Supplier is not 'House' then first check for equipment to match
	# our print supplier.
	my $price = compare_equipment( $j, grep { $_->{supplier} ne 'House' 
                                       and $_->{supplier} eq $j->supplier } @eids )
				if $j->supplier ne 'House';

	# Next try all of the House equipment.
	$price = compare_equipment( $j, grep { $_->{supplier} eq 'House' } @eids )
				if $j->supplier eq 'House' or not $price;

	# Finally try anything that is left if we still do not have a price.
	$price = compare_equipment(  $j, grep { $_->{supplier} ne 'House'
                                        and $_->{supplier} ne $j->supplier } @eids ) 
				if not $price;

	return $price;
}


sub compare_equipment{
	my ( $j,  @eids ) = @_;
	my @e_prices;
	
	foreach my $e (@eids) {
#		next unless fits($j, $e);
		my $error;
		my $total = 0;

		if ( $j->inserts ) {
			my $make_ready = price(undef,'InsertingMakeReady', undef);
			$error =  'Price not found' unless $make_ready;

			my $p = price(undef,'InsertingPocketMakeReady', undef);
			$make_ready += ($p * $j->inserts);

			$p = run_price('Inserting',$j->inserts,$e->{ref}, $j->qty);
			$error =  'Price not found' unless $p;
			callback::call('service_calc_end', $j->{pid}, $j->{sid}, \$make_ready, \$p);
			$total += $p + $make_ready;

		}


		push @e_prices, { 	
							cost            => $total,
							equipment       => $e, 
							qty             => $j->qty, 
						} unless $error;
	}

	return (sort { $a->{cost} <=> $b->{cost} } @e_prices)[0];
}

sub insert_station {
	my $dbh = shift;
	my $eid = shift;


	# BASIC INFO
    #
    # General equipment information.
    my %e = %{ $dbh->selectrow_hashref(q{
        SELECT lngindex    AS id,
               strid       AS ref,
               strname     AS name,
               strsupplier AS supplier 
        FROM tbl_equipment
        WHERE lngindex = ?
    }, undef, $eid) };
	
	# EQUIPMENT SPECIFICATIONS
    # 
    # Get the standard sizing specs. (max/min height/width).
    my $spec = $dbh->selectall_hashref(q{
        SELECT strname AS name, strvalue AS value
        FROM tbl_equipment_specifications
        WHERE strname IN ('Maximum Sheet Length', 'Maximum Sheet Width')
          AND lngequipmentindex = ?
    }, 'name', undef, $eid);
    $e{max_width}  = $spec->{'Maximum Sheet Width'}{value};
    $e{max_length} = $spec->{'Maximum Sheet Length'}{value};

	return \%e;

}

struct INSERT_Job => {
    signature => '$', # signature,  # Signature ID [optional]
    
	# Standard Fields
    width     => '$', # float,      # |
    height    => '$', # float,      # |- Before cutting dimensions
    calliper  => '$', # float,      # |
    qty       => '$', # int,        # Quantity of sheets/bound projects
    supplier  => '$', # string,     # Supplier of the printed sheet
	press     => '$', # string      # Press the project was printed on.
    note      => '$', # text,       # Freeform text of the type of cut, etc.

	# Specific to Inserting
	inserts	  => '$', # int, 	    # Number of Inserts per Package
};


1;
