package eprint::support;
use strict;

use Apache2::Const qw(OK);
use Apache2::RequestUtil ();
use MIME::QuotedPrint;
use Mail::Sendmail;
use sql ();

use HTTP::Request::Common qw(POST); 
use LWP::UserAgent;

sub rma {
    my ($r, $log, $dbh, $variable) = @_;

# Remove revision # from order id.
    my ($order_id) = $r->param('txtOrderID') =~ /(\d*)/;
    my  $prod_id   = $r->param('txtProductID');

print STDERR "HAVE MY ORDERID: $order_id \n";
    
    $_ = "SELECT lngOrderID, lngCustomerID FROM tbl_Orders WHERE lngOrderID='$order_id'";
    my ( $check_order_id, $check_cust_id ) = sql::sql_statement( $log, $dbh, $_ ) if $order_id;
    if ( $check_order_id eq '' ) {
        return misc::error( $log, $dbh, $variable, 'Error','Invalid Order ID' );
    } elsif ( $check_cust_id != $variable->{cust_id} ) {
        return misc::error( $log, $dbh, $variable, 'Error','You are not the owner of that order.' );
    }

    $_ = "SELECT lngProjectIndex FROM tbl_Order_Contents WHERE lngOrderID='$order_id' AND lngProjectIndex='$prod_id'";
    if ( ! sql::sql_statement( $log, $dbh, $_ ) ) {
        return misc::error( $log, $dbh, $variable, 'Error',"Order $order_id does not contain project $prod_id" );
    }
    
    my ( $rma_id ) = sql::sql_statement( $log, $dbh, "SELECT nextval('RMA_Index_seq')" );
    
    sql::insert( $log, $dbh, 'tbl_RMA',
        lngIndex           => $rma_id,
        lngProjectIndex    => $prod_id,
        lngCustomerIndex   => $variable->{cust_id},
        lngUserIndex       => $variable->{user_id},
        lngOrderID         => $order_id,
        chrRMAType         => $r->param('rdbRMAType'),
        strDescription     => $r->param('txtDescription'),
        ysnApprove         => 'NULL',
        dtmRequestDate     => 'NOW()',
    );

    my %info;
    $_ = "SELECT strSalutation, strFirstName, strLastName, strEmail FROM tbl_Orders WHERE lngOrderID = '$order_id'";
    @info{'Salutation','FirstName','LastName','Email'} = sql::sql_statement( $log, $dbh, $_ );

    $info{ProjectIndex} = $prod_id;
    $_ = "SELECT strProjectReference FROM tbl_PRojects WHERE lngProjectIndex='$prod_id'";
    @info{ProjectReference} = sql::sql_statement( $log, $dbh, $_ );
    $info{OrderID} = $order_id;
    $info{RMAType} = ( $r->param('rdbRMAType') eq 'C' ? 'Credit' : 'Reproduction' );
    $info{Description} = $r->param('txtDescription');
    $info{RMAIndex} = $rma_id;
    $info{siteURL} = "http://" . $r->hostname;
    $info{SecureSiteURL} = "https://" . $r->hostname;


    my $template = misc::load_file($r, '/email/content/rma_notification.html');
    $template = ssi::variable_substitution( $r, $log, $dbh, $template, \%info );

    my %mail = (
            SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
            FROM    => configuration::get_value($log, $dbh, 'RMAEmail'),
            TO      => configuration::get_value($log, $dbh, 'RMAEmail'),
            SUBJECT => 'Order Return Request'
            );
    misc::send_email_with_attachment($r, $log, \%mail, ( '', encode_qp($template), 'text/html', 'quoted-printable' ) );

    my $email_template = misc::load_file($r, '/email/email_template.html');
    $info{ReplacementText} = "<!--#include virtual=\"/email/content/rma_confirmation.html\"-->";
    $email_template = ssi::variable_substitution( $r, $log, $dbh, $email_template, \%info );

    my %mail = (
        SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
        TO      => $info{Email},
        FROM    => configuration::get_value($log, $dbh, 'RMAEmail'),
        SUBJECT => 'Order Return Request'
    );
    misc::send_email_with_attachment($r, $log, \%mail, ( '', encode_qp($email_template), 'text/html', 'quoted-printable' ) );
}

sub helpdesk {
    my ( $r, $log, $dbh, $variable ) = @_;


    my $error = '';
#    $error .= 'Missing First Name<br>' if $r->param('txtFirstName')  eq '';
#    $error .= 'Missing Last Name<br>'  if $r->param('txtLastName')   eq '';
#    $error .= 'Missing Address<br>'    if $r->param('txtAddress1')   eq '';
#    $error .= 'Missing City<br>'       if $r->param('txtCity')       eq '';

#    $r->param('ddmStateProvince' => $r->param('txtOtherStateProv') ) 
#                if $r->param('ddmStateProvince') eq '';

#    $error .= 'Missing Postal Code<br>' if $r->param('txtPostalCode') eq '';
#    $r->param('ddmCountry' => $r->param('txtOtherCountry') ) if $r->param('ddmCountry') eq '';
#    $error .= 'Missing Phone<br>' if $r->param('txtPhone') eq '';
#    $error .= 'Missing/Invalid E-mail<br>' if $r->param('txtEmail') eq '';
#    $error .= 'Missing Question or Comment<br>' if $r->param('txtQuestion-Quote') eq '';

    if ( $error ) {
        return misc::error( $log, $dbh, $variable, 'Bad Field', $error );
    }


	unless ( $variable->{user_id} ) {
		my $ua = LWP::UserAgent->new();  

   		my $response  = $r->param('g-recaptcha-response');
		my $key = configuration::get_value($log, $dbh, 'reCAPTCHA_key');

		my $req = POST 'https://www.google.com/recaptcha/api/siteverify', [ secret => $key, response => $response, remoteip => $ENV{'REMOTE_ADDR'} ]; 

		my $result = $ua->request($req)->content;
		   $result =~ /success": (.*)/;
		my $valid = $1;

		if ( $valid eq 'true' ) {
		} else {
			# Error
			return misc::error( $log, $dbh, $variable, 'Bad Field', 'Your Captcha is incorrect. Please press the back button to try again' );
		}
	}


	my $index = $r->param('HelpDeskIndex');

	my %info;
	my $i = \%info;
    @$i{qw( title first_name last_name salutation 
                   company_name address address_two city 
                   province postal_code country 
                   phone extension fax email
      )} = $dbh->selectrow_array(q{
        SELECT u.strTitle, u.strFirstName, u.strLastName, u.strSalutation,
               c.strCompanyName, u.Address1, u.Address2, u.City, 
               u.state, u.postalcode, u.Country, 
               u.strPhone, u.strExt, u.strFax, u.strEmail
         FROM tbl_Customer c, tbl_Customer_Users u
         WHERE c.lngCustomerID = ?
           AND u.lngUserID     = ?
    }, undef, @$variable{qw(cust_id user_id)}) if $variable->{user_id};

	$info{HelpDeskIndex} = $index;

	unless ($index ) {

		( $index ) = sql::sql_statement( $log, $dbh, "SELECT nextval('HelpDeskIndex_seq')");
		if ( $index eq '' ) {
			return misc::error( $log, $dbh, $variable, 'System Error', 'Unable to create helpdesk entry.' );
		}
		
		sql::insert($log, $dbh, 'tbl_Help_Desk',
			lngIndex         => $index,
			lngCustomerIndex => $variable->{cust_id},
			lngUserIndex     => $variable->{user_id},
			blbQuestion      => $r->param('txtQuestion-Quote') || undef,
			dtmRequestDate   => 'NOW()',
			chrMethod        => $r->param('rdbMethod') || 'E', 
			strCompanyName   => $info{company_name},
			strFirstName   	 => $info{first_name},
			strLastName      => $info{last_name},
			strPhone   		 => $info{phone},
			strEmail   		 => $info{email},
		);
	}



	
	

	if ( $r->param('AddNew') ) {
		my $ins = $dbh->prepare(qq{ INSERT INTO helpdesk_specs VALUES ( ?,?,?,?)});
		my $req = $dbh->selectrow_array(q{
			SELECT request FROM tbl_help_desk WHERE lngIndex = ?
		}, undef, $index);

		$req++;
		foreach my $key ( $r->param() ) {
			$info{$key} = $r->param($key);
			$ins->execute($index, $req, $key, $r->param($key));

		}

		$dbh->do(q{UPDATE tbl_help_desk SET request = ? WHERE lngindex = ?}, undef, $req, $index);
	
		$variable->{Redirect} = "/main/support/support_help_desk.html?HelpDeskIndex=$index";
		return;
	} else {
		foreach my $key ( $r->param() ) {
			$info{$key} = $r->param($key);

		}
	}

# **** Get Data for multipe requests

	my $data = $dbh->selectall_arrayref(q{
		SELECT * from helpdesk_specs WHERE id = ? 
	}, {Slice=>{}}, $index);;	
	my @req;
	map { $req[$_->{req}-1]->{$_->{name}} = $_->{value} } @{$data};

	$info{DATA} = \@req;
print STDERR "HAVE DATA: " , Dumper(\%info);
# **********************************


    $info{siteURL} = "http://" . $r->hostname;
    $info{SecureSiteURL} = "https://" . $r->hostname;
    
    my $template = misc::load_file($r, '/email/content/helpdesk_notification.html');
    $template = ssi::variable_substitution( $r, $log, $dbh, $template, \%info );

    my %mail = (
        SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
        FROM    => configuration::get_value($log, $dbh, 'HelpdeskEmail'),
        TO      => configuration::get_value($log, $dbh, 'HelpdeskEmail'),
        SUBJECT => 'Online Helpdesk Submission.'
    );
    misc::send_email_with_attachment($r, $log, \%mail, ( '', encode_qp($template), 'text/html', 'quoted-printable' ) );

    my $email_template = misc::load_file($r, '/email/email_template.html');
    $info{ReplacementText} = "<!--#include virtual=\"/email/content/helpdesk_confirmation.html\"-->";
    $email_template = ssi::variable_substitution( $r, $log, $dbh, $email_template, \%info );

    my %mail = (
        SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
        TO      => $info{email},
        FROM    => configuration::get_value($log, $dbh, 'HelpdeskEmail'),
        SUBJECT => 'Online Helpdesk Submission.'
    );
    misc::send_email_with_attachment($r, $log, \%mail, ( '', encode_qp($email_template), 'text/html', 'quoted-printable' ) );

    $variable->{index} = $index;

	my $path = $r->dir_config('site_specific')
		|| $r->document_root.'/site_specific/';
	$path .= "/customers/uploads/$index";
	
	mkdir $path or die "Could not make directory: $path";

    use eprint::project_files;
    for my $upload ($r->upload) {
        my $filename = $upload->filename;
        next unless $filename;

        eprint::project_files::save_upload($upload->fh, "$path", $filename);
    }

}

sub generic_form {
    my ( $r, $log, $dbh, $variable ) = @_;

    my $error = '';

    my %info = (); 

    my $data = '';
    foreach my $key ( $r->param() ) {
        $info{$key} = $r->param($key);
        $data .= $key . ' - ' . $info{$key} . '<br>';
    }
    $info{DATA} = $data;

    
    #my $template = misc::load_file($r, '/email/content/helpdesk_notification.html');
    my $template = misc::load_file($r, $info{ContentFile} );

    $template = ssi::variable_substitution( $r, $log, $dbh, $template, \%info );

    my %mail = (
        SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
        FROM    => $info{txtEmailFrom},
        TO      => $info{txtEmailTo},
        SUBJECT => $info{txtEmailSubject},
    );
    misc::send_email_with_attachment($r, $log, \%mail, ( '', encode_qp($template), 'text/html', 'quoted-printable' ) );

}

sub userinfo {
    my ($r, $log, $dbh, $variable) = @_;
my $index = $r->param('HelpDeskIndex');
print STDERR "HELP DESK INDEX: $index \n";
	map { print STDERR "PARAMS: $_ = " . $r->param($_) . "\n"; } $r->param();

    @$variable{qw( title first_name last_name salutation 
                   company_name address address_two city 
                   province postal_code country 
                   phone extension fax email
      )} = $dbh->selectrow_array(q{
        SELECT u.strTitle, u.strFirstName, u.strLastName, u.strSalutation,
               c.strCompanyName, u.Address1, u.Address2, u.City, 
               u.state, u.postalcode, u.Country, 
               u.strPhone, u.strExt, u.strFax, u.strEmail
         FROM tbl_Customer c, tbl_Customer_Users u
         WHERE c.lngCustomerID = ?
           AND u.lngUserID     = ?
    }, undef, @$variable{qw(cust_id user_id)}) if $variable->{user_id};

    $variable->{ $variable->{salutation} } = 'checked="checked"';

    $variable->{state}   = ssi::return_states_and_provinces($variable->{province});
    $variable->{country} = ssi::return_countries($variable->{country});


	my $data = $dbh->selectall_arrayref(q{
		SELECT * from helpdesk_specs WHERE id = ? 
	}, {Slice=>{}}, $index);;	
	my @req;
	map { $req[$_->{req}-1]->{$_->{name}} = $_->{value} } @{$data};

	$variable->{DATA} = \@req;

	$variable->{HelpDeskIndex} = $index;
use Data::Dumper;
print STDERR "HAVE SPECS: ", Dumper(\@req);

    return OK;
}

1;

