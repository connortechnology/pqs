use strict;
require openprint::Object;
require openprint::User;

package openprint::Blocklist;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table @identified_by %fields %find_fields %defaults %transforms %block_cache );
$debug = 0;
$table = 'blocklist';
@identified_by = ( 'blockee', 'blocker' );

%fields = (
	blockee	=>	'blockee',
	blocker	=>	'blocker',
	reason	=>	'reason',
	unblock	=>	'unblock',
	created_on	=>	'created_on',	
);
%find_fields = (
	user_id	=>	[ 'blockee', 'blocoker' ],
);
%transforms = (
    reason => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
	created_on	=>	q`'NOW()'`,
	unblock		=>	0,
);

sub Blockee {
	return new openprint::User( $_[0]{blockee} );
}
sub Blocker {
	return new openprint::User( $_[0]{blocker} );
}

sub is_blocked {
	my ( $user_id1, $user_id2 ) = @_;
	if ( (! exists $block_cache{$user_id1} ) and $user_id1 ) {
		@{$block_cache{$user_id1}} = map { $_->blockee() } openprint::Blocklist->find(blocker=>$user_id1);
	} # end if
	return 1 if $user_id1 and $user_id2 and sets::isin( $user_id2, $block_cache{$user_id1} );
	if ( ( ! exists $block_cache{$user_id2} ) and $user_id2 ) {
		@{$block_cache{$user_id2}} = map { $_->blockee() } openprint::Blocklist->find(blocker=>$user_id2);
	} # end if
	return 1 if $user_id2 and $user_id1 and sets::isin( $user_id1, $block_cache{$user_id2} );
#$openprint::log->debug("Not blocked " . new openprint::User($user_id1)->name(). ' ' . new openprint::User( $user_id2)->name());
	return 0;
} # end sub is_blocked
1;
__END__
