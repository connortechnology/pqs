package eprint::admin_clerical;
use strict;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY); # Offers OK, Error, etc for web server.
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Request::Common;

use sql ();
require configuration;

sub misc_settings_edit {
    my ($r, $log, $dbh, $variable) = @_;

    # Save the setting if the user has posted them
    save_settings($r, $log, $dbh) if $r->param('btnFunction') eq 'Save';

    $$variable{'ddmProofShippingOverride'} = ssi::fill_drop_down( $log, $dbh,
        "SELECT lngindex, strname FROM tbl_ship_via ORDER BY lngindex"
        , configuration::get_value( $log, $dbh, 'ProofShippingOverride' ) );
    $$variable{'ddmSampleShippingOverride'} = ssi::fill_drop_down( $log, $dbh,
        "SELECT lngindex, strname FROM tbl_ship_via ORDER BY lngindex"
        , configuration::get_value( $log, $dbh, 'SampleShippingOverride' ) );
    $$variable{'ddmProjectShippingOverride'} = ssi::fill_drop_down( $log, $dbh,
        "SELECT lngindex, strname FROM tbl_ship_via ORDER BY lngindex"
        , configuration::get_value( $log, $dbh, 'ProjectShippingOverride' ) );
    $$variable{'txtSSRMsg'} = configuration::get_value( $log, $dbh, 'SuppliedServiceRemovalMessage' );
    $$variable{'txtStdErrorMsg'} = configuration::get_value( $log, $dbh, 'StandardErrorMessage' );
    $$variable{'txtMailServer'} = configuration::get_value( $log, $dbh, 'Mail Server' );
    $$variable{'txtIdleTime'} = configuration::get_value( $log, $dbh, 'idletime' );
    $$variable{'txtCompanyName'} = configuration::get_value( $log, $dbh, 'companyname' );
    $$variable{'txtDomain'} = configuration::get_value( $log, $dbh, 'domain' );
    $$variable{'txtSiteURL'} = "http://" . $r->hostname;
    $$variable{'txtSecureSiteURL'} = "https://" . $r->hostname;
    $$variable{'txtCookieDomain'} = configuration::get_value( $log, $dbh, 'cookiedomain' );
    $$variable{'txtPublicURIs'} = configuration::get_value( $log, $dbh, 'public_URIs' );
    $$variable{'txtExportAccountService'} = configuration::get_value( $log, $dbh, 'ServiceExportAccount' );
    $$variable{'txtExportAccountMaterial'} = configuration::get_value( $log, $dbh, 'MaterialExportAccount' );
    $$variable{'txtExportAccountStock'} = configuration::get_value( $log, $dbh, 'StockExportAccount' );

    $$variable{'rdbNewCustomerAccountActivation'.configuration::get_value( $log, $dbh, 'NewCustomerAccountActivation')} = 'CHECKED';
    $$variable{'rdbFirstNewUserAccountActivation'.configuration::get_value( $log, $dbh, 'NewFirstUserAccountActivation')} = 'CHECKED';
    $$variable{'rdbNonFirstNewUserAccountActivation'.configuration::get_value( $log, $dbh, 'NewNonFirstUserAccountActivation')} = 'CHECKED';
    $$variable{'rdbDefaultProjectCreateMode'.configuration::get_value( $log, $dbh, 'DefaultProjectCreateMode')} = 'CHECKED';
    $$variable{'txtDefaultDownpayment'} = configuration::get_value( $log, $dbh, 'DefaultDownpayment' );
    $$variable{'OrderCalendarProfile'} = configuration::get_value( $log, $dbh, 'OrderCalendarProfile' );
    $$variable{'OrderLeadTime'} = configuration::get_value( $log, $dbh, 'OrderLeadTime' );

    $$variable{'ddmDefaultUSPricelist'} = ssi::fill_drop_down( $log, $dbh, q{
        SELECT id, currency || ' - ' || name 
        FROM pricelist
        WHERE currency = 'USD'
        ORDER BY currency, name
    }, configuration::get_value( $log, $dbh, 'DefaultUSPricelist' ) );
    $$variable{'ddmDefaultCAPricelist'} = ssi::fill_drop_down( $log, $dbh, q{
        SELECT id, currency || ' - ' || name 
        FROM pricelist
        WHERE currency = 'CAD'
        ORDER BY currency, name
    }, configuration::get_value( $log, $dbh, 'DefaultCAPricelist' ) );
    $$variable{'ddmDefaultOtherPricelist'} = ssi::fill_drop_down( $log, $dbh, q{
        SELECT id, currency || ' - ' || name 
        FROM pricelist
        ORDER BY currency, name
    }, configuration::get_value( $log, $dbh, 'DefaultOtherPricelist' ) );

#     $$variable{'rdbSendInvoiceOnProjectCompletion'.configuration::get_value( $log, $dbh, 'SendInvoiceOnProjectCompletion')} = 'CHECKED';

    # PRESS TYPES
    #
    $variable->{press_types} = $dbh->selectall_arrayref(q{
        SELECT e.strid                                              AS id, 
               e.strname                                            AS name, 
               (CASE WHEN strid = ?::text THEN true ELSE false END) AS selected
        FROM tbl_equipment_type e, equipment_type_service_type m 
        WHERE m.service_type = 68 -- Printing
          AND e.lngindex = m.equipment_type
    }, { Slice => {} }, configuration::get_value($log, $dbh, 'default_press_type'));

    # ALLOWED SERVICES
    #
    # The services that are allowed to be perfomed on predefined project may
    # be limited by the user.
    my @services = split /,/, 
        configuration::get_value($log, $dbh, 'predefined_allowed_services');
    my %allowed;
    @allowed{@services} = (1) x scalar @services;
    
    # Get a list of services by category.
    my $sth = $dbh->prepare(q{
        SELECT c.strname AS category, s.lngindex AS id, s.strname AS name 
        FROM tbl_service_types s, tbl_service_categories c 
        WHERE s.strcategory = c.strid 
          AND s.strid <> 'Discount' 
          AND ysnviewvisible = 'Y'
          AND strtype <> 'bind'
        ORDER BY c.lngsort, s.lngsort
    });
    $sth->execute;
    my ($category, $id, $name);
    $sth->bind_columns(\$category, \$id, \$name);

    my @categories;
    while ($sth->fetch) {
        push @categories, { name => $category, services => [] }
            if !@categories || $categories[-1]{name} ne $category;

        push @{ $categories[-1]{services} }, 
            { id => $id, name => $name, selected => $allowed{$id} };
    }
    $variable->{categories} = \@categories;

    return;
}

sub save_settings {
    my ($r, $log, $dbh) = @_;

    # extra processing on public_URis, includes stripping extra whitespace, and escaping \\s
    my @public_uris = split( ',', $r->param('txtPublicURIs') );
    for ( my $index = 0; $index < @public_uris; $index += 1 ) {
        $public_uris[$index] =~ s/^\s*(.*?)\s*$/$1/;
        $public_uris[$index] =~ s/\\/\\\\/g;
    }
    my $uri_list = join( ',', @public_uris );

    configuration::save_entry($log, $dbh, 'public_URIs' => $uri_list);

    my %fields = (
        'companyname'   => 'txtCompanyName',
        'domain'        => 'txtDomain',
        'cookiedomain'  => 'txtCookieDomain',
        'Mail Server'   => 'txtMailServer',

        'siteURL'           => 'txtSiteURL',
        'SecureSiteURL'     => 'txtSecureSiteURL',
        
        'DefaultDownpayment' => 'txtDefaultDownpayment',
        'idletime'           => 'txtIdleTime',
        'NewCustomerAccountActivation'     => 'rdbNewCustomerAccountActivation',
        'NewFirstUserAccountActivation'    => 'rdbFirstNewUserAccountActivation',
        'NewNonFirstUserAccountActivation' => 'rdbNonFirstNewUserAccountActivation',
        'DefaultUSPricelist'    => 'ddmDefaultUSPricelist',
        'DefaultCAPricelist'    => 'ddmDefaultCAPricelist',
        'DefaultOtherPricelist' => 'ddmDefaultOtherPricelist',

        'default_press_type' => 'txtDefaultPressType',
        'OrderLeadTime'      => 'OrderLeadTime',
        'StandardErrorMessage'          => 'txtStdErrorMsg',
        'SuppliedServiceRemovalMessage' => 'txtSSRMsg',
        'ProofShippingOverride'   => 'ddmProofShippingOverride',
        'SampleShippingOverride'  => 'ddmSampleShippingOverride',
        'ProjectShippingOverride' => 'ddmProjectShippingOverride',
        
        'ServiceExportAccount'  => 'txtExportAccountService',
        'MaterialExportAccount' => 'txtExportAccountMaterial',
        'StockExportAccount'    => 'txtExportAccountStock',
        'OrderCalendarProfile'  => 'OrderCalendarProfile',

        'SendInvoiceOnProjectCompletion' => 'rdbSendInvoiceOnProjectCompletion',
    );
    while (my ($name, $param) = each %fields) {
        configuration::save_entry($log, $dbh, $name => $r->param($param));
    }


    # We need to serialise the list to save it down.
    if (my @services = $r->param('predefined_allowed_services')) {
        configuration::save_entry($log, $dbh, 
            'predefined_allowed_services' => join(',', @services)
        );
    }

    return 1;
}

sub county_tax_tables {
    my ( $r, $log, $dbh, $variable ) = @_;

    if ( $r->param('btnFunction') eq 'Submit' ) {
        $_ = 'SELECT id from county_taxes';
        my $sth = $dbh->prepare( q{
                      UPDATE county_taxes SET amount = ? WHERE id = ?} );
        foreach my $state ( sql::sql_statement( $log, $dbh, $_ ) ) {
            $sth->execute(    ($r->param("tax-$state") || 0),
                            $state ) || $log->error( $dbh->errstr );
		}
	}

	my $tax = $dbh->selectall_hashref(q{
     	SELECT * FROM county_taxes ORDER BY name
	},'name',{});

	map { push @{$variable->{TAXES}}, $tax->{$_} } sort keys %{$tax};

    return OK;
}    



sub tax_tables {
    my ( $r, $log, $dbh, $variable ) = @_;

    if ( $r->param('btnFunction') eq 'Submit' ) {
        $_ = 'SELECT lngStateID from tbl_Taxes';
        my $sth = $dbh->prepare( q{UPDATE tbl_Taxes SET dblStatePercent = ?, dblFederalPercent = ?, dblHarmonisedPercent = ? WHERE lngStateID = ?} );
        foreach my $state ( sql::sql_statement( $log, $dbh, $_ ) ) {
            $sth->execute(    ($r->param("txtSST$state") eq '' ? undef : $r->param("txtSST$state")),
                            ($r->param("txtFST$state") eq '' ? undef : $r->param("txtFST$state")),
                            ($r->param("txtHST$state") eq '' ? undef : $r->param("txtHST$state")),
                            $state ) || $log->error( $dbh->errstr );
        }
    }

    $_ = 'SELECT txtStateName, lngStateID, dblFederalPercent, dblStatePercent, dblHarmonisedPercent '.
        'FROM tbl_Taxes ORDER BY txtStateName';
    @{$$variable{'TAXES'}} = sql::sql_statement( $log, $dbh, $_ );

    return OK;
}

sub tax_stewardship {
    my ( $r, $log, $dbh, $variable ) = @_;

    if ( $r->param('btnFunction') eq 'Submit' ) {
        $_ = 'SELECT id from stax';

        my $sth = $dbh->prepare( q{UPDATE stax SET 
				ABrate = ?, BCrate = ?, MBrate = ?, 
				NBrate = ?, NFrate = ?, NTrate = ?, 
				NSrate = ?, NUrate = ?, ONrate = ?, 
				PErate = ?, QCrate = ?, SKrate = ?, 
				YTrate = ?
		WHERE id = ?} );

        foreach my $id ( sql::sql_statement( $log, $dbh, $_ ) ) {
            $sth->execute(    ($r->param("AB-$id") eq '' ? 0 : $r->param("AB-$id")),
                              ($r->param("BC-$id") eq '' ? 0 : $r->param("BC-$id")),
                              ($r->param("MB-$id") eq '' ? 0 : $r->param("MB-$id")),
                              ($r->param("NB-$id") eq '' ? 0 : $r->param("NB-$id")),
                              ($r->param("NF-$id") eq '' ? 0 : $r->param("NF-$id")),
                              ($r->param("NT-$id") eq '' ? 0 : $r->param("NT-$id")),
                              ($r->param("NS-$id") eq '' ? 0 : $r->param("NS-$id")),
                              ($r->param("NU-$id") eq '' ? 0 : $r->param("NU-$id")),
                              ($r->param("ON-$id") eq '' ? 0 : $r->param("ON-$id")),
                              ($r->param("PE-$id") eq '' ? 0 : $r->param("PE-$id")),
                              ($r->param("QC-$id") eq '' ? 0 : $r->param("QC-$id")),
                              ($r->param("SK-$id") eq '' ? 0 : $r->param("SK-$id")),
                              ($r->param("YT-$id") eq '' ? 0 : $r->param("YT-$id")),
                            $id 
			) || $log->error( $dbh->errstr );
        }
    }



    $$variable{'TAXES'} = $dbh->selectall_arrayref(q{
    	SELECT * FROM stax ORDER BY name
	}, {Slice => {}}); 

use Data::Dumper;
print STDERR "TAXES: ", Dumper($variable->{TAX});
    return OK;
}


sub currency_edit {
    my ( $r, $log, $dbh, $variable ) = @_;
    my ( $temp );

    if ( $r->param('btnFunction') eq 'Save' ) {
        configuration::save_entry( $log, $dbh, 'DefaultCurrency', $r->param('ddmCurrency') );

        if ( $r->param("name") ) {
            sql::insert( $log, $dbh, 'currency',
                code   => $r->param("code"),
                name   => $r->param("name"),
                symbol => $r->param("symbol"),
            );
        }

        my $currencies = $dbh->selectcol_arrayref(q{SELECT code FROM currency});
        
        foreach my $currency ( @{ $currencies } ) {
            next unless $r->param("name$currency");

            sql::update( $log, $dbh, 'currency', "code = '$currency'",
                code   => $r->param("code$currency"),
                name   => $r->param("name$currency"),
                symbol => $r->param("symbol$currency"),
            );
        }
    } elsif ( $r->param('btnFunction') eq 'Delete' ) {
        $dbh->do(q{ DELETE FROM currency WHERE code = ? }, undef, $_)
            for $r->param('delete');
    }
   
    my $default = configuration::get_value( $log, $dbh, 'DefaultCurrency' );

    $temp = 'SELECT code, name FROM currency';
    $$variable{'ddmCurrency'} = ssi::fill_drop_down( $log, $dbh, $temp, $default );

    $variable->{currency} = $dbh->selectall_arrayref(q{
        SELECT name, code, symbol FROM currency
    }, { Slice => {} });

    return OK;
}

sub notifications_edit {
    my ( $r, $log, $dbh, $variable ) = @_;

    if ( $r->param('btnFunction') eq 'Save' ) {
        configuration::save_entry( $log, $dbh, 'AdministratorEmail', $r->param('txtAdministratorEmail') );
        configuration::save_entry( $log, $dbh, 'FileUploadEmail', $r->param('txtFileUploadEmail'));
        configuration::save_entry( $log, $dbh, 'OrderingEmail', $r->param('txtOrderingEmail') );
        configuration::save_entry( $log, $dbh, 'QuotingEmail', $r->param('txtQuotingEmail') );
        configuration::save_entry( $log, $dbh, 'UserRegistrationEmail', $r->param('txtUserRegistrationEmail') );
        configuration::save_entry( $log, $dbh, 'CreditApplicationEmail', $r->param('txtCreditApplicationEmail') );
        configuration::save_entry( $log, $dbh, 'ResellerApplicationEmail', $r->param('txtResellerApplicationEmail') );
        configuration::save_entry( $log, $dbh, 'HelpdeskEmail', $r->param('txtHelpdeskEmail') );
        configuration::save_entry( $log, $dbh, 'RMAEmail', $r->param('txtRMAEmail') );
        configuration::save_entry( $log, $dbh, 'AccountingEmail', $r->param('txtAccountingEmail') );
        my $projectCompleteEmail = $r->param('txtProjectCompletionEmail') ? $r->param('txtProjectCompletionEmail') : "'Accounting' <accounting@".$r->hostname.">";
        configuration::save_entry( $log, $dbh, 'ProjectCompletionEmail', $projectCompleteEmail);
        configuration::save_entry( $log, $dbh, 'ProductionChangeEmail', $r->param('txtProductionChanges'));
        configuration::save_entry( $log, $dbh, 'ProductionChangeEmail', $r->param('txtProductionChanges'));
        configuration::save_entry( $log, $dbh, 'InventoryReorder', $r->param('InventoryReorder'));
    }

    #display
    $$variable{'txtAdministratorEmail'} = configuration::get_value( $log, $dbh, 'AdministratorEmail' );
    $$variable{'txtOrderingEmail'} = configuration::get_value( $log, $dbh, 'OrderingEmail');    
    $$variable{'txtFileUploadEmail'} = configuration::get_value( $log, $dbh, 'FileUploadEmail');    
    $$variable{'txtQuotingEmail'} = configuration::get_value( $log, $dbh, 'QuotingEmail');    
    $$variable{'txtUserRegistrationEmail'} = configuration::get_value( $log, $dbh, 'UserRegistrationEmail');    
    $$variable{'txtResellerApplicationEmail'} = configuration::get_value( $log, $dbh, 'ResellerApplicationEmail');    
    $$variable{'txtCreditApplicationEmail'} = configuration::get_value( $log, $dbh, 'CreditApplicationEmail');    
    $$variable{'txtHelpdeskEmail'} = configuration::get_value( $log, $dbh, 'HelpdeskEmail');    
    $$variable{'txtRMAEmail'} = configuration::get_value( $log, $dbh, 'RMAEmail');    
    $$variable{'txtAccountingEmail'} = configuration::get_value( $log, $dbh, 'AccountingEmail');    
    $$variable{'txtProjectCompletionEmail'} = configuration::get_value( $log, $dbh, 'ProjectCompletionEmail');    
    $$variable{'txtProductionChanges'} = configuration::get_value( $log, $dbh, 'ProductionChangeEmail');    
    $$variable{'InventoryReorder'} = configuration::get_value( $log, $dbh, 'InventoryReorder');    
}

sub payment_options_edit {
    my ( $r, $log, $dbh, $variable ) = @_;
    my $temp;
    my $id = $r->param('ddmPaymentOption');

    if ( $r->param('btnFunction') eq '<<' ) {
        $id = misc::nav_get_previous( $r, $log, $dbh, $id, 'strPaymentOption', 'tbl_Payment_Options','','strPaymentOption' );
    } elsif ( $r->param('btnFunction') eq '>>' ) {
        $id = misc::nav_get_next( $r, $log, $dbh, $id, 'strPaymentOption', 'tbl_Payment_Options' ,'','strPaymentOption');
    } elsif ( $r->param('btnFunction') eq 'Delete' ) {
        $temp = "DELETE FROM tbl_Payment_Options WHERE strPaymentOption='$id'";
        sql::sql_statement( $log, $dbh, $temp);
        $id = misc::nav_get_next( $r, $log, $dbh, $id, 'strPaymentOption', 'tbl_Payment_Options' ,'','strPaymentOption');
    } elsif ( $r->param('btnFunction') eq 'Save' ) {
        if ( $id eq '' ) {
            # add
            sql::insert( $log, $dbh, 'tbl_Payment_Options', (
                'strPaymentOption', $r->param('txtPaymentOption') ) );
            $id = $r->param('txtPaymentOption');
        } else {
            #save
            $temp = "UPDATE tbl_Payment_Options SET strPaymentOption='" . $r->param('txtPaymentOption') . "' ".
                    "WHERE strPaymentOption='$id'";
            sql::sql_statement( $log, $dbh, $temp);
            $id = $r->param('txtPaymentOption');
        }
    }
    
    my $temp = "SELECT strPaymentOption,strPaymentOption FROM tbl_Payment_Options ORDER BY strPaymentOption";
    $$variable{'ddmPaymentOption'} = ssi::fill_drop_down( $log, $dbh, $temp, $id, 25 );
    $$variable{'txtPaymentOption'} = $id;

    return OK;
}

sub shipping_options_edit {
    my ( $r, $log, $dbh, $variable ) = @_;
    my $temp;
    my $id = $r->param('ddmShippingOption');

    if ( $r->param('btnFunction') eq '<<' ) {
        $id = misc::nav_get_previous( $r, $log, $dbh, $id, 'lngIndex', 'tbl_Ship_Via','','strName' );
    } elsif ( $r->param('btnFunction') eq '>>' ) {
        $id = misc::nav_get_next( $r, $log, $dbh, $id, 'lngIndex', 'tbl_Ship_Via' ,'','strName');
    } elsif ( $r->param('btnFunction') eq 'Delete' ) {
        $temp = "DELETE FROM tbl_Ship_Via WHERE lngIndex='$id'";
        sql::sql_statement( $log, $dbh, $temp);
        $id = misc::nav_get_next( $r, $log, $dbh, $id, 'lngIndex', 'tbl_Ship_Via' ,'','strName');
    } elsif ( $r->param('btnFunction') eq 'Save' ) {
        if ( $id eq '' ) {
            if ( $r->param('txtShipVia') ne '' ) {
                # add
                sql::insert( $log, $dbh, 'tbl_Ship_Via', 'strName', $r->param('txtShipVia') );
                $temp = "SELECT MAX(lngIndex) FROM tbl_Ship_Via WHERE strName = '".$r->param('txtShipVia')."'";
                ( $id ) = sql::sql_statement( $log, $dbh, $temp);
            }
        } else { #save
            sql::update( $log, $dbh, 'tbl_Ship_Via', "lngIndex='$id'", 'strName', $r->param('txtShipVia') );
        }
        configuration::save_entry( $log, $dbh, 'shipping_method', $r->param('ddmShippingMethod') );
        configuration::save_entry( $log, $dbh, 'shipping_rate', $r->param('txtShippingRate') );
        configuration::save_entry( $log, $dbh, 'shipping_gst_exempt', $r->param('rdbGSTExempt') );
        configuration::save_entry( $log, $dbh, 'shipping_pst_exempt', $r->param('rdbPSTExempt') );
    }

    my $temp = "SELECT lngIndex,strName FROM tbl_Ship_Via ORDER BY strName";
    $$variable{'ddmShippingOption'} = ssi::fill_drop_down( $log, $dbh, $temp, $id, 25 );
    if ( $id ne '' ) {
        $temp = "SELECT strName FROM tbl_Ship_Via WHERE lngIndex = '$id'";
        @$variable{'txtShipVia'} = sql::sql_statement( $log, $dbh, $temp );
    }
    $$variable{'txtShippingRate'} = configuration::get_value( $log, $dbh, 'shipping_rate' );
    my $selectedmethod = configuration::get_value( $log, $dbh, 'shipping_method' );
    my @methods = split( ',', configuration::get_value( $log, $dbh, 'shipping_methods' ) );
    foreach my $method ( @methods ) {
        $method =~ s/^\s*(.*)\s*$/$1/;
        if ( $method eq $selectedmethod ) {
            $$variable{'ddmShippingMethod'} .= "<option selected>$method</option>"; 
        } else {
            $$variable{'ddmShippingMethod'} .= "<option>$method</option>"; 
        }
    }
    configuration::get_value( $log, $dbh, 'shipping_gst_exempt' ) eq 'Y' ? $$variable{'GSTExemptYes'} = 'CHECKED' : $$variable{'GSTExemptNo'} = 'CHECKED';
    configuration::get_value( $log, $dbh, 'shipping_pst_exempt' ) eq 'Y' ? $$variable{'PSTExemptYes'} = 'CHECKED' : $$variable{'PSTExemptNo'} = 'CHECKED';

    return OK;
}

sub inventory_locations {
    my ( $r, $log, $dbh, $variable ) = @_;

    if ( $r->param('btnFunction') eq 'Save' ) {

		my $ins = $dbh->prepare(q{ INSERT INTO inventory_locations ("name", "notification")  VALUES ( ?,?); });
		$ins->execute( $r->param("location-new"), $r->param('notification-new')) if $r->param('location-new');

		my $up = $dbh->prepare(q{ UPDATE inventory_locations SET name = ?, notification = ? WHERE id = ?  });
		map { $up->execute($r->param("location-$_"), $r->param("notification-$_"), $_)  } $r->param('id');

		my $del = $dbh->prepare(q{ DELETE FROM inventory_locations WHERE id = ?});
		map { $del->execute($_) } $r->param('delete');

	}
	my $locations = $dbh->selectall_hashref(q{
		SELECT * FROM inventory_locations
	},'id',{});
	

	my @sorted;
	map { push @sorted, $locations->{$_} } sort keys %{$locations};
	$variable->{LOCATIONS} = \@sorted;
       
    return OK;

}

1;

