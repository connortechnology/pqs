use strict;
package openprint::messaging;

use openprint ();
use vars qw( $r %variable %session %param %config $log $dbh );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

require openprint::Message;
require openprint::Message_To;
require openprint::Conversation;

sub history {
	if ( $param{'action'} eq 'Destroy' ) {
		my $Message = new openprint::Message( $param{'message_id'} );
		$variable{'error'} .= $Message->destroy();
	} elsif ( $param{'action'} eq 'Delete' ) {
		my $Message = new openprint::Message( $param{'message_id'} );
		$variable{'error'} .= $Message->destroy();
	} # end if

	if ( ( ! $session{'/messaging/history.html?lastupdated'} ) or ( time - $session{'/messaging/history.html?lastupdated'} ) > ( 12*60*60 ) ) {
		ssi::setup_date_select( '/messaging/history.html', 'created_on_start', '' );
		ssi::setup_date_select( '/messaging/history.html', 'created_on_end', '' );
		ssi::setup_date_select( '/messaging/history.html', 'sent_on_start', -31 );
		ssi::setup_date_select( '/messaging/history.html', 'sent_on_end', '' );
	} # end if
	ssi::save_params( '/messaging/history.html', ( 
				'created_on_start_year','created_on_start_month','created_on_start_day',
				'created_on_end_year','created_on_end_month','created_on_end_day',
				'sent_on_start_year','sent_on_start_month','sent_on_start_day',
				'sent_on_end_year','sent_on_end_month','sent_on_end_day',
				'from_id', 'to_id' ) );
} # end sub history

sub _history {
	if ( ! $param{'action'} ) {
	ssi::save_params( '/messaging/history.html', ( 
				'created_on_start_year','created_on_start_month','created_on_start_day',
				'created_on_end_year','created_on_end_month','created_on_end_day',
				'sent_on_start_year','sent_on_start_month','sent_on_start_day',
				'sent_on_end_year','sent_on_end_month','sent_on_end_day',
				'from_id', 'to_id' ) );
	} # end if
} # end sub _history

sub list {
	my $Message = $variable{'Message'} = new openprint::Message( $param{'message_id'} );
	my $Conversation = $variable{'Conversation'} = new openprint::Conversation( $param{'conversation_id'} );
	if ( sets::isin( $param{'action'}, [ 'Save', 'Send' ] ) ) {
		if ( ! $Conversation->id() ) {
			$variable{error} .= $Conversation->save({ subject=>$param{subject}});
		} # end if
		my $Message = new openprint::Message();
		if ( $param{'action'} eq 'Send' and ! $variable{'error'} ) {
			$Message->sent_on('NOW()');
		} # end if send
		$variable{'error'} .= $Message->save({
			'conversation_id'	=>	$Conversation->id(),
			'body'				=>	$param{'body'},
			});
	} elsif ( $param{'action'} ) {
		$log->error("Invalid value for action $param{action}");
	} else {
		ssi::save_params( '/messaging/list.html', ( 
				'sent_on_start_year','sent_on_start_month','sent_on_start_day',
				'sent_on_end_year','sent_on_end_month','sent_on_end_day',
				'folder',
		) );
	} # end if
	if ( ( ! $session{'/messaging/list.html?lastupdated'} ) or ( time - $session{'/messaging/list.html?lastupdated'} ) > ( 12*60*60 ) ) {
		ssi::setup_date_select( '/messaging/list.html', 'sent_on_start', -31 );
		ssi::setup_date_select( '/messaging/list.html', 'sent_on_end', '' );
	} # end if
} # end sub list

sub _list {
	if ( $param{'action'} eq 'delete' ) {
		my $Conversation = $variable{'Conversation'} = new openprint::Conversation( $param{'conversation_id'} );
		my @message_ids = map { $$_{id} } $Conversation->Messages();
		foreach my $To ( openprint::Message_To->find('message_id'=>\@message_ids, 'user_id'=>$session{'user_id'}) ) {
			$variable{'error'} .= $To->delete();
		} # end foreach To
	} elsif ( ! $param{'action'} ) {
		ssi::save_params( '/messaging/list.html', ( 
				'starting_on_start_year','starting_on_start_month','starting_on_start_day',
				'starting_on_end_year','starting_on_end_month','starting_on_end_day',
				'user_id', 'category_id' ) );
	} # end if
} # end sub _list

sub edit {
	$variable{'Conversation'} = new openprint::Conversation( $param{'conversation_id'} );
	#$variable{'Conversation'}->save() if ! $variable{'Conversation'}->id();
} # end sub edit

sub view {
	my $Conversation = $variable{'Conversation'} = new openprint::Conversation( $param{'conversation_id'} );
	if ( $param{'action'} eq 'Delete' ) {
		my @message_ids = map { $$_{id} } $Conversation->Messages();
		foreach my $To ( openprint::Message_To->find('message_id'=>\@message_ids, 'user_id'=>$session{'user_id'}) ) {
			$variable{'error'} .= $To->delete();
		} # end foreach To
		$variable{'ExternalRedirect'} = '/messaging/list.html' if ! $variable{'error'};
	} elsif ( sets::isin( $param{'action'}, [ 'Save', 'Send' ] ) ) {
		if ( ! ( $param{'body'} or $param{'subject'} ) ) {
			$variable{'error'} .= 'Please enter a subject or message.';
			return;	
		} # end if
		if ( ! $param{'to_id'} ) {
			$variable{'error'} .= 'Please select someone to send the message to.';
			return;
		} # end if

		if ( ! $Conversation->id() ) {
			$variable{error} .= $Conversation->save({ subject=>$param{subject}});
		} # end if
		my $Message = new openprint::Message();
		if ( $param{'action'} eq 'Send' and ! $variable{'error'} ) {
			$Message->sent_on('NOW()');
		} # end if send
		$variable{'error'} .= $Message->save({
			'conversation_id'	=>	$Conversation->id(),
			'from'				=>	$session{user_id},
			'body'				=>	$param{body},
			});
		foreach my $user_id ( ref $param{'to_id'} eq 'ARRAY' ? @{$param{'to_id'}} : ( $param{'to_id'} ) ) {
			next if $user_id == $session{'user_id'};
			my $Message_To = new openprint::Message_To();
			$variable{'error'} .= $Message_To->save({
				message_id	=>	$Message->id(),
				user_id		=>	$user_id,
			});
		} # end foreach user_id in to
		my $Message_To = new openprint::Message_To();
		$variable{error} .= $Message_To->save({
			message_id	=>	$Message->id(),
			user_id		=>	$session{'user_id'},
			viewed		=>	1,
		});
		if ( (! $variable{'error'}) and (!$param{'conversation_id'}) ) {
			$variable{'ExternalRedirect'} = '/messaging/list.html';
		} # end if
	} elsif ( $param{'to_id'} ) {
		my @To = $Conversation->To();
		if ( ! sets::isin( $param{'to_id'}, [ map { $_->user_id() } @To ] ) ) {
			my $New_To = new openprint::Message_To();
			$New_To->user_id( $param{'to_id'} );
			push @To, $New_To;
			$Conversation->To( \@To );
		} # end if
	} # end if
} # end sub view

sub _view {
	my $Message = $variable{'Message'} = new openprint::Message( $param{'message_id'} );
	my $Conversation = $variable{'Conversation'} = new openprint::Conversation( $param{'conversation_id'} );
	if ( $param{'action'} eq 'Delete Message' ) {
		my @To = $Message->To();
		for ( my $to_index = 0; $to_index < @To; $to_index += 1 ) {
			if ( $To[$to_index]{'user_id'} == $session{'user_id'} ) {
				if ( ! ( $variable{'error'} .= $To[$to_index]->delete() ) ) {
					splice @To, $to_index, 1;
					$Message->To( @To );
				} # end if
				last;
			} else {
$log->debug("Delete to but $To[$to_index]{user_id} != $session{user_id}");
			} # end if
		} # end foreach T
	} elsif ( $param{'action'} eq 'reply' ) {
		if ( ! $param{'body'} ) {
			$variable{'error'} .= 'Please enter a message.';
			return;	
		} # end if
		my $Reply = new openprint::Message();
		$variable{'error'} .= $Reply->save({
			'conversation_id'	=>	$Message->conversation_id(),
			'from_id'	=>	$session{'user_id'},
			'reply_to'	=>	$param{'message_id'},
			'body'		=>	$param{'body'},
			'sent_on'	=>	'NOW()',
		});
		foreach my $user_id ( ref $param{'to_id'} eq 'ARRAY' ? @{$param{'to_id'}} : ( $param{'to_id'} ) ) {
			next if $user_id == $session{'user_id'};
			my $Message_To = new openprint::Message_To();
			$variable{'error'} .= $Message_To->save({
				'message_id'	=>	$Reply->id(),
				'user_id'		=>	$user_id,
			});
		} # end foreach user_id in to
		my $Message_To = new openprint::Message_To();
		$variable{'error'} .= $Message_To->save({
				'message_id'	=>	$Reply->id(),
				'user_id'		=>	$session{'user_id'},
				});
	} # end if
} # end sub _view

# to_id is [user_id]_[company_id]
# user-id is optional
sub _to {
	my $Conversation = $variable{'Conversation'} = new openprint::Conversation( $param{'conversation_id'} );
	if ( $param{'action'} eq 'add' ) {
		my @ids = sets::exclude([''], [ sets::union(
			$param{to_id} ? ( ref $param{to_id} eq 'ARRAY' ? @{$param{to_id}} : ( $param{to_id} ) ) : (),
			$param{user_id} ) ] );
		my @user_ids;
$log->debug("Ids: @ids");
		foreach my $to_id ( @ids ) {
			my ( $user_id, $company_id );
			if ( ($user_id,$company_id ) = $to_id =~ /^(\d*)_(\d*)$/ ) {
			} else {
				$user_id = $to_id;
			} # end if

			if ( $user_id ) {
				push @user_ids, $user_id;
			} elsif ( $company_id ) {
				push @user_ids, map { $_->id() } openprint::User->find(company_id=>$company_id);
			} # end if
			#FIXME need to add block list checking
		} # end foreach
$log->debug("Got user_ids @user_ids ");

		my @To = map { my $MTo = new openprint::Message_To(); $$MTo{user_id} = $_; $MTo } @user_ids;
		$Conversation->To( \@To );
	} elsif ( $param{'action'} eq 'remove' ) {
		my @ids = sets::exclude(['', $param{'user_id'} ], [ sets::union(
			$param{'to_id'} ? ( ref $param{'to_id'} eq 'ARRAY' ? @{$param{to_id}} : ( $param{to_id} ) ) : (),
			) ] );

		my @To = map { my $MTo = new openprint::Message_To(); $$MTo{user_id} = $_; $MTo } @ids;
		$Conversation->To( \@To );
	} # end if
} # end sub _to

sub _messages {
	my $Conversation = $variable{'Conversation'} = new openprint::Conversation( $param{'conversation_id'} );
} # end sub _messages

sub _users {
} # end sub _users

1;
__END__
