use strict;
package openprint::Task_Type;
our @ISA = qw( openprint::Object );
require openprint::Object;

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'task_types';
$serial = 'task_types_id_seq';

%fields = (
	id	=>	'id',
	name	=>	'name',
	description	=>	'description',
  created_at => 'created_at',
  created_by => 'created_by',
);
%transforms = (
);
%defaults = (
);

1;
__END__
