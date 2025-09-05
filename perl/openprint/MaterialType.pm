use strict;
use warnings;

package openprint::MaterialType;
our @ISA = qw( openprint::Object );
require openprint::Material;

use vars qw( $debug $table $serial %fields $default_sort);

$debug = 1;

$table = 'material_type';
$serial = 'material_type_id_seq';
$default_sort = 'lower(name)';
%fields = (
	id	=>	'id',
	name	=>	'name',
  price_unit => 'price_unit',
  range_unit => 'range_unit',
);

sub Materials {
	my $self = shift;
	return openprint::Material->find(type_id=>$$self{id});
} # end sub project_types

 1;
__END__
