use strict;
package openprint::RFIDTagType;
our @ISA = qw(openprint::Object);
require openprint::Object;

use vars qw( $debug $serial $table %fields %transforms %defaults );

$debug = 0;
$table = 'rfidtagtypes';
$serial = 'rfidtagtypes_id_seq';

%fields = (
	id		=>	'id',
	name	=>	'name',
);

%transforms = (
);

%defaults = (
);

1;
__END__
