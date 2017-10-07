package eprint::Service::SpecialHandling;
use strict;

# TODO Merge packing and handling as their only difference is the service type
# name used in getting pricing.

use eprint::project qw(get_type get_quantities get_print_container);
use sql qw(:common);
use eprint::service qw(:common);

sub necessary {
    my ($log, $dbh, $pid, $service_type) = @_;

    # We only apply to screen items.
    return 0 unless get_type($log, $dbh, $pid) eq 'ScreenItem';

    # Get the print container as it stores packing info.
    my $main = get_print_container($log, $dbh, $pid);

    # If any packing (counted in seconds) is needed, we're needed.
    return get_specifications($log, $dbh, $pid, $main, 'txtSpecialHandling');
}

# Handling charges are per second per item, the handling rate is stored in
# dollars per hour.
sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    # Get the print container as it stores handling info.
    my $item = get_print_container($log, $dbh, $pid);

    my $seconds 
        = get_specifications($log, $dbh, $pid, $item, 'txtSpecialHandling');

    return 'uncalculated' unless $seconds;

    my $make_ready = get_price($log, $dbh, $variable, 'HandlingMakeReady');
    my $run_rate   = get_price($log, $dbh, $variable, 'Handling');
    my @qty        = (undef, get_quantities($log, $dbh, $pid));

    return 'error' unless $run_rate && $run_rate > 0;

    for my $i (1..3) {
        next unless $qty[$i] && $qty[$i] > 0;

        # Run pricing is in hours.
        my $price = $make_ready + $run_rate * ($seconds/60/60) * $qty[$i];

        return 'error' unless $price && $price > 0;

        @$specs{"txtPrice$i", "txtUnitPrice$i"}
            = format_pricing($price, $qty[$i]);
    }

    return 'calculated';
}

sub display {
    my ($log, $dbh, $service_type, $pid, $sid, $specs) = @_;

    # Get the print container as it stores packing info.
    my $item = get_print_container($log, $dbh, $pid);

    my $seconds 
        = get_specifications($log, $dbh, $pid, $item, 'txtSpecialHandling');

    return { seconds => $seconds };
}

1;
