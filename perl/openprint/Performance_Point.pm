use strict;
require openprint::Equipment;
use openprint ();

package openprint::Performance_Point_Type;
our @ISA = qw( openprint::Object );
use vars qw( $table $serial %fields %transforms %defaults );
$table = 'performance_point_types';
$serial = 'performance_point_types_id_seq';
%fields = (
	'id'	=>	'id',
	'name'	=>	'name',
	'category'	=>	'category',
);

sub delete {
	my $error;
	my $ac = sql::start_transaction( $openprint::dbh );
	foreach my $Point ( openprint::Performance_Point->find('type_id'=>$_[0]{'id'}) ) {
		last if $error .= $Point->delete();
	} # end foreach Point
	$error .=  $_[0]->SUPER::delete() if ! $error;
	sql::end_transaction( $openprint::dbh, $ac );
	return $error;
} # end sub delete

package openprint::Performance_Point;
our @ISA = qw( openprint::Object );

use vars qw( $table $serial %fields %transforms %defaults @identified_by );

$table = 'performance_points';
$serial = 'performance_points_id_seq';

@identified_by = ('type_id','equipment_id');

%fields = (
	'type_id'		=>	'type_id',
	'type'			=>	undef,
	'units'			=>	'units',
	'equipment_id'	=>	'equipment_id',
	'value'			=>	'value',
	'max_value'		=>	'max_value',
);

%defaults = (
	'value'		=>	undef,
	'max_value'		=>	undef,
	'type_id'	=>	undef,
);

%transforms = (
);

sub Type {
	return new openprint::Performance_Point_Type( $_[0]{'type_id'} );
} # end sub Type

sub Equipment {
	return new openprint::Equipment( $_[0]{'equipment_id'} );
} # end sub Equipment

1;
__END__
