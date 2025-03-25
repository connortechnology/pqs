use strict;
require openprint::Object_Type;
require openprint::Opinion_Type;
package openprint::Opinion;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table %fields %find_fields %transforms %defaults @identified_by );

$debug = 0;
$table = 'opinions';
%fields = (
	'user_id'		=>	'user_id',
	'object_type_id'	=>	'object_type_id',
	'object_type'	=>	undef,
	'object_id'		=>	'object_id',
	'created_on'	=>	'created_on',
	'value'			=>	'value',
	'opinion_type_id'	=>	'opinion_type_id',
);
%find_fields = (
	'object_type'	=>	'(SELECT name FROM object_types WHERE id=object_type_id)',
	'opinion_type'	=>	'(SELECT name FROM opinion_types WHERE id=opinion_type_id)',
);
@identified_by = ( 'user_id', 'object_type_id', 'object_id', 'opinion_type_id' );
%defaults = (
	'created_on'	=>	q`'NOW()'`,
	'value'			=>	undef,
);

sub Object {
	if ( ! $_[0]{'Object'} ) {
#$openprint::log->debug("Opinion: new object ".$_[0]->object_type());
		my $type = $_[0]->object_type();
		if ( ! $type ) {
			$openprint::log->warn("No object_type $type");

		} elsif ( $type->can('new') ) {
			$_[0]{'Object'} = $type->new( $_[0]{'object_id'} );
#$openprint::log->debug("lOpinion: new object type: " . (ref $_[0]{'Object'}) . ' id: ' . $_[0]{'Object'}->id() );
		} else {
			$openprint::log->warn("Unable to create an $_[0]{object_type}");
		} # end if
	} 
	if ( ! $_[0]{'Object'} ) {
		return new openprint::Object();
	} # end if
	return $_[0]{'Object'};
} # end sub Object

sub Opinion_Type {
	return new openprint::Opinion_Type( $_[0]{'value'} );
} # end sub Opinion_Type

1;
__END__
