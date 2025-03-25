use strict;
use warnings;

package openprint::EquipmentSpecification;
our @ISA = qw( openprint::Object );
require openprint::Equipment;

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 1;
$table = 'tbl_Equipment_Specifications';
$serial = 'tbl_equipment_specifications_id_seq';

%fields = (
	id				=>	'id',
	equipment_id	=>	'lngequipmentindex',
	min				=>	'dblmin',
	max				=>	'dblmax',
  range_units => 'range_units',
	name			=>	'strname',
	value			=>	'strvalue',
	units			=>	'strunits',
	interpolate		=>	'interpolate',
);
%transforms = (
	min		=> [ 's/[^\d\.]//g' ],
	max		=> [ 's/[^\d\.]//g' ],
	name	=> [ 's/^\s+//', 's/\s+$//' ],
	value	=> [ 's/^\s+//', 's/\s+$//' ],
);
%defaults = (
	min	=>	undef,
	max	=>	undef,
	value	=>	undef,
	interpolate	=>	0,
);

sub Equipment {
	return new openprint::Equipment( $_[0]{equipment_id} );
} # end sub Equipment

1;
__END__
