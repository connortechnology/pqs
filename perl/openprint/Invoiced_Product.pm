use strict;
package openprint::Invoiced_Product;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %defaults %transforms %find_cache );

$debug = 1;
$table = 'invoiced_products';
$serial = 'invoiced_products_id_seq';

%fields = (
	id	  			=>	'id',
	price				=>	'price',
	quantity		=>	'quantity',
	invoice_id	=>	'invoice_id',
	product_id	=>	'product_id',
	description	=>	'description',
	po			  	=>	'po',
);

%transforms = (
);
%defaults = (
	invoice_id	=>	undef,
	product_id	=>	undef,
	price			=>	undef,	# undef means look it up in the Product
	quantity		=>	undef,
);

sub Invoice {
	return new openprint::Invoice( $_[0]{invoice_id} );
} # end sub Invoice

sub Product {
	return new openprint::Product( $_[0]{product_id} );
} # end sub Product

sub name {
	return $_[0]->Product()->name();
} # end sub name

sub total {
	my ( $self ) = @_;
	return $$self{quantity} * $self->price();
} # end sub total

sub price {
	my $self = shift;
  $$self{price} = shift if @_;

	if ( ( ! defined $$self{price} ) and $$self{product_id} ) {
		my %Price = $self->Product()->get_price( $$self{quantity}, { pricelist_id=>$self->Invoice()->Pricelist()->id() } );
$openprint::log->debug("Got price: %Price: " . join(',', map { $_.'=>'.$Price{$_} } keys %Price ) ) if $debug;
		$$self{price} = $Price{Price};
	} # end if
	return $$self{price};
} # end sub price

sub description {
	my ( $self ) = @_;
	if ( ( ! $$self{'description'} ) and $$self{'product_id'} ) {
		$$self{'description'} = $self->Product()->description();
	} # end if
	return $$self{'description'};
} # end if

1;
__END__
