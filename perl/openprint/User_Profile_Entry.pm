use strict;
require openprint::User_Profile_Field;
package openprint::User_Profile_Entry;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table @identified_by %fields %transforms %defaults );
$debug = 0;
$table = 'user_profiles';
@identified_by = ( 'user_id', 'field_id' );
%fields = (
	user_id 	=>	'user_id',
	field_id	=>	'field_id',
	value		  =>	'value',
);
%transforms = (
	value => [ 's/^\s+//', 's/\s+$//', 's/\s\s+$/ /g' ],
);
%defaults = (
);

sub Field {
	if ( @_ > 1 ) {
		$_[0]{Field} = $_[1];
	} # end if
	if ( ! $_[0]{Field} ) {
		$_[0]{Field} = new openprint::User_Profile_Field( $_[0]{field_id} );
	} # end if
	return $_[0]{Field};
} # end sub Field

sub field {
	return $_[0]->Field()->name();
} # end sub field

sub html {
	return $_[0]->Field()->html( $_[0]{value} );
} # end sub html

1;
__END__
