use strict;
package openprint::Link;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'links';
$serial = 'links_id_seq';

%fields = (
	'id'	=>	'id',
	'name'	=>	'name',
	'href'	=>	'href',
	'count'	=>	'count',
	'sorting'	=>	'sorting',
	'_TEXT'		=>	undef,
	'text'		=>	'text',
);
%transforms = (
    'name' => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);

sub _TEXT {
	if ( @_ > 1 ) {
		$_[0]
	} # end if
	return sprintf('<a href="%s"%s%s>%s</a>', $_[0]{'href'},
		( $_[0]{'target'} ? ' target="'.$_[0]{'target'}.'"' : '' ),
		( $_[0]{'title'} ? ' title="'.$_[0]{'title'}.'"' : '' ),
	);
}
1;
__END__
