use strict;
package openprint::Expense_Rule_Category;
our @ISA = qw( openprint::Object );

use vars qw( $debug %fields %find_fields %transforms %defaults $table $serial );
$debug = 0;
%fields = (
	id			=>	'id',
	name		=>	'name',
);
%find_fields = (
);
$table = 'expense_rule_categories';
$serial = 'expense_rule_categories_id_seq';

1;
__END__
