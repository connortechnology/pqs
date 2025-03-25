use strict;
package openprint::Feed;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'feeds';
$serial = 'feeds_id_seq';

%fields = (
	'id'			=>	'id',
	'name'			=>	'name',
	'type'			=>	'type',
	'url'			=>	'url',
	'company_id'	=>	'company_id',
	'category_id'	=>	'category_id',
	'filters'		=>	'filters',
	'published'		=>	'published',
	'active'		=>	'active',
);

%defaults = (
	'company_id'	=>	q`$openprint::session{'company_id'}`,
	'published'		=>	0,
	'active'		=>	0,
);

1;
__END__
