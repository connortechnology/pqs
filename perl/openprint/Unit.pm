use strict;
package openprint::Unit;
our @ISA = qw( openprint::Object );

use vars qw( $table $serial %fields );

$table = 'unit';
$serial = 'unit_id_seq';
%fields = (
	id	=>	'id',
	name	=>	'name',
);

 1;
__END__
