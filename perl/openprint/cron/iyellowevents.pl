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
require openprint::Log;

my %months = (
	jan	=>	'01',
	feb	=>	'02',
	mar	=>	'03',
	apr	=>	'04',
	may	=>	'05',
	jun	=>	'06',
	jul	=>	'07',
	aug	=>	'08',
	sep	=>	'09',
	oct	=>	'10',
	nov	=>	'11',
	dec	=>	'12',
);

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
GetOptions($opts, 'help', 'log_file=s', 'log_level=s', 'config=s',
	'db_name=s', 'db_host=s', 'db_user=s', 'db_pass=s',
 );

if ($opts->{help}) {
	usage();
	exit 0;
}

$$opts{config} = '/etc/openprint/pleasurablethings.conf' if ! $$opts{config};
$log = new logger( { level=>'debug'} );
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
	host		=> $config{'db_host'},
	database	=> $config{'db_name'},
	driver		=> 'Pg',
	login		=> $config{'db_user'},
	password	=> $config{'db_pass'},
);
die 'Error opening db' if ! $dbh;
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
my $base_url = 'http://iyellowwineclub.com/';
my $req = HTTP::Request->new(GET => $base_url.'/learn' );
# Pass request to the user agent and get a response back
my $res = $ua->request($req);
# Check the outcome of the response
if (! $res->is_success) {
    $log->debug("No success.");
	exit(0);
} # end f

my $user_name = 'iYellow Wine Club';
my $company_name = 'iYellow Wine Club';

my $User = openprint::User->find_one(firstname=>$user_name);
if ( ! $User ) {
	$log->warn("User $user_name not found... continuing...");
	my $Company = openprint::Company->find_one(name=>$company_name);
	if ( ! $Company ) {
		$log->warn("Company $company_name not found... continuing...");
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
my $content_div = $tree->look_down( id => 'main' );
if ( ! $content_div ) {
	$tree->dump();
	die "No content";
} # end if

foreach my $post ( $content_div->look_down( class=>'post') ) {
	my $Title = $post->look_down( class => 'post-title');
	if ( ! $Title ) {
		$log->warn("No Title for ");
		$post->dump();
		next;
	} # end if
	my $title = openprint::Event->transform( 'name', $Title->as_text() );
	if ( ! $title ) {
		$log->warn("No title after transform");
		$post->dump();
		next;
	} # end if
	$log->debug("Event: $title");

	my $content = $post->look_down( class=>'spoiler');
	$content = $content->as_HTML();

	#my ( $caption, $description, $location, $when ) = $content =~ /$title\s+(.+)Description:\s+(.+)Location:\s+(.+)Date & Time:\s+(.+)/;
	my ( $description, $location, $start, $end ) = $content =~ /<div class="spoiler">(.+)<b>Location:<\/b>\s+(.+)<b>Begins:<\/b>\s+(.+)<b>Ends:<\/b>\s+(.+)<\/div>/;
	$log->debug("desc: $description, loc: $location, start: $start, end: $end");
	if ( ! $description ) {
		$log->debug( "No description from $content" );
		next;
	} # end if

	my $address = $location =~ /\(([^\)]+)\)/;
	my $city = $location =~ /, (.+)/;

$log->debug("Location $location  address: $address city: $city");

	my $Asset;
	foreach my $img ( $post->look_down(_tag=>'img') ) {
		my $posterurl = $img->attr('src');
		$posterurl = URI::Escape::uri_unescape( $posterurl );
		if ( $Assets{$posterurl} ) {
			$Asset = $Assets{$posterurl};
			if ( ! $Asset->source() ) {
				$Asset->save({source=>$posterurl});
			} # end if
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

	$start =~ s/ at//;
	$start =~ s/ Times very//i;
	$start =~ s/<br\s*\/>//i;
	my $starting_time = Date::Parse::str2time( $start );
	my $time_associated = 1;
	if ( ! $starting_time ) {
		$log->debug("No starttime_time from $start");
	} # end if
	if ( my ( $mon, $day, $year, $hours, $minutes, $ampm ) = $start =~ /^(\w+) (\d+), (\d\d\d\d) (\d+):(\d+)(am|pm)$/ ) {
		$hours += 12 if $ampm eq 'pm';
		$start = sprintf('%.4d-%.2d-%.2d %.2d:%.2d:00', $year, $months{lc $mon}, $day, $hours, $minutes );
		$starting_time = Date::Parse::str2time( $start );
		$time_associated = 0;
	} # end if
		
	if ( ! $starting_time ) {
		$log->debug("No starttime_time from $start");
		next;
	} # end if

    $end =~ s/ at//;
    $end =~ s/ Times very//i;
	$end =~ s/<br\s*\/>//i;
    my $ending_time = Date::Parse::str2time( $end );
    if ( ! $ending_time ) {
        $log->debug("No endtime_time from $end");
    } # end if
	if ( my ( $mon, $day, $year, $hours, $minutes, $ampm ) = $end =~ /^(\w+) (\d+), (\d\d\d\d) (\d+):(\d+)(am|pm)$/ ) {
		$hours += 12 if $ampm eq 'pm';
		$end = sprintf('%.4d-%.2d-%.2d %.2d:%.2d:00', $year, $months{lc $mon}, $day, $hours, $minutes );
        $ending_time = Date::Parse::str2time( $end );
    } # end if

    if ( ! $ending_time ) {
        $log->debug("No endtime_time from $end");
        next;
    } # end if

	my $parser = 'DateTime::Format::Pg';
	my $st = DateTime->from_epoch( epoch=>$starting_time, time_zone=>$TZ );
	my $et = DateTime->from_epoch( epoch=>$ending_time, time_zone=>$TZ );
	
	my $starting_on = $parser->format_datetime( $st );
	my $ending_on = $parser->format_datetime( $et );
	#my $ending_on = sprintf( '%.4d-%.2d-%.2d %.2d:%.2d:00', $ending_year, $ending_month, $ending_day, $ending_hour, $ending_minute );
	$log->debug("Starting $starting_on ending $ending_on");

	my $Url = $post->look_down( rel=>'bookmark');
	my $url = $Url->attr( 'href' );
	
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
		ending_on	=>	$ending_on,
		info		=>	$description,
		location_id	=>	$Location->id(),
		created_by	=>	$User->id(),
		template	=>	0,
		category	=>	'Wine Tasting',
		time_associated	=> $time_associated,
		url			=>	$url,
		});
			if ( ! openprint::Log->find_one(action=>'Create Event', object_type=>'openprint::Event',object_id=>$Event->id() ) ) {
				(new openprint::Log())->save({action=>'Create Event', object_type=>'openprint::Event',object_id=>$Event->id()});
			}
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

    --log_file	File to output logs to.

    --log_level	valid options debug, info, warn, error

EOH
}

1;
__END__
