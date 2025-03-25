use strict;
package openprint::QuotedProduct;
our @ISA = qw(openprint::Product);

use vars qw( $debug $table $serial %fields %transforms %defaults );

require Math::Round;

$debug = 0;

$table = 'Quoted_Products';
$serial = 'Quoted_Products_id_seq';

%fields = (
		id			=>	'id',
		quantity	=>	'quantity',
		markup		=>	'markup',
		cost		=>	'cost',
		price		=>	'price',
		product_id	=>	'product_id',
		quote_id	=>	'quote_id',
		comments		=>	'comments',
		);

%transforms = (
	quantity	=> [ 's/[^\d\.\-]//g' ],
	markup		=> [ 's/[^\d\.\-]//g' ],
	price		=> [ 's/[^\d\.\-]//g' ],
	cost		=> [ 's/[^\d\.\-]//g' ],
    comments		=> [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);

%defaults = (
	id			=> undef,
	product_id	=>	undef,
	markup		=> undef,
	price		=> undef,
	cost		=> undef,
	quantity	=> 1,
);

sub Quote {
	return new openprint::Quote( $_[0]{quote_id} );
} # end sub Quote

sub Product {
	return new openprint::Product( $_[0]{product_id} );
} # end sub Product

sub description {
	return $_[0]->Product()->description();
}
sub name {
	return $_[0]->Product()->name();
}

sub cost {
	my ( $self, $new_value ) = @_;
	if ( @_ == 2 ) {
		$$self{cost} = $new_value;
	} # end if
	if ( ! defined $$self{cost} ) {
		my %Price = $self->Product()->get_price($self->quantity());
		$$self{cost} = $Price{Price};
	} # end if
	return $$self{cost};
} # end sub cost

sub units {
	my ( $self, $new_value ) = @_;
	if ( @_ == 2 ) {
		$$self{units} = $new_value;
	} # end if
	if ( ! defined $$self{units} ) {
		my %Price = $self->Product()->get_price($self->quantity());
		$$self{units} = $Price{units};
	} # end if
	return $$self{units};
}

sub price {
	my ( $self, $new_value ) = @_;
	if ( @_ == 2 ) {
		$$self{price} = $new_value;
	} # end if
	if ( ! defined $$self{price} ) {
		$$self{price} = Math::Round::nearest(0.01, $self->cost() * ( 1 + $$self{markup}/100 ) );
	} # end if
	return $$self{price};
} # end sub price

sub total {
	my ( $self, $new_value ) = @_;
	if ( @_ == 2 ) {
		$$self{total} = $new_value;
	} # end if
	if ( ! defined $$self{total} ) {
		$$self{total} = Math::Round::nearest(0.01, $self->price() * $$self{quantity});
	} # end if
	return $$self{total};
} # end sub total

sub quantity {
	my ( $self, $new_value ) = @_;
	if ( @_ == 2 ) {
		$$self{quantity} = $new_value;
	} # end if
	return $$self{quantity};
} # end sub total

sub save {
	my $self = shift;
	if ( ( my $error = $self->SUPER::save( @_ ) ) ) {
		return $error;
	} # end if
	my $Quote = $self->Quote();
	delete $$Quote{Products};
	return;
} # end sub save

sub copy {
	no strict 'refs';
	my $type = ref $_[0];
	my $new = new $type;
	my $fields = \%{$type.'::fields'};
	@$new{keys %$fields} = @{$_[0]}{keys %$fields};
	delete $$new{id};

	return $new;
}
1;

__END__
