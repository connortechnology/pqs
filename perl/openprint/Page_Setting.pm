use strict;
package openprint::Page_Setting;
our @ISA = qw(openprint::Object);

use vars qw( $debug $serial $table %fields %transforms %defaults $cache_field $cached %cache );
use constant DEBUG => 0;

$debug = 0;
$cached = 0;
$table = 'page_settings';
$serial = 'page_settings_id_seq';
%fields = (
	id				=>	'id',
	url				=>	'url',
	user_level		=>	'user_level',
	cacheable		=>	'cacheable',
	keywords		=>	'keywords',
	description		=>	'description',
	user_ids		=>	'user_ids',
	usergroup_ids	=>	'usergroup_ids',
	message			=>	'message',
);
%transforms = (
  #url	=>	[ 's/\/+$//g' ],
);
%defaults = (
	user_level		=>	undef,
	cacheable		=>	undef,
	user_ids		=>	'[]',
	usergroup_ids	=>	'[]',
);
$cache_field = 'url';
sub cache_field {
    return $cache_field;
}

sub can_view {

	if ( $openprint::session{user_id} ) {
		if ( $_[0]{user_ids} and sets::isin( $openprint::session{user_id}, $_[0]{user_ids} ) ) {
			$openprint::log->debug("User is in user_ids") if DEBUG;
			return 1;
		} # end if
		if ( $openprint::session{user_type} eq 'A' ) {
			$openprint::log->debug("User is an admin") if DEBUG;
			return 1;
		} elsif ( DEBUG ) {
			$openprint::log->debug("User is not an admini $openprint::session{user_type}") if DEBUG;
		}
	} # end if
		
	if ( $_[0]{usergroup_ids} and @{$_[0]{usergroup_ids}} ) {
#$openprint::log->debug("CHecking usergroups " . ( $_[0]{usergroup_ids} ? join(', ', @{ $_[0]{usergroup_ids} } ) : 'none' ) );
		return 0 if ! $openprint::session{user_id};
		my $User = $openprint::User;
$openprint::log->debug( "is User in groups: " . join(',', $User->usergroup_ids()) ) if DEBUG;
$openprint::log->debug( "Usergroups are " . join(',', @{$_[0]{usergroup_ids}}) ) if DEBUG;
		my @intersection = sets::intersection( @{$_[0]{usergroup_ids}}, $User->usergroup_ids() );
		$openprint::log->debug( "Inserection: (" . join(',', @intersection ) . ')' . @intersection) if DEBUG;
		if ( @intersection ) {
			#$openprint::log->debug("REturning 0");
			return 1;
		}
		return 0;
	} else {
#$openprint::log->debug("Not CHecking usergroups " );

	}
	# User level defineds the default response.
	if ( $_[0]{user_level} ) {
		if ( $_[0]{user_level} eq 'A' ) {
			if ( $openprint::session{user_type} ne 'A' ) {
				$openprint::log->debug("REturning 0 cuz not an admin") if DEBUG;
				return 0;
			}
		} elsif ( $_[0]{user_level} eq 'E' ) {
			return 0 if ( $openprint::session{user_type} ne 'A' and $openprint::session{user_type} ne 'E' );

		} elsif ( $_[0]{user_level} eq 'C' ) {
			return 0 if ( $openprint::session{user_type} ne 'C' and $openprint::session{user_type} ne 'A' and $openprint::session{user_type} ne 'E' );
		} else {
			return 0;
		} 
	} 
$openprint::log->debug("Returning 1") if DEBUG;
	return 1; 
} # end sub can_view

sub Users {
	if ( ! exists $_[0]{Users} ) {
	require openprint::User;
		$_[0]{Users} = [ openprint::User->find( id=>$_[0]{user_ids}, order=>'lower(firstname),lower(lastname)' ) ] if $_[0]{user_ids} and @{$_[0]{user_ids}};
	} 
	return @{$_[0]{Users}} if $_[0]{Users};
	return ();
} 

sub get {
	my ( $page ) = @_;

	if ( ! $cache{$openprint::config{db_name}} ) {
		$openprint::log->debug("loading Page settings for $openprint::config{db_name}") if DEBUG;
		$cache{$openprint::config{db_name}} = { map { $_->url(), $_ } openprint::Page_Setting->find() };
	} # end if

	my $cache = $cache{$openprint::config{db_name}};

	if ( ! $$cache{$page} ) {
    $openprint::log->debug("No cached Page Setting found for $page") if DEBUG;
# Need to create one.
		my @chunks = split('/', $page);
		while ( @chunks ) {
			pop @chunks;
			last if ! @chunks;

# Because there is a / at the beginning of the url, the first entry in chunks is '', so we don't need to prepend a /
			my $chunk = join('/', @chunks);
      #$chunk = '/' if ! $chunk; # neccessary to deal with the empty string

			$openprint::log->debug("Looking for page setting for $chunk") if DEBUG;
			if ( $$cache{$chunk} ) {
# Why stuff up the db with entries, just fill the hash with copies.
				$$cache{$page} = $$cache{$chunk};
				last;
      } elsif ( $$cache{$chunk.'/'} ) {
# Why stuff up the db with entries, just fill the hash with copies.
				$$cache{$page} = $$cache{$chunk.'/'};
				last;
			} # end if
		} # end while chunks
		if ( ! $$cache{$page} ) {
$openprint::log->debug("Didn't find page setting for $page") if DEBUG;
			$$cache{$page} = new openprint::Page_Setting();
			#$$cache{$page}->save({url=>$page}) if $openprint::session{user_type} eq 'A';
		} # end if
	} # end if Page Settings not found
$openprint::log->debug("Found Page setting " . $$cache{$page}->to_string() ) if DEBUG;
	return $$cache{$page};
} # end sub get

1;
__END__
