package eprint::admin_customer;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY); # Offers OK, Error, etc for web server.
use MIME::QuotedPrint;
use strict;

use sql ();
require ssi;
require eprint::customer;
require eprint::customer_credit;
require eprint::obj_customer;
require eprint::address;

sub product_markup {
    my ($r, $log, $dbh, $variable) = @_;


	my $index;

## New Product Markup
	$variable->{new_product_categories} = $dbh->selectall_arrayref(q{
		SELECT * FROM categories ORDER by name 
	}, {Slice => {} } );

	map { 
		$_->{markup} = $dbh->selectrow_array(q{
			SELECT markup from product_markup WHERE customer = ? and category = ?
		}, undef, $index, $_->{id} );
	} @{ $variable->{new_product_categories} };
}


sub admin_customer_edit {
    my ($r, $log, $dbh, $variable) = @_;
    
    # Form field to db field mappings.
    my %fields = (
            rdbAccountActivation  =>  'AccountActivation',
            txtAccountNum         =>  'AccountNumber',
            txtCompanyName        =>  'Name',
            txtAddress1           =>  'Address1',
            txtAddress2           =>  'Address2',
            txtCity               =>  'City',
            ddmStateProvince      =>  'StateProvince',
            txtStateProvince      =>  'StateProvince',
            ddmCountry            =>  'Country',
            txtCountry            =>  'Country',
            txtPostalCode         =>  'PostalCode',
            txtPhone              =>  'Phone',
            txtExtension          =>  'Extension',
            txtFax                =>  'Fax',
            ShippingAddressIndex  =>  'ShippingAddressIndex',
            rdbLegalForm          =>  'LegalForm',
            txtLegalBusinessName  =>  'LegalBusinessName',
            txtBusinessType       =>  'BusinessType',
            BusinessStartDate     =>  'BusinessStartDate',
            txtPresidentOwner     =>  'PresidentOwner',
            ddmEmployees          =>  'Employees',
            ddmAnnualSales        =>  'AnnualSales',
            txtGSTNumber          =>  'TaxNumber1',
            txtPSTNumber          =>  'TaxNumber2',
            rdbGSTExempt          =>  'TaxExempt1',
            rdbPSTExempt          =>  'TaxExempt2',
            ddmPriceList          =>  'PriceList',
            ddmCountyTax          =>  'CountyTax',
            ddmSalesPerson        =>  'SalesPerson',
            ddmCSR        		  =>  'csr',
            txtBankBranch         =>  'BankBranch',
            txtBankName           =>  'BankName',
            txtBankAccountNo      =>  'BankAccountNumber',
            txtBankAccountManager =>  'BankAccountManager',
            txtBankPhone          =>  'BankPhone',
            txtBankFax            =>  'BankFax',
            txtBankEmail          =>  'BankEmail',
            rdbReseller           =>  'Reseller',
            rdbSupplier           =>  'Supplier',
            txtCustomGreeting     =>  'CustomGreeting',
            txtPricingLevel       =>  'Discount',
	    	ddmDivision		  	  =>  'division',
            txtNationalCredit     =>  'NationalCredit',
            txtMailingCredit      =>  'MailingCredit',
            txtOrderCredit        =>  'OrderCredit',
            txtNationalCreditDefault     =>  'NationalCreditDefault',
            txtMailingCreditDefault      =>  'MailingCreditDefault',
            txtOrderCreditDefault        =>  'OrderCreditDefault',
            chkOrderCreditCarry        =>  'OrderCreditCarry',
            txtNotificationEmail  =>  'NotificationEmail',
			linescreen				=> 'linescreen',
    );
    
    # Project/service pricing display flags.
    my %display_flag = (
            ysnpricingservice     =>  'PricingServices',
            ysnpricingprojectview =>  'PricingProjectView',
            ysnseparatestock      =>  'SeparateStock',
            ysnproductsonly       =>  'ProductsOnly',
            ysnpricingquotes      =>  'PricingQuotes',
    );

    my %shipping_fields = (
            txtShippingCompanyName    =>  'CompanyName',
            rdbShippingSalutation     =>  'Salutation',
            txtShippingFirstName      =>  'FirstName',
            txtShippingLastName       =>  'LastName',
            txtShippingAddress1       =>  'Address1',
            txtShippingAddress2       =>  'Address2',
            txtShippingCity           =>  'City',
            ddmShippingStateProvince  =>  'StateProvince',
            ddmShippingCountry        =>  'Country',
            txtShippingPostalCode     =>  'PostalCode',
            txtShippingPhone          =>  'Phone',
            txtShippingExtension      =>  'Extension',
            txtShippingFax            =>  'Fax',
            txtShippingEmail          =>  'Email',
			txtShippingCubicle		  =>  'Cubicle',
    );

    my %credit_fields = (
            txtTerms          =>  'Terms',
            txtCreditLimit    =>  'CreditLimit',
            rdbCreditHold     =>  'CreditHold',
            txtDownpayment    =>  'Downpayment',
    );

    my $index = $r->param('ddmCustomer');

    if ( $r->param('btnFunction') eq '<<' ) {
        $index = eprint::customer::get_prev( $log, $dbh, $index ) if $index;
        $index = scalar $dbh->selectrow_array(q{ 
                SELECT lngCustomerID 
                FROM tbl_Customer 
                ORDER BY lower(strCompanyName)
                DESC
                LIMIT 1
        }) unless $index;
    }
    elsif ( $r->param('btnFunction') eq '>>') {
        $index = eprint::customer::get_next( $log, $dbh, $index ) if $index;
        $index = scalar $dbh->selectrow_array(q{ 
            SELECT lngCustomerID 
            FROM tbl_Customer 
            ORDER BY lower(strCompanyName)
            LIMIT 1
        }) unless $index;
    } 
    elsif ( $r->param('btnFunction') eq 'Go' ) {
        if ( $r->param('txtSearchAccountNum') ne '' ) {
            $_ = "SELECT lngCustomerID from tbl_Customer WHERE strAccountNum = '".sql::escape($r->param('txtSearchAccountNum'))."'"; 
            ( $index ) = sql::sql_statement( $log, $dbh, $_ );
        }
    } 
    elsif ( $r->param('btnFunction') eq 'Save' ) {

my $ls = $r->param('linescreen');

print STDERR  "HAVE LINE SCREEN: $ls \n";

        my $customer = eprint::obj_customer->new($log, $dbh, $index);

        my ( $activation, $reseller, $supplier ) = $customer->get( 'AccountActivation', 'Reseller','Supplier' );
        if ( $activation ne $r->param('rdbAccountActivation') ) {
            my %info;
            my $email_template = misc::load_file($r, '/email/email_template.html');

            $_ = $r->param('rdbAccountActivation') eq 'Y' ? 'account_activated.html' : 'account_deactivated.html';
            $info{'ReplacementText'} = "<!--#include virtual=\"/email/content/$_\"-->";

            $info{'siteURL'} = "http://" . $r->hostname;
            $info{'SecureSiteURL'} = "https://" . $r->hostname;
            $info{'CustomerServiceEmail'} = configuration::get_value( $log, $dbh, 'CustomerServiceEmail' );
            $email_template = ssi::variable_substitution( $r, $log, $dbh, $email_template, \%info ); 

            $_ = "SELECT strEmail FROM tbl_Customer_Users WHERE lngCustomerID = '$index'";
            my @to = sql::sql_statement( $log, $dbh, $_ ) if $index;
            my %mail = (
                    SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
                    FROM    => configuration::get_value( $log, $dbh, 'AdministratorEmail'),
                    CC    	=> configuration::get_value( $log, $dbh, 'AdministratorEmail'),
                    TO      => join( ',', @to ),
                    SUBJECT => "Customer account status has changed!",
                    );
            misc::send_email_with_attachment($r, $log, \%mail, ( '', encode_qp($email_template), 'text/html', 'quoted-printable' ) );
        }
        if ( $reseller ne $r->param('rdbReseller') ) {
            my %info;
            my $email_template = misc::load_file($r, '/email/email_template.html');
            $info{'siteURL'} = "http://" . $r->hostname;
            $info{'SecureSiteURL'} = "https://" . $r->hostname;
            $info{'CustomerServiceEmail'} = configuration::get_value( $log, $dbh, 'CustomerServiceEmail' );
            $_ = "SELECT strEmail FROM tbl_Customer_Users WHERE lngCustomerID = '$index'";
            my @to = sql::sql_statement( $log, $dbh, $_ ) if $index;

            $_ = $r->param('rdbReseller') eq 'Y' ? 'customer_account_reseller.html' : 'customer_account_non_reseller.html';
            $info{'ReplacementText'} = "<!--#include virtual=\"/email/content/$_\"-->";
            $email_template = ssi::variable_substitution( $r, $log, $dbh, $email_template, \%info ); 
            my %mail = (
                    SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
                    FROM    => configuration::get_value( $log, $dbh, 'AdministratorEmail'),
                    TO      => join( ',', @to ),
                    SUBJECT => "Customer account status has changed!",
                    );
            misc::send_email_with_attachment($r, $log, \%mail, ( '', encode_qp($email_template), 'text/html', 'quoted-printable' ) );
        }
        if ( $supplier ne $r->param('rdbSupplier') ) {
            my %info;
            my $email_template = misc::load_file($r, '/email/email_template.html');
            $info{'CustomerServiceEmail'} = configuration::get_value( $log, $dbh, 'CustomerServiceEmail' );
            $_ = "SELECT strEmail FROM tbl_Customer_Users WHERE lngCustomerID = '$index'";
            my @to = sql::sql_statement( $log, $dbh, $_ ) if $index;

            $_ = $r->param('rdbSupplier') eq 'Y' ? 'customer_account_supplier.html' : 'customer_account_non_supplier.html';
            $info{'ReplacementText'} = "<!--#include virtual=\"/email/content/$_\"-->";
            $email_template = ssi::variable_substitution( $r, $log, $dbh, $email_template, \%info );
            my %mail = (
                    SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
                    FROM    => configuration::get_value( $log, $dbh, 'AdministratorEmail'),
                    TO      => join( ',', @to ),
                    SUBJECT => "Customer account status has changed!",
                    );
            misc::send_email_with_attachment($r, $log, \%mail, ( '', encode_qp($email_template), 'text/html', 'quoted-printable' ) );
        }

        my %params;
        foreach my $field ( keys %fields ) {
			print STDERR "CHECK FILED: $field = " . $r->param($field) . "\n";
            $params{$fields{$field}} = $r->param($field) if defined $r->param($field);
        }

        
        # Set all display flags.
        $params{ $display_flag{$_} } = $r->param($_) ? 1 : 0 for keys %display_flag;
        
        if ( $r->param('txtStartYear') ) {
            $params{'BusinessStartDate'} = $r->param('txtStartYear') . '-' . $r->param('ddmStartMonth') . '-01';
        }
	
		# if check box is not checked, then update db to be false.
		$params{OrderCreditCarry} = 0 unless $params{OrderCreditCarry};

        $customer->set( \%params );
        $index = $customer->{index};

# Customer Categories
# I was trying to do this the hard way.  Then it occurred to me: Just delete them all from the table, and add back in the ones we want.  
        $_ = "SELECT lngIndex FROM tbl_Marketing_Categories";
        my @customercategories = sql::sql_statement( $log, $dbh, $_ );

        $_ = "DELETE FROM tbl_Customers_in_Categories WHERE lngCustomerID = '$index'";
        sql::sql_statement( $log, $dbh, $_ ) if $index;
# add them back in 
        my $sth = $dbh->prepare( q{INSERT INTO tbl_Customers_in_Categories (lngCategoryID,lngCustomerID) VALUES ( ?, ? )} );
        foreach my $cat ( $r->param('selectCustomerCategories') ) {
            if ( grep { $_ eq $cat } @customercategories ) {
                $sth->execute( $cat, $index ) or $log->error( DBI->errstr );
            }
        }


		# Mark the Services that Will be disabled to the Customer.
		$dbh->do(q{DELETE FROM customer_service_type WHERE customer= ?},undef,$index);

		my $sth = $dbh->prepare( q{INSERT INTO customer_service_type VALUES ( ?, ? )} );

		foreach my $st ( $r->param('selectCustomerServiceType') ) {
			$sth->execute( $index, $st ) or $log->error( DBI->errstr );
		}

		my @ids = ($r->param('ShippingID'),'New');
		map {
        
			my %params;
        	foreach my $field ( keys %shipping_fields ) {
				my $f = $field."-$_";

				print STDERR "GE FIELD F: $f = " . $r->param($f) . " \n";

            	$params{$shipping_fields{$field}} = $r->param($f) if defined $r->param($f);
        	}


        	$customer->save_shipping( $_, \%params )
				if $r->param("txtShippingCompanyName-$_"); 

		} @ids;


        eprint::customer::save_tradereferences( $r, $log, $dbh, $index );

        my $customer_credit = eprint::customer_credit->new( $log, $dbh, $index );
        my %params;
        foreach my $field ( keys %credit_fields ) {
            $params{$credit_fields{$field}} = $r->param($field) if defined $r->param($field);
        }
        $customer_credit->set( \%params );

		$dbh->do(q{ DELETE from product_markup WHERE customer = ? }, undef, $index );
		map { 
			if ( $_ =~ /txtMarkup-(\d*)/ ){
				print STDERR  "HAVE MARKUP $1 \n";
				$dbh->do(q{INSERT INTO product_markup ( customer, category, markup) VALUES ( ?, ?, ? ) },
					undef, $index, $1, $r->param($_) ) if $r->param($_);
			}
		} $r->param();
	
		
    }
	if ( $r->param('deleteshipaddress') ) {
			$dbh->do(qq{ DELETE FROM customer_ship_address WHERE shipid = } . $r->param('deleteship'));
	}

    # we no longer default to displaying the first record.  The user must select one.,
    if ( $index ne '' ) {
        my $customer = new eprint::obj_customer( $log, $dbh, $index );
        if ( $r->param('btnFunction') eq 'Delete' ) {
            my $new_id = $customer->next();
            $customer->delete();
	    if ( $new_id ) {
            	$customer = new eprint::obj_customer( $log, $dbh, $new_id );
           	$index = $new_id;
	    }
        }

        @$variable{ keys %fields } = ssi::htmlize( $customer->get( @fields{ keys %fields } ) );
        my @tmp = ssi::htmlize( $customer->get( @fields{ keys %fields } ) );

        # Set the checkboxes of any true flags.
        for my $flag (keys %display_flag) {
            $variable->{$flag} = $customer->get( $display_flag{$flag} ) ? 'checked="checked"' : '';
        }
        
    
        $$variable{'rdbReseller'.$$variable{'rdbReseller'}} = 'CHECKED';
        $$variable{'rdbSupplier'.$$variable{'rdbSupplier'}} = 'CHECKED';
        $$variable{'rdbPricingProjectView'.$$variable{'rdbPricingProjectView'}} = 'CHECKED';
        $$variable{'rdbSeparateStock'.$$variable{'rdbSeparateStock'}} = 'CHECKED';
        $$variable{'rdbPricingQuotes'.$$variable{'rdbPricingQuotes'}} = 'CHECKED';

        $$variable{'rdbLegalForm'.$$variable{'rdbLegalForm'}} = 'CHECKED';
        $$variable{'rdbPSTExempt'.$$variable{'rdbPSTExempt'}} = 'CHECKED';
        $$variable{'rdbGSTExempt'.$$variable{'rdbGSTExempt'}} = 'CHECKED';
        
        $$variable{'rdbAccountActivation'.$$variable{'rdbAccountActivation'}} = 'CHECKED';

        $$variable{'txtPricingLevel'} = sprintf ( "%.0f", $$variable{'txtPricingLevel'} ) . "%";
        $$variable{'txtDownpayment'} = sprintf ( "%.0f", $$variable{'txtDownpayment'} ) . "%";

        eprint::customer::load_tradereferences( $r, $log, $dbh, $index, $variable );

        $$variable{'SHIPPING_ADDRESSES'} = $customer->shipping_hash();

use Data::Dumper;
print STDERR "HAVE SHIPPING", Dumper($$variable{'SHIPPING_ADDRESSES'});

        map { $_->{'rdbSalutation'. $_->{strsalutation}} = 'CHECKED'; 
    		$_->{'ddmShippingStateProvince'} = ssi::return_states_and_provinces($_->{'strstateprovince'});
    		$_->{'ddmShippingCountry'}       = ssi::return_countries($_->{'strcountry'});
		} @{$variable->{'SHIPPING_ADDRESSES'}};

        my $customer_credit = eprint::customer_credit->new( $log, $dbh, $index );
        @$variable{ keys %credit_fields } = ssi::htmlize( $customer_credit->get( @credit_fields{ keys %credit_fields } ) );

    }

    $_ = "SELECT lngWarehouseID, strDescription FROM tbl_Warehouse ORDER BY lngWarehouseID";
    $$variable{'ddmWarehouse'} = ssi::fill_drop_down( $log, $dbh, $_, $$variable{'ddmWarehouse'} );

print STDERR "GET DIVISION: $variable->{ddmDivision} \n";

    $_ = "SELECT id, name FROM division ORDER BY name";
    $$variable{'ddmDivision'} = ssi::fill_drop_down( $log, $dbh, $_, $$variable{'ddmDivision'} );
print STDERR "HAVE DIVISION: $variable->{ddmDivision} \n";

    # Get Customer Category Inforamation - get all categories, and highlight the ones this customer is in.
    $_ = 'SELECT lngIndex, strName FROM tbl_Marketing_Categories';
    my @available_categories = sql::sql_statement( $log, $dbh, $_);
  
    # get categories this customer is in we do it this way to limit databse transaction to 2.
    my @customers_categories = @{ $dbh->selectcol_arrayref(q{
        SELECT lngCategoryID 
        FROM tbl_Customers_in_Categories 
        WHERE lngCustomerID = ?
    }, undef, $index) } if $index;
    
    $$variable{'selectCustomerCategories'} = ssi::make_select( \@available_categories, \@customers_categories );


	if ( $index ) {
		# Create multi-select For Serivces that can be disabled for
		# individual accounts.
		my $cust_service_types = $dbh->selectcol_arrayref(q{
			SELECT service_type 
			FROM customer_service_type 
			WHERE customer = ?
		}, undef, $index);

		my $service_types = $dbh->selectall_arrayref(q{
			SELECT lngindex, strname
			FROM tbl_service_types 
			ORDER BY strname
		});
		my @servicetypes  = map {$_->[0], $_->[1]} @{$service_types};

		$$variable{'selectCustomerServiceType'} = ssi::make_select( \@servicetypes, $cust_service_types );
	}

    @$variable{'txtStartYear','ddmStartMonth'} = $$variable{'BusinessStartDate'} =~ /^(\d+)-(\d+)-(\d+)/;
    $$variable{'ddmStartMonth'} = ssi::getmonths( $$variable{'ddmStartMonth'} );

    $_ = "SELECT lngUserID, strLastName || ', ' || strFirstName 
			FROM tbl_Customer_Users WHERE (chrType = 'E' or chrType = 'A') OR lngCustomerId IN (
					SELECT lngCustomerId FROM tbl_customer where ysnReseller = 'Y') ORDER By strLastname ";
    $$variable{'ddmSalesPeople'} = ssi::fill_drop_down( $log, $dbh, $_, $$variable{'ddmSalesPerson'} );

    $_ = "SELECT lngUserID, strLastName || ', ' || strFirstName 
			FROM tbl_Customer_Users WHERE (chrType = 'E' or chrType = 'A') OR lngCustomerId IN (
					SELECT lngCustomerId FROM tbl_customer where ysnReseller = 'Y') ORDER By strLastname ";
    $$variable{'ddmCSR'} = ssi::fill_drop_down( $log, $dbh, $_, $$variable{'ddmCSR'} );
    

    $$variable{'ddmEmployees'} = ssi::getemployee_numbers( $r, $log, $dbh, $$variable{'ddmEmployees'} );
    $$variable{'ddmAnnualSales'} = ssi::getannual_sales( $r, $log, $dbh, $$variable{'ddmAnnualSales'} );

    $$variable{'ddmStateProvince'} = ssi::return_states_and_provinces($$variable{'ddmStateProvince'});
    $$variable{'ddmCountry'} = ssi::return_countries($$variable{'ddmCountry'});

    $$variable{'rdbCreditHold'.$$variable{'rdbCreditHold'}} = 'CHECKED';
    $$variable{'rdbTerms'.$$variable{'rdbTerms'}} = 'CHECKED';

    $_ = "SELECT lngCustomerID, strCompanyName FROM tbl_Customer ORDER BY lower(strCompanyName)";
    $$variable{'ddmCustomer'} = ssi::fill_drop_down( $log, $dbh, $_, $index );

    $_ = "SELECT id, currency || ' - ' || name FROM pricelist ORDER BY currency, name";
    $$variable{'ddmPriceList'} = ssi::fill_drop_down( $log, $dbh, $_, $$variable{'ddmPriceList'} );

    $_ = "SELECT id, name FROM county_taxes ORDER BY name";
    $$variable{'ddmCountyTax'} = ssi::fill_drop_down( $log, $dbh, $_, $$variable{'ddmCountyTax'} );

    my $total = 0;
    my $payments = 0;
    if ( $index ) {
        $_ = "SELECT SUM(curTotalSale) FROM tbl_Orders WHERE lngCustomerID='$index'\n".
            "AND (strStatus='Pending Deposit' OR strStatus='In Production' OR strStatus='Complete' OR strStatus='Paid' )";
        ( $total ) = sql::sql_statement( $log, $dbh, $_ );

        $_ = "SELECT SUM(curAmount) FROM tbl_Payments WHERE lngCustomerIndex='$index'";
        ( $payments ) = sql::sql_statement( $log, $dbh, $_ );
    }

    $$variable{'CreditBalance'} = '$ '.sprintf( "%.2f", ( $total - $payments ) );
    if ( $$variable{'txtCreditLimit'} < ($total - $payments) ) {
        $$variable{'CreditRemaining'} = '$ 0.00';
    } else {
        $$variable{'CreditRemaining'} = '$ '.sprintf( '%.2f', ( $$variable{'txtCreditLimit'} - ($total - $payments) ) );
    }
	
	$variable->{__FillInForm}{chkOrderCreditCarry} = $variable->{chkOrderCreditCarry};
	$variable->{__FillInForm}{linescreen} = $variable->{linescreen};
print STDERR "HAVE LINE SCRREN TO FILL: $variable->{linescreen} \n";

    $$variable{'CustomerIndex'} = $index;


## Product Markup
	$variable->{product_categories} = $dbh->selectall_arrayref(q{
		SELECT * FROM product.category ORDER by name 
	}, {Slice => {} } );

	map { 
		$_->{markup} = $dbh->selectrow_array(q{
			SELECT markup from product_markup WHERE customer = ? and category = ?
		}, undef, $index, $_->{id} );
	} @{ $variable->{product_categories} };


## New Product Markup
	$variable->{new_product_categories} = $dbh->selectall_arrayref(q{
		SELECT * FROM categories ORDER by name 
	}, {Slice => {} } );

	map { 
		$_->{markup} = $dbh->selectrow_array(q{
			SELECT markup from product_markup WHERE customer = ? and category = ?
		}, undef, $index, $_->{id} );
	} @{ $variable->{new_product_categories} };

    return OK;
}

1;
