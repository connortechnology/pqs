use strict;
require openprint::Material;
require openprint::Service;
package openprint::Ink;
our @ISA = qw( openprint::Object );

use openprint ();

use vars qw( $table $debug $serial %fields %transforms %defaults );
$debug = 0;

$table = 'inks';
$serial = 'inks_id_seq';

%fields = (
	id			=>	'id',
	pmsid		=>	'pmsid',
	name		=>	'name',
	service_id	=>	'service_id',
	mix_service_id	=>	'mix_service_id',
	material_id	=>	'material_id',
	washups		=>	'washups',
	grades		=>	'grades',
	mix			=>	'mix',
);

%defaults = (
	mix			=>	0,
	washups		=>	undef,
	mix_service_id	=>	undef,
	service_id	=>	undef,
	material_id	=>	undef,
	grades		=>	undef,
);

%transforms = (
	washups	=> [ 's/\D//g' ],
);

sub Material {
	if ( ! $_[0]{Material} ) {
		$_[0]{Material} = new openprint::Material( $_[0]{material_id} );
	}
	return $_[0]{Material};
} # end sub Material
sub Service {
	if ( ! $_[0]{Service} ) {
		$_[0]{Service} = new openprint::Service( $_[0]{service_id} );
	} # end if
	return $_[0]{Service};	
} # end sub Service
sub Mix_Service {
	if ( ! $_[0]{Mix_Service} ) {
		$_[0]{Mix_Service} = new openprint::Service( $_[0]{mix_service_id} );
	} # end if
	return $_[0]{Mix_Service};	
} # end sub Mix_Service

# Provides cached coverage lookup
sub Coverage {
	my ( $self, $Press, $grade ) = @_;
	$$self{Coverages} = {} if ! $$self{Coverages};
	$$self{Coverages}{$$Press{id}} = {} if ! $$self{Coverages};
	if ( ! $$self{Coverages}{$$Press{id}}{$grade} ) {
		$$self{Coverages}{$$Press{id}}{$grade} = $self->Material()->New_Specification('Coverage', { range=>$grade, equipment_id=>$$Press{id}} );
	}
	return $$self{Coverages}{$$Press{id}}{$grade};
}


1;
__END__
