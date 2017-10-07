package crypto;
use strict;
use warnings;

use Crypt::CBC;

use constant KEY => 'Pr1ntQu0t3s';

sub get_crypt {
    my ( $log, $dbh ) = @_;

    # added keysize to hash, since new versions of Crypt::CBC require it.
    return Crypt::CBC->new( {
            key            => KEY,
            keysize        => length KEY,
            cipher         => 'Blowfish',
            regenerate_key => 0,
            padding        => 'space',
            prepend_iv     => 0,
            iv             => '$KJh#(}q',
    } );
}

sub new     { return bless {}, shift; }
sub encrypt { return $_[1] }
sub decrypt { return $_[1] }

1;
