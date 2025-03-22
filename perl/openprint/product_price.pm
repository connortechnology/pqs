use strict;
package openprint::product_price;
our @ISA = qw(openprint::price);

sub save {
	my $self = shift;

	if ( ! $self->{Price} ) {
		$self->{Price} = $self->{Cost} * ( 1 + $self->{Markup}/100 );
	} # end if

	sql::insert( undef, undef, 'Product_Prices',
		'pricelist_id',		$self->{group}->{list_index},
		'product_id',		$self->{group}->{product_index},
		'min',				( $self->{min} eq '' ? undef : $self->{min} ),
		'max',				( $self->{max} eq '' ? undef : $self->{max} ),
		'units',			( $self->{units} eq '' ? undef : $self->{units} ),
		'cost',				( $self->{Cost} eq '' ? undef : $self->{Cost} ),
		'markup',			( $self->{Markup} eq '' ? undef : $self->{Markup} ),
		'price',			( $self->{Price} eq '' ? undef : $self->{Price} ),
		'Discountable',		( $self->{Discountable} eq '' ? 'Y' : $self->{Discountable} )
	);
} # end sub save

1;
__END__
