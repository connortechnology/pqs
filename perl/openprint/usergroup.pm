use strict;
package openprint::usergroup;
require sql;

use vars qw( %cache %groups_cache %groups_by_id );

sub init_cache {
    %cache = ();
    %groups_cache = sql::execute( undef, undef, q{SELECT name, id FROM usergroups} );
		#%groups_by_id = sql::execute( undef, undef, q{SELECT id, name FROM usergroups} );
}


# Similar to Ruby style.... takes an optional hash ref to determine filters
# Currently returns an array of id/name pairs maybe someday should return an array of objects...
sub find {
	my %params = @_;

	return sql::execute( undef, undef, q{SELECT id, name FROM UserGroups ORDER BY lower(name)} );
} # end if

sub exists {
	if ( ! %groups_cache ) {
		%groups_cache = sql::execute( undef, undef, q{SELECT name, id FROM usergroups} );
	} # end if
	return $groups_cache{$_[0]};
} # end sub exists

sub names {
	my( $log, $dbh, @ids ) = @_;

	return if ! @ids;
	return sql::execute( $log, $dbh, "SELECT name FROM usergroups WHERE id IN (".join(',',@ids).")" );
} # end sub names

sub is_user_in {
	my ( $groups, $user_id ) = @_;

	return if ! $user_id;

	if ( ! exists $cache{$user_id} ) {
		@{$cache{$user_id}} = sql::execute( undef, undef, 'SELECT usergroup_id FROM users_in_usergroups WHERE user_id=?', $user_id );
	} # end if
	if ( ! %groups_cache ) {
		%groups_cache = sql::execute( undef, undef, q{SELECT name, id FROM usergroups} );
	} # end if

	# If the groups don't exist, then default to true
	if ( ! @groups_cache{@$groups} ) {
		$openprint::log->debug("Non of the groups @$groups were in the cache");
		return @$groups;
	} # end if
#$openprint::log->debug("Groups for $user_id " . join(',', @{$cache{$user_id}} ) . '=>' . join(',', @groups_by_id{ @{$cache{$user_id}} } ) );
	
	return sets::intersection( @{$cache{$user_id}}, @groups_cache{@$groups} );
} # end if

sub users_in {
	my ( $group_name ) = @_;

	return sql::execute( undef, undef, 'SELECT user_id FROM users_in_usergroups WHERE usergroup_id=?', $groups_cache{$group_name} );

} # sub users_in

1;
__END__
