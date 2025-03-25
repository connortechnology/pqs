use strict;
use openprint ();
require openprint::Object_Type;
package openprint::Authorization;
our @ISA = qw(openprint::Object);
use vars qw( $debug $table $serial %fields %find_fields %defaults %transforms );

$debug = 0;
$table = 'authorizations';
$serial = 'authorizations_id_seq';
%fields = (
	id				=>	'id',
	object_type_id	=>	'object_type_id',
	object_type		=>	undef,
	object_id		=>	'object_id',
	mode			=>	'mode',
	usergroup_id	=>	'usergroup_id',# an array of group_id
	usertype_id		=>	'usertype_id',# an array of usertype _ids
	user_id			=>	'user_id', # an array
	setting			=>	'setting',
);
%find_fields = (
	object_type			=>	'(SELECT name FROM object_types WHERE id=object_type_id)',
	usergroup_id		=>	q`undef`,
	user_id				=>	q`undef`,
	usertype_id			=>	q`undef`,
);
%defaults = (
	object_type_id	=>	undef,
	object_id		=>	undef,
);

sub Object {
	return $_[0]->object_type()->new( $_[0]{object_id} );
} # end sub Object

sub user_id {
	my $self = shift;
	if ( @_ > 1 ) {
		# passing in an array
		$$self{user_id} = [@_];
	} elsif ( @_ == 1 ) {
		if ( ref $_[0] eq 'ARRAY' ) {
			$$self{user_id} = @{$_[0]} ? $_[0] : undef;
		} else {
			$$self{user_id} = $_[0] ? [ $_[0] ] : undef;
		} # end if
	} # end if
	if ( ! $$self{user_id} ) {
		$$self{user_id} = [];
	} 
	return $$self{user_id};
}

sub usergroup_id {
	my $self = shift;
	if ( @_ > 1 ) {
		# passing in an array
		$$self{'usergroup_id'} = [@_];
	} elsif ( @_ == 1 ) {
		if ( ref $_[0] eq 'ARRAY' ) {
			$$self{'usergroup_id'} = @{$_[0]} ? $_[0] : undef;
		} else {
			$$self{'usergroup_id'} = $_[0] ? [ $_[0] ] : undef;
		} # end if
	} # end if
	return $$self{'usergroup_id'} ? $$self{'usergroup_id'} : [];
}

sub usertype_id {
	my $self = shift;
	if ( @_ > 1 ) {
		# passing in an array
		$$self{usertype_id} = [@_];
	} elsif ( @_ == 1 ) {
		if ( ref $_[0] eq 'ARRAY' ) {
			$$self{usertype_id} = @{$_[0]} ? $_[0] : undef;
		} else {
			$$self{usertype_id} = $_[0] ? [ $_[0] ] : undef;
		} # end if
	} # end if
	return $$self{usertype_id} ? $$self{usertype_id} : [];
} # end sub usertype_id

sub can_do {
$openprint::log->debug("Authorizations Object: " . $_[0]->to_string() ) if $debug;
	my $user_id = $_[1] ? $_[1] : $openprint::session{user_id};
	my $User = new openprint::User( $user_id );
	return 1 if $$User{type} eq 'A';
$openprint::log->debug("Auth::can_view; not admin") if $debug;
	if ( $_[0]{'mode'} eq 'public' ) {
$openprint::log->debug("Prinvacu::can_view; public") if $debug;
		return 1;
	} elsif ( $_[0]{'mode'} eq 'logged_in' ) {
$openprint::log->debug("Prinvacu::can_view; logged in") if $debug;
		return 1 if $user_id;
	} elsif ( $_[0]{'mode'} eq 'specific' ) {
$openprint::log->debug("Prinvacu::can_view; specfic") if $debug;
		if ( @{$_[0]->usergroup_id()} ) {
			my @Groups = openprint::UserGroup->find('user_id any'=>$user_id );
			return 1 if sets::intersection( ( map { $_->id() } @Groups ), @{$_[0]->usergroup_id()} );
		} # end if
		if ( @{$_[0]->usertype_id()} ) {
			return 1 if sets::isin( $$User{type}, $_[0]->usertype_id() );
		} # end if
		if ( $_[0]->user_id() and sets::isin( $user_id, $_[0]->user_id() ) ) {
			return 1;
		} # end if
	} elsif ( $_[0]{'mode'} eq 'onlyyou' ) {
		return 1 if $_[0]->Object()->created_by() == $user_id;
	} else {
		$openprint::log->warn("Unknown value for privacy mode: ".$_[0]{'mode'} );
	} # end if
	return 0;
} # end sub can

1;
__END__
