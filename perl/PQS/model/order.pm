package PQS::model::order;
use strict;
use warnings;
no warnings qw(uninitialized);

use session;

use Data::Dumper;

sub active_orders {
  	my $dbh = session::dbh;

	
	my $orders = $dbh->selectall_arrayref(q{
		SELECT * from tbl_orders LIMIT 10
	}, undef );

}

sub get_order {
	my $id = shift;
  	my $dbh = session::dbh;

	my $o = $dbh->selectrow_hashref(q{
		SELECT * FROM tbl_orders WHERE lngorderid = ?
	},undef, $id); 
}

sub get_order_products {
	my $id = shift;
  	my $dbh = session::dbh;

	my $prod = $dbh->selectall_arrayref(q{
		select * from tbl_order_contents where lngorderid = ? AND product IS NOT Null
	}, {Slice=>{}}, $id);
	return $prod;
}

sub set_price {
  	my $dbh 	= session::dbh;
	my $id 		= shift;
	my $price 	= shift;
	$dbh->do(q{UPDATE tbl_order_contents SET cursalesprice = ? WHERE lngcontentindex = ?}, undef, $price, $id);
}


sub tax_exemptions {
  	my $dbh = session::dbh;
	my $id = shift;

	my @data = $dbh->selectrow_array(q{
		select tax_exempt1, tax_exempt2, tax_exempt3 from tbl_products where id = ?
	}, undef, $id);

	return @data;
}

sub get_payment_from_token {
  	my $dbh = session::dbh;
	my $token = shift;
	return $dbh->selectrow_array(q{select curamount from tbl_payments where strtransactionid = ?}, undef, $token);
	
}

sub get_id_from_token {
  	my $dbh = session::dbh;
	my $token = shift;
	return $dbh->selectrow_array(q{select lngorderid from tbl_orders where paypal_token = ?}, undef, $token);
	
}

sub token_type {
  	my $dbh = session::dbh;
	my $order = shift;
	return $dbh->selectrow_array(q{select token_type from tbl_orders where lngorderid = ?}, undef, $order);
	
}

sub set_admin_comments {
print STDERR "SET AMDIN COMMENTS \n";
	my $order  = shift;
    my $comments  = shift;
  	my $dbh = session::dbh;

	$dbh->do(q{update tbl_orders set stradministratorcomments = ? where lngorderid = ?}, undef, $comments, $order);
}

sub set_status {
	my $order  = shift;
    my $status  = shift;
  	my $dbh = session::dbh;

	$dbh->do(q{update tbl_orders set strstatus = ? where lngorderid = ?}, undef, $status, $order);
}

sub set_paypal_token {
	my $order  = shift;
    my $token  = shift;
    my $type  = shift;
  	my $dbh = session::dbh;

	$dbh->do(q{update tbl_orders set paypal_token = ?, token_type = ? where lngorderid = ?}, undef, $token, $type, $order);
}

sub get_pid_from_index {
	my $dbh = session::dbh;
	my $index = shift;

	return $dbh->selectrow_array(q{select spec_pid from tbl_order_contents where lngcontentindex= ?}, undef, $index);
	
}


sub get_status {
	my $dbh = session::dbh;
	my $index = shift;

	return $dbh->selectrow_array(q{select strstatus from tbl_orders where lngorderid = ?}, undef, $index);
	
}


sub set_mediawide_id {
	my $ocid  = shift;
  	my $mwid  = shift;
  	my $dbh = session::dbh;

	$dbh->do(q{update tbl_order_contents set MWJobId = ? where lngcontentindex= ?}, undef, $mwid, $ocid);
}

sub set_spec_pid {
	my $ocid  = shift;
  	my $pid  = shift;
  	my $dbh = session::dbh;

	$dbh->do(q{update tbl_order_contents set spec_pid = ? where lngcontentindex= ?}, undef, $pid, $ocid);
	$dbh->do(q{update tbl_order_contents set lngprojectindex = ? where lngcontentindex= ?}, undef, $pid, $ocid);
}

sub set_mw_session {
	my $ocid  	= shift;
  	my $session = shift;
  	my $dbh = session::dbh;

	$dbh->do(q{update tbl_order_contents set mw_session = ? where lngcontentindex= ?}, undef, $session, $ocid);
}

sub get_mw_session {
	my $ocid  	= shift;
  	my $dbh = session::dbh;

	return $dbh->selectrow_array(q{select mw_session from  tbl_order_contents where lngcontentindex= ?}, undef, $ocid);
}


sub get_paypal_token {
	my $order  = shift;
  	my $dbh = session::dbh;

	return $dbh->selectrow_array(q{select paypal_token from tbl_orders where lngorderid = ?}, undef, $order);
}


sub user_id {
	my $order  = shift;
  	my $dbh = session::dbh;

	return $dbh->selectrow_array(q{select lnguserid, lngcustomerid from tbl_orders where lngorderid = ?}, undef, $order);
}

#removes a project from an order
sub remove_project {
  my ($oid, $pid) = @_;
  my $dbh = session::dbh;
  $dbh->do("delete from tbl_order_contents where lngorderid = ? and lngprojectindex = ?", undef, $oid, $pid);
}

sub remove_content {
  my $id  = shift;
  my $dbh = session::dbh;
  $dbh->do("delete from tbl_order_contents where lngcontentindex = ?", undef, $id);
  $dbh->do("delete from tbl_order_contents where subgroup 		 = ?", undef, $id);
}


sub set_ship_price {
  my ($oid, $price) = @_;
  my $dbh = session::dbh;
  $dbh->do("update tbl_orders set shipping = ? where lngorderid = ?", undef, $price, $oid);
}

sub shipping_price {
  my $order = shift;
  my $dbh = session::dbh;
  my $price = $dbh->selectrow_array(q{
		SELECT shipping FROM tbl_orders WHERE lngorderid = ?
  }, undef, $order);

print STDERR "HAVE ORDER SHIPPING PRICE: $price \n";

  return $price;
}

sub address {
  my $order = shift;
  my $dbh = session::dbh;
  my @add = $dbh->selectrow_array(q{
		SELECT strpostalcode, strstate, strcountry FROM tbl_orders WHERE lngorderid = ?
  }, undef, $order);

print STDERR "HAVE MODEL ADDRESS: @add \n";

  return @add;
}


sub get_products { 
  my $order = shift;
  my $dbh = session::dbh;
  my $products = $dbh->selectall_arrayref(q{
		SELECT product, intquantity FROM tbl_order_contents WHERE lngorderid = ? AND product IS NOT NULL
  }, {Slice =>{}}, $order);
  
  return $products;
	
}

sub get_cust_id {
  my $order = shift;
  my $dbh = session::dbh;
  my $cust_id = $dbh->selectrow_array(q{
		SELECT lngcustomerid FROM tbl_orders WHERE lngorderid = ?
  }, undef, $order);
  
  return $cust_id;

}

#gets the order for a given project
sub get_order_by_pid {
  my ($pid) = @_;
  my $dbh = session::dbh;
  my $order = $dbh->selectrow_hashref(q{
    SELECT tbl_orders.* FROM tbl_orders left join tbl_order_contents on tbl_orders.lngorderid = tbl_order_contents.lngorderid
    WHERE tbl_order_contents.lngprojectindex = ?
  }, undef, $pid);
  return $order;
}

#gets the details of an ordered project
sub get_ordered_project_info {
  my ($pid) = @_;
  my $dbh = session::dbh;
  my $proj = $dbh->selectrow_hashref("select * from tbl_order_contents where lngprojectindex = ?", undef, $pid);
  return $proj;
}

sub duedate {
	my $pid = shift;
	my $dbh = session::dbh;
	my $date = $dbh->selectrow_array(q{SELECT daterequired FROM tbl_order_contents WHERE lngprojectindex = ?}, undef, $pid);
	return $date
}

#saves the details of an ordered project
sub save_ordered_project_info {
  my ($proj) = @_;
  my $dbh = session::dbh;
  if ($proj->{lngprojectindex}) {
    my $columns = join ",", keys $proj;
    my @vals = values $proj;
    $dbh->do("update tbl_order_contents set ($columns) = (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) where lngprojectindex = ? and lngorderid = ?", undef, @vals, $proj->{lngprojectindex}, $proj->{lngorderid});
  }
}
1;
