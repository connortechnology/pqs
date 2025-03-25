use strict;
require Math::Round;
require openprint::Tax;
package openprint::Invoice_Tax;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %defaults %transforms );

$debug = 1;

$table = 'invoice_taxes';
$serial = 'invoice_taxes_id_seq';

%fields = (
	id		    	=>	'id',
	invoice_id	=>	'invoice_id',
	tax_id	  	=>	'tax_id',
	rate		    =>	'rate',
	amount     	=>	'amount',
  charge      =>  'charge',
);

%transforms = (
);
%defaults = (
  rate    =>  undef,
  amount  =>  undef,
  charge => 0,
);

sub Tax {
	return new openprint::Tax( $_[0]{tax_id} );
} # end sub Tax

sub Invoice {
  return new openprint::Invoice($_[0]{invoice_id});
}

sub name {
	return $_[0]->Tax()->name();
} # end sub name

sub amount {
	my $self = $_[0];
	if ( @_ == 2 ) {
		$$self{amount} = $_[1];
	} # end if

  if (!$$self{charge}) {
    return '0.00';
  }

	if ( $$self{invoice_id} and ! defined $$self{amount} ) {
		$$self{amount} = ($$self{rate}/100) * $self->Invoice()->subtotal();
	} # end if
	return Math::Round::nearest( 1/(10**$self->Invoice()->Currency()->precision()), $$self{amount} );
} # end sub amount

sub charge {
  my $self = $_[0];
  if ( @_ == 2 ) {
    $$self{charge} = $_[1];
  } # end if

  if ( ( ! defined $$self{charge} ) and $self->Invoice()->invoicer_id() ) {
#$openprint::log->debug("Calculating Tax: " . $self->name() . 'exempt: ' . $self->PurchaseOrder()->Supplier()->taxexempt1() );
    if ( sets::isin( $self->name(), ['GST','HST'] ) ) {
      if ( $self->Invoice()->Invoicer()->taxexempt1() eq 'Y' ) {
        return 0;
      } # end if
      return 1;
    } elsif ( sets::isin( $self->name(), ['PST'] ) ) {
      if ( $self->Invoice()->Invoicer()->taxexempt2() eq 'Y' ) {
        return 0;
      } # end if
      return 1;
    } # end if
  } # end if
  return $$self{charge};
} # end sub charge
1;
__END__
