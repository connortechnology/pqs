use strict;
package openprint::ProjectType_Default;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults %find_fields );

$debug = 0;

$table = 'projecttype_defaults';
$serial = 'projecttype_defaults_id_seq';

%fields = (
	id				=>	'id',
	projecttype_id	=>	'projecttype_id',
	name			=>	'name',
	value			=>	'value',
);
%find_fields = (
	projecttype		=>	'(SELECT name FROM project_types WHERE id=projecttype_id)',
);

%transforms = (
	id				=>	[ 's/\D//g' ],
	projecttype_id	=>	[ 's/\D//g' ],
);

%defaults = (
	projecttype_id	=>	undef,
);

1;
__END__
