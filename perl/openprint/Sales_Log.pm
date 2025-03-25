use strict;
package openprint::Sales_Log;
our @ISA = qw( openprint::Object );
use openprint ();
require openprint::Object;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'sales_logs';
$serial = 'sales_logs_id_seq';
%fields = (
	id			=>	'id',
	salesrep_id	=>	'salesrep_id',
	user_id		=>	'user_id',
	company_id	=>	'company_id',
	date_time	=>	'date_time',	
	notes		=>	'notes',
);
%defaults = (
	user_id		=>	undef,
	company_id	=>	undef,
	date_time	=>	"'NOW()'",
	salesrep_id	=>	q`$openprint::session{user_id}`,
);

sub User {
	require openprint::User;
	return new openprint::User( $_[0]{user_id} );
} # end sub User

sub Company {
	return new openprint::Company( $_[0]{company_id} );
} # end sub Company

1;
__END__
