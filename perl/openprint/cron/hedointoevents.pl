#!/usr/bin/perl  -w
use lib '/var/www/testing/perl';
use 5.10.0;
use utf8;

# INCLUDES
use strict;
use URI::Escape;

use Data::Dumper;
require configuration;
require sql;
require ssi;
require misc;
require openprint::Company;
require openprint::User;
require logger;
require Date::Parse;
require Date::Format;
require openprint;

require openprint::Event;
require openprint::Location;
require openprint::Asset;
require Date::Calc;


use vars qw( $log $dbh %config );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;

use File::Basename qw(basename);
use Getopt::Long;
use Mail::Sendmail;
use MIME::QuotedPrint;
use Time::HiRes qw(usleep);
use Encode qw(decode);

my $program = basename($0);

my @args = @ARGV;

my $opts = {};
GetOptions($opts, 'help', 'log_file=s', 'log_level=s',
	'db_name=s', 'db_host=s', 'db_user=s', 'db_pass=s',
 );

if ($opts->{help}) {
	usage();
	exit 0;
}

$$opts{config} = '/etc/openprint/hedointo.conf';
$log = new logger( { level=>'debug'});
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
if ( 1 ) {
$openprint::dbh = sql::open_sql( $log, 
	host		=> $config{'db_host'},
	database	=> $config{'db_name'},
	driver		=> 'Pg',
	login		=> $config{'db_user'},
	password	=> $config{'db_pass'},
);
die 'Error opening db' if ! $dbh;
}
configuration::init();
configuration::from_file($$opts{config});
configuration::merge($opts);

require DateTime::Format::Pg;
require DateTime;
require DateTime::TimeZone;
my $TZ = DateTime::TimeZone->new( name => $config{Timezone} );

use LWP::UserAgent ();
use HTTP::Request ();
my $ua = LWP::UserAgent->new;
$ua->agent("IQ/0.1 ");
# Create a request
my $base_url = 'http://hedointo.com/';
my $req = HTTP::Request->new(GET => $base_url.'/events' );
# Pass request to the user agent and get a response back
my $res = $ua->request($req);
# Check the outcome of the response
if (! $res->is_success) {
    $log->debug("No success.");
	exit(0);
} # end f

my $user_name = 'ONYX';
my $company_name = 'HEDOinTO';

my $User = openprint::User->find_one(firstname=>$user_name);
if ( ! $User ) {
	my $Company = openprint::Company->find_one(name=>$company_name);
	if ( ! $Company ) {
		$Company = new openprint::Company();
		$Company->save({name=>$company_name});
	} # end if

	$User = new openprint::User();
	$User->save({company_id=>$Company->id(), firstname=>$user_name});
} # end if
#indexed by url
my %Assets;
my %Templates;
	
#$log->debug( "Content: " . $res->content );
my $content = Encode::decode('utf-8',$res->content);

use HTML::TreeBuilder;
my $tree = HTML::TreeBuilder->new;
$tree->parse_content($content);
$tree->elementify();

my $posts = $tree_div->look_down( class=>'ailec-agenda-view');
if ( ! $posts ) {
	$content_div->dump();
	die "No posts";
} # end if

foreach my $post ( $posts->look_down(class=>'ailec-date') ) {
	my ( $year ) = Date::Calc::Today();
	my $month = $post->look_down(class=>'ailec-month');
	my $day = $post->look_down(class=>'ailec-day');

	my $Title = $post->look_down(_tag => 'span');
	if ( ! $Title ) {
		$log->warn("No Title");
		next;
	} # end if
	my $title = openprint::Event->transform( 'name', $Title->as_text() );
	if ( ! $title ) {
		$log->warn("No title");
		$post->dump();
		next;
	} # end if

	my $content = $post->look_down(_tag=>'td');
	$content = $content->as_text();

	my ( $caption, $description, $location, $when ) = $content =~ /$title\s+(.+)Description:\s+(.+)Location:\s+(.+)Date & Time:\s+(.+)/;
	$log->debug("desc: $description, loc: $location, when: $when");
	if ( ! $description ) {
		$log->debug( "No description from $content" );
		next;
	} # end if
	$description = $caption . '<br/>'.$description;

	my $address = $location =~ /\(([^\)]+)\)/;
	my $city = $location =~ /, (.+)/;



$log->debug("$title $description $location $when");

	my $Asset;
	foreach my $img ( $post->look_down(_tag=>'img') ) {
		my $posterurl = $img->attr('src');
$log->debug("GOt $posterurl");
		$posterurl = URI::Escape::uri_unescape( $posterurl );
$log->debug("GOt2 $posterurl");
		if ( $Assets{$posterurl} ) {
			$Asset = $Assets{$posterurl};
		} else {
			$Asset = openprint::Asset::fetch($posterurl);
			if ( ref $Asset ne 'openprint::Asset' ) {
				
				die("Unable to get asset: $Asset from $posterurl " . $img->attr('src') );
				$log->error("Unable to get asset: $Asset");
				$post->dump();
				$Asset = undef;
			} else {
				$Assets{$posterurl} = $Asset;
			} # end if
		} # end if cached
	} # end foreach img

	$when =~ s/ at//;
	my $starting_time = Date::Parse::str2time( $when );
	if ( ! $starting_time ) {
		$log->debug("No starttime_time from $when");
		next;
	} # end if

	my $parser = 'DateTime::Format::Pg';
	my $st = DateTime->from_epoch( epoch=>$starting_time, time_zone=>$TZ );
	
	my $starting_on = $parser->format_datetime( $st );
	#my $ending_on = sprintf( '%.4d-%.2d-%.2d %.2d:%.2d:00', $ending_year, $ending_month, $ending_day, $ending_hour, $ending_minute );

	my $Event = openprint::Event->find_one( created_by=>$$User{id}, name=>$title, starting_on => $starting_on, template => 0 );

	if ( $Event ) {
		next if (
				( $Event->info() eq $description ) 
				and $$Event{album_id}
#and ( $event->starting_on() eq $starting_onI#
				);
	} else {
		$Event = new openprint::Event();
	} # end if
	my $Location;
	my @Location = openprint::Location->find(name=>$location);
	if ( @Location == 1 ) {
		$Location = $Location[0];
	} else {
		$Location = openprint::Location::google( $location . ' Toronto Canada' );
	} # end if
	$log->debug( $Location->to_string() ) if $Location;
	$Event->save({
		name =>  $title,
		starting_on	=>	$starting_on,
		#ending_on	=>	$ending_on,
		info		=>	$description,
		location_id	=>	$Location->id(),
		created_by	=>	$User->id(),
		template	=>	0,
		category	=>	'Wine Tasting',
		time_associated	=> 1,
		});
	if ( $Asset ) {
		my $Album = $Event->Album();
		if ( ! $Album->id() ) {
			$Album = new openprint::Photo_Album();
			$_ = $Album->save({name=>'Photos for event ' . $Event->id() . ' ' . $Event->name(), user_id=>$$User{id}});
			if ( ! $_ ) {
				$Event->save({album_id=>$$Album{id}});
			} else {
				$log->error($_);
			} # end if
		} # end if
		my $Photo = openprint::Photo_in_Album->find_one( album_id=>$$Album{id}, asset_id=>$$Asset{id} );
		if ( ! $Photo ) {
			$Photo = new openprint::Photo_in_Album();
			$Photo->save({album_id=>$$Album{id}, asset_id=>$$Asset{id}});
		} # end if
	} # end if
		

} # end foreach post


1;
__END__
