package openprint::employee_reports;
use strict;

require ssi;
require openprint::Company;
require openprint::Project;
require openprint::Quote;
require openprint::Project_Log;
require openprint::Order_Status;
require openprint::OrderedProduct;

require openprint;
use vars qw( $r $log $dbh %variable %session %param %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*session = \%openprint::session;
*param = \%openprint::param;
*variable = \%openprint::variable;
*config = \%openprint::config;

sub project_history {
	my $page = '/employee/reports/project_history.html';
	ssi::save_params($page,
		( map { 'created_on_start_'.$_ } ( 'year','month','day' ) ),
		( map { 'created_on_end_'.$_ } ( 'year','month','day' ) ),
		( map { 'created_on_time_start_'.$_ } ( 'hour','minute' ) ),
		( map { 'created_on_time_end_'.$_ } ( 'hour','minute' ) ),
		( map { 'status_on_start_'.$_ } ( 'year','month','day','hour','minute' ) ),
		( map { 'status_on_end_'.$_ } ( 'year','month','day','hour','minute' ) ),
		'status', 'previous_status', 'company_id', 'Estimator', 'CSR', 'reprint', 'type_id','press_id',
	);
	ssi::setup_date_select( $page, 'created_on_start', -31 );
	ssi::setup_date_select( $page, 'created_on_end', '' );
}
sub _project_history_results {
	my $page = '/employee/reports/project_history.html';
	ssi::save_params($page,
		( map { 'created_on_start_'.$_ } ( 'year','month','day' ) ),
		( map { 'created_on_end_'.$_ } ( 'year','month','day' ) ),
		( map { 'created_on_time_start_'.$_ } ( 'hour','minute' ) ),
		( map { 'created_on_time_end_'.$_ } ( 'hour','minute' ) ),
		( map { 'status_on_start_'.$_ } ( 'year','month','day','hour','minute' ) ),
		( map { 'status_on_end_'.$_ } ( 'year','month','day','hour','minute' ) ),
		'status', 'previous_status', 'company_id', 'Estimator', 'CSR', 'reprint', 'type_id','press_id',
	);
	my %parameters; 
	if ( ( $session{user_type} ne 'A' ) and ! openprint::usergroup::is_user_in( ['Sales Admin','Reporting'], $session{user_id} ) ) {
		$parameters{or} = {
			salesrep_id => $session{user_id},
			id					=> $openprint::User->company_id(),
		};
	} elsif ( $session{$page.'?CSR'} ) {
		$parameters{salesrep_id} = $session{$page.'?CSR'};
	} # end if
	#$parameters{order} = 'lower(strcompanyname)';
	$parameters{'last_project_id is null'}=0;
	my @Companies = openprint::Company->find( %parameters );
	my %companies = map { int($_->id()), $_->name() } @Companies;
	my @company_ids = map { $_->id() } @Companies;
	openprint::User->find(company_id=>\@company_ids);

	my %filters = (
			ssi::date_filter( $page.'?created_on_start', 'created_on >=' ),
			ssi::date_filter( $page.'?created_on_end', 'created_on <=' ),
			( $session{$page.'?type_id'} ? ( type_id => $session{$page.'?type_id'} ) : () ),
			( 
			 ( $session{$page.'?created_on_time_start_hour'} or $session{$page.'?created_on_time_start_minute'} ) ? (			
				 'created_on::time >=' => sprintf('%.2d:%.2d', @session{$page.'?created_on_time_start_hour',$page.'?created_on_time_start_minute'} ) ) : () ),
			( 
			 ( $session{$page.'?created_on_time_end_hour'} or $session{$page.'?created_on_time_end_minute'} ) ? (			
				 'created_on::time <=' => sprintf('%.2d:%.2d', @session{$page.'?created_on_time_end_hour',$page.'?created_on_time_end_minute'} ) ) : () ),
			( $session{$page.'?status'} ? ( status => [ split(',', $session{$page.'?status'} ) ] ) : () ),
			( $session{$page.'?value_start'} ? ( 'value >=' => $session{$page.'value_start'} ) : () ),
			( $session{$page.'?value_end'} ? ( 'value <=' => $session{$page.'value_end'} ) : () ),
			company_id	=> ( ( $session{$page.'?company_id'} and ( exists $companies{$session{$page.'?company_id'}} ) ) ? $session{$page.'?company_id'} : \@company_ids ),
			( $session{$page.'reprint'} ? ( reprint	=> $session{$page.'?reprint'} ) : () ),
			order		=> 'id',
			);
	if ( $session{$page.'?Estimator'} ) {
			$filters{user_id} = $session{$page.'?Estimator'} eq 'Non Employee' ? q{NOT IN (SELECT id FROM Users WHERE type IN ('E','A') AND id IN (SELECT user_id FROM users_in_usergroups WHERE usergroup_id = (SELECT id FROM usergroups WHERE name='Sales')))} : $session{$page.'?Estimator'};
	} # end if

	if ( $session{$page.'?company_id'} and ! exists $companies{$session{$page.'?company_id'}} ) {
		$variable{error} .= 'Specified company is not allowed.<br/>';
	} # end if

	if ( %companies ) {
		my $Press = new openprint::Equipment($param{press_id} ) if $param{press_id};
		@{$variable{Projects}} = ();
		foreach my $Project ( openprint::Project->find( %filters ) ) {
			if ( $param{previous_status} and (
						Date::Calc::check_date( @param{'status_on_start_year','status_on_start_month','status_on_start_day'} ) or 
						Date::Calc::check_date( @param{'status_on_end_year','status_on_end_month','status_on_end_day'} )
						) ) {
				my @statuses = split(',', $param{previous_status} );
				my $keep = 0;
				if ( sets::isin( 'Waiting For QA Approval', \@statuses ) ) {
					$keep = 1 if openprint::Project_Log->find(
							ssi::date_filter( '/employee/reports/project_history.html?status_on_start', 'created_on >=' ),
							ssi::date_filter( '/employee/reports/project_history.html?status_on_end', 'created_on <=' ),
							project_id=>$Project->id(),
							'description like'=>'Marked Proofs Waiting For QA Approval%'
							);
				} # end if
				if ( (!$keep) and sets::isin( 'Waiting For Customer Approval', \@statuses ) ) {
					$keep = 1 if openprint::Project_Log->find(
							ssi::date_filter( '/employee/reports/project_history.html?status_on_start', 'created_on >=' ),
							ssi::date_filter( '/employee/reports/project_history.html?status_on_end', 'created_on <=' ),
							project_id=>$Project->id(),
							'description like'=>'Marked Proofs Waiting For Customer Approval%'
							);
				} # end if
				if ( (!$keep) and sets::isin( 'Approved', \@statuses ) ) {
					$keep = 1 if openprint::Project_Log->find(
							ssi::date_filter( '/employee/reports/project_history.html?status_on_start', 'created_on >=' ),
							ssi::date_filter( '/employee/reports/project_history.html?status_on_end', 'created_on <=' ),
							project_id =>$Project->id(),
							'description in'	=>	[ map { 'Marked ' . $_ } @statuses ],
							);
				} # end if
				next if ! $keep;
			} # end if previous_status

			if ( $param{press_id} ) {
				my $on_press = 0;
				foreach my $sig_id ( $Project->signatures() ) {
					my $sig_specs = openprint::service::get_specs_ref($Project, $sig_id);
					if ( ! $$sig_specs{UsePress} ) {
						$$sig_specs{UsePress} = $$sig_specs{'ddmPress'.$Project->ordered_quantity_index()};
					} # end if
					if ( $$sig_specs{UsePress} eq $$Press{strid} ) {
						$on_press = 1;
					} # end if
					last if $on_press;
				} # end foreach sig
				next if ! $on_press;
			} # end if press_id

			push @{$variable{Projects}}, $Project;
		} # end foreach Project
	} else {
		@{$variable{Projects}} = ();
		return 'There were no companies to filter on.<br/>';
	} # end if
	%{$variable{Companies}} = %companies;
	$variable{ReportCount} = 0;
	$variable{OrderedCount} = 0;
	return '';
} # end sub _project_history_results

sub project_performance {
	ssi::setup_date_select( '/employee/reports/project_performance.html', 'created_on_start', -31 );
	ssi::setup_date_select( '/employee/reports/project_performance.html', 'created_on_end', '' );
	_project_performance();
} # end sub _project_history_results

sub _project_performance {
	my $page = '/employee/reports/project_performance.html';

	ssi::save_params($page, (
		( map { 'created_on_start_'.$_ } ( 'year','month','day' ) ),
		( map { 'created_on_end_'.$_ } ( 'year','month','day' ) ),
		'company_id', 'estimator', 'estimator_exclude', 'CSR',
	) );
	my %parameters; 
	if ( $session{user_type} ne 'A' and ! openprint::usergroup::is_user_in( ['Sales Admin','Reporting'], $session{user_id} ) ) {
		$parameters{salesrep_id} = $session{user_id};
		$parameters{or} = "id=(SELECT company_id FROM Users WHERE id=$session{user_id})";
	} elsif ( $session{$page.'?CSR'} ) {
		$parameters{salesrep_id} = $session{$page.'?CSR'};
	} # end if
	#$parameters{order} = 'lower(strcompanyname)';
	my @Companies = openprint::Company->find( %parameters );
	my %companies = map { $_->id(), $_->name() } @Companies;
	my @company_ids = map { $_->id() } @Companies;
	openprint::User->find(company_id=>\@company_ids);
	my %filters = (
			ssi::date_filter( $page.'?created_on_start', 'created_on >=' ),
			ssi::date_filter( $page.'?created_on_end', 'created_on <=' ),
			( $session{$page.'?estimator_exclude'} ? ( 'user_id not in'	=> [ split(',', $session{$page.'?estimator_exclude'} ) ] ) : () ),
			company_id => ( ( $session{$page.'?company_id'} and ( exists $companies{$session{$page.'?company_id'}} ) ) ? $session{$page.'?company_id'} : \@company_ids ),
			order	=> 'id',
	);

	if ( $session{$page.'?estimator'} ) {
		$filters{user_id} = ($session{$page.'?estimator'} eq 'Non Employee' ? q{NOT IN (SELECT id FROM users WHERE type IN ('E','A') AND id IN (SELECT user_id FROM users_in_usergroups WHERE usergroup_id = (SELECT id FROM usergroups WHERE name='Sales')))} : $session{$page.'?estimator'}),
	} # end if

	if ( $session{$page.'?company_id'} and ! exists $companies{$session{$page.'?company_id'}} ) {
		$variable{error} .= 'Specified company is not allowed.<br/>';
	} # end if

	if ( %companies ) {
		$variable{Projects} = [ openprint::Project->find( %filters ) ];
	} else {
		@{$variable{Projects}} = ();
		$variable{information} .= 'There were no companies to filter on.<br/>';
	} # end if
	%{$variable{Companies}} = %companies;
} # end sub _project_performance

sub lost_orders {
	ssi::setup_date_select($r->uri(), 'created_on_start', -31);
	ssi::setup_date_select($r->uri(), 'created_on_end', '');
	_lost_orders();
}

sub _lost_orders {
	my $uri = '/employee/reports/lost_orders.html';
	ssi::save_params( $uri,
			( map { 'created_on_start_'.$_ } ( 'year','month','day' ) ),
			( map { 'created_on_end_'.$_ } ( 'year','month','day' ) ),
			'company_id','salesrep_id',
			);
	my %parameters;
	if ( ( $session{user_type} ne 'A' ) and ! openprint::usergroup::is_user_in( ['Sales Admin','Reporting','Accounting'], $session{user_id} ) ) {
		$parameters{or} = {
			company_id  => $openprint::User->company_id(),
			salesrep_id => $session{user_id},
		};
	} elsif ( $param{salesrep_id} ) {
		$parameters{salesrep_id} = $session{$uri.'?salesrep_id'};
	} # end if
	$parameters{id} = $session{$uri.'?company_id'} if $session{$uri.'?company_id'};
	$parameters{'last_ordered_on is null'}=0;
	my @Companies = openprint::Company->find( %parameters ) if (keys %parameters) > 1;
	my %companies = map { $_->id(), $_->name() } @Companies;

	$variable{Orders} = [];

	my @Orders = openprint::Order->find(
			( @Companies ? ( company_id => [ keys %companies ] ) : () ),
			( $session{$uri.'?salesrep_id'} ? ( salesrep_id => $session{$uri.'?salesrep_id'} ) : () ),
			ssi::date_filter( $uri.'?created_on_start', 'created_on >=' ),
			ssi::date_filter( $uri.'?created_on_end', 'created_on <=' ),
			order=>'id ASC',
			);
	my %OrdersByDocket = map { $$_{docket} => $_ } @Orders;
	foreach my $docket ( $Orders[0]->docket() .. $Orders[@Orders-1]->docket() ) {
		if ( ! $OrdersByDocket{$docket} ) {
			push @{$variable{Orders}}, $docket;

			# Get previous
			$_ = $docket - 1;
			while ( $_ and  ! $OrdersByDocket{$_} ) {
				$_ -= 1;
			}
			push @{$variable{Orders}}, $OrdersByDocket{$_};

			# Get Next
			$_ = $docket + 1;
			while ( $_ and  ! $OrdersByDocket{$_} ) {
				$_ += 1;
			}
			push @{$variable{Orders}}, $OrdersByDocket{$_};
		}
	}
}

sub order_history {

	_order_history_results();
	$session{$r->uri().'?status'} = join(',', map { $_->id() } openprint::Order_Status->find() ) if ! $session{$r->uri().'?status'};
	ssi::setup_date_select( $r->uri(), 'created_on_start', -31 );
	ssi::setup_date_select( $r->uri(), 'created_on_end', '' );
	if ( ! $session{$r->uri().'?servicetype_category_id'} ) {
		$session{$r->uri().'?servicetype_category_id'} = join(',',map { $$_{id} } @{$variable{Categories}});
	}
	if ( ! $session{$r->uri().'?servicetype_id'} ) {
		$session{$r->uri().'?servicetype_id'} = join(',',map { $$_{id} } @{$variable{ServiceTypes}});
	}

	if ( $param{action} eq 'download' ) {
		require Number::Format;
		my $Formatter = new Number::Format(
				-decimal_digits     =>  2,
				-int_curr_symbol    =>  $openprint::Currency->symbol(),
				-thousands_sep      =>  '',
				);

		my @servicetype_ids = split(',',$session{$r->uri().'?servicetype_id'} );
		my %ServiceTypesById = map { $$_{id} => $_ } @{$variable{ServiceTypes}};

		my @Header = ( 'OrderID', 'Docket', 'Invoice', 'Company',
				'Date Ordered', 'Date Printed', 'Date Shipped', 'Date Invoiced', 'Status', 'Subtotal', 
        ( map { (exists $variable{tax_totals}{$$_{id}}) ?
          sprintf('%s (%d%)', $_->name(), $_->rate() ) : () } @{$variable{Taxes}} ),
				'Total', 'Commission', 'Credit Card Fee',
				map { $ServiceTypesById{$_}->description() } @servicetype_ids );
		my @Data = ();
		my %service_totals;
		my $order_total = 0;
		my $subtotal_total = 0;
		my $csr_commission_total = 0;
		my $credit_card_fee_total = 0;
		foreach my $Order ( @{$variable{Orders}} ) {
			my $Currency = $Order->Currency();
			foreach my $Project ( $Order->Projects() ) {

				my %totals;
				my @Services = openprint::Project_Service->find(project_id=>$$Project{id}, servicetype_id=>\@servicetype_ids);
				foreach my $Service ( @Services ) {
					$totals{$$Service{servicetype_id}} += $Currency->convert_from($Service->ordered_price());
				}

				push @Data, (
						$Order->id(), $Order->docket(),
						join(',', map { $_->Invoice()->num() } $Order->Invoices()),
						$Order->Company()->name(),
						ssi::format_csv_date($Order->created_on()),
						ssi::format_csv_date($Project->printed_on()),
						ssi::format_csv_date($Project->shipped_on()),
						ssi::format_csv_date($Order->invoiced_on()),
						$Order->status(),
						$Formatter->format_number($Currency->convert_from($Order->subtotal()), 2),
						( map { exists $variable{tax_totals}{$_->id()} ?
								$Formatter->format_number($Currency->convert_from($Order->Tax($_)->amount()), 2) : () } @{$variable{Taxes}} ),
						$Formatter->format_number($Currency->convert_from($Order->total()), 2),
						$Formatter->format_number($Currency->convert_from($Order->csr_commission()), 2),
						$Formatter->format_number($Currency->convert_from($Order->credit_card_fee()), 2),
				);
				foreach my $servicetype_id ( @servicetype_ids ) {
					my $price = $totals{$servicetype_id};
					push @Data, $price;
					$service_totals{$servicetype_id} += $price;
				}
			} # end foreach Project
			$subtotal_total += $Currency->convert_from($Order->subtotal());
			$order_total += $Currency->convert_from($Order->total());
			$csr_commission_total += $Currency->convert_from($Order->csr_commission());
			$credit_card_fee_total += $Currency->convert_from($Order->credit_card_fee());
		} # end foreach Order
		push @Data, '','','','','','','','','Totals',
				 $Formatter->format_number($subtotal_total, 2),
				 ( map { exists $variable{tax_totals}{$_->id()} ?
							 $Formatter->format_number($variable{tax_totals}{$_->id()}, 2)
							 : () } @{$variable{Taxes}} ),
				 $Formatter->format_number($order_total, 2),
				 $Formatter->format_number($csr_commission_total, 2),
				 $Formatter->format_number($credit_card_fee_total, 2),
				 map { $service_totals{$_} } @servicetype_ids;

		misc::export_csv($r, $log, \%variable, 'order_history_report.csv', \@Header,\@Data);	
	} # end if
} # end sub order_history

sub _order_history_results {
	my $uri = '/employee/reports/order_history.html';
	ssi::save_params( $uri,
		( map { 'created_on_start_'.$_ } ( 'year','month','day' ) ),
		( map { 'created_on_end_'.$_ } ( 'year','month','day' ) ),
		( map { 'printed_on_start_'.$_ } ( 'year','month','day' ) ),
		( map { 'printed_on_end_'.$_ } ( 'year','month','day' ) ),
		'status', 'company_id', 'CSR', 'reprint', 'currency_id', 'total_start', 'total_end',
		'servicetype_id', 'servicetype_category_id', 'pos', 'fsc',
	);

	my @ServiceTypes = @{$variable{ServiceTypes}} = openprint::ServiceType->find(order=>'lower(description)');
	@{$variable{Categories}} = openprint::ServiceType_Category->find(order=>'lower(name)');
	%{$variable{ServiceTypesByCategory}} = {};
	foreach my $Category ( @{$variable{Categories}} ) {
		$variable{ServiceTypesByCategory}{$$Category{id}} = [ map { $$_{category_id} == $$Category{id}?$_:() } @ServiceTypes ];
	}

	if ( %param ) {
		delete $session{$uri.'?servicetype_id'} if ! $param{servicetype_id};
		delete $session{$uri.'?servicetype_category_id'} if ! $param{servicetype_category_id};
		my %parameters;
		if ( ( $session{user_type} ne 'A' ) and
				! openprint::usergroup::is_user_in( ['Sales Admin','Reporting','Accounting'], $session{user_id} ) ) {
			$parameters{or} = {
					company_id	=> $openprint::User->company_id(),
					salesrep_id => $session{user_id},
					user_id			=> $session{user_id},
			};
		#} elsif ( $param{CSR} ) {
			#$parameters{salesrep_id} = $session{$uri.'?CSR'};
		} # end if
		$parameters{'last_ordered_on is null'} = 0;
		my @Companies = openprint::Company->find(%parameters) if keys %parameters;
		my %companies = map { $_->id(), $_->name() } @Companies;
		my @servicetype_ids = split(',', $session{$uri.'?servicetype_id'} );

		$variable{Orders} = [];

		$variable{Taxes} = [ openprint::Tax->find(
				ssi::date_filter($uri.'?created_on_end', 'period_start null_or_<='),
				ssi::date_filter($uri.'?created_on_start', 'period_end null_or_>='),
				order   =>  'period_start,name',
				) ];
	  # Companies should always have 1 because we include our own, so if empty, then we must be an admin.

		my @Orders = openprint::Order->find(
				( @Companies ? (
												company_id => (
													($session{$uri.'?company_id'} and $companies{$session{$uri.'?company_id'}})
													?
													$session{$uri.'?company_id'} : [ keys %companies ] ) 
											 ) : () ),
			( $session{$uri.'?CSR'} ? ( salesrep_id	=> $session{$uri.'?CSR'} ) : () ),
			ssi::date_filter( $uri.'?created_on_start', 'created_on >=' ),
			ssi::date_filter( $uri.'?created_on_end', 'created_on <=' ),
			( $session{$uri.'?status'} ? ( status_id => [ split(',', $session{$uri.'?status'} ) ] ) : () ),
			( $session{$uri.'?total_start'} ne '' ? ( 'total >=' => $session{$uri.'?total_start'} ) : () ),
			( $session{$uri.'?total_end'} ne '' ? ( 'total <=' => $session{$uri.'?total_end'} ) : () ),
			( $session{$uri.'?currency_id'} ? ( currency_id=>$session{$uri.'?currency_id'} ) : () ),
			order => ($param{order} ? $openprint::Order::fields{$param{order}} : 'id'),
		);
		if ( ! @Orders ) {
			$variable{Orders} = \@Orders;
			return;
		}
		my @order_ids = map { $$_{id} } @Orders;

		my %Order_Taxes = misc::make_hash_from_array('order_id',
				openprint::Order_Tax->find(order_id=>\@order_ids));

		my @Projects = openprint::Project->find(order_id=>\@order_ids);
		my %Projects_By_OrderId = misc::make_hash_from_array('order_id', @Projects);

		my %Services;
		if ( @servicetype_ids and ( @servicetype_ids != @ServiceTypes ) ) {
			%Services = misc::make_hash_from_array('project_id',
					openprint::Project_Service->find(
						project_id      => [ map { $$_{id} } @Projects ],
						servicetype_id  => \@servicetype_ids,
						) );
		}

		my %Invoices_By_OrderId = misc::make_hash_from_array('order_id',
				openprint::Order_Invoice->find(order_id=>\@order_ids));
		my %Ordered_Products_By_OrderId = misc::make_hash_from_array('order_id',
				openprint::OrderedProduct->find(order_id=>\@order_ids));

		my @invoice_ids = map { $$_{invoice_id} } ( map { @{$Invoices_By_OrderId{$_}} } keys %Invoices_By_OrderId );

		openprint::Invoice->find(id=>\@invoice_ids) if @invoice_ids;

		foreach my $Order ( @Orders ) {
			$$Order{Projects} = $Projects_By_OrderId{$$Order{id}};
			$$Order{Products} = $Ordered_Products_By_OrderId{$$Order{id}};
			$$Order{Invoices} = $Invoices_By_OrderId{$$Order{id}};
			$$Order{Taxes} = $Order_Taxes{$$Order{id}};
			if ( $param{reprint} ) {
				my $reprint = 0;
				foreach my $Project ( $Order->Projects() ) {
					if ( $Project->reprint() eq 'Y' ) {
						$reprint=1;
						last;
					} # end if
				} # end foreach Project
				next if ( $param{reprint} eq 'Y' ) and ! $reprint;
				next if ( $param{reprint} eq 'N' ) and $reprint;
			} # end if reprint

			if ( $param{fsc} ne '' ) {
				next if ( $param{fsc} == 1 ) and ! $Order->is_fsc();
				next if ( $param{fsc} == 0 ) and $Order->is_fsc();
			}

			my @printed_on_start = map{ @session{$uri.'?printed_on_start_'.$_} } ( 'year','month','day' );
			my $printed_on_start = join('-', @printed_on_start) if Date::Calc::check_date(@printed_on_start);
			my $printed_on_start_seconds = Date::Parse::str2time($printed_on_start) if $printed_on_start;

			my @printed_on_end = map{ @session{$uri.'?printed_on_end_'.$_} } ( 'year','month','day' );
			my $printed_on_end = join('-', @printed_on_end) if Date::Calc::check_date(@printed_on_end);
			my $printed_on_end_seconds = Date::Parse::str2time($printed_on_end) if $printed_on_end;

			if ( $printed_on_start or $printed_on_end ) {
				my $keep = 0;
				foreach my $Project ( $Order->Projects() ) {
					my $printed_on = $Project->printed_on();
					my $printed_on_seconds = Date::Parse::str2time( $printed_on );
					next if ! $printed_on;
					if (
							( (!$printed_on_start_seconds) or ( $printed_on_seconds > $printed_on_start_seconds ) )
							and
							( (!$printed_on_end_seconds) or ( $printed_on_seconds < $printed_on_end_seconds ) )
						 ) {
						$keep = 1;
						last;
					}
				}
				next if ! $keep;
			} # end if printed_on_start or printed_on_end
			
			if ( $param{press_id} ) {
				my $Press = new openprint::Equipment( $param{press_id} );
				my $on_press = 0;
				foreach my $Project ( $Order->Projects() ) {
					foreach my $sig_id ( $Project->signatures() ) {
						my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
						if ( ! $$sig_specs{UsePress} ) {
							$$sig_specs{UsePress} = $$sig_specs{'ddmPress'.$Project->ordered_quantity_index()};
						} # end if
						if ( $$sig_specs{UsePress} eq $$Press{strid} ) {
							$on_press = 1;
						} # end if
						last if $on_press;
					} # end foreach sig
					last if $on_press;
				} # end foreach Project
				next if ! $on_press;
			} # end if press_id

			if ( @servicetype_ids and ( @servicetype_ids != @ServiceTypes ) ) {
				
				next if (!$Order->Projects()) or !openprint::Project_Service->find(
						project_id			=> [ map { $$_{id} } $Order->Projects() ],
						servicetype_id	=> \@servicetype_ids,
						);
			}

			push @{$variable{Orders}}, $Order;

			foreach my $Tax ( @{$variable{Taxes}} ) {
				my $OT = $Order->Tax($Tax);
				next if ! $$OT{tax_id};
				$variable{tax_totals}{$$Tax{id}} += $Order->Currency()->convert_from($OT->amount());
			} # end foreach Tax
		} # end foreach Order
		$variable{Companies} = \%companies;
	} # end if param
} # end sub _order_history

sub services {

	_services();
	ssi::setup_date_select( $r->uri(), 'created_on_start', -31 );
	ssi::setup_date_select( $r->uri(), 'created_on_end', '' );
	if ( ! $session{$r->uri().'?servicetype_category_id'} ) {
		$session{$r->uri().'?servicetype_category_id'} = join(',',map { $$_{id} } @{$variable{Categories}});
	}

	if ( $param{action} eq 'download' ) {
		my @Header = ( 'OrderID', 'Docket', 'Company', 'Ordered On', 'Order Total' );
		my @Data = ();

		my %servicetypes = map{ $_=>$_ } split(',', $session{$r->uri().'?servicetype_id'});
    my %category_ids = map{ $_=>$_ } split(',', $session{$r->uri().'?servicetype_category_id'});

    # If a service is clicked, but not it's category then add the category
    foreach my $ServiceType ( @{$variable{ServiceTypes}} ) {
      if ( $servicetypes{$$ServiceType{id}} and ! $category_ids{$$ServiceType{category_id}} ) {
        $category_ids{$$ServiceType{category_id}} = $$ServiceType{category_id};
      }
    }
    my @Categories = map { $category_ids{$$_{id}} ? $_ : () } @{$variable{Categories}};
		push @Header, map { $$_{name} . ' Service ', $$_{name} . ' Price' } @Categories;

		foreach my $Order ( @{$variable{Orders}} ) {
			foreach my $Project ( $Order->Projects() ) {


				my %category_data;
				my $rows = 1;

				my @Services = $Project->Services();
				my $Services_By_ServiceType = misc::make_hash_from_array('servicetype_id', @Services );

				for( my $category_index = 0; $category_index < @Categories; $category_index += 1 ) {
					my $Category = $Categories[$category_index];
					my ( @service_names, @service_prices );
					$category_data{$$Category{id}} = [];

					foreach my $ServiceType ( @{$variable{ServiceTypesByCategory}{$$Category{id}}} ) {
						next if ! $servicetypes{$$ServiceType{id}};
						if ( ! $$Services_By_ServiceType{$$ServiceType{id}} ) {
							#push @Data, '', '';
							next;
						}

					
						if ( @{$$Services_By_ServiceType{$$ServiceType{id}}} > $rows ) {
							$rows = @{$$Services_By_ServiceType{$$ServiceType{id}}};
						}

						foreach my $Service ( @{$$Services_By_ServiceType{$$ServiceType{id}}} ) {

							my $specs = $Service->specs();

							my $price = $openprint::Currency->format(
									$Order->Currency()->convert_from(
										$Service->ordered_price() ));
							push @{$category_data{$$Category{id}}}, $$ServiceType{description}.' '.$$specs{ServiceName}, $price;
						} # end foreach Service
					} # end foreach ServiceType

				} # end foreach category
				foreach ( 1 .. $rows ) {
					push @Data, ( $$Order{id}, $$Order{docket},
							$Order->Company()->name(), 
							$Order->created_on(),
							$Order->Currency()->format_price($Project->ordered_price()),
							);
					foreach my $Category ( @Categories ) {

						if ( @{$category_data{$$Category{id}}} ) {
							push @Data, shift @{$category_data{$$Category{id}}}, shift @{$category_data{$$Category{id}}};
						} else {
							push @Data, ( '', '' );
						}
					} # end foreach category
				} # end foreach row

			} # end foreach Project
		} # end foreach Order

		misc::export_csv( $r, $log, \%variable, 'services_report.csv', \@Header,\@Data );	
	} # end if
} # end sub services

sub _services {
	my $uri = '/employee/reports/services.html';
	ssi::save_params($uri,
			( map { 'created_on_start_'.$_ } ( 'year','month','day' ) ),
			( map { 'created_on_end_'.$_ } ( 'year','month','day' ) ),
			'company_id', 'CSR', 'servicetype_category_id','servicetype_id',
			);
	my @ServiceTypes = @{$variable{ServiceTypes}} = openprint::ServiceType->find(order=>'lower(description)');
	@{$variable{Categories}} = openprint::ServiceType_Category->find( order=>'lower(name)' );
	%{$variable{ServiceTypesByCategory}} = {};
	foreach my $Category ( @{$variable{Categories}} ) {
		$variable{ServiceTypesByCategory}{$$Category{id}} = [ map { $$_{category_id} == $$Category{id}?$_:() } @ServiceTypes ];
	}

	if ( %param ) {
		delete $session{$uri.'?servicetype_id'} if ! $param{servicetype_id};
		delete $session{$uri.'?servicetype_category_id'} if ! $param{servicetype_category_id};

		my %parameters; 
		if ( ( $session{user_type} ne 'A' ) and ! openprint::usergroup::is_user_in( ['Sales Admin','Reporting','Accounting'], $session{user_id} ) ) {
			$parameters{or} = {
				id					=> $openprint::User->company_id(),
				salesrep_id => $session{user_id},
			};
		} elsif ( $param{CSR} ) {
			$parameters{salesrep_id} = $session{$uri.'?CSR'};
		} # end if
		$parameters{id} = $session{$uri.'?company_id'} if $session{$uri.'?company_id'};
		$parameters{'last_ordered_on is null'} = 0;
		my @Companies = openprint::Company->find( %parameters ) if (keys %parameters) > 1;
		my %companies = map { $_->id(), $_->name() } @Companies;
		my @servicetype_ids = split(',',$session{$uri.'?servicetype_id'});

		$variable{Orders} = [];
		return if (keys %parameters > 1 ) and !@Companies;

		my @Orders = openprint::Order->find(
					( @Companies ? ( company_id => [ keys %companies ] ) : () ),
					( $session{$uri.'?CSR'} ? ( salesrep_id	=> $session{$uri.'?CSR'} ) : () ),
					ssi::date_filter( $uri.'?created_on_start', 'created_on >=' ),
					ssi::date_filter( $uri.'?created_on_end', 'created_on <=' ),
					order => ($param{order} ? $openprint::Order::fields{$param{order}} : 'id'),
					);
		return if ! @Orders;

		my @dockets = map { $$_{docket} } @Orders;
		my @Projects = openprint::Project->find(
				docket => \@dockets,
				( 
				 ( @servicetype_ids and ( @servicetype_ids != @ServiceTypes ) ) ?
				 ( 'servicetype_id	&&'	=> [ split(',',$session{$uri.'?servicetype_id'}) ] ) 
				 : () ),
				);
		my @project_ids = map { $$_{id} } @Projects;

		my @Services = openprint::Project_Service->find( project_id=>\@project_ids );
		my %Services;
		foreach my $Service ( @Services ) {
			$Services{$$Service{project_id}} = [] if ! $Services{$$Service{project_id}};
			push @{$Services{$$Service{project_id}}}, $Service;
		}

		my %Projects;
		foreach my $Project ( @Projects ) {
			$Projects{$$Project{docket}} = [] if ! $Projects{$$Project{docket}};
			push @{$Projects{$$Project{docket}}}, $Project;
			$Project->Services($Services{$$Project{id}});
		}

		foreach my $Order ( @Orders ) {
			next if ! $Projects{$$Order{docket}};
			$Order->Projects( $Projects{$$Order{docket}} );
			push @{$variable{Orders}}, $Order;
		} # end foreach Order
		$variable{Companies} = \%companies;
	} # end if param
} # end sub _services

sub order_performance {
	ssi::setup_date_select( '/employee/reports/order_performance.html', 'created_on_start', -31 );
	ssi::setup_date_select( '/employee/reports/order_performance.html', 'created_on_end', '' );
	_order_performance();
} # end sub order_performance

sub _order_performance {

	my $uri = '/employee/reports/order_performance.html';
	ssi::save_params($uri,
		( map { 'created_on_start_'.$_ } ( 'year','month','day' ) ),
		( map { 'created_on_end_'.$_ } ( 'year','month','day' ) ),
		'company_id', 'status', 'press_id', 'CSR', 'reprint', 'pos',
	);
	my %parameters; 
	if ( ( $session{user_type} ne 'A' ) and ! openprint::usergroup::is_user_in( ['Sales Admin','Reporting','Accounting'], $session{user_id} ) ) {
		$parameters{or} = {
			id=>$openprint::User->company_id(),
			salesrep_id => $session{user_id},
		};
	} elsif ( $session{$uri.'?CSR'} ) {
		$parameters{salesrep_id} = $session{$uri.'?CSR'};
	} # end if
	$parameters{id} = $session{$uri.'?company_id'} if $session{$uri.'?company_id'};
	my @Companies = openprint::Company->find( %parameters ) if %parameters;
	my %companies = map { int($_->id()), $_->name() } @Companies;
	@{$variable{Orders}} = ();
	if (%companies or ( ! %parameters ) ) {
		foreach my $Order ( openprint::Order->find(
			( ( $session{$uri.'?company_id'} or %companies ) ? (
			company_id => ( ($session{$uri.'?company_id'} and exists $companies{$session{$uri.'?company_id'}} ) ? $session{$uri.'?company_id'} : [ keys %companies ] ) ) : () ),
			ssi::date_filter( $uri.'?created_on_start', 'created_on >=' ),
			ssi::date_filter( $uri.'?created_on_end', 'created_on <=' ),
			( $session{$uri.'?status'} ? (
				status => [ split(',', $session{$uri.'?status'} ) ],
				) : () ),
			order => ($param{order} ? $param{order} : 'id'),
			( $param{Estimator} ? ( 
								   user_id => ($param{Estimator} eq 'Non Employee' ? q{NOT IN (SELECT id FROM Users WHERE type IN ('E','A') AND id IN (SELECT user_id FROM users_in_usergroups WHERE usergroup_id = (SELECT id FROM usergroups WHERE name='Sales')))} : $param{Estimator}) ) : () ),
		) ) {
			if ( $session{$uri.'?reprint'} ) {
				my $reprint = 0;
				foreach my $Project ( $Order->Projects() ) {
					if ( $Project->reprint() eq 'Y' ) {
						$reprint=1;
						last;
					} # end if
				} # end foreach Project
				next if ( $session{$uri.'?reprint'} eq 'Y' ) and ! $reprint;
				next if ( $session{$uri.'?reprint'} eq 'N' ) and $reprint;
			} # end if reprint
			if ( $session{$uri.'?press_id'} ) {
				my $Press = new openprint::Equipment( $session{$uri.'?press_id'} );
				my $on_press = 0;
				foreach my $Project ( $Order->Projects() ) {
					foreach my $sig_id ( $Project->signatures() ) {
						my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
						if ( ! $$sig_specs{UsePress} ) {
							$$sig_specs{UsePress} = $$sig_specs{'ddmPress'.$Project->ordered_quantity_index()};
						} # end if
						if ( $$sig_specs{UsePress} eq $Press->strid() ) {
							$on_press = 1;
						} # end if
						last if $on_press;
					} # end foreach sig
					last if $on_press;
				} # end foreach Project
				next if ! $on_press;
			} # end if
			push @{$variable{Orders}}, $Order;
		} # end foreach Order
	} else {
		$variable{error} .= 'There were no companies to filter on.<br/>';
	} # end if
	$variable{Companies} = \%companies;
} # end sub _order_performance

sub stock {
	_stock();
} # end sub stock

sub _stock {
	ssi::save_params('/employee/reports/stock.html', 'owner_id', 'manufacturer_id', 'brand_id', 'finish_id', 'colour_id', 'weight_id', 'type', 'fsc_code', 'last_seen', 'location_id','width','height','OrLarger' );
} # end sub _stock

sub stock_usage {
	_stock_usage();

	if ( $param{action} eq 'download' ) {
		my @Header = ( 'Manufacturer','Brand','Finish','Colour','Weight','Quality','Material','Group','Width','Height','Type','Calliper','GSM','FSC','Projects','Orders','Sheets','Weight','Price in ' . $openprint::Currency->name() );
		my @Data = ();
		my %totals = %{$variable{totals}};
		my %Stocks = %{$variable{Stocks}};
		my %Projects = %{$variable{Projects}};
		my @Orders = @{$variable{Orders}};
		my $total_projects = 0;
		my $total_orders = 0;
		my $total_sheets = 0;
		my $total_weight = 0;
		my $total_price = 0;
		foreach my $paper_string ( sort keys %totals ) {
			my $Stock = $Stocks{$paper_string};
            my $quantity = $totals{$paper_string}{quantity};
            my @unique_order_ids = sets::union( map { $$_{id} } @{$totals{$paper_string}{Orders}} );
            my @unique_project_ids = sets::union( map { $$_{id} } @{$totals{$paper_string}{Projects}} );
			push @Data, (
				$Stock->manufacturer(),
				$Stock->brand(),
				$Stock->finish(),
				$Stock->colour(),
				$Stock->weight(),
				$Stock->quality(),
				$Stock->material(),
				$Stock->group(),
				$Stock->width(),
				$Stock->height(),
				$Stock->type(),
				$Stock->calliper(),
				$Stock->gsm(),
				$Stock->fsc_code(),
                scalar @unique_project_ids,
                scalar @unique_order_ids,
                $Stock->type() eq 'Sheet' ? Number::Format::format_number($quantity).' sheets' : '',
                Number::Format::format_number($Stock->type() eq 'Roll' ? $quantity : $quantity * $Stock->sheet_weight() ),
				$totals{$paper_string}{price},
            );
			$total_projects += @unique_project_ids;
			$total_orders += @unique_order_ids;
			$total_sheets += $Stock->type() eq 'Sheet' ? $quantity : 0;
			$total_weight += $Stock->type() eq 'Roll' ? $quantity : $quantity * $Stock->sheet_weight();
			$total_price += $totals{$paper_string}{price};

		} # end foreach Project
		push @Data, ( '', #manufacturer
				'', #brand
				'', #finish
				'', #colour
				'', #weight
				'', #quality
				'', #material
				'', #group
				'', #width
				'', #height
				'', #type
				'', #calliper
				'', #gsm,
				'', #fsc
				$total_projects,
				$total_orders,
				$total_sheets . ' sheets',
				$total_weight . ' lbs',
				$total_price,
				);
		misc::export_csv( $r, $log, \%variable, 'stock_usage.csv', \@Header,\@Data );	
	} # end if
} # end sub stock_usage

sub _stock_usage {
	ssi::save_params('/employee/reports/stock_usage.html', 'company_id', 
			( map { 'ordered_on_start_'.$_ } ( 'year','month','day' ) ),
			( map { 'ordered_on_end_'.$_ } ( 'year','month','day' ) ),
			'manufacturer_id', 'brand_id', 'finish_id', 'colour_id', 'weight_id',
			'type', 'fsc', 'fsc_code', 'width','height','OrLarger', 'basis_weight','mweight',
			'projects_orders','customer_supplied',
	 );
	ssi::setup_date_select( '/employee/reports/stock_usage.html', 'ordered_on_start', -31 );
	ssi::setup_date_select( '/employee/reports/stock_usage.html', 'ordered_on_end', '' );
	if ( ! exists $session{'/employee/reports/stock_usage.html?projects_orders'} ) {
		$session{'/employee/reports/stock_usage.html?projects_orders'} = 'Orders';
	} # end if
	if ( ! exists $session{'/employee/reports/stock_usage.html?customer_supplied'} ) {
		$session{'/employee/reports/stock_usage.html?customer_supplied'} = 'N';
	} # end if
$log->debug("done saving params");
    my @company_ids = ( $session{'/employee/reports/stock_usage.html?company_id'} ) if $session{'/employee/reports/stock_usage.html?company_id'};

    my @Orders;
    my %Projects;

	if ( $session{'/employee/reports/stock_usage.html?projects_orders'} eq 'Orders' ) {
		@Orders = openprint::Order->find(
				status      =>  [ 'In Production','Picked Up','Shipped','Waiting For QA Approval', 'Waiting For Customer Approval','Complete','Waiting For Pickup','Order Submitted','Paid','Pending Deposit','Re-Opened' ],
				( @company_ids ? ( company_id => \@company_ids ) : () ),
				ssi::date_filter( '/employee/reports/stock_usage.html?ordered_on_end', 'created_on <=' ),
				ssi::date_filter( '/employee/reports/stock_usage.html?ordered_on_start', 'created_on >=' ),
				);
		foreach my $Order ( @Orders ) {
			$Projects{$Order->id()} = [] if ! $Projects{$Order->id()};
			push @{$Projects{$Order->id()}}, $Order->Projects();
		}

	} else {
$log->debug("Loading projects");
		foreach my $Project ( openprint::Project->find(
					( @company_ids ? ( company_id => \@company_ids ) : () ),
					ssi::date_filter( '/employee/reports/stock_usage.html?ordered_on_end', 'created_on <=' ),
					ssi::date_filter( '/employee/reports/stock_usage.html?ordered_on_start', 'created_on >=' ),
					) ) {
			push @Orders, $Project->Order() if $Project->order_id();
			$Projects{$Project->order_id()} = [] if ! $Projects{$Project->order_id()};
			push @{$Projects{$Project->order_id()}}, $Project;
		} # end foreach Project
	} # end if

	my %totals;
	my %Stocks;
	$openprint::log->debug("orders: " . @Orders );
	my %types = map { $_, $_ } split( ',', $session{'/employee/reports/stock_usage.html?type'} );
	my $uri = '/employee/reports/stock_usage.html';
	my $StockBrand = new openprint::StockBrand( $session{$uri.'?brand_id'} ) if $session{$uri.'?brand_id'};
	my $StockFinish = new openprint::StockFinish( $session{$uri.'?finish_id'} ) if $session{$uri.'?finish_id'};
	my $StockColour = new openprint::StockColour( $session{$uri.'?colour_id'} ) if $session{$uri.'?colour_id'};
	my $StockWeight = new openprint::StockWeight( $session{$uri.'?weight_id'} ) if $session{$uri.'?weight_id'};

	foreach my $Order ( @Orders, ( $session{'/employee/reports/stock_usage.html?projects_orders'} eq 'Projects' ? new openprint::Order() : () ) ) {

		next if ! $Projects{$Order->id()};

		foreach my $Project ( @{$Projects{$Order->id()}} ) {
			my $qty_index = $Project->ordered_quantity_index();
			if ( ! $qty_index ) {
				if ( $session{'/employee/reports/stock_usage.html?projects_orders'} eq 'Projects' ) {
					my @qtys = $Project->quantity_indexes();
					$qty_index = $qtys[0];
				} else {
					$log->error("No Ordered QTY Index in $$Order{id} $$Project{id}!");
				} # end
			} # end if
			my $services = $Project->services();
			if ( $$services{Paper} and @{$$services{Paper}} ) {
				my $Service = $Project->Service( $$services{Paper}[0] );

				my $stock_sheets_quoted = 0;
				my $stock_weight_quoted = 0;
				my $stock_specs = $Service->specs();
				my @stocks_and_quantities = openprint::Estimating::Paper::get_stocks_and_quantities( $Project, $$services{Paper}[0], $stock_specs, $qty_index );
				my $stock_index = 1;
				foreach my $SQ ( @stocks_and_quantities ) {
					my ( $Stock, $qty ) = @$SQ{'Stock','quantity'};
					next if ! $qty;

					if ( %types and ! $types{ $Stock->type() } ) {
						next;
					}

					if ( $session{'/employee/reports/stock_usage.html?mweight'} ) {
						if ( ( $Stock->mweight() < ( $session{'/employee/reports/stock_usage.html?mweight'}-1) )
								or ( $Stock->mweight() > ( $session{'/employee/reports/stock_usage.html?mweight'}+1 ) ) ) {
							next;
						} # end if
					} # end if

					if (
							( ( $session{'/employee/reports/stock_usage.html?customer_supplied'} eq 'Y' ) and ! $Stock->supplied() )
							or
							( ( $session{'/employee/reports/stock_usage.html?customer_supplied'} eq 'N' ) and $Stock->supplied() )
					   ) {
						next;
					} # end if

					if ( $session{'/employee/reports/stock_usage.html?width'} and $session{'/employee/reports/stock_usage.html?height'} ) {
						next if $Stock->area() < $session{'/employee/reports/stock_usage.html?width'} * $session{'/employee/reports/stock_usage.html?height'};
						if ( ! $session{'/employee/reports/stock_usage.html?OrLarger'} ) {
							next if $Stock->area() != $session{'/employee/reports/stock_usage.html?width'} * $session{'/employee/reports/stock_usage.html?height'};
						} # end if
					} elsif ( $session{'/employee/reports/stock_usage.html?width'} ) {
						next if $Stock->width() < $session{'/employee/reports/stock_usage.html?width'};
						if ( ! $session{'/employee/reports/stock_usage.html?OrLarger'} ) {
							next if $Stock->width() != $session{'/employee/reports/stock_usage.html?width'};
						} # end if
					} elsif ( $session{'/employee/reports/stock_usage.html?height'} ) {
						next if $Stock->height() < $session{'/employee/reports/stock_usage.html?height'};
						if ( ! $session{'/employee/reports/stock_usage.html?OrLarger'} ) {
							next if $Stock->height() != $session{'/employee/reports/stock_usage.html?height'};
						} # end if
					} # end if

					if ( $session{'/employee/reports/stock_usage.html?basis_weight'} ) {
						if ( ( $Stock->basis_mweight() < ( $session{'/employee/reports/stock_usage.html?basis_weight'}-1) )
								or ( $Stock->basis_mweight() >( $session{'/employee/reports/stock_usage.html?basis_weight'}+1 ) ) ) {
							next;
						} # end if
					} # end if
					if ( $session{'/employee/reports/stock_usage.html?manufacturer_id'} ) {
						if ( $Stock->manufacturer_id() ne $session{'/employee/reports/stock_usage.html?manufacturer_id'} ) {
							$log->debug("Different manufacturer_id: $$Stock{manufacturer_id} != $session{'/employee/reports/stock_usage.html?manufacturer_id'}");
							next;
						} # end if
					} # end if
					if ( $StockBrand ) {
						if ( lc $Stock->brand() ne lc $StockBrand->name() ) {
							$log->debug("Different Brand: $$Stock{brand} != $$StockBrand{name}");
							next;
						} # end if
					} # end if
					if ( $StockFinish ) {
						if ( lc $Stock->finish() ne lc $StockFinish->name() ) {
							$log->debug("Different Finish: $$Stock{finish} != $$StockFinish{name}");
							next;
						} # end if
					} # end if
					if ( $StockWeight ) {
						if ( lc $Stock->weight() ne lc $StockWeight->name() ) {
							$log->debug("Different Weight: $$Stock{weight} != $$StockWeight{name}");
							next;
						} # end if
					} # end if
					if ( $StockColour ) {
						if ( lc $Stock->colour() ne lc $StockColour->name() ) {
							$log->debug("Different Colour: $$Stock{colour} != $$StockColour{name}");
							next;
						} # end if
					} # end if

					my $stock_id = $Stock->to_string();
					$Stocks{$stock_id} = $Stock;
					$totals{$stock_id}{quantity} += $qty;
					$totals{$stock_id}{price} += $Project->Currency()->convert_from( $$SQ{price} );

					$totals{$stock_id}{Orders} = [] if ! $totals{$stock_id}{Orders};
					$totals{$stock_id}{Projects} = [] if ! $totals{$stock_id}{Projects};
$log->debug("$$Project{id} $stock_id $qty price:$$SQ{price}");

					push @{$totals{$stock_id}{Projects}}, $Project;
					push @{$totals{$stock_id}{Orders}}, $Order;

				} # end foreach StockQuantity
			} # end if has Paper service
		} # end foreach Project
	} # end foreach Order

	$variable{totals} = \%totals;
	$variable{Stocks} = \%Stocks;
	$variable{Projects} = \%Projects;
	$variable{Orders} = \@Orders;

} # end sub _stock_usage

sub delivery {
} # end sub delivery
sub efficiency {
} # end sub efficiency
sub prepress_overview {
	_prepress_project_list();
	ssi::setup_date_select( '/employee/reports/prepress_overview.html', 'takeover_on_start', -31 );
	ssi::setup_date_select( '/employee/reports/prepress_overview.html', 'takeover_on_end', '' );
} # end sub prepress_overview
sub _prepress_project_list {
	ssi::save_params('/employee/reports/prepress_overview.html', 
			( map { 'takeover_on_start_'.$_ } ( 'year','month','day' ) ),
			( map { 'takeover_on_end_'.$_ } ( 'year','month','day' ) ),
	);
} # end sub _prepress_project_list

sub _delivery_results {
} # end sub _delivery_results

sub turnaround {
	ssi::setup_date_select( '/employee/reports/turnaround.html', 'due_date_start', -31 );
	ssi::setup_date_select( '/employee/reports/turnaround.html', 'due_date_end', '' );
	_turnaround();
}# end sub turnaround

sub _turnaround {
	ssi::save_params('/employee/reports/turnaround.html', 
			( map { 'due_date_start_'.$_ } ( 'year','month','day' ) ),
			( map { 'due_date_end_'.$_ } ( 'year','month','day' ) ),
	);
} # end sub _turnaround

sub plates {
	if ( ! %param ) {
		ssi::setup_date_select( $r->uri(), 'ordered_on_start', -31 );
		ssi::setup_date_select( $r->uri(), 'ordered_on_end', '' );
		#ssi::setup_date_select( $r->uri(), 'printed_on_start', -31 );
		#ssi::setup_date_select( $r->uri(), 'printed_on_end', '' );
		if ( ! $session{$r->uri().'?press_id'} ) {
			$session{$r->uri().'?press_id'} = join(',',map{$$_{id}} openprint::Equipment->find('category any'=>'Printing'));
		}
	} # end if
	_plates();

	if ( $param{action} eq 'download' ) {
		misc::export_csv( $r, $log, \%variable, 'plates.csv', @variable{'Header','Data'} );	
	} # end if
} # end sub plates

sub _plates {
	my $uri = '/employee/reports/plates.html';

	ssi::save_params($uri, 'company_id', 
			( map { 'ordered_on_start_'.$_ } ( 'year','month','day' ) ),
			( map { 'ordered_on_end_'.$_ } ( 'year','month','day' ) ),
			( map { 'printed_on_start_'.$_ } ( 'year','month','day' ) ),
			( map { 'printed_on_end_'.$_ } ( 'year','month','day' ) ),
			'press_id', 'csr_id', 'reprint','format',
			);

	my %parameters; 
	if ( ( $session{user_type} ne 'A' ) and ! openprint::usergroup::is_user_in( ['Sales Admin','Reporting','Accounting'], $session{user_id} ) ) {
		$parameters{or} = {
			id =>$$openprint::User{company_id},
			salesrep_id	=>	$session{user_id},
			};
	} elsif ( $param{csr_id} ) {
		$parameters{salesrep_id} = $param{csr_id};
	} # end if
	
	my @Companies;
	if ( %parameters ) {
		@Companies = openprint::Company->find( %parameters ) if %parameters;
		if ( ! @Companies ) {
			$variable{error} .= 'There were no companies to filter on.<br/>';
			return;
		} # end if
	} # end if
	my %companies = map { int($_->id()), $_->name() } @Companies if @Companies;

	my @Presses = openprint::Equipment->find();
	my %Presses_by_id = map { $$_{id}, $_ } @Presses;
	my %Presses_by_strid = map { $$_{strid}, $_ } @Presses;
	
	my @press_ids = split( ',', $session{$uri.'?press_id'} );
	my %press_names = map { $Presses_by_id{$_} ? ( $Presses_by_id{$_}{strid} => $_ ) : () } @press_ids;
	my @press_names = sort { $a cmp $b } keys %press_names;

	my %PlateCounts; # Indexed by plateid->Cost->Press

	my @Orders = openprint::Order->find(
				( ( @Companies or $session{$uri.'?company_id'} ) ? ( company_id => ( ($session{$uri.'?company_id'} and (( !%companies) or exists $companies{$session{$uri.'?company_id'}} ) ) ? $session{$uri.'?company_id'} : [ keys %companies ] ) ) : () ),
				ssi::date_filter( $uri.'?ordered_on_start', 'created_on >=' ),
				ssi::date_filter( $uri.'?ordered_on_end', 'created_on <=' ),
				#( $session{$uri.'?status_id'} ? ( status_id => [ split(',', $session{$uri.'?status_id'} ) ] ) : () ),
				order => ($param{order} ? $param{order} : 'id'),
				);
	my @order_ids = map { $$_{id} } @Orders;

	my %Projects_By_OrderId;
	if ( @order_ids ) {
		foreach my $Project ( openprint::Project->find(order_id=>\@order_ids) ) {
			$Projects_By_OrderId{$$Project{order_id}} = [] if ! $Projects_By_OrderId{$$Project{order_id}};
			push @{$Projects_By_OrderId{$$Project{order_id}}}, $Project;
		}
	}

	my @printed_on_start = map{ @session{$uri.'?printed_on_start_'.$_} } ( 'year','month','day' );
	my $printed_on_start = join('-', @printed_on_start ) if Date::Calc::check_date( @printed_on_start );
	my $printed_on_start_seconds = Date::Parse::str2time( $printed_on_start ) if $printed_on_start;

	my @printed_on_end = map{ @session{$uri.'?printed_on_end_'.$_} } ( 'year','month','day' );
	my $printed_on_end = join('-', @printed_on_end) if Date::Calc::check_date(@printed_on_end);
	my $printed_on_end_seconds = Date::Parse::str2time($printed_on_end) if $printed_on_end;

	foreach my $Order ( @Orders ) {
		next if ! $$Order{docket};
		if ( $session{$uri.'?reprint'} ) {
			my $reprint = 0;
			foreach my $Project ( $Order->Projects() ) {
				if ( $Project->reprint() eq 'Y' ) {
					$reprint = 1;
					last;
				} # end if
			} # end foreach Project
			next if ( $session{$uri.'?reprint'} eq 'Y' ) and ! $reprint;
			next if ( $session{$uri.'?reprint'} eq 'N' ) and $reprint;
		} # end if reprint

		foreach my $Project ( $Order->Projects() ) {

			if ( $printed_on_start or $printed_on_end ) {
				my $printed_on = $Project->printed_on();


				if ( ! $printed_on ) {
					$log->debug("Project $$Project{id} has not been printed");
					next;
				} else {
					$log->debug("Project $$Project{id} was printed $printed_on");
				}
				my $printed_on_seconds = Date::Parse::str2time( $printed_on );
				if (
							( $printed_on_start_seconds and ( $printed_on_seconds < $printed_on_start_seconds ) )
							or	
							( $printed_on_end_seconds and ( $printed_on_seconds > $printed_on_end_seconds ) )
							) {
					$log->debug("Project $$Project{id} was printed $printed_on_start_seconds < $printed_on < $printed_on_end_seconds ");
					next;
				}
			} # end if printed_on_start or printed_on_end

			my $services = $Project->services();
			my @signatures = $Project->signatures();
			my $qty_index = $Project->ordered_quantity_index();

			my $plate_qty = 0;
			my $plate_cost = 0;
			my $plate_price = 0;
			foreach my $sig_id ( @signatures ) {
				my $Service = $Project->Service( $sig_id );
				my $sig_specs = $Service->specs();

				next if ! $$sig_specs{"txtImposition$qty_index"};

				#if ( ! $$sig_specs{UsePress} ) {
					$$sig_specs{UsePress} = $$sig_specs{'ddmPress'.$qty_index};
				#} # end if
				if ( ! $press_names{$$sig_specs{UsePress}} ) {
					# Not interested in this press
					next;
				}

				if ( ! $$sig_specs{'PlateID'.$qty_index} ) {
					my $Press = $Presses_by_strid{$$sig_specs{UsePress}};
					next if ! $Press;
					my $plate_size = $Press->specification('Plate Size');
					next if ! $plate_size;
					$$sig_specs{'PlateID'.$qty_index} = $plate_size.'"-'.$Press->specification('Plate Type').'Plate';
				} # end if
				my $plate_id = $$sig_specs{'PlateID'.$qty_index};

				my $Plate = openprint::Material->find_one( name=>$$sig_specs{'PlateID'.$qty_index} ) if $$sig_specs{'PlateID'.$qty_index};
				my %plate_cost = $Plate->get_price( $$sig_specs{'txtPlateQuantity'.$qty_index} ) if $Plate;

				$plate_qty += $$sig_specs{'txtPlateQuantity'.$qty_index};
				#$plate_cost += $plate_cost{Cost} * $$sig_specs{'txtPlateQuantity'.$qty_index};
				#my $plate_price = $Project->Currency()->convert_from($$sig_specs{'PerPlateCost'.$qty_index});
				#if ( ! $plate_price ) {
					$plate_price = $plate_cost{Cost};
 #* $$sig_specs{'txtPlateQuantity'.$qty_index};
				#}

				$PlateCounts{$plate_id} = {} if ! exists $PlateCounts{$plate_id};
				$PlateCounts{$plate_id}{$plate_price} = {} if ! exists $PlateCounts{$plate_id}{$plate_price};
				$PlateCounts{$plate_id}{$plate_price}{$$sig_specs{UsePress}} = 0 if ! exists $PlateCounts{$plate_id}{$plate_price}{$$sig_specs{UsePress}};

				$PlateCounts{$plate_id}{$plate_price}{$$sig_specs{UsePress}} += $$sig_specs{'txtPlateQuantity'.$qty_index};
			} # end foreach sig

		} # end foreach Project
	} # end foreach Order

	if ( $session{$uri.'?format'} eq 'Separate' ) {
		$variable{Header} = [ 'Plate Type', 'Quoted Cost' ];
		foreach my $press ( @press_names ) {
			push @{$variable{Header}}, $press.' Count', $press.' Total';
		}

		foreach my $plate ( keys %PlateCounts ) {
			foreach my $price ( keys %{$PlateCounts{$plate}} ) {
			  push @{$variable{Data}}, $plate, $price;
				foreach my $press ( @press_names ) {
					if ( $PlateCounts{$plate}{$price}{$press} ) {
						push @{$variable{Data}}, $PlateCounts{$plate}{$price}{$press}, $price*$PlateCounts{$plate}{$price}{$press};
					} else {
						push @{$variable{Data}}, '', '';
					}
				}
			}
		}
	} else {
		$variable{Header} = [ 'Plate Type', 'Quoted Cost', 'Press', 'Count', 'Total' ];

		foreach my $plate ( keys %PlateCounts ) {
			foreach my $price ( keys %{$PlateCounts{$plate}} ) {
				foreach my $press ( keys %{$PlateCounts{$plate}{$price}} ) {
					push @{$variable{Data}}, $plate, $price, $press, $PlateCounts{$plate}{$price}{$press}, $price*$PlateCounts{$plate}{$price}{$press};
				}
			}
		}
	} # end if format
	$variable{PlateCounts} = \%PlateCounts;

} # end sub _plates

sub production_performance {
	if ( ! %param ) {
		ssi::setup_date_select( $r->uri(), 'ordered_on_start', -31 );
		ssi::setup_date_select( $r->uri(), 'ordered_on_end', '' );
		ssi::setup_date_select( $r->uri(), 'completed_on_start', -31 );
		ssi::setup_date_select( $r->uri(), 'completed_on_end', '' );
	} # end if
	_production_performance();

	if ( $param{action} eq 'download' ) {
		misc::export_csv( $r, $log, \%variable, 'production_performance_report.csv', @variable{'Header','Data'} );	
	} # end if
} # end sub production_performance

sub _production_performance {
	my $uri = '/employee/reports/production_performance.html';

	ssi::save_params($uri, 'company_id', 
			( map { 'ordered_on_start_'.$_ } ( 'year','month','day' ) ),
			( map { 'ordered_on_end_'.$_ } ( 'year','month','day' ) ),
			( map { 'completed_on_start_'.$_ } ( 'year','month','day' ) ),
			( map { 'completed_on_end_'.$_ } ( 'year','month','day' ) ),
			'press_id', 'csr_id', 'reprint','columns','status_id','runstyles',
			);

	my %columns = map { $_, $_ } split(',', $session{$uri.'?columns'} ) if $session{$uri.'?columns'};
	%columns = map { $_, 1 } qw( plates ) if ! %columns;
	$variable{columns} = \%columns;

	my %parameters; 
	if ( ( $session{user_type} ne 'A' ) and ! openprint::usergroup::is_user_in( ['Sales Admin','Reporting','Accounting'], $session{user_id} ) ) {
		$parameters{or} = {
			id =>$$openprint::User{company_id},
			salesrep_id	=>	$session{user_id},
			};
	} elsif ( $param{csr_id} ) {
		$parameters{salesrep_id} = $param{csr_id};
	} # end if
	
	my @Companies;
	if ( %parameters ) {
		@Companies = openprint::Company->find( %parameters ) if %parameters;
		if ( ! @Companies ) {
			$variable{error} .= 'There were no companies to filter on.<br/>';
			return;
		} # end if
	} # end if
	my %companies = map { int($_->id()), $_->name() } @Companies if @Companies;

	my @Presses = openprint::Equipment->find();
	my %Presses_by_id = map { $$_{id}, $_ } @Presses;
	my %Presses_by_strid = map { $$_{strid}, $_ } @Presses;
	
	my @press_names = split( ',', $session{$uri.'?press_id'} );
	my %press_names = map { $Presses_by_id{$_}{strid}, $_ } @press_names;
	my @Data;

	my %wanted_runstyles = map { $_ => $_ } split(',', $session{$uri.'?runstyles'});

	my @ServiceType_Categories = openprint::ServiceType_Category->find( order=>'sorting,lower(name)' );
	my %ServiceTypes_By_Category;
	foreach my $Service ( openprint::ServiceType->find() ) {
		$ServiceTypes_By_Category{$$Service{category_id}} = [] if ! $ServiceTypes_By_Category{$$Service{category_id}};
		push @{$ServiceTypes_By_Category{$$Service{category_id}}}, $Service;
	}
	my @Orders = openprint::Order->find(
				( ( @Companies or $session{$uri.'?company_id'} ) ? ( company_id => ( ($session{$uri.'?company_id'} and (( !%companies) or exists $companies{$session{$uri.'?company_id'}} ) ) ? $session{$uri.'?company_id'} : [ keys %companies ] ) ) : () ),
				ssi::date_filter( $uri.'?ordered_on_start', 'created_on >=' ),
				ssi::date_filter( $uri.'?ordered_on_end', 'created_on <=' ),
				( $session{$uri.'?status_id'} ? ( status_id => [ split(',', $session{$uri.'?status_id'} ) ] ) : () ),
				order => ($param{order} ? $param{order} : 'id'),
				);
	my @dockets = map { $_->docket() } @Orders;
	my %PI_by_docket = misc::make_hash_from_array('docket', openprint::PaperInventory->find(docket=>\@dockets, 'skid_id is null'=>0)) if @dockets;
	my %POC_by_docket = misc::make_hash_from_array('docket', openprint::PurchaseOrder_Content->find(docket=>\@dockets)) if @dockets;

	foreach my $Order ( @Orders ) {
		next if ! $$Order{docket};
		if ( $session{$uri.'?reprint'} ) {
			my $reprint = 0;
			foreach my $Project ( $Order->Projects() ) {
				if ( $Project->reprint() eq 'Y' ) {
					$reprint = 1;
					last;
				} # end if
			} # end foreach Project
			next if ( $session{$uri.'?reprint'} eq 'Y' ) and ! $reprint;
			next if ( $session{$uri.'?reprint'} eq 'N' ) and $reprint;
		} # end if reprint

		foreach my $Project ( $Order->Projects() ) {
			my $services = $Project->services();
			my @signatures = $Project->signatures();
			my $qty_index = $Project->ordered_quantity_index();

			if ( @press_names ) {
				my $found = 0;

				foreach my $sig_id ( @signatures ) {
					my $Service = $Project->Service($sig_id);
					my $sig_specs = $Service->specs();
					if ( ! $$sig_specs{UsePress} ) {
						$$sig_specs{UsePress} = $$sig_specs{'ddmPress'.$qty_index};
					} # end if
					if ( $press_names{$$sig_specs{UsePress}} ) {
						$found = 1;
						last;
					}
				}
				next if ! $found;
			} # end if press_names

			if ( %wanted_runstyles ) {
				my $found = 0;
				foreach my $sig_id ( @signatures ) {
					my $Service = $Project->Service( $sig_id );
					my $sig_specs = $Service->specs();
					if ( $wanted_runstyles{$$sig_specs{'ddmRunStyle'.$qty_index}} ) {	
						$found = 1;
						last;
					}
				} # end foreach sig
				next if ! $found;
			}

			my @fragment = ( $Order->id(), $Order->docket(), $Project->id(), $Order->company_name(), $Order->created_on(), 
					$Project->status(), $Project->ordered_price() );
			my %runstyles;
			my $impressions = 0;
			foreach my $sig_id ( @signatures ) {
				my $Service = $Project->Service( $sig_id );
				my $sig_specs = $Service->specs();
				next if ! $$sig_specs{'txtPrice'.$qty_index};
				if ( ! $$sig_specs{'hdnImpressionQuantity'.$qty_index} ) {
					next;
				} # end if
				$impressions += $$sig_specs{'hdnImpressionQuantity'.$qty_index};
				$runstyles{$$sig_specs{'ddmRunStyle'.$qty_index}} = 1;
			}
			push @fragment, $impressions, join(',',keys %runstyles);
	
			if ( $columns{services} ) {
				my %category_totals;
				foreach my $Category ( @ServiceType_Categories ) {
					$category_totals{$$Category{id}} = 0;
					foreach my $ServiceType ( @{$ServiceTypes_By_Category{$$Category{id}}} ) {
						next if ! $$services{$$ServiceType{name}};
						foreach my $service_id ( @{ $$services{$$ServiceType{name}} } ) {
							my $Service = $Project->Service( $service_id );
							$category_totals{$$Category{id}} += $Service->ordered_price();	
						} # end foreach service_id
					} # end foreach ServiceType
					push @fragment, $category_totals{$$Category{id}};
				} # end foreach category
			}

			if ( $columns{plates} ) {
				my $plate_qty = 0;
				my $plate_cost = 0;
				my $plate_price = 0;
				foreach my $sig_id ( @signatures ) {
					my $Service = $Project->Service( $sig_id );
					my $sig_specs = $Service->specs();
					next if ! $$sig_specs{'txtPrice'.$qty_index};

					if ( ! $$sig_specs{'PlateID'.$qty_index} ) {
						my $Press = $Presses_by_strid{$$sig_specs{UsePress}};
						next if ! $Press;
						$$sig_specs{'PlateID'.$qty_index} = $Press->specification('Plate Size').'"-'.$Press->specification('Plate Type').'Plate';
					} # end if

					my $Plate = openprint::Material->find_one( name=>$$sig_specs{'PlateID'.$qty_index} ) if $$sig_specs{'PlateID'.$qty_index};
					my %plate_cost = $Plate->get_price( $$sig_specs{'txtPlateQuantity'.$qty_index} ) if $Plate;

					$plate_qty += $$sig_specs{'txtPlateQuantity'.$qty_index};
					$plate_cost += $plate_cost{Cost} * $$sig_specs{'txtPlateQuantity'.$qty_index};
					$plate_price += $plate_cost{Price} * $$sig_specs{'txtPlateQuantity'.$qty_index};
				} # end foreach sig
				push @fragment, $plate_qty, $plate_cost, $plate_price;
			} # end if include plate info

			if ( $columns{production} ) {
				push @fragment,
						 ssi::format_csv_datetime($Project->takeover_on()),
						 ssi::format_csv_datetime($Project->printed_on()),
						 ssi::format_csv_datetime($Project->completed_on());
				my $shipped_on = ssi::format_csv_datetime($Project->shipped_on());
				push @fragment, $shipped_on;
				my $invoiced_on = ssi::format_csv_datetime($Order->invoiced_on());
				push @fragment, $invoiced_on;
			}

			if ( $columns{stock} or $columns{stock_customer_supplied} ) {
				my $stock_sheets = 0;
				my $stock_weight = 0;
				my $stock_cost = 0;	
			
				# This the used counts from inventory, theoretically each has a manifest
				foreach my $PI ( $PI_by_docket{ $$Order{docket} } ? @{$PI_by_docket{ $$Order{docket} } } : () ) {
#openprint::PaperInventory->find( docket=>$Order->docket(), 'skid_id is null'=>0 ) ) {
#$openprint::log->debug("PI Stock for $$Order{docket} is $$PI{delta} " . $PI->Paper()->to_string() );
					if ( $PI->Paper()->units() eq 'Roll' ) {
						$stock_weight += -1*$$PI{delta};
					} else {
						$stock_sheets += -1*$$PI{delta};
					}
					my $Cost = $PI->Value();
					$stock_cost += $$Cost{value};
				}

				push @fragment, $stock_sheets, int($stock_weight), $stock_cost;

				$stock_sheets = $stock_weight = $stock_cost = 0;
        # Now do the counts from Manifests/POs
        foreach my $POC ( $POC_by_docket{$$Order{docket}} ? @{$POC_by_docket{$$Order{docket}}} : () ) {
						next if $POC->PurchaseOrder()->cancelled();
#openprint::PurchaseOrder_Content->find( docket=>$Order->docket() ) ) {
            if ( $POC->type() eq 'Roll Stock' ) {
              $stock_weight += $POC->qty();
            } elsif ( $POC->type() eq 'Sheet Stock' ) {
              $stock_sheets += $POC->qty();
              $stock_weight += $POC->weight();
            } else {
							next; # Not stock
						}
            $stock_cost += $POC->PurchaseOrder()->Currency()->convert_from($POC->total());
        } # end foreach POC
        push @fragment, $stock_sheets, int($stock_weight), $stock_cost;

				$stock_sheets = $stock_weight = $stock_cost = 0;	
				# Now do the counts from Manifests/POs
				foreach my $MT ( openprint::Manifest_Content_Type->find( docket=>$Order->docket() ) ) {
					#my $POC = $MT->PurchaseOrder_Content();
					foreach my $MC ( openprint::ManifestContent->find( type_id=>$$MT{id} ) ) {
						if ( $MT->Paper()->type() eq 'Roll' ) {
							$stock_weight += $MC->quantity();
						} else {
							$stock_sheets += $MC->quantity();
							$stock_weight += $MC->quantity() * $MT->Paper()->sheet_weight();
						}
						if ( $MC->value() ) {
$openprint::log->debug("Adding stock_cost from MC value $stock_weight $stock_sheets $$MC{value} = $stock_cost");
							$stock_cost += $MT->Manifest()->Currency()->convert_from($MC->value());
						#} elsif ( $POC ) {
							#$stock_cost += $POC->PurchaseOrder()->Currency()->convert_from($POC->price() * $MC->quantity() / 100);
						}
					}
				} # end foreach Manifest Type
				push @fragment, $stock_sheets, int($stock_weight), $stock_cost;

				if ( $$services{Paper} and @{$$services{Paper}} ) {
					my $Service = $Project->Service( $$services{Paper}[0] );

					$stock_sheets = $stock_weight = $stock_cost = 0;	
					my @stocks_and_quantities = openprint::Estimating::Paper::get_stocks_and_quantities( $Project, $$services{Paper}[0], $Service->specs(), $qty_index );
					foreach my $SQ ( @stocks_and_quantities ) {
						my ( $Stock, $qty ) = @$SQ{'Stock','quantity'};
						next if ! $qty;
						if ( $Stock->supplied() ) {
							next if ! $columns{stock_customer_supplied};
						} else {
							next if ! $columns{stock};
						}
						if ( $Stock->type() eq 'Roll' ) {
							$stock_weight += $qty;
            } else {
              $stock_sheets += $qty;
              $stock_weight += $qty * $Stock->sheet_weight();
            }
            $stock_cost += $Project->Currency()->convert_from($$SQ{price});
					}
					push @Data, @fragment, $stock_sheets, int($stock_weight), $stock_cost;

				} else {
					# No quoted stock section
					push @Data, @fragment, 0, 0, 0;
				}
			} else {
				# Not doing stocks
				push @Data, @fragment;
			} # end if stock
			$fragment[6] = 0; # clear project price so that a subsequent line won't get the same value again

		} # end foreach Project
	} # end foreach Order

	$variable{Header} = [ 'Order ID', 'Docket', 'Project ID', 'Company',
		'Created On', 'Status', 'Project Value',
		'Impressions', 'Runstyles',
		( $columns{services} ? ( map { $$_{name} } @ServiceType_Categories ) : () ),
		( $columns{plates} ? ( 'Plates', 'Plate Cost', 'Plate Total' ) : () ),
		( $columns{production} ? ( 'Operator Assigned', 'Printed On', 'Completed On', 'Shipped On', 'Invoiced On' ) : () ),
		( ($columns{stock} or $columns{stock_customer_supplied}) ? ( 
												 'Used Stock Sheets', 'Used Stock Weight', 'Used Stock Cost',
												 'Purchased Stock Sheets', 'Purchased Stock Weight', 'Purchaseed Stock Cost',
												 'Received Stock Sheets', 'Received Stock Weight', 'Received Stock Cost',
												 'Quoted Stock Sheets', 'Quoted Stock Weight', 'Quoted Stock Price'
												) : () ),
	];

	$variable{Data} = \@Data;

} # end sub _production_performance

sub production_performance2 {
	if ( ! %param ) {
		ssi::setup_date_select( $r->uri(), 'ordered_on_start', -31 );
		ssi::setup_date_select( $r->uri(), 'ordered_on_end', '' );
		ssi::setup_date_select( $r->uri(), 'completed_on_start', -31 );
		ssi::setup_date_select( $r->uri(), 'completed_on_end', '' );
	} # end if
	_production_performance();

	if ( $param{action} eq 'download' ) {
		misc::export_csv( $r, $log, \%variable, 'production_performance2_report.csv', @variable{'Header','Data'} );	
	} # end if
} # end sub production_performance

sub _production_performance2 {
	my $uri = '/employee/reports/production_performance2.html';

	ssi::save_params($uri, 'company_id', 
			( map { 'ordered_on_start_'.$_ } ( 'year','month','day' ) ),
			( map { 'ordered_on_end_'.$_ } ( 'year','month','day' ) ),
			( map { 'completed_on_start_'.$_ } ( 'year','month','day' ) ),
			( map { 'completed_on_end_'.$_ } ( 'year','month','day' ) ),
			'press_id', 'csr_id', 'reprint','columns','status_id',
			);

	my %columns = map { $_, $_ } split(',', $session{$uri.'?columns'} ) if $session{$uri.'?columns'};
	%columns = map { $_, 1 } qw( plates ) if ! %columns;
	$variable{columns} = \%columns;

	my %parameters; 
	if ( ( $session{user_type} ne 'A' ) and ! openprint::usergroup::is_user_in( ['Sales Admin','Reporting','Accounting'], $session{user_id} ) ) {
		$parameters{or} = {
			id =>$$openprint::User{company_id},
			salesrep_id	=>	$session{user_id},
			};
	} elsif ( $param{csr_id} ) {
		$parameters{salesrep_id} = $param{csr_id};
	} # end if
	
	my @Companies;
	if ( %parameters ) {
		@Companies = openprint::Company->find( %parameters ) if %parameters;
		if ( ! @Companies ) {
			$variable{error} .= 'There were no companies to filter on.<br/>';
			return;
		} # end if
	} # end if
	my %companies = map { int($_->id()), $_->name() } @Companies if @Companies;

	my @Presses = openprint::Equipment->find();
	my %Presses_by_id = map { $$_{id}, $_ } @Presses;
	my %Presses_by_strid = map { $$_{strid}, $_ } @Presses;
	
	my @press_names = split( ',', $session{$uri.'?press_id'} );
	my %press_names = map { $Presses_by_id{$_}{strid}, $_ } @press_names;
	my @Data;

	my @ServiceType_Categories = openprint::ServiceType_Category->find( order=>'sorting,lower(name)' );
	my %ServiceTypes_By_Category;
	foreach my $Service ( openprint::ServiceType->find() ) {
		$ServiceTypes_By_Category{$$Service{category_id}} = [] if ! $ServiceTypes_By_Category{$$Service{category_id}};
		push @{$ServiceTypes_By_Category{$$Service{category_id}}}, $Service;
	}
	my @Orders = openprint::Order->find(
				( ( @Companies or $session{$uri.'?company_id'} ) ? ( company_id => ( ($session{$uri.'?company_id'} and (( !%companies) or exists $companies{$session{$uri.'?company_id'}} ) ) ? $session{$uri.'?company_id'} : [ keys %companies ] ) ) : () ),
				ssi::date_filter( $uri.'?ordered_on_start', 'created_on >=' ),
				ssi::date_filter( $uri.'?ordered_on_end', 'created_on <=' ),
				( $session{$uri.'?status_id'} ? ( status_id => [ split(',', $session{$uri.'?status_id'} ) ] ) : () ),
				order => ($param{order} ? $param{order} : 'id'),
				);
	foreach my $Order ( @Orders ) {
		next if ! $$Order{docket};
		if ( $session{$uri.'?reprint'} ) {
			my $reprint = 0;
			foreach my $Project ( $Order->Projects() ) {
				if ( $Project->reprint() eq 'Y' ) {
					$reprint = 1;
					last;
				} # end if
			} # end foreach Project
			next if ( $session{$uri.'?reprint'} eq 'Y' ) and ! $reprint;
			next if ( $session{$uri.'?reprint'} eq 'N' ) and $reprint;
		} # end if reprint

		foreach my $Project ( $Order->Projects() ) {
			my $services = $Project->services();
			my @signatures = $Project->signatures();
			my $qty_index = $Project->ordered_quantity_index();

			if ( @press_names ) {
				my $found = 0;

				foreach my $sig_id ( @signatures ) {
					my $Service = $Project->Service( $sig_id );
					my $sig_specs = $Service->specs();
					if ( ! $$sig_specs{UsePress} ) {
						$$sig_specs{UsePress} = $$sig_specs{'ddmPress'.$qty_index};
					} # end if
					if ( $press_names{$$sig_specs{UsePress}} ) {
						$found = 1;
						last;
					}
				}
				next if ! $found;
			} # end if press_names

			my @fragment = ( $Order->id(), $Order->docket(), $Project->id(), $Order->company_name(), $Order->created_on(), $Project->status(), $Project->ordered_price() );
			my $impressions = 0;
			foreach my $sig_id ( @signatures ) {
				my $Service = $Project->Service( $sig_id );
				my $sig_specs = $Service->specs();
				if ( ! $$sig_specs{'hdnImpressionQuantity'.$qty_index} ) {
					next;
				} # end if
				$impressions += $$sig_specs{'hdnImpressionQuantity'.$qty_index};
			}
			push @fragment, $impressions;
	
			my %category_totals;
			foreach my $Category ( @ServiceType_Categories ) {
				$category_totals{$$Category{id}} = 0;
				foreach my $ServiceType ( @{$ServiceTypes_By_Category{$$Category{id}}} ) {
					next if ! $$services{$$ServiceType{name}};
					foreach my $service_id ( @{ $$services{$$ServiceType{name}} } ) {
						my $Service = $Project->Service( $service_id );
						$category_totals{$$Category{id}} += $Service->ordered_price();	
					} # end foreach service_id
				} # end foreach ServiceType
				push @fragment, $category_totals{$$Category{id}};
			} # end foreach category

			if ( $columns{plates} ) {
				my $plate_qty = 0;
				my $plate_cost = 0;
				my $plate_price = 0;
				foreach my $sig_id ( @signatures ) {
					my $Service = $Project->Service( $sig_id );
					my $sig_specs = $Service->specs();

					if ( ! $$sig_specs{'PlateID'.$qty_index} ) {
						my $Press = $Presses_by_strid{$$sig_specs{UsePress}};
						next if ! $Press;
						$$sig_specs{'PlateID'.$qty_index} = $Press->specification('Plate Size').'"-'.$Press->specification('Plate Type').'Plate';
					} # end if

					my $Plate = openprint::Material->find_one( name=>$$sig_specs{'PlateID'.$qty_index} ) if $$sig_specs{'PlateID'.$qty_index};
					my %plate_cost = $Plate->get_price( $$sig_specs{'txtPlateQuantity'.$qty_index} ) if $Plate;

					$plate_qty += $$sig_specs{'txtPlateQuantity'.$qty_index};
					$plate_cost += $plate_cost{Cost} * $$sig_specs{'txtPlateQuantity'.$qty_index};
					$plate_price += $plate_cost{Price} * $$sig_specs{'txtPlateQuantity'.$qty_index};
				} # end foreach sig
				push @fragment, $plate_qty, $plate_cost, $plate_price;
			} # end if include plate info

			if ( $columns{production} ) {
				push @fragment, ''.$Project->takeover_on(), ''.$Project->printed_on(), ''.$Project->completed_on();
				my $invoiced_on = ''.$Order->invoiced_on();
				push @fragment, $invoiced_on;
			}

			if ( $columns{stock} ) {
				my $stock_sheets = 0;
				my $stock_weight = 0;
				my $stock_cost = 0;	
				my %skids;
				foreach my $PI ( openprint::PaperInventory->find( docket=>$Order->docket(), 'skid_id is null'=>0 ) ) {
					$skids{$$PI{skid_id}} = 1;
$openprint::log->debug("PI Stock for $$Order{docket} is $$PI{delta} " . $PI->Paper()->to_string() );
					if ( $PI->Paper()->units() eq 'Roll' ) {
						$stock_weight += -1*$$PI{delta};
					} else {
						$stock_sheets += -1*$$PI{delta};
					}
					my $Cost = $PI->Value();
					$stock_cost += $$Cost{value};
				}
				foreach my $MT ( openprint::Manifest_Content_Type->find( docket=>$Order->docket() ) ) {
					foreach my $MC ( openprint::ManifestContent->find( type_id=>$$MT{id} ) ) {
						next if $skids{$$MC{skid_id}};
						if ( $MT->Paper()->type() eq 'Roll' ) {
							$stock_weight += $MC->quantity();
						} else {
							$stock_sheets += $MC->quantity();
							$stock_weight += $MC->quantity() * $MT->Paper()->sheet_weight();
						}
						$stock_cost += $MC->value();
					}
				}
				push @fragment, $stock_sheets, $stock_weight, $stock_cost;

				if ( $$services{Paper} and @{$$services{Paper}} ) {
					my $Service = $Project->Service( $$services{Paper}[0] );

					my $stock_sheets_quoted = 0;
					my $stock_weight_quoted = 0;
					my $stock_specs = $Service->specs();
					my @stocks_and_quantities = openprint::Estimating::Paper::get_stocks_and_quantities( $Project, $$services{Paper}[0], $stock_specs, $qty_index );
					my $stock_index = 1;
					foreach my $SQ ( @stocks_and_quantities ) {
						my ( $Stock, $qty ) = @$SQ{'Stock','quantity'};
						next if ! $qty;

						push @Data, @fragment, $Stock->to_string(), ( $Stock->type() eq 'Sheet' ? ($qty,$qty*$Stock->sheet_weight()) : ('', $qty) ), $$SQ{price};
					}

				} else {
					push @Data, @fragment, 0,0,0,0;
				}
			} else {
				push @Data, @fragment;
			} # end if stock

		} # end foreach Project
	} # end foreach Order

	$variable{Header} = [ 'Order ID', 'Docket', 'Project ID', 'Company', 'Created On', 'Status', 'Project Value',
		'Impressions',
		( map { $$_{name} } @ServiceType_Categories ),
		( $columns{plates} ? ( 'Plates', 'Plate Cost', 'Plate Total' ) : () ),
		( $columns{production} ? ( 'Operator Assigned', 'Printed On', 'Completed On', 'Invoiced On' ) : () ),
		( $columns{stock} ? ( 'Used Stock Sheets', 'Used Stock Weight', 'Stock Cost', 'Stock', 'Quoted Stock Sheets', 'Quoted Stock Weight', 'Stock Quoted Price' ) : () ),
	];

	$variable{Data} = \@Data;

} # end sub _production_performance
sub job_size {
	if ( ! %param ) {
		ssi::setup_date_select( '/employee/reports/job_size.html', 'ordered_on_start', -31 );
		ssi::setup_date_select( '/employee/reports/job_size.html', 'ordered_on_end', '' );
		ssi::setup_date_select( '/employee/reports/job_size.html', 'completed_on_start', -31 );
		ssi::setup_date_select( '/employee/reports/job_size.html', 'completed_on_end', '' );
	} # end if
	_job_size();

	if ( $param{action} eq 'download' ) {
		misc::export_csv( $r, $log, \%variable, 'job_size_report.csv', @variable{'Header','Data'} );	
	} # end if
} # end sub job_size

sub _job_size {
	my $uri = '/employee/reports/job_size.html';

	ssi::save_params($uri, 'company_id', 
			( map { 'ordered_on_start_'.$_ } ( 'year','month','day' ) ),
			( map { 'ordered_on_end_'.$_ } ( 'year','month','day' ) ),
			( map { 'completed_on_start_'.$_ } ( 'year','month','day' ) ),
			( map { 'completed_on_end_'.$_ } ( 'year','month','day' ) ),
			'press_id', 'csr_id', 'reprint','columns','status_id',
			);

	my %columns = map { $_, $_ } split(',', $session{$uri.'?columns'} ) if $session{$uri.'?columns'};
	%columns = map { $_, 1 } qw( plates ) if ! %columns;
	$variable{columns} = \%columns;

	my %parameters; 
	if ( ( $session{user_type} ne 'A' ) and ! openprint::usergroup::is_user_in( ['Sales Admin','Reporting'], $session{user_id} ) ) {
		$parameters{salesrep_id} = $session{user_id};
		$parameters{or} = "id=(SELECT company_id FROM Users WHERE users.id=$session{user_id})";
	} elsif ( $param{csr_id} ) {
		$parameters{salesrep_id} = $param{csr_id};
	} # end if
	
	my @Companies;
	if ( %parameters ) {
		@Companies = openprint::Company->find( %parameters ) if %parameters;
		if ( ! @Companies ) {
			$variable{error} .= 'There were no companies to filter on.<br/>';
			return;
		} # end if
	} # end if
	my %companies = map { int($_->id()), $_->name() } @Companies if @Companies;

	my @Presses = openprint::Equipment->find();
	my %Presses_by_id = map { $$_{id}, $_ } @Presses;
	my %Presses_by_strid = map { $$_{strid}, $_ } @Presses;
	
	my @press_names = split(',', $session{$uri.'?press_id'} );
	my %press_names = map { $Presses_by_id{$_}{strid}, $_ } @press_names;
	my @Data;

	foreach my $Order ( openprint::Order->find(
				(@Companies ? ( company_id => ( ($session{$uri.'?company_id'} and exists $companies{$session{$uri.'?company_id'}} ) ? $session{$uri.'?company_id'} : [ keys %companies ] ) ) : () ),
				ssi::date_filter( $uri.'?ordered_on_start', 'created_on >=' ),
				ssi::date_filter( $uri.'?ordered_on_end', 'created_on <=' ),
				( $session{$uri.'?status_id'} ? ( status_id => [ split(',', $session{$uri.'?status_id'} ) ] ) : () ),
				order => ($param{order} ? $param{order} : 'id'),
				) ) {
		if ( $session{$uri.'?reprint'} ) {
			my $reprint = 0;
			foreach my $Project ( $Order->Projects() ) {
				if ( $Project->reprint() eq 'Y' ) {
					$reprint=1;
					last;
				} # end if
			} # end foreach Project
			next if ( $session{$uri.'?reprint'} eq 'Y' ) and ! $reprint;
			next if ( $session{$uri.'?reprint'} eq 'N' ) and $reprint;
		} # end if reprint

		foreach my $Project ( $Order->Projects() ) {
			my $services = $Project->services();
			my @signatures = $Project->signatures();
			next if ! @signatures;
			if ( $Project->Type()->name() ne 'MultiPagePublication' ) {
				if ( ! sets::isin( $$services{''}[0], \@signatures ) ) {
					push @signatures, $$services{''}[0];
				} # end if
			} # end if

			my $qty_index = $Project->ordered_quantity_index();

			foreach my $sig_id ( @signatures ) {
				my $Service = $Project->Service( $sig_id );
				my $sig_specs = $Service->specs();

				next if ! $Service->ordered_price();

				if ( ! $$sig_specs{UsePress} ) {
					$$sig_specs{UsePress} = $$sig_specs{'ddmPress'.$qty_index};
				} # end if

				if ( @press_names ) {
					next if ! $press_names{$$sig_specs{UsePress}};
				} # end if press_names

				if ( ! $$sig_specs{'hdnImpressionQuantity'.$qty_index} ) {
					next;
				} # end if

				push @Data, ( $Order->id(), $Order->docket(), $Project->id(), 
					 ( $$sig_specs{SignatureIndex} ? $$sig_specs{SignatureIndex} : 1 ),
					 $Order->company_name(), $Project->reference(), 
					 $Order->created_on(),
					 $$sig_specs{UsePress},
				);

				if ( $columns{plates} ) {
					if ( ! $$sig_specs{'PlateID'.$qty_index} ) {
						my $Press = $Presses_by_strid{$$sig_specs{UsePress}};

						$$sig_specs{'PlateID'.$qty_index} = $Press->specification('Plate Size').'"-'.$Press->specification('Plate Type').'Plate';
					} # end if
		
					my $Plate = openprint::Material->find_one('name'=>$$sig_specs{'PlateID'.$qty_index}) if $$sig_specs{'PlateID'.$qty_index};
					my %plate_cost = $Plate->get_price( $$sig_specs{'txtPlateQuantity'.$qty_index} ) if $Plate;
					push @Data, (
							$$sig_specs{'txtPlateQuantity'.$Project->ordered_quantity_index()},
							$$sig_specs{'PlateID'.$Project->ordered_quantity_index()},
							$plate_cost{Cost}, $plate_cost{Price}, $plate_cost{units}, $plate_cost{Price} * $$sig_specs{'txtPlateQuantity'.$Project->ordered_quantity_index()}, 
							);
				} # end if include plate info
				if ( $columns{production} ) {
					push @Data, $Project->takeover_on(), $Project->printed_on(), $Project->completed_on();
				}
				if ( $columns{stock} ) {
					my $stock_cost = 0;	
					foreach my $PI ( openprint::PaperInventory->find( docket=>$Order->docket(), 'skid_id is null'=>0 ) ) {
						my $Cost = $PI->Skid()->Cost();
						$stock_cost += $$Cost{cost};
					}
					push @Data, $stock_cost;
				}

				push @Data, (
					 $$sig_specs{'hdnImpressionQuantity'.$Project->ordered_quantity_index()},
					 $Project->status(),
					 $Project->ordered_price(), $Service->ordered_price(),
					 );
			} # end foreach sig
		} # end foreach Project
	} # end foreach Order

	$variable{Header} = [ 'Order ID', 'Docket', 'Project ID', 'Form #', 'Company', 'Reference', 'Created On', 'Press', 
				( $columns{plates} ? ( 'Plates', 'Plate Type', 'Plate Cost', 'Plate Price', 'Plate Units', 'Plate Total' ) : () ),
				( $columns{production} ? ( 'Operator Assigned', 'Printed On', 'Completed On' ) : () ),
				( $columns{stock} ? ( 'Stock Cost' ) : () ),
				'Impressions', 'Status', 'Project Value', 'Form Value' ];

	$variable{Data} = \@Data;

} # end sub _job_size

sub customer_performance {
	my $uri = $variable{uri};

	_customer_performance();
	#ssi::setup_date_select( $uri, 'ordered_on_start', -31 );
	#ssi::setup_date_select( $uri, 'ordered_on_end', 0 );
	#ssi::setup_date_select( $uri, 'not_ordered_on_start', -31 );
	#ssi::setup_date_select( $uri, 'not_ordered_on_end', 0 );

	if ( exists $param{Download} ) {
		my $sql = openprint::Company->find_sql(
          ( $param{salesrep_id} ? ( salesrep_id=>$param{salesrep_id} ) : () ),
          order=>'lower(name)',
          ( $session{$uri.'?country'} ? ( country=>$session{$uri.'?country'} ) : () ),
          );
		$$sql{sql} =~ s/\*/id/;

    my @Companies = openprint::Company->find(
					( $param{salesrep_id} ? ( salesrep_id=>$param{salesrep_id} ) : () ),
					order=>'lower(name)',
					( $session{$uri.'?country'} ? ( country=>$session{$uri.'?country'} ) : () ),
					);
		my %Companies_By_CSR = misc::make_hash_from_array('salesrep_id', @Companies);
    my @quote_ids = map { $$_{last_quote_id} } @Companies;

		my $do_not_ordered_since = 1 if Date::Calc::check_date( @session{
							$uri.'?not_ordered_on_start_year',
							$uri.'?not_ordered_on_start_month',
							$uri.'?not_ordered_on_start_day'
							} ) or Date::Calc::check_date( @session{
								$uri.'?not_ordered_on_end_year',
								$uri.'?not_ordered_on_end_month',
								$uri.'?not_ordered_on_end_day'
								} );
		my $do_ordered_since = 1 if Date::Calc::check_date( @session{
							$uri.'?ordered_on_start_year',
							$uri.'?ordered_on_start_month',
							$uri.'?ordered_on_start_day'
							} ) or Date::Calc::check_date( @session{
								$uri.'?ordered_on_end_year',
								$uri.'?ordered_on_end_month',
								$uri.'?ordered_on_end_day'
								} );
		my @status_ids = map { $$_{id} } openprint::Order_Status->find(name=>['Complete','Picked Up','Shipped','Waiting For QA Approval','Waiting For Customer Approval','Order Submitted','In Production','Waiting For Pickup','Re-Opened','Pending Deposit','Paid','Complete' ]);

		my @header = ( 'CSR', 'Company Name', 'Country', 'Contact Name','Contact Phone','Contact Email', '# of Orders', 'Order Value', 'Date of Last Order', 'Date of Last Quote', 'Payment Cycle', 'Discount/Markup' ,'Credit Card Fee','CSR Commission');
		my @data;
		my @csr_ids;
		if ( ( $session{user_type} ne 'A' ) and ! openprint::usergroup::is_user_in( ['Sales Admin','Reporting'], $session{user_id} ) ) {
			@csr_ids = ( $session{user_id} );
		} elsif ( $param{salesrep_id} ) {
			@csr_ids = ( $param{salesrep_id} );
		} else {
			@csr_ids = map { $_->id() } openprint::User->find( company_id=>$config{owner_id}, type=>['E','A'], 'usergroup any'=>'Sales', order=>'lower(firstname),lower(lastname)');
		} # end if

		my @Orders = openprint::Order->find( 
      'company_id in' => $sql,
      ssi::date_filter( $uri.'?ordered_on_start', 'created_on >=' ),
      ssi::date_filter( $uri.'?ordered_on_end', 'created_on <=' ),
      status_id => \@status_ids,
    );
    my ($min_order_id, $max_order_id ) = (undef,undef);
    foreach my $Order ( @Orders ) {
      $min_order_id = $$Order{id} if (!defined($min_order_id)) or ($min_order_id > $$Order{id});
      $max_order_id = $$Order{id} if (!defined($max_order_id)) or ($max_order_id < $$Order{id});
    }
    my @order_ids = map { $$_{id} } @Orders;
		my %orders_by_company = misc::make_hash_from_array('company_id', @Orders);
		my @Quotes = openprint::Quote->find( id=>\@quote_ids,
    #'company_id in' => $sql,
      ssi::date_filter( $uri.'?ordered_on_start', 'created_on >=' ),
      ssi::date_filter( $uri.'?ordered_on_end', 'created_on <=' ),
      limit => 10000,
    );
    my %quotes_by_company = misc::make_hash_from_array('company_id', @Quotes);

		my %not_ordered_since;
		my @Orders_Since = openprint::Order->find(
		'company_id in' => $sql,
				ssi::date_filter( $uri.'?not_ordered_on_start', 'created_on >=' ),
				ssi::date_filter( $uri.'?not_ordered_on_end', 'created_on <=' ),
				status_id => \@status_ids,
				) if $do_not_ordered_since;
		foreach my $Order ( @Orders_Since ) {
			$not_ordered_since{$$Order{company_id}} = 1;
		}

    my @invoice_ids;
    my %OI_By_Invoice_Id;
    my %OI_By_Order_Id;
    my ( $min_invoice_id, $max_invoice_id ) = ( undef, undef );

    foreach ( openprint::Order_Invoice->find(
        order_id=>\@order_ids,
        #'order_id <=' => $max_order_id,
        #'order_id >=' => $min_order_id,
        order=>'order_id') ) {

      $OI_By_Invoice_Id{$$_{invoice_id}} = [] if !$OI_By_Invoice_Id{$$_{invoice_id}};
      push @{$OI_By_Invoice_Id{$$_{invoice_id}}}, $_;

      $OI_By_Order_Id{$$_{order_id}} = [] if !$OI_By_Order_Id{$$_{order_id}};
      push @{$OI_By_Order_Id{$$_{order_id}}}, $_;

      push @invoice_ids, $$_{invoice_id};
      $min_invoice_id = $$_{invoice_id} if (!defined($min_invoice_id)) or ($min_invoice_id > $$_{invoice_id});
      $max_invoice_id = $$_{invoice_id} if (!defined($max_invoice_id)) or ($max_invoice_id < $$_{invoice_id});
    } # end foreach Order_Invoice

    my @Invoices = openprint::Invoice->find(
        'id <=' => $max_invoice_id,
        'id >=' => $min_invoice_id,
        #id=>\@invoice_ids
      );
    die if !@Invoices;

    foreach my $Invoice (@Invoices) {
      if ( $OI_By_Invoice_Id{$$Invoice{id}} ) {
        foreach my $OI ( @{$OI_By_Invoice_Id{$$Invoice{id}}} ) {
          $$OI{Invoice} = $Invoice;
          #$log->debug("Setting invoice for $$OI{invoice_id} order $$OI{order_id} = $$OI{Invoice}");
        } # end foreach OI
      } else {
        #$log->debug("NO OI_BY_INVOICE_ID for $$Invoice{id}");
      } # end if have ois for this invoice
    }

     my %Payments = misc::make_hash_from_array('order_id',
          openprint::Payment->find(
            'order_id <=' => $max_order_id,
            'order_id >=' => $min_order_id,
            order=>$openprint::Payment::fields{received_on}.' DESC'),
          );

    foreach my $Order ( @Orders ) {
      $$Order{Invoices} = $OI_By_Order_Id{$$Order{id}} ? $OI_By_Order_Id{$$Order{id}} : [];
      $$Order{Payments} = $Payments{$$Order{id}} ?$Payments{$$Order{id}} : [];
    }

		foreach my $csr_id ( @csr_ids ) {
			my $CSR = new openprint::User($csr_id);

			next if ! $Companies_By_CSR{$csr_id};

			foreach my $Company ( @{$Companies_By_CSR{$csr_id}} ) {
				my $order_total;
				my $payment_cycle;

				next if $do_ordered_since and !$orders_by_company{$$Company{id}};
        next if $do_not_ordered_since and $not_ordered_since{$$Company{id}};

				if ( $session{$uri.'?has_discount'} ne '' ) {
					next if $session{$uri.'?has_discount'} eq 'Y' and ! $Company->discount();
					next if $session{$uri.'?has_discount'} eq 'N' and $Company->discount();
				}

				foreach my $Order ( @{ $orders_by_company{$$Company{id}} } ) {
					$order_total += $Order->Currency()->convert_from( $Order->total() );
					$payment_cycle += $Order->payment_days();
				} # end foreach Order

				$payment_cycle = @{ $orders_by_company{$$Company{id}} } ? int( $payment_cycle / scalar @{ $orders_by_company{$$Company{id}} } ) : 0;
				if ( $param{payment_cycle} ) {
					if ( $payment_cycle > $param{payment_cycle} ) {
						next;
					} # end if
				} # end if

				my $Contact = openprint::User->find_one( company_id=>$Company->id(), administrator=>1, web_active=>1, order=>'id');
				$Contact = openprint::User->find_one( company_id=>$Company->id(), web_active=>1, order=>'id') if ! $Contact;
				$Contact = openprint::User->find_one( company_id=>$Company->id(), order=>'id') if ! $Contact;
				$Contact = new openprint::User() if ! $Contact;

				my $LastOrder = $orders_by_company{$$Company{id}}[ @{ $orders_by_company{$$Company{id}} } - 1] if 
					$orders_by_company{$$Company{id}} and @{ $orders_by_company{$$Company{id}} };
				my $LastQuote = $quotes_by_company{$$Company{id}}[ @{ $quotes_by_company{$$Company{id}} } - 1] if 
					$quotes_by_company{$$Company{id}} and @{ $quotes_by_company{$$Company{id}} };

				push @data, ( $CSR->name(),
						$Company->name(), 
						$Company->country(), 
						$Contact->name(), $Contact->phone(), $Contact->email(),
						Number::Format::format_number( scalar @{ $orders_by_company{$$Company{id}} } ), 
						$order_total,
						( $LastOrder ? ssi::format_csv_date($LastOrder->created_on()) : 'never' ),
						( $LastQuote ? ssi::format_csv_date($LastQuote->created_on()) : 'never' ),
						$payment_cycle . ' days',
						$Company->discount(),
						$Company->credit_card_fee(),
						$Company->csr_commission(),
						);
			} # end foreach Company
		} # end foreach CSR
		misc::export_csv( $r, $log, \%variable, 'customer_performance.csv', \@header, \@data );
	} # end if
} # end sub customer_performance

sub _customer_performance {
	my $uri = '/employee/reports/customer_performance.html';
	ssi::save_params($uri,  
			'ordered_on_start_year','ordered_on_start_month','ordered_on_start_day',
			'ordered_on_end_year','ordered_on_end_month','ordered_on_end_day', 
			'not_ordered_on_start_year','not_ordered_on_start_month','not_ordered_on_start_day',
			'not_ordered_on_end_year','not_ordered_on_end_month','not_ordered_on_end_day', 
			'salesrep_id','payment_cycle','country','has_discount','has_credit_card_fee','has_csr_commission' );
} # end sub _customer_performance

sub prepress_productivity {
	ssi::setup_date_select( '/employee/reports/prepress_productivity.html', 'ordered_on_start', -31 );
	ssi::setup_date_select( '/employee/reports/prepress_productivity.html', 'ordered_on_end', 0 );
} # end sub prepress_productivity

sub project_log {
	_project_log();
	ssi::setup_date_select( '/employee/reports/project_log.html', 'created_on_start', -7 );
	ssi::setup_date_select( '/employee/reports/project_log.html', 'created_on_end', '' );
} # end sub project_log

sub _project_log {
	ssi::save_params('/employee/reports/project_log.html',
			( map { 'created_on_start_'.$_ } ( 'year','month','day' ) ),
			'company_id','user_id',
			);
} # end sub _project_log

sub user_activity {
	_user_activity();
	ssi::setup_date_select($r->uri(), 'period_start', -7);
	ssi::setup_date_select($r->uri(), 'period_end', '');
}

sub _user_activity {
  my $uri = '/employee/reports/user_activity.html';
	ssi::save_params($uri, 
			'company_id','user_id',
			(map {'period_start_'.$_} ('year','month','day')),
			(map {'period_end_'.$_} ('year','month','day')),
			);
	$variable{Results} = [];

	if ( ! $param{user_id} ) {
		$variable{error} .= 'You must select a user to see results.<br/>';
		return;
	}

	my $parser = 'DateTime::Format::Pg';

	my $start_dt = Date::Calc::check_date(map { $session{$uri.'?period_start_'.$_} } ( 'year','month','day' )) ?
		DateTime->new(
				( map { $_ => $session{$uri.'?period_start_'.$_} } ( 'year','month','day' ) ), 
				hour=>0, minute=>0, second=>0,
				time_zone	=> $openprint::TZ)
		: 
		DateTime->now()
		;
	my $end_dt = Date::Calc::check_date(map { $session{$uri.'?period_end_'.$_} } ( 'year','month','day' )) ?
		DateTime->new(
				( map { $_ => $session{$uri.'?period_end_'.$_} } ( 'year','month','day' ) ),
				hour=>23, minute=>59, second=>59,
				time_zone	=> $openprint::TZ)
		:
		DateTime->now()
		;
$log->debug("Start $start_dt => $end_dt");
	my $current_dt = $start_dt;
	my @action_ids = map { $$_{id} } openprint::Log_Action->find(name=>['Login']);

	while ( $current_dt <= $end_dt ) {
		my $next_week = $current_dt->clone();
		$next_week->add(weeks=>1);
		my @Logins = openprint::Log->find(
				'date_time >=' => $parser->format_datetime($current_dt),
				'date_time <=' => $parser->format_datetime($next_week),
				action_id=>\@action_ids,
				user_id=>$session{$uri.'?user_id'},
				);

		my @Projects = openprint::Project->find(
				'created_on >=' => $parser->format_datetime($current_dt),
				'created_on <=' => $parser->format_datetime($next_week),
				user_id=>$session{$uri.'?user_id'},
				);
		my @Quotes = openprint::Quote->find(
				'created_on >=' => $parser->format_datetime($current_dt),
				'created_on <=' => $parser->format_datetime($next_week),
				user_id=>$session{$uri.'?user_id'},
				);
		my @Orders = openprint::Order->find(
				'created_on >=' => $parser->format_datetime($current_dt),
				'created_on <=' => $parser->format_datetime($next_week),
				user_id=>$session{$uri.'?user_id'},
				);
		push @{$variable{Results}}, {
			logins=>\@Logins,
				projects => \@Projects,
quotes => \@Quotes,
orders => \@Orders,
				week=>$current_dt->clone(),
				next_week=>$next_week,
		};
		$current_dt = $next_week;
	} # end while
		
}

1;
__END__
