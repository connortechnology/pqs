use strict;
package openprint::MaterialSpecification;
our @ISA = qw( openprint::Object );
use openprint ();
use openprint::Material;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'Material_Specifications';
$serial = 'materialspecification_id_seq';

%fields = (
	'id'			=>	'id',
	'material_id'	=>	'material_id',
	'equipment_id'	=>	'equipment_id',
	'min'			=>	'min',
	'max'			=>	'max',
	'units'			=>	'units',
	'name'			=>	'name',
	'value'			=>	'value',
	'interpolate'	=>	'interpolate',
);

%transforms = (
	id				=>	[ 's/\D//g','<2147483647' ],
);
%defaults = (
	equipment_id	=>	undef,
	min				=>	undef,
	max				=>	undef,
	value			=>	undef,
	interpolate		=>	1,
);

1;
__END__
