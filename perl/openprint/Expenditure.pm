use strict;
package openprint::Expenditure;
our @ISA = qw(openprint::Object);
require openprint::Object;
require Math::Round;

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;

$table = 'expenditures';
$serial = 'expenditures_id_seq';

%fields = (
	'id'				=>	'id',
	'owner_id'			=>	'owner_id',
	'description'		=>	'description',
	'amount'			=>	'amount',
	'created_on'		=>	'created_on',
	'occurred_on'		=>	'occurred_on',
	'currency_id'		=>	'currency_id',
	'federaltax_rate'	=>	'federaltax_rate',
);

%transforms = (
	'id'				=>	[ 's/\D//g' ],
	'owner_id'			=>	[ 's/\D//g' ],
	'currency_id'		=>	[ 's/\D//g' ],
	'amount'			=>	[ 's/[^\d\.\-]//g' ],
	'federaltax_rate'	=>	[ 's/[^\d\.]//g' ],
);

%defaults = (
	'occurred_on'		=>	'NOW()',
);

sub Payor {
	return new openprint::Company( $_[0]{'payor_id'} );
} # end sub Payor

sub Currency {
	return new openprint::Currency( $_[0]{'currency_id'} );
} # end sub Currency

sub federaltax {
	return Math::Round::nearest( 0.01, $_[0]{amount} * $_[0]{federaltax_rate}/100 );
} # end sub federaltax

1;
#__END__
