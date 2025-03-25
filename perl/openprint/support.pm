use strict;
package openprint::support;

require MIME::QuotedPrint;
require Email::Valid;
use openprint ();
use vars qw( $r $log $dbh %variable %param %session %config);
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*param = \%openprint::param;
*session = \%openprint::session;
*config = \%openprint::config;

require sql;
require openprint::RMA;
require openprint::RMA_Type;
require openprint::RMA_Status;

require openprint::Project;
require openprint::Order;
require openprint::Company;
require openprint::Helpdesk;

sub rma {
	if ( $param{action} eq 'Submit' ) {

		$param{project_id} = openprint::Project->transform( 'id', $param{project_id} );
		my $Order;

		if ( $param{docket} ) {
			$param{docket} = openprint::Order->transform('docket', $param{docket} );
			$Order = openprint::Order->find_one(docket=>$param{docket}) if $param{docket};
		} elsif ( $param{order_id} ) {
			$param{order_id} = openprint::Order->transform('id', $param{order_id} );
			$Order = openprint::Order->find_one(id=>$param{order_id}) if $param{order_id};
		} # end if

		
		if ( ! $Order ) {
			if ( $param{company} ) {
				my $Company = openprint::Company->find_one('name lc'=>lc openprint::Company->transform($param{company}) );
				if ( ! $Company ) {
					$Company = new openprint::Company();
					$Company->save({name=>$param{company}});
				} # end if
			} # end if
			if ( $config{RMAValidOrder} ne 'Y' ) {
				$Order = new openprint::Order();
				$variable{error} .= $Order->save({
					id		=>	$param{order_id},
					docket	=>	$param{docket},
					company_id => ( $param{company_id} ? $param{company_id} : $session{company_id} ),
				}, 1 );
			} else {
				$variable{error} .= 'Invalid Order ID';
				return;
			} # end if
		} elsif ( ( ! sets::isin( $session{user_type}, ['E','A'] ) ) and ( $Order->company_id() != $session{company_id} ) ) {
			$variable{error} .= 'You are not the owner of that order.';
			return;
		} # end if

		my $Project = new openprint::Project( $param{project_id} );
		if ( $param{project_id} and ! openprint::OrderedProject->find(order_id=>$$Order{id},project_id=>$param{project_id}) ) {
			$variable{error} .= qq`Order <a href="/main/order/history_details.html?order_id=$$Order{id}">$$Order{id}</a> does not contain project <a href="/main/project/view.html?project_id=$param{project_id}">$param{project_id}</a>.`;
			return;
		} # end if

		my $RMA = new openprint::RMA();
		$variable{error} .= $RMA->save({
				project_id		=>	$param{project_id},
				company_id		=>	( sets::isin( $session{user_type}, ['E','A'] ) ? $param{company_id} : $session{company_id} ),
				user_id			=>	$session{user_id},
				order_id		=>	$$Order{id},
				type_id			=>	$param{type_id},
				description		=>	$param{description},
				});
		return if $variable{error};
		
		$session{information} .= 'RMA has been saved.';

		my %info = (
			RMA		=>	$RMA,
			Project	=>	$Project,
			Order	=>	$Order,
		);

		my $template = ssi::include( '/email_content/rma_notification.html', \%info );

		my $Email = new openprint::Email();
		$Email->html_body( $template );
		$Email->send(
				FROM	=> $config{RMAEmail},
				TO		=> $config{RMAEmail},
				SUBJECT => 'Online RMA Submission.',
				);

		$info{ReplacementText} = ssi::include( '/email_content/rma_confirmation.html', \%info );

		$template = ssi::include( '/email_template.html', \%info );
		$Email->html_body( $template );
		$Email->send(
				TO		=> $info{Email},
				);
		$variable{ExternalRedirect} = '/support/returns.html';
		%param = ();
	} # end if action

} # end sub rma

sub help_desk {

	if ( $param{btnSubmit} ) {
		my $error = '';
		$error .= 'Missing First Name<br/>' if $param{txtFirstName} eq '';
		$error .= 'Missing Last Name<br/>' if $param{txtLastName} eq '';
		$error .= 'Missing Address<br/>' if $param{txtAddress1} eq '';
		$error .= 'Missing City<br/>' if $param{txtCity} eq '';
		$error .= 'Missing Postal Code<br/>' if $param{txtPostalCode} eq '';
		$error .= 'Missing Phone<br/>' if $param{txtPhone} eq '';
		my $addr = Email::Valid->address( $param{txtEmail} );

		$error .= 'Missing/Invalid E-mail<br/>' if ( ! $param{txtEmail} ) or ( ! $addr ) or ( $addr ne $param{txtEmail} );
		$error .= 'Missing Question or Comment<br/>' if $param{'txtQuestion-Quote'} eq '';
		if ( ! $session{user_id} ) {
			if ( $config{UseCaptchaOnRegistration} eq 'Y' ) {
				# Remove spaces, because some people want to put spaces between the characters, etc.
				$param{Captcha} =~ s/\s//g;
				require Authen::Captcha;
				my $Captcha = new Authen::Captcha(
						data_folder => $config{SkinPath}.'/tmp',
						output_folder => $config{SkinPath}.'/images/captcha'
						);
				if ( 1 != $Captcha->check_code( $param{Captcha}, $param{MD5SUM} ) ) {
					$error .= 'Validation Code incorrect. Please try again.';
				} # end if
			} # end if
		} # end if

		if ( $error ) {
			$variable{error} = $error;
			$log->debug($error);
			return;
		} # end if

		my ( $index ) = sql::execute( $log, $dbh, q{SELECT nextval('HelpDesk_Id_seq')} );
		if ( ! $index ) {
			return misc::error( $log, $dbh, \%variable, 'System Error', 'Unable to create helpdesk entry.' );
		} # end if

		sql::insert( $log, $dbh, 'Helpdesk',
				'Id', $index,
				'company_id', $session{company_id},
				'user_id',	 $session{user_id},
				'strCompanyName',	$param{txtCompanyName},
				'strTitle',			$param{txtTitle},
				'strFirstName',		$param{txtFirstName},
				'strLastName',		$param{txtLastName},
				'strAddress',		$param{txtAddress1},
				'strAddress2',		$param{txtAddress2},
				'strCity',			$param{txtCity},
				'strStateProv',		$param{ddmStateProvince},
				'strPostalCode',	$param{txtPostalCode},
				'strCountry',		$param{ddmCountry},
				'strPhone',			$param{txtPhone},
				'strExtension',		$param{txtExtension},
				'strEmail',			$param{txtEmail},
				'blbdescription',	$param{'txtQuestion-Quote'},
				'chrMethod',		$param{rdbMethod},
				'dtmRequestDate',	'NOW()',
				);

		my %info = ( 
				HelpDeskIndex => $index,
				txtSalutation	=>	$param{rdbSalutation},
				txtFirstName	=>	$param{txtFirstName},
				txtLastName	=>	$param{txtLastName},
				);

		@info{ keys %param } = values %param;

		my $template = ssi::include( '/email_content/helpdesk_notification.html', \%info );

		my $Email = new openprint::Email();
		$Email->html_body( $template );
		$Email->send(
				FROM	=> sprintf('"%s %s" <%s>', @param{'txtFirstName','txtLastName','txtEmail'} ),
				TO		=> $config{HelpdeskEmail},
				SUBJECT => 'Online Helpdesk Submission.',
				);

		%param = ();
		$variable{information} .= "Thank you for your help desk submission. Your reference # is $index";
		$variable{ExternalRedirect} = '/support/help_desk.html';
	} else {
		# Guess location?
	} # end if

} # end sub help_desk
sub helpdesk_view {
	$variable{Helpdesk} = new openprint::Helpdesk($param{helpdesk_id} );
}

1;
__END__
