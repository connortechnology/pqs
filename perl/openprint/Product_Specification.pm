use strict;
package openprint::Product_Specification;
our @ISA = qw( openprint::Object );
use vars qw( $debug $table %fields %transforms %defaults $serial );

$debug = 0;
$serial = 'product_specifications_id_seq';
$table = 'product_specifications';

%fields = (
		'id'				=>	'id',
		'product_id'		=>	'product_id',
		'name'				=>	'name',
		'value'				=>	'value',
);
%transforms = (
    'name' => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    'value' => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);

%defaults = (
);

1;
__END__
