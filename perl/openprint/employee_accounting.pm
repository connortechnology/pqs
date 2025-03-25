use strict;
package openprint::employee_accounting;

require openprint::Payment;
require openprint::Credit_Application;
require MIME::QuotedPrint;
require Encode;
require openprint::Company_Credit;
require openprint::order;
require openprint::Order;
require openprint::Order_Invoice;
require openprint::Ledger;
require openprint::Expenditure;
require openprint::Expense;
require openprint::Expense_Rule;
require openprint::Expense_Rule_Category;
require openprint::Payment;
require misc;
require sql;
require JSON;

use openprint ();
use vars qw( $r $log $dbh %variable %param %session %config);
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*param = \%openprint::param;
*session = \%openprint::session;
*config = \%openprint::config;

sub _jump {
}

sub search {
	if ( $param{btnFunction} eq 'Go' ) {
		if ( $param{StartDocket} or $param{order_id} or $param{invoice_id} ) {
			my @Orders = openprint::Order->find(
					( $param{StartDocket} ? ( docket=>$param{StartDocket} ) : () ),
					( $param{order_id} ? ( id=>$param{order_id} ) : () ),
					( $param{invoice_id} ? ( invoice_id=>$param{invoice_id} ) : () ),
					);
			if ( @Orders == 1 ) {
				$variable{ExternalRedirect} = '/employee/accounting/details.html?order_id='.$Orders[0]->id();
				return;
			} # end if
		} elsif ( $param{project_id} ) {
			my $Project = new openprint::Project( $param{project_id} );
			if ( $Project->id() and $Project->order_id() ) {
				$variable{ExternalRedirect} = '/employee/accounting/details.html?order_id='.$Project->order_id();
				return;
			} # end if
		} # end if
	} # end if

	_search();
	ssi::setup_date_select( '/employee/accounting/search.html', 'ordered_on_start', -365 );
	ssi::setup_date_select( '/employee/accounting/search.html', 'ordered_on_end', '' );
	if ( ( ! $session{'/employee/accounting/search.html?ddmStatus'} ) or ( $session{'/employee/accounting/search.html?ddmStatus'} =~ /\w/ ) ) {
		my  %Statuses = map { $$_{name}, $$_{id} } openprint::Order_Status->find();
		$session{'/employee/accounting/search.html?ddmStatus'} = join(',', @Statuses{'Complete','In Production',' Order Submitted', 'Pending Deposit', 'Paid', 'Picked Up','Re-Opened', 'Shipped', 'Waiting For Customer Approval', 'Waiting For Pickup', 'Waiting For QA Approval' } );
	} # end if
} # end sub search

sub _search {
	ssi::save_params( '/employee/accounting/search.html',
			'ddmCustomer','ddmStatus','ddmEmployee','dblTotal1','dblTotal2',
			( map { 'ordered_on_start_'.$_ } ( 'year', 'month','day' ) ),
			( map { 'ordered_on_end_'.$_ } ( 'year', 'month','day' ) ),
			);
} # end sub _search

sub details {

	my $order_id;
	my $Order;

	if ( $param{order_id} ) {
		$order_id = openprint::Order->transform( id => $param{order_id} );
		$Order = new openprint::Order( $order_id );
	} elsif ( $param{docket} ) {
		$Order = openprint::Order->find_one( docket=> openprint::Order->transform( docket => $param{docket} ) );
		$order_id = $Order->id() if $Order;
	}
	if ( ! ( $Order and $Order->id() ) ) {
		$variable{error} .= 'Please specify the order by order id or docket #.<br/>';
		return;
	}

	if ( $param{btnFunction} eq 'Send' ) {
		openprint::order::send_sales_order( $r, $log, $dbh, $order_id );
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		my $Payment = new openprint::Payment( $param{payment_id} );
		if ( $Payment->id() ) {
			$variable{error} .= $Payment->delete();
			$variable{error} .= $Order->save() if ! $variable{error};
		} # end if
		$variable{ExternalRedirect} = '/employee/accounting/details.html?order_id='.$Order->id() if ! $variable{error};
	} elsif ( $param{btnFunction} eq 'Pay' ) {
		$variable{error} .= $Order->pay();
		$variable{ExternalRedirect} = '/employee/accounting/details.html?order_id='.$Order->id() if ! $variable{error};
	} elsif ( $param{btnFunction} eq 'ChangeSupplier' ) {
		if ( ! $param{supplier_id} ) {
			$variable{error} .= 'No supplier specified.  No change made.<br/>';
		} elsif ( $Order->supplier_id() == $param{supplier_id} ) {
			$variable{error} .= 'Supplier is already ' . $Order->Supplier()->name().'. No change made.<br/>';
		} else {
			$Order->add_log( "Supplier changed from " . $Order->Supplier()->name() . ' to ' . (new openprint::Company($param{supplier_id}))->name() );
			$variable{error} .= $Order->save({supplier_id=>$param{supplier_id}});
		} # end if
		$variable{ExternalRedirect} = '/employee/accounting/details.html?order_id='.$Order->id() if ! $variable{error};
	} elsif ( $param{btnFunction} eq 'Save' ) {

		my $error;
		$error .= 'Please enter a valid monetary amount.<br/>' if ( ! $param{amount} ) or $param{amount} =~ /[^-\$\d\.]/;
		$error .= 'Please enter a valid received on date.<br/>' if ! Date::Calc::check_date( @param{'received_on_year','received_on_month','received_on_day'} );

		return misc::error( $log, $dbh, \%variable, 'Payment errors', $error ) if $error;

		my $Payment = new openprint::Payment();
		$error = $Payment->save({
				order_id			=>	$order_id,
				recipient_id	=>	$Order->supplier_id(),
				payor_id			=>	$Order->company_id(),
				amount				=>	$param{amount},
				received_on		=>  join('-', @param{'received_on_year','received_on_month','received_on_day'} ),
				method				=>	$param{method},
				currency_id		=>	$Order->currency_id(),
				memo					=>	$param{memo},
				transaction_id	=>	$param{transaction_id},
				});

		if ( $error ) {
			return misc::error( $log, $dbh, \%variable, 'Error Saving Payment', $error );
		} else {
			$Order->add_log( "Add payment $$Payment{amount}." );
		} # end if

		openprint::order::get_misc( \%variable, $Order );

		if ( $variable{DepositDue} > 0 ) {
			foreach my $project_index ( sql::execute( $log, $dbh, 'SELECT lngProjectIndex FROM Order_Contents WHERE OrderIndex=?', $order_id ) ) {
				sql::update( $log, $dbh, 'Projects', ['id=? AND strStatus=?', $project_index, 'In Prepress'], 'strStatus', 'Pending Deposit' );
				sql::update( $log, $dbh, 'tbl_Project_Contents', "lngProjectIndex=$project_index AND strStatus='Ordered'", 'strStatus', 'Pending Deposit' );
			} # end foreach
		} else {
			$Order->status('In Production') if $Order->status() eq 'Pending Deposit';

			foreach my $project_index ( sql::execute( $log, $dbh, 'SELECT lngProjectIndex FROM Order_Contents WHERE OrderIndex=?', $order_id ) ) {
				sql::update( $log, $dbh, 'Projects', ['id=? AND strStatus=?', $project_index, 'Pending Deposit'], 'strStatus', 'In Prepress' );
				sql::update( $log, $dbh, 'tbl_Project_Contents', ['lngProjectIndex=? AND strStatus=?', $project_index, 'Pending Deposit'], 'strStatus', 'Ordered' );
			} # end foreach
			if ( $variable{AmountPaid} >= $variable{TOTAL} ) {
				$Order->status('Paid') if $Order->status() eq 'Complete';
			} # end if
			$Order->save();
		} # end if
		$variable{ExternalRedirect} = '/employee/accounting/details.html?order_id='.$Order->id();
#openprint::order::send_invoice( $r, $log, $dbh, $order_id );
	} elsif ( $param{btnFunction} eq 'Cancel' ) {
		$variable{error} .= $Order->cancel();
	} # end if

	openprint::order::get_invoice_to( \%variable, $Order );
	$variable{CCITYPROVCOUNTRY} = misc::build_city_prov_country(@variable{'txtCity','txtStateProvince','txtCountry'} );
	openprint::order::get_misc( \%variable, $Order );
	$variable{OrderID} = $order_id;
	my $Currency = $Order->Currency();
	@variable{'Currency','CurrencyName','CurrencySymbol'} = ( $Currency, $Currency->name(), $Currency->symbol() );
	$variable{Order} = $Order;
} # end sub details

sub credit {

	my $company_id = $param{ddmCustomer};

	if ( $param{btnFunction} eq 'Go' ) {
		if ( $param{txtSearchAccountNum} ne '' ) {
			my @Companies = openprint::Company->find( accountnumber=>$param{txtSearchAccountNum}, deleted=>[0,1] );
			if ( @Companies == 1 ) {
				$company_id = $Companies[0]{id};
			} elsif ( @Companies > 1 ) {
				$variable{error} = join('<br/>',
						'There are multiple companies with that account number.  Select by clicking:',
						map { '<a href="credit.html?ddmCustomer='.$_->id().'">'.$_->accountnumber() . ' : ' . $_->name().'</a>' } @Companies,
						);
			} else {
				$variable{error} = 'No company found with account # ' . $param{txtSearchAccountNum}.'<br/>';	
			} # end if
		} # end if

 } elsif ( $param{btnFunction} eq 'Cancel' ) {
    if ( ! $param{PAID} ) {
      $variable{error} = 'Please select an order to cancel.<br/>';
    } else {
      my @errors;
      foreach my $order_id ( ref $param{PAID} eq 'ARRAY' ? @{$param{PAID}} : $param{PAID} ) {
        my $Order = new openprint::Order( $order_id );
        if ( $Order->company_id() != $company_id ) {
          push @errors, 'Order ' . $Order->id() . ' does not belong to ' . new openprint::Company($company_id)->name().'.';
          next;
        } # end if
				$_ = $Order->cancel();
        push @errors, $_ if $_;
      } # end foreach
      if ( @errors ) {
        $variable{error} = join('<br/>', @errors );
      } # end if
    } # end if

	} elsif ( $param{btnFunction} eq 'Pay' ) {
		if ( ! $param{PAID} ) {
			$variable{error} = 'Please select an order to pay.<br/>';
		} else {
			my @errors;
			foreach my $order_id ( ref $param{PAID} eq 'ARRAY' ? @{$param{PAID}} : $param{PAID} ) {
				my $Order = new openprint::Order( $order_id );
				if ( $Order->company_id() != $company_id ) {
					push @errors, 'Order ' . $Order->id() . ' does not belong to ' . new openprint::Company($company_id)->name().'.';
					next;
				} # end if
				push @errors, $Order->pay();
			} # end foreach
			if ( @errors ) {
				$variable{error} = join('<br/>', @errors );
			} # end if
		} # end if
	} elsif ( $param{btnFunction} eq 'Save' ) {
		if ( ! $company_id ) {
			$variable{error} .= 'No customer specified.<br/>';
		} else {
			my $Company = new openprint::Company($company_id);
			my $ac = sql::start_transaction( $dbh );
			$dbh->do( 'LOCK TABLE Company_Credit IN ACCESS EXCLUSIVE MODE' ) or $log->error( $dbh->errstr );
			foreach my $Supplier ( openprint::Company->find( offers_credit=>1) ) {
				my $Credit = new openprint::Company_Credit( { company_id=>$company_id, supplier_id=>$Supplier->id() } );

				if (
						( $Credit->denydays() != openprint::Company_Credit->transform('denydays', $param{'denydays-'.$$Supplier{id}} ) ) or
						( $Credit->warndays() != openprint::Company_Credit->transform('warndays', $param{'warndays-'.$$Supplier{id}} ) ) or
						( $Credit->limit() != openprint::Company_Credit->transform('limit', $param{'limit-'.$$Supplier{id}} ) ) or
						( $Credit->hold() ne openprint::Company_Credit->transform('hold', $param{'hold-'.$$Supplier{id}} ) ) or
						( $Credit->downpayment() != openprint::Company_Credit->transform('downpayment', $param{'downpayment-'.$$Supplier{id}} ) ) or
						( $Credit->cod() != openprint::Company_Credit->transform('cod', $param{'cod-'.$$Supplier{id}} ) ) or
						( $Credit->late_payment_amount() != openprint::Company_Credit->transform('late_payment_amount', $param{'late_payment_amount-'.$$Supplier{id}} ) ) or
						( $Credit->late_payment_units() ne openprint::Company_Credit->transform('late_payment_units', $param{'late_payment_units-'.$$Supplier{id}} ) ) or
						( $Credit->early_payment_amount() != openprint::Company_Credit->transform('early_payment_amount', $param{'early_payment_amount-'.$$Supplier{id}} ) ) or
						( $Credit->early_payment_units() ne openprint::Company_Credit->transform('early_payment_units', $param{'early_payment_units-'.$$Supplier{id}} ) ) or
						( $Credit->early_payment_days() != openprint::Company_Credit->transform('early_payment_days', $param{'early_payment_days-'.$$Supplier{id}} ) )
					 ) {
					my $note = 'Old credit: ' . $Credit->to_string() if $Credit->supplier_id();
					$variable{error} .= $Credit->save( { 'company_id'=>$company_id, 'supplier_id'=>$Supplier->id(), 
							map { $_ => $param{$_.'-'.$Supplier->id()} } ( 'denydays','warndays','limit','hold','downpayment','cod',
									'late_payment_amount','late_payment_units','early_payment_amount','early_payment_units','early_payment_days' ) } );
					$note .= '<br/>new credit: ' . $Credit->to_string();
					$variable{error} .= (new openprint::Log())->save( {
							action		=>	'Credit Information Changed',
							object_id	=>	$company_id,
							object_type	=>	'openprint::Company',
							note		=>	$note,
							});
				} else {
					$variable{information} .= 'Credit unchanged for ' . $Supplier->name() . '<br/>';
				} # end if
			} # end foreach Supplier
			my %updates;
			foreach my $p ( 'csr_commission','credit_card_fee', 'discount', 'salesrep_id', 'notes' ) {
				$updates{$p} = $param{$p} if exists($param{$p}) and ($$Company{$p} ne $param{$p});
			}
			if ( %updates ) {
				my $note = join('<br/>', map { $_ . ' changed from ' . $$Company{$_} . ' to ' . $updates{$_} } sort keys %updates );
				if ( ! ( $_ = $Company->save(\%updates) ) ) {
					(new openprint::Log())->save({ action=>'Edit Company', Object=>$Company, note=>$note });
				} else {
					$variable{error} .= $_ . '<br/>';
				} # end if
			} 
			sql::end_transaction( $dbh, $ac );
		} # end if
	} elsif ( $param{btnFunction} eq 'Export' ) {
		my @header = ( 'Creditor', 'Company Internal Name','Legal Name', 'Warn After Days', 'Deny After Days', 'Limit', 
				'Hold', 'Downpayment', 'COD', 'Balance', 'Remaining', 'Note' );
		my @data;
		openprint::Company->find();
		foreach my $Credit ( openprint::Company_Credit->find() ) {
			push @data, ( $Credit->Supplier()->name(), $Credit->Company()->name(), $Credit->Company()->business_name(),
					$Credit->warndays(), $Credit->denydays(), $Credit->limit(), 
					$Credit->hold(), $Credit->downpayment(), $Credit->cod(),
					$Credit->debt(), $Credit->remaining(), '',
					);
		} # ebd foreach Credut
		misc::export_csv( $r, $log, \%variable, 'Credit.csv', \@header, \@data );
	} elsif ( $param{btnFunction} eq 'Import' ) {
		my $upload;
		if ( ! $param{import} ) {
			$variable{error} = 'Please select a file for import.';
		} elsif ( ! ( $upload = $r->upload('import') ) ) {
			$variable{error} = 'Something wrong with upload.';
		} else {
			my $io = $upload->io();
			$_ = <$io>;

			my %Companies = map { $_->name(), $_ } openprint::Company->find();
			my %Legal = map { $_->business_name(), $_ } values %Companies;
			my $csv = Text::CSV_XS->new({binary=>1});
			my $ac = sql::start_transaction( $dbh );
			while ( <$io> ) {
				$csv->parse($_);
#my ( $creditor_name, $company_name, $legal_name, $warndays, $denydays, $limit, $hold, $downpayment, $cod, $note ) = misc::trim( $csv->fields() );
				my ( $creditor_name, $company_name, $legal_name, $warndays, $denydays, $limit, $hold, $downpayment, $cod, $note ) = $csv->fields();
				next if ! $creditor_name;
				next if ! $company_name;
				if ( ! $Companies{$creditor_name} ) {
					$variable{error} .= "Unknown creditor $creditor_name<br/>";
					next;
				} elsif ( ! $Companies{$creditor_name}->offers_credit() ) {
					$variable{error} .= "Creditor $creditor_name doesn't offer credit.  Adding anyways.<br/>";
				} # end if
				if ( ! $Companies{$company_name} ) {
					if ( $Legal{$company_name} ) {
						$Companies{$company_name} = $Legal{$company_name};
					} elsif ( $legal_name and $Legal{$legal_name} ) {
						$Companies{$company_name} = $Legal{$legal_name};
					} elsif ( substr( $company_name, -1,1) eq '.' and $Companies{substr($company_name,0,-1)} ) {
						$Companies{$company_name} = $Companies{substr($company_name,0,-1)};
					} elsif ( substr( $company_name, -1,1) ne '.' and $Companies{$company_name.'.'} ) {
						$Companies{$company_name} = $Companies{$company_name.'.'};
					} elsif ( substr( $company_name, -3,3) ne 'Inc' and $Companies{$company_name.' Inc'} ) {
						$Companies{$company_name} = $Companies{$company_name.' Inc'};
					} elsif ( substr( $company_name, -3,3) ne 'Ltd' and $Companies{$company_name.' Ltd'} ) {
						$Companies{$company_name} = $Companies{$company_name.' Ltd'};
					} elsif ( substr( $company_name, -4,4) eq ' Inc' and $Companies{substr($company_name,0,-4)} ) {
						$Companies{$company_name} = $Companies{substr($company_name,0,-4)};
					} elsif ( substr( $company_name, -5,5) eq ' Inc.' and $Companies{substr($company_name,0,-5)} ) {
						$Companies{$company_name} = $Companies{substr($company_name,0,-5)};
					} elsif ( substr( $company_name, -4,4) eq ' Ltd' and $Companies{substr($company_name,0,-4)} ) {
						$Companies{$company_name} = $Companies{substr($company_name,0,-4)};
					} elsif ( substr( $company_name, -5,5) eq ' Ltd.' and $Companies{substr($company_name,0,-5)} ) {
						$Companies{$company_name} = $Companies{substr($company_name,0,-5)};
					} else {
						$log->debug("$company_name " . substr( $company_name, -1,1) . ','. substr($company_name,0,-1) );
						$variable{error} .= "Unknown company $company_name<br/>";
						next;
					} # end if
				} # end if
				$warndays = openprint::Company_Credit->transform('warndays', $warndays);
				$denydays = openprint::Company_Credit->transform('denydays', $denydays);
				$limit = openprint::Company_Credit->transform('limit', $limit);
				$downpayment = openprint::Company_Credit->transform('downpayment', $downpayment);
				$cod = openprint::Company_Credit->transform('cod', $cod);
				$hold = 1 if sets::isin(lc $hold, [ 'y','yes' ] );
				$hold = 0 if $hold != 1;
				my $Credit = $Companies{$company_name}->Credit($Companies{$creditor_name}->id());
				if ( 
						( $warndays eq '' or $Credit->warndays() == $warndays ) and
						( $denydays eq '' or $Credit->denydays() == $denydays ) and
						( $limit eq '' or $Credit->limit() == $limit ) and
						( $hold eq '' or $Credit->hold() == $hold ) and
						( $downpayment eq '' or $Credit->downpayment() == $downpayment ) and
						( $cod eq '' or $Credit->cod() == $cod ) 
					 ) {
					$variable{information} .= "No change made for $creditor_name for $company_name $legal_name<br/>";
					next;
				} # end if

				$variable{information} .= "$company_name for $creditor_name changed:".join(', ',
						(( $warndays eq '' or $Credit->warndays() == $warndays ) ? () : ('warn days: '.$Credit->warndays().' to '.$warndays )),
						(( $denydays eq '' or $Credit->denydays() == $denydays ) ? () : ('deny days: '.$Credit->denydays().' to '.$denydays )),
						(( $limit eq '' or $Credit->limit() == $limit )? () : ('limit: ' . $Credit->limit().' to ' . $limit )),
						(( $hold eq '' or $Credit->hold() == $hold ) ? () : ( 'hold: ' . $Credit->hold().' to ' . $hold )),
						(( $downpayment eq '' or $Credit->downpayment() == $downpayment ) ? () : ( 'downpayment: ' . $Credit->downpayment() . $downpayment )),
						(( $cod eq '' or $Credit->cod() == $cod ) ? () : ('cod: ' . $Credit->cod() . ' to ' . $cod ) ),
						).'<br/>';

				$variable{error} .= $Credit->save({
						( $$Credit{company_id} ? () : ( 'company_id'=>$Companies{$company_name}->id() ) ),
						( $$Credit{supplier_id} ? () : ( 'supplier_id'=>$Companies{$creditor_name}->id() ) ),
						( $warndays ne '' ? ('warndays'=>$warndays) : () ),
						( $denydays ne '' ? ('denydays'=>$denydays) : () ),
						( $limit ne '' ? ('limit'=>$limit) : () ),
						( $hold ne '' ? ('hold'=>$hold) : () ),
						( $downpayment ne '' ? ('downpayment'=>$downpayment) : () ),
						( $cod ne '' ? ('cod'=>$cod) : () ),
						});
				$variable{error} .= (new openprint::Log())->save({action=>'Credit Information Imported',object_id=>$Companies{$company_name}->id(),object_type=>'openprint::Company',note=>$note. " for $company_name for $creditor_name"}) if $note;
			} # end while
			(new openprint::Log())->save({'action'=>'Credit Information Imported',note=>$variable{error}.$variable{information}});
			sql::end_transaction( $dbh, $ac );
		} # end if	
	} # end if btnFunction

	$variable{CompanyIndex} = $company_id;
	$variable{Company} = new openprint::Company($company_id);
} # end sub credit

sub ledger {
	ssi::save_params( '/employee/accounting/ledger.html', ( 'occurred_on_start_year','occurred_on_start_month','occurred_on_start_day','occurred_on_end_year','occurred_on_end_month','occurred_on_end_day') );
} # end sub ledger

sub _ledger {
	ssi::save_params( '/employee/accounting/ledger.html', ( 'occurred_on_start_year','occurred_on_start_month','occurred_on_start_day','occurred_on_end_year','occurred_on_end_month','occurred_on_end_day') );
} # end sub _ledger

sub expenditures {
	if ( $param{btnFunction} eq 'Save' ) {
		$param{owner_id} = $session{company_id} if ! $param{owner_id};
		my $Expenditure = new openprint::Expenditure( $param{expenditure_id} );
		if ( $variable{error} .= $Expenditure->save( \%param ) ) {
			$variable{Redirect} = '/employee/accounting/expenditure.html';
			return;	
		} # end if
		delete $param{expenditure_id};
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		my $Expenditure = new openprint::Expenditure( $param{expenditure_id} );
		if ( $variable{error} .= $Expenditure->delete() ) {
			$variable{Redirect} = '/employee/accounting/expenditure.html';
			return;	
		} # end if
		delete $param{expenditure_id};
	} else {
		ssi::save_params( '/employee/accounting/expenditures.html', ( 'occurred_on_start_year','occurred_on_start_month','occurred_on_start_day','occurred_on_end_year','occurred_on_end_month','occurred_on_end_day') );
	} # end if
	ssi::setup_date_select( '/employee/accounting/expenditures.html', 'occurred_on_start', -31 );
	ssi::setup_date_select( '/employee/accounting/expenditures.html', 'occurred_on_end', '' );

} # end sub expenditures

sub _expenditures {
	ssi::save_params( '/employee/accounting/expenditures.html', ( 'occurred_on_start_year','occurred_on_start_month','occurred_on_start_day','occurred_on_end_year','occurred_on_end_month','occurred_on_end_day') );
} # end sub _expenditures

sub expenditure {
	$variable{Expenditure} = new openprint::Expenditure( $param{expenditure_id} );
} # end sub expenditure

sub expenses {
  if ($param{btnFunction}) {
    if ( $param{btnFunction} eq 'Delete' ) {
      my $Expenditure = new openprint::Expense( $param{expense_id} );
      if ( $variable{error} .= $Expenditure->delete() ) {
        $variable{ExternalRedirect} = '/employee/accounting/expense.html';
        return;	
      } # end if
      delete $param{expense_id};
    } elsif ( $param{btnFunction} eq 'Download') {
      my $uri = '/employee/accounting/expenses.html';
      my @Taxes = openprint::Tax->find(
        ssi::date_filter( $uri.'?invoiced_on_end', 'period_start null_or_<=' ),
        ssi::date_filter( $uri.'?invoiced_on_start', 'period_end null_or_>=' ),
        ssi::date_filter( $uri.'?paid_on_end', 'period_start null_or_<=' ),
        ssi::date_filter( $uri.'?paid_on_start', 'period_end null_or_>=' ),
        order   =>  'period_start,name',
      );
      my @header = ('Recipient', 'Account', 'Category', 'Description', 'Invoiced', 'Due', 'Paid', 'Bus %', 'Currency','Amount in Original Currency','Amount','Business Use Amount', (map { $_->name() . ' ' . $_->rate().'%' } @Taxes), 'Total');
      my @data = ();

      my @Expenses = openprint::Expense->find(
        ( map {
            ( exists $session{$uri.'?'.$_} and $session{$uri.'?'.$_} ne '' ) ? ( $_ => [split(',',$session{$uri.'?'.$_})] ) : ()
          } ( 'category_id', 'recipient_id', 'account_id','attention','amount','total', 'currency_id', 'business_use' ) ),
        ssi::date_filter( $uri.'?invoiced_on_end', 'invoiced_on <=' ),
        ssi::date_filter( $uri.'?invoiced_on_start', 'invoiced_on >=' ),
        ssi::date_filter( $uri.'?due_on_end', 'due_on <=' ),
        ssi::date_filter( $uri.'?due_on_start', 'due_on >=' ),
        ssi::date_filter( $uri.'?paid_on_end', 'paid_on <=' ),
        ssi::date_filter( $uri.'?paid_on_start', 'paid_on >=' ),
        ssi::date_filter( $uri.'?entered_on_end', 'created_on <=' ),
        ssi::date_filter( $uri.'?entered_on_start', 'created_on >=' ),
        ($openprint::User->type() eq 'A' ? ( $session{$uri.'?owner_id'} ? (owner_id=>$session{$uri.'?owner_id'}):()) : (owner_id=>$session{owner_id})),
        ( $session{$uri.'?description'} ? ('description ilike'=>$session{$uri.'?description'}.'%') : () ),
        order     => 'paid_on,due_on',
        deleted   => ($session{$uri.'?deleted'} eq '' ? [0,1] : $session{$uri.'?deleted'}),
      );
      foreach my $Expense ( @Expenses ) {
        my $Currency = $Expense->Currency();
        push @data, (
          $Expense->Recipient()->name(), $Expense->account(), $Expense->category(), 
          $Expense->description(),
          ssi::format_csv_date($Expense->invoiced_on()),
          ssi::format_csv_date($Expense->due_on()),
          ssi::format_csv_date($Expense->paid_on()),
          $Expense->business_use(),
          $Currency->short(),
          $Expense->amount(),
          $Currency->convert_from($Expense->amount(), { period=>$Expense->paid_on()}),
          $Currency->convert_from($Expense->business_use_amount(), { period=>$Expense->paid_on()}),
          ( map { $Expense->Tax( $_ )->amount() } @Taxes),
          $Expense->total(),
          #( map { $Currency->convert_from($Expense->Tax( $_ )->amount(), { period=>$Expense->paid_on()}) } @Taxes),
          #$Currency->convert_from($Expense->total(), { period=>$Expense->paid_on()}),
        );
      } # end foreach Expense
      misc::export_csv( $r, $log, \%variable, 'expenses.csv', \@header, \@data );
    }
	} else {
		_expenses();
		ssi::setup_date_select( '/employee/accounting/expenses.html', 'invoiced_on_start', -31 );
		ssi::setup_date_select( '/employee/accounting/expenses.html', 'invoiced_on_end', '' );
		ssi::setup_date_select( '/employee/accounting/expenses.html', 'due_on_start', -31 );
		ssi::setup_date_select( '/employee/accounting/expenses.html', 'due_on_end', '' );
		ssi::setup_date_select( '/employee/accounting/expenses.html', 'paid_on_start', -31 );
		ssi::setup_date_select( '/employee/accounting/expenses.html', 'paid_on_end', '' );
		ssi::setup_date_select( '/employee/accounting/expenses.html', 'entered_on_start', '' );
		ssi::setup_date_select( '/employee/accounting/expenses.html', 'entered_on_end', '' );
	} # end if
} # end sub expenses

sub _expenses {
	ssi::save_params( '/employee/accounting/expenses.html', ( 
				'entered_on_start_year','entered_on_start_month','entered_on_start_day',
				'entered_on_end_year','entered_on_end_month','entered_on_end_day',
				'invoiced_on_start_year','invoiced_on_start_month','invoiced_on_start_day',
				'invoiced_on_end_year','invoiced_on_end_month','invoiced_on_end_day',
				'due_on_start_year','due_on_start_month','due_on_start_day',
				'due_on_end_year','due_on_end_month','due_on_end_day',
				'paid_on_start_year','paid_on_start_month','paid_on_start_day',
				'paid_on_end_year','paid_on_end_month','paid_on_end_day',
				'category_id', 'recipient_id', 'account_id','attention', 'currency_id',
				'amount','total','business_use', 'owner_id','deleted','description',
				) );
} # end sub _expenses

sub expense {
	my $Expense = $variable{Expense} = new openprint::Expense($param{expense_id});
  if ( $param{btnFunction} ) {
    if ( $param{btnFunction} eq 'Copy' ) {
      $variable{information} .= $Expense->id() . ' has been copied';
      $variable{Expense} = $Expense = $Expense->copy();
    } elsif ( $param{btnFunction} eq 'Destroy' ) {
      if ( ! ( $variable{error} .= $Expense->destroy() ) ) {
        $variable{information} .= 'Expense ' . $Expense->id() . ' destroyed successfully.';
        $variable{ExternalRedirect} = '/employee/accounting/expenses.html';
        return;	
      } # end if
    } elsif ( $param{btnFunction} eq 'Delete' ) {
      if ( ! ( $variable{error} .= $Expense->delete() ) ) {
        $variable{information} .= 'Expense ' . $Expense->id() . ' deleted successfully.';
        $variable{ExternalRedirect} = '/employee/accounting/expenses.html';
        return;	
      } # end if
    } elsif ( $param{btnFunction} eq 'Undelete' ) {
      if ( ! ( $variable{error} .= $Expense->undelete() ) ) {
        $variable{information} .= 'Expense ' . $Expense->id() . ' undeleted.';
        $variable{ExternalRedirect} = '/employee/accounting/expenses.html';
        return;	
      } # end if
    } elsif ( $param{btnFunction} eq 'Save' ) {
      if ( $param{amount} =~ /[=+\-*\/]/ ) {
        $log->debug("Calcing amount: $param{amount}");
        if ( $param{amount} =~ /\=/ ) {	
          eval('$param{amount} ' . "$param{amount};" );
        } else {
          eval('$param{amount} = ' . "$param{amount};" );
        } # end if
        $log->debug("Calcing amount: $param{amount}");
      } else {
        $log->debug("Not Calcing amount: $param{amount}");

      } # end if
      $param{owner_id} = $session{company_id} if ! $param{owner_id};
      $param{due_on} = sprintf('%.4d-%.2d-%.2d', @param{'due_on_year','due_on_month','due_on_day'} ) if Date::Calc::check_date( @param{'due_on_year','due_on_month','due_on_day'} );
      $param{paid_on} = sprintf('%.4d-%.2d-%.2d', @param{'paid_on_year','paid_on_month','paid_on_day'} ) if Date::Calc::check_date( @param{'paid_on_year','paid_on_month','paid_on_day'} );
      $param{invoiced_on} = sprintf('%.4d-%.2d-%.2d', @param{'invoiced_on_year','invoiced_on_month','invoiced_on_day'} );
      if ( ! $param{recipient_id} ) {
        my $Recipient = openprint::Company->find_one('name lc'=>lc $param{recipient});
        if ( ! $Recipient ) {
          $Recipient = new openprint::Company();
          $variable{error} .= $Recipient->save({name=>$param{recipient}});
        } # end if ! Recipeint
        $param{recipient_id} = $Recipient->id();
      } # end if ! recipient_Id
      delete $param{recipient};
      if ( $param{category_id} ) {
        delete $param{category};
      } elsif ( $param{category} ) {
        delete $param{category_id};
      } # end if
      if ( $param{account_id} ) {
        delete $param{account};
      } elsif ( $param{account} ) {
        delete $param{account_id};
      } # end if
      my $Expense = new openprint::Expense( $param{expense_id} );
      if ( $variable{error} .= $Expense->save( \%param ) ) {
        return;	
      } # end if

  # At this point, the array returned should be the correct, appropriate list of taxes.  What we are updating is merely whether we are charging for those taxes
      foreach my $Tax ( $Expense->Taxes() ) {
  # Order is important here. Also the 1* turns an undef value into a specific boolean 0, because we used a checkbox
        if ( $Tax->charge() != 1*$param{'tax_charge-'.$Tax->tax_id()} ) {
          $Tax->charge(1*$param{'tax_charge-'.$Tax->tax_id()});
          $Tax->amount(undef);
          $Tax->save();
        } # end if
        ssi::save_params( '/employee/accounting/expense.html', $param{'tax_charge-'.$Tax->tax_id()} ) if $param{'tax_charge-'.$Tax->tax_id()};
      } # end foreach
      ssi::save_params( '/employee/accounting/expense.html', 'category_id', 
          'due_on', 'invoiced_on', 'paid_on', 'recipient_id', 'business_use', 'account_id'
          );

      $variable{information} .= 'Expense saved successfully.<br/>';
      $variable{ExternalRedirect} = '/employee/accounting/expenses.html';

  # Now update the session for expenses so that we always show the entry we just saved.
      foreach my $key ( 'owner_id', 'recipient_id', 'account_id', 'category_id' ) {
        if (
          $session{'/employee/accounting/expenses.html?'.$key}
            and
          $$Expense{$key}
            and
          ! sets::isin( split(',', $session{'/employee/accounting/expenses.html?'.$key}), $$Expense{$key})
        ) {
          $session{'/employee/accounting/expenses.html?'.$key} .= ','.$$Expense{$key};
          #delete $session{'/employee/accounting/expenses.html?'.$key};
        } # end if
      } # end foreach

      %param = ();
      return;
    } else {
      $variable{error} .= 'Unsupported action '.$param{btnFunction}.'</br>';
    } # end if btnFUnction ==
	} # end if btnfunction
	$Expense->owner_id( $session{company_id} ) if ! $Expense->owner_id();
	$Expense->invoiced_on( join('-', Date::Calc::Today() ) ) if ! $Expense->invoiced_on();

	if ( ( ! $Expense->id() ) and ( time - $session{'/employee/accounting/expense.html?lastupdated'} < ( 12*60*60 ) ) ) {
		$variable{Expense}->recipient_id( $session{'/employee/accounting/expense.html?recipient_id'} ) if ! $variable{Expense}->recipient_id();
		$variable{Expense}->due_on( $session{'/employee/accounting/expense.html?due_on'} ) if ! $variable{Expense}->due_on();
		$variable{Expense}->invoiced_on( $session{'/employee/accounting/expense.html?invoiced_on'} ) if ! $variable{Expense}->invoiced_on();
		$variable{Expense}->paid_on( $session{'/employee/accounting/expense.html?paid_on'} ) if ! $variable{Expense}->paid_on();
		$variable{Expense}->category_id( $session{'/employee/accounting/expense.html?category_id'} ) if ! $variable{Expense}->category_id();
		$variable{Expense}->business_use( $session{'/employee/accounting/expense.html?business_use'} ) if ! $variable{Expense}->business_use();
		$variable{Expense}->account_id( $session{'/employee/accounting/expense.html?account_id'} ) if ! $variable{Expense}->account_id();
		foreach my $Tax ( $Expense->Taxes() ) {
			$Tax->charge( $session{'/employee/accounting/expense.html?tax_charge-'.$Tax->tax_id()} ) if $session{'/employee/accounting/expense.html?tax_charge-'.$Tax->tax_id()};
		} # end foreach
	} # end if

} # end sub expense

sub _expense_taxes {
	my $Expense = $variable{Expense} = new openprint::Expense( $param{expense_id} );
	$Expense->owner_id( $session{company_id} ) if ! $Expense->owner_id();
	if ( $param{invoiced_on_year} and $param{invoiced_on_month} and $param{invoiced_on_day} ) {
		$variable{Expense}->invoiced_on( join('-', @param{'invoiced_on_year','invoiced_on_month','invoiced_on_day'} ) );
	} # end if

}

sub stock {
	require openprint::ManifestContent;

	if ( $param{btnFunction} eq 'Save' ) {
		foreach my $Type ( openprint::Manifest_Content_Type->find(cost=>undef) ) {
			$param{'cost-'.$Type->id()} =~ s/[^\d\.]//g;
			if ( $param{'units-'.$Type->id()} eq '/lb' ) {
				$param{'cost-'.$Type->id()} *= 100;
			} # end if
			if ( ( $param{'supplier_invoice-'.$Type->id()} ne $Type->supplier_invoice() ) or ( $param{'cost-'.$Type->id()} != $Type->cost() ) ) {
				$variable{error} .= $Type->save({
						supplier_invoice=>$param{'supplier_invoice-'.$Type->id()},
						cost=>$param{'cost-'.$Type->id()} 
						});
			} # end if
		} # end foreach
	} else {
		_stock();
		ssi::setup_date_select( '/employee/accounting/stock.html', 'received_on_start', -30 );
		ssi::setup_date_select( '/employee/accounting/stock.html', 'received_on_end', 0 );
	} # end if
} # end sub stock

sub _stock {
	if ( $param{action} ) {
		if ( $param{action} eq 'confirm_po_content' ) {
			my $Manifest_Content_Type = openprint::Manifest_Content_Type->find_one(id=>$param{manifest_content_type_id});
			if ( $Manifest_Content_Type ) {
				$variable{error} .= $Manifest_Content_Type->save({po_content_id=>$param{po_content_id}});
				my $POC = $Manifest_Content_Type->PurchaseOrder_Content();
				(new openprint::Log())->save({
						Object=>$Manifest_Content_Type->Manifest(),
						action=>'Edit',
						note=>'Confirm PO Content '.$POC->item(),
						});

			} else {
				$variable{error} .= "Manifest Content Type not found for id=.$param{manifest_content_type_id}<br/>";
			}
		} elsif ( $param{action} eq 'unconfirm_po_content' ) {
			my $Manifest_Content_Type = openprint::Manifest_Content_Type->find_one(id=>$param{manifest_content_type_id});
			if ( $Manifest_Content_Type ) {
				my $POC = $Manifest_Content_Type->PurchaseOrder_Content();
				$variable{error} .= $Manifest_Content_Type->save({po_content_id=>undef});
				(new openprint::Log())->save({
						Object=>$Manifest_Content_Type->Manifest(),
						action=>'Edit',
						note=>'Unconfirm PO Content '.$POC->item(),
						});
			} else {
				$variable{error} .= "Manifest Content Type not found for id=.$param{manifest_content_type_id}<br/>";
			}
		} # end if
	} else {
		ssi::save_params( '/employee/accounting/stock.html',
				( map { 'received_on_start_'.$_ } ( 'year', 'month','day' ) ),
				( map { 'received_on_end_'.$_ } ( 'year', 'month','day' ) ),
				);
	}
} # end sub _stock

sub credit_applications {

	ssi::setup_date_select( '/employee/accounting/credit_applications.html', 'created_on_start', -180 );
	ssi::setup_date_select( '/employee/accounting/credit_applications.html', 'created_on_end', 0 );
	ssi::save_params( '/employee/accounting/credit_applications.html',
			'ddmStatus',
			'created_on_start_year', 'created_on_start_month','created_on_start_day',
			'created_on_end_year', 'created_on_end_month','created_on_end_day',
			);

} # end sub credit_applications

sub credit_application {

	my $Application = $variable{Application} = new openprint::Credit_Application( $param{credit_index} );
	if ( ! $Application->id() ) {
		$variable{error} .=  'Application does not exist.';
		return;
	} # end if

	my $Company = $variable{Company} = $Application->Company();
	if ( ! $Company->id() ) {
		$variable{error} .= 'The company that created this credit app has been deleted from the system.  This credit app has been deleted.';
	} # end if

	my $User = $variable{User} = $Application->User();
	my $Credit = $variable{Credit} = $Company->Credit();

	if ( $param{btnFunction} eq 'Save' ) {
		$variable{error} .= $Application->save({
				'status'				=>	$param{status},
				'granted_terms'			=>	$param{denydays},
				'granted_limit'			=>	$param{limit},
				'granted_downpayment'	=>	$param{downpayment},
				'granted_cod'			=>	$param{cod},
				});

		$variable{error} .= $Credit->save( {
				'company_id'	=>	$Application->company_id(),
				'denydays'		=>	$param{denydays},
				'warndays'		=>	$param{warndays},
				'limit'			=>	$param{limit},
				'downpayment'	=>	$param{downpayment},
				'cod'			=>	$param{cod},
				} );
		if ( ! $variable{error} ) {

			$variable{ReplacementText} = ssi::slurp_content( '/email_content/credit_change_notification.html' );
			$variable{ReplacementText} = ssi::variable_substitution( \$variable{ReplacementText}, \%variable );
			my $template = ssi::include( '/email_template.html', \%variable );
			$variable{error} .= ( new openprint::Email())->send(
					FROM	=> $config{AdministratorEmail},
					TO		=> $Application->User()->email(),
					SUBJECT => 'Credit Status Changed.',
					ATTACHMENTS	=> [ '', MIME::QuotedPrint::encode_qp(Encode::encode('utf-8',$template)), 'text/html', 'quoted-printable' ],
					);
		} # end if
		$variable{ExternalRedirect} = '/employee/accounting/credit_applications.html' if ! $variable{error};
	} elsif ( $param{btnFunction} eq 'SendToMe' ) {
		$variable{information} .= $Application->send_notification( $openprint::User );
		$variable{ExternalRedirect} = '/employee/accounting/credit_application.html?credit_index='.$Application->id();
	} elsif ( $param{btnFunction} eq 'Resend' ) {
		$variable{information} .= $Application->send_notification( );
		$variable{ExternalRedirect} = '/employee/accounting/credit_application.html?credit_index='.$Application->id();
	} # end if

} # end sub credit_application

sub _order_invoices {
	my $Order = $variable{Order} = new openprint::Order( $param{order_id} );
	if ( $param{action} eq 'Delete' ) {
		my $OI = openprint::Order_Invoice->find_one( { order_id=>$param{order_id}, invoice_id=>$param{invoice_id} } );
		if ( $OI ) {
			$OI->Order()->add_log( 'Invoice ' . $OI->Invoice()->link_to() . ' removed. ' . $param{reason} );
			$OI->delete();
		} else {
			$variable{error} = 'Invoice not found.  Not deleted<br/>';
		} # end if
	} elsif ( $param{action} eq 'add' ) {
		$param{invoice_num} = openprint::Invoice->transform('num', $param{invoice_num} );
		if ( ! $param{invoice_num} ) {
			$variable{error} .= 'Empty or invalid Invoice #.<br/>';
		} elsif ( ! $param{order_id} ) {
			$variable{error} .= 'Empty or invalid Order #.<br/>';
		} else {
			my $Invoice = openprint::Invoice->find_one(num=>$param{invoice_id});
			if ( ! $Invoice ) {
				$Invoice = new openprint::Invoice();
				$variable{error} .= $Invoice->save({
						invoicer_id	=> $config{owner_id},
						invoicee_id	=> $Order->company_id(),
						total		=> $param{amount},
						num			=> $param{invoice_num},
						posted_on	=> ( $param{posted_on} ? $param{posted_on} : sprintf('%.4d-%.2d-%.2d', ssi::date( 'posted_on', \%param ) ) ),
						posted		=> 1,
						currency_id => $Order->currency_id(),
						});
			} # end if ! Invoice
			if ( ! $variable{error} ) {
				my $OI = new openprint::Order_Invoice();
				$variable{error} .= $OI->save({ order_id=>$$Order{id}, invoice_id=>$$Invoice{id} });
				$Order->add_log('Invoiced # ' . $Invoice->link_to());
			} # end if
		} # end if
	} # end if action
} # end sub _order_invoices

sub _delete_order_invoice {
	$variable{OI} = openprint::Order_Invoice->find_one( { order_id=>$param{order_id}, invoice_id=>$param{invoice_id} } );
} # end sub _delete_order_invoice

sub _select_category {
}

sub expense_rules {
  _expense_rules();
}
sub _expense_rules {
  ssi::save_params( '/employee/accounting/expense_rules.html', (
      'created_on_start_year','created_on_start_month','created_on_start_day',
      'category_id', 'recipient_id', 'account_id', 'currency_id',
      'name',
    ) );
}

sub expense_rule {
  my $Rule = $variable{Rule} = new openprint::Expense_Rule($param{expense_rule_id});
  return if ! $param{action};

  if ( $param{action} eq 'Save' ) {
    eval {
      JSON::decode_json($param{rules_json});
      JSON::decode_json($param{action_json});
    }; # end eval
    $variable{error} .= $@;
    if ( !$variable{error} ) {
      $variable{error} .= $Rule->save(\%param);
      if ( !$variable{error} ) {
        $variable{ExternalRedirect} = '/employee/accounting/expense_rules.html';
      }
    } else {
      $Rule->set(\%param);
    }
  } elsif ( $param{action} eq 'Copy' ) {
    $Rule = $variable{Rule} = $Rule->copy();
  } elsif ( $param{action} eq 'Delete' ) {
    $Rule->delete();
    $variable{ExternalRedirect} = '/employee/accounting/expense_rules.html';
  }
}

1;
__END__
