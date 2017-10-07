package eprint::Service::Grommeting;
use strict;
use warnings;

use base qw( eprint::print_service_base );

use eprint::service qw(valid_equipment_dropdown);
use ssi             qw(make_drop_down);

sub new {
    my ($class) = @_;

    my $service_names = {
        action    => 'Grommeting',
        service   => 'Grommeting',
        makeready => 'GrommetMakeReady',
        mincharge => 'GrommetMinCharge',
    };

    my $self = {
        service_names   => $service_names,
        required_fields => [qw( txtGrommetCount ddmGrommet )],
        quantity_field  => 'txtGrommetCount',
        material_field  => 'ddmGrommet',
    };

    bless $self, $class;
    return $self;
}

sub display {
    my ($self, $log, $dbh, $service_type, $pid, $sid, $specs) = @_;

    my $materials = $dbh->selectcol_arrayref(q{
        SELECT lngindex, strname
        FROM tbl_materials
        WHERE lngtype = 14
    }, { Columns => [1, 2] });

    return { 
        ddmDeviceList  => valid_equipment_dropdown($dbh, $service_type),
        ddmGrommetList => make_drop_down($materials),
    }
}


1;
