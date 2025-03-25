use strict;
package openprint::Object_Specification;
our @ISA = qw( openprint::Object );
use vars qw( $debug $table %fields %find_fields %transforms %defaults $serial );

$debug = 0;
$serial = 'object_specifications_id_seq';
$table = 'object_specifications';

%fields = (
		id				=>	'id',
		object_id		=>	'object_id',
		object_type_id	=>	'object_type_id',
		name			=>	'name',
		value			=>	'value',
		object_type		=>	undef,
		Object			=>	undef,
		Object_Type		=>	undef,
);
%find_fields = (
		object_type	=>	'(SELECT name FROM object_types WHERE id=object_type_id)',
);
%transforms = (
		name  => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
		value => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g','s/[^[:ascii:]]//g' ],
);

%defaults = (
);

sub save_changes {
	my ( $Object, $input ) = @_;
	my @specs_changes;
	foreach my $Spec ( $Object->Specifications() ) {
		my %spec_changes = map { exists $$input{"spec_$_-$$Spec{id}"} ? ( $_ => $$input{"spec_$_-$$Spec{id}"} ) : () } ( 'name', 'value' ) ;
		my @spec_changes = $Spec->changes( \%spec_changes ) if %spec_changes;
		if ( @spec_changes ) {
			$Spec->save( \%spec_changes );
			push @specs_changes, @spec_changes;
		} # end if
	} # end foreach
} # end sub
1;
__END__
