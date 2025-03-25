use strict;
package openprint::imposition;
use Carp;
use Data::Dumper;

use openprint::Imposition;

use constant DEBUG => 0;
use constant DEBUG_DUTCH => 0;
use constant DEBUG_CONVERT => 0;

# The various way we can group spreads
use vars qw( %blocks );
%blocks = (
		1	=>	[ [1,1] ],
		2	=>	[ [1,2], [2,1] ],
		3	=>	[ [1,3], [3,1] ],
		4	=>	[ [1,4], [4,1], [2,2] ],
		5	=>	[ [1,5], [5,1] ],
		6	=>	[ [2,3], [3,2], [1,6], [6,1] ],
		7	=>	[ [7,1], [1,7] ],
		8	=>	[ [2,4], [4,2] ],
		9	=>	[ [3,3] ],
		10	=>	[ [5,2], [2,5], ],
		12	=>	[ [3,4], [4,3], [6,2], [2,6] ],
		14	=>	[ [7,2], [2,7] ],
		15	=>	[ [3,5],[5,3] ],
		16	=>	[ [4,4], [2,8],[8,2] ],
		18	=>	[ [3,6],[6,3] ],
		20	=>	[ [4,5], [5,4] ],
		21	=>	[ [3,7],[7,3] ],
		#22	=>	[ [3,8],[8,3] ],
		24	=>	[ [6,4],[4,6],[2,12],[12,2],[3,8],[8,3] ],
		32	=>	[ [8,4],[4,8],[2,16],[16,2] ],
		36	=>	[ [6,6] ],
		40	=>	[ [8,5],[5,8], [10,4], [4,10] ],
		46	=>	[ [13,2], [2,13] ],
		48	=>	[ [8,6],[6,8] ],
		64	=>	[ [8,8],[8,8] ],

		);

sub fit {
	my ( $object_width, $object_height, $space_width, $space_height ) = @_;
	my $imp1 = new openprint::Imposition;
	$$imp1{image_orientation} = openprint::Imposition::Vertical;
	my $imp2 = new openprint::Imposition;
	$$imp2{image_orientation} = openprint::Imposition::Horizontal;
	calc_setup( $imp1, $object_width, $object_height, $space_width, $space_height );
	calc_setup( $imp2, $object_height, $object_width, $space_width, $space_height );
	return $$imp1{imposition} > $$imp2{imposition} ? $imp1 : $imp2;
} # end sub fit

sub calc_setup {
# this function calculates how many 'objects' will fit in the given 'space' based on length & width.
# this code was part of the calc_setup_object function in the javascript code, but we split it out cause it
# will be useful in other spots.
	my ( $setup, $object_width, $object_height, $space_width, $space_height ) = @_;

	# This test used to be for > 1 but we had a labels job that was .75...
	my $cols = $object_width > 0 ? int(($space_width / $object_width)) : 0;
  $openprint::log->debug("calc_setup: space width $space_width / object width $object_width = $cols cols") if DEBUG;
	my $rows = $object_height > 0 ? int(($space_height / $object_height)) : 0;
  $openprint::log->debug("calc_setup: space height $space_height / object height $object_height = $rows rows") if DEBUG;

	$setup->set(imposition=>$rows * $cols, rows=>$rows, columns=>$cols );
} # end sub calc_setup

sub calc_dutch {
	my ( $setup, $space_width, $space_height, $specs ) = @_;
$setup->display("Trying dutch from:") if DEBUG_DUTCH;
	my ( $image_width, $image_height );
	if ( $$setup{image_orientation} == openprint::Imposition::Vertical ) {
		( $image_width, $image_height ) = @$setup{'image_width','image_height'};
	} else {
		( $image_width, $image_height ) = @$setup{'image_height','image_width'};
	} # end if

	my @dutch_imps;
	my $previous_dutch_imp = 0;
	# So now we have a non-dutch imp, now
	foreach my $col_delta ( 1 .. int ( $$setup{columns} / 2 ) ) {

		my $col_space = $space_width - ( ($$setup{columns} -$col_delta) * $image_width );
		my $dutch_cols = int($col_space / $image_height);
		my $dutch_rows = int($space_height / $image_width);

		my $dutch_imp = $setup->copy();
		$dutch_imp->set(
				dutch_columns	=>	$dutch_cols,
				dutch_rows		=>	$dutch_rows,
				columns				=>	$$setup{columns} - $col_delta,
				start_columns =>	$$setup{columns} - $col_delta,
				#imposition		=>	($$setup{columns} - $col_delta) * $$setup{rows} + ( $dutch_cols * $dutch_rows ),
				dutch_orientation	=>	'width',
				);
		if ( $$dutch_imp{imposition} <= $$setup{imposition} ) {
			$dutch_imp->display(" <= setup $$setup{imposition} skipping") if DEBUG_DUTCH;
			next;
		}
		if ( $$dutch_imp{imposition} <= $previous_dutch_imp ) {
			$dutch_imp->display( " <= previous $previous_dutch_imp skipping") if DEBUG_DUTCH;
			next ;
		}
    my $Paper = $dutch_imp->Paper();
		if ( ! $Paper->start_width() ) {
			$openprint::log->debug("Setting dutch paper width to " . $dutch_imp->used_width() );
			$Paper->width( $dutch_imp->used_width() );
		}
		if ( ! $$Paper{height} ) {
			$openprint::log->debug("Setting Paper height... " . $$Paper{height} . " to " . $dutch_imp->used_height() );
			$Paper->height( $dutch_imp->used_height() );
		}

		if ( check_setup( $dutch_imp, $specs ) ) {
			push @dutch_imps, $dutch_imp;
			$previous_dutch_imp = $$dutch_imp{imposition};
		} else {
			$dutch_imp->display("Failed check_setup");
		} # end if
	} # end foreach

	$previous_dutch_imp = 0;
	foreach my $row_delta ( 0 .. int ( $$setup{rows} / 2 ) ) {

		my $row_space = $space_height - ( ($$setup{rows} -$row_delta) * $image_height );
		my $dutch_rows = int($row_space / $image_width);
		my $dutch_cols = int($space_width / $image_height);

		my $dutch_imp = $setup->copy();
		$dutch_imp->set(
				dutch_columns		=>	$dutch_cols,
				dutch_rows			=>	$dutch_rows,
				rows						=>	$$setup{rows} - $row_delta,
				start_rows			=>	$$setup{rows} - $row_delta,
				#imposition			=>	($$setup{rows} - $row_delta) * $$setup{columns} + ( $dutch_cols * $dutch_rows ),
				dutch_orientation	=>	'height',
				);
		if ( $$dutch_imp{imposition} <= $$setup{imposition} ) {
			$dutch_imp->display(" <= setup $$setup{imposition}");
			next;
		}
		if ( $$dutch_imp{imposition} <= $previous_dutch_imp ) {
			$dutch_imp->display(" <= previous $previous_dutch_imp");
			next;
		}
		my $Paper = $dutch_imp->Paper();
		if ( ! $Paper->start_width() ) {
			$openprint::log->debug("Setting Paper width.... " . $Paper->start_width() . " to " . $dutch_imp->used_width() );
			$Paper->width( $dutch_imp->used_width() );
		} # end if
		if ( ! $$Paper{height} ) {
			$openprint::log->debug("Setting Paper height... " . $$Paper{height} . " to " . $dutch_imp->used_height() );
			$Paper->height( $dutch_imp->used_height() );
		}

		if ( check_setup( $dutch_imp, $specs ) ) {
			push @dutch_imps, $dutch_imp;
			$previous_dutch_imp = $$dutch_imp{imposition};
		} else {
			$dutch_imp->display("Failed check_setup");
		} # end if
	} # end foreach
	return @dutch_imps;
} # end sub calc_dutch

# This function makes sure that the setup is valid.
sub check_setup {
	my ( $setup, $specs ) = @_;

	return 0 if ! $$setup{imposition};
  # MPI says as long as there is space at the edges, we are good.
  if (
    ( $$setup{columns} == 1 ) and
    ( $$setup{runstyle} eq 'Perfecting' ) and
    $$setup{perfecting_wheel_space} and
    $setup->used_width() + $$setup{perfecting_wheel_space} > $setup->sheet_width()
  ) {
    $openprint::log->debug("check)setup no good") if DEBUG;
    return 0;
  }

  #my $Equipment = $setup->Press();
  #if ( 0 and $Equipment ) {
  ## Run Equipment Tests
  #if ( $setup->layout_width() > $Equipment->specification( 'Maximum Image Width' ) ) {
  #$setup->rows(0);
  #} # end if
  #if ( $setup->layout_width() < $Equipment->specification( 'Minimum Image Width' ) ) {
  #$setup->rows(0);
  ##} # end if
  #if ( $setup->layout_height() > $Equipment->specification( 'Maximum Image Height' ) ) {
  #$setup->rows(0);
  #} # end if
  #if ( $setup->layout_height() < $Equipment->specification( 'Minimum Image Height' ) ) {
  #$setup->rows(0);
  #} # end if
  #} # end if

	$openprint::log->debug("Checking used_width against sheetwidth " . $setup->used_width() . ' <=> ' . $setup->sheet_width() ) if DEBUG;
	if ( $setup->used_width() > $setup->sheet_width() ) {
	$openprint::log->debug("Checking used_width against sheetwidth " . $setup->used_width() . ' <=> ' . $setup->sheet_width() ) if DEBUG;
		return 0;
	} # end if

	return 1;
} # end sub check_setup

sub calc_setup_object {
	my ( $specs, $image_width, $image_height, $Paper, $run_style, $Press, $bleed_size ) = @_;

	my $min_bleed_size = $Press->specification( 'Minimum Bleed Size' );

	my $Maximum_Image_Width = $Press->specification( 'Maximum Image Width ' . $run_style );
	$Maximum_Image_Width = $Press->specification( 'Maximum Image Width' ) if ! $Maximum_Image_Width;
	my $Maximum_Image_Length = $Press->specification( 'Maximum Image Length ' . $run_style );
	$Maximum_Image_Length = $Press->specification( 'Maximum Image Length' ) if ! $Maximum_Image_Length;

	my $press_grain;
	if ( my $Stock_Setting = $Press->Stock_Setting( $Paper ) ) {
		$press_grain = $Stock_Setting->grain();
	} else {
		$press_grain = $Press->Specification('Grain');
		if ( $$press_grain{units} eq 'gsm' ) {
			$press_grain = $Press->specification('Grain', $Paper->gsm());
		} elsif ( $$press_grain{units} eq 'calliper' ) {
			$press_grain = $Press->specification('Grain', $$Paper{calliper});
		} else {
			$press_grain = $$press_grain{value};
		}
	} # end if
#$openprint::log->debug("Grains: $grain_direction, Press: $press_grain, Paper: ". $Paper->grain_direction() . ', paper->long: ' . $Paper->long() );
	if ( $press_grain and $press_grain ne 'Both' ) {
		if ( $press_grain eq 'Long' ) {
			if ( $Paper->grain_direction() ne $Paper->long() ) {
				$openprint::log->debug('Improper grain Paper('.$Paper->grain_direction().') Long ('.$Paper->long().')') if DEBUG;
				return;
			} elsif ( DEBUG ) {
				$openprint::log->debug('PROPER grain Paper('.$Paper->grain_direction().') Long ('.$Paper->long().')');
			} # en dif
		} elsif ( $press_grain eq 'Short' ) {
			if ( $Paper->grain_direction() ne $Paper->short() ) {
				$openprint::log->debug('Improper grain Paper('.$Paper->grain_direction().') Short ('.$Paper->short().')') if DEBUG;
				return;
			} elsif ( DEBUG ) {
				$openprint::log->debug('Proper grain Paper('.$Paper->grain_direction().') Short ('.$Paper->short().')');
			} # en dif
		} elsif ($press_grain ne $Paper->grain_direction() ) {
			$openprint::log->debug("Improper grain Paper(".$Paper->grain_direction().") Press($press_grain)") if DEBUG;
			return;
		} elsif ( DEBUG ) {
			$openprint::log->debug("Proper grain Paper(".$Paper->grain_direction().") Press($press_grain)") if DEBUG;
		} # end if
    #} elsif ( DEBUG ) {
    #$openprint::log->debug("No grain direction. $$Paper{gsm}gsm");
	} # end if press_grain

	if ( $run_style eq 'Perfecting' ) {
		my $press_grain = $Press->specification('Perfecting Grain', $Paper->gsm() );

#$openprint::log->debug("Grains: $grain_direction, Press: $press_grain, Paper: ". $Paper->grain_direction() . ', paper->long: ' . $Paper->long() );
		if ( $press_grain and ( $press_grain ne 'Both' ) ) {
			if ( $press_grain eq 'Long' ) {
				if ( $Paper->grain_direction() ne $Paper->long() ) {
					$openprint::log->debug("Improper perfecting grain Paper(".$Paper->grain_direction().") Long (".$Paper->long().")") if DEBUG;
					return;
				} elsif ( DEBUG ) {
					$openprint::log->debug("PROPER perfecting grain Paper(".$Paper->grain_direction().") Long (".$Paper->long().")");
				} # en dif
			} elsif ( $press_grain eq 'Short' ) {
				if ( $Paper->grain_direction() ne $Paper->short() ) {
					$openprint::log->debug("Improper perfecting grain Paper(".$Paper->grain_direction().") Short (".$Paper->short().")") if DEBUG;
					return;
				} elsif ( DEBUG ) {
					$openprint::log->debug("Proper perfecting grain Paper(".$Paper->grain_direction().") Short (".$Paper->short().")") if DEBUG;
				} # en dif
			} elsif ($press_grain ne $Paper->grain_direction() ) {
				$openprint::log->debug("Improper perfecting grain Paper(".$Paper->grain_direction().") Press($press_grain)") if DEBUG;
				return;
			} elsif ( DEBUG ) {
				$openprint::log->debug("Proper perfecting grain Paper(".$Paper->grain_direction().") Press($press_grain)") if DEBUG;
			} # end if
		} elsif ( DEBUG ) {
			$openprint::log->debug("No perfecting grain direction. $$Paper{gsm}");
		} # end if press_grain
	} # end if Perfecting

	if ( my $amount = $Press->specification($run_style.' Pre-trim stock') ) {
    #$openprint::log->debug("Pretrimming by $amount") if DEBUG;
		$Paper = $Paper->clone();
		$Paper->cut( $$Paper{width} - $amount, $$Paper{height} - $amount );
		$Paper->width( 0 ) if $$Paper{width} < 0;
		$Paper->height( 0 ) if $$Paper{height} < 0;
	} else {
    #$openprint::log->debug("Not Pretrimming on $$Press{strid}") if DEBUG;
	} # end if

	my $setup1 = new openprint::Imposition();
	my $setup2 = new openprint::Imposition();
	my @results;
	my $paper_width;
	my $paper_height;
	my $cropmarkspace;

	$$setup1{quantity} = 1;
	$$setup1{sides} = $$specs{print_sides};
	$$setup1{Paper} = $Paper->clone();
	$$setup1{runstyle} = $run_style;
	$$setup1{image_orientation} = openprint::Imposition::Vertical;
	$setup1->image_orientation_text();
	$setup1->spread_size( $$specs{txtSpreadSize} );
	$setup1->bleed_size( $bleed_size );
	$setup1->spread_rows( 1 );
	$setup1->spread_columns( 1 );

	#$setup1->page_rows( POSIX::ceil( $$specs{txtHeight}/$$specs{txtFinalHeight} ) );
	#$setup1->page_columns( POSIX::ceil( $$specs{txtWidth}/$$specs{txtFinalWidth}) );
	$setup1->page_rows( Math::Round::nearest( 1, $$specs{txtHeight}/$$specs{txtFinalHeight} ) );
	$setup1->page_columns( Math::Round::nearest( 1, $$specs{txtWidth}/$$specs{txtFinalWidth}) );

	$setup1->object_width( $image_width );
	$setup1->object_height( $image_height );
	$$setup1{page_width} = $$specs{txtFinalWidth};
	$$setup1{page_height} = $$specs{txtFinalHeight};
	$$setup1{Press} = $Press;
	$$setup1{printing_type} = $Press->specification('Printing Type');
	if ( $run_style eq 'Perfecting' ) {
		$$setup1{colour_bar_size} = $$specs{Perfecting_colour_bar_size};
		$$setup2{colour_bar_size} = $$specs{Perfecting_colour_bar_size};
	} else {
		$$setup1{colour_bar_size} = $$specs{colour_bar_size};
		$$setup2{colour_bar_size} = $$specs{colour_bar_size};
	} # end if
	$$setup1{colour_bar_orientation} = $$specs{'Colour Bar Orientation'};
	$$setup1{spine} = $$specs{ProjectSpecs}{spine};
	$setup1->spine_direction();


	$$setup2{quantity} = 1;
	$$setup2{sides} = $$specs{print_sides};
	$$setup2{Paper} = $Paper->clone();
	$$setup2{runstyle} = $run_style;
	$$setup2{image_orientation} = openprint::Imposition::Horizontal;
	$setup2->image_orientation_text();
	$$setup2{bleed_size} = $bleed_size;
	$$setup2{spread_size} = $$specs{txtSpreadSize};
	$$setup2{spread_rows} = 1;
	$$setup2{spread_columns} = 1;
	#$$setup2{page_columns} = POSIX::ceil( $$specs{txtHeight}/$$specs{txtFinalHeight} );
	#$$setup2{page_rows} = POSIX::ceil( $$specs{txtWidth}/$$specs{txtFinalWidth});
	$$setup2{page_columns} = Math::Round::nearest( 1, $$specs{txtHeight}/$$specs{txtFinalHeight} );
	$$setup2{page_rows} = Math::Round::nearest( 1, $$specs{txtWidth}/$$specs{txtFinalWidth});
	$$setup2{page_width} = $$specs{txtFinalWidth};
	$$setup2{page_height} = $$specs{txtFinalHeight};
	$setup2->object_width( $image_width );
	$setup2->object_height( $image_height );
	$$setup2{Press} = $Press;
	$$setup2{printing_type} = $Press->specification('Printing Type');
	$$setup2{colour_bar_orientation} = $$specs{'Colour Bar Orientation'};
	$$setup2{spine} = $$specs{ProjectSpecs}{spine};
	$setup2->spine_direction();

	# Grain is on the second dimension by default (according to Rick)

	#		we need to rotate the sheet because that is what would physically happen when running the job, width will always be
	#		the largest dimension when running the paper on the press. 'rotate_sheet' is used to track grain direction.
	if ( $$specs{Orientation} eq 'Portrait' ) {
		if ( $$Paper{width} > $$Paper{height} ) {
			$$setup1{rotate_sheet} = 1;
			$$setup2{rotate_sheet} = 1;
			$paper_width = $$Paper{height};
			$paper_height = $$Paper{width};
		} else {
			$$setup1{rotate_sheet} = 0;
			$$setup2{rotate_sheet} = 0;
			$paper_width = $$Paper{width};
			$paper_height = $$Paper{height};
		} # end if
	} else {
		# default to landscape
		if ( $$Paper{width} < $$Paper{height} ) {
			$$setup1{rotate_sheet} = 1;
			$$setup2{rotate_sheet} = 1;
			$paper_width = $$Paper{height};
			$paper_height = $$Paper{width};
		} else {
			$$setup1{rotate_sheet} = 0;
			$$setup2{rotate_sheet} = 0;
			$paper_width = $$Paper{width};
			$paper_height = $$Paper{height};
		} # end if
	} # end if
	$setup1->sheet_width( $paper_width );
	$setup1->sheet_height( $paper_height );
	$setup1->grain_direction();

	$setup2->sheet_width( $paper_width );
	$setup2->sheet_height( $paper_height );
	$setup2->grain_direction();

	my $bindery_gutters = 0;
	my $bindery_bleed = 0;
	my $bindery_head = 0;

	if ( $$specs{Binding} ) {
		if ( sets::isin( $$specs{Binding}, ['SaddleStitching','LoopStitching'] ) ) {
			$bindery_gutters = $Press->specification('StitchingGutter');
			$bindery_bleed = $Press->specification('StitchingBleed');
			if ( $bindery_bleed ) {
				$setup1->bleed_size( $bindery_bleed );
				$setup2->bleed_size( $bindery_bleed );
			} # end if
			$setup1->folio_lip( $bindery_gutters );
			$setup2->folio_lip( $bindery_gutters );
		} elsif ( sets::isin( $$specs{Binding}, ['PerfectBound','SpinePaste'] ) ) {
			$bindery_gutters = $Press->specification('PerfectBindGutter');
			$bindery_bleed = $Press->specification('PerfectBindBleed');
			if ( $bindery_bleed ) {
				$setup1->bleed_size( $bindery_bleed );
				$setup2->bleed_size( $bindery_bleed );
			} # end if
			$setup1->folio_lip( $bindery_gutters );
			$setup2->folio_lip( $bindery_gutters );
			$bindery_head = $$specs{PerfectBindCoverGutter};
		} # end if
	} # end if
#$openprint::log->debug("Using perfectbind cover gutter: $bindery_head Bindery bleed: $bindery_bleed");
	my %bleed_locations = map { $_, $_ } split(',', $$specs{BleedLocations} );
	my $bleed_width  = 2*$bindery_bleed; # .25
	my $bleed_height  = 2*$bindery_bleed;#.25
	if ( $bleed_locations{Right} ) {
		$image_width += $bleed_size; # 17.0625
		$bleed_width -= $bleed_size; # .1875
	} # end if
	if ( $bleed_locations{Left} ) {
		$image_width += $bleed_size; # 17.125
		$bleed_width -= $bleed_size; #0.125
	} # end if
	if ( $bleed_locations{Top} ) {
		$bindery_head -= $bleed_size;
		$image_height += $bleed_size;
		$bleed_height -= $bleed_size;
	} # end if
	if ( $bleed_locations{Bottom} ) {
		$image_height += $bleed_size;
		$bleed_height -= $bleed_size;
	} # end if
	$bleed_width = 0 if $bleed_width < 0;
	$bleed_height = 0 if $bleed_height < 0;
#$openprint::log->debug("BleedSize: $bleed_size bindery: $bindery_bleed, width: image: $image_width + extra: $bleed_width");

	#$openprint::log->debug("Using perfectbind cover gutter: $bindery_head Bindery bleed: $bindery_bleed");
	if ( $bindery_head < 0 ) {
		$bindery_head = 0;
	} else {
		$image_height += $bindery_head;
	} # end if
	#$openprint::log->debug("Using perfectbind cover gutter: $bindery_head Bindery bleed: $bleed_height Image height: $image_height");

	$setup1->image_width( $image_width + $bleed_width );
	$setup1->image_height( $image_height );
#$openprint::log->debug("Setup1 $bleed_width " . $setup1->image_width() .'x'.$setup1->image_height() );

	$setup2->image_width( $image_width );
	$setup2->image_height( $image_height + $bleed_height );
#$openprint::log->debug("Setup2 $bleed_height " . $setup2->image_width() .'x'.$setup2->image_height() );


#	Now here is how I understand things to be..
#	1. At this point Paper Width is relative to the press.
#	2. Grip will always be subtracted from Paper Height & Gutter will always be subtracted from Paper Width.
#	3. For %setup1, Paper Width is matched to Image Width. eg: For a 22x28 Image on 23x39 sheet would match the 22 IW to the 39 PW and 28 IH to the 22 PW.

	my $gutters = $$specs{Gutter};
	#$gutters = $bindery_gutters if $gutters < $bindery_gutters;
	if ( $bleed_locations{Right} ) {
		$gutters -= $bleed_size;
	} # end if
	if ( $bleed_locations{Left} ) {
		$gutters -= $bleed_size;
	} # end if
$openprint::log->debug("Gutters: specs : $$specs{Gutter}, bindery: $bindery_gutters, minus bleeds: $gutters bleed_width: $bleed_width bleed_height: $bleed_height") if DEBUG;

	$gutters = 0 if $gutters < 0;

	$$specs{'Grip Size'} = $$specs{Grip} - $bindery_head;
# doube grip for a perfecting or Work & Tumble.
	$openprint::log->debug("Grip  $$specs{'Grip Size'}") if DEBUG;
	if ( ( $run_style eq 'Work & Tumble' ) or ( $run_style eq 'Perfecting' ) ) {
		$$specs{'Grip Size'} *= 2;
		$openprint::log->debug("Grip  $$specs{'Grip Size'}") if DEBUG;
	} # emd
	if ( ( $run_style eq 'Work & Tumble' ) and ( $$specs{'Colour Bar Orientation'} ne 'Length' ) ) {
		# For Work & TUmble, the grip happens on the head and tail, but we can print on the backside of the grip so to speak.  So we can tuck the colour bar into the second grip space.
		$$specs{'Grip Size'} -= $$specs{colour_bar_size};
	} # end if
	$$setup1{grip} = $$specs{'Grip Size'};
	$$setup2{grip} = $$specs{'Grip Size'};
#$openprint::log->debug("Setup1 after grip $bleed_width " . $setup1->image_width() .'x'.$setup1->image_height() );

# Setup 1. Width to Width
# Calculate Available Printing Space
	my $adjusted_paper_height = 0;
	if ( $paper_height ) {
		$adjusted_paper_height = $paper_height;
	} elsif ( $$specs{'Cut Off'} ) {
		$adjusted_paper_height = $$specs{'Cut Off'};
		$setup1->Paper()->height( $$specs{'Cut Off'} );
		$$setup1{stock_height} = $$specs{'Cut Off'};
	} # end if

	# Becomes Printable area
	$adjusted_paper_height -= $$specs{'Grip Size'} if $$specs{'Add Grip Height'} ne 'N';
#n$openprint::log->debug("Adjusted PHeght after grip: $adjusted_paper_height") if DEBUG;

# On the web press, we have no paper dimensions, only the maximagesize, so this effectively sets the printing area to the max image size. Theoretically Max Image Size = Cutoff-Grip anyways
	if ( $Maximum_Image_Length and ( ( $adjusted_paper_height <= 0 ) or ( $adjusted_paper_height > $Maximum_Image_Length ) ) ) {
		my $max_image_height = $Maximum_Image_Length;
		$max_image_height += ( $bleed_size - $$specs{CropMarkSpace} ) if $bleed_locations{Top}; # Can bleed outside the image area
		$max_image_height += ( $bleed_size - $$specs{CropMarkSpace} ) if $bleed_locations{Bottom}; # Can bleed outside the image area
		if ( $max_image_height < $adjusted_paper_height ) {
			$openprint::log->debug("*** Using Max Image Length1: Before: $adjusted_paper_height After: $max_image_height***") if DEBUG;
			$adjusted_paper_height = $max_image_height;
		} # end if
	} # end if

	my $colour_bar = 0;
	if ( $$specs{'Colour Bar Orientation'} ne 'Length' ) {
		$colour_bar = $$setup1{colour_bar_size};

# colour bar is at bottom or top, then can bleed into it.  Or it can go in the middle, in which case you put it in the bleed space. W&Tumble we put it in grip, so don't do this at all.
		if ( $run_style ne 'Work & Tumble' ) {
			#$colour_bar -= $bleed_size if $bleed_locations{Top};
			#$colour_bar -= $bleed_size if $bleed_locations{Bottom};
			#$colour_bar = 0 if $colour_bar < 0;
		#} else {
# If impo was x2 then it can go in middle, but we don't know that yet.
			# Apparently you can
# 2014-09-25: Brendan and Rick say you really can't.  You need a minimum of bleed space.
# SInce we don't know if rows > 1 yet, let's just only subtract 1
			if ( $bleed_size ) {
			$colour_bar -= ( $bleed_size - $min_bleed_size ) if $bleed_locations{Top} or $bleed_locations{Bottom};
			#$colour_bar -= ( $bleed_size - $min_bleed_size ) if $bleed_locations{Top} and $bleed_locations{Bottom};
			} # end if
			$colour_bar = 0 if $colour_bar < 0;
			$colour_bar = $$setup1{colour_bar_size} if $colour_bar > $$setup1{colour_bar_size};

$openprint::log->debug("Colour bar is now $colour_bar") if DEBUG;
		}

		$adjusted_paper_height -= $colour_bar;
	} # end if

	if ( $Paper->cuttable() ) {
	# There needs to be enough space to put crop marks, but they can go in th bleed space, so it's only an issue if we are running small or no bleeds.
		$cropmarkspace = $$specs{CropMarkSpace};
		$cropmarkspace -= $bleed_size if $bleed_locations{Top};
		$cropmarkspace = 0 if $cropmarkspace < 0;
		$adjusted_paper_height -= $cropmarkspace;
		$$setup1{cropmark_top} = $cropmarkspace;

		$cropmarkspace = $$specs{CropMarkSpace};
		$cropmarkspace -= $bleed_size if $bleed_locations{Bottom};
		$cropmarkspace = 0 if $cropmarkspace < 0;
		$adjusted_paper_height -= $cropmarkspace;
		$$setup1{cropmark_bottom} = $cropmarkspace;
	} # end if

	$adjusted_paper_height = 0 if $adjusted_paper_height < 0;
	$openprint::log->debug("Height: $paper_height - CB $$specs{colour_bar_size} - Grip $$specs{'Grip Size'} CropTOp: $$setup1{cropmark_top} - CropBottom: $$setup1{cropmark_bottom} = $adjusted_paper_height") if DEBUG;

	my $adjusted_paper_width = $paper_width;
	if ( $Paper->cuttable() ) {
		$cropmarkspace = $$specs{CropMarkSpace};
		$cropmarkspace -= $bleed_size if $bleed_locations{Left};
		$cropmarkspace = 0 if $cropmarkspace < 0;
		$$setup1{cropmark_left} = $cropmarkspace;
		$gutters -= $cropmarkspace;
		$cropmarkspace = $$specs{CropMarkSpace};
		$cropmarkspace -= $bleed_size if $bleed_locations{Right};
		$cropmarkspace = 0 if $cropmarkspace < 0;
		$$setup1{cropmark_right} = $cropmarkspace;
		$gutters -= $cropmarkspace;
		$gutters = 0 if $gutters < 0;
	} # end if
	$setup1->gutters($gutters);
	$adjusted_paper_width -= $gutters;

	if ( $run_style eq 'Perfecting' and ! $Paper->perfecting() ) {
		calc_setup( $setup1, @$setup1{'image_width','image_height'}, $adjusted_paper_width, $adjusted_paper_height ? $adjusted_paper_height : $$setup1{image_height} );
		my $wheel_space;
		if ( $$setup1{columns} % 2 ) {
			$wheel_space = $$specs{'Perfecting Double Gutter Size'};
			$setup1->perfecting_wheel_space( $wheel_space );
			if ( $bleed_locations{Right} ) {
				$wheel_space -= 2*$bleed_size;
			} # end if
			if ( $bleed_locations{Left} ) {
				$wheel_space -= 2*$bleed_size;
			} # end if
$openprint::log->debug("Using Double wheel space $$specs{'Perfecting Double Gutter Size'} -> $wheel_space") if DEBUG;
		} else {
			$wheel_space = $$specs{'Perfecting Single Gutter Size'};
			$setup1->perfecting_wheel_space( $wheel_space );
			if ( $bleed_locations{Right} ) {
				$wheel_space -= $bleed_size;
			} # end if
			if ( $bleed_locations{Left} ) {
				$wheel_space -= $bleed_size;
			} # end if
$openprint::log->debug("Using Single wheel space $$specs{'Perfecting Single Gutter Size'} -> $wheel_space") if DEBUG;
		} # end if
		$wheel_space = 0 if $wheel_space < 0;
		$openprint::log->debug("Adding " . $wheel_space . " for Perfecting wheel since columns is $$setup1{columns} ") if DEBUG;
		$adjusted_paper_width -= $wheel_space;
	} # end if


	if ( ( ! $paper_width ) or ( $Maximum_Image_Width > 0 and $adjusted_paper_width > $Maximum_Image_Width ) ) {
		$openprint::log->debug("*** Using Max Image Width1: paper_width: $paper_width adj paper width: $adjusted_paper_width > $Maximum_Image_Width***") if DEBUG;
		$adjusted_paper_width = $Maximum_Image_Width;
	} # end if
	if ( $$specs{'Colour Bar Orientation'} eq 'Length' ) {
		$adjusted_paper_width -= $$setup1{colour_bar_size};
	} # end if

	if ( $Paper->cuttable() ) {
		$adjusted_paper_width -= $$setup1{cropmark_left};
		$adjusted_paper_width -= $$setup1{cropmark_right};
		$adjusted_paper_width = 0 if $adjusted_paper_width < 0;
	} # end if
	$openprint::log->debug("Paper Width after gutters bleeds and crops gutters: $adjusted_paper_width") if DEBUG;

	if ( $run_style eq 'Perfecting' or $run_style eq 'Sheet Work' or $run_style eq 'Web' ) {
		calc_setup( $setup1, @$setup1{'image_width','image_height'}, $adjusted_paper_width, $adjusted_paper_height ? $adjusted_paper_height : $$setup1{image_height} );
		$openprint::log->debug(" CHECK 1 Upright $run_style Using Paper $paper_width x $paper_height -> $adjusted_paper_width x $adjusted_paper_height Gutter: $gutters, Image: $$setup1{image_width} x $$setup1{image_height} Imposition: " . $$setup1{imposition}. ":".$$setup1{columns} . 'x' . $$setup1{rows}. " $run_style " . $setup1->layout_width(undef) . 'x' . $setup1->layout_height() ) if DEBUG;

		if ( ( $run_style eq 'Perfecting' ) and ( $$setup1{rows} == 1 ) and ( $$specs{'Colour Bar Orientation'} ne 'Length' ) ) {
			# Can't put colour bar in middle... so it has to go on leading edge... so need space for it at both head and tail
			if ( $adjusted_paper_height - $setup1->layout_height() < $colour_bar ) {
				$openprint::log->debug("Imp no good because need enough space for extra colour bar $adjusted_paper_height - $$setup1{layout_height} > cb $colour_bar");
				$$setup1{imposition} = 0;
			}
		}

		if ( $$setup1{imposition} ) {
			my $Paper1 = $setup1->Paper();

			$Paper1->height( $setup1->used_height() ) if ! $$Paper1{height};
			$Paper1->width( $setup1->used_width() ) if ! $$Paper1{width};
			if ( check_setup( $setup1, $specs ) ) {
				$openprint::log->debug("Success CHECK 1 $run_style Using Paper $paper_width x $paper_height -> $adjusted_paper_width x $adjusted_paper_height Gutter: $gutters, Image: $$setup1{image_width} x $$setup1{image_height} Imposition: " . $$setup1{imposition}. ":".$$setup1{columns} . 'x' . $$setup1{rows}. " $run_style " . $setup1->layout_width() . 'x' . $setup1->layout_height() ) if DEBUG;
				push @results, $setup1;
				if ( $$specs{dutch} and ( $run_style ne 'Perfecting' or $Paper->perfecting() or $$specs{PerfectingDutchByDefault} or ( $$specs{OverrideRunStyle} and $$specs{OverrideImposition} ) ) ) {
					# Too hard to figure space for rollers
	$openprint::log->debug("add dutches");
					push @results, calc_dutch( $setup1, $adjusted_paper_width, $adjusted_paper_height, $specs );
				} else {
	$openprint::log->debug("Not doing dutch because ($$specs{dutch}) or $run_style or $$Paper{perfecting}") if DEBUG;
				} # end if
			} # end if check_setup
		} # end if imposition
	} elsif ( $run_style eq 'Work & Turn' ) {
		calc_setup( $setup1, @$setup1{'image_width','image_height'}, $adjusted_paper_width/2, $adjusted_paper_height );
		$openprint::log->debug( sprintf('CHECK 1 Work&Turn Using Paper %sx%s -> %s x %s Image: %s x %s Imposition: %dout:%dx%d ',$paper_width, $paper_height, $adjusted_paper_width/2, $adjusted_paper_height, $setup1->image_width(), $setup1->image_height(), $setup1->imposition(), $setup1->columns(), $setup1->rows() ) ) if DEBUG;

		if ( $$setup1{imposition} ) {
			if ( $$specs{dutch} ) {
				foreach my $imp ( calc_dutch( $setup1, $adjusted_paper_width/2, $adjusted_paper_height, $specs ) ) {
					$imp->columns( $$imp{columns} * 2 );
          $imp->start_columns($$imp{columns});
					$imp->dutch_columns( $$imp{dutch_columns} * 2 );
					$imp->Paper()->width( $imp->used_width() ) if ! $imp->Paper()->start_width();
					$openprint::log->debug( sprintf('CHECK 1 Work&Turn Dutch Using Paper %sx%s -> %sx%s Image: %s x %s Imposition: %dout:%dx%d+%dx%d',$paper_width, $paper_height, $adjusted_paper_width/2, $adjusted_paper_height, $setup1->image_width(), $setup1->image_height(), $imp->imposition(), $imp->columns(), $imp->rows(), $imp->dutch_columns(), $imp->dutch_rows() ) ) if DEBUG;
					push @results, $imp;
				} # end foreach
			} # end if grain_direction
			$setup1->columns( $$setup1{columns} * 2 );
			$setup1->start_columns( $$setup1{columns} );
			if ( ! $setup1->Paper()->width() ) {
				$setup1->Paper()->width( $setup1->used_width()*2 );
			} # end if
			$setup1->Paper()->height( $setup1->used_height() ) if ! $setup1->Paper()->height();
			push @results, $setup1;
		} # end if imposition
	} elsif ( $run_style eq 'Work & Tumble' ) {
		calc_setup( $setup1, @$setup1{'image_width','image_height'}, $adjusted_paper_width, $adjusted_paper_height/2 );
		$openprint::log->debug( sprintf('CHECK 1 Work&TumbleUsing Paper %sx%s -> %sx%s Image: %s x %s Imposition: %dout:%dx%d ',$paper_width, $paper_height, $adjusted_paper_width, $adjusted_paper_height/2, @$setup1{'image_width','image_height','imposition', 'columns','rows'} ) ) if DEBUG;
		if ( $$setup1{imposition} ) {

			if ( $$specs{dutch} ) {
				foreach my $imp ( calc_dutch( $setup1, $adjusted_paper_width, $adjusted_paper_height/2, $specs ) ) {
					$imp->rows( $$imp{rows} * 2 );
					$imp->dutch_rows( $$imp{dutch_rows} * 2 );
					$imp->Paper()->height( $imp->used_height() ) if ! $imp->Paper()->height();
					$openprint::log->debug( sprintf('CHECK 1 Work&Tumble Dutch Using Paper %sx%s -> %sx%s Image: %s x %s Imposition: %dout:%dx%d+%dx%d',$paper_width, $paper_height, $adjusted_paper_width/2, $adjusted_paper_height, $image_width, $image_height, $imp->imposition(), $imp->columns(), $imp->rows(), $imp->dutch_columns(), $imp->dutch_rows() ) ) if DEBUG;
					push @results, $imp;
				} # end foreach
			} # end if grain_direction
			$setup1->rows( $$setup1{rows} * 2 );
			$setup1->Paper()->width( $setup1->used_width() ) if ! $setup1->Paper()->width();
			$setup1->Paper()->height( $setup1->used_height() ) if ! $setup1->Paper()->height();
			push @results, $setup1 if $$setup1{imposition};
		} # end if imposition
	} # end if run_style

# Only consider the rotated view if teh grain direction is unspecified or is correct for this.
	$gutters = $$specs{Gutter};

	# Bindery gutter is actually folio lip, which should be at the bottom
	#$gutters = $bindery_gutters if $gutters < $bindery_gutters;
	if ( $bleed_locations{Top} ) {
		$gutters -= $bleed_size;
	} # end if
	if ( $bleed_locations{Bottom} ) {
		$gutters -= $bleed_size;
	} # end if
#$openprint::log->debug("Bindery Gutters 2: $gutters <? $bindery_gutters");

	$gutters = 0 if $gutters < 0;

	$adjusted_paper_height = 0;
	if ( $paper_height ) {
		$adjusted_paper_height = $paper_height;
	} elsif ( $$specs{'Cut Off'} ) {
		$openprint::log->debug("Using Cut Off : $$specs{'Cut Off'}") if DEBUG;
		$adjusted_paper_height = $$specs{'Cut Off'};
		$setup2->Paper()->height( $$specs{'Cut Off'} );
		$$setup2{stock_height} = $$specs{'Cut Off'};
	} # end if

	# Becomes printable area
	if ( $$specs{'Add Grip Width'} ne 'N' ) {
		$adjusted_paper_height -= $$specs{'Grip Size'};
		if ($$specs{'Grip Size'} < $bindery_gutters ) {
			$adjusted_paper_height -= ( $bindery_gutters - $$specs{'Grip Size'} );
		}
	} else {
	# Don't need folio lip if we have enoguh grip
	$adjusted_paper_height -= $bindery_gutters;
	}
	#$$openprint::log->debug("Height after grip: $adjusted_paper_height ");

	if ( ($adjusted_paper_height<=0) or ( ( $Maximum_Image_Length > 0 ) and ( $adjusted_paper_height > $Maximum_Image_Length ) ) ) {
		$openprint::log->debug("*** Using Max Image Length2: Before: $adjusted_paper_height After: $Maximum_Image_Length***") if DEBUG;
		$adjusted_paper_height = $Maximum_Image_Length;
	} else {
		$openprint::log->debug("*** NOT Using Max Image Length2: $adjusted_paper_height After: $Maximum_Image_Length***") if DEBUG;
	} # end if

	$colour_bar = 0;
	if ( $$specs{'Colour Bar Orientation'} ne 'Length' ) {

# if colour bar is at bottom,
		$colour_bar = $$setup2{colour_bar_size};

# colour bar is at bottom or top, then can bleed into it.  Or it can go in the middle, in which case you put it in the bleed space. W&Tumble we put it in grip, so don't do this at all.
		if ( $run_style eq 'Work & Tumble' ) {
# It goes in grip space, don't adjust it to fit in bleed
		} else {
		#$colour_bar -= $bleed_size if $bleed_locations{Top};
		#$colour_bar -= $bleed_size if $bleed_locations{Bottom};
		#$colour_bar = 0 if $colour_bar < 0;
		#} else {
		# If impo was x2 then it can go in middle, but we don't know that yet.
		# Apparently you can
		# 2014-09-25: Brendan and Rick say you really can't.  You need a minimum of bleed space.
		# SInce we don't know it rows > 1 yet, let's just only subtract 1
			if ( $bleed_size ) {
				$colour_bar -= ( $bleed_size - $min_bleed_size ) if $bleed_locations{Top} or $bleed_locations{Bottom};
		#$colour_bar -= ( $bleed_size - $min_bleed_size ) if $bleed_locations{Top} and $bleed_locations{Bottom};
			} # end if
			$colour_bar = 0 if $colour_bar < 0;
			$colour_bar = $$setup2{colour_bar_size} if $colour_bar > $$setup2{colour_bar_size};
		}

		$openprint::log->debug("Colour bar is now $$setup2{colour_bar_size} - ( $bleed_size - $min_bleed_size ) = $colour_bar") if DEBUG;
		$adjusted_paper_height -= $colour_bar;
	} # end if

	$adjusted_paper_width = $paper_width;

	if ( $Paper->cuttable() ) {
		$cropmarkspace = $$specs{CropMarkSpace};
		$cropmarkspace -= $bleed_size if $bleed_locations{Left};
		$cropmarkspace = 0 if $cropmarkspace < 0;
		$$setup2{cropmark_top} = $cropmarkspace;

		$cropmarkspace = $$specs{CropMarkSpace};
		$cropmarkspace -= $bleed_size if $bleed_locations{Right};
		$cropmarkspace = 0 if $cropmarkspace < 0;
		$$setup2{cropmark_bottom} = $cropmarkspace;

		$adjusted_paper_height -= $$setup2{cropmark_top};
		$adjusted_paper_height -= $$setup2{cropmark_bottom};
		$adjusted_paper_height = 0 if $adjusted_paper_height < 0;

		$cropmarkspace = $$specs{CropMarkSpace};

		$cropmarkspace -= $bleed_size if $bleed_locations{Top};
		$cropmarkspace = 0 if $cropmarkspace < 0;
		$$setup2{cropmark_left} = $cropmarkspace;
		$gutters -= $cropmarkspace;
		$cropmarkspace = $$specs{CropMarkSpace};
		$cropmarkspace -= $bleed_size if $bleed_locations{Bottom};
		$cropmarkspace = 0 if $cropmarkspace < 0;
		$$setup2{cropmark_right} = $cropmarkspace;
#$openprint::log->debug( "Crop marks: $$setup2{cropmark_left} $$setup2{cropmark_right}");
		$gutters -= $cropmarkspace;
		$gutters = 0 if $gutters < 0;
	} # end if
	$setup2->gutters($gutters);
#$openprint::log->debug("Gutters after cropmarks $gutters");
	$adjusted_paper_width -= $gutters;

	if ( $run_style eq 'Perfecting' and ! $Paper->perfecting() ) {

		# This will calc an initial imposition.  It will get updated later.
		calc_setup( $setup2, @$setup2{'image_height','image_width'}, $adjusted_paper_width, $adjusted_paper_height ? $adjusted_paper_height : $$setup2{image_width} );
		my $wheel_space;
		if ( $$setup2{columns} % 2 ) {
			$wheel_space = $$specs{'Perfecting Double Gutter Size'};
			$setup2->perfecting_wheel_space( $wheel_space );
			if ( $bleed_locations{Top} ) {
				$wheel_space -= 2*$bleed_size;
			} # end if
			if ( $bleed_locations{Bottom} ) {
				$wheel_space -= 2*$bleed_size;
			} # end if
			$openprint::log->debug("Using Single wheel space $$specs{'Perfecting Double Gutter Size'} -> $wheel_space") if DEBUG;
		} else {
			$wheel_space = $$specs{'Perfecting Single Gutter Size'};
			$setup2->perfecting_wheel_space( $wheel_space );
			if ( $bleed_locations{Top} ) {
				$wheel_space -= $bleed_size;
			} # end if
			if ( $bleed_locations{Bottom} ) {
				$wheel_space -= $bleed_size;
			} # end if
			$openprint::log->debug("Using Single wheel space $$specs{'Perfecting Single Gutter Size'} -> $wheel_space") if DEBUG;
		} # end if
		$wheel_space = 0 if $wheel_space < 0;
		$openprint::log->debug("Adding " . $wheel_space . " for Perfecting wheel since columns is $$setup1{columns} ") if DEBUG;
		$adjusted_paper_width -= $wheel_space;
	} # end if

	if ( (! $paper_width ) or ( $Maximum_Image_Width > 0 and $adjusted_paper_width > $Maximum_Image_Width ) ) {
		$openprint::log->debug("*** Using Max Image Width2: $Maximum_Image_Width instead of $adjusted_paper_width ***") if DEBUG;
		$adjusted_paper_width = $Maximum_Image_Width;
	} # end if
	if ( $$specs{'Colour Bar Orientation'} eq 'Length' ) {
		$adjusted_paper_width -= $$setup2{colour_bar_size};
	} # end if

	if ( $Paper->cuttable() ) {
		$adjusted_paper_width -= $$setup2{cropmark_left};
		$adjusted_paper_width -= $$setup2{cropmark_right};
		$adjusted_paper_width = 0 if $adjusted_paper_width < 0;
	} # end if

	my $Paper2 = $setup2->Paper();

	if ( $run_style eq 'Perfecting' or $run_style eq 'Sheet Work' or $run_style eq 'Web' ) {
		calc_setup( $setup2, @$setup2{'image_height','image_width'}, $adjusted_paper_width, $adjusted_paper_height ? $adjusted_paper_height : $$setup2{image_width} );

		if ( ( $run_style eq 'Perfecting' ) and ( $$setup2{rows} == 1 ) and ( $$specs{'Colour Bar Orientation'} ne 'Length' ) ) {
			# Can't put colour bar in middle... so it has to go on leading edge... so need space for it at both head and tail
			if ( $adjusted_paper_height - $setup2->layout_height() < $colour_bar ) {
				$openprint::log->debug("Imp no good because need enough space for extra colour bar $adjusted_paper_height - $$setup2{layout_height} > cb $colour_bar");
				$$setup2{imposition} = 0;
			}
		}

		if ( $$setup2{imposition} ) {
			$openprint::log->debug(" CHECK 2 $run_style Using Paper $paper_width x $paper_height -> $adjusted_paper_width x $adjusted_paper_height Gutter: $gutters, Image: $$setup2{image_width} x $$setup2{image_height} Imposition: " . $$setup2{imposition}. ":".$$setup2{columns} . 'x' . $$setup2{rows}. " $run_style") if DEBUG;
			$Paper2->width( $setup2->used_width() ) if ! $$Paper2{width};
			$Paper2->height( $setup2->used_height() ) if ! $$Paper2{height};
			if ( check_setup( $setup2, $specs ) ) {
				if ( $run_style eq 'Perfecting' ) {
					$setup2->perfecting_wheel_space( $$setup1{imposition} % 2 ? $$specs{'Perfecting Double Gutter Size'} : $$specs{'Perfecting Single Gutter Size'} );
				} # end if
				$openprint::log->debug(" CHECK 2 $run_style Using Paper $paper_width x $paper_height -> $adjusted_paper_width x $adjusted_paper_height Gutter: $gutters, Image: $$setup2{image_width} x $$setup2{image_height} Imposition: " . $$setup2{imposition}. ":".$$setup2{columns} . 'x' . $$setup2{rows}. " $run_style") if DEBUG;

#	Rotating sheet reverses the grain direction, so grain width + rotated sheet is the same as grain height + non rotated sheet.
#	if no grain direction is specified, then use the larger imposition
				if ( $$specs{dutch} and ( $run_style ne 'Perfecting' or $Paper->perfecting() or $$specs{PerfectingDutchByDefault} or ( $$specs{OverrideRunStyle} and $$specs{OverrideImposition}  ) ) ) {
					push @results, calc_dutch( $setup2, $adjusted_paper_width, $adjusted_paper_height, $specs );
				} # end if
				push @results, $setup2;
			} elsif ( DEBUG ) {
				$openprint::log->debug(' failed check_setup');
			} # end if
		} # end if
	} elsif ( $run_style eq 'Work & Turn' ) {
		calc_setup( $setup2, @$setup2{'image_height','image_width'}, $adjusted_paper_width/2, $adjusted_paper_height );
		$openprint::log->debug( sprintf('CHECK 2 Work&Turn Using Paper %sx%s -> %sx%s Image: %s x %s Imposition: %dout:%dx%d',$paper_width, $paper_height, $adjusted_paper_width/2, $adjusted_paper_height, @$setup2{'image_height','image_width','imposition','columns','rows'} ) ) if DEBUG;
		if ( $$setup2{imposition} ) {
			if ( $$specs{dutch} ) {
				foreach my $imp ( calc_dutch( $setup2, $adjusted_paper_width/2, $adjusted_paper_height, $specs ) ) {
					$imp->columns( $$imp{columns} * 2 );
					$imp->start_columns($$imp{columns});
					$imp->dutch_columns( $$imp{dutch_columns} * 2 );
					$imp->Paper()->width( $imp->used_width() ) if ! $imp->Paper()->start_width();
					#$openprint::log->debug( sprintf('CHECK 2 Work&Turn Dutch Using Paper %sx%s -> %sx%s Image: %s x %s Imposition: %dout:%dx%d+%dx%d',$paper_width, $paper_height, $adjusted_paper_width, $adjusted_paper_height/2, $setup2->image_height(), $setup2->image_width(), $imp->imposition(), $imp->columns(), $imp->rows(), $imp->dutch_columns(), $imp->dutch_rows() ) ) if DEBUG;
					push @results, $imp;
				} # end foreach
			} # end if grain_direction
			$setup2->columns( $$setup2{columns} * 2 );
			$Paper2->width( $setup2->used_width() ) if ! $$Paper2{width};
			$Paper2->height( $setup2->used_height() ) if ! $$Paper2{height};
      $openprint::log->debug( sprintf('CHECK 2 adjusted Work&Turn Using Paper %sx%s -> %sx%s Image: %s x %s Imposition: %dout:%dx%d',$paper_width, $paper_height, $adjusted_paper_width/2, $adjusted_paper_height, @$setup2{'image_height','image_width','imposition','columns','rows'} ) ) if DEBUG;
			push @results, $setup2;
		} # end if imposition
	} elsif ( $run_style eq 'Work & Tumble' ) {
		calc_setup( $setup2, @$setup2{'image_height','image_width'}, $adjusted_paper_width, $adjusted_paper_height/2 );
		$openprint::log->debug( sprintf(
					'CHECK 2 Work&Tumble Using Paper %sx%s -> %sx%s Image: %s x %s Imposition: %dout:%dx%d',
					$paper_width, $paper_height, $adjusted_paper_width, $adjusted_paper_height/2,
					@$setup2{'image_height','image_width','imposition','columns','rows'}
					) ) if DEBUG;
		if ( $$setup2{imposition} ) {

			if ( $$specs{dutch} ) {
				foreach my $imp ( calc_dutch( $setup2, $adjusted_paper_width, $adjusted_paper_height/2, $specs ) ) {
					$imp->rows( $$imp{rows} * 2 );
					$imp->dutch_rows( $$imp{dutch_rows} * 2 );
					$imp->Paper()->height( $imp->used_height() ) if ! $imp->Paper()->height();
					$openprint::log->debug( sprintf(
								'CHECK 2 Work&Tumble Dutch Using Paper %sx%s->%sx%s Image: %s x %s Imposition: %dout:%dx%d+%dx%d',
								$paper_width, $paper_height, $adjusted_paper_width, $adjusted_paper_height/2,
								@$imp{'image_height','image_width','imposition','columns', 'rows', 'dutch_columns','dutch_rows'}
								) ) if DEBUG;
					push @results, $imp;
				} # end foreach imposition
			} # end if grain_direction
			$setup2->rows( $$setup2{rows} * 2 );
			$Paper2->width( $setup2->used_width() ) if ! $$Paper2{width};
			$Paper2->height( $setup2->used_height() ) if ! $$Paper2{height};
			push @results, $setup2;
		} # end if imposition
	} # end if run_style
	return @results;
} # end calc_setup_object

sub get_imposition {
	my ( $project, $do_work_turn, $do_perfecting, $versions, $Paper, $Press ) = @_;

#$log->debug("****** TIME TO PROCESS SHEET SIZES Overrides: $override_width, $override_height	**********");
#$log->debug("Override RunStyle: $runstyle_override");
	my @styles = ();
	@styles = ( 'Sheet Work', 'Web' );
	push @styles, 'Work & Turn', 'Work & Tumble' if $do_work_turn;
	push @styles, 'Perfecting' if $do_perfecting;
	if ( $$project{Runstyles} ) {
		$openprint::log->debug(" *1* Run Styles to consider for $$Press{strid}: style:@styles ** Available runstyle:$$project{Runstyles} perfecting:$do_perfecting") if DEBUG;
		@styles = sets::intersection( @styles, misc::trim(split(',', $$project{Runstyles} ) ) );
		$openprint::log->debug(" *1* Resulting Run Styles to consider for $$Press{strid}: style:@styles") if DEBUG;
	} # end if
	#$openprint::log->debug(" *2* Run Styles to consider for $$Press{strid}: @styles **") if DEBUG;

	return add_imposition( $project, $Paper, $versions, $Press, @styles );
} # end sub

sub add_imposition {
	my ( $project, $Paper, $versions, $Press, @styles ) = @_;
	#$log->debug("***************** START OF ADD IMPOSITION $do_work_turn, $do_perfecting W: $$paper{width} * $$paper{height}	*****************");
	my @impositions;

	#$openprint::log->debug(" ** Run Styles to consider: @styles **") if DEBUG;
	foreach my $run_style ( @styles ) {
		$openprint::log->debug(" ** Processing Run Style: $run_style on $$Paper{width} x $$Paper{height} CutOff: $$project{'Cut Off'}**") if DEBUG;

		my $wt = $run_style =~ /^Work/;

		if ( ! $Paper->cuttable() ) {
			if ( ! ( $run_style eq 'Perfecting' or $run_style eq 'Sheet Work' or $run_style eq 'Web' ) ) {
				$openprint::log->debug("$run_style not possible when stock not cuttable") if DEBUG;
				next;
			} # end if
			# this is usually evelopes or forms
			$openprint::log->debug(" ** Creating No Cut Imposition ** $$project{BleedSize}");
			#push @impositions, {Imposition => 1, Rows => 1, Cols => 1 };
			foreach my $bleed_size ( $$project{BleedSize} ? split(',', $$project{BleedSize} ) : 0 ) {
				foreach my $i ( calc_setup_object( $project, @$project{'image_width','image_height'}, $Paper, $run_style, $Press, $bleed_size ) ) {
					next if $$i{imposition} != 1;
					push @impositions, $i;
				} # end foreach
			} # end foreach bleed
			next;
		} elsif ( ($$Paper{type} eq 'Roll') and $wt and ($Press->specification('W&TonRoll') eq 'N') ) {
			next;
		} # end if

		foreach my $bleed_size ( $$project{BleedSize} ? split(',', $$project{BleedSize} ) : 0 ) {
			foreach my $i ( calc_setup_object( $project, @$project{'image_width','image_height'}, $Paper, $run_style, $Press, $bleed_size ) ) {
				if ( $wt ) {
					if ( $versions and ( ($versions * 2) > $$i{imposition} ) ) {
#$log->debug("Nixing imposition because W&T needds 2* versions > imposition");
						next;
					} # end if
				} # end if

				push @impositions, $i;
			} # end foreach i
		} # end foreach bleed
	} # end foreach runstyle
#if ( DEBUG ) {
	#foreach my $i ( @impositions ) {
#$i->display();
	#} # end foreach
#} # end if
	return @impositions;
} # end sub add_imposition

# A permutation is a hash with an integer value for each version representing the # of times that version appears in the image
# So it begins as a hash indexed by version id.
# Set size starts as imposition

sub permutate_versions {
	my ( $versions, $set_size ) = @_;
# versions is a point to an array of permutations

$openprint::log->debug("$versions, $set_size");
$openprint::log->debug(Data::Dumper::Dumper($versions));
	my @perms;

	if ( $set_size == 1 ) {
		foreach my $v ( @$versions ) {
			$$v{imposition} = 1;
		} # end foreach
		#@perms = @$versions;
		@perms = ( [{1=>@$versions}] );
		return @perms;
	} # end if

	foreach my $P ( permutate_versions( $versions, $set_size-1 ) ) {
$openprint::log->debug(Data::Dumper::Dumper($P));
		foreach my $v ( @$versions ) {
			my %P2 = %$P;
			$P2{$$v{index}}{imposition} += 1;
			push @perms, \%P2;
		} # end foreach
	} # end foreach version

	# remove duplicates
	for ( my $i = 0; $i < @perms; $i += 1 ) {
		for ( my $j = $i+1; $j < @perms; $j += 1 ) {
			my $equal = 1;
			my $pi = $perms[$i];
			my $pj = $perms[$j];

			foreach my $k ( keys %$pi ) {
$openprint::log->debug("PI: $pi, PJ: $pj K: $k");
				if ( $$pi{$k}{imposition} != $$pj{$k}{imposition} ) {
					$equal = 0;
					last;
				} # end if
			} # end foreach k
			if ( $equal ) {
				splice @perms, $j, 1;
				$j -= 1;
			} # end if
		} # end for j
	} # end for i

	return @perms;
} # end sub permutate_versions

# Generate the set of integer partitions of n.
# #  Ex. 5 becomes [5], [4,1], [3,2], [3,1,1], [2,2,1], [2,1,1,1], [1,1,1,1,1]
sub partitions {
	my ( $n ) = @_;

	return []  if $n == 0;
	return [1] if $n == 1;

	my @set;
	foreach my $p ( partitions($n - 1) ) {
		my $append = [@$p, 1];

# Any set that's a singleton or whose first field is less than the
# second, gets the first field incremented. (ie. [3+1], [2,1+1])
		if ( (@$p == 1) or ($$p[-1] < $$p[-2]) ) {
			$$p[-1] += 1;
			push @set, $p;
		} # end if

		push @set, $append;
	} # end foreach
	return @set;
} # end sub partitions


# $versions is a pointer to an array of Version objects, sorted by decreasing quantity
sub do_versions {
	my ( $versions, $impositions ) = @_;
	my @good_impositions = ();
	my %ps;


$openprint::log->debug(Data::Dumper::Dumper($versions));
  my @versions = @$versions;
  
	foreach my $i ( @$impositions ) {
    my @partitions = partitions($$i{imposition});
$openprint::log->debug(Data::Dumper::Dumper(\@partitions));
    foreach my $partition (@partitions) {
      next if @{$partition} > @versions;

			my $i2 = $i->copy();

      $$i2{version_qty} = @{$partition};
			foreach my $v ( @versions ) {
				$$i2{versions}{$$v{index}} = (@{$partition} ? shift @{$partition} : 0);
			} # end foreach v

			push @good_impositions, $i2;
		} # end if
	} # end foreach $i
	return @good_impositions;
} # end sub do_versions

sub convert_impositions {
	my ( $desired_signature_size, $spread_size, $spine, $impositions ) = @_;
	my @good_impositions;
$openprint::log->debug("Convert Impositions: Desired: $desired_signature_size, Spread size: $spread_size,") if DEBUG_CONVERT;
	return @$impositions if $desired_signature_size == 1;

	foreach my $imp ( @$impositions ) {
		my $impo = $$imp{imposition};
		$impo /= 2 if $$imp{runstyle} eq 'Work & Turn' or $$imp{runstyle} eq 'Work & Tumble';
		$$imp{start_imposition} = $impo;
		#$impo = int( $impo / ($spread_size/2) );
		# impo has become max spreads

		my @imps;
		my $start = $impo > $desired_signature_size ? $desired_signature_size : $impo;
$imp->display("Converting From Desired: $desired_signature_size impo: $impo From reverse 1 to $start" ) if DEBUG_CONVERT;
		foreach my $signature_size ( reverse 1 .. $start ) {
		#my $a = int($start/3);
		#$a -= 1 if $a % 3;
		#foreach my $signature_size ( reverse $a .. $start ) {
			next if ! $blocks{$signature_size};
#Now figure out how to cut up the imposition
$openprint::log->debug("Considering sig size: $signature_size") if DEBUG_CONVERT;
			my ( $rows, $cols );
			my $imp_rows = $$imp{rows};
			my $imp_cols = $$imp{columns};
			foreach my $block ( @{$blocks{$signature_size}} ) {
				my ( $col, $row ) = @$block;


				$cols = int( $imp_cols / $col );

				$rows = int( $imp_rows / $row );
				$openprint::log->debug("Trying $signature_size: IMP: $imp_cols x $imp_rows BLOCK: $col x $row Got $cols x $rows") if DEBUG_CONVERT;
				next if ! ( $rows and $cols );
				next if ( $cols % 2 and $$imp{runstyle} eq 'Work & Turn' );
				next if ( $rows % 2 and $$imp{runstyle} eq 'Work & Tumble' );

				my $newimp = $imp->copy();

				$newimp->rows($rows);
				$$newimp{start_rows} = $rows;
				$newimp->columns($cols);
				$$newimp{start_columns} = $cols;
				#$newimp->imposition($rows * $cols);
				if ( $$newimp{image_orientation} == openprint::Imposition::Vertical ) {
					$newimp->image_width( $$newimp{image_width} * $col );
					$newimp->image_height( $$newimp{image_height} * $row );
				} else {
					$newimp->image_width( $$newimp{image_width} * $row );
					$newimp->image_height( $$newimp{image_height} * $col );
				} # end if
				$newimp->spread_columns( $col );
				$newimp->spread_rows( $row );
				$newimp->display( 'To: ' ) if DEBUG_CONVERT;

        if ( $spread_size == 2 and $signature_size > 1 ) {
          if ( $spine eq 'width' ) {
            if ( $$imp{image_orientation} == openprint::Imposition::Vertical ) {
              if ( $row < 2 ) {
                $openprint::log->debug("Next because page_row $row == 1 and $$imp{image_orientation} eq Vertical and spine is on the width") if DEBUG_CONVERT;
                next;
              }
            } else {
              if ( $col < 2 ) {
                $openprint::log->debug("Next because page_col $col == 1 and $$imp{image_orientation} eq Horizontal and spine is on the width") if DEBUG_CONVERT;
                next;
              }
            }
          } else {
            if ( $$imp{image_orientation} == openprint::Imposition::Vertical ) {

              if ( $col < 2 ) {
                $openprint::log->debug("Next because page_col $col == 1 and $$imp{image_orientation} eq Vertical and spine is on the height") if DEBUG_CONVERT;
                next;
              }
            } else {
              if ( $row < 2 ) {
                $openprint::log->debug("Next because page_row $row == 1 and $$imp{image_orientation} eq Horizontal and spine is on the height") if DEBUG_CONVERT;
                next;
              }
            }
          }
        }
        if ( $newimp->used_width() <= $newimp->sheet_width() and $newimp->used_height() <= $newimp->sheet_height() ) {
				push @imps, $newimp;
      } elsif (DEBUG_CONVERT) {
        $newimp->display("Too big: " . $newimp->used_width().' < '.$newimp->sheet_width() . ' and '. $newimp->used_height().' < '. $newimp->sheet_height() );
      }
			} # end foreach block
			#last if @imps and (@imps[@imps-1]->imposition() >= 4);
			#last if @imps and ($signature_size < $start/2);
		} # end foreach signature_size
		push @good_impositions, @imps;
	} # end foreach
	return @good_impositions;
} # end sub convert_impositions

sub decrease_imposition {
	my @results;

	foreach my $imposition ( @_ ) {
		next if ( ($$imposition{columns} * $$imposition{rows}) <= 1 );

		if ( $$imposition{dutch_columns} ) {
			my $imp1 = $imposition->copy();
			$imp1->dutch_rows( 0 );
			$imp1->dutch_columns( 0 );
			push @results, $imp1;

			my $imp2 = $imp1->copy();
			$imp2->columns( $$imposition{dutch_columns} );
			$imp2->rows( $$imposition{dutch_rows} );
			push @results, $imp2;
		} elsif ( $$imposition{runstyle} eq 'Work & Turn' ) {
			{
				my $imp1 = $imposition->copy();
				$imp1->runstyle( 'Sheet Work' );
				$imp1->columns( $$imp1{columns} / 2 );
				push @results, $imp1;
			}

			if ( $$imposition{columns} > 2 ) {
# Consider removing a column from each half.
				my $imp1 = $imposition->copy();
				$imp1->columns( $$imp1{columns} - 2 );
				push @results, $imp1;
			}

			if ( $$imposition{rows} > 1 ) {
# Consider knocking a row off
				my $imp1 = $imposition->copy();
				$imp1->rows( $$imp1{rows}-1 );
				push @results, $imp1;
			}

			#f ( $$imposition{rows} >= 2 ) {
			#foreach my $row ( 2 .. $$imposition{rows} ) {
			#	my $imp1 = $imposition->copy();
			#	$imp1->rows( $$imp1{rows} - ( $row -1 ) );
			#	push @results, $imp1;
			#} # end foraech
			# # end if
		} elsif ( $$imposition{runstyle} eq 'Work & Tumble' ) {
			#if ( $$imposition{rows} >= 2 ) {
				my $imp1 = $imposition->copy();
					$imp1->runstyle( 'Sheet Work' );
				$imp1->rows( $$imp1{rows} / 2 );
				push @results, $imp1;
			#} # end foraech
			#if ( $$imposition{columns} >= 2 ) {
				#foreach my $columns ( 2 .. $$imposition{columns} ) {
					##my $imp2 = $imposition->copy();
					#$imp2->columns( $$imp2{columns} - ( $columns -1 ) );
					#push @results, $imp2;
				#}
			#} # end if

		} else {

			if ( $$imposition{rows} >= 2 ) {
				foreach my $row ( 2 .. $$imposition{rows} ) {
					my $imp1 = $imposition->copy();
					$imp1->rows( $$imp1{rows} - ( $row -1 ) );
					push @results, $imp1;
				} # end foraech
			} # end if

			if ( $$imposition{columns} >= 2 ) {
				foreach my $columns ( 2 .. $$imposition{columns} ) {
					my $imp2 = $imposition->copy();
					$imp2->columns( $$imp2{columns} - ( $columns -1 ) );
					push @results, $imp2;
				}
			} # end if

		} # end if
	} # end foreach

	return @results;
} # end sub decrease_imposition

sub get_all_impositions {
#Carp::cluck("Really don't want to use get_all_impositions");
#map { $openprint::log->debug( $_ ) } @_;
	my @results = @_;
	my @imps = @_;

	while ( @imps = decrease_imposition( @imps ) ) {
		#@imps = get_all_impositions( @imps );
		push @results, @imps;
	}
	return @results;
}

sub breakup_impositions {
	my ( $I ) = @_;

	my @imposition = @_;

	my @results = ( [$I] );
	if ( $I->dutch_columns() ) {
		my $I2 = $I->copy();
		$I2->dutch_columns(0);
		$I2->dutch_rows(0);
		my $I3 = $I->copy();
		$I3->columns( $I->dutch_columns() );
		$I3->rows( $I->dutch_rows() );
		push @results, [ $I2, $I3 ];
		@imposition = ( $I2, $3 );
	} # end if

	foreach my $i ( @imposition ) {
		my @result;
		foreach my $p1 ( openprint::imposition::partitions( $$i{columns} ) ) {
			foreach my $p2 ( openprint::imposition::partitions( $$i{rows} ) ){

			} # end foreach p2
		} # end foreach p1

	} # end foreach

} # end sub breakup_impositions

sub sort {
	return sort {
		if ( $$a{runstyle} ne $$b{runstyle} ) {
			return $$a{runstyle} cmp $$b{runstyle};
		} elsif ( $$a{pages} != $$b{pages} ) {
			return $$b{pages} <=> $$a{pages};
		} elsif ( $$a{imposition} != $$b{imposition} ) {
			return $$b{imposition} <=> $$a{imposition};
		} elsif ( $$a{columns} != $$b{columns} ) {
			return $$a{columns} <=> $$b{columns};
		} # end if
		my $APaper = $a->Paper();
		my $BPaper = $b->Paper();
		if ( $$APaper{width} != $$BPaper{width} ) {
			return $$APaper{width} <=> $$BPaper{width};
		} elsif ( $$APaper{height} != $$BPaper{height} ) {
			return $$APaper{height} <=> $$BPaper{height};
		} # end if
		my $APress = $a->Press();
		my $BPress = $b->Press();
		return $$APress{strid} cmp $$BPress{strid};
	} @_;
}

sub cut {
	my ( $I ) = @_;

	my $i1 = $I->copy();
	my @Results;

	if ( $$I{runstyle} eq 'Work & Turn' ) {
		$i1->runstyle( 'SheetWork' );
		$i1->columns( $$i1{columns} / 2 );
		if ( $$I{dutch_columns} ) {
			$i1->dutch_columns( $$i1{dutch_columns} / 2 );
		} # end if
		$i1->quantity($i1->quantity()*2);
		push @Results, $i1;

	} elsif ( $$I{runstyle} eq 'Work & Tumble' ) {
		$i1->runstyle( 'SheetWork' );
		$i1->rows( $$i1{rows} / 2 );
		$i1->dutch_rows( $$i1{dutch_rows} / 2 ) if $$I{dutch_rows};
		$i1->quantity($i1->quantity()*2);
		push @Results, $i1;

	} elsif ( $$I{dutch_columns} ) {
		$i1->dutch_rows( 0 );
		$i1->dutch_columns( 0 );
		my $i2 = $I->copy();
		$i2->rows( $I->dutch_rows() );
		$i2->columns( $I->dutch_columns() );
		$i2->image_orientation( $I->image_orientation() == openprint::Imposition::Vertical ? openprint::Imposition::Horizontal : openprint::Imposition::Vertical );
		$i2->dutch_rows( 0 );
		$i2->dutch_columns( 0 );
		push @Results, $i1, $i2;
	} elsif ( ( $I->layout_width() >= $I->layout_height() ) and ( $$I{columns} > 1 ) ) {
		$i1->columns( int($$I{columns} / 2) );
		if ( ! ( $$I{columns} % 2 ) ) {
			$i1->quantity( $i1->quantity() * 2 );
			push @Results, $i1;
		} else {
			my $i2 = $I->copy();
			$i2->columns( $$I{columns} - $$i1{columns} );
			push @Results, $i1, $i2;
		} # end if
	} elsif ( ( $I->layout_width() < $I->layout_height() ) and ( $$I{rows} > 1 ) ) {
		$i1->rows( int($$I{rows} / 2) );
		if ( ! ( $$I{rows} % 2 ) ) {
			$i1->quantity( $i1->quantity() * 2 );
			push @Results, $i1;
		} else {
			my $i2 = $I->copy();
			$i2->rows( $$I{rows} - $$i1{rows} );
			push @Results, $i1, $i2;
		} # end if
	} elsif ( ( $$I{columns} >= $$I{rows} ) and ( $$I{columns} > 1 ) ) {
		my $i2 = $I->copy();
		$i1->columns( int($$I{columns} / 2) );
		$i2->columns( $$I{columns} - $$i1{columns} );
		push @Results, $i1, $i2;
	} elsif ( $$I{rows} > 1 ) {
		my $i2 = $I->copy();
		$i1->rows( int($$I{rows} / 2) );
		$i2->rows( $$I{rows} - $$i1{rows} );
		push @Results, $i1, $i2;
	} # end if
	foreach my $i ( @Results ) {
$i->display('Cut to ');
	}
	return @Results;
} # end sub cut_imposition
# Takes an array of impositions(Folds) and merges duplicates.
sub compact {
    my @results;
    while ( @_ ) {
        my $Imposition = shift @_;
        $Imposition = $Imposition->copy();
        push @results, $Imposition;

        for ( my $index = 0; $index < @_; $index += 1 ) {
            if ( $$Imposition{imposition} == $_[$index]{imposition} and $$Imposition{spreads} == $_[$index]{spreads} ) {
                $$Imposition{quantity} += $_[$index]->quantity();
                splice @_, $index, 1;
                $index -= 1;
            } # end if
        } # end for each index
    } # end while @_
    return @results;
} # end sub compact_impositions



1;
__END__
