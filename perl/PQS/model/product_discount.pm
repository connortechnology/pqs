package PQS::model::product_discount;

use strict;
use warnings;
no warnings qw(uninitialized);

use session;


use Data::Dumper;


sub insert {
	my @row = @_;
print STDERR "HAVE ROW: ", Dumper(@row);
	my $dbh = session::dbh;
	$dbh->do(q{Insert INTO product_discount VALUES ( ?, ?, ?, ? ) }, undef, @row);
}
sub delete {
	my @row = @_;

	my $dbh = session::dbh;
	$dbh->do(q{Delete From product_discount WHERE product = ? AND discount = ? }, undef, @row);
}

sub clear_product {
	my $id = shift;

	my $dbh = session::dbh;
	$dbh->do(q{Delete FROM product_discount WHERE product = ? }, undef, $id);
}

sub get_discount {

	my $product = shift;
	my $q 		= shift;
	
	my $dbh = session::dbh;


	my $d =  $dbh->selectrow_array(q{
		SELECT discount FRom product_discount WHERE product = ? 
		AND (min <= ? OR min is NULL ) AND (MAX >= ? OR MAX is NULL) 
	}, undef, $product,  $q, $q );

	print STDERR "VERSIOINS ", Dumper($product, $q, $d );

	return $d;
}
sub array_for_item {
	my $id = shift;
	my $dbh = session::dbh;

	my $data = $dbh->selectall_arrayref(q{
		SELECT *  from product_discount WHERE product = ? ORDER by min nulls first
	}, {Slice => {}}, $id);
	
	return $data;

}

1;
