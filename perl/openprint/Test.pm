use strict;
package openprint::Test;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'tests';
$serial = 'tests_id_seq';

%fields = ( 
	id	=>	'id',
	name=>	'name',
	description=>	'description',
	mandatory	=>	'mandatory',
);
%transforms = (
	id	=>	['s/\D//g'],
    name => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    description => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
	mandatory	=>	'0',
);

1;
__END__
