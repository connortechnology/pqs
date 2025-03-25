use strict;
require openprint::Object;
package openprint::PurchaseOrder_ContentType;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;

$table = 'PurchaseOrder_ContentTypes';
$serial = 'PurchaseOrder_ContentTypes_id_seq';
%fields = (
	'id'		=>	'id',
	'name'		=>	'name',
	'type'		=>	'type',
);

%transforms = (
);

%defaults = (
);

1;
__END__
