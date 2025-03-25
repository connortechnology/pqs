use strict;
package openprint::ZM_Server;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %defaults %transforms $dbh );
$debug = 0;
$table = 'Servers';

%fields = (
	id			=>	'Id',
	Name		=>	'Name',
	Hostname	=>	'Hostname',
);

sub connect {
    if ( ! ( $dbh and $dbh->ping() ) ) {
$dbh = sql::open_sql( $openprint::log,
              database  => $openprint::config{'zm_db_name'},
              driver    => $openprint::config{'zm_db_driver'},
              host      => $openprint::config{'zm_db_hostname'},
              login     => $openprint::config{'zm_db_username'},
              password  => $openprint::config{'zm_db_password'},
            );
    }
	return $dbh;
}


1;
__END__
