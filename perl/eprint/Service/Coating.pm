package eprint::Service::Coating;
use strict;
use Class::Struct;

use eprint::project   qw(get_print_container get_quantities);
use eprint::service   qw(:common);
use eprint::equipment ();
use sql               qw(:common);
use POSIX             qw(floor);
use Data::Dumper;
use callback;

require openprint;
require openprint::Equipment;

sub calc {
  my ($log, $dbh, $var, $pid, $sid, $service_type, $specs) = @_;
  my $status = 'uncalculated';

	my @quantities = (undef, get_quantities($log, $dbh, $pid));

	return $status unless $specs->{rdbCoatingSides};

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

	# Start be getting the basic specs needed for the pricing.
  my $print = get_print_container($log, $dbh, $pid);
  my ( $sw, $sh, $cal, $imp, $runstyle ) = get_specifications(
    $log, $dbh, $pid, $print,
    qw( hdnSheetSizeWidth hdnSheetSizeHeight txtStockCalliper hdnImposition runstyle)
  );

	# For now we will let the user override the sheet size going through the coater.
	if ( $specs->{hdnSheetSizeWidth} ) {;
		$sw = $specs->{hdnSheetSizeWidth}
	} else {
		$specs->{"hdnSheetSizeWidth"}  = $sw;
	}
	if ( $specs->{hdnSheetSizeHeight} ) {
		$sh = $specs->{hdnSheetSizeHeight}
	} else {
		$specs->{"hdnSheetSizeHeight"} = $sh;
	}

print STDERR "HAVE SHEET: W: $sw H: $sh \n";

	my $sides = int($specs->{rdbCoatingSides});
  #$sides = 2 if $runstyle =~ /(WT|WF)/;

	#now make a price for each quantity.
	foreach my $i ( 1 .. 3 ) {
    $$specs{"hdnBreakdown$i"} = '';
		my $qty = $specs->{'txtQuantity'.$i} || $quantities[$i];
		next unless $qty;

		# Get the supplier so we can give preference to suppliers
		# who are doing some of the printing.
		my $s = $dbh->selectrow_array(q{
        	SELECT strsupplier FROM tbl_equipment WHERE strid = (
				SELECT strValue FROM tbl_service_specifications
				 WHERE lngserviceindex = ?
				 AND   strname = ?
			)
       	}, undef, $print, "hdnEquipment$i");

		# Get the Coating type so we know what
		# pricing to use.
		my $type = $dbh->selectrow_array(q{ SELECT strservicetype FROM tbl_project_contents WHERE lngserviceindex = ?  }, undef, $sid);

		# This is our oversimplified version of pricing coating
		# in sheets even though our qty on the coating page is in
		# individual pieces.
		$qty /= $imp if $imp > 1;

print STDERR "HAVE SHEET 2:w: W: $sw H: $sh \n";

		my @jobs;
		my $j = COATING_Job->new(
			width 	 => $sw,
			height 	 => $sh,
			calliper => $cal,
			qty  	 => $qty,
			supplier => $s,
			type 	 => $type,
			sides    => $sides
			);
print STDERR "HAVE J: " . $j->width . " * \n";


		push @jobs, $j;

		my $total;
		foreach my $j ( @jobs ) {
			my $price = price_job( $dbh, $pid, $sid, $j);
			$total += $price->{cost};
      $$specs{"hdnBreakdown$i"} .= $$price{breakdown} if $openprint::User->is_staff();
		}

    @$specs{"txtPrice$i", "txtUnitPrice$i"} = format_pricing($total, $qty);
		$status = 'calculated' if $specs->{"txtPrice$i"} > 0;
	} # end foreach qty

  return $status;
}

sub price_job {
	my ($dbh, $pid, $sid, $j ) = @_;

	my @eids = map { coater($dbh, $_) }
					 eprint::service::valid_equipment(undef, $dbh, $j->type);

print STDERR "START PRICE JOB: 1 \n";
	# If our print Supplier is not 'House' then first check for equipment to match
	# our print supplier.
	my $price = compare_equipment($pid, $sid, $j, grep { $_->{supplier} ne 'House'
                                       and $_->{supplier} eq $j->supplier } @eids )
				if $j->supplier ne 'House';
print STDERR "START PRICE JOB: 1 \n";

	# Next try all of the House equipment.
	$price = compare_equipment( $pid, $sid, $j, grep { $_->{supplier} eq 'House' } @eids )
				if $j->supplier eq 'House' or not $price;
print STDERR "START PRICE JOB: 1 \n";

	# Finally try anything that is left if we still do not have a price.
	$price = compare_equipment($pid, $sid,  $j, grep { $_->{supplier} ne 'House'
                                        and $_->{supplier} ne $j->supplier } @eids )
				if not $price;

	return $price;
}

sub compare_equipment{
	my ( $pid, $sid, $j,  @eids ) = @_;
	my @e_prices;

	foreach my $e (@eids) {

		next unless fits($j->width, $j->height, $j->calliper, $e);
		my $error;

		my $min_charge = price($e->{ref}, $j->type.'MinimumCharge');

		my $make_ready = price($e->{ref}, $j->type.'MakeReady');


    my $service_price = price($e->{ref}, $j->type, $j->qty * $j->sides);
		my $run_price = $j->qty * $service_price * $j->sides;

		callback::call('service_calc_end', $pid, $sid, $make_ready, $run_price);

		my $total = $make_ready + $run_price;
		$total = $min_charge if $total < $min_charge;


		$error = "\n Could not Price Equipment $e->{ref} For Service: " .  $j->type
			unless $total;

		push @e_prices, {
							cost            => $total,
							equipment       => $e,
							qty             => $j->qty,
              breakdown       => sprintf('On %s MR: $%.2f RUN: %d * %d sides * $%.2f = $%.2f, total: $%.2f',
                new openprint::Equipment($e)->name(),
                $make_ready, $j->qty, $j->sides, $service_price, $run_price, $total),
						} unless $error;


	} # end foreach equipment

	return (sort { $a->{cost} <=> $b->{cost} } @e_prices)[0];

}

sub coater {
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

struct COATING_Job => {

    signature => '$', # signature,  # Signature ID [optional]

	# Standard Fields
    width     => '$', # float,      # |
    height    => '$', # float,      # |- Before cutting dimensions
    calliper  => '$', # float,      # |
    qty       => '$', # int,        # Quantity of sheets/bound projects
    supplier  => '$', # string,     # Supplier of the printed sheet
    press     => '$', # string      # Press the project was printed on.
    note      => '$', # text,       # Freeform text of the type of cut, etc.
    sides     => '$', # int,        # Number of sides to be coated.

	# Specific to COATING
	type	  => '$', # text, 		# Coating Type
};


sub display {
	my ($log, $dbh, $service_type, $pid, $sid, $specs) = @_;

	unless ($specs->{hdnSheetSizeWidth} and $specs->{hdnSheetSizeHeight} ) {
    my $print  = get_print_container($log, $dbh, $pid);

    my @fields = qw(hdnSheetSizeWidth hdnSheetSizeHeight);

    @$specs{@fields} = get_specifications($log, $dbh, $pid, $print, @fields);
  }

	return {};
}

1;
