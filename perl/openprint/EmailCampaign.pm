use strict;
package openprint::EmailCampaign;
our @ISA=qw(openprint::Object);

require openprint::Object;
require Email::Valid;
require openprint;

require sql;
require openprint::Email;
require openprint::Log;
require openprint::EmailTemplate;
require openprint::User;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'emailcampaigns';
$serial = 'emailcampaigns_id_seq';

%fields = (
		id	=>	'id',
		name	=>	'name',
		query	=>	'query',
		interval	=>	'interval',
		active	=>	'active',
		runnable	=>	'runnable',
		timestosend	=>	'timestosend',
		timeofday		=>	'timeofday',
		email_subject	=>	'email_subject',
		email_from	=>	'email_from',
		email_to		=>	'email_to',
		email_cc		=>	'email_cc',
		email_bcc		=>	'email_bcc',
		email_text	=>	'email_text',
		email_html	=>	'email_html',
		attachments	=>	'attachments',
		lastrun		=>	'lastrun',
		nextrun		=>	'nextrun',
		created_on	=>	'created_on',
		updated_on	=>	'updated_on',
		template_id	=>	'template_id',
		deleted			=>	'deleted',
		user_id				=>	'user_id',
		recipients_per_run	=>	'recipients_per_run',
	mailinglist		=>	'mailinglist',
);

%defaults = (
		lastrun	=>	undef,
		nextrun	=>	undef,
		interval	=> q`'00:00:00'`,
		timeofday	=> undef,
		created_on	=> q`'NOW()'`,
		updated_on	=> q`'NOW()'`,
		timestosend	=>	undef,
		template_id	=>	undef,
		deleted			=>	0,
		user_id			=>	undef,
		runnable		=> 0,
		recipients_per_run	=>	undef,
		mailinglist	=>	1,
);
%transforms = (
		email_text					=>	[ 's/^\s+//', 's/\s+$//' ],
		email_html					=>	[ 's/^\s+//', 's/\s+$//' ],
);

sub destroy {
	my $self = shift;
	my $ac = sql::start_transaction( $openprint::dbh );
	sql::execute( undef, undef, q{DELETE FROM EmailCampaign_Log WHERE campaign_id=?},$self->{id} );
	sql::execute( undef, undef, q{DELETE FROM EmailCampaign_Sent WHERE campaign_id=?},$self->{id} );
	sql::execute( undef, undef, q{DELETE FROM EmailCampaigns WHERE id=?}, $self->{id} );
	sql::end_transaction( $openprint::dbh, $ac );
	
	new openprint::Log()->save({action=>'Delete Email Campaign', note=>'Campaign ID: ' . $self->{id} . ' Campaign Name: '  . $self->{name}, Object=>$self});
} # end sub delete

sub send_admin_email {
	my ($log, $dbh, $replacements) = @_;

	# Load the email template
	#my $email_template = misc::load_file( $log, $config{SkinPath} . '/email_template.html' );
	my $email_template = <<__ADMIN_EMAIL__;
Dear Sales Rep.
You need to delete this account because they have not responded to many
automatic emails.

Account User Name: <?FIRSTNAME?> <?LASTNAME?>
Email address: <?EMAIL_ADDRESS?>
Company: <?COMPANY_NAME?>
Users Rep: <?REPNAME?>

__ADMIN_EMAIL__

	$email_template = ssi::variable_substitution( \$email_template, $replacements );

	# Setup the mail message
	my $Email = new openprint::Email();
	$Email->send(
			FROM => sprintf("\"%s\" <%s>", @$replacements{'REPNAME','REPEMAIL'} ),
			#TO => sprintf("\"%s\" <%s>", @$replacements{'REPNAME','REPEMAIL'} ),
			TO => 'iconnor@connortechnology.com',
			SUBJECT => 'Automatically Generated Account Deletion Email',
			HTML_BODY => $email_template,
		);
} # end sub send_admin_email

sub send_email {
	my ($self, $replacements) = @_;

	# Setup the mail message
	my $Email = new openprint::Email();
	$$replacements{Email} = $Email;

	# Do the appropriate variable substitutions
	# - The first substitution replaces the 'ReplacementText' field
	# - The seconds substitution replaces the any tags that were
	#   inserted by the first replacement
	# NB. Only encode_qp ONCE
	my $html_body = '';
	my $text_body = '';

	if ( $$self{email_html} ) {
		# Load the email template
		my $email_template = '';
		if ( $$self{template_id} ) {
			my $EmailTemplate = $self->Template();
			$email_template = $EmailTemplate->body();
		} else {
			$email_template = ssi::slurp_content('/email_template.html');
		} # end if

		$$replacements{ReplacementText} = ssi::variable_substitution(\$$self{email_html}, $replacements);
		$html_body = ssi::variable_substitution(\$email_template, $replacements) if $$replacements{ReplacementText};
	}
	$text_body = ssi::variable_substitution(\$$self{email_text}, $replacements) if $$self{email_text};

	my @attachments = $self->{attachments} ? (eval $self->{attachments}) : ();
	$openprint::log->warn('Eval error Reason: '.$@) if $@;

	my $results = $Email->send(
			FROM	=> $self->{email_from} ? $self->{email_from} : sprintf('"%s" <%s>', @$replacements{'REPNAME','REPEMAIL'} ),
			TO		=> ( $$self{email_to} ? $$self{email_to} : $$replacements{User} ),
#BCC => 'iconnor@point-one.com',
			( $$self{email_cc} ? ( CC=>$$self{email_cc} ) : () ),
			( $$self{email_bcc} ? ( BCC=>$$self{email_bcc} ) : () ),
			SUBJECT => $$self{email_subject},
			( $text_body ? ( BODY => $text_body ) : () ),
			( $html_body ? ( HTML_BODY => $html_body ) : () ),
			( @attachments ? ( ATTACHMENTS =>	\@attachments ) : () ),
		);
		
	if ( $$replacements{User} and $$replacements{User}->id() ) {
		sql::insert(undef, undef, 'EmailCampaign_Sent', 
				campaign_id =>	$self->{id},
				emailsenton	=>	'NOW()',
				numemailsent=> 1,
				user_id	=>	$$replacements{User}->id(),
				);
	}
	sql::insert(undef, undef, 'EmailCampaign_Log', 
			campaign_id =>	$self->{id},
			Log=>			$results,
			time=>				'NOW()',
			);
} # end sub send_email

sub send {
	my $self = shift;

	my $results = '';

	my %replacements;
	$replacements{Campaign} = $self;

	# Find the email and company name for all accounts that match
	# this campaign
	my $query = $self->{query};
	if ( $$self{timestosend} ) {
		$query .= " AND (
( NOT EXISTS (SELECT numemailsent FROM EmailCampaign_Sent WHERE campaign_id=$$self{id} AND EmailCampaign_Sent.user_id=users.id))
 OR
( (SELECT MAX(numemailsent) FROM EmailCampaign_Sent WHERE campaign_id=$$self{id} AND EmailCampaign_Sent.user_id=users.id) < $$self{timestosend}) )";
	}
	if ( $$self{recipients_per_run} ) {
		$query .= ' LIMIT ' . int($$self{recipients_per_run});
	}
	# We aren't filtering by timeofday.  Manual runs should ignore it, we filter by it in email_scheduler.pl

	$openprint::log->debug("SQL query $query");
	my @mail_user_ids = sql::execute(undef, undef, $query);
	$results .= 'There are '.(scalar @mail_user_ids)." users that fit the campaign<br/>\n";

	if ( $$self{timeofday} ) {
		@$self{nextrun} = sql::execute(undef, undef,
				"SELECT date(NOW()+interval) + '$$self{timeofday}'::time FROM emailcampaigns WHERE id=?", $$self{id}) if $$self{interval};
	} else {
		@$self{nextrun} = sql::execute(undef, undef,
				'SELECT NOW()+interval FROM emailcampaigns WHERE id=?', $$self{id}) if $$self{interval};
	}

	#$self->{log}->info("There are ". scalar @mail_user_ids." users that fit the campaign<br/>\n");

	# for each userid, prepare an email to send if the following
	# conditions are met
	#
	#	1) This is the first time an email is being sent for this
	#		campaign to this user
	#
	#	OR
	#
	# 	2.1) The interval specififed in emailcampaign.dtminterval
	# 	 	 has elapsed since the last email was sent
	# 	 	 (emailcampaignsent.dtmemailsenton)
	#
	# 	AND
	#
	# 	2.2) The number of emails sent to this user fot this campaign
	# 		 has not exceeded the specified number for the campaign
	# 		 (emailcampaign.lngnumtimestosend < 
	# 		 	emailcapaignsent.lngnumtiemssent)
	#
	# If 2.1 and 2.2 are not met, send an email to an administrator
	# flagging the account for removal.
	#
	# If an email is sent, update the row in emailcampaigsent for this
	# campaign/user, or add one as necessary
	#
	my $email_text = $$self{email_text};
	my $email_html = $$self{email_html};

	foreach my $user_id ( @mail_user_ids ) {
		my $User = $replacements{User} = new openprint::User($user_id);

		# do we need to send this email?

		my ( $interval_expired, $last_sent_on, $num_email_sent );
# First check if a sent row exists
    $_ = 'SELECT (NOW() - emailsenton) > ?, emailsenton, numemailsent FROM EmailCampaign_Sent WHERE campaign_id=? AND user_id=?';
		if ( ( $interval_expired, $last_sent_on, $num_email_sent ) = sql::execute( undef, undef, $_, @$self{'interval','id'}, $user_id ) ) {

# Check if the duration has elapsed 
			if ( !$interval_expired ) {
				$results .= sprintf('Not Sending Email to: %s %s at %s, already sent on %s<br/>',
						$replacements{User}->get('firstname','lastname','email'), $last_sent_on);
				next;
			}
# Check if we have sent this too many times
			if ( $num_email_sent and $self->{timestosend} and ( $num_email_sent >= $self->{timestosend} ) ) {
				$results .= sprintf('Not Sending Email to: %s %s at %s, have already<br/>',
						$replacements{User}->get('firstname','lastname','email') );
				next;
			} # if $num_email_sent > num_times to send
		}

		if ( $$self{mailinglist} and $User->mailinglist() and ($User->mailinglist() eq 'N') ) {
			$results .= sprintf(
					'<span class="error">NOT Sending Email to: %s at %s : they have chosen to not receive email.</span><br/>',
					$replacements{User}->link_to(), $replacements{User}->email()
					);
			next;
		} # end if

		my $addr = Email::Valid->address($replacements{User}->email());

		if ( ( !$addr ) or ( $addr ne $replacements{User}->email() ) ) {
			$results .= sprintf(
					'<span class="error">NOT Sending Email to: %s at %s : the email address appears to be invalid.</span><br/>',
					$replacements{User}->link_to(), $replacements{User}->email()
					);
			$User->save({email_valid=>0});
			next;
		} # end if

		$$self{email_text} = ssi::variable_substitution(\$$self{email_text}, \%replacements) if $$self{email_text};
		$$self{email_html} = ssi::variable_substitution(\$$self{email_html}, \%replacements) if $$self{email_html};
		if ( ! ( $$self{email_text} or $$self{email_html} ) ) {
			$results .= sprintf(
					'<span class="error">NOT Sending Email to: %s %s at %s : No body.</span><br/>%s<br/>',
					$User->get('firstname','lastname','email'), ($@ ? $@ : '')
					);
			next;
		} # end if
		$results .= sprintf('Sending Email to: %s at %s<br/>', $replacements{User}->get('link_to','email'));
		$self->send_email(\%replacements);
	} # for all mail user ids

  #Restore values
	$$self{email_text} = $email_text;
	$$self{email_html} = $email_html;

	$self->{lastrun} = 'NOW()';
	$self->save();

	(new openprint::Log())->save({
			Object	=>	$self,
			note		=>	$results,
			action	=>	'Email Campaign Run',
			});


	if ( $$self{user_id} ) {
# Load the email template
#my $email_template = misc::load_file( $log, $config{SkinPath} . '/email_template.html' );
		my $email_template = '

			Dear <?echo($$variable{Campaign}->Owner()->firstname())?>,</br>
			<br/>
			Your email campaign called <?echo($$variable{Campaign}->name())?> has recently run and the results are as follows:<br/><br/>
			<?echo($$variable{Results})?>

			';

		$email_template = ssi::variable_substitution( \$email_template, { Campaign=>$self, Results=>($results?$results:'') } );

# Setup the mail message
		my $Email = new openprint::Email();
		$Email->send(
				FROM => ($openprint::User->id() ? $openprint::User : $$self{email_from}),
				TO => $self->Owner(),
				#BCC => 'iconnor@connortechnology.com',
				SUBJECT => 'Email Campaign Results for '.$self->name(),
				HTML_BODY => $email_template,
				);
	}
	return $results;
} # end sub send

sub recipients {
	my ( $self ) = @_;
	return sql::execute( undef, undef, $$self{query});
} # end sub recipients

sub Recipients {
	my ( $self ) = @_;
	return map { $_->email_valid() ? $_ : () } openprint::User->find( id=>[ sql::execute( undef, undef, $$self{query} ) ] );
} # end sub recipients

sub test {
	my ( $self ) = @_;
	my %replacements;
# do we need to send this email?
	$replacements{Campaign} = $self;
	$replacements{User} = $openprint::User;
	$$self{email_text} = ssi::variable_substitution( \$$self{email_text}, \%replacements ) if $$self{email_text};
	$$self{email_html} = ssi::variable_substitution( \$$self{email_html}, \%replacements ) if $$self{email_html};
	if ( ! ( $$self{email_text} or $$self{email_html} ) ) {
		return 'No body.  Not sending<br/>';
	} # end if

	my $addr = Email::Valid->address($replacements{User}->email());
	if ( ( ! $addr ) or ( $addr ne $replacements{User}->email() ) ) {
		return sprintf('<span class="error">NOT Sending Email to: %s %s at %s because the email address appears to be invalid.</span><br/>', $replacements{User}->get('firstname','lastname','email') );
	} else {
		$self->send_email(\%replacements);
		return sprintf('Sending Email to: %s %s at %s<br/>',
				$replacements{User}->get('firstname','lastname','email'));
	} # end if email is valid
} # end sub test

sub trial {
	my ( $self ) = @_;

	my $results = '';

	# Find the email and company name for all accounts that match
	# this campaign
	my @mail_user_ids = sql::execute($openprint::log, $openprint::dbh, $self->{query});

	$results .= 'There are '.@mail_user_ids.' users that fit the campaign<br/>';
	my %replacements;
	my $body = $self->{email_text};
	foreach my $user_id ( @mail_user_ids ) {
# de we need to send this email?
		$replacements{User} = new openprint::User($user_id);
		$replacements{ReplacementText} = ssi::variable_substitution(\$body, \%replacements);
		if ( !$replacements{ReplacementText} ) {
			$results .= 'No body. Not sending<br/>';
			next;
		} # end if

		my ( $interval_expired, $num_email_sent );

# First check if a sent row exists
		$_ = 'SELECT (NOW() - emailsenton) > ?, numemailsent FROM EmailCampaign_Sent WHERE campaign_id=? AND user_id=?';
		if ( ( $interval_expired, $num_email_sent ) = sql::execute( undef, undef, $_, @$self{'interval','id'}, $user_id ) ) {

# Check if the duration has elapsed	
			if ( ($interval_expired == 1) ) {

# Check if we have sent this too many times
				if ($num_email_sent < $self->{timestosend}) {
					$results .= sprintf('Sending Email to: %s %s at %s<br/>', $replacements{User}->get('firstname','lastname','email') );
				} # if $num_email_sent > num_times to send
			} # if interval expired
		} else {
# No record of sent email, we need to send the first one
			$results .= sprintf('Sending Email to: %s %s at %s<br/>', $replacements{User}->get('firstname','lastname','email') );
		} # if row exists

	} # for all mail user ids
	return $results;
} # end sub trial

sub Template {
	return new openprint::EmailTemplate($_[0]->template_id());
} # end sub Template

sub url_to {
	return '/marketing/email_campaign.html?campaign_id='.$_[0]{id};
}
sub link_to {
  return sprintf('<a href="/marketing/email_campaign.html?campaign_id=%d">%s</a>', $_[0]{id}, $_[0]{name});
}

sub can_view {
	if ( $openprint::session{user_type} eq 'A' ) {
		$openprint::log->debug('Can view because admin');
		return 1 ;
	}
	if ( ! $_[0]{user_id} ) {
		$openprint::log->debug('Can view because no user_id assigned');
		return 1;
	}
	if ( $openprint::session{user_id} == $_[0]{user_id} ) {
		$openprint::log->debug('Can view because user_Id matches');
		return 1;
	}
	if ( !$_[0]{id} ) {
		$openprint::log->debug('Can view because no Id');
		return 1;
	}
	return 0;
}

sub Owner {
	return new openprint::User($_[0]{user_id});
}

1;
__END__
