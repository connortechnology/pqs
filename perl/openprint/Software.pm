use strict;
package openprint::Software;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'software';
$serial='software_id_seq';
%fields = (
		id		=>	'id',
		name	=>	'name',
);
%transforms = (
		name => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
);

1;
__END__
