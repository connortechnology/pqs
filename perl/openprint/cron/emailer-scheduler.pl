#!/usr/bin/perl -w
use lib '/etc/apache2/lib/perl';
use strict;
use utf8;

use File::Basename qw(basename);
use Getopt::Long;

require sql;
require logger;
require misc;
require ssi;
require openprint::Object;
require openprint::EmailCampaign;
require configuration;

use openprint;
use vars qw( %variable $log $dbh %config %session );
*variable = \%openprint::variable;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;
*session = \%openprint::session;

my $program = basename($0);

my @args = @ARGV;

my $opts = {};
GetOptions($opts,
		'help', 'log_file=s', 'log_level=s',
		'db_port=s', 'db_name=s', 'db_host=s', 'db_user=s', 'db_pass=s',
		'config=s', 'campaign_id=s',
);

if ( $opts->{help} ) {
	usage();
	exit 0;
}

$$opts{config} = '/etc/openprint/emailer-scheduler.conf' if ! $$opts{config};

$log = new logger({level=>'debug'});
configuration::init();
configuration::from_file($$opts{config});
configuration::merge($opts);

# required params
foreach my $param ( 'db_name','db_user','db_pass' ) {
	die "$program: missing required --$param parameter" if ! $config{$param};
} # end foreach required-param

$dbh = sql::open_sql( $log, 
	port			=> $config{db_port},
	host			=> $config{db_host},
	database	=> $config{db_name},
	driver		=> 'Pg',
	login			=> $config{db_user},
	password	=> $config{db_pass},
);
die 'Error opening db' if ! $dbh;
configuration::from_db();
configuration::from_file($$opts{config});
configuration::merge($opts);
$config{log_level} = 'debug' if !$config{log_level};
$log = logger->new({file=>$config{log_file}, level=>$config{log_level}});

$session{company_id} = $config{owner_id} ? $config{owner_id} : $config{company_id};
die "No company assigned" if ! $session{company_id};
$session{user_type} = $config{user_type} ? $config{user_type} : '';
$ENV{DOCUMENT_ROOT} = $config{DOCUMENT_ROOT};

openprint::session_init();

# The first query to execute grabs the ids of all of the email campaigns
# that are currently set to run
openprint::EmailCampaign->lock();
my @Campaigns = openprint::EmailCampaign->find(
		$$opts{campaign_id} ?
		( id=>$$opts{campaign_id} ) :
    (
      active => 'Y', 'nextrun is null or <' => 'NOW()',
      custom=>['(timeofday IS NULL) OR (timeofday <= CURRENT_TIME)']
    )
);

$log->info('There are '.@Campaigns.' active campaigns');

# For each campaign, we need to get the associated query and interval of
# between the last login time and now (which will be our threshold of concern)
foreach my $Campaign ( @Campaigns ) {
	if ( !$Campaign->runnable() ) {
		$log->error("Campaign $$Campaign{name} is active but not runnable");
		next;
	}
	$log->info("Running campaign $$Campaign{name}");
	$Campaign->send();
	#print "Done campaign " . $Campaign->name() . "\n";
} # foreach campaign_id
openprint::EmailCampaign->unlock();

$dbh->disconnect();

sub usage {
  print "email_scheduler.pl 'help', 'log_file=s', 'log_level=s',
    'db_port=s', 'db_name=s', 'db_host=s', 'db_user=s', 'db_pass=s',
	'config=s', 'campaign_id=s',\n";
}

1;
__END__
