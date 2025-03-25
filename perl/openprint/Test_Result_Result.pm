use strict;
package openprint::Test_Result_Result;
our @ISA = qw(openprint::Object);

use vars qw( $table $serial %fields %transforms %defaults );
$table = 'test_result_results';
$serial = 'test_result_results_id_seq';

%fields = ( 
	id		=>	'id',
	name	=>	'name',
);
%transforms = (
	name => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = ();

1;
__END__
