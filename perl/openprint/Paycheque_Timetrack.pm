use strict;
require openprint::Timetrack;
require openprint::Paycheque;
package openprint::Paycheque_Timetrack;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table @identified_by %fields %defaults %transforms );

$debug = 0;

$table = 'paycheques_timetracks';
@identified_by = ( 'timetrack_id', 'paycheque_id' );

%fields = (
	paycheque_id	=>	'paycheque_id',
	timetrack_id	=>	'timetrack_id',
);

%transforms = (
);
%defaults = (
);


sub Timetrack {
	return new openprint::Timetrack( $_[0]{timetrack_id} );
} # end sub Payor

sub Paycheque {
	return new openprint::Paycheque( $_[0]{paycheque_id} );
} # end sub Paycheque

1;
__END__
