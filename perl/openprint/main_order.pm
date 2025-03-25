use strict;
use warnings;
package openprint::main_order;

require Email::Valid;
use Date::Calc qw(Add_Delta_Days check_date);

use openprint ();
use vars qw( $r %config %param %variable $log $dbh %session );
*variable = \%openprint::variable;
*session = \%openprint::session;
*config = \%openprint::config;
*param = \%openprint::param;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

use constant DEBUG => 0;

require sql;
require openprint::Currency;
require openprint::service;
require openprint::Order;
require openprint::order;
require openprint::OrderedProduct;
require openprint::OrderedProject;
require openprint::press_schedule;
require openprint::Payment;
require openprint::Tax;

sub information {

	my $error;
	my $order_id = $param{order_id};
	# Order creation can happen here as well, because we are doing away with quantity_select
	# order_id may also be the word New

	if ( $order_id and $param{action} and ($param{action} eq 'remove') ) {
		if ( $param{project_id} ) {
			$param{project_id} =~ s/\D//g;
			my $OrderedProject = openprint::OrderedProject->find_one(project_id=>$param{project_id}, order_id=>$order_id);
			if ( ! $OrderedProject ) {
				$variable{error} .= "Project $param{project_id} is not in order $order_id<br/>";
			} elsif ( $OrderedProject->order_id() != $order_id or $OrderedProject->project_id() != $param{project_id} ) {
				$openprint::log->error('Wrong OrderedProject returned!');
			} else {
				$variable{error} .= $OrderedProject->delete();
			} # end if
			$variable{ExternalRedirect} = '/main/order/information.html?order_id='.$order_id;
		} elsif ( $param{product_id} ) {
			$param{product_id} =~ s/\D//g;
			my $OrderedProduct = openprint::OrderedProduct->find_one( id=>$param{product_id}, order_id=>$order_id );
			if ( ! $OrderedProduct ) {
				$variable{error} .= "Product $param{product_id} is not in order $order_id<br/>";
			} elsif ( $OrderedProduct->order_id() != $order_id or $OrderedProduct->id() != $param{product_id} ) {
				$openprint::log->error('Wrong OrderedProduct returned!');
			} else {
				$variable{error} .= $OrderedProduct->delete();
			} # end if
			$variable{ExternalRedirect} = '/main/order/information.html?order_id='.$order_id;
		} else {
			$openprint::log->error('Nothing specified to delete');
			$variable{error} .= 'Nothing specified to delete.';
		} # end if
	} elsif ( $param{btnFunction} ) {
		if ( $param{btnFunction} eq 'New Order' ) {
			# Re order situation

			my $SRC_Order = new openprint::Order( $order_id );
			return 0 if check_credit( $SRC_Order->total() );

			if ( $SRC_Order->status() eq '' ) {
				misc::error( $log, $dbh, \%variable, 'Can\'t re-order.', 'Order does not exist.' );
				return 0;
			} elsif ( ! sets::isin( $SRC_Order->status(), 'Complete', 'Paid',	'Shipped', 'Waiting For Pickup', 'Picked Up' ) ) {
				misc::error( $log, $dbh, \%variable, 'Can\'t re-order.', 'The given order is not complete.' );
				return 0;
			} 

			my $ac = sql::start_transaction( $openprint::dbh );
			# this goes before get_order_id so that we re-use orderids
			delete_unfinished_orders();

			# get the contents
			my @contents = sql::execute($log, $dbh, q{SELECT lngProjectIndex, intQuantityIndex FROM Order_Contents WHERE OrderIndex=?}, $order_id);

			my $order_id = openprint::order::make_order($log, $dbh, $session{_session_id}, \%variable);
			if ( $order_id ) {
				while ( my ( $p_id, $qty ) = splice(@contents, 0, 2) ) {
					my $Project = new openprint::Project( $p_id );
					my $New = $Project->copy();
					$New->save({reference=>'ReOrder of ' . $New->reference() });
					openprint::order::add_to_order($log, $dbh, $order_id, \%variable, ( $New->id(), $qty ));
				} # end while
				foreach my $Product ( $SRC_Order->Products() ) {
					my $NewProduct = $Product->copy();
					$NewProduct->order_id($order_id);
					$NewProduct->save();
				} # end foreach
			} # end if
			if ( $openprint::dbh->errstr() ) {
				$openprint::dbh->rollback();
				sql::end_transaction($openprint::dbh, $ac);
				return;
			} # end if
			sql::end_transaction($openprint::dbh, $ac);
			return if ! $order_id;

		} elsif ( $param{btnFunction} eq 'ReOpen' ) {
			if ( $order_id ) {
				openprint::order::delete_unfinished_orders();
				my $Order = new openprint::Order( $order_id );
				$Order->save({status=>'Re-Opened', session_id=>$session{_session_id}, total=>undef});
				foreach my $OP ( $Order->Ordered_Projects() ) {
					$variable{error} .= $OP->save({price=>undef});
				} # end foreach
				$Order->add_log('Re-Opened');
			} else {
				$error = 'No order_id given to Re-Open.';
			} # end if order_id
		} elsif ( $param{btnFunction} eq 'Process Order' ) {
			if ($param{quote_id}) {
				($order_id, $error) = openprint::order::make_order_from_quote($param{quote_id});
			} elsif ($param{ProjectIndex}) {
				if ( openprint::Order->find( project_id=>$param{ProjectIndex},
            status=>['Pending Deposit', 'In Production', 'Complete', 'Shipped', 'Waiting For Pickup', 'Picked Up']) ) {
					return misc::error($log, $dbh, \%variable, q{Can't order project.}, "Project $param{ProjectIndex} has already been ordered." );
				} # end if

				# Normal Order Creation
				my $Project = new openprint::Project( $param{ProjectIndex} );
				# migt be recalculating, wait for it to finish
				$Project->lock();
				( $order_id, $error ) = openprint::order::add_project_to_order( $Project, $order_id );
				$Project->unlock();
			} # end if
			if ( ! $order_id ) {
				$log->debug("Had trouble generating order $error");
				$variable{error} .= 'Had trouble generating order.' . $error;
			}
			$variable{ExternalRedirect} = '/main/order/information.html?order_id='.$order_id;
			return;
		} elsif ( $param{btnFunction} eq 'Continue') { # saving projcet information
			$order_id = openprint::order::get_unfinished_order( ) if ! $order_id;
			foreach my $OP ( openprint::OrderedProject->find(order_id=>$order_id) ) {
				$variable{error} .= openprint::order::save_project_information( $OP );
			} # end foreach
		} # end if btnFunction
	} elsif ( $param{Product} and $param{Quantity} ) {
		( $order_id, $error ) = openprint::order::add_product( $order_id, @param{'Product','Quantity'} );
	} elsif ( $param{product_id} and $param{quantity} ) {
		( $order_id, $error ) = openprint::order::add_product( $order_id, @param{'product_id','quantity'} );
	} # end if

	if ( $error ) {
		$variable{error} = $error;
		return;
	} # end if
	$order_id = openprint::order::get_unfinished_order() if !$order_id;
	my $Order = new openprint::Order($order_id);
	$session{order_id} = $order_id;

	if ( $order_id ) {
		$variable{error} = check_for_errors( $Order ) if ! $variable{error};

	  # First thing to do is to try to load info directly from the order.
		my @company_fields = ('company_name','salutation','firstname','lastname','address1','address2','city','state','postalcode','country','phone','fax','email','alsonotify');
		@variable{@company_fields} = @$Order{@company_fields};

		if ( !defined($variable{company_name}) or ($variable{company_name} eq '')) {
			@variable{'company_name',
				'address1',
				'address2',
				'city',
				'state',
				'postalcode',
				'country',
				'phone',
				'fax'} = $openprint::Company->get('name','address1','address2','city','state','postalcode','country','phone','fax');
		} # end if

		if ( !defined($variable{email}) or ($variable{email} eq '')) {
			my $User = $openprint::User;
			# Assume that we are acting on someone else's behalf
			if ( sets::isin( $session{user_type}, [ 'A','E'] ) ) {
			
				# We are logged in as someone else
				if ( $User->company_id() != $session{company_id} ) {
					my @Users = openprint::User->find( 
							company_id=>($param{company_id} ? $param{company_id} : $session{company_id}), 
							order=>'lower(lastname),lower(firstname)'
							);
					$User = $Users[0] if @Users;
				} # end if
			} # end if
			my @user_fields = ('email', 'title', 'firstname', 'lastname', 'salutation');
			@variable{@user_fields} = $User->get(@user_fields);
			foreach my $field ( 'phone', 'fax' ) {
				# These fields exist in Company as well, so only store them in variable if not defined
				$variable{$field} = $User->$field() if $User->$field();
			}

		} # end if
		foreach my $OP ( openprint::OrderedProject->find(order_id=>$order_id) ) {
			if ( ! ($OP->quantity_index() and sets::isin($OP->quantity_index(), $OP->Project->quantity_indexes())) ) {
				$OP->save({quantity_index=>undef});
			}
		}
	} # end if $Order_id
	$variable{order_id} = $order_id;
	$variable{Order} = new openprint::Order( $order_id );
	%{$variable{RequiredFields}} = map { $_ => $_ } split(',',$openprint::config{OrderRequiredFields});

} # end sub information

# So I guess the idea should be that there shouldn't be any changes after the viewing of submit.
# So we should save currency, save prices, save all the data.
sub submit {
	my $order_id = $param{order_id};
	$order_id =~ s/\D//g;
	$order_id = openprint::order::get_unfinished_order() if !$order_id;
	my $Order = new openprint::Order($order_id);
	$session{order_id} = $order_id;
	my $Currency = openprint::Currency::get_current();
	$variable{error} .= $Order->save({currency_id=>$Currency->id()}) if $$Order{currency_id} != $$Currency{id} or ! $Order->id();

	if ( $param{btnFunction} ) {
		if ( $param{btnFunction} eq 'Continue') { # saving project information

			foreach my $OP ( openprint::OrderedProject->find( order_id=>$Order->id() ) ) {
				$variable{error} .= openprint::order::save_project_information( $OP );
			} # end foreach
			foreach my $Product ( $Order->Products() ) {
				if ( exists $param{'ProductQuantity'.$Product->id()} ) {
					$param{'ProductQuantity'.$Product->id()} =~ s/\D//g;
					$Product->quantity( $param{'ProductQuantity'.$Product->id()} );
				} # end if
#my %price = $Product->Product()->get_price( $Product->quantity() );
#$Product->price( $price{Price} );
				$variable{error} .= openprint::order::save_project_information( $Product );
# Need to update price to include shipping costs
				my %Price = $Product->Product()->get_price( $Product->quantity() );
				$openprint::log->debug('Initial price for ' . $Product->quantity() . ' is : ' . $Price{Price} );
				my $Project = $Product->Project();
				if ( $Project ) {
					my $services = $Project->services();
					foreach my $ShippingType ( openprint::ServiceType->find(category=>'Shipping') ) {
						next if ! $$services{$ShippingType->name()};
						foreach my $service_id ( @{$$services{$ShippingType->name()}} ) {
							my $specs =  openprint::service::get_specs_ref( $Project, $service_id );
							$Price{Price} += $$specs{txtPrice1};
						} # end foreach service_id
					} # end foreach
				} # end if
				$Product->price( $Product->Currency()->convert_to( $Currency, $Price{Price} ) );
				$Product->requested_for( sprintf('%.4d-%.2d-%.2d', @param{'ddmDueDateYear'.$$Project{id},'ddmDueDateMonth'.$$Project{id},'ddmDueDateDay'.$$Project{id}} ) ) if exists $param{'ddmDueDateYear'.$$Project{id}};
				$Product->save();
			} # end foreach Product

			$variable{error} .= openprint::order::store_order_info( $openprint::r, $log, $dbh, $session{_session_id}, \%variable );
			if ( $variable{error} ) {
				$session{error} = $variable{error};
				$variable{ExternalRedirect} = '/main/order/information.html';
				return;
			} else {
				$variable{ExternalRedirect} = '/main/order/submit.html?order_id='.$Order->id();
			} # end if
		} elsif ( $param{btnFunction} eq 'Save Service' ) {
			my $Project = new openprint::Project( $param{ProjectIndex} );
			openprint::print::save_service( $openprint::r, $log, $dbh, \%variable, $Project, $param{ServiceIndex} );
		} # end if
	} # end if btnFunction

	$variable{error} = check_for_errors( $Order );
	if ( $variable{error} ) {
		$variable{ExternalRedirect} = '/main/order/information.html?order_id='.$$Order{id};
		return;
	} # end if
	
	@variable{'Currency','CurrencyName','CurrencySymbol'} = ( $Currency, $Currency->name(), $Currency->symbol() );
	$variable{Order} = $Order;
	$Order->subtotal(undef); # Force a reload
	foreach my $Tax ( $Order->Taxes() ) {
		$Tax->amount(undef);
	} # end foreach Tax

	$variable{order_id} = $order_id;

	@{$variable{Projects}} = $Order->Projects();
	$variable{Order} = $Order;

	if ( sets::isin( $session{user_type}, ['A','E'] ) ) {
		$variable{AdministratorName} = $openprint::User->name();
	} # end if

} # end sub submit

sub confirmation {
	my $order_id = $param{order_id};
	$order_id = openprint::order::get_unfinished_order( ) if ! $order_id;
	if ( $order_id eq '' ) {
		$log->error('Still no Order ID');
		return;
	} # end if

	my $Order = new openprint::Order( $order_id );

	if ( $param{btnFunction} eq 'Complete' ) {
	
		if ( $Order->id() and ( sets::isin( $Order->status(), ['Incomplete','Re-Opened'] ) ) ) {
			if ( ( $Order->company_id() == $session{company_id} ) and ( $session{company_id} == $openprint::User->company_id() ) ) {
				if ( ! $param{accept_terms} ) {
					$variable{error} = 'Terms not accepted';
					$variable{information} = 'You must check the box to indicate your acceptance of the terms and conditions.';
					$variable{ExternalRedirect} = '/main/order/submit.html';
					return;
				} else {
					$Order->add_log('User accepted the terms and conditions.');
					$Order->save({terms_accepted=>1});
				} # end if
			} # end if employee or admin

			# Commit Project Information
			foreach my $OP ( $Order->Ordered_Projects() ) {
				my $Project = $OP->Project();
				$variable{error} .= $OP->save({
					reference	=> $Project->reference(),
					price	  	=> undef,
					quantity	=> undef,
				});
				$variable{error} .= $Project->check_for_order( $OP );
			} # end foreach Project
			$variable{error} = check_for_errors( $Order ) if ! $variable{error};

			if ( $variable{error} ) {
				$variable{ExternalRedirect} = '/main/order/submit.html';
				return;
			} # end if

			my $sub_total = $Order->subtotal(undef);
			foreach my $Tax ( $Order->Taxes() ) {
				$Tax->save({ amount => undef });
			} # end foreach Tax
			my $total = $Order->total(undef);

			#my $customer_credit = new openprint::customer_credit( $session{company_id} );
			my $downpayment = 0;
			#my ( $downpayment ) = $customer_credit->get( 'Downpayment' );
			#if ( $downpayment eq '' ) {
				#$downpayment = $config{DefaultDownpayment};
			#} # end if
			#$downpayment = $total * ( $downpayment / 100 );
			#$downpayment = Math::Round::nearest( 0.01, $downpayment );

			my $status = ( ( $downpayment - $Order->paid() ) > 0 ) ? 'Pending Deposit': 'In Production';
			# Get Docket #
			my $docket_number = $Order->docket();
			if ( ! $docket_number ) {
				( $docket_number ) = sql::execute( $log, $dbh, q{SELECT nextval('DocketNumber_seq')} );
			} # end if
			# This is messed up.  I think an order should never switch companies unless it doesn't have a company assigned.  I don't see how it could work any other way.
			$Order->company_id( $session{company_id} ) if ! $Order->company_id();
			$Order->salesrep_id( $openprint::Company->salesrep_id() );
			$Order->downpayment( $downpayment );
			$Order->status( $status );
			$Order->administrator_name( $param{AdministratorName} );
			$Order->administrator_comments( $param{AdministratorComments} );
			$Order->docket( $docket_number );
			$Order->currency_id( $session{Currency_id} );
			$Order->save();

			$Order->add_log( $param{btnFunction} eq 'Close' ? 'Close Order' : 'Submit Order' );

			foreach my $OP ( $Order->Ordered_Projects() ) {
				my $Project = $OP->Project();
				sql::update( $log, $dbh, 'tbl_Project_Contents', ["lngProjectIndex=? AND strStatus NOT IN ( 'Complete', 'Approved', 'Proofs Out', 'Waiting For Customer Approval','Waiting For QA Approval','')", $Project->id()], 'strStatus', 'Ordered' );
				$Project->docket( $docket_number );
				$Project->order_id( $Order->id() );
				$Project->status( $status eq 'Pending Deposit' ? $status : 'In Prepress' );
				$Project->save();	
				$Project->update_status();
				$Project->allocate_for_order( $OP );
				openprint::press_schedule::add_project_to_press_schedule( $Project );
			} # end foreach Project
			foreach my $Product ( $Order->Products() ) {
				if ( $$Product{project_id} ) {
					my $Project = $Product->Project();
					sql::update( $log, $dbh, 'tbl_Project_Contents', ["lngProjectIndex=? AND strStatus NOT IN ( 'Complete', 'Approved', 'Proofs Out', 'Waiting For Client Approval','Waiting For QA Approval','')", $Project->id()], 'strStatus', 'Ordered' );
					$Project->docket( $docket_number );
					$Project->order_id( $Order->id() );
					$Project->status( $status eq 'Pending Deposit' ? $status : 'In Prepress' );
					$Project->save();	
					$Project->update_status();

					openprint::press_schedule::add_project_to_press_schedule( $Project );
				}
			} # end foreach Product

			$variable{Downpayment} = $downpayment - $Order->paid();
			$variable{Downpayment} = 0 if $variable{Downpayment} < 0;
			$variable{Downpayment} = Math::Round::nearest( 0.01, $variable{Downpayment} );

			$Order->update_status();
	# send out email notifications
			$variable{information} .= $Order->send_sales_order( ) if $param{btnFunction} eq 'Complete';

	# *************************** WE are going to manually invoice for now *******************
			if ( $variable{Downpayment} > 0 ) {
			#	send_invoice( $r, $log, $dbh, $order_id );
			} # end if
		} else {
			$log->debug("Already complete");
		} # end if
	} elsif ( $param{btnFunction} eq 'Close' ) {
		if ( $Order->status() ne 'Re-Opened' ) {
			$variable{error} .= "Can only close a re-opened Order.";
			$variable{ExternalRedirect} = '/main/order/submit.html?order_id='.$Order->id();
			return;
		}
		$Order->close();

		$variable{information} .= $Order->link_to() . ' has been closed';
		$variable{ExternalRedirect} = $Order->url_to();
	} # end if btnFunction eq 'Close or Complete

	$variable{order_id} = $order_id;
	$variable{Order} = $Order;
	delete $session{order_id}
} # end sub confirmation

sub history {
	ssi::setup_date_select( '/main/order/history.html', 'created_on_start', -30 );
	ssi::setup_date_select( '/main/order/history.html', 'created_on', 0 );
	$session{$r->uri().'?company_id'} = $session{company_id} if ! exists $session{$r->uri().'?company_id'};
	_history();
} # end sub history

sub _history {
  ssi::save_params( '/main/order/history.html', 
    'user_id','company_id','status_id','salesrep_id',
    'created_on_start_year', 'created_on_start_month','created_on_start_day', 
    'created_on_end_year', 'created_on_end_month','created_on_end_day', 
  );
  if ($param{btnFunction}) {
    if ($param{btnFunction} eq 'delete') {
      my @order_ids;
      if (exists $param{'order_id[]'}) {
        @order_ids = @{$param{'order_id[]'}};
      } elsif ( exists $param{order} ) {
        @order_ids = ref $param{order_id} eq 'ARRAY' ? @{$param{order_id}} : split(',', $param{order_id});
      }
      if (!@order_ids) {
        $variable{error} .= 'Please specify the orders to delete<br/>';
      } else {
        foreach my $Order (openprint::Order->find(id=>\@order_ids)) {
          if ($Order->can_delete()) {
            $variable{error} .= $Order->delete();
          } else {
            $variable{error} .= 'No permission to delete order ' . $Order->id(). '</br>';
          }
        } # end foreach
      } # end if order_ids
    } # end if which function
  } # end if has a function

} # end sub _history

sub history_details {
	my $order_id;
	my $Order;

  if ( $param{order_id} ) {
    $order_id = openprint::Order->transform(id=>$param{order_id});
    $Order = new openprint::Order($order_id);
  } elsif ( $param{docket} ) {
    $Order = openprint::Order->find_one(docket=>openprint::Order->transform(docket=>$param{docket}));
    $order_id = $Order->id() if $Order;
  }
  if ( ! ( $Order and $Order->id() ) ) {
    $variable{error} .= 'Please specify the order by order id or docket #.<br/>';
    return;
  }

  if ( $param{action} ) {
    if ( $param{action} eq 'reopen' ) {
			if ( $Order->can_reopen() ) {
				$Order->save({status=>'Re-Opened', session_id=>$session{_session_id}, total=>undef});
				foreach my $OP ( $Order->Ordered_Projects() ) {
					$variable{error} .= $OP->save({price=>undef});
				} # end foreach
				$Order->add_log('Re-Opened. Reason: '.$param{reason});
				$variable{information} .= 'Order re-opened.';
			} else {
				$variable{error} .= 'You are not permitted to reopen this order.<br/>';
			}
		} else {
			$variable{error} .= 'Invalid action '.$param{action};
    }
		$variable{ExternalRedirect} = '/main/order/history_details.html?order_id='.$Order->id();
  } elsif ( $param{btnFunction} ) {
		if ( $param{btnFunction} eq 'AcceptTerms' ) {
			if ( ( $Order->company_id() != $session{company_id} ) or ( $openprint::User->company_id() != $session{company_id} ) ) {
				$variable{error} = 'Terms not accepted';
				$variable{information} = 'You are not authorised to accept the terms and conditions.';
			} elsif ( ! $param{accept_terms} ) {
				$variable{error} = 'Terms not accepted';
				$variable{information} = 'You must check the box to indicate your acceptance of the terms and conditions.';
			} else {
				$Order->add_log('User accepted the terms and conditions.');
				$Order->save({terms_accepted=>1});
			} # end if

		} elsif ( $param{btnFunction} eq 'Cancel' ) {
			$variable{error} .= $Order->cancel();
		} elsif ( $param{btnFunction} eq 'ChangeSupplier' ) {
			if ( $openprint::User->Groups('Accounting') ) {
				if ( ! $param{supplier_id} ) {
					$variable{error} .= 'No supplier specified.  No change made.<br/>';
				} elsif ( $Order->supplier_id() == $param{supplier_id} ) {
					$variable{error} .= 'Supplier is already ' . $Order->Supplier()->name().'. No change made.<br/>';
				} else {
					$Order->add_log('Supplier changed from '.$Order->Supplier()->name().' to '.(new openprint::Company($param{supplier_id}))->name());
					$variable{error} .= $Order->save({supplier_id=>$param{supplier_id}});
				} # end if
			} else {
				$variable{error} .= 'You are not permitted to change the supplier.<br/>';
			}
			$variable{ExternalRedirect} = '/employee/accounting/details.html?order_id='.$Order->id() if ! $variable{error};
		} elsif ( $param{btnFunction} eq 'Pay' ) {
			if ( $openprint::User->Groups('Accounting') ) {
				$variable{error} .= $Order->pay();
				$variable{ExternalRedirect} = '/main/order/history_details.html?order_id='.$Order->id();
			} else {
				$variable{error} .= 'You are not permitted to record a payment.<br/>';
			}
		} elsif ( $param{btnFunction} eq 'Save Payment' ) {
			if ( $openprint::User->Groups('Accounting') ) {

				$param{amount} = openprint::Payment->transform(amount=>$param{amount});

				if ( ! $param{amount} ) {
					$variable{error} .= 'Invalid Amount<br/>';
					$variable{information} .= 'Please enter a valid monetary amount.';
				} # end if
				if ( ! Date::Calc::check_date( @param{'received_on_year','received_on_month','received_on_day'} ) ) {
					$variable{error} .= 'Invalid received on date.';
					$variable{information} .= 'Please enter a valid date.';
				} # end if
				if ( ! $variable{error} ) {

					my $Payment = new openprint::Payment();
					$variable{error} .= $Payment->save( {
							order_id			=> $order_id,
							payor_id			=> $Order->company_id(),
							recipient_id	=> $Order->supplier_id(),
							amount				=> $param{amount},
							method        => $param{method},
							currency_id		=> ( $param{payment_currency_id} ? $param{payment_currency_id} : $Order->currency_id() ),
							memo					=> $param{memo},
							completed			=> 1,
							received_on   =>  join('-', @param{'received_on_year','received_on_month','received_on_day'} ),
							transaction_id  =>  $param{transaction_id},
							} );
					if ( ! $variable{error} ) {
						$Order->add_log("Add payment $$Payment{amount}.");
						if ( $Order->deposit_due() > 0 ) {
							foreach my $Project ( $Order->Projects() ) {
								$Project->save({status=>'Pending Deposit'}) if $Project->status() eq 'In Prepress';
								foreach my $Service ( $Project->Services() ) {
									$Service->save({status=>'Pending Deposit'}) if $Service->status() eq 'Ordered';
								}
							} # end foreach Project
						} else {
							$Order->status('In Production') if $Order->status() eq 'Pending Deposit';

							foreach my $Project ( $Order->Projects() ) {
								$Project->save({status=>'In Prepress'}) if $Project->status() eq 'Pending Deposit';
								foreach my $Service ( $Project->Services() ) {
									$Service->save({status=>'Ordered'}) if $Service->status() eq 'Pending Deposit';
								}
							} # end foreach Project

							if ( $Order->owing() <= 0 ) {
								$Order->status('Paid') if $Order->status() eq 'Complete';
							} # end if
							$Order->save();
						} # end if DepositDue
					} # end if no error
				} # end if no error
			} else {
				$variable{error} .= 'You are not permitted to record a payment.<br/>';
			}
			$variable{ExternalRedirect} = '/main/order/history_details.html?order_id='.$Order->id();
		} elsif ( $param{btnFunction} eq 'Delete Payment' ) {
			if ( $openprint::User->Groups('Accounting') ) {
				my $Payment = new openprint::Payment($param{payment_id});
				if ( !$Payment->id() ) {
					$variable{error} .= 'Invalid payment id specified.<br/>';
				} else {
					if ( my $error = $Payment->delete() ) {
						$variable{error} .= 'Payment not deleted: <br/>'.$error.'<br/>';
					} else {
						$variable{information} .= 'Payment deleted successfully.<br/>';
						$Order->Payments(undef);
						$Order->owing(undef);
						$Order->paid(undef);
						$Order->update_status();
						$variable{error} .= $Order->save();
					} # end if
				} # end if
				$variable{ExternalRedirect} = '/main/order/history_details.html?order_id='.$Order->id();
			} else {
				$variable{error} .= 'You are not permitted to delete a payment.<br/>';
			}
		} elsif ( $param{btnFunction} eq 'Resend' ) {
			$variable{information} .= $Order->send_sales_order();
			$variable{ExternalRedirect} = '/main/order/history_details.html?order_id='.$Order->id();
		} # end if
	} # end if action or btnFunction

	openprint::order::display_order($order_id);
} # end sub history_details

sub _Shipping {
	$variable{Project} = new openprint::Project( $param{project_id} );
	$variable{Order} = $variable{Project}->Order();
} # end sub _Shipping
sub _CustomerPickUp {
	$variable{Project} = new openprint::Project( $param{project_id} );
	$variable{Order} = $variable{Project}->Order();
} # end sub _CustoemrPickUp
sub _view_log {
} # end sub _view_log
sub _UPS {
	$variable{Project} = new openprint::Project( $param{project_id} );
	$variable{ProjectIndex} = $variable{Project}->id();
	$variable{Order} = $variable{Project}->Order();
} # end sub _UPS

sub _order {
	if ( $param{action} eq 'select_quantity' ) {
		my $Project = openprint::OrderedProject->find_one( order_id=>$param{order_id}, project_id=>$param{project_id} );
		if ( ! $Project ) {
			$variable{error} = 'Project is not in order.<br/>';
		} else {
			$variable{error} .= $Project->save({quantity_index=>$param{quantity_index}});
		} # end if
	} # end if
} # end sub _order

sub _user_info {
} # end sbu _user_info

sub check_for_errors {
	my ( $Order ) = @_;
# Only check for errors if we don't have any yet
	my @errors;
# If there are any unspecified quantities, keep looping on the selection page.
	foreach my $OP ( openprint::OrderedProject->find( order_id=>$Order->id() ) ) {
		if ( ( ! $OP->quantity_index() ) and ( $OP->Project()->quantity_indexes() > 1 ) ) {
			push @errors, "Please select the quantity to order for project $$OP{project_id}<br/>";
		} # end if
		if ( ! $OP->description() ) {
			push @errors, "Please give project $$OP{project_id} a reference<br/>";
		} # end if
		if ( ! $OP->shippingtype() ) {
			push @errors, "Please select a shipping type for project $$OP{project_id}<br/>";
		} # end if
		my $Project = $OP->Project();
		my $project_error = $Project->check_for_order( $OP );
		push @errors, $project_error if $project_error;

		if ( ! $Project->reference() ) {
			push @errors, "Please give project $$Project{id} a reference";
		} # end if
		my $services = $Project->services();
		my @ServiceTypes = openprint::ServiceType->find('category'=>'Shipping');
		foreach my $ServiceType ( @ServiceTypes ) {
			next if ! $$services{$ServiceType->name()};
			next if sets::isin( $ServiceType->name(), [ 'CustomerPickUp','Turnaround'] );
		
			foreach my $service_id ( @{$$services{$ServiceType->name()}} ) {
				my $specs = openprint::service::get_specs_ref( $Project, $service_id );
# do error checks
				push @errors, 'Please enter the Shipping Company Name.' if ! $$specs{ToCompanyName};
				push @errors, 'Please enter the Shipping Address.' if ! $$specs{ToAddress1};
				push @errors, 'Please enter the Shipping City.' if ! $$specs{ToCity};
				push @errors, 'Please enter the Shipping State/Province.' if ! $$specs{ToStateProvince};
				push @errors, 'Please enter the Shipping PostalCode.' if ! $$specs{ToPostalCode};
				push @errors, 'Please enter the Shipping Country.' if ! $$specs{ToCountry};
				push @errors, 'Please enter the Shipping Phone.' if ! $$specs{ToPhone};
				#push @errors, 'Please enter the Shipping Email.' if	! $$specs{ToEmail};

				if ( $$specs{ToEmail} ) {
					$_ = Email::Valid->address($$specs{ToEmail} );
					if ( ( ! $_ ) or ( $_ ne $$specs{ToEmail} ) ) {
						push @errors, 'Shipping Email is not a valid email address.';
					} # end if
				} # end if
	
				if ( openprint::service::status( $Project->id(), $service_id ) eq 'uncalculated' ) {
					push @errors, 'Unable to calculate shipping:' . $$specs{alert};
				} # end if
			} # end foreach service_id
		} # end foreach ServiceType
		if ( $Project->order_id() != $$Order{id} ) {
$log->error("Updating project order_id, shouldn't have to do this");
			$Project->save( { order_id=>$$Order{id} } );
		} # end if
	} # end foreach OP
	if ( @errors ) {
		return join('<br/>', @errors );
	} # end if
# Only check for errors if we don't have any yet
	foreach my $Product ( $Order->Products() ) {
		if ( ! $Product->shippingtype() ) {
			#push @errors, "Please select a shipping type.<br/>";
		} # end if
	} # end foreach Project
	if ( @errors ) {
		return join('<br/>', @errors );
	} # end if
	return;
} # end sub check_for_errors

sub _add_product_popup {
	my $Order = $variable{Order} = openprint::Order->find_one(id=>$param{order_id} );
	if ( ! $Order ) {
		$variable{error} .= 'Order ' . $param{order_id} . ' not found.';
		return;
	}
}

sub _product_list_edit {
	my $Order = $variable{Order} = openprint::Order->find_one(id=>$param{order_id} );
	if ( ! $Order ) {
		$variable{error} .= 'Order ' . $param{order_id} . ' not found.';
		return;
	}
	if ( $param{action} eq 'add' ) {
		my $OP = new openprint::OrderedProduct();
		$variable{error} .= $OP->save({
			order_id	=>$Order->id(),
			product_id	=>	$param{product_id},
			quantity	=>	1,
		});
	} elsif ( $param{action} eq 'remove' ) {
		my $OP = openprint::OrderedProduct->find_one(order_id => $param{order_id}, id=>$param{id} );
		$variable{error} .= $OP->delete() if $OP;
	} # end if
	$variable{Products} = [ $Order->Products() ];
} # end sub 

sub _reopen_order {
  my $Order = $variable{Order} = openprint::Order->find_one(id=>$param{order_id});
} # end sub _reopen_order

1;
__END__
