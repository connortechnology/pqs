use strict;
package openprint::Object_Payment;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %defaults %transforms %find_fields );

$debug = 0;
$table = 'object_payments';
$serial = 'object_payments_id_seq';

require sql;
require openprint::Payment;

%fields = (
	id				=>	'id',
	amount			=>	'amount',
	payment_id		=>	'payment_id',
	object_id		=>	'object_id',
	object_type_id	=>	'object_type_id',
	object_type		=>	undef,
);
%find_fields = (
	received_on		=>	'(SELECT date FROM Payments WHERE Payments.id=payment_id)',
	object_type		=>	'(SELECT name FROM object_types WHERE object_types.id=object_type_id)',
);

%transforms = (
	amount	=>	[ 's/[^\d\.]//g' ],
);
%defaults = (
	amount	=>	0,
);

sub Payment {
	return new openprint::Payment( $_[0]{payment_id} );
} # end sub Payment

sub save {
	my ( $self, $data ) = @_;
	my $ac = sql::start_transaction( $openprint::dbh );
	my $error = $self->SUPER::save( $data );
	$error .= $self->Object()->save({ payments_total=>undef});
	$error .= $self->Payment()->save({ remaining=>undef});
	sql::end_transaction( $openprint::dbh, $ac );
	return $error;
} # end sub save

sub delete {
	my ( $self ) = @_;
	my $ac = sql::start_transaction( $openprint::dbh );
	$self->Payment()->delete();
	my $error = $self->SUPER::delete();
	$openprint::dbh->rollback() if $error;
	$self->Object()->Payments( undef );
	sql::end_transaction( $openprint::dbh, $ac );
	return $error;
} # end sub delete

1;
__END__
