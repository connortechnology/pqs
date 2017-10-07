package eprint::Service::Welding;
use strict;
use warnings;

use base qw( eprint::print_service_base );

use eprint::service qw(valid_equipment_dropdown get_specifications);
use eprint::project qw(get_press_type get_print_container);
use eprint::Service::Printing::Constants qw(LARGE_FORMAT);

sub necessary {
    my ($specs, $log, $dbh, $pid, $service_type) = @_;

    my $press_type = get_press_type($log, $dbh, $pid);

    return 0 unless $press_type eq LARGE_FORMAT;

    my $print = get_print_container($log, $dbh, $pid);
    my $type  = get_specifications($log, $dbh, $pid, $print, 'rdbBindMethod');

    return 1 if $type && $type eq 'Weld';

    return 0;
}

sub new {
    my ($class) = @_;

    my $service_names = {
        action    => 'Welding',
        service   => 'Welding',
        makeready => 'WeldingMakeReady',
        mincharge => 'WeldingMinCharge',
    };

    my $self = {
        service_names   => $service_names,
        required_fields => [qw( txtWeldLength )],
        quantity_field  => 'txtWeldLength',
		specs_splice	=> ['txtWeldLength'],
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
