package PQS::model::product_markup;

use strict;
use warnings;
no warnings qw(uninitialized);

use session;
use Data::Dumper;





sub get {
  my ($cust, $cat) = @_;
  my $dbh = session::dbh;

  my $id = $dbh->selectrow_array("select markup from product_markup where customer = ? and category = ?", undef, $cust, $cat);
}






1;
