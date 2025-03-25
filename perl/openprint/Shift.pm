use strict;
package openprint::Shift;
our @ISA = qw(openprint::Object);
require openprint::Object;

use Carp;
use openprint ();
use vars qw(%variable $log $dbh %config %session $debug $table $serial %fields %find_fields %transforms %defaults );
*variable = \%openprint::variable;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;
*session = \%openprint::session;

require Date::Parse;
require openprint::Equipment_Shift;
require openprint::User;
require openprint::ScheduledJob;

$debug = 1;

$table = 'shifts';
$serial = 'shifts_id_seq';

%fields = (
	id								=>	'id',
	starttime					=>	'starttime',
	endtime						=>	'endtime',
	operator_ids			=>	'operator_ids',
	shift_id					=>	'shift_id',
	equipment_id			=>	'equipment_id',
	starttime_seconds	=>	undef,
	endtime_seconds		=>	undef,
	created_on				=>	'created_on',
	updated_on				=>	'updated_on',
);
%find_fields = (
	name		=>	'(SELECT name FROM equipment_shifts WHERE shift_id=equipment_shifts.id)',
	startdate	=>	'date(starttime)',
);

%transforms = (
	id			=>	[ 's/\D//g' ],
);

%defaults = (
	operator_ids		=>	'[]',
	created_on		=>	q`'NOW()'`,
	updated_on		=>	q`'NOW()'`,
);

my $parser = 'DateTime::Format::Pg';

sub starttime_dt {
	if ( $_[0]{starttime} ) {
		return $parser->parse_datetime( $_[0]{starttime} );
	} else {
		$openprint::log->error('tried to get a dt for '.$_[0]{starttime});
		return;
	}
}
sub starttime_seconds {
	if (@_ == 2) {
		$_[0]{starttime} = $parser->format_datetime( DateTime->from_epoch( epoch=>$_[1], time_zone=>$openprint::TZ ) );
	} # end if
	return $parser->parse_datetime($_[0]{starttime})->epoch();
} # endsub

sub startdate_seconds {
	my ( $self ) = @_;
	my $time = $self->starttime_seconds();
	return Date::Parse::str2time(Date::Format::time2str('%Y-%m-%d', $time));
} # end sub startdate_seconds

sub endtime_dt {
	return $parser->parse_datetime( $_[0]{endtime} );
}
sub endtime_seconds {
	if ( @_ == 2 ) {
		$_[0]{endtime} = Date::Format::time2str( '%Y-%m-%d %H:%M:%S%z', $_[1] );
		$_[0]{endtime_seconds} = $_[1];
	} # end if
	if ( ! $_[0]{endtime_seconds} ) {
		$_[0]{endtime_seconds} = Date::Parse::str2time( $_[0]{endtime} );
$log->debug("Parsing endtime_seconds to $_[0]{endtime_seconds} from $_[0]{endtime}");
	}
	return $_[0]{endtime_seconds};
} # end sub endtime_seconds

sub Operator {
	my ( $caller, undef, $line ) = caller;
	$log->error("Deprecated call to Shift::Operator from $caller:$line");
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

sub Equipment_Shift {
	return new openprint::Equipment_Shift( $_[0]{shift_id} );
} # end sub Equipment_Shift

# We have this here so that changing the shift_id will cause reloading of the shift name
sub shift_id {
	if ( @_ > 1 ) {
		$_[0]{shift_id} = $_[1];
		delete $_[0]{name};
	} # end if
	return $_[0]{shift_id};
} # end sub shift_id

sub name {
	my ( $self, $new_name ) = @_;
	if ( defined $new_name ) {
		$$self{name} = $new_name;
	} elsif ( ! $$self{name} ) {
		$$self{name} = $self->Equipment_Shift()->name();
	} # end if
	return $$self{name};
} # end sub name

sub schedule {
	return openprint::press_schedule->find(
			'starttime >='=>$_[0]{starttime},
			'starttime <='=>$_[0]{endtime},
			equipment_id	=>$_[0]{equipment_id}
			);
} # end sub schedule

sub Schedule {
	#if ( ! $_[0]{Schedule} ) {
		$_[0]{Schedule} = [ openprint::ScheduledJob->find( 
				( $_[0]{starttime} ? 
					( 
					 'starttime >='		=>	$_[0]{starttime}, 
					 'starttime <'		=>	$_[0]{endtime}, 
					) : (
						'starttime is null'	=>	$_[0]{starttime} ? 0 : 1,
						) ),
				equipment_id		=>	$_[0]{equipment_id},
				order				=>	'starttime,projectindex,service_id',
				)];
	#}
	return @{$_[0]{Schedule}};
} # end sub Schedule

sub Schedule_Without_Job {
	return map { $$_{id} != $_[1] ? $_ : () } $_[0]->Schedule();
}

sub operator_id {
	my $self = shift;
	my ( $caller, undef, $line ) = caller;
  $log->error("Deprecated call to Shift::operator_id from $caller:$line");
	return 0;
} # end sub operator_id

sub operator_ids {
	my $self = shift;

	if ( @_ ) {
		if ( $$self{id} ) {
			my @new_operator_ids = ( (@_ == 1) and (ref $_[0] eq 'ARRAY')) ? @{$_[0]} : @_;

$openprint::log->debug("Setting operator from ".join(',',@{$$self{operator_ids}})." to @new_operator_ids");
			foreach my $Job ( $self->Schedule() ) {
				$Job->save({ operator_ids=>@new_operator_ids });
			} # end foreach

			if ( sets::intersection(@new_operator_ids, @{$$self{operator_ids}}) != @new_operator_ids ) {
$openprint::log->debug("Setting operator to @new_operator_ids");
				$$self{operator_ids} = \@new_operator_ids;
				$self->save();
			} # end if
		} # end if
	} # end if
	return $$self{operator_ids};
} # end sub operator_id

sub Equipment {
	return new openprint::Equipment( $_[0]{equipment_id} );
} # end sub Equipment

sub to_string {
	my ( $self ) = @_;
	if ( ! exists $$self{to_string} ) {
		$$self{to_string} = sprintf('%s %s %s to %s op:(%s)', $self->Equipment()->name(), $self->name(), 
			$self->starttime() ? $parser->format_datetime( $self->starttime_dt ) : '',
			$self->endtime() ? $parser->format_datetime( $self->endtime_dt ) : '',
			join(', ', map { $_->name() } $self->Operators() )
			);
	} # end if
	return $$self{to_string};
} # end sub to_string

sub get_lis {
	my ( $Shift, $filters, $jobs ) = @_;

	my @Jobs = $jobs ? @{$jobs} : $Shift->Schedule();
	if ( ( ! @Jobs ) and ! $Shift->starttime() ) {
		return 'empty';
	} elsif ( $debug ) {
		$openprint::log->debug( @Jobs . " jobs loaded" );
	} # end if
	my $html;
	my $ul_id = $Shift->ul_id();

	foreach my $Job ( @Jobs ) {
		if ( $filters ) {
			if ( $$filters{Status} ) {
				next if ! $$Job{project_id};
				next if ! sets::isin( $Job->Project()->status(), $$filters{Status} );
			} # end if
		} # end if
		
		$html .= $Job->get_li( $ul_id );
	} # end foreach Job

	return $html;
} # end sub get_lis

sub ul_id {
	my ( $self ) = @_;
	if ( $self->starttime() ) {
		return sprintf('ul%d-%s-%s', $$self{equipment_id},
				Date::Format::time2str('%Y-%m-%d', $self->starttime_seconds() ),
				$self->name() );
	} else {
		return sprintf('ul%d-%s', $$self{equipment_id}, $self->name() );
	} # end if
} # end sub ul_id

sub get_from_ul_id {
	my ( $id ) = @_;

	$id =~ /^ul(\d*)-(\d\d\d\d-\d\d-\d\d)?-?(\w*)?$/;
	my ( $equipment_id, $date, $shift_name ) = ( $1, $2, $3 );

	my $Shift;
	if ( $date ) {
		$Shift = openprint::Shift->find_one(
				equipment_id=>$equipment_id,
				name=>($shift_name ? $shift_name : undef ),
				startdate=>$date );
		return if ! $Shift;
	} else {
		$Shift = new openprint::Shift();
		$Shift->set({ equipment_id	=>	$equipment_id });
		$Shift->name( $shift_name );
	} # end if Shift
	return $Shift;
} # end if

sub get_ul {
	my ( $Shift, $filters ) = @_;

	my $html;
	my $total_impressions = 0;

	my @Jobs = $Shift->Schedule();
	openprint::Project->find(id=>[ map { $$_{project_id} } @Jobs ]) if @Jobs;
	foreach my $Job ( @Jobs ) {
		if ( $filters ) {
			if ( $$filters{Status} ) {
				next if ! ( $$Job{project_id} and sets::isin( $Job->Project()->status(), $$filters{Status} ) );
			} # end if
		} # end if
		$total_impressions += $Job->impressions();
	} # end foreach Job

	# Why if name?
	if ( $Shift->starttime() ) {
		my ( $s, $min, $h, $day, $month, $year );
		if ( $Shift->starttime() ) {
			( $s, $min, $h, $day, $month, $year ) = Date::Parse::strptime( $Shift->starttime );
			$year += 1900;
			$month += 1;
		} # endif
		if ( Date::Calc::check_date( $year, $month, $day ) ) {
			my @Operators = $Shift->Operators();

			if ( openprint::usergroup::is_user_in( ['PressManager','Scheduling'], $session{user_id} ) ) {
				$html .= sprintf(
						q`
<div class="When" onclick="popup_window('_shift_popup.html','shift_id=%d', {width:475});" title="`.$$Shift{id} . ': '.$$Shift{starttime} . ' to ' . $$Shift{endtime}.q`">
  <span class="Interval">%s %d %.3s %s %s to %s</span>
  <span class="TotalImpressions">(%d)</span>
  <span class="%s">%s</span>
</div>`, 
						$$Shift{id}, 
						Date::Calc::Day_of_Week_Abbreviation( Date::Calc::Day_of_Week($year, $month, $day) ), 
						$day, 
						Date::Calc::Month_to_Text($month), $Shift->name(), 
						Date::Format::time2str('%H:%M', $Shift->starttime_seconds() ),
						Date::Format::time2str('%H:%M', $Shift->endtime_seconds() ),
						$total_impressions, (@Operators ? 'operator' : 'assign' ), 
						( @Operators ? join(', ', map { $_->name() } @Operators ) : 'assign'),
						);
			} else {
				$html .= sprintf(
						'<div class="When"><span class="Shift_time">%s %d %.3s %s %s to %s</span><span class="operator">%s</span></div>', 
						Date::Calc::Day_of_Week_Abbreviation( Date::Calc::Day_of_Week($year, $month, $day)), $day, Date::Calc::Month_to_Text( $month ), $Shift->name(), 
						Date::Format::time2str('%H:%M', $Shift->starttime_seconds() ),
						Date::Format::time2str('%H:%M', $Shift->endtime_seconds() ),
						( @Operators ? join(', ', map { $_->name() } @Operators ) : 'assign'),
						);
			} # end if
		} else {
			$openprint::log->debug("Not a valid date in Shift->get_ul() ($year,$month,$day) from $$Shift{starttime}");
		} # end if valid date
	#} else {
		#$openprint::log->debug("Shift does not have a name");
	} # end if Shift->name
# See if we are the last shift with jobs.
	my $content = $Shift->get_lis($filters);
	my @after_jobs = openprint::ScheduledJob->find(equipment_id=>$$Shift{equipment_id}, 'starttime >'=>$Shift->endtime()) if ! $content;
	$html = '<div id="'.$Shift->ul_id().'_div"'.((!($content or @after_jobs)) ? ' class="last"' : '').'>'.$html;
	$html .= sprintf('<ul id="%s" class="shift%s">', $Shift->ul_id(),
			($content ? '' : ' Empty'),
			);
	$html .= $content;
	$html .= '</ul></div>';
	return $html;
} # end sub get_ul

sub get {
	return $_[0]->Shift();
} # end sub get

sub Previous {
	my ( $self ) = @_;
	if ( ! $$self{Previous} ) {
		my $Previous = openprint::Shift->find_one('starttime <' => $self->starttime(), 'equipment_id'=>$$self{equipment_id}, 'order'=>'starttime DESC' );
		$log->debug( 'Previous: ' . $Previous->to_string() );
		$$self{Previous} = $Previous;
	} # end if
	return $$self{Previous};
} # end sub Previous

sub Next {
	my ( $self ) = @_;
	if ( ! $$self{Next} ) {
		my $Next = openprint::Shift->find_one('starttime >=' => $self->endtime(), equipment_id=>$$self{equipment_id}, order=>'starttime' );
		$log->debug( 'Next: ' . $Next->to_string() );
		if ( ! $Next ) {
			my $ES = openprint::Equipment_Shift->find_one(
					'equipment_id'		=>	$$self{equipment_id},
					'starttime_seconds >='	=>	$self->Shift()->Equipment_Shift()->endtime_seconds(),
					'order'			 =>	'starttime_seconds',
					);
			$Next = $ES->emanantise( $self->endtime_seconds() );
		} # end if
		$$self{Next} = $Next;
	} # end if
	return $$self{Next};
} # end sub Next

sub delete {
	my ( $self ) = @_;
	if ( ( ! $self->Equipment()->smartscheduling() ) and $self->Schedule() ) {
		return 'Cannot delete a shift with jobs in it.	Please move the jobs to another shift first.';	
	} # end if
	return $self->SUPER::delete();
} # end sub delete

sub TZ {
	if ( ! $_[0]{TZ} ) {
		$_[0]{TZ} = DateTime::TimeZone->new( name => $openprint::config{Timezone} );
	} # end if
	return $_[0]{TZ};
} # end sub TZ

# Returns shifts in the interval between start_dt and end_dt.

sub get_Shifts {
	my ( $Equipment, $start_dt, $end_dt, @Equipment_Shifts ) = @_;

	@Equipment_Shifts = $Equipment->Equipment_Shifts() if ! @Equipment_Shifts;
	if ( ! @Equipment_Shifts ) {
		$openprint::log->error("There are no shifts defined for " . $Equipment->to_string() );
		return ();
	}
	my @Shifts;
	# Three cases, no shifts, shifts before, shifts after.

	# Case #1 Shift before
	if ( my $LastShift = openprint::Shift->find_one(
			equipment_id	=>	$$Equipment{id},
# 2018-09-19 change from < to <= on the premise that the shift may start on the exact second
			'starttime <='	=>	$parser->format_datetime( $start_dt ),
			order			=>	'starttime DESC',
			) ) {
		$openprint::log->debug("Found a previous shift " . $LastShift->to_string() );
		# This is going to be thie most common
		my $last_dt = $LastShift->endtime_dt() + DateTime::Duration->new( seconds => 1 );

		if ( $LastShift->starttime_dt() <= $start_dt and $last_dt > $start_dt ) {
			# This can happen because we may call this with successive start_dt to adjust the start to the start of a shift
			$openprint::log->debug("Have a Shift for the given start time $last_dt < $start_dt ");
			return ( $LastShift );
		}
		my $ES_index = 0;

		# Find the index of the matching shift.
		for ( $ES_index = 0; $ES_index < @Equipment_Shifts; $ES_index += 1 ) { 
			if ( $Equipment_Shifts[$ES_index]{id} == $$LastShift{shift_id} ) {
				last;
			}
		}

		if ( $ES_index == @Equipment_Shifts ) {
			$log->error("Unable to find ES $$LastShift{shift_id} in Equipment_Shifts");
			$ES_index = 0;
		} else {
$log->debug("Found ES for last shift: " . $Equipment_Shifts[$ES_index]->to_string() . " at index $ES_index" );
			$ES_index += 1;
			$ES_index = 0 if $ES_index == @Equipment_Shifts;
		}
		
		# The ordering of the Shifts is important for multi-day schedules
		while ( $last_dt < $end_dt ) {
$log->debug("Last_dt: $last_dt < job end time: $end_dt");
			while ( $Equipment_Shifts[$ES_index]->compare( $last_dt ) ) {
				# Add by hours until we fit into a shift again.
				$last_dt += DateTime::Duration->new( seconds => 3600 );
$log->debug("while Last_dt: $last_dt < $end_dt");
				last if $last_dt > $end_dt;
			} # end if

			if ( $last_dt > $end_dt ) {
				# Found a shift after the requested time period.  So give up.
				$log->debug("last cuz Last_dt: $last_dt > $end_dt");
				last;
			}

			# Need to start on the correct shift.
			my $Shift = $Equipment_Shifts[$ES_index]->emanantise( $last_dt );
			if ( $Shift ) {
				$last_dt = $Shift->endtime_dt() + DateTime::Duration->new( seconds => 1 );

				# Onlyr eturn the shifts asked for, even though this may generate shifts prior to when asked for
				push @Shifts, $Shift if $Shift->starttime_dt() > $start_dt;
			} else {
				$log->error("UNablet o get shift for $last_dt");
			} # end if
			$ES_index += 1;
			$ES_index = 0 if $ES_index == @Equipment_Shifts;
		} # end while last_dt < end_dt

	} elsif ( my $NextShift = openprint::Shift->find_one(
			equipment_id	=>	$Equipment->id(),
			'starttime >'	=> $parser->format_datetime( $start_dt ),
			order			=>	'starttime',
			) ) {
$openprint::log->debug("Have shift after: " . $NextShift->to_string());
		# No previous shifts, but have one after, so go backwards
		my $next_time = $NextShift->starttime_seconds();
		while ( $NextShift->starttime_seconds() > $start_dt->epoch() ) {
			my $PreviousEquipmentShift = $NextShift->Equipment_Shift()->Previous();
$openprint::log->debug("Have previous Equipment Shift" . $PreviousEquipmentShift->to_string());

			my $previous_seconds = $NextShift->starttime_seconds() - $PreviousEquipmentShift->duration_seconds();

			$NextShift = $PreviousEquipmentShift->emanantise( $previous_seconds );
			if ( ! $NextShift ) {
$openprint::log->error("Unable to emanantise for $previous_seconds " . Date::Format::time2str($config{DateTimeFormat}, $previous_seconds));
				last;
			}
			unshift @Shifts, $NextShift if $NextShift->starttime_seconds() < $end_dt->epoch();
		} # end while
	} else {
	# Just add them all in the specified range
		my $ES = $Equipment_Shifts[0];
		while ( $start_dt < $end_dt ) {
$openprint::log->debug("Eman for " . $start_dt->epoch());
			my $Shift = $ES->emanantise( $start_dt->epoch() );
			if ( ! $Shift ) {
				$log->error("failed to emanantise");
				last;
			} elsif ( ref $Shift ne 'openprint::Shift' ) {
				$log->error("emanantise returned crap $Shift");
			} # end if

			if ( $start_dt->epoch() > $Shift->starttime_seconds() ) {
				$log->error("Created shift before requeted time!");
				last;
			} else {
				push @Shifts, $Shift;
				$log->debug("Starttime : " . $parser->format_datetime($start_dt). ' ' . $parser->format_datetime( DateTime->from_epoch( 'epoch'=>$Shift->starttime_seconds(), 'time_zone'=>$start_dt->time_zone() ) ));
			} # end fi
			$start_dt = DateTime->from_epoch( 'epoch'=>$Shift->starttime_seconds() + 1, 'time_zone'=>$start_dt->time_zone() );
			$ES = $ES->Next();
		} # end while
	} # end if
	return @Shifts;
} # end sbu get_Shifts

sub docket {
	if ( ! $_[0]{docket} ) {
		$_[0]{docket} = $_[0]->Project()->docket();
	}
	return $_[0]{docket};
}

sub add_job {
	my ( $self, $Job ) = @_;

	my @Schedule = $self->Schedule();
	$Job->starttime_seconds( @Schedule ? $Schedule[@Schedule-1]->endtime_seconds()+1 : $self->starttime_seconds() );
	$Job->save();

	if ( $self->Equipment->smartscheduling() ) {
		my @before = openprint::ScheduledJob->find(
				equipment_id=>$$self{equipment_id},	
				'starttime <'	=>	$Job->starttime(),
				'id !='				=>	$$Job{id},
				order					=>	'starttime'
				);
		my @after = openprint::ScheduledJob->find(
				equipment_id=>$$self{equipment_id},	
				'starttime <'	=>	$Job->starttime(),
				'id !='				=>	$$Job{id},
				order	=>	'starttime'
				);
		openprint::employee_production::reorder_jobs( @before, $Job, @after );
	}
}

sub check_and_fix {
	my ( $Shift ) = @_;

	if ( $Shift->endtime_seconds() == $Shift->starttime_seconds() ) {
		$openprint::log->warn("Resetting shift duration because it is zero");
		$openprint::log->debug("Shift before " . $Shift->to_string());
		$Shift->endtime_seconds( $Shift->starttime_seconds() + $Shift->Equipment_Shift()->duration_seconds() );
		$openprint::log->debug("Shift aftere " . $Shift->to_string());
		$openprint::log->debug("Added " . $Shift->Equipment_Shift()->duration_seconds() . ' seconds');
		$Shift->save() if $Shift->endtime_seconds() != $Shift->starttime_seconds();
	}
} # end sub check_and_fix


1;
__END__
