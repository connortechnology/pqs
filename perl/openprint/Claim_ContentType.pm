use strict;
package openprint::Claim_ContentType;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;

$table = 'Claim_ContentTypes';
$serial = 'Claim_ContentTypes_id';
%fields = (
	'id'		=>	'id',
	'name'		=>	'name',
);

%transforms = (
);

%defaults = (
);

1;
__END__
