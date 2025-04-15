use strict;
use warnings;
package openprint::Bug;
our @ISA = qw( openprint::Object );
require openprint::Object;

require openprint::Bug_Comment;
require openprint::Company;
require openprint::User;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'bugs';
$serial = 'bugs_id_seq';
%fields = (
	'id'			=>	'id',
	'description'	=>	'description',
	'owner_id'		=>	'owner_id',
	'project_id'	=>	'project_id',
	'created_on'	=>	'created_on',
	'updated_on'	=>	'updated_on',
	'user_id'		=>	'user_id',
	'status_id'		=>	'status_id',
	'company_id'	=>	'company_id',
	deleted			=>	'deleted',
);
%transforms = (
);
%defaults = (
	deleted			=>	0,
	'created_on'	=>	q`'NOW()'`,
	'updated_on'	=>	q`'NOW()'`,
	'user_id'		=>	q`$session{'user_id'}`,
	'owner_id'		=>	q`$config{'owner_id'}`,
	'company_id'	=>	q`$session{'company_id'}`,
);

sub destroy {
	foreach my $C ( openprint::Bug_Comment->find('bug_id'=>$_[0]{'id'}) ) {
		$C->destroy();
	} # end foreach C
	return $_[0]->SUPER::destroy();
} # end sub destroy

sub url_to {
	return '/openprint/bugs/view.html?bug_id='.$_[0]{id};
} # end sub url_to

sub link_to {
	return sprintf('<a href="/openprint/bugs/view.html?bug_id=%1$d">%2$s</a>', $_[0]{id}, ( $_[1] ? $_[1] : $_[0]{id} ) );
} # end sub link_to

sub Company {
	return new openprint::Company( $_[0]{company_id} );
}
sub User {
	return new openprint::User( $_[0]{user_id} );
}
sub Created_By {
	return new openprint::User( $_[0]{user_id} );
}

1;
__END__
