package eprint::reseller_application;

use strict;

use sql ();
require ssi;
require misc;

require eprint::customer;
require eprint::obj_customer;

	my %fields = (
			'rdbLegalForm'			=>	'LegalForm',
			'txtLegalBusinessName'	=>	'LegalBusinessName',
			'txtBusinessType'		=>	'BusinessType',
			'BusinessStartDate'		=>	'BusinessStartDate',
			'txtPresidentOwner'		=>	'PresidentOwner',
			'ddmEmployees'			=>	'Employees',
			'ddmAnnualSales'		=>	'AnnualSales',
			'txtGSTNumber'			=>	'TaxNumber1',
			'txtPSTNumber'			=>	'TaxNumber2',
	);

sub reseller_application_display {
	my ( $r, $log, $dbh, $variable ) = @_;

	$$variable{'CustomerIndex'} = ( $r->param('CustomerIndex') ? $r->param('CustomerIndex') : $$variable{'cust_id'} ) if ! $$variable{'CustomerIndex'};
	if ( $$variable{'CustomerIndex'} ne '' ) {

		my $customer = new eprint::obj_customer( $log, $dbh, $$variable{'cust_id'} );
		@$variable{ keys %fields } = ssi::htmlize( $customer->get( @fields{ keys %fields } ) );

		$$variable{'BusinessStartDate'} =~ /^(\d\d\d\d)-(\d\d)-(\d\d) .*/;
		$$variable{'txtStartYear'} = $1;
		$$variable{'rdbLegalForm'.$$variable{'rdbLegalForm'}} = 'checked="checked"';

		$$variable{'ddmEmployees'} = ssi::getemployee_numbers( $r, $log, $dbh, $$variable{'ddmEmployees'} );
		$$variable{'ddmAnnualSales'} = ssi::getannual_sales( $r, $log, $dbh, $$variable{'ddmAnnualSales'} );

		eprint::customer::load_shipping( $log, $dbh, $$variable{'CustomerIndex'}, $variable );
		eprint::customer::load_tradereferences( $r, $log, $dbh, $$variable{'CustomerIndex'}, $variable );

		$$variable{'ddmShippingStateProvince'} = ssi::return_states_and_provinces($$variable{'ddmShippingStateProvince'});
		$$variable{'ddmShippingCountry'} = ssi::return_countries($$variable{'ddmShippingCountry'});
	} # end if
} # end sub reseller_application_display

sub reseller_application_process {
	my ( $r, $log, $dbh, $variable ) = @_;

	my $cust_id = $r->param('CustomerIndex');
	my $user_id = $r->param('UserIndex');
	$_ = "SELECT strEmail FROM tbl_Customer_Users WHERE lngUserID='$user_id'";
	my ( $email ) = sql::sql_statement( $log, $dbh, $_ );

	my $error = '';
	# first, check all fields that are required

	$error .= "Missing legal form<br>" if $r->param('rdbLegalForm') eq '';
	$error .= "Missing legal business name<br>" if $r->param('txtLegalBusinessName') eq '';
	$error .= "Missing legal business type<br>" if $r->param('txtBusinessType') eq '';
	$error .= "Missing President/Owner<br>" if $r->param('txtPresidentOwner') eq '';
#$error .= "Bad Federal Tax number<br>" if $r->param('txtGSTNumber') eq '';
#$error .= "Bad State Tax number<br>" if $r->param('txtPSTNumber') eq '';

	foreach my $tr ( 1 .. 3 ) {
		$error .= "Missing company name for trade reference $tr<br>" if $r->param('txtTradeReferenceCompanyName'.$tr) eq '';
		$error .= "Missing contact for trade reference $tr<br>" if $r->param('txtTradeReferenceContact'.$tr) eq '';
		$error .= "Missing phone number for trade reference $tr<br>" if $r->param('txtTradeReferencePhone'.$tr) eq '';
#$error .= "Missing email address for trade reference $tr<br>" if $r->param('txtTradeReferenceEmail'.$tr) eq '';
	} # end foreach


# process error conditions
	if ( $error ne '' ) {
		return misc::error( $log, $dbh, $variable, 'Bad Field', $error );
	} # end if

    my $customer = new eprint::obj_customer( $log, $dbh, $$variable{'cust_id'} );
    my %params;
    foreach my $field ( keys %fields ) { 
        $params{$fields{$field}} = $r->param($field) if defined $r->param($field);
    } # end foreach 
    if ( $r->param('txtStartYear') ) {
        $params{'BusinessStartDate'} = $r->param('txtStartYear') . '-' . 
            ( $r->param('ddmStartMonth') ? $r->param('ddmStartMonth') : '01' ) . '-01';
    } # end if 
    $customer->set( \%params );
	eprint::customer::save_shipping( $r, $log, $dbh, $cust_id );
	eprint::customer::save_tradereferences( $r, $log, $dbh, $cust_id );

	my %info; 
	foreach my $key ( $r->param() ) {
		$info{$key} = $r->param($key);
	} # end foreach
	$info{'date'} = localtime;
	$info{'siteURL'} = "http://" . $r->hostname;
	$info{'SecureSiteURL'} = "https://" . $r->hostname;
	my $email_template = misc::load_file($r, '/email/email_template.html');

	eprint::customer::load( $r, $log, $dbh, $cust_id, \%info );
	eprint::user::load( $log, $dbh, $user_id, \%info );
	$info{'txtEmployees'} = ssi::get_range_text( sql::sql_statement( $log, $dbh, "SELECT lngMin, lngMax FROM tbl_Employee_Numbers WHERE lngEmployeeID='$info{'ddmEmployees'}'" ) );
	$info{'txtAnnualSales'} = ssi::get_range_text( sql::sql_statement( $log, $dbh, "SELECT dblMin, dblMax FROM tbl_Annual_Sales WHERE lngIndex='$info{'ddmAnnualSales'}'" ) );

#$template = misc::load_file($r, '/email/content/reseller_application_confirmation.html');
#$template = ssi::variable_substitution( $r, $log, $dbh, $template, \%info );
#
#my %mail = (
#SMTP	=>	configuration::get_value($log,$dbh,'Mail Server'),
#TO		=>	$email,
#FROM	=>	'creditapp@'.configuration::get_value($log,$dbh,'domain'),
#SUBJECT =>	"Reseller application received."
#);
#misc::send_email_with_attachment( $log, \%mail, ( '', encode_qp($template), 'text/html', 'quoted-printable' ) );

	$info{'ReplacementText'} = "<!--#include virtual=\"/email/content/reseller_application_notification.html\"-->";
	my $template = ssi::variable_substitution( $r, $log, $dbh, $email_template, \%info );

	my %mail = (
			SMTP	=> configuration::get_value( $log, $dbh, 'Mail Server'),
			FROM	=> configuration::get_value( $log, $dbh, 'ResellerApplicationEmail'),
			TO		=> configuration::get_value( $log, $dbh, 'ResellerApplicationEmail'),
			SUBJECT	=> "New Reseller Application"
			);

	misc::send_email_with_attachment($r, $log, \%mail, ( '', encode_qp($template), 'text/html', 'quoted-printable' ) );

} # sub reseller_application_process

1;

__END__
