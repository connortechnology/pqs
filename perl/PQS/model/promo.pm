package PQS::model::promo;

use strict;
use warnings;
no warnings qw(uninitialized);

use session;
use Data::Dumper;
#use PQS::model::foreign_reference;


sub next_id {
  my $dbh = session::dbh;
  my $id = $dbh->selectrow_array(q{SELECT nextval('promo_seq')});

}

sub insert {
  my ($str) = @_;
  my $dbh = session::dbh;

  $dbh->do("insert into promo ( name ) values ( ? )" , undef, $str);
  my  $id = $dbh->last_insert_id('', 'public', 'promo', 'id');
 print STDERR "HAVE ID FOR INSERT: $id -- $str \n";
 return $id;
  
}


sub get {
  my ($id) = @_;
  my $dbh = session::dbh;

  my $data = $dbh->selectrow_hashref("select * from promo where id = ?",undef, $id);
}

sub update {
  my ($id, $data) = @_;
  my $dbh = session::dbh;

  my @names;
  my @values;

  map { $data->{$_} = undef unless $data->{$_} } keys %{$data};

  print STDERR "HAVE DATA UP ", Dumper($data);


  map { push @names, $_; push @values, $data->{$_} } keys %{$data};


  my $columns = join ',', @names;
  
  my $placeholders = join ',', ('?') x keys @names;
  
  my $product = $dbh->do("UPDATE promo set ( $columns ) = ( $placeholders) WHERE id = ?" , undef, @values, $id);


}
sub check_date {
	my $dbh 	= session::dbh;
	my $id = shift;


	my $data = $dbh->selectrow_array(q{
		select 1 FROM promo WHERE id = ? and now() between startdate + '-1 day' and enddate + '1 day'
	}, undef, $id);

}

sub columns {
	my $dbh 	= session::dbh;
	my $data = $dbh->selectcol_arrayref(q{
		select column_name from information_schema.columns where table_schema='public' and table_name='promo'
	});

}

sub set_categories {
	my $dbh 	= session::dbh;
	my $id = shift;
	my $data = shift;


	$dbh->do(q{DELETE FROM marketing_promo where promo = ?}, undef, $id);
	map {
		$dbh->do(q{INSERT INTO marketing_promo  VALUES ( ?, ?)}, undef, $_, $id);
	} @{$data};


}

sub delete {
	my $dbh 	= session::dbh;
	my $id = shift;

	$dbh->do(q{DELETE FROM promo WHERE id = ?}, undef, $id);
}

sub promos_for_cat {
	my $dbh 	= session::dbh;
	my $id = shift;


	$dbh->selectcol_arrayref(q{SELECT id FROM promo WHERE productcategory = ?}, undef, $id);


}

sub get_categories {
	my $dbh 	= session::dbh;
	my $id = shift;


	$dbh->selectcol_arrayref(q{SELECT marketing FROM marketing_promo WHERE promo = ?}, undef, $id);


}

#******************************************************************



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
	$dbh->do(q{DELETE FROM kit WHERE id = ? and product  IN ( SELECT id from tbl_products Where category = ?)}, undef, $id, $cat);

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

  return $dbh->selectrow_array("select lead_time from tbl_products WHERE id = ?",undef, $id);
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


sub update_category {
  my ($id, $cat) = @_;
  my $dbh = session::dbh;
  my $product = $dbh->do("UPDATE tbl_products set category  = ? WHERE id = ?" , undef, $cat, $id);
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
