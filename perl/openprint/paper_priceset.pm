use strict;
package openprint::paper_priceset;
our @ISA = qw(openprint::priceset);

require openprint::paper_price;

sub save {
	my $self = shift;

	$_ = "DELETE FROM Paper_Prices WHERE lngPaperIndex='" . $self->{product_index} . "'\n".
		"AND lngListIndex = '" . $self->{list_index} .  "'\n";
	$_ .= "AND ($self->{qty} :: numeric >= lngMin OR lngMin isNull) AND ($self->{qty} :: numeric <= lngMax OR lngMax isNull)" if $self->{qty};
	sql::execute( $self->{log}, $self->{dbh}, $_ );

	foreach my $price ( @{$self->{prices}} ) {
		$price->save();
	} # end foreach
}

sub load {
	my $self = shift;

    $_ = "SELECT lngMin, lngMax, strUnits, dblCost, dblMarkup, dblPrice, ysnDiscountable\n".
         "FROM Paper_Prices\n".
         "WHERE lngPaperIndex = '".$self->{product_index}."' ".
         "AND lngListIndex = '".$self->{list_index}."' ";
	$_ .= "AND ($self->{qty} :: numeric >= lngMin OR lngMin isNull) AND ($self->{qty} :: numeric <= lngMax OR lngMax isNull)" if $self->{qty};
    my @records = sql::execute( $self->{log}, $self->{dbh}, $_ );
    while ( @records ) {
		my $price = openprint::service_price->new( $self->{log}, $self->{dbh}, $self );
		$price->set( undef, splice @records, 0, 7 );
		push @{$self->{prices}}, $price;
    } # end while
}

1;
__END__
