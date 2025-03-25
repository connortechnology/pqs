use strict;
package openprint::includes_main;

use openprint ();
use vars qw( $r %variable %session %param %config $log $dbh $starttime );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
require openprint::Project;

sub _additional_colour_coating {
  $variable{Project} = new openprint::Project($param{project_id});
}

sub _gatefolds {
}
1;
__END__

