#!/usr/bin/perl 
use lib '/var/www/testing/perl';
use 5.10.0;
use utf8;

# INCLUDES
use strict;
use JSON ();
use LWP::UserAgent ();
use HTTP::Request ();

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
configuration::from_file($$opts{config} ? $$opts{config} : '/etc/bitcoin_exchangerate.conf');
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
configuration::from_file($$opts{config} ? $$opts{config} : '/etc/bitcoin_exchangerate.conf');
configuration::merge( $opts );

my $BTC = openprint::Currency->find_one(short=>'BTC');
die "No Bitcoin currency found in system." if ! $BTC;

my $url = 'http://api.bitcoincharts.com/v1/weighted_prices.json';

my $ua = LWP::UserAgent->new;
$ua->agent("MyApp/0.1 ");
# Create a request
my $req = HTTP::Request->new(GET => $url );
# Pass request to the user agent and get a response back
my $res = $ua->request($req);
# Check the outcome of the response
if ($res->is_success) {
	$log->debug("Content: " . $res->content );
	my $content = $res->content;
  if (!$content) {
    $log->error("Received no content but with success from $url");
    return;
  }
  my $rates = {};
  eval {
    $rates = JSON::decode_json( $content );
  };
  $log->error("Failed to decode $content as json: $@") if $@;
  my %Currencies = map { $_->short(), $_ } openprint::Currency->find();
	foreach my $cur ( keys %$rates ) {
		next if ! $Currencies{$cur};
		if ( ! $$rates{$cur}{'30d'} ) {
			$log->error("NULL 30d rate for $cur");
			next;
		} # end if
		my $rate = $$rates{$cur}{'30d'};
		if ( ! $rate ) {
			$log->error("NULL 30d rate for $rate");
			next;
		} # end if
		$rate = openprint::Currency_Conversion->transform( 'rate', $rate );
		if ( ! $rate ) {
			$log->error("NULL 30d rate after transform for $rate");
			next;
		} # end if

		my $Conversion = openprint::Currency_Conversion->find_one(from_id=>$Currencies{$cur}->id(), to_id=>$$BTC{id}, period_end=>undef);
		if ( ! $Conversion ) {
			$Conversion = new openprint::Currency_Conversion();
			$_ = $Conversion->save({
					from_id	=>	$Currencies{$cur}->id(), 
					to_id	=>	$$BTC{id},
					rate	=>	Math::Round::nearest(0.0001,1/$rate),
					});
			if ( $_ ) {
				$log->error("Error saving currency conversion: $rate : $_ ");
			} # end if
		} elsif ( Math::Round::nearest(0.01,$Conversion->rate()) != Math::Round::nearest(0.01, 1/$rate ) ) {
			#$Conversion->save({period_end=>'NOW()'});
			$_ = $Conversion->save({
				id=>undef,
				period_start=>'NOW()',
				period_end	=>	undef,
				rate		=>	Math::Round::nearest(0.0001/1/$rate),
				});
			if ( $_ ) {
				$log->error("Error saving currency conversion: $rate : $_ ");
			} # end if
		} # end if

		my $Conversion = openprint::Currency_Conversion->find_one(to_id=>$Currencies{$cur}->id(), from_id=>$$BTC{id}, period_end=>undef);
		if ( ! $Conversion ) {
			$Conversion = new openprint::Currency_Conversion();
			$Conversion->save({to_id=>$Currencies{$cur}->id(), from_id=>$$BTC{id},
					rate=>$rate,
					});
		} elsif ( Math::Round::nearest(0.01,$Conversion->rate()) != Math::Round::nearest(0.01, $rate ) ) {
			$Conversion->save({period_end=>'NOW()'});
			$Conversion->save({id=>undef,period_start=>'NOW()',
					period_end=>undef,
					rate=>$rate,
					});
		} # end if

		
	} # end foreach cur	
		
} else {
	$log->error("Bad status" . $res->status_line );
	$log->error( 'Unable to grab content from source.: ' . $res->status_line );
} # end if

$dbh->disconnect();

1;
__END__
