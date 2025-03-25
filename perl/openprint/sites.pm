use strict;
use warnings;

package openprint::sites;
use openprint;
use vars qw( %variable %session %param %config $log $dbh $r );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

require openprint::Site;
require openprint::Host;
require openprint::Host_Site;
require openprint::Location;

use Data::Dumper;

sub index {
}

sub list {
	_list();
	ssi::setup_date_select( $r->uri(), 'created_on_start', '' );
	ssi::setup_date_select( $r->uri(), 'created_on_end', '' );
	ssi::setup_date_select( $r->uri(), 'updated_on_start', '' );
	ssi::setup_date_select( $r->uri(), 'updated_on_end', '' );
} # end sub list

sub _list {
  if ($param{action}) {
    if ( $param{action} eq 'Delete' ) {
      foreach my $site_id ( ref $param{'site_id[]'} eq 'ARRAY' ? @{$param{'site_id[]'}} : $param{'site_id[]'} ) {
        my $Site = new openprint::Site( $site_id );
        $variable{error} .= $Site->delete();
      } # end foreach site_id
      %param = ();
    } else {
      $log->error("Unknown action $param{action}");
    } # end if
	} # end if
	ssi::save_params( '/sites/list.html', 
    ( map { 'created_on_start_' . $_ } ( 'year', 'month', 'day' ) ),
    ( map { 'created_on_end_' . $_ } ( 'year', 'month', 'day' ) ),
    ( map { 'updated_on_start_' . $_ } ( 'year', 'month', 'day' ) ),
    ( map { 'updated_on_end_' . $_ } ( 'year', 'month', 'day' ) ),
    'order',
  );
} # end sub _sites

sub view {
  my $Site = $variable{Site} = new openprint::Site( openprint::Site->transform(id=>$param{site_id}) );
}

sub edit {
  my $Site = $variable{Site} = new openprint::Site( openprint::Site->transform(id=>$param{site_id}) );
  if ($param{action}) {
    if ( $param{action} eq 'Delete' ) {
      $variable{error} .= $Site->delete();
      if (!$variable{error}) {
        $variable{ExternalRedirect} = '/sites/list.html';
        %param = ();
      } # end if
    } elsif ( $param{action} eq 'Save' ) {
      my $Site = new openprint::Site( $param{site_id} );
      $variable{error} .= $Site->save(\%param);
      if ( ! $variable{error} ) {
        %param = ();
        $variable{ExternalRedirect} = '/sites/list.html';
      } # end if
    } # end if
  } # end if param
} # end sub edit

sub _host_popup {
	my $Site = $variable{Site} = new openprint::Site($param{site_id});
	if ( ! $Site->id() ) {
		$variable{error} .= 'Site not found.';
		return;
	} # end if
} # end sub _host_popup

sub _host_results {
	my $Site = $variable{Site} = new openprint::Site($param{site_id});
	if ( ! $Site->id() ) {
		$variable{error} .= 'Site not found.';
		return;
	} # end if
} # end sub _host_results

sub _hosts {
  my $Site = $variable{Site} = new openprint::Site($param{site_id});
  if ( ! $Site->id() ) {
    $variable{error} .= 'Site not found.';
    return;
  } # end if
  if ($param{action}) {
    if ( $param{action} eq 'allocate' ) {
      my $Host = new openprint::Host($param{host_id});
      if ( ! $Host->id() ) {
        $variable{error} .= 'Host not found.';
        return;
      } # end if

      my $SH = new openprint::Host_Site();
      $variable{error} .= $SH->save({site_id=>$param{site_id}, host_id=>$param{host_id}});
    } elsif ( $param{action} eq 'delete' ) {
      my $SH = openprint::Host_Site->find_one( site_id=>$param{site_id}, host_id=>$param{host_id} );
      if ( ! $SH ) {
        $variable{error} .= 'Allocation not found.';
        return;
      } 
      $variable{error} .= $SH->delete();
    } # end if	
	} # end if action
} # end sub _hosts

1;
__END__
