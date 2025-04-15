use strict;
package Configuration;
our @ISA = qw(openprint::Object);
require sql;

use vars qw( $debug $table @identified_by %fields %transforms %defaults @types );
$debug = 0;
$table = 'tbl_configuration';
@identified_by = ( 'name' );

%fields = ( 
	name		=>	'strconfigtitle',
	value		=>	'strconfigdata',
	type		=>	'type',
	category	=>	'category',
	description	=>	'label',
);
%transforms = (
    name => [ 's/\s/_/g' ],
    description => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    category => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    value => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = ();

@types = ( 'Owner', 'Supplier', 'pricelist', 'currency', 'yes/no', 'textarea', 'text','number', 'list','boolean' );

sub categories {
  my $sql = 'SELECT DISTINCT '.$fields{category}.' FROM '.$table.' ORDER BY '.$fields{category};
  return sql::execute(undef,undef, $sql);
}

1;
__END__
