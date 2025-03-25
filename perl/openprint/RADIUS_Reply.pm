use strict;
package openprint::RADIUS_Reply;
our @ISA = qw(openprint::Object);
use vars qw( $debug %fields %transforms %defaults $table $serial $dbh );
use vars qw( %attributes );


$debug = 0;
$table = 'radreply';
$serial = 'radreply_id_seq';
%fields = (
	id			=>	'id',
	username	=>	'username',
	attribute	=>	'attribute',
	op			=>	'op',
	value		=>	'value',
);

# Looks like contents of op for radreply should be an '=' not ':='
%attributes = (
	'Framed-IP-Address'		=>	'IP Address',
	'Framed-Route'			=>	'Router',
	'DHCP-Subnet-Mask'		=>	'DHCP Subnet Mask',
	'DHCP-Your-IP-Address'		=>	'DHCP IP Address',
	'DHCP-Router-Address'		=>	'DHCP Router Address',
	'DHCP-Bootp-Extensions-Path'		=>	'DHCP Bootp Externsions Path',
	'DHCP-TFTP-Server-Name'		=>	'DHCP TFTP Server Name',
);

sub connect {
	if ( $openprint::config{RADIUS_Support} eq 'Y' ) {
		if ( ! ( $dbh and $dbh->ping() ) ) {
			$dbh = sql::open_sql( $openprint::log,
					database	=> $openprint::config{RADIUS_DB_Name},
					driver		=> $openprint::config{RADIUS_DB_Driver},
					host		=> $openprint::config{RADIUS_DB_Server},
					login		=> $openprint::config{RADIUS_DB_Username},
					password	=> $openprint::config{RADIUS_DB_Password},
					);

			if ( ! $dbh ) {
				$openprint::log->error( 'Unable to connect to RADIUS DB server.' );
			} # end if
		}
	}
	return $dbh;
}
1;
__END__
