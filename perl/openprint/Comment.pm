use strict;
require openprint::Object_Type;
package openprint::Comment;
our @ISA = qw(openprint::Object);
use vars qw( $debug $table $serial %fields %find_fields %defaults %transforms );

$debug = 0;
$table = 'comments';
$serial = 'comments_id_seq';
%fields = (
	'id'			=>	'id',
	'user_id'		=>	'user_id',
	'object_type_id'	=>	'object_type_id',
	'object_type'		=>	undef,
	'object_id'		=>	'object_id',
	'created_on'	=>	'created_on',
	'deleted'		=>	'deleted',
	'approved'		=>	'approved',
	'text'			=>	'text',
);
%find_fields = (
	'object_type'	=>	'(SELECT name FROM object_types WHERE id=object_type_id)',
);
%defaults = (
	'created_on'	=>	q`'NOW()'`,
	'deleted'		=>	0,
	'approved'		=>	0,
	'user_id'		=> q`$openprint::session{user_id}`,
	'approved'		=>	0,
);
sub Object {
	my $type = $_[0]->object_type();
	$type =~ s/::/_/g;
	require $type.'.pm';
	return $_[0]->object_type()->new( $_[0]{'object_id'} );
} # end sub Object

sub can_delete {
	return 1 if $openprint::session{'user_type'} eq 'A';
	return 1 if $_[0]{'user_id'} == $openprint::session{'user_id'};
	return $_[0]->Object()->can_delete();
} # end sub can_delete

sub can_approve {
	return 1 if $openprint::session{'user_type'} eq 'A';
	return $_[0]->Object()->can_approve();
} # end sub can_approve
1;
__END__
