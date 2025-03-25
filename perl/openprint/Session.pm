use strict;
package openprint::Session;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table %fields %transforms %defaults @identified_by );

$debug = 0;
$table = 'sessions';
@identified_by = ( 'session_id' );
%fields = (
	'id'	=>	'id',
	'a_session'	=>	'a_session',
	'created_on'	=>	'created_on',
);
%transforms = (
);
%defaults = (
	'created_on'	=>	q`'NOW()'`,
);

1;
__END__
