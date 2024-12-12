package eprint::credit_application;
use strict;

use MIME::QuotedPrint;

require eprint::customer_credit;
require eprint::obj_customer;
require eprint::customer;

my %fields = (
        rdbLegalForm          => 'LegalForm',
        txtLegalBusinessName  => 'LegalBusinessName',
        txtBusinessType       => 'BusinessType',
        BusinessStartDate     => 'BusinessStartDate',
        txtPresidentOwner     => 'PresidentOwner',
        ddmEmployees          => 'Employees',
        ddmAnnualSales        => 'AnnualSales',
        txtGSTNumber          => 'TaxNumber1',
        txtPSTNumber          => 'TaxNumber2',
        txtBankBranch         => 'BankBranch',
        txtBankName           => 'BankName',
        txtBankAccountNo      => 'BankAccountNumber',
        txtBankAccountManager => 'BankAccountManager',
        txtBankPhone          => 'BankPhone',
        txtBankFax            => 'BankFax',
        txtBankEmail          => 'BankEmail',
        Country               => 'Country',
);

sub credit_app_display {
    my ( $r, $log, $dbh, $variable ) = @_;

    return unless $variable->{cust_id};

    my $customer = new eprint::obj_customer( $log, $dbh, $variable->{cust_id} );
    @$variable{ keys %fields } = ssi::htmlize( $customer->get( @fields{ keys %fields } ) );

    $variable->{BusinessStartDate} =~ /^(\d+)-(\d+)/;
    $variable->{txtStartYear} = $1;
    $variable->{ddmStartMonth} = ssi::getmonths( $2 );
        
    $variable->{'rdbLegalForm'.$variable->{rdbLegalForm}} = 'CHECKED';
    $variable->{ddmEmployees} = ssi::getemployee_numbers( $r, $log, $dbh, $variable->{ddmEmployees} );
    $variable->{ddmAnnualSales} = ssi::getannual_sales( $r, $log, $dbh, $variable->{ddmAnnualSales} );

    eprint::customer::load_tradereferences( $r, $log, $dbh, $variable->{cust_id}, $variable );
}
        
sub credit_app_process {
    my ( $r, $log, $dbh, $variable ) = @_;

    # first, check all fields that are required
    my $error = '';
    $error .= "Missing legal business name<br>" if $r->param('txtLegalBusinessName') eq '';
    $error .= "Missing legal form<br>" if $r->param('rdbLegalForm') eq '';
    # $error .= "Missing legal business nature<br>" if $r->param('txtBusinessNature') eq '';
    $error .= "Missing president/owner<br>" if $r->param('txtPresidentOwner') eq '';
    $error .= "Missing/bad year established<br>" if $r->param('txtStartYear') !~ /^\s*\d+\s*$/;
    # $error .= "Bad Federal Tax number<br>" if $r->param('txtGSTNumber') eq '';
    # $error .= "Bad State Tax number<br>" if $r->param('txtPSTNumber') eq '';
    $error .= "Missing number of employees<br>" if $r->param('ddmEmployees') eq '';
    $error .= "Missing annual sales<br>" if $r->param('ddmAnnualSales') eq '';
    $error .= "Missing bank name<br>" if $r->param('txtBankName') eq '';
    $error .= "Missing bank branch<br>" if $r->param('txtBankBranch') eq '';
    $error .= "Missing bank account number<br>" if $r->param('txtBankAccountNo') eq '';
    $error .= "Missing bank account manager<br>" if $r->param('txtBankAccountManager') eq '';
    $error .= "Bad bank phone number entered.<br>" if $r->param('txtBankPhone') eq '';
    foreach my $tr ( 1 .. 3 ) {
        $error .= "Missing company name for trade reference $tr<br>" if $r->param('txtTradeReferenceCompanyName'.$tr) eq '';
        $error .= "Missing contact for trade reference $tr<br>" if $r->param('txtTradeReferenceContact'.$tr) eq '';
        $error .= "Missing phone number for trade reference $tr<br>" if $r->param('txtTradeReferencePhone'.$tr) eq '';
        # $error .= "Missing email address for trade reference $tr<br>" if $r->param('txtTradeReferenceEmail'.$tr) eq '';
    }
    $error .= "Missing accounts payable contact<br>" if $r->param('txtAccountsPayableContact') eq '';
    $error .= "Missing signature<br>" if $r->param('txtSignature') eq '';

    # process error conditions
    if ( $error ne '' ) {
        return misc::error( $log, $dbh, $variable, 'Bad Field', $error );
    }

    my $customer = new eprint::obj_customer( $log, $dbh, $variable->{cust_id} );
    my %params;
    foreach my $field ( keys %fields ) {
        my $x = $r->param($field);
        $params{$fields{$field}} = $r->param($field) if defined $r->param($field);
    }
    if ( $r->param('txtStartYear') ) {
        $params{BusinessStartDate} = $r->param('txtStartYear') . '-' . ( $r->param('ddmStartMonth') ? $r->param('ddmStartMonth') : '01' ) . '-01';
    }
    $customer->set( \%params );

    eprint::customer::save_tradereferences( $r, $log, $dbh, $variable->{cust_id} );

    my $creditlimit = $r->param('txtDesiredCreditLimit');
       $creditlimit =~ s/[^\d\.]//g;
    
    sql::insert($log, $dbh, 'tbl_Credit_App',
        lngUserIndex              => $variable->{user_id},
        lngCustomerIndex          => $variable->{cust_id},
        lngTerms                  => $r->param('ddmDesiredTerms'),
        strAccountsPayableContact => $r->param('txtAccountsPayableContact'),
        strStatus                 => 'Non-Reviewed',
        dtmCreationDate           => 'NOW()',
        ( defined $r->param('txtSignature')                   ? ( strSignature                   => $r->param('txtSignature') ) : () ),
        ( defined $r->param('rdbFinancialStatementAvailable') ? ( ysnFinancialStatementAvailable => $r->param('rdbFinancialStatementAvailable') ) : () ),
        ( defined $r->param('txtFirstOrderValue')             ? ( strFirstOrderValue             => $r->param('txtFirstOrderValue') ) : () ),
        ( defined $r->param('txtAnnualPurchases')             ? ( strAnnualPurchases             => $r->param('txtAnnualPurchases') ) : () ),
        ( $creditlimit ne '' ? ( dblCreditLimit => $creditlimit ) : () ),
    );

    # Now send email notifications
    my %info;
    eprint::customer::load( $r, $log, $dbh, $variable->{cust_id}, \%info );
    foreach my $key ( $r->param() ) {
        $info{$key} = $r->param($key);
    }
    $info{date} = localtime;
    $info{siteURL} = "https://" . $r->hostname;

    $info{SecureSiteURL} = "https://" . $r->hostname;

    $_ = "SELECT MAX(lngIndex) FROM tbl_Credit_App WHERE lngUserIndex='$variable->{user_id}' AND lngCustomerIndex='$variable->{cust_id}'";
    @info{CreditAppIndex} = sql::sql_statement( $log, $dbh, $_ );
    $_ = "SELECT dblMin,dblMax FROM tbl_Annual_Sales WHERE lngIndex = '$info{ddmAnnualSales}'";
    $info{txtAnnualSales} = ssi::get_range_text( sql::sql_statement( $log, $dbh, $_ ) );
    $_ = "SELECT lngMin,lngMax FROM tbl_Employee_Numbers WHERE lngEmployeeID = '$info{ddmEmployees}'";
    $info{txtEmployees} = ssi::get_range_text( sql::sql_statement( $log, $dbh, $_ ) );
    
    my $email_template = misc::load_file($r, '/email/email_template.html');
    $info{ReplacementText} = "<!--#include virtual=\"/email/content/credit_application_notification.html\"-->";
    my $template = ssi::variable_substitution( $r, $log, $dbh, $email_template, \%info );
    
    my %mail = (
        SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
        FROM    => configuration::get_value( $log, $dbh, 'CreditApplicationEmail'),
        TO      => configuration::get_value( $log, $dbh, 'CreditApplicationEmail'),
        SUBJECT => "New Credit Application"
    );

    misc::send_email_with_attachment( $r, $log, \%mail, ( '', encode_qp($template), 'text/html', 'quoted-printable' ) );

}

sub credit_applications {
    my ($r, $log, $dbh, $variable) = @_;

    # Save the application before display (if requested).
    save_application(@_) if $r->param('btnFunction') eq 'Save';

    ssi::get_start_end_dates( $log, $dbh, $variable,
            $r->param('ddmStartYear'),
            $r->param('ddmStartMonth'),
            $r->param('ddmStartDay'),
            $r->param('ddmEndYear'),
            $r->param('ddmEndMonth'),
            $r->param('ddmEndDay') );

    @{$variable->{CreditApps}} = ();
    $_ = "SELECT lngIndex, strSignature, date(dtmCreationDate), (SELECT strCompanyName FROM tbl_Customer WHERE lngCustomerID=lngCustomerIndex), strStatus\n".
        "FROM tbl_Credit_App\n".
        "WHERE date(dtmCreationDate) BETWEEN date('$variable->{StartDate}') AND date('$variable->{EndDate}')\n";
    $_ .= "AND strStatus = 'Approved'\n" if $r->param('ddmStatus') eq 'Approved';
    $_ .= "AND strStatus = 'Declined'\n" if $r->param('ddmStatus') eq 'Declined';
    $_ .= "AND strStatus != 'Non-Reviewed'\n" if $r->param('ddmStatus') eq 'Reviewed';
    $_ .= "AND strStatus = 'Non-Reviewed'\n" if $r->param('ddmStatus') eq 'Non-Reviewed';
    $_ .= "AND lngCustomerIndex = '".$r->param('ddmCompany')."'\n" if $r->param('ddmCompany');
    #$_ .= "AND lngSupplierIndex = '$variable->{cust_id}'";
    $_ .= "ORDER BY dtmCreationDate, lngIndex";
    @{$variable->{CreditApps}} = sql::sql_statement( $log, $dbh, $_ );

    $_ = "SELECT lngCustomerID, strCompanyName FROM tbl_Customer ".
         "ORDER BY lower(strCompanyName)";
    $variable->{ddmCompany} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmCompany') );
    $variable->{$r->param('ddmStatus')} = 'SELECTED';
}

sub save_application {
    my ($r, $log, $dbh, $variable) = @_;

    my %credit_fields = (
            txtTerms        => 'Terms',
            CreditLimit     => 'CreditLimit',
            txtDownpayment  => 'Downpayment',
    );
    my $credit_app = $r->param('credit_index');

    return unless $credit_app;

    sql::update( $log, $dbh, 'tbl_Credit_App', "lngIndex='$credit_app'", 
        strStatus             => $r->param('verdict'),
        lngGrantedTerms       => $r->param('txtTerms'),
        dblGrantedCreditLimit => $r->param('CreditLimit'),
        dblGrantedDownpayment => $r->param('txtDownpayment'),
    );

    @$variable{qw(
        hiddenCustomerID     UserIndex  
        Signature            FinancialStatementAvailable
        FirstOrderValue      AnnualPurchases
        AccountLimitDesired  AccountsPayableContact
        SubmissionDate 
      )} = $dbh->selectrow_array(q{
        SELECT lngCustomerIndex,   lngUserIndex, 
               strSignature,       ysnFinancialStatementAvailable,
               strFirstOrderValue, strAnnualPurchases, 
               dblCreditLimit,     strAccountsPayableContact, 
               to_char(dtmCreationDate,'Day Month DD, YYYY HH24:MI') 
        FROM tbl_Credit_App
        WHERE lngIndex = ?
    }, undef, $credit_app);


    $_ = "SELECT lngCustomerID FROM tbl_Customer WHERE lngCustomerID='$variable->{hiddenCustomerID}'";

    if ( ! sql::sql_statement( $log, $dbh, $_ ) ) {
        return misc::error( $log, $dbh, $variable, 'Deleted Customer', "The company that created this credit app has been deleted from the system.  This credit app has been deleted." );
    }

    $variable->{FinancialStatementAvailable} 
        = $variable->{FinancialStatementAvailable} eq 'Y' ? 'Yes' : 'No';

    my $customer_credit = new eprint::customer_credit($log, $dbh, $variable->{hiddenCustomerID}, $variable->{cust_id});
    my %params;

    foreach my $field ( keys %credit_fields ) {
        $params{$credit_fields{$field}} = $r->param($field) if defined $r->param($field);
    }
    $params{txtSignature} = $variable->{Signature};
    $customer_credit->set( \%params );

    $params{siteURL}       = "https://" . $r->hostname;
    $params{SecureSiteURL} = "https://" . $r->hostname;

    my $email = scalar $dbh->selectrow_array(q{
        SELECT strEmail FROM tbl_Customer_Users WHERE lngUserID = ?
    }, undef, $variable->{UserIndex});

    my $email_template = misc::load_file($r, '/email/email_template.html');

    $params{ReplacementText} = "<!--#include virtual=\"/email/content/credit_change_notification.html\"-->";
    my $template = ssi::variable_substitution( $r, $log, $dbh, $email_template, \%params );
    
    my %mail = (
        SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
        FROM    => configuration::get_value( $log, $dbh, 'AdministratorEmail'),
        TO      => $email,
        SUBJECT => 'Credit Status Changed.'
    );
    misc::send_email_with_attachment($r, $log, \%mail, ( '', encode_qp($template), 'text/html', 'quoted-printable' ) );
}


sub credit_application {
    my ($r, $log, $dbh, $variable) = @_;

    my %credit_fields = (
        txtTerms        => 'Terms',
        CreditLimit     => 'CreditLimit',
        txtDownpayment  => 'Downpayment',
    );

    my $credit_app = $r->param('credit_index');
    $variable->{credit_index} = $credit_app;

    return unless $credit_app;
        
    @$variable{qw(
        hiddenCustomerID        UserIndex
        Signature               FinancialStatementAvailable
        FirstOrderValue         AnnualPurchases
        AccountLimitDesired     AccountTermsDesired
        AccountsPayableContact  SubmissionDate
        verdict                 GrantedTerms
        GrantedCreditLimit      GrantedDownpayment
      )} = $dbh->selectrow_array(q{
        SELECT lngCustomerIndex,          lngUserIndex, 
               strSignature,              ysnFinancialStatementAvailable,
               strFirstOrderValue,        strAnnualPurchases, 
               dblCreditLimit,            lngTerms, 
               strAccountsPayableContact, to_char(dtmCreationDate,'Day Month DD, YYYY HH24:MI'), 
               strStatus,                 lngGrantedTerms, 
               dblGrantedCreditLimit,     dblGrantedDownpayment
        FROM tbl_Credit_App
        WHERE lngIndex = ?
    }, undef, $credit_app);


    $variable->{FinancialStatementAvailable} = $variable->{FinancialStatementAvailable} eq 'Y' ? 'Yes' : 'No';
    $variable->{'verdict'.$variable->{verdict}} = 'CHECKED';

    ($variable->{AnnualSales}, $variable->{Employees}) = sql::sql_statement(
        $log, $dbh, sprintf(
            "SELECT strannualsales, stremployees 
             FROM tbl_customer WHERE lngcustomerid = %d", $variable->{cust_id}
        )
    );

    my $customer_credit = new eprint::customer_credit( $log, $dbh, $variable->{hiddenCustomerID}, $variable->{cust_id} );

    eprint::customer::load( $r, $log, $dbh, $variable->{hiddenCustomerID}, $variable );

    if ($variable->{AnnualSales})
    {
        $_ = "SELECT dblMin, dblMax FROM tbl_Annual_Sales WHERE lngIndex='$variable->{AnnualSales}'";
        $variable->{txtAnnualSales} = ssi::get_range_text( sql::sql_statement( $log, $dbh, $_ ) );
    }
    if ($variable->{Employees})
    {
        $_ = "SELECT lngMin, lngMax FROM tbl_Employee_Numbers WHERE lngEmployeeID='$variable->{Employees}'";
        $variable->{txtEmployees} = ssi::get_range_text( sql::sql_statement( $log, $dbh, $_ ) );
    }
    $variable->{txtStartDate} =~ /(\d\d\d\d)-\d\d-\d\d/;
    $variable->{txtStartYear} = $1;

    @$variable{ keys %credit_fields } = ssi::htmlize( $customer_credit->get( @credit_fields{ keys %credit_fields } ) );
    $variable->{'rdbTerms'.$variable->{rdbTerms}} = 'CHECKED';

    eprint::customer::load_shipping( $log, $dbh, $variable->{hiddenCustomerID}, $variable );
    eprint::customer::load_tradereferences( $r, $log, $dbh, $variable->{hiddenCustomerID}, $variable );
}

1;
