use strict;
package openprint::Skid_Verification;

require openprint::User;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;

$table = 'skid_verifications';
$serial = 'skid_verifications_id_seq';

%fields = (
	id			=>	'id',
	code		=>	'code',
	created_on	=>	'created_on',
	skid_id		=>	'skid_id',
	user_id		=>	'user_id',
);

%transforms = (
);

%defaults = (
	created_on	=>	q`'NOW()'`,
);

sub User {
	return new openprint::User( $_[0]{user_id} );
} # end sub User

1;
__END__
