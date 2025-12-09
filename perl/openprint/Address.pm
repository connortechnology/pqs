use strict;
package openprint::Address;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'tbl_addresses';
$serial = 'addresses_id_seq';

%fields = (
	id			=>	'lngindex',
	location_id	=>	'location_id',
	company_id	=>	'company_id',
	user_id		=>	'user_id',
	created_on	=>	'created_on',
	name		=>	'name',
	notes		=>	'notes',
);

%transforms = (
	id			=>	[ 's/\D//g' ],
	location_id	=>	[ 's/\D//g' ],
	company_id	=>	[ 's/\D//g' ],
	user_id		=>	[ 's/\D//g' ],
    name		=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    notes		=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);

%defaults = (
	user_id		=>	undef,
	created_on	=>	q`'NOW()'`,
);

sub Location {
	require openprint::Location;
	return new openprint::Location( $_[0]{location_id} );
} # end sub Location

sub to_string {
	return $_[0]{name} . $_[0]->Location()->address_line();
} # end 

1;
__END__
