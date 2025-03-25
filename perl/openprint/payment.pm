package openprint::payment;

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

require openprint::Payment;
require openprint::Invoice;
require openprint::Invoice_Payment;
require openprint::Expense_Account;

sub history {
	if ( $param{btnFunction} ) {
		if ( $param{btnFunction} eq 'Delete' ) {
			my $Payment = new openprint::Payment( $param{payment_id} );
			$variable{error} .= $Payment->delete();
		} elsif ( $param{btnFunction} eq 'UnDelete' ) {
			my $Payment = new openprint::Payment( $param{payment_id} );
			$variable{error} .= $Payment->undelete();
		} elsif ( $param{btnFunction} eq 'Destroy' ) {
			my $Payment = new openprint::Payment( $param{payment_id} );
			$variable{error} .= $Payment->destroy();
		} elsif ( $param{btnFunction} eq 'Send Receipt' ) {
			my $Payment = new openprint::Payment( $param{payment_id} );
			$variable{error} .= $Payment->send_receipt();
		} elsif ( $param{btnFunction} eq 'Send Receipt To Me' ) {
			my $Payment = new openprint::Payment( $param{payment_id} );
			$variable{error} .= $Payment->send_receipt( $openprint::User );
		} else {
			$log->error("Unknonwn function in payment_history $param{btnFunction}");
		}
	} else {
		_history();
		ssi::setup_date_select( '/payment/history.html', 'received_on_start', -31 );
		ssi::setup_date_select( '/payment/history.html', 'received_on_end', '' );
		ssi::setup_date_select( '/payment/history.html', 'entered_on_start', -31 );
		ssi::setup_date_select( '/payment/history.html', 'entered_on_end', '' );
	} # end if
} # end sub history

sub _history {
	ssi::save_params('/payment/history.html',  
		( map { 'received_on_start_'.$_ } ( 'year','month','day' ) ),
		( map { 'received_on_end_'.$_ } ( 'year','month','day' ) ),
		( map { 'entered_on_start_'.$_ } ( 'year','month','day' ) ),
		( map { 'entered_on_end_'.$_ } ( 'year','month','day' ) ),
		'payor_id', 'recipient_id', 'transaction_id' );
} # end sub _history

sub edit {
	$param{payment_id} = openprint::Payment->transform(id=>$param{payment_id});
	my $Payment = $variable{Payment} = new openprint::Payment( $param{payment_id} );
	if ( $param{btnFunction} eq 'Save' ) {
		$param{recipient_id} = $session{company_id} if ! $param{recipient_id};
		if ( ! Date::Calc::check_date( @param{'received_on_year','received_on_month','received_on_day'} ) ) {
			$variable{error} .= 'Invalid received on date.<br/>';
      return;
    }
    $param{received_on} = sprintf('%.4d-%.2d-%.2d', @param{'received_on_year','received_on_month','received_on_day'} );
    my @changes = $Payment->changes(\%param);
    $openprint::log->debug("@changes");
    if ( @changes ) {
			$variable{error} .= $Payment->save(\%param);
      if ( !$variable{error} ) {
        (new openprint::Log())->save({Object=>$Payment, action=>'Edit', note=>join('<br/>', @changes)});
        if ( $param{payment_id} ) {
          $variable{ExternalRedirect} = '/payment/history.html';
        } else {
          $variable{ExternalRedirect} = '/payment/edit.html?payment_id='.$Payment->id();
        } # end if
			} # end if
    } else {
      $variable{information} .= 'No changes....<br/>';
		} # end if
	} elsif ( $param{btnFunction} eq 'Send Receipt' ) {
		$variable{error} .= $Payment->send_receipt();
	} elsif ( $param{btnFunction} eq 'Send Receipt To Me' ) {
		$variable{error} .= $Payment->send_receipt( $openprint::User );
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		$variable{error} .= $Payment->delete();
		$variable{ExternalRedirect} = '/payment/history.html' if ! $variable{error};
	} elsif ( $param{btnFunction} eq 'UnDelete' ) {
		$variable{error} .= $Payment->undelete();
		$variable{ExternalRedirect} = '/payment/history.html' if ! $variable{error};
	} # end if
} # end sub edit

sub _paid {
	$param{payment_id} = openprint::Payment->transform(id=>$param{payment_id});
	my $Payment = $variable{Payment} = new openprint::Payment( $param{payment_id} );
	if ( ! $$Payment{id} ) {
		$variable{error} .= "Payment $param{payment_id} not found.<br/>";
		return;
	} # end if
	if ( $param{invoice_id} ) {
		my $Invoice = new openprint::Invoice( $param{invoice_id} );
		if ( ! $$Invoice{id} ) {
			$variable{error} .= "Payment $param{payment_id} not found.<br/>";
			return;
		} # end if
		$variable{error} .= $Invoice->add_Payment( $Payment );
	} # end if
} # end sub _paid

sub _unpaid {
	$param{payment_id} = openprint::Payment->transform(id=>$param{payment_id});
	my $Payment = new openprint::Payment( $param{payment_id} );
	if ( $param{invoice_id} ) {
		my $Invoice = new openprint::Invoice( $param{invoice_id} );
		$Invoice->del_Payment( $Payment );
	} # end if
  foreach my $k ( 'recipient_id', 'payor_id' ) {
    if ( $param{$k} ) {
      $$Payment{$k} = $param{$k};
    }
  }
	$variable{Payment} = $Payment;
} # end sub _paid

sub make {
	$param{order_id} = $param{OrderID} if $param{OrderID};
	$variable{Order} = new openprint::Order( $param{order_id} );

	$variable{Payment} = new openprint::Payment( $param{payment_id} );
	
	$variable{Payment}->set( \%param );
	$variable{Payment}->amount( $variable{Order}->balance() ) if ! $variable{Payment}->amount();

	if ( $param{btnFunction} eq 'SetExpressCheckOut' ) {
		# Express CheckOut takes an Order
		my $Order = new openprint::Order( $param{order_id} );
		require PayPal;
		my $PayPal = PayPal->new('api_USER'=>$config{'PayPal_API_Username'},'api_PWD'=>$config{'PayPal_API_Password'},'api_SIGNATURE'=>$config{'PayPal_API_Signature'} );

		my $result = $PayPal->Call_Service({
					METHOD			=>	'SetExpressCheckout',
					PAYMENTACTION	=>	'Sale',
					CURRENCYCODE	=>	openprint::Currency::get_current()->short(),
					AMT				=>	$Order->balance(),
					RETURNURL		=>	$config{ExternalSiteURL}.'/payment/make.html?btnFunction=DoExpressCheckOut&order_id='.$Order->id(),
					CANCELURL		=>	$config{ExternalSiteURL}.'/payment/make.html?btnFunction=CancelExpressCheckOut&order_id='.$Order->id(),
					});
		if ($$result{ack} ne 'Success') {
			$variable{error} .= 'Api call failed:<br/>';
			foreach my $error ( $PayPal->Parse_Errors($result) ) {
				$variable{error} .= "$$error{errorcode} $$error{longmessage}<br/>";
			} # end foreach error
		} else {
			foreach my $k ( keys %$result ) {
				$log->debug("Results: $k => $$result{$k}");
			}
			$session{PayPal_token} = $$result{token};	
			$session{PayPal_correlationid} = $$result{correlationid};
			$variable{ExternalRedirect} = $PayPal::url.$$result{token};
			return;
		} # end if
	} elsif ( $param{btnFunction} eq 'DoExpressCheckOut' ) {
		my $Order = new openprint::Order( $param{order_id} );
		require PayPal;
		my $PayPal=PayPal->new('api_USER'=>$config{'PayPal_API_Username'},'api_PWD'=>$config{'PayPal_API_Password'},'api_SIGNATURE'=>$config{'PayPal_API_Signature'} );
		my $result = $PayPal->Call_Service({
				METHOD			=>	'DoExpressCheckout',
				PAYMENTACTION	=>	'Sale',
				CURRENCYCODE	=>	openprint::Currency::get_current()->short(),
				AMT				=>	$Order->balance(),
				PAYERID			=>	$param{PayPal_PayerID},
				TOKEN			=>	$session{PayPal_token},
				});
		if ($$result{ack} ne 'Success') {
			$variable{error} .= 'Api call failed:<br/>';
			foreach my $error ( $PayPal->Parse_Errors($result) ) {
				$variable{error} .= "$$error{errorcode} $$error{longmessage}<br/>";
			} # end foreach error
		} else {
			foreach my $k ( keys %$result ) {
				$log->debug("Results: $k => $$result{$k}");
			}
			my $Payment = new openprint::Payment();
			$variable{error} .= $Payment->save({
					'order_id'		=>	$Order->id(),
					'recipient_id'	=>	$config{owner_id},
					'payor_id'		=>	$session{company_id},
					'amount'		=>	$Order->balance(),
					'method'		=>	'PayPal',
					'transaction_id'	=>	$session{PayPal_correlationid},
					'memo'			=>	'',
					'completed'		=>	1,
					'currency_id'	=>	openprint::Currency::get_current()->id(),
					}); 
			delete $session{PayPal_token};
			delete $session{PayPal_PayerID};
			delete $session{PayPal_correlationid};
			$variable{information} .= 'Payment was received.';
			$variable{Redirect} = '/main/order/history_details.html';
		} # end if
		return;
	} elsif ( $param{btnFunction} eq 'CancelExpressCheckOut' ) {
		delete $session{payment_id};
		delete $session{PayPal_token};
		delete $session{PayPal_PayerID};
		delete $session{PayPal_correlationid};
		$variable{information} .= 'Payment was cancelled.';
		$variable{Redirect} = '/main/order/history_details.html';
		return;
	} elsif ( $param{btnFunction} eq 'Submit' ) {
		if ( $variable{Payment}->Type()->name() eq 'PayPal' ) {
			require PayPal;

			my $Paypal=PayPal->new('api_USER'=>$config{'PayPal_API_Username'},'api_PWD'=>$config{'PayPal_API_Password'},'api_SIGNATURE'=>$config{'PayPal_API_Signature'} );

			my $result = $Paypal->Call_Service({
					#METHOD=>'GetBalance',
					METHOD			=>	'SetExpressCheckout',
					PAYMENTACTION	=>	'Sale',
					AMT				=>	$param{amount},
					#COUTNRYCODE=>'CA',

					#creditcardtype=>$param{cc_type},
					#firstname=>$param{firstname},
					#lastname=>$param{lastname},
					#street=>$param{address1},
					#city=>$param{city},
					#state=>$param{state},
					#zip=>$param{postalcode},
					#country=>$param{country},
					RETURNURL=>$config{ExternalSiteURL}.'/payment/make.html',
					CANCELURL=>$config{ExternalSiteURL}.'/payment/make.html',
					});

			if ($$result{ack} eq 'Success') {
				$variable{information} = 'Api call successfull<br/>';
			} else {
				$variable{error} .= 'Api call failed:<br/>';
				foreach my $error ( $Paypal->Parse_Errors($result) ) {
					$variable{error} .= "$$error{errorcode} $$error{longmessage}<br/>";
				} # end foreach error
			} # end if
		} # end if PaymentProcessor == Paypal
	} elsif ( $param{btnFunction} eq '' ) {
	} else {
		$log->error("Unknown btnFunction in payment::make : $param{btnFunction}");
	} # end if btnFunction
} # end sub make

sub _edit_payment {
	if ( $param{action} eq 'update' ) {
		my $IP = $variable{Invoice_Payment} = new openprint::Invoice_Payment($param{id});
		$IP->save({$param{field}=>$param{value}}) if $IP->id();
	} # end if
} # end sub_edit_payment

 1;
__END__
