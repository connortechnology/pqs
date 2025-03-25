use strict;
package openprint::Survey_Question_Available_Answer;
our @ISA = qw( openprint::Object );

require openprint::Survey_Answer;

use vars qw( $debug $table %fields %transforms %defaults @identified_by );
$debug = 0;
$table = 'survey_question_available_answers';
#$serial = 'survey_question_available_answers_id_seq';
@identified_by = ( 'question_id','answer_id' );
%fields = (
	'question_id'	=>	'question_id',
	'answer_id'	=>	'answer_id',
	'sorting'	=>	'sorting',
);

%transforms = (
	'sorting'	=>	[	's/\D//g' ],
);

%defaults = (
	'sorting'	=>	q`undef`,
);

sub Answer {
	return new openprint::Survey_Answer( $_[0]{answer_id} );
} # end sub Answer

1;
__END__
