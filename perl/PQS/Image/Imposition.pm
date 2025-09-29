=head1 NAME

PQS::Image::Imposition - Generate an SVG representations of press sheet
impositions.

=head1 SYNOPSIS

As an apache handler:

  <Location image/imposition>
      SetHandler     perl-script
      PerlHandler    PQS::Image::Imposition
      PerlSendHeader On
  </Location>

=head1 DESCRIPTION

Generates an generalised imposition image showing the press sheet with margins
and the locations of the images on it.

=head CACHE

There is no long any cache, everything is generated on the fly.

=head1 TODO
=over

=item
Where to start? Generation functionality, error checking and handling,.

=item
An error document that is an SVG image.

=item
Add modification and expire information. C<$r->no_cache(1)> is not an option
as it prevents IE Win using the Adobe SVG Viewer from using "View SVG" in the
context menu.

=item
Add a cache. Either we can cache per project (not much benefit) or we'll need
to serialise quite a few (at least eight) fields into a key.

=back
=cut
package PQS::Image::Imposition;
use utf8;
use strict;
use warnings;

use base qw(Exporter);
our @EXPORT_OK = qw(generate);

use Apache2::Const qw(:common :http);
use Apache2::Request ();
use Fcntl qw(:flock);
use Compress::LZF q(sthaw);
use Data::Dumper;
use MIME::Base64;
use Storable qw(thaw);
use session;

use SVG;

use eprint::Config;
use PQS::DB;
use PQS::Imposition::Constants;
use PQS::Imposition::Colour qw(:all);

require openprint;

use vars qw( $r %variable %session %param %config $log $dbh $starttime );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

# Canvas size, taken from max imposition bounds.
use constant { 
    MAX_X => eprint::Config->get(Imposition => 'bound_x') + 4, 
    MAX_Y => eprint::Config->get(Imposition => 'bound_y') + 4 
}; 
use constant PADDING => 2; # Padding around largest sheet size.

use constant DPI => 900; # Rasterization DPI for SVG -> bitmap

use constant STYLESHEET => '/site_specific/base-css/imposition.css';

# Grabs the imposition information from the DB for the passed and generates an
# image of it on-the-fly.
sub handler {
    $r = shift;
    $r = Apache2::Request->new($r);

    # Service ID (will be checked later for existance).
    my $sid = $r->param('sid'); 
       $sid =~ tr/0-9//cd;
    return NOT_FOUND unless $sid;

    session::r($r);
#    session::log($r->log);
    $log = $r->log;
    
    # The layout number only applies in multi-version. Any integer from 0..inf
    # is allowed.
    my $n = $r->param('n');
       $n =~ tr/0-9//cd;
       $n = 0 unless defined $n and $n >= 0;

    # Retrieve the imposition "object" (heh) from the database.
    my $imp = imposition($r, $sid);

    # If we can't find the service, it's not the correct type of service, or
    # it doesn't have the object we expected we'll say we can't find it.
    return NOT_FOUND 
        unless defined $imp 
           && ref $imp eq 'eprint::impositionObject'
           && defined $imp->{layout}[$n];

    my ($filetype) = ($r->filename =~ /\.(svgz?|png)$/);

    # Generate the imposition image.
    my $image = generate($imp, $n, ($filetype eq 'png' ? load_stylesheet($r) : ()));

    if ($filetype =~ /^svg/) {
        # Compressed SVGs should always be supported in addition to cleartext.
        if ($filetype eq 'svgz') {
            require Compress::Zlib;
            $image = Compress::Zlib::memGzip($image);

            my ($ie_version) = $ENV{HTTP_USER_AGENT} =~ /MSIE (\d+\.\d+)/i;

            # Older IEs don't like this header (which is supposed to be there).
            $r->content_encoding('gzip') unless ($ie_version && $ie_version < 6);
        }

        $r->content_type('image/svg+xml; charset=utf-8');
        $r->headers_out->{'Content-Length'} = length $image;
    }
    elsif ($filetype eq 'png') {
        # Render a PNG for clients that don't support SVG (IE for example).
        require Image::Magick;

        my $img = Image::Magick->new(
            magick => 'svg',
            density => DPI,
        );
        $img->BlobToImage($image);
    
        # Preview images are scaled down versions of the full image.
        $img->Scale(geometry => ($r->param('preview') ? '190x190' : '740x740'));
        $img->Set(magick => 'png');

        $image = $img->ImageToBlob();

        # Set the file size, modification time, etc. headers for the client.
        $r->content_type('image/png');
        $r->headers_out->{'Content-Length'} = length $image;
    }
    else { die "Filetype ($filetype) not supported." }

    $r->headers_out->{'Content-Disposition'} = qq{inline; filename="imposition-$sid-$n.$filetype"};

    # If the client is only requesting the header, we'll give them just that.
    return OK if $r->header_only;

    print $image;

    return OK;
}

# Get the services imposition as a frozen datastructure. It's stored where it
# is due to legacy code and time constraints. Originally we were going for a
# binary stored in ByteA but it's now a Base64 encoded LZF compressed
# 'Storable' structure.
sub imposition {
    my ($r, $sid) = @_;

    my $dbh = PQS::DB->connect($r);
    my $frozen = $dbh->selectrow_array(q{
        SELECT strvalue FROM tbl_service_specifications
        WHERE strname = 'imp' AND lngserviceindex = ?
    }, {}, $sid);
    return undef unless $frozen;

    session::dbh($dbh);

    my $imposition = sthaw(decode_base64($frozen));

    # Due to some persistant interpretter/mod_perl issue we need to 'prime'
    # the package before we can retrieve into it.
    require PQS::Imposition::Node;
    my $tmp = PQS::Imposition::Node->new(cut => 0, size => [1,1]);
    undef $tmp;
   
    $imposition->{tree} = thaw($imposition->{tree}); # Frozen object.

    return $imposition;
}

# Load the stylesheet from disk for embedding (for bitmap generation).
sub load_stylesheet {
    my $r = shift;

    my $fh;
    if (!open($fh, $r->document_root . STYLESHEET)) {
      #$openprint::log->error("Couldn't open stylesheet at ".($r->document_root . STYLESHEET)." : $!");
      return \'';
    }
   
    flock   $fh, LOCK_SH or die "Couldn't lock styles for reading\n";
    binmode $fh; 
 
    my $styles = do { local $/ = undef; <$fh> };
 
    flock $fh, LOCK_UN; # Unlock and cleanup.
    close $fh;

    return \$styles;
}

# Create a SVG image to represent the imposition.
sub generate {
    my ($imposition, $n, $stylesheet) = @_;
    my $versions = $imposition->{layout}[$n]; # Chosen layout.
    
    my ($sheet, $style, $tree) = @{ $imposition }{qw(paper style tree)};

    # Make sure we're working on what we think we are.
    unless ($tree and ref $tree eq 'PQS::Imposition::Node') {
        die "Invalid imposition tree. ",
            "Expected: PQS::Imposition::Node Got: ", ref $tree, "\n";
    }

    # If the sheet is rotated change that once here so we don't have to
    # constantly check the rotation.
    @{ $sheet }{qw(width height)} = @{ $sheet }{qw(height width)}
        if $imposition->{rotate_sheet};

    # DOCUMENT
    #
    # Our SVG will be slightly larger than our sheet.
    my ($w, $h) = @{ $sheet }{qw(width height)};

    # Create the document.
    my $svg = SVG->new(
        width      => '100%',
        height     => '100%',
        viewBox    => join(q{ } => 0, 0, MAX_X, MAX_Y), # In local units (inches)
        -nocredits => 1,
        -standalone => 'no',
        preserveAspectRation => 'xMidYMid meet',  # Keep relative size.
    );


    # Attach our external stylesheet (unless one was provided).
    unless ($stylesheet) {
        my $pi = $svg->pi(
            'xml-stylesheet type="text/css" href="' . STYLESHEET . '"'
        );
        $pi->removeSelf; # This removes a fake 'pi' element but not the directive.
    }

    # DEFINTIONS
    # 
    # Create a definition section.
    my $define = $svg->defs();

    # If an embedded stylesheet was provided, add it.
    $define->style->CDATA($$stylesheet) if $stylesheet;

    drop_shadow($define);         # Create a drop shadow effect.
    colour_bar($define);          # The colour bar pattern.
    # images($define, $imposition); # The unique images in the imposition.
    
    my $colours = slot_colours($imposition, $n);

print STDERR "HAVE N: $n \n", Dumper($versions, $imposition);

    my $group = $define->group(id => 'imposition');

    # Draw each node in the layout starting with the root.
    draw_node($group, $tree, $colours, [0,0]);

    
    # DRAWING
    #    
    # Draw a white backgound as transparency prints as black on many browsers.
    $svg->rect(
        id     => 'background', 
        x      => 0,     y      => 0, 
        width  => MAX_X, height => MAX_Y, 
    );

    # Now that we've defined the various elements we can combine them on the
    # canvas to create a full image.

    my $offx = (MAX_X - $w) / 2;
	my $offy = (MAX_Y - $h) / 2;

    my $offset = join(q{, }, ((MAX_X - $w) / 2), ((MAX_Y - $h) / 2));
    
    # Translate the canvas so padding doesn't effect our co-ordinate system.
    my $canvas = $svg->g(transform => "translate($offset)");

    draw_sheet($canvas, $imposition); # Draw

    # Create a link (a plus inside a circle) to a bigger version.
    # draw_link($canvas, $w+2, $h+2);

	#Label Y axis position;
	my $ly =  $offy + $h + 4.5;
	my $lh =  5;

	$style = $imposition->{run_style};
	# Add Lables to Image
		$svg->text( 
			x      		=> $lh + 2,
            y      		=> $ly, 
			'font-size' => 1.5,
 		)->cdata("Run Style:"); 

		$svg->text( 
			x      		=> $lh + 10,
            y      		=> $ly,
			'font-size' => 1.5,
			'font-weight' => 'bold',
 		)->cdata("$style");

		$svg->text( 
			x      		=> $lh + 15,
            y      		=> $ly,
			'font-size' => 1.5,
 		)->cdata("Width:"); 

		$svg->text( 
			x      		=> $lh + 20,
            y      		=> $ly,
			'font-size' => 1.5,
			'font-weight' => 'bold',
 		)->cdata("$w\"");

		$svg->text( 
			x      		=> $lh + 25,
            y      		=> $ly,
			'font-size' => 1.5,
 		)->cdata("Height:"); 

		$svg->text( 
			x      		=> $lh + 30,
            y      		=> $ly,
			'font-size' => 1.5,
			'font-weight' => 'bold',
 		)->cdata("$h\"");

		#Height Label of left of sheet
		$svg->text( 
			x      		=> $offx - 1.7, 
            y      		=> MAX_Y / 2 + 1.5,  
			'font-size' => 1,
			'font-weight' => 'bold',
 		)->cdata("$h\"");

		#Width label at top of sheet
		$svg->text( 
			x      		=> MAX_X / 2 - 0.75,
            y      		=>  $offy - 1,
			'font-size' => 1,
			'font-weight' => 'bold',
 		)->cdata("$w\"");


		print STDERR "HAVE IMP: ", Dumper($imposition);

		#)->cdata("$style</bold> Stock Width: $w Height $h ");
    
    return $svg->xmlify;
}

sub draw_link {
    my ($canvas, $x, $y) = @_;

    # Link to a page that displays only the imposition in a large format.
    my $link = $canvas->anchor(
        id    => 'bigger', 
        -href => '/imposition.svg?pid=1;n=0',
    );

    # Draw a plus inside a circle.
    $link->circle(cx => $x, cy => $y, r => 5/8);
    $link->line(x1 => $x-3/8, x2 => $x+3/8, y1 => $y,     y2 => $y    );
    $link->line(x1 => $x,     x2 => $x,     y1 => $y-3/8, y2 => $y+3/8);

    return $link;
}

sub draw_sheet {
    my ($canvas, $imposition) = @_;
    
    my ($w, $h)         = @{ $imposition->{paper} }{qw(width height)};
    my ($grip, $gutter) = @{ $imposition          }{qw(grip gutter)};
  
    # SHEET
    #
    # Draw the sheet dimensions with a drop shadow effect.
    $canvas->rect(
        id     => 'sheet', 
        x      => 0,  y      => 0, 
        width  => $w, height => $h + 0.5, 
        filter => 'url(#dropShadow)',
    );

    # Offset the drawing space to take grip and gutter into account.
    $canvas = $canvas->g(transform => "translate($gutter, $grip)");


    # COLOUR BAR
    #
    # If the project has a colour bar, draw it.
    if (my $y = $imposition->{colour_bar}) {
        my $colour_bar = $canvas->rect(
            id     => 'colourBar',
            fill   => 'url(#processColours)',
            width  => $w - 2 * $gutter, height => $y,
        );

        # WF fits the colour bar into the other side's grip space.
        if ($imposition->{run_style} eq 'WF') { 
            $colour_bar->setAttributes({x => 0, y => $h - $grip - $y - 1/32,});
        }
        # All other run styles fit it directly after grip.
        else {
            $colour_bar->setAttributes({x => 0, y => 0,});

            # We've decreased the availible space.
            $canvas = $canvas->g(transform => "translate(0, $y)");
        }
    }

    
    # IMPOSITION IMAGE
    # 
    # The imposition layout itself was drawn in the definition section. Here
    # we just place it centred on the sheet. TODO Rework WT/WF.

    my $x = ($w - 2*$gutter - $imposition->{tree}->size->[W]) / 2; 
    my $y = ($h - $grip     - $imposition->{tree}->size->[H]) / 2;

    # Centre the imposition on the printable page area.
    my $group = $canvas->group(transform => "translate($x, $y)");

    $group->use(-href => "#imposition");

    # Draw a centre line to indicate a WT/WF job (which are mirrored).
    if ($imposition->{run_style} eq 'WT') {

        # We're going to cheat for the sake of MV colouring. Until we actually
        # start marking nodes to determine where mirrors are occuring, we'll
        # just grab the first half of the image in a new viewport and mirror.
        my $dim = $imposition->{tree}->size->[W] / 2;

        my $mirror = $group->svg(
            width  => $dim,
            height => $imposition->{tree}->size->[H], 
            overflow => 'hidden',
            x => $dim,
            y => 0,
        );
        $mirror->use(-href => "#imposition", transform => "translate($dim, 0) scale(-1,1)");

        # Draw a vertical centre line (y-axis).
        my $centre = $w / 2 - $gutter;
        $canvas->line(
            id => 'centreline', 
            x1 => $centre,   x2 => $centre,
            y1 => - PADDING, y2 => $h + PADDING,
        );
    }
    elsif ($imposition->{run_style} eq 'WF') {
        # We're going to cheat for the sake of MV colouring. Until we actually
        # start marking nodes to determine where mirrors are occuring, we'll
        # just grab the first half of the image in a new viewport and mirror.
        my $dim = $imposition->{tree}->size->[H] / 2;

        my $mirror = $group->svg(
            width  => $imposition->{tree}->size->[W],
            height => $dim,
            overflow => 'hidden',
            x => 0,
            y => $dim,
        );
        $mirror->use(-href => "#imposition", transform => "translate(0, $dim) scale(1,-1)");

        # Draw a horizontal centre line (x-axis).
        my $centre = $h / 2 - $grip;
        $canvas->line(
            id => 'centreline', 
            x1 => - PADDING, x2 => $w + PADDING,
            y1 => $centre,   y2 => $centre,
        );
    }

    return $canvas;
}

# Add a drop shadow filter effect to the document.
sub drop_shadow {
    my ($define) = @_; # Definition section of an SVG document.
    
    my $filter = $define->filter(id => 'dropShadow', x => 0, y => 0);

    # Blur the alpha channel.
    $filter->fe(
        -type  => 'GaussianBlur', 
        in     => 'SourceAlpha', 
        result => 'blur',
        stdDeviation=> 0.5,
    );

    # Offset the blur an 1/8" to the bottom-right.
    $filter->fe(
        -type  => 'Offset', 
        in     => 'blur', 
        result => 'shadow',
        dx     => 0.125, 
        dy     => 0.125, 
    );

    # Merge the shadow under the original source graphic.
    my $merge = $filter->fe(-type  => 'Merge'); 
    $merge->fe(-type => 'MergeNode', in => 'shadow',);
    $merge->fe(-type => 'MergeNode', in => 'SourceGraphic',);
    
    return $filter;
}

# Create a simple horizontal colour bar pattern (process). TODO Read colours
# from project and create the colour bar from them (will require proposed PMS
# formula/RGB value main system enhancement).
sub colour_bar {
    my ($define) = @_; # Definition section of an SVG document.

    # Define the outer bounds of a single whitespace padded CYMK block.
    my $pattern = $define->pattern(
        id                => 'processColours', 
        patternUnits      => 'userSpaceOnUse',
        viewbox           => '0 0 1.5 2',
        x     => 0, y        => 0, 
        width => 1.5, height => 2, 
    );

    # Draw a box for each of the process colours.
    my %common = (width => 0.25, y => 0, height => '100%',);
   
    my $offset = $common{width};
    for my $colour (qw(cyan yellow magenta black)) {
        $pattern->rect(%common, x => $offset, fill => $colour);
        $offset += $common{width};
    }

    return $pattern;
}

# Generate an image for each unique image in the imposition (until gang-run
# this is only ever one).
sub images {
    my ($define,     # Definition section of an SVG document.
        $imposition,
    ) = @_;

    my ($w, $h);

    my $image = $define->group(id => 'image');
    $image->rect(x => 0,    y => 0,    width => $w, height => $h);
    $image->text(x => $w/2, y => $h/2);
    
    die Dumper $imposition;
    
    return $image;
}

# Construct the imposition layout geometry from the already defined images.
sub layout {
    my ($define, # Definition section of an SVG document.
        $tree,   # Imposition tree.
    ) = @_; 
    
    return;
}

# TODO This is a typical traversal pattern that could be added as a method on
# the tree and the specifics just passed as a function. Or it gives a list.
sub draw_node {
  my ($canvas, $node, $colour, $offset) = @_; 

  return unless $node; # Empty node.

  # Sinks (with cardinality) are images. Draw it where it stands.
  if ($node->is_sink && $node->card) {
    # TODO Predefine images and just `use` them.
    #
    # $canvas->use(-href => '#image', x => $offset->[W], y => $offset->[H]);

    my ($w, $h) = @{ $node->size };

    my ($fill, $label, $i) = $colour->();

    $label //= '';
    $i //= '';

    $canvas = $canvas->group();

    $canvas->rect(
      class  => 'image',
      x      => $offset->[W], 
      y      => $offset->[H],
      width  => $w,
      height => $h,
      #fill   => $colour->(),
      fill   => $fill,
    )->cdata($label . $i);

    #$canvas->title()->cdata('hello');

    #Shorten label to defined length
    my $l = substr($label, 0, 7);

    $canvas->text( 
      x      		=> $offset->[W] + 0.25, #Text start on left/mirrored on right. 
      y      		=> $offset->[H] + ($h/2), #Center text vertically in box.
      'font-size' => 1
    )->cdata($l);

  } else {  
  # We're a cutting group. TODO Draw a dashed cutting line.
    $canvas = $canvas->group();

    my @internal  = @$offset;   # Keep track of our draw offset.
    my $direction = $node->cut; # Traversal direction (vert. | horz.)

    # Draw each of the children keeping track of their locations.
    for my $child ($node->children) {
      draw_node($canvas, $child, $colour, \@internal);

      $internal[$direction] += $child->size()->[$direction];
    }
  }

  return $canvas;
}

# Creates an iterator that can be bumped during node traversal to properly
# colour the node based on which version (from multi-version jobs) it is.
sub slot_colours {
    my ($imp, $n) = @_;

    my $next_colour = gen_colours();
    my $c;

    # Create a flattened list of which version is in which slot. Given the
    # layout algorithm we can assume each version will only be seen once. WT/F
    # slots are halved as we draw only one side then mirror it.
    my $div = $imp->{run_style} =~ /^W[TF]$/ ? 2 : 1;
    
    my @versions = map { ($_->{label}) x ($_->{slots}/$div) } 
                      @{$imp->{layout}[$n]};


print STDERR "SLOT COLOURS", Dumper(\@versions);
    # Bump the colour generator until we get to our current layout (if we're
    # the 0th layout this will be skipped due to invalid range). Kludgy but
    # it works.
    for my $j (0 .. $n-1) {
        $next_colour->() for 1 .. @{ $imp->{layout}[$j] };
    }

    # When bumped return the colour of the next slot in the list.
    my $i = 0;
    my %colour_of;
    return sub {
        return 'white' if $i > $#versions;

        $c = $colour_of{ $versions[$i] }
          || ($colour_of{ $versions[$i] } = rgb2hex(hsv2rgb($next_colour->())));

        $i++;

        return $c, $versions[$i-1], $i-1;
    }
}


# Silly, but it's the only way I've been able to delete an element so far.
sub SVG::Element::removeSelf {
    my $self = shift;
    my $children = $self->getParentElement->getChildren;
    $children->[ $self->getChildIndex ] = undef;
}


1;
