package PQS::Imposition;
use strict;
use warnings;

use Carp;
use Data::Dumper;
use List::Util qw(sum max min);
use Scalar::Util qw(weaken);
use Cache::FileCache;

use eprint::Config;
use Object::InsideOut;          # Class heirarchy.
use PQS::Imposition::Constants;
use PQS::Imposition::Node;

no warnings qw(uninitialized);

# TEMPORARY!
use constant BOUNDS => [
    eprint::Config->get(Imposition => 'bound_x'),
    eprint::Config->get(Imposition => 'bound_y'),
];

my @project :Field(Name => 'project');
my @lookup  :Field(Name => 'lookup');

# TEMP: Replace these package variables with private object variables.
our (@images, $cache);
our $round_to;

use constant ID    => 2; # REMOVE - When image is an object.
use constant BLEED => 3; # REMOVE
use constant GRAIN => 4; # REMOVE

use constant DEBUG => 1;

sub get_precision {
  return map {
    # Assume a valid number, so only 1 decimal.
    my $decimal_pos = index($_, '.');
    ($decimal_pos == -1 ? 0 : (length($_) - $decimal_pos)-1);
  } @_;
}

sub _init :Init {
  my ($self, $args_ref) = @_;

  # TODO Use the :InitArgs construct and do some type checking and validation on these arguements.
  # Save a reference to the project for later use.
  $self->set(\@project, $args_ref->{project});

  my $project = $args_ref->{project};

  # Our imposition code wasn't in an object before, we'll wrap it in
  # it's own little closure type environment until we have time to refactor it.
  local @images = ();
  local $cache  = {};

  # Screen items surfaces are the size they are.
  if ($project->{type} eq 'ScreenItem' || $project->{type} eq 'Envelopes') {
    $lookup[$$self] = [ PQS::Imposition::Node->new(
        size  => [@$project{qw(width height)}],
        image => 1,
        bleed => [0,0,0,0],
        grain => undef,
      ) ];
    return $self;
  }

  my $start_time = $args_ref->{start};

  # Our file cache (shared between children).
  my $result_cache = Cache::FileCache->new({ namespace => 'imposition' }) or die "Couldn't initialise cache: $!";

  my $max_precision = List::Util::max(get_precision(@$project{qw(width height trim)}));
  $max_precision = 4 if $max_precision < 4;
  $round_to = 1/(10**$max_precision);
  # A kludge to handle multi-page books the way they were previously. We do
  # two rounds of imposition, one for each grain direction.
  my $is_special = $project->{is_multipage} && (!defined $project->{grain} or $project->{grain} eq '');
  my $grain = $is_special ? 0 : $project->{grain};
  $openprint::log->debug("START PQS IMPOSE 1: ".(Time::HiRes::time() - $start_time)." max precision $max_precision grain:".(defined $grain ? $grain : undef)) if DEBUG;

  # Incoming grain, can be undef == No preference, 'Mixed', 'Unmixed', 0=>Width, 1=>Heihgt
  #imposition grain has to be either Mixed, 0 or 1
  # width x height - bleed size - trim size - multipage - bleed sides
  my $key = sprintf("%06.${max_precision}fx%06.${max_precision}f-%4.${max_precision}f-%d-%s-%s",
    @$project{qw(width height trim)},
    $project->{is_multipage} ? 1 : 0,
    join(',', @{ $project->{bleed} }),
    $grain,
  );

  my $have_cache = $result_cache->get($key);

  $openprint::log->debug("START PQS IMPOSE 2: ".(Time::HiRes::time() - $start_time)) if DEBUG;
  # Retrieve cached results if we've seen this before.
  if ($have_cache) {
    $lookup[$$self] = $have_cache;
    #return $self;
  }

  my @valid;
  IMPOSITION: {
    @images = $self->images($grain);

    $openprint::log->debug("START PQS IMPOSE 3: ".(Time::HiRes::time() - $start_time) . ' '.Data::Dumper::Dumper(\@images)) if DEBUG;

    my $trees = fill_box(BOUNDS); # Impose.

    $openprint::log->debug("START PQS IMPOSE 4: ".(Time::HiRes::time() - $start_time). ' '.Data::Dumper::Dumper($trees)) if DEBUG;

    # TEMP: The sub-node generation is currently generating impositions with
    # spacing and sub-optimal results. We'll do a simple post-processing prune
    # of the cache to remove the worst of these.
    push @valid, post_process($trees, $cache);

    $openprint::log->debug("START PQS IMPOSE 5: ".(Time::HiRes::time() - $start_time)) if DEBUG;
    # If we're multipage, try the rotated image appending any results.
    if ($is_special && $grain != 1 ) {
      $grain = 1;
      $cache = {};
      redo IMPOSITION;
    }
  } # end IMPOSITION

  $openprint::log->debug("START PQS IMPOSE 6: ".(Time::HiRes::time() - $start_time)) if DEBUG;

  $lookup[$$self] = \@valid;           # Impositions
  $result_cache->set($key => \@valid); # Store to cache.

  $openprint::log->debug("START PQS IMPOSE 7: ".(Time::HiRes::time() - $start_time)) if DEBUG;
  return $self;
}

# Generate the image information from the project. TODO The images would
# probably be better suited as objects.
sub images { # :Private
  my ($self, $grain)  = @_;

  my $project = $project[$$self];
  my ($w, $h) = @$project{qw(width height)}; # Image (w x h)
  my @bleed   = @{ $project->{bleed} };

  if(!( $w >= 0.25 && $h >= 0.25)) {
    print STDERR "Invalid sizes ($w x $h)";
    return ();
  }

  # Drop dead simple (and wrong) bindery trim/grind-off space. Basically we
  # just expand any bleeds there might be to at least the trim size.
  # TODO Really it should be usable (for gutters, etc.) non-printing space.
  my $trim = $project->{trim};
  @bleed   = map { max($trim, $_) } @bleed;

  # Add the bleeds to the appropriate image sides.
  $w += $bleed[L] + $bleed[R];
  $h += $bleed[T] + $bleed[B];

  my @images;

  if (($grain eq '') || ($grain == 0) || ($grain eq 'Mixed')) {
    $openprint::log->debug("Grain $grain so adding vertical");
    push @images, [ $w, $h, 0, \@bleed, 0 ];
  }

  # If the grain direction isn't constrained and we're not a multipage
  # project (not handled yet) we can try the rotated version as well. TODO
  # The image format is an array of stuff, make it an object or something.
  if (($grain eq '') || $grain == 1 || ($grain eq 'Mixed')) {
    $openprint::log->debug("Grain $grain so adding horizcal");
    push @images, [ $h, $w, 0, [ @bleed[R, B, L, T] ], 1 ];
  }

  return @images;
} # end sub images

# Add an image to the imposition (invalidates the cache and calculations).
# sub add_image { }

sub best_fit {
  my ($self, $press, $style, $sheet) = @_;
  my $project = $project[$$self];

  #print STDERR "START BEST FIT: ", Dumper($press, $style, $sheet);

  # Only one way to print a screen item.
  return ($style, $lookup[$$self][0]) if $project->{type} eq 'ScreenItem';

  #print STDERR "SETP BEST FIT: $press->{name}, $style \n";

  my @possible;
  my $override_runstyle = $project->{override}{runstyle};

  # While work & turn/flop are identical in how they run on the press,
  # they aren't in terms of imposition. If we haven't been overriden expand them
  # out now. TODO Move this section into Print::Impose.
  my @styles = $style ne 'Wx' ? ($style) : $override_runstyle ? ($override_runstyle) : qw(WT WF);

  #print STDERR "SETP BEST FIT: $press->{name}, $style \n";
  # Digital presses with inline bindery are currently overriden to HAVE to
  # use that bindery, so they must be 1-up impositions (a four page spread
  # for stitching is one 1-up). Non-cuttable paper (like multi-part premade
  # forms) also require 1-up impositions no matter the substrate size.
  my $is_one_up =  ( $press->{type} eq 'digital' && grep { $_ eq $project->{bind_type} } @{ $press->{services} } ) || ( !$sheet->{cut_paper} );

  #print STDERR "SETP BEST FIT: $press->{name}, $style \n";
  #This is a Safeway only rule	
  # Allow this one type of project to print multi out ( 17x5.5)
  # and variants that are slightly smaller.
  #	if (    ($project->{width} <= 5.5 or $project->{height} <= 5.5)
  #		and ($project->{width} == 17  or $project->{height} == 17 ) ) {
  #		#keep current is_on_up setting.
  #	} else { 
  #		$is_one_up = 1 if $project->{width} * $project->{height} > 93 && $press->{type} eq 'digital';
  #	}

  #print STDERR "CHECK IMPOSITION: ISONEUP: $is_one_up \n";

  # TODO normalize this during printing page input validation.
  my $grain = $project->{grain} eq '' ? undef : $project->{grain} ? 1 : 0;
  #print STDERR "SETP BEST FIT: $press->{name}, $style \n";
  for my $style (@styles) {

    # Inline bindery can not be W/TF if one up.
    next if $style =~ /^W[TF]$/ && ( $is_one_up || $project->{type} eq 'Envelopes' );

    # Envelopes imposition is exactly the size of the envelope
    # (currently). So just return that with the style (SW/PF).
    return ($style, $lookup[$$self][0]) if $project->{type} eq 'Envelopes';

    my $rotated  = 0;
    my @dims     = qw(width height);

    BEST_FIT:
    {
      my ($w, $h) = @$sheet{@dims}; # Imagable area.

      #print STDERR "STEP BEST FIT: $w x $h \n";
      # TODO move to substrate section (substrate section needs to pass
      # both rotated and unrotated sheets per press). Hrmm... though if
      # we do we lose the optimization where we determine the best
      # rotation for a single press sheet (as all other variables can be
      # considered equal).
      if (!sheet_fits_press(@$sheet{@dims}, $press) && !$rotated) {
        @dims = reverse @dims;
        $rotated = 1;

        redo BEST_FIT;
      }

      unless ($project->{override}{margin}) {

        my $cb = $project->{colour_bar};
        #$cb = min($cb, $press->{colour_bar_size}) if $press->{type} eq 'digital' && defined $press->{colour_bar_size};

        $cb = 0 if  $press->{type} eq 'digital';

        # A flop (WF) trades head for tail, so we need to double up
        # the grip. We can sneak (hopefully all of) the colour bar
        # into the grip for the other side. Other run styles need the
        # grip and colour bar at the head.
        if ($style eq 'WF') { $h -= 2 * max($press->{grip} , $cb) }
        else                { $h -=         $press->{grip} + $cb  }

        #print STDERR "STEP BEST FIT WF: $w x $h,  GRIP: $press->{grip}, CB: $cb \n";
        # Most presses can't print to the absolute edge of the sheet.
        # A gutter applies to the two edges perpendicular to the feed.
        $w -= $press->{gutter} if exists $press->{gutter};

        #print STDERR "STEP BEST FIT GUTTER: $w x $h \n";

        #The available space is the smallest of maximum image area and the space available after the gutter and grab space
        $w = min($w, $press->{maximum_image_area_width});

        $h = min($h, $press->{maximum_image_area_length} - $cb);

        #print STDERR "STEP BEST FIT IMAGE AREA: $w x $h \n";
      }

      #print STDERR "STEP BEST FIT: $w x $h \n";
      $w /= 2 if $style eq 'WT'; # Mirrored edge to edge.
      $h /= 2 if $style eq 'WF'; # Mirrored head to tail.

      # TODO If we're running perfecting and the sheet isn't stiff enough to
      # hold it's form during a flip, we may need one or more rollers to guide
      # it. As the ink is wet the roller can't be over printable area.
      if (!$sheet->{perfecting} and $style eq 'PF') {
        # We'll need to look at the cutting tree as we'll need vertical cuts and
        # more than one child at the first level so we can guaruntee the roller a
        # clear path.

        # If the roller can't be near the middle of the sheet, we can use multiple
        # rollers spaced somewhat evenly across the sheet.
      }

      #print STDERR "TIME TO FIND FIT: $w x $h \n";
      foreach my $node ( $self->find_fit($w, $h, $grain, $rotated, $is_one_up) ) {
        #$openprint::log->debug("Find fit from $w x $h grain $grain rotated $rotated ".$node->card);
        $node = $node->work_and(TURN) if $node && $style eq 'WT';
        $node = $node->work_and(FLOP) if $node && $style eq 'WF';

        #print STDERR "STEP BEST FIT: $w x $h \n";
        #print STDERR "ADD NODE TO POSSIBLE LIST \n";
        push @possible, [ $style, $node, $rotated ] if $node->card;
      }

      # Try the rotated version to see if feeding that way is better.
      if (!$rotated) {
        @dims = reverse @dims;
        $rotated = 1;

        redo BEST_FIT if sheet_fits_press(@$sheet{@dims}, $press);
      }
    }
  }

  my $override_imposition = $project->{override}{imposition};
  if ($override_imposition) {
    @possible = grep { $_->[1]->card == $override_imposition } @possible;
  }

  # We want the most images that will fit on this sheet. TODO Right now we
  # blindly prefer WT over WF when really it should be the cutting
  # complexity and bindery options that have first say.

  #Swapped Sort order, card is top of list, then check wt/wf
  #reversed back to the what it was in older versions.
  my @best = (
    sort { $b->[1]->card <=> $a->[1]->card }
    sort { $b->[0]       cmp $a->[0]       } # Prefere WT over WF
    grep { $_->[1] }
    @possible
  );

  #no warnings qw(uninitialized);
  #print STDERR "SETP BEST FIT: $press->{name}, $style POSSIBLE: ", Dumper(@possible);

  # TEMP: Simple call for now.
  return @best ? (shift @best) : ();
}

# Determine if a given sheet size will fit on the given press.
sub sheet_fits_press {
  my ($w, $h, $press) = @_;

  return $w <= $press->{maximum_sheet_width}
  && $h <= $press->{maximum_sheet_length}
  && $w >= $press->{minimum_sheet_width}
  && $h >= $press->{minimum_sheet_length};
}


# Determines the imposition with the highest cardinality that can fit in the
# given bounds. TODO Currently just a naïve grep/reduce over entire list.
sub find_fit {
  my ($self, $w, $h, $grain, $rotation, $is_one_up) = @_;
  # If the sheet is rotated the grain we're looking for is opposite to the
  # constraint (as width and height of the sheet are reversed).
  $rotation = $grain ^ $rotation if defined $grain;

  # TODO Gang-run related stuff.

  #print STDERR "FIND FIT:  $w, $h, $grain, $rotation, $is_one_up \n";

  # TODO Handle 1-up earlier so we don't have to do as much work.
  my @nodes = sort {
    $b->card      <=> $a->card        # Max cardinality
  }
  grep {    
    #print STDERR "FIND FIT NODE: ", Dumper($_->size->[W],  $_->size->[H] ,  $_->grain, $_->card);
    ($_->size->[W] <= $w && $_->size->[H] <= $h) 
    && (!defined $grain ? 1 
    :    defined $_->grain 
    && $_->grain == $rotation)
    && ($is_one_up ? $_->card == 1 : 1) 
  } @{ $lookup[$$self] };

  return @nodes;
}


# Given a box [w,h] and images to fit into it, determine all possible ways to
# fill that box that match the given criteria. NOTE: Images are currently a
# package variable and the criteria (cardinality, cutting, etc.) are hard
# coded in. The first should be a private object variable the second a
# callback.
sub fill_box :Private {
  my ($box) = @_;              # Bounding box (w×h)
  my $size  = join 'x', @$box; # Node size.

  # If we've already been calculated just reference our table entry.
  # ICON: This is a negative cache as well, 
  return $cache->{$size} if exists $cache->{$size};

  my @forest;                  # Possible impositions for size.
  #$openprint::log->debug("Images on $size ".Data::Dumper::Dumper(\@images));
  IMAGE:
  for my $image (@images) {

    my $image_size = join('x', $image->[W], $image->[H]);
    # Don't bother with this image if it can't fit.
    if ($image->[W] > $box->[W] or $image->[H] > $box->[H]) {
      $openprint::log->debug("Image $image_size doesn't fit on $size");
      next IMAGE;
    }

    # TODO: If we prepopulate the cache with these nodes and mark the
    # cache as incomplete (as other images may be able to fit within the
    # space taken by a large image), will it be less expensive then
    # checking this for every image on every node?
    if ($image->[W] == $box->[W] and $image->[H] == $box->[H]) {
      push @forest, PQS::Imposition::Node->new(
        size  => $box,
        image => $image->[ID],
        bleed => $image->[BLEED],
        grain => $image->[GRAIN], # 0 width, 1 height
      );
      return $cache->{$size} = \@forest;
    }

    DIRECTION:
    for my $dir (VERTICAL, HORIZONTAL) { # TODO grain override
      my ($bound, $len) = ($box->[$dir], $image->[$dir]); # -| to cut.

      $openprint::log->debug("box $size image size $image_size bound: $bound len:$len dir:$dir");
      next DIRECTION if $bound == $len;

      # Fill the sub-boxes made by paritioning the box.
      my @partitions = map {
      fill_box($dir ?
      [ $box->[W], $_        ] # Horizontal cut.
      : [ $_,        $box->[H] ] # Vertical cut.
      );
      } ($len, 
        Math::Round::nearest($round_to, $bound - $len)
        #($round_to, $bound - $len)
      );

      $openprint::log->debug("Parititons: ".Data::Dumper::Dumper(\@partitions));


      # Compare each pairing (cartesian product) of the two partitions and choose the best ones.
      # ICON: If we are overriding to 9 out, but there exists a 10 out, this code would prevent that.
      for my $n (@{ $partitions[HORIZONTAL] }) {
      $openprint::log->debug("Partition n ".$n->card) if $n;
        for my $p (@{ $partitions[VERTICAL] }) {
      $openprint::log->debug("Partition p ".$p->card) if $p;
          my $node = PQS::Imposition::Node->new( # Faster than copying.
            size     => $box,
            cut      => $dir,
            children => [$n, $p],
          );
      $openprint::log->debug("Partition node ".$node->card);

          if (!@forest) {
            $openprint::log->debug("No forest, just adding ".($n ? $n->card : 'none') . ' p '.($p  ? $p->card : 'none'). ' node:'.$node->card);
            push @forest, $node;
            next;
          }

          # Can we be compared? If so are we better?
          # Modified: preserve different orientations and comparable-but-worse nodes.
          # We only treat a node as an exact duplicate when both size and cut axis
          # are identical; in that case we compare and may replace the existing one.
          my $is_exact_duplicate = 0;

          for my $i (0 .. $#forest) {
            my $potential = $forest[$i];
            # If exact same size and same cut axis, compare and possibly replace.
            # Otherwise preserve both - different cuts/orientations are kept for diversity.
            if (same_size($node->size, $potential->size) && defined($potential->cut) && defined($node->cut) && $potential->cut == $node->cut) {
              my $cmp = PQS::Imposition::Node::compare($node, $potential);
              if (defined $cmp) {
                # If the new node is better, replace the existing one.
                if ($cmp > 0) {
                  $forest[$i] = $node;
                }
                $is_exact_duplicate = 1;
                last;
              }
            }
          } # end foreach comparison

          # Add node unless we already handled exact duplicate replacement above.
          push @forest, $node unless $is_exact_duplicate;
        } # end foreach p
      } # end foreach n
    } # end foreach direction
  } # end foreach image
  # If nothing matched, we're a blank node (represented as undefined).
  @forest = (undef) unless @forest;
  #$openprint::log->debug("$size => ".Data::Dumper::Dumper(\@forest));
  #foreach my $node ( @forest) {
  #$openprint::log->debug("forest $size => ".$node->card) if $node;
#}

  return $cache->{$size} = \@forest;
} # end fill_box

# TEMP: The sub-node generation is currently generating impositions with
# spacing and sub-optimal results. We'll do a simple post-processing prune of
# the cache to remove the worst of these.
sub post_process :Private {
  my ($trees, $cache) = @_;

  # UGLY! Refactor initial generation so we don't even need this. ASAP.

  my (@nodes, %seen);

  while (my ($size, $nodes) = each %{ $cache }) {
    next if ref $nodes ne 'ARRAY';

    foreach my $node (@$nodes) {
      #for my $i (0 .. $#{ $nodes }) {
      #my $node = $nodes->[$i];

      next if !$node; # Skip invalid.

      # Skip through trim nodes (nodes that contain only one other
      # container node to trim off one side).
      $node = ($node->children)[0] while $node->children == 1;

      # If the node is an image (leaf) add it to our lookup.
      if ($node->is_sink) {
        my $id = join 'x', @{ $node->size };
        if (!$seen{$id}) {
          $seen{$id} = 1;
          push @nodes, $node; # Add to valid list.
        }
        next;
      }

      # Now we'll look for extraneous white space, both parallel and perpendicular to the initial cut.
      my ($w, $h) = @{ $node->size };
      my $dir     = $node->cut;

      my ($len_x, $max_y) = (0, 0);
      for my $child ($node->children) {
        # Parallel || dimension.
        $len_x += $child->size->[$dir];

        # Perpendicular _|_.
        my $len_y = 0;
        for my $grandchild ($child->children) {
          $len_y += $grandchild->size->[!$dir];
        }

        # Find the largest child perpendicular child.
        $max_y = $len_y if $max_y < $len_y;
      }
      $max_y = $node->size->[!$dir] unless $max_y;

      my ($width, $height) = $dir ? ($max_y, $len_x) : ($len_x, $max_y);

      # Now we'll create a new box sized exactly to the nodes.
      if ($len_x < $w || $h > $max_y) {
        my @box            = @{ $node->size }; # Inital size.
        @box[ $dir, !$dir] = ($len_x, $max_y); # New size.
        my $id             = join 'x', @box;   # New ID.

        # This size optimized node already exists.
        next if exists $seen{$id};

        # Create trimmed down (y dimension) children.
        my @children;
        for my $child ($node->children) {
          my $new = $child; # New smaller child if needed.

          # If the child isn't an image or already the correct size.
          if (!$child->is_sink && $child->size->[$dir] < $max_y) {
            my @box     = @{ $child->size };

            $box[!$dir] = $max_y;

            # Create a new trimmed down node.
            $new = PQS::Imposition::Node->new(
              size  => \@box,
              cut   => $child->cut,
              grain => $child->grain,
            );
            $new->add_edge( $child->children );
          }

          push @children, $new;
        }

        # Now create the trimmed down current node.
        my $new = PQS::Imposition::Node->new(
          size  => \@box,
          cut   => $dir,
          grain => $node->grain,
        );
        $new->add_edge( @children );

        # Mark that we've seen this node size (invalid for gang-run).
        $seen{$id} = 1;

        # Add whitespace nodes for accurate cutting and mirroring.
        $new->mark_whitespace;

        push @nodes, $new; # Add to valid list.
      }
    }
  }

  return wantarray ? @nodes : \@nodes;
}


# Returns true if box A is the same size and orientations as box B. TODO:
# Really we want to generalise this to == between two pairs (n,m).
sub same_size :Private {
  my ($n, $p) = @_;
  return 1 if $p->[W] == $n->[W] and $p->[H] == $n->[H];
}

1;
__END__
