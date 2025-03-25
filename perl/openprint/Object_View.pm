use strict;
require openprint::Object_Type;
package openprint::Object_View;
our @ISA = qw(openprint::Object);
use vars qw( $debug $table @identified_by %fields %find_fields %defaults %transforms );

$debug = 0;
$table = 'object_views';
@identified_by = ( 'user_id', 'object_type_id', 'object_id' );
%fields = (
	'user_id'		=>	'user_id',
	'object_type_id'	=>	'object_type_id',
	'object_type'		=>	undef,
	'object_id'		=>	'object_id',
	'created_on'	=>	'created_on',
);
%find_fields = (
	'object_type'	=>	'(SELECT name FROM object_types WHERE id=object_type_id)',
);
%defaults = (
	'created_on'	=>	q`'NOW()'`,
	'user_id'		=> q`$openprint::session{user_id}`,
);
sub Object {
	return $_[0]->object_type()->new( $_[0]{'object_id'} );
} # end sub Object

1;
__END__
