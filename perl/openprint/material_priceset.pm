package openprint::material_priceset;
@ISA = qw(openprint::priceset);
use strict;

require openprint::material_price;

sub save {
	my $self = shift;

	$self->{log}->debug( "Saving priceset" );

	$_ = "DELETE FROM tbl_Material_Prices WHERE lngMaterialIndex='" . $self->{product_index} . "'\n".
		"AND lngListIndex = '" . $self->{list_index} . "'\n";
	$_ .= "AND lngEquipmentIndex = '".$self->{equipment_index}."'\n" if $self->{equipment_index};
	$_ .= "AND ($self->{qty} :: numeric >= lngMin OR lngMin isNull) AND ($self->{qty} :: numeric <= lngMax OR lngMax isNull)" if $self->{qty};
	sql::execute( $self->{log}, $self->{dbh}, $_ );

	foreach my $price ( @{$self->{prices}} ) {
		$price->save();
	} # end foreach
}

sub load {
	my $self = shift;

	my @values = ( @$self{'product_index','list_index'} );
    my $sql = 'SELECT lngEquipmentIndex, lngMin, lngMax, range_units, strUnits, dblCost, dblMarkup, dblPrice, ysnDiscountable FROM tbl_Material_Prices WHERE lngMaterialIndex=? AND lngListIndex=?';
	if ( $self->{equipment_index} ) {
		$sql .= ' AND (lngEquipmentIndex=? OR lngEquipmentIndex IS NULL)';
		push @values, $self->{equipment_index};
	} # end if
	if ( $self->{'qty'} ) {
		$sql .= ' AND (? >= lngMin OR lngMin IS NULL) AND ( ? <= lngMax OR lngMax IS NULL)';
		push @values, @$self{'qty','qty'};
	} # end if
    my @records = sql::execute( 0, undef, $sql, @values );

    while ( @records ) {
		my $price = openprint::material_price->new( $self->{log}, $self->{dbh}, $self );
		$price->set( splice @records, 0, 9 );
		push @{$self->{prices}}, $price;
    } # end while
} # end sub load

1;

__END__
~       
