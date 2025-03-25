use strict;
require sql;
require openprint::CAR_Area;
require openprint::CAR_Reason;
require openprint::Email;
require openprint::usergroup;

package openprint::CAR;
our @ISA = qw(openprint::Object);

use vars qw( %config $log %session );
*session = \%openprint::session;
*config = \%openprint::config;
*log = \$openprint::log;

use vars qw( $debug $table $serial %fields %defaults %transforms );

$debug = 0;
$table = 'car';
$serial = 'car_id_seq';
%fields = (
	'id'			=>	'id',
	'issued_to_id'	=> 'issued_to_id',
	'issued_on'		=> 'issued_on',
	'issued_by_id'	=> 'issued_by_id',
	'reply_by'		=> 'reply_by',
	'docket'		=> 'docket',
	'company_id'	=> 'company_id',
	'problem'		=> 'problem',
	'cause'			=> 'cause',
	'action'		=> 'action',	
	'effectiveness'	=> 'effectiveness',
	'area_id'		=> 'area_id',
	'reason_id'		=> 'reason_id',
	'presses'		=> 'presses',
	'part1_user_id'	=> 'part1_user_id',
	'part1_signed_on'	=> 'part1_signed_on',
	'part2_user_id'		=> 'part2_user_id',
	'part2_signed_on'	=> 'part2_signed_on',
	'part3_user_id'		=> 'part3_user_id',
	'part3_signed_on'	=> 'part3_signed_on',
	'part4_user_id'		=> 'part4_user_id',
	'part4_signed_on'	=> 'part4_signed_on',
	'reprint'			=> 'reprint',
	'reprint_approval'	=> 'reprint_approval',
	'artwork'			=> 'artwork',
	'reprint_on'		=> 'reprint_on',
	'reprint_charge'	=> 'reprint_charge',
	'approved_by_id'	=> 'approved_by_id',
	'created_on'		=> 'created_on',
	'approved_on'		=> 'approved_on',
	'updated_on'		=> 'updated_on',
	'printed_on'		=> 'printed_on',
	'identified_by'		=> 'identified_by',
	'deleted'			=> 'deleted',
	'reprint_quantity'	=>	'reprint_quantity',
	'reprint_value'		=>	'reprint_value',
);

%transforms = (
	'reprint_quantity'	=>	[ 's/[^\d\.]//g' ],
	'reprint_value'		=>	[ 's/[^\d\.]//g' ],
	'docket'			=>	[ 's/[\D]//g' ],
);
%defaults = (
	'issued_to_id'	=> undef,
	'issued_by_id'	=> undef,
	'docket'		=> undef,
	'company_id'	=> undef,
	'part1_user_id'	=> undef,
	'part2_user_id'	=> undef,
	'part3_user_id'	=> undef,
	'part4_user_id'	=> undef,
	'approved_by_id'	=> undef,
	'created_on'	=> q`'NOW()'`,
	'updated_on'	=> q`'NOW()'`,
	'approved_on'	=> undef,
	'printed_on'	=> undef,
	'deleted'		=> 0,
	'reprint'		=> undef,
	'area_id'		=> undef,
	'reason_id'		=> undef,
	'reprint_quantity'	=>	undef,
	'reprint_value'	=>	undef,
);

sub send_notifications {
	my ( $self ) = @_;

	my @Users = openprint::User->find(type=>['E','A'], 'usergroup any'=>'Quality Control Notifications',
			'id NOT IN'=>[$openprint::User->id(), $$self{issued_to_id}],
			);

	if ( @Users ) {
		my $email_template = misc::load_file($log, $config{SkinPath}.'/email_template.html');
		my %info = (
			CAR	=>	$self,
		);
		$info{ReplacementText} = ssi::include('/email_content/iso_car_notification.html', \%info);
		my $Email = new openprint::Email();
		$Email->html_body(ssi::variable_substitution(\$email_template, \%info));
		my $results = $Email->send(
				FROM    => $openprint::User,
				TO      => \@Users,
				SUBJECT => 'A new CAR has been generated requiring your attention.',
				);
		(new openprint::Log())->save({
				Object	=>	$self,
				action 	=> 'Notification',
				note		=>	$results,
				});
	} # end if to
} # end sub send_notification

sub send_assignee_notification {
	my $self = shift;

	my $From = new openprint::User( $session{user_id} );
	my $To = new openprint::User( $$self{issued_to_id} );
	if ( $To->id() == $session{user_id} ) {
		$log->debug('Not Sending CAR Notifications becuase I am ME to ' . $To->email());
		return;
	} 
	my $email_template = misc::load_file($log, $config{SkinPath}.'/email_template.html');
	my %info = (
			CAR	=>	$self,
			To    =>  $To,
			From  =>  $From,
			);
	$info{ReplacementText} = ssi::include('/email_content/iso_car_assignee_notification.html', \%info);
	my $Email = new openprint::Email();
	$Email->html_body(ssi::variable_substitution(\$email_template, \%info));
	my $results = $Email->send(
			FROM    => $From,
			TO      => $To,
			SUBJECT => 'NEW CAR',
			);
	(new openprint::Log())->save({
			Object	=>	$self,
			action 	=> 'Notification',
			note		=>	$results,
			});
} # end sub send_assignee_notification

sub send_reprint_request_notification {
	my ($self) = @_;
	my $From = $openprint::User;

	my $email_template = misc::load_file( $log, $config{SkinPath}.'/email_template.html' );
	my %info = (
			CAR   =>  $self,
			From  =>  $From,
			);
	$info{ReplacementText} = ssi::include('/email_content/iso_car_reprint_request.html', \%info );

	my @Users = openprint::User->find( type=>['E','A'], 'usergroup any'=>'Reprint Approvals', 'id !='=>$openprint::User->id());
	if ( @Users ) {
		my $Email = new openprint::Email();
		$Email->html_body(ssi::variable_substitution(\$email_template, \%info));
		my $results = $Email->send(
				FROM    => $From,
				TO      => \@Users, 
				SUBJECT => 'CAR Reprint Request',
				);
		(new openprint::Log())->save({
				Object=>$self,
				action => 'Notification',
				note=>	$results,
				});
	}
} # end sub send_reprint_request_notification

sub send_reprint_approval_notification {
	my ($self) = @_;

	my $From = $openprint::User;
	my $To = new openprint::User( $$self{issued_by_id} );
	if ( $To->id() == $session{user_id} ) {
		$log->debug('Not Sending Reprint Approval because I am ME to ' . $To->email());
		return;
	}
	my $email_template = misc::load_file( $log, $config{SkinPath}.'/email_template.html' );
	my %info = (
			CAR   =>  $self,
			To    =>  $To,
			From  =>  $From,
			);
	$info{ReplacementText} = ssi::include('/email_content/iso_car_reprint_approval.html', \%info );
	my $Email = new openprint::Email();
	$Email->html_body(ssi::variable_substitution(\$email_template, \%info));
	my $results = $Email->send(
			FROM    => $From,
			TO      => $To,
			SUBJECT => 'Reprint ' . ($$self{reprint_approval} eq 'Yes' ? 'approved' : 'not approved' ) . ' for CAR ' . $$self{id},
			);
	(new openprint::Log())->save({
			Object	=>	$self,
			action 	=>	'Notification',
			note		=>	$results,
			});
} # end sub send_reprint_approval_notification

sub send_changed_notification {
	my ($self) = @_;

	my $From = $openprint::User;

	my %To = map { ($$_{id} != $$openprint::User{id}) ? ($$_{id} => $_) : () } (
			new openprint::User($$self{issued_by_id}),
			openprint::User->find(type=>['E','A'], 'usergroup any'=>['Quality Control Notifications'])
			);
	my @To = values %To;
	if ( @To ) {
		my $email_template = misc::load_file( $log, $config{SkinPath}.'/email_template.html' );
		my %info = (
				CAR   =>  $self,
				From  =>  $From,
				);
		$info{ReplacementText} = ssi::include('/email_content/iso_car_changed_notification.html', \%info);
		my $Email = new openprint::Email();
$Email->html_body(ssi::variable_substitution( \$email_template, \%info ));
		my $results = $Email->send(
				FROM    => $From,
				TO      => \@To,
				SUBJECT => 'CAR ' . $$self{id} . ' has been changed.',
				);
		(new openprint::Log())->save({
				Object	=>	$self,
				action 	=> 	'Notification',
				note		=>	$results,
				});
	} # end if To
} # end sub send_changed_notification

sub Area {
	return new openprint::CAR_Area( $_[0]{area_id} );
} # end sub Area

sub Reason {
	return new openprint::CAR_Reason( $_[0]{reason_id} );
} # end sub Reason

sub issued_to {
	return new openprint::User( $_[0]{issued_to_id} );
} # end sub issued_to

sub can_edit {
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if $openprint::session{user_id} == $_[0]{issued_by_id};
	return 1 if openprint::usergroup::is_user_in( ['Reprint Approvals','Quality Control'], $openprint::session{user_id} );
	return 0;
} # end sub can_edit

1;
__END__
