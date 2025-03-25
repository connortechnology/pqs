use strict;
require openprint::Message;
require openprint::User;

package openprint::Message_To;
our @ISA = qw( openprint::Object );
use vars qw( $debug $table %fields %find_fields %defaults @identified_by );
$debug = 0;
$table = 'message_to';
@identified_by = ( 'message_id', 'user_id' );
%fields = (
	message_id	=>	'message_id',
	user_id		=>	'user_id',
	viewed		=>	'viewed',
	deleted		=>	'deleted',
);
%find_fields = (
	created_on	=>	'(SELECT created_on FROM messages WHERE messages.id=message_id)',
	conversation_id	=>	'(SELECT conversation_id FROM Messages WHERE messages.id = message_to.message_id)',
);
%defaults = (
	viewed	=>	0,
	deleted	=>	0,
);

sub Message {
	return new openprint::Message( $_[0]{'message_id'} );
} # end sbu Message

sub User {
	return new openprint::User( $_[0]{'user_id'} );
} # end sub User
 1;
__END__
