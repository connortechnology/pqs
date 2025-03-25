package openprint::Todo;
@ISA = qw( openprint::Object );
require openprint::Object;
use strict;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'todos';
$serial = 'todos_id_seq';
%fields = (
	'id'			=>	'id',
	'description'	=>	'description',
	'title'			=>	'title',
	'owner_id'		=>	'owner_id',
	'completed'		=>	'completed',
	'project_id'	=>	'project_id',
	'created_on'	=>	'created_on',
	'updated_on'	=>	'updated_on',
	'duedate'		=>	'duedate',
);
%transforms = (
);
%defaults = (
	'created_on'	=>	q`'NOW()'`,
	'updated_on'	=>	q`'NOW()'`,
	'completed'		=>	0,
);

1;
__END__
