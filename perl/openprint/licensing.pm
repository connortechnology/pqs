use strict;
use warnings;

package openprint::licensing;
use openprint;
use vars qw( %variable %session %param %config $log $dbh $r );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

require openprint::License;
require openprint::Software;
require openprint::Location;
require openprint::Site;

use Data::Dumper;

sub index {
}

sub licenses {
	_licenses();
	ssi::setup_date_select( '/licensing/licenses.html', 'created_on_start', '' );
	ssi::setup_date_select( '/licensing/licensess.html', 'created_on_end', '' );
	ssi::setup_date_select( '/licensing/licenses.html', 'updated_on_start', '' );
	ssi::setup_date_select( '/licensing/licenses.html', 'updated_on_end', '' );
} # end sub licenses

sub _licenses {
  if ($param{action}) {
    if ( $param{action} eq 'Delete' ) {
      foreach my $license_id ( ref $param{'license_id[]'} eq 'ARRAY' ? @{$param{'license_id[]'}} : $param{'license_id[]'} ) {
        my $License = new openprint::License( $license_id );
        $variable{error} .= $License->delete();
      } # end foreach license_id
      %param = ();
    } else {
      $log->error("Unknown action $param{action}");
    } # end if
	} # end if
	ssi::save_params( '/licensing/licenses.html', 
	( map { 'created_on_start_' . $_ } ( 'year', 'month', 'day' ) ),
	( map { 'created_on_end_' . $_ } ( 'year', 'month', 'day' ) ),
	( map { 'updated_on_start_' . $_ } ( 'year', 'month', 'day' ) ),
	( map { 'updated_on_end_' . $_ } ( 'year', 'month', 'day' ) ),
	( map { 'purchased_on_start_' . $_ } ( 'year', 'month', 'day' ) ),
	( map { 'purchased_on_end_' . $_ } ( 'year', 'month', 'day' ) ),
	( map { 'expires_on_start_' . $_ } ( 'year', 'month', 'day' ) ),
	( map { 'expires_on_end_' . $_ } ( 'year', 'month', 'day' ) ),
			'ip', 'hostname', 'mac', 'software_id', 'serialkey',
			'order',
			);
} # end sub _licenses

sub license {
  my $License = $variable{License} = new openprint::License( openprint::License->transform(id=>$param{license_id}) );
  if ($param{action} ) {
    if ( $param{action} eq 'Delete' ) {
      $variable{error} .= $License->delete();
      if ( ! $variable{error} ) {
        $variable{ExternalRedirect} = '/licensing/licenses.html';
        %param = ();
      } # end if
    } elsif ( $param{action} eq 'Save' ) {
      if ( 0 and $_ = openprint::License->find_one(serialkey=>$param{serialkey},
          ( $param{license_id} ? ('id !=' => $param{license_id}) : () ) ) ) {
        $variable{error} .= 'License has already been entered.  Click <a href="license.html?license_id='.$_->id().'">here</a> to view it.<br/>';
        return;
      } # end if
      if ( $param{software_id} ) {
        delete $param{software};
      } else {
        delete $param{software_id};
      } # end if
      my $features = {};
      foreach my $feature ('cameras','motion_detection', 'facial_recognition','object_detection','alpr') {
        $$features{$feature} = $param{"feature[$feature]"};
      }
      $param{features} = $features;

      my @changes = $License->changes(\%param);
      $log->debug("@changes");
      if (@changes) {
        $variable{error} .= $License->set(\%param);
        $License->generate_key();
        $variable{error} .= $License->save();
        if ( ! $variable{error} ) {
          %param = ();
          $variable{ExternalRedirect} = '/licensing/licenses.html';
        } # end if
      } # end if
    }
  } # end if
} # end sub license

sub _license_host_popup {
	my $License = $variable{License} = new openprint::License($param{license_id});
	if ( ! $License->id() ) {
		$variable{error} .= 'License not found.';
		return;
	} # end if
} # end sub _license_host_popup

sub _license_host_results {
	my $License = $variable{License} = new openprint::License($param{license_id});
	if ( ! $License->id() ) {
		$variable{error} .= 'License not found.';
		return;
	} # end if
} # end sub _license_host_results

sub _license_allocations {
	my $License = $variable{License} = new openprint::License($param{license_id});
	if ( ! $License->id() ) {
		$variable{error} .= 'License not found.';
		return;
	} # end if
	if ( $param{action} eq 'allocate' ) {
		my $Host = new openprint::Host($param{host_id});
		if ( ! $Host->id() ) {
			$variable{error} .= 'Host not found.';
			return;
		} # end if
		
		my $LH = new openprint::License_Host();
		$variable{error} .= $LH->save({license_id=>$param{license_id}, host_id=>$param{host_id}});
	} elsif ( $param{action} eq 'delete' ) {
		my $LH = openprint::License_Host->find_one( license_id=>$param{license_id}, host_id=>$param{host_id} );
		if ( ! $LH ) {
			$variable{error} .= 'Allocation not found.';
			return;
		} 
		$variable{error} .= $LH->delete();
	} # end if	
} # end sub _license_alliations

1;
__END__
