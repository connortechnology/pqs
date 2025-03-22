use strict;
package openprint::service_price;
our @ISA = qw(openprint::price);

sub save {
	my $self = shift;

	if ( ! $self->{Price} ) {
		$self->{Price} = $self->{Cost} * ( 1 + $self->{Markup}/100 );
	} # end if

	sql::insert( $self->{log}, $self->{dbh}, 'Service_Prices',
		'pricelist_id',		$self->{group}->{list_index},
		'service_id',		$self->{group}->{product_index},
		'equipment_id',		$self->{equipment_index},
		'supplier_id',		$$self{'supplier_id'},
		'period_start',		( $self->{period_start} eq '' ? undef : $self->{period_start} ),
		'period_end',				( $self->{period_end} eq '' ? undef : $self->{period_end} ),
		'min',				( $self->{min} eq '' ? undef : $self->{min} ),
		'max',				( $self->{max} eq '' ? undef : $self->{max} ),
		'range_units',			( $self->{range_units} eq '' ? undef : $self->{range_units} ),
		'units',			( $self->{units} eq '' ? undef : $self->{units} ),
		'cost',				( $self->{Cost} eq '' ? undef : $self->{Cost} ),
		'markup',			( $self->{Markup} eq '' ? undef : $self->{Markup} ),
		'price',			( $self->{Price} eq '' ? undef : $self->{Price} ),
		'discountable',		( $self->{Discountable} eq '' ? 'Y' : $self->{Discountable} )
	);
} # end sub save

sub set {
	@{$_[0]}{'self','service_id','equipment_index','period_start','period_end','min','max','range_units','units','Cost','Markup','Price','discountable','mode'} = @_;
} # end sub set

1;
__END__
