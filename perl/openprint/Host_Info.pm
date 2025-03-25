use strict;
require openprint::Object;
require openprint::Host;

package openprint::Host_Info;
our @ISA = qw( openprint::Object );
use vars qw( $debug $table $serial %fields %transforms %defaults %types %find_fields );
$debug = 0;
$table = 'host_info';
$serial = 'host_info_id_seq';
%fields = (
	id			=>	'id',
	host_id		=>	'host_id',
	name		=>	'name',
	value		=>	'value',
);
%find_fields = (
);
%transforms = (
	id		=>	[ 's/\D//g' ],
	name	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	value	=>	[ 's/^\s+//', 's/\s+$//' ],
);

sub Host {
	return new openprint::Host( $_[0]{host_id} );
}

1;
__END__
