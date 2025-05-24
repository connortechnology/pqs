package eprint::Service::Printing::Validate;
use strict;
use warnings;
no warnings qw(uninitialized);

use base qw(Exporter);
our @EXPORT = 'munge';

use Data::Dumper;
use eprint::Config;
use eprint::project qw(:common);
use List::Util		qw(sum);
use Math::Round;

use constant VARNISHES        => qw(gloss matte);
use constant DEFAULT_COVERAGE => eprint::Config->get('Printing' => 'default_coverage');

# Change the specs hash into a somewhat better data structure.
sub munge {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    #$openprint::log->("munge start ".Dumper($specs));
    # 'Detailed' mode signatures aren't allowed to calculate until the user
    # has viewed them (display() function removes 'needs_view' flag).
    if ($specs->{needs_view}) {
      print STDERR "Signature needs viewing for detailed mode\n";
    }

    my @qtys         = get_quantities($log, $dbh, $pid);
    my $project_type = get_type($log, $dbh, $pid);
    my $press_type   = get_press_type($log, $dbh, $pid, $sid);

    # This whole section is incredibly kludgy.
    my $spread    = spread($dbh, $press_type, $project_type, $specs, $pid);
    my $versions  = versions($specs, $qtys[0]);
    my $overrides = overrides($specs, $variable->{user_type});
    $openprint::log->debug("HAVE OVERRIDES: ", Dumper($overrides)) if %$overrides;

    #delete $specs->{$_} for keys %$specs;

    $specs->{spread}    = $spread;
    $specs->{versions}  = $versions;
    $specs->{overrides} = $overrides;
    #$openprint::log->debug( "munge end ".Dumper($specs));
    return;
}

sub rfq_only {
	my ( $dbh, $pid ) = @_;
	return $dbh->selectrow_array(q{ SELECT rfq_only FROM tbl_projects WHERE lngprojectindex = ?  }, undef, $pid);
}
sub product_only {
	my ( $dbh, $pid ) = @_;
	return $dbh->selectrow_array(q{
		SELECT product FROM tbl_projects WHERE lngprojectindex = ?
	}, undef, $pid);
}


# Extract the spread information from the printing form.
sub spread {
  my ($dbh, $press_type, $project_type, $specs, $pid) = @_;

  my %spread;

  # TEMPLATE AND DIMENSIONS
  #
  # TODO: Do something other than just accept these as-is and make cleaner.
  $spread{template} = $specs->{template};
  $spread{template} =~ tr/0-9a-zA-Z//cd;

  # Make sure the project dimensions are valid positive reals. TODO: This
  # doesn't make sure they're there, do that too.
  for (keys %$specs) {
    next unless /^(f(?:lat|inal))_(width|height)$/;
    my ($type, $dim) = ($1, $2);

    my $value = $specs->{"${type}_$dim"};
    $value =~ tr/0-9.//cd;

    die "Invalid dimesion for $type $dim. It must be a positive real number."
    unless defined $value && $value > 0 && $value =~ /^\d+\.?\d*$/;

    $spread{$type}{$dim} = $specs->{"${type}_$dim"};
  }
  # Multipage interior spreads don't pass their dimensions.
  #
  # die "Invalid dimensions"
  #     unless $spread{flat}{width} && $spread{flat}{height};

  $spread{gatefold_lip} = $specs->{gatefold_lip}+0 if $specs->{gatefold_lip};

  # Colour critical
  $spread{colourcritical_extra_waste} = $specs->{colourcritical_enabled} ? $specs->{colourcritical_extra_waste} : 0;
  $spread{colourcritical_make_ready} = $specs->{colourcritical_enabled} ? $specs->{colourcritical_make_ready} : 0;


  # BLEED, COLOUR BARS, AND REGISTRATION
  #
  $spread{bleed} = [0,0,0,0];

  # See if the user chosen a bleed, and if so what size it is.
  my $size = $specs->{bleed_size};
  #print STDERR "bleed $size";
  $size =~ tr/0-9.+-//cd;
  #print STDERR " bleed $size \n";

  # If only one bleed side is selected then we must force it into an
  # array ref.
  if ($specs->{bleed_sides} && ref $specs->{bleed_sides} ne 'ARRAY') {
    $specs->{bleed_sides} = [ $specs->{bleed_sides} ];
  }

  # If the user has defined a bleed size we'll map that to each side they
  # selected. For multipage right is considered the face and left the spine.
  if ($size and $size =~ /^-?\d+\.?\d*$/ and $size > 0) {
    for my $side (@{ $specs->{bleed_sides} }) {
      $side =~ tr/0-3//cd;
      next unless defined $side;

      $spread{bleed}[$side] = $size + 0;
    }
  }

  # The user's grain direction preference.
  $spread{grain} = $specs->{grain_direction};

  # Do they want a colour bar for this spread?
  $spread{colour_bar} = ($specs->{colour_bar}) ? 1 : 0;

  # COLOUR AND COATINGS 
  $spread{side} = colours_coatings($specs); 

  # Metal Effects
  $spread{metal_effects} =     $specs->{s0_metal_effects} 
  || $specs->{s1_metal_effects};

  # Chemical Emboss
  $spread{chem_emboss} =       $specs->{s0_chem_emboss} 
  || $specs->{s1_chem_emboss};

  #Screen Printing Foil
  $spread{screen_foil} = 	     $specs->{s0_foil} && $specs->{s0_foil} ne 'None' ? 1 : 0;
  $spread{screen_foil}++  if   $specs->{s1_foil} && $specs->{s1_foil} ne 'None';

  $spread{underbase} = 	     $specs->{underbase} eq 'Discharge' ? 1 : 0;

  # SUBSTRATE (STOCK)
  $spread{stock} = $project_type ne 'ScreenItem' 
  ? stock($dbh, $specs) 
  : { substrate => 'item' };

  # Large format options.
  $spread{large_format} = {
    mounting => $specs->{mounting_type},
    binding  => $specs->{bind_method},

    quality  => [ $specs->{s0_quality} ,     $specs->{s1_quality}      ],
    coverage => [ $specs->{s0_ink_coverage}, $specs->{s1_ink_coverage} ],
    laminate => [ $specs->{s0_laminate},     $specs->{s1_laminate}     ],
  } if $press_type eq 'inkjetprinter';

  # A jig is required to process this screen surface?
  $spread{screen_jig} = $specs->{jig_required} 
  if $press_type eq 'screen' && $project_type eq 'ScreenItem';

  # Number of sheets to put into the pad.
  $spread{pad_sheets}   = $specs->{pad_sheets}; 

  # Additional plates are required to print this (int).
  $spread{add_plates}   = $specs->{add_plates}; 
  $spread{colour_changes} = colour_changes($specs);

  $spread{rfq_only}     = rfq_only($dbh, $pid);
  $spread{product_only} = product_only($dbh, $pid);

  $spread{SpreadWidth} = $specs->{ovrSpreadWidth};
  $spread{SpreadHeight} = $specs->{ovrSpreadHeight};

  #print STDERR "HAVE RFQ ONLY: $spread{rfq_only} \n";

  return \%spread;
} # end sub spread

sub colour_changes {
	my $specs = shift;

	#Only for multipage projects
	my $colour_changes;

	map { 
		if ( $_ =~ /mv_num_colour/ ) {
			$colour_changes += $specs->{$_};
		}
	} %{$specs};

  #print STDERR "HAVE COLOUR CHANGES: $colour_changes \n";

	return $colour_changes;
}

# Extract the colours and coating (inks, varnishes, aqueous, etc.) information
# from the form. Takes a reference to the spread.
sub colours_coatings {
    my ($specs) = @_;
    my @sides;

    # Each side of the spread may require different colours and coatings (not
    # to be confused with the signature itself as how we run it isn't
    # important here). We gather all the inks, varnishes, and coatings per
    # side here.
    for my $s (0 .. 1) {
        my (%side, @colours);

        # INKS (PROCESS AND PMS)
        #
        # Do we want black?
        push @colours, { 
            type      => 'process',
            name      => 'black',
            coverage  => DEFAULT_COVERAGE, 
            mv_varies => (defined $specs->{"s${s}_black_mv"}),
        } if $specs->{"s${s}_black"} || $specs->{"s${s}_process"};


        # Add the process colours if we want them (black's been handled).
        if ($specs->{"s${s}_process"}) {
            push @colours, { 
                type      => 'process',
                name      => $_,
                coverage  => DEFAULT_COVERAGE,
                mv_varies => (defined $specs->{"s${s}_process_mv"}),
            } for qw(cyan magenta yellow);
        }

        # We allow n (where n is currently 8) pantone colours.
        for my $i (1 .. 15) {
            my $name     = $specs->{"s${s}_pms_${i}_name"};
            my $coverage = $specs->{"s${s}_pms_${i}_coverage"};
            my $ink = $specs->{"s${s}_pms_${i}_type"};
            my $is_mv    = (defined $specs->{"s${s}_pms_${i}_mv"});
            $coverage =~ tr/0-9.//cd;

            # A pantone colour is valid if it's been given a name and a
            # pecentage coverage greater than zero.
            push @colours, { 
                type      => 'pantone',
                name      => $name,
                coverage  => $coverage, 
                mv_varies => $is_mv,
                ink       => $ink,
            } if $name and $coverage and $coverage > 0;
        }

        # VARNISH
        #
        # Varnishes are treated the same as inks, with the special case of
        # flood varnishes which are represented as 100% coverage but don't
        # require a plate. We can have any or all combinations of (spot,
        # flood) X (gloss, matte) so we'll add them as we find them.

        # Check for flood varnishes first.
        for my $name ($specs->{"s${s}_varnish_flood"}) {

            # If it's not a valid varnish (eg. gloss) ignore it.
            next unless grep { $name eq $_ } VARNISHES;

            push @colours, {
                type     => 'varnish',
                name     => $name,
                coverage => 100, 
            };
        }

		$specs->{"s${s}_varnish_spot"} = [ 
                                            $specs->{"s${s}_varnish_spot_gloss"} , 
                                            $specs->{"s${s}_varnish_spot_matte"} ]; 

#			unless ref($specs->{"s${s}_varnish_spot"}) eq 'ARRAY';

        # Spot varnishes get the default coverage.
        for my $name (@{$specs->{"s${s}_varnish_spot"}}) {

            # If it's not a valid varnish (eg. gloss) ignore it.
            next unless grep { $name eq $_ } VARNISHES;

            push @colours, { 
                type      => 'varnish',
                name      => $name,
                coverage  => DEFAULT_COVERAGE,
            }
        }

        $side{colours} = \@colours; # Store the colours.

        # DRY TRAPPING
        #
        # We have no idea what the user wants to dry trap, how many dry traps
        # are needed, or really anything except they want dry trapping. Well,
        # we do assume it's varnish they want dry trapped as that's where we
        # put it in the interface, it could be any ink though.
        $side{dry_trap} = ($specs->{"s${s}_drytrap"}) ? 1 : 0;


        # AQUEOUS AND UV COATINGS
        #
        # There can only be one aqueous coating per side of any given spread.
        # Potentially there could be a dry trapping case where multiple
        # aqueouses could be offered, but we don't handle it.
        my $type    = $specs->{"s${s}_coating_type"};
        my $texture = $specs->{"s${s}_coating_texture"};


        if (    $type 
#		and $texture
#       and grep { $texture eq $_ } qw(gloss silk matte))
            and grep { $type    eq $_ } qw(aqueous uv soft_touch)
		   )
        {

            # If we're the second side we need to make sure we don't have a
            # different type or texture of coating than on the first. TODO:
            # This is an application shortcoming, at some point this may no
            # longer apply.
            unless ( $s == 1 && defined $sides[0]{coating} 
                && (   $sides[0]{coating}{type} ne $type
                    || $sides[0]{coating}{name} ne $texture ) )
            {
                $side{coating} = {
                    type => $type,
                    name => $texture,
                    spot => (defined $specs->{"s${s}_coating_spot"} || 0),
                };
            }
            else { warn "Invalid coating on side two, ignoring"; }
        }

        $sides[$s] = \%side;

		# If the side_link is activated just make side1 the
		# same as side0
		if ( $specs->{side_link} ) {
			my %s1 = %side;
			$sides[1] = \%s1;
			last;
		}
    }

    return \@sides;
}

# Extract the substrate (stock) information from the form.
sub stock {
  my ($dbh, $specs) = @_;
  my %stock;

  # At this stage we've chosen a family/type (for some reason we combine
  # them), coatings, colour, and weight. Due to our poor database design
  # this does not equate to a paper, so we pass it all. TODO: Add some
  # assertions and other validity checks.

  if ($specs->{rdbSpecificStock} eq 'Y') {
    $stock{custom} = 1;
    $stock{name} = $specs->{txtSpecificStockBrand};
    $stock{finish} = $specs->{txtSpecificStockFinish};
    $stock{colour} = $specs->{txtSpecificStockColour};
    $stock{weight} = $specs->{txtSpecificStockWeight};
    $stock{calliper} = $specs->{txtSpecificStockCalliper};
    $stock{type} = lc $specs->{StockType};
    $stock{width} = $specs->{txtSpecificStockWidth};
    $stock{height} = $specs->{txtSpecificStockHeight};
    $stock{cut_paper} = $stock{type} eq 'sheet' ? 'Y' : 'N';
    $stock{mweight} = $specs->{txtCustomMWeight};
    $stock{doublesided} = $specs->{doublesided};
    $stock{grade} = $specs->{StockGrade};
    $stock{minimum_order} = $specs->{minimum_order};
    $stock{sheets_per_package} = $specs->{sheets_per_package};
    $stock{full_packages} = $specs->{full_packages};
    $stock{multipart} = $specs->{multipart} eq '1' ? $specs->{parts} : 1;
    $stock{c1sc2s} = $specs->{c1sc2s};
    $stock{Price} = {
      Cost  => (($$specs{CustomStockPrice}/100) * ($specs->{txtCustomMWeight} / 1000)),
      Price => (($$specs{CustomStockPrice}/100) * ($specs->{txtCustomMWeight} / 1000)),
      units => 'lbs'
    };
      $openprint::log->debug("Per sheet price from $$specs{CustomStockPrice} * $$specs{txtCustomMWeight} / (100*1000)=".$stock{Price}{Price});

  } else {
    $stock{name} = $specs->{stock_name} or warn "No stock name selected.";
    $stock{colour} = $specs->{stock_colour} or warn "No stock colour selected.";

    # In addition to setting our stock coating, we'll tell each side of the
    # spread whether they're coated or not.
    $stock{finish} = $specs->{stock_finish} or warn "No stock finish selected.";

    # $spread{side}[0]{coated_paper} = ($stock{coating} >= 1);
    # $spread{side}[1]{coated_paper} = ($stock{coating} >= 2);

    $stock{weight} = $specs->{stock_weight};

    # Add the calliper as everyone wants it.
    @stock{'calliper','multipart'} = $dbh->selectrow_array(qq{
      SELECT strcalliper, lngmultipart, c1sc2s FROM tbl_paper 
      WHERE strname = ?
      AND strfinish = ?
      AND strcolour = ?
      AND strweight = ?
      }, {}, @{\%stock}{qw(name finish colour weight)});

    #if ( ! $stock{calliper} ) { 
      #$stock{calliper} = $dbh->selectrow_array(qq{
      #SELECT strcalliper FROM tbl_paper_roll 
      #WHERE strname   = ?
        #AND strfinish = ?
        #AND strcolour = ?
        #AND strweight = ?
        #}, {}, @{\%stock}{qw(name finish colour weight)});

        #if ( $stock{calliper} ) {
        #$stock{is_roll} = 1;
        #} else {
        #warn "Stock Calliper Not Found FOR: " . Dumper(\%stock);
        #}
        #} # end if ! calliper
  } #end if specific

  # Does the customer wish to supply their own stock?
  $stock{supplied} = ($specs->{stock_supplied}) ? 1 : 0;

  return \%stock;
}

# Extract the version information from the form.
sub versions {
    my ($specs, $total) = @_;

    return {} unless $specs->{is_mv}; # Are we a multi-version project?

    my @name  = @{$specs->{mv_name}};
    my @qty   = @{$specs->{mv_qty}};

    die "Invalid quantity ($total)." unless $total > 0;

    my %versions;

    # Record each valid name/quantity pair the makes up a version.
    for my $i (0 .. $#qty) {
        my $name    = $name[$i];
        my $qty     = int($qty[$i] || 0);

        next unless $name && $qty > 0;

        $versions{$name} = 0 unless exists $versions{$name};

        $versions{$name} += $qty; # Identical names are tallied.
    }

    # We check quantites not percentiles due to rounding errors.
    warn "Version total does not equal total quantity ($total)."
        unless sum(values %versions) == $total;
    
    # Map the counts into percentages as we need to use them for
    # all project estimate quantites.
    $_ = Math::Round::nearest(0.01, ($_/$total) * 100) for values %versions;

    return \%versions;
}

sub overrides {
  my ($specs, $user_type) = @_;

  my %override;

  # Each field shows the automatically selected value by default, so we only
  # set it as an override if the user has checked the associated box.
  for my $field (qw(press runstyle substrate quality imposition)) {
    $override{$field} = $specs->{$field} if $specs->{"override_$field"};
  }

  $override{margin} = $specs->{ignore_margins} || undef;

  # TODO Before these are allowed we must make sure the user is priveledged
  # (ie. employee/admin).
  if ( $user_type eq 'A' || $user_type eq 'E' ) {	
    $override{overs}{unit} = $specs->{override_overs_unit};
    $override{overs}{run}  = $specs->{override_overs_run} ne '' ? $specs->{override_overs_run} / 100 : undef;
  }

  # Multipage projects can override the number of spreads on a form and the
  # number of forms in that group.
  if ($specs->{spreads} and $$specs{override_spreads}) {
    $specs->{spreads} =~ s/\D//g;
    $override{spreads} = $specs->{spreads} if $specs->{spreads};
  }
  if ($specs->{forms} and $$specs{override_forms}) {
    $specs->{forms} =~ s/\D//g;
    $override{forms} = $specs->{forms} if $specs->{forms};
  }

  $override{chargefor} = $specs->{chargefor};

  return \%override;
}

1;
__END__
