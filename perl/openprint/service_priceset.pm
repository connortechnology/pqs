use strict;
package openprint::service_priceset;
our @ISA = qw(openprint::priceset);

require openprint::service_price;

sub save {
	my $self = shift;

	$_ = "DELETE FROM Service_Prices WHERE service_id=? AND pricelist_id = ?";
	$_ .= "AND equipment_id = '".$self->{equipment_index}."'\n" if $self->{equipment_index};
	$_ .= "AND ($self->{qty} :: numeric >= min OR min IS NULL) AND ($self->{qty} :: numeric <= max OR max IS NULL)" if $self->{qty};
	sql::execute( $self->{log}, $self->{dbh}, $_, $self->{product_index}, $self->{list_index} );

	foreach my $price ( @{$self->{prices}} ) {
		$price->save();
	} # end foreach
}

sub load {
	my $self = shift;

	my @values = @$self{'product_index','list_index'};
	my $sql = 'SELECT service_id, equipment_id, period_start, period_end, Min, Max, Range_Units, Units, Cost, Markup, Price, Discountable,mode FROM Service_Prices WHERE service_id=? AND pricelist_id=?';
	if ( $self->{equipment_index} ) {
		$sql .= ' AND (equipment_id=? OR equipment_id IS NULL)';
		push @values, $self->{equipment_index};
	} # end if
	if ( $self->{qty} ) {
		$sql .= ' AND (? >= Min OR Min IS NULL) AND (? <= Max OR Max IS NULL)';
		push @values, @$self{'qty','qty'};
	} # end if
	if ( $self->{period} ) {
		$sql .= ' AND (? >= period_start OR period_start IS NULL) AND (? <= period_end OR period_end IS NULL)';
		push @values, @$self{'period','period'};
	} # end if
	my @records = sql::execute( $openprint::log, undef, $sql, @values );
	while ( @records ) {
		my $price = openprint::service_price->new( $self->{log}, $self->{dbh}, $self );
		$price->set( splice @records, 0, 13 );
		push @{$self->{prices}}, $price;
	} # end while
}

1;
__END__
