use strict;
package openprint::Ledger;
our @ISA = qw(openprint::Object);
require openprint::Object;
require Math::Round;

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;

$table = 'Ledgers';
$serial = 'ledgers_id_seq';

%fields = (
	'id'				=>	'id',
	'owner_id'			=>	'owner_id',
	'payor_id'			=>	'payor_id',
	'memo'				=>	'memo',
	'credit'			=>	'credit',
	'debit'				=>	'debit',
	'payment_id'		=>	'payment_id',
	'created_on'		=>	'created_on',
	'total'				=>	'total',
	'occurred_on'		=>	'occurred_on',
	'currency_id'		=>	'currency_id',
	'account_id'		=>	'account_id',
);

%transforms = (
	'id'			=>	[ 's/\D//g' ],
	'owner_id'		=>	[ 's/\D//g' ],
	'payor_id'		=>	[ 's/\D//g' ],
	'payment_id'	=>	[ 's/\D//g' ],
	'currency_id'	=>	[ 's/\D//g' ],
	'account_id'	=>	[ 's/\D//g' ],
	'credit'		=>	[ 's/[^\d\.\-]//g' ],
	'debit'			=>	[ 's/[^\d\.\-]//g' ],
	'total'			=>	[ 's/[^\d\.\-]//g' ],
);

%defaults = (
);

sub Payor {
	return new openprint::Company( $_[0]{'payor_id'} );
} # end sub Payor

sub credit {
	if ( @_ > 1 ) {
		$_[0]{credit} = int($_[1] * 100);
	} # end if
	return Math::Round::nearest( 0.01, $_[0]{credit} / 100 );
} # end sub credit

sub debit {
	if ( @_ > 1 ) {
		$_[0]{debit} = int($_[1] * 100);
	} # end if
	return Math::Round::nearest( 0.01, $_[0]{debit} / 100 );
} # end sub debit

sub Currency {
	return new openprint::Currency( $_[0]{'currency_id'} );
} # end sub Currency

1;
#__END__
