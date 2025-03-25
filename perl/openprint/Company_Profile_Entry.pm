use strict;
package openprint::Company_Profile_Entry;
our @ISA = qw( openprint::Object );

use vars qw( $table @identified_by %fields %transforms %defaults $debug );
$debug = 0;

$table = 'company_profiles';
@identified_by = ( 'company_id', 'field_id' );
%fields = (
	company_id	=>	'company_id',
	field_id	=>	'field_id',
	value		=>	'value',
);
%defaults = (
	required	=>	0,
);

sub Field {
    if ( @_ > 1 ) {
        $_[0]{Field} = $_[1];
    } # end if
    if ( ! $_[0]{Field} ) {
        $_[0]{Field} = new openprint::Company_Profile_Field( $_[0]{field_id} );
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
