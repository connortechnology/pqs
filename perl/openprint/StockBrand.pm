use strict;
package openprint::StockBrand;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'stockbrands';
$serial= 'stockbrands_id_seq';
%fields = (
	id		=>	'id',
	name	=>	'name',
);
%transforms = (
	name	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
);

sub sort {
	shift if $_[0] eq 'openprint::StockBrand';
	return sort { $$a{name} cmp $$b{name} } @_;
}# end sub sort
1;
__END__
