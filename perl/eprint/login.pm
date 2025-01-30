package eprint::login;
use strict;
use utf8;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY);
use Apache2::Cookie ();
use Captcha::reCAPTCHA;
use Data::Dumper;

#use sql qw(:common);
require sql;
require ssi;
require eprint::obj_customer;
require misc;
require eprint::greetings;
require eprint::user;
require eprint::order;
require MIME::QuotedPrint;
require crypto;

# displays the login page, and populates the destination variable
sub login_display {
    my ($r, $log, $dbh, $cookie, $variable) = @_;

    # A GET request can be redirected back to it's exact destination, a POST
    # is redirected to the section login.
    $variable->{destination} = $r->param('destination');

    return OK;
}

# login verification.    called when someone logs in
sub verify_login {
    my ($r, $log, $dbh, $cookie, $variable, $site) = @_;
    my ($temp, $error, $details);

    # convert the email address to lower case. All email addresses stored in
    # DB will be lower case.
    my $email = lc $r->param('txtEmail');
    if (!$email) {
	    $error = "No password provided. Authentication Failed.";
	    return misc::error($log, $dbh, $variable, $error, $details);
    }

    my $crypt = crypto::get_crypt();
    my $password = misc::escape($crypt->encrypt($r->param('txtPassword')));

    # doing it this way allows for multiple accounts with the same email
    # address, identified by their password.  however, on user registration,
    # we enforce the uniqueness of email addresses.    Also, the db should
    # have a UNIQUE attribute on the strEmail field.
    $_ =
      "SELECT lngUserID, lngCustomerID, strSalutation, strFirstName, strLastName, chrType "
      . "FROM tbl_Customer_Users "
      . "WHERE strEmail = ? "
      . "AND strPassword = ?";

    my ($user_id, $cust_id, $salutation, $first_name, $last_name, $user_type) =
      sql::execute($log, $dbh, $_, $email, $password);

    if ($user_id eq '') {
        # user not found. Let's see if we got the password wrong, or the email
        # wrong.
        $_ = "SELECT lngUserID FROM tbl_Customer_Users WHERE strEmail = '$email'";
        ($user_id) = sql::sql_statement($log, $dbh, $_);
        if ($user_id eq '') {
            $details = "\"$email\" is not a valid account.    Please push the back button and try again. If you require assistance please call us at 1-888-500-0999.";
        }
        else {
            $details = "The password you entered was not correct.     Please push the back button and try again. If you require assistance please call us at 1-888-500-0999.";
        }
        $error = "Authentication Failed.";
        return misc::error($log, $dbh, $variable, $error, $details);
    }

    # Have a valid user now.
    $_ =
      "SELECT ysnAccountActivation FROM tbl_Customer WHERE lngCustomerID = '$cust_id'";
    my ($acct_activated) = sql::sql_statement($log, $dbh, $_);
    if ($acct_activated eq 'N') {
        $error   = "Account not activated.";
        $details = "Your customer account has not been looked over and activated by an administrator yet. You will be notified when your application has been approved.";
        return misc::error($log, $dbh, $variable, $error, $details);
    }
    elsif ($acct_activated ne 'Y') {
        $error   = "Customer Account activation status is unknown.";
        $details = "Please report this error.";
        return misc::error($log, $dbh, $variable, $error, $details);
    }

    # Have a valid user now.
    $_ = "SELECT ysnAccountActivation FROM tbl_Customer_Users WHERE lngUserID = '$user_id'";
    ($acct_activated) = sql::sql_statement($log, $dbh, $_);
    if ($acct_activated eq 'N') {
        return misc::error( $log, $dbh, $variable, "Account not activated.", "Applications for existing corporate accounts must be approved by and administrator. You will be notified when you application had been approved.");
    }
    elsif ($acct_activated ne 'Y') {
        return misc::error($log, $dbh, $variable, "User Account activation status is unknown.", "Please report this error.");
    }

    if ($site eq 'E') {
        if ($user_type ne 'E' and $user_type ne 'A') {
            return misc::error($log, $dbh, $variable, "Not authorised.", "You are not an employee.  You do not have access to the employee site." );
        }
    }
    elsif ($site eq 'A') {
        if ($user_type ne 'A') {
            return misc::error($log, $dbh, $variable, "Not authorised.", "You are not an administrator.  You do not have access to the administrator site.");
        }
    }

    # The chrUserType in tbl_Logged_In tells us what site they are logged
    # into. In this case, they are logged into the customer site.  An S value
    # is set in the supplier version of this function, and A value is set in
    # the admin version of this function
    sql::update($log, $dbh, 'tbl_Logged_In', "strSessionID = '$cookie'", # AND chrSite = '$site'",
            chrUserType     => $user_type,
            lngCustomerID   => $cust_id,
            lngUserID       => $user_id,
            strEmail        => $email,
            dtmLastAccessed => 'NOW()'
    );
    @openprint::session{'company_id','user_id','email','user_type'} = ($cust_id, $user_id, $email, $user_type);


    $$variable{'GREETING'}                   = eprint::greetings::select_greeting($log, $dbh, $cust_id, $user_id);
    $$variable{'USER_GREETING'}              = eprint::greetings::select_user_greeting($log, $dbh, $user_id);
	# Moved to www.pm
    #$$variable{'USER_CATEGORY_GREETING'}     = eprint::greetings::select_user_category_greeting($log, $dbh, $user_id);
    $$variable{'CUSTOMER_GREETING'}          = eprint::greetings::select_customer_greeting($log, $dbh, $cust_id) unless $$variable{'USER_GREETING'};
    $$variable{'CUSTOMER_CATEGORY_GREETING'} = eprint::greetings::select_customer_category_greeting($log, $dbh, $cust_id) unless $$variable{'USER_CATEGORY_GREETING'};

    $_ = "SELECT ysnChangePassword FROM tbl_Customer_Users WHERE lngUserID = '$user_id'";
    my ($changepass) = sql::sql_statement($log, $dbh, $_);
    if ($changepass eq 'Y') {
        $r->err_headers_out->{Location} = configuration::get_value($log, $dbh, 'passchangepage');
        return HTTP_MOVED_TEMPORARILY;
    }

    # Set the user's name in a cookie so we don't have to hit the DB every time
    # we want it (which is virtually every page). Eventually we should have a
    # shared in memory session cache to handle stuff like this.
    my $sth = $dbh->prepare_cached(q{
        SELECT strfirstname || ' ' || strlastname
        FROM tbl_customer_users
        WHERE lnguserid = ?
    });

    my $username = $dbh->selectrow_array($sth, undef, $user_id);
    $cookie = Apache2::Cookie->new($r,
        -name   => 'username',
        -value  => $username,
        -path   => '/',
        -domain => $r->dir_config('cookiedomain'));
    $cookie->bake($r);
    $variable->{user}{name} = $username;

    # this is to pass through to ultimate destination after login
    if ($r->param('destination') =~ /orde_deta/i) {
        $$variable{'destination'} =
          q{To continue your order, please click <a href="/main/order/order_selection.html">here</a>};
    }
    elsif ($r->param('destination') =~ /quot_deta/i) {
        $$variable{'destination'} =
          q{To continue your quote, please click <a href="/main/quote/quote_details.html">here</a>};
    }
    elsif ($r->param('destination') =~ /acco_appl/i) {
        $$variable{'destination'} =
          q{To continue your credit application, please click <a href="/main/account/credit_application.html">here</a>};
    }

    # If we have a known destination and we're a GET (POST redirects are not
    # handled yet), send us back to the page we came from.
    elsif ($r->param('destination')) {
        $r->headers_out->set(Location => $r->param('destination'));
        return HTTP_MOVED_TEMPORARILY;
    }

    $variable->{user_type} = $user_type;
    $variable->{user_id}   = $user_id;

    display_select_customer($r, $log, $dbh, $variable, $cust_id);

    $log->debug("** Login Verified for: $email **");

    return OK;
}


# Remove the session from the database (for the specified site area). TODO: We
# should also remove the user's cookie.
sub logout {
    my ($log, $dbh, $cookie, $site) = @_;

    $dbh->do('DELETE FROM tbl_logged_in WHERE strSessionID = ?' # AND chrSite = ?
    , undef, $cookie);#, $site);

    return OK;
}

sub email_password {
    my ($r, $log, $dbh, $variable) = @_;

    my $c = Captcha::reCAPTCHA->new;
    my $challenge = 1;
    my $response  = $r->param('g-recaptcha-response');
    my $key = "6LdWLJkqAAAAAO8NEwEMoeumR5L0wB9mCagA3ZrP";
    if (!$response) {
      return misc::error( $log, $dbh, $variable, 
        'Bad Field', 'You must provide the Captcha.  Please press the back button to try again'  );
    }

    my $result = $c->check_answer_v2($key, $response, $ENV{'REMOTE_ADDR'});
    if (!$result->{is_valid}) {
      return misc::error( $log, $dbh, $variable, 
        'Bad Field', 'Your Captcha is incorrect. Please press the back button to try again'  );
    }

    my $email = $r->param('txtEmail2');
    $email =~ tr/[A-Z]/[a-z]/;
    $email = sql::escape($email);

    $_ = "SELECT strPassword FROM tbl_Customer_Users WHERE strEmail = '$email'";
    my ($password) = sql::sql_statement($log, $dbh, $_);

    if ($password eq '') {
        return misc::error($log, $dbh, $variable, 'Account doesn\'t exist.', 'The account you entered does not exist.  Please push the back button and try again. If you require assistance please call us at 1-888-500-0999.');
    }

    eval {
      my %info;
      my $crypt = crypto::get_crypt();
      # data coming from db may not be utf8
      utf8::encode($password);
      $info{password} = $crypt->decrypt(misc::unescape($password));

      my $email_template = misc::load_file($r, '/email/email_template.html');
      $info{'ReplacementText'} = "<!--#include virtual=\"/email/content/forgotten_password.html\"-->";
      $info{'domain'} = configuration::get_value($log, $dbh, 'domain');
      $info{'siteURL'} = "https://" . $r->hostname;
      $_ = MIME::QuotedPrint::encode_qp(ssi::variable_substitution($r, $log, $dbh, $email_template, \%info));
      my @body = ('', $_, 'text/html', 'quoted-printable');

      my %mail = (
        SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
        FROM    => configuration::get_value($log, $dbh, 'AdministratorEmail'),
        TO      => $r->param('txtEmail2'),
        SUBJECT => 'Forgotten Password',
      );
      misc::send_email_with_attachment($r, $log, \%mail, @body);
    };

    return OK;
} 

sub login_app_display {
    my ($r, $log, $dbh, $variable) = @_;

#    $_ = "SELECT strCompanyName, strCompanyName FROM tbl_Customer ORDER BY lower(strCompanyName)";
#    $$variable{'ddmCompany'}       = ssi::fill_drop_down($log, $dbh, $_);

    display_select_customer($r, $log, $dbh, $variable, $variable->{cust_id});
    $variable->{ddmCompany} = $variable->{ddmCustomer};

    $$variable{'ddmStateProvince'} = ssi::return_states_and_provinces();
    $$variable{'ddmCountry'}       = ssi::return_countries();
    $$variable{'destination'}      = $ENV{'HTTP_REFERER'};
    return OK;
}

sub login_app_process {
	my ($r, $log, $dbh, $variable, $cookie) = @_;
	my ($error, $temp, $cust_id, $user_id, $email);

	my $result;

	if (!$r->param('g-recaptcha-response')) {
		return misc::error( $log, $dbh, $variable,
				'Bad Field', 'You must provide the Captcha.  Please press the back button to try again'  );
	}

	eval {
		my $c = Captcha::reCAPTCHA->new;
		my $challenge = 1;
		my $response  = $r->param('g-recaptcha-response');
		my $key = "6LdWLJkqAAAAAO8NEwEMoeumR5L0wB9mCagA3ZrP";

		#print STDERR "START LOGIN APP PROCESS \n\n\n";
#unless ( $variable->{user_id} ) {
# Verify submission
		$result = $c->check_answer_v2($key, $response, $ENV{'REMOTE_ADDR'});
	};

	#print STDERR "CONTINUE LOGIN APP PROCESS:  \n\n\n", Dumper($result);

	unless ( $result->{is_valid} ) {
# Error
		return misc::error( $log, $dbh, $variable, 
				'Bad Field', 'Your Captcha is incorrect. Please press the back button to try again'  );
	}
	#}
	#

#wsc    $r->param('txtCompanyName' => $r->param('ddmCompany'))
#wsc    if $r->param('txtCompanyName') eq '';

    # perform input field validation
    $error  = '';
    $error .= 'Missing company name.<br>' if $r->param('txtCompanyName') eq '';
    $error .= 'Missing contact first name.<br>' if $r->param('txtFirstName') eq '';
    $error .= 'Missing contact last name.<br>' if $r->param('txtLastName') eq '';
#    $error .= 'Missing Salutation.<br>' if $r->param('rdbSalutation') eq '';
#    $error .= 'Missing position.<br>' if $r->param('txtTitle') eq '';
    $error .= 'Missing address.<br>' if $r->param('txtAddress1') eq '';
    $error .= 'Missing city.<br>' if $r->param('txtCity') eq '';
    $error .= 'Missing state/province.<br>' if $r->param('ddmStateProvince') eq '' and $r->param('txtOtherStateProvince') eq ''; 
    $error .= 'Missing country.<br>' if $r->param('ddmCountry') eq '' and $r->param('txtOtherCountry') eq '';
    $error .= 'Missing Postal Code.<br>' if $r->param('txtPostalCode') eq '';
    $error .= 'Postal Code too long.<br>' if length $r->param('txtPostalCode') > 12;
    $error .= 'Missing Phone Number.<br>' if $r->param('txtPhone') eq '';
    $error .= 'Phone Number too long.<br>' if length $r->param('txtPhone') > 16;
    $error .= 'Extension too long.<br>' if length $r->param('txtExt') > 10;
    $error .= 'Fax # too long.<br>' if length $r->param('txtFax') > 16;
    $error .= 'Missing E-mail Address.<br>' if $r->param('txtEmail') eq '';
    $error .= 'Empty Password.<br>' if $r->param('txtPassword') eq '';
    $error .= 'Passwords do not match.<br>' if $r->param('txtPassword') ne $r->param('txtVerifyPassword');

	
    
    if ($error) {
        return misc::error($log, $dbh, $variable, 'bad field.', $error);
    }

    # enforce uniquity for email addresses.
    $email = sql::escape($r->param('txtEmail'));
    $email =~ tr/[A-Z]/[a-z]/;
    
    if (sql::sql_statement($log, $dbh, "SELECT lngUserID FROM tbl_Customer_Users WHERE strEmail = '$email'")) {
        return misc::error($log, $dbh, $variable, 'User already exists', $r->param('txtEmail') . " is already a user!");
    }

    my $jar      = Apache2::Cookie::Jar->new($r);
    my $agent_cookie = $jar->cookies('Agent');
    my $agent;
    if ($agent_cookie) {
        $agent = $agent_cookie->value;
        $agent =~ /(\w*) (\w*)/;
        $_ = "SELECT strEmail FROM tbl_Customer_Users WHERE strFirstName='$1' AND strLastName='$2'";
        ($agent) = sql::sql_statement($log, $dbh, $_);
    }
    else {
        $agent = configuration::get_value($log, $dbh, 'UserRegistrationEmail');
    }

    my $crypt = crypto::get_crypt();

    # No errors, We are in go status
    my %info;
    foreach my $key ($r->param()) {
        $info{$key} = $r->param($key);
    }

    $info{'date'} = localtime;
    $info{'siteURL'} = "https://" . $r->hostname;
    $info{'SecureSiteURL'} = "https://" . $r->hostname;
    $info{'CustomerServiceEmail'} =
      configuration::get_value($log, $dbh, 'CustomerServiceEmail');

    # passwords may not have spaces now.
#wsc    $_ = $r->param('txtPassword');
#wsc    $_ =~ s/\s//g;
#wsc    $r->param('txtPassword' => $_);


    # Clean up the postal code
#wsc    $_ = $r->param('txtPostalCode');
#wsc    $_ =~ s/[^\w]//g;
#wsc    $_ =~ tr/[a-z]/[A-Z]/;
#wsc    $r->param('txtPostalCode' => $_);

    # if Company already exists in the DB, then just add the user to that
    # company. Otherwise, add the company
    $_ =
      "SELECT lngCustomerID FROM tbl_Customer WHERE lower(strCompanyName) = lower('"
      . sql::escape($r->param('txtCompanyName')) . "')\n";
    ($cust_id) = sql::sql_statement($log, $dbh, $_);

    if ($cust_id eq '') {

        # Choose a price list for the customer. First check to see if there's
        # a default price list for the country in which they reside. If there
        # isn't, we'll assign them the general default. If THAT doesn't exist,
        # we'll assign them the first price list in the system.
        my $pricelist = configuration::get_value($log, $dbh, 'Default' . $r->param('ddmCountry') . 'Pricelist');
           $pricelist = configuration::get_value($log, $dbh, 'DefaultOtherPricelist') 
                unless $pricelist;

        # If the specified price list doesn't exist, we'll do something silly
        # and just choose the first price list in the system.
        $pricelist = $dbh->selectrow_array(q{ SELECT min(id) FROM pricelist })
            unless $pricelist and $dbh->selectrow_array(q{ SELECT id FROM pricelist WHERE id = ? }, undef, $pricelist);


        my $cust = eprint::obj_customer->new($log, $dbh, $cust_id);

        $cust->set({
            Name              => $r->param('txtCompanyName'),
            Address1          => $r->param('txtAddress1') ? $r->param('txtAddress1') : '',
            Address2          => $r->param('txtAddress2') ? $r->param('txtAddress2') : '',
            City              => $r->param('txtCity'),
            StateProvince     => $r->param('txtOtherStateProvince') ne '' ? $r->param('txtOtherStateProvince') : $r->param('ddmStateProvince'),
            Country           => $r->param('txtOtherCountry') ne '' ? substr($r->param('txtOtherCountry'),0,25) : $r->param('ddmCountry'),
            PostalCode        => $r->param('txtPostalCode') ne ''? substr($r->param('txtPostalCode'),0,12) : '',
            Phone             => $r->param('txtPhone') ne '' ? substr($r->param('txtPhone'),0,16) : '',
            Extension         => $r->param('txtExtension') ne '' ? substr($r->param('txtExtension'),0,10) : '',
            Fax               => $r->param('txtFax') ne '' ? substr($r->param('txtFax'),0,16) : '',
            Website           => $r->param('txtURL') ? $r->param('txtURL') : '',

            BusinessType      => $r->param('txtBusinessType') ne '' ? substr($r->param('txtBusinessType'),0,50) : undef,
            PrintExpenditure  => $r->param('ddmPrintExpenditure') ne '' ? $r->param('ddmPrintExpenditure') : 0,            

            AccountActivation => configuration::get_value( $log, $dbh, 'NewCustomerAccountActivation') ,
            Reseller          => $r->param('rdbAccountType') eq 'Reseller' ? 'Y' : 'N',
            Supplier          => 'N',

            PriceList         => $pricelist,
            TaxExempt1        => $r->param('txtGSTNumber') ne '' ? 'Y' : 'N',
            TaxExempt2        => $r->param('txtPSTNumber') ne '' ? 'Y' : 'N',

            TaxNumber1        => $r->param('txtGSTNumber') ne '' ? $r->param('txtGSTNumber') : undef,
            TaxNumber2        => $r->param('txtPSTNumber') ne '' ? $r->param('txtPSTNumber') : undef,
        });


        # Pull the new customer's autogenerated ID.
        $cust_id = $cust->id;

        # Setup default Credit
        my $customer_credit = new eprint::customer_credit( $log, $dbh, $cust_id );
        my %params = (
            Terms        => configuration::get_value($log, $dbh, 'DefaultTerms')+0,
            CreditLimit  => configuration::get_value($log, $dbh, 'DefaultCreditLimit')+0 || 0,
            CreditHold   => configuration::get_value($log, $dbh, 'DefaultCreditHold')    || 'N',
            Downpayment  => configuration::get_value($log, $dbh, 'DefaultDownpayment')+0,
        );
        $customer_credit->set( \%params );

        sql::insert( $log, $dbh, 'tbl_Customer_Users',
                lngCustomerID        => $cust_id,
                strEmail             => $email,
                strPassword          => misc::escape($crypt->encrypt($r->param('txtPassword'))),
                strTitle             => $r->param('txtTitle'), 
                strFirstName         => $r->param('txtFirstName'),
                strLastName          => $r->param('txtLastName'),
                strPhone             => $r->param('txtPhone')     ne '' ? substr($r->param('txtPhone'),0,16)     : '',
                strExt               => $r->param('txtExtension') ne '' ? substr($r->param('txtExtension'),0,10) : '',
                strFax               => $r->param('txtFax')       ne '' ? substr($r->param('txtFax'),0,16)       : '',
                ysnMailingList       => 'Y',
                ysnAdministrator     => 'N',
                ysnChangePassword    => 'N',
                ysnAccountActivation => configuration::get_value( $log, $dbh, 'NewNonFirstUserAccountActivation'),
                chrType              => 'C',
                dtmDateEntered       => 'NOW()',
                dtmLastModified      => 'NOW()', 
                ( defined $r->param('rdbSalutation') ? ( strSalutation => $r->param('rdbSalutation') ) : () ),
        );
        
        $_ = "SELECT lngUserID FROM tbl_Customer_Users WHERE strEmail='$email'";
        ($user_id) = sql::sql_statement($log, $dbh, $_);

        $$variable{'CustomerIndex'} = $info{'CustomerIndex'} = $cust_id;
        $$variable{'UserIndex'}     = $info{'UserIndex'}     = $user_id;

		$dbh->do(q{INSERT INTO user_gift VALUES ( ?,?)}, undef, $user_id, $r->param('gift')) if $r->param('gift');

        my $password;
        $password =  $dbh->selectrow_array(q{
            SELECT strPassword FROM tbl_Customer_Users WHERE lngUserID = ?
        }, undef, $user_id) if $user_id;

        my $crypt = crypto::get_crypt();
        $info{'password'} = $crypt->decrypt(misc::unescape($password));

        # Send confirmation
        my $email_template = misc::load_file($r, '/email/email_template.html');
        $info{'ReplacementText'} = "<!--#include virtual=\"/email/content/first_user_login_app_confirmation.html\"-->";
        $email_template = ssi::variable_substitution($r, $log, $dbh, $email_template, \%info);
        my %mail = (
            SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
            FROM    => $agent,
            TO      => $email,
            SUBJECT => "New Login Application"
        );
        misc::send_email_with_attachment($r, $log, \%mail, ('', MIME::QuotedPrint::encode_qp($email_template), 'text/html', 'quoted-printable'));

        $log->debug("** Sent Notification to $email **");

        # send notification
        my $template = misc::load_file($r, '/email/email_template.html');
        $info{'ReplacementText'} = "<!--#include virtual=\"/email/content/first_user_login_app_notification.html\"-->";
        $template = ssi::variable_substitution($r, $log, $dbh, $template, \%info);

        %mail = (SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
                 FROM    => $agent,
                 TO      => $agent,
                 SUBJECT => "New Login Application");
        misc::send_email_with_attachment($r, $log, \%mail, ('', MIME::QuotedPrint::encode_qp($template), 'text/html', 'quoted-printable'));

        if (   configuration::get_value($log, $dbh, 'NewFirstUserAccountActivation') eq 'Y'
            && configuration::get_value($log, $dbh, 'NewCustomerAccountActivation')  eq 'Y')
        {
            # auto log in.
            sql::update( $log, $dbh, 'tbl_Logged_In', "strSessionID='$cookie'", # AND chrSite='C'",
                    lngCustomerID   => $cust_id,
                    lngUserID       => $user_id,
                    strEmail        => $email,
                    dtmLastAccessed => 'NOW()',
                    chrUserType     => 'C',
                    );    
            get_login_info( $log, $dbh, $cookie, $variable, 'C' );
        }
    } else {
        sql::insert( $log, $dbh, 'tbl_Customer_Users',
                lngCustomerID        => $cust_id,
                strEmail             => $email,
                strPassword          => misc::escape($crypt->encrypt($r->param('txtPassword'))),
                strTitle             => $r->param('txtTitle') || '', 
                strFirstName         => $r->param('txtFirstName') || '',
                strLastName          => $r->param('txtLastName') || '',
                strPhone             => $r->param('txtPhone') || '',
                strExt               => $r->param('txtExtension') || '',
                strFax               => $r->param('txtFax') || '',
				address1			 => $r->param('txtAddress1') || '',
				address2			 => $r->param('txtAddress2') || '',
				cubicle			 	 => $r->param('cubicle') || '',
				city			 	 => $r->param('txtCity') || '',
				state			 	 => $r->param('ddmStateProvince'),
				country			 	 => $r->param('ddmCountry'),
				postalcode			 => $r->param('txtPostalCode') || '',
                ysnMailingList       => 'Y',
                ysnAdministrator     => 'N',
                ysnChangePassword    => 'N',
                ysnAccountActivation => configuration::get_value( $log, $dbh, 'NewNonFirstUserAccountActivation'),
                chrType              => 'C',
                dtmDateEntered       => 'NOW()',
                dtmLastModified      => 'NOW()', 
                ( defined $r->param('rdbSalutation') ? ( strSalutation => $r->param('rdbSalutation') ) : () ),
        );

        # TODO This should just get the last_insert_id().
        my $user_id = $dbh->selectrow_array(q{SELECT lngUserID FROM tbl_Customer_Users WHERE strEmail = ?}, undef, $email);

        $$variable{'CustomerIndex'} = $info{'CustomerIndex'} = $cust_id;
        $$variable{'UserIndex'}     = $info{'UserIndex'}     = $user_id;

	$dbh->do(q{INSERT INTO user_gift VALUES ( ?,?)}, undef, $user_id, $r->param('gift')) if $r->param('gift');

        if (configuration::get_value($log, $dbh, 'NewNonFirstUserAccountActivation') ne 'Y') {
            # send notifications
            $_ =
              "SELECT strEmail FROM tbl_Customer_Users WHERE lngCustomerId='$cust_id' AND ysnAdministrator = 'Y'";
            foreach my $notification (sql::sql_statement($log, $dbh, $_)) {
                $_ =
                  "SELECT strSalutation, strFirstName, strLastName FROM tbl_Customer_Users WHERE strEmail='$notification'";
                @info{ 'AdminSalutation', 'AdminFirstName', 'AdminLastName' } =
                  sql::sql_statement($log, $dbh, $_);

                my $email_template =
                  misc::load_file($r, '/email/email_template.html');
                $info{'ReplacementText'} =
                  "<!--#include virtual=\"/email/content/not_first_user_login_app_notification_for_company_admin.html\"-->";
                $email_template =
                  ssi::variable_substitution($r, $log, $dbh, $email_template,
                                             \%info);
                my %mail = (
                    SMTP   => configuration::get_value($log, $dbh, 'Mail Server'),
                    FROM   => $agent,
                    TO      => $notification,
                    SUBJECT => 'New Login Application' 
                );
                misc::send_email_with_attachment($r, $log, \%mail, ('', MIME::QuotedPrint::encode_qp($email_template), 'text/html', 'quoted-printable'));
            }
        }

        my $template = misc::load_file($r, '/email/email_template.html');
        $info{'ReplacementText'} =
                  "<!--#include virtual=\"/email/content/not_first_user_login_app_notification_for_site_admin.html\"-->";
        $template = ssi::variable_substitution($r, $log, $dbh, $template, \%info);

        my %mail = (
            SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
            FROM    => $agent,
            TO      => $agent,
	    BCC => 'iconnor@connortechnology.com',
            SUBJECT => 'New Login Application' 
        );
        misc::send_email_with_attachment($r, $log, \%mail, ('', MIME::QuotedPrint::encode_qp($template), 'text/html', 'quoted-printable'));

        if (configuration::get_value($log, $dbh, 'NewNonFirstUserAccountActivation') ne 'Y') { 
            # Send confirmation
            my $email_template =
              misc::load_file($r, '/email/email_template.html');
            $info{'ReplacementText'} =
              "<!--#include virtual=\"/email/content/not_first_user_login_app_confirmation.html\"-->";
            $email_template =
              ssi::variable_substitution($r, $log, $dbh, $email_template,
                                         \%info);
            my %mail = (
                 SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
                 FROM    => $agent,
                 TO      => $email,
                 SUBJECT => 'New Login Application');
            misc::send_email_with_attachment($r, $log, \%mail, ('', MIME::QuotedPrint::encode_qp($email_template), 'text/html', 'quoted-printable' ));
        }

        if ($r->param('rdbReasonForPurchase') eq 'Reseller') {
            $_ =
              "SELECT ysnReseller FROM tbl_Customer WHERE lngCustomerID = '$cust_id'";
            ($_) = sql::sql_statement($log, $dbh, $_);

            if ($_ ne 'Y') {
                $$variable{'Redirect'} =
                  '/main/account/reseller_application.html';
            }
        }

        if (configuration::get_value($log, $dbh, 'NewNonFirstUserAccountActivation') eq 'Y') {
            # auto log in.
            my $activate_account = $dbh->selectrow_array(q{
                SELECT ysnAccountActivation 
                FROM tbl_Customer 
                WHERE lngCustomerID = ?
            }, undef, $cust_id);

# Disabled for Safeway.
# Bug 4846.
# Reactivated for safeway
# See bug 5018

            if ($activate_account eq 'Y') {
                sql::update($log, $dbh, 'tbl_Logged_In', "strSessionID='$cookie'", # AND chrSite='C'",
                    lngCustomerID   =>  $cust_id,
                    lngUserID       => $user_id,
                    strEmail        => $email,
                    dtmLastAccessed => 'NOW()',
                    chrUserType     =>  'C',
                );
                get_login_info($log, $dbh, $cookie, $variable, 'C')
            }

        }
    }
}

sub login_password {
    my ($r, $log, $dbh, $variable) = @_;

    $_ = configuration::get_value($log, $dbh, 'customerlogin');
    if ($ENV{'HTTP_REFERER'} =~ /$_/) {
        $$variable{'message'} =
          "Your account has been activated.    While it is not required, it is recommended you change your password now.";
    }
    else {
        $$variable{'message'} =
          "Please enter the required information to change your password.";
    }
}

sub cust_edit {
    my ($r, $log, $dbh, $variable) = @_;
    my ($temp, $error);

    my %fields = (txtAccountNum         => 'AccountNumber',
                  txtCompanyName        => 'Name',
                  txtAddress1           => 'Address1',
                  txtAddress2           => 'Address2',
                  txtCity               => 'City',
                  ddmStateProvince      => 'StateProvince',
                  txtStateProvince      => 'StateProvince',
                  ddmCountry            => 'Country',
                  txtCountry            => 'Country',
                  txtPostalCode         => 'PostalCode',
                  txtPhone              => 'Phone',
                  txtExtension          => 'Extension',
                  txtFax                => 'Fax',
                  ShippingAddressIndex  => 'ShippingAddressIndex',
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
                  txtBankEmail          => 'BankEmail',);

    my $customer = new eprint::obj_customer($log, $dbh, $$variable{'cust_id'});

    if ($r->param('btnFunction') eq 'Save') {
        my %params;
        foreach my $field (keys %fields) {
            $params{ $fields{$field} } = $r->param($field)
              if defined $r->param($field);
        }
        if ($r->param('txtStartYear')) {
            $params{'BusinessStartDate'} =
                $r->param('txtStartYear') . '-'
              . $r->param('ddmStartMonth') . '-01';
        }
        $customer->set(\%params);

        eprint::customer::save_shipping($r, $log, $dbh, $$variable{'cust_id'});
        eprint::customer::save_tradereferences($r, $log, $dbh,
                                               $$variable{'cust_id'});
    }

    @$variable{ keys %fields } =
      ssi::htmlize($customer->get(@fields{ keys %fields }));
    $$variable{ 'rdbLegalForm' . $$variable{'rdbLegalForm'} } = 'CHECKED';
    $$variable{'BusinessStartDate'} =~ /^(\d+)-(\d+)/;
    $$variable{'txtStartYear'}  = $1;
    $$variable{'ddmStartMonth'} = ssi::getmonths($2);

    $$variable{'ddmEmployees'} =
      ssi::getemployee_numbers($r, $log, $dbh, $$variable{'ddmEmployees'});

    eprint::customer::load_shipping($log, $dbh, $$variable{'cust_id'},
                                    $variable);

    $$variable{'ddmStateProvince'} =
      ssi::return_states_and_provinces($$variable{'ddmStateProvince'});
    $$variable{'ddmShippingStateProvince'} =
      ssi::return_states_and_provinces($$variable{'ddmShippingStateProvince'});
    $$variable{'ddmCountry'} = ssi::return_countries($$variable{'ddmCountry'});
    $$variable{'ddmShippingCountry'} =
      ssi::return_countries($$variable{'ddmShippingCountry'});
    $$variable{ 'rdbShippingSalutation'
          . $$variable{'rdbShippingSalutation'} } = 'CHECKED';

    eprint::customer::load_tradereferences($r, $log, $dbh,
                                           $$variable{'cust_id'}, $variable);

    $$variable{'ddmAnnualSales'} =
      ssi::getannual_sales($r, $log, $dbh, $$variable{'ddmAnnualSales'});
}

sub user_edit {
    my ($r, $log, $dbh, $variable) = @_;

    # We assume that we are authorized to be here now.
    $variable->{isAdmin} = scalar $dbh->selectrow_array(q{
        SELECT ysnadministrator 
        FROM tbl_Customer_users
        WHERE lngUserID = ?
    }, undef, $$variable{'user_id'});

    my $user_id = $variable->{isAdmin} eq 'Y' && $r->param('ddmUser') 
        ? $r->param('ddmUser') : $variable->{user_id};

    if ($$variable{'isAdmin'} eq 'Y') {
        if ($user_id) {
            # Enforce that we can only edit users from our company
            $_ = "SELECT lngUserID FROM tbl_Customer_Users WHERE lngUserID='$user_id' AND lngCustomerID='$$variable{'cust_id'}'";
            ($user_id) = sql::sql_statement($log, $dbh, $_);
        }

        if ($r->param('btnFunction') eq '<<') {
            if (!$user_id) {
                $_ =
                    "SELECT lngUserID FROM tbl_Customer_Users "
                  . "WHERE lngCustomerID='$$variable{'cust_id'}'\n"
                  . "ORDER BY strLastName DESC , strFirstName DESC LIMIT 1";
                ($user_id) = sql::sql_statement($log, $dbh, $_);
                eprint::user::load($log, $dbh, $user_id, $variable);
            }
            else {
                $user_id =
                  eprint::user::get_prev($log, $dbh, $$variable{'cust_id'},
                                         $user_id);
            }
        }
        elsif ($r->param('btnFunction') eq '>>') {
            if (!$user_id) {
                $_ =
                    "SELECT lngUserID FROM tbl_Customer_Users "
                  . "WHERE lngCustomerID='$$variable{'cust_id'}'\n"
                  . "ORDER BY strLastName , strFirstName LIMIT 1";
                ($user_id) = sql::sql_statement($log, $dbh, $_);
                eprint::user::load($log, $dbh, $user_id, $variable);
            }
            else {
                $user_id =
                  eprint::user::get_next($log, $dbh, $$variable{'cust_id'},
                                         $user_id);
            }
        }
        elsif ($r->param('btnFunction') eq 'Delete') {
            eprint::user::delete($r, $log, $dbh, $user_id, $variable);
            $user_id =
              eprint::user::get_next($log, $dbh, $$variable{'cust_id'},
                                     $user_id);
        }
    }

    # options available to non-company administrators
    if ($r->param('btnFunction') eq 'Save') {
        $user_id = $r->param('ddmUser');

        my $error = "";
        $error .= "Password fields do not match.\n" if $r->param('txtPassword') ne $r->param('txtVerifyPassword');
        $error .= "First Name cannot be blank.\n"   if $r->param('txtFirstName') eq '';
        $error .= "Last Name cannot be blank.\n"    if $r->param('txtLastName') eq '';
        $error .= "Salutation cannot be blank.\n"   if $r->param('rdbSalutation') eq '';
        $error .= "Phone cannot be blank.\n"        if $r->param('txtPhone') eq '';
        $error .= "Email Cannot be blank.\n"        if $r->param('txtEmail') eq '';
        if ($error ne '') {
            return misc::error($log, $dbh, $variable, 'Bad Field', $error);
        }

        if ($user_id eq '') {    # add
            $_ ="SELECT lngUserID FROM tbl_Customer_Users WHERE strEmail = '"
              . sql::escape($r->param('txtEmail')) . "'";
            ($_) = sql::sql_statement($log, $dbh, $_);
            if ($_ ne '') {
                return misc::error($log, $dbh, $variable, 'User already exists.', $r->param('txtEmail') . " is already a user.");
            }

            if ($r->param('txtPassword') eq '') {
                return misc::error($log, $dbh, $variable, 'Bad Password.', 'Sorry, we insist on a non-empty password.');
            }

            $user_id = eprint::user::add($r, $log, $dbh, $variable, $$variable{'cust_id'});

    # FIXME detect error case
        }
        else {                   # save
            eprint::user::save($r, $log, $dbh, $variable, $user_id);
        }
    }
    eprint::user::load($log, $dbh, $user_id, $variable);
    if ($$variable{'isAdmin'} eq 'Y') {
        $$variable{ 'rdbAccountActivation' . $$variable{'AccountActivation'} } = 'CHECKED';
        $$variable{ 'rdbAdministrator' . $$variable{'rdbAdministrator'} }      = 'CHECKED';
        $_ =
          "SELECT lngUserID, strFirstName || ' ' || strLastName FROM tbl_Customer_Users "
          . "WHERE lngCustomerID='$$variable{'cust_id'}'\n"
          . "ORDER BY strLastName, strFirstName";
        $$variable{'FILL_USER_NAME'} = ssi::fill_drop_down($log, $dbh, $_, $user_id);
    }
    $$variable{ 'rdbSalutation' . $$variable{'rdbSalutation'} }   = 'CHECKED';
    $$variable{ 'rdbMailingList' . $$variable{'rdbMailingList'} } = 'CHECKED';

    $log->debug("LOGIN: isAdmin at end: " . $$variable{'UserType'});
    return OK;
}

sub change_password {
    my ($r, $log, $dbh, $variable) = @_;
    my ($temp, $password);

    if ($r->param('txtNewPassword') ne $r->param('txtConfirmPassword')) {
        return misc::error($log, $dbh, $variable, 'Passwords don\'t match.', 'The new password, and the verification passwords you entered do not match.    Please push the back button and try again. If you require assistance please call us at 1-888-500-0999.');
    }

    if ($r->param('txtNewPassword') eq '') {
        return misc::error($log, $dbh, $variable, 'Insecure Password.', 'The new password you entered was blank.    This is too insecure, and will not be allowed.     Please push the back button and try again. If you require assistance please call us at 1-888-500-0999.');
    }

    $_ = "SELECT strPassword FROM tbl_Customer_Users WHERE lngUserID = '$$variable{'user_id'}'";
    ($password) = sql::sql_statement($log, $dbh, $_);
    if ($password eq '') {
        return
          misc::error($log, $dbh, $variable, 'No password.', 'We were unable to retrieve a valid password from the database.    This is likely a programming error.    Please report to support\@print-quotes-software.com.' );
    }

    my $crypt = crypto::get_crypt();
    $password = $crypt->decrypt(misc::unescape($password));

    if ($password eq $r->param('txtOldPassword')) {
        $password = misc::escape($crypt->encrypt($r->param('txtNewPassword')));
        sql::update($log, $dbh, 'tbl_Customer_Users', "lngUserID = '$$variable{'user_id'}'",
            strPassword       => $password,
            ysnChangePassword =>  'N',
        );
    }
    else {
        return misc::error($log, $dbh, $variable, 'Passwords don\'t match.', 'Your old password and what you entered are inconsistent.     Please push the back button and try again. If you require assistance please call us at 1-888-500-0999.' );
    }
    return OK;
}

# looks up user info, and handle timeouts. Updates accessdate.
sub verify_user {
  my ($r, $log, $dbh, $cookie, $variable, $site) = @_;

  # If the user doesn't have a cookie they aren't authenticated.
  if (!$cookie) {
    print STDERR "No cookie\n";
    return;
  }

  my $idletime = configuration::get_value($log, $dbh, 'idletime');

  # Retrieve the 'session' information based on the cookie.
  my $session = $dbh->prepare_cached(q{ SELECT lnguserid AS user, dtmLastAccessed AS last_visit FROM tbl_Logged_In WHERE strSessionID=?});
  $session = $dbh->selectrow_hashref($session, {}, $cookie);

  # Lookup the user that went with this session.
  my $user = $dbh->prepare_cached(q{
    SELECT u.lnguserid       AS user_id,
    c.lngcustomerid   AS cust_id,
    u.stremail        AS email,
    u.chrtype         AS user_type,
    c.ysnproductsonly AS products_only
    FROM tbl_customer c, tbl_customer_users u
    WHERE c.lngcustomerid = u.lngcustomerid
    AND u.lnguserid = ?
    });
  $user = $dbh->selectrow_hashref($user, {}, $session->{user});

  if (not $session->{last_visit}) {
    # no logged In information yet, so create some. NOTE: This code is
    # stupid. The 0,0 bit has caused a ton of weird problems.
    sql::insert($log, $dbh, 'tbl_Logged_In',
      dtmLastAccessed => 'NOW()',
      lngCustomerID   => 0,
      lngUserID       => 0,
      chrUserType     => '',
      chrSite         => $site,
      strSessionID    => $cookie,);

    $variable->{user_type} = '';
  } elsif ($user->{'user_id'} && (misc::gettime() - misc::gettime($session->{last_visit}) > $idletime)) {
    logout($log, $dbh, $cookie, $site);
    $$variable{'idletime'} = $idletime;
    $$variable{'destination'} = misc::get_destination($r, $log);

    $variable->{Redirect} = $site eq 'C' ? '/error/idle_timeout.html'
    : $site eq 'A' ? '/administrator/error/idle_timeout.html'
    : $site eq 'E' ? '/employee/error/idle_timeout.html'
    :                undef;
  } else {
    $cookie = $dbh->quote($cookie);
    $site   = $dbh->quote($site);

    # Update the last accessed time.
    sql::update($log, $dbh, 'tbl_logged_in',
      "strSessionID = $cookie", # AND chrSite = $site",
      dtmLastAccessed => 'NOW()');

    # Map the user info into the global storage thingy.
    $variable->{$_} = $user->{$_} for keys %$user;
  }

  $$variable{'CUSTOMER_CATEGORY_GREETING'} = eprint::greetings::select_customer_category_greeting($log, $dbh, $user->{cust_id}) if $user->{cust_id};
  @openprint::session{'company_id','user_id','email','user_type'} = @$user{'cust_id', 'user_id', 'email', 'user_type'};

  return OK;
}

# Load up "variable" with the customer's info from the current session.
sub get_login_info {
    my ($log, $dbh, $cookie, $variable, $site) = @_;

    # Load the session ID into variable.
    $variable->{cookie} = $cookie;

    # If we're logging into the employee site, also check logins on the
    # administrator side as we don't want admins to have to double login.
    $site = 'A' if $site eq 'E'
                && !$dbh->selectrow_array(q{
                     SELECT true FROM tbl_logged_in 
                     WHERE strsessionid = ? AND chrsite = ?
                     AND chrusertype IN ( 'A', 'E' )}, undef, $cookie, $site);

    # Get the company information.
    my $company = $dbh->prepare_cached(q{
        SELECT lngcustomerid                                          AS id,
               strcompanyname                                         AS "name",
               (CASE WHEN ysnsupplier = 'Y' THEN true ELSE false END) AS is_supplier,
               (CASE WHEN ysnreseller = 'Y' THEN true ELSE false END) AS is_reseller
        FROM tbl_logged_in JOIN tbl_customer USING (lngcustomerid)
        WHERE strsessionid = ?
     });
   #AND chrsite      = ?
    my $company = $dbh->selectrow_hashref($company, undef, $cookie);

    # User information
    my $user = $dbh->prepare_cached(q{
        SELECT u.lnguserid      AS id,
               u.stremail       AS email,
               u.strfirstname   AS firstname,
               u.strlastname    AS lastname,
               u.chrtype        AS "type",
			   u.editproject	AS editproject
        FROM tbl_logged_in l JOIN tbl_customer_users u USING (lnguserid)
        WHERE l.strsessionid = ?
    });

  #AND l.chrsite      = ?
    $user = $dbh->selectrow_hashref($user, undef, $cookie);

    # die "Invalid session or customer does not exist."
    #     unless $company->{id} && $user->{id};

    $user->{name}     = "$user->{firstname} $user->{lastname}";
    $user->{is_staff} = ($user->{type} =~ /^[AE]$/);
    $user->{company}  = $company;

    # Legacy mappings.
    $variable->{user}      = $user;
    $variable->{user_id}   = $user->{id};
    $variable->{user_type} = $user->{type};
    $variable->{email}     = $user->{email};
    $variable->{is_staff}  = $user->{is_staff};
    $variable->{cust_id}   = $company->{id};
    $variable->{Reseller}  = $company->{is_reseller} ? 'Y' : 'N';
    $variable->{Supplier}  = $company->{is_supplier} ? 'Y' : 'N';

	if ( $variable->{user_id} ) {
		my $order_id = eprint::order::get_unfinished_order(
				undef, $dbh, $cookie, $variable->{cust_id}, $variable->{user_id} );

		$variable->{order_count} = $dbh->selectrow_array(q{
				SELECT count(*) FROM tbl_order_contents
				WHERE lngorderid = ?
		}, undef, $order_id) if $order_id;
	}

    $variable->{budget_balance} = $dbh->selectrow_array(q{
	SELECT	
		(cu.budget) - (SELECT SUM(curtotalsale)
		FROM tbl_orders tor
		WHERE tor.lnguserid = ?
		AND strstatus <> 'Incomplete'
		AND strstatus <> 'Cancelled'
		AND dtmorderdate::date > (SELECT extract (year from current_date)|| '-01-01')::date)
	FROM tbl_customer_users cu
	WHERE cu.lnguserid = ?
    },undef, $user->{id}, $user->{id} );

	$variable->{nationalcredit} = $dbh->selectrow_array(q{
		SELECT nationalcredit FROM tbl_customer WHERE lngcustomerid = ?
	}, undef, $variable->{cust_id});

	$variable->{dollarcredit}  = $dbh->selectrow_array(q{
		SELECT ordercredit FROM tbl_customer WHERE lngcustomerid = ?
	}, undef, $variable->{user}{company}{id}) || '0.00';

	$variable->{mailingcredit}  = $dbh->selectrow_array(q{
		SELECT mailingcredit FROM tbl_customer WHERE lngcustomerid = ?
	}, undef, $variable->{user}{company}{id}) || '0.00';

    return $company->{id};
} 
sub display_select_customer { 
	my ($r, $log, $dbh, $variable, $cust_id) = @_;
    my $sql;

    my $is_reseller = $dbh->selectrow_array(q{
        SELECT (CASE WHEN ysnreseller = 'Y' THEN true 
                                            ELSE false 
                END) AS is_reseller
        FROM tbl_customer WHERE lngcustomerid = ?
    }, undef, $cust_id);

    # Let Admins select anybody.
    if ($variable->{user_type} eq 'A') {
        $sql = q{ SELECT lngCustomerID, strCompanyName 
                  FROM tbl_Customer 
				  WHERE show_in_company_list
				  ORDER BY lower(strCompanyName)
				};
    }    
    # If our company is a reseller the Select only from our Accounts. This
    # includes regular Customers and Employees.
    elsif ($is_reseller) {
        $sql = qq{ 
            SELECT lngCustomerID, strCompanyName 
            FROM tbl_Customer
            WHERE lngSalesPerson = $variable->{user_id} 
			AND show_in_company_list
            ORDER BY lower(strCompanyName)
	
        };
    }    
    # If we are not an admin and Our company it not a Reseller the if we are
    # an employee for now we will select from all accounts.
    elsif ($variable->{user_type} eq 'E') {
        $sql = q{ SELECT lngCustomerID, strCompanyName 
                  FROM tbl_Customer 
				  WHERE show_in_company_list
				  ORDER BY lower(strCompanyName) 
		};
    }

print STDERR "SELECT CUSTOMER: " , $sql , "\n";
    $$variable{'ddmCustomer'} = ssi::fill_drop_down($log, $dbh, $sql) if $sql;


    return OK;
}

# Called when a salesperson/admin selects a customer to act as.
sub select_customer {
  my ($r, $log, $dbh, $cookie, $variable, $customer) = @_;

  my $cust_id = $customer || $r->param('ddmCustomer') || $r->param('SelectCustomer');

  sql::update($log, $dbh, 'tbl_Logged_In', "strSessionID= '$cookie'",# AND chrSite = 'C' ",
    lngCustomerID => $cust_id
  );

  $variable->{cust_id} = $cust_id;

  #print STDERR "UPDATE CUST TO : $variable->{cust_id} \n";

  # Update this session's company information to the newly selected one.
  $variable->{user}{company} = $dbh->selectrow_hashref(q{
    SELECT lngcustomerid                                          AS id,
    strcompanyname                                         AS "name",
    (CASE WHEN ysnsupplier = 'Y' THEN true ELSE false END) AS is_supplier,
    (CASE WHEN ysnreseller = 'Y' THEN true ELSE false END) AS is_reseller,
    ordercredit
    FROM tbl_customer WHERE lngcustomerid = ?
    }, undef, $variable->{cust_id});

  $variable->{strCompanyName} = $variable->{user}{company}{name};
  $variable->{dollarcredit}  = $variable->{user}{company}{ordercredit} // '0.00';

  my $order_id = eprint::order::get_unfinished_order(
    undef, $dbh, $cookie, $variable->{cust_id}, $variable->{user_id} );

  $variable->{order_count} = $order_id ? $dbh->selectrow_array(q{
    SELECT count(*) FROM tbl_order_contents
    WHERE lngorderid = ?
    }, undef, $order_id) : '';


  #print STDERR "VERIFY HAVE ORDER: $order_id OC: $variable->{order_count} \n";
  return OK;
}

1;
__END__
