# X-Y Cutting is for large format jobs and replacing the traditional offset
# guillotine cutting for them. (Bug 3844).
package eprint::Service::XYCutting;
use strict;
use warnings;

use Data::Dumper;
use POSIX qw(ceil);

use PQS::Equipment;
use eprint::project qw(:common);
use eprint::service qw(:common);
use eprint::Service::Printing::Constants qw(:press_types);
use callback;

sub necessary {
    my ($log, $dbh, $pid, $service_type) = @_;

    # We only apply to large format jobs.
    return 0 unless get_press_type($log, $dbh, $pid) eq LARGE_FORMAT;

    # I-cutting (contour cutting) handles all project cutting if present.
    return 0 if check_for_service($log, $dbh, $pid, 'ICutting');

    # Other conditions?

    return 1;
}

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    my @qty = (undef, get_quantities($log, $dbh, $pid));

    # Get the imposition object.
    my $imp = get_imposition($dbh, get_print_container($log, $dbh, $pid))
        or die "Failed getting imposition object from project ($pid)";

    # Get the equipment that can process us.
    my @equipment = valid_equipment(undef, $dbh, $service_type, $pid);

    die "No equipment for $service_type." unless @equipment;

    QUANTITY:
    for my $i (1..3) {
        next unless $qty[$i] && $qty[$i] > 0;

        my %best; # Best price for the given quantity.

        ROTATION:
        for my $rotated (0,1) {
            my $job = job($imp, $qty[$i], $rotated) or return 'error';

            EQUIPMENT:
            for my $eid (@equipment) {
                my $equip = get_equipment($dbh, $eid);

                # Check that the equipment can process the job.
                next unless specs_pass($equip, $job);

                my $price = eval { 
                    calc_price($log, $dbh, $variable, $service_type, $pid, $sid, $eid, $job->{cuts});
                };
                next EQUIPMENT if $@;

                # TODO Check the rotation (though not for rolls on roll cutters) to see if
                # it's possible (recheck rotated width/height) and cheaper.

                %best = (
                    equip => $eid, 
                    price => $price,
                    job   => $job,
                ) if !exists $best{price} || $price < $best{price};
            }
        }

#        return 'error' unless $best{price} && $best{price} > 0;

        $specs->{"ddmEquipment$i"} = $best{equip};
        $specs->{"rotated$i"}      = $best{job}{rotated};
        $specs->{"cuts$i"}         = $best{job}{cuts};

        @$specs{"txtPrice$i", "txtUnitPrice$i"}
            = format_pricing($best{price}, $qty[$i]);
    }

    return 'calculated';
}

# Gets (fetches, decodes, and thaws) the requested imposition object.
sub get_imposition {
    my ($dbh, $sid) = @_;

    use Compress::LZF         qw(:compress :freeze);
    use Storable              qw(thaw);
    use MIME::Base64;
    use PQS::Imposition::Node;

    my $frozen = $dbh->selectrow_array(q{
        SELECT strvalue FROM tbl_service_specifications
        WHERE strname = 'imp' AND lngserviceindex = ?
    }, {}, $sid);
    return undef unless $frozen;

    my $imposition = sthaw(decode_base64($frozen));

    return $imposition;
}

# Check the the given equipment can perform the job.
sub specs_pass {
    my ($equip, $job) = @_;

    # "I'll cut you so bad, you'll wish I never cut you so bad!" -- Cockroach
    return 1 if $equip->{type} eq 'manual';

    return 0 if $job->{paper}{calliper} > $equip->{maximum_calliper};

    if (exists $equip->{rolls} && $equip->{rolls}) {
        # Roll cutters can't process sheet jobs. Note: Is this really the case or
        # should we just enforce min. sizes?
        return 0 if ! $job->{paper}{is_roll};

        return 0 if $job->{rotated}; # Obviously rolls can't just be rotated.

        return 0 if $job->{width} > $equip->{maximum_sheet_width}
                 || $job->{width} < $equip->{minimum_sheet_width};

        return 1; # Done for roll x-y cutters.
    }

    # Check all dimensions for sheets.
    return 0 if $job->{width}  > $equip->{maximum_sheet_width}
             || $job->{width}  < $equip->{minimum_sheet_width}
             || $job->{height} > $equip->{maximum_sheet_length}
             || $job->{height} < $equip->{minimum_sheet_length};

    return 1;
}

# Cutting pricing is simply priced per cut (volume discounted).
sub calc_price {
    my ($log, $dbh, $var, $type, $pid, $sid, $eid, $cuts) = @_;

    my $make_ready = get_price($log, $dbh, $var, "${type}MakeReady",     undef, $eid) || 0;
    my $min_price  = get_price($log, $dbh, $var, "${type}MinimumCharge", undef, $eid) || 0;
    my $run_rate   = get_price($log, $dbh, $var, $type, $cuts, $eid);

    my $price = $run_rate * $cuts;
    callback::call('service_calc_end', $pid, $sid, $make_ready, $price);

    $price += $make_ready;
    $price = $min_price if $price && $price < $min_price;

    return $price;
}

# Given the layout and the quantity being produced, determine the number of
# cuts (guillotine style) required. NOTE: Exact quantity based as large format
# often has a very low quantity.
sub job {
    my ($imp, $qty, $rotated) = @_;

    die "Quantity required" unless $qty && int $qty > 0;

    my %job = (
        paper   => $imp->{paper},
        width   => $imp->{paper}{width},
        height  => undef,
        cuts    => undef,
        rotated => $rotated,
    );

    # If a job is tiled each tile is trimmed on all sides. The tile is the
    # only thing which needs to fit on the cutter.
    if ($imp->{spreads} && $imp->{spreads} > 1) {
        $job{height} = $imp->{paper}{is_roll} ? $imp->{image_height} * $qty
                                              : $imp->{paper}{height};

        $job{cuts} = ($imp->{spreads} * 4) * $qty;
    }
    else {
        my ($cols, $rows) = @$imp{qw(cols rows)};

        # If it's a roll we treat it as a single long sheet for cutting.
        $rows = ceil $qty / $cols if $imp->{paper}{is_roll};

        $job{height} = $imp->{paper}{is_roll} ? $imp->{image_height} * $rows
                                              : $imp->{paper}{height};

        $job{cuts} = cuts($qty, $cols, $rows, $rotated);
    }
    
    @job{qw(width height)} = @job{qw(height width)} if $rotated;

    return \%job;
}

# Guillotine like cutting for large format x-y cutters (non-dutch). All pieces
# are trimmed (no dead-cuts), rows are cut across then each piece is processed.
sub cuts {
    my ($qty, $cols, $rows, $rotated) = @_;

    my $setup = $cols * $rows;
    my $cuts  = 0;

    my $sheets = ceil $qty / $setup; # Rolls become a single 'sheet'

    # Process all the sheets as if they're full.
    $cuts += $sheets * 2 * (!$rotated ? $cols * $rows + $rows
                                      : $rows * $cols + $cols);

    # Remove the extra cuts from any partial sheets.
    if (my $remaining = $qty % $setup) {

        $cuts -= 2 * ($setup - $remaining); # Side cuts.

        # Sheets are filled by column first and we want to preserve that
        # geometry during cut rotation. So a 4 x 3 layout filled with 10
        # images and rotated is different from a 3 x 4 layout filled the same.

        if (!$rotated) {
            $cuts -= 2 * ($rows - ceil($remaining / $cols));
        }
        else {
            $cuts -= 2 * ($cols - $remaining) if $cols > $remaining;
        }
    }

    return $cuts;
}

1;
