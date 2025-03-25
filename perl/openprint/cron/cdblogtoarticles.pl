#!/usr/bin/perl 
use lib '/var/www/testing/perl';
use 5.10.0;
use utf8;

# INCLUDES
use strict;
use WWW::Mechanize;
use CGI qw/:standard/;
use HTML::TreeBuilder;

use Data::Dumper;
require configuration;
require sql;
require ssi;
require misc;
require openprint::Company;
require openprint::User;
require Email::Valid;
require openprint::Email;
require openprint::User_Notification;
require logger;
require openprint::Wall;
require Date::Parse;
require Date::Format;
require openprint;
require openprint::User_Profile_Entry;

use vars qw( $log $dbh %config );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;

use File::Basename qw(basename);
use Getopt::Long;
use Mail::Sendmail;
use MIME::QuotedPrint;
use Time::HiRes qw(usleep);
use Encode qw(encode);

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
configuration::from_file('/etc/cdblogtoarticles.conf');
configuration::merge( $opts );
$log->level($config{'log_level'}) if $config{'log_level'};

# Declare variables
foreach my $param ( 'db_name','db_user','db_pass' ) {
	if ( ! $config{$param} ) {
		die "$program: missing required --$param parameter";
	}
} # end foreach required-param
if ( 0 ) {
$openprint::dbh = sql::open_sql( $log, 
	'host'		=> $config{'db_host'},
	'database'	=> $config{'db_name'},
	'driver'	=> 'Pg',
	'login'		=> $config{'db_user'},
	'password'	=> $config{'db_pass'},
);
die 'Error opening db' if ! $dbh;
}

# Login inputs are member and password, also need VIEWSTATE AND EVENTVALIDATION


my $mech = WWW::Mechanize->new();
$mech->get('http://cafedesire.com');

$mech->submit_form(
        form_name => 'Form1',
        fields    => { 
			'password'		=>	'XV32me',
			'member'		=>	'SAZZAANDSAAC',
		},
		button	=>	'Logon_btn',
    );
#print $mech->content();
$mech->get('http://cafedesire.com/user_blog.aspx?member=11321&name=THESENSUALS');
#print $mech->content();
my $tree = HTML::TreeBuilder->new;
$tree->parse_content($mech->content());
$tree->elementify();
foreach my $post ( $tree->look_down('class','post_message') ) {
	#$post->dump();
	my $post_date = $post->look_down('class','post_date')->as_text();
	$post_date =~ s/^Posted on: //g
	print $post_date."\n";

	my $title = $post->look_down('color','blue')->as_text();
	print $title."\n";

            $Article = new openprint::Article();
            $Article->save({
                'title' =>  $title,
                'body'  =>  $post->as_html(),
                'source'    =>  undef,
                #'published' =>  $Feed->published(),
                'published' =>  0,
                'published_on'  =>  Date::Format::time2str('%Y-%m-%d %H:%M:%S%z', Date::Parse::str2time( $post_date ) ),
                'created_on'    =>  Date::Format::time2str('%Y-%m-%d %H:%M:%S%z', Date::Parse::str2time( $post_date ) ),
                'company_id'    =>  $Feed->company_id(),
                'category_id'   =>  $Feed->category_id(),
                ( $User ? ( 'created_by'    => $User->id() ) : () ),
            });

} # end foreach post


1;
__END__
