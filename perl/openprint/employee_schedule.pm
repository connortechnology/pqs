use strict;
package openprint::employee_schedule;
use strict;

use openprint ();
use vars qw( $log $dbh %variable %config );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*config = \%openprint::config;

require sql;
require openprint::Equipment;
require openprint::service;
require openprint::ScheduledJob;

sub update_late_jobs {
	# Make sure that we don't lose any jobs to the past.
	foreach my $Job ( openprint::ScheduledJob->find(endtime=>Date::Format::time2str('%Y-%m-%d %H:%M:%S', time ),order=>'starttime' ) ) {
		$Job->save({starttime_seconds=>time});
	} # end while
} # end sub update_late_jobs

sub insert {
	my ( $log, $dbh, $project_index, $service_index, $equipment_id ) = @_;

	my $ac = sql::start_transaction( $dbh );
	my ( $start_time ) = sql::execute( $log, $dbh, q{SELECT MAX(StartTime+RunTime) FROM Schedule, Projects WHERE Index=ProjectIndex AND strStatus='Approved' AND Equipment_ID=?}, $equipment_id );
	( $start_time ) = sql::execute( $log, $dbh, 'SELECT NOW()' ) if ! $start_time;
	foreach my $Job ( openprint::ScheduledJob->find('service_id @>'=>$service_index) ) {
		$Job->delete();
	} # end foreach Job
	my $runtime = openprint::service::get_runtime( new openprint::Project( $project_index ), $service_index );

	my $Job = new openprint::ScheduledJob();
	$Job->save({
			project_id		=>	$project_index,
			service_id		=>	[ $service_index ],
			pertains_id		=>	[ $service_index ],
			equipment_id		=>	$equipment_id,
			starttime			=>	$start_time,
			runtime_seconds	=>	$runtime,
			});
	sql::end_transaction( $dbh, $ac );
} # end sub insert

# Removes a form from the press schedule
sub remove {
	my ( $log, $dbh, $project_index, $service_index ) = @_;
	my $ac = sql::start_transaction( $dbh );

	my @equipment_ids = ();
	foreach my $Job ( openprint::ScheduledJob->find(project_id=>$project_index, 'service_id @>'=>$service_index) ) {
		push @equipment_ids, $Job->equipment_id();
		$Job->delete();
	} # end foreach Job
	foreach my $equipment_id ( sets::union( @equipment_ids ) ) {
		new openprint::Equipment( $equipment_id )->update_schedule();
	} # end foreach
	sql::end_transaction( $dbh, $ac );
} # end sub remove

1;
__END__
