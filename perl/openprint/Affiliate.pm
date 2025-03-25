use strict;
package openprint::Affiliate;
our @ISA = qw( openprint::Object );
require openprint::Company;

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'affiliates';
$serial = 'affiliates_id_seq';

%fields = (
	'id'			=>	'id',
	'created_on'	=>	'created_on',
	'name'			=>	'name',	
	'url'			=>	'url',
	'image_url'		=>	'image_url',
	'supplier_id'	=>	'supplier_id',
	'title'			=>	'title',
	'sort'			=>	'sort',
);

%defaults = (
	supplier_id	=>	undef,
	created_on	=>	q`'NOW()'`,
	sort		=>	undef,
);

sub Supplier {
	return new openprint::Company( $_[0]{'supplier_id'} );
} # end sub Supplier

1;
__END__
