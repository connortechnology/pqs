use strict;
use warnings;
require openprint::Object;
require openprint::Host;
#use Data::Dumper;

package openprint::Host_Interface;
our @ISA = qw( openprint::Object );
use vars qw( $debug $table $serial %find_fields %fields %transforms %defaults $cache_field );
$debug = 0;
$serial = 'host_interfaces_id_seq';
$table = 'host_interfaces';

$cache_field = 'ip';
sub cache_field {
  return $cache_field;
}

%fields = (
	id						=>	'id',
	mac						=>	'mac',
	ip						=>	'ip',
	comment				=>	'comment',
	dhcp					=>	'dhcp',
  host_id       =>  'host_id',
  connected_to  =>  'connected_to',
	monitor				=>	'monitor',
	online				=>	'online',
);

%transforms = (
	mac           	=> [ 's/[^\da-fA-F:\-]//g' ],
	connected_to  	=> [ 's/[^\da-fA-F:\-]//g' ],
	ip            	=> [ 's/[^\d\.\:a-fA-F\/]//g' ],
);

%find_fields = (
	whitelist	=>	'(SELECT whitelist FROM Hosts WHERE Hosts.id=host_id)',
);
%defaults	= (
	dhcp	  	=>	0,
	ip		  	=>	undef,
	mac		  	=>	undef,
  connected_to  =>  undef,
	monitor		=>	0,
	online		=>	undef,
);
my %macBases;

sub Host {
  if ( ! $_[0]{Host} ) {
    $_[0]{Host} = new openprint::Host( $_[0]{host_id} );
  }
  return $_[0]{Host};
} # end sub Host;

sub resolve {
	my ( $self ) = @_;
	my @h = gethostbyaddr(pack('C4',split('\.',$$self{ip})),2);
	if ( @h ) {
		return $h[0];
	} elsif ( $debug ) {
		$openprint::log->warn("Unable to reverse DNS $$self{ip}");
	} # end if
	return undef;
} # end sub resolve

sub get_mac {
	my ( $self ) = @_;

	my ( $subnet ) = $$self{ip} =~ /^(\d+\.\d+\.\d+)\.\d+$/;

	my $use_iface;

	require IO::Interface::Simple;
	foreach my $iface ( IO::Interface::Simple->interfaces ) {
$openprint::log->debug("Looking at $iface. " . $iface->address . ', subnet: ' . $subnet );
		if ( $iface->address =~ /^$subnet\.\d+$/ ) {
			$use_iface = $iface;
$openprint::log->debug("Using $iface. " . $iface->address . ', subnet: ' . $subnet );
		} # end if
	}

	if ( $use_iface ) {
		require Net::ARP;
		my $mac = Net::ARP::arp_lookup( $use_iface, $$self{ip} );
		$openprint::log->debug("Mac: $mac");
		return $mac;
	} else {
		$openprint::log->debug("Unable to determine interface");
	} # end if
  return undef;
} # end sub get_mac

sub authenticate {
  my ( $HI, $browser, $response, $method, $port, $url, $args ) = @_;
  my $headers = $response->headers();
  if ( $$headers{'www-authenticate'} ) {
    $openprint::log->debug("Having authenticate $$headers{'www-authenticate'}");

    my ( $auth, $tokens ) = $$headers{'www-authenticate'} =~ /^(\w+)\s+(.*)$/;
    my %tokens = map { /(\w+)="?([^"]+)"?/i } split(', ', $tokens );
    if ( $tokens{realm} ) {
      my $Host = $HI->Host();
      my $username = $Host->info('username');
      my $password = $Host->info('password');
      $openprint::log->debug("tokens: $tokens realm: $tokens{realm} username: $username password: $password args: ".
        ($args ? join(',',map { $_.'=>'.$$args{$_} } keys %{$args}) :'none'));
      $browser->credentials(
        $HI->ip().':'.$port,
        $tokens{realm},
        ($username ? $username : ''), 
        ($password ? $password : ''),
      );
      $response = $browser->get($url);
      $openprint::log->debug("Auth response for get $url $tokens{realm}, $username, $password ".$response->is_success);

      #if ( $response->is_success and ( ($method ne 'get') or $args ) ) {
      #$openprint::log->debug('Sending actual url '.$method . ' ' . $url);
      #$response = $browser->$method($url, ($args and %{$args}) ? $args : () );
      #}
    } else {
      $openprint::log->error('No realm');
    } # end if
  } else {
    foreach my $k ( keys %{$headers} ) {
      $openprint::log->debug("No auth Header $k => $$headers{$k}");
    }
    my $Host = $HI->Host();
    my $username = $Host->info('username');
    my $password = $Host->info('password');
    $openprint::log->debug("username: $username password: $password args: " . ($args ? join(',',map { "$_=>$$args{$_}" } keys %{$args}) :'none'));
    $browser->credentials(
      $HI->ip().':'.$port,
      '',
      ($username ? $username : ''),
      ($password ? $password : ''),
    );

    $response = $browser->$method( $url, $args ? $args : () );
    $openprint::log->debug("Auth response for $method $url $username, $password ".$response->is_success);
  }
  return $response;
} # end sub authenticate

sub vendor {
  if ( !$_[0]{vendor} ) {
    if ( $_[0]{mac} ) {
      require openprint::OUI_Vendor;
      my $oui = $_[0]{mac};
      $oui =~ s/[^A-Fa-f0-9]//g;
      $oui =~ s/^([A-Fa-f0-9]{6}).*$/${1}000000/;
      if ( ! $oui ) {
        $openprint::log->error("Got no oui from $oui $_[0]{mac}");
        return;
      }

      if ( my $Vendor = openprint::OUI_Vendor->find_one(oui=>$oui) ) {
        $_[0]{vendor} = $$Vendor{vendor_name};
      } elsif (-e '/usr/share/arp-scan/ieee-oui.txt') {
        if (!%macBases) {
          my $oui_txt = misc::load_file($openprint::log, '/usr/share/arp-scan/ieee-oui.txt');
          if (!$oui_txt) {
            $openprint::log->error('No content from /usr/share/arp-scan/ieee-oui.txt');
          } else {
            foreach my $line (split("\n",  $oui_txt)) {
              next if $line =~ /#/;
              my ($mac, $vendor) = split("\t", $line);
              next if !$mac;
              $mac = lc $mac;
              my $type = $vendor;
              $type =~ s/\W//g;
              $macBases{$mac} = { vendor=>$type, type=>$type} if !$macBases{$mac};
            } # end foreach line
          } # end if out_txt
        } # end if ! macBases
      } else {

        eval {
          require Net::MAC::Vendor;
          my $vendor = Net::MAC::Vendor::lookup($_[0]{mac});
          #$_ = Data::Dumper::Dumper($vendor);
          if ( $vendor and @{$vendor} ) {

            $_[0]{vendor} = shift @{$vendor};

            my $Vendor = new openprint::OUI_Vendor();
              $Vendor->save({ oui=>$oui, vendor_name=>$_[0]{vendor} });
            }
          };
        }
        $openprint::log->error("Error in eval: $@") if $@;
        return $_[0]{vendor};
      }
    return '';
  }
  return $_[0]{vendor};
}

sub is_subnet {
  return ( index($_[0]{ip}, '/') == -1 ) ? 0 : 1;
}

sub wake {
	my $error;
	my $info;

	my $I = shift;

	if ( $I->ip() ) {
		$_ = `wakeonlan -i $$I{ip} $$I{mac} 2>&1`;
		if ( defined $_ ) {
			$info = "running wakeonlan -i $$I{ip} $$I{mac}<br/>Output: $_<br/>";
		} else {
			$error .= "Error running wakeonlan -i $$I{ip} $$I{mac}<br/>";
		}
	} # end if ip
	$_ = `wakeonlan $$I{mac} 2>&1`;
	if ( defined $_ ) {
		$info .= "running wakeonlan -i $$I{ip} $$I{mac}<br/>Output: $_<br/>";
	} else {
		$error .= "Error running wakeonlan -i $$I{ip} $$I{mac}<br/>";
	}
	return ($error, $info );
}

sub ipv6_link_local {
  return '' if ! $_[0]{mac};
  my @segments = split(/:/, $_[0]{mac});
  $segments[0] = hex($segments[0]);
  $segments[0] ^= 2;
  return 'fe80::'.sprintf('%x',$segments[0])."$segments[1]:$segments[2]ff:fe$segments[3]:$segments[4]$segments[5]";
}

1;
__END__
