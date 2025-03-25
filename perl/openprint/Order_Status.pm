use strict;
package openprint::Order_Status;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults $default_sort );

$debug = 0;
$default_sort = 'name';
$table = 'order_statuses';
$serial= 'order_statuses_id_seq';
%fields = (
    id    =>  'id',
    name =>  'name',
);
%transforms = (
    name => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
);

sub sort {
	shift if $_[0] eq 'openprint::Order_Status';
	return sort { $$a{name} cmp $$b{name} } @_;
}# end sub sort
1;
__END__
