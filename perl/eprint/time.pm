package eprint::time;

use Mail::Sendmail;
use MIME::QuotedPrint;
use strict;

use sql ();
require misc;
use Data::Dumper;

sub service_history {
	my ($r, $dbh, $var) = @_;

	my $sql = q{ SELECT lnguserid, strfirstname || ' ' || strlastname FROM tbl_customer_users };
	$var->{USERS} = ssi::fill_drop_down( $r->log, $dbh, $sql, $r->param('ddmUser') );

	my $userid = $var->{user_type} eq 'A' ? $r->param('ddmUser') : $var->{user_id};
	
	my $user =  $userid ? " AND tc.userid = $userid " : '';

	my $services = $dbh->selectall_arrayref(qq{
		SELECT 	p.lngprojectindex as pid, 
				pc.lngserviceindex as sid, 
				pc.strservicetype
		FROM    
				tbl_project_contents 	pc,
				tbl_projects 			p,
				time_user_service		t
		WHERE 
				pc.lngprojectindex = p.lngprojectindex
		 AND	t.service = pc.lngserviceindex
	
		GROUP BY p.lngprojectindex, pc.lngserviceindex, pc.strservicetype 
		ORDER BY p.lngprojectindex, pc.lngserviceindex

	},{Slice=>{}});

	my $elist = $dbh->selectall_hashref(q{
		SELECT lngindex, strname FROM tbl_equipment
	}, 'lngindex', {}, );


	foreach my $id ( @{$services} ) {

		my $sid = $id->{sid};

		$id->{HISTORY} = $dbh->selectall_arrayref(qq{
			SELECT 	
					tc.equip as equip,
					tc.tstart,
					tc.tstop,
					u.strfirstname || ' ' || strlastname as user,
					to_char(tstop - tstart, 'HH24:MI::SS') as duration

			FROM   
					time_collection 		tc,
					tbl_customer_users		u
			WHERE 
				  tc.service = ?
			  AND u.lnguserid = tc.userid
			$user

			ORDER  BY 4

		},{Slice=>{}},  $sid);

		map {
			$_->{equipment} = $elist->{$_->{equip}}{strname};
		} @{$id->{HISTORY}};

		$id->{service_time} = $dbh->selectrow_array(q{
			SELECT to_char(sum(tstop - tstart), 'HH24:MI::SS') as duration
			FROM time_collection tc 
			WHERE tc.service = ?
		}, undef, $sid);


	}

	$var->{SERVICES} = $services;


}


sub punch_history {
	my ($r, $dbh, $var) = @_;


	ssi::get_dates($r, $r->log, $dbh, $var);

	my $userid = $var->{user_type} eq 'A' ? $r->param('ddmUser') : $var->{user_id};

	my $sql = q{ SELECT lnguserid, strfirstname || ' ' || strlastname FROM tbl_customer_users };
	$var->{USERS} = ssi::fill_drop_down( $r->log, $dbh, $sql, $r->param('ddmUser') );

	my $start = $var->{StartDate};
	my $end   = $var->{EndDate};

	my $date = "punch_in BETWEEN '${start}' AND '${end}'";

	my $user = " AND userid = $userid " if $userid;

	$sql = qq{ 
		SELECT *, to_char(punch_out - punch_in,'HH24:MI::SS') as duration,
		(SELECT strfirstname || ' ' || strlastname 
		 FROM tbl_customer_users u WHERE u.lnguserid = userid) as user
		 FROM punch_clock
		 WHERE $date
		 $user
	};

	$var->{PUNCH} = $dbh->selectall_arrayref($sql, {Slice=>{}});


}

sub time_collection {
	my ($r, $dbh, $var) = @_;

	my $userid = $var->{user_id};
	
	if ( $r->param('Punch_In') ) {
		$dbh->do(q{ INSERT INTO punch_clock (userid, punch_in) VALUES ( ?, NOW() ) }, undef, $userid);
	} elsif ( $r->param('Punch_Out') ) {
		$dbh->do(q{ 
			UPDATE punch_clock set punch_out = NOW() WHERE userid = ? AND punch_out IS NULL 
		}, undef, $userid);
	}


	if ( $r->param('START') ) {
		my $service = $r->param('service');
		my $equip = $r->param('ddmEquipment') || 0;

		my $serial = $dbh->selectrow_array(q{
			SELECT serial FROM tbl_service_types, tbl_project_contents
			WHERE tbl_service_types.strid = tbl_project_contents.strservicetype
			AND lngserviceindex = ?
		}, undef, $service);
		if ( $serial ) {
			$dbh->do(q{ 
				UPDATE time_collection set tstop = NOW() 
				WHERE userid = ? AND tstop IS NULL 
			}, undef, $userid);
		}

		$dbh->do(q{ INSERT INTO time_collection (userid, service, equip, tstart) 
					VALUES ( ?, ?, ?, NOW() ) 
		}, undef, $userid, $service, $equip);

	} elsif ( $r->param('STOP') ) {
		$dbh->do(q{ 
			UPDATE time_collection set tstop = NOW() 
			WHERE userid = ? AND service = ? AND tstop IS NULL 
		}, undef, $userid, $r->param('service'));
	} elsif ( $r->param('REMOVE') ) {
		$dbh->do(q{ 
			DELETE FROM time_user_service 
			WHERE userid = ? AND service = ? 
		}, undef, $userid, $r->param('service'));
	}

	my $list = $dbh->selectall_arrayref(q{
		SELECT * 
 
		FROM  tbl_order_contents c, tbl_project_contents pc, time_user_service t, tbl_projects p
		WHERE  c.lngprojectindex = pc.lngprojectindex AND t.service = lngserviceindex
		AND pc.lngprojectindex = p.lngprojectindex
		AND t.userid = ?
	},{Slice=>{}}, $userid);

	my $esql = q{ SELECT lngindex, strname FROM tbl_equipment ORDER by strname };

	foreach my $x (@{$list}) {

print STDERR "UPDATE ME: $_->{lngserviceindex} \n";

		$x->{start} = $dbh->selectrow_hashref(q{
			SELECT * FROM time_collection WHERE userid = ? AND service = ? AND tstop IS NULL 
		}, undef, $userid, $x->{lngserviceindex});

		my $e = $dbh->selectrow_array(q{
			SELECT equip FROM time_collection WHERE userid = ? AND service = ? 
			order by tstart desc
		}, undef, $userid, $x->{lngserviceindex});

print STDERR "HAVE EQUIPMENT: $e - $userid / $x->lngserviceindex \n";
		$x->{EQUIPMENT}  = ssi::fill_drop_down( $r->log, $dbh, $esql, $e );
		
		$x->{duration} = $dbh->selectrow_array(q{
			select to_char(sum(tstop - tstart), 'HH24::MI::SS') FROM time_collection 
			WHERE userid = ? and service = ?
		}, undef, $userid, $x->{lngserviceindex});
		
	}

	$var->{SERVICES} = $list;

	$var->{in} = $dbh->selectrow_array(q{
		SELECT punch_in FROM punch_clock WHERE userid = ? AND punch_out IS NULL
	}, undef, $userid);

print STDERR "PROJECTS: ", Dumper($list, $var->{in});

}

sub service_allocation {
	my ($r, $dbh, $var) = @_;

	my $userid = $r->param('ddmUser') || $var->{user_id};

	my $ins = $dbh->prepare(q{ INSERT into time_user_service VALUES ( ?, ? ) });
	my $del = $dbh->prepare(q{ DELETE FROM time_user_service WHERE userid = ? AND service = ?});

	if ( $r->param('Update') ) {
		map { $del->execute($userid, $_) } $r->param('uncheck');
		map { $ins->execute($userid, $_) } $r->param('assign');
	}


	my $list = $dbh->selectall_arrayref(q{
		SELECT *, 

			( SELECT count(*) FROM time_user_service 
				WHERE lngserviceindex = service AND userid = ?) as a 

 
		FROM  
				tbl_order_contents c, 
				tbl_project_contents pc, 
			  	tbl_projects p, 
				tbl_service_types s

		WHERE  	c.lngprojectindex = p.lngprojectindex 
		AND 	pc.lngprojectindex = p.lngprojectindex
		AND 	pc.strservicetype = s.strid
		AND 	s.active
		AND		pc.strstatus <> 'Complete'
		AND		p.strstatus <>  'Unordered'
		AND       p.strstatus <> 'Complete'
		AND       p.strstatus <> 'Canceled'
		AND       p.strstatus <> 'Cancelled'
		AND       p.strstatus <> 'Deleted'
		
		ORDER By c.lngorderid, p.lngprojectindex, pc.strservicetype

	},{Slice=>{}}, $userid);

	map { 
		$_->{assigned_to} = join(',',
			@{$dbh->selectcol_arrayref(q{
				SELECT strfirstname || ' ' || strlastname 
				FROM   tbl_customer_users, time_user_service
				WHERE  lnguserid = time_user_service.userid 
				AND    service = ?
			}, undef, $_->{lngserviceindex})} );
	} @{$list};

	$var->{SERVICES} = $list;

	my $sql = q{ SELECT lnguserid, strfirstname || ' ' || strlastname FROM tbl_customer_users };
	$var->{USERS} = ssi::fill_drop_down( $r->log, $dbh, $sql, $r->param('ddmUser') );

	$sql = q{ SELECT lngindex, strname FROM tbl_service_types WHERE active ORDER by strname };
	$var->{SERVICE_LIST} = ssi::fill_drop_down( $r->log, $dbh, $sql, $r->param('ddmService') );

}


sub service_list {
	my ($r, $dbh, $var) = @_;

	if ( $r->param('btnFunction') eq 'Save' ) {
		my $up = $dbh->prepare(q{
			UPDATE tbl_service_types SET serial = ? , active = ? WHERE lngindex = ?
		});
		map { 
			my $id = $_;
			my $a =  $r->param("active_$id") ? 'true' : 'false';
			my $s = $r->param("serialparallel_$id") eq 'Serial' ? 'true' : 'false';

			$up->execute($s, $a, $id);
print STDERR "UPDATING: $id -$a -$s \n";
		} $r->param('service_id');
		if ( $r->param('service_new') ) {
			my $ins = $dbh->prepare(q{
				INSERT INTO tbl_service_types (strname) VALUES (?)
			});
			$ins->execute($r->param('service_new'));
			my $id = $dbh->selectrow_array(q{
				SELECT max(lngindex) FROM tbl_service_types
			});
		}


	}



	my $list = $dbh->selectall_arrayref(q{
		SELECT lngindex as id, serial, active, strname as servicename 
		FROM tbl_service_types s
		ORDER by strname
	},{Slice=>{}},);

	$var->{SERVICES} = $list;
	
}

1;

__END__

