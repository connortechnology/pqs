use strict;
use warnings;

package openprint::EquipmentSpecification;
our @ISA = qw( openprint::Object );
require openprint::Equipment;

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'tbl_Equipment_Specifications';
$serial = 'EquipmentSpecification_seq';

%fields = (
	id				=>	'lngindex',
	equipment_id	=>	'lngequipmentindex',
	min				=>	'dblmin',
	max				=>	'dblmax',
  range_units => 'range_units',
	name			=>	'strname',
	value			=>	'strvalue',
	units			=>	'strunits',
	interpolate		=>	'interpolate',
  sorting   => 'sorting',
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

sub to_breakdown {
  my $self = shift;
  return (1*$$self{value}).(lc $$self{units} eq 'percent' ? '%' : $$self{units}).'='.(1*$$self{total});
}

sub help {
  my $self = shift;
  return '';
}

1;
__END__
