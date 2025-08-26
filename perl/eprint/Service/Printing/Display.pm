package eprint::Service::Printing::Display;
use strict;
use warnings;
no warnings qw(uninitialized);

#use Data::Dumper;
use List::Util qw(sum);

use eprint::Service::Printing::Constants qw(:spread_types);
use eprint::Service::Printing::Price     qw(spreads_remaining);

use eprint::project                      qw(:common project_info);
use eprint::paper                        ();
use eprint::service                      qw(get_specifications);
use ssi                                  qw(make_drop_down material_drop_down);
use configuration                        ();


# Large format project types that display mounting
#use constant LF_MOUNTING => qw(
#    Billboards   Calendars   Custom    Fabrics      Fineart    Photos
#    POS          PSC         Signage   Tradeshow    Vehicles
#);

# Large format project types that allow 'binding' (welding, sewing, etc.).
use constant LF_BINDERY => qw(
    Billboards   Custom      Fabrics    POS         PSC        Signage   
    Tradeshow    Vehicles    Wallpaper
);

use base qw(Exporter);
our @EXPORT_OK = qw(display template_sizes multiversion);


sub display {
    my ($log, $dbh, $service_type, $pid, $sid, $specs, $variable) = @_;

    my %page;

    # General project information
    my $project      = $page{project} = project_info($dbh, $pid);
    
    my $project_type = $project->{type}{ref};
    my $press_type   = get_press_type($log, $dbh, $pid, $sid);

	$page{NoPrint} = 1 if $project_type eq 'NoPrint';

    # DETAILED MODE SIGNATURES
    #
    # Kludge to manually step through each signature in "detailed" mode. A
    # 'needs_view' flag is set during signature creation that forces an
    # uncalculated state (in validation) so it gets displayed here.
    if ($project->{is_multipage}) {
        $dbh->do(q{
            DELETE FROM tbl_service_specifications
            WHERE strname = 'needs_view'
              AND lngprojectindex = ?
              AND lngserviceindex = ?
        }, undef, $pid, $sid);
        
        $page{is_cover} = $specs->{txtSignatureType} eq COVER;

        $page{spreads_remaining} = spreads_remaining($log, $dbh, $pid, $sid)
            unless $page{is_cover};
    }

    # TEMPLATES AND DIMENSIONS
    #
    # Project type templates (pictures with radio buttons on print pages).
    my ($templateurl) = $dbh->selectrow_array(q{
        SELECT strtemplateurl FROM tbl_projecttypes WHERE strid = ?
    }, undef, $project_type);

    # If the template is defined, append the path for the include.
    $page{templateurl} = "/includes/main/proj/$templateurl"
        if $templateurl;

    $page{templates} = template_sizes($log, $dbh, $project_type);

    # MULTI-VERSION
    #
    # For now we only show multi-version controls if the press is sheetfed
    # offset and we're not doing a pads or a press sheet combo.
    $page{multiversion_allowed} = ( 
			#     !$project->{is_multipage}
			#&& $press_type =~ /^(web|digital|press)$/
               $press_type =~ /^(web|digital|press)$/
            && $project_type ne 'PressSheetCombination'
            && $project_type ne 'Scratch/WritingPads'
    );

    # Get info to recreate version table when editting the service.
    @page{qw(versions remaining)} = multiversion($log, $dbh, $pid, $specs)
            if $specs->{mv_name} && $specs->{mv_qty};


    # Fill inks
    my $fill_inks = eprint::material::get_materials_by_type($dbh, 1);
    $page{fill_ink_materials} = "";
    foreach my $key (keys %{$fill_inks}) {
      $page{fill_ink_materials} .=  "<option value=" . $fill_inks->{$key}{'strid'};
      $page{fill_ink_materials} .=  " selected=selected" if ($fill_inks->{$key}{'strid'} eq 'PMSInk');
      $page{fill_ink_materials} .=  ">" . $fill_inks->{$key}{'strname'} . "</option>";
    }

    # PRINTING
    #
    # Can any presses perform qqueous or ultraviolet coatings? TODO Check for
    # external coaters as well when the code supports them within printing.
    $page{can_uv} = can_coat($dbh, $press_type, 'uv');
    $page{can_aq} = can_coat($dbh, $press_type, 'aquoeus');
    $page{can_soft_touch} = can_coat($dbh, $press_type, 'soft_touch');
    $page{can_metal_effects} = can_metal_effects($dbh);


    # STOCK
    #
    # Populate the paper drop downs.
    $page{stock} = get_paper_options($log, $dbh, $variable, $pid, $sid, $specs);

    # Is the user allowed to supply their own stock?
    $page{can_supply_stock} 
        = !configuration::get_value($log, $dbh, 'HideSuppliedStock');


    # OVERRIDES
    #
    # Create and populate the press drowbox.
    $page{presses} = presses($dbh, $press_type);

    $page{substrate} = substrate_override($dbh, $specs->{substrate})
        if $specs->{override_substrate};


    # LARGE FORMAT
    #
    if ($project_type =~ /^LF/) {
        # Create laminate and material drop downs.
#        $page{ddmMountings} = material_drop_down($log, $dbh, 'Mounting Board'); 
#        $page{ddmLaminates} = material_drop_down($log, $dbh, 'Laminate'); 

#        $page{show_mounting} = 1
#            if grep { $project_type eq "LF_$_" } (LF_MOUNTING);

        $page{show_lf_bindery} = 1
            if grep { $project_type eq "LF_$_" } (LF_BINDERY);

        # Something to do with tiling?
        my $feature = check_for_service($log, $dbh, $pid, 'Welding')
                   || check_for_service($log, $dbh, $pid, 'Stitching');

        $page{stitch_or_weld} = "var stitchorweld = '$feature';";
    }


    # DIGITAL
    #
    # We Now have Optional Quality Ratings for Digital Presses.
    # If there is more than 1 rating in the system then display the override.
    my $q = $dbh->selectall_arrayref(q{
        SELECT DISTINCT strvalue, strvalue FROM tbl_equipment_specifications 
        WHERE strName = 'Quality Rating'
    }, { Slice => {} });
    if ( scalar @$q > 1 ) {
        $page{press_quality} = $q;
    }

    
    # PRICING
    #
    # Display stock pricing as separate to service pricing?
    $page{separate_stock} = $dbh->selectrow_array(q{
        SELECT ysnseparatestock FROM tbl_customer WHERE lngcustomerid = ?
    }, undef, $variable->{cust_id});

    return \%page;
}

# Gets the list of project sizes grouped by 'template'. Used to populate the
# project_size drop downs.
sub template_sizes {
    my ($log, $dbh, $project_type, $template_types) = @_;

    my $sth;

    # Limit template types (for instance for bindery types on book page).
    if (defined $template_types) {
        my $template_types = join ',', map { $dbh->quote($_->{id}) } @$template_types;

        $sth = $dbh->prepare(qq{
            SELECT dblFlatWidth,     dblFlatHeight,
                   dblFinishedWidth, dblFinishedHeight,
                   strDimensions,    strTemplateType
            FROM tbl_Project_Templates 
            WHERE strProjectType = ?
              AND strtemplatetype IN ($template_types)
            ORDER BY strtemplatetype
        });
    }
    # Basic lookup (cached).
    else {
        $sth = $dbh->prepare_cached(qq{
            SELECT dblFlatWidth,     dblFlatHeight,
                   dblFinishedWidth, dblFinishedHeight,
                   strDimensions,    strTemplateType
            FROM tbl_Project_Templates 
            WHERE strProjectType = ?
            ORDER BY strtemplatetype
        });
    }

    $sth->execute($project_type);

    my ($w_flat, $h_flat, $w_finished, $h_finished, $dims, $template);
    $sth->bind_columns(\$w_flat, \$h_flat, \$w_finished, \$h_finished, \$dims, \$template);

    my (@options, $prev);
    while ($sth->fetch) {
        my $name = $template;
           $name =~ s/([A-Z])/ $1/g;

        # Add a new option group if we have a new template.
        push @options, { name => $name, sizes => [] }
            if !$prev || $template ne $prev;

        # The value is the sizing of the template
        my $value = join(',', $template,
                              join('x', $w_finished+0, $h_finished+0),
                              join('x', $w_flat+0,     $h_flat+0));

        # Add the option.
        push @{ $options[-1]{sizes} }, { name => $dims, value => $value };

        $prev = $template; # Keep track of optgroups.
    }

    return \@options;
}

# Create an array of version information to make the version text boxes and
# quantity information on printing edit.
sub multiversion {
  my ($log, $dbh, $pid, $specs) = @_;

  my %versions;

  eval { @versions{ @{$specs->{mv_name}} } = @{$specs->{mv_qty}}; };

  return unless scalar keys %versions;

  # Calculate the initial quantity breakdown. TODO: Let JS do that as
  # non-JS clients will get invalid values after editing otherwise. 
  my @qty = (undef, get_quantities($log, $dbh, $pid));

  # We've changed the version storage to the name and a breakdown of the
  # first quantity.
  my (@list, $remaining);
  my $i;
  for my $name (sort {
    return $a <=> $b if ($a =~ /^\d+$/ and $b =~ /^\d+$/);
    return $a cmp $b;
    } keys %versions) {
    $i++;
    my $q1      = $versions{$name};
    my $percent = $q1 / $qty[1];

    # Calculate the percentage based on the first quantity.
    my %v = ( 
      name    => $name, 
      q1      => $q1,
      percent => sprintf("%.2f", $percent * 100), # Approx.
      id	=> $i,
    );
    # Extrapolate the second and third quantities.
    $v{"q$_"} = int($qty[$_] * $percent) for 2..3;

    push @list, \%v;
  }

  $remaining = $qty[1] - sum(values %versions);

  # We don't want the newly created form filled automatically.
  delete $specs->{mv_qty};
  delete $specs->{mv_name};

  return \@list, $remaining;
}

# Determines if any presses of the given type can perform the given coating.
sub can_coat {
    my ($dbh, $press_type, $coating) = @_;

    $coating = $coating =~ /^aq/i    ? 'Aqueous'
             : $coating =~ /^u\w*v/i ? 'UV'
             : $coating =~ /^soft_touch/i ? 'Soft Touch'
             :                          undef;

    die "Uknown coating ($coating)" unless $coating;

    my @can_coat = $dbh->selectrow_array(qq{
        SELECT count(s.*)
        FROM tbl_equipment e, tbl_equipment_specifications s
        WHERE s.strname  = '$coating Coating'
          AND s.strvalue ~* '^Y'
          AND e.lngindex = s.lngequipmentindex
          AND e.strtype = ?
    }, undef, $press_type);

    return $can_coat[0];
}

sub can_metal_effects {
    my ($dbh) = @_;
    return $dbh->selectrow_array(qq{
        SELECT count(*) 
        FROM service_type_equipment 
        WHERE service_type = ( SELECT lngindex 
                               FROM tbl_service_types 
                               WHERE strid = 'MetalEffects')
    });
}

# Creates the dropdowns for paper selection.
sub get_paper_options {
    my ($log, $dbh, $variable, $pid, $sid, $specs) = @_;

    # Paper attributes (if any) stored with the project.
    my $attr;
    for my $field (qw(name finish colour weight)) {
        $attr->{$field} = $specs->{"stock_$field"};
    }

    # Check that we have valid paper/get our options if we're a new signature.
    my $paper = eprint::paper::substrate_lookup(
        undef, $log, $dbh, $variable, $pid, $sid,
        $specs->{template}, 
        '', 
        $specs->{press}, 
        @$attr{qw(name finish colour weight)}
    );

    # If the paper lookup returned anything the current selections weren't
    # valid (or we're a new signature).
    $attr = $paper if scalar keys %$paper;

    # Create select options for the paper selections stored in the db.
    my %stock;
    while (my ($field, $options) = each %$attr) {
        $options = [ $options ] if !ref $options;

        $stock{$field} = [];

        # Add a "Please select" option if there's more than one choice.
        push @{ $stock{$field} }, { key => '', value => 'Please select one' }
            if scalar @$options > 1;

        push @{ $stock{$field} }, { key => $_ , value => $_ } for @$options;
    }

    return \%stock;
}

sub substrate_override {
    my ($dbh, $substrate) = @_;
        
    # If we have a substrate override, then we must decode the id and add
    # a option to the select box when the page loads.
    my @id = split /-/, $substrate;

    # The first part of the id is the paper index.  Get the paper
    # dimensions to create the text for the select option.
    my ($w, $h) = $dbh->selectrow_array(q{
        SELECT dblWidth, dblHeight FROM tbl_paper WHERE lngindex = ?
    }, undef, shift @id);

    # The optional second and third parts are the number of cuts along the
    # specified edge of the paper i.e ( W2 | H3 )
    while (@id) {
        my $i = shift @id;
        $w /= substr($i,1) if substr($i,0,1) eq 'W';
        $h /= substr($i,1) if substr($i,0,1) eq 'H';
    }   

    # Format the dims the same way they will appear when supplied by the
    # pricing request.
    $w = (sprintf "%.3f", $w )+0;
    $h = (sprintf "%.3f", $h )+0;

    # The correctly named option.
    return qq{<option value="$substrate" selected="selected">$w x $h </option>};
}

# Creates an HTML <option> list of press IDs/string IDs based on the press
# type of the supplied project.
sub presses {
    my ($dbh, $press_type) = @_; 

    my $presses = $dbh->selectcol_arrayref(q{
        SELECT lngindex, strid FROM tbl_equipment WHERE strtype = ?
    }, { Columns => [1,2] }, $press_type);

    return { @$presses };
}

1;
