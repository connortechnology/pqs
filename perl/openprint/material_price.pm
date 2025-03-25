package openprint::material_price;
@ISA = qw(openprint::price);
use strict;

require openprint::logs;

sub save {
	my $self = shift;

	if ( ! $self->{Price} ) {
		$self->{Price} = $self->{Cost} * ( 1 + $self->{Markup}/100 );
	} # end if

	sql::insert( $self->{log}, $self->{dbh}, 'tbl_Material_Prices',
		'lngListIndex',			$self->{group}->{list_index},
		'lngMaterialIndex',		$self->{group}->{product_index},
		'lngEquipmentIndex',	$self->{equipment_index},
		'lngMin',				( $self->{min} eq '' ? undef : $self->{min} ),
		'lngMax',				( $self->{max} eq '' ? undef : $self->{max} ),
		'range_units',				( $self->{range_units} eq '' ? undef : $self->{range_units} ),
		'strUnits',				( $self->{units} eq '' ? undef : $self->{units} ),
		'dblCost',				( $self->{Cost} eq '' ? undef : $self->{Cost} ),
		'dblMarkup',			( $self->{Markup} eq '' ? undef : $self->{Markup} ),
		'dblPrice',				( $self->{Price} eq '' ? undef : $self->{Price} ),
		'ysnDiscountable',      ( $self->{Discountable} eq '' ? 'Y' : $self->{Discountable} )

	);
	
	# Add record to audit log - action "Update Material".
	openprint::logs::insertLogRecord('44', "List Index: " . $self->{group}->{list_index} . " Material Index: " . $self->{group}->{product_index},);
} # end sub save

1;

__END__
~       
