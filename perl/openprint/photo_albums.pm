use strict;
package openprint::photo_albums;
use openprint ();
use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

require openprint::Photo_Album;
require openprint::Asset;

sub history {
	if ( $param{btnFunction} eq 'Delete' ) {
		my $Album = $variable{Album} = new openprint::Photo_Album( $param{album_id} );
		$variable{error} .= $Album->delete();
		%param = ();
	} elsif ( $param{btnFunction} eq 'Undelete' ) {
		my $Album = $variable{Album} = new openprint::Photo_Album( $param{album_id} );
		$variable{error} .= $Album->undelete();
		%param = ();
	} elsif ( $param{btnFunction} eq 'Destroy' ) {
		my $Album = $variable{Album} = new openprint::Photo_Album( $param{album_id} );
		$variable{error} .= $Album->destroy();
		%param = ();
	} # end if
	_history();
	if ( ( ! $session{'/photo_albums/history.html?lastupdated'} ) or ( time - $session{'/photo_albums/history.html?lastupdated'} ) > ( 12*60*60 ) ) {
		ssi::setup_date_select( '/photo_albums/history.html', 'created_on_start', -31 );
		ssi::setup_date_select( '/photo_albums/history.html', 'created_on_end', '' );
		ssi::setup_date_select( '/photo_albums/history.html', 'starting_on_start', 0 );
		ssi::setup_date_select( '/photo_albums/history.html', 'starting_on_end', '' );
		$session{'/photo_albums/history.html?deleted'} = 0;
		$session{'/photo_albums/history.html?company_id'} = $session{company_id} if ! $session{'/photo_albums/history.html?company_id'};
	} # end if
} # end sub history
sub _history {
	ssi::save_params( '/photo_albums/history.html', ( 
				'created_on_start_year','created_on_start_month','created_on_start_day',
				'created_on_end_year','created_on_end_month','created_on_end_day',
				'company_id', 'user_id', 'deleted' ) );
} # end sub _history

sub list {
	my $Album = $variable{Album} = new openprint::Photo_Album( $param{album_id} );
	if ( $param{btnFunction} eq 'Save' ) {
		$param{user_id} = $session{user_id};
		$variable{error} .= $Album->save(\%param);
		(new openprint::Log())->save({action=>'Create Photo Album', Object=>$Album}) if ! $param{album_id};
		$variable{error} .= $Album->Privacy()->save( {
				map { $_, $param{'privacy_'.$_} } ( 'mode','user_id','relationship_type_id','usergroup_id' )
			} );

        if ( $param{filename} ) {
			$variable{error} .= $Album->upload( 'filename' );
			$variable{information} .= "File $param{filename} was uploaded successfully.<br/>" if ! $variable{error};
        } # end if
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		$variable{error} .= $Album->delete();
	} # end if
	_list();
	$session{'/photo_albums/list.html?user_id'} = $session{user_id} if ! exists $session{'/photo_albums/list.html?user_id'};
} # end sub list

sub _list {
	ssi::save_params( '/photo_albums/list.html', ( 'user_id' ) );
} # end sub _list

sub view {
	my $album_id = openprint::Photo_Album->transform( id => $param{album_id} );
	my $Album = $variable{Album} = openprint::Photo_Album->find_one( id=>$album_id );
	if ( ! $Album ) {
		$variable{Album} = new openprint::Photo_Album();
		$variable{error} .= "No album found for id $album_id<br/>";
	}
} # end sub view

sub edit {
	my $Album = $variable{Album} = new openprint::Photo_Album( $param{album_id} );
	if ( $param{btnFunction} eq 'Save' ) {
		$param{user_id} = $session{user_id} if ! ( ( $session{user_type} eq 'A' ) and $param{user_id} );
		my @changes = $Album->changes( \%param );
		$variable{error} .= $Album->save(\%param) if @changes;

        if ( $param{filename} ) {
			$variable{error} .= $Album->upload( 'filename' );
			$variable{information} .= "File $param{filename} was uploaded successfully.<br/>" if ! $variable{error};
        } # end if
		my $Privacy = $Album->Privacy();
		my $changes = { map { $_, $param{'privacy_'.$_} } ( 'mode','user_id','relationship_type_id','usergroup_id' ) };
		push @changes, $Privacy->changes( $changes );
		$variable{error} .= $Privacy->save( $changes );
		(new openprint::Log())->save({
				action	=>	($param{album_id} ? 'Edit Photo Album' : 'Create Photo Album'),
				url		=>	'/photo_albums/view.html?album_id='.$Album->id(),
				Object	=>	$Album,
				note	=>	join('<br/>', @changes) ,
				}) if @changes;
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/photo_albums/view.html?album_id='.$$Album{id};
		} # end if
	} elsif ( $param{btnFunction} eq 'Upload' ) {
        if ( $param{filename} ) {
			$variable{error} .= $Album->upload( 'filename' );
			$variable{information} .= "File $param{filename} was uploaded successfully.<br/>" if ! $variable{error};
        } # end if
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		$variable{error} .= $Album->delete();
		$variable{ExternalRedirect} = '/photo_albums/list.html';
	} # end if
	$variable{Privacy} = $Album->Privacy();
} # end sub edit

sub _album_photos {
	my $Object;
	my $Album;
	if ( ( ! $param{album_type} ) or ( $param{album_type} eq 'openprint::Photo_Album' ) ) {
		$Album = $variable{Album} = new openprint::Photo_Album( $param{album_id} );
	} else {
		$Object = $variable{Album} = $param{album_type}->new( $param{album_id} );
		$Album = $Object->Album();
		if ( ! $Album->id() ) {
			$Album->save();
			$Object->save({'album_id'=>$Album->id()});
		} # end if
	} # end if

	if ( $param{action} eq 'set as album thumbnail' ) {
		$variable{error} .= $Album->save({thumbnail_id=>$param{asset_id}});
		$variable{error} .= $Object->save({thumbnail_id=>$param{asset_id}}) if $Object and exists $$Object{thumbnail_id};
	} elsif ( $param{action} eq 'add' ) {
		my ( $id, $filename ) = $param{filename} =~ /^(\d+)_(.+)$/; 
$log->debug("$id , $filename ");
			
		my $Asset = openprint::Asset->find_one('id'=>$id, 'filename'=>$filename );
		if ( ! $Asset ) {
			# May be a thumbnail, so let's strip off the extension
			my ( $blah, $extension ) = $filename =~ /(.+)\.([^\.]+)$/;
			$Asset = openprint::Asset->find_one('id'=>$id, 'filename like'=>$blah.'%' );
		} # end if
		if ( $Asset ) {
			if ( sets::isin( $Asset->id(), [ map { $_->asset_id() } $Album->Photos() ] ) ) {
				$variable{error} .= 'Asset already in album.';
			} elsif ( $$Album{id} ) {
				my $Photo = new openprint::Photo_in_Album();
				$variable{error} .= $Photo->save({'album_id'=>$$Album{id}, 'asset_id'=>$Asset->id()});
				$Album->Photos(undef);
			} else {
				my $Photo = new openprint::Photo_in_Album();
				$Photo->set({'asset_id'=>$Asset->id()});
				$Album->Photos($Photo);
			} # end if
		} else {
			$variable{error} .= 'Asset not found.';
		} # end if
	} elsif ( $param{action} eq 'add to album' ) {
		my $A = new openprint::Photo_Album( $param{a_id} );
		if ( ! $A->id() ) {
			$variable{error} .= 'Album does not exist<br/>';
			return;
		} # end if
		my $Photo = openprint::Photo_in_Album->find_one('album_id'=>$param{a_id}, 'asset_id'=>$param{asset_id});
		if ( $Photo ) {
			$variable{error} .= 'Photo is already in ' . $A->name().'<br/>';
			$log->error("Photo is already in $$A{name}");
			return;
		}
		my $Photo = new openprint::Photo_in_Album();
		$variable{error} .= $Photo->save({'album_id'=>$$A{id}, 'asset_id'=>$param{asset_id}});
	} elsif ( $param{action} eq 'remove from album' ) {
		my $Photo = openprint::Photo_in_Album->find_one('album_id'=>$param{a_id}, 'asset_id'=>$param{asset_id});
		$Photo->delete();
	} elsif ( $param{action} eq 'set as profile pic' ) {
		my $User = new openprint::User( $session{user_id} );
		$variable{error} .= $User->save({'asset_id'=>$param{asset_id}});
	} elsif ( $param{action} eq 'delete' ) {
		my $Asset = new openprint::Asset( $param{asset_id} );
		foreach my $Photo ( $Album->Photos() ) {
			next if $Photo->asset_id() != $Asset->id();
			$variable{error} .= $Photo->delete();
		} # end foreach Photo
		$Album->Photos(undef); # Refresh cache

		# Why am I deleting the asset?
		#$variable{error} .= $Asset->delete();
	} # end if
} # end sub _album_photos

sub _view_photo {
view_photo();
} # end sub _view_photo

sub view_photo {
	$param{asset_id} = openprint::Asset->transform( id => $param{asset_id} );
	$param{album_id} = openprint::Photo_Album->transform( id => $param{album_id} );

	if ( ! ( $param{asset_id} and $param{album_id} ) ) {
		# Search engines, etc might get here
		$variable{Photo} = new openprint::Photo_in_Album();
    $variable{Album} = new openprint::Photo_Album();
		return;
	} # end if

	my $Photo = openprint::Photo_in_Album->find_one( asset_id => $param{asset_id}, album_id=> $param{album_id} );
	if ( ! $Photo ) {
		$variable{Photo} = new openprint::Photo_in_Album();
		$log->warn("No photo for album $param{album_id} phto: $param{asset_id}");
    $variable{Album} = new openprint::Photo_Album();
		return;
	} # end if

	my $Album = $Photo->Album();

	if ( $Album->can_edit() ) {

		if ( $param{action} eq 'set as thumbnail' ) {
			$variable{error} .= $Album->save({'thumbnail_id'=>$param{asset_id}});
		} elsif ( $param{action} eq 'set as profile pic' ) {
			if ( $Album->user_id() == $session{user_id} ) {
				my $User = new openprint::User( $session{user_id} );
				$variable{error} .= $User->save({'asset_id'=>$param{asset_id}});
			} else {
				$variable{error} .= q`That photo isn't yours. Not cool.`;
				$log->error($variable{error} );
			} # end if
		} elsif ( $param{action} eq 'Do/Dont' ) {
			my $DoDont = openprint::Photo_Album->find_one('name'=>'Do/Dont','user_id is null'=>1);
			if ( ! $DoDont ) {
				$log->error("DoDont not found");
			} else {
				my $DoDontPhoto = new openprint::Photo_in_Album();
				$variable{error} .= $DoDontPhoto->save({'asset_id'=>$param{asset_id}, 'album_id'=>$DoDont->id()});
			} # end if
		} elsif ( $param{action} eq 'UnDo/Dont' ) {
			my $DoDont = openprint::Photo_Album->find_one('name'=>'Do/Dont','user_id is null'=>1);
			if ( ! $DoDont ) {
				$log->error("DoDont not found");
			} else {
				my $DoDontPhoto = openprint::Photo_in_Album->find_one( 'asset_id'=>$param{asset_id}, 'album_id'=>$DoDont->id() );
				$variable{error} .= $DoDontPhoto->delete() if $DoDontPhoto;
			} # end if
			
		} elsif ( $param{action} eq 'Delete' ) {
			if ( $Photo->can_edit() ) {
				$variable{error} .= $Photo->delete();
				if ( ! $variable{error} ) {
					$variable{ExternalRedirect} = '/photo_albums/view.html?album_id='.$param{album_id};
				} # end if
			} else {
				$variable{error} .= 'You cant delete that!';
			} # end if

		} elsif ( $param{action} eq 'Undelete' ) {
			$variable{error} .= $Photo->undelete();
		} elsif ( $param{btnFunction} eq 'Save' ) {
$log->debug("Saving");
			$variable{error} .= $Photo->save( \%param );
			if ( ! $variable{error} ) {
				$variable{information} .= 'Information successfully stored.<br/>';
			} # end if
		} elsif ( $param{btnFunction} eq 'Send' ) {
			$variable{information} .= $Photo->send();
		} # end if btnfunction
	} else {
		if ( ! $Photo ) {
			$log->error('Photo not found.');
		}
	} # end if owner of the photo
	$variable{Photo} = $Photo;
	$variable{Album} = $Album;
} # end sub view_photo

sub _photo_comments {
	my $Photo = $variable{Photo} = openprint::Photo_in_Album->find_one( 'album_id'=>$param{album_id}, 'asset_id'=>$param{asset_id} );
	if ( ! $Photo ) {
		$variable{error} .= 'Photo not found.';
		return;
	} # end if
	if ( $param{text} =~ /\S/ ) {
		if ( ! openprint::Comment->find_one(
			'user_id'	=>	$session{user_id},
			'text'		=>	$param{text},
			'object_id'	=>	$Photo->asset_id(),
			'object_type'	=>	'openprint::Asset',
			) ) {

			my $approved = 0;
			if ( $session{user_type} eq 'A' or $session{user_id} == $Photo->Asset()->created_by() ) {
				$approved = 1;
			} # endif

			$variable{error} .= new openprint::Comment()->save({
					'text'			=>	$param{text},
					'object_type'	=>	'openprint::Asset',
					'object_id'		=>	$Photo->Asset()->id(),
					'approved'		=>	$approved,
					});
		} # end if comment already exists
	} elsif ( $param{action} eq 'approve' ) {
		my $Comment = openprint::Comment->find_one('object_id'=>$$Photo{asset_id}, 'object_type'=>'openprint::Asset', 'id'=>$param{comment_id} );
		if ( $Comment ) {
			if ( $Comment->can_approve() ) {
				$Comment->save({'approved'=>1});
			} else {
				$variable{error} .= 'You do not have rights to approve that comment.';
$log->error("Attempt to approve a comment without rights");
			} # end if
		} else {
			$variable{error} .= 'Comment not found.';
		} # end if
	} elsif ( $param{action} eq 'remove' ) {
		my $Comment = openprint::Comment->find_one('object_id'=>$$Photo{asset_id}, 'object_type'=>'openprint::Asset', 'id'=>$param{comment_id} );
		if ( $Comment ) {
			if ( $Comment->can_delete() ) {
				$variable{error} .= $Comment->delete();
			} else {
				$variable{error} .= 'You do not have rights to delete that comment.';
$log->error("Attempt to delete a comment without rights");
			} # end if
		} else {
			$variable{error} .= 'Comment not found or you do not have rights to delete.';
		} # end if
	} # end if
} # end sub _photo_comments

sub _photo_actions {
	#my $Photo = $variable{Photo} = new openprint::
	my $Asset = $variable{Asset} = new openprint::Asset( $param{asset_id} );
	if ( ! $Asset->id() ) {
		$variable{error} .= "Asset $param{asset_id} not found.";
		return;
	} # end if
	if ( $param{function} eq 'rotate' ) {
		require IPC::Run3;
		my $filepath = $Asset->on_disk_path();
		my $command = "convert -rotate $param{degrees} $filepath $filepath";
		my $stdout;
		my $stderr;
		IPC::Run3::run3($command, undef, $stdout, $stderr );
		if ( $? ) {
			$variable{error} .= "Error rotating. command was($command) output is ($stdout) error is ($stderr)<br/>";
			$log->error( 'error rotating ' . $? );
		} # end if
		# Need to remove all sized versions
		foreach my $size ( 'small','medium','large' ) {
			my $path = $Asset->sized_path( $size );
			if ( -e $path ) {
				unlink $path;
			} # end if
		} # end foreach
	} # end if function
} # end sub _photo_actions

sub photos {
	_photos();
} # end sub photos

sub _photos {
	ssi::save_params( '/photo_albums/photos.html', ( 'company_id','user_id' ) );
} # end sub _photos

sub upload {
	my $album = $variable{Album} = new openprint::Photo_Album();
  if ($param{action}) {
	  if ( $param{action} eq 'Upload' ) {
    } elsif ($param{action} eq 'Save' ) {
      if ($param{choose_album} eq 'new') {
        $album->save({
            name=>$param{name},
            user_id=>$openprint::User->id(),
            #privacy_mode_id=>
          });
      }
    }
	} # end if
} # end sub upload

1;
__END__
