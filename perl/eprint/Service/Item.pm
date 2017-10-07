# This is really not a service so much as a place to store specifications we
# don't otherwise have anywhere to put.
package eprint::Service::Item;
use strict;
use warnings;
no warnings qw(uninitialized);

use eprint::project                      qw(get_type get_press_type check_for_service);
use eprint::print_project                qw(insert_service delete_service);
use eprint::Service::Printing::Constants qw(SURFACE);

sub necessary {
    my ($log, $dbh, $pid, $service_type) = @_;

    return get_type($log, $dbh, $pid) eq 'ScreenItem';
}

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    die "Only screen presses can print on items" 
        unless get_press_type($log, $dbh, $pid) eq 'screen';

    my $surfaces 
        = $specs->{txtScreenPrintingSurfaces} 
        = int $specs->{txtScreenPrintingSurfaces};

    return $surfaces ? 'calculated' : 'uncalculated';
}

# Create a surface for each one needed.
sub action {
    my ($log, $dbh, $pid, $sid, $service_type, $specs) = @_;

    # Remove all existing surfaces. TODO Preserve the ones we can unless the
    # dimensions are changed. Maybe ask the user too?
    delete_service($log, $dbh, $pid, $_) 
        for check_for_service($log, $dbh, $pid, 'Printing');

    # Add a new surface for each requested by the user. NOTE: Reversed due to
    # build process calculating last modified first (so covers can come after
    # interior spreads for books).
    for my $i (reverse (1 .. int $specs->{txtScreenPrintingSurfaces})) {
        my $surface = insert_service($log, $dbh, $pid, 'Printing', {}, {
            txtSignatureType          => SURFACE,
            txtServiceDescription     => SURFACE . " $i",
            SignatureIndex            => $i,
        });
    }

    # NOTE: Special packing and handling will handle themselves via their
    # necessary() functions.
    
    return 1;
}

1;
