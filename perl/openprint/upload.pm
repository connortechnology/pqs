use strict;
package openprint::upload;
require handlers::upload;
require Number::Format;

use openprint ();
use vars qw( $log $dbh %variable %param %session );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*param = \%openprint::param;
*variable = \%openprint::variable;
*session = \%openprint::session;

sub upload_center {
} # end sub upload_center

sub _upload_form {
} # end sub _upload_form

sub _files {
$log->debug("Here");
   if ( $param{'btnFunction'} eq 'Delete' ) {
		my $destdir = handlers::upload::get_destdir();
		my $error = '';
		if ( $param{'chkFiles'} ) {
			foreach my $filename ( ref($param{'chkFiles'}) =~ /ARRAY/ ? @{$param{'chkFiles'}} : $param{'chkFiles'} ) {
				if ( ! unlink "$openprint::config{'ProjectFilesPath'}/$destdir$filename" ) {
					$error .= "Error deleting file $destdir$filename ! Reason: $!";
				} elsif ( $param{'project_id'} ) {
					sql::execute( $log, $dbh, q{DELETE FROM project_files WHERE project_id=? AND filename=?}, $param{'project_id'}, $destdir.$filename );
				} # end if
			} # end foreach

			if ( $error ne '' ) {
				$variable{'error'} .= 'Errors deleting files.';
				$variable{'information'} .= $error;
			} # end if
		} # end if chkFiles
	} # end if

} # end sub _files

1;
__END__
