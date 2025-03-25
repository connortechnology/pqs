use strict;
package openprint::User_Friend;
our @ISA = qw( openprint::Object );

use vars qw( $table @identified_by %fields %transforms %defaults );


%fields = (
	'user_id'	=>	'user_id',
	'friends'	=>	'freinds',
);
@identified_by = ('user_id');

1;
__END__

