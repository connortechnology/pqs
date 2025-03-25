use strict;
package openprint::PurchaseOrder_Content;
our @ISA = qw(openprint::Object);

require openprint;
use vars qw( $debug $table $serial %fields %transforms %defaults );

require openprint::PurchaseOrder_ContentType;
require openprint::PurchaseOrder_Item;
require openprint::PurchaseOrder_Department;

$debug = 0;
$table = 'PurchaseOrder_Contents';
$serial = 'PurchaseOrder_Contents_id_seq';

%fields = (
	id							=>	'id',
	po_id						=>	'po_id',
	created_on			=>	'created_on',
	qty							=>	'qty',
	price						=>	'price',
	price_units			=>	'price_units',
	total						=>	'total',
	product					=>	'product',
	item						=>	'item',
	item_id					=>	'item_id',
	docket					=>	'docket',
	description			=>	'description',
	type_id					=>	'type_id',
	type						=>	undef,
	department_id		=>	'department_id',
	department			=>	undef,
	object_type_id	=>	undef,
	object_id				=>	undef,
);

%transforms = (
	docket					=> [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	price			=>	[ 's/[^\-\d\.]//g' ],
	total			=>	[ 's/[^\-\d\.]//g' ],
	qty				=>	[ 's/[^\-\d\.]//g' ],
);

%defaults = (
	po_id			=>	undef,
	created_on		=>	q`'NOW()'`,
	price			=>	undef,
	total			=>	undef,
	qty				=>	undef,
	type_id			=>	undef,
	item_id			=>	undef,
	department_id	=>	undef,
	object_type_id	=>	undef,
	object_id		=>	undef,
);

sub Cost { 
	return {
		cost				=>	$_[0]{price}, 
		price				=>	$_[0]{price}, 
		units				=>	$_[0]{price_units},
		currency_id	=>	$_[0]->PurchaseOrder()->currency_id(),
		Currency		=>  $_[0]->PurchaseOrder()->Currency(),
	};
}
sub PurchaseOrder {
	return new openprint::PurchaseOrder( $_[0]{po_id} );
} # end sub Supplier

sub Type {
	return new openprint::PurchaseOrder_ContentType( $_[0]{type_id} );
} # end sub Type

sub type {
	if ( @_ > 1 ) {
		my $Type = openprint::PurchaseOrder_ContentType->find_one(name=>$_[1]);
		if ( $Type ) {
			$_[0]{type_id} = $Type->id();
			return $Type->name();
		} # end if
	} # end if
	if ( ! $_[0]{type} ) {
		$_[0]{type} = $_[0]->Type()->name();
	}
	return $_[0]{type};
} # end sub type

sub Department {
	return new openprint::PurchaseOrder_Department( $_[0]{department_id} );
} # end sub Department

sub department {
	if ( @_ > 1 ) {
		$_[1] = openprint::PurchaseOrder_Department->transform( 'name', $_[1] );
		my $Department = openprint::PurchaseOrder_Department->find_one('name'=>$_[1]);
		if ( $Department ) {
			$_[0]{department_id} = $Department->id();
			return $Department->name();
		} else {
			$Department = new openprint::PurchaseOrder_Department();
			$Department->save({'name'=>$_[1]});
			$_[0]{department_id} = $Department->id();
			return $Department->name();
		} # end if
	} # end if
	return new openprint::PurchaseOrder_Department( $_[0]{department_id} )->name();
} # end sub department

sub units {
	my ( $self ) = @_;
	if ( $self->Type()->name() eq 'Roll Stock' ) {
		return 'lbs';
	} elsif ( $self->Type()->name() eq 'Sheet Stock' ) {
		return 'sheets';
	} # end if
	return '';
} # end sub units

sub Item {
	return new openprint::PurchaseOrder_Item( $_[0]{item_id} );
} # end sub Item

sub item {
	my $Item = new openprint::PurchaseOrder_Item( $_[0]{item_id} );
	if ( @_ > 1 ) {
		if ( $Item->name() ne $_[1] ) {
			my $NewItem = openprint::PurchaseOrder_Item->find_one( 'name lc'=>lc $_[1], company_id=>$_[0]->PurchaseOrder()->company_id(), vendor_id=>$_[0]->PurchaseOrder()->supplier_id(), type_id=>$_[0]{type_id} );
			if ( ! $NewItem ) {
				$NewItem = new openprint::PurchaseOrder_Item();
				$NewItem->save( { 
					name				=>	$_[1], 
					company_id	=>	$_[0]->PurchaseOrder()->company_id(), 
					vendor_id		=>	$_[0]->PurchaseOrder()->supplier_id(), 
					type_id			=>	$_[0]{type_id},
					price				=>	$_[0]{price},
					product			=>	$_[0]{product},
				 } );
			} # end if
			$_[0]{item_id} = $$NewItem{id};
		} # end if
	} # end if
	if ( ! $Item->id() ) {
		return $_[0]{item};
	} # end if
	return $Item->name();
} # end sub item

sub Order {
	my $docket = $_[0]{docket};
	$docket =~ s/\D//g;
	$_ = openprint::Order->find_one('docket'=>$docket) if $docket;
	return $_ if $_;
	return new openprint::Order();
} # end sub Order

sub Orders {
	my @dockets = map { $_ ? $_ : () } split( /\D/, $_[0]{docket} );
	return openprint::Order->find(docket=>\@dockets) if @dockets;
	return ();
} # end sub Orders

sub can_view {
	return 1 if ! $_[0]{id};
	my $User = $_[1] ? $_[1] : $openprint::User;
	if ( 
			( $$User{type} eq 'A' )
			or ( sets::isin( $_[0]->PurchaseOrder->created_by(), [ $$User{id}, $User->assistant_ids(), $User->csr_ids() ] ) )
			or ( openprint::usergroup::is_user_in( ['Accounting','Shipping','Inventory'], $$User{id} ) ) 
			or ( sets::contains( [ $$User{id}, $User->assistant_ids(), $User->csr_ids() ], [ map { $_->salesrep_id() } $_[0]->Orders() ] ) )
	   ) {
		return 1;
	} # end if
	if ( my @notifications = $_[0]->PurchaseOrder()->notifications() ) {
		if ( sets::isin( $$User{id}, \@notifications ) ) {
			$openprint::log->debug($$User{firstname} . ' can see because in notifications.' ) if $debug;
			return 1;
		} # end if
	} # end if
	return 0;
} # end sub can_view

sub mprice {
	return if $_[0]->type() ne 'Sheet Stock';
	my ( $mweight, $type, $name ) = $_[0]->item() =~ /^([\d\.]+)M *([\w\/]*) *(.*)$/;
	return Math::Round::nearest(0.01, $_[0]{price} * $mweight / 100 );
} # end sub mprice

sub weight {
	return if $_[0]->type() ne 'Sheet Stock';
	my ( $mweight, $type, $name ) = $_[0]->item() =~ /^([\d\.]+)M *([\w\/]*) *(.*)$/;
	return Math::Round::nearest(0.01, $_[0]{qty} * $mweight / 1000);
}

sub Manifest_Content_Type {
	if ( !  $_[0]{Manifest_Content_Type} ) {
		$_[0]{Manifest_Content_Type} = openprint::Manifest_Content_Type->find_one( po_content_id=>$_[0]{id} );
	} 
	return $_[0]{Manifest_Content_Type};
}
sub price_units {
	my $self = shift;
	$$self{price_units} = shift if @_;
	if ( ! $$self{price_units} ) {
		if ( $self->type() eq 'Sheet Stock' or $self->type() eq 'Roll Stock' ) {
			$$self{price_units}  = '/100lb';
		}
	}
	return $$self{price_units};
}

sub check {
	my ( $POC, $item ) = @_;
	my @results;
	if ( $item ) {
		if ( $POC->type() eq 'Sheet Stock' ) {
			push @results, "PO has wrong stock format $$item{type} != $$POC{type}" if $$item{type} ne 'Sheet';
			my ( $mweight, $type, $name ) = $POC->item() =~ /^([\d\.]+)M *([\w\/]*) *(.*)$/;
			if ( $name =~ / ([\d\.]+)x([\d\.]+)/i ) {
				my ( $width, $height ) = ( $1, $2 );
				push @results, "PO width does not match: $$item{width} != $width" if $$item{width} != $width;
				push @results, "PO height does not match: $$item{height} != $height" if $$item{height} != $height;
			} else {
				$openprint::log->warn("No sheet size for $$POC{item} in $name");
			}
			push @results, "PO has Wrong mweight! $$item{mweight} != $mweight" if abs($item->mweight() - $mweight) > 1;
	$openprint::log->debug("POC Matches $$POC{item} == " . $item->to_string() );
		} elsif ( $POC->type() eq 'Roll Stock' ) {
			push @results, "PO has wrong stock format $$item{type} != $$POC{type}" if $$item{type} ne 'Roll';
			#my ( $mweight, $type, $name ) = $POC->item() =~ /^([\d\.]+)M *([\w\/]*) *(.*)$/;
	$openprint::log->debug("POC Matches $$POC{item} == " . $item->to_string());
		} else {
	$openprint::log->debug("unsupported type $$POC{type}");
		}

		my ( $caliper ) = $POC->item() =~ /([\d\.]+)PT/i;
		if ( $caliper ) {
			if ( $item->weight() =~ /([\d\.]+PT)/i ) {
				if ( $1 != $caliper ) {
					push @results, "Caliper doesn't match $caliper != $1";
				} # end if
			} elsif ( $item->calliper() and ( ($item->calliper()*1000) != $caliper ) ) {
				push @results, "Caliper doesn't match $caliper != $$item{calliper}";
			}
		}

	if ( 0 ) {
	# We don't really care about the FSC
		if ( $item->fsc_code() and ( $POC->item() !~ /FSC/ ) ) {
			push @results, "FSC Mismatch stock is FSC but PO isn't";
		} elsif ( (!$item->fsc_code()) and $POC->item() =~ /FSC/ ) {
			push @results, "FSC Mismatch stock isn't FSC but PO is";
		} # end if
	}
	} else {
		if ( $POC->type() eq 'Sheet Stock' ) {

		# No item to match against, just ferify our own data
      my ( $mweight, $type, $name ) = $POC->item() =~ /^([\d\.]+)M *([\w\/]*) *(.*)$/;

			if ( $name =~ / ([\d\.]+)x([\d\.]+)/i ) {
				my ( $width, $height ) = ( $1, $2 );
				my $is_cover = $POC->item() =~ /cover/i;
$openprint::log->debug("Have $width x $height iscover $is_cover");
				my ( $weight ) = $POC->item() =~ /(\d+)lb/i;
				if ( $weight ) {
$openprint::log->debug("Have weight $weight");
					if ( $weight*2 == $mweight ) {
						# check basis size
						if ( $is_cover ) {
							if ( $width != 20 or $height != 26 ) {
								push @results, 'MWeight might be wrong.';
							} elsif ( $width != 25 or $height != 38 ) {
								push @results, 'MWeight might be wrong.';
							}
						}
					}
				}
			} # has width and heigt
		}
	}
	return join('<br/>', @results);

} # end sub check

sub destroy {
  my $self = shift;
  my $error = '';
  sql::update(undef,undef, 'manifest_content_types', ['po_content_id=?', $$self{id}], po_content_id=>undef);
  $error .= $openprint::dbh->errstr;
  sql::execute(undef,undef, 'DELETE FROM purchaseorder_contents WHERE id=?', $$self{id});
  $error .= $openprint::dbh->errstr;
  return $error;
}

1;
__END__
