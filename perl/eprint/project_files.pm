package eprint::project_files;
use strict;
use warnings;

use Apache2::Const     qw(:common HTTP_MOVED_TEMPORARILY);
use Apache2::Util;
use Apache2::RequestUtil ();
use Fcntl                 qw(:flock);
use File::Copy            qw(cp);
use File::Path;
use File::MimeInfo::Magic qw(mimetype);
use MIME::QuotedPrint     qw(encode_qp);
use POSIX                 qw(strftime);

use configuration   ();
use eprint::project qw(project_allowed get_path has_pdf_template project_status);
use eprint::user    ();
use ssi             ();

require misc;


# Display the upload page.
sub display_upload {
    my ($r, $log, $dbh, $variable) = @_;

    my $pid = $variable->{pid} = $r->param('pid');

    # Is the user even allowed to view this project?
    # return FORBIDDEN unless project_allowed($dbh, $pid, $variable);

    # Does the project have any files?
    $variable->{files} = $dbh->selectrow_arrayref(q{
        SELECT true FROM project_files WHERE pid = ?
    }, undef, $pid);

    # Display users in the given company for sending email notification on
    # staff file uploads and approvals (through the system).
    $variable->{contacts} = project_contacts($dbh, $pid)
        if $variable->{is_staff};

# Use a port other than port 80 for uploading files.
#    my ($user, $pass, $host, $port) = $r->header_in('Host')
#        =~ /(?:([^:]+):([^\@]+)\@)?([^\@:]+)(?::(\d+))?/;
#
#    $variable->{domain} = $port ? '' : "http://$host:7080";

    return OK;
}

# Display the project files page. **NOTE** We synchronize (insert/delete)
# database entries for files added through the file system here as well.
sub display_files {
    my ($r, $log, $dbh, $variable) = @_;

    $variable->{pid} = $r->param('pid') || $r->param('ProjectIndex') unless $variable->{pid};

    my $pid = $variable->{pid};

    # Is the user even allowed to view this project?
    #return FORBIDDEN unless project_allowed($dbh, $pid, $variable);
	

	#print STDERR "GET FILES FOR PID: $pid - $variable->{pid} \n", Dumper($variable);

	use Data::Dumper;
	print STDERR Dumper($r->param());	
	map {
		print STDERR "HAVE PARAM $_ = " . $r->param($_) . "\n";
	} $r->param();

    my $projdir    = get_path(undef, $dbh, $pid);


	mkpath($projdir);

    my ($location) = $projdir =~ m|/customers/(.*$)|;
        $location  =~ tr|/|/|s;
        $location  = Apache2::Util::escape_path($location, $r->pool);

    $variable->{location} = $location;
    
    # User initials are required to confirm some actions.
    $variable->{user}{initials} = uc( 
         substr($variable->{user}{firstname}, 0, 1)
       . substr($variable->{user}{lastname},  0, 1)
    );




    # FILES
    #
    my $files = $dbh->selectall_hashref(q{
        SELECT f.filename, 
               f.description,
			   approval_info,
               approval_prepress,
               approval_production,
               u.strfirstname || ' ' || u.strlastname AS owner
        FROM project_files f 
          LEFT JOIN tbl_customer_users u ON (f.owner = u.lnguserid)
        WHERE pid = ?
    }, 'filename', undef, $pid);

    # For synchronizing file system with DB.
    my $add_file = $dbh->prepare(q{
        INSERT INTO project_files (pid, filename, approval_prepress) 
        VALUES (?, ?, 'Unknown User')
    });

    opendir my $dirhandle, $projdir or die "Couldn't open project directory ($projdir): $!";
    
    while (my $name = readdir($dirhandle)) {

        # Only display non-hidden files (no dirs, etc.)
        next if substr($name, 0, 1) eq '.' || ! -f "$projdir/$name";

        my ($mtime, $size) = (stat("$projdir/$name"))[9,7];

        $mtime = strftime "%Y-%m-%d %H:%M", localtime($mtime);
        $size  = format_size($size);

        my $icon = icon_lookup(mimetype("$projdir/$name"));

        if (exists $files->{$name}) {
            @{$files->{$name}}{qw(size mtime icon)} = ($size, $mtime, $icon);
        }
        else {
            # Add the previously unseen file to the database so approvals can
            # be attached to it.
            $add_file->execute($pid, $name);

            $files->{$name} = {
                filename => $name,
                size     => $size,
                mtime    => $mtime,
                icon     => $icon,
            }
        }
    }
    
    closedir $dirhandle or die "Couldn't close project directory: $!";

    # Sort the files into their display order (TODO different sort orders).
    $variable->{files} = [ @$files{ sort keys %$files } ];
                       # [ sort { $a->{filename} cmp $b->{filename} } values %$files ];


    # UPLOAD REDIRCT
    #
    # If the project doesn't have any files associated with it, redirect the
    # user to the upload page.
    my $templating = $variable->{is_staff} 
                  && has_pdf_template($log, $dbh, $pid);

    unless ( @{ $variable->{files} } || $templating ) {
        $r->status(HTTP_MOVED_TEMPORARILY);
        $r->headers_out->set(Location => "/main/proj/upload.html?pid=$pid" );
        return HTTP_MOVED_TEMPORARILY;
    }


    # PDF TEMPLATE GENERATION
    #
    # If the project has a template allow admins to generate/view final PDFs.
    if ($templating) {

        $variable->{has_pdf_template} = 1;

#		my $cust_name = $dbh->selectrow_array(q{
#			SELECT strcompanyname FROM tbl_customer, tbl_projects 
#			WHERE tbl_customer.lngcustomerid = tbl_projects.lngcustomerid
#			AND lngprojectindex = ?
#		}, undef, $pid);

#		my $order_id = $dbh->selectrow_array(q{
#			SELECT lngorderid FROM tbl_order_contents WHERE lngprojectindex = ?
#		}, undef, $pid);

        my $generated = get_zip_name($dbh, $pid).'.zip';

print STDERR "TEMPLATE: $generated GO \n";

        #my $generated = "$cust_name-$order_id-print_ready.zip";
        #my $generated = "$pid-print_ready.zip";

        # If we're a PDF template project and a final output has already
        # been generated, show the user.
        if (-e "$projdir/.template/$generated") { 
            $variable->{is_generated} = 1;

            my ($mtime, $size) = (stat _)[9,7];

            $mtime = strftime "%Y-%m-%d %H:%M", localtime($mtime);
            $size  = format_size($size);

            my $icon = icon_lookup(mimetype("$projdir/.template/$generated"));

            unshift @{ $variable->{files} }, {
                template    => 1,
                subdir      => '.template/',
                filename    => $generated,
                description => 'Print ready PDFs generated from a template.',
                owner       => '&lt;Special&gt;',
                size        => $size,
                mtime       => $mtime,
                icon        => $icon,
            }
        }
    }

    # NOTIFICATION
    #
    # Display users in the given company for sending email notification on
    # staff file uploads and approvals (through the system).
    $variable->{contacts} = project_contacts($dbh, $pid)
        if $variable->{is_staff};

	my $ordered = $dbh->selectrow_array(q{
		SELECT o.lngorderid FROM tbl_orders o , tbl_order_contents oc
		WHERE o.lngorderid = oc.lngorderid AND lngprojectindex = ?
		AND ysnfinished = true
	}, undef, $pid);

	$variable->{ordered} = $ordered;


	$variable->{next_project} = $dbh->selectrow_array(q{
		Select p.lngprojectindex FROM tbl_projects p, tbl_order_contents oc 
		where oc.lngorderid = ?
		AND oc.lngprojectindex = p.lngprojectindex
		AND files is null
		Limit 1
	}, undef, $ordered);


	$variable->{jobname} = $dbh->selectrow_array(q{
		SELECT jobname FROM tbl_order_contents WHERE lngprojectindex = ?
	}, undef, $variable->{next_project});


	$variable->{done} = $dbh->selectrow_array(q{
		Select files FROM tbl_projects where lngprojectindex = ?}, undef, $pid);

print STDERR "IS ORDERED : $ordered \n\n";

    return OK;
}

# Stupid little function to present a somewhat human readable size (MB is
# largest unit) given the size in bytes.
sub format_size {
    my ($bytes) = @_;

    return $bytes <         1024  ? "$bytes B"
         : $bytes <    1024*1024  ? int ($bytes/1024) . " KB"
         : $bytes < 10*1024*1024  ? sprintf "%.1f MB", $bytes / 1024*1024
         :                          int ($bytes / (1024*1024)) . " MB";
}

# Company contacts for the current project. The project owner is flagged if
# they're in the list.
sub project_contacts {
    my ($dbh, $pid) = @_;

    return $dbh->selectall_arrayref(q{
        SELECT u.lnguserid                             AS id, 
               u.strlastname || ', ' || u.strfirstname AS name,
               (CASE WHEN u.lnguserid = p.lnguserindex 
                    THEN true 
                    ELSE false
               END) AS selected
        FROM tbl_customer_users u, tbl_projects p
        WHERE u.lngcustomerid = p.lngcustomerid
          AND p.lngprojectindex = ?
        ORDER by 2
    }, { Slice => {} }, $pid);
}

# Dispatch for file actions (upload, approve, delete, etc). 
sub actions {
    my ($r, $log, $dbh, $variable) = @_;



    my $pid = $r->param('pid');
       $pid =~ tr/0-9//cd;

    die "Invalid project ID." unless $pid;

    my $location =  "/main/proj/files.html?pid=$pid";

	map {
		print STDERR "ACTIONS HAVE PARAM $_ = " . $r->param($_) . "\n";
	} $r->param();

	print STDERR "DISPLAY FILES \n";
	if ( $r->param('lastfile') ) {
		print STDERR "LAST FILE \n";
		$dbh->do(q{Update tbl_projects set files = true where lngprojectindex = ? }, undef, $pid);

		project_status($dbh, $pid, 'In Production');

		my $sids = $dbh->selectcol_arrayref(q{
			SELECT lngserviceindex FROM tbl_project_contents where lngprojectindex = ?}, undef, $pid);

		eprint::service::set_status($log, $dbh, $pid, 'In Production', @{$sids});
		
		send_notice($r, $log, $dbh, $variable, $pid);
	}
	elsif ( $r->param('morefiles') ) {
		$dbh->do(q{Update tbl_projects set files = false where lngprojectindex = ? }, undef, $pid);
		print STDERR "MORE FILE \n";
    	$location =  "/main/proj/upload.html?pid=$pid";
	}


    if ($r->param('upload') || $r->param('approve')) {

        # Users must confirm uploads/approvals with their initials (staff excepted).
        return misc::error(
            $log, $dbh, $variable, 'Validition Failed', 
            'The initials you entered are incorrect. You must enter your initials to upload files.'
        ) unless $variable->{is_staff} 
              || check_initials($variable->{user}, $r->param('initials'));

        # Both uploads and approvals are initially approved for either
        # prepress or production.
		my $approval = $r->param('approve_for');

        my ($action, $files);

        if ($r->param('upload')) {
            $action = 'upload';

            $files  = upload_files($r, $dbh, $variable, $pid);
        }
        else {
            $action = 'approve';
            $files  = [ map { { filename => $_ } } $r->param('filename') ];

            approve_files($dbh, $pid, $variable->{user}, $approval, $r->param('filename'));
			die('Missing Approval Level') unless $approval;
        }

		#send_notice($r, $log, $dbh, $variable, $pid, $action, $approval, $files);
    
    }
    elsif ($r->param('delete')) {
        delete_project_files($dbh, $pid, $r->param('filename'));
    }
    # Template generation.
    elsif ($variable->{is_staff} && has_pdf_template($log, $dbh, $pid)) {

        # Generate the print PDFs from the template if requested.
        if ($r->param('generate')) {
            generate_template_archive($r, $log, $dbh, $pid);
        }
        elsif ($r->param('delete_archive')) {
            my $projdir = get_path(undef, $dbh, $pid);
			my $n = get_zip_name($dbh, $pid).'.zip';
		#my $cust_name = $dbh->selectrow_array(q{
		#	SELECT strcompanyname FROM tbl_customer, tbl_projects 
		#	WHERE tbl_customer.lngcustomerid = tbl_projects.lngcustomerid
		#	AND lngprojectindex = ?
		#}, undef, $pid);

		#my $order_id = $dbh->selectrow_array(q{
		#	SELECT lngorderid FROM tbl_order_contents WHERE lngprojectindex = ?
		#}, undef, $pid);
        
            unlink("$projdir/.template/$n")
                or die "Couldn't remove archive: $!\n";
        }
    }


    my ($user, $pass, $host, $port) = $r->headers_in->{'Host'}
        =~ /(?:([^:]+):([^\@]+)\@)?([^\@:]+)(?::(\d+))?/;


    $location = "/main/order/order_submit.html" if $r->param('return_to_order');
    
    # if were on the file uploading port then return them back to
    # the defualt port 80. 
    $location = "http://".$host.$location if $port == 7080; 

    # Our action is complete, redirect back to the file display page.
    $r->status(HTTP_MOVED_TEMPORARILY);
    $r->headers_out->set(Location => $location);
    return HTTP_MOVED_TEMPORARILY;
}



# Check that the provided input matches the user's initials.
sub check_initials {
    my ($user, $check) = @_;

    my $initials = uc( 
         substr($user->{firstname}, 0, 1)
       . substr($user->{lastname},  0, 1)
    );

    return $initials eq uc($check);
}


# Given a project ID and a list of filenames, remove them from the DB and the
# system.
sub delete_project_files {
    my ($dbh, $pid, @filenames) = @_;

    my $path = get_path(undef, $dbh, $pid); # Current project's dir.

    my $delete = $dbh->prepare(q{
        DELETE FROM project_files WHERE pid = ? AND filename = ?
    });
   
    for my $name (@filenames) {
        # The filesytem and DB can get out of sync as direct file access is
        # allowed, don't complain if the file isn't there.
        if (-e "$path/$name") {
            unlink "$path/$name" or die "Couldn't delete project file: $!";
        }
            
        $delete->execute($pid, $name);
    }

    return;
}

# Allow a user to approve files for (prepress|production) for a given project.
sub approve_files {
    my ($dbh, $pid, $user, $type, @filenames) = @_;

	die('Missing Approval Level') unless $type;

    my $approve = $dbh->prepare(qq{
        UPDATE project_files 
        SET approval_$type = ? 
        WHERE pid      = ? 
          AND filename = ?
    });
    $approve->execute($user->{name}, $pid, $_) for @filenames;

    return;
}

# Given a project ID and Apache2::Request object with file uploads, save the
# uploads to the project directory and return info on the processed files.
sub upload_files {
    my ($r, $dbh, $variable, $pid) = @_;
    my $projdir = get_path(undef, $dbh, $pid);

	mkpath($projdir) unless -e $projdir && -d _;

    die "Project directory doesn't exist or isn't a directory ($projdir)"
        unless -e $projdir && -d _;

    # For new files.
    my $insert = $dbh->prepare(q{
        INSERT INTO project_files (pid, filename, description, owner, 
                                   approval_prepress, approval_production)
        VALUES (?, ?, ?, ?, ?, ?)
    });

    # When replacing existing.
    my $update = $dbh->prepare(q{
        UPDATE project_files 
        SET pid               = $1, filename            = $2, 
            description       = $3, owner               = $4, 
            approval_prepress = $5, approval_production = $6
       WHERE pid      = $1
         AND filename = $2
    });
use Data::Dumper;
print STDERR "HAVE FILES \n" , Dumper($r->upload);

    my @files;
    for my $f ($r->upload) {
        my $upload = $r->upload($f);
        my $filename = $upload->filename;

        next unless $filename;

        die "File exists but we don't have write permissions"
            if -e "$projdir/$filename" && ! -w _;

        # The spool file typically doesn't reside on the same file system as
        # where we want it, so we copy instead of hard linking. Replacing any
        # existing files.
        save_upload($upload->fh, $projdir, $filename);

        my ($id)          = ($upload->name =~ m/-(\d+)$/);         # Record no.
        my $description  = $r->param("description-$id") || undef;
        my $owner        = $variable->{user}{id};

        # Prepress approvals are implicit with uploading.
        #my $prepress = $variable->{user}{name};
        my $prepress;

        # Uploads can be pre-approved for production.
        my $production = $r->param('approve_for') eq 'production'
                ? $variable->{user}{name} 
                : undef;

        my $exists = $dbh->selectrow_array(q{
            SELECT true FROM project_files WHERE pid = ? AND filename = ?
        }, undef, $pid, $filename);

        my $sth = $exists ? $update : $insert;

        $sth->execute(
            $pid, $filename, $description, $owner, $prepress, $production
        );

        push @files, { filename => $filename, description => $description};
    }

    # Return information on the files we processed.
    return \@files;
}

# Given a source filehandle and the path and name of the destination, perform
# a binary copy. We assume the source is an already locked Apache spool file
# so don't perform any locking on it.
sub save_upload {
    my ($src, $projdir, $filename) = @_;

    open my $fh, '>', "$projdir/$filename" 
        or die "Error opening project file ($filename) for upload: $!";

    flock $fh, LOCK_EX or die "Couldn't lock file ($filename): $!";

    binmode($src);
    binmode($fh);

    cp($src, $fh); # Up to 2Mb copy buffer.
    
    flock $fh, LOCK_UN;

    close $fh or die "Can't close project file ($filename): $!";

    return;
}


# Notify interested parities that project files have been changed.
sub send_notice {
    my ($r, $log, $dbh, $variable, $pid, $action, $approval, $files) = @_;

	
	$variable->{pid} = $pid;

print STDERR "HAVE SEND PID: $variable->{pid} \n";
	display_files($r, $log, $dbh, $variable);
	$files = $variable->{files};



    # Who's getting the notice?
    my ($to, $bcc) = recipients($r, $dbh, $variable, $pid);

print STDERR "SEND NOTICE" , Dumper($pid, $to, $bcc, @_);

    # No 'To' is allowed by RFC2822 as RFC2821 'RCPT TO' will handle delivery,
    # but Mail::Sendmail doesn't seem to like it.
    if (!@$to) {
        $to  = $bcc;
        $bcc = [];
    }

    # There's nothing to do unless we have some recipients.
    return unless @$to;
print STDERR "SEND TO: @$to \n";
   
    my %header = (
        SMTP       => configuration::get_value(undef, $dbh, 'Mail Server'),
        From       => configuration::get_value(undef, $dbh, 'FileUploadEmail'),
        Subject    => "[PQS] Project #${pid}'s files have changed.", 
    );
    $header{To}  = join ',', @$to;
    $header{Bcc} = join ',', @$bcc if @$bcc;

    # [uploaded and ]approved for (production|prepress)
    my $message = "approved for $approval";
       $message = 'uploaded and ' . $message if $action eq 'upload';

    my %info = (
        siteURL => "http://" . $r->hostname,
        user    => $variable->{user},

        pid     => $pid,
        action  => $message,
        files   => $files,

        # Is the user required to take action? Yes, if a staff member uploaded
        # a file without pre-approving it for production.
        needs_approval =>  
            ( $variable->{is_staff} && $approval ne 'production' ),
		

        # Include file for body of email.
        ReplacementText =>
            qq{<!--#include virtual="/email/content/project_files.html"-->},
    );

	$info{needs_approval} = 1 if $variable->{Supplier} eq 'Y';
  
    my $body = misc::load_file($r, '/email/email_template.html');
       $body = ssi::variable_substitution($r, $log, $dbh, $body, \%info);


#	misc::save_file(undef, "/usr/local/share/pqs/www/test.html", ($body));



#	return 1;


    misc::send_email_with_attachment($r, $log, \%header, 
        ('', encode_qp($body), 'text/html', 'quoted-printable')
    );

    # Notify the user's manager (if applicable) they have uploaded
    # and/or modified at least one file.
    eprint::user::notify_manager($r, $log, $dbh, $variable->{user_id}, 'file', {
        subject  => "[PQS] Project #${pid}'s files have changed.",
        template => 'notify_manager_file_upload.html',
        info     => { pid => $pid, },
    });

    return 1;
}

# Determine who's getting a notice.
sub recipients {
    my ($r, $dbh, $variable, $pid) = @_;
    my (@to, @bcc);

    my $staff_email = configuration::get_value(undef, $dbh, 'FileUploadEmail');

    # Staff members can choose who gets notifications.
    if ($variable->{is_staff}) {
        # Retrieve the email addresses of any selected users.
        my $users = join ',', map { tr/0-9//cd; $_ ? $_ : () } 
                                    $r->param('notify_users');

        push @to, @{ $dbh->selectcol_arrayref(qq{
            SELECT strfirstname ||' '|| strlastname ||' <'|| stremail ||'>'
            FROM tbl_customer_users 
            WHERE lnguserid IN ($users)
        }) } if $users;

		#Always send to notfication address;
        push @bcc, $staff_email;

        push @bcc, $staff_email             if $r->param('notify_staff');
        push @bcc, $variable->{user}{email} if $r->param('notify_self');

        #@recipients = uniq @recipients; # Incase 'self' is staff or in 'users'
    }
	elsif ( $variable->{Supplier} eq 'Y' ) {

print STDERR "IS SUPPLIER ADD PROJECT CREATOR TO LIST \n";

		push @to, @{ $dbh->selectcol_arrayref(qq{
            SELECT strfirstname ||' '|| strlastname ||' <'|| stremail ||'>'
            FROM tbl_customer_users u, tbl_projects p 
            WHERE u.lnguserid = p.lnguserindex AND p.lngprojectindex = ? 
        }, undef, $pid) };

		push @bcc, $staff_email;

	}
    # Normal users performing an action get a confirmation and an notice is
    # sent to the staff department.
    else {
        push @to, @{ $dbh->selectcol_arrayref(qq{
            SELECT strfirstname ||' '|| strlastname ||' <'|| stremail ||'>'
            FROM tbl_customer_users 
            WHERE lnguserid IN (SELECT owner FROM project_files WHERE pid = ?)
        }, undef, $pid) };

print STDERR "I AM A USER: PLEASE EMAIL ME TO: @to \n";
		
#        push @to,  $variable->{user}{email};
        push @bcc, $staff_email;
    }

    return \@to, \@bcc;
}

sub get_zip_name {
	my ( $dbh, $pid ) = @_;

	my $cust_name = $dbh->selectrow_array(q{
		SELECT strcompanyname FROM tbl_customer, tbl_projects 
		WHERE tbl_customer.lngcustomerid = tbl_projects.lngcustomerid
		AND lngprojectindex = ?
	}, undef, $pid);

	my $order_id = $dbh->selectrow_array(q{
		SELECT lngorderid FROM tbl_order_contents WHERE lngprojectindex = ?
	}, undef, $pid);

	my $proj = $dbh->selectrow_array(q{
		SELECT strprojectreference FROM tbl_projects WHERE lngprojectindex = ?
	}, undef, $pid);

	my $name = "$cust_name-$order_id-" . substr($proj,0,16);
	$name =~ s/\#//g;
	return $name;


}


# Creates an archive of all PDF template files including print ready output
# files.
sub generate_template_archive {
    my ($r, $log, $dbh, $pid) = @_;


    require File::Temp;
    require eprint::Template;
    require PQS::PDF;

    my $proj_dir   = get_path(undef, $dbh, $pid);
    my $path       = $proj_dir . '/.template/';
    my $template   = 'template.pdf';
    my $datasource = eprint::Template::get_datasource($dbh, $pid);



	my $order_id = $dbh->selectrow_array(q{
		SELECT lngorderid FROM tbl_order_contents WHERE lngprojectindex = ?
	}, undef, $pid) || 'no_order';

	my ($proj, $mail) = $dbh->selectrow_array(q{
		SELECT strprojectreference, mail_type FROM tbl_projects WHERE lngprojectindex = ?
	}, undef, $pid);


    my $sth = $datasource->prepare('SELECT * FROM data');
    $sth->execute;

use Data::Dumper;

	my $count = $datasource->selectrow_array(q{
		SELECT count(*) FROM data
	});

	my @pdfs;
    while (my $rec = $sth->fetchrow_hashref) {

		# Go hunting for the locator field because
		# they like to spell it 12 different ways.
		my @loc = grep { lc($_) =~ /^loc/}  keys %{$rec};
		my $n = shift @loc;

		#Lookup the store number once we have found the locater field.
		my $name = $n ?  $datasource->selectrow_array(qq{
							SELECT name FROM asset_$n WHERE id = ?
						 }, undef, $rec->{$n}) || 'locator_not_selected'
					  : 'missing_locator';

		#Build a file name based on locater, record number, order id, project name
        my $id 		 = "$name-$rec->{id}-${order_id}_";
		my $filename = $id .  substr($proj,0,30) . ".pdf";

		my ($tempdir, $master)  = get_temp_dir($mail, $proj, $name, $order_id);

        PQS::PDF::fill_file(
            $path,
            $template,            # Input template
            "$tempdir/$filename", # Output file
            $rec                  # Fill data
        );

		#replaced File::Copy copy -> fcopy;

		# Use File::Copy::Recursive to make a master copy of the ftp files.
		# File::Copy::Recursive will create any required dirs.
		use File::Copy::Recursive qw(fcopy dircopy);

		# Copy our completed pdf into the project dir.
		fcopy("$tempdir/$filename", $proj_dir);

		if ( $mail ) {
			# For mailing projects copy the address csv file into the 
			# ftp pickup dir, rename to match pdf file using $id
			my $n = 'mailing_address.csv';
			fcopy("$path/$n", "$tempdir/${id}$n");

			$path =~ /www\/(.*)\/\.template/;
			my $dir = $1;
    		push @pdfs, misc::load_file($r,"$dir/$filename");
		} else {
			email_pdf($r, $log, $dbh, "$tempdir/$filename", 
					  $order_id, $filename, $pid, $name
			) if $count < 10;

		}

		dircopy($tempdir, $master) if $master;
	

    }

    $datasource->rollback;


   return \@pdfs;

}

sub get_temp_dir {
		my ($mail, $proj, $name, $order_id) = @_;

		my $tempdir = Apache2::RequestUtil->request->document_root;
		my $master;

		if ( $mail ) { 
			#Make sure parent dir exists for this mailing type
			$tempdir .= "/ftp_mail/$proj";

			mkdir $tempdir unless -e $tempdir;
			
			#Make sub dir based on locator, order id
			$tempdir .= "/${name}_${order_id}";

			mkdir $tempdir;
			
			#Location of the master copy of files
			$master = $tempdir;
			$master =~ s/ftp_mail/ftp_master/;

		} else {

			# For standard projects just put them in one spot
			$tempdir .= "/ftp_zip/$proj/";
	
			mkdir $tempdir unless -e $tempdir;
		}

print STDERR "Temp dir is: $tempdir  \n Master: $master \n";
		return $tempdir, $master;
}

sub encode_base64 {
	use integer;
	my $res = "";
	my $eol = $_[1];
	$eol = "\n" unless defined $eol;
	pos($_[0]) = 0; # ensure start at the beginning

	while ($_[0] =~ /(.{1,45})/gs) {
		$res .= substr(pack('u', $1), 1);
		chop($res);
	}

	$res =~ tr|` -_|AA-Za-z0-9+/|; # `# help emacs
	# fix padding at the end
	my $padding = (3 - length($_[0]) % 3) % 3;
	$res =~ s/.{$padding}$/'=' x $padding/e if $padding;
	# break encoded string into lines of no more than 76 characters each
	if (length $eol) {
		$res =~ s/(.{1,76})/$1$eol/g;
	}
	return $res;
}

sub	email_pdf {
	my ( $r, $log, $dbh, $filename, $order_id, $fname, $pid, $locator) = @_;

    my %header = (
        SMTP       => configuration::get_value(undef, $dbh, 'Mail Server'),
        From       => configuration::get_value(undef, $dbh, 'FileUploadEmail'),
        Subject    => "Domino's Project files for Store #$locator", 
    );
    
    my $add = configuration::get_value(undef, $dbh, 'ProjectFileNotification');
    $header{Bcc}   => $add if $add; 

	my $email = $dbh->selectrow_array(q{
		SELECT stremail FROM tbl_orders WHERE lngorderid =  ?
	}, undef, $order_id);


    $header{To}  = $email;
	

    my %info = (
        siteURL => "http://" . $r->hostname,
		order_id => $order_id,
		pid 	 => $pid, 

        # Include file for body of email.
        ReplacementText =>
            qq{<!--#include virtual="/email/content/file_notification.html"-->},
    );


	my $filesize = -s $filename;
print STDERR "FILESIZE: $filesize \n";

# 	File is bigger than 10 Megs
	my @attach;
	if ( $filesize < 10000000 ) {
		my $file;
		open F,"$filename" or die $!;
		{
			local $/ = undef; # turn on slurp mode
			$file = <F>;
		}
		close F;
		$file = encode_base64($file);
		@attach = ($fname,$file, 'application/acrobat', 'base64');
	} else {
        $info{ReplacementText} =
            qq{<!--#include virtual="/email/content/file_notification_large.html"-->},
		
	}

    my $body = misc::load_file($r, '/email/email_template.html');
       $body = ssi::variable_substitution($r, $log, $dbh, $body, \%info);

print STDERR "HAVE PDF: ", Dumper($filename, $order_id, \%info, \%header);
	
    misc::send_email_with_attachment(undef, undef, \%header, 
        ('', encode_qp($body), 'text/html', 'quoted-printable'),
		@attach
    );
}

{
    # Map mime types to icon images. Not a complete list by far but a
    # selection of common ones for which we have graphics.
    my %MIME_IMAGE = (
        application => {
            _default   => 'binary',

            # Archives (bz2, gzip, etc. are encodings not mime-types)
            'x-tar'            => 'tar',
            'x-archive-tar'    => 'archive',
            'x-gtar'           => 'archive',
            zip                => 'archive',
            rar                => 'archive',
            'x-gzip'           => 'archive',


            # Document formats we commonly deal with (TODO add quark, etc.)
            pdf                           => 'pdf',
            postscript                    => 'postscript',
            msword                        => 'ms_word',
            msaccess                      => 'ms_access',
            'vnd.ms-excel'                => 'ms_excel',
            'vnd.oasis.opendocument.text' => 'document',
            'illustrator'                 => 'vectorgfx',

            # Font files (most don't have properly registered mime-types).
            'x-font'       => 'font_type1',
            'x-font-type1' => 'font_type1',
            'x-font-ttf'   => 'font_truetype',
            'x-fong-pcf'   => 'font_bitmap',
        },

        audio => { _default => 'sound' },

        image => { 
            _default  => 'image',

            # Bitmap image types
            png  => 'image',
            gif  => 'image',
            jpeg => 'image',
            tiff => 'image',

            # Vector image types
            'svg+xml'           => 'vectorgfx',
            'image/x-coreldraw' => 'vectorgfx'
        },

        text => {
            _default              => 'ascii',
            csv                   => 'spreadsheet',
            'tab-seprated-values' => 'spreadsheet',
            html                  => 'html',
            plain                 => 'txt',
            richtext              => 'document',
            rtf                   => 'document',
        },

        video => { _default => 'video' },
    );

    # Given a mimetype, return the name of the image.
    sub icon_lookup {
        my $mimetype = shift;

        return 'unknown' unless $mimetype;

        my ($type, $subtype) = split '/', $mimetype; # Mime-types are two parts.

        return 'unknown' unless exists $MIME_IMAGE{$type};

        return $MIME_IMAGE{$type}{_default} || 'unknown'
            unless exists $MIME_IMAGE{$type}{$subtype};

        return $MIME_IMAGE{$type}{$subtype} || 'unknown';
    }
}

sub ftp_file {
	my ($r, $dbh, $var) = @_;

	my $f = $r->param('folder');
	print STDERR "GET FILES FOR : $f \n";
    my $dir = $r->dir_config("site_specific").'/customers/ftp/' . $f;
    my $loc = '/customers/ftp/' . $f;

    opendir my $dirhandle, $dir or die "Couldn't open project directory ($dir): $!";

	my $files = [];
    while (my $name = readdir($dirhandle)) {

		next if $name =~ /_thumb/;

        # $filter out stuff we don't want them to see.
        next if substr($name, 0, 1) eq '.';
		next if $name eq 'CVS';

		my @t = split('\.' , $name);

		my $thumb = $loc . '/' . $t[0] . '_thumb.' . 'jpg';

		$thumb = -e  $r->dir_config("site_specific") . $thumb ? $thumb : '';



		print STDERR "NAME PARTS: " , Dumper(\@t, $name);

		#For directorys change the link to go back to the files.html
		#to display files inside sub dir
		my $is_dir = -d $dir . "/$name";
		my $l = $is_dir ? "/main/files/files.html?folder=$f/$name" :  $loc . "/$name"; 

		my $new_file = 
		push @{$files}, {	
			name 		=> $name, 
			dir 		=> $is_dir,
			location 	=> $l,
			thumbnail 	=> $thumb,
			short_name 	=> substr($name, 0, 44),
		};



    }

	#sort dirs first, then by filename, case insensitive.
	@{$files} = sort  { $b->{dir} cmp $a->{dir} || lc($a->{name}) cmp lc($b->{name}) } @{$files};
    
    closedir $dirhandle or die "Couldn't close project directory: $!";

	$var->{FILES} = $files;
	print STDERR "HAVE FILES: ", Dumper($var->{FILES});
}


sub ftp_folder {
	my ($r, $dbh, $var) = @_;

    my $projdir =  $r->dir_config("site_specific").'/customers/ftp';

print STDERR "GET FILES FOR: $projdir \n";


    opendir my $dirhandle, $projdir or die "Couldn't open project directory ($projdir): $!";
    
	my $folders = [];
    while (my $name = readdir($dirhandle)) {

        # Only display non-hidden files (no dirs, etc.)
        next if substr($name, 0, 1) eq '.';
		next if $name eq 'CVS';
        #next if substr($name, 0, 1) eq '.' || ! -f "$projdir/$name";
		print STDERR "HAVE NAME: $name \n";
		push @{$folders}, { name 		=> $name,
							short_name 	=> substr($name, 0, 44)
		};

    }
    
    closedir $dirhandle or die "Couldn't close project directory: $!";

	$var->{FOLDERS} = $folders;
	print STDERR "HAVE FOLDERS: ", Dumper($var->{FOLDERS});
}

1;
