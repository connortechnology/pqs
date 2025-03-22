use strict;
package openprint::Service;
our @ISA = qw( openprint::Object );
use vars qw($debug $table $serial %fields %find_fields %transforms %defaults %session $log $dbh $cache_field $cached %ServicePrices %Configuration );

require sql;
require openprint::Object;
require openprint::pricing;
require openprint::ServiceCategory;
require openprint::ServiceType;
use openprint ();
*session = \%openprint::session;
*log = \$openprint::log;
*dbh = \$openprint::dbh;

foreach my $Service ( 'UVCoating', 'ThreeKnifeTrim' ) {
	eval "
		my \@keys = keys %openprint::Estimating::${Service}::ServicePrices;
		\@Configuration{\@keys} = values %openprint::Estimating::${Service}::ServicePrices if \@keys;
	";
}
foreach my $service ( keys %ServicePrices) {
$log->debug("Have a price definition for $service");
}


$debug = 1;
$cached = 1;

$table = 'tbl_services';
$serial = 'tbl_services_lngindex_seq';

%fields = (
		id				=>	'lngindex',
		name			=>	'strname',
		description		=>	'strdescription',
		supplier_id		=>	'supplier_id',
		category_id		=>	'category_id',
		category		=>	undef,
		taxexempt1		=>	'taxexempt1',
		taxexempt2		=>	'taxexempt2',
		owner_id		=>	'owner_id',
		activity_code	=>	'activity_code',
		servicetype_id	=>	'servicetype_id',
		deleted					=>	'deleted',
	 	);	
%find_fields = (
		category		=> '(SELECT name FROM Service_Categories WHERE service_categories.id=category_id)',
		equipment_id	=> '(SELECT equipment_id FROM service_prices WHERE service_id=services.id)',
);


%transforms = (
		name		=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
		description	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
		);

%defaults = (
		servicetype_id	=>	undef,
		supplier_id	=>	undef,
		category_id	=>	undef,
		taxexempt1	=>	q`'N'`,
		taxexempt2	=>	q`'N'`,
		owner_id	=>	q`$openprint::config{owner_id}`,
		deleted					=>	0,
		);

%Configuration = (
		'1ColourImpression'	=> {
			range_units => [ 'impressions', 'total impressions' ],
			units	=>	[ 'per 1000', 'per 1000 impressions', 'per m', 'per hour' ],
		},
		'2ColourImpression'	=> {
			range_units => [ 'impressions', 'total impressions' ],
			units	=>	[ 'per 1000', 'per 1000 impressions', 'per m', 'per hour' ],
		},
		'3ColourImpression'	=> {
			range_units => [ 'impressions', 'total impressions' ],
			units	=>	[ 'per 1000', 'per 1000 impressions', 'per m', 'per hour' ],
		},
		'4ColourImpression'	=> {
			range_units => [ 'impressions', 'total impressions' ],
			units	=>	[ 'per 1000', 'per 1000 impressions', 'per m', 'per hour' ],
		},
		'5ColourImpression'	=> {
			range_units => [ 'impressions', 'total impressions' ],
			units	=>	[ 'per 1000', 'per 1000 impressions', 'per m', 'per hour' ],
		},
		'6ColourImpression'	=> {
			range_units => [ 'impressions', 'total impressions' ],
			units	=>	[ 'per 1000', 'per 1000 impressions', 'per m', 'per hour' ],
		},
		'7ColourImpression'	=> {
			range_units => [ 'impressions', 'total impressions' ],
			units	=>	[ 'per 1000', 'per 1000 impressions', 'per m', 'per hour' ],
		},
		'8ColourImpression'	=> {
			range_units => [ 'impressions', 'total impressions' ],
			units	=>	[ 'per 1000', 'per 1000 impressions', 'per m', 'per hour' ],
		},
);

$cache_field = 'name';
sub cache_field {
	return $cache_field;
}

sub save {
	my ( $self, $params ) = @_;

	$self->set( $params ) if $params;

	if ( $$self{category} and ! $$self{category_id} ) {
		my $Category = new openprint::ServiceCategory();
		if ( ! $Category->save({ name=>$$self{category} }) ) {
			$$self{category_id} = $Category->id();
		}
	} # end if
	$$self{owner_id} = $session{company_id} if ! $$self{owner_id};

	if ( ( my $error = $self->SUPER::save( ) ) ) {
		return $error;
	} # end if
	return '';

} # end sub save

sub destroy {
	my $self = shift;

	delete $openprint::Object::cache{'openprint::Service'}{$$self{id}} if $openprint::Object::cache{'openprint::Service'};	
	my $ac = sql::start_transaction($dbh);
	sql::execute(undef, undef, q{DELETE FROM Service_Prices WHERE service_id=?}, $$self{id});
	$self->SUPER::destroy();
	sql::end_transaction($dbh, $ac);
	return $dbh->errstr() if $dbh->errstr();
  return '';
} # end sub delete

sub prices {
	return openprint::ServicePrice->find( service_id=>$_[0]{id} );
} # end sub prices

sub get_Price {
  my ( $self, $quantity, $Equipment, $Pricelist, $period ) = @_;

  my %price = $self->get_price($quantity, $Equipment, $Pricelist, $period);
  if (%price) {
    my $price = \%price;
    bless $price, 'openprint::ServicePrice';
    return $price;
  }
  return undef;
} # end sub get_Price

sub Prices {
  my $self = shift;
  $$self{Prices} = shift if @_;
  if (!$$self{Prices}) {
    $$self{Prices} = [ openprint::ServicePrice->find( 'period_end is null'=>1, order=>'min NULLS FIRST, max NULLS FIRST', service_id=>$$self{id}) ];
  }
  return @{$$self{Prices}} if wantarray;
  return $$self{Prices};
}

sub get_price {
  my ( $self, $quantity, $Equipment, $Pricelist, $period ) = @_;
  if (! $$self{id}) {
    my ( $caller, undef, $line ) = caller;
    $openprint::log->error("Service::get_price called without id from $caller:$line");
    return ;
  }

	if (!$period) {
		$period = 'NOW()';
    #if ( $debug ) {
    #$log->debug("No period specified defaulting to $period");
    #} # end if
	} # end if

	$Pricelist = $openprint::Pricelist if ! $Pricelist;
  my %price = openprint::pricing::get_best_price_object(
			$openprint::session{company_id}, $$self{id}, $$Pricelist{id}, $self, $quantity, $$Equipment{id}, $period );

	if (!%price) {
# Populating these breaks tests for if a price was returned
    #$price{ServiceName} = $$self{name};
    #$price{Service} = $self;
		$log->debug("No price returned for $$self{name} $$Equipment{strid} $quantity $period") if $debug;
		return;
	} # end if

	$price{currency_id} = $Pricelist->currency_id();
	$price{ServiceName} = $$self{name};
	$price{Service} = $self;
  $price{range_units} //= '';
  $price{units} //= '';
	openprint::Currency::convert( \%price ) if $$Pricelist{currency_id} != $openprint::session{Currency_id};
	return %price;
} # end sub get_price

sub next {
	my ($self, $params) = shift;
	my $sql = q{SELECT min(name) FROM Services WHERE name > ?};
	my @values = ($$self{name});
	if ( $params and $$params{category_id} ) {
		$sql .= ' AND category=?';
		push @values, $$params{category_id};
	} # end if
    my ($name) = sql::execute( undef, undef, $sql, @values );
	( $_ ) = sql::execute( undef, undef, q{SELECT id FROM Services WHERE name=?}, $name );
    return $_;
} # end sub next

sub Next {
	my ($self, $params) = shift;
	return new openprint::Service( $self->next($params) );
} # end sub Next

sub prev {
    my ( $self, $params ) = shift;
	my $sql = q{SELECT max(name) FROM Services WHERE name < ?};
	my @values = ($$self{name});
	if ( $params and $$params{category_id} ) {
		$sql .= ' AND category=?';
		push @values, $$params{category_id};
	} # end if
    my ($name) = sql::execute( undef, undef, $sql, @values );
	( $_ ) = sql::execute( undef, undef, q{SELECT id FROM Services WHERE name=?}, $name );
    return $_;
} # end sub next

sub Previous {
	my ($self, $params) = shift;
	return new openprint::Service( $self->prev($params) );
} # end sub Next

sub category {
    my ( $self, $category ) = @_;

    if ( defined $category ) {
        $category =~ s/^\s*(.*)\s*$/$1/;
		@$self{'category_id','category'} = sql::execute( undef, undef, q{SELECT id, name FROM Service_Categories WHERE lower(name)=?}, lc $category );
		if ( ! $$self{category_id} ) {
			$$self{category} = $category;
		} # end if
    } elsif ( $$self{category_id} and ! $$self{category} ) {
        $$self{category} = new openprint::ServiceCategory( $$self{category_id} )->name();
    } # end if
    return $$self{category};
} # end sub category

sub Category {
  my $self = shift;
  if ( !exists $$self{Category} ) {
    $$self{Category} = new openprint::ServiceCategory($$self{category_id});
  }
  return $$self{Category};
}

sub ServiceType {
  my $self = shift;
  if ( !exists $$self{ServiceType} ) {
    $$self{ServiceType} = new openprint::ServiceType($$self{servicetype_id});
  }
  return $$self{ServiceType};
}

sub Supplier {
  my $self = shift;
  if ( !exists $$self{Supplier} ) {
    $$self{Supplier} = new openprint::Company($$self{supplier_id});
  }
  return $$self{Supplier};
}
sub Owner {
  my $self = shift;
  if ( !exists $$self{Owner} ) {
    $$self{Owner} = new openprint::Company($$self{owner_id});
  }
  return $$self{Owner};
}

sub link_to {
	my $self = shift;
	return '<a href="/administrator/services/edit.html?service_id='.$$self{id}.'">'.(@_?$_[0]:$$self{name}).'</a>';
}

1;
__END__
