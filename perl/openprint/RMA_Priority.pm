use strict;
package openprint::RMA_Priority;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'rma_priorities';
$serial = 'rma_priorities_id_seq';

%fields = ( 
	id		=>	'id',
	name	=>	'name',
	sort	=>	'sort',
);
%transforms = (
	id		=>	[ 's/\D//g' ],
	name	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = ();

1;
__END__
