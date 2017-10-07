package eprint::imposition;
use strict;
use warnings;
no warnings qw(uninitialized);

use base qw(Exporter);
our @EXPORT = qw(
    convert_to_old        desired_signature_size 
    convert_to_signature  lf_imposition
);

use Data::Dumper;
use Memoize;
use List::Util qw(sum max);
use POSIX qw(floor ceil);

use eprint::impositionObject ();

# Convert the return from the new imposition code into the old style object.
# Any multi-version processing is also still done here.
sub convert_to_old {
    my ($dbh, $project, $press, $sheet, $style, $imposition, $rotation) = @_;

    # Ask imposition to figure out the final image size it used again (there
    # can be multiple and rotations of it).
    my ($width, $height) = (1,1); # @{ ($imposition->images)[0] };

    # The total number of images in this imposition.
    my $slots = $imposition->card;

    # These should always exist but they don't for all presses so we check
    # existance first to avoid an error on equipment lookup.
    my $grip   = exists $press->{grip}   && !$project->{override}{margin} ? $press->{grip}   : 0;
    my $gutter = exists $press->{gutter} && !$project->{override}{margin} ? $press->{gutter} : 0;

    # Create a nice string version of the grain. TODO Should be external.
    my $grain = !defined $imposition->grain ? 'Mixed'
              :          $imposition->grain ? 'Height'
              :                               'Width';

    # Non-dutch (mixed grain) impositions can still get the old rows ×
    # columns fields filled out.
    my ($rows, $cols);
    if ($grain ne 'Mixed') {
        # We assume that there is NO DUTCH LAYOUT, so we look at the initial
        # cut direction and count the number of children down and across.
        my @children = $imposition->children;

        my ($x, $y);

        if (@children) {
            $x = scalar @children              || 1; # Child count.
            $y = scalar $children[0]->children || 1; # First child's children count.
        }
        # If the image fits exactly to the sheet.
        elsif ($imposition->card == 1) {
            ($x, $y) = (1,1);
        }
        else { die "Invalid imposition.\n"; }
    
        ($rows, $cols) = $imposition->cut ? ($y, $x) : ($x, $y);
    }

    # Multi-version needs it's layouts determined, single version is just
    # the full sheet.
    my $versions = $project->{versions};
    my $n        = $style =~ /^W[TF]$/ ? $slots/2 : $slots;

    my $layouts  = (%$versions) ? version_layouts($n, $versions)
                                : [[[{ n         => 0,
                                      label     => 'Signature',
                                      requested => 100,
                                      final     => 100,
                                      slots     => $n,
                                }]]]
    ;

    # TEMPORARY: For now we'll treat each as a totally new imposition.
    # Really we want to only recalculate the running costs so the
    # whole layout set will travel with the invidiual imposition until
    # we do running (no setup, etc.) comparison in pricing.
    my @impositions;

    for my $layout (@$layouts) {
        # Mirror back across the slots (*2) to display W&T/F
        # correctly. Note: Quick and Dirty deep copy needed as the
        # return is memoized.
        my $corrected = ($style =~ /^W[TF]$/)
            ? [map{[map{$a={%$_};$a->{slots}*=2;$a}@$_]}@$layout]
            : $layout;
        
        # Create the new imposition.
        my $imp = eprint::impositionObject->new($press->{id});

		my $orientation = $grain eq 'Height' ? 'Horizontal' : 'Veritcal'; 

        # Load up the old imposition object.
        $imp->set(
            $slots,                 # Image 'slots'
            $style,                 # Run style
            $grain,                 # Grain direction
            $rotation,              # Rotate sheet
            ($rows, $cols),         # Rows × Cols
            ($width, $height),      # Final image width × height
            $orientation,           # Orientation
            $sheet,                 # Paper
            $corrected,             # Layout (multi-version)
            $imposition,            # Layout geometry tree.
            $project->{colour_bar}, # Colour bar size
            $grip,                  # Grip size
            $gutter,                # Gutter size
        );
        
        push @impositions, $imp;
    }

    return @impositions;
}

# Multi-page is still done the old way. Basic impositions are post-processed
# to see if 'valid' multi-page signatures can be created from them. NOTE - See
# Bugzilla for a number of significant issues with this section
sub desired_signature_size {
    my ($desired_signature_size, $impositions) = @_;
  
    my $max_setup = max(map { $_->{setup} } @$impositions);
    if ($max_setup == 9) {
        # right now 36 pg signatures are not a good thing, so until we can
        # figure when we do want them we are just going to do without. will -
        # jan 21/03 e.x. on a 112pg book we want 3 32s instead of 3 36s. for
        # the most part 32s are more better.
        $max_setup = 8;
    }
    elsif ($max_setup == 18) {
        # create the same rule for 2pg Signatures.
        $max_setup = 16;
    }

    if ($desired_signature_size > $max_setup) {
        $desired_signature_size = $max_setup;
    }
    else {
        # OK here is where we handle optimizing signature sizes.  This is a
        # simple start that replaces the logic we used to have in calc_book.js

        # e.x.: 4 - 3 = 1;
        my $empty_slots = $max_setup - $desired_signature_size;
        my $new_layout  = $desired_signature_size - $empty_slots;

        # If the new layout is exactly half of the max then use it.
        if ($new_layout * 2 == $max_setup) {    
            $desired_signature_size = $new_layout;
        }
        elsif ($desired_signature_size == 5) {
            # until we figure out when 20pg sigs are a good thing, we don't
            # want to do them cause there is almost always a better format.
            $desired_signature_size = 4;
        }
    }
    return $desired_signature_size;
}

sub convert_to_signature {
    my ($desired_signature_size, $imp) = @_;

    my $setup   = $imp->{setup};

    my ($r, $c) = @{ $imp }{ qw(rows cols) };

    $imp->setSpreadRows($imp->{rows});
    $imp->setSpreadCols($imp->{cols});
    $imp->setSpreads($desired_signature_size);

    if (        $setup == $desired_signature_size
         || int($setup / $desired_signature_size) == 1
    ) {

        # Can't have a 1 out W&T
        if (    $imp->{run_style} ne 'WT'
            and $imp->{run_style} ne 'WF')
        {
            # Make signature image out of spread Image
            $imp->setRows(1);
            $imp->setCols(1);
            $imp->setSetup(1);

            return $imp;
        }
    }
    elsif ($setup > $desired_signature_size) {

        # Now figure out how to cut up the imposition
        my ($rows, $cols);
        my $imp_rows = $imp->{rows};
        my $imp_cols = $imp->{cols};
        if ($imp_rows >= $desired_signature_size) {
            $rows = int($imp_rows / $desired_signature_size);
            $cols = $imp_cols;
        }
        else {
            $rows = 1;
            my $temp = $desired_signature_size / $imp_rows if $imp_rows;
            $temp = int($temp) == $temp ? $temp : $temp + 1;
            if ($imp_cols > $temp) {
                $cols = int($imp_cols / $temp);
            }
            else {
                $cols = 1;
            }

        }

        if ($rows * $cols * $desired_signature_size != $setup) {
            my $row_check = $rows;
            my $col_check = $cols;

            if ($imp_cols >= $desired_signature_size) {
                $cols = int($imp_cols / $desired_signature_size);
                $rows = $imp_rows;
            }
            else {
                $cols = 1;
                my $temp = $desired_signature_size / $imp_cols if $imp_cols;
                $temp = int($temp) == $temp ? $temp : $temp + 1;
                if ($imp_rows > $temp) {
                    $rows = int($imp_rows / ($temp));
                }
                else {
                    $rows = 1;
                }
            }
            if ($row_check * $col_check > $rows * $cols) {
                $rows = $row_check;
                $cols = $col_check;
            }
        }

        $imp->setRows($rows);
        $imp->setCols($cols);
        $imp->setSetup($rows * $cols);
        if ((    $imp->{'RotateSheet'}
             and $imp->{'GrainDirection'} eq 'width')
            or (    $imp->{'RotateSheet'} == 0
                and $imp->{'GrainDirection'} eq 'height')

          )
        {
            $imp->setImageWidth($imp->{image_width} / $imp->{cols});
            $imp->setImageHeight($imp->{image_height} / $imp->{rows});
        }
        else {
            $imp->setImageWidth($imp->{image_width} / $imp->{rows});
            $imp->setImageHeight($imp->{image_height} / $imp->{cols});
        }

       return $imp;
    }

    return ();
}


sub descrease_imposition { # [sic]
    # When refactoring this please change to correct spelling of 'decrease'.

    my ($imposition) = @_;
    
    if ($$imposition{'Rows'} > $$imposition{'Cols'}) {
        $$imposition{'Rows'} -= 1;
    }
    else {
        $$imposition{'Cols'} -= 1;
    }
    $$imposition{'Imposition'} = $$imposition{'Rows'} * $$imposition{'Cols'};

    return;
}


#
# LARGE FORMAT IMPOSITION
#
# Large format doesn't share the new imposition code as it was developed
# concurrently by different developers and the imposition goals are
# significantly different (at this time).

sub lf_imposition {
    my ($dbh, $project, $press, $substrate, $style) = @_;

    my ($w, $h) = @$substrate{qw(width height)};

    if (exists $press->{grip} and defined $press->{grip}) {
        $w -= $press->{grip};
    }

    # The imposition method varies with the substrate format.
    my $impose = $substrate->{type} eq 'roll'
        ? \&get_lf_roll_impositions : \&get_lf_sheet_impositions;

    my @lf_impositions = $impose->($project, $substrate, $w, $h);

    my @impositions;
    foreach my $lf_imp (@lf_impositions) {
        my $imp = eprint::impositionObject->new($press->{id});

        my $slots = $lf_imp->{rows} * $lf_imp->{cols};

        my $map = {
            Setup            => $slots,
            RotateSheet      => $lf_imp->{rotate},
            Rows             => $lf_imp->{rows},
            Cols             => $lf_imp->{cols},
            SpreadRows       => $lf_imp->{spread_rows},
            SpreadCols       => $lf_imp->{spread_cols},
            StitchSize       => $lf_imp->{stitch_size},
            CutOff           => $lf_imp->{cutoff},

            Spreads          => $lf_imp->{spread_rows}
                              * $lf_imp->{spread_cols},


            ImageWidth       => $project->{width},
            ImageHeight      => $project->{height},

            Setup            => $lf_imp->{rows} * $lf_imp->{cols},

            GrainDirection   => undef,
            ImageOrientation => undef,
            Style            => $style,
            Paper            => $substrate,
            Layout           => [[{ n         => 0,
                                     label     => 'Inkjet Output',
                                     requested => 100,
                                     final     => 100,
                                     slots     => $slots,
                                }]],
            tree             => {}, # A dummy reference.
        };

        while (my ($key, $value) = each %$map) {
            my $command = "set$key";
            $imp->$command( $value );
        }

        push @impositions, $imp;
    }

    return @impositions;
}

sub get_lf_roll_impositions {
    my ($project, $substrate, $w, $h) = @_;

    my @impositions;

    foreach my $dimension (qw( width height )) {
        if ( $project->{$dimension} <= $w) {
            push @impositions, {
                stitch_size => 0,
                rows        => 1,
                cols        => floor($w / $project->{$dimension}),
                spreads     => 1,
                spread_rows => 1,
                spread_cols => 1,
                rotate      => $dimension eq 'height',
                cutoff      => (  $dimension eq 'height'
                                ? $project->{width}
                                : $project->{height}),
            };
        }
    }

    return @impositions if scalar @impositions;

    # Neither dimension fits without tiling.
    my @dimensions = qw( image_height image_width );
    my @col_names  = qw( rows         cols        );

    foreach my $dimension (0, 1) {
        my %spreads = ( rows => 1, cols => 1 );

        $spreads{ $col_names[$dimension] } = ceil(
            $project->{ $dimensions[$dimension] } / $w
        );

        my $stitch_size
            = ($spreads{ $col_names[$dimension]      } - 1)
            *  $project->{ $dimensions[$dimension ^ 1] };

        push @impositions, {
            stitch_size => $stitch_size,
            rows        => 1,
            cols        => 1,
            spread_rows => $spreads{rows},
            spread_cols => $spreads{cols},
            rotate      => $dimension,
            cutoff      => $project->{ $dimensions[$dimension ^ 1] },
        };
    }

    return @impositions;
}

sub get_lf_sheet_impositions {
    my ($project, $sheet, $w, $h) = @_;

    my @impositions;

    my @dimensions = qw( height width );

    foreach my $dimension (0, 1) {
        my $x = $dimensions[$dimension    ];
        my $y = $dimensions[$dimension ^ 1];

        if (   $project->{$x} < $h
            && $project->{$y} < $w ) {

            my $cols = floor( $h / $project->{$x} );
            my $rows = floor( $w / $project->{$y} );

            push @impositions, {
                stitch_size => 0,
                rows        => $rows,
                cols        => $cols,
                spread_rows => 1,
                spread_cols => 1,
                rotate      => $dimension,
            };
        }
    }

    return @impositions if scalar @impositions;

    foreach my $dimension (0, 1) {
        my $x = $dimensions[$dimension    ];
        my $y = $dimensions[$dimension ^ 1];

        my $spread_rows = ceil($project->{$x} / $h);
        my $spread_cols = ceil($project->{$y} / $w);

        my $stitch_size
            = ( $spread_cols * $sheet->{width}  * ($spread_rows - 1) )
            + ( $spread_rows * $sheet->{height} * ($spread_cols - 1) );

        push @impositions, {
            rows        => 1,
            cols        => 1,
            stitch_size => $stitch_size,
            spread_rows => $spread_rows,
            spread_cols => $spread_cols,
            rotate      => $dimension,
        };
    }

    return @impositions;
}


#
# MULTI-VERSION
#

# Given an imposition setup (n slots on a press sheet) and a list of versions
# (labels => percentages) return a set of possible impositions to produce the
# versions. Follow through for exact methods of generating the set.
memoize('version_layouts', 
   # Version labels and order doesn't effect the end result.
   NORMALIZER => sub {my ($s,$v)=@_; join ',', $s, sort {$a<=>$b} values %$v},
   LIST_CACHE   => 'MEMORY',
   SCALAR_CACHE => 'MEMORY',
);
sub version_layouts {
    my ($slots, $versions) = @_;

    # Given the number of versions determine all the unique groupings where no
    # version spans multiple press sheets (integer partitions). TODO: We
    # really should span one version across multiple sheets as situations like
    # a setup of 4 with version % of 40,30,20,10 will probably work best that
    # way (only one plate change, 0 waste for 2A2B, 2C1D1A layout).
    my @partitions = partitions(scalar keys %$versions);

    # If there're less slots than versions we need to discard the first n
    # partitions that contain layouts with more than x slots.
    @partitions = grep { $_->[0] <= $slots } @partitions
        if $slots < scalar keys %$versions;

    # We need the versions to be in percentile order so we can close groupings
    # in an easier fashion.
    my $i = 0;
    my @nversions = map  { $i++; { n         => $i,
                                   label     => $_, 
                                   requested => $versions->{$_}, }}
                    sort { $versions->{$a} <=> $versions->{$b}    }
                         keys %$versions;
    undef $i;

    # It's important to note that the partitions are processed in ascending
    # order of plate changes.
    my (%result, $max_waste);
    foreach my $set (@partitions) {
        my @remaining = @nversions;

        # Choose which n versions will go on the current sheet (n is a single
        # integer from a partion) until all versions are gone.
        my ($selected, @layout);
        foreach my $n (@$set) {
            ($selected, @remaining) = get_matching_versions($n, @remaining);

            # Determine how the selected version get laid out on the sheet.
            push @layout, match_versions($slots, $selected);
        }

        # Determine the layout wastage.
        my $wastage = sum( map { map { $_->{final} } @$_ } @layout ) - 100;

        # Subsequent layouts use the same or more plates, so they must use
        # less waste or they aren't worth considering.
        if (not defined $max_waste or $wastage < $max_waste) {
            $max_waste = $wastage;
            $result{@layout} = \@layout;
        }

        # Note: Run overs are variable based on each form's run length, so
        # wastage is not the only factor. However it's felt 
    }

    return [values %result];
}


# Generate the set of integer partitions of n. TODO: Optimize.
#  Ex. 5 becomes [5], [4,1], [3,2], [3,1,1], [2,2,1], [2,1,1,1], [1,1,1,1,1]
memoize('partitions');
sub partitions {
    my $n = shift;
   
    return []  if $n == 0;
    return [1] if $n == 1;

    my @set;
    for my $p ( partitions($n - 1) ) {
        my $append = [@$p, 1]; # Append 1 to each elem.

        # Any set that's a singleton or whose first field is less than the
        # second, gets the first field incremented. (ie. [3+1], [2,1+1])
        if ( @$p == 1 or $p->[-1] < $p->[-2] ) {
            $p->[-1]++;
            push @set, $p;
        }

        push @set, $append;
    }
    return @set;
}


# Given a set of version percentages and n slots to fill, choose the n
# versions that have the least standard deviation. TODO: This is not actually
# how it works. TODO: The full set is in n choose r but that grows insanely
# quick for us, a possible middle point is successive linear slices of the
# ordered array (think slot sizes window sliding over the array). We still
# rely on a standard deviation in this case which in many cases won't be the
# best way to lay it out: Eg. (3,1) partitions, 12 slots, 4 versions (A 31.25,
# B 25, C 25, D 18.75). stddev telss us BCD belong together, however given 12
# slots 5A:4B:3D fills it with no waste and C fills the second. This brings
# back my thinking of treating it all as ratios with a common divisor... other
# ideas?  TODO: We may not want to # keep the cached values (version
# percentages) around for long?
memoize('get_matching_versions',
   NORMALIZER => sub { my($s,@v)=@_; join ',', $s, map {$_->{requested}} @v; }
);
sub get_matching_versions {
    my ($n, @versions) = @_;

    # The simple case of we only need one or we need them all. We can do the
    # first because partitions are always in descending order.
    return [ shift @versions ], @versions if $n == 1;
    return \@versions                     if $n >= @versions;

    # We'll do a linear scan (which we can do since they're sorted) over the
    # requested percentages and choose the n closest together. 
    my @percentages = map { $_->{requested} } @versions;

    my ($start, $min);
    for my $i (0..$#percentages - $n) {
        my $stddev = stddev([ @percentages[$i..$i + $n] ]);
        
        if (not defined $min or $stddev < $min) {
            $min   = $stddev;
            $start = $i;
        }
    }
    my @selected = splice @versions, $start, $n;

    return \@selected, @versions;
}


# Given n slots on a press sheet and m versions to try to fit on it (where n
# >= m at all times), determine how to fit them closest to their requested
# percentages. TODO This is still the old crap function, it needs WORK!
sub match_versions {
    my ($setup, $versions) = @_;

    # For now we'll continue to humour the matching function and put the
    # labels and percentages into two separate lists. TODO: Rework!
    my (@keys, @values);
    for my $v (@$versions) {
        push @keys,   [$v->{n}, $v->{label}];
        push @values, $v->{requested};
    }

    my @adjusted_values = @values;
    my @adjustment_keys = (1) x @values;
    my @result;

    for (0..($setup - @values - 1)) {
        my $largest_element = 0;
        my $largest_index   = 0;

        for my $j (0..$#adjusted_values) {
            if ($adjusted_values[$j] > $largest_element) {
                $largest_element = $adjusted_values[$j];
                $largest_index   = $j;
            }
        }

        $adjustment_keys[$largest_index]++;

        $adjusted_values[$largest_index] =
          $values[$largest_index] / $adjustment_keys[$largest_index];
    }

    my $largest_element = 0;
    my $largest_index   = 0;
    for my $j (0..$#adjusted_values) {
        if ($adjusted_values[$j] > $largest_element) {
            $largest_element = $adjusted_values[$j];
            $largest_index   = $j;
        }
    }
    for my $i (0..$#adjusted_values) {
        $adjusted_values[$i] = $largest_element * $adjustment_keys[$i];
    }

    # And now convert back. The body _really_ needs to be rewritten.
    for my $i (0..$#adjustment_keys) {
        push @result, {
            n         => $keys[$i][0],
            label     => $keys[$i][1],
            requested => $values[$i],
            final     => $adjusted_values[$i],
            slots     => $adjustment_keys[$i],
        };
    }

    return \@result;
}


# Standard deviation. TODO Replace with XS function for speed?
sub stddev {
    my $array = shift;
    
    my $elems  = scalar @$array;
    my $sum    = 0;
    my $sum_sq = 0;
    
    for (@$array) {
        $sum    += $_;
        $sum_sq += ($_ **2);
    }

    # Floating point errors can cause negative results, for our purposes
    # anything that close can just be 0.
    my $result = $sum_sq/$elems - (($sum/$elems) ** 2);

    return ($result <= 0) ? 0 : sqrt($result);
}


1;
