package eprint::Service::ICutting;
use strict;
use warnings;

use base qw( eprint::print_service_base );

use eprint::service qw(valid_equipment_dropdown);

sub new {
    my ($class) = @_;

    my $service_names = {
        action    => 'ICutting',
        service   => 'ICutter',
        makeready => 'ICutterMakeReady',
        mincharge => 'ICutterMinCharge',
    };

    my $self = {
        service_names   => $service_names,
        specs_splice    => [ 'txtLinearCut' ],
        required_fields => [ 'txtLinearCut' ],
        quantity_field  => 'txtLinearCut',
    };

    bless $self, $class;

    return $self;
}

sub display {
    my ($self, $log, $dbh, $service_type, $pid, $sid, $specs) = @_;

    return { 
        ddmDeviceList => valid_equipment_dropdown($dbh, $service_type),
    }
}


1;
