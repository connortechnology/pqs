# DESCRIPTION
#
#   Displays the graph of the imposition tree.
#
# TODO: Make this a method of our tree instead of an external function.
#
# TODO: Generalize or use some other tree walking algorithm so both can use
# the same one.
#
package PQS::Image::Tree;
use strict;
use warnings;

use Apache2::Const qw(:common :http);
use Apache2::Request ();
use Apache2::Log       ();
use Compress::LZF q(sthaw);
use Compress::Zlib ();
use Data::Dumper;
use MIME::Base64;
use Storable qw(thaw);
use Image::Magick;
use GraphViz;
use session;

use PQS::DB;
use PQS::Imposition::Node;

use base qw(Exporter);
our @EXPORT_OK = qw(graph);

use constant PREVIEW_WIDTH => 190; # Pixels

use constant SETTINGS => (
        node => { 
            fontname  => 'Verdana',
            shape     => 'box',
            style     => 'filled, bold',
            fillcolor => 'white',
            fontsize  => 48,
        },
        edge => {
            fontname  => 'Arial',
            style     => 'bold',
            fontsize  => 24,
            arrowsize => 3,
        },
        overlap => 'false',
        width  => 8,
        height => 8,
        ratio => 'fill',
        # concentrate => 1, # Turn back on when we colour edges.
);


# Grabs the imposition information from the DB for the passed and generates an
# image of it on-the-fly.
sub handler {
    my $r = Apache2::Request->new(shift);

    # Service ID (will be checked later for existance).
    my $sid = $r->param('sid'); 
       $sid =~ tr/0-9//cd;
    return NOT_FOUND unless $sid;

    session::r($r);
    session::log($r->log);

    my $is_preview = $r->param('preview');

    # Retrieve the imposition "object" (heh) from the database.
    my $imp = imposition($r, $sid);

    # If we can't find the service, it's not the correct type of service, or
    # it doesn't have the object we expected; we'll say we can't find anything.
    return NOT_FOUND 
        unless defined $imp 
           && ref $imp eq 'PQS::Imposition::Node';

    # Generate the imposition image.
    my $image = graph($imp)->as_png;

    # If we're generating a preview pull in image magick to resize the image.
    if ($is_preview) {
        my $img = Image::Magick->new(magick => 'png');
        
        $img->BlobToImage($image);
        
        my $ratio = $img->get('width') / PREVIEW_WIDTH;

        $img->Scale(map { $_ => $img->get($_) / $ratio } qw(width height));

        $image = $img->ImageToBlob();
    }

    # Set the file size, modification time, etc. headers for the client.
    $r->content_type('image/png');
    $r->headers_out->{'Content-Length'} = length $image;
    $r->headers_out->{'Content-Disposition'} = qq{inline; filename="tree-$sid.png"};

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
    session::dbh($dbh);
    my $frozen = $dbh->selectrow_array(q{
        SELECT strvalue FROM tbl_service_specifications
        WHERE strname = 'imp' AND lngserviceindex = ?
    }, {}, $sid);
    return undef unless $frozen;

    my $imposition = sthaw(decode_base64($frozen));

    # Due to some persistant interpretter/mod_perl issue we need to 'prime'
    # the package before we can retrieve into it.
    my $tmp = PQS::Imposition::Node->new(cut => 0, size => [1,1]);
    undef $tmp;
   
    $imposition->{tree} = thaw($imposition->{tree}); # Frozen object.

    return $imposition->{tree};
}


# A simple tree walk to feed Graphviz the nodes and edges. Returns a Graphviz
# object.
sub graph {
    my $tree = shift;
    my $g    = GraphViz->new(SETTINGS);

    my ($i, $depth) = (0,0);
    
    # Walk the tree adding nodes and edges as they're found.
    my $walk_tree;
    $walk_tree = sub {
        my ($node) = @_;

        my $box        = $node->size;
        my ($w, $h)    = @$box;
        my $id         = $i++;

        # Generate the label and reflect the node size.
        my %attr = (
            label  => "$w&#215;$h",
            depth  => $depth,
            width  => $w,
            height => $h
        );
        
        # Distinguish between images and choice nodes.
        $attr{fillcolor} = '#bdbded'
            if $node->is_sink && $node->card;
        
        CHILD:
        for my $child ( $node->children ) {
            $depth++;
            
            my $cid = $walk_tree->($child);

            $depth--;

            # As we're representing choices we only need one edge per node pair.
            $g->add_edge($id => $cid);
        }

        $g->add_node($id, %attr);
        
        return $id;
    };

    $walk_tree->($tree);

    return $g;
}

1;
