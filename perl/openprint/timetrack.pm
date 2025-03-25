use strict;
package openprint::timetrack;

use openprint ();
use vars qw( $r %variable %session %param %config $log $dbh );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

require Date::Format;
require openprint::Timetrack;
require openprint::Currency;
require ssi;
require DateTime::Format::Pg;
require DateTime::TimeZone;

sub history {
	if ( $param{func} eq 'Destroy' ) {
		my $Timetrack = new openprint::Timetrack( $param{timetrack_id} );
		$variable{error} .= $Timetrack->destroy();
	} elsif ( $param{func} eq 'Download' ) {
    
		ssi::save_params( $r->uri(), ( 'starting_start_year','starting_start_month','starting_start_day','starting_end_year','starting_end_month','starting_end_day','invoiced','paid','user_id','company_id', 'service_id', 'billable') );
        my @header = ('Who', 'Company', 'Start', 'End', 'Duration', 'Service', 'Description', 'Rate', 'Price');
        my @data;
        my ( $total_hours, $total_value );
        foreach my $Timetrack ( openprint::Timetrack->find(
					ssi::date_filter( $r->uri().'?starting_start', 'starting >=' ),
					ssi::date_filter( $r->uri().'?starting_end', 'starting <=' ),
					( sets::isin( $session{user_type}, ['E', 'A'] ) ?
					  ( $session{$r->uri().'?company_id'} ? ( company_id => $session{$r->uri().'?company_id'} ) : () ) :
					  ( company_id  => $session{company_id} ) ),
					( $session{$r->uri().'?user_id'} ? ( user_id => $session{$r->uri().'?user_id'} ) : () ),
					( $session{$r->uri().'?service_id'} ? ( service_id   => $session{$r->uri().'?service_id'} ) : () ),
					( $session{$r->uri().'?billable'} ? ( billable => $session{$r->uri().'?billable'} ) : () ),
          ( $session{$r->uri().'?contains'} ? ( 'description ilike' => $session{$r->uri().'?contains'} ) : () ),
					order             => 'starting',
					) ) {
			next if $Timetrack->paid() and ! sets::isin( 1, split(',', $session{'/timetrack/history.html?paid'} ) );
			next if ( ! $Timetrack->paid() ) and ! sets::isin( 0, split(',', $session{'/timetrack/history.html?paid'} ) );
			next if $Timetrack->invoiced() and ! sets::isin( 1, split(',', $session{'/timetrack/history.html?invoiced'} ) );
			next if ( ! $Timetrack->invoiced() ) and ! sets::isin( 0, split(',', $session{'/timetrack/history.html?invoiced'} ) );

			push @data, ( $Timetrack->User()->name(), $Timetrack->Company()->name(), 
					Date::Format::time2str(($Timetrack->time_associated() ? $config{DateTimeFormat} : $config{DateFormat}), Date::Parse::str2time( $Timetrack->starting() ) ),
					Date::Format::time2str(($Timetrack->time_associated() ? $config{DateTimeFormat} : $config{DateFormat}), Date::Parse::str2time( $Timetrack->ending() ) ),
					misc::seconds_to_pretty_interval( $Timetrack->elapsed() ),
					$Timetrack->Service()->name(),
					$Timetrack->description(),
					join('',$Timetrack->get('rate','units' ) ),
					openprint::Currency::format( $Timetrack->value() ),
					);
			$total_hours += $Timetrack->elapsed();
			$total_value += $Timetrack->value();
		} # end foreach Timetrack
		push @data, '','','','Totals:',misc::seconds_to_pretty_interval($total_hours),'','','',openprint::Currency::format($total_value);
		misc::export_csv( $r, $log, \%variable, 'timetracks.csv', \@header, \@data );

	} elsif ( $param{func} eq 'reset' ) {
		foreach ( 'starting_start_year','starting_start_month','starting_start_day','starting_end_year','starting_end_month','starting_end_day','invoiced','paid','user_id','company_id', 'service_id', 'lastupdated', 'billable' ) {
			delete $session{'/timetrack/history.html?'.$_}
		} # end foreach
	} # end if

	_history();
	if ( ( ! $session{'/timetrack/history.html?lastupdated'} ) or ( time - $session{'/timetrack/history.html?lastupdated'} ) > ( 12*60*60 ) ) {
		ssi::setup_date_select( '/timetrack/history.html', 'starting_start', -31 );
		ssi::setup_date_select( '/timetrack/history.html', 'starting_end', '' );
	} # end if

	$session{'/timetrack/history.html?invoiced'} = '0' if ! $session{'/timetrack/history.html?invoiced'};
	$session{'/timetrack/history.html?paid'} = '0' if ! $session{'/timetrack/history.html?paid'};
	if ( sets::isin( $session{user_type}, ['A','E'] ) ) {
		$session{'/timetrack/history.html?user_id'} = $session{user_id} if ! exists $session{'/timetrack/history.html?user_id'};
	} # end if
} # end sub history

sub _history {
	if ( ! $param{func} ) {
		ssi::save_params( '/timetrack/history.html', ( 'starting_start_year','starting_start_month','starting_start_day','starting_end_year','starting_end_month','starting_end_day','invoiced','paid','user_id','company_id', 'service_id', 'billable','travel_associated','contains', 'keywords' ) );
	} else {
		if ( $param{func} eq 'merge' ) {
			my $start = undef;
			my $end = undef;
			my $desc = '';
			my $NewTimetrack;
      my @Src_Timetracks = openprint::Timetrack->find(id=>ref $param{timetrack_id} eq 'ARRAY' ? $param{timetrack_id} : [ split(',', $param{timetrack_id}) ] );
			foreach my $Timetrack ( @Src_Timetracks ) {
				next if ! $Timetrack->can_edit();
				if ( ! $NewTimetrack ) {
					$NewTimetrack = $Timetrack->copy();
				} else {
					if ( $NewTimetrack->company_id() != $Timetrack->company_id() ) {
						$variable{error} .= "Timetracks must be from same company.";
						return;
					}
					if ( $NewTimetrack->user_id() != $Timetrack->user_id() ) {
						$variable{error} .= "Timetracks must be from same user.";
						return;
					}
				}
				if ( (!$start) or $Timetrack->starting_dt() < $start ) {
					$start = $Timetrack->starting_dt();
				}
				if ( (!$end) or $Timetrack->ending_dt() > $end ) {
					$end = $Timetrack->ending_dt();
				}
				$desc .= $Timetrack->starting_dt() . ' to ' . $Timetrack->ending_dt() . ': ' . $Timetrack->description() . '<br/>';
			} # end foreach Source Timetrack
			if ( $NewTimetrack ) {
        
				$variable{error} .= $NewTimetrack->save({ starting_dt=>$start, ending_dt=>$end, description=>$desc });
        if ( ! $variable{error} ) {
          foreach my $T ( @Src_Timetracks ) {
            next if ! $T->can_edit();
            $T->delete();
          }
        }
			}
		} elsif ( $param{func} eq 'delete' ) {
			foreach my $Timetrack ( openprint::Timetrack->find(id=>ref $param{timetrack_id} eq 'ARRAY' ? $param{timetrack_id} : [ split(',', $param{timetrack_id}) ] ) ) {
				next if ! $Timetrack->can_edit();
				$variable{error} .= $Timetrack->delete();
			}
		}
	} # end if
} # end sub _history

sub view {
	my $Timetrack = $variable{Timetrack} = new openprint::Timetrack( $param{timetrack_id} );
	if ( $param{func} eq 'Destroy' ) {
		$variable{error} .= $Timetrack->destroy();
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/timetrack/history.html';
			return;
    }
  }
}

sub edit {
	my $Timetrack = $variable{Timetrack} = new openprint::Timetrack( $param{timetrack_id} );
	if ( $param{func} eq 'Save' ) {
		$param{owner_id} = $session{company_id} if ! $param{owner_id};

    my $start_datetime = DateTime->new( time_zone => $openprint::TZ,
        ( map { $_ => int($param{'starting_'.$_ }) } ( 'year', 'month', 'day', 'hour','minute' ) ),
        );

    my $end_datetime = DateTime->new( time_zone => $openprint::TZ,
        ( map { $_ => int($param{'ending_'.$_ }) } ( 'year', 'month', 'day', 'hour','minute' ) ),
        );

    if ( $start_datetime > $end_datetime ) {
      $variable{error} .= 'Invalid end time. The end of the shift must occur after the start of the shift.  No changes made.<br/>';
      return;
    } # end if

    my $parser = 'DateTime::Format::Pg';

		$param{starting} = $parser->format_datetime( $start_datetime );
		$param{ending} = $parser->format_datetime( $end_datetime );
		if ( ! $param{timetrack_id} ) {
			if ( openprint::Timetrack->find_one(
						user_id	  	=>  ( $param{user_id} ? $param{user_id} : undef ),
						owner_id  	=>  $param{owner_id},
						company_id	=>  $param{company_id},
						starting  	=>  $param{starting},
						ending		  =>  $param{ending},
						service_id	=>  ( $param{service_id} ? $param{service_id} : undef ),
						description	=>	$param{description},
						) ) {
				$variable{error} = 'Not creating duplicate.<br/>';
				return;
			} # end if
		} # end if
		$variable{error} .= $Timetrack->save(\%param);
		if ( ! $variable{error} ) {

			# Keywords won't get saved when creating a timetrack, so have to save them manually
			$Timetrack->keywords( $param{keywords} ) if ! $param{timetrack_id};
			if ( $param{referrer_invoice_id} ) {
				$_ = $param{referrer_invoice_id};
				$variable{ExternalRedirect} = '/invoice/edit.html?invoice_id='.$_;
				%param = ();
				return;
			} else {
				ssi::save_params( '/timetrack/edit.html', 'ending', 'company_id' );
				$variable{ExternalRedirect} = '/timetrack/history.html';
				return;
			} # end if
		} # end if
	} elsif ( $param{func} eq 'Copy' ) {
		$variable{Timetrack} = $variable{Timetrack}->copy();
	} elsif ( $param{func} eq 'Destroy' ) {
		$variable{error} .= $Timetrack->destroy();
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/timetrack/history.html';
			return;
		}
	} else {
    if ( (!$variable{Timetrack}->id()) ) {
      $variable{Timetrack}->set(\%param); # Sets defaults
      $variable{Timetrack}->user_id( $session{user_id} ) if ! $variable{Timetrack}->user_id();
      if ( time - $session{'/timetrack/edit.html?lastupdated'} < ( 12*60*60 ) ) {
        $variable{Timetrack}->company_id( $session{'/timetrack/edit.html?company_id'} ) if ! $variable{Timetrack}->company_id();
        $variable{Timetrack}->starting( $session{'/timetrack/edit.html?ending'} ) if ! $variable{Timetrack}->starting();
        $variable{Timetrack}->ending( $session{'/timetrack/edit.html?ending'} ) if ! $variable{Timetrack}->ending();
      } # end if
    } # end if
	} # end if
} # end sub edit

sub _currency {
}

1;
__END__
