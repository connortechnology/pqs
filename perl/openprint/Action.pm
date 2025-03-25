package openprint::Department;
@ISA = qw( openprint::Object );
require openprint::Object;
use strict;
use warnings;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'departments';
$serial = 'departments_id_seq';
%fields = map { $_ => $_ } qw(
   id
   name
);
%transforms = (
);
%defaults = (
);

1;
__END__
