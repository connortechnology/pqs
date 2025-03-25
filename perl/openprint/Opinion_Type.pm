use strict;
package openprint::Opinion_Type;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'opinion_types';
$serial= 'opinion_types_id_seq';
%fields = (
    'id'    =>  'id',
    'name' =>  'name',
);
%transforms = (
    'name' => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
);

1;
__END__
