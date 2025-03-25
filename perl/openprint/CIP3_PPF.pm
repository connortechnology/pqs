use strict;
package openprint::CIP3_PPF;
our @ISA = qw(openprint::Object);

require sets;
require misc;
require sql;
require openprint::Object;
require Compress::Zlib;
use openprint ();
use MIME::Base64;
use Image::Magick;

use vars qw( $debug $log $dbh %config $table $serial %fields %find_fields %transforms %defaults );

$debug = 1;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;

$table = 'CIP3_PPF';
$serial = 'CIP3_PPF_id_seq';
%fields = (
	id						=>	'id',
	created_on		=>	'created_on',
	data					=>	'data',
	front_preview	=>	'front_preview',
	back_preview	=>	'back_preview',
	signature			=>	'signature',
	side					=>	'side',
	docket				=>	'docket',
	version				=>	'version',
	deleted				=>	'deleted',
	compressed		=>	'compressed',
);
%find_fields = (
	status		=>	'(SELECT strstatus from tbl_Projects WHERE lngdocketnumber=docket)',
);
%defaults = (
	created_on	=>	q`'NOW()'`,
	deleted			=>	0,
);
%transforms = (
	signature		=> [ 's/\D//g' ],
);

my %WorkStyles = (
	Perfecting	=>	'Perfecting',
	WorkAndTurn	=>	'Work & Turn',
	WorkAndBack	=>	'Work & Tumble',
);

sub runstyle {
	my ( $self ) = @_;
	if ( ! $$self{parsed} ) {
		$self->parse();
	} # end if
	if ( $$self{WorkStyle} and ! $WorkStyles{$$self{WorkStyle}} ) {
		$log->error("Unknown Workstyle: $$self{WorkStyle}");
	} 
	return $WorkStyles{$$self{WorkStyle}};
}

sub parseSheet {
	my $sheet = shift @_;
	while ( @_ ) {
		my $line = shift @_;
		if ( $line =~ /^CIP3AdmWorkStyle \/(\w+) def$/ ) {
			$$sheet{WorkStyle} = $1;
		} elsif ( $line =~ /^CIP3AdmPaperExtent \[ ([\d\.]+) ([\d\.]+) \] def$/ ) {
			$$sheet{StockWidth} = $1;
			$$sheet{StockHeight} = $2;
		} elsif ( $line =~ /^CIP3BeginFront/ ) {
			$$sheet{Front} = {};
			@_ = parseSide( $$sheet{Front}, @_ );
		} elsif ( $line =~ /^CIP3BeginBack/ ) {
			$$sheet{Back} = {};
			@_ = parseSide( $$sheet{Back}, @_ );
		} elsif ( $line =~ /^CIP3EndSheet/ ) {
			last;
		} # end if
	} # end while
	return @_;
} # end sub parseSheet

sub parseSide {
	my $front = shift @_;
	while ( @_ ) {
		my $line = shift @_;
		if ( $line =~ /^CIP3BeginPreviewImage$/ ) {
			my $preview = {};
			@_ = parsePreviewImage( $preview, @_ );
			push @{$$front{previews}}, $preview;
		} elsif ( $line =~ /^CIP3EndFront$/ ) {
			last;
		} elsif ( $line =~ /^CIP3EndBack$/ ) {
			last;
		} # end if
	} # end while
	return @_;
} # end sub parseFront

sub parsePreviewImage {
	my $image = shift;
	my @inks = ( 'Cyan','Magenta','Yellow','Black' );
	while ( @_ ) {
		my $line = shift @_;
		if ( $line =~ /^\( Separation preview for ink: "(\w+)" \) CIP3Comment/ ) {
			my $separation = {};
			$$separation{ink} = $1;
			@inks = sets::exclude( [$1], \@inks );
			$line = shift @_;
			if ( $line =~ /^CIP3BeginSeparation$/ ) {
#$log->debug("Start parseSeparation ($$separation{ink}) @inks");
				@_ = parseSeparation( $separation, @_ );
#$log->debug("Done parseSeparation ($$separation{ink}) @inks");
				push @{$$image{separations}}, $separation;
			} # end if
		} elsif ( $line =~ /^CIP3BeginSeparation$/ ) {
			my $separation = {};
			$$separation{ink} = shift @inks;
#$log->debug("Start parseSeparation ($$separation{ink}) @inks");
			@_ = parseSeparation( $separation, @_ );
#$log->debug("Done parseSeparation ($$separation{ink}) @inks");
			push @{$$image{separations}}, $separation;
		} elsif ( $line =~ /^\/CIP3AdmSeparationNames \[ (.*) \] def$/ ) {
			my $separations = $1;
			$separations =~ s/[\(\)]//g;
			@inks = split(' ', $separations);
#$log->debug("INK Sep @inks");
		} elsif ( $line =~ /^CIP3EndPreviewImage/ ) {
			last;
		} # end if
	} # end while
	return @_;	
} # end sub parsePreviewImage

sub parseSeparation {
	my $image = shift @_;
	while ( @_ ) {
		my $line = shift @_;
#$log->debug($line);
		if ( $line =~ /^\/CIP3PreviewImageWidth (\d+) def/ ) {
			$$image{width} = $1;
		} elsif ( $line =~ /^\/CIP3PreviewImageHeight (\d+) def/ ) {
			$$image{height} = $1;
		} elsif ( $line =~ /^\/CIP3PreviewImageEncoding \/(\w+) def/ ) {
			$$image{encoding} = $1;
		} elsif ( $line =~ /^\/CIP3PreviewImageCompression \/(\w+) def/ ) {
			$$image{compression} = $1;	
		} elsif ( $line =~ /^\/CIP3PreviewImageBitsPerComp (\d+) def/ ) {
			$$image{depth} = $1;
		} elsif ( $line =~ /^\/CIP3PreviewImageComponents/ ) {
		} elsif ( $line =~ /^\/CIP3PreviewImageMatrix \[\s*([\d\.\-]*)\s+([\d\.\-]*)\s+([\d\.\-]*)\s+([\d\.\-]*)\s+([\d\.\-]*)\s+([\d\.\-]*)\s*\] +def/ ) {
			$$image{matrix} = sprintf('%d %d %d %d %d %d', $1, $2, $3, $4, $5, $6 );
#$log->debug("Matrix: $line ");
		} elsif ( $line =~ /^\/CIP3PreviewImageResolution/ ) {

		} elsif ( $line =~ /^CIP3PreviewImage$/ ) {
			$line = shift;
			my @image_data;
			while ( @_ and ! ( $line =~ /^CIP3EndSeparation/ ) ) {
				push @image_data, $line;
				$line = shift;
			} # end while
			$$image{image} = join("\r\n", @image_data);
			last;
		} elsif ( $line =~ /^CIP3EndSeparation/ ) {
			last;
		} else {
			$log->warn("UNknown line: $line in parseSeparation");
		} # end if
	} # end while
	return @_;
} # end sub parseSeparation

sub parse {
	my ( $self ) = @_;

	$$self{parsed} = 1;
	$_ = decode_base64($$self{data});
	$openprint::log->error("Unable to decode") if $$self{data} and ! $_;
	$_ = Compress::Zlib::uncompress($_) if $$self{compressed};
	$openprint::log->error("Unable to uncompress" . length $$self{data} ) if $$self{data} and ! $_;
	my @data = split("\r\n", $_ );
#$log->debug("# of lines: " . @data ) if $debug;
	while ( @data ) {
		my $line = shift @data;
		if ( $line =~ /^CIP3BeginSheet$/ ) {
			my $sheet = {};	
			@data = parseSheet( $sheet, @data );
			push @{$$self{sheets}}, $sheet;
		} # end if
	} # end while
} # end sub parse;


sub previews {
	my ( $self, $side ) = @_;
	if ( ! $$self{parsed} ) {
		$self->parse();
	} # end if

	if ( $$self{sheets} and ! $$self{previews} ) {
		my $previews = $$self{previews} = {};

		foreach my $sheet ( @{$$self{sheets}} ) {
			$$previews{Front} = $$sheet{Front}{previews} if $$sheet{Front} and $$sheet{Front}{previews};
			$$previews{Back} = $$sheet{Back}{previews} if $$sheet{Back} and $$sheet{Back}{previews};
		} # end foreach sheet
	}
	my $previews = $$self{previews};

	if ( $side ) {
		if ( wantarray ) {
			return $$previews{$side} ? @{$$previews{$side}} : ();
		} 
		return $$previews{$side};
	}
	if ( wantarray ) {
		return (
			( $$previews{Front} ? @{$$previews{Front}} : () ),
			( $$previews{Back} ? @{$$previews{Back}} : () ),
				);
	}
	return $previews;
} # end sub previews

sub side {
	my $self = shift;
	$$self{side} = shift if @_;
	if ( !$$self{side} ) {
		my $previews = $self->previews();
		if ( $$previews{Front} and $$previews{Back} ) {
			$$self{side} = 'M';
		} elsif ( $$previews{Front} ) {
			$$self{side} = 'Front';
		} elsif ( $$previews{Back} ) {
			$$self{side} = 'Back';
		} else {
			$openprint::log->error("No side");
		}
	} # end if ! side
	return $$self{side};
}

sub generate_previews {
	my ( $self, $path, $force ) = @_;

	$path = $config{SkinPath} . '/images/previews/' if $config{SkinPath} and ! $path;
	my $part_path = '';
	foreach my $e ( split ('/', $path ) ) {
		$part_path .= $e . '/';
		mkdir $part_path unless -d $path;
	} # end foreach

	my $changed = 0;
	foreach my $side ( 'Front', 'Back' ) {
		my $filename = sprintf('%s%dsg%dsd%s.jpg', $path, $self->get('docket','signature'), $side );
		if ( (!$force) and -f $filename ) {
			$log->warn("$filename exists, not generating the preview.");	
			next;
		} else {
#$log->debug("Blah");
#$log->warn("generating preview for ".$self->to_string(). " Force: $force Previews: " . length($$self{lc($side).'_preview'}) );
		} # end if

		if ( $force or (length $$self{lc($side).'_preview'} < 100 )) {
			if ( ! $$self{parsed} ) {
				$self->parse();
			} # end if

			my @previews = $self->previews($side);
			if ( ! @previews ) {
#$log->error("NO Previews for side $side");
			} # end if

			foreach my $preview ( @previews ) {
				if ( ! $$preview{separations} ) {
					$log->warn('No separations in preview.');
				} # end if

				my $image_data;
				my $depth = $$preview{separations}[0]{depth};
				my $width = $$preview{separations}[0]{width};
				my $height = $$preview{separations}[0]{height};

				foreach my $image ( @{$$preview{separations}} ) {
					if ( $$image{encoding} eq 'ASCIIHexDecode' ) {
						require Text::PDF::Filter;
						my $f = Text::PDF::ASCIIHexDecode->new;
						$$image{image} = $f->infilt($$image{image}, 1 );
					} # end if
					if ( $$image{compression} eq 'RunLengthDecode' ) {
						$$image{image} = misc::rle_decode($$image{image});
						$$image{compression} = 'None';
					} elsif ( $$image{compression} eq 'DCTDecode' ) {
						my $Image = Image::Magick->new(magick=>'jpg');
						$_ = $Image->BlobToImage($$image{image});
						$log->error( $_ ) if $_;
					} elsif ( $$image{compression} eq 'None' ) {
					} else {
						$log->error("Unknown compression $$image{compression}");
					} # end if
				} # end foreach separation

				my $orientation;
				my $s = $$preview{separations}[0];
				if ( $$s{matrix} eq "$$s{width} 0 0 $$s{height} 0 0" ) {
					$orientation = 'left-bottom';
				} elsif ( $$s{matrix} eq "$$s{width} 0 0 -$$s{height} 0 $$s{height}" ) {
					$orientation = 'left-top';
				} elsif ( $$s{matrix} eq "-$$s{width} 0 0 $$s{height} $$s{width} 0" ) {
					$orientation = 'right-bottom';
				} elsif ( $$s{matrix} eq "-$$s{width} 0 0 -$$s{height} $$s{width} $$s{height}" ) {
					$orientation = 'right-top';
				} elsif ( $$s{matrix} eq "0 $$s{height} $$s{width} 0 0 0" ) {
					$orientation = 'bottom-left';
				} elsif ( $$s{matrix} eq "0 $$s{height} -$$s{width} 0 $$s{height} 0" ) {
					$orientation = 'top-left';
				} elsif ( $$s{matrix} eq "0 -$$s{height} $$s{width} 0 0 $$s{width}" ) {
					$orientation = 'bottom-right';
				} elsif ( $$s{matrix} eq "0 -$$s{height} -$$s{width} 0 $$s{height} $$s{width}" ) {
					$orientation = 'top-right';
				} # end if
#$log->debug("Orientation: $orientation");

				my %separations;
				foreach my $s ( @{$$preview{separations}} ) {
					$separations{$$s{ink}} = $s;
				} # end foreach
				if ( $orientation eq 'bottom-left' ) {
					my @cols =  ( 1 .. $height );
					my @rows =  reverse ( 1 .. $width);
					foreach my $w ( @cols ) {
						foreach my $h ( @rows ) {
							foreach my $ink ( 'Cyan','Magenta','Yellow','Black' ) {
								if ( $separations{$ink} ) {
									$image_data .= substr( $separations{$ink}{image}, ($h-1)*$height+($w-1), 1 );
								} else { 
									$image_data .= pack('C', 255 );
								} #end if;
							} # end foreach ink
						} # end foreach w
					} # end foreach h
				} else {
# Just interleave
					foreach my $pos ( 1 .. ($width*$height) ) {
						foreach my $ink ( 'Cyan','Magenta','Yellow','Black' ) {
							if ( $separations{$ink} ) {
								$image_data .= substr( $separations{$ink}{image}, $pos-1, 1 );
							} else { 
								$image_data .= pack('C', 255 );
							} #end if;
						} # end foreach ink
					} # end foreach
				} # end if
#$log->error("Assembling CMYK image from separations. Width: $width x $height = " . $width*$height*4 . " dept: $depth " . length $image_data );

				my $Image = Image::Magick->new(magick=>'cmyk',depth=>$depth,size=>$width.'x'.$height,'debug'=>'Blob','colorspace'=>'CMYK','orientation'=>$orientation);
#$log->debug("Orientation Mgick: " . $Image->Get('orientation') );
				$_ = $Image->BlobToImage($image_data);
				$log->error( $_ ) if $_;
				$_ = $Image->Negate('channel'=>'CMYK');
				$log->error( $_ ) if $_;
#$_ = $Image->Quantize('colorspace'=>'RGB');
#$log->error( $_ ) if $_;
				$_ = $Image->Set('magick'=>'jpg','colorspace'=>'RGB','orientation'=>$orientation);
				$log->error( $_ ) if $_;
#$log->debug("Orientation Mgick: " . $Image->Get('orientation') );
				my @blobs = $Image->ImageToBlob();
#$log->debug("# of blobs: " . @blobs );
				if ( ! @blobs ) {
					$log->debug("No blobs");
				} else {
					$$self{lc($side).'_preview'} = encode_base64($blobs[0]);
					if ( ! $$self{lc($side).'_preview'} ) {
						$log->debug("No good ImageToBlob");
					}
				}
				$changed = 1;
			} # end foreach preview
		} # end if force or ! side_preivew
		if ( $path ) {
			my $filename = sprintf('%s%dsg%dsd%s.jpg', $path, $self->get('docket','signature'), $side );
			$log->debug("Writing to $filename") if $debug;
			if ( $$self{lc($side).'_preview'} ) {
				$_ = misc::save_file( $log, $filename, decode_base64($$self{lc($side).'_preview'}) );
				$log->error( $_ ) if $_;
			} elsif ( ! $self->previews($side) ) {
				$log->error("No data in the preview for $filename");
			} # end if
		} else {
			$log->error("No path");
		} # end if
	} # end foreach side
	if ( $changed ) {
		$_ = $self->save();
		$log->error( $_ ) if $_;
	} # end if
} # end sub generate_previews

sub send_ppf {
	my ( $self, $Equipment ) = @_;
	my $data = decode_base64($$self{data});
	if ( ! $data ) {
		$log->error('No data in send_ppf '.$self->to_string());
		return;
	} # end if
	$data = Compress::Zlib::uncompress($data) if $self->compressed();
	if ( ! $data ) {
		$log->error('No uncompressed data in send_ppf');
		return;
	} # end if

	if ( 0 ){
		$log->debug('PPF DATA: ' . $data . "uncomressed: " . decode_base64($$self{data}) );
		if ( ! ( $data =~ /^%!PS\-Adobe/ ) ) {
			$log->error( "Didn't find signature\n");
# Must be already compressed.
			while ( $_ = Compress::Zlib::uncompress($data) ) {
				$log->debug( "Uncompressing\n");
				$data = $_;
			} 
			print substr($data, 0, 10 ) . "\n";
			if ( ! ( $data =~ /^%!PS\-Adobe/ ) ) {
				$log->error( "Still didn't find signature");
				return;
			} 
		} 
	} 
#$log->warn("Saving PPF: " . sprintf('%s/%d_Sg%dSd%s.ppf', $$Equipment{cip3_out}, @$self{'docket','signature','side'}, ) );
	my $error = misc::save_file( $log, sprintf('%s/%d_%sSg%dSd%s.ppf', $$Equipment{cip3_out}, @$self{'docket','version','signature','side'}), $data);
	if ( $error ) {
		$log->error($error);
		if ( $$self{docket} ) {
			foreach my $Project ( openprint::Project->find(docket=>$$self{docket}) ) {
				$Project->add_to_log( @openprint::session{'company_id','user_id'}, "Failed to send CIP Files for form $$self{signature} side $$self{side}. Reason: $error");
			} # end foreach $Project
		} # end if

		return $error;
	} 
	if ( $$self{docket} ) {
		foreach my $Project ( openprint::Project->find(docket=>$$self{docket}) ) {
			$Project->add_to_log( @openprint::session{'company_id','user_id'}, "CIP Files released for form $$self{signature} side $$self{side}" );
		} # end foreach $Project
	} # end if docket
	return;
} # end sub send_ppf

sub convert_job_name {
	my ( $self, @data ) = @_;
	my @results;

	for ( my $i = 0; $i < @data; $i += 1 ) {
		my $line = $data[$i];
		if ( $line =~ /^\/CIP3AdmJobCode\s+\((.*)\)\s+def(.*)/ ) {
			if ( ! $1 ) {
				$line = "/CIP3AdmJobCode ($$self{docket}) def$2\r\n";
			} # end if
		} elsif ( $line =~ /^\/CIP3AdmJobName\s+\((.*)\)\s+def/ ) {
			my $job_name = $1;
			if ( length $job_name > 16 ) {
				if ( my ( $pre, $j_name, $sig ) = ( $job_name =~ /(\d+\w\w)(.+)SIG(\d\d\d)/ ) ) {
					$line = '/CIP3AdmJobName ('.$pre.(substr($j_name,0,4)).'Sg'.$sig.'Sd'.$$self{side}.") def\r\n";
				} else {
					$line = '/CIP3AdmJobName ('.(substr($job_name,0,16)).") def\r\n";
				} # end if
			} # end if
		} # end if
		push @results, $line;
	} # end foreach line
	return @results;
} # end sub convert_job_name

sub convert_sheet_name {
	my ( $self, @data ) = @_;

	my @results;

	for ( my $i = 0; $i < @data; $i += 1 ) {
		my $line = $data[$i];
		if ( $line =~ /^\/CIP3AdmSheetName \(Sheet (\d*)\) def/ ) {
			$line = sprintf("/CIP3AdmSheetName (Sig#%dSheet#%d) def\r\n", 1*$_[0]{signature}, $1);
		}
		push @results, $line;
	} # end foreach line
	return @results;
}

sub to_string {
	return sprintf('%d Sig: %d Side: %s', $_[0]{docket}, $_[0]{signature}, $_[0]{side});
} # end sub to_string

sub upload {
	my ( $self, $filename, $param ) = @_;
  my $upload = $openprint::r->upload($filename);
  if ( ! $upload ) {
    return "There was no upload for $filename<br/>";
  } # end if
  my $data;
  $upload->slurp($data);
	
	my $compressed_data = Compress::Zlib::compress($data);
	$log->debug('Compressed PPF from ' . (length $data) . ' to ' . (length $compressed_data) ) if $debug;
  $self->save({
      docket      =>  $$param{docket},
      signature   =>  $$param{signature},
      side        =>  $$param{side},
      version  		=>  $$param{version},
      data        =>  encode_base64($compressed_data ? $compressed_data : $data),
      compressed  =>  ($compressed_data ? 1 : 0),
      });

} # end sub upload

1;
__END__
