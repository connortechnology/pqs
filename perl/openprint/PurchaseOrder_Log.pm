package openprint::PurchaseOrder_Log;
@ISA = qw(openprint::Object);
require openprint::Object;

use strict;
use vars qw( $debug $table $serial %fields %transforms %defaults );

require openprint::PurchaseOrder;
require openprint::User;

$debug = 0;
$table = 'PurchaseOrder_Logs';
$serial = 'PurchaseOrder_Logs_id_seq';

%fields = (
	id			=>	'id',
	po_id		=>	'po_id',
	created_on	=>	'created_on',
	user_id		=>	'user_id',
	reason		=>	'reason',
);

%transforms = (
);

%defaults = (
	po_id		=>	undef,
	created_on	=> q`'NOW()'`,
);

sub PurchaseOrder {
	return new openprint::PurchaseOrder( $_[0]{po_id} );
} # end sub Supplier

sub User {
	return new openprint::User( $_[0]{user_id} );
} # end sub Type

1;
__END__
