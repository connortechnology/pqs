use strict;
package openprint::ZM_Monitor;
our @ISA = qw(openprint::Object);
#use ZoneMinder;
require openprint::ZM_Server;

use vars qw( $debug $table $serial %fields %defaults %transforms $dbh );
$debug = 0;
$table = 'Monitors';

%fields = (
	id				=>	'Id',
	name			=>	'Name',
	type			=>	'Type',
	function		=>	'Function',
	enabled			=>	'Enabled',
	width			=>	'Width',
	height			=>	'Height',
	max_fps			=>	'MaxFPS',
	alarm_max_fps	=>	'AlarmMaxFPS',
	path			=>	'Path',
	jpg_path		=>	'JPGPath',
	mjpeg_path		=>	'MJPGPath',
	host			=>	'Host',
	server_id		=>	'ServerId',
	public			=>	'public',
	protocol		=>	'Protocol',
	method			=>	'Method',

);

sub Server {
	if ( ! $_[0]{Server} ) {
		$_[0]{Server} = openprint::ZM_Server->find_one( dbh=>$dbh, id=>$_[0]{server_id} ) if $_[0]{server_id};
		if ( ! $_[0]{Server} ) {
			$_[0]{Server} = new openprint::ZM_Server();
		}

	}
	return $_[0]{Server};
}

sub source_stream_url {
$openprint::log->debug($_[0]->Server()->to_string() );
	#$return ($_[0]{type} eq 'Remote' and $_[0]{protocol} eq 'http' ) ? 
		#$'http://'.$_[0]{host}.$_[0]{path} :
		sprintf('https://%2$s:%3$d/cgi-bin/zms?mode=jpeg&amp;monitor=%1$d&amp;user=all&pass=p1GraPHic',
				$_[0]{id}, $_[0]->Server()->Hostname(), 30000+$_[0]{id});
} # end sub source_stream_url

sub source_snapshot_url {
	#return $_[0]{type} eq 'Remote' ? 'http://'.$_[0]{host}.($_[0]{jpg_path}?
		#$_[0]{jpg_path}:$_[0]{path}) :
			return sprintf('https://%2$s:%3$d/cgi-bin/zms?mode=single&amp;monitor=%1$d&amp;user=all&pass=p1GraPHic',
					$_[0]{id}, $_[0]->Server()->Hostname(), 30000+$_[0]{id} );
} # end sub source_snapshot_url

sub can_view {
	if ( $_[0]{public} ) {
		$openprint::log->debug("Public") if $debug;
		return 1;
	}
	if ( $openprint::session{user_type} eq 'A' ) {
		$openprint::log->debug("Admin") if $debug;
		return 1;
	}
	$openprint::log->debug("Not public") if $debug;
	return 0;
} # end sub can_view

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
