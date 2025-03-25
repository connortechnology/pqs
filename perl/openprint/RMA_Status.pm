use strict;
package openprint::RMA_Status;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'rma_statuses';
$serial = 'rma_statuses_id_seq';

%fields = ( 
	id		=>	'id',
	name	=>	'name',
	sort	=>	'sort',
	current_status_id	=>	'current_status_id',
);
%transforms = (
	id		=>	[ 's/\D//g' ],
	name	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = ();

1;
__END__
