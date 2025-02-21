package eprint::Service::Laminating;
use strict;
use warnings;

use base qw( eprint::print_service_base );
use POSIX           qw(floor ceil);


use eprint::service qw( get_service_full_price );
use eprint::project qw( get_print_container get_quantities  );
use ssi             qw( make_drop_down material_drop_down);
use callback;
use PQS::model::materials;
use PQS::model::service;

sub display {
	my ($self, $log, $dbh, $service_type, $pid, $sid, $specs) = @_;

    return {
		ddmLaminates => material_drop_down($log, $dbh, 'Laminate') 
	}

}

sub necessary {
    my ( $specs, $log, $dbh, $pid, $service_type) = @_;

	my $prin_sid = get_print_container( $log, $dbh, $pid);

	my %specs = eprint::service::get_specifications_pairs($log, $dbh, $pid, $prin_sid,
            qw( s0_laminate  s1_laminate )
	);

	return 1 if grep {$specs{$_}} keys %specs;

	return 0;
}

sub new {
    my ($class) = @_;

    my $service_names = {
        action    => 'Laminating',
        service   => 'Laminating',
        makeready => 'LaminatingMakeReady',
        mincharge => 'LaminatingMinCharge',
    };

    my $self = {
        specs_splice  => [qw( s0_laminate s1_laminate )],
        service_names => $service_names,
    };

    bless $self, $class;

    return $self;
}


#TODO - we can probably eliminate this sub by making a _get_quantity internal
#method that will know to do a $specs->{flat_height} * $specs->{final_width} --
#the default can just return 1 and use it as a multiplier, or something to
#that effect.
sub calc {
  my ($self, $log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

	my $prin_sid = get_print_container( $log, $dbh, $pid);

	my %p_specs = eprint::service::get_specifications_pairs($log, $dbh, $pid, $prin_sid,
            qw( s0_laminate s1_laminate flat_width flat_height)
	);

	map {$specs->{$_} = $p_specs{$_}} keys %p_specs;
									  
	my @qtys = (undef, get_quantities($log, $dbh, $pid));

  my ($device, $laminate_price, $material_price, $setup_price ) = calc_price($self, $log, $dbh, $variable, $specs);

	my $run_total = $laminate_price + $material_price;

	my @mats = (
      PQS::model::materials::material_by_strid($specs->{s0_laminate}),
      PQS::model::materials::material_by_strid($specs->{s1_laminate})
    );

	for my $i (1..3) {
    next if !$qtys[$i];
    my $run_price = ($laminate_price * $qtys[$i]);
    my $make_ready = $setup_price;
    callback::call('service_calc_end', $pid, $sid, \$make_ready, \$run_price); $specs->{'txtPrice'.$i} =  sprintf("%.2f", $run_price + $make_ready);

    foreach my $side (0..1) {
      next unless $mats[$side];
      PQS::model::service::set_material_estimate($qtys[$i], undef, $sid, $mats[$side]->{lngindex}, $i);
    }
	}

	my $status = $run_total ? 'calculated' : 'uncalculated';

	return $status;
}

sub calc_price {
    my ($self, $log, $dbh, $variable, $specs) = @_;

    my $squarefeet = $specs->{flat_width} * $specs->{flat_height} / 144;

    my $laminate_price = 0;
    my $setup_price    = 0;
    my $material_price = 0;
    my $device;

    SIDE:
    foreach my $side (@{ $self->specs_splice }) {

        next SIDE if !$specs->{$side};

        my ($hardware, $price, $mat, $setup) = get_service_full_price(
            $log, $dbh, $variable, $self->service_names, $squarefeet,
            $specs->{$side}
        );
	print STDERR "MD: $hardware, $price, $mat, $setup \n";

        #yes, I realise this has a potential for bugs because we could end up
        #with different hardware for each side, but that (technically)
        #shouldn't be possible, since the price for material doesnt change
        #based on equipment.
        $device          = $hardware;
        $laminate_price += ($price - $setup);
        $material_price += $mat;
        $setup_price     = $setup;
    }

    die "Failed fetching laminate price!\n" if $device == -1;

    return wantarray ? ($device, $laminate_price, $material_price,
                        $setup_price                              )
                     : $laminate_price;
}
1;
