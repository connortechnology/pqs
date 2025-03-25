use strict;
package openprint::SRED_Content_Type;
our @ISA = qw(openprint::Object);
require openprint::Object;

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'sred_content_types';
$serial = 'sred_content_types_id_seq';

%fields = (
	'id'	=>	'id',
	'name'	=>	'name',
);

1;
__END__
