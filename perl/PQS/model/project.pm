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

sub get {
	my $dbh = session::dbh;
	my $pid = shift;

	return $dbh->selectrow_hashref(q{SELECT * from tbl_projects WHERE lngprojectindex = ?}, undef, $pid);


}

1;
