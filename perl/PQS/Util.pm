package PQS::Util;
use strict;
use warnings;

use base qw(Exporter);

our @EXPORT = qw(group);

our @EXPORT_OK = qw( verify_cc get_modules );

=head3 group $set $field

Takes a 'set' and a list of fields and returns the 'set' grouped by the given
field. Very useful for displaying record with groupings in an appealing
manner. The set does not need to be ordered, but if it's not there is no
guaranteed return order of groupings.

A 'set' for our Perlish purposes is a reference to an array of hashrefs and
the return is the reference to an array of hash references with two keys {
name => $key, group => $original_hashref }. 

So this: 
 
   [ 
       { id => foo, category => c1, name => 'name', },
       { id => bar, category => c2, name => 'name', },
       { id => foo, category => c2, name => 'name', },
   ]

becomes this: 

   [
       { group => foo,
         data  => [ 
             { id => foo, category => c1, name => 'name', },
             { id => foo, category => c2, name => 'name', }, ] },
       { group => bar,
         data  => [
             { id => $id, category => $cat, name => $name, } ] },
             
   ]

=head4 ATTRIBUTES

=item name

 name => 'string'

If some records are missing or have an unknown group, this sets the name they
are grouped by. Default is "Unknown".

=item unsorted 

 unsorted => 1

A boolean flag that sets whether the set is sorted or not. This speed up a few
checks for unsorted sets, but will probably soon be deprecated for a 'sorted'
flag (see the L<TODO>)

=item sort 

  sort=> { $a cmp $b }

B<Not yet implemented>. Defines the sort order to apply to the groupings.
Default currently is the order they're seen for sorted sets (order is
preserved) and hash order for unsorted sets. It will soon be the first for
both types of sets. 

=head4 TODO

=item

If the need arises this function could be sped up quite a bit by optimising
the use of references (instead of copying) in some section.

=item

Allow sort orders for groups to be passed into the attributes hash.

=item 

Revise how we treat ordered and unordered sets, we now always check so do we
need the flag or should we have a 'sorted' flag that if set speeds things up
but user beware if they pass an unsorted set (weird displays of groups).

=cut

sub group (\@$;%) {
    my $set   = shift;
    my $field = shift;
    my $attr  = shift; # Attributes hash

    my (%data, @order, $prev);
    
    for my $rec (@$set) {
        my $key = $rec->{ $field };
        
        # If the key is undefined (0 is an okay key) we need a default name
        # for that group.
               $attr->{name} = "Unknown" unless exists $attr->{name};
        $key = $attr->{name}             unless defined $key;

        $data{$key} = [] unless exists $data{$key};
        
        # Add the group name to the key list (so we can preserve the record
        # set orderering) unless we've already seen that name or the user told
        # us the set was unordered; in which case we don't give a shit.
        push @order, $key unless $key eq $prev or $attr->{unordered};

        push @{ $data{$key} }, $rec;

        $prev = $key;
    }
    
    # If the user forgot to tell us the set was unordered, we could get really
    # weird ouput options as we treat it as ordered by default. Make sure it
    # really was ordered, and if it's not set the unordered flag.
    if (@order) {
        my %uniq; 
        $uniq{$_}++ for @order;
        $attr->{unordered} = scalar grep { $uniq{$_} > 1 } keys %uniq;
    }
    
    # If the set is unordered, we'll send it back in hash order. TODO: The
    # user should be able to specify a sort in the attributes hash.
    @order = keys %data if $attr->{unordered};

    # Create the return set.
    my @set;
    push @set, { group => $_, data => $data{ $_ } } for @order;

    # Output the set in our grouped format.
    return \@set;
}

# a simple mod10 cc check subroutine.
sub verify_cc {
    my ($card_no) = @_;

    return 0 if length $card_no < 12 || length $card_no > 16;

    my $count = 0;
    my $xor   = 1;

    foreach my $digit (split q{}, $card_no) {
        if ($xor) {
            $digit *= 2;

            if ($digit >= 10) {
                $count++;
                $digit -= 10;
            }
        }

        $count += $digit;

        $xor ^= 1;
    }

    return !($count % 10);
}

sub get_modules {
    my ($base_class) = @_;

    $base_class =~ s{::}{/}g;

    my @modules;

    foreach my $dir (@INC) {
        push(@modules, <$dir/$base_class/*.pm>);
    }

    map { s{.*?([^/]+)[.]pm$}{$1}; $_ } @modules;

    return @modules;
}


1;
