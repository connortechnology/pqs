use strict;
package openprint::Wall;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'wall';
$serial = 'wall_id_seq';

%fields = (
	id			=>	'id',
	created_on	=>	'created_on',
	user_id		=>	'user_id',
	author_id	=>	'author_id',
	message		=>	'message',
	reply_to	=>	'reply_to',
	has_replies	=>	'has_replies',
);

%defaults = (
	reply_to	=>	undef,
	created_on	=>	q`'NOW()'`,
	user_id		=>	q`$openprint::session{user_id}`,
	has_replies	=>	'0',
);

sub Author {
	return new openprint::User( $_[0]{author_id} );
} # end sub Author

sub can_edit {
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if $openprint::session{user_id} == $_[0]{author_id};
	return 0;
} # end sub can_edit

sub delete {
	my $error;
	my $ac = sql::start_transaction( $openprint::dbh );
	foreach ( openprint::Wall->find(reply_to=>$_[0]{id}) ) {
		$error .= $_->delete();
		last if $error;
	} # end foreach
	$error .= $_[0]->SUPER::delete() if ! $error;
	sql::end_transaction( $openprint::dbh, $ac );
	return $error;
} # end sub delete

1;
__END__
