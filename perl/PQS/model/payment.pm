package PQS::model::payment;
use strict;
use warnings;
no warnings qw(uninitialized);

use session;

sub new_payment {
	my ($order_id, $user, $cust, $session, $method, $currency, $trans_id, $desc, $amount) = @_;
	my $dbh = session::dbh;

	$dbh->do(q{ insert into tbl_payments ( 
		lngorderid, lngcustomerindex, lnguserindex, strsessionid, curamount, 
		dtmdate, strmethod,	strcurrencyname, strtransactionid, 	strdescription  )
		VALUES (?, ?, ?, ?, ?, ?, ?, ?,?,? )
	}, undef, $order_id, $cust, $user, $session, $amount, 
	'NOW()', $method, $currency, $trans_id, $desc, );

}
sub ew_payment {
	my ($order_id, $user, $cust, $session, $method, $currency, $trans_id, $desc, $amount) = @_;
	my $dbh = session::dbh;

	$dbh->do(q{ insert into tbl_payments ( lngorderid, lngcustomerindex. lnguserindex )
		VALUES (?, ?, ?)
	}, undef, $order_id, $cust, $user);

}


1;
