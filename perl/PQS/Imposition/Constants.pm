package PQS::Imposition::Constants;
use strict;
use warnings;

use base qw(Exporter);

our @EXPORT = qw(
    VERTICAL   WIDTH  W
    HORIZONTAL HEIGHT H

    TURN FLOP

    TOP T RIGHT R BOTTOM B LEFT L

    SPINE FACE

    FACING_SIDES
);


# All box/image dimensions are stored as (width, height) pairs.
use constant {
    VERTICAL   => 0, WIDTH  => 0, W => 0,
    HORIZONTAL => 1, HEIGHT => 1, H => 1,
};

# WT/F are mirror about the vertical (y) and horizontal (x) axes respectively.
use constant { TURN => 0, FLOP => 1 };

# Bleeds, trim, margins, etc. are top, right, bottom, left in an array.
use constant { 
                   TOP => 0,
                   T   => 0, 
     LEFT  => 3,                RIGHT => 1,
     L     => 3,                R     => 1,
     SPINE => 3,                FACE  => 1, # Alternate names for 4pg. spreads.
                  B      => 2,
                  BOTTOM => 2,

};

use constant FACING_SIDES => (
    [BOTTOM, TOP], # Vertical
    [RIGHT, LEFT]  # Horizontal
);

1;
