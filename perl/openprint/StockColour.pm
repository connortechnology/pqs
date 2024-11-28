use strict;
package openprint::StockColour;
our @ISA = qw(openprint::Object);

use vars qw( $table $serial %fields %transforms %defaults );

$table = 'stockcolours';
$serial= 'stockcolours_id_seq';
%fields = (
	id		=>  'id',
	name	=>  'name',
);
%transforms = (
    name	=> [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
);

sub sort {
	shift if $_[0] eq 'openprint::StockColour';
	return sort { $$a{'name'} cmp $$b{'name'} } @_;
}# end sub sort

1;
__END__
