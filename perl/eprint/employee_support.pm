package eprint::employee_support;

use Mail::Sendmail;
use MIME::QuotedPrint;
use Apache2::RequestUtil ();
use strict;

use sql ();
require misc;

sub helpdesk {
	my ( $r, $log, $dbh, $variable ) = @_;

	my $index = $r->param('HelpDeskIndex');
	$index = $r->param('helpdesk_id') unless $index;



	my $data = $dbh->selectall_arrayref(q{
		SELECT * from helpdesk_specs WHERE id = ? 
	}, {Slice=>{}}, $index);;	
	my @req;
	map { $req[$_->{req}-1]->{$_->{name}} = $_->{value} } @{$data};

	$variable->{DATA} = \@req;

print STDERR "HAVE DATA: " , Dumper($variable);


	if ( $r->param('btnFunction') eq 'Submit' ) {
		sql::update( $log, $dbh, 'tbl_Help_Desk', "lngIndex = '$index'", 
			'ysnReviewed',	$r->param('rdbReviewed'),
			'blbResponse',	$r->param('txtQuestion-Quote')
		);
		$_ = "SELECT tbl_Customer_Users.strFirstName || ' ' || tbl_Customer_Users.strLastName, tbl_Customer_Users.strEmail\n".
			"FROM tbl_Help_Desk,tbl_Customer_Users WHERE tbl_Help_Desk.lngIndex = '$index'\n".
			"AND tbl_Customer_Users.lnguserid=lngUserIndex\n";

		my ($name, $email) = sql::sql_statement( $log, $dbh, $_);

		my %info;
		$_ = "SELECT to_char(dtmRequestDate,'MM/DD/YYYY'), blbquestion,blbResponse 
              FROM tbl_Help_Desk WHERE lngIndex='$index'";

		$info{'RequestDate','Question', 'Response'} = sql::sql_statement( $log, $dbh, $_);

        if ( $r->param('rdbReviewed') eq 'Y' ) {
		    my $email_template = misc::load_file($r, '/email/email_template.html');
		    $info{'ReplacementText'} = "<!--#include virtual=\"/email/content/helpdesk_response.html\"-->";
		    $email_template = ssi::variable_substitution( $r, $log, $dbh, $email_template, \%info );

		    my %mail = (
			    SMTP	=> configuration::get_value($log, $dbh,'Mail Server'),
			    FROM	=> configuration::get_value($log, $dbh,'HelpdeskEmail'),
			    TO		=> $email,
			    SUBJECT	=> 'Your help desk submission has been reviewed.',
		    );
		    $$variable{'Redirect'} = "employee/support/helpdesk_search.html";
		    misc::send_email_with_attachment($r, $log, \%mail, 
                ( '', encode_qp($email_template), 'text/html', 'quoted-printable' ) );
        }
	} # end if

	$_ = "SELECT strCompanyName,    strTitle,       strFirstName,       strLastName, 
                 strAddress,        strAddress2,    strCity,            strStateProv, 
                 strPostalCode,     strCountry,     strPhone,           strExtension, 
                 strEmail,          blbQuestion,    chrMethod,          ysnReviewed, 
                 blbResponse,       to_char(dtmRequestDate,'MM/DD/YYYY')
		  FROM tbl_Help_Desk WHERE lngIndex = '$index'";

	@$variable{ 'company_name',     'title',        'first_name',   'last_name', 
                'address_one',      'address_two',  'city',         'state', 
                'postal_code',      'country',      'phone',        'extension', 
                'email',            'question',     'method',       'rdbReviewed', 
                'response',         'sub_date' 
    } = sql::sql_statement( $log, $dbh, $_) if $index;

	my $data = $dbh->selectall_hashref(q{
		SELECT * FROM helpdesk_specs WHERE id = ?
	}, 'name',{}, $index);

	map { $variable->{$_} = $data->{$_}{value} } keys %{$data};

use Data::Dumper;
print STDERR "HERE is my Data: ", Dumper($data, $variable);


	$$variable{'response_type'} = "Email" if $$variable{'method'} eq 'E';
	$$variable{'response_type'} = "Phone" if $$variable{'method'} eq 'P';

	$$variable{'rdbReviewed'.$$variable{'rdbReviewed'}} = 'CHECKED';
	$$variable{'HelpdeskIndex'} = $index;

    use eprint::project_files;

        my $path = $r->dir_config('site_specific')
            || $r->document_root.'/site_specific/';

        $path .= "customers/uploads/$index";

    $variable->{index} = $index;

    #opendir my $dirhandle, $path or die "Couldn't open project directory ($path): $!";
    opendir my $dirhandle, $path or warn "Couldn't open project directory ($path): $!";
    
	
    my @files;
    while (my $name = readdir($dirhandle)) {
        next if substr($name, 0, 1) eq '.';
        push @files, { name => $name };
    }
    $variable->{uploaded_files} = \@files;
    
} # end sub helpdesk

sub rma {
	my ( $r, $log, $dbh, $variable ) = @_;
	
	my $rma = $r->param('rma_id');


	$_ = "SELECT lngCustomerIndex, (SELECT strCompanyName FROM tbl_Customer WHERE lngCustomerID=lngCustomerIndex),\n".
		"to_char(dtmRequestDate,'MM/DD/YYYY'), chrRMAType, strDescription, ysnApprove, txtComments,strRMANumber,\n".
		"lngOrderID, (SELECT dtmOrderDate FROM tbl_Orders WHERE tbl_Orders.lngOrderID=tbl_RMA.lngOrderID),\n".
		"lngProjectIndex, (SELECT strProjectReference FROM tbl_Projects WHERE tbl_Projects.lngProjectIndex=tbl_RMA.lngProjectIndex)\n".
		"FROM tbl_RMA WHERE lngIndex='$rma'";
	@$variable{'CustomerIndex', 'CompanyName', 
		'RequestDate', 'RMAType','Problem','Verdict','txtAdminComments','RMANumber',
		'OrderID', 'OrderDate',
		'ProjectIndex','ProjectReference'
	} = sql::sql_statement( $log, $dbh, $_ );


	$$variable{'rmatype'} = 'Credit' if $$variable{'RMAType'} eq 'C';
	$$variable{'rmatype'} = 'Reproduction' if $$variable{'RMAType'} eq 'R';
	$$variable{'rmatype'} = 'Service' if $$variable{'RMAType'} eq 'S';

	$$variable{'rdbVerdict'.$$variable{'Verdict'}} = 'CHECKED';

	$$variable{'RMAIndex'} = $rma;
} # end sub rma

sub helpdesk_search {
	my ( $r, $log, $dbh, $variable ) = @_;
	if ( $r->param('btnFunction') eq 'Submit' ) {
		my $index = $r->param('HelpdeskIndex');
		sql::update( $log, $dbh, 'tbl_Help_Desk', "lngIndex = '$index'", 
			'ysnReviewed',	$r->param('rdbReviewed'),
			'blbResponse',	$r->param('txtQuestion-Quote')
		);
		$_ = "SELECT tbl_Customer_Users.strFirstName || ' ' || tbl_Customer_Users.strLastName, tbl_Customer_Users.strEmail\n".
			"FROM tbl_Help_Desk,tbl_Customer_Users WHERE tbl_Help_Desk.lngIndex = '$index'\n".
			"AND tbl_Customer_Users.lnguserid=lngUserIndex\n";

		my ($name, $email) = sql::sql_statement( $log, $dbh, $_);

		my %info;
		$_ = "SELECT to_char(dtmRequestDate,'MM/DD/YYYY'), blbquestion,blbResponse FROM tbl_Help_Desk WHERE lngIndex='$index'";
		@info{'RequestDate','Question', 'Response'} = sql::sql_statement( $log, $dbh, $_);

		my $data = $dbh->selectall_arrayref(q{
			SELECT * from helpdesk_specs WHERE id = ? 
		}, {Slice=>{}}, $index);;	
		my @req;
		map { $req[$_->{req}-1]->{$_->{name}} = $_->{value} } @{$data};

		$info{DATA} = \@req;
print STDERR "INFO DATA: ", Dumper(\%info);

        if ( $r->param('rdbReviewed') eq 'Y' ) {
		my $email_template = misc::load_file($r, '/email/email_template.html');
		$info{'ReplacementText'} = "<!--#include virtual=\"/email/content/helpdesk_response.html\"-->";
		$email_template = ssi::variable_substitution( $r, $log, $dbh, $email_template, \%info );

		my %mail = (
			SMTP	=> configuration::get_value($log, $dbh,'Mail Server'),
			FROM	=> $r->param('reply-email') || configuration::get_value($log, $dbh,'HelpdeskEmail'),
			TO		=> $email,
			SUBJECT	=> 'Your help desk submission has been reviewed.',
		);
		misc::send_email_with_attachment($r, $log, \%mail, ( '', encode_qp($email_template), 'text/html', 'quoted-printable' ) );
        }

        my $path = $r->dir_config('site_specific')
            || $r->document_root.'/site_specific/';
        $path .= "customers/uploads/$index";

        foreach my $p ( $r->param() ) {
            if ( $p =~ m/del_(.*)/ ) {
                print STDERR "DELETE FILES $1 \n";
                unlink "$path/$1" or die "Could not delete file: $!";
            }

        }

	} # end if


	ssi::get_start_end_dates( $log, $dbh, $variable, 
			$r->param('ddmStartYear'),
			$r->param('ddmStartMonth'),
			$r->param('ddmStartDay'),
			$r->param('ddmEndYear'),
			$r->param('ddmEndMonth'),
			$r->param('ddmEndDay') );

	$_ = "SELECT lngCustomerID, strCompanyName FROM tbl_Customer ORDER BY lower(strCompanyName)";
	$$variable{'ddmCustomers'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmCustomers') );

	$_ = "SELECT lngIndex, strFirstName || ' ' || strLastName,\n".
			"date(dtmRequestDate), strCompanyName, ysnReviewed\n".
		"FROM tbl_Help_Desk\n";
	$_ .= "WHERE date(dtmRequestDate) BETWEEN date('$$variable{'StartDate'}') AND date('$$variable{'EndDate'}')\n";# if $r->param('ddmStartYear');
	$_ .= "AND ysnReviewed = '".$r->param('ddmReviewed')."'\n" if $r->param('ddmReviewed');
	$_ .= "AND lngCustomerIndex = '".$r->param('ddmCustomers')."'\n" if $r->param('ddmCustomers');
	$_ .= "ORDER BY lngIndex";
	@{$$variable{'HELPDESKENTRIES'}} = sql::sql_statement( $log, $dbh, $_ );

	$$variable{'ddmReviewed'.$r->param('ddmReviewed')} = 'SELECTED';

} # end sub helpdesk_search

sub rma_search {
	my ( $r, $log, $dbh, $variable ) = @_;

	if ( $r->param('btnFunction') eq 'Send' ) {
		my $rma = $r->param('rma_id');
		sql::update( $log, $dbh, 'tbl_RMA', "lngIndex = '$rma'",
			'ysnApprove',	$r->param('rdbVerdict'),
			'strRMANumber',	$r->param('RMANumber'),
			'txtComments',	$r->param('txtAdminComments'),
		);

		my %info;
		$_ = "SELECT (SELECT strCompanyName FROM tbl_Customer WHERE lngCustomerID=lngCustomerIndex),\n".
			"(SELECT strSalutation || '' || strFirstName || ' ' || strLastName FROM tbl_Customer_Users WHERE lngUserID=lngUserIndex),\n".
			"(SELECT strEmail FROM tbl_Customer_Users WHERE lngUserID=lngUserIndex),\n".
			"to_char(dtmRequestDate,'MM/DD/YYYY'), chrRMAType, strDescription, ysnApprove, txtComments, strRMANumber,\n".
			"lngOrderID, (SELECT dtmOrderDate FROM tbl_Orders WHERE tbl_Orders.lngOrderID=tbl_RMA.lngOrderID),\n".
			"lngProjectIndex, (SELECT strProjectReference FROM tbl_Projects WHERE tbl_Projects.lngProjectIndex=tbl_RMA.lngProjectIndex)\n".
			"FROM tbl_RMA WHERE lngIndex='$rma'";
		@info{'CompanyName', 'UserName','Email',
			'RequestDate', 'RMAType','Problem','Verdict','txtAdminComments','RMANumber',
			'OrderID', 'OrderDate',
			'ProjectIndex','ProjectReference'
		} = sql::sql_statement( $log, $dbh, $_ );
		$info{'siteURL'} = "http://" . $r->hostname;

		my $email_template = misc::load_file($r, '/email/email_template.html');
		$info{'ReplacementText'} = "<!--#include virtual=\"/email/content/rma_response.html\"-->";
		$email_template = ssi::variable_substitution( $r, $log, $dbh, $email_template, \%info );

		my %mail = (
				SMTP	=> configuration::get_value($log, $dbh,'Mail Server'),
				FROM	=> configuration::get_value($log, $dbh,'RMAEmail'),
				TO		=> $info{'Email'},
				SUBJECT	=> 'Your RMA has been reviewed.'
		);
		misc::send_email_with_attachment($r, $log, \%mail, ( '', encode_qp($email_template), 'text/html', 'quoted-printable' ) );

	} # end if
	ssi::get_start_end_dates( $log, $dbh, $variable, 
			$r->param('ddmStartYear'),
			$r->param('ddmStartMonth'),
			$r->param('ddmStartDay'),
			$r->param('ddmEndYear'),
			$r->param('ddmEndMonth'),
			$r->param('ddmEndDay') );

	$_ = "SELECT lngCustomerID, strCompanyName FROM tbl_Customer ORDER BY lower(strCompanyName)";
	$$variable{'ddmCustomers'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmCustomers') );

	$_ = "SELECT lngIndex, (SELECT strCompanyName FROM tbl_Customer WHERE lngCustomerID=lngCustomerIndex), lngOrderID, to_char(dtmRequestDate,'MM/DD/YYYY'), ysnApprove FROM tbl_RMA\n";
	$_ .= "WHERE date(dtmRequestDate) BETWEEN date('$$variable{'StartDate'}') AND date('$$variable{'EndDate'}')\n";
	$_ .= "AND ysnReviewed = '".$r->param('ddmReviewed')."'\n" if $r->param('ddmReviewed');
	$_ .= "AND lngCustomerIndex = '".$r->param('ddmCustomers')."'\n" if $r->param('ddmCustomers');
	$_ .= "ORDER BY lngIndex";
	@{$$variable{'RMAS'}} = sql::sql_statement( $log, $dbh, $_ );

	$$variable{'ddmReviewed'.$r->param('ddmReviewed')} = 'SELECTED';

} # end sub rma_search 


1;

__END__

