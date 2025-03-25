use strict;
package openprint::Promo_Code;
our @ISA = qw( openprint::Object );

use vars qw( $table %fields %transforms %defaults @identified_by );
$table = 'promo_codes';
@identified_by = ('code');
%fields = (
	'code'	=>	'code',
	'name'	=>	'name',
	'effect'	=>	'effect',
);
%transforms = (
	'code'	=>	[ 's/[^A-Za-z0-9]//g' ],
    'name' => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    'effect' => [ 's/^\s+//', 's/\s+$//' ],
);
%defaults = (
);

1;
__END__
