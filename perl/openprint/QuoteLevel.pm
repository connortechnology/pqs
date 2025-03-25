use strict;
package openprint::QuoteLevel;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'quotelevels';
$serial = 'quotelevels_id_seq';

%fields = ( 
	'id'	=>	'id',
	'name'=>'name',
 );
%transforms = ();
%defaults = ();

1;
__END__
