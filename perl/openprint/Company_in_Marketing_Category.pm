use strict;
package openprint::Company_in_Marketing_Category;
our @ISA = qw(openprint::Object);

require openprint::Company;
require openprint::MarketingCategory;

use vars qw( $debug $table @identified_by %fields %find_fields %transforms %defaults );
$debug = 0;

$table = 'companies_in_marketing_categories';
@identified_by = ('company_id', 'category_id');
%fields = (
	company_id		=>	'company_id',
	category_id		=>	'category_id',
);

%transforms = (
);
%defaults = (
	company_id	=>	undef,
	category_id	=>	undef,
);

1;
__END__
