#!/usr/bin/perl  -w
use lib '/var/www/testing/perl';
use 5.10.0;
use utf8;

# INCLUDES
use strict;
use HTML::TreeBuilder;
use LWP::UserAgent ();
use HTTP::Request ();
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

$log = new logger( {'level'=>'debug'});
# Get our configuration information
configuration::from_file('/etc/openprint/pleasurablethings.conf');
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
	'host'		=> $config{'db_host'},
	'database'	=> $config{'db_name'},
	'driver'	=> 'Pg',
	'login'		=> $config{'db_user'},
	'password'	=> $config{'db_pass'},
);
die 'Error opening db' if ! $dbh;
}

my %months = (
	January	=>	'01',
	February	=>	'02',
	March	=>	'03',
	April	=>	'04',
	May	=>	'05',
	June	=>	'06',
	July	=>	'07',
	August	=>	'08',
	September	=>	'09',
	October	=>	'10',
	November	=>	'11',
	December	=>	'12',
);
# Login inputs are member and password, also need VIEWSTATE AND EVENTVALIDATION

my $ua = LWP::UserAgent->new;
$ua->agent("IQ/0.1 ");
# Create a request
my $base_url = 'http://www.thexclubforum.com/';
my $req = HTTP::Request->new(GET => $base_url.'index.php' );
# Pass request to the user agent and get a response back
my $res = $ua->request($req);
# Check the outcome of the response
if (! $res->is_success) {
    $log->debug("No success.");
	exit(0);
} # end f

my $Location = openprint::Location->find_one(name=>'The X Club');
my $User = openprint::User->find_one(firstname=>'Cheekyduo');
if ( ! $User ) {
	my $Company = openprint::Company->find_one(name=>'TheXClub');
	if ( ! $Company ) {
		$Company = new openprint::Company();
		$Company->save({name=>'TheXClub'});
	} # end if

	$User = new openprint::User();
	$User->save({company_id=>$Company->id(), firstname=>'Cheekyduo'});
} # end if

my $Category = openprint::Event_Category->find_one(name=>'Swinger Event');
if ( ! $Category ) {
	$Category = new openprint::Event_Category();
	$Category->save({name=>'Swinger Event'});
} # end if

#indexed by url
my %Assets;
my %Templates;
	
#$log->debug( "Content: " . $res->content );
my $content = Encode::decode('utf-8',$res->content);

my $tree = HTML::TreeBuilder->new;
$tree->parse_content($content);
$tree->elementify();
my $calendar = $tree->look_down(id=>'fo_calendar');

foreach my $post ( $calendar->look_down( _tag => 'a' ) ) {
	my $href = $post->attr( 'href' );
	if ( ! $href ) {
		$log->warn("No href");
		$post->dump();
	} else {
		$log->debug("Getting $href");
	} # end if
	next if $href =~ /showweek/;

	$req = HTTP::Request->new(GET => $href );
	# Pass request to the user agent and get a response back
	my $res = $ua->request($req);
	# Check the outcome of the response
	if (! $res->is_success) {
		$log->debug("No success.");
		next;
	} # end f

	my $event_tree = HTML::TreeBuilder->new;
	$event_tree->parse_content( Encode::decode('utf-8', $res->content ) );
	$event_tree->elementify();

	foreach my $event ( $event_tree->look_down( 'class'=>'ipbtable' ) ) {
		my $content = $event->look_down( 'class' => 'postcolor' );
		if ( ! $content ) {
			$log->warn("No content for $href");
			$event->dump();
			next;
		} # end if
		my $desc = $content->as_HTML();
		$desc =~ s/^<span class="postcolor">//;
		$desc =~ s/<\/span>$//;
		my ( $day, $month, $year ) = $event->as_text() =~ /Event Date: (\d+) (\w+) (\d+)/;
		if ( ! $day ) {
			$log->warn("No date in $desc");
			next;
		} # end if
		if ( ! $months{$month} ) {
			$log->warn("Invlaid month $month");
			next;
		} # end if
		$month = $months{$month};
		if ( Date::Calc::Delta_Days( Date::Calc::Today(), $year, $month, $day ) < 0 ) {
			$log->debug("Event in the past $year-$month-$day");
			next;
		} # end if
			

		my $title_span = $content->look_down(_tag => 'b');
		if ( ! $title_span ) {
			$log->warn("No title span");
			$content->dump();
			next;
		} # end if
		my $title_html = $title_span->as_HTML();
$log->debug("title html $title_html");
		$desc =~ s/$title_html//;
		$title_html =~ s/<\/?b>//g;
$log->debug("title html $title_html");
		$title_html =~ s/<\/?span[^>]*>//g;
$log->debug("title html $title_html");
		$title_html =~ s/^<br ?\/>(.*)$/$1/mi;
$log->debug("title html $title_html");
		$title_html =~ s/^(.*)<br ?\/>.*$/$1/mi;
$log->debug("title html $title_html");
		$title_html =~ s/<[^>]+\/?>//g;
$log->debug("title html $title_html");
		my $title = openprint::Event->transform( 'name', $title_html );
		if ( ! $title ) {
			$log->warn("No title");
			$event->dump();
			next;
		} # end if

		$log->debug("Title: $title\n, When: $year $month $day\n desc: $desc");

		my $img = $content->look_down(_tag=>'img' );
		my $Asset;
		if ( $img ) {
			$desc =~ s/<img[^>]+>//;

			my $posterurl = $img->attr('src');
			$log->debug("GOt $posterurl");
			$posterurl = URI::Escape::uri_unescape( $posterurl );
			if ( ! $posterurl =~ /^http/i ) {
				$posterurl = $base_url.$posterurl;
			} # end if
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
		} # end if img
		$desc =~ s/<br ?\/>//;
		$desc =~ s/<br ?\/>//;
		$log->debug("Title: $title\n, When: $year $month $day\n desc: $desc");

		my ( $hour, $minute, $ending_hour, $ending_minute ) = ( 21, 0, 3, 30 );
		my ( $ending_year, $ending_month, $ending_day ) = Date::Calc::Add_Delta_Days( $year, $month, $day, 1 );

		if ( ! Date::Calc::check_date( $year, $month, $day ) ) {
			$log->error(" Got event $title, $year-$month-$day $hour:$minute until $ending_year-$ending_month-$ending_day $ending_hour:$ending_minute");
			next;
		} else {
			$log->debug(" Got event $title, $year-$month-$day $hour:$minute until $ending_year-$ending_month-$ending_day $ending_hour:$ending_minute");
		} # end if

		my $starting_on = sprintf('%.4d-%.2d-%.2d %.2d:%.2d:00', $year, $month, $day, $hour, $minute );
		my $ending_on = sprintf( '%.4d-%.2d-%.2d %.2d:%.2d:00', $ending_year, $ending_month, $ending_day, $ending_hour, $ending_minute );

		my $Event = openprint::Event->find_one( created_by=>$$User{id}, name=>$title, starting_on => $starting_on, template => 0 );

		if ( $Event ) {
			if ( ! defined $Event->time_associated() ) {
				$_ = $Event->save({time_associated =>  ( $hour ? 1 : 0 )});
				die $_ if $_;
			} # end if
			if ( ! defined $Event->category_id() ) {
				$_ = $Event->save({category_id=>$$Category{id}});
				die $_ if $_;
			} # end if
			next if (
					( $Event->info() eq $desc ) 
					and $$Event{album_id}
	#and ( $event->starting_on() eq $starting_onI#
					);
		} else {
			$Event = new openprint::Event();
		} # end if
		$_ = $Event->save({
			name =>  $title,
			starting_on	=>	$starting_on,
			ending_on	=>	$ending_on,
			info		=>	$desc,
			location_id	=>	$Location->id(),
			created_by	=>	$User->id(),
			template	=>	0,
			time_associated =>	( $hour ? 1 : 0 ),
			category_id	=>	$$Category{id},
			});
		die $_ if $_;
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

	} # end foreach event
		
} # end foreach post

1;
__END__
