use strict;
package openprint::RADIUS_Check;
our @ISA = qw(openprint::Object);
use vars qw( $debug %fields %transforms %defaults $table $serial $dbh );
use vars qw( %attributes );


$debug = 0;
$table = 'radcheck';
$serial = 'radcheck_id_seq';
%fields = (
	id			=>	'id',
	username	=>	'username',
	attribute	=>	'attribute',
	op			=>	'op',
	value		=>	'value',
);
%transforms = (
		username	=>	[ 's/^\s+//', 's/\s+$//' ],
		value	=>	[ 's/^\s+//', 's/\s+$//' ],
);

%attributes = (
	'Cleartext-Password'	=>	'Cleartext Password', 
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
