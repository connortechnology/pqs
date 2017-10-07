package eprint::Service::GraphicDesign;
use strict;
use warnings;
no warnings qw(uninitialized numeric);

use eprint::service qw(:common);
use eprint::project qw(get_print_container);

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    die "Service type must be GraphicDesign ($service_type)" 
        unless $service_type eq 'GraphicDesign';

    # Get the valid hourly services for graphic design.
    my $services = $dbh->selectcol_arrayref(q{
        SELECT s.strid 
        FROM tbl_services s, tbl_service_types t
        WHERE s.lngtype = t.lngindex
          AND t.strid   = 'GraphicDesign'
    });

    #changing the printing service will impact the graphic design hours so it needs to be recalculated
    return 'uncalculated' if get_design_hours($log, $dbh, $pid) != $specs->{GraphicDesign} && !$specs->{Override_GraphicDesign};

    my %hours = map { $_ => sprintf "%.2f", $specs->{$_} } 
                    @$services;

    # If we don't have any hours, we can't calculate anything.
    return 'uncalculated' unless grep { defined && $_ > 0 } values %hours;

    # Get the equipment that can process us.
    my @equipment = valid_equipment(undef, $dbh, $service_type);

    die "No equipment for $service_type." unless @equipment;

    my %best; # Best price for the given quantity.

    for my $eid (@equipment) {
        my $price = calc_price(
            $log, $dbh, $variable, $service_type, $eid, \%hours);

        %best = (equip => $eid, price => $price) 
            if !exists $best{price} || $price < $best{price};
    }

    return 'error' unless $best{price} > 0;

    for my $i (1..3) {
        # Store the best price for the quantity.
        $specs->{"hdnEquipment$i"} = $best{equip};
        $specs->{"txtPrice$i"}     = format_pricing($best{price});
    }

    return 'calculated';
}

# Calculate a generalised n item per quantity (project) charge.
sub calc_price {
    my ($log, $dbh, $var, $service_type, $eid, $hours) = @_;
   
    my $price = 0;

    # Get the service pricing.
    while (my ($type, $hours) = each %$hours) {
        my $rate = get_price($log, $dbh, $var, $type, $hours, $eid);
        
        $price += $rate * $hours;
    }

    return $price;
}

sub display {
    my ($log, $dbh, $service_type, $pid, $sid, $specs) = @_;

    # Enter in hours on the first pass through.
    $specs->{Default_GraphicDesign} = get_design_hours($log, $dbh, $pid);
    $specs->{GraphicDesign} = $specs->{Default_GraphicDesign}
        unless $specs->{Override_GraphicDesign};

    return {
      Default_GraphicDesign => $specs->{Default_GraphicDesign},
      Override_GraphicDesign => $specs->{Override_GraphicDesign},
    };
}

# Determine the default graphic design hours for the project.
sub get_design_hours {
	my ($log, $dbh, $pid) = @_;

    my $prin = get_print_container($log, $dbh, $pid);
    
    my ($width, $height, $template) 
        = get_specifications($log, $dbh, $pid, $prin, 
            qw(flat_width flat_height template)
    );

    #detects a second side by looking for either the two sides being linked or a colour for the second side
    my $side_two = $dbh->selectrow_array(q{
            SELECT strvalue FROM tbl_service_specifications WHERE (strname ~ 'side_link' or strname ~ 's1_(black|process)' or strname ~ 's1_pms_\d+_name')
            AND lngserviceindex = ?
    }, undef, $prin);

    my $sided = $side_two ? 'Double' : 'Single';

    my $hours = $dbh->selectrow_array(qq{
        SELECT dblDesignHours${sided}Side 
        FROM tbl_Project_Templates 
        WHERE strTemplateType = ?
          AND dblFlatWidth    = ?
          AND dblFlatHeight   = ?
    }, {}, $template, $width, $height);
print STDERR "GET DESIGN HOURS: $sided, $template -- $width x $height = $hours | $side_two \n";

    # If we don't have design hours for that particular template, try
    # using the custom template.
    if (!$hours || $hours <= 0) {
        # Hours per square inch.
        $hours = $dbh->selectrow_array(qq{
            SELECT dblDesignHours${sided}Side 
            FROM tbl_Project_Templates 
            WHERE strTemplateType = 'Custom'
        });
        return undef unless $hours;

        $hours *= $width * $height;
    }

    my $pages = get_specifications($log, $dbh, $pid, $prin, 'txtTotalPageQuantity');

    # divide by 2 because the flat dimesions = 2 Pages. TODO Is this correct?
    $hours *= $pages / 2 if $pages > 1; 

#    return int($hours);
    return $hours;
}


1;
