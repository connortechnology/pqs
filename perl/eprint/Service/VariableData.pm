package eprint::Service::VariableData;
use strict;
use Class::Struct;

use eprint::project   qw( get_quantities get_print_container);
use eprint::service   qw(:common);
use eprint::equipment ();
use sql               qw(:common);
use POSIX             qw(floor);
use callback;
use Data::Dumper;

sub calc {
    my ($log, $dbh, $var, $pid, $sid, $service_type, $specs) = @_;
    my $status = 'uncalculated';

	# Why come up with your own ideas when you can
	# steal raymonds. Lets wrap some of the older functions
	# into nice little packages.
	local *price = sub {
        my ($equip, $service, $qty) = @_;
        my $p = get_price($log, $dbh, $var, $service, $qty, $equip);
		return $p;
    };
	local *fits = sub {
        my ($width, $height, $cal, $e) = @_;
		return 1 if $width == 1 and $height == 1;
        eprint::equipment::equipment_fits(
			$log, $dbh, $e->{id}, $width, $height, $cal);
    };


	# Start be getting the basice specs needed for the pricing.
	my $print = get_print_container($log, $dbh, $pid);
    my ( $w, $h, $cal, $sw, $sh ) = get_specifications(
        $log, $dbh, $pid, $print, 
			qw( flat_width flat_height txtStockCalliper hdnSheetSizeWidth hdnSheetSizeHeight)
    );

	# For Envelopes we do not have flat size dims, so we use the stock size instead.
	$w = $sw unless $w;
	$h = $sh unless $h;

	 my @qtys = (undef, get_quantities($log, $dbh, $pid));
		
	#now make a price for each quantity.
	foreach my $i ( 1 .. 3 ) {
		my $qty = $specs->{"txtQuantity$i"} || $qtys[$i];
		if ( $qty ) {
			my ( $p ) = get_specifications(
				$log, $dbh, $pid, $print, "hdnEquipment$i");

			
			my $s = $dbh->selectrow_array(q{
            		SELECT strsupplier FROM tbl_equipment WHERE strid = ?
        		}, undef, $p);



			my %press_imp;
		    @press_imp{qw/Rows Cols Imposition Orient/} = get_specifications( $log, $dbh, $pid, $print, qw{
				hdnImpositionRows
				hdnImpositionColumns
				hdnImposition
				hdnImageOrientation
				});


	
			my @jobs;
			my $j = VD_Job->new(
				width 	 => $w,
				height 	 => $h,
				calliper => $cal,
				qty  	 => $qty,
				supplier => $s,
				press    => $p,
				datav    => $$specs{'txtTextStreamVerificationQty'} >= 1 ? $$specs{'txtTextStreamVerificationQty'} : undef,
				press_imp => \%press_imp,
				pid => $pid,
				sid => $sid
				);

			map { my $x = $_; $x =~ s/^txt//;$x =~ s/Qty//; $j->streams($x,  int($specs->{$_})) }
					grep { m/StreamQty/ } keys %{$specs};

			push @jobs, $j;

			my $total;
			foreach my $j ( @jobs ) {
				my $price = price_job( $dbh, $j);
				$total += $price->{cost};
			}

            @$specs{"txtPrice$i", "txtUnitPrice$i"}
                = format_pricing($total, $qty);

			$status = 'calculated' if $$specs{'txtPrice'.$i} > 0;
		}
	} 

    return $status;
}

sub price_job {
	my ($dbh, $j ) = @_;

	my @eids = map { vd_station($dbh, $_) }
					 eprint::service::valid_equipment(undef, $dbh, 'VariableData');
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

sub get_impositions {
	my ( $j, $e ) = @_;
	my $imp = $j->press_imp;
	my $vd_imp;
	my @impositions;

	while ( $$imp{'Imposition'} ) {

		my $width  = ($j->width  * ($$imp{'Orient'} eq 'Vertical' ? $$imp{'Cols'} : $$imp{'Rows'}) );
		my $height = ($j->height * ($$imp{'Orient'} eq 'Vertical' ? $$imp{'Rows'} : $$imp{'Cols'}) );

		if ( fits( $width, $height, $j->calliper, $e) ) {
			$vd_imp = $$imp{'Imposition'};
			my %copy = %$imp;
			push @impositions, \%copy;
		} else {
			print STDERR " \n\n IMP NO FIT " . Dumper( $imp ) . "\n\n";
		}
		eprint::imposition::descrease_imposition( $imp );
	}
	return @impositions;
}

sub compare_equipment{
	my ( $j,  @eids ) = @_;
	my @e_prices;
	
	foreach my $e (@eids) {

		my $error;
		my $total = 0;
		my $tp = 0;
		my $ip = 0;

		foreach my $s ( keys %{ $j->streams() } ) {

			next unless $j->streams($s);

			my $p = price($e->{ref}, $s, $j->qty) * $j->streams($s);
			$error .=  " 1. Price not found $s" unless $p;

			if ( $s =~ m/TextStream/ ) {
				$tp += $p * $j->qty  / 1000;
			} else { 
				$ip += $p * $j->qty  / 1000;
			}

		}
		my $tp_mr = $tp ? price($e->{ref}, 'VariableTextStreamMakeReady') : 0;
		my $ip_mr = $ip ? price($e->{ref}, 'VariableImageStreamMakeReady') : 0;
#print STDERR "tp_mr $tp_mr ip_mr $ip_mr tp: $tp ip $ip\n";

		callback::call('service_calc_end', $j->{pid}, $j->{sid}, \$tp_mr, \$tp);
		callback::call('service_calc_end', $j->{pid}, $j->{sid}, \$ip_mr, \$ip);

		$tp += $tp_mr if $tp;
		$ip += $ip_mr if $ip;

		$total = $ip + $tp;

		if ( $j->press ne $e->{id} and $total ) {
			# Very quick and nasty guesstimate of what are click charge is going
			# to be. Really we need to actually figure out our new imp of VD and use
			# that instead.

			my $click_factor = int ( ($e->{max_width} * $e->{max_length}) / ($j->width * $j->height) );
			my $click_charge = price($e->{ref}, '1ColourImpression', $j->qty) * $j->qty / 1000;
			$click_charge /= $click_factor if $click_factor > 1;
#print STDERR "Adding click factor $click_factor, $click_charge\n";
			$total += $click_charge;

		}

		if ( $j->datav ) {
			my $p = price(undef,'VariableDataVerificationMakeReady', undef);
			$error .=  '2. Price not found' unless $p;
			$total += $p;

			$p = price(undef,'VariableDataVerification', $j->datav * $j->qty);
			$error .=  '3. Price not found' unless $p;
			$total += $p * $j->datav * $j->qty / 1000;

		}


		push @e_prices, { 	
							cost            => $total,
							textstreamcost  => $tp,
							imagestreamcost => $ip,
							equipment       => $e, 
							qty             => $j->qty, 
						} unless $error;
		print STDERR " \n\n ERROR: $error \n\n" if $error;

}

	return (sort { $a->{cost} <=> $b->{cost} } @e_prices)[0];

}

sub vd_station {
	my $dbh = shift;
	my $eid = shift;


	# BASIC INFO
    #
    # General equipment information.
    my %vd = %{ $dbh->selectrow_hashref(q{
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
    $vd{max_width}  = $spec->{'Maximum Sheet Width'}{value};
    $vd{max_length} = $spec->{'Maximum Sheet Length'}{value};

	return \%vd;

}

struct VD_Job => {
    signature => '$', # signature,  # Signature ID [optional]
    
	# Standard Fields
    width     => '$', # float,      # |
    height    => '$', # float,      # |- Before cutting dimensions
    calliper  => '$', # float,      # |
    qty       => '$', # int,        # Quantity of sheets/bound projects
    supplier  => '$', # string,     # Supplier of the printed sheet
	press     => '$', # string      # Press the project was printed on.
    note      => '$', # text,       # Freeform text of the type of cut, etc.

	# Specific to Variabe Data
	streams   => '%', 			    # hash of streams.
	datav	  => '$', # int, 	    # Data Streams to be verified

	press_imp => '$', # int, 	    # pointer to hash of Imposition info
	vd_imp 	  => '$', # int, 	    # pointer to hash of Imposition info
};

1;
