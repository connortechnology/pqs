#!/usr/bin/perl
use lib qw( /etc/apache2/lib/perl );
use Linux::Inotify2;
use Fcntl qw(:flock);


use strict;

require misc;
require sql;
require logger;
require configuration;
use openprint ();
use Getopt::Long;
require IPC::Run3;
require Data::Dumper;
require openprint::Project;
require openprint::Email;

use vars qw( $log $dbh %config $use_compression $debug );

*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;
$debug = 0;
$log = logger->new();
$log->{level} = 'debug';

my $program = 'TIFMerge.pl';
my $opts = {};
GetOptions($opts, 'help', 'base_path=s','merge_path=s', 'debug=s', 'pid_file=s', 'config=s');

if ($opts->{help}) {
	usage();
	exit 0;
}
if ( $opts->{debug}) {
	$$log{level} = $opts->{debug};
}

configuration::init( );
$$opts{config} = '/etc/openprint/TIFMerge.conf' if ! $$opts{config};
if (my $err = configuration::from_file($$opts{config})) {
    die $err;
}

die if ! db_connect();

configuration::from_db();
configuration::merge( $opts );
$log = new logger( {file=>$config{log_file}, level=>$config{log_level}} );

if ( $config{pid_file} ) {
	my $pidh;
	if (open($pidh, '> '.$config{pid_file} ) ) {
		print $pidh $$."\n";
		close($pidh);
	} else {
		die "Unable to open pid file";
	} # end if
} # end if

while ( 1 ) {
	sleep 10;

	my ( @base_filenames, @imprint_filenames );
	if ( ! open(S, "> $config{base_path}/.lock.lck") ) {
		$log->error("Unable to open semaphoreat $config{base_path}/.lock.lck\n");
		next;
	} # end if
	if ( ! flock(S, LOCK_EX) ) {
		$log->error("Unable to lock semaphore\n");
		next;
	} # end if

	if ( opendir DIRHANDLE, $config{base_path} ) {
		@base_filenames = readdir DIRHANDLE;
		closedir DIRHANDLE;
	} else {
		print "Cannot open input hotfolder for $config{base_path}\n";
		next;
	} # end if

	if ( opendir DIRHANDLE, $config{imprint_path} ) {
		@imprint_filenames = readdir DIRHANDLE;
		closedir DIRHANDLE;
	} else {
		print "Cannot open imprint hotfolder for $config{imprint_path}\n";
		next;
	} # end if

#$log->warn("Remaining FIlenames before: @filenames");
	foreach my $file ( @base_filenames ) {
# Will ignore ., .., any hidden file
		next if $file =~ /^\./; 
		next if -d $config{base_path}.'/'.$file;

# CHeck AGE
if ( 0 ) {
		my $mtime = ( stat $file )[9];
		if ( time - $mtime < 2*60 ) {
			next;
		} # end if
}

		$log->debug("Have base file $file");
		my ( $docket, $file_base, $form, $side, $colour, $extension ) = $file =~ /^(\d+)(.*)\.(\d+)([AB])\.(\w)\.(TIF)$/i;
		$log->debug("Base Parsed to $docket $file_base, $form, Side: $side, $colour, $extension from $file") if $debug;

		foreach my $imprint_file ( @imprint_filenames ) {
			next if $imprint_file =~ /^\./; 
			next if -d $config{base_path}.'/'.$imprint_file;
			next if $imprint_file eq "${file_base}M.$colour.TIF";
			next if $imprint_file =~ /\.done$/;

			if ( ( $imprint_file =~ /^$docket([_A-Za-z0-9 ]*)\.(\d+)$side\.$colour(\.[^\.]+)?\.$extension$/ ) ) {
				my ($base, $imprint_form, $extra) = ($1, $2, $3);

				my $dest_file = "$config{merged_path}/${docket}${base}.$imprint_form$side.$colour$extra.M.TIF";
				if ( -e $dest_file ) {
					$log->debug("Skipping because $dest_file exists");
					next;
				}
				my $start_time = time;
				my ( $stdout, $stderr );
my $cmd = qq`/usr/local/bin/tiffmerge "$config{base_path}/$file" "$config{imprint_path}/$imprint_file" "$dest_file"`;
				$log->debug("Merging with $imprint_file using $cmd");
				IPC::Run3::run3( $cmd, undef, $stdout, $stderr );
				#GOODIPC::Run3::run3(qq`TMPDIR=/media/Brick2/tmp composite-im6 -compose Multiply "$config{base_path}/$file" "$config{imprint_path}/$imprint_file" "$config{merged_path}/${file_base}.$form$side.$colour.M.TIF"`, undef, $stdout, $stderr );
				#IPC::Run3::run3(qq`TMPDIR=/media/Brick2/tmp gm composite -compose Over "$config{base_path}/$file" "$config{imprint_path}/$imprint_file" "$config{merged_path}/${file_base}.$form$side.$colour.M.TIF"`, undef, $stdout, $stderr );
				if ( $? ) {
					$openprint::log->error("ERror merging mage. Reason: ($?) stdout($stdout) stderr($stderr)");
					next;
				}

				rename( $config{imprint_path}.'/'.$imprint_file, $config{imprint_path}.'/'.$imprint_file.'.done' );
				#unlink $config{imprint_path}.'/'.$imprint_file;
				my $runtime = misc::seconds_to_pretty_interval( time - $start_time );

				# Success, let's figure out who to email about it.
				if ( ! db_connect() ) {
					$log->error("Next because no db!");
					next;
				}

				my %Operators;
				foreach my $Project ( openprint::Project->find( docket=>$docket ) ) {
					my $services = $Project->services();
					foreach my $s_id ( @{$$services{Proofs}} ) {
						my $Service = $Project->Service( $s_id );
						foreach my $User ( $Service->Operators() ) {
							$Operators{$$User{id}} = $User;
						}
					}
				}	
				if ( %Operators ) {
					my $Email = new openprint::Email();
					$log->debug($Email->send(
						TO	=> [values %Operators],
						BCC=>'iconnor@point-one.com',
						FROM=>'iconnor@point-one.com',
						SUBJECT=>'Merged TIFF available',
						BODY	=>	 "
Base: $file
Imprint: $imprint_file
Runtime: $runtime
",

					));
				}
			} else {
				$log->debug("Didn't match $file and $imprint_file => $docket$file_base.$side.$colour.$extension");
			}
		} # end if
	} # end foreach file in input hotfolder
	close S;

} # end foreach Equipment
$dbh->disconnect() if $dbh;

sub db_connect {
	if ( ! ( $dbh and $dbh->ping() ) ) {
		$dbh = sql::open_sql( $log, 
				database	=> $config{'db_name'},
				driver		=> $config{'db_driver'}, 
				host		=> $config{'db_host'},
				port		=> $config{'db_port'},
				login		=> $config{'db_user'},
				password	=> $config{'db_password'},
				);
	}
	return $dbh;
}

sub usage {
	print <<EOH;

usage: $program [--help] [--db_name \$db_name] [--db_host \$db_host] [--db_user \$db_user] [--db_pass \$db_pass]

The purpose of this script is to monitor the hotfolders configured for each
press for PPF files and perform conversions for Heidelberg JDF, Merge front 
and backs for presses that require it, and to import the PPF previews and 
other data into the IntelligentQuote system.

Command-line options:

	--help		Displays this message.

EOH
}
1;
__END__
