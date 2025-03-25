use strict;
package openprint::product_priceset;
our @ISA = qw(openprint::priceset);

require openprint::product_price;
require openprint::Pricelist;

sub save {
	my $self = shift;

	$_ = "DELETE FROM Product_Prices WHERE Product_Id='" . $self->{product_index} . "'\n".
		"AND pricelist_id = '" . $self->{list_index} .  "'\n";
	$_ .= "AND ($self->{qty} :: numeric >= min OR min IS NULL) AND ($self->{qty} :: numeric <= max OR max IS NULL)" if $self->{qty};
	sql::execute( undef, undef, $_ );

	foreach my $price ( @{$self->{prices}} ) {
		$price->save();
	} # end foreach
}

sub load {
	my $self = shift;

	my $Pricelist = new openprint::Pricelist( $self->{list_index} );

  $_ = q{SELECT min, max, '', units, cost, markup, price, discountable FROM Product_Prices
  WHERE product_id=? AND pricelist_id=?};
  $_ .= "AND ($self->{qty} :: numeric >= min OR min is NULL) AND ($self->{qty} :: numeric <= max OR max IS NULL)" if $self->{qty};
  my @records = sql::execute( $openprint::log, $openprint::dbh, $_, @$self{'product_index','list_index'} );
  while ( @records ) {
    my $price = openprint::product_price->new( $self->{log}, $self->{dbh}, $self );
    $price->set( undef, splice @records, 0, 8 );
    $$price{'currency_id'} = $Pricelist->currency_id();
    push @{$self->{prices}}, $price;
  } # end while
}

1;
__END__
