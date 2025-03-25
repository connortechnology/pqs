use strict;
package openprint::EmailCampaign_Sent;
our @ISA=qw(openprint::Object);

require openprint::Object;

require openprint::EmailCampaign;
require openprint::User;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'emailcampaign_sent';
$serial = 'emailcampaign_sent_id_seq';

%fields = (
		id						=>	'id',
		campaign_id		=>	'campaign_id',
		user_id				=>	'user_id',
		emailsenton		=>	'emailsenton',
		numemailsent	=>	'numemailsent',
		markedfordeletion	=>	'markedfordeletion',
		last_read     =>	'last_read',
);

%defaults = (
		emailsenton	=>	undef,
		markedfordeletion	=> 	q`'N'`,
		last_read		=>	undef,
);

1;
__END__
