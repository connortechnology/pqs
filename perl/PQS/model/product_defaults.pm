package PQS::model::product_defaults;

use strict;
use warnings;

use session;
use Data::Dumper;

sub delete {
  my $id = shift;
  my $dbh = session::dbh;
  $dbh->do(q{delete from product_defaults where category = ?},undef,  $id);
}

sub insert {
  my ($cat, $name, $value) = @_;
  my $dbh = session::dbh;
  $dbh->do(q{insert into product_defaults (category, name, value) values ( ?, ?, ? ) },undef, $cat, $name, $value);
}

sub get {
  my ($id) = @_;
  my $dbh = session::dbh;

  return $dbh->selectall_arrayref("select * from product_defaults where category = ?", {Slice=>{}}, $id);
}

1;
__END__
