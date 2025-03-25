use strict;
package openprint::maps;
use openprint ();
use vars qw( %variable %session %param %config $log $dbh $r );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

require openprint::Location;

sub index {
   if ( $param{'selected_name'} ) {
        $variable{'Selected'} = openprint::Location->find_one( 'name' => $param{'selected_name'} );
    } elsif ( $param{'selected_id'} ) {
        $variable{'Selected'} = new openprint::Location( $param{'selected_id'} );
    } # end if
    if ( $param{'location_name'} ) {
        $variable{'Location'} = openprint::Location->find_one( 'name' => $param{'location_name'} );
    } elsif ( $param{'location_id'} ) {
        $variable{'Location'} = new openprint::Location( $param{'location_id'} );
    } else {
        $variable{'Location'} = new openprint::Location( 1 );
    } # end if
    if ( defined $param{'parent'} and $variable{'Location'}->Parent() ) {
        $variable{'Location'} = $variable{'Location'}->Parent();
    } # end if
	if ( $variable{'Selected'} and ( $variable{'Selected'}->id() != $variable{'Location'}->id() ) ) {
$log->debug("selected $param{selected_id} $param{located_id} " . $variable{'Location'}->name() . ' -> ' . $variable{'Selected'}->name() );
		$variable{'MapFile'} = join('/', $variable{'Location'}->name(), $variable{'Selected'}->name() );
	} else {
		$variable{'MapFile'} = $variable{'Location'}->name();
	} # end if

} # end sub index

sub _popup {
	openprint::maps::index();
} # end sub _popup

1;
__END__
