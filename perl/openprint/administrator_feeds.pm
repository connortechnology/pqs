use strict;
package openprint::administrator_feeds;

require openprint::Feed;
require openprint::Article_Category;

use openprint ();
use vars qw( $r $log $dbh %variable %param %session );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*param = \%openprint::param;
*session = \%openprint::session;

sub edit {
	my $Feed = new openprint::Feed( $param{'feed_id'} );

	if ( $param{'action'} eq 'Delete' ) {
		$Feed->delete();
		$variable{'ExternalRedirect'} = '/administrator/feeds/list.html';
	} elsif ( $param{'action'} eq 'Save' ) {
		$variable{'error'} .= $Feed->save( \%param );
		$variable{'ExternalRedirect'} = '/administrator/feeds/list.html' if ! $variable{'error'};
	} # end if
	$variable{'Feed'} = $Feed;
} # end sub edit

sub list {
	_list();

} # end sub list

sub _list {
	if ( ! $param{'action'} ) {
		ssi::save_params( '/administrator/feeds/list.html', ( 
					'company_id', ) );
	} # end if
} # end sub _list
1;
__END__
