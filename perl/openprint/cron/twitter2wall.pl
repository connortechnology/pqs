#!/usr/bin/perl 
use lib '/var/www/testing/perl';
use 5.10.0;
use utf8;

# INCLUDES
use strict;
#use Net::Twitter::Lite;
use XML::RSS;
use LWP::Simple;

use Data::Dumper;
require configuration;
require sql;
require ssi;
require misc;
require openprint::User;
require logger;
require openprint::Wall;
require Date::Parse;
require Date::Format;
require openprint;
require openprint::Object;
require openprint::User_Profile_Field;
require openprint::User_Profile_Entry;

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

$$opts{config} = '/etc/twitter2wall.conf' if ! $$opts{config};

$log = new logger( {'level'=>'debug'});
# Get our configuration information
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

my $ID_Field = openprint::User_Profile_Field->find_one('name'=>'Twitter ID');
die "No User Profile Field found for Twitter ID\n" if ! $ID_Field;
#my $Password_Field = openprint::User_Profile_Field->find_one('name'=>'Twitter Password');
#die "No User Profile Field found for Twitter Password\n" if ! $Password_Field;

# create new instance of XML::RSS
my $rss = new XML::RSS;

foreach my $Twitter_ID ( openprint::User_Profile_Entry->find('field_id'=>$ID_Field->id(), 'value is null'=>0 ) ) {

	my $content;
	my $file;
	my $arg = 'http://api.twitter.com/1.1/statuses/user_timeline.rss?screen_name='.$Twitter_ID->value();
# argument is a URL
	if ($arg=~ /http:/i) {
		$content = Encode::encode('utf-8',get($arg));
		die "Could not retrieve $arg" unless $content;
#$log->debug($content);
# parse the RSS content
		$rss->parse($content);
# argument is a file
	} else {
		$file = $arg;
		die "File \"$file\" does't exist.\n" unless -e $file;
# parse the RSS file
		$rss->parsefile($file);
	} # end if

	foreach my $item (@{$rss->{'items'}}) {
		$$item{title} =~ s/^$$Twitter_ID{value}: //i;
		my $Wall = openprint::Wall->find_one(
			user_id		=>	$Twitter_ID->user_id(),
			author_id	=>	$Twitter_ID->user_id(),
			message		=>	$$item{'title'},
			created_on	=>	Date::Format::time2str('%Y-%m-%d %H:%M:%S%z', Date::Parse::str2time( $item->{'pubDate'} ) ),
		);
		$$item{title} =~ s/^@(\w+)/<a href="https:\/\/twitter.com\/$1" target="_blank">\@$1<\/a>/;
		$$item{title} =~ s/([^>])@(\w+)/$1<a href="https:\/\/twitter.com\/$2" target="_blank">\@$2<\/a>/gm;

		if ( $Wall and ! openprint::Wall->find_one(
            user_id     =>  $Twitter_ID->user_id(),
            author_id   =>  $Twitter_ID->user_id(),
            message     =>  $$item{'title'},
            created_on  =>  Date::Format::time2str('%Y-%m-%d %H:%M:%S%z', Date::Parse::str2time( $item->{'pubDate'} ) ),
        ) ) {
			$Wall->delete();
			$Wall = undef;
		} # end if
		next if $Wall;
		$Wall = new openprint::Wall();
		$Wall->save({
				'user_id'	=>	$Twitter_ID->user_id(),
				'author_id'	=>	$Twitter_ID->user_id(),
				'message'	=>	$$item{'title'},
			'created_on'	=>	Date::Format::time2str('%Y-%m-%d %H:%M:%S%z', Date::Parse::str2time( $item->{'pubDate'} ) ),
		});
	} # end foreach item

} # end foreach User

1;
__END__
