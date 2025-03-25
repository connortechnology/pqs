use strict;
require openprint::Company;
require openprint::User;

package openprint::Credit_Application;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %defaults %transforms );

$debug = 0;

$table = 'creditapplications';
$serial = 'lngCreditAppIndex_seq';

%fields = (
	'id'					=>	'id',
	'user_id'				=>	'user_id',
	'company_id'			=>	'company_id',
	'signature'				=>	'strsignature',
	'financialstatementavailable'	=>	'ysnfinancialstatementavailable',
	'firstordervalue'		=>	'strfirstordervalue',
	'annualpurchases'		=>	'strannualpurchases',
	'desired_limit'			=>	'dblcreditlimit',
	'desired_terms'			=>	'lngterms',
	'accountspayablecontact'	=>	'straccountspayablecontact',
	'created_on'			=>	'dtmcreationdate',
	'status'				=>	'strstatus',
	'granted_terms'			=>	'lnggrantedterms',
	'granted_limit'			=>	'dblgrantedcreditlimit',
	'granted_downpayment'	=>	'dblgranteddownpayment',
	'granted_cod'			=>	'grantedcod',

);

%transforms = (
    'signature' => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	'granted_terms'	=>	[ 's/\D//g' ],
	'desired_terms'	=>	[ 's/\D//g' ],
	'granted_limit'	=>	[ 's/[^\d\.]//g' ],
	'desired_limit'	=>	[ 's/[^\d\.]//g' ],
	'granted_downpayment'	=>	[ 's/[^\d\.]//g' ],
	'granted_cod'	=>	[ 's/[^\d\.]//g' ],

);
%defaults = (
	'created_on'	=>	'NOW()',
	'desired_terms'	=>	undef,
	'desired_limit'	=>	undef,
	'granted_terms'	=>	undef,
	'granted_limit'	=>	undef,
	'granted_cod'	=>	undef,
	'granted_downpayment'	=>	undef,
);

sub Company {
	return new openprint::Company( $_[0]{company_id} );
} # end sub Company

sub User {
	return new openprint::User( $_[0]{user_id} );
} # end sub User

sub send_notification {
	my ( $this, @To ) = @_;
# Now send email notifications
	my %info;
	$info{Company} = $this->Company();
	$info{User} = $this->User();

	$info{CreditAppIndex} = $this->id();
	$info{Application} = $this;

	$info{ReplacementText} = ssi::include( '/email_content/credit_application_notification.html', \%info );
	my $body = ssi::include( '/email_template.html', \%info );
	$info{ReplacementText} = ssi::include( '/email_content/credit_application.html', \%info );
	my $credit_application;
	$credit_application = ssi::include( '/credit_application_template.html', \%info );
	$credit_application = ssi::include( '/email_template.html', \%info ) if ! $credit_application;

	my $Email = new openprint::Email();

	$Email->add_pdf_attachment_from_html( 'CreditApplication'.$this->id(), $credit_application );
	if ( @To ) {
		$Email->add_html_attachment( 'CreditApplication'.$this->id().'.html', $credit_application );
		#$Email->add_html_attachment( 'CreditApplicationBody.html', $body );
	} else {
		push @To, $openprint::config{CreditApplicationEmail};
	}

	my $results = $Email->send(
			FROM		=> $openprint::config{CreditApplicationEmail},
			TO			=> \@To,
			BCC			=> 'iconnor@connortechnology.com',
			SUBJECT		=> 'New Credit Application',
			HTML_BODY	=>  $body,
			);
	return $results;
} # end if
1;
__END__
