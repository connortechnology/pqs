#!/usr/bin/perl 
use lib '/var/www/testing/perl';
use 5.10.0;
use utf8;

# INCLUDES
use strict;
use XML::RSS;
use LWP::Simple;

use Data::Dumper;
require configuration;
require sql;
require openprint::User;
require logger;
require openprint::Article;
require openprint::Feed;
require Date::Parse;
require Date::Format;
require openprint;

use vars qw( $log $dbh %config );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;

use File::Basename qw(basename);
use Getopt::Long;
use Encode qw(encode);

my $program = basename($0);

my @args = @ARGV;

my $opts = {};
GetOptions($opts, 'help', 'log_file=s', 'log_level=s', 'config=s',
	'db_name=s', 'db_host=s', 'db_user=s', 'db_pass=s',
 );

if ($opts->{help}) {
	usage();
	exit 0;
}

$$opts{config} = '/etc/rss2article.conf' if ! $$opts{config};

$log = new logger( {'level'=>'debug'});
configuration::from_file($$opts{config});
configuration::merge( $opts );
$log->level($config{'log_level'}) if $config{'log_level'};

# Declare variables
foreach my $param ( 'db_name','db_user','db_pass' ) {
	if ( ! $config{$param} ) {
		die "$program: missing required --$param parameter";
	}
} # end foreach required-param
$openprint::dbh = sql::open_sql( $log, 
	'host'		=> $config{'db_host'},
	'database'	=> $config{'db_name'},
	'driver'	=> 'Pg',
	'login'		=> $config{'db_user'},
	'password'	=> $config{'db_pass'},
);
die 'Error opening db' if ! $dbh;
configuration::init( $log, $dbh, \%CFG::Config );
configuration::from_file($$opts{config});
configuration::merge( $opts );

# create new instance of XML::RSS
my $rss = new XML::RSS;

#my @Feeds = split(',', ( $CFG::Config{'RSS_Feeds'} ? $CFG::Config{'RSS_Feeds'} : $config{'RSS_Feeds'} ) );
#@Feeds = openprint::Feed->find() if ! @Feeds;

foreach my $Feed ( openprint::Feed->find('active'=>1) ) {
	my $content;
	my $file;
	my $arg = $Feed->url();
# argument is a URL
	if ($arg=~ /http:/i) {
		$content = Encode::encode('utf-8',get($arg));
		die "Could not retrieve $arg" unless $content;
# parse the RSS content
		$rss->parse($content);
##$log->debug($content);

# argument is a file
	} else {
		$file = $arg;
		die "File \"$file\" does't exist.\n" unless -e $file;
# parse the RSS file
		$rss->parsefile($file);
	} # end if

#$log->debug("RSS: " . Data::Dumper::Dumper($rss));
#print "RSS: " . Data::Dumper::Dumper($rss) . "\n";
    # print the channel items
    foreach my $item (@{$rss->{'items'}}) {
#$log->debug("Item: " . Data::Dumper::Dumper($item));
#print "Item: " . Data::Dumper::Dumper($item) ."\n";
		next unless defined($item->{'title'}) && defined($item->{'link'});
		my $Article = openprint::Article->find_one('title'=>$item->{'title'});
		if ( ! $Article ) {
			my $User;
			if ( $$item{'dc'} and $$item{dc}{creator} ) {
				$User = openprint::User->find_one('company_id'=>$Feed->company_id(), 'firstname'=>$$item{dc}{creator});
			} # end if
			$item->{'description'} =~ s/\n/ /g;

			# Get rid of the feedburner stuff
			if ( $$item{'http://rssnamespace.org/feedburner/ext/1.0'} and $$item{'http://rssnamespace.org/feedburner/ext/1.0'}{'origLink'} ) {
				$$item{'link'} = $$item{'http://rssnamespace.org/feedburner/ext/1.0'}{'origLink'};
			} # end if

			if ( $Feed->filters() ) {
				foreach my $filter ( split("\n", $Feed->filters() ) ) {
$log->debug("Apply filter $filter");
					eval q`$item->{'description'} =~ `.$filter;
					$log->error( "Eval error, Reason: " . $@ ) if $@;
				} # end foreach filter
$log->debug("after filtering: $$item{'description'}");
			} else {
				$log->warn("No filters ");
				$log->debug("No filters $$Feed{'filters'}");	
			} # end $Feed->filters
			$Article = new openprint::Article();
			$Article->save({
				'title'	=>	$item->{'title'},
				'body'	=>	$item->{'description'},
				'source'	=>	$item->{'link'},
				'published'	=>	$Feed->published(),
				'published_on'	=>	Date::Format::time2str('%Y-%m-%d %H:%M:%S%z', Date::Parse::str2time( $item->{'pubDate'} ) ),
				'created_on'	=>	Date::Format::time2str('%Y-%m-%d %H:%M:%S%z', Date::Parse::str2time( $item->{'pubDate'} ) ),
				'company_id'	=>	$Feed->company_id(),
				'category_id'	=>	$Feed->category_id(),
				( $User ? ( 'created_by'	=> $User->id() ) : () ),
			});
		#$log->debug( $Article->to_string() );
		} else {
$log->debug( "Already have article for $$item{title}" );
		} # end if
    } # en dforeach
} # end foreach Feed

1;
__END__
