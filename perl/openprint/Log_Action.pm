use strict;
package openprint::Log_Action;
our @ISA = qw( openprint::Object );
require openprint::Object;

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'log_actions';
$serial = 'log_actions_id_seq';

%fields = (
	id	=>	'id',
	name	=>	'name',
	description	=>	'description',
);
%transforms = (
);
%defaults = (
);

1;
__END__
