use strict;
use Digest::MD5;
require openprint::Asset;
require openprint::Video_in_Album;
# A collection of Assets
package openprint::Video_Album;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$serial = 'video_albums_id_seq';
$table = 'video_albums';

%fields = (
	'id'				=>	'id',
	'user_id'			=>	'user_id',
	'name'				=>	'name',
	'thumbnail_id'		=>	'thumbnail_id',
	'created_on'		=>	'created_on',
	'privacy_mode_id'	=>	'privacy_mode_id',
	'deleted'			=>	'deleted',
);

%defaults = (
	'created_on'	=> q`'NOW()'`,
	'thumbnail_id'	=>	undef,
	'user_id'		=>	q`$openprint::session{'user_id'}`,
	'deleted'		=>	0,
);


sub created_by {
	return $_[0]{'user_id'};
} # end sub

sub Thumbnail {
	if ( ! $_[0]{'thumbnail_id'} ) {
		my @Videos = $_[0]->Videos();
		return $Videos[0] if @Videos;
	} # end if
	return new openprint::Video_in_Album( { 'asset_id'=>$_[0]{'thumbnail_id'}, 'album_id'=>$_[0]{'id'} } );
} # end sub Thumbnail

sub thumbnail_url {
	return $_[0]->Thumbnail()->thumbnail_url();
} # end sub thumbnail_url

sub Videos {
	if ( @_ > 1 or ! $_[0]{'Videos'} ) {
		@{$_[0]{'Videos'}} = openprint::Video_in_Album->find('album_id'=>$_[0]{'id'},'order'=>'asset_id');
	} # end if
	return @{$_[0]{'Videos'}};
} # end sub Videos

sub destroy {
	foreach my $Video ( $_[0]->Videos() ) {
		$Video->destroy();
	} # end foreach Video
} # end sub delete

sub upload {
	my $filename = $openprint::param{$_[1]};
	my $upload = $openprint::r->upload($_[1]);
	if ( ! $upload ) {
		return "There was no upload for $filename<br/>";
	} # end if
	my $data;
	$upload->slurp( $data );
	my $md5 = Digest::MD5::md5_hex( $data );
$openprint::log->debug("MD5: $md5");
	foreach my $Video ( $_[0]->Videos() ) {
		if ( $md5 eq $Video->Asset()->md5() ) {
			return "Video already exists in album.<br/>";
		} else {
			$openprint::log->debug("Videos md5: " . $Video->Asset()->md5() );
		} # end if
	} # end foreach
	my $error;
	my $Asset = new openprint::Asset();
	$error .= $Asset->save({'filename'=>$filename, 'md5'=>$md5});
	if ( ! $upload->link( $Asset->on_disk_path() ) ) {
		$error .= "There was an error saving file $filename to " . $Asset->on_disk_path() . ": $!<br/>";
	} else {
		my $data = misc::load_file( $openprint::log, $Asset->on_disk_path() );
		my $Video = new openprint::Video_in_Album();
		$error .= $Video->save({'asset_id'=>$Asset->id(), 'album_id'=>$_[0]->id()});
	} # end if
	return $error;
} # end sub upload
sub User {
	return new openprint::User( $_[0]{'user_id'} );
} # end sub User

sub can_edit {
	return 1 if ! $_[0]{'id'};
	return 1 if $openprint::session{'user_type'} eq 'A';
	return 1 if $_[0]{'user_id'} == $openprint::session{'user_id'};
	return 0;
} # end sub can_edit
sub can_view {
	return 1 if ! $_[0]{'id'};
	return 1 if $openprint::session{'user_type'} eq 'A';
	return 1 if $_[0]{'user_id'} == $openprint::session{'user_id'};
	my $Privacy = $_[0]->Privacy();
		
	return 1 if ! $$Privacy{'id'};
	return $Privacy->can_view();
} # end sub can_view
1;
__END__
