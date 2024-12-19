package eprint::Service::Printing::Substrate;
use strict;
use warnings;

use Carp;
use eprint::Config;
use Readonly;

# Every sheet gets cut down by the following factors for pricing alternatives.
use constant CUT_SHEET_FACTORS => split /,/, 
(eprint::Config->get(Printing => 'prepress_cutting_factors') || '');


use base qw(Exporter);
our @EXPORT = qw(get_substrates fit_to_press);
use Data::Dumper;

{
  # Different press types can handle different formats. TODO Move this check
  # to per press so we're not locked to one press type per project.
  Readonly my %FORMATS_FOR => (
    web            => [qw(      roll)],
    inkjetprinter  => [qw(sheet roll)],
    screen         => [qw(sheet     )],
    press          => [qw(sheet     )], # TODO +rolls when we implement sheeters.
    digital        => [qw(sheet     )],
  );

  # Get a list of all substrates (including cut-down sheets) that match the
  # given criteria and can fit the project image.
  sub get_substrates {
    my ($dbh, $project) = @_;

    my $override = $project->{override}{substrate};

    # Which substrate formats can the press type accept?
    my $formats = $FORMATS_FOR{ $project->{press_type} };

    # A quick override for custom items (screen printing). TODO Expand to
    # allow fully custom stock of any type.
    if (defined $override && $override eq 'item') {
      my %item = (
        width  => $project->{width},
        height => $project->{height},
        type   => 'item',
      );

      return [ \%item ];
    }

    # For each of the formats; gather the substrates that match the search
    # criteria, cut down any sheets, and make sure the project image can
    # at least fit onto the substrate.
    my @substrates;
    for my $format (@$formats) {
      my @list = find_substrates($dbh, $project->{paper}, $format);

      #print STDERR "HAVE SUBSTRATE LIST: ", Dumper(\@list);

      push @substrates, 
      grep { substrate_fits_project($_, $project)       }
      map  { $_->{type} eq 'sheet' ? cut_sheet($_) : $_ }
      @list;
    }

    # Allow only the chosen substrate if the override was set. TODO Filter
    # earlier or get the substrate directly to improve performance.
    if ($override) {
      @substrates = grep { $_->{id} eq $override } @substrates;
    }

    return \@substrates;
  }
}


{
  # Queries to get substrate info by format (the tables are a mess).
  Readonly my %SQL_FOR_FORMAT => (
    sheet => q{
    SELECT lngindex    AS index,   lngindex   AS id,
    dblwidth    AS width,   dblheight  AS height,
    strmweight  AS mweight, 'sheet'    AS type,
    strcalliper::NUMERIC AS calliper,
    cut_paper, 
    (CASE WHEN ysnperfecting = 'Y' THEN TRUE ELSE FALSE END) AS perfecting
    FROM tbl_paper 
    },
    roll => q{
    SELECT lngindex    AS index,      lngindex   AS id,
    dblwidth    AS width,      NULL       AS height,    
    strmweight  AS mweight,    'roll'     AS type,
    strcalliper::NUMERIC AS calliper,
    TRUE::bool  AS cut_paper,  TRUE::bool AS perfecting
    FROM tbl_paper_roll 
    },
  );

  # Standard potential substrate lookup attributes.
  Readonly my @FIELDS => qw( name finish colour weight category );

  # Given some substrate attributes as a search criteria and the substrate
  # format, find all matching substrates in the database.
  sub find_substrates {
    my ($dbh, $find_by, $format) = @_;

    if (exists $$find_by{custom}) {
      return ($find_by);
    } else {

      my $sql = $SQL_FOR_FORMAT{ $format } 
        or croak "Invalid format ($format), normally 'roll' or 'sheet'.";

      # Of the attributes we can use, which are there? (0 and '' not allowed)
      my @fields = grep { exists $find_by->{$_} && $find_by->{$_} } @FIELDS;

      # Generate the where clause based on the defined substrate attributes.
      if (@fields) {
        $sql .= " WHERE " . join(q{ AND }, map {"str$_ = ?"} @fields); }

      # Get the substrates from the database.
      my $substrates = 
      $dbh->selectall_arrayref($sql, {Slice => {}}, @{$find_by}{@fields});
      #print STDERR "FOUND SUBSTRATES ", Dumper($sql, $substrates, $find_by);

      # TODO Perhaps this should just be a reference to the search?
      return map { @{$_}{ keys %$find_by } = values %$find_by; $_ } @$substrates;
    }
  }
}

# Given a press and a list of press sheets, pre-cut any of them for the press
# and return a list of sheets with sizes that will fit on the press.
sub cut_sheet {
  my ($sheet) = @_;

  # 'Fix up' the sheet size to be pretty here as we're not going to
  # spend the time to find it all over the user interface.
  $sheet->{$_} = (sprintf "%.3f", $sheet->{$_} )+0 for qw(width height);

  # Substrates can be marked as not being 'cuttable';
  return $sheet unless $sheet->{cut_paper};

  # Cut the sheet along each dimension in turn, the first round is appended
  # to the list for the second round.
  my @sheets = ($sheet);
  for my $dim (qw(width height)) {
    my @processed; # Sheets cut in previous dimension.

    for my $orig (@sheets) {
      for my $n (CUT_SHEET_FACTORS) {
        my %new = %$orig; # Copy.

        # Cut the sheet and format to 3 optional decimal places.
        $new{$dim} = (sprintf "%.3f", $new{$dim} / $n)+0;

        # Quick addition to give a unique 'ID' to cut sheet sizes.
        # TODO Pehaps the format index-rows-colums would be better.
        $new{id} .= '-' . uc(substr($dim, 0, 1)) . $n;

        $new{"start_$dim"}    = $orig->{$dim};  # Store initial dim.
        $new{mweight}        /= $n;             # New MWeight.
        $new{cuts}           += $n-1;           # Dead cuts used.
        $new{"${dim}_factor"} = $n;             # Rows/Cols.

        # NOTE: We consider identical sheet sizes cut from different
        # stocks as the price can vary.
        push @processed, \%new; 
      }
    }
    # Append our sheeted sheets (for the next dim. or final list).
    push @sheets, @processed;
  }

  return @sheets;
}

# Check to see if the current substrate size can fit the project.
sub substrate_fits_project {
  my ($substrate, $project) = @_;

  # Large format printers can tile their media, so they'll happily use
  # anything. TODO Check tiling spec here to make sure tiling is wanted?
  return 1 if $project->{press_type} eq 'inkjetprinter'; 

  my ($w, $h) = @$project{qw(width height)};

  # TODO Hard grain direction constraints should limit the rotation.

  # The project must at least be able to fit (rotation allowed).  
  if ($substrate->{type} eq 'sheet') {
    return unless $w <= $substrate->{width} && $h <= $substrate->{height}
    || $h <= $substrate->{width} && $w <= $substrate->{height};
  }
  # Rolls are considered ifinite in length so we only have to check width.
  else {
    return unless $w <= $substrate->{width} || $h <= $substrate->{width};
  }

  return 1;
}


#
# PRESS SPECIFIC
#

# Given a substrate and a press, either make it fit (if that's possible) or
# get rid of it (returns empty list which removes it in a map {}).
sub fit_to_press {
  my ($substrate, $press) = @_;
  my $type                = $substrate->{type};

  # We now have a exclusion table to stop some substrates from running
  # on specific equipment. 
  return () if (grep {$substrate->{index} eq $_} @{$press->{invalid_substrates}});

  # Sheets must fit on the press.
  if ($type eq 'sheet') {
    return $substrate if sheet_fits_press($substrate, $press);
  }
  elsif ($type eq 'roll') {
    # If we're processing a roll on a web press, it gets cut on the press.
    if ($press->{type} eq 'web') { 
      return cut_roll_to_press($substrate, $press);
    }
    # Otherwise we just make sure the roll width fits the max press width.
    else { return width_fits_press($substrate, $press); }
  }
  elsif ($type eq 'item') {
    # TODO Add fitting code.
    return $substrate if sheet_fits_press($substrate, $press);
  }

  return (); # We throw out anything we can't handle.
}

# Cut the roll to the cut-off specificied by the press.
sub cut_roll_to_press {
  my ($roll, $press) = @_;

  croak "Given press type '$press->{type}' wanted 'web'.",
  "Only web presses have automatic cut-offs for rolls."
  unless $press->{type} eq 'web';

  # The width must fit across the press. (Do not return undef).
  return unless $roll->{width} <= $press->{maximum_sheet_width}
  && $roll->{width} >= $press->{minimum_sheet_width};

  my %sheet = %$roll; # Copy.

  # Web presses (currently the only thing that use rolls) sheet to their
  # maximum allowable length.
  $sheet{height} = $press->{maximum_sheet_length};
  $sheet{cuts}   = 1; # The cut-off will happen on the press.

  return \%sheet;
}


# Bounds check that the sheet (or the rotated sheet) fits on the press.
sub sheet_fits_press {
  my ($sheet, $press) = @_;

  my ($width, $height) = @$sheet{qw(width height)};

  # Check the min and max press dimensions against the dims given.
  my $check = sub {
    my ($x, $y) = @_;

    # Inkjets need only check that one dimension fits the throat width.
    # TODO This assumption doesn't always hold true. We should also check
    # minimum heights.
    if ($press->{type} eq 'inkjetprinter') {
      return (  $x <= $press->{maximum_sheet_width}
        && $x >= $press->{minimum_sheet_width} );
    }

    # Presses have set lengths so require that all dimensions fit.
    return (  $x <= $press->{maximum_sheet_width}
      && $y <= $press->{maximum_sheet_length}
      && $x >= $press->{minimum_sheet_width}
      && $y >= $press->{minimum_sheet_length} );
  };

  # Check that the sheet or the sheet rotated 90 fits the press.
  return ( $check->($width, $height) || $check->($height, $width) );
}


# A simple check that the substrate width (normally used for rolls on inkjet
# printers) can fit the throat of the press.
sub width_fits_press {
  my ($roll, $press) = @_;

  return ($roll->{width} <= $press->{maximum_sheet_width}) ? $roll : ();
}

1;
