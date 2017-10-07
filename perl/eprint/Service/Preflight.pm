package eprint::Service::Preflight;
# DESCRIPTION
#
#   Charges a flat fee and/or a charge prorated to the imposition charge based
#   on the file type supplied. Eg. a QuarkXPress document is charged $20
#   handling fee plus $0.50 on the dollar of imposition for preflight
#   operations.
#
# OTHER DESIGN CONSIDERATIONS
#
#   - We don't consider the fact different spread could be supplied in
#   different file formats (Eg. seperate cover).
#
#   - You shouldn't be able to "supply" preflight, should you?
#   
#   - The necessary pricing present check doesn't respect price lists (as who
#   the customer is and their price list isn't passed to necessary functions).
#
#   - Very hard to debug as if service is missing we'll get 0 which is a valid
#   price.
#  
#   - We don't consider differing versions of the various products.
#
use strict;
use warnings;

use Apache2::Const     qw(OK);
use eprint::print_project qw(remove_service);
use eprint::service       qw(:common :need);
use POSIX                 qw(ceil);

# Are we needed?
sub necessary {
    my ($log, $dbh, $pid, $service_type) = @_;

    # If the project isn't being supplied as a digital file, we're not needed.
    return 0 if 'ElectronicFile' ne $dbh->selectrow_array(q{
        SELECT strdesign FROM tbl_projects WHERE lngprojectindex = ?
    }, {}, $pid);

    # The file type comes from a project attribute.
    my $file_type = $dbh->selectrow_array(q{
        SELECT lower(strprograms) FROM tbl_projects WHERE lngprojectindex = ?
    }, {}, $pid);
    return 0 unless $file_type;

	my $project_type = eprint::project::get_type($log, $dbh, $pid);
	
	return 0 if $project_type eq 'InventoryCheckOut';
   
    # If there are no surcharges, there's no reason to pop up. NOTE: This
    # should only check the current customer's price list.
    return 0 unless $dbh->selectrow_array(qq{
        SELECT true
        FROM tbl_service_prices p, tbl_services s, tbl_service_types t
        WHERE t.lngindex = s.lngtype
          AND s.lngindex = p.lngserviceindex 
          AND t.strid    = ?
          AND s.strid    ~ '^$file_type'
        LIMIT 1
    }, undef, $service_type);

    return 1;
}

# Determine the pre-flight charge.
sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    # The file type comes from a project attribute.
    my $file_type = $dbh->selectrow_array(q{
        SELECT lower(strprograms) FROM tbl_projects WHERE lngprojectindex = ?
    }, {}, $pid);

    # We can't calculate unless we know the file type.
    return 'uncalulated' unless $file_type;

	my ($eid) = valid_equipment(undef, $dbh, $service_type, $pid);

    # Get the base charge and rate for the given file type. TODO: This does
    # not account for multiple pieces of equipment having the same service.
    # We'll get a price IN DATABASE ORDER using this method!
    my $base = get_price($log, $dbh, $variable, $file_type.'_base', undef, $eid);
    my $rate = get_price($log, $dbh, $variable, $file_type.'_rate', undef, $eid);

    # Sum all the imposition charges for the project.
    my $imposition = $dbh->selectrow_array(q{
        SELECT sum(strvalue::numeric) FROM tbl_service_specifications
        WHERE strname = 'hdnImpositionCharge' AND lngprojectindex = ?
    }, {}, $pid);

    $log->debug(
        "PREFLIGHT: File Type: $file_type Base: $base Rate: $rate Imposition Charge: $imposition"
    );

    # The preflight file-type surcharge is the base plus n dollars per
    # imposition dollar (rate). ie. $1.50 = 1.5x imposition charge.
    my ($price) = format_pricing($base + $rate * $imposition, 1);

    $specs->{"txtPrice$_"} = $price for 1..3;

    return 'calculated';
}


1;
