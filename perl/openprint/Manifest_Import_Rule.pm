use strict;
package openprint::Manifest_Import_Rule;
our @ISA = qw(openprint::Object);

use vars qw( $table $serial %fields %transforms %defaults );

$table = 'manifest_import_rules';
$serial= 'manifest_import_rules_id_seq';
%fields = (
	id		=>	'id',
	match	=>	'match',
	replacement	=>	'replacement',
);
%transforms = (
);
%defaults = (
);

1;
__END__
