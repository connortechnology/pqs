use strict;
require openprint::Asset;
package openprint::Banner;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table %fields %transforms %defaults $serial );
$debug = 0;
$table = 'banners';
$serial = 'banners_id_seq';
%fields = (
	'id'	=>	'id',
	'name'	=>	'name',
	'url'	=>	'url',
	'asset_id'	=>	'asset_id',
	'supplier_id'	=>	'supplier_id',
);
%transforms = (
    'name' => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
);

sub Asset {
	return new openprint::Asset( $_[0]{'asset_id'} );
} # end sub Asset
1;
__END__
