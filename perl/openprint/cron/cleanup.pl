#!/usr/bin/perl 
use lib '/var/www/openprint/perl';
use strict;
use warnings;
use Digest::MD5;

require sql;
require ssi;
require logger;
require misc;
require configuration;
require openprint::Object;
require openprint::Quote;
require openprint::Order;
require openprint::Project;
require openprint::PaperInventory;
require openprint::CIP3_PPF;
require openprint::Host;
require openprint::Log;
require openprint::Asset;
require openprint::Claim_Content;
require openprint::ScheduledJob;
use Date::Calc;
use Apache::Session::Postgres;
use File::Basename qw(basename);
use Getopt::Long ();

use openprint ();
use vars qw($log $dbh %config);
*dbh = \$openprint::dbh;
*log = \$openprint::log;
*config = \%openprint::config;

my $program = basename($0);

my $opts = {};
Getopt::Long::GetOptions($opts, 'help',
    'log_file=s', 'log_level=s',
    'db_port=s', 'db_name=s', 'db_host=s', 'db_user=s', 'db_pass=s',
    'config=s',
);

if ($opts->{help}) {
    usage();
    exit 0;
}

my %defaults = (
);
foreach my $default ( keys %defaults ) {
    $$opts{$default} = $defaults{$default} if ! $$opts{$default};
} # end foreach default

$log = new logger(level=>'debug', program=>$program);

# Get our configuration information
$$opts{config} = '/etc/openprint/'.$program.'.conf' if !$$opts{config};
if (my $err = configuration::from_file($$opts{config})) {
	$log->error($err);
}
configuration::merge($opts);
foreach my $param ( 'db_name','db_user','db_pass' ) {
	if ( ! $config{$param} ) {
		die "$program: missing required --$param parameter";
	}
} # end foreach required-param

my $r;

$openprint::dbh = sql::open_sql( $log, 
	port		=> $config{db_port},
	host		=> $config{db_host},
	database	=> $config{db_name},
	driver		=> 'Pg',
	login		=> $config{db_user},
	password	=> $config{db_pass},
);
die 'Error opening db' if ! $dbh;

configuration::init( \%config );
configuration::from_file($$opts{config});
configuration::merge($opts);

# Clear out old sessions
my $session_ids = $dbh->selectcol_arrayref('SELECT id FROM sessions');
$log->debug('Cleaning out sessions: ' . @$session_ids . ' sessions in system');
my $deleted_session_count = 0;
foreach my $session ( @$session_ids ) {
    $session =~ s/\s//g;
    my %session;
    if ( ! eval q`tie %session, 'Apache::Session::Postgres', $session, { Handle => $dbh, Commit => 0, IDLength => 8 }` ) {
        $log->debug("Error fetching Session: $session: $@");
        next;
    }
    if ( !$session{lastupdated} ) {
		$log->debug('Updating time '.$session);
        $session{lastupdated} = time;
        untie %session;
    } elsif ( time - $session{lastupdated} > ( 60*60*24*7 ) ) {
		tied(%session)->delete;
		$deleted_session_count += 1;
    } elsif ( ( time - $session{lastupdated} > ( 60*60*24*1 ) ) and ! $session{user_id} ) {
		tied(%session)->delete;
		$deleted_session_count += 1;
	} else {
		undef %session;
	} # end if
} # end foreach
@$session_ids = ();
$log->debug("Deleted $deleted_session_count sessions");

if ( 0 and openprint::Order->find_one() ) {
  # Clean out unfinished Orders
  my @Orders = openprint::Order->find(status=>'Incomplete','created_on <=' => sprintf('%.4d-%.2d-%.2d', Date::Calc::Add_Delta_Days( Date::Calc::Today(), -180 ) ) );
  $log->debug('Cleaning out '.@Orders.' incomplete orders');
  foreach my $Order ( @Orders ) {
    $Order->delete();
  } # end foreach
  openprint::Object::init_cache();
} # end if


if ( openprint::Order->find_one() ) {
# Clean out unfinished Orders
	my @Orders = openprint::Order->find(
			status=>'Re-Opened',
			'updated_on <='=>sprintf('%.4d-%.2d-%.2d', Date::Calc::Add_Delta_Days(Date::Calc::Today(), -7))
			);
	$log->debug('Closing '.@Orders.' re-opened orders');
	foreach my $Order ( @Orders ) {
		print 'Close order ' . $Order->to_string()."? [Y|n]\n";
		$_ = <STDIN>;
		if ( !$_ or $_ eq 'Y' or $_ eq 'y' ) {
			$Order->close();
		}
	} # end foreach
  openprint::Object::init_cache();
} # end if

if ( openprint::Quote->find_one() ) {
	my @Quotes = openprint::Quote->find(
			status=>'Incomplete',
			'created_on <=' => sprintf('%.4d-%.2d-%.2d', Date::Calc::Add_Delta_Days(Date::Calc::Today(), -365))
			);
	$log->debug('Cleaning out '.@Quotes.' incomplete quotes ');
	foreach my $Quote ( @Quotes ) {
		$Quote->delete();
	} # end foreach
  openprint::Object::init_cache();
}

if ( 0 ) {
if ( ( exists $config{RFID} ) and $config{RFID} ) {
	require openprint::RFIDTag;
	require openprint::RFIDTagHistory;
	require openprint::RFIDScannerHistory;
	my @Hs = openprint::RFIDScannerHistory->find(
			'updated_on <'=>sprintf('%.4d-%.2d-%.2d 23:59:59', Date::Calc::Add_Delta_Days( Date::Calc::Today(), -31 ) ),
			'updated_on >'=>sprintf('%.4d-%.2d-%.2d 23:59:59', Date::Calc::Add_Delta_Days( Date::Calc::Today(), -62 ) ),
			);
	$log->debug( "Scanner History Entries: " . @Hs );
	foreach my $H ( @Hs ) {
		$H->delete();
	} # end foreach H
	@Hs = openprint::RFIDTagHistory->find(
			'updated_on <'=>sprintf('%.4d-%.2d-%.2d 23:59:59', Date::Calc::Add_Delta_Days( Date::Calc::Today(), -31 ) ),
			'updated_on >'=>sprintf('%.4d-%.2d-%.2d 23:59:59', Date::Calc::Add_Delta_Days( Date::Calc::Today(), -62 ) ),
			);
	$log->debug( "Tag History Entries: " . @Hs );
	foreach my $H ( @Hs ) {
		$H->delete();
	} # end foreach H
	my @old_unassigned_tags = openprint::RFIDTag->find(
			'updated_on <'=>sprintf('%.4d-%.2d-%.2d 23:59:59', Date::Calc::Add_Delta_Days( Date::Calc::Today(), -60 ) ),
			'skid_id exists'=>	0,
			'type'			=>	'Skid',
			);
	$log->debug( "Tag History Entries (unassigned and old): " . @old_unassigned_tags );
	foreach my $H ( @old_unassigned_tags ) {
		next if $H->skid_id();
		$H->delete();
	} # end foreach H
} # end if
}


# Paper maintenance
foreach my $Paper ( openprint::Paper->find( 'project_type_id exists' => 1 ) ) {
  if ( (! $$Paper{basis_mweight} ) and $Paper->basis_mweight() ) {
    $log->debug("Updating basis_weight");
    $Paper->save();
  }

  my $check = $Paper->check();
  if ( $check ) {
    if ( $check =~ /basis/ ) {
      if ( $Paper->weight() =~ /(\d+)lb/ ) {
        $log->debug("Updating based on basis_mweight");
        $$Paper{gsm} = undef;
        $$Paper{wpsi} = undef;
        $$Paper{mweight} = undef;
        $Paper->gsm();
        $Paper->mweight();
        $Paper->basis_mweight( 2*$1 );
        $Paper->save();
      }
      $check = $Paper->check();
    }
    $log->error($Paper->to_string() . ' ' . $check . " id:$$Paper{id}");
    #sleep 1;
  }

  my $old_wpsi = $Paper->wpsi();
  $old_wpsi = '' if ! defined $old_wpsi;
  next if ! $Paper->wpsi(undef);
  if ( $old_wpsi ne $Paper->wpsi() ) {
    $openprint::log->debug("Updating wpsi (old: $old_wpsi, new: $$Paper{wpsi}) for " . $Paper->to_string() );
    $Paper->save();
    last if $dbh->errstr();
  } # end if
  openprint::Object::init_cache();
} # end foreach my Paper

if ( 1 ) {
  my $log_count = 0;
  # Delete all logs more than 2 years
  foreach my $Log ( openprint::Log->find('date_time <='=>sprintf('%.4d-%.2d-%.2d 00:00:00',
        Date::Calc::Add_Delta_Days( Date::Calc::Today(), -2*365 ) ) )
  ) {
    $Log->delete();
    $log_count += 1;
  } # end foreach Log
  openprint::Object::init_cache();
  $log->debug("Deleted $log_count log entries");

  $log_count = 0;
  # Delete all WAP connections logs more than 7days
  foreach my $Log (
    openprint::Log->find(
      'date_time <='=>sprintf('%.4d-%.2d-%.2d', Date::Calc::Add_Delta_Days(Date::Calc::Today(), -7)),
      action	=>	'Update',
      'note like'	=> 'Connection to %', )
  ) {
    $Log->delete();
    $log_count += 1;
  } # end foreach Log
  $log->debug("Deleted $log_count log entries for connection updates");
  openprint::Object::init_cache();
}

#if ( $config{AssetPath} ) {
	foreach my $Asset ( openprint::Asset->find('md5 is null'=>1) ) {
		my $data = misc::load_file( $log, $Asset->on_disk_path() );
		if ( $data ) {
			$_ = $Asset->save({md5=>Digest::MD5::md5_base64( $data ) });
			die $_ if $_;
		} # end if
	} # end foreach Asset
	foreach my $Asset ( openprint::Asset->find('width is null'=>1) ) {
		$Asset->layout();
		if ( $Asset->width() ) {
			$_ = $Asset->save();
			die $_ if $_;
		} else {
			$log->debug("Unable to calc image wiwdth: " . $Asset->to_string() );
		} # end if width
	} # end foreach
#} 

foreach my $Photo_Album ( openprint::Photo_Album->find( 'thumbnail_id is null'=>0) ) {
	if ( ! sets::isin( $$Photo_Album{thumbnail_id}, ( map { $_->asset_id() } $Photo_Album->Photos() ) ) ) {
		$Photo_Album->save({'thumnail_id'=>undef});
	} # end if
} # end foreach
my $deleted_skids = 0;
foreach my $Skid ( openprint::Skid->find(
            'created_on <='=>sprintf('%.4d-%.2d-%.2d 00:00:00', Date::Calc::Add_Delta_Days( Date::Calc::Today(), (2*-365)+2 ) ),
            'created_on >='=>sprintf('%.4d-%.2d-%.2d 00:00:00', Date::Calc::Add_Delta_Days( Date::Calc::Today(), 2*-365 ) ),
            ) ) {
    my $delete = 1;
    my @Contents = $Skid->Contents();
    foreach my $C ( @Contents ) {
        $delete = 0 if $C->quantity();
    }
    $delete = 0 if openprint::Claim_Content->find('skid_id'=>$$Skid{id});
    $delete = 0 if openprint::ManifestContent->find('skid_id'=>$$Skid{id});
    if ( $delete ) {
        $Skid->destroy();
        $deleted_skids += 1;
    } # end if
} # end foreach Skid
$log->debug("Deleted $deleted_skids skids");

if ( 0 ) {
	# Resolve any unresolved IP's
	my @Hosts = openprint::Host->find(
			'hostname is null'=>1, 
			'resolved_on null_or_<='	=>	sprintf('%.4d-%.2d-%.2d', Date::Calc::Add_Delta_Days( Date::Calc::Today(), -30 ) ),
	);
	$log->debug("# of hosts needing resolving: " . @Hosts );
	foreach my $Host ( @Hosts ) {
			my $host = $Host->resolve();
			if ( $host ) {
				$Host->hostname( $host );
			}
			$Host->save({ resolved_on	=> 'NOW()' });
	} # end foreach Host
}
if ( 0 ) {
foreach my $Job ( openprint::ScheduledJob->find(
			'starttime <' => sprintf('%.4d-%.2d-%.2d 00:00:00', Date::Calc::Add_Delta_Days( Date::Calc::Today(), -14 ) ),
) ) {
	$Job->delete();
}
}

$dbh->disconnect();

sub usage {
	print <<EOH;

usage: $program [--help] 

The purpose of this script is to cleanup various things in the database.

Command-line options:

	--help		Displays this message.
EOH
}
1;
__END__
