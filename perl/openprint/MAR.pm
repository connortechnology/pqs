use strict;
require openprint::Email;
require openprint::usergroup;

package openprint::MAR;
our @ISA = qw(openprint::Object);

use vars qw( %config $log %session );
*session = \%openprint::session;
*config = \%openprint::config;
*log = \$openprint::log;

use vars qw( $debug $table $serial %fields %defaults %transforms );

$debug = 0;
$table = 'mars';
$serial = 'mars_id_seq';
%fields = (
	'id'			=>	'id',
	'issued_to_id'	=> 'issued_to_id',
	'issued_on'		=> 'issued_on',
	'issued_by_id'	=> 'issued_by_id',
	'reply_by'		=> 'reply_by',
	'problem'		=> 'problem',
	'cause'			=> 'cause',
	'action'		=> 'action',	
	'effectiveness'	=> 'effectiveness',
	'equipment_id'		=> 'equipment_id',
	'part1_user_id'	=> 'part1_user_id',
	'part1_signed_on'	=> 'part1_signed_on',
	'part2_user_id'		=> 'part2_user_id',
	'part2_signed_on'	=> 'part2_signed_on',
	'part3_user_id'		=> 'part3_user_id',
	'part3_signed_on'	=> 'part3_signed_on',
	'part4_user_id'		=> 'part4_user_id',
	'part4_signed_on'	=> 'part4_signed_on',
	'created_on'		=> 'created_on',
	'updated_on'		=> 'updated_on',
	deleted			=> 'deleted',
);

%transforms = (
);
%defaults = (
	issued_to_id	=> undef,
	issued_by_id	=> undef,
	part1_user_id	=> undef,
	part2_user_id	=> undef,
	part3_user_id	=> undef,
	part4_user_id	=> undef,
	created_on	=> q`'NOW()'`,
	updated_on	=> q`'NOW()'`,
	deleted		=> 0,
	equipment_id	=>	undef,
);

sub send_notifications {
	my ( $self ) = @_;

	my @Users = openprint::User->find( type=>['E','A'], 'usergroup any'=>'Quality Control Notifications');

	if ( @Users ) {
		my $email_template = ssi::slurp_content( '/email_template.html' );
		my %info = (
			MAR	=>	$self,
		);
		$info{ReplacementText} = ssi::include('/email_content/iso_mar_notification.html', \%info );
		my $Email = new openprint::Email();
		$Email->send(
				FROM    => new openprint::User( $session{'user_id'} ),
				TO      => \@Users,
				SUBJECT => 'A new CAR has been generated requiring your attention.',
				ATTACHMENTS => [ '', MIME::QuotedPrint::encode_qp( ssi::variable_substitution( \$email_template, \%info ) ), 'text/html', 'quoted-printable' ],
				);

	} # end if to

} # end sub send_notification

sub send_assignee_notification {
	my ($self) = @_;

	my $From = new openprint::User( $session{'user_id'} );
	my $To = new openprint::User( $$self{'issued_to_id'} );
	if ( $To->id() == $session{'user_id'} ) {
		$log->debug("Not Sending MAR Notifications becuase I am ME to " . $To->email());
	} else {
		my $email_template = ssi::slurp_content( '/email_template.html' );
		my %info = (
				MAR	=>	$self,
				To	=>  $To,
				From	=>  $From,
				);
		$info{ReplacementText} = ssi::include('/email_content/iso_mar_assignee_notification.html', \%info );
		my $Email = new openprint::Email();
		$Email->send(
				FROM    => $From,
				TO      => $To,
				SUBJECT => 'NEW MAR',
				ATTACHMENTS => [ '', MIME::QuotedPrint::encode_qp( ssi::variable_substitution( \$email_template, \%info ) ), 'text/html', 'quoted-printable' ],
				);
	} # end if
} # end sub send_assignee_notification

sub send_changed_notification {
    my ($self) = @_;

    my $From = new openprint::User( $session{'user_id'} );
	my $email_template = misc::load_file( $log, $config{'SkinPath'}.'/email_template.html' );
	my %info = (
			'MAR'   =>  $self,
			'From'  =>  $From,
			);
	$info{ReplacementText} = ssi::include('/email_content/iso_mar_changed_notification.html', \%info );
	my $Email = new openprint::Email();
	$Email->send(
			FROM    => $From,
			TO      => [ new openprint::User( $$self{'issued_by_id'} ), openprint::User->find( 'type'=>['E','A'], 'usergroup any'=>['Quality Control Notifications']) ],
			SUBJECT => 'MAR ' . $$self{id} . ' has been changed.',
			ATTACHMENTS => ['', MIME::QuotedPrint::encode_qp( ssi::variable_substitution( \$email_template, \%info ) ), 'text/html', 'quoted-printable' ],
			);

} # end sub send_part2

sub Equipment {
	return new openprint::Equipment( $_[0]{equipment_id} );
} 
sub issued_to {
	return new openprint::User( $_[0]{issued_to_id} );
} # end sub issued_to

sub can_edit {
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if $openprint::session{user_id} == $_[0]{issued_by_id};
	return 1 if openprint::usergroup::is_user_in( ['Quality Control'], $openprint::session{user_id} );
	return 0;
} # end sub can_edit

1;
__END__
