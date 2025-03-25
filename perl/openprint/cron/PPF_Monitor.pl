#!/usr/bin/perl
use lib qw( /etc/apache2/lib/perl );
use Linux::Inotify2;
use Fcntl qw(:flock);


use strict;

require sets;
require sql;
require logger;
require configuration;
require openprint::CIP3_PPF;
require openprint::Project;
require openprint::service;
use openprint ();
use MIME::Base64;
use Getopt::Long;
use Compress::Zlib;

use vars qw( $log $dbh %config $use_compression $debug );

*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;
$use_compression = 1;
$debug = 1;
if ( $debug ) {
	require File::Copy;
}
my $mangle = 1;

$log = logger->new();
$log->{level} = 'warn';

my $program = 'PPF_Monitor.pl';
my $opts = {};
GetOptions($opts, 'help', 'db_name=s', 'db_host=s', 'db_user=s', 'db_pass=s','equipment_name=s','skin_path=s','debug=s', 'config=s');

if ( $opts->{help} ) {
	usage();
	exit 0;
}
$$opts{config} = "/etc/openprint/$program.conf" if !$$opts{config};

configuration::init();
configuration::from_file($$opts{config});
configuration::merge($opts);

if ( $config{debug} ) {
	$$log{level} = $config{debug};
}

foreach my $required ( qw( db_host db_name ) ) {
	unless ($config{$required}) {
		print STDERR "$program: missing required --$required parameter\n";
		exit 1;
	}
}
$config{db_user} = $config{db_name} if ! $config{db_user};
$config{db_pass} = $config{db_name} if ! $config{db_pass};

my %sql_config = (
		host      => $config{db_host},
		database  => $config{db_name},
		driver    => 'Pg',
		login     => $config{db_user},
		password  => $config{db_pass},
		);

$dbh = sql::open_sql($log, %sql_config) or die 'Error opening db';
configuration::from_db( );
configuration::from_file($$opts{config});
configuration::merge($opts);
$config{log_level} = 'debug' if ! $config{log_level};
$log = logger->new( {file=>$config{log_file}, level=>$config{log_level}} );

my @Equipment = openprint::Equipment->find(
		cip3_monitor=>1,
		( exists $opts->{equipment_name} ? ( strid=>$opts->{equipment_name}) : () ),
		);
if ( ! @Equipment ) {
	die "No equipment found.\n";
} # end if

# This script may hang on a remote fs after this point, so in iorder to not tie up db handles, we will disconnect and re-connect if neccessary.
$dbh->disconnect();

foreach my $Equipment ( @Equipment ) {
	$log->debug('Processing '.$Equipment->name());
	my @filenames;
	if ( ! open(S, "> $$Equipment{cip3_in}/.lock.lck") ) {
		$log->error("Unable to open semaphoreat $$Equipment{cip3_in}/.lock.lck");
		next;
	} # end if
	if ( ! flock(S, LOCK_EX) ) {
		$log->error('Unable to lock semaphore');
		next;
	} # end if
	if ( opendir DIRHANDLE, $Equipment->cip3_in() ) {
		@filenames = grep { /.ppf$/i } readdir DIRHANDLE;
		closedir DIRHANDLE;
	} else {
		print "Cannot open input hotfolder for $$Equipment{name} at $$Equipment{cip3_in}";
		next;
	} # end if
	my @filenames = readdir DIRHANDLE;
	closedir DIRHANDLE;

	if ( $$Equipment{cip3_merge} ) {
		#$log->warn("Merging..." ) if $debug;
		# First have to look for Back's, so that we don't process fronts before backs.
		# Have to copy, because we modify filenames
		my @Bs = @filenames;

		foreach my $file ( @Bs ) {
			# Will ignore ., .., any hidden file
			next if $file =~ /^\./;
			next if -d $Equipment->cip3_in().'/'.$file;
			my ( $file_base, $side, $extension ) = $file =~ /^(.*)([AB])\.(ppf)$/i;
$log->debug("Parsed to $file_base, $side, $extension from $file") if $debug;
			if ( $side ne 'B' ) {
$log->debug('Not a B') if $debug;
				next;
			} # end if

			my $out_base = $file_base;
			$out_base =~ s/\./_/g;

			$file_base =~ /^(?<DOCKET>\d+)(?<OP>\w\w)?_(?<COMPANY>.+?)Sg(?<SIG>\d+)/i;
			my ( $docket, $ppo, $name, $sig ) = ( $+{DOCKET}, $+{OP}, $+{COMPANY}, $+{SIG} );

			print "File: $file Docket $docket, Operator: $ppo, Name: $name, Sig: $sig, $side\n" if $debug;
			$sig = 0 if ! $sig;
			my $data;
			$side = 'M';
			if ( ! sets::isin($file_base.'A.'.$extension, \@filenames) ) {
				$log->warn('A file not found '.$$Equipment{cip3_in}.'/'.$file_base.'A.'.$extension.' ignoring B');
				next;
			} # end if
			@filenames = sets::exclude( [$file_base.'A.'.$extension,$file_base.'B.'.$extension], \@filenames );

			if ( ! open(FH, '< '.$$Equipment{'cip3_in'}.'/'.$file_base.'B.'.$extension) ) {
				$log->error('Error opening '.$$Equipment{'cip3_in'}.'/'.$file_base.'B.'.$extension);
				next;
			} # end if
			if ( ! flock(FH, LOCK_EX) ) {
				$log->error('Unable to lock B!');
				close(FH);
				next;
			} # end if

			my @Back;
			my $back_flag = 0;
			while ( <FH> ) {
				my $line = $_;
				$back_flag = 1 if ( $line =~ /CIP3BeginBack/ );
				push @Back, $line if $back_flag;
				last if $line =~ /CIPEndBack/;
			} # end while FH
			close(FH);
			if ( !@Back ) {
				$log->error('No Back found in B file!');
				rename $$Equipment{cip3_in}.'/'.$file_base.'B.'.$extension, $$Equipment{cip3_in}.'/'.$file_base.'E.'.$extension;
				next;
			} # end if
			@Back = $PPF->convert_job_name(@Back) if $mangle;

			my $A;
			my $A_filename = $$Equipment{'cip3_in'}.'/'.$file_base.'A.'.$extension;
			if ( !open($A, '< '.$A_filename) ) {
				$log->error('Error opening '.$A_filename);
				next;
			} # end if
			if ( !flock($A, LOCK_EX) ) {
				$log->error('Unable to lock A!');
				close($A);
				next;
			} # end if
			my $fileA = $file_base.'A';
			my $fileM = $file_base.'M';
			my $complete = 0;

			my @data;
			while ( <$A> ) {
				my $line = $_;
				next if $line =~ /^CIP3EndSheet/;
				if ( $line =~ /%%CIP3EndOfFile/ ) {
					$complete = 1;
					push @data, @Back;
				} else {
					$line =~ s/$fileA/$fileM/g;
					$PPF->convert_sheet_name( $line );
					$PPF->convert_job_name( $line ) if $mangle;
				} # end if
				$line =~ s/$fileA/$fileM/g;
				if ( $line =~ /^\/CIP3AdmSheetName \(Sheet (\d*)\) def/ ) {
					$line = sprintf("/CIP3AdmSheetName (Sig#%dSheet#%d) def\r\n", 1*$sig, $1);
				}
				if ( $mangle ) {
					if ( $line =~ /^\/CIP3AdmJobCode\s+\((.*)\)\s+def(.*)/ ) {
						if ( ! $1 ) {
							$line = "/CIP3AdmJobCode ($docket) def$2";
						} # end if
					} elsif ( $line =~ /^\/CIP3AdmJobName\s+\((.+)\)\s+def/ ) {
						my $job_name = $1;
						if ( length $job_name > 16 ) {
							if ( my ( $pre, $name, $sig ) = ( $job_name =~ /(\d+\w\w)(.+)SIG(\d\d\d)/ ) ) {
								$line = '/CIP3AdmJobName ('.$pre.substr($name, 0, 4).'Sg'.$sig."SdA) def\r\n";
							} else {
								$line = '/CIP3AdmJobName ('.substr($job_name, 0, 16).") def\r\n";
							} # end if
						} # end if
					} # end if
				} # end if mangle

				if ( $line =~ /CIP3EndOfFile/ ) {
					$data .= join('', @Back);
				} # end if
				$data .= $line;
			} # end while
			close $A;

			if ( ! $complete ) {
				$log->error('File was not complete! '.$Equipment->cip3_in().'/'.$file);
				next;
			} # end if
			if ( ! $data ) {
				$log->error("No data! $file_base $docket $sig $side");
				next;
			} # end if

			$dbh = sql::open_sql($log, %sql_config) or die 'Error opening db';
			my $PPF = store_PPF($docket, $name, $sig, $side, $Equipment, $data);
			$PPF->send_ppf($Equipment) if ! $$Equipment{cip3_hold};
			$dbh->disconnect();

			if ( $debug ) {
				File::Copy::move($$Equipment{cip3_in}.'/'.$file_base.'A.'.$extension,
						$$Equipment{cip3_in}.'/done/'.$file_base.'A.'.$extension);
				File::Copy::move($$Equipment{cip3_in}.'/'.$file_base.'B.'.$extension,
						$$Equipment{cip3_in}.'/done/'.$file_base.'B.'.$extension);
			} else {
				unlink $$Equipment{cip3_in}.'/'.$file_base.'A.'.$extension;
				unlink $$Equipment{cip3_in}.'/'.$file_base.'B.'.$extension;
			}
		} # end foreach file in input hotfolder
	} # end if cip3_merge

#$log->warn("Remaining FIlenames before: @filenames");
	foreach my $file ( @filenames ) {
		# Will ignore ., .., any hidden file
		next if $file =~ /^\./;
		next if -d ($Equipment->cip3_in().'/'.$file);

		if ( $file =~ /\.TIF$/i ) {
			# TIF's don't go here, delete them.
			unlink ($Equipment->cip3_in().'/'.$file);
			next;
		}

    # Check AGE
		my $mtime = ( stat $file )[9];
		if ( time - $mtime < 2*60 ) {
			$log->warn("File $file is too old");
			next;
		} # end if

		my ( $file_base, $side, $extension ) = $file =~ /^(.*)([AB])\.(ppf)$/i;
$log->debug("SINGLE SIDE Parsed to $file_base, $side, $extension from $file") if $debug;
		my $out_base = $file_base;
		$out_base =~ s/\./_/g;

		my ( $docket, $ppo, $name, $sig ) = $file_base =~ /^(\d+)(\w\w)?_?(.+?)S?g?(\d+)/i;

		if ( ! open(IN, '< '.$$Equipment{cip3_in}.'/'.$file) ) {
			$log->error('Error opening for read:'.$$Equipment{cip3_in}.'/'.$file);
			next;
		} # end if
		if ( ! flock(IN, LOCK_EX) ) {
			$log->error('Unable to lock CIP FILE!');
			close(IN);
			next;
		} # end if
		my $complete = 0;
		my @data;
		while ( <IN> ) {
			my $line = $_;
			if ( $line =~ /%%CIP3EndOfFile/ ) {
				$complete = 1;
			}
			if ( $line =~ /^\/CIP3AdmSheetName \(Sheet (\d*)\) def/ ) {
				$line = sprintf("/CIP3AdmSheetName (Sig#%dSheet#%d) def\r\n", 1*$sig, $1);
			}
			if ( $mangle ) {
				if ( $line =~ /^\/CIP3AdmJobCode\s+\((.*)\)\s+def/ ) {
					if ( ! $1 ) {
						$line = "/CIP3AdmJobCode ($docket) def\r\n";
					} # end if
				} elsif ( $line =~ /^\/CIP3AdmJobName\s+\((.*)\)\s+def/ ) {
					my $job_name = $1;
	#$log->warn("Truncating JobName $job_name");
					if ( length $job_name > 16 ) {
						if ( my ( $pre, $j_name, $sig ) = ( $job_name =~ /(\d+\w\w)(.+)SIG(\d\d\d)/ ) ) {
							$line = '/CIP3AdmJobName ('.$pre.(substr($j_name,0,4)).'Sg'.$sig.'Sd'.$side.") def\r\n";
						} else {
							$line = '/CIP3AdmJobName ('.(substr($job_name,0,16)).") def\r\n";
						} # end if
					} # end if
				} # end if
			} # end if
			push @data, $line;
		} # end while
		close IN;
		if ( ! $complete ) {
			$log->error('File was not complete! '.$Equipment->cip3_in().'/'.$file);
			next;
		} # end if

# NOt sure if these should be here
		@data = $PPF->convert_sheet_name( @data );
		@data = $PPF->convert_job_name( @data );

		$dbh = sql::open_sql($log, %sql_config) or die 'Error opening db';
		my $PPF = store_PPF( $docket, $name, $sig, $side, $Equipment, join('', @data));
		$PPF->send_ppf( $Equipment ) if ! $$Equipment{'cip3_hold'};
		if ( $debug ) {
			File::Copy::move($$Equipment{cip3_in}.'/'.$file, $$Equipment{cip3_in}.'/done/'.$file);
		} else {
			unlink $$Equipment{cip3_in}.'/'.$file;
		}
	} # end foreach file in input hotfolder
	close S;
} # end foreach Equipment
$dbh->disconnect() if $dbh;

sub store_PPF {
	my ( $docket, $version, $sig, $side, $Equipment, $data ) = @_;

	my $compressed_data;
	if ( $use_compression ) {
		$compressed_data = Compress::Zlib::compress($data);
		$log->warn('Compressed PPF from ' . (length $data) . ' to ' . (length $compressed_data) ) if $debug;
	} # end if
	my $PPF = new openprint::CIP3_PPF();
	$PPF->set({
			docket    	=>  $docket,
			signature 	=>  $sig,
			side      	=>  $side,
			version		=>	$version,
			data      	=>  encode_base64($compressed_data ? $compressed_data : $data),
			compressed	=>	($compressed_data ? 1 : 0),
			});

	if ( $docket ) {
		$_ = $PPF->save();
		$log->error($_) if $_;
		$PPF->generate_previews(undef,1);

		foreach my $Project ( openprint::Project->find(docket=>$docket,limit=>10) ) {
			my $services = $Project->services();

			my $found = 0;
			foreach my $ss_id ( $Project->signatures() ) {
				my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
				if ( $$services{'Signature'} ) {
					if ( $sig == $$sig_specs{'SignatureIndex'} ) {
						$found = 1;
						last;
					} # end if
				} elsif ( $sig == $$sig_specs{'SignatureIndex'}+1 ) {
					$found = 1;
					last;
				} # end if
			} # end foreach sig
			if ( ! $found ) {
				print "Adding new signature for $docket $sig $side\n";
				$Project->add_signature( $sig, 'Ordered', {
						'txtPrice'.$Project->ordered_quantity_index()	=> 0,
						txtSignatureType		=>	'Interior Pages',
						txtServiceDescription	=>	'Interior Pages',
						ddmRunStyleUsed		=>	$PPF->runstyle(),
						( map { 'ddmPress'.$_ => $$Equipment{strid} } ( $Project->quantity_indexes(), 'Used' ) ),
						} );
				$Project->add_to_log( undef, undef, "CIP3 Adding new form $sig $side." );
			} # end if
		} # end foreach Project
	} # end if
	return $PPF;
} # end sub store_PPF

sub usage {
	print <<EOH;

usage: $program [--help] [--db_name \$db_name] [--db_host \$db_host] [--db_user \$db_user] [--db_pass \$db_pass]

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

EOH
}
1;
__END__
