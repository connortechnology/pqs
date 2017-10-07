package eprint::Service::Mounting;
use strict;
use warnings;

use base qw( eprint::print_service_base );
use POSIX           qw(floor ceil);

use eprint::service qw( get_service_full_price :specs );
use ssi             qw( make_drop_down material_drop_down);
use eprint::project qw( get_print_container get_quantities  );
use callback;
use PQS::model::materials;
use PQS::model::service;

sub display {
	my ($self, $log, $dbh, $service_type, $pid, $sid, $specs) = @_;

    return {
		ddmMountings => material_drop_down($log, $dbh, 'Mounting Board') 
	}

}

sub new {
    my ($class) = @_;

    my $service_names = {
        action    => 'Mounting',
        service   => 'Mount',
        makeready => 'MountMakeReady',
        mincharge => 'MountMinCharge',
    };

    my $self = {
        specs_splice  => [ 'mounting_type' ],
        service_names => $service_names,
    };

    bless $self, $class;

    return $self;
}


sub calc {
    my ($self, $log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;
	my $prin_sid = get_print_container( $log, $dbh, $pid);

	my %p_specs = eprint::service::get_specifications_pairs($log, $dbh, $pid, $prin_sid,
            qw( flat_height flat_width)
	);

	map {$specs->{$_} = $p_specs{$_}} keys %p_specs;
				

	my @qtys = (undef, get_quantities($log, $dbh, $pid));

	my $prin_sid = get_print_container( $log, $dbh, $pid);

	my %p_specs = eprint::service::get_specifications_pairs(
			$log, $dbh, $pid, $prin_sid,
            qw(flat_width flat_height)
	);

	map {$specs->{$_} = $p_specs{$_}} keys %p_specs;

    my $square_feet = $specs->{flat_height} * $specs->{flat_width} / 144;

    my ($device, $mount_charge, $mat, $setup) = get_service_full_price(
        $log, $dbh, $variable, $self->service_names, $square_feet,
        $specs->{mounting_type}
    );

use Data::Dumper;
print STDERR "MOUNING ", Dumper($device, $mount_charge, $mat, $setup,
$specs->{mounting_type},  $square_feet, $specs	);

	$mount_charge -= ( $mat/2 ) if $specs->{double_sided};

	my @qtys = (undef, get_quantities($log, $dbh, $pid));

	my $mat = PQS::model::materials::material_by_strid($specs->{mounting_type});

	for my $i (1..3) {
          my $make_ready = $setup;
          my $run_price = (($mount_charge-$setup) * $qtys[$i]);
          callback::call('service_calc_end', $pid, $sid, \$make_ready,    \$run_price);
		$specs->{'txtPrice'.$i} =  sprintf("%.2f", floor(
				$run_price + $make_ready
		));
          PQS::model::service::set_material_estimate($qtys[$i], undef, $sid, $mat->{lngindex}, $i) if $mat->{lngindex};
	}
	
	my $status = $mat ? 'calculated' : 'uncalculated';

    die "Failed fetching mounting price.\n" if $device == -1;

	for my $i (1..3) {
		$specs->{'txtPrice'.$i} =  sprintf("%.2f", 
				($mount_charge * $qtys[$i]) + $setup
		);
	}

	return $status;
}

1;
