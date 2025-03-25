package openprint::press_schedule2;
use strict;

require openprint::Project;
require openprint::Service;
require openprint::service;
require openprint::Schedule;
require Date::Calc;

my $debug = 1;

sub parse_param {
	my $p = shift;
	my $sql;
	my @values;

#$openprint::log->debug("Parse_param $p");
	if ( $p->{fields} ) {
		my @sql;
		foreach my $param ( @{$p->{fields}} ) {
			my ( $sql_frag, @vals ) = parse_param( $param );
			push @sql, $sql_frag;
			push @values, @vals;
		} # end foreach
		$sql .= ' (' . join( ' ' . $p->{operator}.' ', @sql ) . ') ';
	} elsif ( $p->{operator} eq 'BETWEEN' ) {
		$sql .= '('.$p->{field} . ' BETWEEN ? AND ? )';
		push @values, @{$p->{values}};
	} elsif ( $p->{operator} eq 'order') {
		$sql = ' ORDER BY ' . $p->{value};
	} elsif ( $p->{operator} ) {
		$sql .= $p->{field} . ' ' . $p->{operator};
		if ( $p->{value} ) {
			$sql .= ' ?';
			push @values, $p->{value};
		} # end if
	} # end if
#$openprint::log->debug("Returning $sql");
	return ( $sql, @values );
	
} # end sub parse_param

sub find {
  shift if $_[0] eq 'openprint::press_schedule2';
	#my %params = @_;
	my @values;
	my $sql = 'SELECT * FROM Schedule WHERE ';
	foreach my $param ( @_ ) {
#$openprint::log->debug( $param );
		my ( $s, @v ) = parse_param( $param );
		$sql .= $s;
		push @values, @v;
	} # end foreach
	#} # end if
	#if ( $params{'service_status'} ) {
		#if ( ref $params{'service_status'} eq 'ARRAY' ) {
			#$sql .= ' AND (SELECT strStatus FROM tbl_Project_Contents WHERE lngProjectIndex=ProjectIndex AND lngServiceIndex=ServiceIndex) IN ('.join(',', map { '?' } @{$params{'service_status'}} ).')';
			##push @values, @{$params{'service_status'}};
		#} else {
			#$sql .= ' AND (SELECT strStatus FROM tbl_Project_Contents WHERE lngProjectIndex=ProjectIndex AND lngServiceIndex=ServiceIndex)=?';
			#push @values, $params{'service_status'};
		#} # end if
	#} # end if
	#if ( $params{'equipment_id'} ) {
		#$sql .= ' AND equipment_id=?';
		#push @values, $params{'equipment_id'};
	#} # end if
	#if ( $params{'project_id'} ) {
		#if ( substr($params{'project_id'},0,1) == '!' ) {
			#$sql .= ' AND projectindex != ?';
			#push @values, substr $params{'project_id'}, 1, length $params{'project_id'};
		#} else {
			#$sql .= ' AND projectindex=?';
			#push @values, $params{'project_id'};
		#} # end if
	#} # end if
	#if ( $params{'service_id'} ) {
		#$sql .= ' AND service_id=?';
		#push @values, $params{'service_id'};
	#} # end if
#
	#$sql .= " ORDER BY $params{'order'}" if $params{'order'};
	my $data = $openprint::dbh->selectall_arrayref( $sql, {Slice=>{}}, @values );
	if ( ! $data ) {
		$openprint::log->error( "Error loading schedule: ($sql) (@values) : " . $openprint::dbh->errstr() );
		return;
	} elsif ( $debug ) {
		$openprint::log->debug( "Loading schedule: ($sql) (@values) : " . @$data );
	} # end if
	return map { new openprint::Schedule( $_->{id}, $_ ) } @$data;
} # end sub find


sub remove {
	sql::execute( undef, undef, q{DELETE FROM Schedule WHERE ProjectIndex=? AND ServiceIndex=?}, @_ );
}

sub get_li {
	my ( $previous_row, $row, $ul_id, $starttime ) = @_;

	my $html;
	my $Project = new openprint::Project( $$row{'projectindex'} );
	#my %specs = openprint::service::get_specifications_pairs( $openprint::log, $openprint::dbh, @$row{'projectindex','service_id'} );
	#if ( ! $specs{'txtEmployeeComments'} ) {
		#my @side_one = openprint::print_printing::get_colours( \%specs, 'SideOne' );
		#my @side_two = openprint::print_printing::get_colours( \%specs, 'SideTwo' );
		#$specs{'txtEmployeeComments'} .= sprintf( '%d/%d', scalar @side_one, scalar @side_two );
#
		#my %pms;
		##foreach my $side ( 'SideOne', 'SideTwo' ) {
			#foreach my $index ( 1 .. 8 ) {
				#if ( $specs{'chkSpecial'.$side.'Colour'.$index} ) {
					#if ( $specs{'txtSpecial'.$side.'Colour'.$index} ) {
						#$pms{$index} += 1;
					#} # end if
				#} # end if
			#} # end foreach index
		#} # end foreach side
		#if ( keys %pms ) {
			#$specs{'txtEmployeeComments'} .= '+' . ( keys %pms ) . ' PMS';
		#} # end if
#
		#if ( $specs{'rdbAqueousSideOne'} ne 'None' or $specs{'rdbAqueousSideTwo'} ne 'None' ) {
			#$specs{'txtEmployeeComments'} .= '+AQ';
		#} # end if
		#if (
				#$specs{'chkVarnishSpotGlossSideOne'}
				#or $specs{'chkVarnishSpotMatteSideOne'}
				#or $specs{'chkVarnishOverallGlossSideOne'}
				##or $specs{'chkVarnishOverallMatteSideOne'}
				#or $specs{'chkVarnishSpotGlossSideTwo'}
				#or $specs{'chkVarnishSpotMatteSideTwo'}
				#or $specs{'chkVarnishOverallGlossSideTwo'}
				#or $specs{'chkVarnishOverallMatteSideTwo'}
			#) {
			#$specs{'txtEmployeeComments'} .= '+Varnish';
		#} # end if
#
		#$specs{'txtEmployeeComments'} .= ' on ' . $specs{'ddmStockSheetSize'};
		#openprint::service::insert_service_spec( $openprint::log, $openprint::dbh, @$row{'projectindex','service_id'}, 'txtEmployeeComments', $specs{'txtEmployeeComments'} );
	#} # end if

	#if ( ! $specs{'SignatureQuantity'} ) {
		#$specs{'SignatureQuantity'} = $specs{'txtSignatureQuantity'} ? $specs{'txtSignatureQuantity'} : 1;
		#openprint::service::insert_service_spec( $openprint::log, $openprint::dbh, @$row{'projectindex', 'service_id'}, 'SignatureQuantity', $specs{'SignatureQuantity'} );
	#} # end if
	#if ( ! $specs{'ImpressionQuantity'} ) {
		#my ( $qty_index ) = sql::execute( $openprint::log, $openprint::dbh, q{SELECT intQuantityIndex FROM Order_Contents WHERE lngProjectIndex=?}, $$row{'projectindex'} );
#
		#$specs{'ImpressionQuantity'} = $specs{'hdnImpressionQuantity'.$qty_index};
		#$specs{'ImpressionQuantity'} /= 2 if $specs{'ddmRunStyle'} eq 'Perfecting';
		#openprint::service::insert_service_spec( $openprint::log, $openprint::dbh, @$row{'projectindex', 'service_id'}, 'ImpressionQuantity', $specs{'ImpressionQuantity'} );
#
	#} # end if
	my $colour = 'blue';
	if ( sets::isin( $Project->status(), ['In Prepress', 'Proofs Out','Waiting For QA Approval'] ) ) {
		$colour = 'green';
	} elsif ( sets::isin( $Project->status(), ['Printed', 'Complete','Waiting For Pickup', 'Picked Up', 'Shipped'] ) ) {
		$colour = 'pink';
	} elsif ( sets::isin( $Project->status(), 'Waiting For Customer Approval' ) ) {
		$colour = 'red';
	} elsif ( 1 < sql::execute( $openprint::log, $openprint::dbh, q{SELECT DISTINCT equipment_id FROM Schedule WHERE projectindex=?}, $$row{'projectindex'} ) ) {
		$colour = 'yellow';
	} # end if

	my $unallocated_space = Date::Parse::str2time($$row{'starttime'});
	$unallocated_space -= Date::Parse::str2time($starttime );
 #if ( $previous_row ) {
	#$unallocated_space -= Date::Parse::str2time($$previous_row{'starttime'} )
#} else {
	#my ($date, $time ) = split (' ', $$row{'starttime'});
	#$unallocated_space -= Date::Parse::str2time($date )
#
#} # end if
	$unallocated_space = 0 if $unallocated_space < 0;
	$unallocated_space /= 60;

		my ( $h, $m, $s ) = split( ':', $$row{'runtime'} );
		my $runtime = (($h*3600 + $m*60 + $s)/60) -2;
		$runtime = openprint::service::get_runtime( $Project, $$row{'service_index'} ) if $runtime < 20;
		$runtime = 20 if $runtime < 20;
		#$runtime =4320 if $runtime < 4320;
# 4320 = 12hours in seconds
	$html .= sprintf( '<li id="service_%d" class="sizer %s" style="width:%dpx;">', $$row{'service_id'}, $colour, $runtime );
	#$html .= sprintf('<span id="sizer_%d" class="sizer"></span>', $$row{'service_id'} );
	if ( ( ! $previous_row ) or ( $$row{'projectindex'} != $$previous_row{'projectindex'} ) ) {
		#$html .= '<div class="Company">';
		$html .= sprintf( '<a class="docket" href="/employee/project/view.html?ProjectIndex=%1$d&Docket=%2$d">%2$d</a>', $$row{'projectindex'}, $Project->docket() );
		#$html .= $Project->Company->name();
		#$html .= '</div>';
#$html .= $$row{'starttime'} . ' ';
$html .= $$row{'value'};
		#$html .= qq`<span class="DueDate" id="JumpToDate$$row{'service_id'}">`;
		#if ( ! $Project->due_date() ) {
			#$html .= 'no duedate</span>';
		#} else {
			#my ( $year, $month, $day ) = split('-', $Project->due_date() );
			#if ( $month ) { $html .= '&nbsp;'.substr( Date::Calc::Month_to_Text( $month ),0, 3); } # end if
				#$html .= qq` $day</span>`;
		#} # end if

		if ( openprint::usergroup::is_user_in( ['Scheduling'], $openprint::session{'user_id'} ) ) {
			#$html .= sprintf(q`<input type="hidden" name="ScheduleDate-%1$d" id="ScheduleDate-%1$d" value="%2$s"/>`, $$row{'service_id'}, $Project->due_date() );
			#$html .= qq`
				#<script type="text/javascript">
				#Calendar.setup({
				#inputField	 :	"ScheduleDate-$$row{'service_id'}",		// id of the input field
				#ifFormat		:	"\%Y-\%m-\%d",		// format of the input field
				#daFormat		:	"\%b \%d",
				#align			:	"Tl",
				#showsTime		:	false,			// will display a time selector
				#displayArea	:	'JumpToDate$$row{'service_id'}',
				#singleClick	:	false,			// double-click mode
				#onClose		:	setduedate
				#});
				#</script>
				#`;
			} # end if
	} # end if
	if ( openprint::usergroup::is_user_in( $openprint::log, $openprint::dbh, ['Scheduling'], $openprint::session{'user_id'} ) ) {
		#$html .= sprintf( '<div id="%2$dComment" class="Comment" onClick="editComment( %1$s, %2$s, \'%3$s\', event );">%3$s</div>', @$row{'projectindex','service_id'}, @specs{'txtEmployeeComments'} );

		#$html .= sprintf( '<span class="Forms" id="%dForms" onClick="editForms(%s, %s,\'%s\', event );">%d %s</span>', @$row{'service_id','projectindex','service_id'}, @specs{'SignatureQuantity','SignatureQuantity'}, ($specs{'SignatureQuantity'} > 1 ? ' forms' : ' form') );
		#$html .= sprintf( '<span id="%dImpressions" class="Impressions"><span onClick="editImpressions(%s, %s,\'%s\', event );">%d imps</span></span>', @$row{'service_id','projectindex','service_id'}, @specs{'ImpressionQuantity','ImpressionQuantity'} );

		#$html .= '<span class="Buttons">';
		#$html .= ssi::writeButton( $openprint::log, $openprint::dbh, 'Approve'.$$row{'service_id'}, '', "if(confirm('Are you sure?')){f1.ProjectIndex.value=$$row{'projectindex'};f1.ServiceIndex.value=$$row{'service_id'};f1.btnFunction.value='ApproveJob';f1.submit();}", '', 'A' ) if sets::isin( $Project->status(), 'In Prepress', 'Proofs Out','Waiting For Customer Approval','Waiting For QA Approval' );
		#$html .= ssi::writeButton( $openprint::log, $openprint::dbh, 'Bump'.$$row{'service_id'}, '', "if(confirm('Are you sure?')){f1.ProjectIndex.value=$$row{'projectindex'};f1.ServiceIndex.value=$$row{'service_id'};f1.btnFunction.value='BumpJob';f1.submit();}", '', 'B' );
		#$html .= ssi::writeButton( $openprint::log, $openprint::dbh, 'Complete'.$$row{'service_id'}, '', "if(confirm('Are you sure?')){f1.ProjectIndex.value=$$row{'projectindex'};f1.ServiceIndex.value=$$row{'service_id'};f1.btnFunction.value='CompleteJob';f1.submit();}", '', 'C' );
		#$html .= ssi::writeButton( $openprint::log, $openprint::dbh, 'Remove'.$$row{'service_id'}, '', "if(confirm('Are you sure?')){f1.ProjectIndex.value=$$row{'projectindex'};f1.ServiceIndex.value=$$row{'service_id'};f1.btnFunction.value='RemoveJob';f1.submit();}", '', 'D' );
		#$html .= ssi::writeButton( $openprint::log, $openprint::dbh, 'Split'.$$row{'service_id'}, '', "if(confirm('Are you sure?')){split_job($$row{'projectindex'}, $$row{'service_id'}, '$ul_id' );}", '', 'S' ) if $specs{'SignatureQuantity'} > 1;
		#$html .= '</span>';
	} else {
		#$html .= qq`<div class="Comment">$specs{'txtEmployeeComments'}</div>`;
		#$html .= sprintf( '<span class="Forms">%d %s</span>', $specs{'SignatureQuantity'}, ($specs{'SignatureQuantity'} > 1 ? ' forms' : ' form') );
		#$html .= sprintf( '%d imps', $specs{'ImpressionQuantity'} );
	} # end if
	$html .= '</li>';
	return $html;
} # end sub get_li

sub get_ul {
	my ( $start_time_start, $start_time_end, $equipment_id, $shift ) = @_;
	my $total_impressions;

	my $ul_id = join('-', $equipment_id,  $start_time_start );

	my @schedule = find( 
			{'operator'=>'AND', 'fields'=>[
				{'operator'=>'OR', 'fields'=>[
					{ 'operator'=>'BETWEEN', 'field'=>'starttime', 'values'=>[$start_time_start . ' 00:00:00', $start_time_end . ' 23:59:59'] },
					{ 'operator'=>'BETWEEN', 'field'=>'endtime', 'values'=>[$start_time_start . ' 00:00:00', $start_time_end . ' 23:59:59'] },
] },
				{'operator'=>'=','field'=>'equipment_id','value'=>$equipment_id},
			] },
			{'operator'=>'order', value=>'starttime,service_id'},
			);
	my $Interval = Date::Parse::str2time( $start_time_end . ' 23:59:59' ) - Date::Parse::str2time($start_time_start . ' 00:00:00');
	$Interval /= 60;

# This is just for caching purposes
	if ( @schedule ) {
		my @projects = map { $$_{projectindex'} } @schedule;
		if ( @projects ) {
			my @companies = map { $_->company_id() } openprint::Project::find( 'id'=>\@projects );
			openprint::Company::find( 'id'=>\@companies );
		} # end if
	} # end if

	my $html;

	my $previous_row;

	for ( my $index = 0; $index < @schedule; $index += 1 ) {
		my $current_row = $schedule[$index];

		$html .= get_li( $previous_row, $current_row, $ul_id, $start_time_start  );
		my $specs = openprint::service::get_specs_ref( @$current_row{'projectindex','service_id'} );
		$total_impressions += $$specs{'ImpressionQuantity'};
		$previous_row = $current_row;
	} # end for

	return qq{<ul id="$ul_id" class="Schedule shift} . (@schedule ? '' : ' Empty' ) .'" style="width:'.$Interval.'px">' . $html. "</ul>\n";
} # end sub get_ul

sub apply_sort {
$openprint::log->debug("Applying Sort");
	my $ac = sql::start_transaction( $openprint::dbh );
	$openprint::dbh->do( "LOCK TABLE Schedule IN SHARE ROW EXCLUSIVE MODE" ) or $openprint::log->error( DBI->errstr );
	my $starttime = $_[0]{starttime};
	if ( ! $starttime ) {
		$starttime = sprintf( '%.4d-%.2d-%.2d %2.d:%.2d:%.2d', Date::Calc::Today_and_Now() );
	} # end if
	foreach my $row ( @_ ) {
		sql::update( undef, undef, 'Schedule', ['ProjectIndex=? AND ServiceIndex=?', @$row{'projectindex','service_id'}], 'starttime', $starttime, 'equipment_id', $$row{'equipment_id'}, 'value', $$row{'value'},'runtime', $$row{'runtime'}, 'endtime', $$row{'endtime'} );
		( $starttime ) = sql::execute( undef, undef, q{SELECT starttime+runtime FROM Schedule WHERE ProjectIndex=? AND ServiceIndex=?}, @$row{'projectindex','service_id'} );
	} # end foreach
	sql::end_transaction( $openprint::dbh, $ac );
} # end sub apply_sort

sub drop_project {
	my ( $r, $log, $dbh, $variable, $id, $services ) = @_;
	$services =~ s/$id\[\]=//g;
	my @order = split( '&', $services );

	my ( $press_index, $year, $month, $day ) = $id =~ /(\d*)-(\d\d\d\d)-(\d+)-(\d+)/;
	# Start time is always now.  Can't schedule in the past.  The Past is fixed.
	my $start_time = sprintf('%.4d-%.2d-%.2d 00:00:00', $year, $month, $day );

	my %schedule = map { $_->{'service_id'}, $_ } find( {'operator'=>'AND', 'fields'=>[
			{'field'=>'equipment_id','operator'=>'=', 'value'=>$press_index},
			{'field'=>'starttime','operator'=>'>=', 'value'=>$start_time},
			]});
	my @new_schedule;

	my %altered_schedules;

	foreach my $service_index ( @order ) {
		$service_index =~ s/\D//g;
		next if ! $service_index;
		if ( $schedule{$service_index} ) {
			# Already on the schedule, so it's just a re-ordering
			push @new_schedule, $schedule{$service_index};
		} else {
			# Maybe come from different press, maybe from pending
			if ( my @entries = find({'field'=>'service_id','operator'=>'=', 'value'=>$service_index}) ) {
				my $entry = shift @entries;
				if ( $$entry{'equipment_id'} ) {
					if ( Date::Parse::str2time( $altered_schedules{$$entry{'equipment_id'}} ) < Date::Parse::str2time( $$entry{'starttime'} ) ) {
						$altered_schedules{$$entry{'equipment_id'}} = $$entry{'starttime'};
					} # end if
				} # end if
				$$entry{'equipment_id'} = $press_index;
				push @new_schedule, $entry;
			} else {
				# FIXME ERROR
			} # end if
		} # end if
	} # end foreach
	$new_schedule[0]{'starttime'} = $start_time if @new_schedule;
	apply_sort( @new_schedule );
} # end sub drop_project

sub sort_schedule {
	my %jobs;
	my @equipment = openprint::Equipment::find( 'use_in_scheduling'=>'1','category'=>'Printing' );
	# First need to load and initialise the schedule
	my @schedule = find( 
			{'operator'=>'AND', 'fields'=>[
			#{'field'=>'starttime', 'operator'=>'>=', 'value'=>sprintf( '%.4d-%.2d-%.2d %.2d:%.2d:%.2d', Date::Calc::Today_and_Now() )},
			{'field'=>'(SELECT strStatus FROM tbl_Projects WHERE Index=projectindex)', 'operator'=>'=', 'value'=>'Approved' },
			{'field'=>'starttime', 'operator'=>'IS NOT NULL'},
			] }, {'operator'=>'order', 'value'=>'projectindex' },
			);

	# @_ contains jobs to be added to the scedhule
	foreach my $job ( @schedule, @_ ) {
		$$job{'starttime_seconds'} = Date::Parse::str2time( $$job{'starttime'} );
		$$job{'runtime_seconds'} = misc::interval_to_seconds( $$job{'runtime'} );
		$job->display();
		if ( $$job{'locked'} ) {
			push @{$jobs{$$job{equipment_id}}}, $job;
		} else {
			if ( ! $$job{'runtime'} ) {
				my $r = openprint::service::get_runtime( new openprint::Project( $$job{'projectindex'} ), $$job{'service_id'} );
				$$job{'runtime'} = sprintf('%.2d:%.2d:00', $r/60, $r%60);
			} # end if
			push @{$jobs{''}}, $job;
		} # end if
	} # end foreach
	# Sort the locked jobs
	foreach my $Equipment ( @equipment ) {
		@{$jobs{$Equipment->id()}} = sort { $$a{starttime_seconds} <=> $$b{'starttime_seconds'} } @{$jobs{$Equipment->id()}} if $jobs{$Equipment->id()};
	} # end foreach

	my %original_values;

	foreach my $job ( @{$jobs{''}} ) {
		$job->display();
		# Try out each slot
		my %best;
		foreach my $Equipment ( @equipment ) {
			my %e_best;
			my $elapsed = time;
			my @after = @{$jobs{$Equipment->id()}} if $jobs{$Equipment->id()};
			my @before;
			my $damage;
			$original_values{$Equipment->id()} = get_value( $Equipment, @before, @after ) if ! exists $original_values{$Equipment->id()};

			my $before_value = 0;
			while ( @after ) {
				# Need the previous job as well
				my @s = ( @before, arrange_schedule( $job, @after ) );
			foreach my $j ( ($job, @after) ) {
				delete $$j{'value'};
			}
			my $value = get_value($Equipment, @s );
			$damage = $value - $original_values{$Equipment->id()};
				if ( ( ! %e_best ) or ( $damage > $e_best{'damage'} ) ) {
					$e_best{'value'} = $value;
					$e_best{'damage'} = $damage;
					$e_best{'Equipment'} = $Equipment;
					@{$e_best{'placement'}} = @s;
				} # end if
				$_ = shift @after;
				push @before, $_;
					#my $length = @before;
					#if ( $length > 1 ) {
						#$before_value += get_value($Equipment, $before[$length-2], $before[$length-1] );
					#} else {
						#$before_value += $before[0]{'value'};
					#} # end if
					#$openprint::log->debug( $Equipment->id() . ": $length: $before_value : " . @after );
			} # end while @after

			my @s = ( @before, arrange_schedule( $job, @after ));
			foreach my $j ( ($job, @after) ) {
				delete $$j{'value'};
			}
			my $value = get_value($Equipment, @s );
			$damage = $value - $original_values{$Equipment->id()};
			if ( ( ! %e_best ) or ( $damage > $e_best{'damage'} ) ) {
				$e_best{'value'} = $value;
				$e_best{'damage'} = $damage;
				$e_best{'Equipment'} = $Equipment;
				@{$e_best{'placement'}} = @s;
			} # end if

			$openprint::log->debug("Equipment: " . $Equipment->name() . ' ' .@{$e_best{'placement'}} . ' jobs Total Value:' . $original_values{$Equipment->id()} . ' damage: ' . $e_best{'damage'} );
			if ( ( ! %best ) or ( $e_best{'damage'} > $best{'damage'} ) ) {
				%best = %e_best;
			} # end if
		} # end foreach Equipment
$openprint::log->debug("SELECTED Equipment: " . $best{'Equipment'}->name() . ' Total Value:' . $original_values{$best{'Equipment'}->id()} . ' ' . $best{'damage'} . ' jobs: ' . @{$best{'placement'}} );
		@{$jobs{$best{'Equipment'}->id()}} = @{$best{'placement'}};
		$original_values{$best{'Equipment'}->id()} = $best{'value'};
$openprint::log->debug("SELECTED Equipment: " . $best{'Equipment'}->name() . ' Total Value:' . $original_values{$best{'Equipment'}->id()} . ' ' . $best{'damage'} . ' jobs: ' . @{$best{'placement'}} );
	} # end foreach job
	foreach my $Equipment ( @equipment ) {
		next if ! $jobs{$Equipment->id()};
		get_value( $Equipment, @{$jobs{$Equipment->id()}} );
$openprint::log->debug(@{$jobs{$Equipment->id()}} . ' jobs on ' . $Equipment->name() );
		$jobs{$Equipment->id()}[0]{'starttime'} = sprintf('%.4d-%.2d-%.2d %.2d:%.2d:%.2d', Date::Calc::Today_and_Now() );
		foreach my $j ( @{$jobs{$Equipment->id()}} ) {
			$$j{'equipment_id'} = $Equipment->id();
		} # end foreach
		apply_sort( @{$jobs{$Equipment->id()}} );
	} # end foreach

} # end sub sort_schedule

sub get_value {
	my $Equipment = shift;

	
	my $cost;
	for ( my $i = 0; $i < @_; $i += 1 ) {
		if ( ! exists $_[$i]{'value'} ) {
		$_[$i]{'value'} = cost( $Equipment, ( $i-1 ? $_[$i-1] : undef ), $_[$i], ($i+1 > @_) ? undef : $_[$i+1] );
$openprint::log->debug("Getting calue:" . $_[$i]{'value'} );
} else {
$openprint::log->debug("calue:" . $_[$i]->{'value'} );
		} # en dif
		$cost += $_[$i]{'value'};
	} # end for	
$openprint::log->debug("Total: $cost" );
	return $cost;
} # end sub get_damage

sub arrange_schedule {
	# Before we can calculate the cost, we have to run through the list and determine if there are any lcoked jobs, and if there are, resort to make sure everything fits
	my $time = time;
	for ( my $i = 0; $i < @_; $i += 1 ) {
		if ( $_[$i]{locked} ) {
			if ( $time < $_[$i]{starttime_seconds} ) {
				# all good
			} else {
				# Need to move jobs
				while ( $i and $time >= $_[$i]{starttime_seconds} ) {
					my $before = $_[$i-1];
					$_[$i-1] = $_[$i];
					$_[$i] = $before;
					$time -= $_[$i-1]{runtime_seconds};
					$i -=1;
				} # while
			} # end if
		} # endif locked
		$time += $_[$i]{runtime_seconds};
	} # end for
	return @_;
} # end sub arrange_schedule

# The cost function calculates a value based on the previous and next jobs.  It takes into account due dates, colours, stock, etc.
sub cost {
	my ( $Equipment, $previous, $current, $next ) = @_;

	my $value;

	my $C = new openprint::Project( $$current{'projectindex'} );
	my $c_specs = openprint::service::get_specs_ref( @$current{'projectindex','service_id'} );
	if ( Date::Parse::str2time($C->due_date()) < $current->end() ) {
		$value -= 10;
	} # end if
	if ( ! $$c_specs{'UsePress'} ) {
		$$c_specs{'UsePress'} = $$c_specs{'ddmPress'.$C->ordered_quantity_index()};
	} # end if
	if ( $$c_specs{'UsePress'} eq $Equipment->strid() ) {
		$value += 5;
	} # end if
	if ( $Equipment->id() == $$current{'equipment_id'} ) {
		$value += 1;
	} # end if
	if ( $Equipment->specification('Maximum Impression Quantity') > $$c_specs{'hdnImpressionQuantity'.$C->ordered_quantity_index()} ) {
		$value -= 1;
	} elsif ( $Equipment->specification('Minimum Impression Quantity') < $$c_specs{'hdnImpressionQuantity'.$C->ordered_quantity_index()} ) {
		$value -= 1;
	} else {
		$value += 1;
	} # end if

	my @c_colours = (openprint::print_printing::get_colours( $c_specs, 'SideOne' ), openprint::print_printing::get_colours( $c_specs, 'SideTwo' ));
	if ( $previous ) {
		my $P = new openprint::Project( $$previous{'projectindex'} );

		my $p_specs = openprint::service::get_specs_ref( @$previous{'projectindex','service_id'} );
		my @p_colours = (openprint::print_printing::get_colours( $p_specs, 'SideOne' ), openprint::print_printing::get_colours( $p_specs, 'SideTwo' ));
		$value += sets::intersection( @p_colours, @c_colours );
		if ( $$p_specs{'StockWidth'.$P->ordered_quantity_index()} >= $$c_specs{'StockWidth'.$C->ordered_quantity_index()} ) {
			$value += 1;
		} else {
			$value -= 1;
		} # end if

	} else {
		$value += @c_colours;
		$value += 1; # For stock size;
	} # end if
	
	if ( $next ) {
		my $N = new openprint::Project( $$next{'projectindex'} );
		my $n_specs = openprint::service::get_specs_ref( @$next{'projectindex','service_id'} );
		my @n_colours = (openprint::print_printing::get_colours( $n_specs, 'SideOne' ), openprint::print_printing::get_colours( $n_specs, 'SideTwo' ));
		$value += sets::intersection( @n_colours, @c_colours );
		if ( $$n_specs{'StockWidth'.$N->ordered_quantity_index()} <= $$c_specs{'StockWidth'.$C->ordered_quantity_index()} ) {
			$value += 1;
		} else {
			$value -= 1;
		} # end if
	} else {
		$value += @c_colours;
		$value += 1;
	} # end if

	return $value;
} # end sub cost


sub add {
	my ( $p_id, $s_id ) = @_;
	
	if ( $openprint::config{'AutoPilot'} ) {
		my $job = new openprint::Schedule();
		@$job{'projectindex','service_id'} = @_;
		sort_schedule( $job );
	} else {
		# Set pending
		sql::insert( $openprint::log, $openprint::dbh, 'Schedule',
				'ProjectIndex', $p_id,
				'ServiceIndex',	$s_id,
				);
	} # end if

} # end sub add

sub resize {
	my ( $r, $log, $dbh, $variable, $id, $width ) = @_;
	my ( $service_id ) = $id =~ /service_(\d*)/;
	my ( $placement ) = find( {'field'=>'service_id','operator'=>'=','value'=>$service_id} );
	if ( $placement ) {
		$$placement{'runtime'} = $width*60;
		my @schedule = find( { 'operator'=>'AND', 'fields'=>[
				{'field'=>'starttime','operator'=>'>','value'=>$$placement{'starttime'}},
				{'field'=>'equipment_id','operator'=>'=','value'=>$$placement{'equipment_id'}}
				] },
				{'operator'=>'order', value=>'starttime'},
				);
		apply_sort( $placement, @schedule );		
	} else {
		$openprint::log->error("Unable to find schedule entry for form $service_id");
	} # end if
} # end sub resize 

1;
__END__
