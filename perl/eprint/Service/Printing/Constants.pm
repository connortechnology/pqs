package eprint::Service::Printing::Constants;
use strict;
use warnings;

use Scalar::Util qw(dualvar);

use constant COVER    => 'Cover Spreads';
use constant GATEFOLD => 'GateFolded Spreads';
use constant INTERIOR => 'Interior Spreads';
use constant SURFACE  => 'Surfaces';

use constant {
    SHEETFED     => dualvar(14, 'press'), 
    OFFSET       => dualvar(14, 'press'),         # Alias
    WEB          => dualvar(43, 'web'),
    DIGITAL      => dualvar(41, 'digital'),
    SCREEN       => dualvar( 1, 'screen'),
    INKJET       => dualvar(38, 'inkjetprinter'),
    LARGE_FORMAT => dualvar(38, 'inkjetprinter'), # Alias
};

use base qw(Exporter);
our %EXPORT_TAGS = ( 
    spread_types => [ qw(COVER GATEFOLD INTERIOR SURFACE) ],
    press_types  => [ qw(SHEETFED OFFSET WEB DIGITAL SCREEN LARGE_FORMAT INKJET) ],
);

our @EXPORT_OK   = ( 
    @{ $EXPORT_TAGS{spread_types} }, 
    @{ $EXPORT_TAGS{press_types}  }
);


1;
