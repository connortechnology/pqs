use strict;
use Carp qw( cluck );

package openprint::Imposition;
require Math::Round;
require Data::Dumper;
use SVG;
use vars qw( $AUTOLOAD %Orientations @RunStyles %ShortStyles);
use constant DEBUG => 0;
use constant DEBUG_PERFORMANCE => 1;

use constant Vertical => 0;
use constant Horizontal => 1;
%Orientations = (
	0	=>	'Vertical',
	1	=>	'Horizontal',
);

@RunStyles = ( 'Sheet Work', 'Work & Turn', 'Work & Tumble', 'Perfecting', 'Web' );
%ShortStyles = (
  'Sheet Work' => 'SW',
  'Work & Turn' => 'WT',
  'Work & Tumble' => 'WF',
  'Perfecting' => 'PF',
  'Web'   => 'Web',
);

my @fields = (
	'start_imposition','start_columns','start_rows',
	'version_qty','imposition','rows','columns',
	'dutch_rows','dutch_columns', 'dutch_orientation',
	'image_width','image_height', # dimensions + bleed
	'object_width','object_height', # Flat dimensions
	'layout_width','layout_height',
	'perfecting_wheel_space',
	'cut_off',
	'runstyle',
	'spread_rows','spread_columns','spreads','spread_size',
	'grip','gutters',
	'image_orientation','image_orientation_text',
	'Paper',
	'Press',
	'grain_direction','rotate_sheet',
	'Total','Comparison',
	'overs',
	'colour_bar_size',
	'colour_bar_orientation',
	'cropmark_top','cropmark_bottom','cropmark_left','cropmark_right',
	'sheet_width','sheet_height',
	'page_quantity','quantity','width_folds','height_folds',
	'bleed_top','bleed_bottom','bleed_left','bleed_right',
	'bleed_size',
	'specs',
	'pages',
	'stock_weight',
	'sides',
	'Project',
	'printing_type',
	'Folds', 'Fold',
	'runspeed',
	'impressions',
  'net_sheets',
  'gross_sheets',
	'equipment_id', 'Equipment',
	'inkCoverage',
	'folio_lip',
	'page_width',
	'page_height',
	'page_columns',
	'page_rows',
	# spine is relative to the image width/height, spine_direction is to the imposition so vertical or horizontal
	'spine','spine_direction',
);

# spread_cols and spread_rows are oriented identically to the imposition

sub new {
	my $self = {};
	bless $self, $_[0];

	$$self{rows} = 0;
	$$self{columns} = 0;
	$$self{dutch_rows} = 0;
	$$self{dutch_columns} = 0;

	return $self;
} # end sub new

sub layout_width {
  $_[0]{layout_width} = $_[1] if @_ > 1;

	if ( ! defined $_[0]{layout_width} ) {
		if ( $_[0]{image_orientation} == Vertical ) {
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
		} elsif ( $_[0]{image_orientation} == Horizontal ) {
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
		if ( $_[0]{image_orientation} == Vertical ) {
			$_[0]{layout_height} = $_[0]{rows} * $_[0]{image_height};
			if ( $_[0]{dutch_columns} ) {
				my $dutch_height = $_[0]{dutch_rows} * $_[0]{image_width};

				if ( $_[0]{dutch_orientation} eq 'width' ) {
					$_[0]{layout_height} = $dutch_height if $dutch_height > $_[0]{layout_height};
				} else {
					$_[0]{layout_height} += $dutch_height;
				} # end if
			} # end if
		} elsif ( $_[0]{image_orientation} == Horizontal ) {
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

my %fields_to_recalc_layout_for = map { $_, 1 } ( 'rows','columns','dutch_rows','dutch_columns','spread_rows','spread_columns','spreads','image_width','image_height','spread_size','object_width','object_height', 'gutters', 'folio_lip', 'perfecting_wheel_space' );

sub AUTOLOAD {
	no strict;
    my $name = $AUTOLOAD;
    $name =~ s/.*://;
#$openprint::log->debug("Imposition::AUTOLOAD::$name");

    if ( @_ > 1 ) {
		$_[0]{$name} = $_[1];
		if ( $fields_to_recalc_layout_for{$name} ) {
			$_[0]{imposition} = $_[0]{rows} * $_[0]{columns} + $_[0]{dutch_rows} * $_[0]{dutch_columns};
			$_[0]{spreads} = $_[0]{spread_rows} * $_[0]{spread_columns};
			$_[0]{pages} = $_[0]{spreads} * $_[0]{spread_size};

			$_[0]->layout_width(undef);
			$_[0]->layout_height(undef);
		} else {
			my ( $caller, undef, $line ) = caller;
			$openprint::log->debug("optimise $name from $caller : $line setting " . ( @_ > 1 ? 'set to ' . $_[1] : '' ) );
*{$name} = sub {
      @_ > 1 ? $_[0]->{$name} = $_[1]
        : $_[0]->{$name};
    };
		} # end if isin whatever fields
	} else {
		my ( $caller, undef, $line ) = caller;
		$openprint::log->debug("optimise $name from $caller : $line getting " );
#*{$name} = sub {
      #@_ > 1 ? $_[0]->{$name} = $_[1]
        #: $_[0]->{$name};
    #};
	} # end if @_ > 1
	return $_[0]{$name};
} # end sub AUTOLOAD

sub display {
	my ( $self, $prefix ) = @_;
if ( ! $$self{Paper} ) {
my ( $caller, undef, $line ) = caller;
	$openprint::log->error("No Paper in Imposition::sheet_width $caller: $line");
	return 0;
}
	my $Paper = $$self{Paper} ? $$self{Paper} : new openprint::Paper();
	#$openprint::log->debug(sprintf('Imp %s: %dx%dout %dx%d+%dx%d:%dout spreads:%dx%d=%d pages:%dx%d=%d %s on: %sx%s %.3fx%.3f %s I: %.3fx%.3f L:%.3fx%.3f %s %s minimum: %s', $prefix,
	#@$self{'quantity','start_imposition','columns','rows','dutch_columns','dutch_rows','imposition','spread_columns','spread_rows','spreads'},$self->page_columns(), $self->page_rows(), $self->pages(), $$self{runstyle}, $$self{Paper}->{start_width},$$self{Paper}->{start_height},$self->{Paper}->{width},$self->{Paper}->{height},$$self{Press}->{strid}, @$self{'image_width','image_height','layout_width','layout_height','image_orientation'},$self->grain_direction(), $$self{Paper}->minimum_order() ) );
my ( $caller, undef, $line ) = caller;
	$openprint::log->debug(sprintf('Imp %s: %d@ %dx%d+%dx%d:%dout%s pages:%dx%d=%d %s on: %sx%s->%sx%s=%dsq rotate: %d layout: %sx%s min: %s %s %s versions: %d from %s:%d', $prefix,
	@$self{'quantity','columns','rows','dutch_columns','dutch_rows','imposition'},$self->image_orientation_text(),@$self{'page_columns', 'page_rows', 'pages', 'runstyle'}, @$Paper{'start_width','start_height'}, $self->sheet_width(), $self->sheet_height(), $Paper->area(), $$self{rotate_sheet}, $self->layout_width(), $self->layout_height(), $$Paper{minimum_order}, $$self{Press}->{strid}, ( $$self{Price} ? $$self{Price} : '' ), $$self{version_qty}, $caller, $line ) );
} # end sub display

sub get {
	my ( $self, @fields ) = @_;
my ( $caller, undef, $line ) = caller;
$openprint::log->debug("someone using get() from $caller:$line");
	return map { $self->$_ } @fields;
} # end sub get

sub set {
	my $self = shift;
	my %hash = @_;
	foreach my $key ( keys %hash ) {
		$$self{$key} = $hash{$key} if ( sets::isin( $key, \@fields ) );
	} # end foreach
	$self->{imposition} = $$self{rows} * $$self{columns} + $$self{dutch_rows} * $$self{dutch_columns};
	
	$self->layout_width(undef);
	$self->layout_height(undef);

} # end sub set

sub copy {
	my $src = $_[0];
	my $copy = {};
	bless $copy, ref $src;
	@$copy{@fields} = @$src{@fields};
	$$copy{Paper} = $$copy{Paper}->clone() if $$copy{Paper};
	return $copy
} # end copy

sub Paper {
	if ( @_ > 1 ) {
		$_[0]{Paper} = $_[1];
	} 
	return $_[0]{Paper};
} # end sub Paper

# Passing in the Project helps us load the Paper by recommendation
sub load {
	my ( $self, $specs, $qty_index, $Project ) = @_;

	$$self{page_quantity} = $$self{quantity} = 1;
	$$self{specs} = $specs;
	$$self{Paper} = openprint::Paper::load_from_signature( $Project, $specs, $qty_index ) if ! $$self{Paper};
	if ( ! $$self{Press} ) {
		if ( ! $$specs{'ddmPress'.$qty_index} ) {
			#$openprint::log->error("No ddmPress for $qty_index for signature $$specs{SignatureIndex}");
#Carp::cluck("No press in Imposition::load");
		} else {
#Carp::cluck("Loading press in Imposition::load");
			$$self{Press} = openprint::Equipment->find_one( strid=>$$specs{'ddmPress'.$qty_index}, deleted=>0);
			if ( ! $$self{Press} ) {
				$openprint::log->error("load: No Press found for ddmPress$qty_index " . $$specs{'ddmPress'.$qty_index} );
        $$self{Press} = openprint::Equipment->find_one( strid=>$$specs{'ddmPress'.$qty_index}, deleted=>1);
			} # end if
		} # end if
		$$self{Press} = new openprint::Equipment() if ! $$self{Press};
	} # end if
	$$self{SignatureIndex} = $$specs{SignatureIndex};

	$$self{object_width} = $$specs{txtWidth};
	$$self{object_height} = $$specs{txtHeight};
	$$self{image_width} = $$specs{'txtImageWidth'.$qty_index};
	$$self{image_width} = $$self{object_width} if ! $$self{image_width};
	$$self{image_height} = $$specs{'txtImageHeight'.$qty_index};
	$$self{image_height} = $$self{object_height} if ! $$self{image_height};
  $$self{colour_bar_size} = $$self{Press}->specification('Colour Bar Size');
  $$self{colour_bar_orientation} = $$self{Press}->specification('Colour Bar Orientation');

	$$self{imposition} = $$specs{'txtImposition'.$qty_index};
	$$self{version_qty} = $$specs{'Versions'.$qty_index};
	$$self{start_columns} = $$self{columns} = $$specs{'hdnImpositionColumns'.$qty_index};
	$$self{start_rows} = $$self{rows} = $$specs{'hdnImpositionRows'.$qty_index};

	#$$self{columns} = $$self{imposition} / $$self{rows} if $$self{rows} and ! $$self{columns};
	#$$self{rows} = $$self{imposition} / $$self{columns} if $$self{columns} and ! $$self{rows};
	$$self{dutch_rows} = $$specs{'hdnImpositionDutchRows'.$qty_index} or 0;
	$$self{dutch_columns} = $$specs{'hdnImpositionDutchColumns'.$qty_index} or 0;
	$$self{cut_off} = $$specs{'CutOff'.$qty_index};
	if ( ( $$self{columns} * $$self{rows} ) + ( $$self{dutch_rows} * $$self{dutch_columns} ) != $$self{imposition} ) {
		$$self{imposition} = 0;
	}


	#'layout_width','layout_height',
#,'rotate_sheet',
	$$self{runstyle} = $$specs{'ddmRunStyle'.$qty_index};
	$$self{runstyle} = 'Sheet Work' if ! $$self{runstyle};
	$$self{image_orientation_text} = $$specs{'hdnImageOrientation'.$qty_index};
	if ( $$self{image_orientation_text} eq 'Vertical' ) {
		$$self{image_orientation} = Vertical;
	} else {
		$$self{image_orientation} = Horizontal;
	}
	$$self{grain_direction} = $$specs{'rdbGrainDirection'.$qty_index};
	$$self{bleed_size} = $$specs{'ddmBleedSize'.$qty_index};
	$$self{rotate_sheet} = $$specs{"RotateSheet$qty_index"};
	$$self{printing_type} = $$specs{"PrintingType$qty_index"};

	my $Paper = $$self{Paper};

	my ( $dutch_width, $dutch_height );

	if ( $$self{image_orientation} == Vertical ) {
		$$self{layout_width} = $$self{columns} * $$self{image_width};
		$$self{layout_height} = $$self{rows} * $$self{image_height};

		$dutch_width = $$self{dutch_columns} * $$self{image_height};
		$dutch_height = $$self{dutch_rows} * $$self{image_width};
	} else {
		$$self{layout_width} = $$self{columns} * $$self{image_height};
		$$self{layout_height} = $$self{rows} * $$self{image_width};
		$dutch_width = $$self{dutch_columns} * $$self{image_width};
		$dutch_height = $$self{dutch_rows} * $$self{image_height};
	} # end if

	if ( ! $$self{dutch_orientation} ) {
		if ( $$self{layout_width} + $dutch_width > ( $$specs{"RotateSheet$qty_index"} ? $$Paper{height} : $$Paper{width} ) ) {
			$$self{dutch_orientation} = 'height';
		} else {
			$$self{dutch_orientation} = 'width';
		} # end if
	} # end if
	if ( $$self{dutch_orientation} eq 'height' ) {
		$$self{layout_height} += $dutch_height;
		$$self{layout_width} = $dutch_width if $dutch_width > $$self{layout_width};
	} else {
		$$self{layout_width} += $dutch_width;
		$$self{layout_height} = $dutch_height if $dutch_height > $$self{layout_height};
	} # end if

	if ( ! $Project ) {
		my ( $caller, undef, $line ) = caller;
		$openprint::log->error("No Project passed to Imposition::load from $caller:$line");
		$Project = new openprint::Project( $$specs{ProjectIndex} );
	}
	$$self{Project} = $Project;

	if ( $$specs{txtSignatureType} ) {
		if ( ! $$specs{spine} ) {
			my $services = $Project->services();
			if ( $$services{''} and @{$$services{''}} ) {
				my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
				$$self{spine} = $$printing_specs{spine};
			}
			$$self{spine} = 'height' if ! $$self{spine};
		}
		$$self{pages} = $$specs{'PageQuantity'.$qty_index};
		$$self{spread_size} = $$specs{txtSpreadSize};
		$$self{spreads} = $$self{pages} / $$self{spread_size} if $$self{spread_size};
		$$self{spread_rows} = $$specs{'SpreadRows'.$qty_index};
		$$self{spread_columns} = $$specs{'SpreadCols'.$qty_index};
		if ( $$self{spine} eq 'width' ) {
			if ( $$self{image_orientation} == Vertical ) {
				$$self{page_rows} = $$self{spread_rows} * ($$self{spread_size}/2);
				$$self{page_columns} = $$self{spread_columns};
			} else {
				$$self{page_rows} = $$self{spread_rows};
				$$self{page_columns} = $$self{spread_columns} * ($$self{spread_size}/2);
			}
		} else {
			if ( $$self{image_orientation} == Vertical ) {
				$$self{page_rows} = $$self{spread_rows};
				$$self{page_columns} = $$self{spread_columns} * ($$self{spread_size} > 1 ? ($$self{spread_size}/2) : 1 );
			} else {
				$$self{page_rows} = $$self{spread_rows} * ($$self{spread_size} > 1 ? ($$self{spread_size}/2) : 1 );
				$$self{page_columns} = $$self{spread_columns};
			}
		}
	} else {
		# It's a brochure or something, so can't be cut.
		if ( $$self{image_orientation} == Vertical ) {
      #2024-06-19 switch to rounding to nearest quarter because of 717102
      # 2024-06-12 switch to ceil because of job 717036
      if ($$specs{txtFinalWidth}) {
        $$self{page_columns} = int($$specs{txtWidth} / $$specs{txtFinalWidth});
        my $remainder = ($$specs{txtWidth} / $$specs{txtFinalWidth}) - $$self{page_columns};
        $$self{page_columns} ++ if ($remainder > 0.25);
      }
      #$$self{page_columns} = Math::Round::nearest(1,$$specs{txtWidth} / $$specs{txtFinalWidth}) if $$specs{txtFinalWidth};
      #$$self{page_rows} = Math::Round::nearest(1,$$specs{txtHeight} / $$specs{txtFinalHeight}) if $$specs{txtFinalHeight};
      if ($$specs{txtFinalHeight}) {
        $$self{page_rows} = int($$specs{txtHeight} / $$specs{txtFinalHeight});
        my $remainder = ($$specs{txtHeight} / $$specs{txtFinalHeight}) - $$self{page_rows};
        $$self{page_rows} ++ if $remainder > 0.25;
      }
    } else {
      if ($$specs{txtFinalWidth}) {
        $$self{page_rows} = int($$specs{txtWidth} / $$specs{txtFinalWidth});
        my $remainder = ($$specs{txtWidth} / $$specs{txtFinalWidth}) - $$self{page_rows};
        $$self{page_rows} ++ if $remainder > 0.25;
      }
      if ($$specs{txtFinalHeight}) {
        $$self{page_columns} = int($$specs{txtHeight} / $$specs{txtFinalHeight});
        my $remainder = ($$specs{txtHeight} / $$specs{txtFinalHeight}) - $$self{page_columns};
        $$self{page_columns} ++ if $remainder > 0.25;
      }
		}
$openprint::log->debug("Got page layout $$self{page_columns} x $$self{page_rows}");

		#if ( 1 ) {
#20170125 have just gona back to this as it seems like the more correct thing to do
			#$$self{spreads} = $$self{spread_rows} * $$self{spread_columns};
			#$$self{spread_size} = 2;
		#} else {
			# This is the alternate way of doing it, this makes more sense, but it screws something up.  I can never remember what.
			$$self{spread_size} = $$self{page_rows} * $$self{page_columns} * 2;
			$$self{spread_rows} = 1;
			$$self{spread_columns} = 1;
			$$self{spreads} = 1;
		#} # end if
		$$self{pages} = $$self{spreads} * $$self{spread_size};
		$openprint::log->debug("spread_rows $$self{spread_rows} x $$self{spread_columns} = $$self{spread_size} spreads: $$self{spreads} pages: $$self{pages} ");
	} # end if
	$$self{page_width} = $$specs{txtFinalWidth};
	$$self{page_height} = $$specs{txtFinalHeight};
	$$self{sheet_width} = $$self{Paper}{width};
	$$self{sheet_height} = $$self{cut_off} ? $$self{cut_off} : $$self{Paper}{height};
	if ( ! exists $$specs{"RotateSheet$qty_index"} ) {
		if ( $$self{layout_width} > $$self{Paper}->width() or $$self{layout_height} > $$self{sheet_height} ) {
			$$self{rotate_sheet} = 1;
		} else {
			$$self{rotate_sheet} = 0;
		} # end if
	} else {
		$$self{rotate_sheet} = $$specs{"RotateSheet$qty_index"};
	} # end if
	$self->spine_direction();
$$self{impressions} = $$specs{"hdnImpressionQuantity$qty_index"};
$$self{net_sheets} = $$specs{"hdnNetSheetCount$qty_index"};
$$self{gross_sheets} = $$specs{"StockQuantity$qty_index"};
if (!$$self{net_sheets}) {
  $openprint::log->error("No net sheets for $qty_index: $$self{impressions} $$self{net_sheets}");
}
if (!$$self{gross_sheets}) {
  $openprint::log->error("No gross sheets for $qty_index: $$self{impressions} $$self{net_sheets}");
}
$self->display('After load') if DEBUG;
	return $self;
} # end sub load

sub load_used {
	my ( $self, $specs, $qty_index ) = @_;

	$$self{runstyle} = $$specs{ddmRunStyleUsed} ? $$specs{ddmRunStyleUsed} : $$specs{'ddmRunStyle'.$qty_index};
	$$self{image_orientation} = $$specs{hdnImageOrientationUsed} ? $$specs{hdnImageOrientationUsed} : $$specs{'hdnImageOrientation'.$qty_index};
	$$self{imposition} = $$specs{txtImpositionUsed} ? $$specs{txtImpositionUsed} : $$specs{'txtImposition'.$qty_index};
	$$self{rows} = $$specs{hdnImpositionRowsUsed} ? $$specs{hdnImpositionRowsUsed} : $$specs{'hdnImpositionRows'.$qty_index};
	$$self{columns} = $$specs{hdnImpositionColumnsUsed} ? $$specs{hdnImpositionColumnsUsed} : $$specs{'hdnImpositionColumns'.$qty_index};
	$$self{dutch_rows} = $$specs{hdnImpositionDutchRowsUsed} ? $$specs{hdnImpositionDutchRowsUsed} : $$specs{'hdnImpositionDutchRows'.$qty_index};
	$$self{dutch_columns} = $$specs{hdnImpositionDutchColumnsUsed} ? $$specs{hdnImpositionDutchColumnsUsed} : $$specs{'hdnImpositionDutchColumns'.$qty_index};
	$$self{dutch_orientation} = $$self{image_orientation} == Vertical ? Horizontal : Vertical;
	$$self{bleed_size} = $$specs{'ddmBleedSize'.$qty_index};
	if ( ! $$self{Press} ) {
		if ( $$specs{UsePress} ) {
			$$self{Press} = openprint::Equipment->find_one( strid=>$$specs{UsePress}, deleted=>[0,1] );
			if ( ! $$self{Press} ) {
				# This can happen when a press is deleted
				$openprint::log->debug("No Press found for UsePress $qty_index " . $$specs{UsePress} );
			} # end if
		} # end if
		if ( ! $$self{Press} ) {
			if ( ! $$specs{'ddmPress'.$qty_index} ) {
				#$openprint::log->error("No ddmPress for $qty_index");
			} else {
				$$self{Press} = openprint::Equipment->find_one( strid=>$$specs{'ddmPress'.$qty_index}, deleted=>[0,1]);
				if ( ! $$self{Press} ) {
					$openprint::log->error("No Press found for ddmPress$qty_index " . $$specs{'ddmPress'.$qty_index} );
				} # end if
			} # end if
		} # end if
		if ( ! $$self{Press} ) {
			$$self{Press} = new openprint::Equipment();
		} # end 
	} # end if
	$$self{Paper} = openprint::Paper::load_from_signature( undef, $specs, $qty_index ) if ! $$self{Paper};
} # end sub load_used

sub spread_rows {
	( my $self ) = @_;

	if ( @_ > 1 ) {
		$$self{spread_rows} = $_[1];
		if ( $$self{spine} eq 'width' ) {
      if ( $$self{image_orientation} == Vertical ) {
        $$self{page_rows} = $$self{spread_rows} * ($$self{spread_size}/2);
        $$self{page_columns} = $$self{spread_columns};
      } else {
        $$self{page_rows} = $$self{spread_rows};
        $$self{page_columns} = $$self{spread_columns} * ($$self{spread_size}/2);
      }
    } else {
      if ( $$self{image_orientation} == Vertical ) {
        $$self{page_rows} = $$self{spread_rows};
        $$self{page_columns} = $$self{spread_columns} * ($$self{spread_size}/2);
      } else {
        $$self{page_rows} = $$self{spread_rows} * ($$self{spread_size}/2);
        $$self{page_columns} = $$self{spread_columns};
      }
    }
		$$self{pages} = $$self{page_rows} * $$self{page_columns} * 2;
		$$self{spreads} = $$self{spread_rows} * $$self{spread_columns};
#$openprint::log->debug("resulting page_rows/cols $$self{page_columns} / $$self{page_rows}");
	}
	return $$self{spread_rows};
}
sub spread_columns {
	( my $self ) = @_;
  if ( @_ > 1 ) {
    $$self{spread_columns} = $_[1];
    if ( $$self{spine} eq 'width'     ) {
      if ( $$self{image_orientation} == Vertical ) {
        $$self{page_rows} = $$self{spread_rows} * ($$self{spread_size}/2);
        $$self{page_columns} = $$self{spread_columns};
      } else {
        $$self{page_rows} = $$self{spread_rows};
        $$self{page_columns} = $$self{spread_columns} * ($$self{spread_size}/2);
      }
    } else {
      if ( $$self{image_orientation} == Vertical ) {
        $$self{page_rows} = $$self{spread_rows};
        $$self{page_columns} = $$self{spread_columns} * ($$self{spread_size}/2);
      } else {
        $$self{page_rows} = $$self{spread_rows} * ($$self{spread_size}/2);
        $$self{page_columns} = $$self{spread_columns};
      }
    }
		$$self{pages} = $$self{page_rows} * $$self{page_columns} * 2;
		$$self{spreads} = $$self{spread_rows} * $$self{spread_columns};
#$openprint::log->debug("resulting page_rows/cols $$self{page_columns} / $$self{page_rows}");
  }
  return $_[0]{spread_columns};
}


sub save {
	my ( $self, $specs, $qty_index ) = @_;
	$$specs{'txtImposition'.$qty_index} = $$self{imposition};
	$$specs{'Versions'.$qty_index} = $$self{version_qty};
	$$specs{'hdnImpositionRows'.$qty_index} = $$self{rows};
	$$specs{'hdnImpositionColumns'.$qty_index} = $$self{columns};
	$$specs{'hdnImpositionDutchRows'.$qty_index} = $$self{dutch_rows} ? $$self{dutch_rows} : '';
	$$specs{'hdnImpositionDutchColumns'.$qty_index} = $$self{dutch_columns} ? $$self{dutch_columns} : '';
	$$specs{'hdnImageOrientation'.$qty_index} = $$self{image_orientation} == Vertical ? 'Vertical' : 'Horizontal';
	$$specs{'page_columns'.$qty_index} = $self->page_columns();
	$$specs{'page_rows'.$qty_index} = $self->page_rows();
	$$specs{'SpreadRows'.$qty_index} = $$self{spread_rows};
	$$specs{'SpreadCols'.$qty_index} = $$self{spread_columns};
	$$specs{txtSpreadSize} = $$self{spread_size} if $$self{spread_size};
	$$specs{'ddmRunStyle'.$qty_index} = $$self{runstyle};
	$$specs{'txtImageWidth'.$qty_index} = $$self{image_width};
	$$specs{'txtImageHeight'.$qty_index} = $$self{image_height};
	$$specs{'txtLayoutWidth'.$qty_index} = $self->layout_width();
	$$specs{'txtLayoutHeight'.$qty_index} = $self->layout_height();
	$$specs{'rdbGrainDirection'.$qty_index} = $self->grain_direction() if ! $$specs{'chkOverrideGrainDirection'.$qty_index};
	$$specs{'ddmBleedSize'.$qty_index} = $$self{bleed_size};
	$$specs{'PrintingType'.$qty_index} = $$self{printing_type};
	my $Paper = $self->Paper();
	if ( $Paper and ($$Paper{type} eq 'Roll') and $$Paper{height} ) {
		$$specs{'CutOff'.$qty_index} = $$Paper{height};
	} else {
		$$specs{'CutOff'.$qty_index} = '';
	} # end if
	$$specs{'RotateSheet'.$qty_index} = $$self{rotate_sheet};
} # end sub Save

sub used_width {
	my $self = shift;
	my $width = $$self{layout_width} + $$self{gutters} + $$self{cropmark_left} + $$self{cropmark_right} + ( $$self{colour_bar_orientation} eq 'Length' ? $$self{colour_bar_size} : 0 );
  $openprint::log->debug("Setting used_width ($width) = using layout:$$self{layout_width} + gutters:$$self{gutters} + cropleft:$$self{cropmark_left} + crop_right:$$self{cropmark_right} + cb: ( $$self{colour_bar_orientation} eq 'Length' ? $$self{colour_bar_size} : 0 )") if DEBUG;
	return $width;
}
sub used_height {
  my $self = shift;
	my $height = $$self{layout_height} + $$self{grip} + $$self{cropmark_top} + $$self{cropmark_bottom} + ( $$self{colour_bar_orientation} eq 'Width' ? $$self{colour_bar_size} : 0 );
  return $height;
} # end sub used_height

sub object_area {
	$_[0]{object_area} = $_[1] if @_ > 1;
	if ( ! exists $_[0]{object_area} ) {
		$_[0]{object_area} = $_[0]{object_width} * $_[0]{object_height} * $_[0]{imposition} * $_[0]{spreads};
	} 
	return $_[0]{object_area};
}
sub layout_area {
	my $self = shift;
	return $$self{layout_width} * $$self{layout_height};
}

sub sheet_width {
	my $self = shift;

	$$self{start_columns} = $$self{columns} if ! $$self{start_columns};
	$$self{start_rows} = $$self{rows} if ! $$self{start_rows};

	if ( ! $$self{Paper} ) {
		my ( $caller, undef, $line ) = caller;
		$openprint::log->error("No Paper in Imposition::sheet_width $caller: $line");
		return 0;
	}
	if ( $$self{rotate_sheet} ) {
		$$self{Paper}->height( @_ ) if @_;
		if ( $$self{start_columns} and $$self{columns} and $$self{start_columns} != $$self{columns} ) {
			return $$self{sheet_width} = Math::Round::nearest( 0.0001, $$self{Paper}{height} / ( $$self{start_columns} / $$self{columns} ) );
		} else {
			return $$self{sheet_width} = $$self{Paper}->height();
		} # end if
	} else {
		$$self{Paper}->width( @_ ) if @_;
		if ( $$self{start_columns} and $$self{columns} and $$self{start_columns} != $$self{columns} ) {
			return $$self{sheet_width} = Math::Round::nearest( 0.0001, $$self{Paper}{width} / ( $$self{start_columns} / $$self{columns} ) );
		} else {
			return $$self{sheet_width} = $$self{Paper}{width};
		} # end if
	} # end if
} # end sub sheet_width

sub sheet_height {
	my $self = shift;
	$$self{start_columns} = $$self{columns} if ! $$self{start_columns};
	$$self{start_rows} = $$self{rows} if ! $$self{start_rows};

	if ( ! $$self{Paper} ) {
		my ( $caller, undef, $line ) = caller;
		$openprint::log->error("No Paper in Imposition::sheet_height from $caller:$line");
		return 0;
	}
	if ( $$self{rotate_sheet} ) {
		# I don't like the following line
		$$self{Paper}->width( @_ ) if @_;

		if ( $$self{start_rows} and $$self{rows} and $$self{start_rows} != $$self{rows} ) {
			return $$self{sheet_height} = Math::Round::nearest( 0.0001, $$self{Paper}{width} / ( $$self{start_rows} / $$self{rows} ) );
		} else {
			return $$self{sheet_height} = $$self{Paper}{width};
		} # end if
	} else {
		$$self{Paper}->height( @_ ) if @_;
		if ( ! $$self{Paper}{height} ) {
			if ( $$self{start_rows} and $$self{rows} and $$self{start_rows} != $$self{rows} ) {
        return $$self{sheet_height} = Math::Round::nearest( 0.0001, $$self{cut_off} / ( $$self{start_rows} / $$self{rows} ) );
			} else {
				return $$self{sheet_height} = $$self{cut_off};
			} # end if
		} else {
			if ( $$self{start_rows} and $$self{rows} and $$self{start_rows} != $$self{rows} ) {
				return $$self{sheet_height} = Math::Round::nearest( 0.0001, $$self{Paper}{height} / ( $$self{start_rows} / $$self{rows} ) );
			} else {
				return $$self{sheet_height} = $$self{Paper}{height};
			} 
		} # end if
	} # end if
} # end sub sheet_height

sub sheet_area {
	return $_[0]->sheet_width() * $_[0]->sheet_height();
} # end sub sheet_area

if ( ! DEBUG_PERFORMANCE ) {
sub pages {
	if ( @_ > 1 ) {
		$_[0]{pages} = $_[1];
	} # end if
	return $_[0]{pages};
}
sub page_columns {
	if ( @_ > 1 ) {
		$_[0]{page_columns} = $_[1];
	} # end if
	return $_[0]{page_columns};
}
sub page_rows {
	if ( @_ > 1 ) {
		$_[0]{page_rows} = $_[1];
	} # end if
	return $_[0]{page_rows};
}
}

# Is in relation to the image.
sub grain_direction {
	my $self = $_[0];
	if ( @_ > 1 ) {
		$$self{grain_direction} = $_[1];
	} # end if
	if ( ! $$self{grain_direction} ) {
		if ( ! defined $$self{rotate_sheet} ) {
			my ( $caller, undef, $line ) = caller;
			$openprint::log->error("grain_direction called from $caller:$line without defined rotate_sheet");
		}
		if ( $$self{rotate_sheet} ) {
			if ( $$self{image_orientation} == Vertical ) {
				$$self{grain_direction} = $self->Paper()->grain_direction() eq 'width' ? 'height' : 'width';
			} else {
				$$self{grain_direction} = $self->Paper()->grain_direction();
			} # end if
		} else {
			if ( $$self{image_orientation} == Vertical ) {
				$$self{grain_direction} = $self->Paper()->grain_direction();
			} else {
				$$self{grain_direction} = $self->Paper()->grain_direction() eq 'width' ? 'height' : 'width';
			} # end if
		} # end if
#$self->display("Setting grain direction rotate($$self{rotate_sheet}) orientation($Orientations{$$self{image_orientation}}) paper grain:" . $self->Paper()->grain_direction() . " got $$self{grain_direction}" );
	} # end if
	return $$self{grain_direction};
} # end sub grain_direction

sub equals {
	my ( $i1, $i2 ) = @_;
	return 0 if $i1->Press()->id() != $i2->Press()->id();
	return 0 if $$i1{runstyle} ne $$i2{runstyle};
	return 0 if $$i1{imposition} != $$i2{imposition};
	return 0 if $$i1{columns} != $$i2{columns};
	return 0 if $$i1{spreads} != $$i2{spreads};
	return 0 if $$i1{Paper}->width() != $$i2{Paper}->width();
	return 0 if $$i1{Paper}->height() != $$i2{Paper}->height();
	return 1;
}

sub to_string {
	my $self = $_[0];
  $$self{to_string} = $_[1] if @_ > 1;
	if ( ! $_[0]{to_string} ) {
		if ( $_[0]{Paper} ) {
			my $Paper = $_[0]{Paper};
			$_[0]{to_string} = sprintf('%s %d@ %dx%d+%dx%d=%dout %s %dx%d=%dpages %sx%s on %sx%s%s->%sx%s %s', ( $_[0]{Press} ? $_[0]{Press}{strid}: 'unknown equipment' ),
					@$self{'quantity','columns','rows','dutch_columns','dutch_rows','imposition','runstyle'},$_[0]->page_columns(), $_[0]->page_rows(),@$self{'pages','page_width','page_height'},
					@$Paper{'start_width','start_height', 'type','width','height'},
					$_[0]->image_orientation_text() );
		} else {
			if ( $_[0]{quantity} > 1 ) {
			$_[0]{to_string} = sprintf('%s %d @ %dx%d+%dx%d=%dout %s %dx%d=%dpages %s spine %s', ( $_[0]{Press} ? $_[0]{Press}->strid() : 'unknown equipment' ), $_[0]->get('quantity','columns','rows','dutch_columns','dutch_rows','imposition','runstyle','page_columns','page_rows','pages', 'sheet_width','sheet_height'), 
					@Orientations{@$self{'image_orientation_text','spine_direction'}} );
			} else {
			$_[0]{to_string} = sprintf('%s %dx%d+%dx%d=%dout %s %dx%d=%dpages %s spine %s', ( $_[0]{Press} ? $_[0]{Press}->strid() : 'unknown equipment' ), $_[0]->get('columns','rows','dutch_columns','dutch_rows','imposition','runstyle','page_columns','page_rows','pages', 'sheet_width','sheet_height'),
					@Orientations{@$self{'image_orientation_text','spine_direction'}} );
			}
		} # end if
	}
	return $_[0]{to_string};
} # end sub to_string

sub bleed_size {
	$_[0]{bleed_size} = $_[1] if @_ > 1;
	return $_[0]{bleed_size};
} # end sub bleed_size

sub runstyle {
	$_[0]{runstyle} = $_[1] if @_ > 1;
	return $_[0]{runstyle};
} # end sub runstyle

sub rs {
  return $ShortStyles{$_[0]{runstyle}};
}

sub quantity {
	$_[0]{quantity} = $_[1] if @_ > 1;
	return $_[0]{quantity};
} # end subquantity

sub colours {
  my $self = shift;
  my $specs = $self->specs();
  $$self{coloursSideOne} = [openprint::Estimating::Printing::get_colours( $specs, 'SideOne' )] if !$$self{coloursSideOne};
  $$self{coloursSideTwo} = [openprint::Estimating::Printing::get_colours( $specs, 'SideTwo' )] if !$$self{coloursSideTwo};
  my $side = shift;
  return @{$$self{'colours'.$side}};
}

sub sides {
	$_[0]{sides} = $_[1] if @_ > 1;
	if ( ! $_[0]{sides} ) {

		my $specs = $_[0]->specs();
		my @side_one = openprint::Estimating::Printing::get_colours( $specs, 'SideOne' );
		my @side_two = openprint::Estimating::Printing::get_colours( $specs, 'SideTwo' );

		my $CoatingsCategory = openprint::ServiceCategory->find_one( name => 'Coating' );
		my %coatings = map { $_->name(), 1 } $CoatingsCategory->Services() if $CoatingsCategory;

# Split out colours vs coatings, but Varnish is not a coating like AQ

		my @side_one_colours;
		my @side_one_coatings;
		foreach my $c ( @side_one ) {
			if ( $coatings{$$c{name}} and ! ( $$c{name} =~ /Varnish/i ) ) {
#push @side_one_coatings, $c;
			} else {
				push @side_one_colours, $c;
			} # end if
		} # end foreach
		my @side_two_colours = ();
		my @side_two_coatings = ();
		foreach my $c ( @side_two ) {
			if ( $coatings{$$c{name}} and ! ( $$c{name} =~ /Varnish/i ) ) {
#push @side_two_coatings, $c;
			} else {
				push @side_two_colours, $c;
			} # end if
		} # end foreach

		if ( @side_one_colours > 0 ) {
			$_[0]{sides} += 1;
		} 
		if ( @side_two_colours > 0 ) {
			$_[0]{sides} += 1;
		} # end if
	} # end if ! $_[0]s{dies}
	return $_[0]{sides};
} # end sub sides

sub Equipment {
	if ( @_ > 1 ) {
		$_[0]{Equipment} = $_[1];
		$_[0]{equipment_id} = $_[0]{Equipment}{id};
	}
	if ( ! $_[0]{Equipment} ) {
		my ( $caller, undef, $line ) = caller;
		$_[0]{Equipment} = new openprint::Equipment();
		$openprint::log->error("No Equipment in Imposition:Equipment from $caller : $line");
	} # end if
	return $_[0]{Equipment};
} # end sub Equipment

sub Press { 
	$_[0]{Press} = $_[1] if @_ > 1;
	if ( ! $_[0]{Press} ) {
		$openprint::log->error('No Press in Imposition:Press');
		$_[0]{Press} = new openprint::Equipment();
	} # end if
	return $_[0]{Press};
} # end sub Press

sub paper_width {
	return $_[0]->Paper()->width();
}

sub paper_height {
	return $_[0]->Paper()->height();
}

sub paper_type {
	return $_[0]->Paper()->type();
}

sub DESTROY {
}

sub dump {
	$openprint::log->debug( Data::Dumper::Dumper( $_[0] ) );
}

sub image_orientation_text {
	if ( ! $_[0]{image_orientation_text} ) {
		$_[0]{image_orientation_text} = $Orientations{$_[0]{image_orientation}};
	};
	return $_[0]{image_orientation_text};
}

sub spine_direction {
	if ( ! defined $_[0]{spine_direction} ) {
#$openprint::log->debug("Setting spine direction uusing $_[0]{spine}");
		if ( $_[0]{spine} eq 'height' ) {
			$_[0]{spine_direction} = $_[0]{image_orientation};
		} elsif ( $_[0]{spine} eq 'width' ) {
			$_[0]{spine_direction} = $_[0]{image_orientation} == Vertical ? Horizontal : Vertical;
		} else {
			$_[0]{spine_direction} = $_[0]{image_orientation};
		}
	} 
	return $_[0]{spine_direction};
}

sub to_svg {
	my ( $self ) = @_;
	return if ! $$self{imposition};

	# So let's assume that we might want to print this on an 8.5x11 sheet of paper. The source dimensions might be 28x40"

	my $target_width = $self->sheet_width()+2; # inches, I think the idea is 40" sheet plus some margin
	my $target_height = $self->sheet_height()+2; # inches;

	my $margin = 1; #inch

	my $svg = SVG->new(
      width      => '100%',
      height     => '100%',
      viewBox    => join(q{ } => 0, 0, $target_width, $target_height), # In local units (inches)
      -nocredits => 1,
      -standalone => 'no',
      preserveAspectRation => 'xMidYMid meet',  # Keep relative size.
      class=>'Imposition',
      title=>join(' x ',@$self{'columns','rows'} ).($$self{dutch_columns}?' + '.join(' x ', @$self{'dutch_columns','dutch_rows'}):''),
      );
  #my $css = ssi::hash_link('/base_css/imposition.css');
  #my $pi = $svg->style(type=>'text/css', -href=>$css);

  my $defs = $svg->defs();
  add_drop_shadow_define($defs);
  add_colour_bar_define($defs);
  add_diagonal_hatch_define($defs);
# Draw a white backgound as transparency prints as black on many browsers.
  $svg->rect(
      id     => 'background',
      class  => 'background',
      x      => 0,     y      => 0,
      width => $target_width,
      height => $target_height,
      );

	my $sheet_width = $self->sheet_width();
	my $sheet_height = $self->sheet_height();

  my $translate = join(q{, }, (($target_width - $sheet_width) / 2), (($target_height - $sheet_height) / 2));

# Translate the canvas so padding doesn't effect our co-ordinate system.
  my $canvas = $svg->g(transform => "translate($translate)");
  my $sheet = add_sheet($canvas, $self);

	return $svg->xmlify();
}

sub add_sheet {
  my ($canvas, $self) = @_;
# Draw the sheet dimensions with a drop shadow effect.
  my $sheet = $canvas->rect(
      id     => 'sheet',
      class  => 'sheet',
      x      => 0,
      y      => 0,
      width  => $self->sheet_width(),
      height => $self->sheet_height(),
      filter => 'url(#dropShadow)',
      );

  my $grip = $$self{grip};
  if ($grip) {
    $grip /= 2 if ($$self{runstyle} eq 'Work & Tumble' or $$self{runstyle} eq 'Perfecting');
    $canvas->rect(class=>'grip', id=>'grip', x=>0, y=>0, width=>$$self{sheet_width}, height=>$grip, fill=>'url(#diagonalHatch)');
  }
  $canvas = $canvas->g(transform => "translate(0, $grip)");

  if ($$self{colour_bar_size}) {
    my $colour_bar_height = $$self{colour_bar_size};
    my $colour_bar = $canvas->rect( class=>'colourbar', x=>0, y=>$grip, width=>$$self{sheet_width}, height=>$colour_bar_height, fill=>'url(#processColours)');
    if ($$self{runstyle} eq 'Work & Tumble') {
      $colour_bar->setAttributes({x => 0, y => $$self{sheet_height} - $grip*2});
    } else {
      # We've decreased the availible space.
      $canvas = $canvas->g(transform => "translate(0, $colour_bar_height)");
    }
  }

  my $x = ($self->sheet_width() - 2*$$self{gutter} - $self->layout_width()) / 2;
  $x = 0 if $x < 0;
  my $y = ($self->sheet_height() - $self->layout_height()) / 2;
  $y = 0 if $y < 0;

# Centre the imposition on the printable page area.
  my $group = $canvas->group(transform => "translate($x, $y)");
  if ($$self{runstyle} eq 'Work & Turn') {
    my $half = $self->copy();
    $half->columns($$half{columns}/2);
    $half->dutch_columns($$half{dutch_columns}/2);
    add_imposition($group, $half);
# just grab the first half of the image in a new viewport and mirror.
    my $dim = $self->layout_width() / 2;

    $group = $group->g(transform=>'translate('.$dim.', 0)');
        #width  => $dim,
        #height => $self->layout_height(),
        #overflow => 'hidden',
        #x => $self->layout_width(),
        #y => 0,
        ##transform => "translate($dim, 0) scale(-1,1)",
        ##transform => "rotate(180 ".($dim/2).' '.($self->layout_height()/2).')',
        #);
    my $impo = add_imposition($group, $half);
    $impo->setAttributes({transform=>'rotate(180 '.($dim/2).' '.($self->layout_height()/2).')'});

    # Draw a vertical centre line (y-axis).
    my $centre = $self->sheet_width() / 2 - $$self{gutter};
    $canvas->line( id => 'centreline', x1 => $centre,   x2 => $centre, y1 => - 2, y2 => $self->sheet_height() + 2);

  } elsif ($$self{runstyle} eq 'Work & Tumble') {
# just grab the first half of the image in a new viewport and mirror.
    my $half = $self->copy();
    $half->rows($$half{rows}/2);
    $half->dutch_rows($$half{dutch_rows}/2);
    add_imposition($group, $half);

    my $mirror = $group->g(
        #width  => $self->layout_width(),
        #height => $dim,
        #overflow => 'hidden',
        #x => 0,
        #y => $dim,
  #transform => "translate(0, $dim) scale(1,-1)"
        #transform=>'translate(0, '.($self->layout_height()/2).')',
        );
    my $impo = add_imposition($mirror, $half);
    $impo->setAttributes({transform=>'rotate(180 '.($self->layout_width()/2).' '.($self->layout_height()/2).')'});
# Draw a horizontal centre line (x-axis).
    my $centre = $self->sheet_height() / 2;
    $canvas->line(
        id => 'centreline',
        x1 => - 4, x2 => $self->sheet_width() + 4,
        y1 => $centre,   y2 => $centre,
        );

  } else {
    add_imposition($group, $self);
  }

  return $sheet;
} # end sub add_sheet

sub id_string {
  my $self = shift;
  my $stock = $self->Paper();
  return sprintf('%s%dx%dd%dx%don%dx%d', $self->rs(), @$self{'columns','rows','dutch_columns','dutch_rows'}, @$stock{'width','height'});
}
sub add_imposition {
  my ($define, $self) = @_;

  $openprint::log->error($self->to_string());
  my $canvas = $define->group();

  my $image_width = ($$self{image_orientation} == Vertical ? $$self{image_width} : $$self{image_height});
  my $image_height = ($$self{image_orientation} == Vertical ? $$self{image_height} : $$self{image_width});
  my $object_width = ($$self{image_orientation} == Vertical ? $$self{image_width} : $$self{image_height});
  my $object_height = ($$self{image_orientation} == Vertical ? $$self{image_height} : $$self{image_width});
  #my $object_width = ($$self{image_orientation} == Vertical ? $$self{object_width} : $$self{object_height});
  #my $object_height = ($$self{image_orientation} == Vertical ? $$self{object_height} : $$self{object_width});
	foreach my $column ( 1 .. $$self{columns} ) {
		foreach my $row ( 1 .. $$self{rows} ) {
			my $image_x = (($column-1)*$image_width) + $$self{gutter};# + ($column*2);
			my $image_y = (($row-1)*$image_height);# + ($row*2);
			my $object = $canvas->rect(class=>'image', x=>$image_x, y=>$image_y,
          width=>$object_width, height=>$object_height,
          fill=>'rgb(255,255,255)');
			if ( $self->page_columns() > 1 ) {
				my $page_width = $object_width / $self->page_columns();
				my $page_height = $object_height / $self->page_rows();
        my $colour = ( $$self{spine} eq 'height' and $$self{image_orientation} == Vertical ) ? 'red' : 'black';

				foreach my $page_column ( 2 .. $self->page_columns() ) {
					my $page_x1 = $image_x + ($page_column-1)*$page_width;
					my $page_x2 = $image_x + ($page_column-1)*$page_width;

					my $page_y1 = $image_y;
					my $page_y2 = $image_y + ($page_height * $self->page_rows());

# This is the linees between pages, One of these will be the spine.
					$canvas->line(x1=>$page_x1, y1=>$page_y1, x2=>$page_x2, y2=>$page_y2, stroke=>$colour, class=>'foldline');
				} # end foreach page column
			} # draw pages

	  	if ( $self->page_rows() > 1 ) {
				my $colour = ( $$self{spine} eq 'height' and $$self{image_orientation} == Horizontal ) ? 'red' : 'black';
				my $page_width = $image_width / $self->page_columns();
				my $page_height = $image_height / $self->page_rows();
				foreach my $page_row ( 2 .. $self->page_rows() ) {
					my $page_x1 = $image_x;
					my $page_x2 = $image_x + ($page_width * $self->page_columns);

					my $page_y1 = $image_y + ($page_row-1)*$page_height;
					my $page_y2 = $image_y + ($page_row-1)*$page_height;
					$canvas->line(x1=>$page_x1, y1=>$page_y1, x2=>$page_x2, y2=>$page_y2, stroke=>$colour, class=>'foldline');
				}
			}
			
		} # end foreach row
	} # end foreach column

  if ($$self{dutch_columns}) {
    my $sheet_x = 0;
    my $sheet_y = 0;
    if ($$self{sheet_width} - ($$self{columns} * $image_width) > $image_height*$$self{dutch_columns}) {
      # can fit beside
      $sheet_x += ($$self{columns} * $image_width);
    } else {
      $sheet_y += ($$self{rows} * $image_height);
    }
    my $image_width = ($$self{image_orientation} == Vertical ? $$self{image_height} : $$self{image_width});
    my $image_height = ($$self{image_orientation} == Vertical ? $$self{image_width} : $$self{image_height});
    my $object_width = ($$self{image_orientation} == Vertical ? $$self{object_height} : $$self{object_width});
    my $object_height = ($$self{image_orientation} == Vertical ? $$self{object_width} : $$self{object_height});
    foreach my $column ( 1 .. $$self{dutch_columns} ) {
      foreach my $row ( 1 .. $$self{dutch_rows} ) {
        my $image_x = $sheet_x + (($column-1)*$image_width);# + ($column*2);
        my $image_y = $sheet_y + (($row-1)*$image_height);# + ($row*2);
        $canvas->rect( class=>'image', x=>$image_x, y=>$image_y,
            width=>$object_width, height=>$object_height,
            fill=>'rgb(255,255,255);');

        if ( $self->page_columns() > 1 ) {
          my $page_width = $object_width / $self->page_columns();
          my $page_height = $object_height / $self->page_rows();
          my $colour = ( $$self{spine} eq 'height' and $$self{image_orientation} == Vertical ) ? 'red' : 'black';

          foreach my $page_column ( 2 .. $self->page_columns() ) {
            my $page_x1 = $image_x + ($page_column-1)*$page_width;
            my $page_x2 = $image_x + ($page_column-1)*$page_width;

            my $page_y1 = $image_y;
  # + $page_height;
            my $page_y2 = $image_y + ($page_height * $self->page_rows());

  # This is the linees between pages, One of these will be the spine.
            $canvas->line(class=>'foldline', x1=>$page_x1, y1=>$page_y1, x2=>$page_x2, y2=>$page_y2, stroke=>$colour);
          }
        }

        if ( $self->page_rows() > 1 ) {
          my $colour = ( $$self{spine} eq 'height' and $$self{image_orientation} == Horizontal ) ? 'red' : 'black';
          my $page_width = $object_width / $self->page_columns();
          my $page_height = $object_height / $self->page_rows();
          foreach my $page_row ( 2 .. $self->page_rows() ) {
            my $page_x1 = $image_x;
            my $page_x2 = $image_x + ($page_width * $self->page_columns);

            my $page_y1 = $image_y + ($page_row-1)*$page_height;
            my $page_y2 = $image_y + ($page_row-1)*$page_height;
            $canvas->line(class=>'foldline', x1=>$page_x1, y1=>$page_y1, x2=>$page_x2, y2=>$page_y2, stroke=>$colour);
          }
        }

      } # end foreach row
    } # end foreach column
  } # end if has dutch
  return $canvas;
} # end add_imposition

# Add a drop shadow filter effect to the document.
sub add_drop_shadow_define {
  my ($define) = @_;

  my $filter = $define->filter(id => 'dropShadow', x => 0, y => 0);

# Blur the alpha channel.
  $filter->fe( -type  => 'GaussianBlur', in     => 'SourceAlpha', result => 'blur', stdDeviation=> 0.5,);

# Offset the blur an 1/8" to the bottom-right.
  $filter->fe( -type  => 'Offset', in     => 'blur', result => 'shadow', dx     => 0.125, dy     => 0.125,);

# Merge the shadow under the original source graphic.
  my $merge = $filter->fe(-type  => 'Merge');
  $merge->fe(-type => 'MergeNode', in => 'shadow',);
  $merge->fe(-type => 'MergeNode', in => 'SourceGraphic',);

  return $filter;
}
sub add_colour_bar_define {
  my ($defines) = @_;
  my $processColours = $defines->pattern( id=>'processColours', patternUnits=>'userSpaceOnUse', viewbox=>'0 0 1.5 2', x=>0, y=>0, width=>1.5, height=>2);

# Draw a box for each of the process colours.
  my $width = 0.25;
  my $offset = $width;
  for my $colour (qw(cyan yellow magenta black)) {
    $processColours->rect(width=>$width, y=>0, height=>'100%', x=>$offset, fill=>$colour);
    $offset += $width;
  }
  return $processColours;
}
sub add_diagonal_hatch_define {
  my ($defines) = @_;

  my $pattern = $defines->pattern( id=>'diagonalHatch', patternUnits=>'userSpaceOnUse', width=>4, height=>4);
  $pattern->path( d=>"M-1,1 l2,-2 M0,4 l4,-4 M3,5 l2,-2", style=>'stroke:black; stroke-width:1');
  return $pattern;
}

sub landscape_portrait_square {
	if ( $_[0]{image_width} < $_[0]{image_height} ) {
		return 'portrait';
	} elsif ( $_[0]{image_width} > $_[0]{image_height} ) {
		return 'landscape';
	} else {
		return 'square';
	}
}

1;
__END__
