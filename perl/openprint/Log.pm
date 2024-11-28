use strict;
package openprint::Log;
our @ISA = qw( openprint::Object );
use openprint ();
require openprint::Object;
require openprint::Log_Action;
require openprint::Host;

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults %types );
$debug = 0;
$table = 'logs';
$serial = 'logs_id_seq';
%fields = (
	id	=>	'id',
	user_id		=>	'user_id',
	company_id	=>	'company_id',
	date_time		=>	'date_time',	
	action_id	=>	'action_id',
	action			=>	undef,
	note			=>	'note',
	host_id		=>	'host_id',
	ip_address	=>	undef,
	url			=>	'url',
	object_type_id		=>	'object_type_id',
	object_type	=>	undef,
	object_id		=>	'object_id',
	Object		=>	undef,
);
%find_fields = (
  #action		=>	'(SELECT name FROM log_actions WHERE log_actions.id = logs.action_id)',
	action		=>	'action_id = (SELECT id FROM log_actions WHERE name = ?)',
	object_type	=>	'(SELECT name FROM Object_Types WHERE object_types.id=logs.object_type_id)',
	ip_address	=>	'(SELECT ip FROM Host_Interfaces where host_interfaces.host_id=host_id)',
);
%defaults = (
	date_time	=>	"'NOW()'",
	user_id	=>	q`$openprint::session{user_id}`,
	company_id	=>	q`$openprint::session{company_id}`,
	url           =>  q`join('',(defined $ENV{SERVER_NAME}?$ENV{SERVER_NAME}:''),(defined($ENV{REQUEST_URI})?$ENV{REQUEST_URI}:''))`,
	host_id		=>	q`$self->ip_address( $ENV{HTTP_X_FORWARDED_FOR} ? $ENV{HTTP_X_FORWARDED_FOR} : $ENV{REMOTE_ADDR} );return $$self{host_id};`,
	object_type_id		=>	q`undef`,
	object_id		=>	q`undef`,
);

sub User {
	require openprint::User;
	return new openprint::User( $_[0]{user_id} );
} # end sub User

sub Company {
	return new openprint::Company( $_[0]{company_id} );
} # end sub Company

sub Action {
	$_[0]{Action} = new openprint::Log_Action($_[0]{action_id}) if ! $_[0]{Action};
	return $_[0]{Action};
} # end sub Action

sub hostname {
	my ( $self, $new ) = @_;
	my $Host = $self->Host();

	if ( defined $new ) {
		$Host->save({hostname=>$new});
	} # end if
	return $Host->hostname();
} # end sub hostname

sub ip_address {
	my $Host = $_[0]->Host();

	if ( @_ > 1 ) {
		if ( !defined $_[1] ) {
			$_[1] = $ENV{HTTP_X_FORWARDED_FOR} ? $ENV{HTTP_X_FORWARDED_FOR} : $ENV{REMOTE_ADDR};
		} # end if
		if ( (! $_[1]) and $openprint::config{REMOTE_ADDR} ) {
			$_[1] = $openprint::config{REMOTE_ADDR};
		}
		return if ! $_[1];

    require openprint::Host_Interface;
		my $Interface = openprint::Host_Interface->find_one(ip=>$_[1]);
		if ( !$Interface ) {
			$Host = openprint::Host->find_one(hostname=>$_[1]);
			if ( ! $Host ) {
				$Host = new openprint::Host();
				$Host->save({hostname=>$_[1], name=>$_[1]});
			}
			$Interface = new openprint::Host_Interface();
			$Interface->save({host_id=>$$Host{id}, ip=>$_[1]});
		} else {
			$Host = $Interface->Host();
		} # end if
		$_[0]{host_id} = $Host->id();
	} # end if
	return join('<br/>', map { $_->ip() ? $_->ip() : () } $Host->Interfaces());
} # end sub ip_address

sub Host {
	if ( ( ! $_[0]{host_id} ) and ( $_[0]{ip_address} ) ) {
		my $Interface = openprint::Host_Interface->find_one( ip=>$_[0]{ip_address} );
		my $Host;
		if (!$Interface) {
      # This should fix infinite loop when adding a new host.
      $Host = openprint::Host->find_one(hostname=>$_[0]{ip_address});
      if (!$Host) {
        $Host = new openprint::Host();
        $Host->save({hostname=>$_[0]{ip_address}});
      }
      $Interface = new openprint::Host_Interface();
			$Interface->save({ host_id=>$$Host{id}, ip=>$_[0]{ip_address} });
		} else {
			$Host = $Interface->Host();
		} 
			
		$_ = $_[0]->save({host_id=>$Host->id()});
		$openprint::log->error( $_ ) if $_;
	} # end if
		
	return new openprint::Host( $_[0]{host_id} );
} # end sub Host

sub action {
	if (@_ > 1 and $_[1]) {
		my $Action = openprint::Log_Action->find_one('name lc'=>lc $_[1]);
		if (!$Action) {
			$Action = new openprint::Log_Action();
			$Action->save({name=>$_[1], description=>$_[1]});
		} # end if
		$_[0]{Action} = $Action;
		$_[0]{action_id} = $Action->id();
		return $Action->name();
	} # end if
	return $_[0]->Action()->name();
} # end sub action

sub note_html {
	if ( !$_[0]{note_html} ) {
		if ( $_[0]{note} ) {
			$_[0]{note_html} = ssi::htmlize($_[0]{note});
			$_[0]{note_html} =~ s/&lt;a href=&quot;([^"]+)&quot;&gt;(.+)&lt;\/a&gt;/<a href=&quot;$1&quot;>$2<\/a>/ig;
		}
	}
	return defined $_[0]{note_html} ? $_[0]{note_html} : '';
}

1;
__END__
