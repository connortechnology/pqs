use strict;
package openprint::MaterialCategory;
our @ISA = qw( openprint::Object );
require openprint::Material;
use openprint;

use vars qw( $table $serial %fields );

$table = 'Material_Categories';
$serial = 'material_categories_id_seq';
%fields = (
	'id'	=>	'id',
	'name'	=>	'name',
);

sub Materials {
	my $self = shift;
	return openprint::Material->find( 'category_id'=>$$self{'id'} );
} # end sub project_types

 1;
__END__
