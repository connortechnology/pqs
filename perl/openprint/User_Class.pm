use strict;
package openprint::User_Class;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table $serial %fields %transforms %defaults @identified_by);
$debug = 0;
$table = 'user_class';
$serial = 'user_class_id_seq';
@identified_by = ( 'id' );
%fields = (
	'id'	=>	'id',
	'name'	=>	'name',
);

1;
__END__
