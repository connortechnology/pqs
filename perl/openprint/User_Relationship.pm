use strict;
require openprint::Object;
require openprint::User;
package openprint::User_Relationship_Type;
our @ISA = qw(openprint::Object);
use vars qw( $debug $table $serial %fields %defaults %transforms );
$debug = 0;
$table = 'user_relationship_types';
$serial = 'user_relationship_types_id_seq';
%fields = (
	id		=>	'id',
	name	=>	'name',
	text1	=>	'text1',
	text2	=>	'text2',
	text3	=>	'text3',
	sort	=>	'sort',
);
%defaults = (
	sort	=>	undef,
);

package openprint::User_Relationship;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table @identified_by %fields %find_fields %defaults %transforms );
$debug = 0;
$table = 'user_relationships';
@identified_by = ( 'user_id1', 'type_id', 'user_id2' );

%fields = (
	user_id1	=>	'user_id1',
	user_id2	=>	'user_id2',
	type_id	=>	'type_id',
	approved	=>	'approved',
);
%find_fields = (
	type	=>	'(SELECT name from user_relationship_types WHERE id=type_id)',
	user_id	=>	[ 'user_id1', 'user_id2' ],
);
%defaults = (
	approved	=>	0,
);

sub User {
	return new openprint::User( $_[0]{'user_id1'} );
}
sub User1 {
	return new openprint::User( $_[0]{'user_id1'} );
}
sub User2 {
	return new openprint::User( $_[0]{'user_id2'} );
}
sub type {
	if ( @_ > 1 ) {
		my $Type = openprint::User_Relationship_Type->find_one('name lc'=>lc $_[1]);
		if ( ! $Type->id() ) {
			$Type->save( name=>$_[1]);
		} # end if
		$_[0]{type_id} = $Type;
		return $Type->name();
	} # end if
	return new openprint::User_Relationship_Type( $_[0]{type_id} )->name();
} # end sub type

sub Type {
	return new openprint::User_Relationship_Type( $_[0]{type_id} );
} # end sub Type

sub html {
} # end sub html
1;
__END__
