use strict;
package openprint::video_albums;
use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

require openprint;
require openprint::Video_Album;
require openprint::Asset;

sub list {
	my $Album = $variable{'Album'} = new openprint::Video_Album( $param{'album_id'} );
	if ( $param{'btnFunction'} eq 'Save' ) {
		$variable{'error'} .= $Album->save(\%param);
		new openprint::Log()->save({'action'=>'Create Video Album'}) if ! $param{'id'};

		if ( $param{'filename'} ) {
			my $upload = $r->upload('filename');
			if ( ! $upload ) {
				#$Asset->save({'file'=>''});
				$variable{'error'} .= "There was no upload for $param{'filename'}<br/>";
			} else {
				my $Asset = new openprint::Asset();
				$variable{'error'} .= $Asset->save({'filename'=>$param{'filename'}});
				if ( ! $upload->link( $Asset->on_disk_path() ) ) {
					$variable{'error'} .= "There was an error saving file $param{'filename'} to " . $Asset->on_disk_path() . ": $!<br/>";
#$Asset->save({'filename'=>''});
				} else {
					my $Video = new openprint::Video_in_Album();
					$variable{'error'} .= $Video->save({'asset_id'=>$Asset->id(), 'album_id'=>$Album->id()});	
					$variable{'information'} .= "File $param{'filename'} was uploaded successfully.<br/>";
					new openprint::Log()->save({'action'=>'Upload Video', 'Object'=>$Video});
				} # end if
			} # end if
		} # end if
		if ( $variable{'error'} ) {
			$variable{'Redirect'} = '/video_albums/edit.html';
		} # end if
	} elsif ( $param{'btnFunction'} eq 'Delete' ) {
		$variable{'error'} .= $Album->delete();
	} # end if
} # end sub list
sub _list {
} # end sub _list
sub view {
	my $Album = $variable{'Album'} = new openprint::Video_Album( $param{'album_id'} );
} # end sub view
sub edit {
	my $Album = $variable{'Album'} = new openprint::Video_Album( $param{'album_id'} );
} # end sub edit

sub _videos {
	my $Album = $variable{'Album'} = new openprint::Video_Album( $param{'album_id'} );
	if ( $param{'action'} eq 'set as thumbnail' ) {
		$variable{'error'} .= $Album->save({'thumbnail_id'=>$param{'asset_id'}});
	} elsif ( $param{'action'} eq 'delete' ) {
		my $Asset = new openprint::Asset( $param{'asset_id'} );
		foreach my $Video ( openprint::Video_in_Album->find( 'asset_id' => $Asset->id() ) ) {
			$variable{'error'} .= $Video->delete();
		} # end foreach Video
		$variable{'error'} .= $Asset->delete();
	} # end if
} # end sub video

sub view_video {
	$param{'asset_id'} =~ s/\D//g;
	$param{'album_id'} =~ s/\D//g;
	my $Video = new openprint::Video_in_Album( { 'asset_id' => $param{'asset_id'}, 'album_id'=> $param{'album_id'} } );
	if ( $Video->user_id() == $session{'user_id'} ) {
		if ( $param{'btnFunction'} eq 'Delete' ) {
			$variable{'error'} .= $Video->delete();
			if ( ! $variable{'error'} ) {
				$variable{'Redirect'} = '/video_album/view.html';
				%param = ( 'album_id' => $param{'album_id'} );
			} # end if
		} elsif ( $param{'btnFunction'} eq 'Undelete' ) {
			$variable{'error'} .= $Video->undelete();
		} elsif ( $param{'btnFunction'} eq 'Save' ) {
			$variable{'error'} .= $Video->save( \%param );
			if ( ! $variable{'error'} ) {
				$variable{'information'} .= 'Information successfully stored.<br/>';
			} # end if
		} elsif ( $param{'btnFunction'} eq 'Send' ) {
			$variable{'information'} .= $Video->send();
		} # end if btnfunction
	} # end if owner of the video
	$variable{'Video'} = $Video;
} # end sub view_video

sub _video_comments {
	my $Video = $variable{'Video'} = new openprint::Video_in_Album( { 'album_id'=>$param{'album_id'}, 'asset_id'=>$param{'asset_id'} } );
	if ( $param{'text'} =~ /\S/ ) {
		if ( ! openprint::Comment->find_one(
			'user_id'	=>	$session{'user_id'},
			'text'		=>	$param{'text'},
			'object_id'	=>	$Video->asset_id(),
			'object_type'	=>	'openprint::Asset',
			) ) {

			my $approved = 0;
			if ( $session{'user_type'} eq 'A' or $session{'user_id'} == $Video->Asset()->created_by() ) {
				$approved = 1;
			} # endif

			$variable{'error'} .= new openprint::Comment()->save({
					'text'			=>	$param{'text'},
					'object_type'	=>	'openprint::Asset',
					'object_id'		=>	$Video->Asset()->id(),
					'approved'		=>	$approved,
					});
		} # end if comment already exists
	} elsif ( $param{'action'} eq 'approve' ) {
		if ( $session{'user_type'} eq 'A' or $session{'user_id'} == $$Video->Asset()->user_id() ) {
			my $Comment = openprint::Comment->find_one('object_id'=>$$Video{'asset_id'}, 'object_type'=>'openprint::Asset', 'id'=>$param{'comment_id'} );
			if ( $Comment ) {
				$Comment->save({'approved'=>1});
			} else {
				$variable{'error'} .= 'Comment not found.';
			} # end if
		} else {
			$variable{'error'} .= 'You are not authorized to approve this comment.';
		} # end if
	} # end if
} # end sub _video_comments

sub videos {
} # end sub videos
1;
__END__
