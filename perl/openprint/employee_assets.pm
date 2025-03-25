package openprint::employee_assets;
use strict;
require sql;
require misc;

require openprint::Asset;
require openprint::Claim_Asset;
require openprint::SRED_Asset;
require openprint::Article_Asset;

use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

sub history {
	if ( $param{btnFunction} eq 'Delete' ) {
		foreach my $asset_id ( ref $param{asset_id} eq 'ARRAY' ? @{$param{asset_id}} : split(',',$param{asset_id}) ) {
      my $Asset = new openprint::Asset( $asset_id );
      if ( $Asset->deleted() ) {
        $variable{error} .= $Asset->destroy();
      } else {
        $variable{error} .= $Asset->delete();
      }
      last if $variable{error};
		} # end foreach asset_id
		%param = ();
	} elsif ( $param{action} eq 'reset' ) {
		foreach ( 
				'created_on_start_year','created_on_start_month','created_on_start_day',
				'created_on_end_year','created_on_end_month','created_on_end_day'
				,'type_id', 'created_by', 'company_id', 'deleted', 'lastupdated' 
				) {
			delete $session{"/employee/assets/history.html?$_"};
		} # end foreach
	} # end if
	
	if ( ( ! $session{'/employee/assets/history.html?lastupdated'} ) or ( time - $session{'/employee/assets/history.html?lastupdated'} ) > ( 12*60*60 ) ) {
		ssi::setup_date_select( '/employee/assets/history.html', 'created_on_start', -30 );
		ssi::setup_date_select( '/employee/assets/history.html', 'created_on_end', '' );
		$session{'/employee/assets/history.html?deleted'} = 0 if ! exists $session{'/employee/assets/history.html?deleted'};
	} # end if
	ssi::save_params( '/employee/assets/history.html', ( 
				'created_on_start_year','created_on_start_month','created_on_start_day',
				'created_on_end_year','created_on_end_month','created_on_end_day'
				,'type_id', 'created_by', 'company_id', 'deleted'
				) );

} # end sub history

sub _history {
	ssi::save_params( '/employee/assets/history.html', ( 
				'created_on_start_year','created_on_start_month','created_on_start_day',
				'created_on_end_year','created_on_end_month','created_on_end_day',
				'type_id', 'created_by', 'company_id', 'deleted', 'public',
				) );
} # end sub _assets

sub view {
	$param{asset_id} =~ s/\s//g;
	my $Asset = new openprint::Asset( $param{asset_id} );
	if ( $param{btnFunction} eq 'Delete' ) {
		$variable{error} .= $Asset->delete();
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/employee/assets/history.html';
			%param = ();
		} # end if
	} elsif ( $param{btnFunction} eq 'Destroy' ) {
		$variable{error} .= $Asset->destroy();
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/employee/assets/history.html';
			%param = ();
		} # end if
	} elsif ( $param{btnFunction} eq 'Undelete' ) {
		$variable{error} .= $Asset->undelete();
	} elsif ( $param{btnFunction} eq 'Save' ) {
		$variable{error} .= $Asset->save( \%param );
		if ( ! $variable{error} ) {
			$variable{information} .= 'Information successfully stored.<br/>';
		} # end if
		if ( $param{filename} ) {
			$Asset->upload( 'filename' );
			my $upload = $r->upload('filename');
			if ( ! $upload ) {
				$Asset->save({'filename'=>''});
				$variable{error} .= "There was no upload for $param{filename}<br/>";
			} elsif ( ! $upload->link( $Asset->on_disk_path() ) ) {
				$variable{error} .= "There was an error saving file $param{filename} to " . $Asset->on_disk_path() . ": $!<br/>";
				$Asset->save({'filename'=>''});
			} else {
				$variable{information} .= "File $param{filename} was uploaded successfully.<br/>";
			} # end if
		} # end if
		%param = ();
	} elsif ( $param{btnFunction} eq 'Send' ) {
		$variable{information} .= $Asset->send();
	} # end if btnfunction
	$variable{Asset} = $Asset;
} # end sub view

sub edit {
	$variable{Asset} = new openprint::Asset($param{asset_id});
	if ( $param{btnFunction} eq 'Save' ) {
		my $Asset = $variable{Asset};
		$Asset->id( $param{asset_id} ) if ! $Asset->id();
		$variable{error} .= $Asset->save( \%param );
	} # end if
} # end sub edit

sub stream {
	my $Do = openprint::Opinion_Type->find_one('name'=>'Do');
	my $Dont = openprint::Opinion_Type->find_one('name'=>q`Don't`);

	if ( $param{action} eq 'Do' ) {
		my $Asset = new openprint::Asset($param{asset_id});
		$Asset->toggle_Opinion( $$Do{id} ) if $Do;
		my $O = $Asset->Opinion( $$Dont{id} ) if $Dont;;
		$O->delete() if $O;
	} elsif ( $param{action} eq 'Dont' ) {
		my $Asset = new openprint::Asset($param{asset_id});
		$Asset->toggle_Opinion( $$Dont{id} ) if $Dont;
		my $O = $Asset->Opinion( $$Do{id} ) if $Do;
		$O->delete() if $O;
	} # end if
} # end sub stream

sub _assets {
    $variable{Object} = $param{object_type}->new( $param{object_id} );
} # end sub _assets

1;
__END__
