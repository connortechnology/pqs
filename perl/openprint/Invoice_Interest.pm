package openprint::Invoice_Interest;
@ISA = qw(openprint::Object);

use openprint ();
use strict;
use vars qw( $debug $table $serial %fields %defaults %transforms );

$debug = 0;
$table = 'invoice_interests';
$serial = 'invoice_interests_id_seq';

%fields = (
	id		    		=>	'id',
	amount		  	=>	'amount',
	created_on	  =>	'created_on',
	updated_on		=>	'updated_on',
	description		=>	'description',
	compounded_on	=>	'compounded_on',
	invoice_id		=>	'invoice_id',
);

%transforms = (
);
%defaults = (
	invoice_id	=>	undef,
	created_on	=> q`'NOW()'`,
	updated_on	=> q`'NOW()'`,
	amount  		=>	0,
);

sub save {
	my ( $self, $data ) = @_;
	my $ac = sql::start_transaction( $openprint::dbh );
	my $error = $self->SUPER::save( $data );
  # I'm not sure this is a good idea.  It will ONLY update interest, not owing etc.
  # $error .= $self->Invoice()->save({ interest=>undef });
	sql::end_transaction( $openprint::dbh, $ac );
	return $error;
} # end sub save

1;
__END__
