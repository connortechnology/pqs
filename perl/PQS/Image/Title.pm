=head1 NAME

PQS::Image::Title - Generates and caches PQS title images under mod_perl.

=head1 SYNOPSIS

As an apache handler:

  <Location image/title>
      SetHandler     perl-script
      PerlHandler    PQS::Image::Title
      PerlSendHeader On
  </Location>

To generate an image internally:

  use PQS::Image::Title;
  
  my $png = generate($text, $truetype_font, @colours);

=head1 DESCRIPTION

As an Apache handler, the handler generates a PQS title image and caches it to
the directory specified. The filename.png after the directory is rendered as
the text of the image with the first letter of each word of (words are denoted by
an underscore) capitalised. The image is saved and only re-rendered if either
the colours or font face changes.

The only exported function is C<generate()> which will return a binary PNG.

PQS::Image::Title

=head1 TODO
=over
=item 

Better exception handling. Currently we die on errors that could just give a
warning and be handled.

=item 

Startup caching of colours and maybe font.

=item

Use a general PQS config instead of colours.txt.

=cut
package PQS::Image::Title;
use strict;
use warnings;

use base qw(Exporter);
our @EXPORT_OK = qw(generate);

use Apache2::Const qw(:common :http);
use Apache2::File;
use Apache2::Log ();
use GD;
use Fcntl qw(:flock);
use session;

# Template image control.
use constant COLOURS   => '/styles/colours.txt';
use constant FONT_FACE => '/styles/title_font.ttf';

use constant WIDTH     => 500;          # Canvas X dimension.
use constant HEIGHT    => 35;           # Canvas Y dimension.
use constant FONT_SIZE => 20;           # Font size (in points).
use constant BASELINE  => HEIGHT - 10;  # X offset for font baseline.
use constant OFFSET    => 6;            # Y offset for word spacing.

# Global colour cache ([R,G,B] format).
our @colours;

sub handler {
    my $r = shift;

    # Create a case sensitive title (image text)/filename (for caching) for
    # the image. It's what's left of the URI after the location and file
    # extension are removed, with the first letter of every word capitalised
    # (internal caps are respected).
    my $location = $r->location;

    my ($title) = ( $r->uri =~ m|$location/?(\w+)(?:\.png)$| );
        $title  = join ' ', map { ucfirst $_ } split/_/, $title;

    return NOT_FOUND unless $title;

    session::r($r);
    session::log($r->log);

    # The path to support files (site_specific stuff may not be under docroot).
    my $path = $r->dir_config('site_specific') || $r->document_root.'/site_specific/';

    # If it wasn't for the fact site_specific files could be stored outside
    # the document root, we could use $r->filename. As it is we need to
    # generate the path from the requested location.
    my $filename = $path.$r->uri; $filename =~ s/site_specific\///;


    #
    # IMAGE GENERATION
    #
    
    # Determine if we need to (re)generate the image.
    my $generate = 0;
    
    # We need to generate the image if it doesn't exist in the cache.
    if (not -e $r->filename) {
        @colours  = get_colours($path.COLOURS) 
            if not defined @colours;
        $generate = 1; 
    }
    else {
        # Get the last modified dates for all the files in question.        
        my ($image, $colours, $font) = map { (stat($_))[9] } 
                                $r->filename, $path.COLOURS, $path.FONT_FACE;
        
        # Regenerate the image if either of the support files have been
        # modified since the image was last generated.
        $generate = 1 if $colours > $image or $font > $image;

        # Re-populate the global colour cache.
        @colours = get_colours($path.COLOURS) if $colours > $image;
    }
    
    # Generate the image and write it to disk if need be.
    if ($generate) {
        output_file($filename, generate($title, $path.FONT_FACE, @colours))
    }
 
    
    #
    # SERVE REQUESTED FILE
    #

    my $fh = Apache2::File->new;

    # Any error at this point is likely a permissions issue.
    $fh->open($filename) or return FORBIDDEN;
    
    # Set the file size, modification time, etc. headers for the client.
    $r->content_type('image/png');
    $r->set_content_length( -s $filename);
    $r->set_last_modified( (stat($filename))[9] );

    # If the client is only requesting the header, we'll give them just that.
    return OK if $r->header_only;
    
    # Lock the file for shared access, if a lock can't be aquired tell the
    # client the resource isn't currently available.
    flock   $fh, LOCK_SH or return HTTP_SERVICE_UNAVAILABLE;
    binmode $fh; 
    
    $r->send_fd($fh);   # Output the file.

    flock $fh, LOCK_UN; # Unlock and cleanup.
    close $fh;

    return OK;
}

# Given a title string, truetype font path, and colours to render the image in
# (background, primary, secondary) return a PNG of the PQS title requested.
sub generate {
    my $text    = shift; # The text to render.
    my $font    = shift; # Font to render it it.
    my @colours = @_;    # Background, primary, and secondary colours.

    # Some simple assertions.
    die "Empty/undefined text."                             if not $text;
    die "Need a background, primary, and secondary colour." if @colours < 3;

    # Create the canvas.
    my $img = GD::Image->new(WIDTH, HEIGHT, 0);

    # Get the background, primary, and secondary colours, allocating them to
    # the image palatte. The background is anti-aliased.
    my @colour = map { $img->colorAllocate( @$_ ) } @colours;
    $img->transparent($colour[0]);

    # Draw a horizontal rule unders the baseline of the title text.
    #$img->setAntiAliased($colour[1]); gdAntiAliased
    $img->setThickness(1);
    $img->line(0, BASELINE, WIDTH, BASELINE, $colour[1]);
        
    # We preserve the case given, except for the first character of each word
    # (words are denoted by an underscore) which always gets upper case.
    my @words = grep /$_/, map { ucfirst $_ } split' ', $text;

    # Draw the first word in the same colour as the rule, just above it.
    my $first  = shift @words;
    my @bounds = $img->stringFT($colour[1], $font, FONT_SIZE, 0, -1, BASELINE, $first)
        or die "Could not process font (" . $font ."): $!";
    
    # Each subsequent word in the title is drawn in the secondary colour and
    # offset from the previous word (on the X axis) by OFFSET pixels. The
    # lower right corner x co-ordinate is the second element of bounds;
    @bounds = $img->stringFT($colour[2], $font, FONT_SIZE, 0, $bounds[2] + OFFSET, BASELINE, $_)
        for @words;
    
    # $img->clip(0, 0, $bounds[2] < LINE ? LINE : $bounds[2], HEIGHT);
   
    return $img->png;
}

# Retrieve the colours from the site specific colour file.
sub get_colours {
    my $filename = shift; # The colour definition file.
    my %colours;

    my $fh = Apache2::File->new;
    $fh->open("<$filename") or die "Could not open colours ($filename): $!";
    flock $fh, LOCK_SH      or die "Could not lock colours ($filename): $!";

    # Many colour records in the format "label: #FFFFF" may be stored in the
    # colour file. Use a simple regex to grab the record and conver the hex
    # colour scheme to decimal RGB.
    while ( <$fh> ) {
        next unless /^\s*(\w+):\s*#([a-f0-9]{2})([a-f0-9]{2})([a-f0-9]{2})\s*$/i;
        $colours{ lc($1) } = [ hex($2), hex($3), hex ($4) ];
    }
    
    flock $fh, LOCK_UN;    
    $fh->close;

    # We only need these three.
    return map { $colours{$_} } qw(background dark light);
}

# Given a filename and binary data, write to the file.
sub output_file {
    my $filename = shift;
    my $image    = shift;

    my $fh = Apache2::File->new; 

    $fh->open(">$filename") or die "Could not open image file ($filename): $!";
    flock   $fh, LOCK_EX    or die "Could not lock image file ($filename): $!";
    binmode $fh; 
    print   $fh $image      or die "Could not write image file ($filename): $!";
    flock   $fh, LOCK_UN;
    $fh->close;

    return 1;
}

1;
