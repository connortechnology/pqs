use strict;
package openprint::Order_Invoice;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table @identified_by %fields %defaults %transforms );

require openprint::Order;
require openprint::Invoice;

$debug = 0;

$table = 'order_invoices';
@identified_by = ( 'order_id', 'invoice_id' );

%fields = (
	order_id		=>	'order_id',
	invoice_id		=>	'invoice_id',
);

%transforms = (
);
%defaults = (
);

sub Order {
	if ( ! $_[0]{Order} ) {
		$_[0]{Order} = new openprint::Order($_[0]{order_id});
	}
	return $_[0]{Order};
} 
sub Invoice {
	if ( ! $_[0]{Invoice} ) {
		$_[0]{Invoice} = new openprint::Invoice($_[0]{invoice_id});
	}
	return $_[0]{Invoice};
} 

1;
__END__
