use strict;
package openprint::RMA;
our @ISA = qw(openprint::Object);

require openprint::RMA_Type;
require openprint::RMA_Status;
require openprint::RMA_Priority;

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults );

$debug = 0;
$table = 'rma';
$serial = 'rma_id_seq';
%fields = (
	id			=>	'id',
	company_id	=>	'company_id',
	user_id		=>	'user_id',
	project_id	=>	'project_id',
	order_id	=>	'order_id',
	type_id		=>	'type_id',
	type		=>	undef,
	created_on	=>	'created_on',
	updated_on	=>	'updated_on',
	description	=>	'description',
	comments	=>	'comments',
	rmanumber	=>	'rmanumber',
	approved	=>	'approved',
	status_id	=>	'status_id',
	status		=>	undef,
	priority_id	=>	'priority_id',
	priority	=>	undef,
	po_id		=>	'po_id',
	received_on	=>	'received_on',
	warranty			=>	'warranty',
	estimate_required	=>	'estimate_required',
	product_id			=>	'product_id',
	serialnumber		=>	'serialnumber',
	accessories			=>	'accessories',
	shipto_address_id	=>	'shipto_address_id',
	tester_id			=>	'tester_id',
);
%find_fields = (
	supplier_id	=>	'(SELECT supplier_id FROM Product_Prices WHERE product_id=rma.product_id)',
);

%transforms = (
	id				=>	[ 's/\D//g' ],
	shipto_address_id	=>	[ 's/\D//g' ],
	description		=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	comments		=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	rmanumber		=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	serialnumber	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	accessories		=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);

%defaults = (
	company_id	=>	undef,
	user_id		=>	undef,
	project_id	=>	undef,
	order_id	=>	undef,
	type_id		=>	undef,
	status_id	=>	undef,
	created_on	=>	q`'NOW()'`,
	received_on	=>	q`'NOW()'`,
	approved	=>	0,
	status		=>	undef,
	priority_id	=>	undef,
	po_id		=>	undef,
	estimate_required	=>	undef,
	warranty	=>	undef,
	shipto_address_id	=>	undef,
	tester_id	=>	undef,
);

sub Type {
	return new openprint::RMA_Type( $_[0]{'type_id'} );
} # end sub Type

sub type {
	if ( @_ > 1 ) {
		my $type = openprint::RMA_Type->transform( 'name', $_[0] );
		my $Type = openprint::RMA_Type->find_one( 'name lc' => lc $type );
		if ( ! $Type ) {
			$Type = new openprint::RMA_Type();
			$Type->set(name=>$type);
		} # end if

		@{$_[0]}{'type_id','type'} = @$Type{'id','name'};
	} elsif ( $_[0]{type_id} and ! $_[0]{'type'} ) {
		$_[0]{type} = new openprint::RMA_Type( $_[0]{type_id} )->name();
	} # end if
	return $_[0]{type};
} # end sub type

sub update_status {
	if ( ! $_[0]->status() ) {
		$_[0]->status('Submitted');
	} elsif ( $_[0]->received_on() ) {
		$_[0]->status( 'Units Received' );
	} # end if
} # end sub update_status

sub status {
	if ( @_ > 1 ) {
		my $status = openprint::RMA_Status->transform( 'name', $_[0] );
		my $Status = openprint::RMA_Status->find_one( 'name lc' => lc $status );
		if ( ! $Status ) {
			$Status = new openprint::RMA_Status();
			$Status->set(name=>$status);
		} # end if

		@{$_[0]}{'status_id','status'} = @$Status{'id','name'};
	} elsif ( $_[0]{status_id} and ! $_[0]{status} ) {
		$_[0]{status} = new openprint::RMA_Status( $_[0]{status_id} )->name();
	} # end if
	return $_[0]{status};
} # end sub status

sub status_id {
	if ( @_ > 1 ) {
		my $Status = new openprint::RMA_Status( $_[1] );
		@{$_[0]}{'status_id','status'} = @$Status{'id','name'};
	} # end if
	return $_[0]{status_id};
} # end sub status_id
sub priority {
	if ( @_ > 1 ) {
		my $priority = openprint::RMA_Priority->transform( 'name', $_[0] );
		my $Priority = openprint::RMA_Priority->find_one( 'name lc' => lc $priority );
		if ( ! $Priority ) {
			$Priority = new openprint::RMA_Priority();
			$Priority->set(name=>$priority);
		} # end if

		@{$_[0]}{'priority_id','priority'} = @$Priority{'id','name'};
	} elsif ( $_[0]{priority_id} and ! $_[0]{priority} ) {
		$_[0]{priority} = new openprint::RMA_Priority( $_[0]{priority_id} )->name();
	} # end if
	return $_[0]{priority};
} # end sub priority

sub priority_id {
	if ( @_ > 1 ) {
		my $Priority = new openprint::RMA_Priority( $_[1] );
		@{$_[0]}{'priority_id','priority'} = @$Priority{'id','name'} if $Priority;
	} # end if
	return $_[0]{priority_id};
} # end sub priority_id

sub PurchaseOrder {
	require openprint::PurchaseOrder;
	return new openprint::PurchaseOrder( $_[0]{po_id} );
} # end sub PruchaseOrder
sub Order {
	require openprint::Order;
	return new openprint::Order( $_[0]{order_id} );
} # end sub Order
sub Invoice {
	require openprint::Invoice;
	return new openprint::Invoice( $_[0]{invoice_id} );
} # end sub Invoice

sub Address {
	require openprint::Address;
	return new openprint::Address( $_[0]{shipto_address_id} );
} # end sub Address

sub add_log {
	sql::insert( undef, undef, 'RMA_Logs',{
			rma_id		=>	$_[0]{id},
			company_id	=>	$openprint::session{company_id} ? $openprint::session{company_id} : undef,
			user_id		=>	$openprint::session{user_id},
			description	=>	$_[1],
			} );
} # end sub add_log
1;
__END__
