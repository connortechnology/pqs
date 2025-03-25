use strict;
package openprint::SignatureCapture;
our @ISA = qw( openprint::Object );
use openprint ();
require Image::Magick;
require URI::Escape;
require MIME::Base64;

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'signaturecapture';
$serial = 'signaturecapture_id_seq';
%fields = (
	'id'	=>	'id',
	'project_id'	=>	'project_id',
	'image_data'	=>	'image_data',
	'service_id'	=>	'service_id',
	'deleted'		=>	'deleted',
	'created_on'	=>	'created_on',
	'type'			=>	'type',
	'additional_image_data'	=>	'additional_image_data',
	'additional_image_type'	=>	'additional_image_type',
);
%defaults = (
	'deleted'		=>	0,
	'created_on'	=>	'NOW()',
);

sub file_path {
	my $self = $_[0];
	# Not only returns the path relative to url root, but also makes sure that the image is there. o
	if ( ! -e $openprint::config{'SkinPath'}.'/images/SignatureCapture/' ) {
		mkdir $openprint::config{'SkinPath'}.'/images/SignatureCapture/';
	} # end if
	if ( ! -e $openprint::config{'SkinPath'}.'/images/SignatureCapture/'.$$self{'project_id'} ) {
		mkdir $openprint::config{'SkinPath'}.'/images/SignatureCapture/'.$$self{'project_id'};
	} # end if
	if ( ! -e $openprint::config{'SkinPath'}.'/images/SignatureCapture/'.$$self{'project_id'}.'/'.$$self{'service_id'} ) {
		mkdir $openprint::config{'SkinPath'}.'/images/SignatureCapture/'.$$self{'project_id'}.'/'.$$self{'service_id'};
	} # end if
	if ( $self->type() eq 'bmp' ) {
		my $tmp_filename = '/tmp/'.$$self{'project_id'}.'_'.$$self{'service_id'}.'_'.$$self{'id'};

		misc::save_file( $openprint::log, $tmp_filename.'.bmp', $$self{'image_data'} );
		# Convert to gif
		eval {
			my $Image = Image::Magick->new(magick=>'bmp');
			$Image->BlobToImage( $$self{image_data} );
			$Image->set(magick=>'gif');
			my @blobs = $Image->ImageToBlob();
			if ( ! @blobs ) {
				$openprint::log->error("No blobs");
			} elsif ( @blobs > 1 ) {
				$openprint::log->warn("# of blobs: " . @blobs);
			} # end if
			$_ = $self->save({'image_data'=>MIME::Base64::encode_base64($blobs[0]),'type'=>'gif'});
		}; # end eval
		$openprint::log->error( "Eval error of SignatureCapture::file_path bmp conversion Reason: " . $@ ) if $@;
		misc::save_file( $openprint::log, $openprint::config{'SkinPath'}.'/images/SignatureCapture/'.$$self{'project_id'}.'/'.$$self{'service_id'}.'/'.$$self{'id'}.'.'.$$self{type}, MIME::Base64::decode_base64($$self{'image_data'}) );
		return '/images/SignatureCapture/'.$$self{'project_id'}.'/'.$$self{'service_id'}.'/'.$$self{'id'}.'.'.$$self{type};
	} elsif ( $self->type() eq 'path' ) {
		my $filename = '/images/SignatureCapture/'.$$self{'project_id'}.'/'.$$self{'service_id'}.'/'.
			$$self{'id'}.'-'.$$self{width}.'x'.$$self{height}.'.svg';
		misc::save_file( $openprint::log, $openprint::config{'SkinPath'}.$filename, '<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="' . $_[0]->width() .'" height="'.$_[0]->height().'"
    xmlns:xlink="http://www.w3.org/1999/xlink"><path d="'.$$self{'image_data'}.'" style="stroke:#000066; fill:none;"/></svg>' );
		return $filename;
	} else {
		misc::save_file( $openprint::log, $openprint::config{'SkinPath'}.'/images/SignatureCapture/'.$$self{'project_id'}.'/'.$$self{'service_id'}.'/'.$$self{'id'}.'.'.$$self{type}, MIME::Base64::decode_base64($$self{'image_data'}) );
		return '/images/SignatureCapture/'.$$self{'project_id'}.'/'.$$self{'service_id'}.'/'.$$self{'id'}.'.'.$$self{type};
	} # end if
} # end sub file_path

sub scale {
	my $options = $_[1];
	if ( $options ) {
		
#$openprint::log->debug("old dimensions: " . $_[0]->width().'x'.$_[0]->height() );
		my $width_factor = $$options{width} / $_[0]->width() if $$options{width};
		my $height_factor = $$options{height} / $_[0]->height() if $$options{height};
		$width_factor = $height_factor if ! $width_factor;
		$height_factor = $width_factor if ! $height_factor;
#$openprint::log->debug("scaling by: $width_factor x $height_factor");
		if ( $$options{width} or $$options{height} ) {
			my @new_commands;
			foreach my $command ( split(' ', $_[0]->image_data() ) ) {
				$command =~ /^([ML])([\d\-]+),([\d\-]+)$/;
				push @new_commands, $1.Math::Round::nearest(1,$2*$width_factor).','.Math::Round::nearest(1,$3*$height_factor);
			} # end foreach command
			$_[0]{image_data} = join(' ', @new_commands );
			$_[0]{width} = $$options{width} ? $$options{width} : Math::Round::nearest( 1, $_[0]->width() * $width_factor );;
			$_[0]{height} = $$options{height} ? $$options{height} : Math::Round::nearest( 1, $_[0]->height() * $height_factor );
#$openprint::log->debug("new dimensions: $_[0]{width}x$_[0]{height}");
		} # end if
	} # end if
} # end sub scale

sub html {
	my ( $self, $options ) = @_;
	if ( $options ) {
		$self = $self->copy();
		$self->scale( $options );
	} # end if

	# if it's an image like a gif, return an image tag, for svg, blah blah
	if ( $self->type() eq 'gif' ) {
		return sprintf('<img src="%s" alt=""/>', $self->file_path() );
	} elsif ( $self->type() eq 'path' ) {
		if ( ! ( $ENV{HTTP_REFERER} =~ /ip[hone|ad|od]/i ) ) {
		#return sprintf('<svg src="%s" />', $_[0]->file_path() );
			return '<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="' . $self->width() .'" height="'.$self->height().'"
    xmlns:xlink="http://www.w3.org/1999/xlink"><path d="'.$$self{image_data}.'" style="stroke:#000066; fill:none;"/></svg>';
		} else {
			return sprintf('<embed src="%s" type="image/svg+xml"/>', $self->file_path() );
		} # end if
	} else {
		$openprint::log->error('Unknown signature type :' . $self->type().' for signature ' . $$self{id} . $self->to_string() );
	} # end if
	return '';
} # end sub html

sub additional_file_path {
	my $self = $_[0];
	# Not only returns the path relative to url root, but also makes sure that the image is there. o
	if ( ! -e $openprint::config{'SkinPath'}.'/images/SignatureCapture/' ) {
		mkdir $openprint::config{'SkinPath'}.'/images/SignatureCapture/';
	} # end if
	if ( ! -e $openprint::config{'SkinPath'}.'/images/SignatureCapture/'.$$self{'project_id'} ) {
		mkdir $openprint::config{'SkinPath'}.'/images/SignatureCapture/'.$$self{'project_id'};
	} # end if
	if ( ! -e $openprint::config{'SkinPath'}.'/images/SignatureCapture/'.$$self{'project_id'}.'/'.$$self{'service_id'} ) {
		mkdir $openprint::config{'SkinPath'}.'/images/SignatureCapture/'.$$self{'project_id'}.'/'.$$self{'service_id'};
	} # end if
	if ( $self->type() eq 'bmp' ) {

		my $Image = Image::Magick->new(magick=>'bmp');
		$Image->BlobToImage( $$self{additional_image_data} );

		$Image->set(magick=>'gif');
		my @blobs = $Image->ImageToBlob();
		if ( ! @blobs ) {
			$openprint::log->error("No blobs");
		} elsif ( @blobs > 1 ) {
			$openprint::log->warn("# of blobs: " . @blobs);
		} # end if
		$_ = $self->save({'additional_image_data'=>MIME::Base64::encode_base64($blobs[0]),'additional_image_type'=>'gif'});
		$openprint::log->error($_) if $_;
	} # end if
	return '' if ! $$self{'additional_image_data'};
	my $filename = '/images/SignatureCapture/'.$$self{'project_id'}.'/'.$$self{'service_id'}.'/'.$$self{'id'}.'_additional.gif';
	misc::save_file( $openprint::log, $openprint::config{'SkinPath'}.$filename, MIME::Base64::decode_base64($$self{'additional_image_data'}) );
	return $filename;
} # end sub additional_file_path

sub type {
	if ( @_ > 1 ) {
		$_[0]{type} = $_[1];
	}
	if ( ! $_[0]{type} ) {
		if ( $_[0]{image_data} =~ /^GIF/ ) {
			$_[0]{type} = 'gif';
		} elsif ( $_[0]{image_data} =~ /^BM/ ) {
			$_[0]{type} = 'bmp';
		} elsif ( $_[0]{image_data} =~ /^<\?xml/i ) {
			$_[0]{type} = 'svg';
		} # end if
	} # end if
	return $_[0]{type};
} # end sub type

sub size {
	if ( ! ( $_[0]{width} and $_[0]{height} ) ) {
		if ( $_[0]{type} eq 'path' ) {
			my ( $max_width, $max_height ) = (0,0);
			foreach my $command ( split( ' ',$_[0]{image_data} ) ) {
				if ( $command =~ /^[ML]([\-\d]+),([\-\d]+)$/ ) {
#$openprint::log->debug("Parsing size: $1,$2, -> $max_width,$max_height");
					$max_width = $1 if $1 > $max_width;
					$max_height = $2 if $2 > $max_height;
				} else {
					$openprint::log->warn("Wasnt a command in path data $command");
				} # end if
			} # end foreach command
#$openprint::log->debug("Dimensions of svg: $max_width, $max_height");
			return ($max_width,$max_height);
		} # end if
	} # end if
} # end sub size

sub width {
	if ( @_ > 1 ) {
		$_[0]{width} = $_[1];
	} 
	if ( ! $_[0]{width} ) {
		my ( $width, $height ) = $_[0]->size();
		$_[0]{width} = $width;
		$_[0]{height} = $height;
	} # end if
	return $_[0]{width};
} # end sub width 

sub height {
	if ( @_ > 1 ) {
		$_[0]{height} = $_[1];
	} 
	if ( ! $_[0]{height} ) {
		my ( $width, $height ) = $_[0]->size();
		$_[0]{width} = $width;
		$_[0]{height} = $height;
	} # end if
	return $_[0]{height};
} # end sub height 
1;
__END__
