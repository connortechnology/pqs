use strict;
package openprint::EmailCampaign_Subscription;
our @ISA=qw(openprint::Object);

require openprint::Object;

require openprint::EmailCampaign;
require openprint::User;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 1;
$table = 'emailcampaign_subscriptions';
$serial = 'emailcampaign_subscriptions_id_seq';

%fields = (
		id						=>	'id',
		campaign_id		=>	'campaign_id',
		user_id				=>	'user_id',
);

%defaults = (
);

1;
__END__
