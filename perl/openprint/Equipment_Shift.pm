use strict;
package openprint::Equipment_Shift;
our @ISA = qw(openprint::Object);
require DateTime::TimeZone;
require openprint::Object;
require openprint::Shift;
require sql;
require misc;

use constant DAY => 60*60*24;
use constant HOUR => 60*60;

use openprint ();
use vars qw( $log $dbh $debug $table $serial %fields %find_fields %transforms %defaults );
*log = \$openprint::log;
*dbh = \$openprint::dbh;

# Note: duration_seconds is 1 seconds less than duration
my $parser = 'DateTime::Format::Pg';

$debug = 1;

$table = 'equipment_shifts';
$serial = 'equipment_shifts_id_seq';

%fields = (
	id					=>	'id',
	starttime_seconds	=>	'starttime_seconds',
	duration_seconds	=>	'duration_seconds',
	duration			=>	undef,
	endtime_seconds		=>	undef,
	name				=>	'name',
	equipment_id		=>	'equipment_id',
	operator_ids  		=>  'operator_ids',
);

%find_fields = (
	endtime	=>	'starttime_seconds + duration_seconds - 1',
);

%transforms = (
	id			=>	[ 's/\D//g' ],
);

%defaults = (
	operator_ids		=> [],
	starttime_seconds	=>	0,
	duration_seconds	=>	1,
	name							=>	q`'Shift'`,
);

sub to_string {
	return sprintf(
			"EquipmentShift: %s %s %s from %s to %s",
			$_[0]->Equipment()->name(),
			$_[0]->name(),
			$_[0]->duration() ? $_[0]->duration() : $_[0]{duration_seconds},,
			$_[0]->starttime() ? $_[0]->starttime() : $_[0]{starttime_seconds},,
			$_[0]->endtime() ? $_[0]->endtime() : $_[0]{endtime_seconds},,
			);
}

sub starttime {
		#return Date::Format::time2str('%H:%M:%S', $_[0]->starttime_seconds());
		return $_[0]{starttime} = misc::seconds2hms($_[0]->starttime_seconds());
}
sub starttime_seconds {
	if ( @_ > 1 ) {
		if ( ref $_[1] eq 'ARRAY' ) {
			my ( $d, $h, $m, $s ) = @{$_[1]};
			$_[0]{starttime_seconds} = ($d * DAY) + ($h * HOUR) + $m * 60 + $s;
		} else {
			$_[0]{starttime_seconds} = $_[1];
		} # end if
		$_[0]{endtime_seconds} = $_[0]{starttime_seconds} + $_[0]{duration_seconds};
	} # end if
	return $_[0]{starttime_seconds};
} # end sub starttime_seconds

sub endtime {
	if ( ! $_[0]{endtime} ) {
		$_[0]{endtime} = misc::seconds2hms($_[0]->endtime_seconds());
		#$_[0]{endtime} = Date::Format::time2str('%H:%M:%S', $_[0]->endtime_seconds());
	} # end if
	return $_[0]{endtime};
} # end sub endtime_seconds

sub endtime_seconds {
	if ( @_ > 1 ) {
		if ( ref $_[1] eq 'ARRAY' ) {
			my ( $d, $h, $m, $s ) = @{$_[1]};
			$_[0]{endtime_seconds} = ($d * DAY) + ($h * HOUR) + $m * 60 + $s;
		} else {
			$_[0]{endtime_seconds} = $_[1];
		} # end if
		$_[0]{duration_seconds} = $_[0]{endtime_seconds} - $_[0]{starttime_seconds};
	} # end if
	if ( ! $_[0]{endtime_seconds} ) {
		$_[0]{endtime_seconds} = $_[0]{starttime_seconds} + $_[0]{duration_seconds};
	} # end if
	return $_[0]{endtime_seconds};
} # end sub endtime_seconds

sub compare {
	my ( $self, $requested_dt ) = @_;
	if ( ref $requested_dt ne 'DateTime' ) {
		$requested_dt = DateTime->from_epoch( epoch=>$requested_dt, time_zone=>$openprint::TZ );
	}
	my $shift_start_time_dt = DateTime::Duration->new( seconds => $self->starttime_seconds() % DAY );
	my $date_part_dt = $requested_dt->clone()->truncate(to=>'day');
	if ( $requested_dt->is_dst() and ! $date_part_dt->is_dst() ) {
#$log->debug("subtracting an hour for DST");
		$date_part_dt -= DateTime::Duration->new( hours=>1 );
	} elsif ( $date_part_dt->is_dst() and ! $requested_dt->is_dst() ) {
#$log->debug("adding an hour for DST");
		$date_part_dt += DateTime::Duration->new( hours=>1 );
	} # end if
	my $st = $date_part_dt + $shift_start_time_dt;
	$log->debug("compare: start_time: " . $parser->format_datetime( $st ) . ' requested: ' . $parser->format_datetime( $requested_dt ) );
	my $es_duration = DateTime::Duration->new( seconds => $self->duration_seconds() );
	if ( $st > $requested_dt ) {
		$st -= DateTime::Duration->new( days => 1 );
	}
	if ( $st <=  $requested_dt and $st + $es_duration > $requested_dt ) {
		$log->debug("ES " . $self->to_string() . " fits " . $parser->format_datetime( $requested_dt ) );
		return 0;
	} elsif ( $st > $requested_dt ) {
		$log->debug("st>dt " . $self->to_string() . " does not fits rdt" . $parser->format_datetime( $requested_dt ) . ' end was ' . $parser->format_datetime( $st + $es_duration ) );
		return 1;
	} else {
		$log->debug("st<dt " . $self->to_string() . " does not fits rdt " . $parser->format_datetime( $requested_dt ) . ' end was ' . $parser->format_datetime( $st + $es_duration ) );
		return -1;
	}
}

# Doesn't do db queries
sub test_emanantise {
	my ( $self, $requested_dt ) = @_;
	if ( ref $requested_dt ne 'DateTime' ) {
		$requested_dt = DateTime->from_epoch( epoch=>$requested_dt, time_zone=>$openprint::TZ );
	}
	$log->debug("Emanentise: Date: " . $parser->format_datetime( $requested_dt ) ) if $debug;
	# The point is to drop any additional time part, but how can that be right? What we want to do is jump gaps

	my $shift_start_time_dt = DateTime::Duration->new( seconds => $self->starttime_seconds() % DAY );

	my $date_part_dt = $requested_dt->clone()->truncate(to=>'day');
	if ( $requested_dt->is_dst() and ! $date_part_dt->is_dst() ) {
#$log->debug("subtracting an hour for DST");
		$date_part_dt -= DateTime::Duration->new( hours=>1 );
	} elsif ( $date_part_dt->is_dst() and ! $requested_dt->is_dst() ) {
#$log->debug("adding an hour for DST");
		$date_part_dt += DateTime::Duration->new( hours=>1 );
	} # end if
	$log->debug("Date Part: " . $parser->format_datetime( $date_part_dt ) ) if $debug;

	my $st = $date_part_dt + $shift_start_time_dt;
	$log->debug("initial st: " . $parser->format_datetime( $st ) . ' requested: ' . $parser->format_datetime( $requested_dt ) ) if $debug;
	#if ( $st < $requested_dt ) {
		# Need to add a day
		# Who	y?because a shift may go into the next day.  
		#$st += DateTime::Duration->new( days=>1 );
		#$log->error("Dt > $st does not fit on this shift");
	#} els
	if ( $st > $requested_dt ) {
		$log->error("Dt < $st does not fit on this shift, minusing 1 day");
		$st -= DateTime::Duration->new( days=>1 );
	} # end if
	#$log->debug("final st: " . $parser->format_datetime( $st ) . ' requested: ' . $parser->format_datetime( $requested_dt ) );
	my $now = DateTime->now( time_zone => 'UTC' );
	my $es_duration = DateTime::Duration->new( seconds => $self->duration_seconds() );
	$_ = $now->clone->add_duration( $es_duration );
	$es_duration = $_->subtract_datetime_absolute( $now );

	my $et = $st->clone()->add_duration( $es_duration );
	#$log->debug("et: " . $parser->format_datetime( $et ) . " is_dst() ? " . $et->is_dst() . " st_dst? " . $st->is_dst() );
	if ( (!$st->is_dst()) and $et->is_dst() ) {
		$et -= DateTime::Duration->new( hours=>1 );
#$log->debug("subtracting an hour for DST new et:" . $parser->format_datetime( $et ));
	} elsif ( $st->is_dst() and ! $et->is_dst() ) {
#$log->debug("adding an hour for DST");
		$et += DateTime::Duration->new( hours=>1 );
	} # end if
	if ( $et < $requested_dt ) {
		$log->error("Dt > ET $et does not fit on this shift");
		return;
	}
	if ( $et <= $st ) {
		$log->error("ET $et <= ST $st so not creating Shift");
		return;
	}

	my $Shift = new openprint::Shift();
		$Shift->set({
				equipment_id	=>	$$self{equipment_id},
				#operator_id		=>	( $$self{operator_id} ? $$self{operator_id} : undef ),
				operator_ids		=>	$$self{operator_ids},
				shift_id		=>	$$self{id},
				starttime		=>	$parser->format_datetime( $st ),
				endtime			=>	$parser->format_datetime( $et ),
				});
	return $Shift;
} # end sub test_emanantise


#Pass back a shift for the next time slot >= the passed in $date_seconds
# We presume that normally date_seconds is teh starttie + 1 of the previous shift -> why? why not endtime?  I don't kn ow.
sub emanantise {
	my ( $self, $requested_dt ) = @_;
	$log->debug("Emanantise: " . $self->to_string() ) if $debug;

	if ( ref $requested_dt ne 'DateTime' ) {
		$requested_dt = DateTime->from_epoch( epoch=>$requested_dt, time_zone=>$openprint::TZ );
	}
	$log->debug("Emanentise: Date: " . $parser->format_datetime( $requested_dt ) ) if $debug;
	# The point is to drop any additional time part, but how can that be right? What we want to do is jump gaps

	my $shift_start_time_dt = DateTime::Duration->new( seconds => $self->starttime_seconds() % DAY );

	my $date_part_dt = $requested_dt->clone()->truncate(to=>'day');
	if ( $requested_dt->is_dst() and ! $date_part_dt->is_dst() ) {
#$log->debug("subtracting an hour for DST");
		$date_part_dt -= DateTime::Duration->new( hours=>1 );
	} elsif ( $date_part_dt->is_dst() and ! $requested_dt->is_dst() ) {
#$log->debug("adding an hour for DST");
		$date_part_dt += DateTime::Duration->new( hours=>1 );
	} # end if
	$log->debug("Date Part: " . $parser->format_datetime( $date_part_dt ) ) if $debug;

	my $st = $date_part_dt + $shift_start_time_dt;
	$log->debug("initial st: " . $parser->format_datetime( $st ) . ' requested: ' . $parser->format_datetime( $requested_dt ) ) if $debug;
	#if ( $st < $requested_dt ) {
		# Need to add a day
		# Who	y?because a shift may go into the next day.  
		#$st += DateTime::Duration->new( days=>1 );
		#$log->error("Dt > $st does not fit on this shift");
	#} els
	if ( $st > $requested_dt ) {
		$log->debug("Dt $requested_dt < $st does not fit on this shift, adding 1 hour");
		while ( $st > $requested_dt ) {
			$requested_dt += DateTime::Duration->new( hours=>1 );
		}
	
		# If this shift was on the second day of the rotation
		#return;
		#$st -= DateTime::Duration->new( days=>1 );
	} # end if
	#$log->debug("final st: " . $parser->format_datetime( $st ) . ' requested: ' . $parser->format_datetime( $requested_dt ) );
	# WTH is this for? now + duration - now()
	my $now = DateTime->now( time_zone => 'UTC' );
	my $es_duration = DateTime::Duration->new( seconds => $self->duration_seconds() );
$log->debug("Now + duration?" . $es_duration->in_units('seconds') );
	$_ = $now->clone->add_duration( $es_duration );
	$es_duration = $_->subtract_datetime_absolute( $now );
$log->debug("Now + duration?" . $es_duration->in_units('seconds') );

	my $et = $st->clone()->add_duration( $es_duration );
	$log->debug("et: $et (".$es_duration->in_units('seconds').") (".$self->duration_seconds().") is_dst() ? " . $et->is_dst() . " st_dst? " . $st->is_dst() );
	if ( (!$st->is_dst()) and $et->is_dst() ) {
		$et -= DateTime::Duration->new( hours=>1 );
#$log->debug("subtracting an hour for DST new et:" . $parser->format_datetime( $et ));
	} elsif ( $st->is_dst() and ! $et->is_dst() ) {
#$log->debug("adding an hour for DST");
		$et += DateTime::Duration->new( hours=>1 );
	} # end if
	if ( $et < $requested_dt ) {
		$log->error("Dt $requested_dt > ET $et does not fit on this shift");
		return;
	}

	my $Shift;
	# FIXME: This does not handle cases where the times have been overriden.
	# It should be looking for a shift that starts great than date_seconds, which we assume is the previous shift starttime+1
	# With an endtime before the end of the ES AFTER this one!
	# THe current iteration handles all that, except that the end is shorted than normal.
	if ( $Shift = openprint::Shift->find_one(
				equipment_id	=>	$$self{equipment_id},
				shift_id		=>	$$self{id},
				'starttime >='	=>	$parser->format_datetime( $st ),
# 2018-09-18 changed this from <= to <
				'starttime <'	=>	$parser->format_datetime( $et ),
				) ) {

		$log->debug("Emanantise found " . $Shift->to_string());
		# Looks for a shift of the right type that starts within the expected shift time. so start time can be moved up
	} else {
		$Shift = new openprint::Shift();
		$Shift->save({
				equipment_id	=>	$$self{equipment_id},
				operator_ids	=>	$$self{operator_ids},
				shift_id			=>	$$self{id},
				starttime			=>	$parser->format_datetime( $st ),
				endtime				=>	$parser->format_datetime( $et ),
				});
	} # end if
	return $Shift;
} # end sub emanantise

sub Equipment {
    return new openprint::Equipment( $_[0]{equipment_id} );
} # end sub Equipment

sub Operator {
 my ( $caller, undef, $line ) = caller;
$log->error("Deprecated call to Operator from $caller:$line");
	return new openprint::User( $_[0]{operator_id} );
} # end sub Operator

sub Operators {
	if ( ! $_[0]{Operators} ) {
		$_[0]{Operators} = [];
		if ( $_[0]{id} and $_[0]{operator_ids} and @{$_[0]{operator_ids}} ) {
			$_[0]{Operators} = [openprint::User->find(id=>$_[0]{operator_ids})];
		}
	}
	return @{$_[0]{Operators}};
}

sub First {
	my ( $self ) = @_;
	return openprint::Equipment_Shift->find_one( 
			'equipment_id'	=>	$$self{equipment_id},
			'order'			=>	'starttime',
			);
} # end sub First

sub Previous {
	if ( @_ > 1 ) {
		$_[0]{Previous} = $_[1];
	} # end if
	if ( ! $_[0]{Previous} ) {
	$_[0]{Previous} = openprint::Equipment_Shift->find_one( 
			'equipment_id'	=>	$_[0]{equipment_id},
			'starttime_seconds <'	=>	$_[0]{starttime_seconds},
			'order'			=>	'starttime_seconds DESC',
			);
	} # end if
	if ( ! $_[0]{Previous} ) {
	$_[0]{Previous} = openprint::Equipment_Shift->find_one( 
			'equipment_id'	=>	$_[0]{equipment_id},
			'order'			=>	'starttime_seconds DESC',
			);
	} # end if
	return $_[0]{Previous};
} # end sub Previous

sub Next {
	if ( @_ > 1 ) {
		$_[0]{Next} = $_[1];
	} # end if
	if ( ! $_[0]{Next} ) {
	$_[0]{Next} = openprint::Equipment_Shift->find_one( 
			'equipment_id'	=>	$_[0]{equipment_id},
			'starttime_seconds >'	=>	$_[0]{starttime_seconds},
			'order'			=>	'starttime_seconds',
			);
	} # end if
	if ( ! $_[0]{Next} ) {
		$_[0]{Next} = openprint::Equipment_Shift->find_one( 
			'equipment_id'	=>	$_[0]{equipment_id},
			'order'			=>	'starttime_seconds',
			);
	} # end if
	if ( ! $_[0]{Next} ) {
		$_[0]{Next} = new openprint::Equipment_Shift();
		$_[0]{Next}->set( { equipment_id => $_[0]{equipment_id} } );
	} # end if
	return $_[0]{Next};
} # end sub Next

sub delete {
	my $error;

	my $dt = DateTime->from_epoch( epoch=>time, time_zone=>$openprint::TZ );
	my $now = DateTime::Format::Pg->format_datetime( $dt );

	my $ac = sql::start_transaction( $openprint::dbh );

	foreach my $Shift ( openprint::Shift->find( shift_id=>$_[0]{id}, 'starttime <='=> $now ) ) {
		if ( $$Shift{shift_id} == $_[0]{id} ) {
			# Shifts aren't that special
			$error .= $Shift->delete();
			#$error .= $Shift->save({ shift_id=>undef });
		} else {
			$openprint::log->error("Equipment_Shift::delete deleting a shift that isn't ours!");
		} # end if
		last if $error;
	} # end foreach
	foreach my $Shift ( openprint::Shift->find( shift_id=>$_[0]{id}, 'starttime >'=> $now ) ) {
		if ( $$Shift{shift_id} == $_[0]{id} ) {
			$error .= $Shift->delete() 
		} else {
			$openprint::log->error("Equipment_Shift::delete deleting a shift that isn't ours!");
		} # end if
		last if $error;
	} # end foreach
	$error .= $_[0]->SUPER::delete() if ! $error;
	if ( $error ) {
		$openprint::dbh->rollback();
		return $error;
	} # end if
	sql::end_transaction( $openprint::dbh, $ac );
	return;
} # end sub delete

sub starttime_string {
	return 'Day ' . int( $_[0]{starttime_seconds} / DAY ) . ' ' .  misc::seconds2hms( $_[0]->starttime_seconds() % DAY );
} # end sub starttime_string

sub endtime_string {
	return 'Day ' . int( $_[0]->endtime_seconds() / DAY ) . ' ' .  misc::seconds2hms( $_[0]->endtime_seconds() % DAY );
} # end sub starttime_string

sub start_day {
	return int($_[0]{starttime_seconds} / DAY);
}

sub end_day {
	return int($_[0]->endtime_seconds() / DAY);
} # end sub end_day

sub start_hour {
	my $time = $_[0]{starttime_seconds} % DAY;
	return int($time/HOUR);
} # end sub start_hour

sub end_hour {
	my $time = $_[0]->endtime_seconds() % DAY;
	return int($time/HOUR);
} # end sub end_hour

sub start_minute {
	return int(( $_[0]{starttime_seconds} % HOUR )/60);
} # end sub start_minute

sub end_minute {
	return int(( $_[0]->endtime_seconds() % HOUR )/60);
} # end sub end_hour

sub Duration {
	my $dur = DateTime::Duration->new( seconds => $_[0]{duration_seconds} );
	return $dur;
}
sub duration {
	if ( @_ > 1 ) {
		my ( $h, $m, $s ) = split ( ':', $_[1] );
		$_[0]{duration_seconds} = ( $h * HOUR ) + ( $m * 60 ) + $s - 1;
		$_[0]{endtime_seconds} = $_[0]{starttime_seconds} + $_[0]{duration_seconds};
	} # end if
	return misc::seconds2hms( $_[0]{duration_seconds} );
} # end sub duration

sub duration_seconds {
	if ( @_ > 1 ) {
		$_[0]{duration_seconds} = $_[1];
		$_[0]{endtime_seconds} = $_[0]{starttime_seconds} + $_[0]{duration_seconds};
	} # end if
	return $_[0]{duration_seconds};
} # end sub duration_seconds

# Calculates the distance between an ES and it's next, or the given in seconds, taking into account wrap around
sub distance {
	my ( $self, $Next ) = @_;
	$Next = $self->Next() if ! $Next;
	if ( $$Next{starttime_seconds} > $$self{starttime_seconds} ) {
		return $$Next{starttime_seconds} - $self->endtime_seconds();
	} elsif ( $$self{starttime_seconds} == $$Next{starttime_seconds} ) {
		my $distance = DAY - $$self{duration_seconds};
		$distance = 0 if $distance < 0;
		return $distance;
		#return (DAY - $$self{duration_seconds})+1;
	} else {
		# Wrap around
		my $endtime = $self->endtime_seconds() % DAY;
		#if ( $endtime <= $$Next{starttime_seconds} ) {
			# No overlap
			return $$self{duration_seconds} + $$Next{starttime_seconds} - $endtime;
		#} else {
	} # end if
} # end sub


1;
__END__
