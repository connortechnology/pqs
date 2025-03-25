use strict;
package openprint::UserGroup;
our @ISA = qw(openprint::Object);

require openprint::User;

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults $default_sort );
$debug = 0;

$default_sort = 'lower(name)';
$table = 'usergroups';
$serial= 'usergroups_id_seq';
%fields = (
	id			=>	'id',
	name		=>	'name',
	description	=>	'description',
	duration	=>	'duration',
	asset_id	=>	'asset_id',
);
%find_fields = (
	user_id	=>	'(SELECT user_id FROM users_in_usergroups WHERE usergroup_id=usergroups.id)',
);

%transforms = (
	name		=> [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	description	=> [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
	duration	=>	undef,
	asset_id	=>	undef,
);

sub Users {
	my ( $self, %param ) = @_;
	return () if ! $$self{id};
	if ( %param ) {
		$param{usergroup_id} = $$self{id};
		return openprint::User->find( %param );	
	} elsif ( ! $$self{Users} ) {
		$param{usergroup_id} = $$self{id};
		$$self{Users} = [ openprint::User->find( %param ) ];
	} # end if
	return @{$$self{Users}};
} # end sub Users

1;
__END__
