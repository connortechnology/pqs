use strict;
package openprint::StockFinish;
our @ISA = qw(openprint::Object);

use vars qw( $table $serial %fields %transforms %defaults );

$table = 'stockfinishes';
$serial= 'stockfinishes_id_seq';
%fields = (
	'id'	=>	'id',
	'name'	=>	'name',
);
%transforms = (
	'name' => [ 's/^\s+//', 's/\s+$//', 's/\s\s+$/ /g' ],
);
%defaults = (
);

sub sort {
	shift if $_[0] eq 'openprint::StockFinish';
	return sort { $$a{'name'} cmp $$b{'name'} } @_;
}# end sub sort
1;
__END__
