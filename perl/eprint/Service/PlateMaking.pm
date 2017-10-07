package eprint::Service::PlateMaking;
use strict;
use warnings;
no warnings qw(uninitialized);

use eprint::service   qw(:common);
use eprint::equipment ();
use eprint::print     ();

# A function that is smart enough to return true if the project needs plates, and false if it doesn't.
sub necessary {
	my ($log, $dbh, $pid) = @_;
	
    foreach my $sig ( eprint::project::get_signature_indices( $log, $dbh, $pid ) ) {
		my ( $press ) = eprint::service::get_specifications( $log, $dbh, undef, $sig, 'hdnPress' );
		my $plate_type = eprint::equipment::get_specification( $log, $dbh, 'Plate Type', '', $press );
		if ( $plate_type eq 'Conventional' || $plate_type eq 'CTP' || $plate_type eq 'DI') {
			# If we have any Conventional Plates, then we need plates. Simple.
			return 1;
		}
	}
	return 0; #we are using a nonplate press such as a Xerox machine - also for screen printing
}

# The pricing is currently all done during printing.
sub calc { 
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

	foreach my $sig ( eprint::project::get_signature_indices( $log, $dbh, $pid ) ) {
		my ($qty, $material_id, $signature_quantity) = 
			get_specifications( $log, $dbh, undef, $sig, 
                qw( txtPlateQuantity hdnPlateMaterialID txtSignatureQuantity ));

		$qty *= $signature_quantity if $signature_quantity > 1;

		$specs->{"txtPlateQuantity-$sig"} = $qty;
		$specs->{"ddmPlateType-$sig"}     = $material_id;
		
	}

	return 'calculated'; 
}

1;
