package openprint::press_schedule;
use POSIX qw{ceil};
use strict;
use openprint ();
use vars qw( $log $dbh );
*log = \$openprint::log;
*dbh = \$openprint::dbh;

require openprint::Project;
require openprint::Service;
require openprint::service;
require Date::Calc;

my $debug = 0;

sub find {
	my %params = @_;
	my @values;
	my $sql = 'SELECT *, starttime+runtime as endtime FROM Schedule WHERE 1>0';
	if ( $params{'runtime_start'} and $params{'runtime_end'} ) {
		$sql .= ' AND runtime BETWEEN ( ? AND ? )';
		push @values, @params{'runtime_start','runtime_end'};
	} # end if
	if ( exists $params{'starttime'} ) {
		$sql .= ' AND starttime = ?';
		push @values, $params{'starttime'};
	} # end if
	if ( exists $params{'starttime is null'} ) {
		$sql .= ' AND starttime IS ' . ($params{'starttime is null'} ? '' : 'NOT ' ) . ' NULL';
	} # end if
	if ( $params{'starttime <'} ) {
		$sql .= ' AND starttime < ?';
		push @values, $params{'starttime <'};
	} # end if
	if ( $params{'starttime >='} ) {
		$sql .= ' AND starttime >= ?';
		push @values, $params{'starttime >='};
	} # end if
	if ( $params{'starttime_start'} and $params{'starttime_end'} ) {
		$sql .= ' AND ( starttime BETWEEN ? AND ? )';
		push @values, @params{'starttime_start','starttime_end'};
	} elsif ( $params{'starttime_start'} ) {
		$sql .= ' AND starttime >= ?';
		push @values, $params{'starttime_start'};
	} elsif ( $params{'starttime_end'} ) {
		$sql .= ' AND starttime <= ?';
		push @values, $params{'starttime_end'};
	} elsif ( exists $params{'starttime_start'} and ! $params{'starttime_start'} ) {
		$sql .= ' AND starttime IS NULL';
	} elsif ( exists $params{'starttime_end'} and ! $params{'starttime_end'} ) {
		$sql .= ' AND starttime IS NULL';
	} # end if

	if ( $params{'service_status'} ) {
		if ( ref $params{'service_status'} eq 'ARRAY' ) {
			$sql .= ' AND (SELECT strStatus FROM tbl_Project_Contents WHERE lngProjectIndex=ProjectIndex AND lngServiceIndex=ServiceIndex) IN ('.join(',', map { '?' } @{$params{'service_status'}} ).')';
			push @values, @{$params{'service_status'}};
		} else {
			$sql .= ' AND (SELECT strStatus FROM tbl_Project_Contents WHERE lngProjectIndex=ProjectIndex AND lngServiceIndex=ServiceIndex)=?';
			push @values, $params{'service_status'};
		} # end if
	} # end if
	if ( $params{'equipment_id'} ) {
		$sql .= ' AND equipment_id=?';
		push @values, $params{'equipment_id'};
	} # end if
	if ( $params{'id'} ) {
		$sql .= ' AND id=?';
		push @values, $params{'id'};
	} # end if
	if ( $params{'project_id'} ) {
		if ( substr($params{'project_id'},0,1) == '!' ) {
			$sql .= ' AND projectindex != ?';
			push @values, substr $params{'project_id'}, 1, length $params{'project_id'};
		} else {
			$sql .= ' AND projectindex=?';
			push @values, $params{'project_id'};
		} # end if
	} # end if
	if ( $params{'service_id'} ) {
		$sql .= ' AND serviceindex=?';
		push @values, $params{'service_id'};
	} # end if

	$sql .= " ORDER BY $params{'order'}" if $params{'order'};
	$sql .= " LIMIT $params{'limit'}" if $params{'limit'};
	my $data = $dbh->selectall_arrayref( $sql, {Slice=>{}}, @values );
	if ( ! $data ) {
		$log->error( "Error loading schedule: ($sql) (@values) : " . $dbh->errstr() );
		return;
	} elsif ( $debug ) {
		$log->debug( "Loading schedule: ($sql) (@values) : " . @$data ); 
	} # end if
	return @$data;
} # end sub find

sub remove {
	my ( $p_id, $s_id ) = @_;
	my $error;
	foreach my $Job ( openprint::ScheduledJob->find(project_id=>$p_id, ( $s_id ? ('service_id @>'=>$s_id) : () ) ) ) {
		if ( $s_id and ( $Job->service_id() > 1 ) ) {
			$error .= $Job->save({'service_id'=>[ sets::exclude( [ $s_id ], $Job->service_id() ) ]});
		} else {
			$error .= $Job->delete();
		} # end if
	} # end foreach
	return $error;
} # end sub remove

sub add_project_to_press_schedule {
	my ( $Project, $service_id ) = @_;

	my $error = '';

	my $ac = sql::start_transaction( $dbh );

	my @sigs = $service_id ? ( $service_id ) : $Project->signatures();

	my $ServiceType = openprint::ServiceType->find_one(name=>'Signature');

	my @sigs_not_on_schedule;
	foreach my $s_s_id ( sets::union(@sigs) ) {
		next if openprint::ScheduledJob->find_one(project_id=>$$Project{id}, 'service_id @>'=>$s_s_id );
		push @sigs_not_on_schedule, $s_s_id;
	} # end foreach sig

	while ( my $s_s_id = shift @sigs_not_on_schedule ) {

		my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
		$$sig_specs{'UsePress'} = $$sig_specs{'ddmPress'.$Project->ordered_quantity_index()} if ! $$sig_specs{'UsePress'};
		if ( ! $$sig_specs{'UsePress'} ) {
			$error .= "No press for signature $$sig_specs{'SignatureIndex'}<br/>";
			next;
		} # end if

		my @service_ids = ( $s_s_id );
		my @forms = ( $$sig_specs{'SignatureIndex'} );

		# Merge identical sigs
		for( my $i = 0; $i < @sigs_not_on_schedule; $i += 1 ) {
			my $s_id_2 = $sigs_not_on_schedule[$i];

			my $sig_specs2 = openprint::service::get_specs_ref( $Project, $s_id_2 );
			if ( openprint::Estimating::Printing::compare_signatures( $Project, $sig_specs, $sig_specs2, $Project->ordered_quantity_index() ) ) {
				push @service_ids, $s_id_2;
				push @forms, $$sig_specs2{SignatureIndex};
				splice @sigs_not_on_schedule, $i, 1;
				$i -= 1;
			} # end if
		} # end foreach

		if ( my $Equipment = openprint::Equipment->find_one(strid=>$$sig_specs{UsePress}) ) {
			my $Job = new openprint::ScheduledJob();
			$_ = $Job->save({
				project_id		=>	$Project->id(),
				equipment_id	=>	$Equipment->id(),
				starttime		=>	undef,
				service_id		=>	\@service_ids,
				pertains_id		=>	\@service_ids,
				servicetype_id	=>	$ServiceType->id(),
			});
			if ( $_ ) {
				$error .= 'Error adding to press schedule: ' . $_;
				$Project->add_to_log( @openprint::session{'company_id','user_id'}, "Error Adding Form @forms to pending press schedule." );
			} else {
				$Project->add_to_log( @openprint::session{'company_id','user_id'}, "Added Form @forms to pending press schedule for " . $Job->Equipment()->strid() );
			} # end if
		} else {
			$error .= "Error adding to press schedule: Press not found ($$sig_specs{UsePress}) for signature $$sig_specs{'SignatureIndex'}<br/>";
		} # end if
	} # end foreach sig
	sql::end_transaction( $dbh, $ac );
	return $error;
} # end sub add_project_to_press_schedule

1;
__END__
