package openprint::priceset;

use strict;

require openprint::price;
require openprint::Pricelist;

sub new {
	my ( $type, $log, $dbh, $list_index, $product_index, $equipment_index, $qty, $period ) = @_;
	my $self = {};
	bless $self, $type;

	$self->{log} = $log;
	$self->{dbh} = $dbh;
	$self->{period} = $period;
	$self->{list_index} = $list_index;
	$self->{product_index} = $product_index;
	$self->{equipment_index} = $equipment_index;
	$self->{qty} = $qty;
	my $Pricelist = new openprint::Pricelist( $self->{list_index} );
	$$self{currency_id} = $Pricelist->currency_id();

	@{$self->{prices}} = ();
	return $self;
}

sub save {
	my $self = shift;

	$self->{log}->error( "Saving priceset" );

	$_ = "DELETE FROM " . $self->{table}. " WHERE lngIndex='" . $self->{product_index} . 
		"' AND lngListIndex = '" . $self->{list_index} .  "'";
	$_ .= "AND lngEquipmentIndex = '".$self->{equipment_index}."'\n" if $self->{equipment_index};
	$_ .= "AND ($self->{qty} :: numeric >= lngMin OR lngMin isNull) AND ($self->{qty} :: numeric <= lngMax OR lngMax isNull)" if $self->{qty};
	sql::execute( $self->{log}, $self->{dbh}, $_ );

	foreach my $price ( @{$self->{prices}} ) {
		$price->save();
	} # end foreach
}

sub load {
	my $self = shift;
$$self{log}->error("DEPRECATED pricelist::load");
	my $Pricelist = new openprint::Pricelist( $self->{list_index} );

	my @values = @$self{'product_index','list_index'};
	my $sql = 'SELECT lngEquipmentIndex, lngMin, lngMax, range_units, strUnits, dblCost, dblMarkup, dblPrice, interpolate FROM '. $self->{table};
	$sql .= 'WHERE lngIndex=? AND lngListIndex=?';
	if ( $self->{equipment_index} ) {
		$sql .= ' AND lngEquipmentIndex=?';
		push @values, $self->{equipment_index};
	} # end if
	if ( $self->{qty} ) {
		$sql .= ' AND (? >= lngMin OR lngMin IS NULL) AND (? <= lngMax OR lngMax IS NULL)';
		push @values, @$self{'qty','qty'};
	} # end if
	if ( $self->{period} ) {
		$sql .= ' AND (? >= period_start OR period_start IS NULL) AND (? <= period_end OR period_end IS NULL)';
		push @values, @$self{'period','period'};
	} # end if
    my @records = sql::execute( $self->{log}, undef, $sql, @values );
    while ( @records ) {
		my $price = openprint::price->new( $self->{log}, $self->{dbh}, $self );
		$price->set( splice @records, 0, 9 );
		$$price{currency_id} = $Pricelist->currency_id();
		push @{$self->{prices}}, $price;
    } # end while
}

sub addPrice {
	my $self = shift;
	my $price = shift;

	push @{$self->{prices}}, $price;
} # end sub addPrice

1;
__END__
