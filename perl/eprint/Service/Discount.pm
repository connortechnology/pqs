package eprint::Service::Discount;
use strict;
use warnings;

use Date::Calc      qw(Delta_Days Today Add_Delta_YM);
use eprint::project qw(:common :pricing);

require configuration;

sub munge {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;
    # Put the pricing into arrays of quantity pricing for each currency.
    my %total;
    for (keys %$specs) {
        next unless /^c-([A-Z]{3})-([1-3])$/;

        my $i        = $2;
        my $currency = $1;
        my $price    = $specs->{$_};

        $total{$currency} = [] unless exists $total{$currency};

        $total{$currency}[$i] = $price;
    }
    $specs->{prices} = \%total;

    die "No pricing." unless keys %total;

    # Set up the excluded services list as an existance check hash.
    my @services = exists $specs->{services} ? 
						ref($specs->{services}) eq 'ARRAY'
							? @{ $specs->{services} } 
							: ( $specs->{services} )
				   : ();

    my %exclude;
    @exclude{@services} = (1) x scalar @services;
    $specs->{exclude} = \%exclude;

    return;
}

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    # If we have an expiry, make sure we're not past it.
    return 'error' 
      if $specs->{expires}
      && is_expired($specs->{year}, $specs->{month}, $specs->{day});

    # The list of services to exclude from the discount.
    my $exclude = $specs->{exclude};

    # Determine what currency we're in from the customer price list.
    my $currency = $dbh->selectrow_array(q{
        SELECT p.currency 
        FROM pricelist p, tbl_customer c 
        WHERE p.id = c.lngpricelist 
          AND c.lngcustomerid = ?
    }, undef, $variable->{cust_id});

    # Get totals
    my @qty      = (undef, get_quantities(undef, $dbh, $pid));
    my $total    = $specs->{prices}{$currency};
    my $prices   = service_prices($dbh, $pid);
    my @material = stock_price($log, $dbh, $pid);

	my $markup = category_markup($dbh, $pid, $variable->{cust_id});

	map { 
		$total->[$_] *= 1 + ($markup / 100) if $total->[$_] && $markup;
	} (1..3);


    # Build a subtotal (excluding 'allowed' services) for each quantity.
    QTY:
    for my $i (1..3) {
        next QTY unless $qty[$i] && $qty[$i] > 0;

        #die "Quantity $i exists but fixed price for it doesn't"
        return 'error' unless $total->[$i];

        my $sub_total += $material[$i-1];

        # Subtotal the service prices excluding services marked as such.
        SERVICE:
        for my $service (values %{ $prices->[$i-1] }) {
            next SERVICE if exists $exclude->{ $service->{type} }
                         || $service->{service} eq $service_type;

            $sub_total += $service->{price};
        }

        # my $discount = $total->[$i] - $sub_total;
        # $specs->{"txtPrice$i"} = $discount < 0 ? $discount : 0;

        $specs->{"txtPrice$i"} = $total->[$i] - $sub_total;
    }

    return 'calculated';
}

sub category_markup {
  my ($dbh, $pid, $cust_id) = @_;
	
	my $markup = $dbh->selectrow_array(q{
		SELECT pm.markup FROM product_markup pm, product.item_category ic, product.item i, 
					  product.assignment a, tbl_projects pr

		WHERE ic.item = i.id AND a.item = i.id AND pm.category = ic.category
		AND pr.prod = a.project AND pr.lngprojectindex = ? AND pm.customer = ?
	}, undef, $pid, $cust_id);

	return $markup;
}

# Accepts the year, month, day of the expiry date and return true if the
# current date is past that.
sub is_expired {
    my @expiry  = @_[0,1,2];                # Year, month, day

    return Delta_Days(Today(), @expiry) < 0;
}

sub restore {
    my ($dbh, $pid, $sid, $service_type, $specs) = @_;
    
    # De-serialize the multi-select.
    $specs->{services} = [ split(q{,}, $specs->{services}) ] 
        if exists $specs->{services};

    return $specs;
}

sub store {
    my ($log, $dbh, $pid, $sid, $service_type, $specs) = @_;

    # Serialize the multi-select (ick).
    $specs->{services} = defined $specs->{services} ? 
		ref($specs->{services}) eq 'ARRAY' 
			? join(',', @{ $specs->{services} }) 
			:  $specs->{services} 
	: undef;

    delete @$specs{qw(year month day)} unless $specs->{expires};

    return $specs;
}

sub display {
    my ($log, $dbh, $service_type, $pid, $sid, $specs) = @_;

    my %page;

    # PRICING
    #
    my @qty = (undef, get_quantities($log, $dbh, $pid));
    $page{qty} = \@qty;
    
    # There is a price for each quantity in each currency.
    $page{currency} = $dbh->selectall_arrayref(q{
        SELECT code, symbol, name FROM currency
    }, { Slice => {} });

    # EXPIRE DATE
    #
    # If there isn't an expire date set, show a default of one month from now.
    @$specs{qw(year month day)} = Add_Delta_YM(Today(), 0, 1)
        unless $specs->{expires};

    # Setup the year selection dropdown.
    my $year     = (Today())[0];
    $page{years} = [ map { { year => $_ } } $year .. $year + 3 ];
    
    # Add the chosen year if it's before this year.
    unshift @{ $page{years} }, { year => $specs->{year} }
        if $specs->{year} < $year;

    # SERVICES
    #
    # Get a list of services by category.
    my $sth = $dbh->prepare(q{
        SELECT c.strname AS category, s.lngindex AS id, s.strname AS name 
        FROM tbl_service_types s, tbl_service_categories c 
        WHERE s.strcategory = c.strid 
          AND s.strid <> 'Discount' 
          AND ysnviewvisible = 'Y'
          AND strtype <> 'bind'
        ORDER BY c.lngsort, s.lngsort
    });
    $sth->execute;
    my ($category, $id, $name);
    $sth->bind_columns(\$category, \$id, \$name);

    my @categories;
    while ($sth->fetch) {
        push @categories, { name => $category, services => [] }
            if !@categories || $categories[-1]{name} ne $category;

        push @{ $categories[-1]{services} }, { id => $id, name => $name };
    }
    $page{categories} = \@categories;

    # Set the allowed service to their defaults if this is our first time here.
    $specs->{services} = defaults($dbh) unless exists $specs->{services};


		$page{rfq_supplier} = $dbh->selectall_arrayref(q{
				SELECT  strcompanyname as name,
						sum(r.price1) as price1,
						sum(r.price2) as price2,
						sum(r.price3) as price3, 
						supplier as sup,
						rid
				FROM tbl_customer c, rfq_response r, rfq q 
				WHERE c.lngcustomerid = r.supplier and r.rid = q.id 
				AND q.pid = ?
				GROUP BY c.strcompanyname, supplier, rid
		},{Slice => {}}, $pid);
		$page{rfq} = 1 if ( @{$page{rfq_supplier}});

use Data::Dumper;
print STDERR "SUPPLIER ", Dumper($specs->{rfq_supplier});
		



    return \%page;
}

# Get a list of services that are normally allowed in fixed price projects.
sub defaults {
    my ($dbh) = @_;

    my @services = split /,/, 
        configuration::get_value(undef, $dbh, 'predefined_allowed_services');

    return \@services;
}

1;
