use strict;
require openprint;
require openprint::Keyword;
use Fcntl qw(:flock);

package openprint::Asset_Type;
our @ISA = qw(openprint::Object);
use vars qw( $debug %fields %transforms %defaults $table $serial );
$debug = 0;
$table = 'asset_types';
$serial = 'asset_types_id_seq';
%fields = (
	id		=>	'id',
	name	=>	'name',
);

package openprint::Asset;
our @ISA = qw(openprint::Object);

use vars qw( $debug %fields %transforms %defaults $table $serial );

$debug = 1;

%fields = (
	id			=>	'id',
	company_id	=>	'company_id',
	created_by	=>	'created_by',
	type_id		=>	'type_id',
	name		=>	'name',
	description	=>	'description',
	filename	=>	'filename',
	data		=>	'data',
	created_on	=>	'created_on',
	updated_on	=>	'updated_on',
	deleted		=>	'deleted',
	md5			=>	'md5',
	attribution	=>	'attribution',
	license		=>	'license',
	keywords	=>	undef,
	optimised	=>	'optimised',
	layout		=>	'layout',
	width		=>	'width',
	height		=>	'height',
	source		=>	'source',
	public		=>	'public',
);
%defaults = (
	data		=>	undef,
	type_id		=>	undef,
	created_on	=>	q`'NOW()'`,
	updated_on	=>	q`'NOW()'`,
	created_by	=>	q`$openprint::session{user_id}`,
	company_id	=>	q`$openprint::session{company_id}`,
	md5			=>	undef,
	deleted		=>	0,
	optimised	=>	0,
	layout		=>	'',
	width		=>	undef,
	height		=>	undef,
	public	=>	0,
);
%transforms = (
	id			=>	[ 's/\D//g', '<2147483647' ],
	width		=>	[ 's/\D//g' ],
	height		=>	[ 's/\D//g' ],
	filename	=>	[ 's/^\s+//', 's/\s+$//', 's/ /_/g', 's/[\/:\*\?\'"<>|]//g', 's/&/n/g' ],
	name		=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	description	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	attribution	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	license		=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
$table = 'assets';
$serial = 'assets_id_seq';

sub Type {
	return new openprint::Asset_Type( $_[0]{type_id} );
} # end sub Type

sub on_disk_path {
	return $openprint::config{AssetPath}.'/'.$_[0]->on_disk_filename();
} # end sub on_disk_path

sub on_disk_filename {
	return '' if ! $_[0]{id};
	$_ = $_[0]{id}.'_'.$_[0]{filename};
	return $_;
} # end sub on_disk_filename

sub url {
	return '/assets/'.$_[0]->on_disk_filename();
}

sub is_video {
	my $extension;
	if ( ref $_[0] eq 'openprint::Asset' ) {
		my $filename = $_[0]->on_disk_filename();
		( $extension ) = $filename =~ /.+\.([^\.]+)$/;
	} else {
		$extension = $_[0];
	} # end if
	return sets::isin( lc $extension, [ '3gp', '3g2', 'asf', 'avi', 'dat', 'divx', 'dsm', 'evo', 'flv', 'm1v', 'm2ts', 'm2v', 'm4a', 'mj2', 'mjpg', 'mjpeg', 'mkv', 'mov', 'moov', 'mp4', 'mpg', 'mpeg', 'mpv', 'nut', 'ogg', 'ogm', 'qt', 'swf', 'ts', 'vob', 'wmv', 'xvid' ] );
} # end sub is_video

sub is_photo {
	my $extension;
	if ( ref $_[0] eq 'openprint::Asset' ) {
		my $filename = $_[0]->on_disk_filename();
		( $extension ) = $filename =~ /.+\.([^\.]+)$/;
	} else {
		$extension = $_[0];
	} # end if
	return sets::isin( lc $extension, [ 'jpg','jpeg','png','gif','bmp','pdf' ] );
} # end sub is_photo

sub get_dimensions {
	my ( $layout, $size ) = @_;

	my ( $width, $height );
	if ( $layout eq 'Landscape' ) {
		if ( $size eq 'medium' ) {
			$height = $openprint::config{Medium_Asset_Height};
			$width = $openprint::config{Medium_Asset_Width} if ! $height;
		} elsif ( $size eq 'large' ) {
			$height = $openprint::config{Large_Asset_Height};
			$width = $openprint::config{Large_Asset_Width} if ! $height;
		} elsif ( $size eq 'thumbnail' ) {
			$height = $openprint::config{Small_Asset_Height};
			$width = $openprint::config{Small_Asset_Width} if ! $height;
		} elsif ( $size eq 'small' ) {
			$height = $openprint::config{Small_Asset_Height};
			$width = $openprint::config{Small_Asset_Width} if ! $height;
		} # end if
	} else {
		if ( $size eq 'medium' ) {
			$width = $openprint::config{Medium_Asset_Width};
		} elsif ( $size eq 'large' ) {
			$width = $openprint::config{Large_Asset_Width};
		} elsif ( $size eq 'thumbnail' ) {
			$width = $openprint::config{Small_Asset_Width};
		} elsif ( $size eq 'small' ) {
			$width = $openprint::config{Small_Asset_Width};
		} # end if
	} # end if	
} # end sub get_dimensions

sub sized_url {
	my $size = $_[1];
	if ( ! $_[0]{id} ) {
		return '';
	} # end if

	my $src = $_[0]->on_disk_path();
	my $path = $openprint::config{AssetPath}.'/'.($size?$size.'/':'');
	if ( $openprint::config{AssetPath} ) {

		# should not be readable by anyone else
		umask 077;
		mkdir $path;
		if ( ! -e $path ) {
			$openprint::log->error("Unable to create path $path: $!" );
			return '/images/icons/file.png';
		} # end if
	} else {
		$openprint::log->error('No Asset Path');
		return '/images/icons/file.png';
	} # end if

	my $filename = $_[0]->on_disk_filename();
	if ( !$size ) {
		return '/assets/'.$filename;
	}
#$openprint::log->debug("Asset:: on_disk_path: $src, Filename: $filename");

	my ( $blah, $extension ) = $filename =~ /(.+)\.([^\.]+)$/;
	if ( is_photo( $extension ) ) {
		my $dest_filename = $filename;
		if ( $openprint::config{AssetPath} ) {
			my $dest = $path.$dest_filename;
			if ( ! -e $dest ) {
				
				my ( $width, $height ) = get_dimensions($_[0]->layout(), $size);
				if ( ! ( $width or $height ) ) {
					my ( $caller, undef, $line ) = caller;
					$openprint::log->error("No asset size in config for size($size) called from $caller:$line");
					return '/assets/'.$filename;
				} # end if	
				my ( $stderr, $stdout );
				require IPC::Run3;
				if ( $openprint::config{Watermark_Text} ) {
					if ( ! -e $src.'.watermarked' ) {
						IPC::Run3::run3(qq`gmic -input "$src" -watermark_fourier "$openprint::config{Watermark_Text}",33 -output "$src.watermarked"`, undef, $stdout, $stderr );
						if ( $? ) {
							$openprint::log->error("ERror watermarking sized image. Reason: ($?) stdout($stdout) stderr($stderr)");
						} # end if watermark
					} else {
						$src = $src . '.watermarked';
					}
				}
				if (! -e $src) {
					$openprint::log->error("Source file $src does not exist.");
					return '/assets/'.$filename;
				} # end if

				$openprint::log->debug("Creating $size at ${width} x $src $dest");
				my $command;
				if ( $extension eq 'pdf' ) {
					$command  = qq`convert -thumbnail ${width}x${height} -alpha remove "${src}\[0\]" "$dest"`;
				} else {
					$command  = qq`convert -adaptive-resize ${width}x${height} "$src" "$dest"`;
				} # end fi

				IPC::Run3::run3($command, undef, $stdout, $stderr );
				if ($?) {
					$openprint::log->error("ERror creating sized image. Reason: ($?) cmd:($command) stdout($stdout) stderr($stderr)");
					return '/assets/'.$filename;
				} # end if convert
				if (! -e $dest) {
					$openprint::log->error("Unable to create $dest cmd($command) stdout($stdout) stderr($stderr)");
				} # end if
				if ( $extension =~ /jpe?g/i ) {
					IPC::Run3::run3(qq`jpegtran -optimize -copy none -outfile "$dest" "$dest"`, undef, $stdout, $stderr );
					if ( $? ) {
						$openprint::log->error("ERror optimising sized image. Reason: ($?) stdout($stdout) stderr($stderr)");
					} # end if convert
				} # end if
			} # end if -e dest
		} else {
			$openprint::log->error("NO assetpath specified");
		} # end if Asset Path
#$openprint::log->debug("Return /thumbnails/$filename");
		return '/assets/'.$size.'/'.$dest_filename;
	} elsif ( is_video( $extension ) ) {
		my $fallback = '/images/icons/'. lc $extension. '.png';
		if ( ! -e $openprint::config{SkinPath}.$fallback ) {
			$fallback = '/images/icons/unknown.png';
		} # end if
		if ( $openprint::config{AssetPath} ) {
			if ( ! -e $src ) {
				$openprint::log->error("Src file $src no longer exists! Can't make thumbs");
				return $fallback;
			} # end if

			my $dest = $path.$blah.'.jpg';
			if ( ! -e $dest ) {
				my $width;
				if ( $size eq 'medium' ) {
					$width = $openprint::config{Medium_Asset_Width};
				} elsif ( $size eq 'large' ) {
					$width = $openprint::config{Large_Asset_Width};
				} elsif ( $size eq 'thumbnail' ) {
					$width = $openprint::config{Small_Asset_Width};
				} elsif ( $size eq 'small' ) {
					$width = $openprint::config{Small_Asset_Width};
				} elsif ( ! $size ) {
					$size = 'full';
				} # end if
				if ( ! $width ) {
					$openprint::log->error("No asset size in config for video $size");
				} # end if	
				$openprint::log->debug("Creating $size at ${width}x $src $dest");
				if ( ! -d "/tmp/$filename" ) {
					$openprint::log->debug("Going to create tmp directory at /tmp/$filename/ to hold medium thumbnail:" );
					if ( ! mkdir("/tmp/$filename",0777) ) {
						$openprint::log->error("Unable to create tmp directory at /tmp/$filename/ to hold medium thumbnail: $!" );
						return $fallback;
					} # end if
				} else {
					$openprint::log->debug("Strange, tmp dir /tmp/$filename shouldnt already exist, but it does.");
				} # end if

				$openprint::log->debug("avprobe -show_format  $src");
				my $probe = `avprobe -show_format  $src`;
				$openprint::log->debug("Probe: $probe");
				my ( $length ) = $probe =~ /duration=(\d+)\.\d*/m;
				$openprint::log->debug("Length of video: $length");

				if ( $length > 10 ) {
					$length -= 10;
				}
				if ( $length > 5 and $length < 60 ) {
					$length = 5;
				} # end if
				my $command;

if ( 0 ) {
				if ( $width ) {
					$command = qq`mplayer -frames 1 -nosound -quiet -zoom -vf scale=$width:-3 -vo jpeg:outdir="/tmp/$filename/" -ss $length "$src"`;
				} else {
					$command = qq`mplayer -frames 1 -nosound -quiet -zoom -vo jpeg:outdir="/tmp/$filename/" -ss $length "$src"`;
				} # end if
} else {
				if ( $width ) {
					$command = qq`avconv -i "$src" -vf scale=$width:-1 -vframes 1 -ss $length "/tmp/$filename/$size.jpg"`;
				} else {
					$command = qq`avconv -i "$src" -vframes 1 -ss $length "/tmp/$filename/$size.jpg"`;
				} # end if
}
				$openprint::log->debug("about to $command");
				$_ = `$command`;
				if ( $! ) {
					$openprint::log->error("Unable to create $size thumbnail at /tmp/$filename/$size.jpg: $! : $_" );
					return $fallback;
				} # end if
				if ( -e "/tmp/$filename/$size.jpg" ) {
					$openprint::log->debug("Moving /tmp/$filename/$size.jpg to $dest");
					# We use mv because perl's rename doesn't work across filesystem boundaries
					`mv "/tmp/$filename/$size.jpg" $dest`;
					if ( $! ) {
						$openprint::log->error("Unable to mv image  $dest: $!" );
						return $fallback;
					} # end if
					unlink "/tmp/$filename/00000001.jpg";
					rmdir "/tmp/$filename";
					my ( $stdout, $stderr );
					require IPC::Run3;
					IPC::Run3::run3(qq`jpegtran -optimize -copy none -outfile "$dest" "$dest"`, undef, $stdout, $stderr );
					if ( $? ) {
						$openprint::log->error("ERror optimising sized image. Reason: ($?) stdout($stdout) stderr($stderr)");
					} # end if convert
				} else {
					$openprint::log->error("Unable to create medium thumbnail at /tmp/$filename/: Wasn't there! $!" );
					$openprint::log->debug("command was $command");
					return $fallback;
				} # end if
			} # end if
		} # end if
		return  '/assets/'.$size.'/'.$blah.'.jpg';
	} else {
		if ( -e $openprint::config{SkinPath}.'/images/icons/'.(lc $extension).'.png' ) {
			return '/images/icons/'.(lc $extension).'.png';
		} else {
$openprint::log->error("Shuold have found an icon.  Install icons!! for ($extension) at " . $openprint::config{SkinPath}.'/images/icons/'.(lc $extension).'png' ) if $extension;
		} # end if
	} # end if
$openprint::log->error("unknown externsion or somerthitng.  Install icons!! for ($extension)") if $extension;
	return '';
}  # end sub sized_url

sub medium_url {
	return sized_url( $_[0], 'medium' );
} # end sub medium_url
sub small_url {
	return sized_url( $_[0], 'small' );
} # end small_url

sub sized_html {
	return '' if ! $_[0]{id};
	return sprintf('<img src="%1$s" alt="%2$s" title="%2$s" />', $_[0]->sized_url($_[1]), $_[0]->name() );
}

sub large_html {
	return '' if ! $_[0]{id};
	return sprintf('<img src="%1$s" alt="%2$s" title="%2$s" />', $_[0]->sized_url('large'), $_[0]->name() );
} # end sub large_html
sub medium_html {
	return '' if ! $_[0]{id};
	my $options = join(' ', map { qq`$_="$_[1]{$_}"` } keys %{$_[1]} ) if $_[1];
	return sprintf('<img src="%1$s" alt="%2$s" title="%2$s" %3$s/>', $_[0]->medium_url(), $_[0]->name(), $options );
} # end sub medium_html

sub html {
	return '' if ! $_[0]{id};
	return sprintf('<img src="%1$s" alt="%2$s" title="%2$s" />', $_[0]->url(), $_[0]->name() );
} # end sub html

sub thumbnail_html {
	if ( ! $_[0]{id} ) {
		$openprint::log->warn('Called thumbnail_html on asset with no id');
		return '';
	} # end if
	return sprintf('<img src="%1$s" alt="%2$s" title="%2$s" />', $_[0]->sized_url('small'), $_[0]->name() );
} # end sub thumbnail_html

sub thumbnail_path {
	my $url = $_[0]->sized_url('thumbnail');
	if ( $url =~ /^\/thumbnails/ ) {
		return $openprint::config{AssetPath}.$url;
	} elsif ( $url =~ /^\/small/ ) {
		return $openprint::config{AssetPath}.$url;
	} else {
		return $openprint::config{SkinPath}.$url;
	} # end if
} # end sub thumbnail_path
sub medium_path {
	my $url = $_[0]->medium_url();
	$url =~ s/^\/assets//;
	return $openprint::config{AssetPath}.$url;
} # end sub medium_path
sub large_path {
	my $url = $_[0]->sized_url('large');
	$url =~ s/^\/assets//;
	return $openprint::config{AssetPath}.$url;
} # end sub medium_path

sub sized_path {
	my $url = $_[0]->sized_url($_[1]);
	if ( ! $url ) {
		my ( $caller, undef, $line ) = caller;
		$openprint::log->error("No url return for size $_[1] called from $caller:$line");
	}
	$url =~ s/^\/assets//;
	return $openprint::config{AssetPath}.$url;
} # end sub sized_path

sub md5 {
	if ( @_ > 1 ) {
		$_[0]{md5} = $_[1];
	} # end if
	if ( ( ! $_[0]{md5} ) and $_[0]{data} ) {
		require Digest::MD5;
		$_[0]{md5} = Digest::MD5::md5_base64( $_[0]{data} );
	} # end if
	return $_[0]{md5};	
} # end sub md5

sub can_edit {
	return 1 if $_[0]{created_by} == $openprint::session{user_id};
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if openprint::usergroup::is_user_in( ['Accounting','IT'], $openprint::session{user_id} );

	return 0;
} # end sub can_edit

sub can_view {
	return 1 if $_[0]{public};
  return 1 if $$openprint::User{type} eq 'A';

	if ( $_[0]{created_by} == $$openprint::User{id} ) {
		$openprint::log->debug('User is owner');
		return 1;
	} else {
		$openprint::log->debug('User is not owner :'.$$openprint::User{id} .' != ' . $_[0]{created_by});
	}

	my @Albums = openprint::Photo_in_Album->find(asset_id=>$_[0]{id});
	if ( ! @Albums ) {
		if ( $_[0]{company_id} == $$openprint::User{company_id} ) {
			return 1;
		}
		return 0;
	}
	foreach my $Album ( @Albums ) {
		return 1 if $Album->can_view();
	} # end foreach
	return 0;
} # end sub can_view

sub can_delete {
	return 1 if $_[0]{created_by} == $openprint::session{user_id};
	return 0;
} # end sub can_delete
sub can_approve {
	return 1 if $_[0]{created_by} == $openprint::session{user_id};
	return 0;
} # end sub can_approve {

sub destroy {
  my $self = shift;
  my $result = '';
	foreach ( openprint::User->find(asset_id=>$$self{id}) ) {
		$result .= $_->save({asset_id=>undef});
    last if $result;
	} # end foreach User
  return $result if $result;
  require openprint::SRED_Asset;
	foreach ( openprint::SRED_Asset->find(asset_id=>$$self{id}) ) {
		$result .= $_->destroy();
    last if $result;
	} # end foreach SRED_Asset
  return $result if $result;
  require openprint::Claim_Asset;
	foreach ( openprint::Claim_Asset->find(asset_id=>$$self{id}) ) {
		$result .= $_->destroy();
    last if $result;
	} # end foreach Claim_Asset
  return $result if $result;
	foreach ( openprint::Photo_in_Album->find(asset_id=>$$self{id}) ) {
		$result .= $_->destroy();
    last if $result;
	} # end foreach Claim_Asset
	foreach ( openprint::Photo_Album->find(thumbnail_id=>$$self{id}) ) {
    $result .= $_->save({thumbnail_id=>undef});
    last if $result;
  }
  return $result if $result;
	foreach ( openprint::Object_Asset->find(asset_id=>$$self{id}) ) {
		$result .= $_->destroy();
    last if $result;
	} # end foreach Claim_Asset
  return $result if $result;
	unlink $self->sized_path('small');
	unlink $self->sized_path('medium');
	unlink $self->sized_path('large');
	unlink $self->on_disk_path();
	sql::execute(undef, undef, 'DELETE FROM Assets WHERE id=?', $_[0]{id});
  return $result;
} # end sub destroy

sub fetch {
	my ( $Asset, $url );
	if ( @_ == 2 ) {
		( $Asset, $url ) = @_;
	} elsif ( ref $_[0] eq 'openprint::Asset' ) {
		$Asset = $_[0];
		$url = $Asset->source();
	} else {
		$url = $_[0];
	} # end if

	if ( ! $url ) {
		$openprint::log->error("Asset::fetch No source for @_");
		return;
	} # end if

	$openprint::log->debug("Fetching from $url") if $debug;

	my ( $md5, $filename );
	my $data;

	require URI::Escape;
	require File::Slurp;

	if ( $url =~ /^http/i ) {

		require LWP::UserAgent;
		require HTTP::Request;

		my $ua = LWP::UserAgent->new;
		$ua->agent("IQ/0.1 ");
	# Create a request
		my $req = HTTP::Request->new( GET => $url );
	# Pass request to the user agent and get a response back
		my $res = $ua->request($req);
	# Check the outcome of the response
		if (! $res->is_success) {
			$openprint::log->warn("No success.");
			return "Failed to get file. URL($url)<br/>";
		} # end if
		if ( ! $res->content() ) {
			$openprint::log->warn("Empty content.");
			return "Failed to get file. URL($url)<br/>";
		} # end if

		require URI;
		require File::Basename;

		my $URI = URI->new($url);
		my $path = $URI->path();
		$filename = File::Basename::basename( $path );
		$openprint::log->debug("fetch: filename: $filename path: $path from url $url");
		if ( ! $filename ) {
			return "Unable to determine filename from $url";
		} elsif ( $debug ) {
			$openprint::log->debug("saving to filename $filename");
		} # endi f
		$filename = URI::Escape::uri_unescape( $filename );

		require Digest::MD5;
		$md5 = Digest::MD5::md5_base64( $res->content );
		if ( ! $md5 ) {
			return "Unable to MD5?";
		} elsif( $debug ) {
			$openprint::log->debug("MD5 for $filename was $md5");
		} # end if
		$data = $res->content;
	} else {
		$filename = File::Basename::basename( $url );
		$data = File::Slurp::read_file( $filename );
	} # end if
	$Asset = openprint::Asset->find_one( md5 => $md5 ) if ! $Asset;
	if ( ! $Asset ) {
		$Asset = new openprint::Asset();
		$_ = $Asset->save({ filename=>$filename, md5=>$md5, source => $url });
		return $_ if $_;

		if ( ! File::Slurp::write_file($Asset->on_disk_path(), { atomic => 1, err_mode=>'carp' }, $data ) ) {
			return 'There was an error saving file ' . $filename.' to ' . $Asset->on_disk_path() . ": $!<br/>";
		} # end if

		# Why are we saving again?
		$_ = $Asset->save();
		return $_ if $_;
	} else {
		$openprint::log->debug("Asset with this md5 already exists." . $Asset->to_string() ) if $debug;
		if ( $Asset->filename() ne URI::Escape::uri_unescape( $Asset->filename() ) ) {
			$openprint::log->warn("Fixing asset filename from " . $Asset->filename() . ' to ' . URI::Escape::uri_unescape( $Asset->filename() ) );
			$Asset->save({filename=>URI::Escape::uri_unescape( $Asset->filename() )});
		} # end if
		if ( $url and ! $Asset->source() ) {
			$openprint::log->warn("Setting source to $url");
			$Asset->save({source=>$url});
		} # end if
		if ( ! -e $Asset->on_disk_path() ) {
			$openprint::log->debug( "File does not exist on disk at " . $Asset->on_disk_path() ) if $debug;
			if ( ! File::Slurp::write_file($Asset->on_disk_path(), { atomic => 1, err_mode=>'carp' }, $data ) ) {
				return 'There was an error saving file ' . $filename.' to ' . $Asset->on_disk_path() . ": $!<br/>";
			} # end if
		} elsif ( ! -s $Asset->on_disk_path() ) {
			$openprint::log->debug( "File has no size at " . $Asset->on_disk_path() ) if $debug;
			if ( ! File::Slurp::write_file($Asset->on_disk_path(), { atomic => 1, err_mode=>'carp' }, $data ) ) {
				return 'There was an error saving file ' . $filename.' to ' . $Asset->on_disk_path() . ": $!<br/>";
			} # end if
		} else {
			$openprint::log->debug( "File exists and has size " . ( -s $Asset->on_disk_path() ) ) if $debug;
		} # end if
	} # end if
	return $Asset;
} # end sub fetch

sub from_content {
	my ( $self, $filename, $content ) = @_;

	if ( ! $content ) {
		return "Empty content passed to Asset::from_content<br/>";
	} # end if

	require Digest::MD5;
	my $md5 = Digest::MD5::md5_base64( $content );
	if ( ! $md5 ) {
		return "Unable to MD5?";
	} else {
		$openprint::log->debug("MD5 was $md5");
	} # end if
	my $Asset = openprint::Asset->find_one( md5 =>$md5 );
	if ( ! $Asset ) {
		$Asset = new openprint::Asset();
		$! .= $Asset->save({ filename=>$filename, md5=>$md5});
	} # end if
	require File::Slurp;

	if ( ! -e $Asset->on_disk_path() ) {
		if ( ! File::Slurp::write_file( $Asset->on_disk_path(), { err_mode=>'quiet' }, $content ) ) {
			return 'There was an error saving file ' . $filename.' to ' . $Asset->on_disk_path() . ": $!<br/>";
		} # end if
	} # end if

	if ( ( @_ > 3 ) and $_[3] ) {
		# Should be a hash of more attribute
		$Asset->save($_[3]);
	} # end if
	return $Asset;
} # end sub from_content

# What gets passed in the form element name
sub upload {
	my $upload = $openprint::r->upload($_[0]);
	if ( ! $upload ) {
    $openprint::log->error("There was no upload for $_[0]");
		return "There was no upload for $_[0]<br/>";
	} # end if
	require Digest::MD5;
	my $data;
	$upload->slurp( $data );
	my $md5 = Digest::MD5::md5_base64( $data );
	if (!$md5) {
    $openprint::log->error("Unable to MD5");
		return "Unable to MD5?";
	} else {
		$openprint::log->debug("MD5 was $md5");
	} # end if
	my $Asset = openprint::Asset->find_one(md5 =>$md5);
	if (!$Asset) {
		$Asset = new openprint::Asset();
    $openprint::log->debug($Asset->to_string());
		$_ = $Asset->save({filename=>$upload->filename(), md5=>$md5});
    if ($_) {
      return "There was an error saving the asset: $_<br/>";
    }
		if (!$upload->link($Asset->on_disk_path())) {
			return 'There was an error saving file ' . $upload->filename().' to ' . $Asset->on_disk_path() . ": $!<br/>";
		} # end if
		if ((@_ > 1) and $_[1] ) {
      delete $_[1]{id};
			# Should be a hash of more attribute
			$Asset->save($_[1]);
		} # end if
	} else {
		if (!-e $Asset->on_disk_path()) {
			if (!$upload->link( $Asset->on_disk_path())) {
				return 'There was an error saving file ' . $upload->filename().' to ' . $Asset->on_disk_path() . ": $!<br/>";
			} # end if
		} # end if
	} # end if
	return $Asset;
} # end sub upload

sub caption {
	if ( $_[0]{name} ) {
		return $_[0]{name};
	} # end if
	if ( $_[0]{filename} ) {
		return $_[0]{filename};
	} # end if
} # end sub caption

sub width {
	if ( ! $_[0]{width} ) {
		require Image::Size;
		if ( $_[0]->is_video() ) {
			# get the image size, and print it out
			my $url = $_[0]->sized_url('full');
			$url =~ s/^\/assets//;
			my ( $w, $h, $e ) = Image::Size::imgsize( $openprint::config{AssetPath}.$url );
			if ( ! ( $w and $h ) ) {
				$openprint::log->error("imagesize aerrror $e ");
			} else {
			@{$_[0]}{'width','height'} = ( $w, $h );
			} # end if
$openprint::log->debug("Getting size for video: " . $_[0]->sized_url('full') . " got $_[0]{width}x$_[0]{height}");

		} else {
# get the image size, and print it out
			@{$_[0]}{'width','height'} = Image::Size::imgsize( $_[0]->on_disk_path() );
		} # end if
	} # end if
	return $_[0]{width};
} # end sub width

sub height {
	if ( ! $_[0]{height} ) {
		require Image::Size;
		if ( $_[0]->is_video() ) {
			# get the image size, and print it out
			@{$_[0]}{'width','height'} = Image::Size::imgsize( $openprint::config{AssetPath}.$_[0]->sized_url('full') );
		} else {
			# get the image size, and print it out
			@{$_[0]}{'width','height'} = Image::Size::imgsize( $_[0]->on_disk_path() );
		} # end if
	} # end if
	return $_[0]{height};
} # end sub height

sub layout {
	if ( ! $_[0]{layout} ) {
		if ( $_[0]->width() > $_[0]->height() ) {
			$_[0]{layout} = 'Landscape';
		} else {
			$_[0]{layout} = 'Portrait';
		} # end if
	} # end if
	return $_[0]{layout};
} # end sub layout

sub video_url {
	my ( $self, $type ) = @_;
$openprint::log->debug("Calling video_url($type)");
	my $path = $openprint::config{AssetPath}.'/videos/';
	if ( $openprint::config{AssetPath} ) {
		if ( ! -e $path ) {
			mkdir $path;
			$openprint::log->error("Unable to create path $path: $!" );
			return '/images/icons/file.png';
		} # end if
	} # end if
	my $filename = $_[0]->on_disk_filename();
	my ( $base, $extension ) = $filename =~ /(.+)\.([^\.]+)$/;
	if ( ! is_video( $extension ) ) {
		$openprint::log->error("Called video_url on as asset that is not a video. " . $_[0]->to_string() );
		return;
	} # end if
	$self->generate_video( $type );
	return '/assets/videos/'.$base.'.'.$type;
} # end sub video_url

sub video_path( $$ ) {
	my ( $self, $type ) = @_;
	my $filename = $_[0]->on_disk_filename();
	my ( $base, $extension ) = $filename =~ /(.+)\.([^\.]+)$/;
	if ( ! is_video( $extension ) ) {
		$openprint::log->error("Called video_path on as asset that is not a video. " . $_[0]->to_string() );
		return;
	} # end if
	return $openprint::config{AssetPath}.'/videos/'.$base.'.'.$type;
} # end sub video_path

sub generate_video {
	my ( $self, $type ) = @_;
	my $dest = $self->video_path($type);
	my $lock;
	if ( ! open($lock, "> $dest.lck") ) {
		$openprint::log->error("Unable to open semaphore at $dest.lck\n");
		return;
	} # end if
	if ( ! flock($lock, Fcntl::LOCK_EX) ) {
		$openprint::log->error("Unable to lock semaphore\n");
		return;
	} # end if
	if ( ! -e $dest ) {
		# Create it
		my $src  = $_[0]->on_disk_path();
		my ( $base, $extension ) = $src =~ /\/([^\/]+)\.([^\.]+)$/;
		if ( $type eq 'mp4' ) {
			$openprint::log->debug("avconv -i $src -threads 2 -vcodec libx264 -b 1500k -pre:v baseline -g 30 -f mp4 $dest.part:");
			my $output = `avconv -i "$src" -threads 2 -vcodec libx264 -b 1500k -pre:v baseline -g 30 -f mp4 "$dest.part"`;
			$openprint::log->debug("avconv -i $src -threads 2 -vcodec libx264 -b 1500k -pre:v baseline -g 30 -f mp4 $dest.part: $output");
			if ( ! -e "$dest.part" ) {
				$openprint::log->error("avconv didn't do it's thing.");
			} else {
				`qt-faststart "$dest.part" "$dest"`;
				unlink "$dest.part";
			} # end if
		} elsif ( $type eq 'ogg' ) {
			`avconv -i "$src" -vcodec libtheora -b 1500k -acodec libvorbis -ab 160000 -g 30 -f ogg "$dest.part"`;
			if ( ! -e "$dest.part" ) {
				$openprint::log->error("avconv didn't do it's thing.");
			} else {
				`mv $dest.part $dest`;
			} # end if
		} elsif ( $type eq 'webm' ) {
		`avconv -i "$src" -vcodec libvpx -b 1500k -acodec libvorbis -ab 160000 -f webm "$dest.part"`;
			if ( ! -e "$dest.part" ) {
				$openprint::log->error("avconv didn't do it's thing.");
			} else {
				`mv "$dest.part" "$dest"`;
			} # end if
		} else {
			$openprint::log->error("Unknown type in video_url $type");
		} # end if type
	} else {
		$openprint::log->debug("Asset::generate_video: Destination $dest already exists.");
	} # end if ! -e $dest
	close($lock);
	unlink $dest.'.lck';
	return $dest;
} # end sub generate_video

sub content_type {
	my $src = @_ > 1 ? $_[1] : $_[0]->on_disk_path();
	my ( $base, $extension ) = $src =~ /([^\/]+)\.([^\.]+)$/;
	if ( $extension eq 'mp4' ) {
		$openprint::log->error('content type for ' . $src . ' ext:' . $extension);
		return 'video/mp4';
	} elsif ( $extension eq 'ogg' ) {
		return 'video/ogg';
	} elsif ( $extension eq 'webm' ) {
		return 'video/webm';
	} elsif ( $extension eq 'avi' ) {
		return 'video/avi';
	} else {
		$openprint::log->error('unimplemented content type for ' . $src . ' ext:' . $extension);
	} # end if
} # end sub content_type

sub slider {
  my ( $Assets, $size ) = @_;
  $size = 'medium' if ! $size;

  if ( ! ( $Assets and @{$Assets} ) ) {
    return;
  }

  my $html = '<ul class="slider">';
  my @slider_images;

  if ( @$Assets > 1 ) {
    for ( my $i = 0; $i < @$Assets ; $i += 1 ) {
      my $Asset = $$Assets[$i];
      push @slider_images, 'image'.$i;
      if ( ! $i ) {
        $html .= sprintf('<li id="image%d"><img onclick="GoNext();" src="%s"/></li>', $i, $Asset->sized_url( $size ) );
      } else {
        $html .= sprintf('<li id="image%d" style="display:none;"><img onclick="GoNext();" src="%s"/></li>', $i, $Asset->sized_url( $size ) );
      }
    } # end for
    $html .= '</ul>';
    $html .= q`
<script type="text/javascript">
  image_slide = new Array( '`. join("','", @slider_images ) .q`' );
  StartSlideShow();
</script>`;
  } else {
      my $Asset = $$Assets[0];
    $html .= sprintf('<li><img src="%s"/></li>', $Asset->sized_url( $size ) );
    $html .= '</ul>';
  }
  return $html;
} # end sub slider

1;
__END__
