use strict;
require openprint::Event;
require openprint::User;

package openprint::Event_Invitation;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table @identified_by %fields %transforms %defaults );
$debug = 0;
$table = 'event_invitations';
@identified_by = ( 'event_id', 'user_id' );

%fields = (
	event_id	=>	'event_id',
	user_id		=>	'user_id',
	created_on	=>	'created_on',
	sent_on		=>	'sent_on',
);

%defaults = (
	attending	=>	undef,
	created_on	=>	q`'NOW()'`,
);

sub User {
	new openprint::User($_[0]{user_id});
} # end sub User

1;
__END__
