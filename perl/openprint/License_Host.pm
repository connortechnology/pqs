use strict;
package openprint::License_Host;
our @ISA = qw(openprint::Object);

require openprint::Host;
require openprint::License;

use vars qw( $debug $table @identified_by %fields %transforms %defaults );
$debug = 0;
$table = 'license_hosts';
@identified_by	= ( 'license_id', 'host_id' );
%fields = (
		license_id	=>	'license_id',
		host_id		=>	'host_id',
		comment	=>	'comment',
		created_on	=>	'created_on',
);
%transforms = (
);
%defaults = (
	license_id	=>	undef,
	host_id		=>	undef,
	created_on	=>	q`NOW()`,
);

sub Host {
	return new openprint::Host($_[0]{host_id});
} # end sub Host

sub License {
	return new openprint::License($_[0]{license_id});
} # end sub License

1;
__END__
