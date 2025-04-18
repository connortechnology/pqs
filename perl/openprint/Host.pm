use strict;
use warnings;

require openprint::Object;

package openprint::Host_Notification;
our @ISA = qw( openprint::Object );
use vars qw( $debug $table @identified_by %fields %transforms %defaults );
$debug = 0;
$table = 'host_notifications';
@identified_by = ( 'host_id','user_id' );

%fields = (
	host_id			=>	'host_id',
	user_id			=>	'user_id',
);

package openprint::Host_Type;
our @ISA = qw( openprint::Object );
use vars qw( $debug $table $serial %fields %transforms %defaults %types );
$debug = 0;
$table = 'host_types';
$serial = 'host_types_id_seq';
%fields = (
	id			=>	'id',
	name		=>	'name',
);
%transforms = (
	id		=>	[ 's/\D//g' ],
	name	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);

package openprint::Host;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults %types );
$debug = 0;
$table = 'hosts';
$serial = 'hosts_id_seq';
%fields = (
	id			=>	'id',
  name => 'name',
  abbr_name => 'abbr_name',
	hostname	=>	'hostname',
	blacklist	=>	'blacklist',
	whitelist	=>	'whitelist',
	monitored	=>	'monitored',
	description	=>	'description',
	created_on	=>	'created_on',
	updated_on	=>	'updated_on',
	resolved_on	=>	'resolved_on',
	count		=>	'count',
	deleted		=>	'deleted',
	online		=>	'online',
	type_id		=>	'type_id',
	type			=>	undef,
	offline_seconds	=>	'offline_seconds',
	max_ping_time	=>	'max_ping_time',
  min_ping_frequency  =>  'min_ping_frequency',
	state_changed_on	=>	'state_changed_on',
	notified			=>	'notified',
	notify_frequency	=>	'notify_frequency',
	location_id			=>	'location_id',
	owner_id			=>	'owner_id',
  manufacturer_id => 'manufacturer_id',
);
%find_fields = (
	type	=>	'type_id = (SELECT id FROM Host_types WHERE host_types.name = ?)',
	mac	=>	'id=(SELECT host_id FROM host_interfaces WHERE mac=?)',
	ip	=>	'(SELECT ip FROM host_interfaces WHERE host_id=hosts.id)',
);
%transforms = (
	id			=>	[ 's/\D//g' ],
	notify_frequency	=>	[ 's/\D//g' ],
	min_ping_frequency	=>	[ 's/\D//g' ],
	max_ping_time	=>	[ 's/\D//g' ],
	hostname	=>	[ 's/[^\w\-\.\/:_%//g' ],
	description	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	name	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	abbr_name	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
	blacklist 	=>	0,
	whitelist 	=>	0,
	monitored 	=>	0,
	hostname  	=>	undef,
	created_on  =>	q`'NOW()'`,
	updated_on	=>	q`'NOW()'`,
	resolved_on		=>	undef,
	count		=>	0,
	deleted	=>	0,
	online	=>	undef,
	type_id	=>	undef,
	state_changed_on	=>	undef,
	offline_seconds	=>	undef,
	notified      =>	0,
	location_id		=>	undef,
	notify_frequency	=>	undef,
	owner_id			=>	undef,
  max_ping_time =>  1000,
  min_ping_frequency  =>  60,
);

sub save {
  my ( $self, $params ) = @_;

  $self->set( $params ) if $params;

  if ( $$self{Manufacturer} and $$self{Manufacturer}->name() and ! $$self{Manufacturer}->id() ) {
    $$self{Manufacturer}->save();
    $$self{manufacturer_id} = $$self{Manufacturer}->id();
  } # end if

  if ( ( my $error = $self->SUPER::save( ) ) ) {
    return $error;
  } # end if
  return '';

} # end sub save


sub name {
  my $self = shift;
  $$self{name} = shift if @_;
	if (!$$self{name}) {
		$$self{name} = $self->hostname();
		if ( ! $$self{name} ) {
			foreach my $HI ( $self->Interfaces() ) {
				if ( $$HI{ip} ) {
					$$self{name} = $$HI{ip};
					return $$self{name};
				}
			}
			foreach my $HI ( $self->Interfaces() ) {
				if ( $$HI{mac} ) {
					$$self{name} = $$HI{mac};
					return $$self{name};
				}
			}
			return 'unknown';			
		}
	}
	return $$self{name};
}

sub Config {
  my $self = shift;
  $$self{Config} = @_ if @_;
  if (!$$self{Config}) {
    if ($$self{id}) {
require openprint::Host_Config;
      $$self{Config} = [ openprint::Host_Config->find(host_id=>$$self{id}) ];
    } else {
      $$self{Config} = [];
    }
  }
  return @{$$self{Config}};
}

sub destroy {
	my $error = '';
	require openprint::Log;
	foreach my $Log ( openprint::Log->find( host_id=>$_[0]{id} ) ) {
		$error .= $Log->destroy();
		return $error if $error;
	} # end foreach Log
	foreach my $N ( $_[0]->Notifications() ) {
		$error .= $N->destroy();
		return $error if $error;
	} # end foreach Log
	foreach my $I ( $_[0]->Interfaces() ) {
		$error .= $I->destroy();
		return $error if $error;
	} # end foreach Log
	foreach ( $_[0]->Config() ) {
		$error .= $_->destroy();
		return $error if $error;
	} # end foreach
  require openprint::Project_Log;
	foreach my $Log ( openprint::Project_Log->find( host_id=>$_[0]{id} ) ) {
		$error .= $Log->save({host_id=>undef});
		last if $error;
	}
require openprint::Host_Info;
  foreach ( openprint::Host_Info->find(host_id=>$_[0]{id}) ) {
    $error .= $_->destroy();
		last if $error;
  }

	$error .= $_[0]->SUPER::destroy();
	return $error;
} # end sub destroy

sub ping {
	require Net::Ping;
	my $p = Net::Ping->new();
	my $rc;
	foreach my $HI ( $_[0]->Interfaces() ) {
		next if ! $$HI{ip};
		$rc = $p->ping($$HI{ip});
		return $rc if $rc;
	}
	$p->close();
	return $rc;
} # end sub ping

sub Type {
	return new openprint::Host_Type( $_[0]{type_id} );
} # end sub Type

sub type {
	if ( @_ > 1 ) {
		my $Type = openprint::Host_Type->find_one('name lc'=> lc openprint::Host_Type->transform(name=>$_[1]) );
		if ( ! $Type ) {
			$Type = new openprint::Host_Type();
			$Type->save({name=>$_[1]});
		} # end if
		$_[0]{type_id} = $Type->id();
		$_[0]{type} = $Type->name();
	} # end if @_ > 1
	if ( ! defined $_[0]{type} ) {
		$_[0]{type} = new openprint::Host_Type( $_[0]{type_id} )->name();
	} # end if
	return $_[0]{type};
} # end sub type

sub Notifications {
	my $self = shift;
	$$self{Notifications} = shift if @_;

	if ( ! $$self{Notifications} ) {
		@{$$self{Notifications}} = openprint::Host_Notification->find(
				host_id	=> $$self{id},
				) if $$self{id};
				#'order' => 'lower(strfirstName),lower(strlastname)' );
	} # end if
	return $$self{Notifications} ? @{$$self{Notifications}} : ();
} # end sub Notifications

sub Interfaces {
	if ( @_ > 1 ) {
		$_[0]{Interfaces} = $_[1];
	}
	if ( ! $_[0]{Interfaces} ) {
    require openprint::Host_Interface;
		@{$_[0]{Interfaces}} = openprint::Host_Interface->find(
				host_id	=>	$_[0]{id},
				order	=>	'mac',
				) if $_[0]{id};
	} # end if
	return $_[0]{Interfaces} ? @{$_[0]{Interfaces}} : ();
} # end sub Interfaces

sub Info {
  my $self = shift;
  my $key = shift;
  $$self{Info} = shift if @_;
	if ( ! $$self{Info} ) {
require openprint::Host_Info;
		%{$$self{Info}} = map { $_->name(), $_ } openprint::Host_Info->find(host_id=>$$self{id});
		if ( $debug ) {
			foreach my $k ( keys %{$$self{Info}} ) {
				$openprint::log->debug("Host::Info $k => " . ( defined $$self{Info}{$k}->value() ? $$self{Info}{$k}->value() : 'undef') );
			} # end foreach
		}
	} # end if
  return $$self{Info}{$key};
}

sub info {
  my $self = shift;
  my $key = shift;

  my $Info = $self->Info($key);
  return $Info->value() if $Info;
	$openprint::log->debug("No value for $key " . $self->to_string() );
	return '';
} # end sub info

sub Location {
	require openprint::Location;
	return new openprint::Location( $_[0]{location_id} );
} # end sub Location

sub resolve {
	foreach my $Interface (	$_[0]->Interfaces() ) {
		my $hostname = $Interface->resolve();
		return $hostname if $hostname;
	} # end foreach Interface
	return undef;
} # end sub resolve

sub reboot {
	my $Host = $_[0];
	require LWP;
	my $browser = LWP::UserAgent->new();

	my $success = 0;

	foreach my $HI ( $Host->Interfaces() ) {
		next if !$HI->ip();
		my $url;
		my $initial_url; # in case we need to hit a different url first.
		my $method = 'get';
		my $args = undef;
		my $expect;
		my $do_not_expect;
		my $port = 80;
		my $protocol = 'http';
    my $referer = '';

		if ( sets::isin( $Host->type(), [ 'AIC500', 'AIC500W', 'AIC777W', 'AIC747W' ] ) ) {
			$url = $HI->ip().'/admin/reboot.cgi?type=0';
		} elsif ( $Host->type() eq 'AIC250W' ) {
			$url = $HI->ip().'/Reply.htm?Reset=Yes';
		} elsif ( $Host->type() eq 'M8640' ) {
			$url = $HI->ip().'/cgi-bin/reboot.cgi';
		} elsif ( $Host->type() eq 'TL-WPA4220' ) {
			$url = $HI->ip().'/userRpm/SysRebootRpm.htm?Reboot=Reboot';
		} elsif( $Host->type() eq 'D-Link DAP1522' ) {
			$url = $HI->ip().'/sys_cfg_valid.xgi?&exeshell=submit REBOOT';
		} elsif( $Host->type() eq 'DGS-1224T' ) {
			$initial_url = $HI->ip();
			$url = '/cgi_device';
			$args = {
			post_url => 'cgi_reboot.',
			};
			$method = 'post';
    } elsif( $Host->type() eq 'Grandview' ) {
      $initial_url = $HI->ip();
      $url = $HI->ip().'/goform/maintenance?cmd=set&restart=yes';
    } elsif( $Host->type() eq 'Vivotek' ) {
      $initial_url = $HI->ip();
      $url = $HI->ip().'/cgi-bin/admin/setparam.cgi';
			$method = 'post';
			$args = {
				system_reset => 1
			};
		} elsif( $Host->type() eq 'DLink DCS-910' ) {
			$initial_url = $HI->ip();
			$url = $HI->ip().'/ReplyF.htm';
			$method = 'post';
			$args = {
				Reset => 'Reboot the Device',
			};
			$expect = 'Device has been rebooted';

		} elsif( $Host->type() eq 'DLink DCS-2310L' ) {
      $initial_url = $HI->ip();
			$url = $HI->ip().'/vb.htm?setallreboot=1';
			$method = 'get';
			$expect = 'OK setallreboot';
		} elsif ( $Host->type() eq 'TP-Link Archer C7' ) {
			require JSON;

			my $username = $Host->info('username');
			my $password = $Host->info('password');

			# Need to get an auth token
			my $uri = $protocol.'://'.$$HI{ip}.'/cgi-bin/luci/rpc/auth';
			my $json = qq`{"id":"1","method":"login","params":["$username","$password"]}`;
			my $req = HTTP::Request->new('POST', $uri);
			$req->header('Content-Type' => 'application/json');
			$req->content($json);
			my $response = $browser->request($req);

			if ( !$response->is_success ) {
				$openprint::log->error("Failed to get auth token:\n".$response->content);
				next;
			}

			my $json_response = JSON::decode_json($response->content);
			if ( ! ( $json_response and $$json_response{result} ) ) {
				$openprint::log->error("Failed to get auth token:\n".$response->content);
				next;
			}

			$uri = $protocol.'://'.$$HI{ip}.'/cgi-bin/luci/rpc/sys?auth='.$$json_response{result};
			$json = qq`{"id":"1","method":"call","params":["reboot"]}`;
			$req = HTTP::Request->new('POST', $uri);
			$req->header('Content-Type' => 'application/json');
			$req->content($json);
			$response = $browser->request($req);
			if ( !$response->is_success ) {
				$openprint::log->error(join("\n",
							'Failed to reboot:',
							$response->content,
							$response->status_line()
							));
				next;
			}

			$json_response = JSON::decode_json($response->content);
			if ( !$json_response or $$json_response{error} ) {
				$openprint::log->error("Failed to reboot:\n".$response->content);
				next;
			}
			$success = 1;
			last;

		} elsif( $Host->type() eq 'DCS_932L' ) {
			$url = $HI->ip().'/setSystemReboot';
		} elsif( $Host->type() eq 'DCS-933L' ) {
			$initial_url = $HI->ip();
			$url = $HI->ip().'/setSystemReboot';
			$method = 'post';
			$args = {
				ReplySuccessPage=> 'reboot.htm',
				ReplyErrorPage	=> 'reboot.htm',
				Reset						=> 'Reboot the Device',
			};
		} elsif ( $Host->type() eq 'WG602v3' ) {
			$url = $HI->ip().'/cgi-bin/reboot.cgi';
			$args = {
				reboot_ap => 1,
			};
			$do_not_expect = 'SORRY';
    } elsif ( $Host->type() eq 'Trendnet TV-862IC' or $Host->type() eq 'DCS-942L') {
      # Success looks for rebootOK
      $referer = 'http://'.$HI->ip().'/eng/admin/tools_default.cgi';
      $initial_url = $HI->ip().'/eng/admin/tools_default.cgi';
      $url = $HI->ip().'/eng/admin/reboot.cgi';
      $method = 'post';
      $args = {
        reboot => 'true',
      };
    } else {
      $openprint::log->error("Unknown host type $$Host{type}");
			return 0;
		}

		my $response = $browser->get($protocol.'://'.($initial_url ? $initial_url : $url));
		$openprint::log->debug('Sending initial url: ' . $protocol.'://'.($initial_url ? $initial_url : $url).
      ' status: ' . $response->is_success . ' ' . $response->status_line() . $response->content);
    {
      my $headers = $response->headers();
      if ( $$headers{'client-ssl-cipher'} ) {
        $openprint::log->debug('Switching to https');
        $protocol = 'https';
        $port = 443;
      }
      foreach my $k ( keys %$headers ) {
        $openprint::log->debug("Header $k => $$headers{$k}");
      }	# end foreach
    }
		$response = $HI->authenticate($browser, $response, $method, $port, $protocol.'://'.($initial_url ? $initial_url : $url), $args);

		if ( !$response->is_success ) {
			$openprint::log->error("No success: content:".$response->content."\nstatus:".$response->status_line());
			if ( $response->status_line() eq '401 Unauthorized' or $response->status_line() eq '401 Not Authorized' ) {
				$openprint::log->error("Couldn't get content from $url unauthorized trying again:". $response->status_line);
				$response = $browser->get($protocol.'://'.$url);
				if ( $response->status_line() eq '401 Unauthorized' or $response->status_line() eq '401 Not Authorized' ) {
					$openprint::log->error("Couldn't get content from $url unauthorized:". $response->status_line);
					my $headers = $response->headers();
					foreach my $k ( keys %$headers ) {
						$openprint::log->error("Header $k => $$headers{$k}");
					}	# end foreach
					$openprint::log->error( $response->content );
					next;
				} else {
					$openprint::log->debug('Response after second attempt: '.$response->status_line);
					$success = 1;
				} # end if
			} else {
				$openprint::log->warn("Couldn't get content from $protocol://$url rebooting" . $response->status_line );
				my $headers = $response->headers();
				foreach my $k ( keys %$headers ) {
					$openprint::log->error("Header $k => $$headers{$k}");
				}	# end foreach
				next;
			} # end if
		} else {
			$success = 1;
			$openprint::log->debug('Success content after auth to initial_url: '.$response->content);
		} # end if

		if ( $success ) {
      if ( $url ne $initial_url ) {
        $openprint::log->debug('Sending actual url '.$method . ' ' . $url);
        $browser->default_header('Referer', $referer) if $referer;
        $response = $browser->$method($protocol.'://'.$url, $args ? $args : ());
        $openprint::log->debug('Success Content: '.$response->content);
      }
			if ( $expect and ! ( $response->content =~ /$expect/ ) ) {
				$success = 0;
				$openprint::log->error("Did not find expected content $expect in " . $response->content );
			} elsif ( $do_not_expect and ( $response->content =~ /$do_not_expect/ ) ) {
				$success = 0;
				$openprint::log->error("Found unwanted content $do_not_expect in " . $response->content );
			}
		}
		last if $success;
	} # end foreach HI

	if ( $success ) {

		(new openprint::Log())->save({
        action=>'Host rebooted',
        Object=>$Host,
        host_id=>$Host->id(),
        note=>sprintf('<a href="/employee/it/host.html?host_id=%d">%s</a> has been rebooted by %s.', @$Host{'id','hostname'}, $0)
      });
		if ( 0 ) {
			my @To = map { $_->User() } $Host->Notifications();
			if ( @To and ( @To < 10 ) ) {
				$openprint::log->debug("Emailing: " . join(',', map { $_->email() } @To ) );
				my $results = (new openprint::Email())->send(
						TO			=>	\@To,
						SUBJECT	=>	'Camera rebooted ' . $Host->hostname(),
						FROM		=>	$openprint::config{TechSupportEmail},
						BODY		=>	"
						Description: $$Host{description}
						",
						);
			} else {
				$openprint::log->error("No To or too many @To");
			} # end if TO
		} # end if 0
	} # end if
	return $success;
} # end sub reboot

sub is_wap {
	return ( $_[0]{type_id} && $_[0]->type() && sets::isin( $_[0]->type(), [ 'WG602v3', 'WPN802','TP-Link Archer C7' ] ) );
}

sub url_to {
	return sprintf('/employee/it/host.html?host_id=%d', $_[0]{id});
}

sub link_to {
	return sprintf('<a href="/employee/it/host.html?host_id=%d">%s</a>',
      ( $_[0]{id} ? $_[0]{id} : 0 ),
      ( ( @_ > 1 and $_[1] ) ? $_[1] : ( $_[0]->name() ? $_[0]->name() : '' ) )
      );
}

sub online {
	if ( @_ > 1 ) {
		$_[0]{online} = $_[1];
	}
	if ( ! defined $_[0]{online} ) {
		foreach my $HI ( $_[0]->Interfaces() ) {
			if ( $$HI{online} ) {
				$_[0]{online} = 1;
				last;
			} elsif ( defined $$HI{online} ) {
				$_[0]{online} = 0;
			}
		} # end foreach HI
	}
	return $_[0]{online};
}

sub Owner {
  return new openprint::Company( $_[0]{owner_id} );
}

sub can_reboot {
  if ( $_[0]{type_id} and $_[0]->type() and sets::isin( $_[0]->type(), [
				'AIC500', 'AIC500W', 'AIC777W', 'AIC747W','AIC250W',
				'M8640',
				'TL-WPA4220', 'TP-Link Archer C7',
				'D-Link DAP1522','DGS-1224T','DLink DCS-910',
        'DCS_932L','DCS-933L','DCS-942L', 'WG602v3',
        'Trendnet TV-862IC',
				'Vivotek' ] ) ) {
    return !undef;
  }
  return undef;
} # end sub can_reboot

sub get_config {
	my $self = shift;
	my %config;

	if ( !($$self{type_id} and $self->type()) ) {
		my ( $caller, undef, $line ) = caller;
		$openprint::log->debug("get_config called when can_get_config should have been checked from $caller:$line");
		return;
	}

	eval {
		require 'openprint/Host/'.$self->type().'.pm';
		my $Host = ('openprint::Host::'.$self->type())->new($self);
		%config = $Host->get_config();
	};
	$openprint::log->error('Eval error of require Reason: '.$@) if $@;
	return %config;
} # end sub get_config

sub get_status {
	my $self = shift;
	my %status;
	if ( !($$self{type_id} and $self->type()) ) {
		my ( $caller, undef, $line ) = caller;
		$openprint::log->debug("get_status called when can_get_status should have been checked from $caller:$line");
		return;
	}

	eval {
		require 'openprint/Host/'.$self->type().'.pm';
		my $Host = ('openprint::Host::'.$self->type())->new($self);
		%status = $Host->get_status();
	};
	$openprint::log->error('Eval error of require Reason: '.$@) if $@;
	return %status;
} # end sub get_status

sub can_get_status {
	return 0;
	return ( $_[0]{type_id} and sets::isin( $_[0]->type(), [ 'Vivotek' ] ) );
}

sub can_get_config {
	return ( $_[0]{type_id} and sets::isin( $_[0]->type(), [ 'DCS_932L'] ) );
}

sub get_and_store_config {
	my $self = shift;
	if ( $self->can_get_config() ) {
	} else {
		Error("Host type $$self{type} doesn't have support for getting config.");
	}
}

sub can_get_image {
	return ( $_[0]{type_id} and sets::isin( $_[0]->type(), [ 'DCS_932L','Vivotek' ] ) );
}

sub get_image {
	my $self = shift;
	my $url;

	eval {
		require 'openprint/Host/'.$self->type().'.pm';
		my $Host = ('openprint::Host::'.$self->type())->new($self);
		$url = $Host->get_image(@_);
	};
	$openprint::log->error('Eval error of require Reason: '.$@) if $@;
	return $url;
}

sub check {
	my $self = shift;
	my @check;	
	return if ! ( $$self{type_id} and sets::isin($self->type(), ['Vivotek']) );
	eval {
		require 'openprint/Host/'.$self->type().'.pm';
		my $Host = ('openprint::Host::'.$self->type())->new($self);
		@check = $Host->check();
	};
	return @check;
}
#sub new {
	#my $parent = shift;
	#my $self = $parent->SUPER::new(@_);
	#if ( $self->type() eq 'Vivotek' ) {
		#bless $self, 'openprint::Host::Vivotek';
	#}
	#return $self;
#}

sub thumbnail_html {
	my $self = shift;
	my $size = @_ ? shift : 'small';
	if ( $self->can_get_image() ) {
		my @dimensions = openprint::Asset::get_dimensions('Landscape', $size);
    my $src = $self->get_image(@dimensions);
		return '<img src="'.$self->get_image(@dimensions).'" alt=""/>' if $src;
	}
	my @Assets = $self->Assets();
  #$openprint::log->debug("Assets: $size " . @Assets);
	return ( @Assets ? $Assets[0]->Asset()->sized_html($size) : '' );
}

sub thumbnail_url {
	my $self = shift;
	my $size = @_ ? shift : 'small';
	if ( $self->can_get_image() ) {
		my @dimensions = openprint::Asset::get_dimensions('Landscape', $size);
		return $self->get_image(@dimensions);
	}
	my @Assets = $self->Assets();
	return ( @Assets ? $Assets[0]->Asset()->sized_url($size) : '' );
}

sub Manufacturer {
  my $self = shift;
  $$self{Manufacturer} = shift if @_;
  if (!$$self{Manufacturer}) {
require openprint::Manufacturer;
    $$self{Manufacturer} = new openprint::Manufacturer();
  }
  return $$self{Manufacturer};
}

sub manufacturer {
  my $self = shift;
  my $Manufacturer = $self->Manufacturer();
  if (@_) {
    my $manufacturer = shift;
    if ($Manufacturer->name() ne $manufacturer) {
require openprint::Manufacturer;
      my $Manufacturer = openprint::Manufacturer->find_one('name lc'=>lc openprint::Manufacturer->transform(name=>$manufacturer));
      if (!$Manufacturer) {
        $Manufacturer = new openprint::Manufacturer();
        $Manufacturer->name($manufacturer);
      }
      $$self{Manufacturer} = $Manufacturer;
    }
  }
  return $Manufacturer->name();
}

1;
__END__
