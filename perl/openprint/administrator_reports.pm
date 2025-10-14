use strict;
package openprint::administrator_reports;

require openprint::ServiceCategory;
require openprint::order;
require misc;
require sql;
require ssi;

use openprint ();
use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

sub quotes {
  if ($param{btnFunction}) {
	} else {
		ssi::setup_date_select( $r->uri(), 'created_on_start', -30 );
		ssi::save_params( $r->uri(), ( 'company_id',
					( map { 'created_on_start_'.$_ } ( 'year', 'month', 'day' ) ),
					( map { 'created_on_end_'.$_ } ( 'year', 'month', 'day' ) ),
		) );
  }
}

sub _quotes {
}

sub orders {
	if ( $param{btnFunction} eq 'Download in CSV format' ) {
		my @header = ('OrderID', 'Docket', 'Order Date', 'CSR', 'Company Name', 'Status', 'Total', 'Currency');

		my @Orders = openprint::Order->find(
				( $param{company_id} ? ( company_id		=> $param{company_id} ) : () ),
				ssi::date_filter( $r->uri().'?created_on_end', 'created_on <=' ), 
				ssi::date_filter( $r->uri().'?created_on_start', 'created_on >=' ),
				( $param{TotalStart} ? ( 'value >='	   => $param{TotalStart} ) : () ),
				( $param{TotalEnd} ? ( 'value <='		 => $param{TotalEnd} ) : () ),
				( $param{ddmEmployee} ? ( salesrep_id	   => $param{ddmEmployee} ) : () ),
				( $param{ddmStatus} ? ( status			=> $param{ddmStatus} ) : () ),
				( $param{ddmCurrency} ? ( 'currency_id'	   => $param{ddmCurrency} ) : () ),
				);
		my @data;
		my $total = 0;
		foreach my $Order ( @Orders ) {
			push @data, ( 
					$Order->id(), $Order->docket(),
					ssi::format_csv_datetime($Order->created_on()),
					$Order->CSR()->name(),
					$Order->Company()->name(),
					$Order->status(),
					$Order->Currency()->format($Order->total()),
					$Order->Currency()->name(),
					);
			next if $Order->status() eq 'Cancelled';
			$total += $Order->Currency()->convert_from( $Order->total() );
		} # end foreach Order
		push @data, '', '', '', '', '', 'Total:', $openprint::Currency->format($total), $openprint::Currency->name();

		misc::export_csv( $r, $log, \%variable, 'order_report.csv', \@header, \@data );
	} else {
		ssi::setup_date_select( $r->uri(), 'created_on_start', -30 );
		ssi::save_params( $r->uri(), ( 'company_id',
					( map { 'created_on_start_'.$_ } ( 'year', 'month', 'day' ) ),
					( map { 'created_on_end_'.$_ } ( 'year', 'month', 'day' ) ),
		) );
	} # end if
} # end sub orders

sub custom {
	my ( $r, $log, $dbh, $variable ) = @_;

	my $id = $r->param( 'ddmStoredReport' );

	if ( $r->param('btnFunction') eq 'Save' ) {
		my @sql = (
				'strReportName', $r->param('strReportName'),
				'strSQLCommand', $r->param('strSQLCommand'),
				);
		if ( $id ) { # save
			sql::update( $log, $dbh, 'tbl_Reports', ['lngIndex=?', $id], @sql );
		} else { # add
			sql::insert( $log, $dbh, 'tbl_Reports', @sql );
 			$_ = 'SELECT lngIndex FROM tbl_Reports WHERE strReportName=?';
			( $id ) = sql::execute( $log, $dbh, $_, $r->param('strReportName') );
		} # end if
	} elsif ( $r->param('btnFunction') eq 'Delete' ) {
		# perform the record deletion
		sql::execute( $log, $dbh, 'DELETE FROM tbl_Reports WHERE lngIndex=?', $id);
		$id = undef;
	} elsif ( $r->param('btnFunction') eq 'Show Results' ) {
		$_ = 'SELECT strReportName, strSQLCommand FROM tbl_Reports WHERE lngIndex=?';
		my ( $name, $command ) = sql::execute( $log, $dbh, $_, $id );

		my ( $num_columns, @data ) = sql::run_query( $log, $dbh, $command );
		if ( ! @data ) {
			$$variable{RESULTS} = $dbh->errstr;
		} else {
			$$variable{RESULTS} = "<table>";
			while( my @line = splice( @data, 0, $num_columns ) ) {
				for ( my $i = 0; $i < @line; $i += 1 ) {
					$line[$i] =~ s/,//g;
				} # end for
				$$variable{RESULTS} .= "<tr><td>" . join( "</td><td>", @line )."</td></tr>\n";
			} # end for 
			$$variable{RESULTS} .= "</table>\n";
		} # end if

	} elsif ( $r->param('btnFunction') eq 'Download in CSV format' ) {
		$_ = 'SELECT strReportName, strSQLCommand FROM tbl_Reports WHERE lngIndex=?';
		my ( $name, $command ) = sql::execute( $log, $dbh, $_, $id );

		my ( $num_columns, @data ) = sql::run_query( $log, $dbh, $command );

		my @header = splice @data, 0, $num_columns;
		misc::export_csv( $r, $log, $variable, $name.'.csv', \@header, \@data );
	} # end if

	if ( $id ne '' ) {
		# get report to display
		$_ = "SELECT strReportName, strSQLCommand FROM tbl_Reports WHERE lngIndex = '$id'";
		@$variable{'strReportName', 'strSQLCommand'} = sql::execute( $log, $dbh, $_ );
	} # end if

	$_ = "SELECT lngIndex, strReportName FROM tbl_Reports";
	$$variable{ddmStoredReport} = ssi::fill_drop_down( $log, $dbh, $_, $id );

} # end sub custom

sub customer_login {

	ssi::setup_date_select( $r->uri(), 'registered_on_start', -30 );
	_customer_login();
	if ( $param{btnFunction} eq 'Download in CSV format' ) {
		my @header = ( 'Company Name','Contact Name', 'Phone #', 'Email','City','State','Registration Date','Account Rep','# of Projects','Last Project','# of Orders','Last Order', 'Last Order Value');
		my @data;
		foreach my $Company ( @{$variable{Companies}} ) {
			my $User = openprint::User->find_one( company_id=>$$Company{id}, order=>'id' );
			my $CSR = $Company->CSR();
			my @Projects = openprint::Project->find( company_id=>$$Company{id}, order=>'id DESC' );
			my @Orders = openprint::Order->find( company_id=>$$Company{id}, order=>'id DESC' );

			push @data, $Company->name(), $User->name(), $Company->phone(), $User->email(), $Company->city(), $Company->state(),
				 ssi::format_date( $Company->created_on() ),
				 $CSR->name(), scalar @Projects, 
				 ssi::format_date( $Projects[0]->created_on() ),
				 scalar @Orders, 
				 ssi::format_date( $Orders[0]->created_on() ),
				 misc::sum( map { $_->total() } @Orders );
		} # end foreach Company
		misc::export_csv( $r, $log, \%variable, 'customer_login_report.csv', \@header, \@data );
	} # end if	
} 

sub _customer_login {
	ssi::save_params( '/administrator/reports/customer_login.html', ( 
		( map { 'registered_on_start_'.$_ } ( 'year', 'month', 'day' ) ),
		( map { 'registered_on_end_'.$_ } ( 'year', 'month', 'day' ) ),
		( map { 'last_project_start_'.$_ } ( 'year', 'month', 'day' ) ),
		( map { 'last_project_end_'.$_ } ( 'year', 'month', 'day' ) ),
		( map { 'last_order_start_'.$_ } ( 'year', 'month', 'day' ) ),
		( map { 'last_order_end_'.$_ } ( 'year', 'month', 'day' ) ),
		( map { 'last_login_start_'.$_ } ( 'year', 'month', 'day' ) ),
		( map { 'last_login_end_'.$_ } ( 'year', 'month', 'day' ) ),
		'activated', 'salesrep_id',
	) );
	if ( %param ) {
		my %sql = (
				ssi::date_filter( '/administrator/reports/customer_login.html?registered_on_end', 'created_on <=' ), 
				ssi::date_filter( '/administrator/reports/customer_login.html?registered_on_start', 'created_on >=' ),
				ssi::date_filter( '/administrator/reports/customer_login.html?last_ordered_on_end', 'last_ordered_on <=' ), 
				ssi::date_filter( '/administrator/reports/customer_login.html?last_ordered_on_start', 'last_ordered_on >=' ),
				order   =>  'lower(name)',
		);
		if ( $session{'/administrator/reports/customer_login.html?salesrep_id'} eq 'None' ) {
			$sql{'salesrep_id not in'} = [ map { $_->user_id() } openprint::User->find( company_id=>$config{owner_id}, type=>['E','A'], 'usergroup any'=>'Sales' ) ];
		} elsif ( $session{'/administrator/reports/customer_login.html?salesrep_id'} ) {
			$sql{salesrep_id} = $session{'/administrator/reports/customer_login.html?salesrep_id'};
		} # en dif

		$variable{Companies} = [ openprint::Company->find( %sql ) ];
	} # end if	

} # end sub _customer_login

sub CustomerServiceReps {

    ssi::setup_date_select( $r->uri(), 'date_start', -30 );
    ssi::save_params( $r->uri(), (
        ( map { 'date_start_'.$_ } ( 'year', 'month', 'day' ) ),
        ( map { 'date_end_'.$_ } ( 'year', 'month', 'day' ) ),
		) );
	my $date_start = sprintf('%.4d-%.2d-%.2d', @session{map { $r->uri().'?date_start_'.$_ } ( 'year','month','day' ) } ) if Date::Calc::check_date( @session{map { $r->uri().'?date_start_'.$_ } ( 'year','month','day' ) } );
	my $date_end = sprintf('%.4d-%.2d-%.2d', @session{map { $r->uri().'?date_end_'.$_ } ( 'year','month','day' ) } ) if Date::Calc::check_date( @session{map { $r->uri().'?date_end_'.$_ } ( 'year','month','day' ) } );;
 
	$variable{Employees} = openprint::User->dropdown(company_id=>$config{owner_id}, type=>['E','A'],order=>'lower(firstname),lower(lastname)', 'usergroup any'=>'Sales', web_active=>'Y' );
	$variable{ddmEmployees} = ssi::make_drop_down( $variable{Employees}, $param{ddmEmployees} );

	my $estimator = $param{ddmEstimator};
	$variable{ddmEstimatorOptions} = ssi::make_drop_down( $variable{Employees}, $param{ddmEstimator} );

	@{$variable{Currencies}} = sql::execute( $log, $dbh, "SELECT id, Name, Symbol FROM Currencies ORDER BY lower(name)" );

	my %ordered_projects;

	my $query = "SELECT id, strStatus, (SELECT salesrep_id FROM Companies WHERE id=Projects.company_id),
	   ";
	$query .= "(SELECT curSalesPrice FROM Order_Contents, Orders WHERE Orders.id=Order_Contents.OrderIndex AND Order_Contents.lngProjectIndex=Projects.id AND Orders.docket=Projects.lngDocketNumber),";
	$query .= "(SELECT currency_id FROM Orders WHERE Orders.docket=Projects.lngDocketNumber)";

	$query .= " FROM Projects ";
	$query .= "WHERE 1>0 ";
	$query .= "AND dtmcreationdate >= '$date_start 00:00:00'" if $date_start;
	$query .= "AND dtmcreationdate <= '$date_end 23:59:59'" if $date_end;
	$query .= "AND user_id = $estimator\n" if $estimator;
	my @data = sql::execute( $log, $dbh, $query );
	while ( my ( $project_id, $status, $employee, $price, $currency_index ) = splice @data,0,5 ) {
		$variable{'TotalProjectCount'.$employee} += 1;
		$variable{TotalProjectCount} += 1;
		if ( $status eq 'Deleted' ) {
			$variable{'DeletedProjectCount'.$employee} += 1;
			$variable{DeletedProjectCount} += 1;
		} elsif ( $status eq 'uncalculated' ) {
			$variable{'UnfinishedProjectCount'.$employee} += 1;
			$variable{UnfinishedProjectCount} += 1;
		} elsif ( $status eq 'Unordered' ) {
			$variable{'UnorderedProjectCount'.$employee} += 1;
			$variable{UnorderedProjectCount} += 1;
		} else { # ordered
			$variable{'OrderedProjectCount'.$employee} += 1;
			$variable{OrderedProjectCount} += 1;
			$variable{"OrderValue-$employee-$currency_index"} += $price;
			$variable{"OrderValue-$currency_index"} += $price;
		} # end if
	} # end while

} # end sub customer_service_reps

sub order_details {

	my $order_id = $param{order_id};
	$order_id =~ s/\D//g;
	my $Order = new openprint::Order( $order_id );

	if ( $param{btnFunction} eq 'Delete' ) {
		if ( openprint::Payment->find('order_id'=>$order_id ) ) {
			$variable{error} .= "Order $order_id appears to have payments.  Please delete the payments before deleting the order.";
		} else {
			$Order->delete();
			$variable{Redirect} = '/administrator/reports/orders.html';
			return;
		} # en dif
	} elsif ( $param{btnFunction} eq 'Resend' ) {
		$Order->add_log( 'Resent' );
		$Order->send_sales_order( );
	} elsif ( $param{btnFunction} eq 'Pay' ) {
		$Order->pay();
	} elsif ( $param{btnFunction} eq 'Save Payment' ) {

		if ( ( ! $param{Amount} ) or $param{Amount} =~ /[^-\$\d\.]/ ) {
			return misc::error( $log, $dbh, \%variable, 'Invalid Amount', 'Please enter a valid monetary amount.' );
		} # end if

		my $Payment = new openprint::Payment();
		
		my $error = $Payment->save({
				'order_id'		=>	$order_id,
				'recipient_id'	=>	$openprint::User->company_id(), 
				'payor_id'		=>	$Order->company_id(),
				'amount'		=>	$param{Amount},
				'method'		=>	'Manual',
				'currency_id'	=>	$Order->currency_id(),
				'memo'			=>	$param{Description},
				} );
		if ( $error ) {
			return misc::error( $log, $dbh, \%variable, 'Error Saving Payment', $error );
		} # end if

		openprint::order::get_misc( \%variable, $Order );

		if ( $variable{DepositDue} > 0 ) {
			foreach my $project_id ( sql::execute( $log, $dbh, 'SELECT lngProjectIndex FROM Order_Contents WHERE OrderIndex=?', $order_id ) ) {
				sql::update( $log, $dbh, 'Projects', ['id=? AND strStatus=?', $project_id, 'In Prepress'], 'strStatus', 'Pending Deposit' );
				sql::update( $log, $dbh, 'tbl_Project_Contents', [ 'lngProjectIndex=? AND strStatus=?', $project_id, 'Ordered'], 'strStatus', 'Pending Deposit' );
			} # end foreach
		} else {
			$Order->status('In Production') if $Order->status() eq 'Pending Deposit';

			foreach my $project_id ( sql::execute( $log, $dbh, 'SELECT lngProjectIndex FROM Order_Contents WHERE OrderIndex=?', $order_id ) ) {
				sql::update( $log, $dbh, 'Projects', ['id=? AND strStatus=?', $project_id, 'Pending Deposit'], 'strStatus', 'In Prepress' );
				sql::update( $log, $dbh, 'tbl_Project_Contents', ['lngProjectIndex=? AND strStatus=?', $project_id, 'Pending Deposit'], 'strStatus', 'Ordered' );
			} # end foreach
			if ( $variable{AmountPaid} >= $variable{TOTAL} ) {
				$Order->status('Paid') if $Order->status() eq 'Complete';
			} # end if
			$Order->save();
		} # end if
	} elsif ( $param{btnFunction} eq 'Delete Payment' ) {
		$param{payment_id} =~ s/\D//g;
		if ( $param{payment_id} ) {
			my $Payment = new openprint::Payment( $param{payment_id} );
			$Payment->delete();
		} # end if
		$Order->update_status();
	} elsif ( $param{btnFunction} eq 'Cancel' ) {
		$variable{error} .= $Order->cancel();
	} elsif ( $param{btnFunction} eq 'Save' ) {
		$Order->company_id( $param{company_id} );
		$variable{error} .= $Order->save();
		my $Company = new openprint::Company( $param{company_id} );
		if ( ! $$Company{last_order_id} ) {
			$variable{error} .= $Company->save({last_order_id=>$param{company_id}});
		}
	} # end if
	$variable{Order} = $Order;
	openprint::order::display_order( $order_id );
} # end sub display_order

sub uploads {
	require openprint::Upload;
} # end sub uploads

sub yearly_sales {

	ssi::save_params($r->uri(),
			'ordered_on_start_year','ordered_on_start_month','ordered_on_start_day',
			'ordered_on_end_year','ordered_on_end_month','ordered_on_end_day', 
			'salesrep_id' );
	ssi::setup_date_select( $r->uri(), 'ordered_on_start', -365 );
	ssi::setup_date_select( $r->uri(), 'ordered_on_end', '' );

	if ( exists $param{Download} ) {
		my @header = ( 'CSR', 'Company Name', 'Contact Name', 'Contact Phone', 'Contact Email' );
		my @data;
		my @csr_ids;
		if ( ( $session{user_type} ne 'A' ) and ! openprint::usergroup::is_user_in( ['Sales Admin','Reporting'], $session{user_id} ) ) {
			@csr_ids = ( $session{user_id} );
		} elsif ( $param{salesrep_id} ) {
			@csr_ids = ( $param{salesrep_id} );
		} else {
			@csr_ids = map { $_->id() } openprint::User->find( company_id=>$config{owner_id}, type=>['E','A'], usergroup=>'Sales', order=>'lower(firstname),lower(lastname)');
		} # end if

		my ( $y, $m, $d ) = Date::Calc::Today();
		if ( ! $session{$r->uri().'?ordered_on_start_year'} ) {
			$session{$r->uri().'?ordered_on_start_year'} = $y;
		} # end if
		if ( ! $session{$r->uri().'?ordered_on_end_year'} ) {
			$session{$r->uri().'?ordered_on_end_year'} = $y;
		} # end if
		foreach my $year ( $session{$r->uri().'?ordered_on_start_year'} .. $session{$r->uri().'?ordered_on_end_year'} ) {
			push @header, ( 'Orders ' . $year, 'Value ' . $year, 'Payment Cycle ' . $year );
		} # end foreach year
		push @header, 'Last Order';

		foreach my $csr_id ( @csr_ids ) {
			my $CSR = new openprint::User( $csr_id );
			my %totals;

			my @Companies = openprint::Company->find(salesrep_id=>$csr_id, order=>'lower(name)');
			foreach my $Company ( @Companies ) {
				my $Contact = openprint::User->find_one( company_id=>$Company->id(), administrator=>1, web_active=>1, order=>'id');
				$Contact = openprint::User->find_one(company_id=>$Company->id(), web_active=>1, order=>'id') if ! $Contact;
				$Contact = openprint::User->find_one(company_id=>$Company->id(), order=>'id') if ! $Contact;
				$Contact = new openprint::User() if ! $Contact;

				push @data, $CSR->name(), $Company->name(), $Contact->name(), $Contact->phone(), $Contact->email();

				foreach my $year ( $session{$r->uri().'?ordered_on_start_year'} .. $session{$r->uri().'?ordered_on_end_year'} ) {
					my $order_total;
					my $payment_cycle;

					my @Orders = openprint::Order->find( 
							'company_id' => $Company->id(),
							'created_on >=' => sprintf('%.4d-01-01 00:00:00', $year ),
							'created_on <=' => sprintf('%.4d-12-31 23:59:59', $year ),
							'status' => ['Complete','Picked Up', 'Shipped','Waiting For Customer Approval','Order Submitted','In Production','Waiting For Pickup','Re-Opened','Pending Deposit','Paid','Complete' ],
							);
					last if $dbh->errstr();
					foreach my $Order ( @Orders ) {
						$order_total += $Order->Currency()->convert_from( $Order->total() );
						$payment_cycle += $Order->payment_days();
					} # end foreach Order
					$payment_cycle = int( $payment_cycle / scalar @Orders ) if @Orders;
					push @data, (
						 Number::Format::format_number( scalar @Orders ), 
						 openprint::Currency::format( $order_total ),
						 (1*$payment_cycle) . ' days',
						 );
					$totals{$year}[0] += scalar @Orders;
					$totals{$year}[1] += $order_total;
					$totals{$year}[2] += $payment_cycle;
				} # end foreach year
				my $LastOrder = openprint::Order->find_one( 
						company_id => $Company->id(),
						status => ['Complete','Picked Up', 'Shipped','Waiting For Customer Approval','Order Submitted','In Production','Waiting For Pickup','Re-Opened','Pending Deposit','Paid','Complete' ],
						order	=>	$openprint::Order::fields{id}.' DESC',
						);
				push @data, $LastOrder?Date::Format::time2str('%Y-%m-%d', Date::Parse::str2time( $LastOrder->created_on() ) ):'';
				last if $dbh->errstr();
			} # end foreach Company
			
			push @data, ( 'Totals:', '' );
			foreach my $year ( $session{'/administrator/reports/yearly_sales.html?ordered_on_start_year'} .. $session{'/administrator/reports/yearly_sales.html?ordered_on_end_year'} ) {
				push @data, $totals{$year}[0], openprint::Currency::format($totals{$year}[1]), (@Companies ? int($totals{$year}[2]/@Companies) : 0). ' days';
			} # end foreach year
			push @data, '';

		} # end foreach CSR
		misc::export_csv( $r, $log, \%variable, 'yearly_sales.csv', \@header, \@data );
	} # end if Download
} # end sub yearly_sales

sub _yearly_sales {
	ssi::save_params('/administrator/reports/yearly_sales.html',  
			'ordered_on_start_year','ordered_on_start_month','ordered_on_start_day',
			'ordered_on_end_year','ordered_on_end_month','ordered_on_end_day', 
			'salesrep_id' );
} # end sub _yearly_sales

sub bindery {
} # end sub bindery

1;
__END__
