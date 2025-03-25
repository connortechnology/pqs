use strict;
package openprint::Equipment_Operator;
require openprint::User;
require openprint::Equipment;

our @ISA = qw(openprint::Object);

use vars qw( $debug $table %fields %transforms %defaults @identified_by );
$debug = 0;
$table = 'equipment_operators';
@identified_by = ( 'user_id','equipment_id' );
%fields = (
	equipment_id	=>	'equipment_id',
	user_id			=>	'user_id',
);
%transforms = (
);
%defaults = (
);

sub Operator {
	return new openprint::User( $_[0]{user_id} );
}
sub Equipment {
	return new openprint::Equipment( $_[0]{operator_id} );
}

1;
__END__
