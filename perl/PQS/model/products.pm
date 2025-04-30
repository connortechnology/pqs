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
  return $dbh->selectall_arrayref("select kit.*, tbl_products.*, categories.name as cat_name from kit, tbl_products, categories WHERE kit.id = ? AND tbl_products.id = kit.product 
    AND tbl_products.category = categories.id ORDER by kit.sort",{Slice => {}}, $id);
}

sub add_kit_item {
	my $dbh 	= session::dbh;
	my $id  = shift;
	my $prod = shift;
	my $qty = shift;
	$dbh->do(q{INSERT INTO kit ( id, product, qty ) values ( ?, ?, ?)}, undef, $id, $prod, $qty);
}

sub remove_kit_category {
	my $dbh 	= session::dbh;
	my $id  = shift;
	my $cat  = shift;

  print STDERR Dumper("REMOVE KIT Category", $id, $cat);
	$dbh->do(q{DELETE FROM kit WHERE id=? AND product IN ( SELECT id from tbl_products Where category = ?)}, undef, $id, $cat);
}

sub remove_kit_item {
	my $dbh 	= session::dbh;
	my $id  = shift;
	my $prod = shift;
	$dbh->do(q{DELETE FROM kit WHERE id = ? and product = ?}, undef, $id, $prod);
}

sub lead_time {
  my $dbh 	= session::dbh;
  my $id 	= shift;

  return $dbh->selectrow_array("SELECT lead_time FROM tbl_products WHERE id = ?",undef, $id);
}

sub get {
  my ($id) = @_;
  my $dbh = session::dbh;

  my $product = $dbh->selectrow_hashref("select * from tbl_products where id = ?",undef, $id);
}

sub get_name_from_id {
  my ($id) = @_;
  my $dbh = session::dbh;

  my $name = $dbh->selectrow_array("select name from tbl_products where id = ?", undef, $id);
  print STDERR "FOUND ID: $id FROM $name \n";
  return $name;
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
  my $product = $dbh->do('UPDATE tbl_products set category=? WHERE id=?', undef, $cat, $id);
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

sub delete_products_in_category {
	my $cat = shift;
	my $dbh = session::dbh;
	$dbh->do("delete from tbl_products where category = ?", undef, $cat);	
}

sub remove {
	my $id = shift;
	my $dbh = session::dbh;
	$dbh->do("delete from tbl_products where id = ?", undef, $id);	
}

1;
