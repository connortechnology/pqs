use strict;
package openprint::Expense_Tax;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %defaults %transforms );

require openprint::Expense;
require openprint::Tax;
require Math::Round;

$debug = 1;

$table = 'expense_taxes';
$serial = 'expense_taxes_id_seq';

%fields = (
	id		    	=>	'id',
	expense_id	=>	'expense_id',
  Expense     =>  undef,
	tax_id	  	=>	'tax_id',
	rate		  	=>	'rate',
	amount    	=>	'amount',
	charge	  	=>	'charge',
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
	my $self = shift;
  $$self{amount} = shift if @_;

	if ( !defined $$self{amount} ) {
    if ( !$$self{rate} ) {
      $openprint::log->error('No rate in '.$self->to_string());
      return undef;
    }
    if ( $self->charge() ) {
      my $Expense = $self->Expense();

      my $amount = $$Expense{amount};
      if ( !defined($amount) ) {
        $amount = $$Expense{total};
        if ( !defined($amount) ) {
          $$self{amount} = 0;
          $openprint::log->error('No amount in '.$Expense->to_string());
          return undef;
        }
        $amount = $amount / (1+($$self{rate}/100));
        #$openprint::log->error("calculated amouhnt from total: $amount = $$Expense{total} / ($$self{rate}/100);");
      }
      $$self{amount} = $amount * ($$self{rate}/100);
    } else {
      $$self{amount} = 0;
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

  my $Expense = $self->Expense();
  if ( ! $Expense ) {
    $openprint::log->error('No expense in ' . $self->to_string());
  }
	if ( $Expense->owner_id() and ( ! defined $$self{charge} ) ) {
		if ( $self->Tax()->period_end() ) {
			# See if tax is applicabale
			my $period_end = Date::Parse::str2time( $self->Tax()->period_end() );
			my $invoiced_on = Date::Parse::str2time( $Expense->invoiced_on() );
			if ( $period_end < $invoiced_on ) {
				$$self{charge} = 0;
				return $$self{charge};
			} # end if
		} # end if
    if ( $self->Tax()->period_start() ) {
      # See if tax is applicable
      my $period_start = Date::Parse::str2time( $self->Tax()->period_start() );
      if ( $Expense->invoiced_on()) {
        my $invoiced_on = Date::Parse::str2time( $Expense->invoiced_on() );
        if ( $period_start < $invoiced_on ) {
          $$self{charge} = 0;
          return $$self{charge};
        } # end if
      } # end if invoiced_on
    } # end if period_start
		if ( sets::isin( $self->name(), ['GST','HST'] ) ) {
			if ( $Expense->Company()->taxexempt1() eq 'Y' ) {
				$$self{charge} = 0;
			} else {
				$$self{charge} = 1;
			} # end if
		} elsif ( sets::isin( $self->name(), ['PST'] ) ) {
			if ( $Expense->Company()->taxexempt2() eq 'Y' ) {
				$$self{charge} = 0;
			} else {
				$$self{charge} = 1;
			} # end if
		} # end if 
	} # end if
	return $$self{charge};
} # end sub charge

sub rate {
	if ( @_ > 1 ) {
		$_[0]{rate} = $_[1];
	} # end if
	if ( ! defined $_[0]{rate} ) {
		$_[0]{rate} = $_[0]->Tax()->rate();
	} # end if
	return $_[0]{rate};
} # end sub rate

sub Expense {
  my $self = shift;
  $$self{Expense} = shift if @_;

  if ( (!$$self{Expense}) and $$self{expense_id} ) {
    $$self{Expense} = new openprint::Expense($$self{expense_id});
  }
  return $$self{Expense};
}

sub to_string {
  my $self = shift;
  my $type = ref($self);
  #return $type . ': '. join(' ' , map { $$self{$_} ? $_.' => '.(ref $$self{$_} eq 'ARRAY' ? join(',', @{$$self{$_}}) : $$self{$_} ) : () } keys %fields ).
  return 'Tax: '.$self->name().' '.$self->rate().'% charge: '.($self->charge() ? 'yes':'no').' amount: ' . $self->Expense()->Currency()->format($self->amount())."\n";

  #($$self{business_use} ? ' ' . $$self{business_use}. '% business = ' . $self->business_use_amount() : '').
  #"\nTaxes:".join("\n", map { $_->to_string() } $self->Taxes());
}
1;
__END__
