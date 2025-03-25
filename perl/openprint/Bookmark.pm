use strict;
package openprint::Bookmark;
our @ISA = qw(openprint::Object);
use vars qw( $debug $table $serial %fields %find_fields %defaults %transforms );

$debug = 0;
$table = 'bookmarks';
$serial = 'bookmarks_id_seq';
%fields = (
	'id'			=>	'id',
	'user_id'		=>	'user_id',
	'object_type_id'	=>	'object_type_id',
	'object_type'		=>	undef,
	'object_id'		=>	'object_id',
	'created_on'	=>	'created_on',
	'deleted'		=>	'deleted',
	'text'			=>	'text',
);
%defaults = (
	'created_on'	=>	q`'NOW()'`,
	'deleted'		=>	0,
	'approved'		=>	0,
	'user_id'		=> q`$openprint::session{user_id}`,
	'approved'		=>	0,
);
%find_fields = (
	'object_type'	=>	'(SELECT name FROM object_types WHERE id=object_type_id)',
);

1;
__END__
