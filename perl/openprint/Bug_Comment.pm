package openprint::Bug_Comment;
@ISA = qw( openprint::Object );
require openprint::Object;
use strict;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'bug_comments';
$serial = 'bug_comments_id_seq';
%fields = (
	'id'			=>	'id',
	'bug_id'		=>	'bug_id',
	'created_on'	=>	'created_on',
	'updated_on'	=>	'updated_on',
	'user_id'		=>	'user_id',
	'status'		=>	'status',
);
%transforms = (
);
%defaults = (
	'created_on'	=>	q`'NOW()'`,
	'updated_on'	=>	q`'NOW()'`,
);

1;
__END__
