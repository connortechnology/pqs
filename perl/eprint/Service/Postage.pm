package eprint::Service::Postage;
use strict;
use Class::Struct;

use eprint::project   qw( get_print_container);
use eprint::service   qw( :common            );
use eprint::equipment qw( equipment_fits     );
use eprint::print     qw(                    );
use ssi               qw( make_drop_down     );
use callback;

use Data::Dumper;


sub calc {
    my ($log, $dbh, $var, $pid, $sid, $service_type, $specs) = @_;

    my $status  = 'uncalculated';
    my $inserts = int $specs->{txtInsertQty};

    # Why come up with your own ideas when you can steal raymonds. Lets wrap
    # some of the older functions into nice little packages.
    local *price = sub {
        my ($equip, $service, $qty, $subservice) = @_;

        get_price($log, $dbh, $var, $service, $qty, $equip, $subservice);
    };

    local *fits = sub {
        my ($j, $e) = @_;
        return 1 if $j->width == 1 and $j->height == 1;

        equipment_fits(
            $log, $dbh, $e->{id}, $j->width, $j->height, $j->calliper
        );
    };

    # Start be getting the basice specs needed for the pricing.
    my $print = get_print_container($log, $dbh, $pid);

    #now make a price for each quantity.
    foreach my $i ( 1 .. 3 ) {
        if ( $specs->{"txtQuantity$i"} && $specs->{ddmPostage} ) {
            my ($p) = get_specifications(
                $log, $dbh, $pid, $print, "hdnEquipment$i"
            );

            my $s = $dbh->selectrow_array(q{
                SELECT strsupplier
                FROM tbl_equipment
                WHERE strid = ?
            }, undef, $p);

            my $qty = $specs->{"txtQuantity$i"};

            my @jobs;

            my $j = POSTAGE_Job->new(
                supplier    => $s,
                press       => $p,
                records     => $inserts,
                qty         => $qty,
                presort     => $specs->{rdbPreSort} eq 'Yes' ? 1 : 0,
                subservice  => $specs->{ddmPostage},
                pid => $pid,
                sid => $sid
            );

            push @jobs, $j;

            my $total;

            foreach my $j ( @jobs ) {
                my $price  = price_job( $dbh, $j );
                $total    += $price->{cost};
            }


            @$specs{"txtPrice$i", "txtUnitPrice$i"}
                = format_pricing($total, $qty);

            $status = 'calculated' if $specs->{"txtPrice$i"} > 0;
        }
        else {
            $specs->{"txtPrice$i"}     = '0.00';
            $specs->{"txtUnitPrice$i"} = '0.00';
        }
    }

    $specs->{txtPostageDetails} = $dbh->selectrow_array(q{
        SELECT description
        FROM sub_service_type
        WHERE id = ?
    }, undef, $specs->{ddmPostage});

    return $status;
}

sub price_job {
    my ($dbh, $j ) = @_;

    my @eids = map { postage_station($dbh, $_) }
                     valid_equipment(undef, $dbh, 'Postage');

    my $price;

    # If our print Supplier is not 'House' then first check for equipment to
    # match our print supplier.
    if ($j->supplier ne 'House') {
        $price = compare_equipment(
            $j, grep { $_->{supplier} ne 'House'
                   and $_->{supplier} eq $j->supplier } @eids
        );
    }

    # Next try all of the House equipment.
    if ($j->supplier eq 'House' || !$price) {
        $price = compare_equipment(
            $j, grep { $_->{supplier} eq 'House' } @eids
        );
    }

    # Finally try anything that is left if we still do not have a price.
    $price ||= compare_equipment(
        $j, grep { $_->{supplier} ne 'House'
               and $_->{supplier} ne $j->supplier } @eids
    );

    return $price;
}

sub compare_equipment {
    my ($j,  @eids) = @_;

    my @e_prices;

    foreach my $e (@eids) {
        next unless fits($j, $e);

        my $error;
        my $total = 0;

        my $make_ready   = price($e->{ref}, 'PostageMakeReady', undef);
        $error  = 'Price not found' unless $make_ready;

        my $p      = price($e->{ref}, 'Postage', $j->qty, $j->subservice);
        $error  = 'Price not found' unless $p;
        my $run_price = $p * $j->qty;

        if ( $j->presort ) {
            my $p   = price(undef,'PostagePreSortMakeReady', undef);
            $error  = 'Price not found' unless $p;
            $make_ready += $p;

            $p      = price($e->{ref}, 'PostagePreSort', $j->qty, $j->subservice);
            $error  = 'Price not found' unless $p;
            $run_price += $p * $j->qty / 1000;

        }
        callback::call('service_calc_end', $j->{pid}, $j->{sid}, \$make_ready, \$run_price);
        $total += $make_ready + $run_price;

        push @e_prices, {
            cost            => $total,
            equipment       => $e,
            qty             => $j->qty,
        } unless $error;
    }

    return (sort { $a->{cost} <=> $b->{cost} } @e_prices)[0];
}

sub postage_station {
    my $dbh = shift;
    my $eid = shift;

    # BASIC INFO
    #
    # General equipment information.
    my %e = %{ $dbh->selectrow_hashref(q{
        SELECT
            lngindex    AS id,
            strid       AS ref,
            strname     AS name,
            strsupplier AS supplier
        FROM
            tbl_equipment
        WHERE
            lngindex = ?
        }, undef, $eid
    ) };

    # EQUIPMENT SPECIFICATIONS
    #
    # Get the standard sizing specs. (max/min height/width).
    my $spec = $dbh->selectall_hashref(q{
        SELECT
            strname  AS name,
            strvalue AS value
        FROM
            tbl_equipment_specifications
        WHERE
            strname IN ('Maximum Sheet Length', 'Maximum Sheet Width')
        AND
            lngequipmentindex = ?
        }, 'name', undef, $eid
    );

    $e{max_width}  = $spec->{'Maximum Sheet Width'}{value};
    $e{max_length} = $spec->{'Maximum Sheet Length'}{value};

    return \%e;

}

struct POSTAGE_Job => {
    signature  => '$', # signature,  # Signature ID [optional]

    # Standard Fields
    width      => '$', # float,      # |
    height     => '$', # float,      # |- Before cutting dimensions
    calliper   => '$', # float,      # |
    qty        => '$', # int,        # Quantity of sheets/bound projects
    supplier   => '$', # string,     # Supplier of the printed sheet
    press      => '$', # string      # Press the project was printed on.
    note       => '$', # text,       # Freeform text of the type of cut, etc.

    # Specific to Postage
    presort    => '$', # int,        # Do we need presorting
    subservice => '$', # int,        # Type of Postage Service
};

sub display {
    my ( $log, $dbh, $service_type, $pid, $sid, $specs ) = @_;
	my %page;

    my $result_set = $dbh->selectcol_arrayref(q{
        SELECT ss.id, ss.name
        FROM sub_service_type ss, tbl_service_types st
        WHERE st.strid = 'Postage'
        AND ss.service_type = st.lngindex
    }, { Columns => [1, 2] });

    $page{ddmPostage} = make_drop_down(
        $result_set, $specs->{ddmPostage}
    );
	return \%page;
}


1;
