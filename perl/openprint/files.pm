use strict;
package openprint::files;

use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

require sql;
require misc;
require handlers::upload;

sub index {
	ssi::save_params('/files/index.html', 'path');
	$session{'/files/index.html?path'} = handlers::upload::get_destdir() if ! exists $session{'/files/index.html?path'};
} # end sub index

sub _files {
	if ( $param{func} eq 'Delete' ) {
		my $error = '';
		foreach my $filename ( ref($param{files}) eq 'ARRAY' ? @{$param{files}} : $param{files} ) {
			my $full_path = join('/', $config{'ProjectFilesPath'}, $session{'/files/index.html?path'}, $filename);
			if ( ! unlink $full_path ) {
				$variable{error} .= "Error deleting file $full_path. Reason: $!<br/>";
			} # end if
		} # end foreach
	} # end if
} # end sub _files

1;
__END__
