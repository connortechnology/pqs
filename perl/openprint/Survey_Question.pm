use strict;
package openprint::Survey_Question;
our @ISA = qw( openprint::Object );

require openprint::Survey_Question_Available_Answer;
require openprint::Survey_Response;

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults );
$debug = 0;
$table = 'survey_questions';
$serial = 'survey_questions_id_seq';

%fields = (
	id				=>	'id',
	text			=>	'text',
	type			=>	'type',
	survey_id		=>	'survey_id',
	category_id		=>	'category_id',
	alignment		=>	'alignment',
	allow_comments	=>	'allow_comments',
	allow_public	=>	'allow_public',
);

%find_fields = (
		user_id	=>	'(SELECT user_id FROM Survey_Responses WHERE question_id=survey_questions.id)',
);

%transforms = (
		text	=> [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
	alignment	=>	1,
	allow_comments	=>	0,
	allow_public	=>	0,
);

sub Available_Answers {
	return () if ! $_[0]{'id'};
	return openprint::Survey_Question_Available_Answer->find(question_id=>$_[0]{id}, order=>'sorting' );
} # end sub Available_Answers

sub delete {
	my $error = '';
	foreach my $AA ( $_[0]->Available_Answers() ) {
		$error .= $AA->delete();
	} # end foreach AA
	return $error if $error;
	foreach my $R ( openprint::Survey_Response->find('question_id'=>$_[0]{'id'}) ) {
		$error .= $R->delete();
	} # end foreach Response
	return $error if $error;
	return $_[0]->SUPER::delete();	
} # end sub delete

sub html {
	my ( $Question, $Response ) = @_;
	if ( ! $Response ) {
		#Load the user's response, if there is one
		if ( $openprint::session{user_id} ) {
			$Response = openprint::Survey_Response->find_one(question_id=>$$Question{id},user_id=>$openprint::session{user_id});
		} # end if
		$Response = new openprint::Survey_Response() if ! $Response;
	} # end if

	my $html;
	$html .= '<li class="Question">';
	$html .= sprintf('<a href="/survey/view.html?survey_id=%1$d">%2$s</a>', $Question->survey_id(), $Question->text() );
	$html .= '<div class="answers">';
	if ( $Question->type() eq 'radio' ) {
		$html .= ssi::radio( 'answer_id-'.$Question->id(),
				[ map { $_->answer_id(), $_->Answer()->text() . ( $Question->alignment() ? '<br/>' : '' ) } $Question->Available_Answers() ],
				$Response->answer_ids(),
				);
	} elsif ( $Question->type() eq 'checkbox' ) {
		$html .= ssi::checkboxes( 'answer_id-'.$Question->id(),
				[ map { $_->answer_id(), $_->Answer()->text() . ( $Question->alignment() ? '<br/>' : '' ) } $Question->Available_Answers() ],
				$Response->answer_ids(),
				);
	} elsif ( $Question->type() eq 'select' ) {
		$html .= sprintf('<select name="answer_id-%1$d" id="answer_id-%1$d">%2$s</select>', $$Question{'id'},
				ssi::make_drop_down( [ map { $_->answer_id(), $_->Answer()->text() } $Question->Available_Answers() ], $Response->answer_ids() ) );
	} # end if
	if ( $$Question{allow_comments} ) {
		$html .= sprintf('<textarea name="answer-%1$d" id="answer-%1$d" placeholder="additional comments"></textarea>', $$Question{id} );
	} # end if
	$html .= '</div>';
	if ( $$Question{allow_public} ) {
		$html .= sprintf('<input type="checkbox" name="public-%1$d" value="1" /> Others can see my response<br/>', $Question->id() );
	} # end if
	if ( ! $openprint::session{user_id} ) {
		$html .= 'You will be asked to login in order to save your answer.';
	} # end if
	$html .= '</li>';
	return $html;
} # end sub html

1;
__END__
