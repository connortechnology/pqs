package PQS::model::product_filter;

use strict;
use warnings;
no warnings qw(uninitialized);

use session;
use Data::Dumper;



sub set {
  my ($filter) = @_;
  my $dbh = session::dbh;

  my $id = $filter->{id};
  my $cat = $filter->{cat};
  my $name = $filter->{name};

	if ( $id ) {
  		$dbh->do(q{update product_filter set name = ? where id = ?},undef,  $name, $id);
	} else { 
  		$dbh->do(q{insert into product_filter (name, category) values ( ?, ? ) },undef,  $name, $cat);
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
  my ($name, $cat) = @_;
  my $dbh = session::dbh;
  $dbh->do(q{insert into product_filter (name, category) values ( ?, ? ) },undef,  $name, $cat);
}

sub insert_option {
  my ($name, $filter) = @_;
  my $dbh = session::dbh;
  $dbh->do(q{insert into options (filter, name) values ( ?, ? ) },undef,  $filter, $name);
}

sub get_options {
  my ($filter) = @_;
  my $dbh = session::dbh;
  my $id = $dbh->selectall_arrayref(
	"select * from options where filter = ? order by name", {Slice => {}}, $filter);

}


sub get {
  my ($id) = @_;
  my $dbh = session::dbh;

  my $id = $dbh->selectrow_hashref("select * from product_filter where id = ?", undef, $id);
}


sub get_all {
  my $dbh = session::dbh;

  my $all = $dbh->selectall_arrayref("select * from product_filter",{Slice => {}});

}
sub products_with_option {
  my $dbh = session::dbh;
  my $id = shift;

  my $all = $dbh->selectcol_arrayref("select product from product_options WHERE opt = ?",undef, $id);

}


sub get_category {
  my $dbh = session::dbh;
  my $id  = shift;

  my $all = $dbh->selectall_arrayref("select * from product_filter Where category = ? order by name"
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


sub insert_product_option {
  my $dbh = session::dbh;
  my $prod  = shift;
  my $opt  = shift;
  $dbh->do("Insert into product_options values (?,?)", undef, $prod, $opt);
}





1;
