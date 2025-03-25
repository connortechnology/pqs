use strict;
package openprint::PurchaseOrder_Item;
our @ISA=qw(openprint::Object);

use openprint ();
use vars qw( $debug $table $serial %fields %transforms %defaults );
require openprint::Company;
require openprint::PurchaseOrder_ContentType;

$debug = 0;
$table = 'purchaseorder_items';
$serial = 'purchaseorder_items_id_seq';
%fields = (
	'id'	=>	'id',
	'company_id'	=>	'company_id',
	'vendor_id'		=>	'vendor_id',
	'type_id'		=>	'type_id',
	'name'			=>	'name',
	'description'	=>	'description',
	'price'			=>	'price',
	'product'		=>	'product',
	created_on		=>	'created_on',
	updated_on		=>	'updated_on',
);

%transforms = (
	name	=>	[ 's/^\s+//', 's/\s+$//', 's/ \s+/ /g' ],
	product	=>	[ 's/^\s+//', 's/\s+$//', 's/ \s+/ /g' ],
	price	=>	[ 's/[^\d\.\-]//g' ],
);
%defaults = (
	price	=>	undef,
	created_on	=>	'NOW()',
	updated_on	=>	'NOW()',
);

sub Vendor {
	return new openprint::Company( $_[0]{'vendor_id'} );
} # end sub Vendor

sub Type {
	return new openprint::PurchaseOrder_ContentType( $_[0]{type_id} );
} # end sub Type

sub type {
	if ( @_ > 1 ) {
		my $Type = openprint::PurchaseOrder_ContentType->find_one('name'=>$_[1]);
		if ( $Type ) {
			$_[0]{'type_id'} = $Type->id();
			return $Type->name();
		}
	}
	return new openprint::PurchaseOrder_ContentType( $_[0]{'type_id'} )->name();
} # end sub type

sub PurchaseOrders {
	return openprint::PurchaseOrder->find( 'supplier_id'=>$_[0]{'vendor_id'}, 'item_id in'=>$_[0]{'id'}, 'order'=>'id' );
} # end sub PurchaseOrders

sub delete {
	if ( ! $_[0]{'id'} ) {
		return "PurchaseOrder_Item->delete called without an id";
	} # end if
	my $error = '';
	my $ac = sql::start_transaction( $openprint::dbh );
	foreach my $C ( openprint::PurchaseOrder_Content->find( 'item_id'=>$_[0]{'id'} ) ) {
		if ( $error .= $C->save({'item_id'=>undef}) ) {
			$openprint::dbh->rollback();
			return $error;
		} # end if
	} # end foreach C

	$error = $_[0]->SUPER::delete();
	if ( $error ) {
		$openprint::dbh->rollback();
		return $error;
	} # end if	

	sql::end_transaction( $openprint::dbh, $ac );
	return;
} # end sub delete

sub Inventory_Items {
	require openprint::PurchaseOrder_Item_to_Inventory_Item;
	return openprint::PurchaseOrder_Item_to_Inventory_Item->find( purchaseorder_item_id => $_[0]{id}, order=>'purchaseorder_item_id' );
}

1;
__END__
