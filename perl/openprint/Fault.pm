use strict;
package openprint::Fault;
our @ISA = qw(openprint::Object);

use vars qw( $table $serial %fields %transforms %defaults );
$table = 'faults';
$serial = 'faults_id_seq';

%fields = ( 
	id	=>	'id',
	name=>	'name',
	description=>	'description',
);
%transforms = (
    name => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    description => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = ();

1;
__END__
