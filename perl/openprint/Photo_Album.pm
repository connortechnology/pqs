use strict;
require openprint::Asset;
require openprint::Photo_in_Album;
# A collection of Assets
package openprint::Photo_Album;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults );
$debug = 0;
$serial = 'photo_albums_id_seq';
$table = 'photo_albums';

%fields = (
	id				=>	'id',
	user_id			=>	'user_id',
	name			=>	'name',
	description		=>	'description',
	thumbnail_id	=>	'thumbnail_id',
	created_on		=>	'created_on',
	privacy_mode_id	=>	'privacy_mode_id',
	deleted			=>	'deleted',
);
%find_fields = (
	asset_id	=>	'(SELECT asset_id FROM Photos_in_Albums WHERE album_id=photo_albums.id)',
	company_id	=>	'(SELECT company_id FROM Users WHERE users.id=user_id)',
);

%defaults = (
	created_on		=>	q`'NOW()'`,
	thumbnail_id	=>	undef,
	deleted			=>	0,
);
%transforms = (
	id			=>	[ 's/\D//g', '<2147483647' ],
);

sub created_by {
	return $_[0]{user_id};
} # end sub

sub Thumbnail {
	if ( ! $_[0]{Thumbnail} ) {
		if ( ! $_[0]{thumbnail_id} ) {
	#$openprint::log->debug("Album $_[0]{id} No thumbnail assigned, showing first.");
			my @Photos = $_[0]->Photos();
	#$openprint::log->debug("Album $_[0]{id} $_[0]{name} No thumbnail assigned");
			if ( @Photos ) {
#$openprint::log->debug(", showing first. $Photos[0]{asset_id}");
			$_[0]{Thumbnail} = $Photos[0];
			} # end if
		} else {
			$_[0]{Thumbnail} = openprint::Photo_in_Album->find_one( 'asset_id'=>$_[0]{thumbnail_id}, 'album_id'=>$_[0]{id} );
		} # end if
		if ( ! $_[0]{Thumbnail} ) {
			$_[0]{Thumbnail} = new openprint::Photo_in_Album();
			$_[0]{Thumbnail}->set( { 'album_id'=>$_[0]{id} } );
		} # end if
	} # end if
	return $_[0]{Thumbnail};
} # end sub Thumbnail

sub thumbnail_url {
	my $Thumbnail = $_[0]->Thumbnail();
	$openprint::log->debug(ref$Thumbnail);
	return $Thumbnail->thumbnail_url();
} # end sub thumbnail_url

sub sized_url {
	my $Thumbnail = $_[0]->Thumbnail();
	return $Thumbnail->sized_url( $_[1] );
} # end sub thumbnail_url
	

sub thumbnail_html {
	my $Photo = $_[0]->Thumbnail();
	if ( $Photo->asset_id() ) {
#$openprint::log->debug("Photo has asset" . $Photo->to_string() );
		return sprintf('<a class="thumbnail" href="/photo_albums/view.html?album_id=%1$d" title="%3$s"><img src="%2$s" alt="%3$s" /></a>', $_[0]{id}, $Photo->thumbnail_url(), $_[0]->name() );
	} # end if
#$openprint::log->debug("Photo no asset"  );
	return sprintf('<a class="thumbnail" href="/photo_albums/view.html?album_id=%d" title="%s">Empty</a>', $_[0]{id}, $_[0]{name} );
} # end sub thumbnail_html

sub asset_html {
	my $Photo = $_[0]->Thumbnail();
	if ( $Photo->asset_id() ) {
$openprint::log->debug("Photo has asset" . $Photo->to_string() );
		return sprintf('<a class="asset" href="/photo_albums/view.html?album_id=%1$d" title="%3$s"><img src="%2$s" alt="%3$s" /></a>', $_[0]{id}, $Photo->url(), $_[0]->name() );
	} # end if
$openprint::log->debug("Photo no asset"  );
	return sprintf('<a class="thumbnail" href="/photo_albums/view.html?album_id=%d" title="%s">Empty</a>', $_[0]{id}, $_[0]{name} );
} # end sub asset_html

sub Photos {
	my $self = shift;
	$$self{Photos} = shift if @_;

	if ( $$self{id} and !$$self{Photos} ) {
		@{$$self{Photos}} = openprint::Photo_in_Album->find( album_id=>$$self{id}, order=>'asset_id');
	} # end if
	return $$self{Photos} ? @{$$self{Photos}} : ();
} # end sub Photos

sub destroy {
	my $error = '';
	foreach my $Photo ( $_[0]->Photos() ) {
		$error .= $Photo->destroy();
	} # end foreach Photo
	$error .= $_[0]->SUPER::destroy();
	return $error;
} # end sub delete

sub upload {
	my $error = '';
	my $Asset = openprint::Asset::upload($_[1], $_[2]);
	if (ref $Asset eq 'openprint::Asset') {
		my $Photo = openprint::Photo_in_Album->find_one(asset_id=>$$Asset{id}, album_id=>$_[0]{id});
		if (!$Photo) {
			$Photo = new openprint::Photo_in_Album();
			$error .= $Photo->save({ asset_id=>$$Asset{id}, album_id=>$_[0]->id() });   
			$error .= new openprint::Log()->save({'action'=>'Upload Photo', 'Object'=>$Photo});
		} else {
			#$error .= 'Photo already exists in album.';
		} # end if
	} else {
		$error .= "Failed to upload photo: $Asset";
    $openprint::log->error($error);
	} # end if
	return $error;
} # end sub upload

sub User {
	return new openprint::User( $_[0]{user_id} );
} # end sub User

sub can_edit {
	return 1 if ! $_[0]{id};
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if $openprint::session{user_id} and ( $_[0]{user_id} == $openprint::session{user_id} );
	return 0;
} # end sub can_edit

sub can_view {
	return 1 if ! $_[0]{id};
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if $_[0]{user_id} == $openprint::session{user_id};
	my $Privacy = $_[0]->Privacy();
	return 1 if ! $$Privacy{id};
	return $Privacy->can_view();
} # end sub can_view

sub copy {
	my $New = $_[0]->SUPER::copy();
	$New->save({created_on=>undef,user_id=>$openprint::session{user_id},deleted=>0});
	foreach my $Photo ( $_[0]->Photos() ) {
		my $NewPhoto = $Photo->copy();
		$NewPhoto->save({album_id=>$$New{id}});
	} # end foreach Photo
	return $New;
} # end sub copy

sub slider {
	my ( $Album, $size ) = @_;
	$size = 'medium' if ! $size;

  my @Assets = map { $_->Asset() } $_[0]->Photos();
	return openprint::Asset::slider( \@Assets, $size );
} # end sub slider

1;
__END__
