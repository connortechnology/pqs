#!/usr/bin/perl
use utf8;
use lib '/var/www/pqs/perl';
use strict;

require configuration;
require sql;
require sets;
require logger;
require openprint;
require openprint::Host;
require openprint::Log;
require openprint::Project;

require eprint::service;

use vars qw( $log $dbh %config %session %variable);
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;
*session = \%openprint::session;
$log = logger->new({level=>'debug'});

use Getopt::Long;
use File::Basename qw(basename);

my $opts = {};
GetOptions($opts, 'help', 
		'db_name=s', 'db_host=s', 'db_user=s', 'db_pass=s', 'debug=s', 'command=s', 'project_id=s',
		);

if ($opts->{help}) {
    usage();
    exit 0;
}

my $program = basename($0);
# Get our configuration information
$_ = configuration::from_file("/etc/openprint/$program.conf");
$log->error($_) if $_;
configuration::merge($opts);

foreach my $param ( 'db_name','db_user','db_pass', 'project_id' ) {
	if ( ! $config{$param} ) {
		die "$program: missing required --$param parameter";
	} # end if
} # end foreach required-param

$log->file( $config{log_file} ) if $config{log_file};
$log->level( $config{log_level} ) if $config{log_level} ne 'debug';

if ( $config{pid_file} ) {
	my $pidh;
	if (open($pidh, '> '.$config{pid_file} ) ) {
		print $pidh $$."\n"; 
		close($pidh);
	} else {
		die 'Unable to open pid file';
	} # end if
} # end if

$log->debug("Connecting to db");	
$dbh = sql::open_sql( $log,
		host			=> $config{db_host},
		database	=> $config{db_name},
		driver		=> 'Pg',
		login			=> $config{db_user},
		password	=> $config{db_pass},
		);
if ( ! $dbh ) {
	die "Error opening db. $!";
} # end if
configuration::init( $opts );
$_ = configuration::from_file("/etc/openprint/$program.conf");
$log->error($_) if $_;
configuration::merge($opts);
openprint::session_init();
$openprint::session{'Currency_id'} =1 if ! $openprint::session{'Currency_id'};
foreach my $k ( keys %openprint::session ) {
$log->debug("Session $k => $openprint::session{$k}");
}


my $pid = $$opts{project_id};
my $Project = new openprint::Project( $$opts{project_id} );
foreach my $sig_id ($Project->signatures()) {
  my $service = $Project->Service($sig_id);
  my $specs = $service->specs();
  my $type = eprint::service::load_service_type($service->ServiceType());
  my $state = eprint::service::price($log, $dbh, \%variable, $pid, $sig_id, $type, $specs, 1);
}
#$Project->recalculate();

$dbh->disconnect() if $dbh;
exit 0;

sub usage {
	print <<EOH;

usage: recalc_project.pl [--help] 

The purpose of this script is to reboot or move cameras.

Command-line options:

	--help		Displays this message.
		--db_name
--db_host
--db_user
--db_pass
--debug--project_id

EOH
} # end sub usage

1;
__END__
