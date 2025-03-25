use strict;
package openprint::Claim_Payment;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %defaults %transforms %find_fields );

$table = 'claim_payments';
$serial = 'claim_payments_id_seq';

require sql;
require openprint::Payment;

%fields = (
	'id'				=>	'id',
	'amount'			=>	'amount',
	'claim_id'			=>	'claim_id',
	'payment_id'		=>	'payment_id',
);
%find_fields = (
	'received_on'	=>	'(SELECT date FROM Payments WHERE Payments.id=payment_id)',
);

%transforms = (
	'amount'	=>	[ 's/[^\d\.]//g' ],
);
%defaults = (
	'amount'		=>	0,
);

sub save {
	my ( $self, $data ) = @_;
	my $ac = sql::start_transaction( $openprint::dbh );
	my $error = $self->SUPER::save( $data );
	#$error .= $self->Claime()->save({'paid'=>undef});
	$error .= $self->Payment()->save({'remaining'=>undef});
	sql::end_transaction( $openprint::dbh, $ac );
	return $error;
} # end sub save

1;
__END__
