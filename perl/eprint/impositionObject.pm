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
    $$Paper{width} *= $$self{paper}{width_factor} if $$self{paper}{width_factor};
    $$Paper{height} *= $$self{paper}{height_factor} if $$self{paper}{height_factor};
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
    if ( $Paper and $Paper->id() ) {
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

sub columns {
  my $self = shift;
  if (@_) {
    $$self{columns} = $$self{cols} = shift;
  }
  return $$self{columns};
}

sub rows {
  my $self = shift;
  $$self{rows} = shift if @_;
  return $$self{rows};
}

sub  runstyle {
  my $self = shift;
  $$self{runstyle} = $$self{style} = shift if @_;
  return $$self{runstyle};
}

sub cut {
	my ( $I ) = @_;

	my $i1 = $I->clone();
	my @Results;

	if ( $$I{runstyle} eq 'WT' ) {
		$i1->runstyle( 'SW' );
		$i1->columns( $$i1{columns} / 2 );
		$i1->cols( $$i1{columns} / 2 );
		if ( $$I{dutch_columns} ) {
			$i1->dutch_columns( $$i1{dutch_columns} / 2 );
		} # end if
		$i1->quantity($i1->quantity()*2);
		push @Results, $i1;

	} elsif ( $$I{runstyle} eq 'WF' ) {
		$i1->runstyle( 'SW' );
		$i1->rows( $$i1{rows} / 2 );
		$i1->dutch_rows( $$i1{dutch_rows} / 2 ) if $$I{dutch_rows};
		$i1->quantity($i1->quantity()*2);
		push @Results, $i1;

	} elsif ( $$I{dutch_columns} ) {
		$i1->dutch_rows( 0 );
		$i1->dutch_columns( 0 );
		my $i2 = $I->clone();
		$i2->rows( $I->dutch_rows() );
		$i2->columns( $I->dutch_columns() );
		$i2->image_orientation( $I->image_orietation() == openprint::Imposition::Vertical ? openprint::Imposition::Horizontal : openprint::Imposition::Vertical );
		$i2->dutch_rows( 0 );
		$i2->dutch_columns( 0 );
		push @Results, $i1, $i2;
	} elsif ( ( $I->layout_width() >= $I->layout_height() ) and ( $$I{columns} > 1 ) ) {
		$i1->columns( int($$I{columns} / 2) );
		if ( ! ( $$I{columns} % 2 ) ) {
			$i1->quantity( $i1->quantity() * 2 );
			push @Results, $i1;
		} else {
			my $i2 = $I->clone();
			$i2->columns( $$I{columns} - $$i1{columns} );
			push @Results, $i1, $i2;
		} # end if
	} elsif ( ( $I->layout_width() < $I->layout_height() ) and ( $$I{rows} > 1 ) ) {
		$i1->rows( int($$I{rows} / 2) );
		if ( ! ( $$I{rows} % 2 ) ) {
			$i1->quantity( $i1->quantity() * 2 );
			push @Results, $i1;
		} else {
			my $i2 = $I->clone();
			$i2->rows( $$I{rows} - $$i1{rows} );
			push @Results, $i1, $i2;
		} # end if
	} elsif ( ( $$I{columns} >= $$I{rows} ) and ( $$I{columns} > 1 ) ) {
		my $i2 = $I->clone();
		$i1->columns( int($$I{columns} / 2) );
		$i2->columns( $$I{columns} - $$i1{columns} );
		push @Results, $i1, $i2;
	} elsif ( $$I{rows} > 1 ) {
		my $i2 = $I->clone();
		$i1->rows( int($$I{rows} / 2) );
		$i2->rows( $$I{rows} - $$i1{rows} );
		push @Results, $i1, $i2;
	} # end if
	foreach my $i ( @Results ) {
$openprint::log->debug('Cut to'.$i->to_string());
	}
	return @Results;
} # end sub cut_imposition

sub layout_width {
  $_[0]{layout_width} = $_[1] if @_ > 1;

	if ( ! defined $_[0]{layout_width} ) {
		if ( $_[0]{image_orientation} == openprint::Imposition::Vertical ) {
			$_[0]{layout_width} = ( $_[0]{columns} * $_[0]{image_width} ) + $_[0]{perfecting_wheel_space};
#$_[0]->display();
#$openprint::log->debug("Layout width $_[0]{layout_width} = ( $_[0]{columns} * $_[0]{image_width} ) + $_[0]{perfecting_wheel_space};") if DEBUG;
			if ( $_[0]{folio_lip} ) {
				my $folio_size = $_[0]{columns} * ( $_[0]{folio_lip} - ( $_[0]{columns} * $_[0]{bleed_size} ) );
#$openprint::log->debug("Adding folio lip size to width $folio_size = $_[0]{columns} * ( $_[0]{folio_lip} - $_[0]{bleed_size} );");

				$folio_size -= $_[0]{colour_bar_size} if $_[0]{colour_bar_orientation} ne 'Width';
				$folio_size -= $_[0]{gutters} / 2;
				$folio_size -= $_[0]{perfecting_wheel_space};
				if ( $folio_size > 0 ) {
					#$openprint::log->debug("Adding folio lip size to width " . $folio_size . 'gutters ' . $_[0]{gutters}  );
					$_[0]{layout_width}  += $folio_size - $_[0]{gutters};
					#$openprint::log->debug("image size is $_[0]{image_width}a nd perfecting wheel space is $_[0]{perfecting_wheel_space} ttial is $_[0]{layout_width}");
#} else {
					#$openprint::log->debug("NOT Adding folio lip size to width " . $folio_size . 'gutters:' . $_[0]{gutters}  );

				}
			}

#$openprint::log->debug("layout_width = $_[0]{columns} * $_[0]{image_width} + ( $_[0]{perfecting_wheel_space} - $_[0]{bleed_size} )");
			if ( $_[0]{dutch_columns} ) {
				my $dutch_width = $_[0]{dutch_columns} * $_[0]{image_height};

				if ( $_[0]{dutch_orientation} eq 'width' ) {
					$_[0]{layout_width} += $dutch_width;
				} else {
# Only adjust the width if it exceeds the non-dutch width
					$_[0]{layout_width} = $dutch_width if $dutch_width > $_[0]{layout_width};
				} # end if
			} # end if
		} elsif ( $_[0]{image_orientation} == openprint::Imposition::Horizontal ) {
			$_[0]{layout_width} = $_[0]{columns} * $_[0]{image_height} + $_[0]{perfecting_wheel_space};
#$openprint::log->debug("Horz: $_[0]{layout_width} = $_[0]{columns} * $_[0]{image_height} + $_[0]{perfecting_wheel_space};");

			if ( $_[0]{dutch_columns} ) {
				my $dutch_width = $_[0]{dutch_columns} * $_[0]{image_width};

				if ( $_[0]{dutch_orientation} eq 'width' ) {
					$_[0]{layout_width} += $dutch_width;
				} else {
					$_[0]{layout_width} = $dutch_width if $dutch_width > $_[0]{layout_width};
				} # end if
			} # end if
		} else {
$openprint::log->warn("layout_width: Unknown orientation ($_[0]{image_orientation})");
		} # end if
	} # end if ! defined $_[0]{layout_width}
	return $_[0]{layout_width};
}

sub layout_height {
  $_[0]{layout_height} = $_[1] if @_ > 1;
	if ( ! defined $_[0]{layout_height} ) {
		if ( $_[0]{image_orientation} == openprint::Imposition::Vertical ) {
			$_[0]{layout_height} = $_[0]{rows} * $_[0]{image_height};
			if ( $_[0]{dutch_columns} ) {
				my $dutch_height = $_[0]{dutch_rows} * $_[0]{image_width};

				if ( $_[0]{dutch_orientation} eq 'width' ) {
					$_[0]{layout_height} = $dutch_height if $dutch_height > $_[0]{layout_height};
				} else {
					$_[0]{layout_height} += $dutch_height;
				} # end if
			} # end if
		} elsif ( $_[0]{image_orientation} == openprint::Imposition::Horizontal ) {
			$_[0]{layout_height} = $_[0]{rows} * $_[0]{image_width};
			my $folio_size = $_[0]{rows} * ( $_[0]{folio_lip} - $_[0]{bleed_size} );
			$folio_size -= $_[0]{colour_bar_size} if $_[0]{colour_bar_orientation} eq 'Width';
			$folio_size -= $_[0]{grip};
			if ( $folio_size > 0 ) {
				$openprint::log->debug("Adding folio lip size $folio_size to height  $_[0]{rows} * ( $_[0]{folio_lip} - $_[0]{bleed_size} ) - $_[0]{colour_bar_size} $_[0]{colour_bar_orientation}  grip: $_[0]{grip}"  );
				$_[0]{layout_height} += $folio_size;
        #} else {
        #$openprint::log->debug("Not Adding folio lip size $folio_size to height  $_[0]{rows} * ( $_[0]{folio_lip} - $_[0]{bleed_size} ) - $_[0]{colour_bar_size} $_[0]{colour_bar_orientation}  grip: $_[0]{grip}"  );
			}

			if ( $_[0]{dutch_columns} ) {
				my $dutch_height = $_[0]{dutch_rows} * $_[0]{image_height};

				if ( $_[0]{dutch_orientation} eq 'width' ) {
					$_[0]{layout_height} = $dutch_height if $dutch_height > $_[0]{layout_height};
				} else {
					$_[0]{layout_height} += $dutch_height;
				} # end if
			} # end if
		} else {
$openprint::log->debug("Unknown orientation $_[0]{image_orientation}");
		} # end if
	} 
	return $_[0]{layout_height};
}
1;
__END__
