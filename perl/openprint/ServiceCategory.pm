use strict;
use warnings;

package openprint::ServiceCategory;
our @ISA = qw( openprint::Object );
require openprint::Service;

use vars qw( $debug $table $serial %fields %transforms %defaults $default_sort );

$debug = 0;
$default_sort = 'lower(strname)';
$table = 'tbl_Service_Categories';
$serial = 'Service_Categories_id_seq';

%fields = (
	id		=>	'lngindex',
	name	=>	'strname',
  strid =>  'strid',
  sort => 'lngsort',
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
