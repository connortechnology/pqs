use strict;
package openprint::RSS;
our @ISA=('openprint::Object');


use vars qw ( $table $serial %fields %transforms %defaults );
%fields = (
	'id'	=>	'id',
	'name'	=>	'name',
	'url'	=>	'url',
	'created_on'	=>	'created_on',
	'updated_on'	=>	'updated_on',
	'scan_interval'	=>	'scan_interval',
	'last_scanned'	=>	'last_scanned',
	'next_scan'		=>	'next_scan',
);

1;
__END__
