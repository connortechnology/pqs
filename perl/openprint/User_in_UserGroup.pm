use strict;
package openprint::User_in_UserGroup;
our @ISA = qw(openprint::Object);

require openprint::User;
require openprint::UserGroup;

use vars qw( $debug $table @identified_by %fields %find_fields %transforms %defaults );
$debug = 0;

$table = 'users_in_usergroups';
@identified_by = ('user_id', 'usergroup_id');
%fields = (
	'user_id'		=>	'user_id',
	'usergroup_id'		=>	'usergroup_id',
);

%transforms = (
);
%defaults = (
	'user_id'	=>	undef,
	'usergroup_id'	=>	undef,
);

1;
__END__
