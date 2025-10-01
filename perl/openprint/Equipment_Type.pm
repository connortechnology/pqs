use strict;
package openprint::Equipment_Type;
our @ISA = qw(openprint::Object);
require openprint::Object;

use vars qw( $debug $table $serial %find_fields %fields %transforms %defaults $cache_field $dropdown_field $default_sort);

$debug = 0;
$table = 'tbl_equipment_type';
$serial = 'tbl_equipment_type_lngindex_seq';
$dropdown_field = 'description';
$default_sort = 'lower(strname)';

%fields = (
	id			    	=>	'lngindex',
	name		    	=> 'strid',
	description		=> 'strname',
);
%find_fields = (
);
%transforms = (
  name => ['s/\W//g'],
);
%defaults = (
);

sub cache_field {
	return 'name';
}
$cache_field = 'name';

sub destroy {
  #my $ac = sql::start_transaction( $openprint::dbh );
	sql::execute( undef, undef, 'DELETE FROM '.$table.' WHERE id=?', $_[0]{id} );
  #sql::end_transaction( $openprint::dbh, $ac );
} # end sub destroy

1;
__END__
