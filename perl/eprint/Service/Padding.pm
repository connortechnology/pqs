package eprint::Service::Padding;
use strict;
use warnings;
no warnings qw(uninitialized);

use eprint::Config;
use eprint::project   qw(:common);
use eprint::service   qw(:common);
use eprint::equipment ();
use sql               qw(:common);
use POSIX             qw(floor);
use callback;
use PQS::model::materials;
use PQS::model::service;

# Backing material
use constant BACKING => eprint::Config->get(Padding => 'backing_material');

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    my $print = get_print_container($log, $dbh, $pid);
    my @qty  = (undef, get_quantities($log, $dbh, $pid));

    # Grab the padding specs.
    my ($backing, $calliper) = get_specifications(
        $log, $dbh, $pid, $sid,
        qw(rdbCardboardBacking txtStockCalliper));

    # If we don't have a page quantity for the service, but we do have one for
    # the printing service, then we should be shoving it in
    my $page_qty = get_specifications($log, $dbh, $pid, $print, 'pad_sheets');

	$page_qty = $specs->{pad_sheets} unless $page_qty;

    # We can't proceed unless we have a page quantity for the pads.
    unless (defined $page_qty and $page_qty > 0) {
        $log->debug("PADDING: No page quantity defined for pads.");
        return 'uncalculated';
    }

    $backing = defined $specs->{rdbCardboardBacking} 
    		? $specs->{rdbCardboardBacking} 
		: get_specifications(
		       	   $log, $dbh, $pid, $print, 'rdbCardboardBacking');

    # If the project height or width haven't been set for padding, grab the
    # project final dimensions for the initial values.
    my ($w, $h) = get_specifications($log, $dbh, $pid, $print,
        qw(final_width final_height)
    );

    # default calliper to NCR precollated forms if not found
    $calliper = .003 if !$calliper;    


    # NOTE: Padding currently only considers the first equipment that fits!
    my $padding_station = get_padding_station($dbh, $service_type, $w, $h, $pid);

print STDERR "HAVE PADDING STATION: $padding_station -- $w -- $h \n";


    my $status;
    for my $i (1..3) {
        my $qty = int ($specs->{"txtQuantity$i"} || $qty[$i] || 0);

        next unless $qty && $qty > 0;


        my $max_width 
            = eprint::equipment::get_specification($log, $dbh, 'Maximum Sheet Width',
                                               undef, $padding_station);
        # default our padding width if the spec is missing
        $max_width = 40 if !$max_width;
        
        my $maximum_thickness =
          eprint::equipment::get_specification($log, $dbh, 'Maximum Calliper',
                                               undef, $padding_station);
        $maximum_thickness = 4
          if !$maximum_thickness
          ;    # default our padding lift depth if the spec is missing
        my $max_imp =
          eprint::equipment::get_specification($log, $dbh,
                                               'Maximum Padding Imposition',
                                               undef, $padding_station);

        my $padding_imposition = $max_imp == 1 ? 1
                               : $w            ? floor($max_width / $w)
                               : 0;


        return 'error' if $padding_imposition < 1
                       || ($calliper * $page_qty > $maximum_thickness);


        my $padding_makeready =
          get_price($log, $dbh, $variable, 'PaddingMakeReady', undef,
                    $padding_station);

#        my $price = get_price($log, $dbh, $variable, 'Padding',
#                    $qty / $padding_imposition,
#                    $padding_station);

        my $price = get_price($log, $dbh, $variable, 'Padding',
                    $page_qty,
                    $padding_station);

        # If a backing has been requested, add a backing. Backing are charged
        # out per square foot, with a possible volume discount on the total
        # project (not per unit) backing area used.
        my ($area, $material) = (0, 0);
        if ($backing) {
            $area = ($w / 12 * $h / 12);    # Area in square feet.
            $material =
              eprint::material::get_price($log, $dbh, $variable, BACKING,
                                          $area * $qty, undef);

            my $mat = PQS::model::materials::material_by_strid(BACKING);
            PQS::model::service::set_material_estimate(int ($area * $qty), undef, $sid, $mat->{lngindex}, $i) if $mat->{lngindex};

            # The unit price is a product of the material cost and pad area.
        }

        # Add the pricing.

        # If we're padding a project that doesn't have native padding, then
        # we're dividing our quantity of pads made by pages per pad
        my $project_type = eprint::project::get_type($log, $dbh, $pid);
        if ($project_type ne 'Scratch/WritingPads')
        {
            $qty /= $page_qty if $page_qty;
        }

        $price = ($price * $qty / $padding_imposition);
        callback::call('service_calc_end', $pid, $sid, \$padding_makeready, \$price);

        my $total = $padding_makeready                     # Setup
                  + $price  # Run
                  + ($material * $area * $qty);            # Material

print STDERR "HAVE MAKE READY: $padding_makeready \n";
print STDERR "HAVE PRICE: $price * Qty: $qty / IMP: $padding_imposition \n";
print STDERR "HAVE MATERIAL: $material * Area: $area QTY: $qty \n";

        # Unit cost is price per pad.
        @$specs{"txtPrice$i", "txtUnitPrice$i"}
            = format_pricing($total, $qty);
        
        # If the price is ever zero, we have a problem.
#        $status = 'uncalculated' if $total <= 0;

        # Spit out some debugging information if we need it.
        $specs->{txtPaddingImposition} = $padding_imposition;
        $specs->{pad_sheets}           = $page_qty;
		$specs->{equipment} = eprint::equipment::get_id_by_index(
			$log, $dbh, $padding_station
		);
    }

    return $status ? $status : 'calculated';
}


# Return the first padding station that can process the job. TODO consider
# them all, this is just a cleanup of existing code.
sub get_padding_station {
    my ($dbh, $service_type, $w, $h, $pid) = @_;

    for my $eid (valid_equipment(undef, $dbh, $service_type, $pid)) {

        my ($max_w, $min_w, $max_h, $min_h, $max_imp) 
            = eprint::equipment::get_specifications(undef, $dbh, $eid, 
                qw(maximumSheetWidth minimumSheetWidth  maximumSheetLength minimumSheetLength maximumPaddingImposition));

print STDERR "$max_w, $min_w, $max_h, $min_h, $max_imp ON $eid \n";
        return $eid if $w <= $max_w && ($w >= $min_w || $max_imp > 1) && $h <= $max_h;
    }

    return undef;
}

1;

