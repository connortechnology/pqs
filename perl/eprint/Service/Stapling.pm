# NOTE: The 'stitching' this module handles is large format sewing, NOT saddle
# stitching or loop stitching. Those are handled by the bindery module.
package eprint::Service::Stapling;
use strict;
use warnings;

use base qw( eprint::print_service_base );

use ssi             qw(make_drop_down);
use eprint::service qw(valid_equipment_dropdown get_specifications valid_equipment format_pricing);
use eprint::project qw(get_press_type get_print_container get_finished_calliper);
use eprint::Service::Printing::Constants qw(LARGE_FORMAT);
use eprint::equipment qw(get_specification);

sub necessary {
    my ($specs, $log, $dbh, $pid, $service_type) = @_;

    return 0;
}



sub calc {
    my ($self, $log, $dbh, $var, $pid, $sid, $service_type, $specs) = @_;

# Need to lookup price ranged on number of staples.
# Will now divide by StapleGroup after price has been caclulated.
#	$specs->{staples} = $specs->{txtStapleQty} / $specs->{txtStapleQtyGroup};

	$specs->{staples} = $specs->{txtStapleQty};

	my $cal = get_finished_calliper($log, $dbh, $var, $pid) * $specs->{txtStapleQtyGroup} ;

	my ($e) = valid_equipment($log, $dbh, 'Stapling');

	my $max_cal = get_specification($log, $dbh, 'Maximum Stapling Calliper Standard',undef,$e);

	my $s = $self->service_names;

	$specs->{hdnStapleType} = 'Standard';

	if ( $cal > $max_cal ) {

		$max_cal = get_specification($log, $dbh, 
					'Maximum Stapling Calliper Heavy',undef,$e);

		if ( $cal  > $max_cal ) {
			$specs->{error} = "You have exceeded the maximum stapling calliper of: $max_cal";
		} else { 
			$s->{service} = 'HeavyStapling';
			$specs->{hdnStapleType} = 'Heavy';
		}
	}

	my $x = eprint::print_service_base::calc(
		$self, $log, $dbh, $var, $pid, $sid, $service_type, $specs);

	$specs->{txtStapleQtyGroup} = 1 unless $specs->{txtStapleQtyGroup};

	map {
		$specs->{"txtPrice$_"} 		=   format_pricing( $specs->{"txtPrice$_"} 
															/ $specs->{txtStapleQtyGroup});
		$specs->{"txtUnitPrice$_"} 	=   format_pricing( $specs->{"txtUnitPrice$_"} 
															/ $specs->{txtStapleQtyGroup});
	} (1..3);

	return $x;

};



sub new {
    my ($class) = @_;

    my $service_names = {
        action    => 'Stapling',
        service   => 'Stapling',
        makeready => 'StaplingMakeReady',
        mincharge => 'StaplingMinCharge',
    };

    my $self = {
        service_names   => $service_names,
        quantity_field  => 'staples',
		specs_splice	=> ['staples']
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
