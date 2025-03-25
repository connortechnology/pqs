use strict;
package openprint::PurchaseOrder_Item_to_Inventory_Item;
our @ISA=qw(openprint::Object);

use openprint ();
use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'purchaseorder_items_to_inventory_items';
$serial = 'purchaseorder_items_to_inventory_items_id_seq';
%fields = (
	purchaseorder_item_id	=>	'purchaseorder_item_id',
	inventory_item_id	=>	'inventory_item_id',
	inventory_object_type_id	=>	'inventory_object_type_id',
);

%transforms = (
);
%defaults = (
);

1;
__END__
