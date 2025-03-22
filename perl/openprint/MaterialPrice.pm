use strict;
use warnings;

package openprint::MaterialPrice;
our @ISA = qw( openprint::Object );

require sql;
require openprint::Object;
use Math::Round qw(nearest);

require openprint::logs;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'tbl_material_prices';
$serial = 'materialprices_id_seq';

%fields = (
	id							=>  'id',
	pricelist_id		=>	'lnglistindex',
	material_id			=>	'lngmaterialindex',
	equipment_id		=>	'lngequipmentindex',
	min							=>	'lngmin',
	max							=>	'lngmax',
	range_units			=>	'range_units',
	units						=>	'strunits',
	cost						=>	'dblcost',
	markup					=>	'dblmarkup',
	price						=>	'dblprice',
	discountable		=>	'ysndiscountable',
	interpolate			=>	'interpolate',
);
%transforms = (
	min			=>	[ 's/[^\d\.\-]//g' ],
	max			=>	[ 's/[^\d\.\-]//g' ],
	cost		=>	[ 's/[^\d\.\-]//g' ],
	markup	=>	[ 's/[^\d\.\-]//g' ],
	price		=>	[ 's/[^\d\.\-]//g' ],
);
%defaults = (
	min						=>	undef,
	max						=>	undef,
	cost					=>	undef,
	markup				=>	undef,
	price					=>	undef,
	equipment_id	=>	undef,
	discountable	=>	q`'Y'`,
	interpolate		=>	0,
);

sub next {
	my $self = shift;
	return new openprint::MaterialPrice( sql::execute( undef,undef, q{SELECT MIN(id) FROM 'tbl_material_prices WHERE id > ?}, $$self{id} ) );
} # end sub next

sub Pricelist {
	return new openprint::Pricelist( $_[0]{pricelist_id} );
}
sub Equipment {
	return new openprint::Equipment( $_[0]{equipment_id} );
} # end sub Equipment

sub Material {
	return new openprint::Material( $_[0]{material_id} );
} # end sub Material

sub markup {
	if ( @_ > 1 ) {
		$_[0]{markup} = $_[0]->transform(markup=>$_[1]);
		$_[0]->price(undef);
	} # end if
	return $_[0]{markup};
} # end sub markup

sub cost {
	if ( @_ > 1 ) {
		$_[0]{cost} = $_[0]->transform(cost=>$_[1]);
		$_[0]->price(undef);
	} # end if
	return $_[0]{cost};
} # end sub cost

sub price {
	if ( @_ > 1 ) {
		$_[0]{price} = $_[1];
	} # end if
	my $self = $_[0];
	if ( ! defined $_[0]{price} ) {
		$_[0]{price} = Math::Round::nearest( .00001, $_[0]{cost} * ($_[0]{markup}? 1+($_[0]{markup}/100) : 1 ) ) if $_[0]{cost};
	} # end if
	return $_[0]{price};
} # end sub price

1;
__END__
