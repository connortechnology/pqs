use strict;
package openprint::Survey_Answer;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'survey_answers';
$serial = 'survey_answers_id_seq';

%fields = (
	'id'		=>	'id',
	'text'		=>	'text',
	'sorting'	=>	'sorting',
);

%transforms = (
    'text' => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);

1;
__END__
