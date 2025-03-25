use strict;
package openprint::WorkOrder;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'workorders';
$serial= 'workorders_id_seq';
%fields = (
	id	=>	'id',
);
%transforms = (
);
%defaults = (
);

1;
__END__
