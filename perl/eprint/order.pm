package eprint::order;
use strict;

use Apache2::Const         qw(:common HTTP_MOVED_TEMPORARILY);
use Apache2::ServerUtil;
use Business::OnlinePayment;
use Date::Calendar::Profiles  qw( $Profiles );
use Date::Calendar;
use Mail::Sendmail;
#use MIME::QuotedPrint;
use Encode;


use File::Path;

use PQS::Util       qw(verify_cc);
use sql             ();
use eprint::service ();
use eprint::project qw(:common has_pdf_template);

use Mail;

use PQS::model::payment ();
use PQS::model::order ();
use PQS::Object::product ();
use PQS::Object::project ();
use PQS::model::order ();
use PQS::Object::promotion();


require configuration;
require eprint::customer;
require eprint::customer_credit;
require eprint::obj_customer;
require eprint::user;
require eprint::docket;
require eprint::print_project;
require eprint::products;


sub delete_order {
    my ($log, $dbh, $id) = @_;

    $id =~ tr/0-9//cd;

    # die "Invalid order ID." unless $id;
    return unless $id;

    eprint::inventory::delete_by_order($log, $dbh, $id);
    $dbh->do(q{DELETE FROM tbl_Order_Contents WHERE lngOrderID = ?}, undef, $id);
    $dbh->do(q{DELETE FROM tbl_Orders         WHERE lngOrderID = ?}, undef, $id);
}

#remove all orders associated with a customer
sub delete_customers_orders {
  my ($log, $dbh, $id) = @_;

  $id =~ tr/0-9//cd;

  # die "Invalid order ID." unless $id;
  return unless $id;

  my $orders = $dbh->selectcol_arrayref("select lngorderid from tbl_orders where lngcustomerid = ?", undef, $id);
  for my $order (@$orders) {
    delete_order($log, $dbh, $order);
  }
}

#remove all orders associated with a user
sub delete_users_orders {
  my ($log, $dbh, $id) = @_;

  $id =~ tr/0-9//cd;

  # die "Invalid order ID." unless $id;
  return unless $id;

  my $orders = $dbh->selectcol_arrayref("select lngorderid from tbl_orders where lnguserid = ?", undef, $id);
  for my $order (@$orders) {
    delete_order($log, $dbh, $order);
  }

  $orders = $dbh->selectcol_arrayref("select lngorderid from tbl_orders where lngemployeeid = ?", undef, $id);
  for my $order (@$orders) {
    delete_order($log, $dbh, $order);
  }
}

sub delete_unfinished_orders {
    my ($log, $dbh, $cookie) = @_;
    
    # clean out old orders
    my $temp = "SELECT lngOrderID FROM tbl_Orders WHERE strSessionID = '$cookie' and strStatus = 'Incomplete'";
    
    foreach my $order ( sql::sql_statement( $log, $dbh, $temp) ) {
        delete_order( $log, $dbh, $order );
    }
}

sub get_unfinished_order {
    my ( $log, $dbh, $cookie, $my_cust_id, $my_user_id ) = @_;

    $_ = "SELECT MAX(lngOrderID) FROM tbl_Orders WHERE strSessionID='$cookie' AND strStatus='Re-Opened'";
    my ( $order_id ) = sql::sql_statement( $log, $dbh, $_ );
    if ( ! $order_id ) {

        $_ = "SELECT lngOrderID, lngCustomerID, lngUserID FROM tbl_Orders 
			  WHERE strSessionID='$cookie' AND strStatus='Incomplete' ORDER by lngOrderID Desc Limit 1";

print STDERR "GET UNFINISHED ORDER: $_ \n";
        ( $order_id, my $cust_id, my $user_id ) = sql::sql_statement( $log, $dbh, $_ );

print STDERR "GET UNFINISHED ORDER: $_ - $order_id \n";

        if ( $order_id ) {
            if ( $cust_id != $my_cust_id ) {
                sql::update( $log, $dbh, 'tbl_Orders', "lngOrderID = '$order_id'", 'lngCustomerID', $my_cust_id );
            }
            if ( $user_id != $my_user_id ) {
                sql::update( $log, $dbh, 'tbl_Orders', "lngOrderID = '$order_id'", 'lngUserID', $my_user_id );
            }
        }
    }

    return $order_id;
}

sub get_order_id {
    my ( $log, $dbh ) = @_;
    my ( $order ) = sql::sql_statement( $log, $dbh, 'SELECT MAX(lngOrderID) FROM tbl_Orders' );

    $order =~ /(\d\d\d\d)/;
    if ( $1 != ( 1900 + (localtime(time))[5] ) or $order eq '' ) {
        return 1900 + (localtime(time))[5] . '0001';
    }
    return $order + 1;
}

sub check_customer_account {
    my ( $log, $dbh, $cookie, $variable  ) = @_;
    my $error = '';

    $_ = "SELECT SUM(curAmount) FROM tbl_Payments WHERE lngCustomerIndex='$$variable{'cust_id'}' AND strSessionID IS NULL";
    my ( $payments ) = sql::sql_statement( $log, $dbh, $_ );
    $_ = "SELECT SUM(curTotalSale) FROM tbl_Orders WHERE lngCustomerID='$$variable{'cust_id'}'\n".
        "AND (strStatus='Pending Deposit' OR strStatus='In Production' OR strStatus='Paid' )";
    my ( $debt ) = sql::sql_statement( $log, $dbh, $_ );
    
    $_ = "SELECT lngTerms, dblCreditLimit, ysnCreditHold FROM tbl_Customer_Credit WHERE lngCustomerIndex='$$variable{'cust_id'}'";
    my ( $terms, $creditlimit, $credithold ) = sql::sql_statement( $log, $dbh, $_ );

    if ( $credithold eq 'Y' ) {
        $error = 'Your credit account is on hold, you will not be able to place orders.  Click <a href="/main/account/credit_application.html">here</a> to apply for a credit account now.';
        return ( 0, $error );
    }
    elsif ( !$terms and $debt > $payments ) {
        $error = 'Because you do not have a credit account, your previous order must be paid in full before another order is placed.  Click <a href="/main/account/credit_application.html">here</a> to apply for a credit account now.';
        return ( 0, $error );
    }
    elsif ($debt - $payments > $creditlimit) {
        if (!configuration::get_value($log, $dbh, 'AllowAccountOverDraft')) {
            $error = 'This order would exceed your remaining credit balance.  Please make a payment before placing another order.  To apply for additional credit click <a href="/main/account/credit_application.html">here</a>.';
            return ( 0, $error );
        }
    }

}

sub add_product_to_order {
	my ( $cookie, $var, $product, $qty, $subgroup, $jobname, $versions, $quote_price, $order_id ) = @_;


	my $log = session::log;
	my $dbh = session::dbh;

#	my $error = check_customer_account( $log, $dbh, $cookie, $var);

#	return ( 0, $error) if $error;

	
	$cookie = $var->{cookie} unless $cookie;

	

    $order_id ||= get_unfinished_order(
        $log, $dbh, $cookie, $var->{cust_id}, $var->{user_id}
    ) unless $order_id;
    
    $order_id ||= create_order($log, $dbh, $cookie, $var);

	my $list_index = eprint::customer::get_product_list();

	my $prod = new PQS::Object::product($product);
	# my $price =  defined $quote_price ? $quote_price : $prod->price($var->{cust_id}, $qty, $versions);

	my $price = $quote_price + $prod->price($var->{cust_id}, $qty, $versions);

	$qty = $qty * $versions if $versions > 1;
    
	print STDERR "HAVE: QTY: $qty PRICE: $price QPrice: $quote_price VERSIONS: $versions Name: $jobname \n";
	die("No Product Quantity for Product: $product VERSIONS: $versions") unless $qty;


	print STDERR "ADDD PRODUCT: $product Q: $qty V: $versions PRICE: $price \n";

	die("No Price Found for product: $product ", Dumper($prod) ) unless $price or $prod->{specs}{kit} or defined $quote_price;


	
	insert_prod($log, $dbh, $order_id, $product, $qty, $price, $subgroup, $jobname, $versions);
	


	# Get the next insert id in the sequence.
    my $ocid = $dbh->last_insert_id('',qw(public tbl_order_contents lngcontentindex));

	my $days = $prod->spec('delivery_days') || 7;
	$days .= ' days';

	$dbh->do(q{Update tbl_orders SET dtmrequireddate = now() + ?  WHERE lngorderid = ?}, undef, $days, $order_id);

print STDERR "SET DELIVERY DATE: $days FOR $order_id \n";

	if ( $prod->{specs}{kit} ) {
		map { 
			my $price1 = PQS::model::pricing::price_item( $var->{cust_id}, $list_index, $_->{product}, $_->{qty});
			my $sub = $prod->spec('showprice') ? undef : $ocid;
			insert_prod($log, $dbh, $order_id, $_->{product}, $_->{qty}, $price1, $sub);
		} @{$prod->kit_list()};			
	}

	return ($order_id, $ocid);
}

sub insert_prod {
	my ( $log, $dbh, $order_id, $product, $qty, $price, $subgroup, $jobname, $versions) = @_;
    sql::insert(
        $log, $dbh, 'tbl_Order_Contents', 
        'lngOrderID'    	=> $order_id,
        'product' 			=> $product,
		'intquantity'		=> $qty,
		'intquantityindex'	=> 1,
		'cursalesprice'		=> $qty * $price,
        'type' 				=> 'product',
		subgroup			=> $subgroup || undef,
		jobname				=> $jobname,
		versions			=> $versions
    );

}


sub add_project_to_order {
    my ( $log, $dbh, $cookie, $variable, $project_index, $order_id, $type ) = @_;



	my $error;
	#Allow user to pay with credit card instead.
	#	my $error = check_customer_account( $log, $dbh, $cookie, $variable, $project_index, $order_id, $type );

	#	return ( 0, $error) if $error;


    $order_id ||= get_unfinished_order(
        $log, $dbh, $cookie, $variable->{cust_id}, $variable->{user_id}
    );
    
    $order_id ||= create_order($log, $dbh, $cookie, $variable);

print STDERR "ADD PROJECT TO ORDER PID: $project_index OID: $order_id \n";

    # check to make sure project isn't already in the order.
    my ($previous_pid) = $dbh->selectrow_array(q{
        SELECT lngProjectIndex
        FROM tbl_Order_Contents
        WHERE lngOrderID = ?
         AND lngProjectIndex = ?
         AND type = ?},
        undef, $order_id, $project_index, $type
    );

    if ( $previous_pid ) {
        # If it was already in the order, then we probably changed the
        # project, and want to replace it.
        $dbh->do(q{
            DELETE FROM tbl_Order_Contents
            WHERE lngOrderID = ?
            AND lngProjectIndex = ?
            AND type = ?},
            undef, $order_id, $project_index, $type
        );
    }

    sql::insert(
        $log, $dbh, 'tbl_Order_Contents', 
        'lngOrderID'      => $order_id,
        'lngProjectIndex' => $project_index,
        'type' => $type
    );

    # Quick hack to store the ordered quantity in the project 
    #sql::update( $log, $dbh, 'tbl_Projects', "lngProjectIndex='$project_index'", 
        #'lngOrderID',            $order_id,
        #'intOrderedQuantity',    $quantity, 
        #'strStatus',            'Ordered'
    #);
    return ( $order_id, $error );
}


# creates a new order
# attempts to copy data from the specified quote into the order.
# does NOT verify that the quote exists.
# does NOT delete the quote
sub make_order_from_quote {
    my ( $r, $log, $dbh, $cookie, $quote_id, $variable ) = @_;
    my $error = '';
    my $order_id;

    $_ = "SELECT lngProjectIndex\n".
        "FROM tbl_Quote_Details\n".
        "WHERE lngQuoteID = '$quote_id' AND type <> 'product'";
    my @quote = sql::sql_statement( $log, $dbh, $_ );

    if ( @quote > 0 ) {
        foreach my $project_index ( @quote ) {
            ( $order_id, $_ ) =    add_project_to_order( $log, $dbh, $cookie, $variable, $project_index, $order_id, 'print' );
            $error .= $_;
        }
        return ( $order_id, $error );
    } else {
        $error .= "make_order_from_quote: Empty quote specified: $quote_id";
        $log->debug( "make_order_from_quote: Empty quote specified: $quote_id" );
    }


	my $dbh = session::dbh;

	my $prods = $dbh->selectall_arrayref(q{SELECT * FROM tbl_quote_details WHERE  lngquoteid = ? AND type = 'product'}, 
		{Slice => {}}, $quote_id);
	
	print STDERR "HAVE PRODUCTS: ", Dumper($prods);

	foreach my $p ( @$prods ) {
			my $product =  $p->{product};
			my $qty = $p->{intquantity1};
			my $price =  $p->{dblprice1} / $qty;

			print STDERR "ADD PRODUCT: $product QUANTITY: $qty \n";
			($order_id) = add_product_to_order( $cookie, $variable, $product, $qty, undef, $p->{jobname}, 1, $price );
			#my ( $cookie, $var, $product, $qty, $subgroup, $jobname, $versions, $quote_price, $order_id ) = @_;
	}

    return ( 0, $error );
}

sub add_to_order {
    my ( $log, $dbh, $order_id, $variable, @data ) = @_;

    # add items
    for (my $index = 0; $index < @data; $index += 2) {
        sql::insert( $log, $dbh, 'tbl_Order_Contents', (
            'lngOrderID',         $order_id,
            'lngProjectIndex',    ($data[$index] or 'NULL'),
            'intQuantityIndex', ($data[$index + 1] ne '' ? $data[$index + 1] : 'NULL'), # actually quantity can't be NULL.
        ) );
    }
    return $order_id;
}

sub create_order {
    my ($log, $dbh, $cookie, $variable) = @_;

    my ($currency, $symbol, $rate) 
        = eprint::customer::get_currency($log, $dbh, $variable->{cust_id});

    my ($county_tax_id) 
        = eprint::customer::get_county_tax($dbh, $variable->{cust_id});

    # allocates an order, and ponuutocommit off so our locks stay active
    $dbh->{AutoCommit} = 0;
    $dbh->do( "LOCK TABLE tbl_Orders IN SHARE ROW EXCLUSIVE MODE" ) or $log->error( DBI->errstr );
    
    my $order_id = get_order_id( $log, $dbh );
    
    # insanity code
    delete_order($log, $dbh, $order_id);
    
    sql::insert($log, $dbh, 'tbl_Orders',
        lngOrderID        => $order_id,
        lngUserID         => ( $$variable{'user_id'} eq '' ? 'NULL': $$variable{'user_id'} ),
        lngCustomerID     => ( $$variable{'cust_id'} eq '' ? 'NULL': $$variable{'cust_id'} ),
        strSessionID      => $cookie,
        curTotalSale      => 'NULL',
        curFedTax         => 'NULL',
        curHarmTax        => 'NULL',
        curProvTax        => 'NULL',
        dtmOrderDate      => 'NOW()',
        strStatus         => 'Incomplete',
        strCurrencyName   => $currency,
        strCurrencySymbol => $symbol,
		countytax		  => $county_tax_id || undef
    );

    # unlock database
    $dbh->commit() or $log->error( DBI->errstr );
    $dbh->{AutoCommit} = 1;

    return $order_id;
}

# the data array has the following row form: productindex, quantity, price
sub make_order {
    my ( $log, $dbh, $cookie, $variable, @data ) = @_;

    # this goes before get_order_id so we re-use order_id's
    delete_unfinished_orders($log, $dbh, $cookie);

    my $order_id = create_order( $log, $dbh, $cookie, $variable );
    # add items
    add_to_order( $log, $dbh, $order_id, $variable, @data );
    return $order_id;
}

sub delivery_date {
	# Get delivery date for an Order.
	# Use the earliest delivery date for an individual project.

	my ($dbh, $order_id ) = @_;

	my $date = $dbh->selectrow_array(q{
		SELECT to_char(delivery_time(lngprojectindex)::timestamp, 'DD/MM/YYYY HH12:MI AM') 
		FROM   tbl_order_contents WHERE lngorderid = ?  ORDER by 1 LIMIT 1
	}, undef, $order_id);

print STDERR "DELIVERY DATE: $date \n";
	$date = $dbh->selectrow_array(q{ 
		SELECT to_char(dtmrequireddate, 'DD/MM/YYYY' ) 
		FROM tbl_orders WHERE lngorderid = ?
	}, undef, $order_id) unless $date;

print STDERR "DELIVERY DATE 2: $date \n";

	return $date;
}

# displays the order_info page
sub order_info {
    my ($r, $log, $dbh, $cookie, $variable) = @_;

    $dbh->begin_work;

    my $order_id = $r->param('hiddenOrderID') || get_unfinished_order(
        $log, $dbh, $cookie, $variable->{cust_id}, $variable->{user_id}
    );

	if ( $r->param('GroupPricing') ) {
		$dbh->do(qq{UPDATE tbl_orders set ShowPricing = false WHERE lngorderid = $order_id});
	}

    my $order_total = 0;
    my $sth         = $dbh->prepare(q{
        SELECT strStatus FROM tbl_Orders
        WHERE lngOrderID IN
                (SELECT lngOrderID
                 FROM tbl_Order_Contents
                 WHERE lngProjectIndex = ?)
        AND strStatus IN ('Pending Deposit', 'In Production')
    });

    # Store info from quantity select
    my @projects;
    foreach my $key ($r->param()) {
        next unless $key =~ /rdbQuantity(\d+)/;

        my $pid = $1;

        push @projects, $pid;

        my $date = join '-', $r->param("ddmDueDateYear$pid"),
                             $r->param("ddmDueDateMonth$pid"),
                             $r->param("ddmDueDateDay$pid");

        # you've gotta be kidding me.
        #if ( !$dbh->selectrow_array('SELECT date(?)', undef, $date) ) {
        #    return misc::error(
        #        $log, $dbh, $variable,
        #        'Invalid Date',
        #        "$date is not valid.  Please select a correct date."
        #    );
        #}

        my $qty = $r->param($key);

        my ($ordered) = $dbh->selectrow_array(
            $sth, undef, $pid
        );

        if ( $ordered ) {
            return misc::error(
                $log, $dbh, $variable,
                q{Can't order project.},
                "Project $pid has already been ordered."
            );
        }

        # check if the price fits in their credit limit
        #$_ = "SELECT strValue FROM tbl_Service_Specifications WHERE
        #lngProjectIndex='$pid' AND strName='txtPrice$qty'";
        #$order_total += misc::sum( sql::sql_statement( $log, $dbh, $_ )
        #);

        my @project_prices = eprint::project::project_price(
            $log, $dbh, $pid
        );

        $order_total += $project_prices[$qty - 1];

        sql::update($log, $dbh, 
            'tbl_Order_Contents',
            "lngOrderID = $order_id AND lngProjectIndex = $pid",
            intQuantityIndex => $qty,
            dateRequired     => $date,
        );
    }

#    die "You must have at least one project to create an order." 
 #       unless @projects;

    $dbh->commit;


    my $return = customer_credit_info($log, $dbh, $variable);

    # We'll probably want to make this a little smarter in the future so that
    # it can smartly decide if we'll allow credit card payments or not.
    $variable->{credit_card_payment} = allow_credit_card_payment(
        $log, $dbh, $variable->{cust_id}
    );

    $variable->{amount} = $order_total;

    if ($return->{down_payment}) {
        $variable->{amount} = sprintf(
            '%.2f', $order_total * $return->{down_payment} / 100
        );
    }

    my @date = localtime(time);
    $variable->{ddmMonths} = ssi::getmonths();
    $variable->{ddmYear}   = ssi::getyears($date[5] + 1900, 10);

    my $quantities = $dbh->selectcol_arrayref(q{
        SELECT intQuantityIndex
        FROM tbl_Order_Contents
        WHERE lngOrderID = ?
    }, undef, $order_id);

    if (grep { !$_ } @$quantities) {
		print STDERR "HAVE INCOMPLETE QTY: HTTP_MOVED_TEMPORARILY TO ORDER SELECTION 358 \n";
        $variable->{Redirect} = '/main/order/order_selection.html';
        return OK;
    }

    #this is stupid, but it's how it was done, so I'm cleaning it as best as I
    #can, all things considered...
    my %map = (
        txtCompanyName           => 'strCompanyName',
        rdbSalutation            => 'strSalutation',
        txtFirstName             => 'strFirstName',
        txtLastName              => 'strLastName',
        txtAddress1              => 'strAddress1',
        txtAddress2              => 'strAddress2',
        txtCity                  => 'strCity',
        ddmStateProvince         => 'strState',
        txtPostalCode            => 'strPostalCode',
        ddmCountry               => 'strCountry',
        txtPhone                 => 'strPhone',
        txtExtension             => 'strExt',
        txtFax                   => 'strFax',
        txtEmail                 => 'strEmail',
        txtShippingCompanyName   => 'strShippingCompanyName',
        txtShippingFirstName     => 'strShippingFirstName',
        txtShippingLastName      => 'strShippingLastName',
        txtShippingSalutation    => 'strShippingSalutation',
        txtShippingAddress1      => 'strShippingAddress1',
        txtShippingAddress2      => 'strShippingAddress2',
        txtShippingCity          => 'strShippingCity',
        ddmShippingStateProvince => 'strShippingState',
        txtShippingPostalCode    => 'strShippingPostalCode',
        ddmShippingCountry       => 'strShippingCountry',
        txtShippingPhone         => 'strShippingPhone',
        txtShippingExtension     => 'strShippingExt',
        txtShippingFax           => 'strShippingFax',
        txtShippingEmail         => 'strShippingEmail',
        ship_via                 => 'lngShipVia',
    );

    # Create the list of fields to lookup.
    my $fields = join q{, }, map {$dbh->quote_identifier(lc($_))} values %map;

    # Each field gets a new name in the SSI hashref.
    @{ $variable }{ keys %map } = $dbh->selectrow_array(qq{
        SELECT $fields FROM tbl_Orders WHERE lngOrderID = ?
    }, undef, $order_id);

    if ( $variable->{txtCompanyName} eq '' ) {
        my %fix_map = (
            txtCompanyName   => 'strCompanyName',
            txtAddress1      => 'strAddress1',
            txtAddress2      => 'strAddress2',
            txtCity          => 'strCity',
            ddmStateProvince => 'strProvState',
            txtPostalCode    => 'strPostalCodeZip',
            ddmCountry       => 'strCountry',
            txtPhone         => 'strPhone',
            txtExtension     => 'strExt',
            txtFax           => 'strFax',
        );

        # Create the list of fields to lookup.
        my $fields = join q{, },
                     map { $dbh->quote_identifier(lc($_)) }
                         values %fix_map;

        # TODO Don't use placeholder for table values as they will break when
        # server-side prepares are used.
        @{ $variable }{ keys %fix_map } = $dbh->selectrow_array(qq{
            SELECT $fields FROM tbl_customer WHERE lngCustomerID = ?
        }, undef, $variable->{cust_id});
    }

    my ($cust_id) = $dbh->selectrow_array(q{
        SELECT lngCustomerID
        FROM tbl_Customer_Users
        WHERE lngUserID = ?
    }, undef, $variable->{user_id});

    if ( $variable->{txtEmail} eq '' && $cust_id != $variable->{cust_id} ) {
        my $query = q{
            SELECT strEmail, strFirstName || ' ' || strLastName
            FROM tbl_customer_users
            WHERE lngCustomerID = 
        };
        $query .= $dbh->quote($variable->{cust_id});

        $variable->{ddmOrderForUsers} = ssi::fill_drop_down(
            $log, $dbh, $query
        );

        ($variable->{txtOrderedBy}) = $dbh->selectrow_array(q{
            SELECT strFirstname || ' ' ||  strLastName
            FROM tbl_Customer_Users
            WHERE lngUserId = ?
            }, undef, $variable->{user_id}
        );
    }
    elsif ( $variable->{txtEmail} eq '' ) {
        eprint::user::load( $log, $dbh, $variable->{user_id}, $variable );
    }

    if ( $variable->{txtShippingCompanyName} eq '' ) {
        eprint::customer::load_shipping(
            $log, $dbh, $variable->{cust_id}, $variable
        );

        $variable->{txtShippingSalutation}
            = $variable->{rdbShippingSalutation};
        $variable->{txtShippingCountry}
            = $variable->{ddmShippingCountry};
        $variable->{txtShippingStateProvince}
            = $variable->{ddmShippingStateProvince};
    }

    $variable->{hiddenOrderID} = $order_id;

    # FIXME which shipping options do unlogged in people get?
    my $shippers = $dbh->selectcol_arrayref(q{
        SELECT lngIndex, strName
        FROM tbl_Ship_Via
    }, { Columns => [1, 2] });

    $variable->{ddmShipVia} = ssi::make_drop_down(
        $shippers, $variable->{ship_via}
    );

    my $countys = $dbh->selectcol_arrayref(q{
        SELECT id, name
        FROM county_taxes
    }, { Columns => [1, 2] });

	my $countytax = get_county_tax_id($dbh, $variable->{cust_id}, $variable->{user_id});

    $variable->{ddmCountyTax} = ssi::make_drop_down(
        $countys, $countytax
    );

    $variable->{ddmStateProvince}
        = ssi::return_states_and_provinces($variable->{ddmStateProvince});
    $variable->{ddmCountry}
        = ssi::return_countries($variable->{ddmCountry});

    $variable->{ddmShippingStateProvince} = ssi::return_states_and_provinces(
        $variable->{ddmShippingStateProvince}
    );

    $variable->{ddmShippingCountry}
        = ssi::return_countries($variable->{ddmShippingCountry});

    $variable->{ 'rdbSalutation'        . $variable->{rdbSalutation} }
        = q{checked='checked'};
    $variable->{ 'rdbShippingSalutation'. $variable->{txtShippingSalutation} }
        = q{checked='checked'};

}

# this is just factored out of submit_order -- should probably go somewhere
# else.
sub customer_credit_info {
    my ($log, $dbh, $variable) = @_;

    my $return = {};

    my $account_balance = eprint::customer::get_balance(
        $dbh, $variable->{cust_id}
    );

    my ($terms, $creditlimit, $credithold, $downpayment)
        = $dbh->selectrow_array(q{
            SELECT lngTerms, dblCreditLimit, ysnCreditHold, dblDownPayment
            FROM tbl_Customer_Credit
            WHERE lngCustomerIndex = ?
            }, undef, $variable->{cust_id}
        );

    if (!defined $downpayment) { # I think 0 means no downpayment, and undef
                                 # means use default.

        ($downpayment) = configuration::get_value(
            $log, $dbh, 'DefaultDownpayment'
        );
    }

    return {
        account_balance     => $account_balance,
        down_payment        => $downpayment,
        terms               => $terms,
    };
}

# comes here on the transition from orde_info to orde_info_cred_card or
# order_info_digi_cheq stores the order information into the database
sub store_order_info {
    my ( $r, $log, $dbh, $cookie, $variable ) = @_;

    my $order_id = $r->param('hiddenOrderID');
    if ( $order_id eq '' ) {
        $order_id = get_unfinished_order(
            $log, $dbh, $cookie, $$variable{'cust_id'}, $$variable{'user_id'}
        );
    }

    my $error = '';
#    my $error = 'The following fields need to be corrected. Please push the back button and try again. If you require assistance please call us at 1-888-500-0999.<br />';

    $error .= "Company Name is a required field.<br>" if $r->param('txtCompanyName') eq '';
    $error .= "Address is a required field.<br>" if $r->param('txtAddress1') eq '';
    $error .= "City is a required field.<br>" if $r->param('txtCity') eq '';
    $error .= "Provice/State is a required field.<br>" if $r->param('ddmStateProvince') eq '';
    $error .= "Postal Code/Zip is a required field.<br>" if $r->param('txtPostalCode') eq '';
    $error .= "Country is a required field.<br>" if $r->param('ddmCountry') eq '';

    if ( $r->param('txtShippingCompanyName') ne ''
         or $r->param('txtShippingAddress1') ne ''
         or $r->param('txtShippingCity') ne ''
         or $r->param('txtShippingPostalCode') ne ''
         or $r->param('txtShippingPhone') ne ''
         or $r->param('txtShippingEmail') ne ''
        ) {
        # do error checks
        $error .= "Shipping Company Name is a required field.<br>" if $r->param('txtShippingCompanyName') eq '';
        $error .= "Shipping Address is a required field.<br>" if $r->param('txtShippingAddress1') eq '';
        $error .= "Shipping City is a required field.<br>" if $r->param('txtShippingCity') eq '';
        $error .= "Shipping State/Province is a required field.<br>" if $r->param('ddmShippingStateProvince') eq '';
        $error .= "Shipping PostalCode is a required field.<br>" if $r->param('txtShippingPostalCode') eq '';
        $error .= "Shipping Country is a required field.<br>" if $r->param('ddmShippingCountry') eq '';
        $error .= "Shipping Phone is a required field.<br>" if $r->param('txtShippingPhone') eq '';
        $error .= "Shipping Email is a required field.<br>" if  $r->param('txtShippingEmail') eq '';

    }

    $error = 'The following fields need to be corrected. Please push the back button and try again. If you require assistance please call us at 1-888-500-0999.<br />' . $error if $error;

    return $error if $error;
	

    $_ = "SELECT lngSalesPerson FROM tbl_Customer WHERE lngCustomerID = '$$variable{'cust_id'}'";
    my ( $emp_id ) = sql::sql_statement( $log, $dbh, $_ );

    my $state 	= ( $r->param('ddmShippingStateProvince') ? $r->param('ddmShippingStateProvince') : $r->param('txtShippingOtherStateProvince') );
    my $country = ( $r->param('ddmShippingCountry')		  ? $r->param('ddmShippingCountry'):$r->param('txtShippingOtherCountry'));
    my @data = (
        #'lngEmployeeID',            $emp_id,
        #'strTitle',                 $r->param('txtTitle'),
        'strCompanyName',            $r->param('txtCompanyName'),
        'strFirstName',                $r->param('txtFirstName'),
        'strLastName',                $r->param('txtLastName'),
        'strSalutation',            $r->param('rdbSalutation')?$r->param('rdbSalutation'):'',
        'strAddress1',                $r->param('txtAddress1'),
        'strAddress2',                $r->param('txtAddress2'),
        'strCity',                    $r->param('txtCity'),
        'strState',                    ( $r->param('ddmStateProvince') ? $r->param('ddmStateProvince') : $r->param('txtOtherStateProvince') ),
        'strPostalCode',            $r->param('txtPostalCode'),
        'strCountry',                ( $r->param('ddmCountry') ? $r->param('ddmCountry') : $r->param('txtOtherCountry') ),
        'strPhone',                    $r->param('txtPhone'),
        'strExt',                    $r->param('txtExtension'),
        'strFax',                    $r->param('txtFax'),
        'strEmail',                     $r->param('txtEmail'),
        'strShippingCompanyName', 		$r->param('txtShippingCompanyName') || $r->param('txtCompanyName'),
        'strShippingTitle',         	$r->param('txtShippingTitle') 		|| '',
        'strShippingFirstName',     	$r->param('txtShippingFirstName') 	|| $r->param('txtFirstName'),
        'strShippingLastName',			$r->param('txtShippingLastName') 	|| $r->param('txtLastName'),
        'strShippingSalutation',    	$r->param('rdbShippingSalutation') 	|| $r->param('rdbSalutation') || '',
        'strShippingAddress1',        	$r->param('txtShippingAddress1') 	|| $r->param('txtAddress1'),
        'strShippingAddress2',        	$r->param('txtShippingAddress2')	|| $r->param('txtAddress2'),
        'strShippingCity',            	$r->param('txtShippingCity')		|| $r->param('txtCity'),
        'strShippingPostalCode',    	$r->param('txtShippingPostalCode') 	|| $r->param('txtPostalCode'),
        'strShippingState',            	$r->param('ddmShippingStateProvince') || $state,
        'strShippingCountry',        	$r->param('ddmShippingCountry') 	|| $country,
        'strShippingPhone',            	$r->param('txtShippingPhone')		|| $r->param('txtPhone'),
        'strShippingExt',            	$r->param('txtShippingExtension')	|| $r->param('txtExtension'),
        'strShippingFax',            	$r->param('txtShippingFax')			|| $r->param('txtFax'),
        'strShippingEmail',             $r->param('txtShippingEmail') 		|| $r->param('txtEmail'),
		'countytax',				  $r->param('ddmCountyTax') || undef,
        'strPONumber',                $r->param('txtPurchaseOrder'),
		'addorderinfo',				  $r->param('additionalOrderInformation'),
        #'strPaymentType',            $r->param('ddmPaymentType'),
        #'strShipVia',                $r->param('ddmShipVia'),

    );

    push @data, 'strAdministratorComments', $r->param('AdministratorComments') if $r->param('AdministratorComments');
    sql::update( $log, $dbh, 'tbl_Orders', "lngOrderID = '$order_id'", @data );

    $log->debug("FINISHED STORE ORDER INFO ");

    return $error;

}

sub get_invoice_to {
    my ( $log, $dbh, $variable, $order_id ) = @_;


    my $sth = $dbh->prepare(q{
        SELECT strCompanyName, strSalutation, strFirstName, strLastName, 
               strAddress1,    strAddress2,   strCity,      strState, 
               strCountry,     strPostalCode, strPhone,     strExt, 
               strFax,         strEmail,	  strCubicle
        FROM tbl_orders
        WHERE lngorderid = ?
    });
    
    @$variable{qw(
            txtCompanyName  txtSalutation  txtFirstName  txtLastName  
            txtAddress1     txtAddress2    txtCity       txtStateProvince
            txtCountry      txtPostalCode  txtPhone      txtExtension 
            txtFax          txtEmail 	   txtCubicle
        )} = $dbh->selectrow_array($sth, undef, $order_id);
}

sub get_ship_to {
    my ( $log, $dbh, $variable, $order_id ) = @_;

    $_ = "SELECT strShippingCompanyName, strShippingSalutation,strShippingFirstName, strShippingLastName, strShippingAddress1, strShippingAddress2, strShippingCity, strShippingState, strShippingCountry, strShippingPostalCode, strShippingPhone, strShippingExt, strShippingFax, strShippingEmail\n".
        "FROM tbl_Orders ".
        "WHERE lngOrderID = '$order_id'";
    @$variable{
        'txtShippingCompanyName',
        'txtShippingSalutation',
        'txtShippingFirstName',
        'txtShippingLastName',
        'txtShippingAddress1',
        'txtShippingAddress2',
        'txtShippingCity',
        'txtShippingStateProvince',
        'txtShippingCountry',
        'txtShippingPostalCode',
        'txtShippingPhone',
        'txtShippingExtension',
        'txtShippingFax',
        'txtShippingEmail'
    } = sql::sql_statement( $log, $dbh, $_ );

}

sub fill_contact {
# Fill contact information from shipping page into the Order table.
		my ($r, $dbh, $order_id ) = @_;

		my $log = session::log;
		
		my $pid = $dbh->selectrow_array(q{
			SELECT MIN(lngprojectindex) FROM tbl_order_contents WHERE lngorderid = ?
		}, undef, $order_id);

		my $sid = eprint::project::check_for_service(undef, $dbh, $pid, 'Shipping');
	
		my %ship;

		if ($sid ) {
			%ship = eprint::service::get_specifications_pairs(undef, $dbh, $pid, $sid);
			print STDERR "HAVE SHIP HASH FROM CUST", Dumper(\%ship);
		} else { 
			my $cust_id = PQS::model::order::get_cust_id($order_id);
			eprint::customer::load($r, $log, $dbh, $cust_id, \%ship);
			$ship{stremail}  = $dbh->selectrow_array(q{
				SELECT stremail FROM tbl_customer_users WHERE lnguserid = (
					SELECT lnguserid FROM tbl_orders WHERE lngorderid = ?
				)
			}, undef, $order_id);

			($ship{txtFirstName}, $ship{txtLastName} )  = $dbh->selectrow_array(q{
				SELECT strfirstname, strlastname FROM tbl_customer_users WHERE lnguserid = (
					SELECT lnguserid FROM tbl_orders WHERE lngorderid = ?
				)
			}, undef, $order_id);
		}

print STDERR "FILL CONTACT: " , Dumper(\%ship);


        my %fix_map = (
			txtFirstName	 => 'strFirstName',
			txtLastName	 	 => 'strLastName',
            txtCompanyName   => 'strCompanyName',
            txtAddress1      => 'strAddress1',
            txtAddress2      => 'strAddress2',
            txtCity          => 'strCity',
            ddmStateProvince => 'strstate',
            txtPostalCode    => 'strPostalCode',
            ddmCountry       => 'strCountry',
            txtPhone         => 'strPhone',
            txtExtension     => 'strExt',
            txtFax           => 'strFax',
            stremail         => 'stremail',
        );


		map {	my $field =  $dbh->quote_identifier(lc($fix_map{$_}));
			   $dbh->do(qq{
				UPDATE tbl_orders SET $field = ?  WHERE lngorderid = ?
			  }, undef, $ship{$_}, $order_id ) 
		}  keys %fix_map;

		return;

}


sub verify_order {
    my ($r, $log, $dbh, $cookie, $variable) = @_;

    my $error;

    my $order_id = $r->param('hiddenOrderID') || get_unfinished_order(
        $log, $dbh, $cookie, $variable->{cust_id}, $variable->{user_id}
    );
print STDERR "TIME TO VERIFY ORDER -- $order_id \n";
# Start of new code


	if ( $r->param('btnFunction') eq 'Process Order' ) {
		print STDERR "MAKE QUOTE FORM ORDER  \n";
		my $quote_id = $r->param('quote_id');
 		make_order_from_quote( $r, $log, $dbh, $cookie, $quote_id, $variable );

	}	

	return unless $order_id;

	fill_contact($r, $dbh, $order_id);

	my $ship_method = $r->param('ddmShipVia1');

	$_ = "SELECT lngIndex, strName FROM tbl_Ship_Via";
    $$variable{'SHIP_OPTIONS'} = ssi::fill_drop_down($log, $dbh, $_);

	$variable->{__FillInForm}{ddmShipVia1} = $ship_method;
	
	$dbh->do(q{UPDATE tbl_orders set shipping_type = (select strname from tbl_ship_via WHERE lngindex = ?) WHERE lngorderid = ? }, undef, $ship_method, $order_id);

	my $ship_price = eprint::Service::Shipping::order_ship_cost($order_id, $ship_method);
print STDERR "VERIFY ORDER - HAVE ORDER SHIP PRICE: $order_id = $ship_price METHOD: $ship_method \n";

	PQS::model::order::set_ship_price($order_id, $ship_price);

	PQS::model::order::set_admin_comments($order_id, $r->param('AdministratorComments'));

	if ( $r->param('btnFunction') eq 'Process Order' ) {

		my $pid   = $r->param('ProjectIndex');
		my $projtype = $r->param('ProjectType');
		my $product = $r->param('product');

		$projtype = 'print' unless $projtype;

		if ($pid) {
# This is a hybrid project.
# Already added to order, just have to update order info before completing.

print STDERR "PROCESS ORDER: $order_id - $pid \n";

			$order_id = $dbh->selectrow_array(q{
				SELECT MAX(lngorderid) FROM tbl_order_contents 
				WHERE lngprojectindex = ?
			}, undef, $pid);

			unless ($order_id ) {
				($order_id) = add_project_to_order( $log, $dbh, $cookie, $variable, $pid, undef, 'print' );
			}
			sql::update($log, $dbh, 
				'tbl_Order_Contents',
				"lngOrderID = $order_id AND lngProjectIndex = $pid",
				intQuantityIndex => 1,
				type => $projtype,
				dateRequired     => 'NOW()'
			);
		} elsif ( $product ) {
			my $qty = $r->param('qty');
			die("QTY MISSING FROM ADD to Order") unless $qty;
			($order_id) = add_product_to_order( $cookie, $variable, $product,$qty );
		} else {

# Shortcut for ordering Custom projects.
# Skips Order info page.

print STDERR "PROCESS ORDER: $order_id - $pid \n";

			$order_id = get_unfinished_order( $log, $dbh, $cookie, $variable->{cust_id}, $variable->{user_id} );

			foreach my $key ($r->param()) {
				next unless $key =~ /rdbQuantity(\d+)/;
				my $pid = $1;
				my $qty = $r->param($key);

				my $exists = $dbh->selectrow_array(q{
					SELECT lngprojectindex FROM tbl_order_contents WHERE lngprojectindex = ?
					AND lngorderid = ?
				}, undef, $pid, $order_id);

print STDERR "HAVE QUANTITY FOR ORDER: $qty == $pid EXISTS: $exists \n";

				sql::update($log, $dbh, 
					'tbl_Order_Contents',
					"lngOrderID = $order_id AND lngProjectIndex = $pid",
					intQuantityIndex => $qty,
					dateRequired     => 'NOW()'
				);

			}
print STDERR "DONE ADDING NOW FILL CONTACT \n";
			
		}
	} elsif ( $r->param('Return') ) {
# Return or order from login confirmation.
		$order_id = $r->param('Return');
	} elsif ( $r->param('remove') ) {
		$order_id = $dbh->selectrow_array(q{
			SELECT MAX(lngorderid) FROM tbl_order_contents 
			WHERE lngprojectindex = ?
		}, undef, $r->param('remove')) unless $order_id;
		$dbh->do(q{ 
			DELETE FROM tbl_order_contents WHERE lngprojectindex = ? and lngorderid = ?
		}, undef, $r->param('remove'), $order_id);
	} elsif ( $r->param('remove_product') ) {
	  PQS::model::order::remove_content($r->param('remove_product'));
	} elsif ( $r->param('CHECKOUT') ) {
		show_payflow($r, $log, $dbh, $cookie, $variable );
	} elsif ( $r->param('MW_Return') ) {
		my $ocid = $r->param('MW_Return');
		my $mwid = $r->param('JobId');
		PQS::model::order::set_mediawide_id($ocid, $mwid);

		my $key = PQS::model::order::get_mw_session($ocid);

		my $pid = PQS::model::order::get_pid_from_index($ocid);
die("Can't find pid for $ocid.") unless ($pid);

		eprint::products::get_highres_file($mwid,$key,$pid, $order_id);
	} else {

# Else display what is in our current order.

#		return misc::error(
#			$log, $dbh, $variable,
#			"Email address is invalid",
#			"The e-mail address you provided is invalid!  Please try again.",
#		) if $r->param('txtEmail') !~ /^[^@\s]+\@[^@\s]+\.(?:[\w.]{2,})+/;


	}


# stop here, allow a blank order page to be diplayed if
# there is no current order.
	return OK unless $order_id;


    my $quantities = $dbh->selectcol_arrayref(q{
        SELECT intQuantityIndex
        FROM tbl_Order_Contents
        WHERE lngOrderID = ?
        }, undef, $order_id
    );

    if ($quantities && grep { !$_ } @$quantities) {
		print STDERR "HAVE INCOMPLETE QTY: HTTP_MOVED_TEMPORARILY TO ORDER SELECTION 814 \n";
        $variable->{Redirect} = '/main/order/order_selection.html';
        return OK;
    }

    # if we came eprint from the orde_info page, then store the order
    # uh.. we shouldn't be trusting referer for anything.
    if ( $ENV{HTTP_REFERER} =~ /order_info\.html/ ) {
        $error = store_order_info( $r, $log, $dbh, $cookie, $variable );
    }

    if ( $error ne '' ) {
        return misc::error( $log, $dbh, $variable, 'Error', $error );
    }



    $variable->{hiddenOrderID} = $order_id;

	display_order($variable, $order_id);




	$variable->{additionalOrderInformation} =~ s/\r/<br>/g;
	


	#print STDERR "HAVE PROJECT DATA ", Dumper($variable->{projects});


    return OK;
}


sub finalise_order {
    my ( $r, $log, $dbh, $cookie, $variable, $order_id ) = @_;
print STDERR "FINALIZE ORDER \n\n";

    $order_id =  $order_id || $r->param('hiddenOrderID');

print STDERR "MY ORDER ID: $order_id \n";
    if ( $order_id eq q{} ) {
        $log->debug("No order ID passed, pulling from database.");
        $order_id = get_unfinished_order(
            $log, $dbh, $cookie, $variable->{cust_id}, $variable->{user_id}
        );
    }

    if ( $order_id eq q{} ) {
        return misc::error($log, $dbh, $variable, 'No order id!  Not processing!');
    }

			#Allocate product inventory for mat_inventory
			my $prods = $dbh->selectall_arrayref(q{
				SELECT product, intquantity FROM tbl_order_contents WHERE lngorderid = ?
			}, {Slice => {} }, $order_id);

			foreach my $p ( @{$prods} ) {
				$dbh->do(q{Update inventory_count set onorder = onorder + ? WHERE id = (SELECT strid FROM tbl_products WHERE id = ?)},
					undef, $p->{intquantity}, $p->{product});
			}



print STDERR "CHECK ORDER INFO \n";
    # get order information
    my ( $check_order_id, $status, $ponum, $total ) = $dbh->selectrow_array(q{
        SELECT lngOrderID, strStatus, strPONumber, curTotalSale
        FROM tbl_Orders
        WHERE strSessionID = ?
         AND lngOrderID = ?
        }, undef, $cookie, $order_id);

	$check_order_id = $order_id;
	$status = 'Incomplete';
    if (   $check_order_id
        && $status eq 'Incomplete' || $status eq 'Re-Opened' ) {

		print STDERR "DO ORDER STUFF NOW \n";

        my $order_info = get_order_totals(
            $dbh, $variable->{cust_id}, $order_id
        );

#print STDERR "ORDER TOTALS ", Dumper($order_info);

        foreach my $order (@{ $order_info->{projects} }) {


            sql::update(
                $log, $dbh, 'tbl_Order_Contents',
                "lngOrderID = '$order_id'
                    AND lngProjectIndex = '$order->{index}'",
                strDescription => $order->{name},
                curSalesPrice  => $order->{price},
                intQuantity    => $order->{qty},
                dblTax1        => $order->{gst_amount} || 'NULL',
                dblTax2        => $order->{pst_amount} || 'NULL',
                dblTax3        => $order->{hst_amount} || 'NULL',
                dblTax4        => $order->{county_amount} || 'NULL',
                dblShipping    => $order->{shipping}   || 'NULL',
                dblPostage     => $order->{postage}   || 'NULL',
            );

			#make_rfq($r, $dbh, $order->{index}, $order->{qty});
        }

        $total = $order_info->{total};



        my $customer_credit = eprint::customer_credit->new(
            $log, $dbh, $variable->{cust_id}
        );

    	my $avail_credit = $customer_credit->available;

        my ( $downpayment ) = $customer_credit->get( 'Downpayment' );

        $downpayment = $total * ( $downpayment / 100 );

        $downpayment = sprintf( '%.2f', $downpayment );

		$downpayment = $total unless $downpayment > 0;

		#If we have credit to cover the downpayment then we will not require one.
		if ( $downpayment  <= $avail_credit ) {
			$downpayment = 0;
		}


        my ($amount_paid) = $dbh->selectrow_array(q{
            SELECT SUM(curAmount)
            FROM tbl_Payments
            WHERE lngOrderID = ?
            AND strSessionID IS NULL
            }, undef, $order_id
        );


        sql::update(
            $log, $dbh, 'tbl_Orders', "lngOrderID = '$order_id'",
            curFedTax      => $order_info->{gst_total} || 'NULL',
            curProvTax     => $order_info->{pst_total} || 'NULL',
            curHarmTax     => $order_info->{hst_total} || 'NULL',
            curCountyTax   => $order_info->{county_total} || 'NULL',
            curTotalSale   => $order_info->{total}     || 'NULL',
            curDownpayment => $downpayment             || 'NULL',
            strSessionID   => q{},
            ysnfinished    => 1,

            ( defined $r->param('AdministratorName')
                ? ( 'strAdministratorName',
                        $r->param('AdministratorName') )
                : ()
            ),
            ( defined $r->param('AdministratorComments')
                ? ( 'strAdministratorComments',
                        $r->param('AdministratorComments') )
                : ()
            ),
        );

        $variable->{Downpayment} = $downpayment - $amount_paid;
        $variable->{Downpayment} = 0 if $variable->{Downpayment} < 0;
        $variable->{Downpayment} = sprintf( '%.2f', $variable->{Downpayment});

        my $projects = $dbh->selectcol_arrayref(q{
            SELECT lngProjectIndex
            FROM tbl_Order_Contents
            WHERE lngOrderId = ? AND lngprojectindex is not null
            }, undef, $order_id
        );

   print STDERR "HAVE PROJECT LIST FOR ORDER", Dumper($projects);
		my $plist = [];

        foreach my $pid ( @{ $projects } ) {
#            sql::update(
			#                $log, $dbh, 'tbl_Project_Contents',
			#                "lngProjectIndex = $pid AND strStatus != 'Complete'",
			#                strStatus => $status
			#            );

            my @delete_columns = qw(
                txtEmployeeComments    rdbComplete
                ddmCompletionDateMonth ddmCompletionDateDay
                ddmCompletionDateYear  txtRunHours
                txtDowntimeHours       txtDowntimeHours
                txtMakeReadySetupHours txtStartQuantity
                txtFinalQuantity       txtWasteQuantity
                txtEmployeeName
            );

            my $query = q{
                DELETE FROM tbl_Service_Specifications
                WHERE lngProjectIndex = ?
                AND strName IN (%s)
            };

            $query = sprintf(
                $query, q{'} . join(q{', '}, @delete_columns) . q{'}
            );

            $dbh->do($query, undef, $pid);

			#            sql::update(
			#                    $log, $dbh, 'tbl_Projects',
			#                    "lngProjectIndex = $pid AND strStatus != 'Complete'",
			#                    strStatus => $pstatus
			#            );

            # Send a notice to the user's manager if they're filled a PDF
            # template (as that's about the same as uploading a file).
            if (has_pdf_template($log, $dbh, $pid)) {
                eprint::user::notify_manager($r, $log, $dbh, $variable->{user_id}, 'file', {
                    subject  => 'Print Data Submitted',
                    template => 'notify_manager_data_submitted.html',
                    info     => {
                        order => $order_id,
                        pid   => $pid,
                    },
                });
            }



			# New Feature requested by sherwood.
			# Create project directory when it is ordered.
			mkpath(get_path(undef, $dbh, $pid));
			
			# Get data for Print Dcoket Buttons added for Safeway.
			my $data = $dbh->selectrow_hashref(q{
				SELECT p.lngprojectindex as pid,
					   p.strprojectreference as name,
					   oc.intquantityindex		as qtyIndex
				FROM tbl_projects p, tbl_order_contents oc
				WHERE p.lngprojectindex = oc.lngprojectindex
				AND    p.lngprojectindex = ?
			}, undef, $pid);

			push @{$plist}, $data;

    		inventory_checkin($r, $log, $dbh, $order_id, $pid);


		    
        }



		$variable->{projects} = $plist;


		# Safeway  orders are set to Pending Date Approval.
		#my $pending = 1;



		$variable->{dockets} = make_product_dockets($order_id, $variable);

		#unless ( $status eq 'Pending Deposit' ) { 
        	# Send notice of the order to the user and the solution owner.
			#	send_sales_order($r, $log, $dbh, $order_id, $pending, $inv);
		#}
		

        # Send out a notice to the ordering user's manager (if applicable).
        eprint::user::notify_manager($r, $log, $dbh, $variable->{user_id}, 'order', {
            subject  => 'Order Placed',
            template => 'notify_manager_order_placed.html',
            info     => { order => $order_id, },
        });


        # We are going to manually invoice for now. Now we are back to sending
        # invoice when order is submitted.  Nope, back to manual invoice
		#if ($variable->{Downpayment} > 0) {
			##     send_invoice( $r, $log, $dbh, $order_id );
		#}
		


    }

# END if ( $check_order_id...)

    my $cust_id = $variable->{cust_id};


    my $credit = new eprint::customer_credit( $log, $dbh, $cust_id );

    my $avail_credit = $credit->available;


	if ( $avail_credit < 0 ) {
       notify_overdraft( $r, $log, $dbh, $cust_id, $avail_credit );
	}

	my $order = new PQS::Object::order($order_id);

	my $status = $order->status_tree();

	#If we are peding deposit then don't send sales order yet.
	unless ( $status eq 'Pending Deposit' ) { 
		my $pending = 1;

      	# Send notice of the order to the user and the solution owner.
       	send_sales_order($r, $log, $dbh, $order_id, $pending);
	}


    $variable->{order_id} = $order_id;

    return OK;
}

sub order_product_list {
       my $oid = shift;
       my $var = shift;

       my $list = PQS::model::order::get_order_products($oid);

       my @kit;

       my $have;

       map { $have->{$_->{product}} = 1} @{$list};

       foreach my $o ( @{$list} ) {

               my $product = PQS::model::products::get($o->{product});

               print STDERR "HAVE PRODUcT " , Dumper($o, $product->{kit});

               if ( $product->{kit} ) {

                       print STDERR "HAVE KIT \n";
                       my $klist = PQS::model::products::kit_list($o->{product});
                       #print STDERR "HAVE KIT \n", Dumper($klist);
                       foreach my $k ( @{$klist} ) {

                               my $qty =  $k->{qty} * $o->{intquantity};
                               my $jobname = $o->{jobname} . ' - ' . $k->{name};

                               die("Missing Kit Qty for kit:  $o->{product} ") unless $qty;

                               print STDERR "ADD PRODUCT: $k->{product}, QTY: $qty \n";
                               add_product_to_order( undef, $var, $k->{product}, $k->{qty}, undef, $o->{jobname}, $o->{versions} || 1, 0, $oid )
                               unless $have->{$k->{product}};


                       }
               }
       }

       my $list = PQS::model::order::get_order_products($oid);

       return $list;

}

sub make_product_dockets {
	my $orderid = shift;
	my $var = shift;
	my $dbh = session::dbh;
	my $log = session::log;
	my $r   = session::r;

	
	my @pids;
	my $list = order_product_list($orderid, $var);

	my $order = PQS::model::order::get_order($orderid);

print STDERR "HAVE ORDER LINE: " , Dumper( $order);



	foreach my $o ( @{$list} ) {
print STDERR "HAVE ORDER LINE: " , Dumper($o, $list, $order);
		my $prod = new PQS::Object::product($o->{product});
		my $ppid = $prod->{specs}{project};

		next unless $ppid;

		my $args = {
			name => $o->{jobname} . ' - ' . $prod->{specs}{name},

#			name => "Docket for: " . $o->{jobname},
# remove 'Docket for' from job name, add it as a 'label' on order/project history
			#
			qty  		=> $o->{intquantity},
			comment 	=> $prod->{specs}{description},
			no_assets	=> 1,
		};

		my ($pid) = eprint::print_project::copy_project($dbh, $var, $ppid, $args);

		$dbh->do(q{UPDATE tbl_projects set prod = ? WHERE lngprojectindex = ?}, undef,  $prod->{id}, $pid); 



		my $p = new PQS::Object::project($pid);
		$p->upload_required($prod->{specs}{file_upload});

		
		my $versions = $o->{versions};
print STDERR "OV1 HAVE VERSIONS: $versions \n";
		if ( $versions > 1 ) {
			use POSIX;
			my $qty = $o->{intquantity};
			my $perversion = ceil($qty / $versions); 
print STDERR "OV1 PER VERSIONS: $versions Q: $qty : $perversion \n";
    		my $print 	= eprint::project::check_for_service( undef, $dbh, $pid, 'Printing');
			eprint::service::insert_service_spec( $log, $dbh, $pid, $print, 'is_mv' , 1);
			my $v;
			
			foreach (1..$versions) {
				$v .=   "," if $v;
				$v .=   "Version $_,$perversion";
			}

			eprint::service::insert_service_spec( $log, $dbh, $pid, $print, 'version_quantities' , $v);
print STDERR "OV1 PER VERSIONS: $versions Q: $qty : $perversion V: $v \n";
		}


    	my $sid 	= eprint::project::check_for_service( undef, $dbh, $pid, 'Discount');
    	my $ship 	= eprint::project::check_for_service( undef, $dbh, $pid, 'Shipping');

	   	$ship = eprint::print_project::insert_service($log, $dbh, $pid, 'Shipping') unless $ship;

		my $type = $dbh->selectrow_array(q{SELECT shipping_type FROM tbl_orders WHERE lngorderid = ?}, undef, $orderid);
		my $id   = $dbh->selectrow_array(q{SELECT lngindex  FROM tbl_ship_via WHERE strname = ?}, undef, $type);

		my $dm = $type ? 'Standard' : 'Customer Pick-up';

		map { print STDERR "PARAM: $_ = " . $r->param($_) . "\n" } $r->param();


		eprint::service::insert_service_spec( $log, $dbh, $pid, $ship, 'deliverymethod' , $dm);
		eprint::service::insert_service_spec( $log, $dbh, $pid, $ship, 'ddmShipVia1' , $id) if $id;


		unless ( $sid ) {
	    	$sid = eprint::print_project::insert_service($r->log, $dbh, $pid, 'Discount') unless $sid;
			eprint::service::insert_service_spec( $log, $dbh, $pid, $sid, 'c-CAD-1' , '1');
			eprint::service::insert_service_spec( $log, $dbh, $pid, $sid, 'services' , '0');
			eprint::service::insert_service_spec( $log, $dbh, $pid, $sid, 'txtPrice1' , '1');
		}


	map { 
		if ( $_ =~ /strshipping(.*)/ ) {
			print STDERR "HAVE KEY : $_, $1  		-- $ship \n";
			my $f = "txtShipping" . ucfirst($1);
			my $v =  $order->{$_};

			$f = 'txtShippingPostalCode' if  $1 eq  'postalcode';
			if ($1 eq  'firstname' ) {
				$f = 'txtShippingContact';
				$v .= " $order->{strshippinglastname}";
			}

			eprint::service::insert_service_spec( $log, $dbh, $pid, $ship, $f, $v);
		} else {
			print STDERR "NO MATCH: $_ \n";
		}
	} keys %{$order};
	 
	#die();


		$dbh->do("UPDATE tbl_service_specifications set strvalue = ? where strname = 'c-CAD-1' and lngprojectindex = ?", undef, $o->{cursalesprice}, $pid);

		eprint::Build::build($log, $dbh, $pid, $var, 0);

		
  		PQS::model::order::set_spec_pid($o->{lngcontentindex}, $pid);

		#eprint::project::project_status($dbh, $pid, 'Waiting For Files');
		project_status($dbh, $pid, 'Waiting For Files');

		my $file_upload = $dbh->selectrow_array(q{
			SELECT upload_required FROM tbl_projects where lngprojectindex = ?
		},undef, $pid);

		push @pids, {
					 pid 		=> $pid,
					 #jobname	=> $o->{jobname},
					 jobname => $o->{jobname} . ' - ' . $prod->{specs}{name},
					 file_upload => $file_upload,
				    };
	}

	my $custom_projects = $dbh->selectall_arrayref(q{ 
		SELECT p.strprojectreference as jobname, p.lngprojectindex as pid 
		FROM tbl_order_contents oc, tbl_projects p
		WHERE oc.lngprojectindex = p.lngprojectindex AND oc.type = 'print' AND lngorderid = ? 
	}, {Slice => {}}, $order->{lngorderid});

	push @pids, @{$custom_projects};



	return \@pids;
}

sub make_rfq {
	my ($r, $dbh, $pid, $qty) = @_;

	use eprint::rfq;
	use eprint::service;
	use eprint::Service::PerItem;
	
    my $sid = eprint::project::check_for_service( undef, $dbh, $pid, 'PerItem');
	
	return unless $sid;

	my $rfq = $dbh->selectrow_array(q{
		SELECT strvalue FROM tbl_service_specifications WHERE lngserviceindex = ? AND strname = 'rfq'
	}, undef, $sid);
	
	return unless $rfq;
	
	my $old_pid = $dbh->selectrow_array(q{
		SELECT copy_pid FROM tbl_projects WHERE lngprojectindex = ?
	}, undef, $pid);


	my $old_rid = $dbh->selectrow_array(q{
		SELECT id FROM rfq WHERE pid = ?
	}, undef, $old_pid);

print STDERR "HAVE OLD RID: $old_rid FROM PID: $old_pid \n";

	my $rid = eprint::rfq::copy_rfq($dbh, undef, $old_rid);
	
	$dbh->do(q{
		UPDATE rfq SET pid = ? WHERE id = ?
	}, undef, $pid, $rid);

	$dbh->do(q{
		DELETE FROM rfq_services WHERE rid = ?
	}, undef, $rid);

	$dbh->do(qq{
		INSERT INTO rfq_services ( 
			SELECT $rid, lngserviceindex FROM tbl_project_contents 
			WHERE lngprojectindex = ? ORDER BY lngserviceindex
		)
	}, undef, $pid);

	
	print STDERR "HAVE RFQ: $rfq RID: $rid OLD_RID: $old_rid, OLD PID: $old_pid \n";

	my $log = $r->log;
	my %spec = eprint::service::get_specifications_pairs($log, $dbh, $pid, $sid);

	my $var = undef;
	my $service_type = 'PerItem';
	eprint::Service::PerItem::munge($log, $dbh, $var, $pid, $sid, $service_type, \%spec);


	my $buy = $spec{buy}{USD}->($qty) * $qty;


	my $sup_id = $dbh->selectrow_array(q{
		SELECT supplier FROM rfq_supplier WHERE rfq = ?
	}, undef, $rid);

	$dbh->do(q{
		INSERT INTO rfq_response ( rid, sid, supplier, price1, accepted ) 
		VALUES ( ?, ?, ?, ?, true ) 
	}, undef, $rid, 1, $sup_id, $buy);

	print STDERR "HAVE BUY PRICE: $buy SUP: $sup_id \n";

	my $info = {
		pid => $pid,
		sup_id => $sup_id,
		rid => $rid
	};

	my $file = q{/email/content/rfq_waiting.html};

    my %mail = (
         SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
         FROM    => configuration::get_value( $log, $dbh, 'AccountingEmail'),
         TO    	 => configuration::get_value( $log, $dbh, 'AccountingEmail'),
         SUBJECT => "RFQ Created for Project $pid"
    );

	misc::email_with_template($r, $log, $dbh, $file, \%mail, $info);
	
	
	
	
}

sub update_order {
	my ($r, $log, $dbh, $cookie, $var, $pid) = @_;
	my $order_id = $dbh->selectrow_array(q{
		SELECT max(lngorderid) from tbl_order_contents WHERE lngprojectindex = ?
	}, undef, $pid);
	

        my $order_info = get_order_totals(
            $dbh, $var->{cust_id}, $order_id
        );

        foreach my $order (@{ $order_info->{projects} }) {
            sql::update(
                $log, $dbh, 'tbl_Order_Contents',
                "lngOrderID = '$order_id'
                    AND lngProjectIndex = '$order->{index}'",
                strDescription => $order->{name},
                curSalesPrice  => $order->{price},
                intQuantity    => $order->{qty},
                dblTax1        => $order->{gst_amount} || 'NULL',
                dblTax2        => $order->{pst_amount} || 'NULL',
                dblTax3        => $order->{hst_amount} || 'NULL',
                dblShipping    => $order->{shipping}   || 'NULL',
            );
        }


        sql::update(
            $log, $dbh, 'tbl_Orders', "lngOrderID = '$order_id'",
            curFedTax      => $order_info->{gst_total} || 'NULL',
            curProvTax     => $order_info->{pst_total} || 'NULL',
            curHarmTax     => $order_info->{hst_total} || 'NULL',
            curTotalSale   => $order_info->{total}     || 'NULL',
        );
}

sub notify_low_inventory {
    my ( $r, $dbh, $item, $current_qty ) = @_;

	my $info = $dbh->selectrow_hashref(q{
		SELECT * from inventory_specs WHERE id = ?
	}, undef, $item);
	my $remaining;

	$info->{inventoryID} = $item;
	$info->{current_inv} = $current_qty;

print STDERR "HAVE SPECS: ", Dumper($info);

	my $file = q{/email/content/inventory_reorder.html};

    my %mail = (
         SMTP    => configuration::get_value( $r->log, $dbh, 'Mail Server'),
         FROM    => configuration::get_value( $r->log, $dbh, 'InventoryReorder'),
         TO    	 => configuration::get_value( $r->log, $dbh, 'InventoryReorder'),
         SUBJECT => "Inventory Reorder"
    );

	misc::email_with_template($r, $r->log, $dbh, $file, \%mail, $info);

}


sub notify_cancel {
    my ( $r, $log, $dbh, $email, $order_id ) = @_;

	my $info = {
		order_id => $order_id,
	};

	my $file = q{/email/content/order_cancel.html};

    my %mail = (
         SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
         FROM  	 => configuration::get_value( $log, $dbh, 'CancelEmail'),
         TO    	 => configuration::get_value( $log, $dbh, 'CancelEmail'),
         SUBJECT => "Order " . order_rev($dbh, $order_id) . " CANCELLED"
    );
print STDERR "SENT CANCEL NOTICE TO: $mail{TO}";

	misc::email_with_template($r, $log, $dbh, $file, \%mail, $info);

}

sub notify_pending_approval {
    my ( $r, $log, $dbh, $email, $order_id ) = @_;

	my $info = {
		ORDER_ID => $order_id,
	};

	my $file = q{/email/forms/order_pending_approval.html};

    my %mail = (
         SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
         FROM    => configuration::get_value( $log, $dbh, 'OrderingEmail'),
         TO      => $email,
         SUBJECT => "Order: " . order_rev($dbh, $order_id)
    );
print STDERR "SENT PENDING NOTICE TO: $email \n";

	misc::email_with_template($r, $log, $dbh, $file, \%mail, $info);

}

sub notify_date_change {
    my ( $r, $log, $dbh, $order_id ) = @_;


	my $info = {
		ORDER_ID => $order_id,
	};

	my $email = $dbh->selectrow_array(q{
		SELECT stremail from tbl_orders where lngorderid = ?
	}, undef, $order_id);

	my $file = q{/email/forms/order_pending_approval_modify.html};

    my %mail = (
         SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
         FROM    => configuration::get_value( $log, $dbh, 'OrderingEmail'),
         TO      => $email,
         SUBJECT => "Order " . order_rev($dbh, $order_id) . " - Pending Approval - Date Change"
    );
print STDERR "SENT PENDING CHANGE NOTICE TO: $email \n";

	misc::email_with_template($r, $log, $dbh, $file, \%mail, $info);

}

sub notify_overdraft {
    my ( $r, $log, $dbh, $cust_id, $avail_credit ) = @_;

    # Send confirmation
    my %info;
    my $cust = eprint::obj_customer->new( $log, $dbh, $cust_id );
    $info{CompanyName}     = $cust->get('Name');
    $info{AvailableCredit} = sprintf("%.2f", $avail_credit);

    my $email_template = misc::load_file($r, '/email/email_template.html');

    $info{ReplacementText}
        = q{<!--#include virtual="/email/content/overdraft_notification.html"}
        . q{-->};

    $email_template
        = ssi::variable_substitution($r, $log, $dbh, $email_template, \%info);

     my %mail = (
         SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
         FROM    => configuration::get_value(
                        $log, $dbh, 'CreditApplicationEmail'
                   ),
         TO      => configuration::get_value(
                        $log, $dbh, 'CreditApplicationEmail'
                   ),
         SUBJECT => "Credit Notification"
     );

     misc::send_email_with_attachment(
         $r, $log, \%mail, '', Mail::encode_qp($email_template), 'text/html',
         'quoted-printable'
     );
}

# only notifies for paypal payments right now
sub notify_payment {
    my ( $r, $log, $dbh, $order_id, $token) = @_;

    # Send confirmation
    my %info;
    my $fullname = $dbh->selectrow_array(q{
        SELECT concat(strfirstname, ' ', strlastname) FROM tbl_orders WHERE lngorderid = ?
    },undef, $order_id);

    my $amount_paid = $dbh->selectrow_array(q{
        SELECT curamount FROM tbl_payments WHERE strtransactionid = ?
    },undef, $token);

    $info{CustomerName}     = $fullname;
    $info{AmountPaid}       = sprintf("%.2f", $amount_paid);
    $info{OrderNumber}      = $order_id;

    my $email_template = misc::load_file($r, '/email/email_template.html');

    $info{ReplacementText}
        = q{<!--#include virtual="/email/content/payment_notification.html"}
        . q{-->};

    $email_template
        = ssi::variable_substitution($r, $log, $dbh, $email_template, \%info);

    my $order_email = $dbh->selectrow_array(q{
        SELECT stremail FROM tbl_orders WHERE lngorderid = ?
    },undef, $order_id);

     my %mail = (
         SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
         FROM    => configuration::get_value( $log, $dbh, 'OrderingEmail'),
         TO      => $order_email,
         SUBJECT => "PayPal Payment Approval Notification"
     );

     misc::send_email_with_attachment(
         $r, $log, \%mail, '', Mail::encode_qp($email_template), 'text/html',
         'quoted-printable'
     );
}
sub inventory_checkin {
    my ($r, $log, $dbh, $order_id, $project_index ) = @_;
print STDERR "START SUB inventory_checkin \n";

	my $type;
    my $checkin = eprint::project::check_for_service( $log, $dbh, $project_index, 'Inventory');
    if ($checkin ) {
		$type = "IN";
        $_ = "SELECT intQuantityIndex FROM tbl_Order_Contents Where lngOrderID='$order_id' AND lngProjectIndex='$project_index'";
        my ($qty_index) = sql::sql_statement( $log, $dbh, $_ );

        my ($inventory_index) =  eprint::project::check_for_service( $log, $dbh, $project_index, 'Inventory');

        my ( $weight, $qty, $case, $inv_id ) = eprint::service::get_specifications( $log, $dbh, undef, $inventory_index, 
				'txtProjectWeight', "txtInventoryQty$qty_index", "piece_case", 'ItemID');

        $_ = "SELECT lngCustomerID, strProjectReference FROM tbl_Projects WHERE lngProjectIndex='$project_index'";
        my ( $cust_id, $desc) = sql::sql_statement( $log, $dbh, $_ );
		my $unit_price = scalar $dbh->selectrow_array(q{
			SELECT cursalesprice / intquantity FROM tbl_order_contents WHERE lngorderid = ? and lngprojectindex = ?
		}, undef, $order_id, $project_index);

print STDERR "HAVE CASE COUNT: $case \n";

		$qty = int($qty/$case) if $case;
		$unit_price = sprintf("%4f", $unit_price * $case) if $case;


		#Remove "Inventory Adjustment" Label FROM project description.
		$desc =~ s/^.*Adjustment"*\s//i;

		my @inv  =  (
				lngCustomerID        => $cust_id,
                lngProjectIndex      => $project_index,
                dtmCheckInDate       => 'NOW()',
                strDescription       => $desc,
				locationid			 => 1,
				unit_price			 => $unit_price,
                dblProjectWeight     => $weight ? $weight : 0,
                lngCheckInQuantity   => $qty ? $qty : 0,
                lngRemainingQuantity => $qty ? $qty : 0
		);

		#IF and id was selected on the check in service page
		#then add it to the insert.
		push @inv, ( id => $inv_id ) if $inv_id;
		

        sql::insert( $log, $dbh, 'tbl_Inventory', @inv);

		#IF id was not selected then INSERT description AS itemid.
		unless ( $inv_id ) {
			my $id = $dbh->selectrow_array(q{
				SELECT id FROM tbl_inventory WHERE lngprojectindex = ?
			}, undef, $project_index);
	print STDERR "UPDATE INVETORY ITEM: $id TO: $desc \n";
			$dbh->do(q{
				INSERT INTO inventory_specs (id, itemid, reorder_notify, reorder_notify_max ) VALUES ( ?, ?, 0, 0)
			}, undef, $id, $desc );
		}
    } 
    else {
		$type = "OUT";
        my $checkout = eprint::project::check_for_service( $log, $dbh, $project_index, 'InventoryCheckOut');
        my $r_qty;
print STDERR "HAVE INVENTORY CHECKOUT: $checkout \n";
        if ( $checkout ) {
            my ( $qty, $inventory_index, $checkout_index, $itemid, $location ) 
                = eprint::service::get_specifications( $log, $dbh, undef, $checkout, 
                'txtCheckOutQty', 'InventoryIndex', 'CheckOutIndex', 'InventoryID', 'InventoryLocation');

            $_ = "SELECT lngRemainingQuantity FROM tbl_Inventory WHERE lngInventoryIndex='$inventory_index'";
            ( $r_qty ) = sql::sql_statement( $log, $dbh, $_ );

print STDERR "HAVE INVENTORY ID: $itemid \n";
			
			if ( $itemid ) {
				my $co = $dbh->prepare(q{
					INSERT into tbl_inventory_checkout values ( ?,?,?,?,NOw(),NULL,?,? )
				});
				my $ids = $dbh->selectall_hashref(q{
					SELECT lnginventoryindex, lngremainingquantity as qty 
					FROM tbl_inventory WHERE id = ? and locationid = ?
				}, 'lnginventoryindex', {}, $itemid, $location);
			
				my $max_qty;
				map { $max_qty += $ids->{$_}{qty} } keys %{$ids};
                $log->error(" Invetory Quantity Error: $qty Remaining: $max_qty ");
				my $co_total;
				my $up = $dbh->prepare(q{
					UPDATE tbl_inventory SET lngremainingquantity = ? WHERE  lnginventoryindex = ?
				});
				map {
				 	my $q = $ids->{$_}{qty};	
					my $co_qty = ($co_total + $q) > $qty ? $qty - $co_total : $q; 
					if ( $co_total < $qty ) {
						$co_total += $co_qty;
						$co->execute($_, 				$checkout_index,	$order_id,
								     $project_index,   	$co_qty,         	$q-$co_qty); 		
						$up->execute($q-$co_qty, $_);
					}
				
				} sort {$a <=> $b} keys %{$ids};
				



		
print STDERR "INVENTORY: QTY: $qty RQTY: $r_qty \n";

				if ( $qty and $qty <= $r_qty ) {
					# $r_qty is now inventory level after check_out.
					$r_qty -= $qty;
					sql::insert( $log, $dbh, 'tbl_Inventory_CheckOut', 
							'lngInventoryIndex',    $inventory_index,
							'lngCheckOutIndex',        $checkout_index,
							'lngOrderID',            $order_id,
							'lngProjectIndex',        $project_index,
							'dtmCheckOutDate',        'NOW()',
							'lngCheckOutQuantity',    $qty ? $qty : 0,
							'lngRemainingQuantity',    $r_qty ,
							);
					$_ = "UPDATE tbl_Inventory set lngRemainingQuantity='$r_qty' WHERE lngInventoryIndex='$inventory_index'";
					sql::sql_statement( $log, $dbh, $_ );


					check_inventory_level($r, $dbh, $itemid);

				} else {
					$log->debug(" Invetory Quantity Error: $qty Remaining: $r_qty ");
				}


			}
        }

    } #
	return $type;
}

sub check_inventory_level {
	my ($r, $dbh, $itemid)  = @_;

	my $inv_level = $dbh->selectrow_array(q{
		SELECT SUM(lngremainingquantity) FROM tbl_inventory 
		WHERE id = ?
		AND obsolete IS NOT true
	}, undef, $itemid);

	my $reorder = $dbh->selectrow_array(q{
		SELECT reorder_notify FROM inventory_specs WHERE id = ?
	}, undef, $itemid );

print STDERR "CHECK INVENTORY LEVEL: $inv_level < $reorder \n";
	if ( $inv_level < $reorder ) {
		notify_low_inventory($r, $dbh, $itemid, $inv_level);
	} 

	return $inv_level;

}

sub send_invoice {
    my ( $r, $log, $dbh, $order_id ) = @_;
    my %order;

    $order{is_invoice} = 1;

        $order{'Terms'} = scalar $dbh->selectrow_array(q{
        SELECT lngTerms 
        FROM tbl_Customer_Credit
        WHERE lngCustomerindex = 
            ( SELECT lngCustomerID
        FROM tbl_orders where 
        lngorderID = ?
        )
    },undef, $order_id);
    get_invoice_to( $log, $dbh, \%order, $order_id );
    get_ship_to( $log, $dbh, \%order, $order_id );
    get_misc( $log, $dbh, \%order, $order_id );
    get_projects( $log, $dbh, \%order, $order_id );
    $order{'CCITYPROVCOUNTRY'} = misc::build_city_prov_country(@order{'txtCity','txtStateProvince','txtCountry'} );
    $order{'FCITYPROVCOUNTRY'} = misc::build_city_prov_country(@order{'txtShippingCity','txtShippingStateProvince','txtShippingCountry'} );
    $order{'ORDER_ID'} = $order_id;

    $order{'siteURL'} = configuration::get_value( $log, $dbh, 'siteURL' );
    $order{'SecureSiteURL'} = configuration::get_value( $log, $dbh, 'SecureSiteURL' );

	my @pids = ();
	map { push @pids, $_->{pid} } @{$order{PROJECTS}}; 
	my $inv_not;
    for my $pid (@pids) {
        my %hash;
        eprint::docket::summary_display($r, $log, $dbh, \%hash, $pid, undef, 1);
        push @{$order{projects}}, \%hash;
		$inv_not = $dbh->selectrow_array(q{
			SELECT inv_not FROM tbl_projects WHERE lngprojectindex = ?
		}, undef, $pid) || $inv_not ? 'Inventory - ' : '';
		
    }

print STDERR "CHECK INV_NOT; $inv_not \n\n";
    my @attachments = ();

    my $email_template = misc::load_file($r, '/email/forms/order.html');
    $_ = Mail::encode_qp( ssi::variable_substitution( $r, $log, $dbh, $email_template, \%order ) );
    my @body = ('', $_, 'text/html', 'quoted-printable');

    $_ = misc::load_file($r, '/email/forms/order.html');
    if ( $_ ) {
        $_ = Mail::encode_qp( ssi::variable_substitution( $r, $log, $dbh, $_, \%order ) );
        push @attachments, "Order$order_id.html", $_, 'text/html', 'quoted-printable';
    }
    my %mail = (
        SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
        FROM    => configuration::get_value( $log, $dbh, 'AccountingEmail'),
        TO        => $order{'txtEmail'},
        SUBJECT => "Invoice for Order " . order_rev($dbh, $order_id),
	);
    misc::send_email_with_attachment( $r, $log, \%mail, @body, @attachments );

    get_projects( $log, $dbh, \%order, $order_id );

    @attachments = ();
    $email_template = misc::load_file($r, '/email/forms/order.html');
    $_ = Mail::encode_qp( ssi::variable_substitution( $r, $log, $dbh, $email_template, \%order ) );
    @body = ('', $_, 'text/html', 'quoted-printable');
    $_ = misc::load_file($r, '/email/forms/order.html');
    if ( $_ ) {
        $_ = Mail::encode_qp( ssi::variable_substitution( $r, $log, $dbh, $_, \%order ) );
        push @attachments, "Order$order_id.html", $_, 'text/html', 'quoted-printable';
    }
    %mail = (
        SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
        FROM    => configuration::get_value( $log, $dbh, 'AccountingEmail'),
        TO        => configuration::get_value( $log, $dbh, 'AccountingEmail'),
        SUBJECT => "$inv_not Invoice for Order " . order_rev($dbh, $order_id),
    );
    misc::send_email_with_attachment( $r, $log, \%mail, @body, @attachments );

}
sub is_chino {
	# Add special flag for Chino/Norcal supplier that changes 
	# Contact info sent out with email.
	my ($dbh, $pid) = @_;
		my ($sid)  = eprint::project::get_signature_indices(undef, $dbh, $pid);
		my ($sup_id) = $dbh->selectrow_array(q{
			SELECT lngcustomerid FROM tbl_customer c, tbl_equipment e
			WHERE c.strcompanyname = e.strsupplier AND e.lngindex = 
			( SELECT strvalue::int FROM tbl_service_specifications WHERE strname = 'press'
			  AND lngserviceindex = ? LIMIT 1 )
		}, undef, $sid);


print STDERR "HAVE SUPPLIER FOR PID: $pid - $sup_id SID: $sid \n"; 

		return $sup_id == 142 ? 1 : 0; 

}


# This is a self-contained function that sends the email messages for a specified order to the apropriate people.
sub send_sales_order {
    my ( $r, $log, $dbh, $order_id, $pending, $inv ) = @_;
    my %order;


	display_order( \%order, $order_id);

#print STDERR "SEND SALES ORDER: $order_id \n", Dumper(\%order);

	



    my $cust_id = scalar $dbh->selectrow_array(q{
        SELECT lngCustomerid FROM tbl_orders WHERE lngorderid = ?
    }, undef, $order_id);


#	my $sup_email = join(',', keys %{$suppliers});
#print STDERR "HAVE EMAIL: $sup_email  - INV NOT: $inv_not \n";

	my $sup_email = '';
	my $inv_not = '';
	my $cc = '';




	use MIME::Base64;

    my @project_summaries;


   	my $email_content = misc::load_file($r, '/email/email_template.html');

   	$order{ReplacementText} = q{<!--#include virtual="/email/forms/order_with_PDF.html"} . q{-->};

    $order{'siteURL'} = configuration::get_value( $log, $dbh, 'siteURL' );

	$email_content = Mail::encode_qp(ssi::variable_substitution( $r, $log, $dbh, $email_content, \%order ));
	#$email_content = encode('utf-8',ssi::variable_substitution( $r, $log, $dbh, $email_content, \%order ));

	#my @body = ("", $email_content,  'text/html', 'utf-8');
	my @body = ("", $email_content,  'text/html', 'quoted-printable');


#print STDERR "SALES ORDER SHOW PROJECTS \n";
#	map {
#		print STDERR "HAVE PROJECT: $_->{project_price} \n", Dumper($_);
#	} @{$order{projects}};


    my $email_template = misc::load_file($r, '/email/forms/order.html');

    my $html = ssi::variable_substitution( $r, $log, $dbh, $email_template, \%order );

	use PDF::WebKit;
	my %opt = (page_size => 'Letter', 
		margin_right => '0.25in', margin_left=>'0.4in',
		margin_top => '0.4in', margin_bottom=>'0.4in'
	);

  	my $kit = PDF::WebKit->new(\$html, %opt);

	my $pdf = $kit->to_pdf;

#	open(my $fh, ">/tmp/test/$order_id.pdf") or die;
#	print $fh $pdf;
#	close $fh;



	$pdf = encode_base64($pdf);

	push @body, ("order-$order_id.pdf", $pdf,  'application/pdf', 'base64');


print STDERR " CHECK ORDER IS PENDING\n";
# Safeway does not want to send out order without date approval.
	if ( $pending ) {
print STDERR "ORDER IS PENDING\n";
		#notify_pending_approval($r, $log, $dbh, $order{'txtEmail'}, $order_id);

		my $sales_email = scalar $dbh->selectrow_array(q{
			SELECT strEmail FROM tbl_customer_users WHERE lnguserid = 
				(SELECT lngsalesperson FROM tbl_customer WHERE lngcustomerid = ?)
		}, undef, $cust_id);

		my $notificationemail = $dbh->selectrow_array(q{
			SELECT notificationemail FROM tbl_customer WHERE lngcustomerid = ?
		}, undef, $cust_id);


		my $creator = $dbh->selectrow_array(q{
			SELECT u.strfirstname || ' ' || u.strlastname FROM tbl_customer_users u, tbl_orders o
			WHERE u.lnguserid = o.lnguserid
			AND lngorderid = ?
		}, undef, $order_id);


		my %mail = (
			SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
			FROM    => configuration::get_value( $log, $dbh, 'OrderingEmail'),

			SUBJECT => "${inv_not}$creator - Order " . order_rev($dbh, $order_id),
			CC => $cc,
		);

		$mail{TO} = $order{'txtEmail'};
		$mail{SUBJECT} = "Order " . order_rev($dbh, $order_id);
		misc::send_email_with_attachment($r, $log, \%mail, @body, @project_summaries ) if $sales_email;
		delete $mail{BODY};

		
		#$mail{TO} = $sales_email;
		#$mail{SUBJECT} = "Sales: ${inv_not}$creator - Order " . order_rev($dbh, $order_id);
		#misc::send_email_with_attachment($r, $log, \%mail, @body, @project_summaries ) if $sales_email;
		#delete $mail{BODY};

		$mail{TO} = configuration::get_value( $log, $dbh, 'OrderingEmail');
		$mail{SUBJECT} = "Admin: ${inv_not}$creator - Order " . order_rev($dbh, $order_id);
		misc::send_email_with_attachment($r, $log, \%mail, @body, @project_summaries );
		delete $mail{BODY};

		$mail{TO} = $notificationemail;
		$mail{SUBJECT} = "Notification: ${inv_not}$creator - Order " . order_rev($dbh, $order_id);
		misc::send_email_with_attachment($r, $log, \%mail, @body, @project_summaries ) if $notificationemail;
		delete $mail{BODY};

		#Add supplier here if needed.



	} elsif ( $r->param('OrderDateApproved') ) {
print STDERR "SEND DATE APPROVAL \n";
		my %mail = (
			SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
			FROM    => configuration::get_value( $log, $dbh, 'OrderingEmail'),
			TO      => $order{'txtEmail'},
			SUBJECT => "Order " . order_rev($dbh, $order_id),
		);
		misc::send_email_with_attachment($r, $log, \%mail, @body, @project_summaries );
	} else {
print STDERR "CAN't SEND DATE APPROVAL \n";
	}


}

sub order_history {
    my ( $r, $log, $dbh, $variable ) = @_;

    if ( $$variable{'cust_id'} ) {
        ssi::get_start_end_dates( $log, $dbh, $variable,
                $r->param('ddmStartYear'),
                $r->param('ddmStartMonth'),
                $r->param('ddmStartDay'),
                $r->param('ddmEndYear'),
                $r->param('ddmEndMonth'),
                $r->param('ddmEndDay') );

        #my $status = sql::escape($r->param('ddmStatus'));

        my $ordered_by = $variable->{user}{type} eq 'C' && $variable->{user_id} ne '293' ? $variable->{user_id}
														: sql::escape($r->param('ddmOrderedBy'));

        $_ = "SELECT DISTINCT lngUserId, strFirstName || ' ' || strLastName FROM tbl_Customer_Users 
			  WHERE lngCustomerID = $$variable{'cust_id'} ORDER BY    strFirstName || ' ' || strLastName";

        $$variable{'ddmOrderedBy'} = ssi::fill_drop_down( $log, $dbh, $_, $ordered_by );


		my $user = $r->param('ddmOrderedBy');

# Start building SQL For Order History
        $_ = "SELECT o.lngOrderID, to_char(dtmOrderDate, 'MM/DD/YYYY'), 
			  strFirstName || ' ' || strLastName, o.strStatus, curTotalSale,\n".
            "(SELECT SUM(curAmount) FROM tbl_Payments 
			  WHERE tbl_Payments.lngOrderID=o.lngOrderID AND strSessionID IS NULL), 'projects'\n".

            "FROM tbl_Orders o 
			 WHERE o.lngCustomerID = '$variable->{'cust_id'}' AND o.strStatus != 'Incomplete'\n
			";


# Customer History is now user specific for Safeway,
# Let customers see any order with projects that were made for that user.

#This does not work with the current non printed products.
#        $_ .= "AND  EXISTS ( SELECT lngorderid FROM tbl_order_contents oc, tbl_projects p  
#					      		WHERE tbl_orders.lngorderid = oc.lngorderid AND oc.lngprojectindex = p.lngprojectindex
#								AND p.lnguserindex = '$ordered_by' )\n"
#         			if $ordered_by ne '';            

		$_ .= " AND o.lnguserid = '$user' " if $user;


		if ( $r->param('search') ) { 
			my $str = $dbh->quote(lc($r->param('search')));
			$_ .= qq{ AND lower(strProjectReference) ~ $str};
			$variable->{search} = $r->param('search');
		}

        $_ .= "AND date(dtmOrderDate) BETWEEN date('$$variable{'StartDate'}') AND date('$$variable{'EndDate'}')\n";
        $_ .= "ORDER BY lngOrderID DESC\n";

print STDERR "have order sql: $_ \n";

        @{$$variable{'ORDERS'}} = sql::sql_statement( $log, $dbh, $_ );

        if ( @{$$variable{'ORDERS'}} ) {
            $$variable{'ReportTotal'} = 0;
            $$variable{'ReportBalance'} = 0;
            for ( my $index = 0; $index < @{$$variable{'ORDERS'}}; $index += 7 ) {
                if ( $$variable{'ORDERS'}[$index+3] ne 'Cancelled' ) {
                    $$variable{'ReportTotal'} += $$variable{'ORDERS'}[$index+4];
                    $$variable{'ORDERS'}[$index+5] = sprintf( "%.2f", $$variable{'ORDERS'}[$index+4] - $$variable{'ORDERS'}[$index+5] );
                    $$variable{'ReportBalance'} += $$variable{'ORDERS'}[$index+5];
                } else {
                    $$variable{'ORDERS'}[$index+5] = '0.00';
                }
                $$variable{'ORDERS'}[$index+6] = $dbh->selectall_arrayref(q{
					SELECT o.lngprojectindex as pid, strprojectreference as reference FROM tbl_Order_contents o, tbl_projects p WHERE lngorderid = ?
					AND o.lngprojectindex = p.lngprojectindex
				}, {Slice=>{}}, $$variable{'ORDERS'}[$index] );

                push @{$$variable{'ORDERS'}[$index+6]}, @{
					$dbh->selectall_arrayref(q{
						SELECT o.product as product, name as reference 
						FROM tbl_Order_contents o, tbl_products p WHERE lngorderid = ?
						AND o.product = p.id
					}, {Slice=>{}}, $$variable{'ORDERS'}[$index] )
				};
                
			
            }
#use Data::Dumper;
#print STDERR "ORDER DUMPER: ", Dumper($variable->{ORDERS});
            $$variable{'ReportTotal'} = sprintf( "%.2f", $$variable{'ReportTotal'} );
            $$variable{'ReportBalance'} = sprintf( "%.2f", $$variable{'ReportBalance'} );

            ( $$variable{'CurrencyName'}, $$variable{'CurrencySymbol'}, undef ) = eprint::customer::get_currency( $log, $dbh, $$variable{'cust_id'} );
        }
    }

	print STDERR "HAVE VAARI", Dumper($variable);
    return OK;
}

sub get_misc {
    my ( $log, $dbh, $variable, $order_id ) = @_;

    @$variable{qw(
        Downpayment  TOTAL         GST           HST           PST  
        ORDERED_BY   CreationDate  ORDER_STATUS  CurrencyName  CurrencySymbol
        PONUM        AdministratorComments  AdministratorName  additionalOrderInformation
	CountyTAX	shipvia
      )} = $dbh->selectrow_array(q{
           SELECT curDownpayment, curTotalSale, curFedTax, curHarmTax, 
                  curProvTax, strFirstName || ' ' || strLastName, 
                  to_char(dtmOrderDate, 'MM/DD/YYYY'), strStatus, 
                  strCurrencyName, strCurrencySymbol, strPoNumber, 
                  strAdministratorComments, strAdministratorName,
				  addorderinfo, curcountytax, shipping_type
            FROM tbl_Orders 
            WHERE lngOrderID = ?
    }, undef, $order_id);
print STDERR "COUNTY TAX: $variable->{CountyTAX} \n";

	$variable->{additionalOrderInformation} =~ s/\r/<br>/g;

    $variable->{SUB_TOTAL} = scalar $dbh->selectrow_array(q{
        SELECT SUM(curSalesPrice) FROM tbl_Order_Contents WHERE lngOrderID = ?
    }, undef, $order_id);

    $variable->{SHIPPING} = scalar $dbh->selectrow_array(q{
        SELECT SUM(dblshipping) FROM tbl_Order_Contents WHERE lngOrderID = ?
    }, undef, $order_id) || '0.00';

    $variable->{SHIPPING} += scalar $dbh->selectrow_array(q{
        SELECT shipping FROM tbl_Orders WHERE lngOrderID = ?
    }, undef, $order_id) || '0.00';
	

    $variable->{POSTAGE} = scalar $dbh->selectrow_array(q{
        SELECT SUM(dblpostage) FROM tbl_Order_Contents WHERE lngOrderID = ?
    }, undef, $order_id) || '0.00';

    $variable->{AmountPaid} = scalar $dbh->selectrow_array(q{
        SELECT SUM(curAmount) 
        FROM tbl_Payments 
        WHERE lngOrderID = ? AND strSessionID IS NULL
    }, undef, $order_id);

    $variable->{CustID} = scalar $dbh->selectrow_array(q{
        SELECT lngcustomerid
        FROM tbl_orders 
        WHERE lngorderid = ?
    }, undef, $order_id);

    $variable->{SalesRep} = scalar $dbh->selectrow_array(q{
        SELECT strFirstName || ' ' || strLastname
        FROM tbl_customer_users 
        WHERE lnguserid = ( SELECT lngsalesperson from tbl_customer where lngcustomerid = ? )
    }, undef, $variable->{CustID});
    
    
    if ($variable->{ORDER_STATUS} ne 'Cancelled') {
        $variable->{AmountOutstanding} = sprintf("%.2f", $variable->{TOTAL}       - $variable->{AmountPaid});
        $variable->{DepositDue}        = sprintf("%.2f", $variable->{Downpayment} - $variable->{AmountPaid}) 
            if $variable->{AmountPaid} < $variable->{Downpayment};
    } 
    else {
        $variable->{AmountOutstanding} = '0.00';
        $variable->{DepositDue}        = '0.00';
    }

	$variable->{NotGroupPricing} = $dbh->selectrow_array(q{
		SELECT ShowPricing FROM tbl_orders WHERE lngorderid = ?
	}, undef, $order_id);
	

    $variable->{AmountPaid} = sprintf("%.2f", $variable->{AmountPaid});

    # Now get shipping information
    @$variable{qw(ShippingDate ShippingVia ShippingTracking)} 
        = $dbh->selectrow_array(q{
            SELECT o.dtmshipdate, v.strname, o.strshippingtracking
            FROM tbl_orders o LEFT JOIN tbl_ship_via v 
                    ON (o.lngshipvia = v.lngindex)
            WHERE o.lngorderid = ?
	}, undef, $order_id);

	$variable->{Delivery_date} = delivery_date($dbh, $order_id);

	$variable->{CTNAME} = $dbh->selectrow_array(q{
		SELECT name FROM county_taxes WHERE id =
			( SELECT CountyTax FROM tbl_orders WHERE lngorderid = ?) 
	}, undef, $order_id);
print STDERR "HAVE COUNTY TAXT NAME: $variable->{CTNAME} \n";

	$variable->{NotGroupPricing} = $dbh->selectrow_array(q{
		SELECT ShowPricing FROM tbl_orders WHERE lngorderid = ?
	}, undef, $order_id);
}


# Gets a listing of an orders contents, this includes line items as well as
# projcets. TODO Cleaned-up version is still pretty dirty.
sub get_projects {
    my ( $log, $dbh, $variable, $order_id ) = @_;

    # Get the details (contents) of the order.
    my $sth = $dbh->prepare(q{
        SELECT lngcontentindex                                AS id,
               lngProjectIndex                                AS pid,
               strDescription                                 AS name,
               ( SELECT strStatus FROM tbl_Projects p
                 WHERE p.lngProjectIndex = c.lngProjectIndex
               )                          
               AS status,
               to_char(dateRequired,'MM/DD/YYYY')             AS "date",
               intQuantity                                    AS qty,
               intQuantityIndex                               AS qty_idx,
               curSalesPrice                                  AS price
        FROM tbl_Order_Contents c
        WHERE lngOrderID = ?
        ORDER by lngProjectIndex
    });
    $sth->execute($order_id);

    my @line_items;

	my $tn = 'SELECT trackingnumber FROM tbl_project_contents WHERE lngprojectindex = ?';

    # Project line items need their pricing and some other stuff?
    LINE_ITEM:
    while (my $line = $sth->fetchrow_hashref) {
        # Add the line to the list.
        push @line_items, $line;

        # We're done with non-projects.
        next LINE_ITEM unless $line->{pid};

        # Project need pricing and an expirery?
        my $pid = $line->{pid};

        # If it's a project we'll need to get the pricing as well.
        my @project_prices = eprint::project::project_price( $log, $dbh, $pid );
        $line->{project_price} = $project_prices[ $line->{qty_idx} - 1 ];
        $line->{expired}       = eprint::project::validate_project_price($log, $dbh, $pid);
        $line->{index}         = $pid; # Alias.
		$line->{trackingnumber} = join(',',grep {$_} @{$dbh->selectcol_arrayref($tn, undef, $pid)});

		$line->{txtInvoiceComments} = $dbh->selectrow_array(q{
			SELECT strInvoiceComments FROM tbl_projects WHERE lngprojectindex = ?
		}, undef, $pid);

        $variable->{InvalidPrices} = 1 if $line->{expired}; # What is this?
    }

    # Push it into $variable for legacy usage.
    $variable->{PROJECTS} = \@line_items;

use Data::Dumper;
print STDERR "ORDER GET PROJECTS : ", Dumper(\@line_items);

    return \@line_items;
}

sub history_details {
    my ( $r, $log, $dbh, $variable ) = @_;

    if (   $r->param('ddmCustomer') 
         && grep { $variable->{user_type} eq $_ } qw(A E))
    {
        eprint::login::select_customer( $r, $log, $dbh, $variable->{cookie}, $variable );
    }

    my $order_id = $r->param('order_id') 
		|| $r->param('pid')
		|| $variable->{param}{order_id};


    $variable->{HidePricing} = 1 if $r->param('PackingSlip');

    if ( $r->param('btnFunction') eq 'Cancel' ) {
        cancel_order($r, $log, $dbh, $order_id );
	}

	if ( $r->param('OrderDateModify') ) {

		notify_date_change( $r, $log, $dbh, $order_id );
	} 
	elsif ( $r->param('OrderDateApproved') ) {
		$dbh->do(q{
			UPDATE tbl_orders SET strstatus  = 'In Production'
			WHERE lngorderid = ?
		}, undef, $r->param('order_id'));
		$dbh->do(q{
			UPDATE tbl_projects SET strstatus  = 'In Production'
			WHERE lngprojectindex IN ( SELECT lngprojectindex 
			FROM tbl_order_contents WHERE lngorderid = ? )
		}, undef, $r->param('order_id'));

		$dbh->do(q{
			UPDATE tbl_project_contents SET strstatus  = 'In Production'
			WHERE lngprojectindex IN ( SELECT lngprojectindex 
			FROM tbl_order_contents WHERE lngorderid = ? )
		}, undef, $r->param('order_id'));


		send_sales_order( $r, $log, $dbh, $order_id, undef );
	}

    display_order($variable, $order_id );

	eprint::login::display_select_customer( $r, $log, $dbh, $variable, $variable->{cust_id} ); 

    my @pids =  @{ $dbh->selectcol_arrayref(q{
        SELECT lngprojectindex
        FROM tbl_order_contents
        WHERE lngorderid = ? and type = 'print'
        }, undef, $order_id
    ) };


    for my $pid (@pids) {

		if ( $r->param('ddmCustomer') ) {
			$dbh->do(q{
				UPDATE tbl_projects SET lngcustomerid = ? WHERE lngprojectindex = ?
			}, undef, $r->param('ddmCustomer'), $pid)
		}


    }

	if ( $r->param('ddmCustomer') ) {
		$dbh->do(q{
			UPDATE tbl_orders SET lngcustomerid = ? WHERE lngorderid = ?
		}, undef, $r->param('ddmCustomer'), $order_id);
	}
	

    if ( $r->param('PackingSlip') ) {
		packing_slip($order_id, $variable);
    }

	$variable->{CTNAME} = $dbh->selectrow_array(q{
		SELECT name FROM county_taxes WHERE id =
			( SELECT CountyTax FROM tbl_orders WHERE lngorderid = ?) 
	}, undef, $order_id);

	my $cookie = undef;

	if ( $r->param('CHECKOUT') ) {
		show_payflow($r, $log, $dbh, $cookie, $variable, $order_id, 'history' );
	}

	map {
	my $pid = $_;
	my @data =  eprint::Service::Shipping::get_ship_info($r, $log, $dbh, $pid, 1);
	$variable->{ship_data} = \@data;



	print STDERR "HAVE SHIP DATA", Dumper($variable->{ship_data}, @data);
	} @pids;

    my $payment_info_query 
    = qq{select strmethod, strtransactionid, TO_CHAR(dtmdate :: DATE,'dd MON yyyy') AS dtmdate, curamount, 
        case 
        when strmethod = 'PayPal' and strdescription LIKE '%Approved%'
        then 'APPROVED'
        when strmethod = 'PayPal' and strdescription NOT LIKE '%Approved%'
        then 'NOT APPROVED'
        when strmethod = 'Manual'
        then 'APPROVED'
        else strdescription
        end as strdescription
        from tbl_payments WHERE lngorderid = ?};
    my $sth = $dbh->prepare($payment_info_query);
    $sth->execute($order_id);    
    my $payment_info = $sth->fetchall_arrayref({});

        
	print STDERR "Payment Info: ", Dumper($payment_info);

    $variable->{payment_info} = $payment_info;
}

sub packing_slip {
	my $r = session::r;
	my $dbh = session::dbh;
	my $log = session::log;

	my $variable = shift;




	my $oid = $r->param('order_id');
	my $pid = $r->param('pid');
	my $packid 	 = $r->param('packid');
       
	$pid = $dbh->selectrow_array(q{SELECT lngprojectindex FROM tbl_order_contents WHERE lngorderid = ?  order by 1}, undef, $oid) unless $pid;
	$pid = $dbh->selectrow_array(q{SELECT pid FROM packing_slip WHERE id = ?}, undef, $packid) unless $pid;

	$oid = $dbh->selectrow_array(q{SELECT lngorderid FROM tbl_order_contents WHERE lngprojectindex = ?  order by 1}, undef, $pid) unless $oid;


	print STDERR "HAVE PID: $pid Order: $oid \n";

	my $PIDS = $dbh->selectall_arrayref(q{
		SELECT lngprojectindex FROM tbl_order_contents WHERE lngorderid = ? order by 1
	}, {Slice => {}}, $oid);

	$variable->{PIDS} = $PIDS;


	my $boxes = $r->param('boxes');
	my $item_qty = $r->param('ship_qty');
	my $notes = $r->param('comments');

	if ( $r->param('Save') ) {
		$dbh->do('DELETE FROM packing_slip where id = ?', undef, $packid) if $packid;
		if ($packid) {
			$dbh->do('INSERT INTO packing_slip values ( ?,?,?,?,? ) ', undef, $packid, $pid, $boxes, $item_qty, $notes);
		} else { 
			$dbh->do('INSERT INTO packing_slip ( pid, boxes, item_qty, notes, pack_date)  values ( ?,?,?,?, NOW() ) ', undef, $pid, $boxes, $item_qty, $notes);
			$packid = $dbh->last_insert_id('','public','packing_slip','id');
		}


		
	}

	print STDERR "HAVE PID: $pid PACK: $packid ORDER: $oid \n";

	my $pack = $dbh->selectrow_hashref(q{SELECT *,
	   to_char(pack_date, 'Mon dd, yyyy') as pdate	from packing_slip WHERE id = ? }, undef, $packid) if $packid;

   ##$pid = $pack->{pid} unless $pid;


	print STDERR "HAVE PACK: ", Dumper($pack);
	

	#	my $sid = $dbh->selectrow_array(q{SELECT sid FROM ship_address WHERE shipid = ?}, undef, $shipid);
	# my $pid = $dbh->selectrow_array(q{SELECT lngprojectindex FROM tbl_project_contents WHERE lngserviceindex = ?}, undef, $sid);

	my $order = $dbh->selectrow_hashref(q{SELECT * FROM tbl_order_contents, tbl_orders WHERE lngprojectindex = ?
			AND tbl_order_contents.lngorderid = tbl_orders.lngorderid}, undef, $pid);

	my $order_id = $order->{lngorderid};

	my $project = $dbh->selectrow_hashref(q{SELECT * from tbl_projects WHERE lngprojectindex = ? }, undef, $pid);
	


	#	my $address = new eprint::address($log, $dbh, $shipid);
	
	#$address->bake_form_hash($variable, 1);




	#my $shipid = $r->param('shipid');

	#my %shipping;
	#   %shipping 	= eprint::service::get_specifications_pairs($log, $dbh, $pid, $sid) if $sid;
	

	   #print STDERR "HAVE: $sid, $pid, $order_id -- $shipid \n", Dumper($order, \%shipping, $variable);

	   #$variable->{ship} = \%shipping;



	print STDERR "HAVE ORDER ID: $variable->{order_id}, $order_id \n";

	#$variable->{boxes}  = $shipping{"boxes-$shipid"};
	#$variable->{weight} = $shipping{"weight-$shipid"};
	#$variable->{size}   = $shipping{"size-$shipid"};
	#$variable->{ship_qty}   = $shipping{"add_qty1-$shipid"};

	$variable->{order_id} = $order_id;
	#$variable->{ship_sid} = $sid;

	$variable->{order} 		= $order;

	#Used for Project details
	$variable->{project} 	= $project;
	$variable->{docket}      = eprint::docket::header_info($log, $dbh, $pid);

	$variable->{pid} = $pid;
	$variable->{boxes} = $pack->{boxes};
	$variable->{ship_qty} = $pack->{item_qty};
	$variable->{packid} = $pack->{id};
	$variable->{comments} = $pack->{notes};

	#$variable->{shipnum} = $dbh->selectrow_array(q{SELECT shipnum FROM ship_address WHERE shipid = ? }, undef, $shipid);

	use POSIX qw(strftime);


	$variable->{date} =  $pack->{pdate};

	print STDERR Dumper($pack), "HAVE: $pid, $order_id -- $packid \n";

	my $r    = session::r;
	my $log    = session::log;
	my $dbh    = session::dbh;



	my $name = $variable->{user}{company}{name};

	my $img = "/images/packing_slip/$name.png";

	my $path = ssi::get_file_path($r, $img);

	
	my $x = -e $path;

	$variable->{logo} =  $x ? $img : "/images/packing_slip/default.png"; 

	print STDERR "HAVE PATH:  $path, $x \n";


}

sub get_products {
	my ($var, $order_id) = @_;


	my $data = PQS::model::order::get_order_products($order_id);

print STDERR "HAVE PRODUCTS: ", Dumper($data);

	map {
		$_->{name} = PQS::model::products::get_name_from_id($_->{product});
		$_->{qty}  = $_->{intquantity};
		$_->{price} = $_->{cursalesprice};

	} @{$data};

	$var->{products} = $data;
	
	return;

}


sub display_order {
    my ( $variable, $order_id ) = @_;

	my $r = session::r;
	my $log = session::log;
	my $dbh = session::dbh;


print STDERR "HAVE VARS: $r, $log, $dbh \n";

	get_invoice_to( $log, $dbh, $variable, $order_id );
	get_ship_to( $log, $dbh, $variable, $order_id );
	get_misc( $log, $dbh, $variable, $order_id );


    my $totals = get_order_totals($dbh, $variable->{cust_id}, $order_id);

    $variable->{projects} = $totals->{projects};

	my ($spid, $ssid) = $dbh->selectrow_array(q{
		SELECT pc.lngprojectindex, pc.lngserviceindex  
		FROM tbl_orders o, tbl_project_contents pc, tbl_order_contents oc
		WHERE o.lngorderid = oc.lngorderid AND oc.lngprojectindex = pc.lngprojectindex
		AND strservicetype = 'Shipping'
		AND o.lngorderid = ?
	}, undef, $order_id );
	print STDERR "HAVE PID: $spid \n";

	my @data =  eprint::Service::Shipping::get_ship_info($r, $log, $dbh, $spid, 1);
	$variable->{ship_data} = \@data;
	$variable->{spid} = $spid;
	$variable->{ssid} = $ssid;


	print STDERR "HAVE ORDER TOTALS: ", Dumper($totals);

    @$variable{qw( SUB_TOTAL SHIPPING POSTAGE GST PST HST CountyTAX TOTAL PROMO_DISCOUNT )}
        = map { sprintf('%.2f', $_) }
            @$totals{qw(sub_total shipping_total postage_total 
						gst_total pst_total hst_total county_total total discount)};


	$variable->{CCITYPROVCOUNTRY} = misc::build_city_prov_country(
		@$variable{qw( txtCity txtStateProvince txtCountry )}
	);
	$variable->{FCITYPROVCOUNTRY} = misc::build_city_prov_country(
		@$variable{qw(
			txtShippingCity txtShippingStateProvince txtShippingCountry
		)}
	);
	$variable->{ORDER_ID} = $order_id;

	$variable->{Terms} = scalar $dbh->selectrow_array(q{
		SELECT lngTerms
		FROM tbl_Customer_Credit
		WHERE lngCustomerindex = ( SELECT lngCustomerID
								   FROM tbl_orders
								   WHERE lngorderID = ? )
		}, undef, $order_id
	);

    if ( $variable->{user_type} eq 'A' || $variable->{user_type} eq 'E' ) {
        ($variable->{AdministratorName}) = @{ $dbh->selectcol_arrayref(q{
            SELECT strFirstName || ' ' || strLastName
            FROM tbl_Customer_Users
            WHERE lngUserID = ?
            }, undef, $variable->{user_id}
        ) };
    }

    my $packing_slips = $dbh->selectall_arrayref(q{SELECT * FROM packing_slip WHERE pid in ( 
	    SELECT lngprojectindex FROM tbl_order_contents WHERE lngorderid = ? ) order by pack_date},  {Slice => {}}, $order_id); 
    $variable->{SLIPS} = $packing_slips;


print STDERR "HAVE QTYS IN VAR", Dumper($variable->{SLIPS});

}


sub quantity_select_display {
    my ($r, $log, $dbh, $cookie, $variable) = @_;

print STDERR "Start quantity SELECT display btnFunction: " . $r->param('btnFunction') . " \n";

    my ($order_id, $error);

    if ($r->param('btnFunction') eq 'ReOpen') {

        delete_unfinished_orders( $log, $dbh, $cookie );

        $order_id = $r->param('order_id');

		$dbh->do(q{
			UPDATE tbl_orders SET rev = rev + 1 WHERE lngorderid = ?
		}, undef, $order_id );

        sql::update(
            $log, $dbh, 'tbl_Orders', "lngOrderID = '$order_id'", 
            strStatus    => 'Re-Opened',
            strSessionID => $cookie 
        );

        my $projects = $dbh->selectcol_arrayref(q{
            SELECT lngProjectIndex
            FROM tbl_Order_Contents
            WHERE lngOrderID = ?
          }, undef, $order_id);

        if ($projects) {
            foreach my $project_index ( @$projects ) {
               next unless $project_index;
                sql::update(
                    $log, $dbh, 'tbl_Projects',
                    "lngProjectIndex = '$project_index'",
                    strStatus => 'Unordered'
                );

                sql::update(
                    $log, $dbh, 'tbl_Project_Contents',
                    "lngProjectIndex = '$project_index'
                     AND strStatus != 'Complete'",
                    strStatus => 'calculated' 
                );
            }
        }
    }
    elsif ($r->param('quote_id') ne '') {
        # Make order from quote
        my $quote_id = $r->param('quote_id');
        ($order_id, $error) = make_order_from_quote(
            $r, $log, $dbh, $cookie, $quote_id, $variable
        );
    }
    elsif ($r->param('btnFunction') eq 'Process Order') {
print STDERR "GO PROCESS ORDER \n";
        # Normal Order Creation
        ($order_id, $error) = add_project_to_order(
            $log, $dbh, $cookie, $variable, $r->param('ProjectIndex'), undef, 'print'
        );
    }

    return misc::error($log, $dbh, $variable, 'Error', $error) if $error;

    $order_id = get_unfinished_order(
        $log, $dbh, $cookie, $variable->{cust_id}, $variable->{user_id}
    ) if !$order_id;

    $variable->{CurrencySymbol} = scalar $dbh->selectrow_array(q{
        SELECT strcurrencysymbol
        FROM tbl_orders
        WHERE lngOrderId = ?
    }, undef, $order_id);

    if ($r->param('remove') ne '') {
        $dbh->do(q{
            DELETE FROM tbl_Order_Contents
            WHERE lngOrderID = ?
              AND lngProjectIndex = ?
        }, undef, $order_id, $r->param('remove'));
    }
   
    # Select all the projects in the current order.
    my @projects = @{ $dbh->selectcol_arrayref(q{
        SELECT lngProjectIndex 
        FROM tbl_Order_Contents 
        WHERE lngOrderID = ? and type = 'print'
    }, undef, $order_id) };

    foreach my $pid ( @projects ) {
        # Get desc and quantities for the project
        my ( $desc, @qtys ) = $dbh->selectrow_array(q{
            SELECT strProjectReference, intQuantity1, intQuantity2, intQuantity3
            FROM tbl_Projects
            WHERE lngProjectIndex = ?
        }, undef, $pid);

        #push @{$$variable{'PROJECTS'}}, $pid, $desc;

		use eprint::Service::Shipping;
		eprint::Service::Shipping::shipping_summary($r, $log, $dbh, $variable, $pid);

        my $hash = { cust_id => $variable->{cust_id} };
        eprint::docket::summary_display(
            $r, $log, $dbh, $hash, $pid, undef, 1
        );
        push @{ $variable->{projects} }, $hash;

		my $ships = $dbh->selectcol_arrayref(q{
			SELECT lngserviceindex FROM tbl_project_contents WHERE lngprojectindex = ? AND strservicetype = 'Shipping'
		}, undef, $pid);
		map { eprint::docket::shipping($r, $log, $dbh, $pid, $_) } @{$ships};

        my ($ordered_quantity) = $dbh->selectrow_array(q{
            SELECT intQuantityIndex
            FROM tbl_Order_Contents
            WHERE lngOrderID = ?
              AND lngProjectIndex = ?
        }, undef, $order_id, $pid);

        # Have to do selection outside
        my $selected = $ordered_quantity ? $ordered_quantity : 1;

        my @projects;
        my @project_prices = eprint::project::project_price(
            $log, $dbh, $pid
        );

        foreach my $i ( 1 .. @qtys ) {
            next unless $qtys[$i - 1];

            my $price     = shift @project_prices;
            my $unitprice = sprintf("%.2f", $price / $qtys[$i - 1]);

            push @projects , {
                index         => $i, 
                qty           => $qtys[$i-1],
                price         => $price, 
                unitprice     => $unitprice, 
                project_index => $pid,
                selected      => ($selected == $i
                                             ? 'checked="checked"'
                                             :'' ),
            };
        }

        push @{ $variable->{PROJECTSINFO} }, {
            index     => $pid, 
            reference => $desc,
            PROJECTS  => \@projects,
        };

    }

    $Profiles->{'CA-ON'}{'Civic Holiday'} = "1/Mon/Aug";

    my $Profile = $Profiles->{'CA-ON'};

    my @time = localtime();
    my $cal = Date::Calendar->new( $Profile ); 
    my $lead_time = configuration::get_value($log, $dbh, 'OrderLeadTime');

    my $date = $cal->add_delta_workdays(
            $time[5]+1900,$time[4]+1,$time[3],$lead_time );

    $variable->{years}  =  ssi::getyears($date->year());
    $variable->{days}   =   ssi::getdays($date->day());
    $variable->{months} = ssi::getmonths($date->month());

    if (allow_credit_card_payment($log, $dbh, $variable->{cust_id})) {
        $variable->{URL} = 'https://' . ($r->header_in('Host') || $r->server->server_hostname);
    }

    return OK;
}

sub cancel_order {
    my ($r, $log, $dbh, $order_id) = @_;

	
    sql::update(
        $log, $dbh, 'tbl_Orders', "lngOrderID='$order_id'",
        cancelled => 1 
    );

    sql::update(
        $log, $dbh, 'tbl_Orders', "lngOrderID='$order_id'",
        strStatus => 'Cancelled'
    );

    my $sth = $dbh->prepare(q{
        SELECT lngProjectIndex
        FROM tbl_Order_Contents
        WHERE lngOrderID = ?
    });

    foreach my $pid (@{ $dbh->selectcol_arrayref($sth, undef, $order_id) }) {
       next unless $pid;
        sql::update(
            $log, $dbh, 'tbl_Projects', "lngProjectIndex = '$pid'",
            strStatus => 'Canceled',
        );

        sql::update(
            $log, $dbh, 'tbl_Project_Contents',
            "lngProjectIndex = '$pid' AND strStatus != 'Complete'",
            strStatus => 'calculated',
        );
		
		$dbh->do(q{
			DELETE FROM tbl_inventory WHERE lngprojectindex = ?
		},undef, $pid);
    }

    my ($amount) = $dbh->selectrow_array(q{
        SELECT SUM(curamount)
        FROM tbl_payments
        WHERE lngorderid = ?
        AND strmethod = 'credit card'
        }, undef, $order_id
    );

    if ($amount > 0) {
        sendmail(
            To   => configuration::get_value($log, $dbh, 'AccountingEmail'),
            From => configuration::get_value($log, $dbh, 'AccountingEmail'),
            SMTP => configuration::get_value($log, $dbh, 'Mail Server'),

            Subject => '(PQS Software) Cancelled order with credit card '
                     . 'transaction.',
            Message => "Order number $order_id has payments totalling $amount"
                     . '.  This order has been cancelled, so you will '
                     . 'need to refund the customer.'
        );
    }
	notify_cancel( $r, $log, $dbh, undef, $order_id );
}

# I'm positive much of this can be cleaned up even more, but for now, I just
# factored it out because it was duplicated (and poorly, at that) in the code.
sub get_order_totals {
    my ( $dbh, $customer_id, $order_id ) = @_;

print STDERR "\n\nwSTART ORDER TOTALS FOR PROJECTS \n";


	my $prov_state = $dbh->selectrow_array(q{SELECT strShippingState FROM tbl_Orders WHERE lngOrderID = ?}, undef, $order_id);
	   $prov_state = $dbh->selectrow_array(q{SELECT strState FROM tbl_Orders WHERE lngOrderID = ?}, undef, $order_id) unless $prov_state;
		
	my ( $pst_rate, $hst_rate, $gst_rate ) = $dbh->selectrow_array(q{
        SELECT dblStatePercent, dblHarmonisedPercent, dblFederalPercent
        FROM tbl_Taxes
        WHERE strStateID = ?
    }, undef, $prov_state);

    my $county_rate = $dbh->selectrow_array(q{
		SELECT amount FROM county_taxes WHERE id = (
			SELECT countytax FROM tbl_orders WHERE lngorderid = ?
		)
	},undef, $order_id);

print STDERR "Have County Tax RATE: $county_rate FOR ORDER: $order_id \n";

    my ( $pst_exempt, $gst_exempt ) = $dbh->selectrow_array(q{
        SELECT ysnPSTExempt, ysnGSTExempt
        FROM tbl_Customer
        WHERE lngCustomerID = ?
    }, undef, $customer_id);

    my $sth = $dbh->prepare(q{
        SELECT lngProjectIndex, product, intquantity, cursalesprice,
               ( SELECT strProjectReference
                 FROM tbl_Projects p
                 WHERE p.lngProjectIndex = o.lngProjectIndex
               ), 
               intQuantityIndex, date(dateRequired), lngcontentindex, subgroup, jobname
        FROM tbl_Order_Contents o
        WHERE lngOrderID = ? ORDER BY product, lngprojectindex
    });

    $sth->execute($order_id);

	my $county_total = 0;
	my $postage_total = 0;
    my ($sub_total, $gst_total, $pst_total, $hst_total, $shipping_total, $total) = qw(0 0 0 0 0 0);
	

                   my ( $pid,  $product,  $qty,  $prod_price,  $desc,  $qtyIndex,  $date,   $ci, $sub, $jobname);
    $sth->bind_columns(\$pid, \$product, \$qty, \$prod_price,  \$desc, \$qtyIndex, \$date, \$ci, \$sub, \$jobname);

    # declaring the array ref isn't necessary, but I'm not entirely sure its
    # always (and always will be) that way, so better safe than sorry.
    my $return_ref;
       $return_ref->{projects} = [];
	my $subgroup;

	my $promo;

	$dbh->do(q{DELETE from order_discount WHERE orderid = ? }, undef,  $order_id);

	my $discount;
    while ($sth->fetch()) {

print STDERR "ADD TO TOTAL- PROJECT PID: $pid, PROD: $product QTY: $qty PRICE: $prod_price \n";

		my $contentid = $pid || $product;
		my $new_promo = new PQS::Object::promotion();


		my @promos = $new_promo->qualify($pid, $product);


		if ( @promos ) {
			#For now use first available promo.
			my $promo_id = shift @promos;
			$promo = new PQS::Object::promotion($promo_id) unless $promo;


			$discount  = $promo->discount($prod_price);

			$dbh->do(q{INSERT INTO order_discount ( promo, orderid, contentid, customer, discount ) VALUES (?, ?, ?, ?, ?) }, undef, 
				$promo_id, $order_id, $contentid,  $customer_id, $discount);

			print STDERR "HAVE VALID PROMO TOAL DISCOUNT: $discount \n";

		
		}




		my $status;
		my $shipping;
		my $postage;

        my ( $pst_amount, $gst_amount, $hst_amount, $county_amount );

        my @project_prices = eprint::project::project_price(
            Apache2::ServerUtil->server->log, $dbh, $pid
        );

print STDERR "HAVE PROJECT PRICES: @project_prices FOR PID: $pid \n";

        my $price = $prod_price > 0 ? $prod_price : $project_prices[$qtyIndex - 1];

print STDERR "NEXT TO TOTAL- PROJECT PID: $pid, PROD: $product QTY: $qty PP: $prod_price PRICE: $price \n";

		if ( $pid ) {

			my $postage = $dbh->selectrow_array(q{
				SELECT SUM(strValue::Numeric(10,2)) FROM tbl_service_specifications
				WHERE  strname = ? and lngserviceindex IN (
					SELECT lngserviceindex FROM tbl_service_specifications
					WHERE strName = 'ServiceName' AND strValue= 'Postage'
					AND lngprojectindex = ?
				)
			}, undef, "txtPrice$qtyIndex", $pid);
	print STDERR "POSTAGE TOTAL: $postage \n";

			$shipping = $dbh->selectrow_array(q{
				SELECT SUM(strValue::Numeric(10,2)) FROM tbl_service_specifications
				WHERE  strname = ? and lngserviceindex IN (
					SELECT lngserviceindex FROM tbl_project_contents
					WHERE strServiceType = 'Shipping'
					AND lngprojectindex = ?
				)
			}, undef, "txtPrice$qtyIndex", $pid);

			$price -= $shipping;
			$price -= $postage;

			$shipping_total += $shipping;
			$postage_total  += $postage;
			($qty, $status) = $dbh->selectrow_array(qq{
				SELECT intQuantity$qtyIndex, strStatus
				FROM tbl_Projects
				WHERE lngProjectIndex = ?
			}, undef, $pid);
		} else {
		  $desc = PQS::model::products::get_name_from_id($product);

		  #$desc = $desc . ' ' . $jobname;
		  #Manoj asked for desc to be reversed, jobname first.
		  
		  $desc = $jobname . ' ' . $desc;
		}



        my ($prod_tax1_exempt, $prod_tax2_exempt, $prod_tax3_exempt );
		my $county_exempt;

		($prod_tax1_exempt, $prod_tax2_exempt, $prod_tax3_exempt ) = 
        	PQS::model::order::tax_exemptions($product) unless $pid;

        #the best I could come up with based on the ugly, ugly, code I'm
        #trying to factor out here that does the *exact* same thing 3 times
        #over.
        my $taxes = {
            pst => [ \$pst_rate, \$pst_amount, \$pst_total,
                     [ \$pst_exempt, \$prod_tax2_exempt ]
                   ],
            gst => [ \$gst_rate, \$gst_amount, \$gst_total,
                     [ \$gst_exempt, \$prod_tax1_exempt ]
                   ],
            hst => [ \$hst_rate, \$hst_amount, \$hst_total,
                     [ \$gst_exempt, \$prod_tax1_exempt ]
                   ],
            county => [ \$county_rate, \$county_amount, \$county_total,
                     [ \$county_exempt, \$prod_tax3_exempt ]
                   ],
        };

        foreach my $tax ( keys %$taxes ) {
            my ($rate, $amount, $total, $exemption_ref) = @{ $taxes->{$tax} };

            if ($$rate) {

				map { print STDERR " $tax HAVE TAX: $$_ \n" } @{ $exemption_ref };

                $$amount = grep({ $$_ eq 'Y' || $$_ == 1 } @{ $exemption_ref })
                         ? 0
                         : $tax eq 'pst' 
						 		? sprintf('%.2f', $price * $$rate / 100)
                         		: sprintf('%.2f', ($price + $shipping) * $$rate / 100);

                $$total += $$amount;
            }
print STDERR "TAX INFO: $tax Rate: $$rate, Amount: $$amount \n";
        }

print STDERR "HAVE ORDER TOTAL PROJECT PRICE: $price \n";

		my $line = {
            'index'       => $pid || $product,
            name          => $desc,
            status        => $status,
            date          => $date,
            qty           => $qty,
            price         => $price,
            project_price => $price,
            gst_amount    => $gst_amount,
            pst_amount    => $pst_amount,
            hst_amount    => $hst_amount,
            county_amount => $county_amount,
	    	shipping      => $shipping,
	    	postage       => $postage,
	    	content_index => $ci,
	    	product 	  => $product,
        };
		$line->{hide} = $dbh->selectrow_array(q{
			SELECT hide FROM tbl_order_contents WHERE lngcontentindex = ?
		}, undef, $ci);

		if ( $product) { 
			$line->{lead_time} =  PQS::model::products::lead_time($product);
			$line->{subgroup} =  $sub;
		} else { 
			project_details($dbh, $customer_id, $line, $pid);
		}

print STDERR "HAVE PROJECT DETAILS: $line->{project_price} FOR PID: $pid \n";
		

		push @{ $return_ref->{projects} }, $line;

		push @{ $return_ref->{products} }, $line if $product;

		$subgroup->{$sub} += $price;

        
        $sub_total   += $price;
        $total       += ($price + $shipping + $postage);
		$total       += $gst_amount + $pst_amount + $hst_amount;
		$total 	     += $county_amount;
    
    }

	#Apply discount after project loop
	$total -= $discount;

	map { 
		my $ci = $_->{content_index};
		$_->{price} = $subgroup->{$ci} if defined $subgroup->{$ci}  
	} @{$return_ref->{products}};
    my $order_ship = PQS::model::order::shipping_price($order_id);
	
    $total          += $order_ship;
    $shipping_total += $order_ship;

    @$return_ref{qw(
         pst_total   gst_total   hst_total   county_total 	sub_total   total   
		 shipping_total postage_total discount
    )} = (
        $pst_total, $gst_total, $hst_total, $county_total, $sub_total, $total, 
		$shipping_total, $postage_total, $discount
    );

    return $return_ref;
}



sub project_details { 

	my ($dbh, $cust_id, $line, $pid ) = @_;

	my $log = session::log;
	my $r   = session::r;

	$line->{expired}       = eprint::project::validate_project_price($log, $dbh, $pid);

	my $tn = 'SELECT trackingnumber FROM tbl_project_contents WHERE lngprojectindex = ?';
	$line->{trackingnumber} = join(',',grep {$_} @{$dbh->selectcol_arrayref($tn, undef, $pid)});

	$line->{txtInvoiceComments} = $dbh->selectrow_array(q{
		SELECT strInvoiceComments FROM tbl_projects WHERE lngprojectindex = ?
	}, undef, $pid);

	my $hash = { cust_id => $cust_id };
	eprint::docket::summary_display( $r, $log, $dbh, $hash, $pid, undef, 1);
	
	#docket overwrites qty variable with array of qty's
	map { $line->{$_} = $hash->{$_} unless $_ eq 'qty' } keys %{$hash};

}



sub get_gateway_info {
    my ($log, $dbh, $cust_id) = @_;

    my $pricelist_id = eprint::customer::get_pricelist_id(
        $log, $dbh, $cust_id
    );

    my ($merchant_id) = $dbh->selectrow_array(q{
        SELECT merchant_id FROM pricelist WHERE id = ?
        }, undef, $pricelist_id
    );

    return {} if !$merchant_id;

    return $dbh->selectrow_hashref(q{
        SELECT module, account_number, password
        FROM payment_merchants WHERE id = ?
        }, undef, $merchant_id
    );
}

sub allow_credit_card_payment {
    my ($log, $dbh, $cust_id) = @_;

    # Ensure there's a payment gateway on this pricesheet.
    my $gateway_info = get_gateway_info($log, $dbh, $cust_id);

    return 0 if !$gateway_info->{module};

    return $dbh->selectrow_arrayref(q{
        SELECT COUNT(*) > 0
        FROM payment_merchants
    })->[0];
}

sub reorder_notice {
    my ($r, $log, $dbh, $cookie, $var) = @_;
	my $id = $r->param('id');
	( $var->{date}, $var->{itemid} ) = $dbh->selectrow_array(q{
		SELECT Now()::date, itemid FROM inventory_Specs WHERE id = ?
	}, undef, $id);

	($var->{order_id}) = $dbh->selectrow_array(q{
		SELECT max(lngorderid) FROM tbl_order_contents WHERE lngprojectindex IN (
				SELECT lngprojectindex FROM tbl_inventory WHERE id = ?
		)
	}, undef, $id);

	my $pid = scalar $dbh->selectrow_array(q{
		SELECT max(lngprojectindex) FROM tbl_order_contents WHERE lngorderid = ?
	}, undef, $var->{order_id});

	$var->{order_qty} = scalar $dbh->selectrow_array(q{
		SELECT intquantity FROM tbl_order_contents WHERE lngorderid = ? and lngprojectindex = ?
	}, undef, $var->{order_id}, $pid);


	my $prep = $dbh->selectrow_hashref(q{
		SELECT strSalutation, strFirstName, strLastname, strAddress1, strAddress2, strcompanyname, 
		       strCity, strpostalcode, strState, strCountry, strphone, strext, strfax, stremail,
			   dtmorderdate::date as order_date
			   
				
		FROM tbl_orders where lngorderid = ?
	}, {}, $var->{order_id});
	map { $var->{$_} = $prep->{$_} } keys %{$prep};

	$var->{type} = scalar $dbh->selectrow_array(q{
		SELECT CASE WHEN ysnmultipage THEN 'B' ELSE 'CT' END FROM tbl_projecttypes WHERE lngindex = (
				SELECT lngprojecttype FROM tbl_projects WHERE lngprojectindex = ?
		)
	}, undef, $pid);
	my $dims = $dbh->selectall_hashref(q{
		SELECT strname, strvalue FROM tbl_service_specifications WHERE lngprojectindex = ?  
			AND strname IN ( 'flat_width', 'flat_height' ) 
	}, 'strname', {}, $pid ) ;
	map { $var->{$_} = $dims->{$_}{strvalue} } keys %{$dims};
	

	$var->{plies} = scalar $dbh->selectrow_array(q{
		SELECT lngmultipart FROM tbl_paper WHERE lngindex = (
			SELECT strvalue::int FROM tbl_service_specifications WHERE lngprojectindex = ?
			AND strname = 'substrate' limit 1
		)
	}, undef, $pid);

	$var->{quantity} =  $dbh->selectrow_array(q{ 
		SELECT sum(lngremainingquantity) FROM tbl_inventory WHERE id = ? 
	}, undef, $id);

	my @t = localtime();
	my $start = ($t[5]+1900-1) . '-' . ($t[4]+0) . '-1'; 
	my $end = ($t[5]+1900) . '-' . ($t[4]+0) . '-1'; 

	$var->{yearly_usage} =  $dbh->selectrow_array(q{ 
		SELECT sum(lngcheckoutquantity) FROM tbl_inventory_checkout WHERE lnginventoryindex IN ( 
			SELECT lnginventoryindex FROM tbl_inventory WHERE id = ? 
		)
	    AND dtmcheckoutdate::date BETWEEN ? AND ? 
	}, undef, $id, $start, $end);

	$var->{monthly_usage} = sprintf("%.0f",$var->{yearly_usage} / 12 );
	$var->{id} = $id;

}

sub order_rev {
	my $dbh = shift;
	my $id = shift;

	my $rev = $dbh->selectrow_array(q{
		SELECT rev FROM tbl_orders WHERE lngorderid = ?
	}, undef, $id); 

	return $id . "-$rev";

}

sub get_county_tax_id {
	my ($dbh, $cust, $user) = @_;

	my $countytax = $dbh->selectrow_array(q{
		SELECT countytax FROM tbl_customer WHERE lngcustomerid = ?
	},undef, $cust) || 0;

print STDERR "Have County Tax: $countytax Cust: $cust User: $user \n";
	return $countytax;

}

sub paypal_error {
	my ($r, $log, $dbh, $cookie, $var, $amount ) = @_;
	
print STDERR "HAVE PAYPAL ERROR \n";

	my $er;

	map { $er .= "$_ = " . $r->param($_) . "<br>" } $r->param();

	$var->{error} = $er;

}



sub paypal_return {
	my ($r, $log, $dbh, $cookie, $var, ) = @_;

	my $results;

	my $token 	= $r->param('SECURETOKENID');
	my $amount 	= $r->param('AMT');

	my $order_id = PQS::model::order::get_id_from_token($token);
	my $payment  = PQS::model::order::get_payment_from_token($token);
	my $token_type =  PQS::model::order::token_type($order_id);

	$var->{HISTORY} = 1 if $token_type eq 'history';

	print STDERR "HAVE ORDER: $order_id FROM token: $token PAYMENT: $payment\n";

	$var->{order_id} = $order_id;
	
    map { 
    	$var->{$_} = $r->param($_);
   		$results .= "$_ = " . $r->param($_) . "<br>" ;
		print STDERR "HAVE RESULTS: $_ = " . $r->param($_) . "\n";
    } $r->param();

	if ( $payment ) {
		print STDERR "ALREADY HAVE PAYMENT FOR TOKEN: $token \n";
		return;
	}

	
	$var->{results} = $results;

	my $state = $r->param('RESPMSG');
	
	if ($state eq 'Approved' ) {

		print STDERR "Payment has been Approved \n";

		my $session 	= undef;
		my $method 		= 'PayPal';
		my $currency 	= 'CA';

		my ($user, $cust) = PQS::model::order::user_id($order_id);

		PQS::model::payment::new_payment( 
			$order_id, $user, $cust, $session, $method, $currency, 
			$token, $results, $amount);

		my $status = PQS::model::order::get_status( $order_id);

		print STDERR "HAVE STATUS: $status \n";

		if ( $status eq 'Incomplete' ) {
			$var->{CONFIRM} = 1;

		}
		
		$status = 'In Production';

		PQS::model::order::set_status( $order_id, $status);
	
		print STDERR "TIME TO COMPLETE Send Sales Order $order_id \n";
		#finalise_order( $r, $log, $dbh, $cookie, $var, $order_id );
		
        #send payment confirmation
        notify_payment( $r, $log, $dbh, $order_id, $token);

		send_sales_order( $r, $log, $dbh, $order_id, 1 );
	} else {
		print STDERR "HAVE PAYAPL RESULT: $results \n";
	}
	

}


sub show_payflow {
	my ($r, $log, $dbh, $cookie, $var, $order_id, $type ) = @_;
	
	$order_id = get_unfinished_order(
		$log, $dbh, $cookie, $var->{cust_id}, $var->{user_id}
	) unless $order_id;

	my $totals = get_order_totals($dbh, $var->{cust_id}, $order_id);
	my $order = new PQS::Object::order($order_id);
    my $amount_paid = $order->payment_total;
    if($amount_paid){
        $totals->{total} = $totals->{total} - $amount_paid;
        if($totals->{total}<0){ $totals->{total} = 0; }
    }
	my $amount = sprintf( "%.2f", $totals->{total} );

print STDERR "HAVE PAYMENT AMOUNT: $amount, Rounded FROM: $totals->{total} \n";

	die("No Payment Amount") unless $amount;

	my $paypal_user 	= configuration::get_value($log, $dbh, 'paypal_user');
	my $paypal_pass 	= configuration::get_value($log, $dbh, 'paypal_password');
	my $paypal_vendor 	= configuration::get_value($log, $dbh, 'paypal_vendor');
	my $paypal_mode 	= configuration::get_value($log, $dbh, 'paypal_mode');
	my $paypal_partner 	= configuration::get_value($log, $dbh, 'paypal_partner');

	my $production = $paypal_mode eq 'LIVE' ? 1 : 0;

    use WebService::PayPal::PaymentsAdvanced;
	my $args = 
        {
            user     		=> $paypal_user,
            password 		=> $paypal_pass,
            vendor   		=> $paypal_vendor,
			production_mode => $production,
			partner			=> $paypal_partner,
        };

	print STDERR "HAVE PAYAPAL ARGS ", Dumper($args);

		
    my $payments = WebService::PayPal::PaymentsAdvanced->new($args);

	print STDERR "HAVE PAYPAL PARAMS: ", Dumper($args, $amount );

    my $response = $payments->create_secure_token(
        {
            AMT            => $amount,
            TRXTYPE        => 'S',
        }
    );

    my $uri = $response->hosted_form_uri;

	$var->{SECURETOKEN} 	= $response->secure_token;
	$var->{SECURETOKENID} 	= $response->secure_token_id;
	$var->{PAYPAL_MODE} 	= $paypal_mode;

	PQS::model::order::set_paypal_token($order_id,  $response->secure_token_id, $type);


}

1;
