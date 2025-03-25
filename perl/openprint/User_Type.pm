use strict;
package openprint::User_Type;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table @identified_by %fields %transforms %defaults );
$debug = 0;
$table = 'user_types';
@identified_by = ( 'id' );
%fields = (
	'id'	=>	'identifier',
	'name'	=>	'label',
);

1;
__END__
