package eprint::admin_accounting;

use Text::CSV_XS;
use strict;

require eprint::order;
require misc;
use sql ();


use Data::Dumper;

use PQS::Object::order;

sub payment {
	my ( $r, $log, $dbh, $variable ) = @_;

	my $cust_id = $r->param('ddmCustomers');
	my $pay_total = $r->param('add_payment');
	if ( $pay_total =~ /[^-\$\d\.]/ ) {
		return misc::error( $log, $dbh, $variable, 'Invalid Amount', 
							'Please enter a valid monetary amount.' );
	} # end if

	my $error;
	if ( $pay_total ) {
		$dbh->begin_work;
		my $trans_id = $dbh->selectrow_array(q{
			SELECT nextval('payment_trans_seq')
		});
		foreach my $p ( $r->param() ) {
			if ( $p =~ /payment_(.*)/ ) {
				my $order_id = $1;
				my $amount   = $r->param($p);
				my $desc     = $r->param('Description'); 
				if ( $amount > 0 ) {
					$error = make_payment($log, $dbh, $variable, $cust_id, 
								      	  $order_id, $amount, $desc, $trans_id);
				}
				last if $error;
			}
		}
		my $ins_total = $dbh->selectrow_array(q{
			SELECT SUM(curamount) FROM tbl_payments WHERE strtransactionid = ?
		}, undef, $trans_id);
		if ( $ins_total == $pay_total ) {
			$dbh->commit;
		} else {
			return misc::error( $log, $dbh, $variable, 'Invalid Amount', $error );
			$dbh->rollback;
		}
	}
	search( $r, $log, $dbh, $variable, 1);

}

sub make_payment {
	my ( $log, $dbh, $variable, $cust_id, 
		 $order_id, $amount, $desc, $trans_id ) = @_;

	my ( $cur_name, $cur_symbol, $order_total, $down_payment )
		 = $dbh->selectrow_array(q{
			SELECT 
					strCurrencyName, strCurrencySymbol, 
					curtotalsale,    curdownpayment 
			FROM   tbl_Orders 
			WHERE  lngOrderID = ?
	}, undef, $order_id);

	my ( $payments ) = $dbh->selectrow_array(q{
		SELECT SUM(curamount) from tbl_payments where lngorderid = ?
	}, undef, $order_id);
	

	# Make our floting point issues fly awy.
	$payments = int(($payments + $amount)*100)/100;

	if ( $payments > $order_total ) {
		return 
		"Invalid Payment Amount: ${cur_symbol}$amount 
		 For Order # $order_id";
	}

	my @data = ( 
		'lngOrderID',		$order_id,
		'lngCustomerIndex',	$cust_id,
		'curAmount',		$amount,
		'dtmDate',			'NOW()',
		'strMethod',		'Manual',
		'strCurrencyName',	$cur_name,
		'strCurrencySymbol',$cur_symbol,
		'strDescription',	$desc,
		'strTransactionId',	$trans_id
	);


	sql::insert( $log, $dbh, 'tbl_Payments', @data );


	my $order = new PQS::Object::order($order_id);

	$order->status_tree();

	#	my $in_production;
	#	if ( $payments == $order_total ) {
	# Set Status of Order to Paid if Complete
	#		sql::update( $log, $dbh, 'tbl_Orders', 
	#			"lngOrderID='$order_id'", 
	#		'strStatus', 'Paid', 'paid', 1 );
	#	$in_production = 1;
	#} 
	#elsif( $payments >= $down_payment ) {
	#	# Set status of Order to 'In Production' if downpayment has been met.
	#	sql::update( $log, $dbh, 'tbl_Orders', 
	#		"lngOrderID='$order_id' AND strStatus='Pending Deposit'", 
	#		'strStatus', 'In Production' );
	#	$in_production = 1;
	#}
	#if ( $in_production ) {
	#
	#	# Put the Projects into production if they were 'Peding Deposit'
	#	my $pids = $dbh->selectcol_arrayref(q{
	#		SELECT lngProjectIndex FROM tbl_Order_Contents WHERE lngOrderID= ?
	#		AND lngProjectIndex Is Not NULL
	#	}, undef, $order_id);
	#
	#	foreach my $pid ( @{$pids} ) {
	#		sql::update( $log, $dbh, 'tbl_Projects', 
	#		"lngProjectIndex='$pid' AND strStatus='Pending Deposit'", 
	#			'strStatus', 'In Production' );

	#		sql::update( $log, $dbh, 'tbl_project_contents', 
	#		"lngProjectIndex='$pid' AND strStatus='Pending Deposit'", 
	#			'strStatus', 'In Production' );
	#	} # end foreach
	#}
	#

	return;
}


sub search {
	my ( $r, $log, $dbh, $variable, $hide_paid ) = @_;
	my ( $search, @employees );
	if ( $r->param('mark_billed') ) {
		$dbh->do(q{
			UPDATE tbl_orders SET bill_date = now() WHERE lngorderid = ?
		}, undef, $r->param('mark_billed'));
	}

#wsc	$r->param('ddmBalance' => 'Owing') unless $r->param('btnFunction');
	
	ssi::get_start_end_dates( $log, $dbh, $variable,
			$r->param('ddmStartYear') 	|| undef,
			$r->param('ddmStartMonth')	|| '01',
			$r->param('ddmStartDay') 	|| undef,
			$r->param('ddmEndYear') 	|| undef,
			$r->param('ddmEndMonth') 	|| undef,
			$r->param('ddmEndDay') 		|| undef );


	$_ = "SELECT lngCustomerID, strCompanyName FROM tbl_Customer ORDER BY lower(strCompanyName)";
	$$variable{'ddmCustomers'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmCustomers') );

	$_ = "SELECT distinct strStatus, strStatus FROM tbl_Orders 
			WHERE cancelled <> true AND strStatus <> 'Incomplete'
			ORDER BY strStatus";
	$$variable{'ddmStatus'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmStatus') );

	$_ = "SELECT lngIndex, strName from tbl_Service_Categories ORDER BY strName";
	$$variable{'ddmCategories'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmCategories') );
	$_ = "SELECT lngIndex, strName FROM tbl_Service_Types ORDER BY strName";
	$$variable{'ddmServices'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmServices') );
	$_ = "SELECT lngUserID, strFirstName || ' ' || strLastName 
			FROM tbl_Customer_Users WHERE chrType='E' OR chrType='A'";
	$$variable{'ddmEmployees'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmEmployees') );

	$$variable{'dblTotal1'} = $r->param('dblTotal1');
	$$variable{'dblTotal2'} = $r->param('dblTotal2');


		my $sql = q{
			SELECT lngOrderID as order_id, 
				   tbl_orders.lngcustomerid as cust_id,
				   to_char(dtmOrderDate, 'MM/DD/YYYY') as date,
				   to_char(bill_date, 'MM/DD/YYYY') as bill_date,
				   tbl_customer.strCompanyName as comp_name, 
				   strPONumber as ponum, 
				   curTotalSale as total,
				   strstatus as status,
				   ( SELECT SUM(curAmount) 
                      FROM tbl_Payments 
                      WHERE tbl_payments.lngorderid = tbl_orders.lngorderid) as payments
			FROM 
					tbl_Orders, tbl_customer
			WHERE  	  
				tbl_orders.lngcustomerid = tbl_customer.lngcustomerid
				AND ysnfinished
			    AND NOT cancelled
		};

		my @params;
#		if ( $r->param('ddmStartMonth') ) {
		if ( $variable->{StartDate} ) {
			push @params, $variable->{StartDate}, $variable->{EndDate};
			$sql .= "   AND dtmOrderDate BETWEEN ? AND ? ";
		}

		if ( $r->param('ddmStatus') ) {;
 			$sql .= " AND tbl_Orders.strStatus = ?"; 
			push @params, $r->param('ddmStatus');
		}
		if ( $r->param('ddmCustomers') ) {
			$sql .= " AND tbl_Orders.lngCustomerID = ?";
			push @params, $r->param('ddmCustomers');
		}
		if ( $r->param('dblTotal1') and $r->param('dblTotal2') ) {
			$sql .= " AND tbl_Orders.curTotalSale BETWEEN ? AND ?";
			push @params, $r->param('dblTotal1'), $r->param('dblTotal2');
		}
		if ($r->param('ddmEmployees')) {
			$sql .= " AND tbl_Orders.lngCustomerId IN 
						( Select lngCustomerId FROM tbl_Customer where lngSalesPerson = ? )";
			push @params, $r->param('ddmEmployees');
		}

		$sql .= " ORDER BY tbl_Orders.lngOrderID";


		my $orders = $dbh->prepare_cached($sql);
		$orders->execute(@params);
		my %cust_list;
		while (my $order = $orders->fetchrow_hashref) {

			$order->{balance} = $order->{total} - $order->{payments};

			next if $r->param('ddmBalance') eq 'Paid' && $order->{balance} > 0;
			next if $r->param('ddmBalance') eq 'Owing' && $order->{balance} <= 0;

			unless (     $r->param('ddmStatus') ne 'Cancelld' 
					 and $order->{status}       eq 'Cancelled'
			) {
				push @{ $cust_list{$order->{cust_id}}{orders} }, $order; 
				$cust_list{$order->{cust_id}}{name} = $order->{comp_name};
				$cust_list{$order->{cust_id}}{cust_total} += $order->{total};
				$cust_list{$order->{cust_id}}{cust_bal} += $order->{balance};
			}
		}

		map { 
				push @{ $variable->{ACCOUNTS} }, 
					 {  
					   name       => $cust_list{$_}{name}, 
					   orders     => $cust_list{$_}{orders},
					   cust_total => $cust_list{$_}{cust_total},
					   cust_bal   => $cust_list{$_}{cust_bal},
					   cust_id    => $_
					 };
				$variable->{TOTAL_SALES} += $cust_list{$_}{cust_total};
				$variable->{BALANCE} += $cust_list{$_}{cust_bal};
	 	} keys %cust_list; 
		
		$variable->{__FillInForm}{ddmBalance} = $r->param('ddmBalance');


        $$variable{'TOTAL_SALES'} = sprintf( "%.2f", $$variable{'TOTAL_SALES'} );
        $$variable{'BALANCE'} = sprintf( "%.2f", $$variable{'BALANCE'} );
} # end sub order_report


sub details {
    my ( $r, $log, $dbh, $variable ) = @_;

    my $order_id = $r->param('order_id');
    $order_id = $r->param('hdnOrderID') if $order_id eq '';

    # Used for optional data in custom order include
    # for Avenue4
    $variable->{is_invoice} = 1;


	$log->debug("OI: $order_id ");

    if ( $r->param('btnFunction') eq 'Send Email Invoice' ) {
		eprint::order::send_invoice( $r, $log, $dbh, $order_id );
    } 
    elsif ( $r->param('btnFunction') eq 'Add to Order' ) {
        if ( $r->param('txtAddToOrderAmount') ne '' ) {
            my $custom_price = $r->param('txtAddToOrderAmount');
			if ( ( ! $custom_price ) or $r->param('txtAddToOrderAmount') =~ /[^-\$\d\.]/ ) {
                return misc::error( $log, $dbh, $variable, 'Error', 'Price is not valid' );
            } # end if
            if ( ! $r->param('txtAddToOrderDescription') ) {
                return misc::error( $log, $dbh, $variable, 'Error', 'Description Required' );
            } # end if

            my $description = $r->param('txtAddToOrderDescription') || '';

            sql::insert( $log, $dbh, 'tbl_Order_Contents',
                lngOrderId      => $order_id,
                lngProjectIndex => undef,
                strDescription  => $description,
                curSalesPrice   => $custom_price,
                daterequired    => 'NOW()',
            );
        }
        
		my @data;
		my $total_price = $r->param('TOTAL');
		push @data, 'curTotalSale', $total_price if $total_price > 0;
		push @data, 'curFedTax',    $r->param('GST')  if $r->param('GST') ne '';
		push @data, 'curProvTax',   $r->param('PST')  if $r->param('PST') ne '';
		push @data, 'curHarmTax',   $r->param('HST')  if $r->param('HST') ne '';
		sql::update( $log, $dbh, 'tbl_Orders',"lngOrderID='$order_id'", @data );
		
    } 
    elsif ( $r->param('btnFunction') eq 'Update') {

		my @data;
		my $total_price = $r->param('TOTAL');
		push @data, 'curTotalSale', $total_price if $total_price > 0;
		push @data, 'curFedTax',    $r->param('GST')  if $r->param('GST') ne '';
		push @data, 'curProvTax',   $r->param('PST')  if $r->param('PST') ne '';
		push @data, 'curHarmTax',   $r->param('HST')  if $r->param('HST') ne '';
		sql::update( $log, $dbh, 'tbl_Orders',"lngOrderID='$order_id'", @data );

		eprint::order::get_misc( $log, $dbh, $variable, $order_id );

		my @data;
		my $total_price = $$variable{'SUB_TOTAL'};
		$total_price += $$variable{'GST'};
		$total_price += $$variable{'PST'};
		$total_price += $$variable{'HST'};
		push @data, 'curTotalSale', $total_price if $total_price > 0;
		sql::update( $log, $dbh, 'tbl_Orders',"lngOrderID='$order_id'", @data ) if @data;

    } 
    elsif ( $r->param('btnFunction') eq 'Save Edit' ) {

	die("Why are you here? This code is no longer used -- Will");
#        $log->debug(" *** SAVING ORDER EDIT *** ");
#	my $cookie = '';
#
#	$r->param('hiddenOrderID' => $order_id);
#
#
#        my $error = eprint::order::store_order_info( $r, $log, $dbh, $cookie, $variable );
#        if ( $error ne '' ) {
#            return misc::error( $log, $dbh, $variable, 'Error', $error );
#        } # end if
    } 
    elsif ( $r->param('btnFunction') eq 'Add Payment' ) {
		my $cust_id = $dbh->selectrow_array(q{
			SELECT lngCustomerid FROM tbl_orders where lngorderid = ?
		}, undef, $order_id);
		my $trans_id = $dbh->selectrow_array(q{
			SELECT nextval('payment_trans_seq') 
		} );
		my $amount = $r->param('Amount');
		my $desc = $r->param('Description');
		my $error = make_payment($log, $dbh, $variable, $cust_id, 
					      	  $order_id, $amount, $desc, $trans_id);
        if ( $error ne '' ) {
            return misc::error( $log, $dbh, $variable, 'Error', $error );
        } # end if
		
    } 
    # Remove the specificied line items from the order. Note: You really
    # shouldn't be able to remove them, just cancel them.
    elsif ( $r->param('btnFunction') eq 'Delete' ) {
        my @line_items   = $r->param('delete');
        my $placeholders = join q{, }, (('?') x @line_items);

        # Remove all the specified items (Only line items, not projects).
        $dbh->do(qq{
            DELETE FROM tbl_order_contents 
            WHERE lngcontentindex IN ($placeholders)
              AND lngprojectindex IS NULL
        }, {}, @line_items) if @line_items;

		my @data;
		push @data, 'curFedTax',    $r->param('GST')  if $r->param('GST') ne '';
		push @data, 'curProvTax',   $r->param('PST')  if $r->param('PST') ne '';
		push @data, 'curHarmTax',   $r->param('HST')  if $r->param('HST') ne '';
		sql::update( $log, $dbh, 'tbl_Orders',"lngOrderID='$order_id'", @data ) if @data;

		eprint::order::get_misc( $log, $dbh, $variable, $order_id );

		my @data;
		my $total_price = $$variable{'SUB_TOTAL'};
		$total_price += $$variable{'GST'};
		$total_price += $$variable{'PST'};
		$total_price += $$variable{'HST'};
		push @data, 'curTotalSale', $total_price if $total_price > 0;
		sql::update( $log, $dbh, 'tbl_Orders',"lngOrderID='$order_id'", @data ) if @data;
    } 
    elsif ( $r->param('btnFunction') eq 'Cancel' ) {
		eprint::order::cancel_order($r, $log, $dbh, $order_id );
	}

	eprint::order::get_invoice_to( $log, $dbh, $variable, $order_id );
	eprint::order::get_ship_to( $log, $dbh, $variable, $order_id );
	$$variable{'CCITYPROVCOUNTRY'} = misc::build_city_prov_country(@$variable{'txtCity','txtStateProvince','txtCountry'} );
	$$variable{'FCITYPROVCOUNTRY'} = misc::build_city_prov_country(@$variable{'txtShippingCity','txtShippingStateProvince','txtShippingCountry'} );
	eprint::order::get_misc( $log, $dbh, $variable, $order_id );
	eprint::order::get_projects( $log, $dbh, $variable, $order_id );

	$variable->{'Terms'} = scalar $dbh->selectrow_array(q{
        SELECT lngTerms 
        FROM tbl_Customer_Credit
        WHERE lngCustomerindex = 
            ( SELECT lngCustomerID
        FROM tbl_orders where 
        lngorderID = ?
        )
    },undef, $order_id);


	my @pids = ();
	map { push @pids, $_->{pid} } @{$variable->{PROJECTS}}; 

    for my $pid (@pids) {
        my %hash;
        eprint::docket::summary_display($r, $log, $dbh, \%hash, $pid, undef, 1);
        push @{$variable->{projects}}, \%hash;
    }


	$$variable{'ORDER_ID'} = $order_id;

	$_ = "SELECT lngIndex, to_char(dtmDate,'MM/DD/YYYY'), strMethod, strDescription, curAmount, strCurrencyName, strCurrencySymbol\n".
		"FROM tbl_Payments WHERE strSessionID IS NULL AND lngOrderID='$order_id' ORDER BY dtmDate";
	@{$$variable{'PAYMENTS'}} = sql::sql_statement( $log, $dbh, $_ );


} # end sub details


1;

