use strict;
package openprint::StockQuality;
our @ISA = qw(openprint::Object);

use vars qw( $table $serial %fields %transforms %defaults );

$table = 'stockqualities';
$serial= 'stockqualities_id_seq';
%fields = (
	id		=>	'id',
	name	=>	'name',
	message	=>	'message',
);
%transforms = (
    name	=> [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    message => [ 's/^\s+//', 's/\s+$//' ],
);
%defaults = (
);

1;
__END__
