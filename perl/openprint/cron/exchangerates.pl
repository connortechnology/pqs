#!/usr/bin/perl 
use lib '/var/www/testing/perl';
use 5.10.0;
use utf8;

use strict;
use warnings;
require LWP::UserAgent;
require HTTP::Request;
require Math::Round;

require configuration;
require sql;
require logger;
require openprint::Currency;
require openprint;

use vars qw( $log $dbh %config );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;

use File::Basename qw(basename);
use Getopt::Long;

my $program = basename($0);

my @args = @ARGV;

my $opts = {};
GetOptions($opts, 'help', 'log_file=s', 'log_level=s',
	'db_port=s', 'db_name=s', 'db_host=s', 'db_user=s', 'db_pass=s',
	'config=s',
 );

if ($opts->{help}) {
	usage();
	exit 0;
}

$log = new logger({level=>'debug'});
configuration::from_file($$opts{config} ? $$opts{config} : "/etc/openprint/$program.conf");
# Commandline overrides config file
configuration::merge( $opts );
$log->level($config{log_level}) if $config{log_level};
$log->debug("log level is: $config{log_level}");

# Declare variables
foreach my $param ( 'db_name','db_user','db_pass' ) {
	if ( ! $config{$param} ) {
		die "$program: missing required --$param parameter";
	} # end if
} # end foreach required-param
$openprint::dbh = sql::open_sql( $log, 
	port		=> $config{db_port},
	host		=> $config{db_host},
	database	=> $config{db_name},
	driver		=> 'Pg',
	login		=> $config{db_user},
	password	=> $config{db_pass},
);
die 'Error opening db' if ! $dbh;
configuration::init();
configuration::from_file($$opts{config} ? $$opts{config} : "/etc/openprint/$program.conf");
configuration::merge( $opts );

my @Currencies = openprint::Currency->find();

my $ua = new LWP::UserAgent;

foreach my $From ( @Currencies ) {
	next if ! $$From{short};
	foreach my $To ( @Currencies ) {
		next if $From == $To;
		next if ! $$To{short};

		my $url = "http://finance.yahoo.com/d/quotes.csv?s=$$From{short}$$To{short}=X&f=l1&e=.csv";
		my $request = HTTP::Request->new(GET => $url );
# Pass request to the user agent and get a response back
		my $resp = $ua->request($request);
		if ($resp->is_error()) {
			$log->error( $resp->status_line );
			next;
		}
		my $rate = $resp->{_content};
		$rate =~ s/[ \n]+/ /gs;
		print $rate, "\n";

		if ( ! $rate ) {
			$log->error("No rate for $$From{short} to $$To{short}");
			next;
		}
		my $inverse_rate = Math::Round::nearest(0.0001,(1/$rate));
		if ( ! $inverse_rate ) {
			$inverse_rate = (1/$rate);
			$log->error("No inverse_rate $inverse_rate for $$From{short} to $$To{short} rate was $rate");
			if ( ! $inverse_rate ) {
				next;
			}
		}


		my $Conversion = openprint::Currency_Conversion->find_one(from_id=>$$From{id}, to_id=>$$To{id}, period_end=>undef);
		if ( ! $Conversion ) {
			$log->debug("Saving new conversion for $$From{short} to $$To{short}");
			$Conversion = new openprint::Currency_Conversion();
			$_ = $Conversion->save({
					to_id	=>	$$To{id}, 
					from_id	=>	$$From{id},
					rate	=>	$rate,
					});
			if ( $_ ) {
				$log->error("Error saving currency conversion: $rate : $_ ");
			} # end if
		} elsif ( Math::Round::nearest(0.01, $Conversion->rate()) != Math::Round::nearest(0.01, $rate ) ) {
			$log->debug("Updating conversion for $$From{short} to $$To{short} from $$Conversion{rate} to $rate");
			$_ = $Conversion->save({ period_end=>'NOW()' });
			if ( $_ ) {
				$log->error("Error saving currency conversion: $rate : $_ ");
			} # end if
			$_ = $Conversion->save({
					id				=>	undef,
					period_start	=>	'NOW()',
					period_end		=>	undef,
					rate			=>	$rate,
					});
			if ( $_ ) {
				$log->error("Error saving currency conversion: $rate : $_ ");
			} # end if
		} # end if

	} # end foreach to
} # end foreach From

$dbh->disconnect();

1;
__END__
