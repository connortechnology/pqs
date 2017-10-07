package eprint::printsys;
use strict;

use Apache2::Request();
use Apache2::Const qw(:common :response);


sub handler {

    my $r        = Apache2::Request->new(shift);

    # Process the request params.
    return SERVER_ERROR unless $r->parse == OK;

	my $orderkey = $r->param('OrderKey');
	my $status  = $r->param('Status') == 2 ? 'In Production'
										   : 'Cancelled';
	
	my $dbh = PQS::DB->connect($r);

	session::r($r);
	session::log($r->log);
	session::dbh($dbh);

	my $pid = $dbh->selectrow_array(q{
		SELECT lngprojectindex FROM tbl_projects where orderkey = ?
	}, undef, $orderkey);

print STDERR "UPDATE PID: $pid  -- $orderkey -- $status \n\n";

    return SERVER_ERROR unless $pid;

	$dbh->do(q{
		UPDATE tbl_projects SET strStatus = ? WHERE orderkey = ?
	}, undef, $status, $orderkey);

	$dbh->commit;
	$dbh->disconnect;
	
 	my $page = '/site_specific/printsys_status.html';

	$r->headers_out->set(Location => $page);
    $r->status(HTTP_MOVED_TEMPORARILY);

    return HTTP_MOVED_TEMPORARILY;

	
	
}

1;
