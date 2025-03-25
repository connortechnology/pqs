use strict;
package openprint::Message;
our @ISA = qw( openprint::Object );
require openprint::User;
require openprint::Message_To;
require openprint::Conversation;
require misc;

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults );

$debug = 0;
$table = 'messages';
$serial = 'messages_id_seq';

%fields = (
	'id'    		=>  'id',
	'body'			=>	'body',
	'from_id'		=>	'from_id',
	'reply_to'		=>	'reply_to',
	'created_on'	=>	'created_on',
	'sent_on'		=>	'sent_on',
	'conversation_id'	=>	'conversation_id',
);
%find_fields = (
	'me_id'			=>	'(SELECT user_id FROM Message_to WHERE message_id=messages.id AND deleted!=true)',
	'to_id'			=>	'(SELECT user_id FROM Message_to WHERE message_id=messages.id AND deleted!=true)',
	'viewed'		=>	'(SELECT viewed FROM Message_to WHERE message_id=messages.id and deleted!=true)',
);
%transforms = (
);
%defaults = (
	'reply_to'			=>	undef,
	'created_on'		=>	q`'NOW()'`,
	'sent_on'			=>	undef,
	'conversation_id'	=>	undef,
	'from_id'			=>	q`$session{'user_id'}`,
);
sub From {
	new openprint::User( $_[0]{'from_id'} );
} # end sub From

# returns an array of objects
sub To {
	my ( $self, $params ) = @_;
	$$params{'message_id'} = $$self{'id'};
	return openprint::Message_To->find($params);
} # end sub To

sub Who {
	my ( $self, $params ) = @_;
	$$params{'message_id'} = $$self{'id'};
	return ( $self->From(), map { new openprint::User( $_->user_id() ) } openprint::Message_To->find($params) );
} # end sub Who

sub sent_on_string {
	if ( ! $_[0]{'sent_on_string'} ) {
		$_[0]{'sent_on_string'} = misc::smart_time( Date::Parse::str2time( $_[0]{'sent_on'} ) );
	} # end if
	return $_[0]{'sent_on_string'};
} # end sub sent_on_string

 1;
__END__
