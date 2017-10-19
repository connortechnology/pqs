package PQS::model::products;

use strict;
use warnings;
no warnings qw(uninitialized);

use session;
use Data::Dumper;
#use PQS::model::foreign_reference;

sub list {
  my $dbh = session::dbh;
  return $dbh->selectall_arrayref("select * from tbl_products order by name", {Slice => {}});
}

sub kit_list {
	my $dbh 	= session::dbh;
	my $id = shift;
  	return $dbh->selectall_arrayref("select * from kit, tbl_products WHERE kit.id = ? AND tbl_products.id = kit.product ORDER by kit.sort",{Slice => {}}, $id);
}

sub lead_time {
  my $dbh 	= session::dbh;
  my $id 	= shift;

  return $dbh->selectrow_array("select lead_time from tbl_products WHERE id = ?",undef, $id);
}

sub get {
  my ($id) = @_;
  my $dbh = session::dbh;

  my $product = $dbh->selectrow_hashref("select * from tbl_products where id = ?",undef, $id);
}
sub get_name_from_id {
  my ($str) = @_;
  my $dbh = session::dbh;

  my $id = $dbh->selectrow_array("select name from tbl_products where id = ?", undef, $str);
  print STDERR "FOUND ID: $id FROM $str \n";
  return $id;
}

sub get_id_from_str {
  my ($str) = @_;
  my $dbh = session::dbh;

  my $id = $dbh->selectrow_array("select id from tbl_products where strid = ?", undef, $str);
  print STDERR "FOUND ID: $id FROM $str \n";
  return $id;
}

sub insert {
  my ($str) = @_;
  my $dbh = session::dbh;

  my $product = $dbh->do("insert into tbl_products ( name ) values ( ? )" , undef, $str);
  my  $id = $dbh->last_insert_id('', 'public', 'tbl_products', 'id');
 print STDERR "HAVE ID FOR INSERT: $id -- $str \n";
 return $id;
  
}

sub update_category {
  my ($id, $cat) = @_;
  my $dbh = session::dbh;
  my $product = $dbh->do("UPDATE tbl_products set category  = ? WHERE id = ?" , undef, $cat, $id);
 }


sub update {
  my ($id, $data) = @_;
  my $dbh = session::dbh;

  my @names;
  my @values;

  map { push @names, $_->{name}; push @values, $_->{value} } @{$data};

  my $columns = join ',', @names;
  
  my $placeholders = join ',', ('?') x keys @names;
  
  my $product = $dbh->do("UPDATE tbl_products set ( $columns ) = ( $placeholders) WHERE id = ?" , undef, @values, $id);


}



sub add_foreign_ref {
  my ($id, $ref_id, $ref_name) = @_;
#  PQS::model::foreign_reference::add($id, 'products', $ref_id, $ref_name);
}
sub remove {
	my $id = shift;
	my $dbh = session::dbh;
	$dbh->do("delete from tbl_products where id = ?", undef, $id);	
}

1;
