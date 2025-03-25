use strict;
package openprint::Payment;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %defaults %transforms );

require sql;
require openprint::PaymentType;
require openprint::Invoice_Payment;
require openprint::Currency;
require openprint::Company;
require openprint::Order;
require openprint::Expense_Account;

$debug = 0;
$table = 'payments';
$serial = 'payments_id_seq';

%fields = (
  id				=>	'id',
  order_id		=>	'order_id',
  recipient_id	=>	'owner_id',
  payor_id		=>	'payor_id',
  amount			=>	'amount',
  amount_locked =>  'amount_locked',
  created_on		=>	'created_on',
  updated_on		=>	'updated_on',
  method			=>	'method',
  currency_id		=>	'currency_id',
  transaction_id	=>	'transaction_id',
  memo			=>	'memo',
  completed		=>	'completed',
  received_on		=>	'received_on',
  remaining		=>	'remaining',
  deleted			=>	'deleted',
  type_id			=>	'type_id',
  exchange  =>  'exchange',
  value     =>  'value',
  value_locked  =>  'value_locked',
  account_id  =>  'account_id',
);

%transforms = (
	amount  	=>	[ 's/[^\-\d\.]//g' ],
	exchange	=>	[ 's/[^\-\d\.]//g' ],
	value  	=>	[ 's/[^\-\d\.]//g' ],
);
%defaults = (
	order_id	=>	undef,
	created_on	=> q`'NOW()'`,
	updated_on	=> q`'NOW()'`,
	received_on	=>	undef,
	completed	=>	1,
	deleted		=>	0,
	owner_id	=>	q`$openprint::config{owner_id}`,
	amount		=>	undef,
	value		=>	undef,
	remaining	=>	undef,
  exchange  =>  undef,
  value_locked  =>  0,
  amount_locked =>  0,
  account_id    =>  undef,
);

sub save {
	$_[0]->set( $_[1] ) if $_[1];
	$_[0]->remaining(undef);
  my $error = $_[0]->SUPER::save( );
	if ( (!$error) and $_[0]{order_id} ) {
# Should check to see who is calling us and don't call Order->save if it's from Order->pay
# I put this back so that order paid status's update. 2018-08-07
		my $Order = $_[0]->Order();

		# Don't need to clear Payments and paid because those are done in Order->save
		#$Order->Payments(undef);
		#$Order->paid(undef);
		$error .= $Order->save();
	} # end if
	return $error;
} # end sub save

sub destroy {
	my $self = shift;
    sql::execute( undef, undef, q{DELETE FROM ledgers WHERE payment_id=?}, $$self{id} );
    return $self->SUPER::destroy();
} # end sub destroy

sub Payor {
	return new openprint::Company( $_[0]{payor_id} );
} # end sub Payor

sub Recipient {
	return new openprint::Company( $_[0]{owner_id} );
} # end sub Recipient

sub Currency {
	return new openprint::Currency( $_[0]{currency_id} );
} # end sub Currency
sub Order {
	return new openprint::Order( $_[0]{order_id} );
} # end sub Order

sub remaining {
	my $self = shift;
	if ( @_ ) {
		$$self{remaining} = $_[0];
	} # end if
	if ( ! defined $$self{remaining} ) {
		$$self{remaining} = $$self{amount} - misc::sum( map { $_->amount() } $self->Invoice_Payments() );
		$$self{remaining} = 0 if $$self{remaining} < 0;
	} # end if
	return $$self{remaining};
} # end sub remaining

sub Invoice_Payments {
	if ( @_ > 1 ) {
		$_[0]{Invoice_Payments} = $_[1];
	}
	if ( ( ! $_[0]{Invoice_Payments} ) and ( $_[0]{id} ) ) {
		$_[0]{Invoice_Payments} = [ openprint::Invoice_Payment->find( payment_id=>$_[0]{id}, order=>'invoice_id' ) ];
	} 

	return @{$_[0]{Invoice_Payments}} if $_[0]{Invoice_Payments};
	return ();
} # end sub Invoice_Payments

sub Type {
	return new openprint::PaymentType( $_[0]{type_id} );
} # end sub Type

sub send_receipt {
	my ( $self, @To ) = @_;

	my %data;
	$data{Payment} = $self;
	$data{uri} = 'payment';
	$data{User} = $openprint::User;
	my $email_template = ssi::slurp_content( '/email_template.html' );
	my @attachments;
	$data{ReplacementText} = ssi::include( '/email_content/payment_receipt.html', \%data );

	@To = $self->Payor()->AccountingContacts() if ! @To;

	my $Email = new openprint::Email();
	$Email->html_body( ssi::variable_substitution( \$email_template, \%data ) );
	my $results = $Email->send(
    TO			=>	\@To,
		BCC			=>	$openprint::User,
		FROM		=>	$data{User},
		#'ATTACHMENTS'	=>	\@attachments,
		SUBJECT		=>	'Thank you for your payment!',
	);
	(new openprint::Log())->save({Object=>$self, action=>'Email Sent', note=>$results });
	return $results;
	
} # end sub send_receipt

sub Invoices {
	if ( ! exists $_[0]{Invoices} ) {
		$_[0]{Invoices} = [ openprint::Invoice_Payment->find( payment_id=>$_[0]{id}, order=>'invoice_id' ) ];
	} # end if
	return @{$_[0]{Invoices}};
} # end sub Invoices

sub value {
  if ( ! $_[0]{value} ) {
    $_[0]{value} = Math::Round::nearest( 0.01, $_[0]{amount} * $_[0]->exchange() );
  }
  return $_[0]{value};
}

sub exchange {
  if ( !$_[0]{exchange} ) {
    if ( $_[0]{currency_id} and ( $_[0]{currency_id} != $$openprint::Currency{id} ) ) {
      my $Conversion = openprint::Currency_Conversion->find_one(
        from_id=>$_[0]{currency_id}, to_id=>$$openprint::Currency{id},
        'period_start null_or_<=' => $_[0]{received_on},
        'period_end null_or_>=' => $_[0]{received_on},
      );
      if ( $Conversion ) {
        $_[0]{exchange} = $$Conversion{rate};
      } else {
        $openprint::log->error("No rate found for exchange from $_[0]{currency_id} to $$openprint::Currency{id} for $_[0]{received_on}");
      }
    } else {
      $_[0]{exchange} = 1;
    }
  }
  return $_[0]{exchange};
}

sub Account {
  if ( !$_[0]{Account} ) {
    $_[0]{Account} = new openprint::Expense_Account( $_[0]{account_id} );
  }
  return $_[0]{Account};
}

1;
__END__
