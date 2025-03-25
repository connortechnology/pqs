use strict;
require openprint::Object_Type;
require openprint::Object;
package openprint::Keyword;
our @ISA=('openprint::Object');


use vars qw ( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'keywords';
$serial = 'keywords_id_seq';
%fields = (
	id		=>	'id',
	word	=>	'word',
);
%transforms = (
	name => [ 's/^\s+//', 's/\s+$//', 's/\s\s+$/ /g', 'tr/[A-Z]/[a-z]/' ],
);

1;
__END__
