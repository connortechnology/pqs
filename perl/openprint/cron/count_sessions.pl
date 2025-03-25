#!/usr/bin/perl
use lib '/var/www/testing/perl';
use strict;
#use warnings;

require sets;
require configuration;
require sql;
require logger;
require openprint::User;
require openprint::Host;
use Apache::Session::Postgres;
use Getopt::Long;

use openprint ();
use vars qw($log $dbh %config);
*dbh = \$openprint::dbh;
*log = \$openprint::log;
*config = \%openprint::config;

my $program = 'count_sessions.pl';
$log = logger->new('warn');
my $opts = {};
GetOptions($opts, 'help', 'db_port=s', 'db_name=s', 'db_host=s', 'db_user=s', 'db_pass=s','output=s','debug=s');

if ($opts->{help}) {
    usage();
    exit 0;
}
if ( $opts->{debug}) {
    $$log{level} = $opts->{debug};
}

unless ($opts->{db_name}) {
    print STDERR "$program: missing required --db_name parameter\n";
    exit 1;
}
$opts->{db_user} = $opts->{db_name} if ! $opts->{db_user};
$opts->{db_pass} = $opts->{db_name} if ! $opts->{db_pass};

$dbh = sql::open_sql( $log,
  port		=>	$$opts{db_port},
  host      => $opts->{db_host},
  database  => $opts->{db_name},
  driver    => 'Pg',
  login     => $opts->{db_user},
  password  => $opts->{db_pass},
);

die 'Error opening db' if ! $dbh;
configuration::init();

my $session_ids = $dbh->selectcol_arrayref( q{SELECT id FROM sessions} );
my @online;
$log->debug('Sessions: ' . @$session_ids );
foreach my $session_id ( @$session_ids ) {
  $session_id =~ s/\s//g;
  my %session;
  if (! eval q`tie %session, 'Apache::Session::Postgres', $session_id, { Handle => $dbh, Commit => 0, IDLength => 8 }`) {
    $log->error("Error fetching Session: $session_id: $@");
    next;
  }
  if (!$session{lastupdated}) {
    $log->warn("Updating time $session_id");
    $session{lastupdated} = time;
  } elsif (time - $session{lastupdated} < (60*60)) {
    $session{ip} = openprint::Host_Interface->transform(ip=>$session{ip});
    next if !$session{ip};
    my $I = openprint::Host_Interface->find_one(ip => $session{ip});
    next if ! $I;
    my $Host = $I->Host();
    if ( $Host->hostname() ) {
      next if $Host->hostname() =~ /googlebot/;
      next if $Host->hostname() =~ /baidu/;
      next if $Host->hostname() =~ /search/;
      next if $Host->hostname() =~ /Yandex/;
    } # end if
    push @online, $session_id;
  } # end if
  untie %session;
  undef %session;
} # end foreach
@$session_ids = ();

if ( $$opts{output} ) {
	open (MYFILE, '>'.$$opts{output}) or die "unable to open output at $$opts{output} : $!";
	print MYFILE @online." currently online<br/>\n";
	
	my @user_ids;
	foreach my $session_id ( @online ) {
		my %session;
		if ( ! eval q`tie %session, 'Apache::Session::Postgres', $session_id, { Handle => $dbh, Commit => 0, IDLength => 8 }` ) {
			$log->debug("Error fetching Session: $session_id: $@");
			next;
		} # en dif
		next if ! $session{user_id};
		push @user_ids, $session{user_id};
		undef %session;
	} # en d foreach session_id
	foreach my $user_id ( sets::union(@user_ids) ) {
		my $User = new openprint::User( $user_id );
		print MYFILE $User->thumbnail_html();
	} # end foreach user_id
	close (MYFILE); 
} # end if
$dbh->disconnect() if $dbh;

sub usage {
	print <<EOH;

usage: $program [--help] [--db_name \$db_name] [--db_host \$db_host] [--db_user \$db_user] [--db_pass \$db_pass] [ --output filename ]

The purpose of this script is to monitor the hotfolders configured for each
press for PPF files and perform conversions for Heidelberg JDF, Merge front 
and backs for presses that require it, and to import the PPF previews and 
other data into the IntelligentQuote system.

Command-line options:

	--help		Displays this message.

	--db_host	The hostname of the machine on which the database resides.

	--db_name	The name of the database.
	
	--db_user	The name of the user to use when connecting to the database.

	--db_pass	The password to use when connecting to the database.

    --output    File to store the session count in.

EOH
}
1;
__END__
