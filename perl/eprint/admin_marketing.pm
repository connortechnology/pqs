package eprint::admin_marketing;
use strict;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY); # Offers OK, Error, etc for web server.
use Mail::Sendmail;
use MIME::QuotedPrint;

require misc;

sub view_email {
	my ( $r, $log, $dbh, $variable ) = @_;
	my $content = join('',misc::get_upload($r, $log, 'txtEmailTemplateFile'));
	$variable->{body} = $r->param('txtBody');
	$variable->{'body'} =~ s/\n/<br>/g;
	$variable->{'ReplacementText'} = $variable->{'body'};
	$variable->{includes} =  ssi::variable_substitution( $r, $log, $dbh, $content, $variable  );
}
sub maillist {
	my ( $r, $log, $dbh, $variable ) = @_;

	$_ = "SELECT DISTINCT strEmail FROM tbl_Customer_Users WHERE lngUserID IN ('" . join("','", $r->param('selectSpecificCustomers'))."')";
	my @emails = sql::sql_statement( $log, $dbh, $_ );

	$_ = "SELECT strFirstName, strLastName FROM tbl_Customer_Users WHERE lngUserID = '$$variable{'user_id'}'";
	my ( $firstname, $lastname ) = sql::sql_statement( $log, $dbh, $_ );

	if ( $r->param('txtEmailTemplateFile') ne '' ) {
		my $content = join('',misc::get_upload($r, $log, 'txtEmailTemplateFile'));
		if ( ! $content ) {
			return misc::error( $log, $dbh, $variable, 'Error reading Template', 'The Template upload failed.' );
		}
		my %variable;
		$variable{'Body'} = $r->param('txtBody');
		$variable{'Body'} =~ s/\n/<br>/g;
		$variable{'ReplacementText'} = $variable{'Body'};

		$content = encode_qp( ssi::variable_substitution( $r, $log, $dbh, $content, \%variable ) );

		foreach my $email ( @emails ) {
			my %mail = (
					SMTP	=> configuration::get_value( $log, $dbh, 'Mail Server'),
					TO	=> $email,
					FROM	=> "$firstname $lastname <$$variable{'email'}>",
					SUBJECT	=> $r->param('txtSubject'),
					);
			misc::send_email_with_attachment($r, $log, \%mail, '', $content, 'text/html', 'quoted-printable' );
		} # end foreach
	} else {
		foreach my $email ( @emails ) {
			my %mail = (
					SMTP	=> configuration::get_value( $log, $dbh, 'Mail Server'),
					TO		=> $email,
					FROM	=> "$firstname $lastname <$$variable{'email'}>",
					SUBJECT	=> $r->param('txtSubject'),
					BODY	=> $r->param('txtBody'),
					);
			sendmail(%mail) || $log->warn( "Error: $Mail::Sendmail::error\n" );
		} # end foreach
	} # end if
} # end maillist

sub mailinglistmembers {
	my ( $r, $log, $dbh, $variable ) = @_;
	$_ = "SELECT lngUserID, strLastName || ' ' || strFirstName ".
		"FROM tbl_Customer_Users Order by strLastName, strFirstName";
	my @userlist = sql::sql_statement( $log, $dbh, $_ );

	for (my $n = 0; $n < @userlist; $n += 2) {
		$$variable{'customers'} .= "<OPTION VALUE=\"$userlist[$n]\" >$userlist[$n + 1]</OPTION>\n";
	} # end for
	$$variable{'UserArray'} = "var UserArray = new Array;\n";
	$$variable{'CategoryArray'} = "var CategoryArray = new Array;\n";

	$_ = "SELECT strName, strName FROM tbl_Marketing_Categories ORDER BY lower(strName)";
	$$variable{'MarketingCategories'} = ssi::fill_select( $log, $dbh, $_ );

	$_ = "SELECT strcompanyname, strcompanyname FROM tbl_customer ORDER BY lower(strcompanyname)";
	$$variable{'Companies'} = ssi::fill_select($log,$dbh,$_);

	$_ = "SELECT DISTINCT id, name FROM pricelist ORDER BY id";
	$$variable{'Pricelists'} = ssi::fill_select($log,$dbh,$_);

	$_ = "SELECT lngIndex, strName FROM tbl_Marketing_Categories ORDER BY strName";
	my %marketing_categories = sql::sql_statement( $log, $dbh, $_ );

	foreach my $index ( keys %marketing_categories ) {
		$$variable{'CategoryArray'} .= "CategoryArray['$marketing_categories{$index}'] = new Array;\n";
	} # end foreach	

	$_ = "SELECT lngUserID, strFirstName || ' ' || strLastName, strEmail, ysnMailingList, lngcustomerid ".
		"FROM tbl_Customer_Users ORDER BY strLastname, strFirstname";
	@userlist = sql::sql_statement( $log, $dbh, $_ );
	while ( @userlist ) {
		my ( $user_id, $name, $email, $mailinglist, $company_id ) = splice @userlist,0,5;
		#convert company number into name
		$_ = "SELECT strcompanyname, lngpricelist FROM tbl_customer WHERE lngcustomerid='$company_id'";
		my ($company,$pricelist) = sql::sql_statement($log,$dbh, $_); 
		$company =~ s/'/\\'/g;
		$$variable{'UserArray'} .= "UserArray[UserArray.length] = new user($user_id,\"$name\",'$email','$mailinglist','$company','$pricelist');\n";

		$_ = "SELECT lngCategoryIndex FROM tbl_Users_In_Categories WHERE lngUserIndex='$user_id'
              UNION SELECT lngCategoryid FROM tbl_customers_In_Categories WHERE lngcustomerid = '$company_id'
             ";
		foreach my $index ( sql::sql_statement( $log, $dbh, $_ ) ) {
			if ( $marketing_categories{$index} ne '' ) {
				$$variable{'CategoryArray'} .= "CategoryArray['$marketing_categories{$index}'][CategoryArray['$marketing_categories{$index}'].length] = '$user_id';\n";	
			} # end if
		} # end foreach
	} # end while
} # end sub mailinglistmembers

sub category_edit {
	my ( $r, $log, $dbh, $variable ) = @_;

	my $cat_id = sql::escape($r->param('ddmCategory'));

	if ( $r->param('btnFunction') eq 'View' ) {
	} elsif ( $r->param('btnFunction') eq '>>' ) {
		$cat_id = misc::nav_get_next( $r, $log, $dbh, $cat_id, 'lngIndex', 'tbl_Marketing_Categories', '' ,'strDescription' );
	} elsif ( $r->param('btnFunction') eq '<<' ) {
		$cat_id = misc::nav_get_previous( $r, $log, $dbh, $cat_id, 'lngIndex', 'tbl_Marketing_Categories', '' ,'strDescription' );
	} elsif ( $r->param('btnFunction') eq 'Save' ) {
		if ( $cat_id eq '' ) {
			$_ = "SELECT lngIndex FROM tbl_Marketing_Categories WHERE strName = '" . sql::escape($r->param('txtName')) . "'";
			($cat_id) = sql::sql_statement( $log, $dbh, $_ );
			if ( $cat_id eq '' ) {
				sql::insert( $log, $dbh, 'tbl_Marketing_Categories',
					'strName',			$r->param('txtName'),
					'strDescription',	$r->param('txtDescription'),
					'strGreeting',		$r->param('txtGreeting')
				);

				$_ = "SELECT lngIndex FROM tbl_Marketing_Categories WHERE strName = '" . sql::escape($r->param('txtName')) . "'";
				($cat_id) = sql::sql_statement( $log, $dbh, $_ );
			} else {
				return misc::error( $log, $dbh, $variable, 'A Category already exists with that name.', 'A Category with the name ' . sql::escape($r->param('txtName')) . 'already exists in our database.' );
			} # end if
		} else {
			sql::update( $log, $dbh, 'tbl_Marketing_Categories', "lngIndex = '$cat_id'",
				'strName',			$r->param('txtName'),
				'strGreeting',		$r->param('txtGreeting'),
				'strDescription',	$r->param('txtDescription')
			);
		} # end if

	} elsif ( $r->param('btnFunction') eq 'Delete' ) {
		$_ = "DELETE FROM tbl_Marketing_Categories WHERE lngIndex = '$cat_id'";
		sql::sql_statement( $log, $dbh, $_ );
		$_ = "DELETE FROM tbl_Customers_in_Categories WHERE lngCategoryID = '$cat_id'";
		sql::sql_statement( $log, $dbh, $_ );
		$_ = "SELECT MIN(lngIndex) FROM tbl_Marketing_Categories WHERE lngIndex > '$cat_id'";
		($cat_id) = sql::sql_statement( $log, $dbh, $_ );
		if ( $cat_id eq '' ) {
			$_ = "SELECT MAX(lngIndex) FROM tbl_Marketing_Categories";
			($cat_id) = sql::sql_statement( $log, $dbh, $_ );
		} # end if
	} # end if

	if ( $cat_id ne '' ) {
		$_ = "SELECT strName, strDescription, strGreeting FROM tbl_Marketing_Categories WHERE lngIndex = '$cat_id'";
		@$variable{'txtName','txtDescription','txtGreeting'} = sql::sql_statement( $log, $dbh, $_ );
	} # end if

	$_ = "SELECT lngIndex, strName FROM tbl_Marketing_Categories ORDER BY strName";
	$$variable{'ddmCategory'} = ssi::fill_drop_down( $log, $dbh, $_, $cat_id );

	return OK;
} # end sub category_edit


1;

__END__

