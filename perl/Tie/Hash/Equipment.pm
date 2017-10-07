use strict;
use warnings;

# Provides a read-only hash that normalizes lookup keys to lowercase with
# spaces converted to underscore.
package Tie::Hash::Equipment; {

use Tie::Hash;
use Carp;

use base qw(Tie::StdHash);

# Bless a copy of the initializing hash reference.
sub TIEHASH {
    my ($class, $hash_ref) = @_;
    bless \%{ $hash_ref }, $class;
}

sub FETCH {
    my ($self, $key) = @_;

    # Normalize the key; all lowercase and space -> underscore.
    $key = lc($key); $key =~ tr/ /_/; # tr/A-Z /a-z_/ <- Not UTF8 compat.

    croak "Invalid attribute ($self->{type}.$key)."
        unless exists $self->{$key};

    return $self->{$key};
}

# TODO. Keep a list of the initializing attributes so a user can add and
# remove custom attributes and functions.
sub STORE  { croak "Equipment attributes are currently read only."; }
sub CLEAR  { croak "Equipment attributes are currently read only."; }
sub DELETE { croak "Equipment attributes are currently read only."; }

}
1;
