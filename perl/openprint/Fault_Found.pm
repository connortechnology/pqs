use strict;
package openprint::Fault_Found;
our @ISA = qw(openprint::Object);
require openprint::Fault;

use vars qw( $table $serial %fields %transforms %defaults );
$table = 'faults_found';
$serial = 'faults_found_id_seq';

%fields = ( 
	id			=>	'id',
	fault_id	=>	'fault_id',
	rma_id		=>	'rma_id',
	action		=>	'action',
	quantity	=>	'quantity',
	user_id		=>	'user_id',
	repaired_on	=>	'repaired_on',
);
%transforms = (
	id		=>	[ 's/\D//g' ],
    action	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
	repaired_on	=>	q`'NOW()'`,
	user_id		=>	q`$session{user_id}`,
);


sub Fault {
	return new openprint::Fault( $_[0]{fault_id} );
} # end sub Fault

sub Technician {
	return new openprint::User( $_[0]{user_id} );
} # end sub Technician

1;
__END__
