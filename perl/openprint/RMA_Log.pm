use strict;
package openprint::RMA_Log;
our @ISA = qw(openprint::Object);
require openprint::User;
require openprint::Company;

use vars qw( $debug $table %fields %transforms %defaults @identified_by );

$debug = 0;
$table = 'rma_logs';
@identified_by = ( 'rma_id', 'created_on' );
%fields = (
	rma_id		=>	'rma_id',
	company_id	=>	'company_id',
	user_id		=>	'user_id',
	created_on	=>	'created_on',
	description	=>	'description',
);
%transforms = (
    description => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
	user_id		=>	undef,
	company_id	=>	undef,
	created_on	=>	q`'NOW()'`,
);

sub User {
	return new openprint::User( $_[0]{user_id} );
} # end sub User
sub Company {
	return new openprint::Company( $_[0]{company_id} );
} # end sub Company

1;
__END__
