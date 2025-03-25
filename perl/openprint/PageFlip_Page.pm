use strict;
package openprint::PageFlip_Page;
our @ISA = qw( openprint::Object );

use Image::Magick;
use openprint ();

use vars qw( $log $dbh %config );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;

use vars qw( $debug $table $serial %fields %defaults %transforms );
$debug = 0;
$table = 'pageflip_page';
$serial = 'pageflip_page_id_seq';

%fields = (
	'id'			=>	'id',
	'pageflip_id'	=>	'pageflip_id',
	'filename'		=>	'filename',
	'page'			=>	'page',
	'created_on'	=>	'created_on',
	'updated_on'	=>	'updated_on',
	'crop_box'		=>	'crop_box',
	'src_width'		=>	'src_width',
	'src_height'	=>	'src_height',
	'width'			=>	'width',
	'height'		=>	'height',
	'crop_top'		=>	undef,
	'crop_bottom'	=>	undef,
	'crop_left'		=>	undef,
	'crop_right'	=>	undef,
);

sub getImage {
	my ( $self ) = @_;
	if ( open(IMAGE, $config{'PageFlipDir'}.'/LR/'.$self->filename() ) ) {
$openprint::log->debug("Loading src image");
		my $Image = Image::Magick->new('magick'=>'jpg');
		$Image->Read(file=>\*IMAGE);
		close(IMAGE);
$openprint::log->debug("done Loading src image");

		return $Image;
	} else {
		$openprint::log->error('Unable to open PageFlip image at '. $config{'PageFlipDir'}.'/LR/'.$self->filename() );
		return;
	} # end if
} # end sub getImage

sub dst_filename {
	my ( $file, $ext ) = $_[0]->filename() =~ /^(.*)\.(.+)$/;
	my $filename = sprintf('%s_%dx%d.jpg', $file, $_[0]->width(), $_[0]->height() );
	return $filename;
} # end sub dst_filename

sub dst_path {
	return $config{'SkinPath'}.'/images/PageFlip/'.$_[0]->PageFlip()->docket().'/';
}

sub writeImage {
	my ( $self ) = @_;
	if ( ! -e $self->dst_path() ) {
		mkdir $self->dst_path();
	} # end if
		my $Image = $self->getImage();
		my $ratio = $Image->Get('width')/$self->width();
#$openprint::log->debug(sprintf('Crop to: %dx%d+%d+%d', 
				#int($ratio*($self->crop_right() - $self->crop_left())), 
				#int($ratio*($self->crop_bottom() - $self->crop_top())),
				#int($ratio*$self->crop_top()),
				#int($ratio*($self->width()-$self->crop_right())),
#) );
		$_ = $Image->Crop(
				'width'		=>	int($ratio*($self->crop_right() - $self->crop_left())), 
				'height'	=>	int($ratio*($self->crop_bottom() - $self->crop_top())),
				'x'			=>	int($ratio*$self->crop_top()),
				'y'			=>	int($ratio*($self->width()-$self->crop_right())),
				);
		$openprint::log->error("Error cropping: $_") if $_;
#$openprint::log->debug("New size: " . $Image->Get('width').'x'.$Image->Get('height'));
		#$_ = $Image->AdaptiveResize('width'=>$$self{'width'}, 'height'=>$$self{'height'});
#$openprint::log->debug("New size: " . $Image->Get('width').'x'.$Image->Get('height'));
		#$openprint::log->error("Error resizing: $_") if $_;
		$Image->Set('quality'=>75);
		$_ = $Image->Write($self->dst_path().$self->dst_filename());
		$openprint::log->error("Error writing: $_") if $_;
		close(IMAGE);
		undef $Image;
} # end sub writeImage 

sub src_width {
	my ( $self ) = @_;
	if ( @_ == 2 ) {
		$$self{'src_width'} = $_[1];
	} # end if
	if ( ! $$self{'src_width'} ) {
		my $Image = $self->getImage();
		@$self{'src_width','src_height'} = $Image->Get('width','height');
		undef $Image;
	} # end if
	return $$self{'src_width'};
} # end sub src_width
sub src_height {
	my ( $self ) = @_;
	if ( @_ == 2 ) {
		$$self{'src_height'} = $_[1];
	} # end if
	if ( ! $$self{'src_height'} ) {
		my $Image = $self->getImage();
		@$self{'src_width','src_height'} = $Image->Get('width','height');
		undef $Image;
	} # end if
	return $$self{'src_height'};
} # end sub src_height

sub crop {
	my ( $self, $crop, $new ) = @_;
	if ( ! defined $$self{'crop_'.$crop} ) {
		if ( $$self{'crop_box'} ) {
			@$self{'crop_top','crop_right','crop_bottom','crop_left'} = $$self{'crop_box'} =~ /^\((\d+),(\d+)\),\((\d+),(\d+)\)$/;
			$$self{'crop_top'} = $self->height() - $$self{'crop_top'};
			$$self{'crop_bottom'} = $self->height() - $$self{'crop_bottom'};
			$$self{'crop_right'} = $self->width() - $$self{'crop_right'};
#$openprint::log->debug("decoded $$self{crop_box} to $$self{crop_top} $$self{crop_bottom} $$self{crop_left} $$self{crop_right}");
		} else {
			@$self{'crop_top','crop_right','crop_bottom','crop_left'} = ( 0, $self->width(), $self->height(), 0 );
#$openprint::log->debug("Defaults: $$self{crop_top} $$self{crop_bottom} $$self{crop_left} $$self{crop_right}");
		} # end if
	} # end if
	if ( @_ == 3 ) {
		$$self{'crop_'.$crop} = $new;
		$$self{'crop_box'} = sprintf('(%d,%d),(%d,%d)', 
			($self->height()-$$self{'crop_top'}),
			($self->width()-$$self{'crop_right'}),
			($self->height()-$$self{'crop_bottom'}),
			($$self{'crop_left'}),
		);
	} # end if
	return $$self{'crop_'.$crop};
} # end sub crop

sub crop_top {
	my $self = shift;
	return $self->crop('top', @_ );
} # end crop_top

sub crop_bottom {
	my $self = shift;
	return $self->crop('bottom', @_ );
} # end crop_bottom

sub crop_left {
	my $self = shift;
	return $self->crop('left', @_ );
} # end crop_left

sub crop_right {
	my $self = shift;
	return $self->crop('right', @_ );
} # end crop_right

sub width {
	if ( @_ == 2 ) {
		$_[0]{'width'} = $_[1];
	} # end if
	if ( ! defined $_[0]{'width'} ) {
		return 640;
	#} else {
		#$openprint::log->debug("Width defined as $_[0]{width}");
	} # end if
	return $_[0]{'width'};
} # end sub width

sub height {
	if ( @_ == 2 ) {
		$_[0]{'height'} = $_[1];
	} # end if
	if ( ! defined $_[0]{'height'} ) {
		my $ratio = $_[0]->src_width/$_[0]->width();
		return int($_[0]->src_height()/$ratio);
	} # end if
	return $_[0]{'height'};
} # end sub height
1;
__END__
