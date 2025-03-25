use strict;
package openprint::EmailCampaign_Destination;
our @ISA=qw(openprint::Object);

require openprint::Object;

require openprint::EmailCampaign;
require openprint::User;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'emailcampaign_destination';
$serial = 'emailcampaign_destination_id_seq';

%fields = (
		id						=>	'id',
		campaign_id		=>	'campaign_id',
		user_id				=>	'user_id',
);

%defaults = (
);

1;
__END__
