use strict;
require openprint::Object;
require openprint::Host;

package openprint::OUI_Vendor;
our @ISA = qw( openprint::Object );
use vars qw( $debug $table @identified_by %fields %transforms %defaults %types );
$debug = 1;
@identified_by = ( 'oui' );
$table = 'oui_vendors';
%fields = (
	oui		=>	'oui',
	vendor_name		=>	'vendor_name',
);
%transforms = (
	oui		=>	[ 's/[^A-Fa-f0-9]//g' ],
	vendor_name	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);

1;
__END__
