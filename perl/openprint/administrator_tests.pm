use strict;
package openprint::administrator_tests;

require openprint::Test;

use openprint ();
use vars qw( $r $log $dbh %variable %param %session );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*param = \%openprint::param;
*session = \%openprint::session;

sub edit {
	my $Test = new openprint::Test( $param{'test_id'} );

	if ( $param{'action'} eq 'Delete' ) {
		$Test->delete();
		$variable{'ExternalRedirect'} = '/administrator/tests/list.html';
	} elsif ( $param{'action'} eq 'Save' ) {
		$variable{'error'} .= $Test->save( { 
			name		=>	$param{name},
			description	=>	$param{description},
			mandatory	=>	$param{mandatory},
			});
		$variable{'ExternalRedirect'} = '/administrator/tests/list.html' if ! $variable{'error'};
	} # end if
	$variable{'Test'} = $Test;
} # end sub edit

sub list {
	_list();

} # end sub list

sub _list {
	if ( ! $param{'action'} ) {
		ssi::save_params( '/administrator/tests/list.html', ( 
 ) );
	} # end if
} # end sub _list
1;
__END__
