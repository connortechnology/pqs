use strict;
package openprint::RMA_Product;
our @ISA = qw(openprint::Object);

require openprint::RMA;
require openprint::Product;

use vars qw( $debug @identified_by %fields %transforms %defaults );

@identified_by = ('rma_id','product_id');

%fields = (
    rma_id		=>	'rma_id',
    product_id	=>	'product_id',
	problem		=>	'problem',
	status_id	=>	'status_id',
);

%transforms = (
);

%defaults = (
);

sub RMA {
	return new openprint::RMA($_[0]{rma_id});
} # end sub RMA

sub Product {
	return new openprint::Product($_[0]{rma_id});
} # end sub Product
1;
__END__
