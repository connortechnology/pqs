package openprint::employee_order;
use strict;

require openprint::Order;
require openprint::order;
require openprint::Payment;

use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

sub view {

	my $order_id = $openprint::param{'order_id'};
	my $Order = new openprint::Order( $order_id );

	if ( $openprint::param{'btnFunction'} eq 'Pay' ) {
		$Order->pay();
	} elsif ( $openprint::param{'btnFunction'} eq 'Save Payment' ) {

		if ( ( ! $openprint::param{'Amount'} ) or $openprint::param{'Amount'} =~ /[^-\$\d\.]/ ) {
			return misc::error( $log, $dbh, \%variable, 'Invalid Amount', 'Please enter a valid monetary amount.' );
		} # end if

		my $Payment = new openprint::Payment();
		my $error = $Payment->save({
				'order_id'		=> $order_id,
				'company_id'	=> $Order->company_id(),
				'amount'		=> $openprint::param{'Amount'},
				'method'		=> 'Manual',
				'currency_id'	=> $Order->currency_id(),
				'description'	=> $openprint::param{'Description'},
				'completed'		=> 1,
				} );
		if ( $error ) {
			return misc::error( $log, $dbh, \%variable, 'Error Saving Payment', $error );
		} # end if

		openprint::order::get_misc( \%variable, $Order );

		if ( $variable{'DepositDue'} > 0 ) {
			foreach my $Project ( $Order->Projects() ) {
				$Project->status('Pending Deposit');
			} # end foreach Project
		} else {
			$Order->status('In Production') if $Order->status() eq 'Pending Deposit';
			foreach my $Project ( $Order->Projects() ) {
				$Project->status('In Production');
			} # end foreach Project

			if ( $variable{'AmountPaid'} >= $variable{'TOTAL'} ) {
				$Order->status('Paid') if $Order->status() eq 'Complete';
			} # end if
			$Order->save();
		} # end if
	} elsif ( $openprint::param{'btnFunction'} eq 'Delete Payment' ) {
		my $payment_index = $openprint::param{'payment_id'};
		$payment_index =~ s/\D//g;
		if ( $payment_index ) {
			sql::execute( $log, $dbh, 'DELETE FROM Payments WHERE id=?', $payment_index );
		} # end if
		$Order->update_status();
	} elsif ( $openprint::param{'btnFunction'} eq 'Cancel' ) {
		$variable{error} .= $Order->cancel();
	} # end if
	$variable{Order} = $Order;
	openprint::order::display_order( $order_id );
} # end sub view

1;
__END__
