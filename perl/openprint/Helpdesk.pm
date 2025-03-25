use strict;
package openprint::Helpdesk;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults );

$debug = 0;
$table = 'helpdesk';
$serial = 'helpdesk_id_seq';
%fields = (
		id =>	'id',
		company_id =>	'company_id',
		user_id       =>	'user_id',
		created_on		=>	'dtmrequestdate',
		description	=>	'blbdescription',
		company_name	=>	'strcompanyname',
		title			=>	'strtitle',
		firstname		=>	'strfirstname',
		lastname		=>	'strlastname',
		address1		=>	'straddress',
		address2		=>	'straddress2',
		city			=>	'strcity',
		state			=>	'strstateprov',
		postalcode		=>	'strpostalcode',
		country		=>	'strcountry',
		phone			=>	'strphone',
		extension		=>	'strextension',
		email			=>	'stremail',
		question		=>	'blbquestion',
		response		=>	'blbresponse',
		method			=>	'chrmethod',
		reviewed		=>	'ysnreviewed',
);

%defaults	=	(
	created_on	=>q`'NOW()'`,
);

sub User {
	return new openprint::User( $_[0]{user_id} );
}

sub Company {
	return new openprint::Company( $_[0]{company_id} );
} # end sub COmpany

1;
__END__
