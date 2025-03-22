use strict;
package openprint::paper_price;
our @ISA = qw(openprint::price);

sub save {
	my $self = shift;

	if ( ! $self->{Price} ) {
		$self->{Price} = $self->{Cost} * ( 1 + $self->{Markup}/100 );
	} # end if

	sql::insert( $self->{log}, $self->{dbh}, 'Paper_Prices', [
		'lngListIndex',			$self->{group}->{list_index},
		'lngPaperIndex',		$self->{group}->{product_index},
		'lngMin',				( $self->{min} eq '' ? undef : $self->{min} ),
		'lngMax',				( $self->{max} eq '' ? undef : $self->{max} ),
		'strUnits',				( $self->{units} eq '' ? undef : $self->{units} ),
		'dblCost',				( $self->{Cost} eq '' ? undef : $self->{Cost} ),
		'dblMarkup',			( $self->{Markup} eq '' ? undef : $self->{Markup} ),
		'dblPrice',				( $self->{Price} eq '' ? undef : $self->{Price} ),
		'ysnDiscountable',      ( $self->{Discountable} eq '' ? 'Y' : $self->{Discountable} )
		]

	);
} # end sub save

1;
__END__
