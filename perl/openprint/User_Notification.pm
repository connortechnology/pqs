use strict;
require openprint::Object;
package openprint::User_Notification_Type;
our @ISA = qw(openprint::Object);
use vars qw( $debug $table $serial %fields %defaults %transforms );
$debug = 0;
$table = 'user_notification_types';
$serial = 'user_notification_types_id_seq';
%fields = (
	id		=>	'id',
	name	=>	'name',
	sort	=>	'sort',
);

package openprint::User_Notification;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %find_fields %defaults %transforms );
$debug = 1;
$table = 'user_notifications';
$serial = 'user_notifications_id_seq';

%fields = (
	id			=>	'id',
	company_id	=>	'company_id',
	user_id		=>	'user_id',
	type_id		=>	'type_id',
	value		=>	'value',
);
%find_fields = (
	type		=>	'(SELECT name from user_notification_types WHERE id=type_id)',
	user_company_id  =>  '(SELECT company_id FROM Users WHERE users.id=user_notifications.user_id)',
);
%defaults = (
	company_id	=>	undef,
);

sub User {
	require openprint::User;
	return new openprint::User( $_[0]{user_id} );
}
sub Company {
	require openprint::Company;
	return new openprint::Company( $_[0]{company_id} );
}
sub type {
	if ( @_ > 1 ) {
		my $Type = openprint::User_Notification_Type->find_one('name lc'=>lc $_[1]);
		if ( ! $Type->id() ) {
			$Type->save('name'=>$_[1]);
		} # end if
		$_[0]{'type_id'} = $Type;
		return $Type->name();
	} # end if
	return new openprint::User_Notification_Type( $_[0]{'type_id'} );
} # end sub type
1;
__END__
