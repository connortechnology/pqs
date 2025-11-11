package PQS::Imposition::Node;
use strict;
use warnings;

our $VERSION = '0.01';

use Object::InsideOut 3.37 qw(Storable);
use PQS::Imposition::Constants;
use List::Util qw(sum);

my @edges :Field(Get => 'edges'); # Out edges.
my @cut   :Field(Get => 'cut');   # Cut direction.
my @size  :Field(Get => 'size');


my @bleeds :Field(Get => 'bleed'); # Promoted bleeds.
my @card   :Field(Get => 'card');  # Image count.
my @rot    :Field(Get => 'rot');   # Aggregate cut rotations.
my @grain  :Field(Get => 'grain');

sub _init :Init {
    my ($self, $args_ref) = @_;

    $edges[$$self]  = [];

    $cut[$$self]    = $args_ref->{cut};
    $size[$$self]   = $args_ref->{size};
    
    $rot[$$self]    = 0; # Cut rotations

    $card[$$self]   = 0; # [0,0,0,0];

    $bleeds[$$self] = [];

    if (exists $args_ref->{image}) {
        # $card[$$self]->[ $args_ref->{image} ] = 1;
        $card[$$self] = 1;

        $bleeds[$$self] = exists $args_ref->{bleed} 
            ? $args_ref->{bleed} 
            : [0,0,0,0];
    }

    $grain[$$self] = exists $args_ref->{grain} ? $args_ref->{grain} : undef;

    if ($args_ref->{children}) {
        for my $child (grep { defined $_ } @{ $args_ref->{children} }) {
            # Collapse the node if it's children can be cut in parallel to ours.
            $self->add_edge( ($child->is_sink or $cut[$$child] != $cut[$$self])
                ? $child
                : $child->children
            );
        }

        # Sort children to optimize parallel cuts and for asthetics.
        $edges[$$self] = [
            sort { $size[$$b][ $cut[$$self] ] <=> $size[$$a][ $cut[$$self] ] } 
                @{ $edges[$$self] }
        ];
    }

    
    return $self;
}

# Add an edge from ourselves to the target.
sub add_edge {
    my ($self, @nodes) = @_;

    my $id = $$self;

    # Adjust the current nodes 'counting' attributes.
    for my $node (@nodes) {
        my $n = $$node;

        next if $node->is_empty;
        
        # If the parent containes images, the grain should be set to mixed if
        # it's already mixed or if the parent doesn't match the child.
        $grain[$id] = $card[$id] && (   !defined $grain[$id] 
                             || !defined $grain[$n] 
                             || $grain[$id] != $grain[$n] )
                ? undef : $grain[$n];
        
        # Add the child's rotations plus one if the cut axis is different.
        if (@{ $edges[$n] }) {
            $rot[$id] += $rot[$n] + ($cut[$id] ^ $cut[$n]);
        }

        # Bleeds.
        my ($k, $p) = ($bleeds[$id], $bleeds[$n]);

        # If we're not yet defined, we're the same as our first child.
        if (!defined $k || !scalar @$k) {
            $bleeds[$id] = [ @$p ];
        }
        # Common bleeds are maintained as-is, otherwise 0 for no relation.
        else {
            for my $i (0 .. 3) {
                my $m = $k->[$i];

                $k->[$i] = ($m == $p->[$i]) ? $m : 0;
            }
        }

        $card[$id] += $card[$n];

        # Sum each image's count. NOTE: Faster than `pairwise`.
        # my ($x, $y) = ($card[$id], $card[$n]);
        
        # $x->[$_] += $y->[$_] for 0 .. $#{ $x }; # In-place modify.
    }

    # Increment (or initialize) the edge count for the given nodes. Note:
    # pushing full set outside loop is faster than item by item.
    push @{ $edges[$id] }, @nodes; 
    
    return $self;
}

# Return the list of nodes we have edges to.
sub children { return @{ $edges[${ $_[0] }] } }

# If there are no outbound edges a vertex is a sink.
sub is_sink { @{ $edges[ ${$_[0]} ] } == 0 }

# A whitespace node has no children and is not an image.
sub is_empty { (@{ $edges[ ${$_[0]} ] } == 0) && ! $card[ ${$_[0]} ] }

# Return a mirrored copy, across the horizontal or vertical axis, of the node.
sub mirror {
    my ($self, $axis) = @_;

    my @sides = $axis ? (TOP, BOTTOM) : (RIGHT, LEFT); # Bleed edges
    my $node  = $self->clone(1);                       # Complete copy

    # Flip the bleed edges along the mirror axis.
    @{ $bleeds[$$node] }[ @sides ] = @{ $bleeds[$$node] }[ reverse @sides ];

    return $node if $node->is_sink; # We're done if we're an image node.

    # Reverse child ordering for cuts along the mirror axis.
    if ($cut[$$node] == $axis) {
        $edges[$$node] = [ reverse @{ $edges[$$node] } ];
    }

    # Replace the original children with mirrored copies.
    $_ = $_->mirror($axis) for @{ $edges[$$node] };

    return $node;
}

# Create whitespace nodes for any nodes where the image children do not fill
# the containing node.
sub mark_whitespace {
    my ($self) = @_;

    return $self if $self->is_sink; # We're done if we're an image node.

    # Whitespace nodes are needed for determining cutting and preserving the
    # geometry during a mirror.
    my $sum = sum map { $size[$$_][ $cut[$$self] ] } @{ $edges[$$self] };

    if ($sum < $size[$$self][ $cut[$$self] ]) { # Children smaller than space.
        my @box = @{ $size[$$self] };
        $box[ $cut[$$self] ] = $size[$$self][ $cut[$$self] ] - $sum;

        $self = $self->clone(1);

        $self->add_edge(PQS::Imposition::Node->new(size => \@box));
        #push @{ $edges[$$self] }, PQS::Imposition::Node->new(size => \@box);
    }

    $_ = $_->mark_whitespace for @{ $edges[$$self] };

    return $self;
}

# Create a work and turn (0) or flop (1) imposition from the given node.
sub work_and {
    my ($self, $axis) = @_;

    # Attaching the node along the given axis means the combined dimensions on
    # the opposite axis.
    my @size = @{ $self->size };
    $size[$axis] *= 2;
    #$openprint::log->debug("work_and new size ".join('x', @size));

    my $node = PQS::Imposition::Node->new(
        size => \@size,
        cut  => $self->cut,
    );

    # If the mirror/merge axis is parallel to the first cut we simply append # the mirrored copy.
    if ($self->is_sink) {
      # one out?
        $node->add_edge($self, $self->mirror($axis));
        $cut[$$node] = $axis;
    } elsif ($axis == $self->cut) {
        $node->add_edge($_) for $self->mirror($axis)->children, $self->children;
    } elsif ($axis != $self->cut) {
      # Otherwise we'll extend the bounding boxes along the axis and append the
      # children of those and it's mirrors.
        # for my $child ( $self->children ) {
        # 
        #     my @box = @{ $child->size };
        #     $box[$axis] *= 2;
        # 
        #     my $new = PQS::Imposition::Node->new(
        #         size => \@box,
        #         cut  => $child->cut, # Talk back to ME will you?
        #     );
        # 
        #     if ($child->is_sink) {
        #         $new->add_edge($child, $child);
        #     }
        #     else {
        #         $new->add_edge($_) 
        #             for $child->mirror($axis)->children, $child->children;
        #     }
        # 
        #     $node->add_edge($new);
        # }
            
        # Alternate mirroring that doesn't combine children. Simplifies MV
        # colouring. Eventually we probably want to combine children as above. 
        $cut[ $$node ] = !$cut[ $$node ] || 0;

        $node->add_edge($_) for $self->mirror($axis), $self;
    }

    return $node;
}



# UTILITY FUNCTIONS
#
# These should go into their own package soon. In fact, as different
# imposition types will use different comparisons, they should be put in that
# package and be switched out to the appropriate one at imposition creation
# time.
sub compare { # Class method
  my ($n, $p) = @_;
  my ($x, $y) = ($$n, $$p);
  
  #if (!(defined $grain[$x] and defined $grain[$y] and  ($grain[$x] == $grain[$y]))) {
    #$openprint::log->debug("Not Comparing cardinality x:$x size:".join('x', @{$size[$x]})." card:$card[$x] grain: $grain[$x] cuts:$cut[$x] <=> y:$y size:".join('x',@{$size[$y]})." $card[$y] grain: $grain[$y] cuts: $cut[$y] size of array: ".scalar @card);
    #return undef;
    #}

  my $cmp = $card[$x] <=> $card[$y];
  #     compare_cardinality($card[$x], $card[$y]);
  #    my $cmp = compare_cardinality_pp($x, $y);

  return $cmp unless defined $cmp and $cmp == 0;

  # Maximize images, minimize rotations, prefer parallel cuts.
  $cmp ||=  $rot[$y]        <=> $rot[$x]        # Min.
  ||   @{ $edges[$x] } <=> @{ $edges[$y] } # Max.
  ;

  # If the trees are equal but they have different cut directions we can't
  # compare them at this level.
  return undef if $cmp == 0 and $cut[$x] != $cut[$y];

  return $cmp;
}

# sub compare_cardinality_pp {
#     my ($n, $p) = map { $card[$_] } @_;
# 
#     # Interating and using boolean flags is a ton faster than using the XS
#     # pairwise.
# 
#     my ($gt, $lt) = 0;
#     for my $i (0..$#{ $n }) {
#         my ($x, $y) = ($n->[$i], $p->[$i]);
# 
#         $gt ||= $x > $y;
#         $lt ||= $x < $y;
#         
#         # The most common result is the nodes can't be compared, so we
#         # short-circuit here (proved by profiling).
#         return undef if $gt && $lt;
#     }
# 
#     # If we have a mix or images we can't compare the two nodes.
#     return  $gt        ?  1
#           : $lt        ? -1
#           :               0
#     ;
# }
# 
# 
# use Inline 'C' => <<'END_C';
# 
# SV* compare_cardinality(AV* xs, AV* ys) {
#     int idx = av_len(xs);
#     
#     bool gt = FALSE;
#     bool lt = FALSE;
#     
#     // Compare the image counts in parallel. Disimilar (x > y in one case, y >
#     // x in another) cases return an unknown (undef) comparison.
#     int i;
#     for (i = 0; i <= idx; i++) {
#         int x = SvIV(*av_fetch(xs, i, FALSE));
#         int y = SvIV(*av_fetch(ys, i, FALSE));
# 
#         gt |= (x > y);
#         lt |= (x < y);
#         
#         if (gt && lt) // Short-circuit as this is most common case.
#             return &PL_sv_undef;
#     }
# 
#     // Return the standard Perl <=> return if the two can be compared.
#     return newSViv(  gt ?  1 
#                    : lt ? -1 
#                    :       0
#     );
# }
# 
# END_C

1;
