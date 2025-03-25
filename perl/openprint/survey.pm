# Copyright (C) 2007 Isaac Connor <isaac@connortechnology.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA

use strict;
use openprint ();
package openprint::survey;

require openprint::Survey;
require openprint::Survey_Question;
require openprint::Survey_Question_Category;
require openprint::Survey_Answer;
require openprint::Survey_Response;

use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

sub view {
$log->debug("In survey view");
	$param{'survey_id'} =~ s/\D//g;
    my $Survey = $variable{'Survey'} = new openprint::Survey( $param{'survey_id'} );
    if ( $param{'btnFunction'} eq 'Save' ) {
        $variable{'error'} = $Survey->save( \%param );
    } elsif ( $param{'action'} eq 'delete' ) {
        $variable{'error'} = $Survey->delete( );
		if ( ! $variable{'error'} ) {
			$variable{'ExternalRedirect'} = '/survey/history.html';
			%param = ();
		} # end if
    } elsif ( $param{'action'} eq 'submit' ) {
		my %Responses = map { $_->question_id(), $_ } openprint::Survey_Response->find('survey_id'=>$Survey->id(),'user_id'=>$session{'user_id'});
		foreach my $Question ( $Survey->Questions() ) {
			my $Response = $Responses{$$Question{id}};
			$Response = new openprint::Survey_Response() if ! $Response;
			if ( 
					( ( ref $param{'answer_id-'.$Question->id()} eq 'ARRAY' ) and ( $Response->answer_id() ne join(',',@{$param{'answer_id-'.$$Question{'id'}}}) ) ) or
					( ( ref $param{'answer_id-'.$Question->id()} ne 'ARRAY' ) and ( $Response->answer_id() != $param{'answer_id-'.$$Question{'id'}} ) ) or
					( $Response->answer() ne $param{'answer-'.$$Question{'id'}} ) 
			   ) {

				$variable{'error'} .= $Response->save({
						'company_id'	=>	$session{'company_id'},
						'user_id'		=>	$session{'user_id'},
						'survey_id'		=>	$$Survey{'id'},
						'question_id'	=>	$$Question{'id'},
						'answer_ids'	=>	(ref $param{'answer_id-'.$Question->id()} eq 'ARRAY' ? $param{'answer_id-'.$Question->id()} : [ $param{'answer_id-'.$Question->id()} ] ),
						'answer'		=>	$param{'answer-'.$Question->id()},
						});
			} # end nif answer has changed
		} # end foreach Question
		if ( ! $variable{'error'} ) {
			$variable{'ExternalRedirect'} = '/survey/history.html';
			%param = ();
		} # end if
    } # end if
} # end sub view


sub edit {
	$param{'survey_id'} =~ s/\D//g;
	my $Survey = $variable{'Survey'} = new openprint::Survey( $param{'survey_id'} );
	if ( $param{'action'} eq 'Copy' ) {
		$variable{'Survey'} = $variable{'Survey'}->copy();
		$variable{'error'} = $variable{'Survey'}->save( );
	} elsif ( $param{'action'} eq 'Save' ) {
		$variable{'error'} = $variable{'Survey'}->save( \%param );
		foreach my $Question ( $Survey->Questions() ) {
			$variable{'error'} .= $Question->save({
					'text'		=>	$param{'text-'.$Question->id()},
					'type'		=>	$param{'type-'.$Question->id()},
					'alignment'	=>	$param{'alignment-'.$Question->id()},
					});
		} # end foreach Question
	} elsif ( $param{'action'} eq 'Delete' ) {
		$variable{'error'} .= $Survey->delete();
		if ( ! $variable{'error'} ) {
			$variable{'ExternalRedirect'} = '/survey/history.html';
			$variable{'information'} .= 'Survey successfully deleted.';
			%param = ();
		} # end if
	} # end if
} # end sub edit

sub responses {
    if ( $param{'btnFunction'} eq 'Delete' ) {
		my $Response = openprint::Survey_Response->find_one(
				'survey_id'=>$param{'survey_id'},
				'user_id'=>$param{'user_id'}
				);
		$Response->delete();
    } # end if
} # end sub responses

sub history {
	_history();
	ssi::setup_date_select( '/survey/history.html', 'created_on_start', '' );
	ssi::setup_date_select( '/survey/history.html', 'created_on_end', '' );
} # end sub history
sub _history {
	ssi::save_params( '/survey/history.html', ( 
		( map { 'created_on_start_'.$_ } ( 'year','month','day' ) ),
		( map { 'created_on_end_'.$_ } ( 'year','month','day' ) ),
		) );
} # end sub _history

sub _questions_edit {
	$param{'survey_id'} =~ s/\D//g;
	$variable{'Survey'} = new openprint::Survey( $param{'survey_id'} );
	if ( $param{'action'} eq 'delete' ) {
		my $Question = openprint::Survey_Question->find_one('id'=>$param{'question_id'} );
		if ( $Question ) {
			$variable{'error'} .= $Question->delete();
		} else {
			$log->error("attempt to delete unfound question $param{question_id}");
		} # end if
	} # end if
} # end sub _questions_edit

sub _question_edit_line {
	$param{'survey_id'} =~ s/\D//g;
	$variable{'Survey'} = new openprint::Survey( $param{'survey_id'} );
	if ( $param{'action'} eq 'new' ) {
		my $Question = $variable{'Question'} = new openprint::Survey_Question();
		$variable{'error'} .= $Question->save({
			'survey_id'	=>	$param{'survey_id'},	
			});
	} elsif ( $param{'action'} eq 'sort' ) {
		my $order = $param{'order'};
		$order =~ s/Questions\[\]=//g;
		my @Order = split '&', $order;
		foreach my $i ( 0 .. @Order ) {
			my $Q = openprint::Survey_Question->find_one('question_id'=>$Order[$i]);
			$variable{'error'} .= $Q->save({'sorting'=>$i}) if $Q;
		} # end foreach
	} # en dif
} # end sub _question_edit_line

sub _answers_edit {
	$param{'question_id'} =~ s/\D//g;
	my $Question = $variable{'Question'} = new openprint::Survey_Question( $param{'question_id'} );
	if ( $param{'action'} eq 'delete' ) {
		$param{'answer_id'} =~ s/\D//g;
		my $Answer = openprint::Survey_Question_Available_Answer->find_one('answer_id'=>$param{'answer_id'}, 'question_id'=>$$Question{'id'});
		if ( $Answer ) {
		$variable{'error'} .= $Answer->delete();
		} else {
		$variable{'error'} .= 'Answer not found.';
		} # end if
	} elsif ( $param{'action'} eq 'add' ) {
		my $Answer = openprint::Survey_Answer->find_one('text'=>openprint::Survey_Answer->transform('text', $param{'text'} ) );
		if ( ! $Answer ) {
			$Answer = new openprint::Survey_Answer();
			$variable{'error'} .= $Answer->save({
					'question_id'	=>	$param{'question_id'},
					'text'			=>	$param{'text'},
					});
		} # end if
		my $AA = new openprint::Survey_Question_Available_Answer();
			$variable{'error'} .= $AA->save({
					'question_id'	=>	$param{'question_id'},
					'answer_id'		=>	$$Answer{'id'},
					});
	} elsif ( $param{'action'} eq 'sort' ) {
		my $order = $param{'order'};
		$order =~ s/answers-(\d+)\[\]=//g;
		my $question_id = $1;
		my @Order = split '&', $order;
		foreach my $i ( 0 .. @Order ) {
			my $A = openprint::Survey_Question_Available_Answer->find_one('question_id'=>$question_id, 'answer_id'=>$Order[$i]);
			$variable{'error'} .= $A->save({'sorting'=>$i}) if $A;
		} # end foreach
		my $Question = $variable{'Question'} = new openprint::Survey_Question( $question_id );
	} # end if
} # end sub _answers_edit

sub questions {
} # end sub questions

sub _comments {
	my $Survey = $variable{'Survey'} = openprint::Survey->find_one( 'id'=>$param{'survey_id'} );
	if ( ! $Survey ) {
		$variable{'error'} .= 'Survey not found.';
		return;
	} # end if
	if ( $param{'text'} =~ /\S/ ) {
		if ( ! openprint::Comment->find_one(
			'user_id'	=>	$session{'user_id'},
			'text'		=>	$param{'text'},
			'object_id'	=>	$Survey->id(),
			'object_type'	=>	ref $Survey,
			) ) {

			my $approved = 0;
			if ( $session{'user_type'} eq 'A' or $session{'user_id'} == $Survey->created_by() ) {
				$approved = 1;
			} # endif

			$variable{'error'} .= new openprint::Comment()->save({
					'text'			=>	$param{'text'},
					'object_type'	=>	ref $Survey,
					'object_id'		=>	$Survey->id(),
					'approved'		=>	$approved,
					});
		} # end if comment already exists
	} elsif ( $param{'action'} eq 'approve' ) {
		my $Comment = openprint::Comment->find_one('object_id'=>$$Survey{'id'}, 'object_type'=>ref $Survey, 'id'=>$param{'comment_id'} );
		if ( $Comment ) {
			if ( $Comment->can_approve() ) {
				$Comment->save({'approved'=>1});
			} else {
				$variable{'error'} .= 'You do not have rights to approve that comment.';
$log->error("Attempt to approve a comment without rights");
			} # end if
		} else {
			$variable{'error'} .= 'Comment not found.';
		} # end if
	} elsif ( $param{'action'} eq 'remove' ) {
		my $Comment = openprint::Comment->find_one('object_id'=>$$Survey{'id'}, 'object_type'=>ref $Survey, 'id'=>$param{'comment_id'} );
		if ( $Comment ) {
			if ( $Comment->can_delete() ) {
				$variable{'error'} .= $Comment->delete();
			} else {
				$variable{'error'} .= 'You do not have rights to delete that comment.';
$log->error("Attempt to delete a comment without rights");
			} # end if
		} else {
			$variable{'error'} .= 'Comment not found or you do not have rights to delete.';
		} # end if
	} # end if
} # end sub _comments
sub _latest_survey_question {
	my $Question = new openprint::Survey_Question($param{question_id});
	if ( ! $$Question{id} ) {
		$variable{error} .= "Invalid question id ($param{question_id})<br/>";
		return;
	} # end if
	if ( $_ = openprint::Survey_Response->find_one(question_id=>$param{question_id}, user_id=>$session{user_id}) ) {
		$variable{error} .= $_->destroy();
		$variable{warning} .= 'You already answered that question, replacing the old answer with your new one.<br/>';
	} # end if
	
	my $Response = new openprint::Survey_Response();
	$variable{error} .= $Response->save({
		question_id	=>	$$Question{id},
		company_id	=>	$session{company_id},
		user_id		=>	$session{user_id},
		answer_ids	=>	( ref $param{"answer_id-$param{question_id}"} eq 'ARRAY' ? $param{"answer_id-$param{question_id}"} : [ $param{"answer_id-$param{question_id}"} ] ),
		answer		=>	$param{answer},
		survey_id	=>	$$Question{survey_id},
	});
} # end sub _latest_survey
sub answer_question {
	_latest_survey_question();
} # end sub answer_question

1;
__END__
