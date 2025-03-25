use strict;
package openprint::InventoryCondition;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'inventoryconditions';
$serial= 'inventoryconditions_id_seq';
%fields = (
	id		=>	'id',
	name	=>	'name',
	message	=>	'message',
);
%transforms = (
	name	=> [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	message	=> [ 's/^\s+//', 's/\s+$//' ],
);
%defaults = (
);

1;
__END__
