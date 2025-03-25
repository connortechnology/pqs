use strict;
package openprint::Tax;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 1;

$table = 'taxes';
$serial = 'taxes_id_seq';

%fields = (
	id				=>	'id',
	rate			=>	'rate',
	state			=>	'state',
	country			=>	'country',
	period_start	=>	'period_start',
	period_end		=>	'period_end',
	name			=>	'name',
);

%transforms = (
	id		=>	[ 's/\D//g' ],
	rate	=>	[ 's/[^\d\.]//g' ],
);

%defaults = (
	rate			=>	undef,
	period_start	=>	undef,
	period_end		=>	undef,
);

1;
__END__
