# NOTE: The 'stitching' this module handles is large format sewing, NOT saddle
# stitching or loop stitching. Those are handled by the bindery module.
package eprint::Service::Stitching;
use strict;
use warnings;

use base qw( eprint::print_service_base );

use ssi             qw(make_drop_down);
use eprint::service qw(valid_equipment_dropdown get_specifications);
use eprint::project qw(get_press_type get_print_container);
use eprint::Service::Printing::Constants qw(LARGE_FORMAT);

sub necessary {
    my ($specs, $log, $dbh, $pid, $service_type) = @_;

    my $press_type = get_press_type($log, $dbh, $pid);

    return 0 unless $press_type eq LARGE_FORMAT;

    my $print = get_print_container($log, $dbh, $pid);
    my $type  = get_specifications($log, $dbh, $pid, $print, 'rdbBindMethod');

    return 1 if $type && $type eq 'Stitch';

    return 0;
}

sub new {
    my ($class) = @_;

    my $service_names = {
        action    => 'Stitching',
        service   => 'Stitching',
        makeready => 'StitchingMakeReady',
        mincharge => 'StitchingMinCharge',
    };

    my $self = {
        service_names   => $service_names,
        required_fields => [ 'txtStitchLength', 'ddmStitchType' ],
        quantity_field  => 'txtStitchLength',
        material_field  => 'ddmStitchType',
    };

    bless $self, $class;

    return $self;
}

sub display {
    my ($self, $log, $dbh, $service_type, $pid, $sid, $specs) = @_;

    my $materials = $dbh->selectcol_arrayref(q{
        SELECT lngindex, strname
        FROM tbl_materials
        WHERE lngtype = 16
    }, { Columns => [1, 2] });

    return { 
        ddmDeviceList => valid_equipment_dropdown($dbh, $service_type),
        ddmTypeList    => make_drop_down($materials),
    }
}


1;
