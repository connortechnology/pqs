use strict;
package openprint::CAR_Reason;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %defaults %transforms );

$debug = 0;
$table = 'car_reasons';
$serial = 'car_reasons_id_seq';

%fields = (
	'id'		=>	'id',
	'name'		=> 'name',
	'deleted'	=> 'deleted',
	'sorting'	=>	'sorting',
);

%transforms = (
);
%defaults = (
	'deleted'		=> 0,
);

1;
__END__
