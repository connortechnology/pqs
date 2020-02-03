package PQS::model::product_filter;

use strict;
use warnings;
no warnings qw(uninitialized);

use session;
use Data::Dumper;


sub reset_category {
	my $cat = shift;
  	my $dbh = session::dbh;

	$dbh->do(q{DELETE FROM product_filter where category = ?}, undef, $cat);

}

sub copy_filter {
	my $from = shift;
	my $to = shift;

  	my $dbh = session::dbh;

	$dbh->do(q{INSERT into product_filter ( SELECT nextval('product_filter_seq'), ?, name, sortorder FROM product_filter where category = ? )
	}, undef, $to, $from );	

	
	print STDERR "COPYING FILTERS FROM $from  TO $to CF \n";



}


sub set {
  my ($filter) = @_;
  my $dbh = session::dbh;

  my $id = $filter->{id};
  my $cat = $filter->{cat};
  my $name = $filter->{name};
  my $sortorder = $filter->{sortorder};

  print STDERR "HAEV SORT ORDER: $sortorder - $id -- $name \n", Dumper($filter);

	if ( $id ) {
  		$dbh->do(q{update product_filter set name = ?, sortorder = ? where id = ?},undef,  $name, $sortorder, $id);
	} else { 
  		$dbh->do(q{insert into product_filter (name, category, sortorder) values ( ?, ?, ? ) },undef,  $name, $cat, $sortorder);
		$id = $dbh->last_insert_id(undef, undef, 'product_filter', 'id');
print STDERR "HAVE INERT ID: $id \n";
		
	}
	return $id;
}

sub delete {
  my $id = shift;
  my $dbh = session::dbh;
  $dbh->do(q{delete from product_filter where id = ?},undef,  $id);
}


sub delete_options {
  my $id = shift;
  my $dbh = session::dbh;
  $dbh->do(q{delete from options where filter = ?},undef,  $id);
}


sub insert {
  my ($name, $cat, $sort) = @_;
  my $dbh = session::dbh;
  $dbh->do(q{insert into product_filter (name, category, sortorder) values ( ?, ?, ? ) },undef,  $name, $cat, $sort);
  my $id = $dbh->last_insert_id(undef, undef, 'product_filter', 'id');

  return $id;

}

sub insert_option {
  my ($name, $filter) = @_;
  my $dbh = session::dbh;
  $dbh->do(q{insert into options (filter, name) values ( ?, ? ) },undef,  $filter, $name);
}

sub get_options {
  my ($filter) = @_;
  my $dbh = session::dbh;

  #Change sort to be id, stay in order created, instead of apha sort.
  #Jan 6 2020.
  my $id = $dbh->selectall_arrayref(
	"select * from options where filter = ? order by id", {Slice => {}}, $filter);

}


sub get {
  my ($id) = @_;
  my $dbh = session::dbh;

  my $id = $dbh->selectrow_hashref("select * from product_filter where id = ?", undef, $id);
}


sub get_all {
  my $dbh = session::dbh;

  my $all = $dbh->selectall_arrayref("select * from product_filter ORDER by sortorder",{Slice => {}});

}
sub products_with_option {
  my $dbh = session::dbh;
  my $id = shift;

  my $all = $dbh->selectcol_arrayref("select product from product_options WHERE opt = ?",undef, $id);

}


sub get_category {
  my $dbh = session::dbh;
  my $id  = shift;

  my $all = $dbh->selectall_arrayref("select * from product_filter Where category = ? order by sortorder, name"
	,{Slice => {}}, $id);

}

sub options_for_product {
  my $dbh = session::dbh;
  my $id  = shift;

  my $all = $dbh->selectall_arrayref("select opt, filter from product_options, options  Where product = ? AND product_options.opt = options.id "
	,{Slice => {}}, $id);


}

sub get_option_id {
  my $dbh = session::dbh;
print STDERR "OPTS ", Dumper(@_);
  my $cat  = shift;
  my $filter  = shift;
  my $opt  = shift;
  my $id = $dbh->selectrow_array(q{select o.id from options o, product_filter pf 
		Where o.filter = pf.id AND pf.category = ?  AND o.name = ? AND pf.name = ?
	},undef, $cat,$opt, $filter );
}

sub delete_product_options {
  my $dbh = session::dbh;
  my $prod  = shift;
  $dbh->do("Delete from product_options where product =  ?", undef, $prod);
  print STDERR "OPTS DEL: $prod \n";
}


sub insert_product_option {
  my $dbh = session::dbh;
  my $prod  = shift;
  my $opt  = shift;
  $dbh->do("Insert into product_options values (?,?)", undef, $prod, $opt);
}





1;
