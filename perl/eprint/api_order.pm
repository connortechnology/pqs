package eprint::api_order;
use strict;
use Apache2::Request;
use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY);
use sql ();

require eprint::order;
require eprint::project;

sub make_order {
    my ($r, $dbh, $var, $req) = @_;
use Data::Dumper;
print STDERR "MAKE ORDER \n", Dumper(@_);
    my $log = $r->log;

    my $date   = $req->{today};
    my $pid    = $req->{pid};
    my $qty    = $req->{qtyIndex};
    my $cookie = $req->{srcid};

print STDERR "START ADD PROJECT \n";
    my ($order_id, $err) = eprint::order::add_project_to_order( 
			    $log, $dbh, $cookie, $var, $pid
    );

print STDERR "DONE ADD PROJECT \n";
    my $order_total;

    my @project_prices = eprint::project::project_price(
	$log, $dbh, $pid
    );

print STDERR "DONE ADD PROJECT 2 \n", Dumper(@project_prices);
    $order_total += $project_prices[$qty - 1];

    $dbh->do(q{
	UPDATE tbl_order_contents Set
	    intQuantityIndex = ?,
	    dateRequired     = ?
	WHERE
	    lngorderid = ? and lngprojectindex = ?
    },{}, 1, $date, $order_id, $pid);
	    
	
print STDERR   "\n ORDER: $order_total -- $err \n";

    $r->param('hiddenOrderID' => $order_id);

    eprint::order::finalise_order( $r, $log, $dbh, $cookie, $var, $order_id );

    return $order_id;
 }


;

