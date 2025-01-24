package eprint::customer;
use strict;

use sql qw(:common);
use ssi ();

require misc;
require eprint::obj_customer;
require openprint;

use base qw(Exporter);
our @EXPORT_OK = qw(get_pricelist_id get_currency get_discount);

sub get_product_list {
	my $list = 1;
	return $list;
}

# We can speed things up a lot by caching this data
sub get_county_tax {
    my ($dbh, $cid) = @_;

    my $tax_id = $dbh->selectrow_array(qq{
        SELECT countytax
        FROM tbl_customer 
        WHERE lngcustomerid = ?
    }, undef, $cid);
    
    return $tax_id;
}


# We can speed things up a lot by caching this data
sub get_pricelist_id {
    my ($log, $dbh, $cid) = @_;

    my ($lid, $country) = $dbh->selectrow_array(qq{
        SELECT lngpricelist, strcountry 
        FROM tbl_customer 
        WHERE lngcustomerid = ?
    }, undef, $cid);

    # As all customers MUST have a price list (enfored by the database) if
    # we didn't get one the customer id must not exist.
    die "Customer ($cid) does not exist" unless defined $lid;
    
    return $lid;
}

# Given a customer id, return their selected currency.
sub get_currency {
    my $log = shift;
    my $dbh = shift;
    my $cid = shift; # Customer identity

    # Return information on selected currency.
    return $dbh->selectrow_array(q{
        SELECT m.name, m.symbol 
        FROM currency m, pricelist p, tbl_customer c
        WHERE m.code = p.currency
          AND p.id   = c.lngpricelist
          AND c.lngcustomerid = ?
    }, undef, $cid);
}

# Get the combined customer's and their pricelist's discount.
sub get_discount {
    my ($dbh, $cid) = @_;

    return $openprint::Company{discount}+$openprint::Pricelist{discount};

    my $sth = $dbh->prepare_cached(q{
        SELECT p.discount + c.dblpricingpercent AS discount
        FROM pricelist p, tbl_customer c
        WHERE p.id = c.lngpricelist
          AND c.lngcustomerid = ?
    });

    return $dbh->selectrow_array($sth, undef, $cid);
}


sub get_pricing_display_info {
    my ($log, $dbh, $cid) = @_;

    return $dbh->selectrow_array(q{
        SELECT ysnpricingservices, ysnpricingprojectview, ysnpricingquotes
        FROM tbl_customer
        WHERE lngcustomerid = ?
    }, undef, $cid);
}

sub attributes {
    my ($log, $dbh, $cid) = @_;

    return $dbh->selectall_hashref(q{
        SELECT strcompanyname AS name,
               straddress1    AS address1,
               straddress2    AS address2,
               strcity        AS city,
               strprovstate   AS province,
               strcountry     AS country,
               strphone       AS phone,
               strfax         AS fax
        FROM tbl_customers
        WHERE lngcustomerid = ?
    }, undef, $cid);
}

sub load_tradereferences {
    my ($r, $log, $dbh, $cid, $variable) = @_;

    my $sth = $dbh->prepare(q{
        SELECT strCompanyName, strContact, 
               strPhone,       strExt, 
               strFax,         strEmail, 
               dblCreditLimit
        FROM tbl_Trade_References
        WHERE lngCustomerID  = ?
          AND lngReferenceID = ?
    });

    for my $i ( 1 .. 3 ) {
        @$variable{
             "txtTradeReferenceCompanyName$i",  "txtTradeReferenceContact$i",
             "txtTradeReferencePhone$i",        "txtTradeReferenceExt$i",
             "txtTradeReferenceFax$i",          "txtTradeReferenceEmail$i",
             "txtTradeReferenceCreditLimit$i"
          } = $dbh->selectrow_array($sth, undef, $cid, $i);
    }
}

sub save_tradereferences {
    my ( $r, $log, $dbh, $cust_id ) = @_;

    # save trade references
    foreach my $tr ( 1 .. 3 ) {

        my @sql = (
            ( defined $r->param('txtTradeReferenceCompanyName'.$tr) ? ( 'strCompanyName', $r->param('txtTradeReferenceCompanyName'.$tr) ) : () ),
            ( defined $r->param('txtTradeReferenceContact'.$tr) ? ( 'strContact',    $r->param('txtTradeReferenceContact'.$tr) ) : () ),
            ( defined $r->param('txtTradeReferencePhone'.$tr) ? ( 'strPhone',        $r->param('txtTradeReferencePhone'.$tr) ) : () ),
            ( defined $r->param('txtTradeReferenceExt'.$tr) ? ( 'strExt',        $r->param('txtTradeReferenceExt'.$tr) ) : () ),
            ( defined $r->param('txtTradeReferenceFax'.$tr) ? ( 'strFax',        $r->param('txtTradeReferenceFax'.$tr) ) : () ),
            ( defined $r->param('txtTradeReferenceEmail'.$tr) ? ( 'strEmail',        $r->param('txtTradeReferenceEmail'.$tr) ) : () ),
            ( defined $r->param('txtTradeReferenceCreditLimit'.$tr) ? ( 'dblCreditLimit', ( $r->param('txtTradeReferenceCreditLimit'.$tr) eq '' ? 'NULL' : $r->param('txtTradeReferenceCreditLimit'.$tr) ) ) : () )
        );

        $_ = "SELECT lngCustomerID FROM tbl_Trade_References WHERE lngCustomerID = '$cust_id' AND lngReferenceID = '$tr'";
        ( $_ ) = sql_statement( $log, $dbh, $_ );
        if ( $_ ne '' ) {
            update( $log, $dbh, 'tbl_Trade_References', "lngCustomerID = '$cust_id' AND lngReferenceID = '$tr'", @sql );
        } else {
            insert( $log, $dbh, "tbl_Trade_References", 'lngCustomerID', $cust_id, 'lngReferenceID', $tr, @sql );
        }
    }

}


{
    my %shipping_fields = (
        'txtShippingCompanyName'    =>  'CompanyName',
        'txtShippingFirstName'      =>  'FirstName',
        'txtShippingLastName'       =>  'LastName',
        'rdbShippingSalutation'     =>  'Salutation',
        'txtShippingAddress1'       =>  'Address1',
        'txtShippingAddress2'       =>  'Address2',
        'txtShippingCity'           =>  'City',
        'ddmShippingStateProvince'  =>  'StateProvince',
        'ddmShippingCountry'        =>  'Country',
        'txtShippingPostalCode'     =>  'PostalCode',
        'txtShippingPhone'          =>  'Phone',
        'txtShippingExtension'      =>  'Extension',
        'txtShippingFax'            =>  'Fax',
        'txtShippingEmail'          =>  'Email',
    );

    sub load_shipping {
        my ( $log, $dbh, $cid, $variable ) = @_;

		my $address_id = $variable->{ddmShippingCompany};
        $address_id = $dbh->selectrow_array(q{
            SELECT lngShippingAddressIndex 
            FROM tbl_Customer 
            WHERE lngCustomerID =? 
        }, undef, $cid) unless $address_id;


        require eprint::address;
        my $address = new eprint::address($log, $dbh, $address_id);

		my @x;
        @$variable{ keys %shipping_fields } = @x =  ssi::htmlize( misc::trim($address->get( @shipping_fields{ keys %shipping_fields } ) ) );

		use Data::Dumper;
		print STDERR "CHECK ADDRESS : " , Dumper($variable);
    }

    sub save_shipping {
        my ($r, $log, $dbh, $cid) = @_;

        my $address_id = $dbh->selectrow_array(q{
            SELECT lngShippingAddressIndex 
            FROM tbl_Customer 
            WHERE lngCustomerID = ? 
        }, undef, $cid);

        require eprint::address;
        my $address = new eprint::address($log, $dbh, $address_id);

        my %params;
        foreach my $field ( keys %shipping_fields ) {
            $params{$shipping_fields{$field}} = misc::trim($r->param($field)) if defined $r->param($field);
        }
        $address->set( \%params );
    }

}

# Throws a ton of customer information into $variable.
sub load {
    my ($r, $log, $dbh, $cid, $variable) = @_; 

    my $sql = qq{
        SELECT strAccountNum,        strCompanyName,        strAddress1, 
               strAddress2,          strCity,               strProvState, 
               strPostalCodeZip,     strCountry,            strPhone,
               strExt,               strFax,                strLegalBusName, 
               LegalForm,            strBusinessType,       dtmBusinessStartdate, 
               strPresidentOwner,    strEmployees,          strAnnualSales, 
               strPSTNumber,         strGSTNumber,          ysnPSTExempt, 
               ysnGSTExempt,         strBankName,           strBankBranch, 
               strBankAccountNo,     strBankAccountManager, strBankPhone,
               strBankFax,           strBankEmail,          lngPriceList, 
               dblPricingPercent,    lngSalesPerson,        lngPrefShipAddressID,
               ysnAccountActivation, ysnSupplier,           ysnReseller,
               strCustomGreeting,    lngWarehouseID,        strWebURL,
			   division
        FROM tbl_Customer
        WHERE lngCustomerID = $cid
    };
        
    @$variable{qw(
        txtAccountNum         txtCompanyName         txtAddress1     
        txtAddress2           txtCity                ddmStateProvince      
        txtPostalCode         ddmCountry             txtPhone            
        txtExtension          txtFax                 txtLegalBusinessName
        rdbLegalForm          txtBusinessType        txtStartDate    
        txtPresidentOwner     ddmEmployees           ddmAnnualSales     
        txtPSTNumber          txtGSTNumber           rdbPSTExempt        
        rdbGSTExempt          txtBankName            txtBankBranch
        txtBankAccountNo      txtBankAccountManager  txtBankPhone   
        txtBankFax            txtBankEmail           ddmPriceList          
        txtPricingLevel       ddmSalesPerson         prefShippingAddress 
        rdbAccountActivation  rdbSupplier            rdbReseller
        txtCustomGreeting     ddmWarehouse           txtURL
		ddmDivision
    )} = misc::trim(sql_statement($log, $dbh, $sql));

    $$variable{Country}              = $$variable{txtCountry}       = $$variable{ddmCountry};
    $$variable{StateProvince}        = $$variable{txtStateProvince} = $$variable{ddmStateProvince};
    $$variable{txtBankAccountNumber} = $$variable{txtBankAccountNo};

    require eprint::customer_credit;
    my $customer_credit = new eprint::customer_credit( $log, $dbh, $cid );
    
    my %credit_fields = (
            txtTerms        => 'Terms',
            txtCreditLimit  => 'CreditLimit',
            rdbCreditHold   => 'CreditHold',
            txtDownpayment  => 'Downpayment',
    );

    @$variable{ keys %credit_fields } = ssi::htmlize( $customer_credit->get( @credit_fields{ keys %credit_fields } ) );

    return 1;
}

sub get_next {
    my ( $log, $dbh, $index ) = @_;

    my $customer = new eprint::obj_customer( $log, $dbh, $index );
    return $customer->next();
}

sub get_prev {
    my ( $log, $dbh, $index ) = @_;

    my $customer = new eprint::obj_customer( $log, $dbh, $index );
    return $customer->prev();
}

sub get_balance {
    my ( $dbh, $cust_id ) = @_;

    my ($payments) = $dbh->selectrow_array(q{
        SELECT SUM(curAmount)
        FROM tbl_Payments
        WHERE lngCustomerIndex = ?
         AND strSessionID IS NULL
        }, undef, $cust_id
    );

    my ($debt) = $dbh->selectrow_array(q{
        SELECT SUM(curTotalSale)
        FROM tbl_Orders
        WHERE lngCustomerID = ?
        AND strStatus IN ('Pending Deposit', 'In Production', 'Paid')
        }, undef, $cust_id
    );

   return $payments - $debt;
}


sub product_page {
    my ($r, $log, $dbh, $variable) = @_;

    my $cust = eprint::obj_customer->new($log, $dbh, $variable->{cust_id});

    my $path = $r->dir_config('site_specific') || $r->document_root.'/site_specific/';

    my $relative_path  = '/customers/' . $cust->path . "/products.html";

    # See if the customer has predefined products assigned to them.
    $variable->{has_products} = -e "$path/$relative_path";
    $variable->{include}      = $relative_path;

    require eprint::inventory;
    eprint::inventory::show_inventory($r, $log, $dbh, $variable);

    return 1;
}


1;
