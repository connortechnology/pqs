package eprint::Service::ClipSealing;
use strict;
use warnings;

use POSIX            qw(ceil);
use List::Util       qw(sum);
use eprint::service  qw(:common);
use eprint::project  qw(get_quantities);

# Currently this is based on a clip sealer that can do two clips per side on a
# sinle pass through the machine.
use constant CLIPS_PER_RUN => 2;

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    my $status = 'uncalculated';
    my @qty    = (undef, get_quantities($log, $dbh, $pid));

    # The total number of runs through the clip sealer a project needs. A clip
    # sealer can put n clips onto a single side of a project each pass.
    my $runs = sum( 
        map  { $_ = ceil ($specs->{$_} / CLIPS_PER_RUN) } 
        grep { /^txtSealsQty/                           } 
              keys %$specs 
    );

    return 'uncalculated' unless $runs && $runs > 0;

    # If the user specifically request perforated clip seals, we'll use them
    # instead of the standard ones.
    my $type = $specs->{rdbPerforated} && $specs->{rdbPerforated} eq 'Y'
        ? 'Perforated' : '';

    my $make_ready = get_price($log, $dbh, $variable, 'ClipSealingMakeReady');
    my $min_price  = get_price($log, $dbh, $variable, 'ClipSealingMinimumCharge');
    my $per_1000   = get_price($log, $dbh, $variable, "ClipSealing$type", $runs);

    for my $i (1..3) {

		my $qty = $specs->{"txtQuantity$i"} || $qty[$i];
        next unless $qty && $qty > 0;

        # The price a product of the number of runs each project needs, and
        # the number of projects to be processed (priced per 1000 projects).
        my $price = $make_ready + $runs * ($qty/1000 * $per_1000);

        # If any valid quantity doesn't price we have a problem.
        return 'error' unless $price > 0;

        $price = $min_price if $min_price && $price < $min_price;

        @$specs{"txtPrice$i", "txtUnitPrice$i"} 
            = format_pricing($price, $qty);

        $status = 'calculated';
    }
    
    return $status;
}

1;
