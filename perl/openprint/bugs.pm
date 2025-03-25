use strict;
package openprint::bugs;

use openprint ();
use vars qw( $r %variable %session %param %config $log $dbh );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

require openprint::Bug;

sub history {
	if ( $param{'btnFunction'} eq 'Save' ) {
		$param{'owner_id'} = $session{'company_id'} if ! $param{'owner_id'};
		$param{'starting'} = sprintf('%.4d-%.2d-%.2d %.2d:%.2d:00', @param{'starting_year','starting_month','starting_day','starting_hour','starting_minute'} );
		$param{'ending'} = sprintf('%.4d-%.2d-%.2d %.2d:%.2d:00', @param{'ending_year','ending_month','ending_day','ending_hour','ending_minute'} );
		if ( ! $param{'bug_id'} ) {
			if ( openprint::Bug->find_one('owner_id'=>$param{'owner_id'},'company_id'=>$param{'company_id'},'starting'=>$param{'starting'},'ending'=>$param{'ending'},'service_id'=>$param{'service_id'}) ) {
				$variable{'error'} = 'Not creating duplicate.<br/>';
				return;
			} # end if
		} # end if
		my $Bug = new openprint::Bug( $param{'bug_id'} );
		$variable{'error'} .= $Bug->save(\%param);
		if ( $param{'referrer_invoice_id'} ) {
			$_ = $param{'referrer_invoice_id'};
			%param = ();
			$param{'invoice_id'} = $_;
			$variable{'Redirect'} = '/invoice/edit.html';
		} else {
			ssi::save_params( '/bug/edit.html', 'ending', 'company_id' );
		} # end if
	} elsif ( $param{'btnFunction'} eq 'Destroy' ) {
		my $Bug = new openprint::Bug( $param{'bug_id'} );
		$variable{'error'} .= $Bug->destroy();
	} elsif ( ! $param{'btnFunction'} ) {
		ssi::save_params( '/bug/history.html', ( 'starting_start_year','starting_start_month','starting_start_day','starting_end_year','starting_end_month','starting_end_day','invoiced','paid','user_id','company_id') );
	} # end if

	if ( ( ! $session{'/bug/history.html?lastupdated'} ) or ( time - $session{'/bug/history.html?lastupdated'} ) > ( 12*60*60 ) ) {
		ssi::setup_date_select( '/bug/history.html', 'starting_start', -31 );
		ssi::setup_date_select( '/bug/history.html', 'starting_end', '' );
	} # end if

	$session{'/bug/history.html?invoiced'} = '0' if ! $session{'/bug/history.html?invoiced'};
	$session{'/bug/history.html?paid'} = '0' if ! $session{'/bug/history.html?paid'};
	$session{'/bug/history.html?user_id'} = $session{'user_id'} if ! exists $session{'/bug/history.html?user_id'};
} # end sub history

sub _history {
	if ( ! $param{'btnFunction'} ) {
		ssi::save_params( '/bug/history.html', ( 'starting_start_year','starting_start_month','starting_start_day','starting_end_year','starting_end_month','starting_end_day','invoiced','paid','user_id','company_id') );
	} # end if
} # end sub _history

sub edit {
	$variable{'Bug'} = new openprint::Bug( $param{'bug_id'} );
	if ( $param{'btnFunction'} eq 'Save' ) {
		$variable{'error'} .= $variable{'Bug'}->save(\%param);
		$variable{'Redirect'} = '/bug/history.html';
	} elsif ( $param{'btnFunction'} eq 'Copy' ) {
		$variable{'Bug'} = $variable{'Bug'}->copy();
		$variable{'error'} .= $variable{'Bug'}->save();
	} # end if
	if ( time - $session{'/bug/edit.html?lastupdated'} < ( 12*60*60 ) ) {
		$variable{'Bug'}->company_id( $session{'/bug/edit.html?company_id'} ) if ! $variable{'Bug'}->company_id();
		$variable{'Bug'}->starting( $session{'/bug/edit.html?ending'} ) if ! $variable{'Bug'}->starting();
		$variable{'Bug'}->ending( $session{'/bug/edit.html?ending'} ) if ! $variable{'Bug'}->ending();
	} # end if
} # end sub edit

sub view {
	$variable{'Bug'} = new openprint::Bug( $param{'bug_id'} );
} # end sub view

1;
__END__
