package PQS::PDF;
use strict;
use warnings;

use Apache2::Const qw(:common);
use Apache2::Request;
use Apache2::ServerUtil;
use Apache2::Log ();
use Data::Dumper;
use session;

use PQS::DB;
use eprint::project qw(get_path);
use eprint::Template qw(get_datasource);

use constant LICENSE_FILE => '/etc/pdflib.license';

sub handler {
    my $r   = Apache2::Request->new(shift);
    my $dbh = PQS::DB->connect($r);

    my $pid = $r->param('pid');
       $pid =~ tr/0-9//cd;

    die "Invalid or no project ID." unless $pid;
print STDERR "PDF RENDER HANDLER \n";

    session::r($r);
    session::log($r->log);
    session::dbh($dbh);

    my $path    = get_path(undef, $dbh, $pid) . '/.template/';

	my $ds = get_datasource($dbh, $pid);
	

	my $data = $ds->selectall_hashref(q{
		SELECT * FROM data
	},'id');

	my $record = $r->param('offset') + 1 || 1;

print STDERR "HAVE RECORD: ", Dumper($data, $record);

    my $type    = $r->param('file_type') || 'png';
    my $page_no = $r->param('n') || 0;

    my $show_fields = $r->param('show_fields');

    my %field;
    $field{$_} = $r->param($_) for $r->param();



    delete $field{pid};
    delete $field{file};
    delete $field{file_type};
    delete $field{n};
    delete $field{show_fields};
	
	#%field = %{$data->{$record}};
	%field = %{$data->{$record}} if $data->{$record};


    my ($pdf, @bounds) = eval { 
        fill_page($path, 'template.pdf', $type, $page_no, \%field, $show_fields) 
    };
    if ($@) { 
        Apache2::ServerUtil->server->log_error($@);
        return SERVER_ERROR; 
    }

    if ($type eq 'pdf') {
        $r->content_type('application/pdf');
        $r->print($$pdf);
    }
    else {
        $r->content_type('image/png');
        my $image = pdf2png($pdf, {
            width      => 1222,
            dropshadow => 1,
            crop       => \@bounds,
        }, $path);
        $r->print($image);
    }
    
    $dbh->disconnect();
    return OK;
}




use constant DPI => 200; # Dots per Inch
use constant PPI => 72;  # Points per Inch

use constant PREVIEW_WIDTH => 170;

use Image::Magick;
use pdflib_pl 7.0;

{
    my %params = (
        textformat   => 'utf8', # Expected encoding from HTTP

        printarea    => 'bleed',
        centerwindow => 'true',
    );

    sub fill_file {
        my ($path, $template, $output, $data) = @_;

        my $p = PDF_new();
        PDF_set_parameter($p, licensefile => LICENSE_FILE);
        PDF_set_parameter($p, errorpolicy => 'exception');

        PDF_begin_document($p, $output, '');

        while (my ($param, $value) = each %params) {
            PDF_set_parameter($p, $param, $value);
        }

        # Open a PDF containing blocks
        my $source = PDF_open_pdi_document($p, "$path/$template", '');

        embed_fonts($p, $path);

        # We have to copy and fill each page individually.
        for my $page_no (1..PDF_pcos_get_number($p, $source, 'length:pages')) {
            
            my $page = copy_page($p, $source, $page_no, 1);

            # Fill the blocks with the given data.
            fill_blocks($p, $path, $page, $page_no - 1, $data);
 
            PDF_end_page_ext($p, '');
            PDF_close_pdi_page($p, $page);
        }

        PDF_end_document($p, '');
        PDF_close_pdi_document($p, $source);

        PDF_delete($p);

        return 1;
    }

    sub fill {
        my ($template, $data) = @_;

        my $p = PDF_new();
        PDF_set_parameter($p, licensefile => LICENSE_FILE);
        PDF_set_parameter($p, errorpolicy => 'exception');

        PDF_begin_document($p, '', '');

        while (my ($param, $value) = each %params) {
            PDF_set_parameter($p, $param, $value);
        }

        # Open a PDF containing blocks
        my $source = PDF_open_pdi_document($p, $template, '');

        embed_fonts($p, $template);

        # We have to copy and fill each page individually.
        for my $page_no (1..PDF_pcos_get_number($p, $source, 'length:pages')) {
            
            my $page = copy_page($p, $source, $page_no, 1);

            # Fill the blocks with the given data.
            fill_blocks($p, $page, $page_no - 1, $data);
 
            PDF_end_page_ext($p, '');
            PDF_close_pdi_page($p, $page);
        }

        PDF_end_document($p, '');
        PDF_close_pdi_document($p, $source);

        my $pdf = PDF_get_buffer($p);
        PDF_delete($p);

        return \$pdf;
    }
}

{
    my %options = (
#        inmemory  => 'true',
#        linearize => 'true',
#        optimize  => 'true',

#        compatibility => 1.5,

        # PERMISSIONS
        #
        # Document permissions: We'll use a fairly restrictive set as we don't
        # want users taking the preview and using it somewhere else.
        masterpassword => '352asna32',
        #permissions    => '{noprint nohiresprint nomodify nocopy noforms plainmetadata}',
        #permissions    => '{noprint nomodify nocopy}',

        # TODO For previews add a JS action on 'willprint' to tell the user we've
        # restricted them to low-res and why.
    );

    my %params = (
        textformat   => 'utf8', # Expected encoding from HTTP

        viewarea     => 'trim', # Preview only the finished product
        printarea    => 'bleed',
        centerwindow => 'true',
    );

    my $optlist = join q{ }, map { "$_=$options{$_}" } keys %options;

    sub fill_page {
        my ($path, $filename, $file_type, $page_no, $data, $show_fields) = @_;

        my $p = PDF_new();
        PDF_set_parameter($p, licensefile => LICENSE_FILE);
        PDF_set_parameter($p, errorpolicy => 'exception');

        # The PNG generation needs full permissions, so only limit for PDF.
        my $optlist = ($file_type eq 'pdf') ? $optlist : '';

        PDF_begin_document($p, '', $optlist);

        while (my ($param, $value) = each %params) {
            PDF_set_parameter($p, $param, $value);
        }

        # Open a PDF containing blocks.
        my $source = PDF_open_pdi_document($p, "$path/$filename", '');

        # Open the requested page.
        my $page = copy_page($p, $source, $page_no + 1, 1);

        embed_fonts($p, $path);

        # Fill the blocks with the given data.
        if (!$show_fields) { fill_blocks($p, $path, $page, $page_no, $data); }
        else               { show_blocks($p, $path, $page, $page_no, $data); } 

        # We need the crop box information for rendering the preview. It's easiest
        # to grab it here and pass it along for now.
        my @trim_box = get_bounds($p, $source, "pages[$page_no]/MediaBox");
            # Should be trim box.

        PDF_end_page_ext($p, '');
        PDF_close_pdi_page($p, $page);

        PDF_end_document($p, '');
        PDF_close_pdi_document($p, $source);

        my $pdf = PDF_get_buffer($p);
        PDF_delete($p);

        return \$pdf, @trim_box; # Return the object as we need pieces of it later.
    }
}

# Taking the pdflib context, page to process, and hash ref containing the
# block name => value pairs. Fill the blocks on the given page.
{
    my $options = q|
        fontsize=6
        fontname=Helvetica-Bold
        encoding=unicode
        bordercolor={gray 0.5}
        linewidth=0.1
        verticalalign=top
        textflow=true
        backgroundcolor={gray 0.8}
    |;
    
    sub show_blocks {
        my ($p, $path, $page, $page_no, $data) = @_;
        
        PDF_set_parameter($p, 'errorpolicy' => 'return');

        my $blocks = get_value($p, $page, 
            "pages[$page_no]/PieceInfo/PDFlib/Private/Blocks"
        );

print STDERR "PDF SHOW BLOCKS \n", Dumper($blocks);
		$blocks->{Line_1}{Rect}[0] = '100';
		$blocks->{Line_1}{Rect}[1] = '50';
print STDERR "PDF SHOW BLOCKS \n", Dumper($blocks->{Line_1});
        my @order = sort {
              ($blocks->{$a}{'z-axis'} || 0) <=> ($blocks->{$b}{'z-axis'} || 0)
            ||             $blocks->{$a}{ID} <=> $blocks->{$b}{ID}
        } keys %$blocks;

        for my $name (@order) {
			my $block_options = $options;
            my $block = $blocks->{$name};
print STDERR "SHOW : $name \n\n";

#			if ( $name eq 'Line_1') {
#				print STDERR "OPTIONS: $block_options \n";
#					$block_options .= ' refpoint={185 154} ';
#				print STDERR "OPTIONS: $block_options \n";
#    
#			}

            if ($block->{Subtype} eq 'Text') {
                PDF_fill_textblock($p, $page, $name, $name, $block_options);
            }
            else {
                image_marker($p, $page, @{ $block->{Rect} });
            }
        }

        PDF_set_parameter($p, 'errorpolicy' => 'exception');

        return 1; # TODO Return the error message if any.
    }
}


# Draws a filled in rectange with diagonal lines through based on the x,y
# co-ordinates passed. Used to indicate where an image is.
sub image_marker {
    my ($p, $page, @bounds) = @_;

    # The sorting is needed as PDFlib blocks don't store their points based on
    # the mouse movement that defined them, not absolute co-ordinates.
    my ($x1, $x2) = sort { $a <=> $b } @bounds[0,2];
    my ($y1, $y2) = sort { $a <=> $b } @bounds[1,3];

    PDF_setcolor($p, 'fill',   'gray', 0.8, 0, 0, 0);
    PDF_setcolor($p, 'stroke', 'gray', 0.5, 0, 0, 0);

    # Fill over the area the image will be.
    PDF_rect($p, $x1, $y1, $x2 - $x1, $y2 - $y1);
    PDF_fill($p);

    # Create the diagonal lines associated generally associated with image
    # placement.
    PDF_moveto($p, $x1, $y1);
    PDF_lineto($p, $x2, $y2);

    PDF_moveto($p, $x1, $y2);
    PDF_lineto($p, $x2, $y1);

    # Draw a border around the area.
    PDF_rect($p, $x1, $y1, $x2 - $x1, $y2 - $y1);
    PDF_stroke($p);

    # TODO Restore previous graphics state.
    return 1;
}



# Taking the pdflib context, page to process, and hash ref containing the
# block name => value pairs. Fill the blocks on the given page.
{
    my %fill = (
        text  => sub { PDF_fill_textblock(@_)},
        image => sub {
            my ($p, $page, $block_name, $filename) = @_;

            my $image = PDF_load_image($p, 'auto', $filename, 'honoriccprofile=true');

            return PDF_fill_imageblock($p, $page, $block_name, $image, '');
        },
        # TODO use defaultpdfpage option for loaded PDFs
        pdf   => sub {
            my ($p, $page, $block_name, $filename) = @_;

            my $doc     = PDF_open_pdi_document($p, $filename, '');
            my $xobject = PDF_open_pdi_page($p, $doc, 1, '');

            my $rv = PDF_fill_pdfblock($p, $page, $block_name, $xobject, '');

            PDF_close_pdi_document($p, $doc);

            return $rv;
        },
    );

    sub fill_blocks {

        my ($p, $path, $page, $page_no, $data) = @_;


        PDF_set_parameter($p, 'SearchPath' => $path);

        my $blocks = get_value($p, $page, 
            "pages[$page_no]/PieceInfo/PDFlib/Private/Blocks"
        );


        PDF_set_parameter($p, 'errorpolicy' => 'return');

        my @order = sort {
              ($blocks->{$a}{'z-axis'} || 0) <=> ($blocks->{$b}{'z-axis'} || 0)
            ||             $blocks->{$a}{Custom}{order} <=> $blocks->{$b}{Custom}{order}
        } keys %$blocks;

print STDERR "START FILL BLOCKS: ", Dumper($blocks);

		fill_data(\@order, $blocks, $p, $page, $data, $path, 'top');

        @order = sort {
              ($blocks->{$b}{'z-axis'} || 0) <=> ($blocks->{$a}{'z-axis'} || 0)
            ||             $blocks->{$b}{Custom}{order} <=> $blocks->{$a}{Custom}{order}
        } keys %$blocks;

		fill_data(\@order, $blocks, $p, $page, $data, $path, 'bottom');


        PDF_set_parameter($p, 'errorpolicy' => 'exception');

        return 1; # TODO Return the error message if any.
    }

	sub fill_data {
		my ($order, $blocks, $p, $page, $data, $path, $align) = @_;
		my %offset;
		my $lb;

		my $options = q|
			encoding=unicode
		|;

        for my $name (@{$order}) {

			my $block_options = $options;
            my $block = $blocks->{$name};
            my $type  = lc $block->{Subtype};
			
			

            # Fill the block with the user input if there, otherwise the default.
            my $value = exists $data->{$name}                               ? $data->{$name} 
                      : $type eq 'text' && defined $block->{"default$type"} ? $block->{"default$type"}
                      :                                                       '';

			my $group = $block->{Custom}{group};


print STDERR "******** START BLOCK: $name LB: $lb ***********************\n";
			if ( $group ) {
				next unless $group =~ /$align/;

				my $x = $align eq 'top' ? 3 : 1;
				$offset{$group} += $block->{Rect}[$x] - $lb->{Rect}[$x] if $lb;

				print STDERR "PDF FILL OFFSET: $x \n", Dumper(\%offset);

			}

print STDERR "PDF FILL BLOCKS: $name ", Dumper($block->{Rect}, $group);

			if ( ! $value ) {
				$lb = $block;
            			next;
			} else { 
				$lb = undef;
			}

			my $x = $block->{Rect}[0];
			my $y = $block->{Rect}[1];

			$y = $block->{Rect}[1] - $offset{$group} if $group && $offset{$group};

			$block_options .= "refpoint={$x $y}";

print STDERR "FILLING PDF BLOCK: $name - $value X: $x Y: $y \n\n";
            PDF_set_parameter($p, 'SearchPath' => "$path/assets/$name") 
                if $type ne 'text';

            $fill{$type}->($p, $page, $name, $value, $block_options);
print STDERR "DONE FILL: $name - $value Type: $type : $block_options \n\n";
        }
	}
}

sub embed_fonts {
    my ($p, $path) = @_;
	PDF_set_parameter($p, 'SearchPath', Apache2::RequestUtil->request->document_root . '/site_specific/fonts');
	PDF_set_parameter($p, 'FontOutline', 'Frutiger 57Cn=Frutiger57Cn.otf');

	PDF_load_font($p, 'Frutiger 57Cn', 'unicode', 'embedding');

    return 1;
}

sub copy_page {
    my ($p, $src, $n, $visible) = @_;

    # Open the existing page.
    my $page = PDF_open_pdi_page($p, $src, $n, '');

    # Retrieve the media dimensions and all the other boxes.
    my ($w, $h, $boxes) = page_info($p, $src, $n);

    # Stringify the box co-ordinates in the format needed 'foo={ 0 0 0 0 }'.
    my $dims = join ' ', map  { "${_}box={" . join(' ', @{$boxes->{$_}}) . "}" }
                         grep { defined $boxes->{$_}                           }
                              qw(art crop trim bleed);
 
    PDF_begin_page_ext($p, $w, $h, ''); #$dims); # Create a new page.

    # The visible flag determines if the source artwork or just the template
    # data will be in the copied page.
    PDF_fit_pdi_page($p, $page, 0, 0, ($visible ? '' : 'blind'));

    return $page;
}

# Grab the width, height, and all the various content boxes of the passed page
# in the document.
sub page_info {
    my ($p, $doc, $n) = @_;

    $n--; # Page arrays are 0 indexed.

    my ($w, $h) 
        = map {PDF_pcos_get_number($p, $doc, "pages[$n]/$_")} qw(width height);

    my %boxes;
    BOX:
    for my $type (qw(art crop trim bleed media)) {
        my $name = ucfirst "${type}Box";

        my @bounds = get_bounds($p, $doc, "pages[$n]/$name")
            or next BOX;

        $boxes{$type} = \@bounds;
    }

    return $w, $h, \%boxes;
}

# Get a rectangular bounding array from the given path.
sub get_bounds {
    my ($p, $doc, $path) = @_;
    
    # A bounding box must a four element array.
    return unless PDF_pcos_get_string($p, $doc, "type:$path") eq 'array'
               && PDF_pcos_get_number($p, $doc, "length:$path") == 4;

    return map { PDF_pcos_get_number($p, $doc, $path."[$_]") } 0..3;
}


sub pdf2png {
    my ($pdf, $opt) = @_;

my $x = time();

print STDERR "START: $x \n";
    # Set the defaults.
    my %default = (
        width => PREVIEW_WIDTH,
        dropshadow => 0,
        crop => undef,
    );

    $opt = {} unless ref $opt eq 'HASH';
    for (keys %default) {
        $opt->{$_} = $default{$_} unless exists $opt->{$_};
    }

my $x = time();
print STDERR "START 1: $x \n";
    # Create a PDF import canvas with a 300DPI screen (larger imports provide
    # better font kerning and anti-aliasing when later downsampled).
    my $image = Image::Magick->new(
        magick => 'pdf', 
        density => DPI,
        orientation => 'bottom-left', # PS/PDF origin
        antialias => 0, 
        fuzz => 0,
    );

my $x = time();
print STDERR "START 2: $x \n";
    # TODO Rip ICC profile out of PDF for use in colourspace conversion.

    # Ghostscript (used by Image::Magick to process the PDF) needs to know
    # where the core PDF fonts are.
    $ENV{GS_LIB} = '/usr/share/fonts/type1/gsfonts/';

    my $rv = $image->BlobToImage($$pdf);
    die $rv if $rv;


my $x = time();
print STDERR "START 3: $x \n";

    # Change from a four colour separation (if the PDF is process or spot,
    # otherwise it's a no-op) to RGB. This MUST be done before resampling for
    # acceptable text anti-aliasing at small point sizes.
    $image->set(
        colorspace => 'RGB',
        magick     => 'png',    # Conver to PNG
        support    => 0.2,
        depth      => 8,        # Low bit rate for preview.
    );

my $x = time();
print STDERR "START 4: $x \n";

    return $image->ImageToBlob; # Return as binary data.
}


# Given dimensions create a dropshadow effect (antialiases to a white
# background and a mask for those same dimensions (for compositing).
sub create_dropshadow {
    my ($w, $h) = @_;

    # Create a dropshadow effect.
    my $dropshadow = Image::Magick->new(
        colorspace => 'RGB',
        magick     => 'png',    # Conver to PNG
        support    => 0.2,
        depth      => 8,        # Low bit rate for preview.
        size       => join ('x', $w + 15, $h + 15),
    );
    $dropshadow->Read('xc:white');

    $dropshadow->Draw(
        antialias => 'true',
        stroke    => 'none',
        fill      => '#707070',
        primitive => 'rectangle', 
        points    => "5 5 $w $h",
    );

    # Not as nice as a high gaussian but MUCH, MUCH faster (IM 6.2-3.x).
    $dropshadow->Blur(radius => 10, sigma => 3);
    
    # Mask off the area of the actual image.
    my $mask = Image::Magick->new(
        depth => 2,
        size  => join ('x', $w + 15, $h + 15),
    );
    $mask->Read('xc:white');
    $mask->Draw(
        stroke    => 'none',
        fill      => 'black',
        primitive => 'rectangle', 
        points    => "0 0 $w $h",
    );

    return ($dropshadow, $mask);
}



# TODO store xref table (hash) in the object and do an ID lookup in the
# initial value lookup. ie. cache what we've already looked up so we don't
# have to on any subsequent call. TODO weaken all references other than the
# xref table one it's cached?
{
    our %xref;
    my $_value; # Predeclar sub routine.

    my %PDF_TYPE = (
        null    => sub { return undef },
        boolean => \&PDF_pcos_get_number, # 0 or 1
        number  => \&PDF_pcos_get_number,
        name    => \&PDF_pcos_get_string,
        string  => \&PDF_pcos_get_string,
        
        # Arrays are heterogeneous so we'll call get_value for each element.
        array => sub {
            my ($p, $doc, $path) = @_;

            my $id = PDF_pcos_get_number($p, $doc, "pcosid:$path");
            return $xref{$id} if exists $xref{$id};

            $xref{$id} = []; # Cyclic paths can reference this.

            push @{ $xref{$id} }, $_value->($p, $doc, $path."[$_]")
                for 0 .. PDF_pcos_get_number($p, $doc, "length:$path") - 1;

            return $xref{$id};
        },

        # Dictionaries are treated as an array of [Name, value] pairs (Name is
        # a PDF type).
        dict => sub {
            my ($p, $doc, $path) = @_;

            my $id = PDF_pcos_get_number($p, $doc, "pcosid:$path");
            return $xref{$id} if exists $xref{$id};

            $xref{$id} = {}; # Cyclic paths can reference this.

            for my $i (0..(PDF_pcos_get_number($p, $doc, "length:$path") - 1)) {
                my $key  = PDF_pcos_get_string($p, $doc, $path."[$i].key");
                $xref{$id}{$key} = $_value->($p, $doc, "$path/$key");
            }

            return $xref{$id};
        },

        # Returns the unfiltered (all filters removed) stream data (none of
        # the stream dictionaries keys and filter info are preserved).
        # stream  => sub {
        #     my ($p, $doc, $path) = @_;
        #     PDF_pcos_get_stream($p, $doc, '', $path);
        # },

        # TODO fstreams are currently NOT handled.
    );

    # Get a Perl mapping of the PDF value; using the type mapping table to
    # properly handle the type.
    $_value = sub {
        my ($p, $doc, $path) = @_;

        my $type = PDF_pcos_get_string($p, $doc, "type:$path");

        return undef unless exists $PDF_TYPE{$type};

        return $PDF_TYPE{$type}->($p, $doc, $path);
    };

    sub get_value {
        local %xref;
        return $_value->(@_);
    }
}



1;
