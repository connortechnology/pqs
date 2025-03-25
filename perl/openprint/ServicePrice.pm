use strict;
require sql;
require openprint::Object;
require Math::Round;
package openprint::ServicePrice;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults );

$debug = 1;
$table = 'tbl_service_prices';
$serial = 'service_prices_id_seq';

%fields = (
	id							=>	'id',
	owner_id				=>	'owner_id',
	pricelist_id		=>	'lnglistindex',
	service_id			=>	'lngserviceindex',
	equipment_id		=>	'lngequipmentindex',
	min							=>	'lngmin',
	max							=>	'lngmax',
	range_units			=>	'range_units',
	units						=>	'strunits',
	cost						=>	'dblcost',
	markup					=>	'dblmarkup',
	price						=>	'dblprice',
	discountable		=>	'ysndiscountable',
	mode						=>	'mode',
	supplier_id			=>	'supplier_id',
	period_start		=>	'period_start',
	period_end			=>	'period_end',
);
%find_fields  = 	(
	service_name	=>	'(SELECT strname from tbl_services WHERE tbl_services.lngindex=lngserviceindex)',
);
%defaults = (
	min							=>	undef,
	max							=>	undef,
	cost						=>	undef,
	markup					=>	undef,
	price						=>	undef,
	discountable		=>	q`'Y'`,
	mode						=>	undef,
	period_start    =>  undef,
	period_end      =>  undef,
	supplier_id			=>	undef,
	equipment_id		=>	undef,
	owner						=>	q`$openprint::Owner->id()`,
);

%transforms = (
	min		=>	[ 's/[^\d\.\-]//g' ],
	max		=>	[ 's/[^\d\.\-]//g' ],
	cost	=>	[ 's/[^\d\.\-]//g' ],
	markup	=>	[ 's/[^\d\.\-]//g' ],
	price	=>	[ 's/[^\d\.\-]//g' ],
	units					=>	[ 's/^\s+//', 's/\s+$//' ],
	range_units					=>	[ 's/^\s+//', 's/\s+$//' ],
);

sub next {
	return new openprint::ServicePrice( sql::execute( undef,undef, q{SELECT MIN(id) WHERE id > ?}, $_[0]{id} ) );
} # end sub next

sub Pricelist {
	return new openprint::Pricelist( $_[0]{pricelist_id} );
}
sub Equipment {
	return new openprint::Equipment( $_[0]{equipment_id} );
}
sub Service {
	return new openprint::Service( $_[0]{service_id} );
}

sub price {
	if ( @_ > 1 ) {
		$_[0]{price} = $_[1];
	} # end if
	if ( ! defined $_[0]{price} ) {
		$_[0]{price} = $_[0]{markup} ? Math::Round::nearest( 0.01, $_[0]{cost} * ( 1+($_[0]{markup}/100) ) ) : $_[0]{cost};
	} # end if
	return $_[0]{price};
} # end sub price

sub markup {
	if ( @_ > 1 ) {
		$_[0]{markup} = $_[1];
		$_[0]->price( undef );
	} # end if
	return $_[0]{markup};
} # end sub markup

sub cost {
	if ( @_ > 1 ) {
		$_[0]{cost} = $_[1];
		$_[0]->price( undef );
	} # end if
	return $_[0]{cost};
} # end sub cost

sub total {
  my $self = shift;
  $$self{total} = shift if @_;
  return $$self{total};
}

sub id_string {
	my $Price = $_[0];
	my $price_desc = '';
	if ( ! ( $Price->min() or $Price->max() ) ) {
		$price_desc .= 'all quantities';
	} else {
		if ( $Price->min() ) {
			$price_desc .= 1*$Price->min() . ' ';
		}
		$price_desc .= 'up';
		if ( $Price->max() ) {
			$price_desc .= ' to ' . 1*$Price->max();
		}
	} # end if
	return $Price->Pricelist()->name() . ' '. $price_desc . ' on ' . $Price->Equipment()->strid();
}

sub to_string {
  my $Price = $_[0];
  my $price_desc = '';
  if ( ! ( $Price->min() or $Price->max() ) ) {
    $price_desc .= 'all quantities';
  } else {
    if ( $Price->min() ) {
      $price_desc .= 1*$Price->min() . ' ';
    }
    $price_desc .= 'up';
    if ( $Price->max() ) {
      $price_desc .= ' to ' . 1*$Price->max();
    }
  } # end if
  return $Price->Pricelist()->name() . ' '. $price_desc . ' on ' . $Price->Equipment()->strid() .sprintf( '%s to %s $%.2f*%.2f% = $%.2f%s<br/>',
            $Price->min(), $Price->max(), $Price->cost(), $Price->markup(), $Price->price(), $Price->units() );

}

1;
__END__
