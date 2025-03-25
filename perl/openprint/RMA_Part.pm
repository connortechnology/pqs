use strict;
package openprint::RMA_Part;
our @ISA = qw(openprint::Object);
require openprint::RMA;
require openprint::Product;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'rma_parts';
$serial = 'rma_parts_id_seq';

%fields = ( 
	id			=>	'id',
	rma_id		=>	'rma_id',
	quantity	=>	'quantity',
	product_id		=>	'product_id',
	serialnumber	=>	'serialnumber',
);
%transforms = (
	id		=>	[ 's/\D//g' ],
    serialnumber	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
	
);


sub Product {
	return new openprint::Product( $_[0]{product_id} );
} # end sub Product

sub RMA {
	return new openprint::RMA( $_[0]{rma_id} );
} # end sub RMA

1;
__END__
