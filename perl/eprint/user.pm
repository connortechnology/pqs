package eprint::user;
use strict;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY);
use MIME::QuotedPrint;

use sql ();
use configuration ();

require crypto;
require misc;

# Add a new user (from form POST).
sub add {
    my ($r, $log, $dbh, $variable, $cust_id) = @_;

    my $email    = $r->param('txtEmail') ||  $r->param('email');  # Email is a required field
       $email    =~ tr/[A-Z]/[a-z]/;
    my $password = $r->param('txtPassword') ||  $r->param('password');

    my $crypt = crypto::get_crypt( $log, $dbh );
    sql::insert( $log, $dbh, 'tbl_customer_users',
        lngCustomerID         => $cust_id,
        strEmail              => $email,
        dtmDateEntered        => 'NOW()',
        dtmLastModified       => 'NOW()',
        chrType               => (defined $r->param('ddmUserType')  ? $r->param('ddmUserType') : 'C'),
        notify_manager_order  => ($r->param('notify_manager_order') ? 1 : 0),
        notify_manager_file   => ($r->param('notify_manager_file')  ? 1 : 0),

        ( defined $password          ? ( strPassword          => misc::escape($crypt->encrypt($password)) ) : () ),
        ( defined $r->param('txtTitle')             ? ( strTitle             => $r->param('txtTitle') ) : () ),
        ( defined $r->param('txtFirstName')         ? ( strFirstName         => $r->param('txtFirstName') ) : () ),
        ( defined $r->param('txtLastName')          ? ( strLastName          => $r->param('txtLastName') ) : () ),
        ( defined $r->param('rdbSalutation')        ? ( strSalutation        => $r->param('rdbSalutation') ) : () ),
        ( defined $r->param('txtPhone')             ? ( strPhone             => $r->param('txtPhone') ) : () ),
        ( defined $r->param('txtExtension')         ? ( strExt               => $r->param('txtExtension') ) : () ),
        ( defined $r->param('txtFax')               ? ( strFax               => $r->param('txtFax') ) : () ),
        ( defined $r->param('rdbMailingList')       ? ( ysnMailingList       => $r->param('rdbMailingList') ) : () ),
        ( defined $r->param('txtCustomGreeting')    ? ( strCustomGreeting    => $r->param('txtCustomGreeting') ) : () ),
        ( defined $r->param('rdbChangePassword')    ? ( ysnChangePassword    => $r->param('rdbChangePassword') ) : () ),
        ( defined $r->param('rdbAccountActivation') ? ( ysnAccountActivation => $r->param('rdbAccountActivation') ) : () ),
        ( defined $r->param('rdbAdministrator')     ? ( ysnAdministrator     => $r->param('rdbAdministrator') ) : () ),
        ( defined $r->param('rdbAdministrator')     ? ( ysnAdministrator     => $r->param('rdbAdministrator') ) : () ),
        ( defined $r->param('address1')     		? ( address1     		 => $r->param('address1') ) : () ),
        ( defined $r->param('address2')     		? ( address2     		 => $r->param('address2') ) : () ),
        ( defined $r->param('cubicle')     			? ( cubicle     		 => $r->param('cubicle') ) : () ),
        ( defined $r->param('city')     			? ( city     		 	 => $r->param('city') ) : () ),
        ( defined $r->param('state')     			? ( state     		 	 => $r->param('state') ) : () ),
        ( defined $r->param('country')     			? ( country     		 => $r->param('country') ) : () ),
        ( defined $r->param('postalcode')     		? ( postalcode     		 => $r->param('postalcode') ) : () ),
        editproject   		=> ($r->param('editproject')  ? 1 : 0),
    );

    return $dbh->selectrow_array(q{
        SELECT lngUserID FROM tbl_Customer_Users WHERE strEmail = ?
    }, undef, $email);
}


# Save changes to a user down to the database (from form POST).
sub save {
  my ( $r, $log, $dbh, $variable, $user_id ) = @_;

  my $email =  $r->param('txtEmail') || $r->param('email');
  my $pass  =  $r->param('txtPassword') || $r->param('password');
  my $verify = $r->param('txtVerifyPassword')  || $r->param('verify');

  # Send a notification about change of user type (if applicable).
  notify_usertype_change($r, $log, $dbh, $user_id, $r->param('ddmUserType')) 
  if defined $r->param('ddmUserType');


  my $crypt = crypto::get_crypt($log, $dbh);

  sql::update($log, $dbh, 'tbl_Customer_Users', "lngUserID = $user_id", 
    notify_manager_order  => ($r->param('notify_manager_order') ? 1 : 0),
    notify_manager_file   => ($r->param('notify_manager_file')  ? 1 : 0),
    editproject   		  => ($r->param('editproject')  ? 1 : 0),

    ( defined $r->param('ddmCompany')           ? (lngCustomerID        => $r->param('ddmCompany')) : () ),
    ( defined $r->param('txtTitle')             ? (strTitle             => $r->param('txtTitle')) : () ),
    ( defined $r->param('txtFirstName')         ? (strFirstName         => $r->param('txtFirstName')) : () ),
    ( defined $r->param('txtLastName')          ? (strLastName          => $r->param('txtLastName')) : () ),
    ( defined $r->param('rdbSalutation')        ? (strSalutation        => $r->param('rdbSalutation')) : () ),
    ( defined $r->param('txtPhone')             ? (strPhone             => $r->param('txtPhone')) : () ),
    ( defined $r->param('txtExtension')         ? (strExt               => $r->param('txtExtension')) : () ),
    ( defined $r->param('txtFax')               ? (strFax               => $r->param('txtFax')) : () ),
    ( defined $r->param('txtCommission')        ? (dblCommission        => ($r->param('txtCommission') ne '' ? $r->param('txtCommission') : '0') ) : () ),
    ( defined $r->param('txtCustomGreeting')    ? (strCustomGreeting    => $r->param('txtCustomGreeting')) : () ),
    ( defined $r->param('ddmUserType')          ? (chrType              => $r->param('ddmUserType')) : () ),
    ( defined $r->param('rdbChangePassword')    ? (ysnChangePassword    => $r->param('rdbChangePassword')) : () ),
    ( defined $r->param('rdbMailingList')       ? (ysnMailingList       => $r->param('rdbMailingList')) : () ),
    ( defined $r->param('rdbAccountActivation') ? (ysnAccountActivation => $r->param('rdbAccountActivation')) : () ),
    ( defined $r->param('rdbAdministrator')     ? (ysnAdministrator     => $r->param('rdbAdministrator')) : () ),
    ( defined $r->param('address1')     		? ( address1     		 => $r->param('address1') ) : () ),
    ( defined $r->param('address2')     		? ( address2     		 => $r->param('address2') ) : () ),
    ( defined $r->param('cubicle')     			? ( cubicle     		 => $r->param('cubicle') ) : () ),
    ( defined $r->param('city')     			? ( city     		 	 => $r->param('city') ) : () ),
    ( defined $r->param('state')     			? ( state     		 	 => $r->param('state') ) : () ),
    ( defined $r->param('country')     			? ( country     		 => $r->param('country') ) : () ),
    ( defined $r->param('postalcode')     		? ( postalcode     		 => $r->param('postalcode') ) : () ),
    ( $pass ? ( strPassword => misc::escape( $crypt->encrypt($pass) ) ) : () ),
    ( defined $email              				? (strEmail             => $email ) : () ),
  );

  my $user = openprint::User->find_one(email=>openprint::User->transform(email=> $email));
  # Send a notification if the user's account has been (en|dis)abled.
  $user->notify_activation_change() if defined $r->param('rdbAccountActivation') and $r->param('rdbAccountActivation') eq 'Y';

  return OK;
}

# Remove the user.
sub delete {
    my ($r, $log, $dbh, $user_id, $variable) = @_;

    my $admin_count = scalar $dbh->selectrow_array(q{
        SELECT count(*)
        FROM tbl_customer_users
        WHERE ysnAdministrator = 'Y' 
          AND lngcustomerid = ( SELECT lngcustomerid
                                FROM tbl_customer_users 
                                WHERE lnguserid = ? )
    }, undef, $user_id);

    my $admin = scalar $dbh->selectrow_array(q{
        SELECT ysnAdministrator FROM tbl_customer_users WHERE lnguserid = ?
    }, undef, $user_id);

    if (( $admin ne 'Y') || ($admin_count >1)){
        $dbh->do('DELETE FROM tbl_Help_Desk WHERE lngUserIndex = ?',   undef, $user_id);
        $dbh->do('DELETE FROM tbl_Customer_Users WHERE lngUserID = ?', undef, $user_id);

        my $admin_id = scalar $dbh->selectrow_array(q{
            SELECT lnguserid
            FROM tbl_customer_users
            WHERE chrType = 'A'
            ORDER BY dtmdateentered
        });
        sql::update($log, $dbh, 'tbl_projects', "lnguserindex = $user_id", 
            lnguserindex => $admin_id
        );
     }
     else {
        return misc::error($log, $dbh, $variable, "Must have an administrator ", "You can not remove the last administrator.") 
            if $admin_count == 1;
    }
}

# Throw the user information into $variable.
sub load {
    my ($log, $dbh, $user_id, $variable) = @_;
    
    return unless $user_id; 

    my $sth = $dbh->prepare(q{
        SELECT strEmail,             strPassword,      strTitle, 
               strFirstName,         strLastName,      strSalutation,     
               strPhone,             strExt,           strFax,
               ysnChangePassword,    chrType,          ysnMailingList, 
               lngCustomerID,        dblCommission,    strCustomGreeting, 
               ysnAccountActivation, ysnAdministrator, notify_manager_order,
               notify_manager_file,	 address1,			address2,
				cubicle,			city,				state,
				country,			postalcode, editproject
        FROM tbl_Customer_Users
        WHERE lngUserID = ?
    });

    @$variable{qw( 
        txtEmail            txtPassword 	txtTitle            
		txtFirstName 		txtLastName     rdbSalutation
        txtPhone            txtExtension    txtFax
		rdbChangePassword   UserType        rdbMailingList
        CustomerIndex       txtCommission   txtCustomGreeting
		AccountActivation   rdbAdministrator notify_manager_order
        notify_manager_file	address1 		address2
		cubicle 			city			state
		country				postalcode	editproject
    )} = $dbh->selectrow_array($sth, undef, $user_id);

    my $crypt = crypto::get_crypt($log, $dbh);
	

# This is crazy, fixes decrypt issues on n2.
	my $y;
	my $t = $variable->{txtPassword};

	map { $y .= substr($t, $_, 1); } (0..length($t)-1);

    $variable->{txtPassword} = $crypt->decrypt(misc::unescape($y));

#    $variable->{txtPassword} 
#        = $crypt->decrypt(misc::unescape($variable->{txtPassword}));
}

# Get the next user by id TODO Should probably be by name as the user profile
# page is done that way. NOTE: Gah! What a mess.
sub get_next {
    my ($log, $dbh, $cust_id, $user_id, $type) = @_;

    my $sql = qq{
        SELECT MIN(lngUserID)
        FROM tbl_Customer_Users
        WHERE lnguserid > $user_id
    };
    
    $sql .= " AND lngCustomerID = $cust_id " if $cust_id;
    $sql .= " AND chrType       = '$type'"   if $type;

    my $id = scalar $dbh->selectrow_array($sql);

    if ($id) {
        my $sql = qq{
            SELECT MAX(lngUserID)
            FROM tbl_Customer_Users 
            WHERE 1>0 
        };
        $sql .= " AND lngCustomerID = $cust_id" if $cust_id;
        $sql .= " AND chrType       = '$type'"  if $type;

        $id = scalar $dbh->selectrow_array($sql);
    }

    return $id;
}

# TODO Should probably be by name as the user profile
# page is done that way.
sub get_prev {
    my ($log, $dbh, $cust_id, $user_id, $type) = @_;

    my $sql = qq{
        SELECT MAX(lngUserID)
        FROM tbl_Customer_Users
        WHERE lngCustomerID = $cust_id
          AND lngUserID     < $user_id
    };
    $sql .= " AND chrType = '$type'" if $type;

    my $id = scalar $dbh->selectrow_array($sql);
    
    if ($id) {
        my $sql = qq{
            SELECT MIN(lngUserID)
            FROM tbl_Customer_Users 
            WHERE 1>0
        };
        $sql .= "AND lngCustomerID = $cust_id" if $cust_id;
        $sql .= "AND chrType       = '$type'"  if $type;

        $id = scalar $dbh->selectrow_array($sql);
    }

    return $id;
}


# If the new (given) user type is different than the exisiting notify the user
# (email) of the change.
sub notify_usertype_change {
    my ($r, $log, $dbh, $user_id, $user_type) = @_;

    my $old_type = $dbh->selectrow_array(q{
        SELECT chrType FROM tbl_Customer_Users WHERE lngUserID = ?
    }, undef, $user_id);

    # Don't notify unless the usertype has changed.
    return 0 unless $user_type ne $old_type;

    my %info = (
        siteURL              => "http://" . $r->hostname,
        SecureSiteURL        => "https://" . $r->hostname,
        CustomerServiceEmail => configuration::get_value($log, $dbh, 'CustomerServiceEmail'),
    );

    my $file = $user_type eq 'R' ? 'usertype_reseller_notification.html'
             : $user_type eq 'S' ? 'usertype_supplier_notification.html'
             : $user_type eq 'A' ? 'usertype_administrator_notification.html'
             : $user_type eq 'C' ? 'usertype_customer_notification.html'
             : $user_type eq 'E' ? 'usertype_employee_notification.html'
             :                     undef;

    die "Unknown user type" unless $file;

    $info{ReplacementText} 
        = qq{ <!--#include virtual="/email/content/$file"--> };

    my $email_template = misc::load_file($r, '/email/email_template.html');
       $email_template = ssi::variable_substitution($r, $log, $dbh, $email_template, \%info);

    my %mail = (
        SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
        FROM    => configuration::get_value($log, $dbh, 'AdministratorEmail'),
        TO      => $r->param('txtEmail'),
        SUBJECT => "User type has changed!"
    );
    misc::send_email_with_attachment($r, $log, \%mail, ( '', encode_qp($email_template), 'text/html', 'quoted-printable' ) );

    return 1;
}

# Notify the user if their account activation changes.
sub notify_activation_change {
    my ($r, $log, $dbh, $user_id, $is_active) = @_;
    
    my $was_active = $dbh->selectrow_array(q{
        SELECT ysnAccountActivation FROM tbl_Customer_Users WHERE lngUserID = ?
    }, undef, $user_id);

    # Don't notify unless there has been a status change.
    return 0 unless $was_active ne $is_active;

    my %info = (
        siteURL              => "http://" . $r->hostname,
        SecureSiteURL        => "http://" . $r->hostname,
        CustomerServiceEmail => configuration::get_value($log, $dbh, 'CustomerServiceEmail'),
    );

    my $file = $r->param('rdbAccountActivation') eq 'Y' 
        ? 'user_account_activated.html' 
        : 'user_account_deactivated.html';

    $info{'ReplacementText'} = "<!--#include virtual=\"/email/content/$file\"-->";

    my $email_template = misc::load_file($r, '/email/email_template.html');
       $email_template = ssi::variable_substitution( $r, $log, $dbh, $email_template, \%info );

    my %mail = (
        SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
        FROM    => configuration::get_value( $log, $dbh, 'AdministratorEmail'),
        TO      => $r->param('txtEmail'),
        SUBJECT => "User account status has changed!"
    );
    misc::send_email_with_attachment($r, $log, \%mail, ( '', encode_qp($email_template), 'text/html', 'quoted-printable' ) );

    return 1;
}

sub notify_manager {
    my ($r, $log, $dbh, $user_id, $action, $option) = @_;

    die "Managerial notification needs either content or a template"
        unless exists $option->{content} || exists $option->{template};

    $option->{subject} = 'Managerial Notification' unless $option->{subject};

    # Get the manager of the current user, it there aren't any we're done.
    my $managers = $dbh->selectcol_arrayref(q{
        SELECT stremail 
        FROM tbl_customer_users c, user_manager m
        WHERE c.lnguserid = m.manager_id
          AND m.user_id   = ?
    }, undef, $user_id);

    return unless @$managers;

    # See if the manager(s) want to receive notification for this action.
    my $actions = $dbh->selectrow_hashref(q{
        SELECT notify_manager_file  AS file,
               notify_manager_order AS order
        FROM tbl_customer_users
        WHERE lnguserid = ?
    }, undef, $user_id);

    warn("Invalid action ($action) for managerial notification") 
        unless exists $actions->{ $action };

    return unless $actions->{ $action };

    # Provide at least the username to the email template.
    $option->{info}{username} = $dbh->selectrow_array(q{
        SELECT strfirstname || ' ' || strlastname 
        FROM tbl_customer_users 
        WHERE lnguserid = ?
    }, undef, $user_id);

    # Either direct text can be given or a template piece filename.
    # 'ReplacementText' is a populated variable in the main email template.
    $option->{info}{ReplacementText} = exists $option->{content} 
        ? $option->{content}
        : "<!--#include virtual=\"/email/content/$option->{template}\"-->";

    # We also need the base href for the email.
    $option->{info}{siteURL} = "http://" . $r->hostname;

    my $email_template = misc::load_file($r, '/email/email_template.html');
       $email_template = ssi::variable_substitution($r, $log, $dbh, $email_template, $option->{info});

    my %mail = (
        SMTP       => configuration::get_value( $log, $dbh, 'Mail Server'),
        FROM       => configuration::get_value( $log, $dbh, 'FileUploadEmail'),
        TO         => join(',', @{$managers}),
        SUBJECT    => "[PQS] $option->{subject}",
    );

    misc::send_email_with_attachment($r, $log, \%mail, 
        ( '', encode_qp($email_template), 'text/html', 'quoted-printable' ) 
    );

    return 1;
}

1;
