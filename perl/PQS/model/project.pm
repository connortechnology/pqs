package PQS::model::project;
use strict;
use warnings;
no warnings qw(uninitialized);

use session;

sub set_status {

	my $dbh = session::dbh;


    my ($pid, $status) = @_;

	die("No status provided") unless $status;

	if ( $status ) {
		$dbh->do(q{UPDATE tbl_projects set strstatus = ? WHERE lngprojectindex = ?}, undef, $status, $pid);
	}

}
sub get_status {
	my $dbh = session::dbh;
	my $pid = shift;

	return $dbh->selectrow_array(q{SELECT strstatus from tbl_projects WHERE lngprojectindex = ?}, undef, $pid);


}

sub set_priority_status {
	my $order  = shift;
    my $status  = shift;
  	my $dbh = session::dbh;

	$dbh->do(q{update tbl_projects set lngpriority = ? where lngprojectindex = ?}, undef, $status, $order);
}

sub get {
	my $dbh = session::dbh;
	my $pid = shift;

	return $dbh->selectrow_hashref(q{SELECT * from tbl_projects WHERE lngprojectindex = ?}, undef, $pid);

}

sub set_equipment{
	my $dbh = session::dbh;
	my $sid = shift;
	my $val = shift;

	$dbh->do(qq{UPDATE tbl_project_contents SET equipment = ? WHERE lngserviceindex = ?}, undef,  $val, $sid);

}

1;
