package openprint::employee_performance;
use strict;

require sql;
require openprint::Performance_Point;
require openprint::Performance_Report;

use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

sub setup {
	if ( $param{'function'} eq 'Save' ) {
		foreach my $Type ( openprint::Performance_Point_Type->find() ) {
			foreach my $Equipment ( openprint::Equipment->find(
						useinscheduling=>1,
						( $Type->category() ? ( 'category'=>$Type->category() ) : () ),
						) ) {
				my $Point = openprint::Performance_Point->find_one('equipment_id'=>$$Equipment{'id'},'type_id'=> $$Type{'id'} );
				if ( ! $Point ) {
					next if ! $param{"value-$$Type{id}-$$Equipment{id}"};
					$Point = new openprint::Performance_Point();
					$Point->set({
						'type_id'	=>	$$Type{'id'},
						'equipment_id'	=>	$$Equipment{'id'},
					});
				} # end if
				if ( ! $param{"value-$$Type{id}-$$Equipment{id}"} ) {
					$Point->delete();
				} elsif( 
						( $Point->value() != $param{"value-$$Type{id}-$$Equipment{id}"} ) or 
						( $Point->max_value() != $param{"max_value-$$Type{id}-$$Equipment{id}"} ) or 
						( $Point->units() ne $param{"units-$$Type{id}-$$Equipment{id}"} ) 
					   ) {
					$variable{'error'} .= $Point->save({
							'value'		=>	$param{"value-$$Type{id}-$$Equipment{id}"},
							'max_value'	=>	$param{"max_value-$$Type{id}-$$Equipment{id}"},
							'units'		=>	$param{"units-$$Type{id}-$$Equipment{id}"},
							});
				} # end if
			} # end foreach my $Equipment
		} # end foreach Type
	} # end if
} # end sub setup

sub _type {
	if ( $param{'function'} eq 'remove' ) {
		my $Type = new openprint::Performance_Point_Type( $param{'type_id'} );
		$variable{'error'} .= $Type->delete();
	} # end if
} # end sub _type

sub history {
	if ( $param{'action'} eq 'Save' ) {
		if ( $param{'shift_id'} ) {
			$variable{'Shift'} = new openprint::Shift( $param{'shift_id'} );
			$variable{'Report'} = openprint::Performance_Report->find_one('shift_id'=>$param{'shift_id'});
		} else {
			$variable{'error'} .= 'No shift given!';
			return;
		} # end if
		foreach my $Record ( $variable{'Report'}->Records() ) {
			$Record->save({
				'quantity'	=>	$param{'quantity-'.$$Record{'docket'}.'-'.$$Record{'type_id'}}
			});
		} # end foreach $Record
		%param = ();
	} elsif ( $param{'action'} eq 'Download' ) {
		my @header = ( 'Operator', 'Equipment', 'Shift Start', 'Shift End', 'Shift Name', 'Docket' );
		my @Types = openprint::Performance_Point_Type->find('order'=>'lower(name)');
		push @header, map { $_->name() } @Types;
		push @header, 'Total';
		my @data;
		foreach my $Shift ( openprint::Shift->find( 
					( $session{'/employee/performance/history.html?operator_id'} ? ( 'operator_id'=>$session{'/employee/performance/history.html?operator_id'} ) : () ),
					( $session{'/employee/performance/history.html?equipment_id'} ? ( 'equipment_id in'=>[ split(',',$session{'/employee/performance/history.html?equipment_id'} ) ] ) : () ),
					ssi::date_filter( '/employee/performance/history.html?starttime_start', 'starttime >=' ),
					ssi::date_filter( '/employee/performance/history.html?starttime_end', 'starttime <=' ),
					'starttime <=' => sprintf('%.4d-%.2d-%.2d 23:59:59', Date::Calc::Today() ),
					'order' =>  'starttime',
					) ) {
			my $Report = openprint::Performance_Report->find_one('shift_id'=>$Shift->id());
			next if ! $Report;
			my %Records;
			foreach my $R ( $Report->Records() ) {
				$Records{$R->docket}{$R->type_id()} = $R;
			} # end foreach Record
	
			my $total = 0;
			foreach my $docket ( keys %Records ) {
				
				push @data, $Shift->Operator()->name(), $Shift->Equipment()->name(), $Shift->starttime(), $Shift->endtime(), $Shift->name(), $docket;
	
				foreach my $Point ( @Types ) {
					if ( ! $Records{$docket}{$Point->id()} ) {
#$log->debug("No value for $docket $$Point{name} :" . $Records{$docket}{$Point->id()} );
						push @data, 0;
					} else {
						$total += $Records{$docket}{$Point->id()}->total();
						push @data, $Records{$docket}{$Point->id()}->total();
					}
				} # end foreach Point
			} # end foreach docket
			push @data, $total;

		} # end foreach Shift
		misc::export_csv( $r, $log, \%variable, 'performance_report.csv', \@header, \@data );

	} elsif ( $param{'action'} eq 'Reset' ) {
		foreach ( 
                'starttime_start_year','starttime_start_month','starttime_start_day',
                'starttime_end_year','starttime_end_month','starttime_end_day',
                'category_id', 'equipment_id', 'operator_id', 'unreported' ) {
			delete $session{'/employee/performance/history.html?$_'};
		} # end foreach
	} # end if
    ssi::save_params( '/employee/performance/history.html', (
                'starttime_start_year','starttime_start_month','starttime_start_day',
                'starttime_end_year','starttime_end_month','starttime_end_day',
                'category_id', 'equipment_id', 'operator_id', 'unreported' ) );
    ssi::setup_date_select( '/employee/performance/history.html', 'starttime_start', -7 );
    ssi::setup_date_select( '/employee/performance/history.html', 'starttime_end', '' );
	$session{'/employee/performance/history.html?category'} = 'Printing' if ! $session{'/employee/performance/history.html?category'};

} # end sub history

sub _history {
    ssi::save_params( '/employee/performance/history.html', (
                'starttime_start_year','starttime_start_month','starttime_start_day',
                'starttime_end_year','starttime_end_month','starttime_end_day',
                'category_id', 'equipment_id', 'operator_id' ) );
} # end sub _history

sub edit {
	if ( $param{'shift_id'} ) {
		$variable{'Shift'} = new openprint::Shift( $param{'shift_id'} );
		$variable{'Report'} = openprint::Performance_Report->find_one('shift_id'=>$param{'shift_id'});
	} # end if
	if ( ! $variable{'Report'} ) {
		$variable{'Report'} = new openprint::Performance_Report( $param{'report_id'} );
		$variable{'Shift'} = $variable{'Report'}->Shift() if ! $variable{'Shift'};
	} # end if
} # end sub edit

sub _docket_records {
	if ( $param{'shift_id'} ) {
		$variable{'Shift'} = new openprint::Shift( $param{'shift_id'} );
		$variable{'Report'} = openprint::Performance_Report->find_one('shift_id'=>$param{'shift_id'});
	} # end if
	if ( ! $variable{'Report'} ) {
		$variable{'Report'} = new openprint::Performance_Report( $param{'report_id'} );
		$variable{'Shift'} = $variable{'Report'}->Shift() if ! $variable{'Shift'};
	} # end if
	if ( ! $variable{'Report'}->id() ) {
		$variable{'error'} .= $variable{'Report'}->save({
				'shift_id'=>$param{'shift_id'},
				'operator_id'=>$param{'operator_id'} ? $param{'operator_id'} : $variable{'Shift'}->operator_id()
				});
	} # end if
	
	if ( $variable{'Report'}->id() and $param{'docket'} ) {
		if ( openprint::Performance_Record->find_one('report_id'=>$variable{'Report'}->id(), 'docket'=>$param{'docket'}) ) {
			$variable{'error'} .= 'Docket ' . $param{'docket'} . ' is already recorded for this shift.';
			return;
		} # end if
		$variable{'docket'} = $param{'docket'};
        my @Points = openprint::Performance_Point->find( 'equipment_id'=>$variable{'Shift'}->equipment_id() );

		foreach my $Point ( @Points ) {
			$variable{'error'} .= new openprint::Performance_Record()->save({
				'report_id'	=>	$variable{'Report'}->id(),
				'docket'	=>	$variable{'docket'},
				'type_id'	=>	$Point->type_id(),
			});
		} # end foreach Type
	
	} # end if
} # end sub _docket_records

1;
__END__
