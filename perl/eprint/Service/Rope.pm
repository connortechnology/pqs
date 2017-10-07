package eprint::Service::Rope;
use strict;
use warnings;

use base qw( eprint::print_service_base );

use eprint::service qw(valid_equipment_dropdown);
use ssi             qw(make_drop_down);

sub new {
    my ($class) = @_;

    my $service_names = {
            action    => 'Rope',
            service   => 'Rope',
            makeready => 'RopingMakeReady',
            mincharge => 'RopingMinCharge',
    };

    my $self = {
        service_names   => $service_names,
        required_fields => [qw( txtRopeLength ddmRopeType )],
        quantity_field  => 'txtRopeLength',
        material_field  => 'ddmRopeType',
    };

    bless $self, $class;

    return $self;
}

sub display {
    my ($self, $log, $dbh, $service_type, $pid, $sid, $specs) = @_;

    my $materials = $dbh->selectcol_arrayref(q{
        SELECT lngindex, strname
        FROM tbl_materials
        WHERE lngtype = 15
    }, { Columns => [1, 2] });

    return { 
        ddmDeviceList => valid_equipment_dropdown($dbh, $service_type),
        ddmRopeList   => make_drop_down($materials),
    }
}

1;
