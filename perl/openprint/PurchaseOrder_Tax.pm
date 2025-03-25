use strict;
package openprint::PurchaseOrder_Tax;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %defaults %transforms );

$debug = 1;
$table = 'purchaseorder_taxes';
$serial = 'purchaseorder_taxes_id_seq';

%fields = (
	id								=>	'id',
	purchaseorder_id	=>	'purchaseorder_id',
	PurchaseOrder			=>	undef,
	tax_id						=>	'tax_id',
	rate							=>	'rate',
	amount						=>	'amount',
	charge						=>	'charge',
);

%transforms = (
);
%defaults = (
	rate		=>	undef,
	amount	=>	undef,
);

sub name {
	return $_[0]->Tax()->name();
} # end sub name

sub amount {
	if ( @_ > 1 ) {
$openprint::log->debug("Setting PO Tax amount to $_[1]");
		$_[0]{amount} = $_[1];
	} # end if
	if ( ! defined $_[0]{amount} ) {
		my $subtotal = $_[0]->PurchaseOrder()->subtotal();
		$openprint::log->debug("caculating amount for po $_[0]{purchaseorder_id} subtotal:" .$subtotal.' charge: ' . $_[0]->charge() . ' tax: ' . $_[0]->name() );
		if ( $_[0]->charge() ) {
			$_[0]{amount} = Math::Round::nearest( 0.01, ($_[0]->rate()/100) * $subtotal );
		} # end if
		$openprint::log->debug("caculating amount for po $_[0]{purchaseorder_id} subtotal:" .$subtotal.' charge: ' . $_[0]->charge() . ' tax: ' . $_[0]->name() . ' amount: ' . $_[0]{amount} );
	} else {
		$openprint::log->debug("NOT caculating amount: $_[0]{purchaseorder_id} charge: " . $_[0]->charge() . ' ' . $_[0]{amount} . ' tax: ' . $_[0]->name() );
	} # end if
	return $_[0]{amount};
} # end sub amount

sub charge {
	my $self = $_[0];
	if ( @_ == 2 ) {
		$$self{charge} = $_[1];
	} # end if

	if ( ( ! defined $$self{charge} ) and $self->PurchaseOrder()->supplier_id() ) {
#$openprint::log->debug("Calculating Tax: " . $self->name() . 'exempt: ' . $self->PurchaseOrder()->Supplier()->taxexempt1() );
		if ( sets::isin( $self->name(), ['GST','HST'] ) ) {
			if ( $self->PurchaseOrder()->Supplier()->taxexempt1() eq 'Y' ) {
				return 0;
			} # end if
			return 1;
		} elsif ( sets::isin( $self->name(), ['PST'] ) ) {
			if ( $self->PurchaseOrder()->Supplier()->taxexempt2() eq 'Y' ) {
				return 0;
			} # end if
			return 1;
		} # end if 
	} # end if
	return $$self{charge};
} # end sub charge

sub PurchaseOrder {
	if ( @_ > 1 ) {
		$_[0]{PurchaseOrder} = $_[1];
		if ( $_[1]{id} ) {
			$_[0]{purchaseorder_id} = $_[1]{id};
		} # end if
	} 
	if ( ! defined $_[0]{PurchaseOrder} ) {
	 	$_[0]{PurchaseOrder} = new openprint::PurchaseOrder( $_[0]{purchaseorder_id} );
	} # end if
	return $_[0]{PurchaseOrder};
} # end sub PurchaseOrder	

sub Tax {
	if ( @_ > 1 ) {
		$_[0]{Tax} = $_[1];
	}
	if ( ! $_[0]{Tax} ) {
		$_[0]{Tax} = new openprint::Tax( $_[0]{tax_id} );
	}
	return $_[0]{Tax};
}

sub rate {
	if ( @_ > 1 ) {
		$_[0]{rate} = $_[0]{rate};
	}
	if ( ( ! defined $_[0]{rate} ) and $_[0]{tax_id} ) {
		$_[0]{rate} = $_[0]->Tax()->rate();
	}
	return $_[0]{rate};
}

1;
__END__
