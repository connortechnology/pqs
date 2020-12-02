package PQS::WWW::Template;
use strict;
use warnings;
use utf8;

use Apache2::Const qw(:common :http);
use Apache2::Request ();
use Apache2::RequestIO ();
use Apache2::RequestUtil ();
use Apache2::Cookie    ();
use Apache2::Log     ();
use Apache2::Upload ();
use Apache2::ServerUtil;
use Fcntl qw(:flock);
use Symbol qw(qualify_to_ref);
use Data::Dumper;
use session;

use HTML::FillInForm ();
use Petal;
use Petal::Utils qw(:all);

use PQS::DB ();
use PQS::Template;
use eprint::Template;


# Templates are located in the customer specific section under this path.
use constant TEMPLATE_LOCATION => "/templates";

# Database handles are as ubiquitous as print statements, we use a globalised
# handle variable (localised per request) so we don't have to pass it
# everywhere. THIS IS NOT THE FINAL WAY IT WILL BE DONE.
our $dbh;

sub handler {
    my $rec = shift;

    # Subclass the Apache request object for a better parameter interface.
    my $r = Apache2::Request->new($rec);

    # Establish a connection to the database and allow everyone in the current
    # request to access it.
    local $dbh = PQS::DB->connect($r);

    session::r($r);
    session::log($r->log);
    session::dbh($dbh);

    # At the end of each request we'll roll back any unsaved change and
    # disconnect from the database. We'd much rather keep the connection but,
    # given the existing eprint code, we can't use a persistant handle.
    Apache2::ServerUtil->server->push_handlers("PerlCleanupHandler", sub {
            if ($dbh) {
                $dbh->rollback();
                $dbh->disconnect();
            }
            return OK;
    });

    # Unless the user is a valid user, throw them back to the login.
    # TEMPORARY: This will be handled in auth handlers.
    unless ( valid_user($r) ) {
        $r->headers_out->set(Location => "/administrator/");
        $r->status(HTTP_MOVED_TEMPORARILY);
        return HTTP_MOVED_TEMPORARILY;
    }

    # Create a template object, it will need to be associated with a template
    # in the dispatched function.
    my $t = Petal->new(
        base_dir         => $r->document_root,
        input            => 'XHTML',
        output           => 'XHTML',
        #    language         => 'en',              # These should soon be
        #    defualt_language => 'en',              # dynamically populated.
    );

    # Determine what function the user has requested by parsing the URI. For
    # now we just use the first argument of the path as the name of a function
    # inside this module. We can decide on more complex mappings later.
    my $name = ( split '/', $r->uri )[2];

	die();

	print STDERR "HAVE FUNC: $name \n";
	# Get a refrence to the function.
    my $func = qualify_to_ref( $name, __PACKAGE__ );

    # Verify that the function requested exists, if not return a 404.
    return NOT_FOUND unless defined &$func;

    # Dispatch the request and return its status.
    my $status = *{ $func }{CODE}->($r, $t);

    $dbh->rollback;
    $dbh->disconnect;

    return $status;
}

# Very, very basic authentication/authorization check that ties in with the
# old sytem. All we do is see if we have a session cookie, the session hasn't
# timed out, and that the user is of type 'A' (Administrator).
sub valid_user {
    my $r = shift;
    my $cookies = Apache2::Cookie->fetch;

    my $session = exists $cookies->{SessionID} ? $cookies->{SessionID}->value : 0;

    # If the session doesn't exist the user isn't valid.
    return 0 unless $session;

    # Using the session, look up the user and whether they've execeeded their
    # idle timeout (as defined in the configuration table).
    my $sth = $dbh->prepare_cached(q{
        SELECT lnguserid                                 AS uid,
               (lnguserid IS NOT NULL AND lnguserid > 0) AS exists,
               chrusertype = 'A'                         AS is_admin,
               ( now() >
                 dtmlastaccessed + (SELECT (strconfigdata||' seconds')::interval
                                     FROM tbl_configuration
                                     WHERE strconfigtitle = 'idletime') )
        FROM tbl_logged_in
        WHERE strsessionid = ? AND chrsite = 'A'
    });
    my ($uid, $exist, $admin, $timed_out) =
        $dbh->selectrow_array($sth, undef, $session);

    # Let apache know the user (even though we're not doing auth) and set some
    # of their information in the request notes.
    $r->user($uid);
    $r->pnotes('user', $dbh->selectrow_hashref(q{
        SELECT lnguserid AS id,
               stremail AS email,
               strfirstname || ' ' || strlastname AS name
        FROM tbl_customer_users
        WHERE lnguserid = ?
    }, {}, $uid));

    # If the session exists, the user is an admin, and the user hasn't timed
    # out, we can let them in. TEMP: Timeout removed for this section.
    return ($exist and $admin);
}

# List the templates in the system and display the controls to modify them.
sub list {
    my ($r, $t) = @_;

    my $templates = $dbh->selectall_arrayref(q{
        SELECT id, name
        FROM template.template
        ORDER BY 2, 1
    }, { Slice => {} });

    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'template/list.html';
    print $t->process(
        r         => $r, 
        templates => $templates,
    );

    return OK;
}

# Allow the user to choose an upload (and to possibly replace) a template.
sub create {
    my ($r, $t) = @_;

    my $template = { id => '', name => '' };
    if ( $r->param('id') ) {
        $template = $dbh->selectrow_hashref(q{
            SELECT id, name
            FROM template.template
            WHERE id = ?
            ORDER BY 2, 1
        }, {}, $r->param('id'));
    }

	if ( $r->param('TemplatePID') ) {
		my $pid = $r->param('pid');
		my $id  = $r->param('id');

		eprint::Template::init_template($dbh, $pid, $id);

	}

	if ( $r->param('Export') ) {

		print STDERR "EXPORT STUFF \n";

		my $sth = $dbh->prepare(q{
			SELECT name, field, value 
			FROM template_defaults
		});
		my @data;
		$sth->execute();

		while (my @row = $sth->fetchrow_array) {
			push @data, \@row;
		}

	 	$r->headers_out->{'Content-Disposition'} = qq{attachment; filename="defaults.csv"};
		$r->content_type( qq{application/octet-stream; name="defaults.csv"} );

		$r->print('userid,template,field,value\n');

		map { 
	
			$r->print(join ',', @{$_}); 
			$r->print("\n");
			print STDERR "ADDING: @{$_} \n";
		} @data;

	} else {
    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'template/create.html';
    print $t->process(
            r => $r, 
            template => $template,
        );
		
	}


    return OK;
}

# Deletes a template from the system.
sub delete {
    my ($r) = @_;

    my @ids = $r->param('id');

    for my $id ($r->param('id')) {
        $id =~ tr/0-9//cd;

        # Delete the template from the filesystem.
        my $filename = $dbh->selectrow_array(q{
            SELECT filename FROM template.template
            WHERE id = ?
        }, {}, $id);

        next unless $id && $filename;

        unlink($filename) 
            or die "Couldn't remove template ($id) file $filename : $!";

        # Remove the DB entry.
        $dbh->do(q{
            DELETE FROM template.template
            WHERE id = ?
        }, {}, $id);
    
        $dbh->commit;
    }

    # Send the user back to the template listing page.
    $r->headers_out->set(Location => "/templating/list" );
    $r->status(HTTP_MOVED_TEMPORARILY);

    return OK;
}

# Retrieve a copy of the template.
sub download {
    my ($r) = @_;
    my $id = $r->param('id');
       $id =~ tr/0-9//cd;

    # Delete the template from the filesystem.
    my $filename = $dbh->selectrow_array(q{
        SELECT filename FROM template.template
        WHERE id = ?
    }, {}, $id);

    die "Invalid id ($id)"
        unless $id && $filename;

    # Open the template file and send it to the client.
    open(my $fh, $filename)
        or die "Can't open template ($id) file ($filename): $!\n";

    $r->content_type('application/pdf');
    $r->headers_out->{'Content-Disposition'} = qq{inline; filename="template-$id.pdf"};
    $r->headers_out->{'Content Length'} = ( -s $filename );

    flock   $fh, LOCK_SH or return HTTP_SERVICE_UNAVAILABLE;
    binmode $fh; 
    
    $r->sendfile($filename);   # Output the file.

    flock $fh, LOCK_UN; # Unlock and cleanup.
    close $fh;

    return OK;
}

# Upload the template file and redirect to listing page.
sub upload {
    my ($r) = @_;

print STDERR "START UPLOAD \n";
    my $upload   = $r->upload('template');
    my $defaults = $r->upload('defaults');

    # TODO This should return a usable error message.
    unless ($defaults || ($upload && $upload->type eq 'application/pdf')) {
      $r->log_error("Upload content type is: " . $upload->type);
      return SERVER_ERROR;
    }
    unless ($r->param('name')) {
      $r->log_error('A name has not been provided');
    }

# TODO trap any errors from openning/reading the PDF and tell the user the
# template is invalid.
#    my $pdf_info = get_pdf_info($upload->tempname);


    my ($filename, $fh);

    # If an ID exist were're overwriting instead of inserting a new template.
    # Just use it's existing filename.
	if ( $upload &&  $upload->type eq 'application/pdf' ) {
		my $x = $r->param('name');
		if (my $id = $r->param('id') && 0) {
			
			$filename = $dbh->selectrow_array(q{
				SELECT filename FROM template.template
				WHERE id = ?
			}, {}, $id);

			die "Invalid ID ($id)" unless $filename;
			
			$dbh->do(q{
				UPDATE template.template
				SET "name" = ?
				WHERE id = ?
			}, {}, $r->param('name'), $id);

			if ( $upload ) {
				open($fh, ">$filename");

				open($fh, ">$filename")
					or die "Couldn't open existing template ($id) $filename: $!";
			}
		}
		else {
			($filename, $fh) = newfile()
				or die "Can't open output file: $!";
			
			$dbh->do(q{
				INSERT INTO template.template ("name", filename)
				VALUES (?, ?)
			}, {}, $r->param('name'), $filename);

			# TODO Just name the file after the unique ID the DB gives us.
			# my $filename = $dbh->last_insert_id . ".pdf";
		}

		# Spool the template file out to it's new location.
		if ( $upload &&  $upload->type eq 'application/pdf' ) {
print STDERR "HAVE NAME START UPLOAD 4 \n";
			my $u = $upload->fh;
			print $fh $_ while <$u>;
			$fh->close;
		}
	}

print STDERR "LOOK FOR DEFAULTS \n";
	if ( $defaults ) {

		my $id = $r->param('id');

		print STDERR "HAVE DEFAULTS FOR: $id \n";

		# get the upload.
		my @content = misc::get_upload($r, $r->log, 'defaults');

		my $del = $dbh->prepare(qq{DELETE FROM template_defaults WHERE name = ? AND field = ?});
		#my $del = $dbh->prepare(qq{DELETE FROM template_defaults });
		#$del->execute();



		my $ins = $dbh->prepare(q{
			INSERT into template_defaults (template, name, field, value) 
			VAlues (?,?,?,?); 
		});
use Data::Dumper;

		# Insert new defaults
		map { 
			my @d = split q{,}, $_,3;
			print STDERR "HAVE DEFAULTS: ", Dumper(\@d);
			$d[2] =~ s/\s*$//g;
			print STDERR "NOW DELETING $d[0], $d[1], $id\n";
			$d[2] = remove_trailing_comma($d[2]);
			$del->execute($d[0], $d[1]);
			$ins->execute($id, @d) 
		} @content;
		
	}


    # Get the meta-data (number of pages, file size, etc.)
    

    # Generate the forms.


    # Generate and cache field location previews. The preview using the
    # defaults can't be generated and stored until all fonts are present.

    $dbh->commit;

    $r->headers_out->set(Location => "/templating/list" );
    $r->status(HTTP_MOVED_TEMPORARILY);

    return OK;
}

sub remove_trailing_comma {
	my $t = shift;

   	my $x = length($t)-1;

   while ( substr($t, $x, 1) eq ',' ) {
      $t =~ /(.*),$/;
      $t = $1;
      $x = length($t)-1;

	}

	return $t;

}

# Stolen from Apache2::File but instead of returning a temporary file returns a
# new unique file in the template directory.
sub newfile {
    my $TMPNAME = time();
    my $limit = 100;  
    my $r     = Apache2::RequestUtil->request;
    my $path  = $r->dir_config('site_specific') 
             || $r->document_root.'/site_specific/';

    while ($limit--) {
        my $newfile = $path . TEMPLATE_LOCATION . "/${$}" . $TMPNAME++;
        ($newfile) = $newfile =~ /^([^<>|;*]+)$/; # untaint
        $newfile =~ tr/\//\//s;

		print STDERR "HAVE NEWFILE 1: $newfile \n";

        next if (-e $newfile);
		print STDERR "HAVE NEWFILE 2: $newfile \n";
        open(my $fh, ">", $newfile) or die("Can Not open Handle for: $newfile \n");
		print STDERR "HAVE NEWFILE 3: $newfile \n";

        if ($fh) {
            return wantarray ? ($newfile, $fh) : $fh;
        }
    }
    die "Couldn't create a unique filename even after 100 tries.";
}

1; 
