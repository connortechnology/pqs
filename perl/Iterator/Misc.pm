package Iterator::Misc;
use strict;
use warnings;

use Iterator;
use Iterator::Util qw(iarray imap);

use base qw(Exporter);
our @EXPORT = qw(cross_product iflatten);

# Given any number of arrays return an iterator over their cross product.
sub cross_product {
    my (@arrays) = @_;

    return Iterator->new( sub { Iterator::is_done }) unless @arrays;
    return imap { [$_] } iarray($arrays[0])          if scalar @arrays == 1;

    my $done;
    my @len = map { $#{$_} } @arrays; # Last valid position of each array.
    my @pos = (0) x @arrays;          # Start all cursors at 0.

    return Iterator->new(sub{
        # If the iterator if finished, return the done signal but also reset
        # all the positions so we can use it again if needed.
        if ($done) {
            @pos = (0) x @arrays;
            return Iterator::is_done;
        }
        
        # Get the current value of the iterator to return.
        my @return = map { $arrays[$_][ $pos[$_] ] } 0..$#arrays;

        # Increment the positions for the next time through.
        my $tail = $#arrays; 
        INCREMENT:
        {
            # We've exhausted the current array.
            if ($pos[$tail] == $len[$tail]) {
                $pos[$tail] = 0; # Reset it (for the next run through).
                $tail--;         # And look at the previous element.

                # If we're on the first list and it's finished, we're done.
                $done++ if $tail == 0 && $pos[$tail] == $len[$tail];

                # We need to increment the previous element.
                redo INCREMENT unless $done;
            }
            
            $pos[$tail]++; # Increment the current counter.
        }
        return \@return;
    });
}

# Given an iterator over iterators, flatten into a single iterator.
sub iflatten {
    my ($main) = @_;

    # If our primary is empty we don't have anything to do.
    return Iterator->new(sub{ Iterator::is_done }) if $main->is_exhausted;

    my $iter = $main->value;

    return Iterator->new(sub{
        # If our current iterator is exhausted get the next.
        if ($iter->is_exhausted) {
            return Iterator::is_done if $main->is_exhausted; # All done.
            
            $iter = $main->value; # Get the next iterator.
        }
        
        return $iter->value;
    });
}

1;
