use strict;
package openprint::User_in_Marketing_Category;
our @ISA = qw(openprint::Object);

require openprint::User;
require openprint::MarketingCategory;

use vars qw( $debug $table @identified_by %fields %find_fields %transforms %defaults );
$debug = 0;

$table = 'users_in_marketing_categories';
@identified_by = ('user_id', 'category_id');
%fields = (
	user_id		=>	'user_id',
	category_id		=>	'category_id',
);

%transforms = (
);
%defaults = (
	user_id		=>	undef,
	category_id	=>	undef,
);

1;
__END__
