use strict;
package openprint::ServiceCategory;
our @ISA = qw( openprint::Object );
require openprint::Service;

use vars qw( $debug $table $serial %fields %transforms %defaults $default_sort );

$debug = 0;
$default_sort = 'lower(name)';
$table = 'Service_Categories';
$serial = 'Service_Categories_id_seq';

%fields = (
	id		=>	'id',
	name	=>	'name',
);
%transforms = (
);
%defaults = (
);

sub Services {
	if ( ! $_[0]{Services} ) {
		$_[0]{Services} = [ openprint::Service->find( category_id=>$_[0]{id} ) ];
	} # end if 
	return @{$_[0]{Services}};
} # end sub Services

1;
__END__
