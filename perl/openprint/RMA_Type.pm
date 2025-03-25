use strict;
package openprint::RMA_Type;
our @ISA = qw(openprint::Object);

use vars qw( $table $serial %fields %transforms %defaults );
$table = 'rma_types';
$serial = 'rma_types_id_seq';

%fields = ( 
	id		=>	'id',
	name	=>	'name',
);
%transforms = (
    name => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = ();

1;
__END__
