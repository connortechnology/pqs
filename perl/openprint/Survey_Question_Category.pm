use strict;
package openprint::Survey_Question_Category;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'survey_question_categories';
$serial = 'survey_question_categories_id_seq';

%fields = (
	'id'		=>	'id',
	'name'		=>	'name',
);

%transforms = (
    'name' => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);

1;
__END__
