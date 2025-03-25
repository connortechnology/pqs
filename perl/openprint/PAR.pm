use strict;
package openprint::PAR;
our @ISA = qw(openprint::Object);

use openprint ();

require openprint::PAR_Area;
require openprint::PAR_Reason;
require MIME::QuotedPrint;

use vars qw( $debug $table $serial %fields %defaults %transforms );

$debug = 0;

$table = 'par';
$serial = 'par_id_seq';

%fields = (
	'id'					=>	'id',
	'issued_to_id'	=> 'issued_to_id',
	'issued_on'		=> 'issued_on',
	'issued_by_id'	=> 'issued_by_id',
	'reply_by'		=> 'reply_by',
	'problem'		=> 'problem',
	'cause'			=> 'cause',
	'action'		=> 'action',	
	'effectiveness'	=> 'effectiveness',
	'area'			=> 'area',
	'area_id'		=> 'area_id',
	'reason'		=> 'reason',
	'reason_id'		=> 'reason_id',
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
	'deleted'			=> 'deleted',
);

%transforms = (
);
%defaults = (
	'issued_to_id'	=> undef,
	'issued_by_id'	=> undef,
	'part1_user_id'	=> undef,
	'part2_user_id'	=> undef,
	'part3_user_id'	=> undef,
	'part4_user_id'	=> undef,
	'created_on'	=> q`'NOW()'`,
	'updated_on'	=> q`'NOW()'`,
	'deleted'		=> 0,
	'area_id'		=>	undef,
);

sub send_notifications {
	my ( $self ) = @_;

	my @Users = openprint::User->find( company_id=>$openprint::config{owner_id}, type=>['E','A'], 'usergroup any'=>'Quality Control Notifications');

	if ( @Users ) {
		my $From = $openprint::User;

		my %info = ( PAR	=>	$self );
		$info{'ReplacementText'} = ssi::include( '/email_content/iso_par_notification.html', \%info );
		my $body = ssi::include( '/email_template.html', \%info );
		my $Mail = new openprint::Email();
		$Mail->send( 
				FROM	=>	$From,
				TO      => \@Users,
				SUBJECT => 'A new PAR has been generated.',
				ATTACHMENTS	=>	['', MIME::QuotedPrint::encode_qp($body), 'text/html', 'quoted-printable'],
				);
	} # end if to
} # end sub send_notification

sub Area {
	return new openprint::PAR_Area( $_[0]{area_id} );
} # end sub Area
sub Reason {
	return new openprint::PAR_Reason( $_[0]{reason_id} );
} # end sub Reason

1;
__END__
