use strict;
package openprint::WorkOrder_Status;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'workorder_statuses';
$serial= 'workorder_statuses_id_seq';
%fields = (
	id	=>	'id',
	name=>	'name',
);
%transforms = (
	name => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
);

sub sort {
	return sort { $$a{'name'} cmp $$b{'name'} } @_;
}# end sub sort
1;
__END__
