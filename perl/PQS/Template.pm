package PQS::Template;
use strict;
use warnings;
use utf8;

use Data::Dumper;
use pdflib_pl 7.0;


my %COREFONTS = (
    'Helvetica'             => 1,
    'Helvetica-Bold'        => 1,
    'Helvetica-Oblique'     => 1,
    'Helvetica-BoldOblique' => 1,

    'Courier'               => 1,
    'Courier-Bold'          => 1,
    'Courier-Oblique'       => 1,
    'Courier-BoldOblique'   => 1,

    'Times-Roman'           => 1,
    'Times-Bold'            => 1,
    'Times-Italic'          => 1,
    'Times-BoldItalic'      => 1,

    'Symbol'                => 1,
    'ZapfDingbats'          => 1,
);



# Get the number of pages from the given PDF (filename).
sub get_pdf_info {
    my $filename = shift;
    my %info;

    my $p = PDF_new();

    PDF_set_parameter($p, 'errorpolicy' => 'exception');

    my $d = PDF_open_pdi_document($p, $filename, '');


    # The number of pages.
    $info{pages} = PDF_pcos_get_number($p, $d, 'length:pages');

    
    # Get the block information for all pages.
    my (@pages, @blocks);
    for my $i (0 .. $info{pages} - 1 ) {
        my $blocks = get_value($p, $d, 
            "pages[$i]/PieceInfo/PDFlib/Private/Blocks"
        );

        my @blocks_on_page;
        for my $block (values %$blocks) {
            push @blocks_on_page, $block;

            my $type = lc $block->{Subtype};

            $block->{page} = $i + 1;

            $block->{default} = $block->{"default$type"} || '';

            next unless $type eq 'text';

            # Get the unique list of fonts and if they're core.
            $info{fonts}{ $block->{fontname} } 
                = exists $COREFONTS{ $block->{fontname} };
        }

        $pages[$i]{blocks} = [ 
            sort {    exists $b->{Custom}{order} <=> exists $a->{Custom}{order}
                   ||        $a->{Custom}{order} <=>        $b->{Custom}{order} } @blocks_on_page
        ];
        push @blocks, @blocks_on_page;
    }
    $info{blocks} = \@blocks;
    $info{pages}  = \@pages;

    PDF_close_pdi_document($p, $d);
    PDF_delete($p);

    return \%info;
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
