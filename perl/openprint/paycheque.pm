package openprint::paycheque;

use strict;
use openprint;
use vars qw( $r %variable %session %param %config $log $dbh );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

require openprint::Paycheque;
require openprint::Invoice;

sub history {
	if ( $param{'btnFunction'} eq 'Destroy' ) {
		my $Paycheque = new openprint::Paycheque( $param{'paycheque_id'} );
		$variable{'error'} .= $Paycheque->destroy();
	
	} elsif ( $param{'btnFunction'} eq 'Export' ) {
		my @Header = ( 'ID', 'When', 'Employee', 'Amount' );
		my @Data;
		foreach my $Paycheque ( openprint::Paycheque->find( 
			ssi::date_filter( 'paid_on_start', 'paid_on >=', \%param ),
			ssi::date_filter( 'paid_on_end', 'paid_on <=', \%param ),
			employer_id       => $param{'employer_id'},
			employee_id       => $param{'employee_id'},
			order             => 'paid_on',
			) ) {
			push @Data, ( $Paycheque->id(), 
					Date::Format::time2str( $config{'DateFormat'}, Date::Parse::str2time( $Paycheque->paid_on() ) ),
					$Paycheque->Employee()->name(),
					$Paycheque->total()
					);
		} # end foreach Paycheque
		misc::export_csv( $r, $log, \%variable, 'Paycheques.csv', \@Header, \@Data );
	} else {
		ssi::setup_date_select( '/paycheque/history.html', 'paid_on_start', -31 );
		ssi::setup_date_select( '/paycheque/history.html', 'paid_on_end', 0 );
		_history();
	} # end if
} # end sub history

sub _history {
	ssi::save_params( '/paycheque/history.html', 'paid_on_start_year','paid_on_start_month','paid_on_start_day','paid_on_end_year','paid_on_end_month','paid_on_end_day', 'employer_id','employee_id' );
} # end sub _history

sub edit {
	my $Paycheque = $variable{'Paycheque'} = new openprint::Paycheque( $param{'paycheque_id'} );
	if ( $param{'btnFunction'} eq 'Save' ) {
		$param{'paid_on'} = sprintf('%.4d-%.2d-%.2d', @param{'paid_on_year','paid_on_month','paid_on_day'} );
		$variable{'error'} .= $Paycheque->save(\%param);
		if ( ! $variable{'error'} ) {
			$variable{'ExternalRedirect'} = '/paycheque/history.html';
		} # end if
	} elsif ( $param{'btnFunction'} eq 'Destroy' ) {
		$variable{'error'} .= $Paycheque->destroy();
		if ( ! $variable{'error'} ) {
			$variable{'ExternalRedirect'} = '/paycheque/history.html';
		} # end if
	} # end if
} # end sub edit

sub _paid {
	my $Paycheque = $variable{'Paycheque'} = new openprint::Paycheque( $param{'paycheque_id'} );
	if ( $param{'timetrack_id'} ) {
		my $Timetrack = openprint::Paycheque_Timetrack->find_one('timetrack_id'=> $param{'timetrack_id'}, 'paycheque_id'=>$param{'paycheque_id'} );
		$variable{'error'} .= (new openprint::Paycheque_Timetrack())->save({'timetrack_id'=> $param{'timetrack_id'}, 'paycheque_id'=>$param{'paycheque_id'}}) if ! $Timetrack;
	} # end if
} # end sub _paid

sub _unpaid {
	my $Paycheque = $variable{'Paycheque'} = new openprint::Paycheque( $param{'paycheque_id'} );
	if ( $param{'timetrack_id'} ) {
		my $Timetrack = openprint::Paycheque_Timetrack->find_one('timetrack_id'=> $param{'timetrack_id'}, 'paycheque_id'=>$param{'paycheque_id'} );
		$variable{'error'} .= $Timetrack->delete() if $Timetrack;
	} # end if
	$variable{'Paycheque'} = $Paycheque;
} # end sub _paid

 1;
__END__
