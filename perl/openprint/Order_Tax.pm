use strict;
package openprint::Order_Tax;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %defaults %transforms );

require Math::Round;
require openprint::Order;
require openprint::Tax;
require openprint::OrderedProject;

$debug = 0;

$table = 'order_taxes';
$serial = 'order_taxes_id_seq';

%fields = (
	id				=>	'id',
	order_id	=>	'order_id',
	tax_id		=>	'tax_id',
	rate			=>	'rate',
	amount		=>	'amount',
	charge		=>	'charge',
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
	my $self = $_[0];
	if ( @_ == 2 ) {
		$$self{amount} = $_[1];
	} # end if

	if ( ! defined $$self{amount} ) {
		if ( $self->charge() ) {
			$$self{amount} = 0;
			foreach my $Project ( $self->Order()->Ordered_Projects() ) {
				$$self{amount} += $Project->price() * ($$self{rate}/100);
			} # end foreach Project
			foreach my $Product ( $self->Order()->Products() ) {
				my $tax = $Product->total() * ($$self{rate}/100);
$openprint::log->debug("Calcing tax from product ".$Product->to_string()." $$Product{price} * $$self{rate}/100 = $tax");
				$$self{amount} += $tax;
			} # end foreach Project
		} # end if
		$$self{amount} = Math::Round::nearest(0.01, $$self{amount});
	} # end if
	return $$self{amount};
} # end sub amount

sub charge {
	my $self = $_[0];
	if ( @_ == 2 ) {
		$$self{charge} = $_[1];
	} # end if

	if ( $self->Order()->company_id() and ( ( ! defined $$self{charge} ) or sets::isin($self->Order()->status(), ['Re-Opened','Incomplete'] ) ) ) {
		if ( sets::isin( $self->name(), ['GST','HST'] ) ) {
			if ( $self->Order()->Company()->taxexempt1() eq 'Y' ) {
				$$self{charge} = 0;
			} # end if
			$$self{charge} = 1;
		} elsif ( sets::isin( $self->name(), ['PST'] ) ) {
			if ( $self->Order()->Company()->taxexempt2() eq 'Y' ) {
				$$self{charge} = 0;
			} # end if
			$$self{charge} = 1;
		} # end if 
	} # end if
	return $$self{charge};
} # end sub charge

1;
__END__
