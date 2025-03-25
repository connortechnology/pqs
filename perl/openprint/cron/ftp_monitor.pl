#!/usr/bin/perl
use utf8;
use lib '/etc/apache2/lib/perl';
use strict;
use warnings;

require configuration;
require sql;
require ssi;
require misc;
require openprint::Company;
require openprint::User;
require Email::Valid;
require openprint::Email;
require openprint::User_Notification;
require openprint::Host;
require openprint::Host_Interface;
require logger;
require openprint::Upload;
require openprint;
require openprint::File;
require openprint::Log;

use vars qw( $log $dbh %config );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;

use File::Basename qw(basename);
use Getopt::Long ();
use Mail::Sendmail ();
use MIME::QuotedPrint qw(encode_qp);
use MIME::Base64 qw(encode_base64);
use Encode ();
use Data::Dumper;
use Date::Parse;

my @banned_files = ( 'ftpchk3' );
my $program = basename($0);

my $opts = {};
Getopt::Long::GetOptions($opts, 'attach-file', 'fifo=s', 'from=s', 'help', 'ignore-users=s',
	'log_file=s', 'log_level=s',
	'recipient=s', 'sleep=s', 'smtp_server=s', 'subject=s',
	'watch-users=s','pid_file=s', 'db_port=s', 'db_name=s', 'db_host=s', 'db_user=s', 'db_pass=s',
	'skin_path=s', 'document_root=s', 'file_path=s','site_title=s', 'site_url=s',
	'scoreboard=s','max_files=s', 'config=s',
);

if ($opts->{help}) {
	usage();
	exit 0;
}

my %codes = (
	200	=> 'Command okay',
	212	=>	'Directory status',
	213	=>	'File status',
	215	=>	'NAME system type',
	221	=>	'Service closing control connection',
	226 =>  'Closing data connection',
	227 => 	'Entering Passive Mode',
	230	=>	'User logged in',
	234 =>	'AUTH TLS successful',
	250 =>	'Requested file action okay, completed',
	257	=>	'Path created',
	331 =>	'User name ok, need password',
	350	=>	'Requested file action pending further information.',
	500	=>	'Syntax error, command unrecognized, command line too long',
	530	=>	'User not logged in',
	550	=>	'Requested action not taken. File unavailable, not found, not accessible',
);
my %defaults = (
    config  =>  '/etc/openprint/ftp_monitor.conf',
);
foreach my $default ( keys %defaults ) {
    $$opts{$default} = $defaults{$default} if ! $$opts{$default};
} # end foreach default

$log = new logger(level=>'debug', program=>$program);
# Get our configuration information
if (my $err = configuration::from_file($$opts{config})) {
    die $err;
}
configuration::merge( $opts );
foreach my $param ( 'db_name','db_user','db_pass','fifo','from','recipient','smtp_server' ) {
	if ( ! $openprint::config{$param} ) {
		die "$program: missing required --$param parameter";
	}
} # end foreach required-param

if ( $config{site_url} ) {
	$config{siteURL} = $config{site_url};
	$config{ExternalSiteURL} = $config{site_url};
} # end if

$config{SiteTitle} = $config{site_title};
$config{SkinPath} = $config{skin_path};
$config{log_level} = 'debug' if ! $config{log_level};
$config{sleep} = 1.0 if ! $config{sleep};

if ( $config{pid_file} ) {
	my $pidh;
	if (open($pidh, '> '.$config{pid_file} ) ) {
		print $pidh $$."\n";
		close($pidh);
	} else {
		die "Unable to open pid file";
	} # end if
} # end if

$openprint::log = logger->new( { file=>$config{log_file}, level=>$config{log_level}} );
$log->info("Opening SQL connection $config{db_host} $config{db_name}");
$openprint::dbh = sql::open_sql( $log,
	port		=> $config{db_port},
	host		=> $config{db_host},
	database	=> $config{db_name},
	driver		=> 'Pg',
	login		=> $config{db_user},
	password	=> $config{db_pass},
);
die 'Error opening db' if ! $dbh;
configuration::init( \%config );
configuration::from_file($$opts{config});
openprint::session_init();
# Cache of recently completed uploads.  keys are username, value is array of upload hashes.  When the user is no longer logged in or
# older than a certain age, the email notification should go out, and the hash entry cleared.
my %uploads;
my %Users; # Cache of User Objects keyed by user/email address

#my $scoreboard = get_scoreboard( $config{scoreboard} );
my $fifoh;
$log->debug("Opening fifo at $config{fifo}");
if (open($fifoh, "< $config{fifo}")) {
$log->debug("Opened fifo at $config{fifo}");
	while (1) {
		my $line;
		eval {
			local $SIG{ALRM} = sub { die "alarm\n" };
			alarm 10;
			$line = <$fifoh>;
			alarm 0;
		}; # end eval
		if ( $@ ) {
			die unless $@ eq "alarm\n";
			check_scoreboard();
			# Update DB scoreboard
			next;
		} elsif ($line) {
			chomp($line);

			#xferlog format
			if ($line =~ /^(\S+\s+\S+\s+\d+\s+\d+:\d+:\d+\s+\d+)\s+(\d+)\s+(.*?)\s+(\d+)\s+(.*?)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.*?)\s+.*?(\S+)$/o) {
				my $curr_time = $1;
				my $xfer_nsecs = $2;
				my $client = $3;
				my $nbytes = $4;

				# Note that any spaces or control characters will be replaced in this
				# path with underscores.	This can make finding the actual file, as for
				# attachments, rather difficult; we have to test to find the difference
				# between a real underscore in the name, and a substituted underscore.
				my $path = $5;
				my $xfer_type = $6;
				my $action_flag = $7;
				my $xfer_direction = $8;
				my $access_mode = $9;
				my $user_name = $10;
				my $completion_status = $11;

				unless (-e $path) {
					# Perform a quick-and-dirty check, on the assumption that all of the
					# underscores in the given path are actually spaces.	If a
					# combination of underscores and spaces appears in the real file,
					# we won't detect that here.

					my $alt_path = $path;
					$alt_path =~ s/_/ /g;

					if (-e $alt_path) {
						$path = $alt_path;
					}
				}

				my $bad = 0;
				foreach my $banned_re ( @banned_files ) {
					if ( $path =~ /$banned_re/i ) {
						# Detected bad file
						$bad = 1;
						last;
					} # end if
				} # end foreach banned_re
				if ( $bad ) {
					# Take evasive action
					take_evasive_action($user_name, $client);
					next;
				} # end if


				my $send_email = $xfer_direction eq 'i' ? 1 : 0;

				if ($send_email) {

					# First, check for any specific --watch-users filter.	If configured,
					# and if the user name does NOT match the --watch-users filter, then
					# don't send email.	Otherwise, check for an --ignore-users filter,
					# and see if the user matches that ignore filter.

					if ($config{'watch-users'}) {
						if ($user_name !~ /$config{'watch-users'}/) {
							$send_email = 0;
						}
					} elsif ($config{'ignore-users'}) {
						if ($user_name =~ /$config{'ignore-users'}/) {
							$send_email = 0;
						}
					}
				} # end if send email

				if ($send_email) {
					push @{$uploads{$user_name}}, {
						timestamp => $curr_time,
						duration => $xfer_nsecs,
						client => $client,
						size => $nbytes,
						file => $path,
						transfer_type => $xfer_type,
						auth_mode => $access_mode,
						user => $user_name,
						status => $completion_status,
						complete	=> ( $completion_status eq 'c' ? 1 : 0 ),
					};
				} # end if send email
			} elsif (0 and $line =~ /^(\S+)\s+(\S+)\s+(\S+)\s+\[([^\]]+)\]\s+"(\S+)\s+([^"]+)"\s+(\d+)\s+(\d+)$/o) {

				my $client = $1;
				my $remote_user = $2;
				my $user_name = $3;
				my $curr_time = $4;
				my $xfer_type = $5;
				my $path = $6;

				my $xfer_nsecs = $7;
				my $nbytes = $8;
$log->debug("Gotextended line: $line");
$log->debug("data: $client $remote_user $user_name $curr_time $xfer_type $path $xfer_nsecs $nbytes");

				# Note that any spaces or control characters will be replaced in this
				# path with underscores.	This can make finding the actual file, as for
				# attachments, rather difficult; we have to test to find the difference
				# between a real underscore in the name, and a substituted underscore.
				#my $action_flag = $7;
				#my $xfer_direction = $8;
				#my $access_mode = $9;
				#my $completion_status = $11;

				my $bad = 0;
				foreach my $banned_re ( @banned_files ) {
					if ( $path =~ /$banned_re/i ) {
						# Detected bad file
						$bad = 1;
						last;
					} # end if
				} # end foreach banned_re
				if ( $bad ) {
					# Take evasive action
					take_evasive_action($user_name, $client);
					next;
				} # end if

				my $send_email = $xfer_type eq 'STOR' ? 1 : 0;

				if ($send_email) {

					# First, check for any specific --watch-users filter.	If configured,
					# and if the user name does NOT match the --watch-users filter, then
					# don't send email.	Otherwise, check for an --ignore-users filter,
					# and see if the user matches that ignore filter.

					if ($config{'watch-users'}) {
						if ($user_name !~ /$config{'watch-users'}/) {
							$send_email = 0;
						}
					} elsif ($config{'ignore-users'}) {
						if ($user_name =~ /$config{'ignore-users'}/) {
							$send_email = 0;
						}
					}
				} # end if send email

				if ($send_email) {
					push @{$uploads{$user_name}}, {
						timestamp => $curr_time,
						duration => $xfer_nsecs,
						client => $client,
						size => $nbytes,
						file => $path,
						transfer_type => $xfer_type,
						#auth_mode => $access_mode,
						user => $user_name,
						status => 'c',
						complete	=> 1,
					};
				} # end if send email
			} elsif ($line =~ /^(\S+)\s+(\S+)\s+(\S+)\s+\[([^\]]+)\]\s+"([^"]*)"\s+"([^"]*)"\s+(\S+)\s+(\d+)\s+([\-\d]+)\s+([\.\d\-]+)$/o) {
#LogFormat IQFormat "%h %l %u %t \"%d\" \"%f\" %m %s %b %T"

				my $client = defined $1 ? $1 : '';
				my $remote_user = defined $2 ? $2 : '';
				my $user_name = defined $3 ? $3 : '';
				my $curr_time = defined $4 ? $4 : '';
				my $dir = defined $5 ? $5 : '';
				my $path = defined $6 ? $6 : '';
				my $command = defined $7 ? $7 : '';
				my $response_code = defined $8 ? $8 : '';
				my $nbytes = defined $9 ? $9 : '';
				my $xfer_nsecs = defined $10 ? $10 : '';
				$log->debug("Got IQFormat extended line: $line");
				if ( ! defined $codes{$response_code} ) {
					$log->error("Need to define the response code for $response_code");
				}
				$log->debug("data: client:$client remote_user:$remote_user username:$user_name time:$curr_time dir:$dir path:$path command:$command code:$response_code(".(exists($codes{$response_code})?$codes{$response_code}:'unknown code').") bytes:$nbytes");
				if ( $response_code == 331 ) {
#Username OK, need password
					next;
				} elsif ( $command eq 'LIST' or $command eq 'MLSD' or $command eq 'CDUP' or $command eq 'RETR' ) {
$log->debug("Command was not an upload");
					next;
				} elsif ( $response_code == 230 ) {
# Successful login
					my $User = openprint::User->find_one( email => $user_name, ftp_active => 1 );
					if ( ! $User ) {
						$log->error("Unable to load user for a valid ftp account.");
						next;
					}
					(new openprint::Log())->save({Object=>$User, action=>'Login', note=>'Successful FTP Login' } );
					next;
				} elsif ( $response_code == 350 ) {
					$log->debug("Requested file action pending further information. ");
					next;
				} elsif ( $response_code == 257 ) {
					$log->debug("PWD");
					next;
				} elsif ( $response_code == 550 ) {
					$log->debug("Action not taken ");
					next;
				} elsif ( $response_code == 257 ) {
					$log->debug("Path Created, ignoring");
					next;
				} elsif ( $nbytes eq '-' ) {
					$log->debug("Not an upload, ignoring");
					next;
				} elsif ( $response_code != 226 ) {
					$log->debug("Not an upload, response_code: $response_code");
					next;
				} elsif ( $path eq '-' ) {
					$log->debug("Not an upload, response_code: $response_code path was $path");
					next;
				} elsif ( -d $path ) {
					$log->debug("Was creating a dir at $path, no notification");
					next;
				}

				# Note that any spaces or control characters will be replaced in this
				# path with underscores.	This can make finding the actual file, as for
				# attachments, rather difficult; we have to test to find the difference
				# between a real underscore in the name, and a substituted underscore.
				#my $action_flag = $7;
				#my $xfer_direction = $8;
				#my $access_mode = $9;
				#my $completion_status = $11;

				my $bad = 0;
				foreach my $banned_re ( @banned_files ) {
					if ( $path =~ /$banned_re/i ) {
						# Detected bad file
						$bad = 1;
						last;
					} # end if
				} # end foreach banned_re
				if ( $bad ) {
					# Take evasive action
					take_evasive_action($user_name, $client);
					next;
				} # end if

				my $send_email = 1;

				if ($send_email) {

					# First, check for any specific --watch-users filter.	If configured,
					# and if the user name does NOT match the --watch-users filter, then
					# don't send email.	Otherwise, check for an --ignore-users filter,
					# and see if the user matches that ignore filter.

					if ($config{'watch-users'}) {
						if ($user_name !~ /$config{'watch-users'}/) {
							$send_email = 0;
						}
					} elsif ($config{'ignore-users'}) {
						if ($user_name =~ /$config{'ignore-users'}/) {
							$send_email = 0;
						}
					}
				} # end if send email

				if ( $send_email ) {
					my $already_uploading = 0;
					foreach my $U ( @{$uploads{$user_name}} ) {
						if ( $$U{file} eq $path ) {
							$$U{size} += $nbytes;
							$$U{duration} += $xfer_nsecs;
							$already_uploading = 1;
							last;
						}
					}
					if ( !$already_uploading ) {
$log->debug("Queing upload $path");
						push @{$uploads{$user_name}}, {
							timestamp => $curr_time,
							duration => $xfer_nsecs,
							client => $client,
							size => $nbytes,
							file => $path,
							transfer_type => 'STOR',
							#auth_mode => $access_mode,
							user => $user_name,
							status => 'c',
							complete	=> 1,
						};
					} # end if
				} # end if send email
			} else {
				$log->error("Unparsed line $line");
			} # end if

			#$log->debug("$line\n");
			$line = undef;
		} else {
			# No input at this time. Sleep for half a second (or less) and check again.
#$log->debug( "No input\n" );
			check_scoreboard();
			sleep($config{sleep}?$config{sleep}:10);
		} # End if $line

		if ( ! $dbh->ping() ) {
			$log->warn("REOpening SQL connection");
			$openprint::dbh = sql::open_sql( $log,
					host		=> $config{db_host},
					database	=> $config{db_name},
					driver		=> 'Pg',
					login		=> $config{db_user},
					password	=> $config{db_pass},
					);
			die 'Error opening db' if ! $dbh;
			configuration::init( \%config );
			configuration::from_file($$opts{config});
		} # end if
	} # end while <input>

	close($fifoh);
	$dbh->disconnect() if $dbh and $dbh->ping();
} else {
	die "$program: unable to read FIFO '$config{fifo}': $!\n";
}
if ( $config{pid_file} ) {
	unlink $config{pid_file};
} # end if

sub check_scoreboard {
	my $scoreboard = get_scoreboard( $config{scoreboard} );
	my @users = map { $$_{user} } @$scoreboard;
	#$log->debug( "Users: @users in scoreboard\n" );

	foreach my $username ( keys %uploads ) {
		if ( ! exists $Users{$username} ) {
			my $User = openprint::User->find_one('email lc'=>lc $username);
			if ( $User ) {
				$Users{$username}= $User;
				(new openprint::Log())->save({action=>'Login', note=>'Successful FTP Login' } );
			} # end if
		} # end if

		if ( ( ! sets::isin( $username, \@users ) ) or ( $config{max_files} and ( @{$uploads{$username}} > $config{max_files} ) ) ) {

$log->debug("Max_files: $config{max_files}");

			if ( $config{wait_before_emailing} ) {
				# Assume the last file is the most recent
				my $Upload = $uploads{$username}[@{$uploads{$username}}-1];
				my $timestamp = Date::Parse::str2time($$Upload{timestamp});
				my $time = time;
				my $diff = $time - $timestamp;
				$log->debug("Timestamp: $timestamp < $time diff: $diff" );
				if ( $diff < $config{wait_before_emailing} ) {
					$log->debug("waiting before emailing for more uploads");
					next;
				} else {
					$log->debug("Not waiting before emailing for more uploads $config{wait_before_emailing}");
				} # end if
			} else {
				$log->debug("No wait_before_emailing set");
			} # end if wait_before_emailing
			$log->debug( "Sending mail for $username\n" );
# No longer logged in, so we can process and send emails.
			send_email( @{$uploads{$username}} );
			delete $uploads{$username};
		} else {
			$log->debug( "Holding mail for $username\n" );
		} # end if
	} # end foreach $user
} # end sub check_scoreboard

sub send_email {
	my @uploads = @_;
	if ( ! @uploads ) {
		$log->error("No uploads!");
		return;
	} # end if
	my $upload = $uploads[0];
	# Try to get User first.  It's going to be the fastest lookup

	my $Company;
	my $User;
	my @Users = openprint::User->find(email=>lc $upload->{user},ftp_active=>1);
	if ( ! @Users ) {
		$log->error("OH NO! No user found for $$upload{user}");
	} elsif ( @Users > 1 ) {
		$log->error("OH NO! More than one user found for $$upload{user}");
		$User = $Users[0];
	} else {
		$User = $Users[0];
		$Company = $User->Company();
	}
	my $company_name;
	if ( $Company ) {
		$company_name = $Company->name();
	} # end if

	my $project_files_path = $config{file_path};

	foreach my $upload ( @uploads ) {
		my $file = $upload->{file};
# File should be the full path, relative to filesystem root.
# Problem is, spaces have been replaced by underscores
$log->debug("Processing upload $file");
		my $file_str = basename($file);
		$$upload{file_str} = $file_str;
		$$upload{company_name} = $company_name;

    #The purpose is to strip off the base path, leaving subdirs and actual file name
		my $regexp = '^'.quotemeta($project_files_path).'\/'.quotemeta($company_name).'\/(.+)\$';
$log->debug("regexp: $regexp");
		@$upload{proper_file_path} = $file =~ /$regexp/;
		if ( ! $$upload{proper_file_path} ) {
			$regexp = "^.*\\/\Q$company_name\E\\/(.+)\$";
			$log->debug("Trying a more generic regexp $regexp against $file");
			@$upload{proper_file_path} = $file =~ /$regexp/;
		}
    if ( ! $$upload{proper_file_path} ) {
      $log->warn("Failed to match path. Setting to $$upload{file_str}");
      $$upload{proper_file_path} = $$upload{file_str};
    }

    # Now that we have just the subdir and file, we should turn it into a regexp to convert _ to spaces
	} # end foreach upload

	my $subject;
	if ($config{subject}) {
		$subject = $config{subject};
	} elsif ( scalar @uploads == 1 ) {
		$subject = "User '$upload->{user}' uploaded file '$$upload{proper_file_path}' via FTP";
	} else {
		$subject = "User '$upload->{user}' has uploaded files via FTP";
	} # end if

	my $dbh_count = 1;
	while ( ! ( $openprint::dbh and $openprint::dbh->ping() ) ) {
		$openprint::dbh = sql::open_sql( $log,
			host		=> $config{db_host},
			database	=> $config{db_name},
			driver		=> 'Pg',
			login		=> $config{db_user},
			password	=> $config{db_pass},
		);
		$log->error("Unable to connect to database, try $dbh_count. sleeping.");
		$dbh_count += 1;
		sleep(1);
	} # end while no db connection

	my @Uploads = ();

	foreach my $upload ( @uploads ) {
		my $Upload = new openprint::Upload();
		my $error = $Upload->save({
			(company_id	=>	$Company ? $Company->id() : undef),
			(user_id		=>	$User ? $User->id() : undef ),
			company			=>	$$upload{company_name},
			size			=>	$upload->{size},
			total			=>	$upload->{size},
			finished		=>	$upload->{timestamp},
			start			=>	$upload->{timestamp},
			file_path		=>	$$upload{proper_file_path},
			type			=>	'FTP',
			complete		=>	$$upload{complete},
		});
		$log->debug("UPload status: ($$upload{status})");
		if ( $error ) {
			$log->error( $error );
		} else {
		push @Uploads, $Upload;
			my $File = new openprint::File();
			$error = $File->save({
				size		=>	$upload->{size},
				filename	=>	$$upload{proper_file_path},
				upload_id	=>	$Upload->id(),
			});
			$log->error( $error ) if $error;
		} # end if
	} # end foreach upload

	if ( $Company and $User ) {
		my $from;
		if ( ! Email::Valid->address( $User->email() ) ) {
			$from = $config{OrderingEmail};
		} else {
			$from = sprintf('"%s" <%s>', $User->name(), $User->email() );
		} # end if

		my @to;
		if ( $User->email() =~ /^iconnor/ ) {
			@to = ( 'iconnor@connortechnology.com' );
		} else {
			if ( $Company->salesrep_id() ) {
				my $CSR = $Company->CSR();
				my $Notification = openprint::User_Notification->find_one( type=>'CSR Client File Uploads', 'value !=' => 'No', user_company_id=>[ $config{owner_id}, $Company->id() ] );

				if ( $Notification ) {
					@to = ( $CSR );
					$log->debug("Adding CSR $$CSR{email}");
				} else {
					$log->debug("Not Adding CSR $$CSR{email} : notifications etting:" );
				} # end if
			} # end if
			push @to, map { $_->User() } openprint::User_Notification->find( type=>'Client File Uploads',value=>'Yes', 'company_id is null or ='=>$Company->id(), company_id=>[ $config{owner_id}, $Company->id() ] );
		} # end if

		if ( ! @to ) {
			@to = ( $config{OrderingEmail} );
		} # end if
		if ( @to ) {
			my %variable;
			$variable{Company} = $Company;
			$variable{User} = $User;
			$variable{Uploads} = \@Uploads;

			$variable{ReplacementText} = ssi::include( '/email_content/ftp_csr_notification.html', \%variable );
			if ( ! $variable{ReplacementText} ) {
				$log->error("No CSR notification text");
			}
			my $body = ssi::include( '/email_template.html', \%variable );
			if ( ! $body ) {
				$log->error("No body notification text");
			}

			my $Mail = new openprint::Email();
			$Mail->send(
					FROM    => ( $config{AdministratorEmail} ? $config{AdministratorEmail} : $from ),
					'Reply-To'	=>	$from,
					TO      => \@to,
#BCC		=>	'iconnor@connortechnology.com',
					SUBJECT => $subject,
					ATTACHMENTS => [ '', MIME::QuotedPrint::encode_qp(Encode::encode('utf-8',$body)), 'text/html', 'quoted-printable' ]
				);
		} # end if
		#$openprint::dbh->disconnect();

	} elsif ( 1 ) {
	my $bytes_str = $upload->{size} == 1 ? 'byte' : 'bytes';
	my $status = $upload->{status} eq 'i' ? 'Incomplete' : 'Completed';
	my $secs_str = $upload->{duration} == 1 ? 'sec' : 'secs';
	my $type_str = $upload->{transfer_type} eq 'a' ? 'ASCII' : 'Binary';
	my $attached = ($config{'attach-file'} and -e $$upload{file}) ? '(attached)' : '';
	my $text = <<EOT;
File just uploaded via FTP:

	User: $upload->{user}
		Client: $upload->{client}

	File: $$upload{proper_file_path} $attached
		Size: $upload->{size} $bytes_str
		At: $upload->{timestamp}
		Duration: $upload->{duration} $secs_str
		Status: $status
		Transfer type: $type_str

Cheers,
	--$program

EOT
		my $email_info = {
			smtp => $config{smtp_server},
			From => $config{from},
			To => $config{recipient},
			#BCC	=>	'iconnor@connortechnology.com',
			Subject => $subject,
		};

		if ($config{'attach-file'}) {
			if (-e $$upload{file}) {
				$email_info->{'MIME-Version'} = '1.0';

				my $boundary = '====' . time() . '====';
				$email_info->{'Content-Type'} = "multipart/mixed; boundary=\"$boundary\"";
				$boundary = '--' . $boundary;

				$email_info->{Body} .= "$boundary\n";
				$email_info->{Body} .= "Content-Type: text/plain; charset=\"iso-8859-1\"\n";
				$email_info->{Body} .= "Content-Transfer-Encoding: quoted-printable\n\n";
				$email_info->{Body} .= "$text\n";

				if (open(my $fh, "< $$upload{file}")) {
					binmode($fh);

	# Note: this reads the entire file into memory, and can fail if
	# the file is too big.

					local $/;
					my $attach;
					while (my $data = <$fh>) {
						$attach .= $data;
					}
					close($fh);

					$email_info->{Body} .= "$boundary\n";

					$email_info->{Body} .= "Content-Disposition: attachment; filename=\"$$upload{file}\"\n";
					if ($upload->{transfer_type} eq 'a') {
						$email_info->{Body} .= "Content-Type: text/plain; charset=\"iso-8859-1\"\n\n";
						$email_info->{Body} .= $attach;

					} else {
						$email_info->{Body} .= "Content-Type: application/octet-stream\n";
						$email_info->{Body} .= "Content-Transfer-Encoding: base64\n\n";
						$email_info->{Body} .= MIME::Base64::encode_base64(Encode::encode('utf-8',$attach));
					}

					$email_info->{Body} .= "\n";

				} else {
					my $timestamp = scalar(localtime());
					$log->error( "$program: $timestamp: error reading file '$$upload{file}' for attaching: $!" );
				}

			} else {
	# Couldn't find/access the uploaded file on the filesystem.	This usually
	# indicates either a permissions problem, or a munged filename.
	#
	# XXX Need to handle this better.
			}

		} else {
			$email_info->{Body} = $text;
		}

		my $res = Mail::Sendmail::sendmail(%$email_info);
		unless ($res) {
			my $timestamp = scalar(localtime());

			$log->error( "$program: $timestamp: error sending email: $Mail::Sendmail::error" );
		}
	} # end if can figure out company name or not
} # end sub send_email

sub usage {
	print <<EOH;

usage: $program [--help] [--fifo \$path] [--from \$addr] [--log \$path] [--pid_file \$pid]
	[--recipient \$addr] [--subject \$string] [--smtp_server \$addr]
	[--attach-file] [--ignore-users \$regex | --watch-users \$regex]

The purpose of this script is to monitor the TransferLog written by proftpd
for uploaded files.	Whenever a file is uploaded by a user, an email will be
sent to the specified recipients.	In the email there will be the timestamp,
the name of the user who uploaded the file, the path to the uploaded file, the
size of the uploaded file, and the time it took to upload.

Command-line options:

	--attach-file		If used, this will cause a copy of the uploaded file
			to be included, as an attachment, in the generated
			email.

	--fifo \$path		Indicates the path to the FIFO to which proftpd is
			writing its TransferLog.	That is, this is the path
			that you used for the TransferLog directive in your
			proftpd.conf.	This parameter is REQUIRED.

	--from \$addr		Specifies the email address to use in the From header.
			This parameter is REQUIRED.

	--help		Displays this message.

	--ignore-users \$regex
			Specifies a Perl regular expression.	If the uploading
			user name matches this regular expression, then NO
			email notification is sent; otherwise, an email is
			sent.

	--log \$path		Since this script reads the TransferLog using FIFOs,
			the actual TransferLog file is not written by default.
			Use this option to write the normal TransferLog file,
			in addition to watching for uploads.

	--pid_file \$pid			Specifies a file to put the pid in

	--recipient \$addr	Specifies an email address to which to send an email
			notification of the upload.	This option can be
			used multiple times to specify multiple recipients.
			AT LEAST ONE recipient is REQUIRED.

	--smtp_server \$addr	Specifies the SMTP server to which to send the email.
												This parameter is REQUIRED.

	--subject \$string	Specify a custom Subject header for the email sent.
			The default Subject is:

				User '\$user' uploaded file '\$file' via FTP

	--watch-users \$regex	Specifies a Perl regular expression.	If the uploading
			user name matches this regular expression, then an
			email notification is sent; otherwise, no email is
			sent.

EOH
}

sub time_stamp {
	my @w = reverse ( (localtime($_[0])) [0..5] );
	$w[0]+=1900; $w[1]++;
	return sprintf "%d-%02d-%02d %02d:%02d:%02d", @w;
}

sub get_scoreboard {
	my ( $score_file ) = @_;
	my ($server_uptime, $record);
	my @scoreboard;
#  pid_t pid;
#  uid_t uid;
#  gid_t gid;
#  char user[32];
#  int server_port;
#  char server_addr[80], server_label[32];
#  char client_addr[INET_ADDRSTRLEN];
#  char client_name[PR_TUNABLE_SCOREBOARD_BUFFER_SIZE];
#  char class[32];
#  char cwd[PR_TUNABLE_SCOREBOARD_BUFFER_SIZE];
#  char cmd[5];
#  char cmd_arg[PR_TUNABLE_SCOREBOARD_BUFFER_SIZE];
#  time_t begin_idle, begin_session;
#  off_t xfer_size, xfer_done, xfer_len;
#  unsigned long xfer_elapsed;
#0000000 beef dead 0000 0000 0002 0104 0000 0000
#0000010 2c20 0000 0000 0000 3d87 4c78 0000 0000
#0000020 307c 0000 0021 0000 0021 0000 6369 6e6f

	my $header = "L L l L L L L L";
	my $template = "L L L A32 L A80 A32 A16 A80 A32 A80 A5 A79 L L L L L L";
	my $recordsize = length(pack($template,(  )));
	if ( open(SCORE,$score_file) ) {
		my $headersize = length(pack($header));
		read(SCORE, $record, $headersize );
		while (read(SCORE,$record,$recordsize)) {
			my %score;
			@score{'sce_pid','sce_uid','sce_gid','sce_user','sce_server_port','sce_server_addr',
				'sce_server_label','sce_client_addr','sce_client_name','sce_class','sce_cwd','sce_cmd','sce_cmd_arg','sce_begin_idle','sce_begin_session',
				'sce_xfer_size','sce_xfer_done','sce_xfer_len','sce_xfer_elapsed'} = unpack($template,$record);
			if ($score{sce_pid} != 0) {
				push @scoreboard, \%score;
			} # end if
		} # end while
		close(SCORE);
	} else {
		$log->warn("Unable to open scoreboard at $score_file: reason $!");
		sleep 1;
	} # end if
	return \@scoreboard;
} # end sub get_scoreboard

sub take_evasive_action {
	my ( $username, $client ) = @_;

	my $dbh_count = 1;
	while ( ! ( $openprint::dbh and $openprint::dbh->ping() ) ) {
		$openprint::dbh = sql::open_sql( $log,
			host		=> $config{db_host},
			database	=> $config{db_name},
			driver	=> 'Pg',
			login		=> $config{db_user},
			password	=> $config{db_pass},
		);
		$log->error("Unable to connect to database, try $dbh_count. sleeping.");
		$dbh_count += 1;
		sleep(1);
	} # enw hwhile no db connection

	my $User = openprint::User->find_one('email lc'=>lc $username, ftp_active=>1 );
	if ( ! $User ) {
		$log->warn("unable to load ftpable user account for $username");
		return;
	} # end if
	$User = openprint::User->find_one('email lc'=>lc $username );
	if ( ! $User ) {
		$log->warn("unable to load insecure user account for $username");
		return;
	} # end if

	my $Company = $User->Company();
	my @To = ( $config{TechSupportEmail}, $username );

	if ( $Company->salesrep_id() ) {
		push @To, $Company->CSR();
	} # end if

	my %variable;
	$variable{Company} = $Company;
	$variable{User} = $User;
$log->debug("Email sent to @To from $config{TechSupportEmail}");

	$variable{ReplacementText} = ssi::include( '/email_content/ftp_account_compromised.html', \%variable );
	if ( $variable{ReplacementText} ) {
		my $email_template = ssi::slurp_content( '/email_template.html' );
		my $body = ssi::variable_substitution( \$email_template, \%variable );
		my $Mail = new openprint::Email();
		$Mail->html_body( $body );
		$_ = $Mail->send(
				FROM    =>	$config{TechSupportEmail},
				TO      =>	\@To,
				SUBJECT =>	'FTP Account compromised',
			);
		$log->debug("Email sent to $_");
		$_ = $User->save({ ftp_active=>0, change_password=>'Y' });
		$log->error($_) if $_;
	} else {
		$log->error("No email content for 'ftp_account_compromised.html'");
	} # end if
	if ( $client ) {
		$log->debug("Blacklisting client $client");
		my $ip;
		# FIXME someday this will have to be updated to detect ipv6
		if ( $client =~ /[^\d\.]/ ) {
			$_ = gethostbyname($client);
			if ( defined $_ ) {
				$ip = Socket::inet_ntoa($_);
				$log->debug( "Got $ip for $client\n");
			} # end if
		} else {
			$ip = $client;
		} # end if
		if ( $ip ) {
			my @Interfaces = openprint::Host_Interface->find(ip=>$ip);
			if ( @Interfaces ) {
				foreach my $Interface ( @Interfaces ) {
					my $Host = $Interface->Host();
					(new openprint::Log())->save({
							Object		=>	$Host,
							action	=> 'Intrusion',
							note		=> "FTP violation. User account $username",
							host_id		=> $$Host{id},
							user_id		=> $$User{id},
							company_id	=> $$User{company_id},
							} );
					if ( ! ( $Host->blacklist() or $Host->whitelist() ) ) {
						$_ = $Host->save({blacklist=>1});
						if ( $_ ) {
							$log->error($_);
						} else {
							last;
						} # end if
					} # end if
				} # end foreach  Interface
			} else {
				my $Host = new openprint::Host();
				$Host->save({});
				my $Interface = new openprint::Host_Interface();
				$Interface->save({ ip=>$ip, host_id=>$$Host{id} });
			} # end if
		} # end if
	} else {
		$log->warn("No client to blacklist.");
	} # end if
} # end sub take_evasive_action

1;
__END__
