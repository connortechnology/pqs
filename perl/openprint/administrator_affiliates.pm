use strict;
package openprint::administrator_affiliates;

require openprint::Affiliate;

use openprint ();
use vars qw( $r $log $dbh %variable %param %session );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*param = \%openprint::param;
*session = \%openprint::session;

sub edit {
	my $Affiliate = new openprint::Affiliate( $param{'affiliate_id'} );

	if ( $param{'action'} eq 'Delete' ) {
		$Affiliate->delete();
		$variable{'ExternalRedirect'} = '/administrator/affiliates/list.html';
	} elsif ( $param{'action'} eq 'Save' ) {
		$variable{'error'} .= $Affiliate->save( \%param );
		$variable{'ExternalRedirect'} = '/administrator/affiliates/list.html' if ! $variable{'error'};
	} # end if
	$variable{'Affiliate'} = $Affiliate;
} # end sub edit

sub list {
	_list();
	if ( ( ! $session{'/administrator/affiliates/list.html?lastupdated'} ) or ( time - $session{'/administrator/affiliates/list.html?lastupdated'} ) > ( 12*60*60 ) ) {
		ssi::setup_date_select( '/administrator/affiliates/list.html', 'created_on_start', -31 );
		ssi::setup_date_select( '/administrator/affiliates/list.html', 'created_on_end', '' );
	} # end if

} # end sub list

sub _list {
    if ( $param{'update'} ) {
        $param{'update'} =~ s/affiliates\[\]=//g;
        my $i = 0;
        foreach my $affiliate_id ( split('&', $param{'update'} ) ) {
            my $Affiliate = new openprint::Affiliate( $affiliate_id );
            $Affiliate->save({'sort'=>$i});
            $i += 1;
        } # end foreach $affiliate_id
	} elsif ( ! $param{'action'} ) {
		ssi::save_params( '/administrator/affiliates/list.html', ( 
					'created_on_start_year','created_on_start_month','created_on_start_day',
					'created_on_end_year','created_on_end_month','created_on_end_day',
					'supplier_id', ) );
    } # end if
} # end sub _list
1;
__END__
