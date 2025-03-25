package openprint::Invoice_Payment;
@ISA = qw(openprint::Object);

use strict;
use vars qw( $debug $table $serial %fields %defaults %transforms %find_fields );

$debug = 0;
$table = 'invoices_payments';
$serial = 'invoices_payments_id_seq';

require sql;
require openprint::Invoice;
require openprint::Payment;
require Math::Round;

%fields = (
	id		    		=>	'id',
	amount		  	=>	'amount',
	invoice_id  	=>	'invoice_id',
	payment_id		=>	'payment_id',
);
%find_fields = (
		received_on	=>	'(SELECT received_on FROM Payments WHERE Payments.id=payment_id)',
);

%transforms = (
	amount	=>	[ 's/[^\d\.]//g' ],
);
%defaults = (
	amount		=>	0,
);

sub save {
	my ( $self, $data ) = @_;
	my $ac = sql::start_transaction( $openprint::dbh );
	my $error = $self->SUPER::save( $data );
	$error .= $self->Invoice()->save({ paid=>undef });
	$error .= $self->Payment()->save({ remaining=>undef });
	sql::end_transaction( $openprint::dbh, $ac );
	return $error;
} # end sub save

sub Payment {
  return new openprint::Payment($_[0]{payment_id});
}

sub value {
  return Math::Round::nearest( 0.01, $_[0]{amount} * $_[0]->Payment()->exchange() );
}

1;
__END__
