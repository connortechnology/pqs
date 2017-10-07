package eprint::Service::Doming;
use strict;
use warnings;

use base qw( eprint::print_service_base );
use POSIX           qw(floor ceil);

use eprint::service qw( get_service_full_price :specs );
use eprint::project qw( get_print_container get_quantities  );
use ssi             qw( make_drop_down material_drop_down);

sub display {
	my ($self, $log, $dbh, $service_type, $pid, $sid, $specs) = @_;
    return;
}

sub new {
    my ($class) = @_;

    my $self = {
        service_names => {
        	action    => 'Doming',
        	service   => 'Doming',
        	makeready => 'DomingMakeReady',
        	mincharge => 'DomingMinimumCharge',
		}
    };

    bless $self, $class;

    return $self;
}

sub calc {
    my ($self, $log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

	my %p_specs = eprint::service::get_specifications_pairs(
			$log, $dbh, $pid, get_print_container( $log, $dbh, $pid),
            qw(flat_width flat_height)
	);

	my @qtys = (undef, get_quantities($log, $dbh, $pid));

	for my $i (1..3) {

		$qtys[$i] = $specs->{"txtQuantity$i"} if $specs->{"txtQuantity$i"};

		next unless $qtys[$i];

    		my $units = $p_specs{flat_height} * $p_specs{flat_width} * $qtys[$i];

    		my ($device, $service_price, $mat, $setup) = get_service_full_price(
        		$log, $dbh, $variable, $self->service_names, $units, undef
    		);

    		die "Failed fetching mounting price.\n" if $device == -1;

		$specs->{'txtPrice'.$i}     =  sprintf("%.2f", $service_price);
		$specs->{'txtUnitPrice'.$i} =  sprintf("%.2f", $specs->{'txtPrice'.$i}/ $qtys[$i]);

	}

    return 'calculated';
}

1;
