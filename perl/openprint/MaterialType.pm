use strict;
package openprint::MaterialType;
our @ISA = qw( openprint::Object );
require openprint::Material;

use vars qw( $table $serial %fields );

$table = 'material_type';
$serial = 'material_type_id_seq';
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
