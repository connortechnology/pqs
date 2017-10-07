package eprint::Service::PerItem;
use strict;
use warnings;

use Date::Calc        qw(Delta_Days Today Add_Delta_YM);
use List::Util        qw(max);
use eprint::project   qw(:common :pricing);
use eprint::equipment ();

require configuration;

sub munge {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;
   
    # Put the pricing into arrays of quantity pricing for each currency.
    my %prices;
    my %buy;;
    for (keys %$specs) {
        next unless /^price-(\w{3})-(\d+)$/
                 && $specs->{$_};

        $prices{ $1 }{ $2 } = $specs->{ $_ };
    }

    my %buy;;
    for (keys %$specs) {
        next unless /^buy-(\w{3})-(\d+)$/
                 && $specs->{$_};

        $buy{ $1 }{ $2 } = $specs->{ $_ };
    }

    die "No pricing." unless keys %prices;

use Data::Dumper;
print STDERR "HAVE PRICES: " , Dumper(%prices);

    # Create range lookups for each currency.
    while (my ($currency, $items) = each %prices) {
        my @ranges;
        
        for my $n (keys %$items) {
            push @ranges, [
                $specs->{"min-$n"},
                $specs->{"max-$n"},
                $items->{$n}
            ];

        }
        
        $specs->{prices}{$currency} 
            = eprint::equipment::create_range_lookup(@ranges);
    }


    while (my ($currency, $items) = each %buy) {
        my @ranges;
        
        for my $n (keys %$items) {
            push @ranges, [
                $specs->{"min-$n"},
                $specs->{"max-$n"},
                $items->{$n}
            ];

        }
        
print STDERR "HAVE BUY DATA: ", Dumper(@ranges); 
        $specs->{buy}{$currency} 
            = eprint::equipment::create_range_lookup(@ranges);
    }



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

    # Get service/material pricing.
    my @qty      = (undef, get_quantities(undef, $dbh, $pid));
    my $prices   = service_prices($dbh, $pid);
    my @material = stock_price($log, $dbh, $pid);

    my $unit_pricing = $specs->{prices}{$currency}
        or return 'error';


    # Build a subtotal (excluding 'allowed' services) for each quantity.
    QTY:
    for my $i (1..3) {
        next QTY unless $qty[$i] && $qty[$i] > 0;

        # Get the unit price for this currency/quantity range
        my $unit_price = $unit_pricing->( $qty[$i] )
            or return 'error';

        my $sub_total += $material[$i-1];

        # Subtotal the service prices excluding services marked as such.
        SERVICE:
        for my $service (values %{ $prices->[$i-1] }) {
            next SERVICE if exists $exclude->{ $service->{type} }
                         || $service->{service} eq $service_type;

            $sub_total += $service->{price};
        }

        $specs->{"txtPrice$i"} = $unit_price * $qty[$i] - $sub_total;
		$specs->{"txtBuyPrice$i"} = $specs->{buy}{$currency}->($qty[$i]) * $qty[$i] if  $specs->{buy}{$currency};

    }

use Data::Dumper;
print STDERR "HAVE SPECS: " , Dumper($specs);

    return 'calculated';
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

    # TODO Re-order ranges for min/max and drop any undef ones.
    

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

    # Determine how many quantity ranges we already have.
    my $ranges = max( 
        map  { /(\d+)$/; $1 } 
        grep { /^min/       }
             keys %$specs 
    ) || 0;

    # Create enough ranges plus an extra for new entry.
    $page{ranges} = [ map { { i => $_ } } 1 .. $ranges + 1 ];
    
    # There is a price for each quantity range in each currency.
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
