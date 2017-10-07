package eprint::Service::HandAssembly;
use strict;
use warnings;

use eprint::service qw(:common);

use constant COMPLEXITIES => qw(Simple Average Complex);

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    # We need to know the assembly complexity to proceed.
    return 'uncalculated' unless 
        grep { $specs->{rdbHandAssemblyType} eq $_ } COMPLEXITIES;


    # This is NOT the way to get equipment for a service.
    my @equipment = valid_equipment(undef, $dbh, $service_type, $pid);

    my @qty = (undef, @$specs{qw(txtQuantity1 txtQuantity2 txtQuantity3)});

    my $status = 'uncalculated';
    for my $i (1..3) {
        next unless $qty[$i] && $qty[$i] > 0;

        my %best;
        for my $equip (@equipment) {
            my $rate = get_price($log, $dbh, $variable, 
                "HandAssembly$specs->{rdbHandAssemblyType}", 
                $qty[$i], 
                $equip
            );

            # Pricing is per thousand based on the type.
            my $price = $rate * $qty[$i]/1000;

            # Keep track of the lowest price as we go.
            if (!exists $best{price} || $price < $best{price}) {
                $best{price}     = $price;
                $best{equipment} = $equip;
            }
        }

#        return 'error' unless $best{price} && $best{price} > 0;

        @$specs{"txtPrice$i", "txtUnitPrice$i"}
            = format_pricing($best{price}, $qty[$i]);
        
        $specs->{"hdnEquipment$i"} = $best{equipment};

        $status = 'calculated';
    } 

    return $status;
}

1;
