use strict;
package openprint::CAR_Area;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %defaults %transforms );

$debug = 0;
$table = 'car_areas';
$serial = 'car_areas_id_seq';

%fields = (
	'id'		=>	'id',
	'name'		=>	'name',
	'assignee_id'	=>	'assignee_id',
	'deleted'	=>	'deleted',
	'sorting'	=>	'sorting',
);

%transforms = (
);
%defaults = (
	'deleted'		=> 0,
);

1;
__END__
