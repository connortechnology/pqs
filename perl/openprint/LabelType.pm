use strict;
package openprint::LabelType;
our @ISA = qw(openprint::Object);
require openprint::Object;

use openprint ();
use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'labeltypes';
$serial = 'labeltypes_id_seq';
%fields = (
	'id'	=>	'id',
	'name'	=>	'name',
);

%transforms = (
);

%defaults = (
);

1;
__END__
