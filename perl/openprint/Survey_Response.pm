use strict;
package openprint::Survey_Response;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table %fields %transforms %defaults $serial @identified_by );
$debug = 0;
#$serial = 'survey_responses_id_seq';
$table = 'survey_responses';
@identified_by = ( 'question_id', 'user_id' );

%fields = (
		'survey_id'		=>	'survey_id',
		'company_id'	=>	'company_id',
		'user_id'		=>	'user_id',
		'question_id'	=>	'question_id',
		'answer'		=>	'answer',
		'answer_ids'		=>	'answer_ids',
		'created_on'	=>	'created_on',
);

%defaults = (
	created_on	=>	q`'NOW()'`,
	answer_ids	=>	undef,
	company_id	=>	undef,
	survey_id	=>	undef,
	answer		=>	undef,
);

sub Answers {
	return map { $_ ? new openprint::Survey_Answer( $_ ) : () } ( $_[0]{answer_ids} ? @{$_[0]{answer_ids}} : () );
} # end sub Answers

1;
__END__
