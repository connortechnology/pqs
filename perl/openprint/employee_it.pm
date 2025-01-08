use strict;
use warnings;

package openprint::employee_it;
use openprint;
use vars qw( %variable %session %param %config $log $dbh $r );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

require openprint::Host;
#require openprint::Host_Config;
#require openprint::User_Type;
#require openprint::Session;
#require openprint::Software;
require openprint::Location;
require openprint::Manufacturer;
#require openprint::Syslog;

use Data::Dumper;

sub index {
}

sub logs {
	_logs();
	ssi::setup_date_select( '/employee/it/logs.html', 'date_time_start', 0 );
	ssi::setup_date_select( '/employee/it/logs.html', 'date_time_end', 0 );
} # end sub logs

sub _logs {
	ssi::save_params( '/employee/it/logs.html', 
			( map { 'date_time_start_' . $_ } ( 'year','month','day','hour','minute' ) ),
			( map { 'date_time_end_' . $_ } ( 'year','month','day','hour','minute' ) ),
	);
} # end sub _logs

sub hosts {
	_hosts();
  my $uri = $r->uri();
	ssi::setup_date_select( $uri, 'created_on_start', '' );
	ssi::setup_date_select( $uri, 'created_on_end', '' );
	ssi::setup_date_select( $uri, 'updated_on_start', -7 );
	ssi::setup_date_select( $uri, 'updated_on_end', '' );
	if ( ! exists $session{$uri.'?has_hostname'} ) {
		$session{$uri.'?has_hostname'} = '';
	} # end if
	if ( ! exists $session{$uri.'?deleted'} ) {
		$session{$uri.'?deleted'} = 0;
	} # end if
} # end sub hosts

sub _hosts {
  $variable{uri} = '/employee/it/hosts.html';
  if ($param{action}) {
    if ( $param{action} eq 'Delete' ) {
      my @host_ids;
      if ( exists $param{host_id} ) {
        @host_ids = ref $param{host_id} eq 'ARRAY' ? @{$param{host_id}} : $param{host_id};
      } elsif ( exists $param{'host_id[]'} ) {
        @host_ids = ref $param{'host_id[]'} eq 'ARRAY' ? @{$param{'host_id[]'}} : $param{'host_id[]'};
      }
      foreach my $host_id ( @host_ids ) {
        my $Host = new openprint::Host( $host_id );
        if ( $Host->deleted() ) {
          $variable{error} .= $Host->destroy();
        } else {
          $variable{error} .= $Host->delete();
        }
      } # end foreach host_id
      %param = ();
    } elsif ( $param{action} eq 'undelete' ) {
      my @host_ids;
      if ( exists $param{host_id} ) {
        @host_ids = ref $param{host_id} eq 'ARRAY' ? @{$param{host_id}} : $param{host_id};
      } elsif ( exists $param{'host_id[]'} ) {
        @host_ids = ref $param{'host_id[]'} eq 'ARRAY' ? @{$param{'host_id[]'}} : $param{'host_id[]'};
      }
      foreach my $host_id ( @host_ids ) {
        my $Host = new openprint::Host( $host_id );
        if ( $Host->deleted() ) {
          $variable{error} .= $Host->undelete();
        } else {
          $variable{error} .= $Host->id() . ' not deleted so not undeleted.<br/>';
        }
      } # end foreach host_id
      %param = ();
    } elsif ( $param{action} eq 'destroy' ) {
      my @host_ids;
      if ( exists $param{host_id} ) {
        @host_ids = ref $param{host_id} eq 'ARRAY' ? @{$param{host_id}} : $param{host_id};
      } elsif ( exists $param{'host_id[]'} ) {
        @host_ids = ref $param{'host_id[]'} eq 'ARRAY' ? @{$param{'host_id[]'}} : $param{'host_id[]'};
      }
      foreach my $host_id ( @host_ids ) {
        my $Host = new openprint::Host( $host_id );
        if ( $Host->deleted() ) {
          $variable{error} .= $Host->destroy();
        } else {
          $variable{error} .= $Host->id() . ' not deleted so not destroying.<br/>';
        }
      } # end foreach host_id
      %param = ();
    } elsif ( $param{action} eq 'wake' ) {
      my @host_ids;
      if ( exists $param{host_id} ) {
        @host_ids = ref $param{host_id} eq 'ARRAY' ? @{$param{host_id}} : $param{host_id};
      } elsif ( exists $param{'host_id[]'} ) {
        @host_ids = ref $param{'host_id[]'} eq 'ARRAY' ? @{$param{'host_id[]'}} : $param{'host_id[]'};
      }
      foreach my $Host ( openprint::Host->find(id=>\@host_ids, deleted=>[0,1])) {
        foreach my $I ( $Host->Interfaces() ) {
          next if ! $I->mac();
          my ( $error, $info ) = $I->wake();
          $variable{error} .= $error;
          $variable{information} .= $info;
        } # end foreach Host_Interface
      } # end foreach Host
    } # end if action
  } # end if action

	ssi::save_params( '/employee/it/hosts.html', 
			'created_on_start_year', 'created_on_start_month', 'created_on_start_day', 
			'created_on_end_year', 'created_on_end_month', 'created_on_end_day', 
			'updated_on_start_year', 'updated_on_start_month', 'updated_on_start_day', 
			'updated_on_end_year', 'updated_on_end_month', 'updated_on_end_day', 
			'has_hostname', 'monitored','whitelisted','blacklisted','online',
			'ip','hostname', 'mac', 'type_id', 'network_id', 'name',
			'radius_auth', 'order', 'deleted', 'owner_id',
			);

	if ($config{'RADIUS_Support'} and ( $config{'RADIUS_Support'} eq 'Y')) {
    require openprint::RADIUS_Check;
    require openprint::RADIUS_Reply;
		$openprint::RADIUS_Reply::dbh = $openprint::RADIUS_Check::dbh = sql::open_sql( $log,
				database  => $config{RADIUS_DB_Name},
				driver    => $config{RADIUS_DB_Driver},
				host      => $config{RADIUS_DB_Server},
				login     => $config{RADIUS_DB_Username},
				password  => $config{RADIUS_DB_Password},
				);
		if ( ! $openprint::RADIUS_Check::dbh ) {
			$variable{error} .= 'Unable to connect to RADIUS DB server.';
		} # end if
	} # end if RADIUS
} # end sub _hosts

sub networks {
	_networks();
  my $uri = $r->uri();
	ssi::setup_date_select( $uri, 'created_on_start', '' );
	ssi::setup_date_select( $uri, 'created_on_end', '' );
	ssi::setup_date_select( $uri, 'updated_on_start', '' );
	ssi::setup_date_select( $uri, 'updated_on_end', '' );
	if ( ! exists $session{$uri.'?has_hostname'} ) {
		$session{$uri.'?has_hostname'} = '';
	} # end if
	if ( ! exists $session{$uri.'?deleted'} ) {
		$session{$uri.'?deleted'} = 0;
	} # end if
} # end sub networks

sub _networks {
  if ($param{action}) {
    if ( $param{action} eq 'Delete' ) {
      my @host_ids;
      if ( exists $param{host_id} ) {
        @host_ids = ref $param{host_id} eq 'ARRAY' ? @{$param{host_id}} : $param{host_id};
      } elsif ( exists $param{'host_id[]'} ) {
        @host_ids = ref $param{'host_id[]'} eq 'ARRAY' ? @{$param{'host_id[]'}} : $param{'host_id[]'};
      }
      foreach my $host_id ( @host_ids ) {
        my $Host = new openprint::Host( $host_id );
        if ( $Host->deleted() ) {
          $variable{error} .= $Host->destroy();
        } else {
          $variable{error} .= $Host->delete();
        }
      } # end foreach host_id
      %param = ();
    } # end if
  } # end if
	ssi::save_params( '/employee/it/networks.html', 
			'created_on_start_year', 'created_on_start_month', 'created_on_start_day', 
			'created_on_end_year', 'created_on_end_month', 'created_on_end_day', 
			'updated_on_start_year', 'updated_on_start_month', 'updated_on_start_day', 
			'updated_on_end_year', 'updated_on_end_month', 'updated_on_end_day', 
			'has_hostname', 'monitored',
			'order', 'deleted', 'owner_id',
			);
} # end sub _networks

sub host {
  if ( $param{host_id} ) {
    $param{host_id} = openprint::Host->transform( id=>$param{host_id} );
    if ( ! $param{host_id} ) {
      $variable{error} .= 'Invalid host_id specified<br/>';
      return;
    }
  }
	my $Host = $variable{Host} = new openprint::Host( $param{host_id} );
  if ( $param{host_id} and ! $$Host{id} ) {
    $variable{error} .= 'Host not found for id ' . $param{host_id}.'<br/>';
    return;
  }
  if ( $param{action} ) {
    if ( $param{action} eq 'Resolve' ) {
      foreach my $I ( $Host->Interfaces() ) {
        if ( ! $I->ip() ) {
          $variable{error} .= 'For ' . $I->mac() . ': No ip.  Cant resolve without an ip.';
        } else {
          my $hostname = $Host->resolve();
          if ( $hostname ) {
            $Host->set({ hostname	=> $hostname });
            $variable{information} .= "Discovered hostname $hostname.";
          } else {
            $variable{error} .= 'Failed to resolve hostname<br/>';
          }
          if ( ! $$I{mac} ) {
            my $mac = $I->get_mac();
            if ( $mac ) {
              $I->set({ mac	=> $mac });
              $variable{information} .= "Discovered mac $mac.";
            } else {
              $variable{error} .= 'Failed to determine mac address<br/>';
            }
          }
          if ( $variable{information} ) {
            $variable{information} .= "<br/>Click Save to commit new values";
          }
        } # end if
      } # end foreach
    } elsif ( $param{action} eq 'Delete' ) {
      $variable{error} .= $Host->delete();
      if ( ! $variable{error} ) {
        $variable{ExternalRedirect} = '/employee/it/hosts.html';
        return;
      } # end if
      %param = ();
    } elsif ( $param{action} eq 'Undelete' ) {
      $variable{error} .= $Host->undelete();
      if ( ! $variable{error} ) {
        $variable{ExternalRedirect} = '/employee/it/hosts.html';
        return;
      } # end if
      %param = ();
    } elsif ( $param{action} eq 'Destroy' ) {
      $variable{error} .= $Host->destroy();
      if ( !$variable{error} ) {
        $variable{ExternalRedirect} = '/employee/it/hosts.html';
        return;
      } # end if
      %param = ();
    } elsif ( $param{action} eq 'reboot' ) {
      if ( $Host->reboot() ) {
        $variable{information} .= 'Host successfully rebooted';
      } else {
        $variable{error} .= 'Host failed to reboot. Check logs';
      }
      $variable{ExternalRedirect} = $Host->url_to();
    } elsif ( $param{action} eq 'get_config' ) {
			my $content = $Host->get_config();
      if ( $content ) {
        $variable{Download} = $content;
				my $filename = $Host->name().Date::Format::time2str( '%Y-%m-%d %H:%M:%S', time).'.cfg';
				$r->headers_out->{'Content-Disposition'} = "attachment; filename=\"$filename\"";
				$r->content_type("text/csv; name=\"$filename\"");
      } else {
        $variable{error} .= 'Failed to get content. ';
      }
    } elsif ( $param{action} eq 'Wake' ) {
      my @Interfaces = $Host->Interfaces();
      $variable{error} .= 'There are no interfaces to wake on<br/>' if ! @Interfaces;
      foreach my $I ( $Host->Interfaces() ) {
        if (! $I->mac() ) {
          $variable{information} .= 'Not waking by '.$I->ip().' because no mac address<br/>';
          next;
        }
				my ( $error, $info ) = $I->wake();
				$variable{error} .= $error;
				$variable{information} .= $info;
			} # end foreach
      $variable{ExternalRedirect} = $Host->url_to();
    } elsif ( $param{action} eq 'GEOLookup' ) {
      foreach my $I ( $Host->Interfaces() ) {
        if ( ! $I->ip() ) {
          $variable{error} .= "Interface $$I{mac} does not have an ip.<br/>";
        } else {
          my $Location = openprint::Location::from_ip( $I->ip() );
          if ( ! $Location ) {
            $variable{error} .= 'No Location found from ip.';
          } else {
            $$Host{location_id} = $Location->id();
          } # end if
        } # end if
      } # end foreach I
      
    } elsif ( $param{action} eq 'Save' ) {
      delete $param{$param{type_id} ? 'type' : 'type_id'};
      delete $param{$param{manufacturer_id} ? 'manufacturer' : 'manufacturer_id'};
      my $Location = openprint::Location::save_location( \%param );
      $param{location_id} = $Location->id() if $Location and $Location->id();
      my @changes = $Host->changes(\%param);

      $variable{error} .= $Host->save(\%param) if @changes;
      foreach my $I ( $Host->Interfaces(), new openprint::Host_Interface() ) {
        $$I{id} = '' if ! $$I{id};
        if ( $param{"mac-$$I{id}"} or $param{"ip-$$I{id}"} or $param{"comment-$$I{id}"} ) {
          if ( ref $param{"mac-$$I{id}"} eq 'ARRAY' ) {
            while (@{$param{"mac-$$I{id}"}}) {
              $log->debug("hello". @{$param{"mac-$$I{id}"}});
              my %c = map { $_=>exists($param{"$_-$$I{id}"}) ? shift @{$param{"$_-$$I{id}"}} : $openprint::Host_Interface::defaults{$_} } ( 'mac', 'ip', 'dhcp', 'monitor', 'comment' );
              $openprint::log->debug( Data::Dumper::Dumper( \%c ) );
              $c{host_id} = $$Host{id};
              $log->debug("hello");
              $variable{error} .= $I->save(\%c);
              $log->debug("hello");
              push @changes, 'Interface added: ' . $I->to_string() . '<br/>' if ! $variable{error};
              $log->debug("hello" . @{$param{"mac-$$I{id}"}});
            } # end while
          } else {
            my %c = map { $_ => exists($param{"$_-$$I{id}"}) ? $param{"$_-$$I{id}"} : $openprint::Host_Interface::defaults{$_} } ( 'mac', 'ip', 'dhcp', 'monitor', 'comment' );
            my @c = $I->changes(\%c);
            if ( @c ) {
              $c{host_id} = $$Host{id};
              $variable{error} .= $I->save(\%c);
              push @changes, 'Interface changed: ' . join(',', @c ) . '<br/>' if ! $variable{error};
            }
          } # end if multiple new interfaces to add
        } else {
          $variable{error} .= $I->delete() if $$I{id};
        } # end if
      } # end foreach Interface

      if ($param{notification_ids}) {
        my %notifications = map { $$_{user_id}, $_ } $Host->Notifications();

        foreach my $user_id (sets::union(split(',', $param{notification_ids}))) {
          if ($notifications{$user_id}) {
            delete $notifications{$user_id};
            next;
          }
          my $Notification = new openprint::Host_Notification();
          $variable{error} .= $Notification->save({host_id=>$$Host{id}, user_id=>$user_id});
        }
        foreach my $Notification ( values %notifications ) {
          $variable{error} .= $Notification->delete();
        }
        $Host->Notifications(undef);
      }
      
      if (!$variable{error}) {
        (new openprint::Log())->save({Object=>$Host, action=>'Edit', note=>join('<br/>', @changes) }) if @changes;
        $variable{ExternalRedirect} = '/employee/it/hosts.html';
        return;
      } else {
        $openprint::log->error($variable{error});
      } # end if
      %param = ();
    } elsif ( $param{action} eq 'ping' ) {
      if ( $Host->ping() ) {
        $variable{information} .= 'Host is alive.';
      } else {
        $variable{information} .= 'Host did not respond to ping.';
      } # end if	
      $variable{ExternalRedirect} = $Host->url();
    } elsif ( $param{action} eq 'Upload' ) {
      $param{mac} = [ map { split( ',', $_ ) } split("\n", $param{mac}) ];
      if ( $param{type_id} ) {
        delete $param{type};
      } else {
        delete $param{type_id};
      } # end if
      $variable{error} .= $Host->save(\%param);
      my $Asset = openprint::Asset::upload( 'filename' );
      if ( ref $Asset ne 'openprint::Asset' ) {
        $variable{error} .= $Asset;
      } else {
        my $Object_Asset = new openprint::Object_Asset();
        $variable{error} .= $Object_Asset->save({
            asset_id	=>	$Asset->id(),
            object_id	=>	$Host->id(),
            object_type	=>	'openprint::Host',
            });
        if ( $param{asset_name} and ! $Asset->name() ) {
          $Asset->save({'name'=>$param{asset_name}});
        } # end if
      } # end if
    } # end if
	} # end if param{action}

	if ( ( ! $Host->id() ) and ( $param{ip} or $param{mac} or $param{hostname} ) ) {
		my $I = new openprint::Host_Interface();
		$I->set({ ip=>$param{ip}, mac=>$param{mac} });
		$Host->Interfaces( [ $I ] );
		$Host->hostname( $param{hostname} );
		if ( $I->ip() ) {
			if ( ! $I->mac() ) {
				$I->mac( [ $I->get_mac() ] );
			} # end if
			if ( ! $Host->hostname() ) {
				$Host->hostname( $Host->resolve() );
			} # end if
		} # end if
	} # end if
	ssi::setup_date_select( '/employee/it/host.html', 'log_created_on_start', 0 );
	ssi::setup_date_select( '/employee/it/host.html', 'log_created_on_end', '' );
	if ( $config{'RADIUS_Support'} and ($config{'RADIUS_Support'} eq 'Y') ) {
    require openprint::RADIUS_Check;
    require openprint::RADIUS_Reply;
		$openprint::RADIUS_Reply::dbh = $openprint::RADIUS_Check::dbh = sql::open_sql( $log,
				'database'  => $config{RADIUS_DB_Name},
				'driver'    => $config{RADIUS_DB_Driver},
				'host'      => $config{RADIUS_DB_Server},
				'login'     => $config{RADIUS_DB_Username},
				'password'  => $config{RADIUS_DB_Password},
				);
		if ( ! $openprint::RADIUS_Check::dbh ) {
			$variable{error} .= 'Unable to connect to RADIUS DB server.';
			return;
		} # end if
  } # end if

} # end sub view_host

sub network {
	my $Host = $variable{Host} = new openprint::Host( $param{host_id} );
  if ( $param{action} ) {
    if ( $param{action} eq 'Delete' ) {
      $variable{error} .= $Host->delete();
      if ( ! $variable{error} ) {
        $variable{ExternalRedirect} = '/employee/it/networks.html';
        return;
      } # end if
      %param = ();
    } elsif ( $param{action} eq 'Undelete' ) {
      $variable{error} .= $Host->undelete();
      if ( ! $variable{error} ) {
        $variable{ExternalRedirect} = '/employee/it/networks.html';
        return;
      } # end if
      %param = ();
    } elsif ( $param{action} eq 'Destroy' ) {
      $variable{error} .= $Host->destroy();
      if ( ! $variable{error} ) {
        $variable{ExternalRedirect} = '/employee/it/networks.html';
        return;
      } # end if
      %param = ();
    } elsif ( $param{action} eq 'Save' ) {
      my @changes = $Host->changes(\%param);

      $variable{error} .= $Host->save(\%param) if @changes;
      foreach my $I ( $Host->Interfaces(), new openprint::Host_Interface() ) {
        if ( $param{"ip-$$I{id}"} or $param{"comment-$$I{id}"} ) {
          my %c = map { $_, $param{"$_-$$I{id}"} } ( 'ip', 'monitor', 'comment' );
          my @c = $I->changes( \%c );
          if ( @c ) {
            $c{host_id} = $$Host{id};
            $variable{error} .= $I->save(\%c);
            push @changes, 'Interface changed: ' . join(',', @c ) . '<br/>' if ! $variable{error};
          }
        } else {
          $variable{error} .= $I->delete() if $$I{id};
        } # end if
      } # end foreach Interface

      my %notifications = map { $$_{user_id}, $_ } $Host->Notifications();

      foreach my $user_id ( sets::union(split(',',$param{notification_ids})) ) {
        if ( $notifications{$user_id} ) {
          delete $notifications{$user_id};
          next;
        }
        my $Notification = new openprint::Host_Notification();
        $variable{error} .= $Notification->save({host_id=>$$Host{id}, user_id=>$user_id});
      }
      foreach my $Notification ( values %notifications ) {
        $variable{error} .= $Notification->delete();
      }
      $Host->Notifications(undef);
      
      if ( ! $variable{error} ) {
        (new openprint::Log())->save({Object=>$Host, action=>'Edit', note=>join('<br/>', @changes) });
        $variable{ExternalRedirect} = '/employee/it/networks.html';
        return;
      } # end if
      %param = ();
    } # end if
	} # end if param{action}

	if ( ( ! $Host->id() ) and ( $param{ip} or $param{hostname} ) ) {
		my $I = new openprint::Host_Interface();
		$I->set({ ip=>$param{ip} });
		$Host->Interfaces( [ $I ] );
		$Host->hostname( $param{hostname} );
		if ( $I->ip() ) {
			if ( ! $Host->hostname() ) {
				$Host->hostname( $Host->resolve() );
			} # end if
		} # end if
	} # end if
	ssi::setup_date_select( '/employee/it/network.html', 'log_created_on_start', 0 );
	ssi::setup_date_select( '/employee/it/network.html', 'log_created_on_end', '' );
  $variable{uri} = '/employee/it/network.html';
} # end sub network

sub camera {
} # end sub camera

sub cameras {
} # end sub cameras

sub camera_viewer {
} # end sub camera_viewer

sub _cameras_viewing {
	if ( $param{camera_id} ) {
		$session{cameras_viewing} = join(',', sets::union( split( ',', $session{cameras_viewing} ), $param{camera_id} ) );
	} # end if
} # end sub _cameras_viewing
sub _cameras_available {
	if ( $param{camera_id} ) {
		$session{cameras_viewing} = join(',', sets::exclude( [ $param{camera_id} ], [ split( ',', $session{cameras_viewing} ) ] ) );
	} # end if
} # end sub _cameras_available
sub _camera { # .json 
	$session{'/employee/it/camera_viewer.html?monitor_size-'.$param{monitor_id}} = join('x', @param{'width','height'} );
}

sub _radius_mac_line {
	if ( $config{RADIUS_Support} ne 'Y' ) {
		$variable{error} .= 'RADIUS Support is not enabled.';
		return;
	} # end if
    require openprint::RADIUS_Check;
    require openprint::RADIUS_Reply;
	$openprint::RADIUS_Reply::dbh = $openprint::RADIUS_Check::dbh = sql::open_sql( $log,
			'database'  => $config{RADIUS_DB_Name},
			'driver'    => $config{RADIUS_DB_Driver},
			'host'      => $config{RADIUS_DB_Server},
			'login'     => $config{RADIUS_DB_Username},
			'password'  => $config{RADIUS_DB_Password},
			);
	if ( ! $openprint::RADIUS_Check::dbh ) {
		$variable{error} .= 'Unable to connect to RADIUS DB server.';
		return;
	} # end if
	if ( $param{action} eq 'add' ) {
		if ( $param{username} =~ /^([[:xdigit:]]{2})[\:\-]?([[:xdigit:]]{2})[\:\-]?([[:xdigit:]]{2})[\:\-]?([[:xdigit:]]{2})[\:\-]?([[:xdigit:]]{2})[\:\-]?([[:xdigit:]]{2})$/ ) {
			# Convert from alternate mac formats
			$param{username} = "$1-$2-$3-$4-$5-$6";
		} else {
			$log->warn("Re didn't match $param{username}");
		} # end if
		if ( $param{attribute} eq 'Cleartext-Password' ) {
			if ( ! $param{value} ) {
			$param{value} = $param{username};
			}
		} elsif ( $param{attribute} eq 'Framed-IP-Address' ) {
			if ( ! $param{value} ) {
				my $Host = openprint::Host->find_one('mac any'=>$param{username});
				if ( $Host ) {
					$param{value} = $Host->ip();
				} # end if
			} # end if
		} # end if

		my $Radius;
		if ( $openprint::RADIUS_Check::attributes{$param{attribute}} ) {
			$Radius = new openprint::RADIUS_Check();
		} elsif ( $openprint::RADIUS_Reply::attributes{$param{attribute}} ) {
			$Radius = new openprint::RADIUS_Reply();
		} else {
			$log->error("Unknown RADIUS Attribute: $param{attribute}");
			$variable{error} .= "Unknown RADIUS Attribute: $param{attribute}<br/>";
			return;
		} # end if
		$variable{error} .= $Radius->save({
			username	=>	$param{username},
			value		=>	$param{value},
			op			=>	':=',
			attribute	=>	$param{attribute},
		});
	} elsif ( $param{action} eq 'remove' ) {
		my $Radius;
		if ( $openprint::RADIUS_Check::attributes{$param{attribute}} ) {
			$Radius = openprint::RADIUS_Check->find_one( username=>$param{username}, attribute=>$param{attribute} );
			$Radius = openprint::RADIUS_Reply->find_one( username=>$param{username}, attribute=>$param{attribute} ) if ! $Radius;
		} elsif ( $openprint::RADIUS_Reply::attributes{$param{attribute}} ) {
			$Radius = openprint::RADIUS_Reply->find_one( username=>$param{username}, attribute=>$param{attribute} );
			$Radius = openprint::RADIUS_Check->find_one( username=>$param{username}, attribute=>$param{attribute} ) if ! $Radius;
		} else {
			$log->error("Unknown RADIUS Attribute: $param{attribute}");
			$variable{error} .= "Unknown RADIUS Attribute: $param{attribute}<br/>";
			return;
		} # end if
		if ( ! $Radius ) {
			$variable{error} .= 'Radius entry for  username=>$param{username}, attribute=>$param{attribute} is not found.<br/>';
		} else {
			$variable{error} .= $Radius->delete() if $Radius->id();
		} # end if
	} # end if
	$variable{username} = $param{username};
	$variable{username} =~ s/[^[[:xdigit:]]]//g;
} # end sub _radius_mac_line

sub radius {
	_radius();
} # end sub radius

sub _radius {
    require openprint::RADIUS_Check;
    require openprint::RADIUS_Reply;
	if ( $config{'RADIUS_Support'} eq 'Y' and ( ! $openprint::RADIUS_Check::dbh ) ) {
		$openprint::RADIUS_Reply::dbh = $openprint::RADIUS_Check::dbh = sql::open_sql( $log,
				'database'  => $config{RADIUS_DB_Name},
				'driver'    => $config{RADIUS_DB_Driver},
				'host'      => $config{RADIUS_DB_Server},
				'login'     => $config{RADIUS_DB_Username},
				'password'  => $config{RADIUS_DB_Password},
				);
		if ( ! $openprint::RADIUS_Check::dbh ) {
			$variable{error} .= 'Unable to connect to RADIUS DB server.';
			return;
		} # end if
	} # end if
	if ( $param{action} eq 'Delete' ) {
		foreach my $id ( ref $param{record_id} eq 'ARRAY' ? @{$param{record_id}} : $param{record_id} ) {
			my $Record = new openprint::RADIUS_Check( $id );
			$variable{error} .= $Record->delete();
		} # end foreach host_id
	} # end if
	ssi::save_params( '/employee/it/radius.html', 
			'attribute','username'
			);
} # end sub _radius

sub _host_logs {
	$variable{Host} = new openprint::Host( $param{host_id} );
	ssi::save_params( '/employee/it/host.html', 
			( map { 'log_created_on_start_'.$_ } ( 'year', 'month','day','hour','minute' ) ),
			( map { 'log_created_on_end_'.$_ } ( 'year', 'month','day','hour','minute' ) ),
	);
} # end sub _host_logs

sub sessions {
	_sessions();
	$session{'/employee/it/sessions.html?company_id'} = $session{company_id} if ! exists $session{'/employee/it/sessions.html?company_id'};
} # end sub sessions

sub _sessions {
	if ( $param{action} eq 'Delete' ) {
		foreach my $session_id ( ref $param{session_id} eq 'ARRAY' ? @{$param{session_id}} : $param{session_id} ) {
			next if ! $session_id;
			sql::execute(undef,undef,'DELETE FROM sessions WHERE id=?', $session_id );
		} # end foreach
	} # end if
	ssi::save_params( '/employee/it/sessions.html', 
			'created_on_start_year', 'created_on_start_month','created_on_start_day',
			'created_on_end_year', 'created_on_end_month','created_on_end_day',
			'updated_on_start_year', 'updated_on_start_month','updated_on_start_day',
			'updated_on_end_year', 'updated_on_end_month','updated_on_end_day',
			'company_id','user_type','user_id','ip',
	);
} # end sub _sessions

sub session {
} # end sub session

sub _notifications {
	my $Host = $variable{Host} = new openprint::Host( $param{host_id} );

	if ( $param{action} eq 'add' ) {

    if ( $$Host{id} ) {
      my $Notification = new openprint::Host_Notification();
      $variable{error} .= $Notification->save({
          user_id	=>	$param{user_id},
          host_id	=>	$$Host{id},
        });
    } else {
      my @Notifications;
      foreach my $user_id ( split(',',$param{notification_ids} ) ) {
        my $Notification = new openprint::Host_Notification();
        $Notification->set({
            user_id	=>	$user_id,
          });

        push @Notifications, $Notification;
      } # end foreach user_id
      $Host->Notifications( \@Notifications );
    }
      
	} elsif ( $param{action} eq 'delete' ) {
    if ( $$Host{id} ) {
      my $Notification = openprint::Host_Notification->find_one(
        user_id	=>	$param{user_id},
        host_id	=>	$$Host{id},
        );
      if ( ! $Notification ) {
        $variable{error} .= 'Notification not found.';
      } else {
        $variable{error} .= $Notification->delete();
        delete $$Host{Notifications};
      } # end if
    } else {
      my @Notifications;
      foreach my $user_id ( split(',',$param{notification_ids} ) ) {
        next if $user_id == $param{user_id};
        my $Notification = new openprint::Host_Notification();
        $Notification->set({
            user_id	=>	$user_id,
          });

        push @Notifications, $Notification;
      } # end foreach user_id
      $Host->Notifications( \@Notifications );
		} # end if
	} # end if
} # end sub _notifications

sub _assets {
	my $Host = $variable{Host} = new openprint::Host( $param{host_id} );
	if ( $param{action} eq 'delete' ) {
		my $Object_Asset = openprint::Object_Asset->find_one('asset_id'=>$param{asset_id}, 'object_type'=>'openprint::Host','object_id'=>$Host->id());
		if ( ! $Object_Asset ) {
			$variable{error} .= 'Object Asset not found.';
			return;
		} # end if
		$variable{error} .= $Object_Asset->delete();
	} # end if
} # end sub _assets

sub licenses {
	_licenses();
	ssi::setup_date_select( '/employee/it/licenses.html', 'created_on_start', '' );
	ssi::setup_date_select( '/employee/it/licensess.html', 'created_on_end', '' );
	ssi::setup_date_select( '/employee/it/licenses.html', 'updated_on_start', '' );
	ssi::setup_date_select( '/employee/it/licenses.html', 'updated_on_end', '' );
} # end sub licenses

sub _licenses {
require openprint::License;
  if ($param{action}) {
    if ( $param{action} eq 'Delete' ) {
      foreach my $license_id ( ref $param{'license_id[]'} eq 'ARRAY' ? @{$param{'license_id[]'}} : $param{'license_id[]'} ) {
        my $License = new openprint::License( $license_id );
        $variable{error} .= $License->delete();
      } # end foreach license_id
      %param = ();
    } else {
      $log->error("Unknown action $param{action}");
    } # end if
	} # end if
	ssi::save_params( '/employee/it/licenses.html', 
	( map { 'created_on_start_' . $_ } ( 'year', 'month', 'day' ) ),
	( map { 'created_on_end_' . $_ } ( 'year', 'month', 'day' ) ),
	( map { 'updated_on_start_' . $_ } ( 'year', 'month', 'day' ) ),
	( map { 'updated_on_end_' . $_ } ( 'year', 'month', 'day' ) ),
	( map { 'purchased_on_start_' . $_ } ( 'year', 'month', 'day' ) ),
	( map { 'purchased_on_end_' . $_ } ( 'year', 'month', 'day' ) ),
	( map { 'expires_on_start_' . $_ } ( 'year', 'month', 'day' ) ),
	( map { 'expires_on_end_' . $_ } ( 'year', 'month', 'day' ) ),
			'ip', 'hostname', 'mac', 'software_id', 'serialkey',
			'order',
			);
} # end sub _licenses

sub license {
require openprint::License;
	my $License = $variable{License} = new openprint::License( openprint::License->transform('id',$param{license_id}) );
	if ( $param{action} eq 'Delete' ) {
		$variable{error} .= $License->delete();
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/employee/it/licenses.html';
			%param = ();
		} # end if
	} elsif ( $param{action} eq 'Save' ) {
		my $License = new openprint::License( $param{license_id} );
		if ( $_ = openprint::License->find_one(serialkey=>$param{serialkey}, ( $param{license_id} ? ('id !=' => $param{license_id}) : () ) ) ) {
			$variable{error} .= 'License has already been entered.  Click <a href="license.html?license_id='.$_->id().'">here</a> to view it.<br/>';
			return;
		} # end if
		if ( $param{software_id} ) {
			delete $param{software};
		} else {
			delete $param{software_id};
		} # end if
		$variable{error} .= $License->save(\%param);
		if ( ! $variable{error} ) {
			%param = ();
			$variable{ExternalRedirect} = '/employee/it/licenses.html';
		} # end if
	} # end if
} # end sub license

sub _license_host_popup {
require openprint::License;
	my $License = $variable{License} = new openprint::License($param{license_id});
	if ( ! $License->id() ) {
		$variable{error} .= 'License not found.';
		return;
	} # end if
} # end sub _license_host_popup

sub _license_host_results {
require openprint::License;
	my $License = $variable{License} = new openprint::License($param{license_id});
	if ( ! $License->id() ) {
		$variable{error} .= 'License not found.';
		return;
	} # end if
} # end sub _license_host_results

sub _license_allocations {
require openprint::License;
	my $License = $variable{License} = new openprint::License($param{license_id});
	if ( ! $License->id() ) {
		$variable{error} .= 'License not found.';
		return;
	} # end if
	if ( $param{action} eq 'allocate' ) {
		my $Host = new openprint::Host($param{host_id});
		if ( ! $Host->id() ) {
			$variable{error} .= 'Host not found.';
			return;
		} # end if
		
		my $LH = new openprint::License_Host();
		$variable{error} .= $LH->save({license_id=>$param{license_id}, host_id=>$param{host_id}});
	} elsif ( $param{action} eq 'delete' ) {
		my $LH = openprint::License_Host->find_one( license_id=>$param{license_id}, host_id=>$param{host_id} );
		if ( ! $LH ) {
			$variable{error} .= 'Allocation not found.';
			return;
		} 
		$variable{error} .= $LH->delete();
	} # end if	
} # end sub _license_alliations

sub _information {
	my $Host = $variable{Host} = new openprint::Host( $param{host_id} );
	if ( ! $Host->id() ) {
		$variable{error} .= "Host not found: id=>$param{host_id}<br/>";
		return;
	} # end if
  require openprint::Host_Info;

	if ( $param{action} eq 'add' ) {
		my $Info = new openprint::Host_Info();
		$variable{error} .= $Info->save({
				host_id	=>	$param{host_id},
				name	=>	$param{name},
				value	=>	$param{value}, 
			});
	} elsif ( $param{action} eq 'delete' ) {
		my $Info = new openprint::Host_Info( $param{info_id} );
		$variable{error} .= $Info->delete();
	} # end if
		
} # end sub _information
sub _host_actions {
} # end sub _host_actions

sub backups {
  _backups();
  my $uri = $r->uri();
  ssi::setup_date_select( $uri, 'created_on_start', '' );
  ssi::setup_date_select( $uri, 'created_on_end', '' );
  ssi::setup_date_select( $uri, 'updated_on_start', '' );
  ssi::setup_date_select( $uri, 'updated_on_end', '' );
}

sub _backups {
  require openprint::Backup;
  if ( $param{action} ) {
    if ( $param{action} eq 'Delete' ) {
      foreach my $id ( ref $param{backup_id} eq 'ARRAY' ? @{$param{backup_id}} : $param{backup_id} ) {
        my $Backup = new openprint::Backup( $id );
        $variable{error} .= $Backup->delete();
      } # end foreach id
      %param = ();
    } # end if
  } # end if
  ssi::save_params( '/employee/it/backups.html',
      'created_on_start_year', 'created_on_start_month', 'created_on_start_day',
      'created_on_end_year', 'created_on_end_month', 'created_on_end_day',
      'updated_on_start_year', 'updated_on_start_month', 'updated_on_start_day',
      'updated_on_end_year', 'updated_on_end_month', 'updated_on_end_day',
      'enabled',
      'name','type',
      'order', 'deleted', 'owner_id',
      );
}

sub backup {
  require openprint::Backup;
  my $Backup = $variable{Backup} = new openprint::Backup( $param{backup_id} );
  if ( $param{action} ) {
    if ( $param{action} eq 'Delete' ) {
      $variable{error} .= $Backup->delete();
      if ( ! $variable{error} ) {
        $variable{ExternalRedirect} = '/employee/it/backups.html';
        return;
      } # end if
      %param = ();
    } elsif ( $param{action} eq 'Destroy' ) {
      $variable{error} .= $Backup->destroy();
      if ( ! $variable{error} ) {
        $variable{ExternalRedirect} = '/employee/it/backups.html';
        return;
      } # end if
      %param = ();
    } elsif ( $param{action} eq 'Run' ) {
      $variable{information} .= $Backup->run(); 
      $variable{ExternalRedirect} = '/employee/it/backup.html?backup_id='.$Backup->id();
    } elsif ( $param{action} eq 'Save' ) {
      my @changes = $Backup->changes(\%param);
      $variable{error} .= $Backup->save(\%param) if @changes;

      if ( ! $variable{error} ) {
        (new openprint::Log())->save({Object=>$Backup, action=>'Edit', note=>join('<br/>', @changes) });
        $variable{ExternalRedirect} = '/employee/it/backups.html';
        return;
      } # end if
      %param = ();
    }
  }
  if ( ! $$Backup{id} ) {
    # set defaults
    $$Backup{owner_id} = $$openprint::Owner{id};
  }

}
sub syslog {
  _syslog();
  my $uri = $r->uri();
  ssi::setup_datetime_select( $uri, 'receivedat_start', -3600 );
  ssi::setup_datetime_select( $uri, 'receivedat_end', '' );
  ssi::setup_datetime_select( $uri, 'devicereportedtime_start', '' );
  ssi::setup_datetime_select( $uri, 'devicereportedtime_end', '' );
}
sub _syslog {
	my $uri = '/employee/it/syslog.html';

	ssi::save_params( $uri,
		 ( map { 'receivedat_start_'.$_ } ( 'year','month','day','hour','minute' ) ),
		 ( map { 'receivedat_end_'.$_ } ( 'year','month','day','hour','minute' ) ),
		 ( map { 'devicereportedtime_start_'.$_ } ( 'year','month','day','hour','minute' ) ),
		 ( map { 'devicereportedtime_end_'.$_ } ( 'year','month','day','hour','minute' ) ),
		'priority','facility','fromhost','syslogtag','message',
		 );
}

sub is_ipv4 {
  $_[0] =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/;
}
sub is_ipv6 {
  $_[0] =~ /:/;
}
sub is_mac {
  $_[0] =~ /^[:0-9A-F]{17}$/;
}

sub _subnet {
  if ( $param{action} ) {
    if ( $param{action} eq 'add subnet' ) {
      my $I = $variable{Interface} = new openprint::Host_Interface();
      $$I{host_id} = $param{host_id};
    }
  }
}

sub _interface {
  if ( $param{action} ) {
    if ( $param{action} eq 'add interface' ) {
      my $I = $variable{Interface} = new openprint::Host_Interface();
      $$I{host_id} = $param{host_id};
      $I->save();
    } elsif ($param{action} eq 'dhcp' ) {
      if ( ! $param{mac} ) {
        $openprint::log->error('Need mac when doing dhcp update');
        return;
      }

      my @HIs = openprint::Host_Interface->find(mac=>$param{mac});
      if ( ! @HIs ) {
        my $Host = new openprint::Host();
        $Host->save({ hostname=>($param{hostname} ? $param{hostname} : $param{mac} ) } );
        my $Interface = new openprint::Host_Interface();
        $Interface->save({ ip=>$param{ip}, mac => $param{mac}, host_id=>$$Host{id}, dhcp=>1 });
        @HIs = ( $Interface );
      } else {
        foreach my $Interface (@HIs) {
          my $Host = $Interface->Host();
          if ( 
            (!$$Interface{ip}) or (
              (
                (is_ipv4($Interface->ip()) and is_ipv4($param{ip}))
                  or
                (is_ipv6($Interface->ip()) and is_ipv6($param{ip}))
              )
                and ( $Interface->ip() ne $param{ip} )
            )
          ) {
            (new openprint::Log())->save( {
                Object  =>  $Host,
                note    =>  'IP Address changed from '.(defined($$Interface{ip})?$$Interface{ip}:'undef').' to '.$param{ip},
                action  =>  'IP Changed',
              } );
            $Interface->save({ip=>$param{ip}});
          } else {
            $log->debug("Not updating HI from $$Interface{ip} to $param{ip} because is_ipv($$Interface{ip})=".is_ipv4($Interface->ip())." is_ipv4($param{ip})=".is_ipv4($param{ip}));
          }
          if ( $param{hostname} and is_mac($Host->hostname()) ) {
            (new openprint::Log())->save( { Object => $Host, note=>"Name changed from $$Host{hostname} to $param{hostname}", action=>'Changed' } );
            $Host->save({hostname=>$param{hostname}});
          } else {
            $log->debug("Not updating hostname from $$Host{hostname} to $param{hostname}");
            $Host->save(); # To update updated_on
          }
        } # end foreach HI
      } # end if @His
      foreach my $I ( openprint::Host_Interface->find( 'mac !='=>$param{mac}, ip=>$param{ip} ) ) {
        (new openprint::Log())->save({
            Object => $I->Host(),
            note   =>'IP Address '.$I->ip().' removed because it is taken by host ' . $HIs[0]->Host()->link_to(),
            action =>'IP Changed',
          });
        $I->save({ip=>undef});
      } # end foreach I

      $variable{PageContent} = "{result:'ok'}";
    } #endif action
  } # end if action
}

sub _backup_files {
  my $Backup = $variable{Backup} = new openprint::Backup($param{backup_id});
  if ( $param{file} ) {
    $r->headers_out->{'Content-Disposition'} = "attachment; filename=\"$param{file}\"";
    $r->content_type("application/octet-stream; name=\"$param{file}\"");
    $r->sendfile(join('/', $Backup->dest_path(), $param{path}, $param{file}));
    return;
  }
}

1;
__END__
