use strict;
package openprint::Company_Category;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %defaults %transforms );

$debug = 0;

$table = 'company_categories';
$serial = 'company_categories_id_seq';

%fields = (
	id				=>	'id',
	name			=>	'name',
	short			=>	'sort',
);

%transforms = (
    name => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    short => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
);

1;
__END__
