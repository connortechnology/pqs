package PQS::Imposition::Colour;
use strict;
use warnings;

use base qw(Exporter);

our @EXPORT_OK = qw(gen_colours hsv2rgb rgb2hex);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

use constant STEP_HUE        => 60;
use constant STEP_SATURATION =>  0.10;
use constant STEP_VALUE      => -0.06;

use constant OFFSET_HUE     => 15;

use constant MAX_SATURATION => 0.45;
use constant MIN_SATURATION => 0.10;
use constant MIN_VALUE      => 0.95;

# Return a simples iterator function that generates 'distinct' hues in a
# reproducable sequence.
sub gen_colours {
    my ($hue, $saturation, $value) 
        = (180, 0.25, 0.90);

    my $i = 0;

    # Simple colour generation, not great but it will do.
    return sub {
        $hue += STEP_HUE;

        if ($hue > 360) {
            $hue %= 360;

            $hue += OFFSET_HUE; # Offset step
        }

        # For every two steps forward take one step back ;)
        $saturation += $i ? STEP_SATURATION : STEP_SATURATION / -2;
        $value      += $i ? STEP_VALUE      : STEP_VALUE      / -2;

        if ($saturation > MAX_SATURATION) {
            $saturation = MIN_SATURATION;
            $value      = MIN_VALUE;
        }

        $i++;
        $i %= 2;

        return ($hue, $saturation, $value);
    }
}

sub hsv2rgb {
  my ( $h, $s, $v ) = @_;
  
  $v *= 255;

  return ( $v, $v, $v ) if $s ==0; # Achromatic (grayscale)

  my $i = int( $h/60 );  # sector 0 to 5
  my $f = ($h/60) - $i;  # fractional part of h/60

  my $p = $v * ( 1 - $s );
  my $q = $v * ( 1 - $s * $f );
  my $t = $v * ( 1 - $s * ( 1 - $f ) );

  $i %= 6;               # tolerate values of $h larger than 360
  if(    $i==0 ) { return ( $v, $t, $p ); }
  elsif( $i==1 ) { return ( $q, $v, $p ); }
  elsif( $i==2 ) { return ( $p, $v, $t ); }
  elsif( $i==3 ) { return ( $p, $q, $v ); }
  elsif( $i==4 ) { return ( $t, $p, $v ); }
  elsif( $i==5 ) { return ( $v, $p, $q ); }
  else { 
    # Never get here!
    die "Bad $i in hsv2rgb( $h, $s, $v )";
  }
}

sub rgb2hex { return sprintf "#%02x%02x%02x", @_ }


1;
