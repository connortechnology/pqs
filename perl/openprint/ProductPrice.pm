use strict;
package openprint::ProductPrice;
our @ISA = qw(openprint::Object);

require openprint;
require openprint::Pricelist;
require openprint::Product;
require Math::Round;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'Product_Prices';
$serial = 'product_prices_id_seq';
%fields = (
	id				=>	'id',
	product_id		=>	'product_id',
	pricelist_id	=>	'pricelist_id',
	min				=>	'min',
	max				=>	'max',
	units			=>	'units',
	cost			=>	'cost',
	markup			=>	'markup',
	price			=>	'price',
	discountable	=>	'discountable',
	owner_id		=>	'owner_id',
	supplier_id		=>	'supplier_id',
);
%transforms = (
	id			=>	[ 's/\D//g' ],
	supplier_id	=>	[ 's/\D//g' ],
	product_id	=>	[ 's/\D//g' ],
	pricelist_id	=>	[ 's/\D//g' ],
	min			=>	[ 's/\D//g' ],
	max			=>	[ 's/\D//g' ],
	cost			=>	[ 's/[^\d\.]//g' ],
	markup		=>	[ 's/[^\d\.]//g' ],
	price			=>	[ 's/[^\d\.]//g' ],
);
%defaults = (
	min			      =>	undef,
	max		      	=>	undef,
	supplier_id 	=>	undef,
	cost		      =>	0,
	markup	    	=>	0,
	price	      	=>	0,
	discountable	=>	1,
	owner_id    	=>	q`$session{company_id}`,
);


sub Product {
    my $self = shift;
	if ( @_ ) {
		my $Product = shift;
		$$self{product_id} = $Product->id();
	} # end if
    return new openprint::Product( $$self{product_id} );
} # end sub Product

sub Pricelist {
    my $self = shift;
	if ( @_ ) {
		my $Pricelist = shift;
		$$self{pricelist_id} = $Pricelist->id();
	} # end if
    return new openprint::Pricelist( $$self{pricelist_id} );
} # end sub Pricelist

sub save {
	my ( $self, $param ) = @_;

	$$self{owner_id} = $openprint::config{owner_id} if ! $$self{owner_id};

	if ( ( my $error = $self->SUPER::save( $param ) ) ) {
		return $error;
	} # end if
} # end sub save

sub price {
	if ( @_ > 1 ) {
		$_[0]{price} = $_[1];
	} # end if
	if ( ! defined $_[0]{price} ) {
		$_[0]{price} = Math::Round::nearest( 0.01, $_[0]{cost} * ( 1+($_[0]{markup}/100) ) );
	} # end if
	return $_[0]{price};
} # end sub price

1;
__END__
