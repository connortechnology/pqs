package eprint::impositionObject;
use strict;
#use warnings;

require openprint::Equipment;
require openprint::Paper;

use Carp;
my %Orientations = (
  0 =>  'Vertical',
  1 =>  'Horizontal',
);


sub new {
	my ($class, $press) = @_;

	my $self = {
        press             => $press,
        setup             => undef,
        run_style         => undef,
        grain_direction   => undef,
        rotate_sheet      => undef,
        rows              => undef, # \
        cols              => undef, # / Still needed for multi-page for now.
        image_width       => undef,
        image_height      => undef,
        image_orientation => undef,
        image_orientation_text => undef,
        spread_rows       => undef, # -|
        spread_cols       => undef, #  |-- Created by convert_imposition()
        spreads           => undef, # -|
        stitch_size       => undef,
        cut_off           => undef,
        paper             => {},
        layout            => [],
        tree              => undef,
        colour_bar        => 0,
        grip              => 0,
        gutter            => 0,
        quantity          => 1,
    };

	bless $self, $class;

    return $self;
}

sub set {
    my ($self, @params) = @_;

    my @param_map = qw(
        setSetup
        setStyle
        setGrainDirection
        setRotateSheet
        setRows
        setCols
        setImageWidth
        setImageHeight
        setImageOrientation
        setPaper
        setLayout
        setTree
        setColourBar
        setGrip
        setGutter
    );

    my $current_param = 0;

    foreach my $code_ref ( @param_map ) {
        $self->$code_ref( $params[$current_param++] );
    }
}

sub clone {
  my $self = shift;
  my %copy = %{$self};
  my $copy = \%copy;
  bless $copy, ref $self;
  return $copy;
}

sub DESTROY { };

sub AUTOLOAD {
  my ($self, @params) = @_;

  my $command = our $AUTOLOAD;
  $command =~ s/.+::(get|set)//;
  my $which   = $1;

  $command = lcfirst $command;

  $command =~ s/([A-Z])/'_' . lc $1/eg;

  if ($command eq 'style') {
    $command = 'run_style';
  }

  if (!$which) {
    my ( $caller, undef, $line ) = caller;
    $openprint::log->error("No whcih @_ from $caller :: $line");
  }
  if ($which eq 'set' && exists $self->{$command}) {
    $self->{$command} = $params[0];
    $$self{runstyle} = $params[0] if $command eq 'run_style';
    $$self{columns} = $params[0] if $command eq 'cols';
    $$self{imposition} = $params[0] if $command eq 'setup';
  } elsif (!exists $self->{$command}) {
    my ( $caller, undef, $line ) = caller;
    $openprint::log->error( "Invalid command: $command from $caller:$line");
  }

  return $self->{$command};
}

sub Press {
  my $self = shift;
  if (!$$self{Press}) {
    $$self{Press} = new openprint::Equipment($$self{press});
  }
  return $$self{Press};
}

sub Paper {
  my $self = shift;
  if (!$$self{Paper}) {
    my $Paper = $$self{Paper} = new openprint::Paper($$self{paper}{index});
    @$Paper{'start_width','start_height'} = @$Paper{'width','height'};
    $$Paper{Supplied} = $Paper->clone();
    $$Paper{width} /= $$self{paper}{width_factor} if $$self{paper}{width_factor};
    $$Paper{height} /= $$self{paper}{height_factor} if $$self{paper}{height_factor};
  }
  return $$self{Paper};
}

sub page_rows {
  my $self = shift;
  if ($$self{spreads}) {
    return $$self{spread_rows};
  } else {
    return 1;
  }
}

sub page_columns {
  my $self = shift;
  if ($$self{spreads}) {
    return $$self{spread_cols};
  } else {
    return 1;
  }
}
sub pages {
  my $self = shift;
  if ( ! $$self{pages}) {
    $$self{pages} = ( $$self{spreads} ? $$self{spreads} : 1 ) * 2;
  }
  return $$self{pages};
}

sub to_string {
  my $self = $_[0];
  $$self{to_string} = $_[1] if @_ > 1;
  my $Press = $self->Press();
  my $Paper = $self->Paper();

  if ( ! $_[0]{to_string} ) {
    if ( $Paper->id() ) {
      $_[0]{to_string} = sprintf('%s %d@ %dx%d+%dx%d=%dout %s %dx%d=%dpages %sx%s on %sx%s%s->%sx%s', ( $Press->id() ? $Press->strid(): 'unknown equipment' ),
        #$_[0]{to_string} = sprintf('%s %d@ %dx%d+%dx%d=%dout %s %dx%d=%dpages %sx%s on %sx%s%s->%sx%s %s', ( $Press->id() ? $Press->strid(): 'unknown equipment' ),
          @$self{'quantity','columns','rows','dutch_columns','dutch_rows','imposition','runstyle'},
          $_[0]->page_columns(), $_[0]->page_rows(),
          @$self{'pages','page_width','page_height'},
          @$Paper{'start_width','start_height', 'type','width','height'},
          #$_[0]->image_orientation_text()
        );
    } else {
      if ( $$self{quantity} and ($_[0]{quantity} > 1)) {
      $_[0]{to_string} = sprintf('%s %d @ %dx%d+%dx%d=%dout %s %dx%d=%dpages', ( $Press->id() ? $Press->strid() : 'unknown equipment' ), $_[0]->get('quantity','columns','rows','dutch_columns','dutch_rows','imposition','runstyle','page_columns','page_rows','pages', 'sheet_width','sheet_height'),
        #@Orientations{@$self{'image_orientation_text','spine_direction'}}
        );
      } else {
      $_[0]{to_string} = sprintf('%s %dx%d+%dx%d=%dout %s %dx%d=%dpages', ( $Press->id() ? $Press->strid() : 'unknown equipment' ), $_[0]->get('columns','rows','dutch_columns','dutch_rows','imposition','runstyle','page_columns','page_rows','pages', 'sheet_width','sheet_height'),
        #@Orientations{@$self{'image_orientation_text','spine_direction'}}
        );
      }
    } # end if
  }
  return $_[0]{to_string};
} # end sub to_string

1;
__END__
