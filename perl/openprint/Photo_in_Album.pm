use strict;
package openprint::Photo_in_Album;
our @ISA = qw( openprint::Object );

require openprint;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'photos_in_albums';
$serial = 'photos_in_albums_id_seq';
%fields = (
	id			=>	'id',
	album_id	=>	'album_id',
	asset_id	=>	'asset_id',
	sort		=>	'sort',
	keywords	=>	undef,
);
%defaults = (
	sort		=>	undef,
	album_id	=>	undef,
	asset_id	=>	undef,
);


sub thumbnail_img {
	my $Asset = $_[0]->Asset();
	return sprintf('<img src="%s" class="thumbnail %s" alt="%s"/>',
			$Asset->sized_url('thumbnail'),
			$Asset->layout(), 
			$Asset->caption(), 
			);
} # end sub thumbnail_img

sub thumbnail_html {
	my $Asset = $_[0]->Asset();
	return sprintf('<a class="thumbnail %s" href="/photo_albums/view_photo.html?asset_id=%d&amp;album_id=%d" title="%s"><img src="%s" alt=""/></a>',
		$Asset->layout(), @{$_[0]}{'asset_id','album_id'}, $Asset->caption(), $Asset->sized_url('thumbnail') );
} # end sub thumbnail_html

sub medium_html {
	my $Asset = $_[0]->Asset();
	return sprintf('<a class="medium %s" href="/photo_albums/view_photo.html?asset_id=%d&amp;album_id=%d" title="%s"><img src="%s" alt=""/></a>',
		$Asset->layout(), @{$_[0]}{'asset_id','album_id'}, $Asset->caption(), $Asset->medium_url() );
} # end sub medium_html

sub thumbnail_url {
	my $Asset = $_[0]->Asset();
	return $Asset->sized_url('thumbnail');
} # end sub thumbnail_url 

sub url {
	my $Asset = $_[0]->Asset();
if ( ! $Asset ) {
$openprint::log->error('Photo_in_Album: no aasset in url: ');
}
	return $Asset->url();
} # end sub url 
sub sized_url {
	my $Asset = $_[0]->Asset();
if ( ! $Asset ) {
$openprint::log->error('Photo_in_Album: no aasset in url: ');
}
	return $Asset->sized_url( $_[1] );
} # end sub sized_url 

sub Album {
	return new openprint::Photo_Album( $_[0]{'album_id'} );
} # end sub Album

sub Comments {
	my $self = shift;
	return $self->Asset()->Comments( @_ );
} # end sub Comments

sub can_edit {
	return 1 if $openprint::session{'user_id'} == $_[0]->Asset()->created_by();
	return 1 if $openprint::session{'user_type'} eq 'A';
	return 0;
} # end sub can_edit

sub view_url {
	return '/photo_albums/view_photo.html?album_id='.$_[0]{'album_id'}.'&amp;asset_id='.$_[0]{'asset_id'};	
} # end sub view_url

sub name {
	return $_[0]->Album()->User()->name()."'s Photo";
} # end sub name

sub attribution {
	return $_[0]->Asset()->attribution();
} # end sub attribution

sub keywords {
	my $self = shift;
$openprint::log->debug("keywords @_ ");
	return $self->Asset()->keywords( @_ );
} # end sub keywords

sub delete {
	my $error = '';
	my $Album = $_[0]->Album();
	if ( $Album->thumbnail_id() == $_[0]{'asset_id'} ) {
		$error .= $Album->save({'thumbnail_id'=>undef});
	} # end if
	$error .= $_[0]->SUPER::delete() if ! $error;
	return $error;
} # end sub delete
1;
__END__
