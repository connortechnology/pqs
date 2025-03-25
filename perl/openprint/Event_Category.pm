use strict;
package openprint::Event_Category;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %defaults %transforms );

$debug = 0;
$table = 'event_categories';
$serial = 'event_categories_id_seq';

%fields = (
	'id'				=>	'id',
	'name'				=>	'name',
	'description'		=>	'description',
	'image_filename'	=>	'image_filename',
);

%transforms = (
);
%defaults = (
);

1;
__END__
