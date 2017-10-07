# NOTE: The 'stitching' this module handles is large format sewing, NOT saddle
# stitching or loop stitching. Those are handled by the bindery module.
package eprint::Service::Taping;
use strict;
use warnings;

use base qw( eprint::print_service_base );

use ssi             qw(make_drop_down);
use eprint::service qw(valid_equipment_dropdown get_specifications valid_equipment);
use eprint::project qw(get_press_type get_print_container get_finished_calliper);
use eprint::Service::Printing::Constants qw(LARGE_FORMAT);
use eprint::equipment qw(get_specification);

sub necessary {
    my ($specs, $log, $dbh, $pid, $service_type) = @_;

    return 0;
}



sub calc {
    my ($self, $log, $dbh, $var, $pid, $sid, $service_type, $specs) = @_;

	$specs->{feet} = $specs->{txtInches};

	return eprint::print_service_base::calc(
		$self, $log, $dbh, $var, $pid, $sid, $service_type, $specs);
};



sub new {
    my ($class) = @_;

    my $service_names = {
        action    => 'Taping',
        service   => 'Taping',
        makeready => 'TapingMakeReady',
        mincharge => 'TapingMinCharge',
    };

    my $self = {
        service_names   => $service_names,
        quantity_field  =>'feet',
		specs_splice	=> ['txtInches'],
		material_field  => 'ddmtaping'
    };

    bless $self, $class;

    return $self;
}

sub display {
    my ($self, $log, $dbh, $service_type, $pid, $sid, $specs) = @_;

    my $materials = $dbh->selectcol_arrayref(q{
        SELECT lngindex, strname
        FROM tbl_materials
        WHERE lngtype = 18
		ORDER by strname
    }, { Columns => [1, 2] });

use Data::Dumper;
print STDERR "DISPLAY ", Dumper(make_drop_down($materials));
    return { 
        ddmtaping => make_drop_down($materials),
    }
}


1;
