package eprint::print_service_base;
use strict;
use warnings;

use Data::Dumper;

use PQS::model::service;
use eprint::project qw( get_quantities );
use eprint::service qw( get_specifications_pairs set_status
                        get_service_full_price insert_service_specs
						format_pricing);

require Apache2::Request;

use jsrs;

our $field_types = {
    #a field containing the quantity of material needed
    quantity_field  => q{},

    #the material id -- can be overridden by entries in specs_splice
    material_field  => q{},

    #an array of the different specs splice (sets material field in each
    #iteration if set.
    specs_splice    => [],

    #a hashref of the name of the 4 different services used by a service.
    service_names   => {},

    #a list of fields that must be set before it will even attempt to price.
    required_fields => [],
};

sub new {
    die __PACKAGE__ . " is meant only to be used as a base class!\n";
}

sub necessary {
    return 0;
}

sub calc {
    my ($self, $log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    my $price = 0;

    # otherwise it just adds and adds and adds ad infinitum.
    delete @$specs{qw( txtPrice      txtPrice1     txtPrice2
                      txtPrice3     txtUnitPrice  txtUnitPrice1
                      txtUnitPrice2 txtUnitPrice3               )};

    $pid = $pid 
         || $variable->{ProjectIndex}
         || $specs->{ProjectIndex};

    my @qty; @qty[1 .. 3] = get_quantities($log, $dbh, $pid);

    if (!scalar @{ $self->specs_splice }) {
        $self->specs_splice([ $self->material_field ]);
    }

    my $status = 'uncalculated';
    foreach my $spec ( @{ $self->specs_splice } ) {
        next unless $specs->{$spec};

 #       $self->material_field( $spec );

        my ($device, $price_for_one, $mat, $setup, $run_price, $min_charge ) = $self->_calc(
            $log, $dbh, $variable, $pid, $sid, $specs
        );

        return 'uncalculated' unless $price_for_one;

        $specs->{ddmDevice} = $device;
        $specs->{hdnDevice} = $device;

        for my $i ( 1 .. 3 ) {
            my $quantity = $qty[$i];

            next unless $quantity;

            PQS::model::service::set_materials_estimate($quantity, undef, $sid, $specs->{$self->material_field}, $i) if $specs->{$self->material_field};

            my $make_ready = $setup;
            my $run_total = $run_price * $quantity;
            callback::call('service_calc_end', $pid, $sid, \$make_ready, \$run_total);

            my $price = $run_total + ($mat * $quantity) + $make_ready;
	       $price = $min_charge if $price < $min_charge;
            return 'uncalculated' unless $price && $price > 0;

            @$specs{"txtPrice$i", "txtUnitPrice$i"}
                = format_pricing($price, $quantity);
        }

        $status = 'calculated';
    }

    return $status;
}


sub _calc {
    my ($self, $log, $dbh, $variable, $pid, $sid, $specs) = @_;

    # This should stop the code from trying to change your input values.
    #  delete $specs{$self->material_field};
    #  delete $specs{$self->quantity_field};

    foreach my $field ( @{ $self->required_fields } ) {
        return -1 if !exists $specs->{$field};
    }

    my $quantity = $specs->{$self->quantity_field};
    my $material = $specs->{$self->material_field};
print STDERR "HAVE MAT: $material \n";

    $variable->{force_device} = $specs->{ddmDevice}
        if $specs->{ddmDevice} && $specs->{chkDeviceOverride} eq 'y';

    my ($hardware, $price, $mat_price, $setup_price, $run_price, $min_charge) = get_service_full_price(
        $log, $dbh, $variable, $self->service_names, $quantity, $material
    );

    return wantarray ? ($hardware, $price, $mat_price, $setup_price, $run_price, $min_charge) : $price;
}

sub DESTROY { }

sub AUTOLOAD {
    my ($self, @params) = @_;

    my $command =  our $AUTOLOAD;
       $command =~ s/.+:://;

    if (!exists $field_types->{$command}) {
        die "Cannot call " . __PACKAGE__ . "->$command()\n";
    }

    if (scalar @params) {
        if (ref $params[0] ne ref $field_types->{$command}) {
            die "Wrong datatype for: " . __PACKAGE__ . "->$command()\n";
        }

        $self->{$command} = $params[0];
    }

    #if the value isnt set, ensure they get the right datatype.
    if (!exists $self->{$command}) {
        return $field_types->{$command};
    }
    else {
        return $self->{$command};
    }
}

1;
