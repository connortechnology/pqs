package PQS::WWW::Status;
# NOTE: This is a very quick prototype coding of this feature set. Many
# features in the set have been left out. No overriding architecture to how to
# handle function dispatches (handler()) has been worked out, nor has how to
# handle JS calls vs. user GET/POSTs that perform the same root action, in
# fact those root actions haven't been abstracted out in most cases. Proper
# error handling is also in it's most rudimentary form if here at all.
use strict;
use warnings;
use utf8;

use Apache2::Cookie ();
use Apache2::Const qw(:common :http);
use Apache2::Cookie ();
use Apache2::Request ();
use Apache2::ServerUtil;
use Data::Dumper;
use HTML::FillInForm ();
use Petal;
use Petal::Utils qw(:all);
use PQS::DB ();
use PQS::Util;
use Symbol qw(qualify_to_ref);
use session;

# The two constant complete states (IDs should always be this).
use constant NOT_STARTED => 0;
use constant COMPLETE    => 5;


use constant STATE_PROD => 'In Production';
use constant STATE_DONE => qw(Complete Paid);


# Database handles are as ubiquitous as print statements, we use a globalised
# handle variable (localised per request) so we don't have to pass it
# everywhere. THIS IS NOT THE FINAL WAY IT WILL BE DONE.
our $dbh; 

sub handler { 
    my $r = shift;
    
    # Subclass the Apache request object for a better parameter interface.
    $r = Apache2::Request->new($r);
    
    # Establish a connection to the database and allow everyone in the current
    # request to access it.
    $dbh = PQS::DB->connect($r);

    session::r;
    session::log;
    session::dbh;

    # At the end of each request we'll roll back any unsaved change and
    # disconnect from the database. We'd much rather keep the connection but,
    # given the existing eprint code, we can't use a persistant handle.
    Apache2::ServerUtil->server->push_handlers("PerlCleanupHandler", sub {
            $dbh->rollback();
            $dbh->disconnect();
            return OK;
    });

    # Unless the user is a valid user, throw them back to the login.
    # TEMPORARY: This will be handled in auth handlers.
    unless ( valid_user($r) ) {
        $r->headers_out->set(Location => "/employee/");
        $r->status(HTTP_MOVED_TEMPORARILY);
        return 302;
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

    # Get a refrence to the function.
    my $func = qualify_to_ref( $name, __PACKAGE__ );
  
    # Verify that the function requested exists, if not return a 404.
    return NOT_FOUND unless defined &$func;

    # Currently we don't allow any caching due to the JS auto-updating we do
    # to the page. This stops the situation of having JS update the page,
    # going somewhere else, coming back and having the page not look as it was
    # left. TODO: We should improve this by setting last-modified-times and
    # aged cache control so we don't need to hit the server as often. This is
    # especially useful for large searches.
    $r->no_cache(1);
    $r->headers_out->{'Cache-Control'} = 'no-cache, no-store, must-revalidate';
    
    # Dispatch the request and return it's status.
    my $status = *{ $func }{CODE}->($r, $t);

    return $status;
}

# Very, very basic authentication/authorization check that ties in with the
# old sytem. All we do is see if we have a session cookie, the session hasn't
# timed out, and that the user is of type 'E' (Employee).
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
               chrusertype IN ('A', 'E')                 AS is_type,
               ( now() > 
                 dtmlastaccessed + (SELECT (strconfigdata||' seconds')::interval
                                     FROM tbl_configuration 
                                     WHERE strconfigtitle = 'idletime') )
        FROM tbl_logged_in
        WHERE strsessionid = ? AND ( chrsite = 'E' OR chrsite = 'A' )
    });
    my ($uid, $exist, $type, $timed_out) = 
        $dbh->selectrow_array($sth, undef, $session);

    # Let apache know the user (even though we're not doing auth) and set some
    # of their information in the request notes.
    $r->user($uid);
    $r->pnotes('user', $dbh->selectrow_hashref(q{
        SELECT lnguserid     AS id, 
               stremail      AS email,
               lngcustomerid AS account,
               strfirstname || ' ' || strlastname AS name
        FROM tbl_customer_users
        WHERE lnguserid = ?
    }, {}, $uid));

    # If the session exists, the user is of the type we want, and the user
    # hasn't timed out, we can let them in. TEMP: Timeout removed.
    return ($exist and $type);
}

# General ordered project info (given a PID).
sub project_info {
    # NOTE: This assumes a project can only ever be ordered once, this is the
    # current standing code but is not DB enforced and older version may not
    # hold to this assumption.
    return $dbh->selectrow_hashref(q{
        SELECT p.lngprojectindex                        AS id, 
               p.strprojectreference                    AS "name",
               p.strcomments                            AS comments,
               to_char(p.dtmcreationdate, 'YYYY-MM-DD') AS createdate,
               to_char(p.completion_date, 'YYYY-MM-DD') AS duedate,

               o.lngorderid       AS order_id,
               o.intquantity      AS order_qty,

	       odr.stremail	  AS user_email,

               u.strlastname      AS user_surname, 
               u.strfirstname     AS user_proname,
               u.strPhone         AS user_phone,
               u.strExt           AS user_ext,
               u.strFax           AS user_fax,

               c.strcompanyname   AS company_name,
               c.strAddress1      AS company_address,
               c.strCity          AS company_city,
               c.strProvState     AS company_province,
               c.strPostalCodeZip AS company_postalcode,
               c.strCountry       AS company_country
        FROM tbl_projects p, tbl_order_contents o,
             tbl_customer c, tbl_customer_users u,
	     tbl_orders odr
        WHERE p.lngprojectindex = o.lngprojectindex
          AND p.lnguserindex    = u.lnguserid
          AND c.lngcustomerid   = u.lngcustomerid
	  AND o.lngorderid	= odr.lngorderid
          AND p.lngprojectindex = ?
    }, {}, shift);
}

# TODO: Full text query at some point?
sub search {
    my $r = shift;
    my $t = shift;

    # TODO: Better searching. TODO: Just have a param -> field mapping and
    # whether it's an exact or anchored ILIKE.
    my %criteria = (
        pid     => q{ AND p.lngprojectindex = ? },
        oid     => q{ AND o.lngorderid      = ? },
        company => q{ AND c.strcompanyname ILIKE        ? || '%' },
        surname => q{ AND u.strlastname    ILIKE        ? || '%' },
        proname => q{ AND u.strfirstname   ILIKE        ? || '%' },
        email   => q{ AND u.stremail       ILIKE '%' || ? || '%' },
    );

    # Generate the extra arguments to the WHERE clause and the values.
    my (@where, @args);
    for my $name ($r->param) {
        if (exists $criteria{$name} and $r->param($name)) {
            push @args, $r->param($name);
            push @where, $criteria{$name};
        }
    }

	my $state = $r->param('state');

    # If the user is searching for a specific project we'll override check in
    # all known good states.
    $state = 'both' if $r->param('pid') || $r->param('oid');

    # The user can request what states to view, the default is in production.
    if (my $status = $state) {
        my @states = $status eq 'both' ? (STATE_PROD, STATE_DONE)
                   : $status eq 'done' ? (STATE_DONE)
                   :                     (STATE_PROD); 

        my $placeholders = join(',', ('?') x @states);
        
        push @where, " AND p.strstatus IN ($placeholders)";
        push @args, @states;
    }
    else {
        push @where, 'AND p.strstatus = ? ';
        push @args,  'In Production';
    }

    # Search with user defined WHERE criteria.
    my $search = $dbh->prepare(qq{
        SELECT c.strcompanyname AS company,
               p.lngprojectindex      AS id, 
               p.strprojectreference  AS "name",
			   p.tech				  AS tech,
			   delivery_date(p.lngprojectindex)::date AS duedate
        FROM tbl_projects p, tbl_order_contents t,
             tbl_customer c, tbl_customer_users u,
             tbl_orders o
        WHERE p.lngprojectindex = t.lngprojectindex
          AND p.lnguserindex    = u.lnguserid
          AND c.lngcustomerid   = o.lngcustomerid
          AND t.lngorderid      = o.lngorderid
          AND NOT o.cancelled
          @where
        ORDER BY 5, 1, 3
    });

    # Not sure if it's faster to prepare this now and loop over it, or to do
    # an IN () and pass it all the IDs returned from the above query. TODO:
    # With the addition of the outer join IN() is probably MUCH faster.
    my $status = $dbh->prepare_cached(q{
        SELECT b.lngindex AS id, lower(b.strid) AS category, a.state
        FROM tbl_service_categories b LEFT JOIN (
                SELECT c.lngindex, c.strid, composite_state(s.type) AS state
                FROM tbl_service_types t, tbl_project_contents p,
                     tbl_service_categories c, project_state s
                WHERE c.strid     = t.strcategory
                  AND t.strid     = coalesce(p.strservicetype, 'Printing')
                  AND s.id        = p.lngcompletestate
                  AND p.lngprojectindex = ?
                GROUP BY c.lngindex, c.strid ) AS a USING (lngindex)
        ORDER BY b.lngindex
    });

    # Add the category statuses to the project set. Note: We could just map
    # over the list but this is probably a bit faster. TODO: Perhaps
    # generating the set as a cross-tab type query in the DB would be faster.
    my @projects;
    $search->execute(@args);
    while (my $project = $search->fetchrow_hashref) {
        $status->execute( $project->{id} );

        # Get the statuses and load it into the hash.
        $project->{status}{ $_->{category} } = { 
            id    => $_->{id},
            class => (defined $_->{state} ? $_->{state} : 'x'),
            label => (not defined $_->{state} or $_->{state} eq 'none') 
                         ? '' : uc(substr($_->{state}, 0, 1)),
        } while ($_ = $status->fetchrow_hashref);

        push @projects, $project;
    }
use Data::Dumper;
print STDERR "HAVE PROJECTS FOR STATUS: ", Dumper(\@projects);

    # Output the template.
    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'status/search.html';

    print HTML::FillInForm->new->fill(
        fobject   => $r, 
        scalarref => \$t->process(
            r         => $r,
            user      =>  $r->pnotes('user'),
            projects  => \@projects,
            records   => scalar @projects,
            timestamp => $dbh->selectrow_array(q{
                SELECT to_char(CURRENT_TIMESTAMP, 'YYYY-MM-DD HH24:MI')
            }),
        )
    );

   return OK; 
}

# Check to see if any search results being displayed need a status update. If
# so send the JS to update them.
sub results_modified {
    my $r = shift;

    my $since = $r->param('timestamp');
    my @pids  = grep { $_ } map { tr/0-9//cd; $_; } $r->param('pid');

    # Determine what's been modified since the last check, then get the
    # overall category status for any category that's been modified.
    my $placeholders = join ',', ('?') x @pids;
    my $sth          = $dbh->prepare(qq{
        SELECT p.lngprojectindex ||'-'|| c.lngindex AS id, 
               composite_state(s.type)              AS state
        FROM tbl_service_types t, tbl_project_contents p,
             tbl_service_categories c, project_state s,
             (  SELECT DISTINCT p.lngprojectindex, c.lngindex
            FROM tbl_service_types t, tbl_project_contents p,
                 tbl_service_categories c
            WHERE c.strid     = t.strcategory
              AND t.strid     = coalesce(p.strservicetype, 'Printing')
              AND p.lngprojectindex IN ($placeholders)
              AND p.dtmlastmodified > ? ) AS a
        WHERE p.lngprojectindex = a.lngprojectindex
          AND c.lngindex        = a.lngindex
          AND c.strid           = t.strcategory
          AND t.strid           = coalesce(p.strservicetype, 'Printing')
          AND s.id              = p.lngcompletestate
        GROUP BY p.lngprojectindex, c.lngindex
    });
    $sth->execute(@pids, $since);
    
    # Change the results into JS updates.
    my @functions;
    push @functions, "updateStatus('$_->[0]', '$_->[1]');"
        while $_ = $sth->fetch;

    # TEMP: Update timestamp so the autoupdate doesn't reget the update.
    my $now = $dbh->selectrow_array(q{
        SELECT to_char(CURRENT_TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')
    });
    
    # Send the resultant JS to the browser.
    $r->content_type('text/plain; charset=utf-8');
    print "@functions; timestamp = '$now';";
    
    return OK;
}



# Display the status summary of the requested project.
sub project {
    my $r = shift;
    my $t = shift;

    # Simplistic sanity checks.
    my $pid = $r->param('pid'); $pid =~ tr/0-9//cd;

    # Basic project information.
    my $proj = project_info($pid);

    # We'll get a cache of the valid project service production states. This
    # is not to be confused with the overall legacy statuses.
    my $states = $dbh->selectall_hashref(q{
        SELECT * FROM project_state
    }, 'id');
    
    # Get the project services.
    $proj->{services} = $dbh->selectall_arrayref(q{
        SELECT p.lngserviceindex AS id,       t.strname          AS name,     
               c.strname         AS category, p.ysnremoved       AS supplied, 
               p.strstatus       AS status,   p.lngcompletestate AS state,
               p.strcomments     AS comments, t.strid            AS ref,
               
               to_char(p.dtmlastmodified, 'YYYY-MM-DD HH24:MI') AS mtime
               -- to_char(now() - p.dtmlastmodified, 'HH24h MIm ago') AS mtime
               
        FROM tbl_project_contents   p, tbl_service_types t, 
             tbl_service_categories c
        WHERE coalesce(p.strservicetype, 'Printing') = t.strid -- Problematic
          AND t.strcategory     = c.strid
          AND p.lngprojectindex = ?
        ORDER BY c.lngindex, t.lngsort, t.strname, p.lngserviceindex
    }, { Slice => {} }, $pid);

    # TODO: If the project is multipage we need to hide 'Printing'.

    # Certain project services have special naming conventions.
    for my $s (@{ $proj->{services} }) {
        # Signatures get their descriptіve names.
        if ($s->{ref} eq 'Printing') {
            $s->{name} = $dbh->selectrow_array(q{
                SELECT strvalue FROM tbl_service_specifications 
                WHERE strname = 'txtServiceDescription' AND lngserviceindex = ?
            }, {}, $s->{id});
        }
        # Shipping displays what it's shipping in it's name. 
        elsif ($s->{ref} eq 'Shipping') {
            $s->{name} .= ' — ' . $dbh->selectrow_array(q{
                SELECT strvalue FROM tbl_service_specifications 
                WHERE strname = 'txtServiceDescription' AND lngserviceindex = ?
            }, {}, $s->{id});
        }
        # Custom line items should display their user provided name.
        elsif ($s->{ref} eq 'Custom') {
            my ($name) = $dbh->selectrow_array(q{
                SELECT strvalue FROM tbl_service_specifications 
                WHERE strname = 'ServiceName' AND lngserviceindex = ?
            }, {}, $s->{id});
            $name =~ s/^\s+(.*?)\s+$/$1/;
            $s->{name} = $name if defined $name and $name ne ''; # 0 is allowed
        }
    }

    $proj->{services} = group @{ $proj->{services} }, 'category';

    # For each category we need to aggregate the state of the services, the
    # fallover works as such: 
    for my $cat (@{ $proj->{services} }) {
        # Map the cached state information to the project services.
        $_->{state} = $states->{ $_->{state} } for @{ $cat->{data} };
        
        # Find the aggregate state for category display. 
        $cat->{state} = aggregate_state($cat->{data});

    }

    # Get the last five changes from the changelog
    $proj->{changelog} = project_changelog($pid, limit => 5);
    
    # Timestamp for JS autoupdate to know when we were generated.
    my $timestamp = $dbh->selectrow_array('SELECT CURRENT_TIMESTAMP');
 
    # Output the template.
    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'status/project.html';

    print $t->process(
        r     => $r,
        user  => $r->pnotes('user'),
        proj  => $proj,
        timestamp => $timestamp,
    );

   return OK; 
}

# Given a list of services, determine the aggregate state type. The rules for
# such are commented within the code below.
sub aggregate_state {
    my $services = shift;

    # If any individual service is in 'wait' the category is.
    return 'wait' if grep {$_->{state}{type} eq 'wait'} @$services;

    # If all are done the category is 'done' as well.
    return 'done' 
        if (grep {$_->{state}{type} eq 'done'} @$services) == @$services;
   
    # Any other mix of states is 'open'.
    return 'open' if grep {$_->{state}{type} ne 'none'} @$services;

    # No states means nothing's been done. 
    return undef;
}

# TODO: Refactor this and project_service_state to use the same function to
# actually modify the states.
sub project_category_state {
    my ($r, $t) = @_;

    # We only support setting the state through this function at this time.
    return HTTP_METHOD_NOT_ALLOWED unless $r->method eq 'POST';

    # Simple argument assertions.
    my $pid     = $r->param('pid');   $pid   =~ tr/0-9//cd;
    my $cat     = $r->param('cat');   $cat   =~ tr/0-9//cd;
    my $state   = $r->param('state'); $state =~ tr/0-9//cd;
    
    die "Integer PID, category, and state expected. Found: ($pid, $cat. $state)."
        unless $pid and $cat and $state >= 0; # 0 state allowed

    # TODO: Only allow alphanumeric, whitespace, and punctuation here.
    my $comment = $r->param('comment') || undef;

    # We audit all changes to project service states. For the moment this
    # means only application logging (we'd need less if we defined a
    # database trigger). TODO: Define afforementioned trigger.
    $dbh->do(q{
        INSERT INTO state_transaction (uid, comment)
        VALUES (?, ?)
    }, {}, $r->pnotes('user')->{id}, $comment);
    my $xid = $dbh->last_insert_id(undef, undef, 'state_transaction', 'id');

    # Update all the project services in the category to the given state.
    $dbh->do(q{
        UPDATE tbl_project_contents 
        SET lngcompletestate = ?
        WHERE lngserviceindex IN (
            SELECT p.lngserviceindex
            FROM tbl_service_types t, tbl_project_contents p,
                 tbl_service_categories c
            WHERE c.strid           = t.strcategory
              AND t.strid           = coalesce(p.strservicetype, 'Printing')
              AND p.lngprojectindex = ?
              AND c.lngindex        = ? )
    }, {}, $state, $pid, $cat);
    # Associate them with their changelog entry.
    $dbh->do(qq{
        INSERT INTO state_transaction_service (xid, sid, state)
            SELECT $xid, p.lngserviceindex, $state
            FROM tbl_service_types t, tbl_project_contents p,
                 tbl_service_categories c
            WHERE c.strid           = t.strcategory
              AND t.strid           = coalesce(p.strservicetype, 'Printing')
              AND p.lngprojectindex = ?
              AND c.lngindex        = ? 
    }, {}, $pid, $cat);
    $dbh->commit;

    # TODO: Get the state name from a cached copy (either here or HTML/JS)
    $state = $dbh->selectrow_array(q{ 
        SELECT type FROM project_state WHERE id = ?}, {}, $state);

    # TEMP: Update timestamp so the autoupdate doesn't reget the update.
    my $now = $dbh->selectrow_array(q{
        SELECT to_char(CURRENT_TIMESTAMP, 'YYYY-MM-DD HH24:MI')
    });
    
    # Send the resultant JS to the browser.
    $r->content_type('text/plain; charset=utf-8');
    print "updateStatus('$pid-$cat', '$state'); timestamp = '$now';";
    
    return OK;
};

sub update_tech {
    my $r = shift;
    my $pid = $r->param('pid'); $pid =~ tr/0-9//cd;
	my $tech = $r->param('tech');

	$dbh->do(q{
		UPDATE tbl_projects SET tech = ? WHERE lngprojectindex = ?
	}, undef, $tech, $pid);

	$dbh->commit;

    $r->headers_out->{Location} = "/status/project?pid=$pid";
    return HTTP_MOVED_TEMPORARILY;
}


# Complete the entire project at once.
sub complete_project {
    my $r = shift;

    my $pid = $r->param('pid'); $pid =~ tr/0-9//cd;

    die "Integer project ID required" unless $pid;

    # Update each individual service in the project.
    my $sids = $dbh->selectcol_arrayref(q{
        SELECT lngserviceindex FROM tbl_project_contents 
        WHERE lngprojectindex = ?
    }, {}, $pid);

    change_state($r->pnotes('user')->{id}, $sids, COMPLETE, 
        'Project completed.'
    );

    # Update the project to complete.
	$dbh->do(q{ 
		UPDATE tbl_projects 
        SET strstatus = 'Complete',
            dtmshipdate = NOW()
		WHERE lngprojectindex = ? 
	}, undef, $pid);

    # TODO Pass this to the function
    my $order = $dbh->selectrow_array(q{
        SELECT lngorderid 
        FROM tbl_order_contents 
        WHERE lngprojectindex = ?
    }, undef, $pid);

    require eprint::employee_project;

    # Mark the order as complete/paid based on if all projects are complete
    # TODO DB trigger.
    eprint::employee_project::mark_order($dbh, $order);

    # Send a project completion email.
#    eprint::employee_project::send_project_complete_email(
#        $r, $dbh, $pid, $order, $r->pnotes('user')->{account}
#    );

	$dbh->commit;

    $r->headers_out->set( Location => "/status/project?pid=$pid" );
    $r->status(HTTP_MOVED_TEMPORARILY);
    return OK;
}


# Retrieve or set the completion state of one or more project services. TODO:
# Take a timestamp argument so we can perform collision checks (return
# HTTP_NOT_MODIFIED with response body setting all the changed project
# services to the proper state ... an internal call to project_modified would
# suffice). TODO: Take a state list to parallel the SID list.
sub project_service_state {
    my ($r, $t) = @_;

    # We only support setting the state through this function at this time.
    return HTTP_METHOD_NOT_ALLOWED unless $r->method eq 'POST';

    # Simple argument assertions.
    # my $pid     = $r->param('pid');     $pid     =~ tr/0-9//cd;
    my $state   = $r->param('state');   $state   =~ tr/0-9//cd;
    my @sids    = grep { defined $_ and $_ >= 0 } 
                   map { tr/0-9//cd; $_         } $r->param('sid');
    
    die "Integer state and one or more SIDs expected. Found: ($state, @sids)."
        unless @sids and $state >= 0; # 0 state allowed

    # TODO: Only allow alphanumeric, whitespace, and punctuation here.
    my $comment = $r->param('comment') || undef;

    # Change the state of the selected project services.
    change_state($r->pnotes('user')->{id}, \@sids, $state, $comment);

    # TODO: There's got to be a better way to do this, for now though we'll
    # pass a redirect param if we want to be redirected elsewhere (probably
    # back to ourselves) if we don't want the JS return used for
    # XMLHttpRequests.
    if ($r->param('location')) {
        $r->headers_out->set( Location => $r->param('location') );
        $r->status(HTTP_MOVED_TEMPORARILY);
        return OK;
    }

    # TEMP: Update timestamp so the autoupdate doesn't reget the update.
    my $now = $dbh->selectrow_array(q{
        SELECT to_char(CURRENT_TIMESTAMP, 'YYYY-MM-DD HH24:MI')
    });
    
    # If we're here we succeeded.
    $r->content_type('text/plain; charset=utf-8');
    my @functions = map { "setState($_, $state, '$now');" } @sids;
    print qq{
        @functions; timestamp = '$now';
    };
    return OK;
}

# Change the given project services to the given state, with an optional
# comment to indicate why the state was modified.
sub change_state {
    my $user    = shift; # User ID of person changing the state.
    my $sids    = shift; # Project service IDs to modify.
    my $state   = shift; # State (int) to change to.
    my $comment = shift; # Optional comment.
    
    # We audit all changes to project service states. For the moment this
    # means only application logging (we'd need less if we defined a
    # database trigger). TODO: Define afforementioned trigger.
    $dbh->do(q{
        INSERT INTO state_transaction (uid, comment)
        VALUES (?, ?)
    }, {}, $user, $comment);
    my $xid = $dbh->last_insert_id(undef, undef, 'state_transaction', 'id');

    # Sets the state of the project service. TODO: If we aren't going to allow
    # different state changes within the same transaction then we should set
    # all the states at once instead of looping over the state change query.
    my $update_state = $dbh->prepare(q{
        UPDATE tbl_project_contents SET lngcompletestate = ?
        WHERE lngserviceindex = ?
    });
    # Insert a changelog entry.
    my $insert_log = $dbh->prepare(q{
        INSERT INTO state_transaction_service (xid, sid, state)
        VALUES (?, ?, ?)
    });

    # Do the above for every service specified.
    for my $sid (@$sids) {
        $update_state->execute($state, $sid);
        $insert_log->execute($xid, $sid, $state);
    }
    $dbh->commit;

    return scalar @$sids;
}


# Given a timestamp returns JS code to update the project display if the
# project has been modified since the timestamp (updates timestamp on each
# check).
sub project_modified {
    my $r = shift;

    # Simple argument assertions.
    my $pid       = $r->param('pid'); $pid =~ tr/0-9//cd;
    my $timestamp = $r->param('timestamp');

    my $now = $dbh->selectrow_array('SELECT CURRENT_TIMESTAMP');

    my $services = $dbh->selectall_arrayref(q{
        SELECT c.lngprojectindex                                AS pid, 
               t.strcategory                                    AS cat,
               c.lngserviceindex                                AS sid,
               c.lngcompletestate                               AS state,
               to_char(c.dtmlastmodified, 'YYYY-MM-DD HH24:MI') AS mtime
        FROM tbl_project_contents c, tbl_service_types t
        WHERE coalesce(c.strservicetype, 'Printing') = t.strid
          AND c.lngprojectindex = ?
          AND c.dtmlastmodified > ?
    }, { Slice => {} }, $pid, $timestamp);

    # Changed will be false if no service records are found.
    my $changed = @$services;
    
    my @functions; # Things to update.
    if ($changed) {
        # Set the services that have changed to the proper state.
        @functions = map { 
            sprintf "setState(%d, %d, '%s');", 
                @$_{ qw(sid state mtime) }
        } @$services;

        # Get any transactions/comments (limit of five) that have occured since
        # the last check. TEMP: For now we always just get the last five.
        my @changelog = map { 
          '['.( join ',', map {"\"$_\""} @$_{qw(xid mtime uid name comment)} ).']' 
        } reverse project_changelog($pid, { limit => 5 });
        push @functions, "appendChangeLog([". join(',', @changelog) ."]);";
    }
    
    # Send the JS code back.
    $r->content_type('text/plain; charset=utf-8');
    print "@functions \n['$now', $changed];";
    
    return OK;
}


sub service {
    my $r = shift;
    my $t = shift;

    # Simplistic sanity checks.
    my $pid = $r->param('pid'); $pid =~ tr/0-9//cd;
    my $sid = $r->param('sid'); $sid =~ tr/0-9//cd;

    # Basic project information.
    my $proj = project_info($pid);

    # Get the service information. TODO: Get it ;)
    my $service = $dbh->selectrow_hashref(q{
        SELECT c.lngserviceindex  AS id, 
               t.strname          AS name,
               s.name             AS state,
               s.type             AS class
        FROM tbl_service_types t, tbl_project_contents c, project_state s
        WHERE t.strid = coalesce(c.strservicetype, 'Printing')
          AND c.lngcompletestate = s.id
          AND c.lngserviceindex  = ?
    }, {}, $sid);

    # Get the union of the state audit log with comments and the general
    # comments for this project service. 
    $service->{comments} = project_changelog ($pid, {
        service     => $sid, 
        gen_comment => 0,
        reverse     => 1,
    });

    # We need to know when we were generated for autoupdates.
    my $timestamp = $dbh->selectrow_array('SELECT CURRENT_TIMESTAMP');

    # As the CSS white-space: pre-wrap isn't widely supported we'll mock
    # a modifier up that performs similarly. This modifier is meant to only be
    # used with the 'structure' keyword.  Not sure enough of extending Petal
    # yet to know how to check for it.
    $Petal::Hash::MODIFIERS->{'prewrap:'} = sub {
        my $hash = shift;
        my $args = shift;
        
        my $res = $hash->fetch($args);
    
        # Encode basic HTML entities for reading and for security.
        $res =~ s/\&/\&amp;/g;
        $res =~ s/\</\&lt;/g;
        $res =~ s/\"/\&quot;/g;

        # Replace newlines and add a non-breaking space between every set of
        # two spaces (one space is always preserved). Tabs become spaces (8).
        $res =~ s/\n/<br \/>/g;
        $res =~ s/  / &nbsp;/g;
        $res =~ s/\t/ &nbsp; &nbsp; &nbsp; &nbsp;/g;
        
        return $res; 
    };

    
    # Output the template.
    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'status/service.html';

    print $t->process(
        r         => $r,
        user      => $r->pnotes('user'),
        proj      => $proj,
        service   => $service,  
        timestamp => $timestamp,
    );

   return OK;  
}


# Retrieve the last (by time) n tranaction records and/or general comments from
# the given project.
#
# Options:
#   since       => timestamp, # Only changes after this date/time
#   service     => SID,       # Only report on one service
#   limit       => int,       # Limit return to n records
#   offset      => int,
#   gen_comment => bool,      # Generate comment on actions if no user text.
#   
sub project_changelog {
    my $pid    = shift; # Project ID

    # Take either a hashref or a flat hash.
    my %opt;
    if   (ref $_[0] eq 'HASH') { %opt = %{(shift)} }
    else                       { %opt = @_         }

    # Comment generation is on by default.
    $opt{gen_comment} = 1 unless defined $opt{gen_comment};
    
    # We'll get a cache of the valid project service production states. This
    # is not to be confused with the overall legacy statuses.
    my $states = $dbh->selectall_hashref(q{
        SELECT * FROM project_state
    }, 'id');

    # Clauses
    my ($service, $limit, $offset, $order, $since);
    $service = "AND s.sid = ?"       if $opt{service} > 0;
    $limit   = "LIMIT  $opt{limit}"  if $opt{limit}   > 0;
    $offset  = "OFFSET $opt{offset}" if $opt{offset}  > 0;
    $order   = $opt{reverse} ? 'ASC' : 'DESC';
    $since   = "AND mtime > ?"       if $opt{since};
    
    # Retrieve the last (by time) n transactions and general comments for the
    # project. TODO: Use :1 instead of ? syntax.
    my $sql = qq{
       SELECT t.xid, t.mtime, t.uid, u.strfirstname || ' ' || u.strlastname AS name, t.comment
        FROM tbl_customer_users u, (
            SELECT x.id AS xid, x.uid, x.mtime, x.comment
            FROM state_transaction x, state_transaction_service s, tbl_project_contents p
            WHERE x.id  = s.xid
              AND s.sid = p.lngserviceindex 
              AND p.lngprojectindex = ?
              $service

            UNION

            SELECT NULL, c.uid, c.mtime, c.comment
            FROM project_service_comment c, tbl_project_contents p
            WHERE c.sid = p.lngserviceindex 
              AND p.lngprojectindex = ?
           ) AS t
        WHERE u.lnguserid = t.uid
          $since
        ORDER BY mtime $order
        $limit
        $offset
    };
    my $xaction = $dbh->prepare($sql);

    # Gets the service and state changes made within a transaction.
    my $services = $dbh->prepare(qq{
        SELECT t.strname AS service_type, s.sid, s.state
        FROM state_transaction_service s, 
             tbl_project_contents      c, tbl_service_types t
        WHERE t.strid = coalesce(c.strservicetype, 'Printing')
          AND s.sid   = c.lngserviceindex
          AND s.xid   = ?
          $service
    });

    my @changelog;
    $xaction->execute(
        $pid, 
        ($opt{service}) ? $opt{service} : (), 
        $pid,
        ($opt{since})   ? $opt{since}   : (), 
    );
    while (my $rec = $xaction->fetchrow_hashref) {
        # Transaction records need a list of what project services they apply
        # to and the states that were set.
        if (defined $rec->{xid}) {
            $rec->{services} = [ 
                map { $_->{state} = $states->{ $_->{state} }; $_ }
                   @{ $dbh->selectall_arrayref($services, { Slice => {} }, 
                           $rec->{xid}, ($opt{service}) ? $opt{service} : ()) }
            ];
            # We only allow one state change within a transaction currently.
            $rec->{state} = $rec->{services}[0]{state};
        
            # If record is without a comment we'll generate one based on what
            # went on in the transaction.
            if ($opt{gen_comment} and not defined $rec->{comment}) {
                my $state = $rec->{state}{name};
                my $list  = join ', ', map { $_->{service_type} } 
                                          @{ $rec->{services}   };
                
                $rec->{comment} = "State '$state' applied to $list.";
            }
        }
        push @changelog, $rec;
    }
    
    # Return the changelog.
    return wantarray ? @changelog : (@changelog ? \@changelog : undef);
}


# Given a timestamp returns JS code to update the project service display if
# the project service has been modified since the timestamp (updates timestamp
# on each check).
sub service_modified {
    my $r = shift;

    my $pid       = $r->param('pid'); $pid =~ tr/0-9//cd;
    my $sid       = $r->param('sid'); $sid =~ tr/0-9//cd;
    my $timestamp = $r->param('timestamp');

    my $now = $dbh->selectrow_array('SELECT CURRENT_TIMESTAMP');

    # See if there have been any changes or comments since the last check.
    my $changelog = project_changelog (
        $pid, { service => $sid, since => $timestamp, gen_comment => 0, }
    );

    if (defined $changelog) {
        for my $x (@$changelog) {
            $x->{state}   = $x->{state}{id}; # Flat int ID only
            $x->{comment} =~ s/"/\"/g;       # JS escaped
            
            $x = sprintf "new XAction (%d,%d,'%s',%d,'%s','%s')", 
                @$x{qw(xid state mtime uid name comment)};
        }

        $changelog = 'appendLog(['. join(',', @$changelog) .'])';
    }

    # Send the JS code back.
    $r->content_type('text/plain; charset=utf-8');
    print "$changelog; timestamp = '$now';";
    
    return OK;
}



1;
