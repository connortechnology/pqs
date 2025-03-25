use strict;
package openprint::StockManufacturer;
our @ISA = qw(openprint::Object);

use vars qw( $table $serial %fields %transforms %defaults $cache_field );

$cache_field = 'name';

$table = 'manufacturers';
$serial= 'manufacturers_id_seq';
%fields = (
		id		=>  'id',
		name	=>  'name',
);
%transforms = (
		name	=> [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
);

1;
__END__
