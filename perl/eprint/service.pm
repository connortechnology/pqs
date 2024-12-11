package eprint::service;
use strict;
use warnings;

no warnings qw(uninitialized);

use base qw(Exporter);

# The canonical list of project service status codes.
use constant COMPLETE => (
    'Waiting For Files', 'In Production', 'Complete',  'calculated', 'Pending Deposit' );

use constant STATUSES => ( COMPLETE,
    'uncalculated',  'dependent', 'error', 'Canceled'   );

# Project service need levels.
use constant {
    NOT_NEEDED => 0,
    SUGGESTED  => 1,
    NEEDED     => 2,
};

# Project service specifications, pricing, and equipment.
my @specs = qw( insert_service_spec   get_specifications
                insert_service_specs  get_specifications_pairs
                get_price             valid_equipment          );
# Project service statuses and dependencies.
my @status = qw( get_status  recalc_dependencies
                 set_status 
                 STATUSES    COMPLETE
                 NOT_NEEDED  SUGGESTED NEEDED );

# Need levels for necessary() function calls.
my @need = qw( NOT_NEEDED SUGGESTED NEEDED get_need set_need);

# Other ones.
my @other = qw( service_type     in_project     
                load_pricing     format_pricing
                get_service_url  get_service_full_price
                                 valid_equipment_dropdown
);

# Generic service calculation.
my @calc = qw(load_service_type price save get_specs);

our @EXPORT_OK = (@specs, @status, @other, @need, @calc);
our %EXPORT_TAGS = (
    common => [ @specs, qw(get_status set_status), 'format_pricing' ],
    specs  => \@specs,
    status => \@status,
    need   => \@need,
    calc   => \@calc,
    all    => \@EXPORT_OK,
);


use Data::Dumper;
use Scalar::Util          qw(looks_like_number);
use POSIX                 qw(ceil floor);
use List::Util            qw(first sum);
use Symbol                qw(qualify_to_ref);

use PQS::Constants;
use sql               qw(:common);
use ssi               qw(make_drop_down);
use eprint::equipment ();
use eprint::material  ();
use PQS::Object::project;

require eprint::customer;

our %cache; # TEMP: Store localized pricing for equipment types per req.

# Given a project service ID return the service type info; ID and name if
# array context just id if scalar context.
sub get_type {
    my ($log, $dbh, $sid) = @_;
    return undef unless $sid;
    
    my $sth = $dbh->prepare_cached(q{
        SELECT t.strid, t.strname
        FROM tbl_service_types t, tbl_project_contents c
        WHERE c.strservicetype  = t.strid
          AND c.lngserviceindex = ?
    });
    my @info = $dbh->selectrow_array($sth, undef, $sid);
    return wantarray ? @info : shift @info;
}

# Returns the service type when given an service specifaction id.
sub service_type {

    # TODO : This currently returns a string, eventually it should use
    # overloading to return the numeric id or string based on context.

    return scalar shift->selectrow_array(q{
        SELECT strservicetype
        FROM tbl_project_contents
        WHERE lngserviceindex = ?
    }, undef, shift);
}

sub common_name {
	my $dbh = session::dbh;
	my $sid = shift;
	my ($name, $strid) =  $dbh->selectrow_array(q{SELECT strname, strid FROM tbl_service_types WHERE strid = 
		(SELECT strservicetype FROM tbl_project_contents WHERE lngserviceindex = ? )
	}, undef, $sid);

	my %modify;

	$modify{Printing} = sub { 
		my $desc = get_spec($sid, 'txtServiceDescription');
		$name .= " - $desc" if $desc;
	};

	&{$modify{Printing}};
	
	die("Could not identify service name for SID: $sid \n") unless $name;
	return $name;
	
}

sub in_project {
    my $dbh = shift;
    return scalar $dbh->selectrow_array(q{
        SELECT lngprojectindex
        FROM tbl_project_contents
        WHERE lngserviceindex = ?
    }, undef, shift);
}

# Create a two level hash of equipment, each with all it's service pricing by
# name. Ranged service prices are coderefs taking a range lookup.
sub load_pricing {
    my ($dbh, $cid, @types) = @_;

    # Get the customer discount to apply to any applicable pricing.
    my $discount = eprint::customer::get_discount($dbh, $cid);

    # Equipment types needed for this request.
    my $types = join ',', map { $dbh->quote($_) } @types;

    # Get the pricing of for the combination of all services (of service
    # types) and equipment of the given type. 
    my $sth = $dbh->prepare(qq{
        SELECT s.strid, e.lngindex, p.lngmin, p.lngmax, p.dblprice, 
               (CASE WHEN p.ysndiscountable = 'Y' THEN 1 ELSE 0 END) 
        FROM tbl_services s, tbl_service_prices p, 
             tbl_equipment e, equipment_type_service t, tbl_customer c
        WHERE s.lngindex       = p.lngserviceindex
          AND s.lngindex       = t.service
          AND e.lngindex       = p.lngequipmentindex
          AND p.lnglistindex   = c.lngpricelist
          AND c.lngcustomerid  = ?
          AND e.strtype IN ($types)
    });
    $sth->execute($cid);

    my ($service, $eid, $min, $max, $price, $discountable);
    $sth->bind_columns(\$service, \$eid, \$min, \$max, \$price, \$discountable);

    my (%pricing, %ranged);
    while ($sth->fetch) {
        # Apply the customer's discount if applicable.
        $price *= 1 + ($discount/100) if $discount && $discountable;

        # If min or max is defined we have a ranged spec. 
        if (defined $min or defined $max) {
            $pricing{$eid}{$service} = [] unless exists $pricing{$eid}{$service};

            # Push a range onto the list (we'll sort them later).
            push @{ $pricing{$eid}{$service} }, [$min, $max, $price];

            # Keep a unique list of the ranged ones so we can convert their
            # data to lookup functions.
            $ranged{"$eid~$service"} = undef;
        }
        # Or it's just an attribute.
        else { 
            $pricing{$eid}{$service} = $price;
        }
    }

    # Now that our ranged specs have all their data, we need to turn them into
    # functions that can do lookups on their data.
    for my $key (keys %ranged) {
        my ($eid, $service) = split /~/, $key;
        $pricing{$eid}{$service} 
            = eprint::equipment::create_range_lookup( @{ $pricing{$eid}{$service} } );
    }

    return %pricing;
}

sub get_price {
    my ($log, $dbh, $variable, $service, $range, $equipment, $subservice) = @_;
    # The cache doesn't handle subservices.
    if (%cache && !$subservice && $equipment && exists $cache{$equipment}) {

        # If the service doesn't exist for the equipment it's not priced.
        return unless exists $cache{$equipment}{$service};

        my $price = $cache{$equipment}{$service};

        if (ref $price eq 'CODE') {
            # If the price is a coderef (for range lookup) and the user didn't
            # pass us a lookup value we can't do anything.
            return unless defined $range && looks_like_number($range);

            $price = $price->($range);
        }
        return $price;
   }

    my $index = $dbh->selectrow_array(q{
        SELECT lngindex FROM tbl_services WHERE strid = ?
    }, {}, $service);
    return unless $index;


    my $eid = !defined $equipment   ? undef
            : $equipment =~ /^\d+$/ ? $equipment
            : $equipment ne ''      ? eprint::equipment::get_index_by_id(
                                         $log, $dbh, $equipment ) 
            :                         undef;

    # filter invalid equipment
    return if $equipment && !$eid;

    return scalar price_item($dbh, $variable->{cust_id}, $index, $range, $eid, $subservice);
}

# Get the pricing (including units and equipment priced on in list context)
# for a given service applying all customer/pricelist discounts.
sub price_item {
    my ($dbh, $cid, $service, $range, $eid, $subservice) = @_;
    my ($clause, @args);
    if (defined $eid && $eid) {
        $clause .= q{ AND lngequipmentindex = ? };
        push @args, $eid;
    }

    # TODO make sure subservice is numeric
    if (defined $subservice) {
        $clause .= q{ AND lngsubservicetype = ? };
        push @args, $subservice;
    }

    # If a quantity is supplied check it's in the range Note: ranges are
    # neither validated nor constrained so you can get 'interesting' results. 
    if (defined $range && $range ne '' && $range >= 0) {
        $range = int $range;

        $clause .= q{ 
            AND (? >= lngmin OR lngmin IS NULL) 
            AND (? <= lngmax OR lngmax IS NULL)
        };
        push @args, $range, $range;
    }

    my $sth = $dbh->prepare_cached(qq{ 
         SELECT dblprice, 
                strunits, 
                lngequipmentindex,
                (CASE WHEN ysndiscountable = 'Y' THEN 1 ELSE 0 END)
          FROM tbl_service_prices p, tbl_customer c
          WHERE lngserviceindex = ?
            AND p.lnglistindex  = c.lngpricelist
            AND c.lngcustomerid = ?
            $clause
          ORDER BY lngmin
          LIMIT 1
    });


    my ($price, $units, $equip, $discountable) 
        = $dbh->selectrow_array($sth, undef, $service, $cid, @args);

    # Apply the customer's discount if applicable.
    if ($discountable) {
        my $discount 
            = eprint::customer::get_discount($dbh, $cid);

        $price *= 1 + ($discount/100) if $discount;
    }

    return wantarray ? ($price, $units, $equip) : $price;
}



# Return a list of equipment that offers the given service type.
sub valid_equipment {
	my ($log, $dbh, $service_type, $pid) = @_;

  #my $specs = shift;
	use session;
	my $r = session::r;
	my $specs;
	map { $specs->{$_} = $r->param($_) } $r->param();

	print STDERR "DUMPER SPECS: " , Dumper($specs, $specs->{chkOverrideEquipment1});

	my $override;
	if ( $specs->{chkOverrideEquipment1} ) {
		$override = $specs->{ddmEquipment1};
	print STDERR " OVERRRIDE FOUND:  $override \n";
	}

	my $over_sql;
	if ( $override ) {
		$over_sql = " AND eq.lngindex = $override ";
	}

	print STDERR "HAVE OVERRRIDE:  $override \n";

	my $sql = qq{
		SELECT equipment 
        FROM service_type_equipment e, tbl_service_types t, tbl_equipment eq
        WHERE t.lngindex = e.service_type AND equipment = eq.lngindex 
        AND t.strid=?
	$over_sql
	};

	my $rfq_only = $pid ? $dbh->selectrow_array('SELECT rfq_only FROM tbl_projects WHERE lngprojectindex=?', undef, $pid) : undef;
	$sql .= q{ AND eq.strsupplier <> 'RFQ Required'} unless $rfq_only;

	my $product_only = '';

#Disable product only functions.
#	my $product_only =  $pid ? $dbh->selectrow_array(q{
#			SELECT product FROM tbl_projects WHERE lngprojectindex = ?
#	}, undef, $pid)
#	: undef;
#
#	my $p = $product_only ? '' : 'NOT';
#
#	$sql .= " AND eq.lngindex $p IN ( SELECT lngequipmentindex FROM tbl_equipment_specifications
#								  WHERE strname = 'product_only' AND strvalue = 'Y')" if $pid;
	

	#print STDERR "VALID EQUIPEMNT SQL: $sql \n";
	
  # As this query will potentially be run for every single service for every
  # project created, let's cache the statment.
  my $sth = $dbh->prepare_cached($sql);
  my @x =  @{ $dbh->selectcol_arrayref($sth, undef, $service_type) };
  return @{ $dbh->selectcol_arrayref($sth, undef, $service_type) };
}

sub valid_equipment_dropdown {
	my ($dbh, $service_type) = @_;

    # As this query will potentially be run for every single service for every
    # project created, let's cache the statment.
    my $sth = $dbh->prepare_cached(q{
		SELECT e.lngindex, e.strname
        FROM service_type_equipment s, tbl_service_types t, tbl_equipment e
        WHERE t.lngindex = s.service_type
          AND e.lngindex = s.equipment
          AND t.strid    = ?
    });

    return make_drop_down(
        $dbh->selectcol_arrayref($sth, { Columns => [1,2] }, $service_type) );
}


sub save_service {
    my ($r, $log, $dbh, $pid, $sid) = @_;

    my $insert = $dbh->prepare(q{
        INSERT INTO tbl_service_specifications 
            (lngprojectindex, lngserviceindex, strname, strvalue, ui_spec)
        VALUES (?, ?, ?, ?, true)
    });

    my $delete = $dbh->prepare(q{
        DELETE FROM tbl_service_specifications 
        WHERE lngprojectindex = ? AND lngserviceindex = ? AND strname = ?
    });

    # Remove all user specified keys on each save (stops now unchecked
    # checkboxes from remaining checked -- as they aren't defined this save, so
    # wouldn't otherwise be overwritten).
    $dbh->do(q{
        DELETE FROM tbl_service_specifications
        WHERE lngprojectindex = ? AND lngserviceindex = ? AND ui_spec = true
    }, undef, $pid, $sid);
    
    foreach my $key ( $r->param() ) {
        # Prevent insertion of duplictes (this is instead of an exist +
        # update/insert type construct).
        $delete->execute($pid, $sid, $key);
        $insert->execute($pid, $sid, $key, scalar $r->param($key));
    }

    # Make sure anyone who depends on us is set to the approriate state.
    recalc_dependencies($log, $dbh, $pid, $sid);

    return 1;
}


sub get_service_url {
    my ($dbh, $pid, $sid) = @_;

    require eprint::print_project;

    my $service_type = service_type($dbh, $sid);

    my $url = !defined $service_type 
        ? eprint::print_project::get_url($dbh, $pid) # Print container
        : $dbh->selectrow_array(q{
            SELECT strurl FROM tbl_service_types WHERE strid = ?
        }, undef, $service_type);

    return $url;
}

# Returns a list of values for the requested specs (in given order).
sub get_specifications {
    my ($log, $dbh, $pid, $sid, @specs) = @_;

    die "Can't get service specs without service id" unless $sid;

    my %pairs = get_specifications_pairs($log, $dbh, $pid, $sid, @specs);

    return @pairs{ @specs };  # List context
}

# Returns a list of key => value pairs for the requested keys (unordered).
sub get_specifications_pairs {
    my ( $log, $dbh, $pid, $sid, @specs ) = @_;

    die "Can't get service specs without service id" unless $sid;

    my $query = "SELECT strName, strValue FROM tbl_service_specifications";

    my @ands;
    push @ands, 'lngProjectIndex = ' . $dbh->quote($pid) if $pid;
    push @ands, 'lngServiceIndex = ' . $dbh->quote($sid) if $sid;

    if (@specs) {
        foreach my $spec (@specs) {
            $spec = $dbh->quote($spec);
        }
        push @ands, 'strName IN (' . join(q{,}, @specs) . ')';
    }

    $query = "$query WHERE " . join(' AND ', @ands); # Will always have some

    return @{ $dbh->selectcol_arrayref($query, { Columns => [ 1, 2 ] }) };
}

sub get_spec {
	my $sid = shift;
	my $name = shift;
	my $dbh = session::dbh;

	my $query =  q{SELECT strvalue FROM tbl_service_specifications WHERE lngserviceindex = ? and strname = ?};
	return $dbh->selectrow_array($query, undef, $sid, $name);
}


sub insert_service_spec {
    my ( $log, $dbh, $pid, $sid, $name, $value, $no_delete, $ui_spec) = @_;

    die "Can't insert spec into service without id" unless $sid;

    if (!$no_delete) {
        my $sth = $dbh->prepare_cached(qq{
            DELETE FROM tbl_Service_Specifications 
            WHERE lngProjectIndex = ?
              AND lngServiceIndex = ?
              AND strName         = ?
        });

        $sth->execute($pid, $sid, $name);
    }
    insert($log, $dbh, 'tbl_Service_Specifications',
            lngProjectIndex => $pid,
            lngServiceIndex => $sid,
            strName         => $name,
            strValue        => $value,
            ui_spec         => ($ui_spec || 0)
    );
print STDERR "INSERTING SPECS: $name - $value - $ui_spec \n";

    return 1;
}

sub insert_service_specs {
    my ($log, $dbh, $pid, $sid, %spec) = @_;
    
    while ( my ($field, $value) = each %spec ) {
        insert_service_spec($log, $dbh, $pid, $sid, $field, $value);
    }

    return scalar keys %spec;
}

sub set_status {
    my ($log, $dbh, $pid, $status, @sids) = @_;

    # We'll contrain valid service statuses here until the DB does.
    die "Invalid status: $status." unless grep { $status eq $_ } STATUSES;

    # As we're directly interpolating, make sure we get what we think we are.
    $pid =~ tr/0-9//cd;
    die "An integer project ID is needed." unless $pid;

    @sids = grep {$_} map { tr/0-9//cd; $_ } @sids;

    # We can't set what we don't get.
    return 0 unless @sids;

    # Update the specified project services with the status.
    if (@sids == 1) {
        my $sth = $dbh->prepare_cached(q{
            UPDATE tbl_project_contents
            SET strstatus = ? 
            WHERE lngprojectindex = ?
              AND lngserviceindex = ?
              AND strstatus <> ?
        });
        $sth->execute($status, $pid, $sids[0], $status);

        return 1;
    }
    else {
        # we are going to hell for this, you know that, right?
        local $" = ', ';

        return $dbh->do(qq{
            UPDATE tbl_project_contents
            SET strstatus = ? 
            WHERE lngprojectindex = ?
              AND lngserviceindex IN (@sids)
              AND strstatus <> ?
        }, undef, $status, $pid, $status);
    }
}

# Given a project and project service, set any dependency changes needed.
sub recalc_dependencies {
    my ($log, $dbh, $pid, $sid) = @_;


    # Get the status and level of the current service.
    my ($status, $level) = $dbh->selectrow_array(q{
        SELECT status, level
        FROM project_service_status
        WHERE project = ?
          AND id = ?
    }, undef, $pid, $sid);

    # If it's not there complain about it.
    die "No project ($pid) service with ID ($sid) exists" unless $status;

    # If we're not part of the dependency tree we don't need to be here.
    return 0 unless defined $level;

	my $p = new PQS::Object::project($pid);

	if ( $p->no_service_dependencies() ) {
		my $service = $dbh->selectall_arrayref(q{
			SELECT id, level
			FROM project_service_status
			WHERE project = ?
			ORDER BY level
		}, { Slice => {} }, $pid);

		 set_status($log, $dbh, $pid, 'calculated',
		    map { $_->{id} } @{$service});

		return 1
	}
	#die($p->no_service_dependencies());



    # If we're calculated but there are other uncalculated services on the
    # current level, we don't need to adjust anything.
    return 0 if $status eq 'calculated' and $dbh->selectrow_array(q{
        SELECT count(*) > 0
        FROM project_service_status
        WHERE status NOT IN ('calculated', 'In Production', 'Complete')
          AND project = ?
          AND level   = ?
    }, undef, $pid, $level);

    # We have to adjust all the service depending on us on one way or the
    # other, so get a list of them.
    my $service = $dbh->selectall_arrayref(q{
        SELECT id, level
        FROM project_service_status
        WHERE project = ?
          AND level   > ?
        ORDER BY level
    }, { Slice => {} }, $pid, $level);

    # If we're calculated and the last on our level, this is either the first
    # time through or we've been recalculated. Either way the next level down
    # needs to calculate (maybe again) and lower is still dependent.
    if ($status eq 'calculated') {
        my $service = $dbh->selectall_arrayref(q{
            SELECT id, level
            FROM project_service_status
            WHERE project = ?
              AND level   > ?
            ORDER BY level
        }, { Slice => {} }, $pid, $level);

        # Get the next level to allow.
        $level = $service->[0]{level};

        # As everything on the current level is calculated, the next level is
        # now allowed to calculate/required to calculate again.
        set_status($log, $dbh, $pid, 'uncalculated',
            map { $_->{id} } grep { $_->{level} <= $level} @{$service});

        # All services below the allowed level are dependent on it. Ensure it.
        set_status($log, $dbh, $pid, 'dependent',
            map { $_->{id} } grep { $_->{level}  > $level} @{$service});
    }
    # If we aren't calculated or we're errored out, we need to make sure all
    # the levels below are still marked as dependent on us.
	else {
		 set_status($log, $dbh, $pid, 'dependent',
		    map { $_->{id} } @{$service});
    }

    return 1; # TODO: Make return number of modified records.
}

# Returns the string project service status given the ID of one.
sub get_status {
    my ($log, $dbh, $sid) = @_;

    my $sth = $dbh->prepare_cached(q{
        SELECT strstatus 
        FROM tbl_project_contents
        WHERE lngserviceindex = ?
    });

    return $dbh->selectrow_array($sth, undef, $sid);
}

# Returns the need level of the project service given the ID of one.
sub get_need {
    my ($log, $dbh, $sid) = @_;

    my $sth = $dbh->prepare_cached(q{
        SELECT lngneedlevel 
        FROM tbl_project_contents
        WHERE lngserviceindex = ?
    });

    return $dbh->selectrow_array($sth, undef, $sid);
}

# Sets the need level of the project service given the ID of one.
sub set_need {
    my ($dbh, $sid, $need) = @_;

    return $dbh->do(q{
        UPDATE tbl_project_contents
        SET lngneedlevel = ?
        WHERE lngserviceindex = ?
    }, {}, $need, $sid);
}

# Takes a price and quantity and return good little conformistly formatted
# total and unit price.
sub format_pricing {
    my ($price, $qty) = @_;

    # There is an absolutely amazing ammount of diversity in rounding
    # (ceiling, floor, int, etc.) and formatting of service total and unit
    # pricing. We aim to crush and uterly annihilate such individualism and
    # diversity!

    return qw(0.00 0.00) unless $price 
                             && looks_like_number($price)
                             && $price > 0;

    $qty = 1 unless $qty 
                 && looks_like_number($qty)
                 && $qty > 0;

# Safeway does not want prices rounded.
    $price = sprintf '%.2f', $price;
#    $price = sprintf '%.2f', ceil $price;

    my $unit_price = sprintf '%.2f', $price / $qty;
       $unit_price = '< 0.01' unless $unit_price >= 0.01;

    return ($price, $unit_price);
}


sub get_inline_web_bindery {
	my ($log, $dbh, $pid, $service_index, $specs, $service_type) = @_;

    require eprint::project;
    
    my @total_bindery_price = (undef, 0, 0, 0);
	my @quantities          = (undef, eprint::project::get_quantities($log, $dbh, $pid));


	my $last_press;
	my $valid_price = 1;

    # Adjust the signature pricing to account for the slowdown to the press
    # based on the service being performed. NOTE: This looks like it will
    # compound over multiple services.
    for my $sig (eprint::project::get_signature_indices($log, $dbh, $pid)) {

    	# Get the rate at which the current service being performed slows down
    	# the web press.
    	my $press = $dbh->selectrow_array(q{
        	SELECT strvalue 
        	FROM tbl_service_specifications 
        	WHERE strname = 'hdnPress' 
          	AND lngserviceindex = ?
    	}, undef, $sig);

    	my $stock_cal = $dbh->selectrow_array(q{
        	SELECT strvalue 
        	FROM tbl_service_specifications 
        	WHERE strname = 'txtStockCalliper' 
          	AND lngserviceindex = ?
    	}, undef, $sig);

		# Covers for web projects can now be done on an offset press
		# so we must check our press type for each signature.
		next unless eprint::equipment::get_type($log, $dbh, $press) eq 'web';

		my $spec;
		my $max_cal;
		my $range;
		# Folding now has different run speeds for different fold types
		# So we must do some extra work to look up the press slowdown spec.
		if ( $service_type eq 'Folding' ) {
			
			my $fold_type = $dbh->selectrow_array(q{
				SELECT strname FROM tbl_service_specifications
				WHERE  strname ~ 'SignatureQty' 
				AND    lngserviceindex = ?
				ORDER by strname LIMIT 1
			}, undef, $sig);


			if ( $fold_type ) {
				$fold_type =~ /SignatureQty(\d*)Page/;
				$spec = "${1}PageSignatureFoldSlowdown";

				$max_cal = eprint::equipment::get_specification(
					$log, $dbh, "MaximumCalliper${1}PageSignature", $range, $press
				);

				return 'uncalculated' if ( $max_cal and $stock_cal > $max_cal ); 
			}
			else {
				$spec = "FoldingSlowdown";
			}
			
			# Currently the Folding slowdowns are ranged by paper weight.
			# There are better units for the range but the is they way TS
			# has requested it.
			my $weight = $dbh->selectrow_array(q{
				SELECT strvalue FROM tbl_service_specifications
				WHERE  strname = 'hdnPaperWeight' AND lngserviceindex = ?
			}, undef, $sig);
			$weight =~ /(\d*)/;
			$range = $1;

			die ("eprint::service::get_inline_bindery 
					'Could not get Paper Weight For SID: $sig'") 
			unless $range;

		} else {
			$spec = "${service_type}Slowdown";
		}

		my $slowdown = eprint::equipment::get_specification(
			$log, $dbh, $spec, $range, $press
		);

        $specs->{InlineSlowDown} += $slowdown;

		$valid_price = 0 unless $slowdown;

        my %pricing = @{ $dbh->selectcol_arrayref(q{
            SELECT strname, strvalue 
            FROM tbl_service_specifications 
            WHERE strname LIKE 'hdnTotalRunCost%' 
              AND lngserviceindex = ?
        }, { Columns => [1,2] }, $sig) };

        my %run_time = @{ $dbh->selectcol_arrayref(q{
            SELECT strname, strvalue 
            FROM tbl_service_specifications 
            WHERE strname LIKE 'hdnRunTime%' 
              AND lngserviceindex = ?
        }, { Columns => [1,2] }, $sig) };


        for my $i (1..3) {
            next unless exists $pricing{"hdnTotalRunCost$i"};

            my $price    = $pricing{"hdnTotalRunCost$i"};
            my $adjusted = $price * 100 / (100 - $slowdown);

            $total_bindery_price[$i] += $adjusted - $price;
			$specs->{"Sig-Equipment-$sig"} = $press;
            $specs->{"hdnRunTime$i"} += sprintf("%.2f", 
                  $run_time{"hdnRunTime$i"} *  $slowdown / 100 
            );

        }
		$last_press = $press;
	}

	for my $i (1..3) {
        next unless $quantities[$i] > 0;

        return 'uncalculated' unless $valid_price
								  && $total_bindery_price[$i]
                                  && $total_bindery_price[$i] > 0;

        @$specs{"txtPrice$i", "txtUnitPrice$i"} 
            = format_pricing($total_bindery_price[$i], $quantities[$i]);
		$specs->{"ddmEquipment$i"} = $last_press;
	}

	return 'calculated';
}

# this function is given the standard stuff, then a hashref containing:
# $hash = { action    => 'action',
#           service   => 'service',
#           makeready => 'makeready' };
#
# as well as a quantity and material, and returns the price for that entire
# service including materials.
sub get_service_full_price {
    my ($log, $dbh, $variable, $names, $quantity, $material) = @_;

    require eprint::project;

    my @equipment = valid_equipment($log, $dbh, $names->{action});
#use Data::Dumper;
 # print STDERR "VALID EQUIPMENT: ", Dumper(@equipment);

    my @specs;

    # try and be smart about what hardware we pick for the job.
    if ($variable->{ProjectIndex}) {
        my $print_sid = eprint::project::get_print_container(
            $log, $dbh, $variable->{ProjectIndex}
        );

        @specs = get_specifications(
            $log, $dbh, $variable->{ProjectIndex}, $print_sid,
            qw( hdnSheetSizeWidth hdnSheetSizeHeight
                txtStockCalliper             )
        );
    }

    die "No valid equipment to perform: " . $names->{service} . " service!"
        if !scalar @equipment;

    my %device_prices;

    DEVICELIST:
    foreach my $device (@equipment) {

        if (   $device && $variable->{force_device}
            && $device != $variable->{force_device}) {
            next DEVICELIST;
        }

        if (grep { $_ > 0 } @specs) {
            next DEVICELIST unless eprint::equipment::equipment_fits($log, $dbh, $device, @specs, 1);
        }
print STDERR "IT FITS: $device \n";

        my $price       = get_price($log, $dbh, $variable, $names->{service}, $quantity, $device);
        my $setup_price = get_price($log, $dbh, $variable, $names->{makeready}, 1, $device);
        my $min_charge  = get_price($log, $dbh, $variable, $names->{mincharge}, 1, $device);


        next DEVICELIST if !$price && !$min_charge;

        my $material_price = 0;

        if ($material) {
            $material_price = eprint::material::get_price(
                $log, $dbh, $variable, $material, $quantity, $device
            );

			$material_price *= $quantity;
        }

        my $setup;

	    my $run_price = $price * $quantity;

        if ($min_charge > $price * $quantity  +  $setup_price) {
            $price = $min_charge;
            $setup = 0;
        }
        else {
            $price = $price * $quantity;
            $setup = $setup_price;
        }


        $device_prices{$device} = [ $price, $material_price, $setup, $run_price, $min_charge ];
    }

    my $deletion = delete $variable->{force_device};

    if (!scalar keys %device_prices) {
        if ($deletion) {
            die "That device cannot perform that service!  Please choose another.\n";
        }
        else {
            die "Unable to find any pricable hardware to perform: $names->{service} service!"
        }
    }

    my ($device)
        = sort { (sum @{ $device_prices{$a} }) <=> (sum @{ $device_prices{$b} }) }
            keys %device_prices;
    my @stuff
        = sort { (sum @{ $device_prices{$a} }) <=> (sum @{ $device_prices{$b} }) }
            keys %device_prices;

    map { print STDERR "SUM: ", sum @{$device_prices{$_}} , "\n" } keys %device_prices;

use Data::Dumper;
print STDERR "BEST  FITS: $device \n", Dumper(\%device_prices);
print STDERR "Stuff \n", Dumper(@stuff);


    #this got real ugly real fast -- it was expanded long after I wrote it to
    #do things it wasn't originally intended to do, hence the long ugly
    #return below.  FIXME: might consider a contextual return so we can
    #return a hash with all the fun values we want later..
    my $total =   $device_prices{$device}->[0]
                + $device_prices{$device}->[1]
                + $device_prices{$device}->[2];
    
    return wantarray
         ? ($device,
            $total,
            $device_prices{$device}->[1],
            $device_prices{$device}->[2],            
            $device_prices{$device}->[3],            
            $device_prices{$device}->[4],            
	   )
         :  $total;
}



# SERVICE PRICING
#
# Generic 'methods' to price and save services.

# Given the service type hash ref, try to load the module and add some helper
# attributes and methods.
sub load_service_type {
    my ($service) = @_;

    $service->{ref} = $service->{type}; # Set an alias.

    my $module = $service->{module};

    # Load the given module.
    eval "require $module;";
    die "Failed requiring $module for $service->{type}\n\n\t$@" if $@;

    # Create a $foo->can() type function that works on our non-OO modules.
    $service->{can} = sub {
        my $function_name = shift;

        # If the module is an OO class see if can perform the named method,
        # otherwise get the code ref out of the module's symbol table.
        my $obj  = $module->can('new') ? $module->new : undef;
        my $func = $obj ? $module->can($function_name)
                        : *{qualify_to_ref($function_name, $module)}{CODE};

        return $obj && $func ? sub { $func->($obj, @_) } : $func;
    };

    return $service;
}

sub get_specs {
    my ($dbh, $pid, $sid, $service, $from_user) = @_;

    my $specs = _from_db($dbh, $sid, $from_user);

    # Run restore if it's defined for the service.
    if (my $func = $service->{can}->('restore')) {
        $specs = $func->($dbh, $pid, $sid, $service->{type}, $specs);
    }

    return $specs;
}


# Gets a hash of the given service specs from the DB.
sub _from_db {
    my ($dbh, $sid, $from_user) = @_;

    my $query = q{
        SELECT strname, strvalue 
        FROM tbl_service_specifications
        WHERE lngserviceindex = ?
          AND strname IS NOT NULL
          AND strname <> ''
    };
    # If we've specifically asked for specs that the user specified (or not)
    # give us just those. Otherwise give them all.
    $query .= '  AND ui_spec = ' . ($from_user ? 'true' : 'false')
        if defined $from_user;

    my $specs = $dbh->selectcol_arrayref($query, { Columns => [1,2] }, $sid);

    return { @$specs };
}


sub price {
    my ($log, $dbh, $variable, $pid, $sid, $service, $specs, $is_save) = @_;

    my $service_type = $service->{type};

    # Allow the service to convert the specs whatever dataformat it wants.
    eval {
        if (my $munge = $service->{can}->('munge')) {
            $munge->($log, $dbh, $variable, $pid, $sid, $service_type, $specs);
        }
    };
    if ($@) { 
        $log->error($@) if DEBUG;

        # An error during munging most likely is a validation error.
        # warn("${service_type}::munge: $@");
        return 'uncalculated';
    }

    # The "fill from" service is a legacy bit that takes things from the main
    # print/book service and throws specs into it's own. As it modifies the DB
    # we only allow it during internal pricing/saving.
    if ($is_save) {
        if (my $func = $service->{can}->('fill_from_printing_service')) {
            $func->($log, $dbh, $pid, $sid);
        }
        my $new = get_specs($dbh, $pid, $sid, $service);
        
        # Because we assign verions in the above munge funciton
        # for the printing service we must not overwrite the current 
        # versions in $spec.
        delete $new->{versions};
       
        @$specs{keys %$new} = values %$new;
    }

    # Calculate the service.
    my $calc   = $service->{can}->('calc') 
        or die "Service $service->{module}::calc() does not exist";
    my $status = eval { 
        $calc->($log, $dbh, $variable, $pid, $sid, $service_type, $specs)
    };
    if ($@) {
        if (DEBUG) { die $@ }
        else       { warn("Pricing $service_type errored: $@") }

        return 'error';
    }

    # Unknown statuses are treated as errors.
    unless (grep { $status eq $_ } STATUSES) {
        no warnings qw(uninitialized);
        warn "$service_type ($sid) returned invalid status ($status)";

        return 'error';
    }

	my $override = $dbh->selectrow_array(q{
		SELECT price_override FROM tbl_project_contents WHERE lngserviceindex = ?
	}, undef, $sid );

	print STDERR "HAVE PRICE OVERRIDE: FOR SID: $sid \n";

	$specs->{txtPrice1} = $override if $override ne '';

    return $status;
}

sub clean_calc {
	my $pid = shift;
	my $specs = shift;
	my $p = new PQS::Object::project($pid);

	if ( $p->noprint() ) {
		my @list = qw( txtImageWidth txtImageHeight txtFinishedCalliper );
		map {
			
			foreach my $s ( keys %{$specs} ) {
				if  ( $s =~ /$_/ ) { 
					delete $specs->{$s}; 
					print STDERR "CHECK SPEC: $s to $_ \n";
				}
			}

		} @list;

	}
}


sub save {
    my ($log, $dbh, $pid, $sid, $service, $form, $specs) = @_;

    # Merge the original user specified specs into the pricing (for storage).    
    $specs->{$_} = $form->{$_} for keys %$form;

    # Some actions need to look at the state of the service or remove control
    # specifications before the service is changed/saved.
    if (my $func = $service->{can}->('preaction')) {
        $func->($log, $dbh, $pid, $sid, $service->{type}, $specs);
    }

    # Allow the service to modify the specs for saving. ie. serializing arrays
    # (eugh), storable()ing complex structures, etc.
    my $store = $service->{can}->('store');
    
    $specs = $store->($log, $dbh, $pid, $sid, $service->{type}, $specs) 
        if $store;

    # TODO Save the actual specs (user specified) as such, and the
    # anything that's new after pricing as not.
    
    to_db($dbh, $pid, $sid, $form, $specs); # Insert into DB.

    # Perform any actions required. eg. create signatures after changing the
    # book specifications.
    if (my $action = $service->{can}->('action')) {
        $action->($log, $dbh, $pid, $sid, $service->{type}, $specs);
    }

    return 1;
}

# Save a batch of service specifications to the DB. Optionally the batch can
# be marked as coming from the user.
sub to_db {
    my ($dbh, $pid, $sid, $form, $specs) = @_;

    # Remove all the specs before we (re)insert (instead of update check).
    $dbh->do(q{
        DELETE FROM tbl_service_specifications
        WHERE lngserviceindex = ?
    }, undef, $sid);

    my $insert = $dbh->prepare_cached(q{
        INSERT INTO tbl_service_specifications
            (lngprojectindex, lngserviceindex, strname, strvalue, ui_spec)
        VALUES (?, ?, ?, ?, ?)
    });

    while (my ($key, $value) = each %$specs) {
        # Only handle simple values that are defined.
        next if ref $value || ! defined $value || $value eq ''; 

        next if $key =~ /^[ps]id$/i; # Don't save project or service ids.

        # If the spec also exists in the form it was from the user.
        $insert->execute(
            $pid, $sid, $key, $value, (exists $form->{$key} ? 1 : 0)
        );
    }

    return 1;
}

1;
