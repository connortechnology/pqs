package PQS::WWW::Admin;
use strict;
use warnings;
use utf8;

use Apache2::Const qw(OK SERVER_ERROR HTTP_MOVED_TEMPORARILY NOT_FOUND HTTP_MOVED_TEMPORARILY);
use Apache2::Request ();
use Apache2::RequestUtil ();
use Apache2::ServerUtil;
use Apache2::Log ();
use HTML::FillInForm ();
use Petal;
use Petal::Utils qw(:all);
use PQS::Constants;
use PQS::DB ();
use PQS::Error;
use PQS::Log::Audit ();
use PQS::Util qw( group get_modules );
use Symbol qw(qualify_to_ref);
use session;

use PQS::WWW::Predefined;

use constant PRESS_TYPES => qw(14 38 41 43);

# NOR SHOULD THESE #

# Banker's round a number to an optional scale (default 2).
sub round ($;$) {my($n,$s)=@_;$s=(defined $s)?$s:2;int($n*10**$s+0.5)/10**$s}
sub precision ($) {($_)=@_;m/-?\d+\.?(\d*)$/ or return;$_=$1;s/0*$//;length$_}

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
    local $dbh = PQS::DB->connect($r);

    session::r($r);
    session::log($r->log);
    session::dbh($dbh);

    $r->pnotes(dbh => $dbh);

    # At the end of each request we'll roll back any unsaved change and
    # disconnect from the database. We'd much rather keep the connection but,
    # given the existing eprint code, we can't use a persistant handle.
    Apache2::ServerUtil::server->push_handlers("PerlCleanupHandler", sub {
            if ($dbh) {
                Apache2::ServerUtil->server->log_error('DB handle still present');
                $dbh->rollback();
                $dbh->disconnect();
            }
            return OK;
    });

    # Register a log handler for auditting.
    Apache2::ServerUtil::server->push_handlers("PerlLogHandler", \&PQS::Log::Audit::handler);


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

print STDERR "HAVE NAME: $name \n";

    # Get a refrence to the function.
    my $func = qualify_to_ref( $name, __PACKAGE__ );

    # Verify that the function requested exists, if not return a 404.
    return NOT_FOUND unless defined &$func;

    # Unless the user is a valid user, throw them back to the login.
    # TEMPORARY: This will be handled in auth handlers.
    unless ( valid_user($r, $name) ) {
print STDERR "NOT VALID USER \n";
        $r->headers_out->{Location} = "/administrator/";
        $r->status(HTTP_MOVED_TEMPORARILY);
        return HTTP_MOVED_TEMPORARILY;
    }


    # Dispatch the request and return its status.
    my $status = eval{ *{ $func }{CODE}->($r, $t) };

    if ($@) {
        my $err = $@;

        $dbh->rollback;
        $dbh->disconnect;

        $r->log->error($err);

        if (DEBUG) {
            require Error::StackTrace;
            $r->status(SERVER_ERROR);
            $r->content_type('text/html');
            print Error::StackTrace::trace($r, $err);
            return OK;
        }

        return SERVER_ERROR;
    }

    $dbh->rollback;
    $dbh->disconnect;

    return $status;
}

sub valid_user {
	my $r = shift;
	my $func = shift;
	my @efunc = qw(item items categories category question modify_question item_paper item_cover_paper item_service );

print STDERR "HAVE FUNC: $func \n";
	return 1 if valid_admin($r);

	my $f =  grep {$_ eq $func} @efunc;
	my $v =  valid_employee($r);
print STDERR "HAVE E: $f VALID: $v \n";
	return 1 if ($f && $v); 
	return 0;
}

sub valid_employee {
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
               chrusertype = 'E'                         AS is_admin,
               ( now() >
                 dtmlastaccessed + (SELECT (strconfigdata||' seconds')::interval
                                     FROM tbl_configuration
                                     WHERE strconfigtitle = 'idletime') )
        FROM tbl_logged_in
        WHERE strsessionid = ?
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

# Very, very basic authentication/authorization check that ties in with the
# old sytem. All we do is see if we have a session cookie, the session hasn't
# timed out, and that the user is of type 'A' (Administrator).
sub valid_admin {
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
        WHERE strsessionid = ?
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

sub get_paper
{
    return $dbh->selectall_arrayref(q{
        SELECT DISTINCT strcategory AS category,
                        strname     AS name,
                        strcalliper AS calliper,
                        strweight   AS weight,
                        strfinish   AS finish,
                        strcolour   AS colour,
                        paper_family(p) AS id
        FROM tbl_paper p

        UNION DISTINCT

        SELECT DISTINCT strcategory AS category,
                        strname     AS name,
                        strcalliper::TEXT AS calliper,
                        strweight   AS weight,
                        strfinish   AS finish,
                        strcolour   AS colour,
                        paper_family(p) AS id
        FROM tbl_paper_roll p

        ORDER BY 1,2,3,4,5,6
    }, { Slice => {} });
}

sub select_paper {
    my $r = shift;
    my $t = shift;

    # Select all the distinct paper 'families' from our non-3NF paper table.
    my $paper = get_paper();

    # Group the paper category (bond, envelope, board, etc).
    $paper = group @$paper, 'category';

    # Output the template.
    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'admin/paper/select.html';

    print $t->process(r => $r,
        title         => 'Paper Selection',
        paper         => $paper,
    );

    return OK;
}

sub visibility {
    my ($r, $t) = @_;

    if ($r->param('action') eq 'Save') {
        my $sth = $dbh->prepare(
            "UPDATE tbl_paper_recommendations SET ysnvisible = ?
                WHERE lngpaperindex IN
                (SELECT lngindex FROM tbl_paper p WHERE paper_family(p) = ?)"
        );

        my $visibility_map = {
            v => 't',
            i => 'f',
        };

        foreach my $selectbox (keys %$visibility_map) {
            foreach my $family ($r->param($selectbox)) {
                $sth->execute($visibility_map->{$selectbox}, $family);
            }
        }
        $dbh->commit();
    }

    my $paper = get_paper();

    my $query = qq{ 
        SELECT DISTINCT paper_family(p) as family, ysnvisible FROM
            tbl_paper_recommendations r, tbl_paper p
            WHERE r.lngpaperindex = p.lngindex

		UNION

        SELECT DISTINCT paper_family(p) as family, ysnvisible FROM
            tbl_paper_recommendations r, tbl_paper_roll p
            WHERE r.lngpaperindex = p.lngindex
	};

    my $visibility = $dbh->selectall_hashref($query, 'family');

    my (@visible, @invisible);

    for my $key (@$paper) {
        if ($visibility->{ $key->{id} }->{ysnvisible} eq '1') {
            push (@visible, $key);
        }
        elsif ($visibility->{ $key->{id} }->{ysnvisible} eq '0') {
            push (@invisible, $key);
        }
    }

    my $visible   = group @visible,   'category';
    my $invisible = group @invisible, 'category';

    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'admin/paper/visible.html';

    print $t->process(
        r         => $r,
        title     => 'Visibility Paper Selection',
        visible   => $visible,
        invisible => $invisible,
    );

    return OK;
}

sub item_service {
    my ($r, $t) = @_;
	
	my $eid = $r->param('item');

	my ($equip_type, $type_id) = ('','');

    if ($r->param('action') eq 'Save') {

		$dbh->do(q{ DELETE FROM product.item_service WHERE item = ?  },undef, $eid);

        my $sh = $dbh->prepare(qq{ INSERT INTO product.item_service  values ( ?, ? ); });

        foreach my $family ($r->param('i')) {
        	$sh->execute($eid, $family);
        }

        $dbh->commit();
    }

    my $service = $dbh->selectall_arrayref(q{
		SELECT *, lngindex as id, strcategory as category FROM tbl_service_types ORDER by 1
	},{Slice=>{}});


    my $query = qq{
		SELECT DISTINCT lngindex as service,
		(SELECT count(*) FROM product.item_service e 
		 WHERE e.service = s.lngindex AND e.item =  ? ) as invalid
		FROM  tbl_service_types s
	};

    my $visibility = $dbh->selectall_hashref($query,'service',{},$eid );

    my (@visible, @invisible);
	for my $key (@$service) {
        if ( $visibility->{ $key->{id} }->{invalid} eq '0') {
            push (@visible, $key);
        }
        elsif (  $visibility->{ $key->{id} }->{invalid}) {
            push (@invisible, $key);
        }
    }

    my $visible   = group @visible,   'category';
    my $invisible = group @invisible, 'category';

    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'admin/predefined/service.html';

    print $t->process(
        r         => $r,
        title     => 'Product Service Selection',
        visible   => $visible,
        invisible => $invisible,
		eid       => $eid
    );

    return OK;
}
sub item_cover_paper {
    my ($r, $t) = @_;
	
	my $eid = $r->param('item');


	my $table = $r->param('type') eq 'roll' ? 'tbl_paper_roll' : 'tbl_paper';

    if ($r->param('action') eq 'Save') {


		$dbh->do(qq{ DELETE FROM product.item_cover_paper WHERE item = ?  
					AND paper IN ( SELECT lngindex FROM $table )
		},undef, $eid);

        my $sh = $dbh->prepare(qq{
        	INSERT INTO product.item_cover_paper (
                SELECT $eid, lngindex FROM tbl_paper p WHERE paper_family(p) = ?
            )
        });
        my $rl = $dbh->prepare(qq{
        	INSERT INTO product.item_cover_paper (
                SELECT $eid, lngindex FROM tbl_paper_roll p WHERE paper_family(p) = ?
            )
        });

        foreach my $family ($r->param('i')) {
print STDERR "INSERT PAPER: $family - $eid T: $table \n";
        	$sh->execute($family);
        	$rl->execute($family);

        }

print STDERR "DBH COMMIT HERE \n";
        $dbh->commit();
    }

    my $paper = get_paper();


    my $query = qq{
		SELECT DISTINCT paper_family(p) as family,
		(SELECT count(*) FROM product.item_cover_paper e WHERE e.paper = p.lngindex AND e.item =  ? ) as invalid
		FROM  $table p
	};

    my $visibility = $dbh->selectall_hashref($query,'family',{},$eid );

    my (@visible, @invisible);
	for my $key (@$paper) {
        if ( $visibility->{ $key->{id} }->{invalid} eq '0') {
            push (@visible, $key);
        }
        elsif (  $visibility->{ $key->{id} }->{invalid}) {
            push (@invisible, $key);
        }
    }

    my $visible   = group @visible,   'category';
    my $invisible = group @invisible, 'category';


    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'admin/predefined/stock.html';
    $t->{file} = 'admin/predefined/cover_stock.html';

    print $t->process(
        r         => $r,
        title     => 'Equipment Paper Selection',
        visible   => $visible,
        invisible => $invisible,
		eid       => $eid,
		type	  => $r->param('type')
    );

    return OK;

}

sub item_paper {
    my ($r, $t) = @_;
	
	my $eid = $r->param('item');


	my $table = $r->param('type') eq 'roll' ? 'tbl_paper_roll' : 'tbl_paper';

    if ($r->param('action') eq 'Save') {

		$dbh->do(qq{ DELETE FROM product.item_paper WHERE item = ?  
					AND paper IN ( SELECT lngindex FROM $table )
		},undef, $eid);

        my $sh = $dbh->prepare(qq{
        	INSERT INTO product.item_paper (
                SELECT $eid, lngindex FROM tbl_paper p WHERE paper_family(p) = ?
            )
        });
        my $rl = $dbh->prepare(qq{
        	INSERT INTO product.item_paper (
                SELECT $eid, lngindex FROM tbl_paper_roll p WHERE paper_family(p) = ?
            )
        });

        foreach my $family ($r->param('i')) {
print STDERR "INSERT PAPER: $family - $eid T: $table \n";
        	$sh->execute($family);
        	$rl->execute($family);

        }

print STDERR "DBH COMMIT HERE \n";
        $dbh->commit();
    }

    my $paper = get_paper();


    my $query = qq{
		SELECT DISTINCT paper_family(p) as family,
		(SELECT count(*) FROM product.item_paper e WHERE e.paper = p.lngindex AND e.item =  ? ) as invalid
		FROM  $table p
	};

    my $visibility = $dbh->selectall_hashref($query,'family',{},$eid );

    my (@visible, @invisible);
	for my $key (@$paper) {
        if ( $visibility->{ $key->{id} }->{invalid} eq '0') {
            push (@visible, $key);
        }
        elsif (  $visibility->{ $key->{id} }->{invalid}) {
            push (@invisible, $key);
        }
    }

    my $visible   = group @visible,   'category';
    my $invisible = group @invisible, 'category';


    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'admin/predefined/stock.html';

    print $t->process(
        r         => $r,
        title     => 'Equipment Paper Selection',
        visible   => $visible,
        invisible => $invisible,
		eid       => $eid,
		type	  => $r->param('type')
    );

    return OK;

}

sub equipment_paper {
  my ($r, $t) = @_;

  my $eid = $r->param('equipment');

  my ($equip_type, $type_id) = $dbh->selectrow_array(q{
    SELECT t.lngindex, t.strid FROM tbl_equipment_type t, tbl_equipment e 
    WHERE  t.strid = e.strtype
    AND    e.lngindex  = ? 
    }, undef, $eid);

  my $table = $type_id eq 'web' || $type_id eq 'inkjetprinter' ? 'tbl_paper_roll' : 'tbl_paper';

  if ($r->param('action') eq 'Save') {

    $dbh->do(q{ DELETE FROM equipment_paper_exclusion WHERE equipment = ?  },undef, $eid);

    my $sh = $dbh->prepare(qq{
      INSERT INTO equipment_paper_exclusion (
      SELECT $eid, lngindex FROM tbl_paper p WHERE paper_family(p) = ?
      )
      });
    my $rl = $dbh->prepare(qq{
      INSERT INTO equipment_paper_exclusion (
      SELECT $eid, lngindex FROM tbl_paper_roll p WHERE paper_family(p) = ?
      )
      });

    foreach my $family ($r->param('i')) {

      print STDERR "HAVE PAPER: $family - $eid \n";

      $sh->execute($family);
      $rl->execute($family);
    }

    $dbh->commit();
  }

  my $paper = get_paper();


  my $query = qq{
  SELECT DISTINCT paper_family(p) as family,
  (SELECT count(*) FROM equipment_paper_exclusion e WHERE e.paper = p.lngindex AND e.equipment =  ? ) as invalid
  FROM  $table p
  };
  if ($type_id eq 'inkjetprinter') {
    $query .= qq{
    UNION
    SELECT DISTINCT paper_family(p) as family,
    (SELECT count(*) FROM equipment_paper_exclusion e WHERE e.item = p.lngindex AND e.equipment =  $eid ) as invalid
    FROM  tbl_paper p
    };

  }
  print STDERR "HAVE Q: $query \n";

  my $visibility = $dbh->selectall_hashref($query,'family',{},$eid );

  my (@visible, @invisible);
  for my $key (@$paper) {
    if ( $visibility->{ $key->{id} }->{invalid} eq '0') {
      push (@visible, $key);
    }
    elsif (  $visibility->{ $key->{id} }->{invalid}) {
      push (@invisible, $key);
    }
  }

  my $visible   = group @visible,   'category';
  my $invisible = group @invisible, 'category';

  $r->content_type('text/html; charset=utf-8');
  $t->{file} = 'admin/paper/equipment.html';

  print $t->process(
    r         => $r,
    title     => 'Equipment Paper Selection',
    visible   => $visible,
    invisible => $invisible,
    eid       => $eid
  );

  return OK;
}

sub recommendations {
    my $r = shift;
    my $t = shift;

    if ($r->method() eq 'GET' and not $r->args) {
        return select_paper($r, $t);
    }
    elsif ($r->method() eq 'POST') {
        update_recommendations($r);
        $r->headers_out->set(
            Location => $r->uri ."?". $r->args );
        $r->status(HTTP_MOVED_TEMPORARILY);
        return OK;
    }

    # Get the recommendations for the selected papers, including how many of
    # the set have that recommendation.
    my @paper = $r->param('p');
    my $paper = join ',', map { $dbh->quote($_) } @paper;
    my $sth = $dbh->prepare(qq{
        SELECT lngprojecttypeindex, lngpresstype, count(DISTINCT paper_family(p))
        FROM tbl_paper_recommendations r, tbl_paper p
        WHERE r.lngpaperindex = p.lngindex
          AND paper_family(p) IN ($paper)
        GROUP BY lngprojecttypeindex, lngpresstype

        UNION

        SELECT lngprojecttypeindex, lngpresstype, count(DISTINCT paper_family(p))
        FROM tbl_paper_recommendations r, tbl_paper_roll p
        WHERE r.lngpaperindex = p.lngindex
          AND paper_family(p) IN ($paper)
        GROUP BY lngprojecttypeindex, lngpresstype
    });
    $sth->execute();

    # Convert the list into our matrix representation of "$proj-$press-$all"
    # where all indicates if some (false 0) or all (true 1) of the selected
    # papers share that recommendation.
    my %recommend;
    $recommend{"$_->[0]-$_->[1]"} = ($_->[2] == @paper || 0)
        while $_ = $sth->fetch;

    # Get all the project types.
    my $project_types = $dbh->selectall_arrayref(q{
        SELECT lngindex AS id, strname AS name
        FROM tbl_projecttypes
        ORDER BY strname
    }, { Slice => {} });

    # And the press types.
    my $press_types = $dbh->selectall_arrayref(q{
        SELECT e.lngindex AS id, strname AS name,
               upper(substr(e.strid, 0, 2)) AS ref
        FROM equipment_type_service_type t, tbl_equipment_type e
        WHERE t.equipment_type = e.lngindex
          AND t.service_type   = ?
        ORDER BY 2
    }, { Slice => {} }, 68); # Printing

    # Output the template.
    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'admin/paper/recommendations.html';

    my $f = new HTML::FillInForm;

    print $f->fill( fdat => \%recommend, scalarref => \$t->process(
        r             => $r,
        title         => 'Paper Recommendations',
        project_types => $project_types,
        press_types   => $press_types,
    ));;

    return OK;
}

sub update_recommendations {
    my $r = shift;

    # Get a stringified list of the paper we're working on.
    my $paper = join ',', map { $dbh->quote($_) } $r->param('p');

    my @paper = @{ $dbh->selectcol_arrayref(qq{
        SELECT lngindex
        FROM tbl_paper
        WHERE paper_family(tbl_paper) IN ($paper)

        UNION

        SELECT lngindex
        FROM tbl_paper_roll
        WHERE paper_family(tbl_paper_roll) IN ($paper)
    })};

    $paper = join ',', @paper;

    # Our recommendation data is composed of a matrix row-col address
    # representing the project type and press type respectively, it's data is
    # the operation we want to perform. We'll remove null (0) operations and
    # change it's representation to a tuple.
    my @data = map  { ($a, $b) = split /-/; [$r->param($_), $a+0, $b+0]; }
               grep { /^\d+-\d+$/ and $r->param($_)                      }
                    $r->param;

    my $delete = $dbh->prepare(qq{
        DELETE FROM tbl_paper_recommendations
        WHERE lngprojecttypeindex = ? AND lngpresstype = ?
          AND lngpaperindex IN ($paper)
    });

    my $exist = $dbh->prepare(q{
        SELECT true FROM tbl_paper_recommendations
        WHERE lngpaperindex       = ?
          AND lngprojecttypeindex = ?
          AND lngpresstype        = ?
    });

    my $insert = $dbh->prepare(q{
        INSERT INTO tbl_paper_recommendations
            (lngpaperindex, lngprojecttypeindex, lngpresstype)
            VALUES
            (?, ?, ?)
    });

    for my $datum (@data) {
        my ($op, $proj, $press) = @$datum;

        # If we're an insert run, through the list of papers and add them if
        # they're not already there.
        if ($op == 1) {
            for my $paper (@paper) {
                $insert->execute($paper, $proj, $press)
                    unless $dbh->selectrow_array(
                        $exist, {}, $paper, $proj, $press
                    );
            }
        }
        # Otherwise delete the recommendation.
        else {
            $delete->execute($proj, $press);
        }
    }

    $dbh->commit;
}

#     # Insert is a subset of remove as we're going
#     my %set;
#     for my $datum (@data) {
#         my ($op, $press, $proj) = @$datum;
#
#         $set{$press}        = {} if not exist $set{$press};
#         $set{$press}{$proj} = [] if not exist $set{$press}{$proj};
#
#         push @{ $set{$press}{$proj} }, ($op == 2) 'DEL' : 'INS';
#     }
#
#     for my $press (keys %set) {
#         my $del = join ',', keys %{ $set{$press} };
#
#         $dbh->do(qq{
#             DELETE FROM tbl_paper_recommendations
#             WHERE lngprojectindex IN ($projects)
#               AND lngpaperindex IN (SELECT lngindex
#                                     FROM tbl_paper
#                                     WHERE press_family(tbl_paper) IN ($paper)
#         });
#
#         my $ins = join ',', grep { $set{$press}{$_} eq 'INS' }
#                                   keys %{ $set{$press} };
#     }




# Currently gives the equipment list, this will also serve as the dispatch
# function for equipment specs, etc.
sub equipment {
    my $r = shift;
    my $t = shift;

print STDERR "START EQUIPMENT NOW $r, $t, \n";

    # Get all the valid types for the 'new' option. An equipment type is valid
    # if any service types can be performed on it.
    my $types = $dbh->selectall_arrayref(q{
        SELECT lngindex AS id, strname AS name
        FROM tbl_equipment_type
        WHERE lngindex IN (
            SELECT equipment_type FROM equipment_type_service_type )
        ORDER BY name
    }, {Slice => {}});

    # Get a list of all equipment in inventory (that has a type currently).
    # Filtering and grouping will be added ASAP.
    my $equip = $dbh->selectall_arrayref(q{
        SELECT e.lngindex       AS eid,
               e.strid          AS id,
               e.strname        AS name,
               e.strdescription AS description,
               t.strid          AS type_ref,
               t.strname        AS type,
               e.strcategory    AS category
        FROM tbl_equipment e, tbl_equipment_type t
        WHERE e.strtype = t.strid
        ORDER BY type, id
    }, { Slice => {} });

    # Group the equipment set by type.
    $equip = group @$equip, 'type';

    # Output the template.
    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'admin/equipment/list.html';

    print $t->process(
        title     => 'Equipment List',
        equipment => $equip,
        types     => $types,
    );

    return OK;
}

# Display and edit equipment specifications.
sub specifications {
    my $r = shift;
    my $t = shift;

    # Simplistic sanity checks.
    my $eid  = $r->param('equipment'); $eid  =~ tr/0-9//cd if $eid; # Edit existing.
    my $type = $r->param('type');      $type =~ tr/0-9//cd if $type; # Create new.

    die "An integer equipment id or an equipment type is required."
        unless $eid or $type;

    if ( $r->method eq 'POST') {
        # This is neither the preferred nor final dispatch method for things
        # like this. The buttons should post (or a link w/ a get param) to the
        # function directly and that function should do a redirect.
        if ( $r->param('copy') ) {
            my $new = copy_equipment($eid);
            $r->headers_out->set(
                Location => "/admin/specifications?equipment=$new" );
            $r->status(HTTP_MOVED_TEMPORARILY);
            return OK;
        }

        # If the delete button was pressed, delete the equipment and redirect
        # the user to the equipment listing.
        if ( $r->param('delete') ) {
            delete_equipment($eid);
            $r->headers_out->set(
                Location => "/admin/equipment"); # $equipment->{type}" );
            $r->status(HTTP_MOVED_TEMPORARILY);
            return OK;
        }

        # If we're posting to the page then we need to do an update before
        # displaying the updated values.
        update_specifications( $r ) if defined $r->param('save');
    }

    # Get the currently selected equipment's basic attributes (if we're
    # editing an existing one) otherwise give it our type.
    my $equipment = $eid ? attributes($eid) : create($type);

    # Get all the valid specifications for the currently selected equipment.
    # Note: We should only have to pass equipment id but due to the
    # interchangable use of strid and id that would require at least two other
    # joins.
    my $sth = $dbh->prepare_cached(q{
        SELECT e.id,
               e.dsc as name,
               e.description,
               e.ranged,
               s.dblmin   AS min,
               s.dblmax   AS max,
               s.strvalue AS value,
               s.strunits AS unit
        FROM equipment_type_specification e
        LEFT JOIN ( SELECT strname, dblmin, dblmax, strvalue, strunits
                    FROM tbl_equipment_specifications
                    WHERE lngequipmentindex = ? ) s ON (e.name = s.strname)

        WHERE (e.type = ? OR e.type IS NULL)
        ORDER BY ranged, name, (dblmin IS NOT NULL), min, max
    });
    $sth->execute( $eid, $equipment->{type_id} );

    # Each spec may have multiple units for it's value. While it's valid
    # to have multiple ranged units we have none now so we don't bother handling
    # it yet. (We could also query all units for the service and uses hashes
    # to map between... might be faster).
    my $unit = $dbh->prepare_cached(q{
        SELECT u.name
        FROM unit u, equipment_type_specification_unit s
        WHERE s.unit          = u.id
          AND s.specification = ?
          AND s.ranged        = ?
    });

    # If we're creating a new piece of equipment and there aren't any results,
    # it must be invalid.

    # TODO : Generalise the grouping function and use hash slices for the
    # attribute slicing.

    # Sort them out into two seperate result sets for easier display.
    my (@ranged, @unranged);

    my $last = undef;
    while ( my $rec = $sth->fetchrow_hashref ) {
        # If the item isn't ranged we can just append it to the list.
        if ( not $rec->{ranged} ) {
            # Get the list of value units.
            $rec->{units}{value} =
                $dbh->selectcol_arrayref($unit, undef, $rec->{id}, 0);
            $rec->{units}{multiple} = @{ $rec->{units}{value} } > 1;

            # Push onto the queue.
            push(@unranged, $rec);
            next;
        }

        # Add a new spec onto the stack if we're done with the current.
        if ( not defined $last or $rec->{id} ne $last->{id} ) {
            # Add a bunch of empty ranges to the tail of spec ranges.
            push @{ $ranged[-1]->{ranges} }, ({}) x 4 if defined $last;

            # Push a new specification onto the stack.
            push @ranged, {
                id           => $rec->{id},
                name         => $rec->{name},
                ranges       => [],
                units        => {
                    value  => $dbh->selectcol_arrayref($unit, undef, $rec->{id}, 0),
                    ranged => $dbh->selectrow_array($unit, undef, $rec->{id}, 1),
                },
            };
            # Due to a mismatch between Petal and Perl (TAL comes from
            # Python's OO) some easy things are harder. Here we set a
            # variable to get the length of the units/price array. Really we
            # should be able to say "units/price/length" or something similar.
            $ranged[-1]->{units}{multiple} = @{$ranged[-1]->{units}{value}} > 1;
        }

        # Push the price range onto the current service's range list.
        push @{ $ranged[-1]->{ranges} }, $rec;

        $last = $rec; # A pointer to the last record processed.
    }
    # Handle the off case of only a single ranged service, or the last one in
    # the list, where $last won't be defined.
    push @{ $ranged[-1]->{ranges} }, ({}) x 4 if @ranged;

    # Output the template.
    $t->{file} = 'admin/equipment/specification.html';


	#Make a list of suppliers.
	my $supplier = $dbh->selectcol_arrayref(q{
		SELECT strcompanyname
		FROM tbl_customer
		WHERE ysnsupplier = 'Y'
		ORDER by lower(strcompanyname)
	},undef);

	my $is_press = grep {$equipment->{type_id} eq $_} PRESS_TYPES;

    # Start making the client happy.
    $r->content_type('text/html; charset=utf-8');
    my $f = new HTML::FillInForm;


	my $list = { comp_price => $equipment->{comp_price}};

    print $f->fill( fdat => $list, scalarref => \$t->process(
        r     => $r,
        title => 'Equipment Specifications',
        equip => $equipment,
		supplier => $supplier,
		is_press => $is_press,
		comp_price => 1,
        specifications => { unranged => \@unranged,
                            ranged   => \@ranged    },
    ));

   return OK;
}


# sub press {
#     my $f = new HTML::FillInForm;
#
#     # Get a list of all valid proof types (which currently equates to
#     # services).
#     my $sth = $dbh->prepare(q{
#         SELECT s.strid AS id, s.strname AS "name"
#         FROM tbl_services s, tbl_service_types t
#         WHERE t.lngindex = s.lngtype
#           AND t.strid    = 'Proofs'
#     });
#
#     print $f->fill( $t->process(
#     );
# }



# Display the equipment / service / pricelist pricing page.
sub pricing {
    my $r = shift;
    my $t = shift;

    # Simplistic sanity checks.
    my $eid = $r->param('equipment'); $eid =~ tr/0-9//cd;
    die "An integer equipment id is required." unless $eid;

    my $lid   = $r->param('pricelist');
    my $stid  = $r->param('servicetype');
    my $subid = $r->param('sub_type');

    # If we're not posting, we only need the equipment id as we'll choose a
    # default service type and list.
    if ( $r->method eq 'POST') {
        $lid =~ tr/0-9//cd;
        die "An integer list id is required." unless $lid;

        $stid =~ tr/0-9//cd;
        die "An integer service type id is required." unless $stid;

        # Delete the pricing for the service type if they've chosen to no
        # longer provide it on this equipment.
        # delete_pricing( $if $r->param('remove')

        # If we're posting to the page then we need to do an update before
        # displaying the updated values.
        update_pricing( $r ) if $r->param('save');
    }

    $t->{file} = '/admin/pricing/pricing.html';

    # EQUIPMENT
    #
    # Get the currently selected equipment's basic attributes.
    my $equipment = attributes($eid);

    
    # SERVICE TYPES
    #
    # Which service types, of all possible for the type of equipment, does the
    # currently selected piece of equipment provide?
    #
    # Should this also check for 0 pricing in the offered service types? So we
    # can display it in the sidebar?.
    #
    # A somewhat bastardised query, we shouldn't have to pass both the type and
    # equipment id in, but ohh well (among other things).
    my $sth = $dbh->prepare_cached(q{
        SELECT a.service_type              AS id,
               s.strname                   AS "name",
               coalesce(b.selected, false) AS "exists"
        FROM tbl_service_types s,
           ( SELECT service_type
             FROM equipment_type_service_type s,
                  tbl_equipment_type          t
             WHERE s.equipment_type = t.lngindex
               AND t.lngindex       = ? ) AS a LEFT JOIN
           ( SELECT service_type, true AS selected
             FROM service_type_equipment
             WHERE equipment        = ? ) AS b USING (service_type)
        WHERE a.service_type = s.lngindex
        ORDER BY "name"
    });
    my $types = $dbh->selectall_arrayref(
        $sth, { Slice => {} }, $equipment->{type_id}, $eid );

    # If we've been supplied a service type, grab it's info out of the list.
    # Otherwise choose the first one as a default.
    my ($type) = defined $stid ? grep {$_->{id} == $stid} @$types : $types->[0];

    # SUB-TYPES
    #
    # A newer addition is labelled service types. This allows multiple service
    # types differing by some labelled attribute. TODO Show the pricing
    # existance for sub-types as well.
    $sth = $dbh->prepare(q{
        SELECT id, "name" 
        FROM sub_service_type 
        WHERE service_type = ? 
        ORDER BY "name"
    });
    my $sub_types = $dbh->selectall_arrayref($sth, { Slice => {} }, $type->{id});

    # There is always the base service type.
    unshift @{ $sub_types }, { id => undef, => name => 'Default' };

    # If the sub-type was supplied use it, otherwise use the default.
    my ($sub_type) = (defined $subid)
        ? grep {defined $_->{id} && $_->{id} == $subid} @$sub_types
        : $sub_types->[0];

    # PRICE LISTS
    #
    # Which price lists, of all possible, does the currently selected equipment
    # and service type have pricing in?
    $sth = $dbh->prepare_cached(q{
        SELECT l.id, l.name, l.currency, c.symbol, count(p.list) > 0 AS "exists"
        FROM pricelist l LEFT JOIN (
             SELECT lnglistindex AS list
             FROM tbl_service_prices
             WHERE lngequipmentindex = ?
              AND lngserviceindex IN (
                 SELECT lngindex
                 FROM tbl_services
                 WHERE lngtype = ? )
             ) AS p ON (l.id = p.list),
             currency c
        WHERE l.currency = c.code
        GROUP BY l.id, l."name", l.currency, c.symbol
        ORDER BY l.currency, l.name
    });
    my $lists = $dbh->selectall_arrayref(
        $sth, { Slice => {} }, $eid, $stid );

    # If we've been supplied a price list, grab it's info out of the list.
    # Otherwise choose the first one as a default.
    my ($list) = defined $lid ? grep {$_->{id} == $lid} @$lists : $lists->[0];

    
    # PRICING
    #
    # Get all the valid services for the currently selected service type and
    # join it with the current pricing. Kludged in equipment_type/service
    # exclusion. TODO This query has gotten ridiculous, refactor.
    $sth = $dbh->prepare_cached(q{
        SELECT s.lngindex       AS id,
               s.strid          AS ref,
               s.strname        AS "name",
               s.strdescription AS description,
               s.ysnranged      AS ranged,

               p.lngmin                                 AS min, -- For ranged
               p.lngmax                                 AS max, -- For ranged
               to_char(p.dblcost,   'FM999990D00999')   AS cost,
               to_char(p.dblprice,  'FM999990D00999')   AS price,
               to_char(p.dblmarkup, 'FM999990D0009999') AS markup,
               p.strunits                               AS unit,
               CASE p.ysndiscountable
               WHEN 'Y' THEN true
               ELSE false         END               AS discountable
        
        FROM equipment_type_service e, 
             tbl_services s
        LEFT JOIN (SELECT lngserviceindex, lngmin, lngmax, 
                          strunits, dblcost, dblprice, dblmarkup, ysndiscountable
                   FROM tbl_service_prices
                   WHERE lngequipmentindex = ?
                     AND lnglistindex      = ? 
                     AND (    lngsubservicetype = ? 
                          OR (lngsubservicetype IS NULL AND ?::INT IS NULL) )
             ) p ON (s.lngindex = p.lngserviceindex)
     
        WHERE s.lngindex = e.service
          AND e.equipment_type = ?
          AND s.lngtype = ?
        ORDER BY ranged, s.lngsortorder, "name", (lngmin IS NOT NULL), min, max
    });
    $sth->execute( $eid,                  $list->{id}, 
                   $sub_type->{id},       $sub_type->{id}, 
                   $equipment->{type_id}, $type->{id}
    );

    # Each service may have multiple units for it's pricing. While it's valid
    # to have multiple ranged units we have none now so don't bother handling
    # it yet. (We could also query all units for the service and uses hashes
    # to map between... might be faster).
    my $unit = $dbh->prepare_cached(q{
        SELECT u.name
        FROM unit u, service_unit s
        WHERE s.unit    = u.id
          AND s.service = ?
          AND s.ranged  = ?
    });

    # TODO : Generalise the grouping function and use hash slices for the
    # attribute slicing.

    # Sort them out into two seperate result sets for easier display.
    my (@ranged, @unranged);

    # We have a kludge to exclude certain services from pricing based on
    # equipment specs if the equipment type is some sort of press.
    my $is_press = is_press($equipment->{type_id});

    my $last = undef;
    while ( my $rec = $sth->fetchrow_hashref ) {
        # Exclude certain services based on the equipment specs, but only for
        # presses. It's kludgerific!
        next if $is_press and service_exkludgeion($eid, $rec->{ref});

        # If the price isn't ranged we can just append it to the list.
        if ( not $rec->{ranged} ) {
            # Get the list of pricing units.
            $rec->{units}{price} =
                $dbh->selectcol_arrayref($unit, undef, $rec->{id}, 0);
            $rec->{units}{multiple} = @{ $rec->{units}{price} } > 1;

            # Push onto the queue.
            push(@unranged, $rec);
            next;
        }

        # Add a new service onto the stack if we're done with the current.
        if ( not defined $last or $rec->{id} != $last->{id} ) {
            # Add a bunch of empty ranges to the tail of services ranges.
            push @{ $ranged[-1]->{ranges} }, ({}) x 4 if defined $last;

            # Push a new service onto the stack.
            push @ranged, {
                id           => $rec->{id},
                name         => $rec->{name},
                discountable => $rec->{discountable},
                ranges       => [],
                units        => {
                price        => $dbh->selectcol_arrayref(
                                    $unit, undef, $rec->{id}, 0
                                ),
                ranged       => scalar $dbh->selectrow_array(
                                    $unit, undef, $rec->{id}, 1
                                ),
                },
            };
            # Due to a mismatch between Petal and Perl (TAL comes from
            # Python's OO) some easy things are harder. Here we set a
            # variable to get the length of the units/price array. Really we
            # should be able to say "units/price/length" or something
            # similar.
            $ranged[-1]->{units}{multiple} = @{$ranged[-1]->{units}{price}}>1;
        }

        # Push the price range onto the current service's range list.
        push @{ $ranged[-1]->{ranges} }, $rec;

        $last = $rec; # A pointer to the last record processed.
    }
    # Handle the off case of only a single ranged service, or the last one in
    # the list, where $last won't be defined.
    push @{ $ranged[-1]->{ranges} }, ({}) x 4 if @ranged;

    # Parse error when the condition in the ternary operator isn't a
    # constant... Don't know if there _is_ a proper syntax to get this
    # working.
    # push(($_->{ranged} ? @ranged : @unranged), $_) while $sth->fetchrow_hashref;

    # Start making the client happy.
    $r->content_type('text/html; charset=utf-8');

    print $t->process(
        # This might be renamed and will definitely added to the infastructure.
        r => $r,

        title     => "Pricing",
        equip     => $equipment,
        
        type      => $type,      # Current
        types     => $types,

        sub_type  => $sub_type, # Current
        sub_types => $sub_types,
        
        list      => $list,      # Current
        lists     => $lists,
        
        price => { ranged => \@ranged, unranged => \@unranged },
    );

    return OK;
}

sub service_exkludgeion {
    my $eid  = shift; # The equipment ID.
    local $_ = shift; # The service reference (string id).

    # Is the press a perfecting press?
    my $is_perfecting = $dbh->selectrow_array(q{
        SELECT (CASE WHEN strvalue = 'Y' THEN true ELSE false END)
        FROM tbl_equipment_specifications
        WHERE lower(replace(strname, ' ', '')) = 'perfectingpress'
          AND lngequipmentindex = ?
    }, undef, $eid);

    return 1 if /^Perfecting ?ChangeOver/i and not $is_perfecting;

    # If the equipment is a press, check it's specs and remove any
    # '$nColourImpression(Perfecting)?' based on the number of colours the
    # press has, and the whether it's perfecting capable.
    my ($n, $p) = /^([1-9][0-1]?)(?:-[1-9])? ?Colour ?Impression ?(Perfecting)?$/i;

    # If we didn't match it's not a spec we handle.
    return 0 unless $n;

    # If the service is for perfecting and the press isn't, exclude it.
    return 1 if $p and not $is_perfecting;

    # How many units does the press have?
    my $colours = $dbh->selectrow_array(q{
        SELECT strvalue
        FROM tbl_equipment_specifications
        WHERE lower(replace(strname, ' ', '')) = 'numberofcolours'
          AND lngequipmentindex = ?
    }, undef, $eid);

    # If the service is a perfecting one, we can only do the number of
    # up to one less than the number of colours (because 4/0 perfecting is
    # actually just 4 sheetwork). And when not perfecting we can do up to the
    # number of colours/press unit we have.
    return (($p and $n >= $colours) or (not $p and $n > $colours)) ? 1 : 0;
}


# Returns wether or not the given equipment type can print (ie. is it a
# press?).
sub is_press {
    my $type = shift;

    my $presses = $dbh->selectcol_arrayref(q{
        SELECT e.equipment_type
        FROM equipment_type_service_type e,
             tbl_service_types s
        WHERE e.service_type = s.lngindex
          AND s.strid = 'Printing'});

    return scalar grep { $type == $_ } @$presses;
}




# Display the material / pricelist pricing page.
sub material {
    my $r = shift;
    my $t = shift;

    # Start making the client happy.
    $r->content_type('text/html; charset=utf-8');

    # Simplistic sanity checks.
    my $lid  = $r->param('pricelist');
    my $mtid = $r->param('materialtype');

    # If we're not posting, we only need the equipment id as we'll choose a
    # default service type and list.
    if ( $r->method eq 'POST') {
        $lid =~ tr/0-9//cd;
        die "An integer list id is required." unless $lid;

        $mtid =~ tr/0-9//cd;
        die "An integer service type id is required." unless $mtid;

        # If we're posting to the page then we need to do an update before
        # displaying the updated values.
        update_material_pricing( $r )
    }

    $t->{file} = '/admin/material/material.html';

    # Get all the material categories, also specifying if any pricing exists
    # for a material in that category. TODO: For now we just say everything
    # exists, fix that.
    my $sth = $dbh->prepare_cached(q{
        SELECT id, name, true AS exists
        FROM material_type
        WHERE id IN (SELECT DISTINCT lngtype FROM tbl_materials)
        ORDER BY name
    });
    my $types = $dbh->selectall_arrayref( $sth, { Slice => {} } );

    # If we've been supplied a material type, grab it's info out of the list.
    # Otherwise choose the first one as a default.
    my ($type) = defined $mtid ? grep {$_->{id} eq $mtid} @$types : $types->[0];

    # Which price lists, of all possible, does the currently selected material
    # category have pricing in? For now we'll just show all.
    $sth = $dbh->prepare_cached(q{
        SELECT l.id,
               l.name,
               l.currency,
               c.symbol,
               true       AS "exists"
        FROM pricelist l, currency c
        WHERE l.currency = c.code
        ORDER BY l.currency, l.name
    });
    my $lists = $dbh->selectall_arrayref( $sth, { Slice => {} });

    # If we've been supplied a price list, grab it's info out of the list.
    # Otherwise choose the first one as a default.
    my ($list) = defined $lid ? grep {$_->{id} eq $lid} @$lists : $lists->[0];

    # Material categories define the units the materials in them are priced
    # by. Get the units for the selected category.
    my ($price_unit, $ranged_unit) = $dbh->selectrow_array(q{
        SELECT p.name, r.name
        FROM material_type t
        LEFT JOIN unit p ON (t.price_unit  = p.id)
        LEFT JOIN unit r ON (t.ranged_unit = r.id)
        WHERE t.id = ?
    }, undef, $type->{id});

    # Get all the valid materials for the currently selected material category
    # and join it with the current pricing.
    $sth = $dbh->prepare_cached(q{
        SELECT m.lngindex  AS id,
               m.strname   AS "name",

               p.lngmin                                 AS min,
               p.lngmax                                 AS max,
               to_char(p.dblcost,   'FM999990D00999')   AS cost,
               to_char(p.dblprice,  'FM999990D00999')   AS price,
               to_char(p.dblmarkup, 'FM999990D0009999') AS markup,

               p.lngequipmentindex                      AS equip,

               CASE p.ysndiscountable
                   WHEN 'Y' THEN true
                   ELSE false         END               AS discountable
        FROM tbl_materials m LEFT JOIN (
                 SELECT lngmaterialindex, lngmin, lngmax, lngequipmentindex,
                        dblcost, dblprice, dblmarkup, ysndiscountable
                 FROM tbl_material_prices
                 WHERE lnglistindex = ? ) p
              ON (m.lngindex = p.lngmaterialindex)
        WHERE m.lngtype = ?
        ORDER BY "name", equip, (lngmin IS NOT NULL), min, max
    });
    $sth->execute( $list->{id}, $type->{id} );

    # TODO : Generalise the grouping function and use hash slices for the
    # attribute slicing.

    # Sort them out into two seperate result sets for easier display.
    my @ranged;

    my $last = undef;
    while ( my $rec = $sth->fetchrow_hashref ) {
        # Add a new service onto the stack if we're done with the current.
        if ( not defined $last or $rec->{id} != $last->{id} ) {
            # Add a bunch of empty ranges to the tail of material ranges.
            push @{ $ranged[-1]->{ranges} }, ({}) x 4 if defined $last;

            # Push a new service onto the stack.
            push @ranged, {
                id           => $rec->{id},
                name         => $rec->{name},
                discountable => $rec->{discountable},
                ranges       => [],
            };
        }

        # Push the price range onto the current service's range list.
        push @{ $ranged[-1]->{ranges} }, $rec;

        $last = $rec; # A pointer to the last record processed.
    }
    # Handle the off case of only a single ranged service, or the last one in
    # the list, where $last won't be defined.
    push @{ $ranged[-1]->{ranges} }, ({}) x 4 if @ranged;

    # Parse error when the condition in the ternary operator isn't a
    # constant... Don't know if there _is_ a proper syntax to get this
    # working.
    # push(($_->{ranged} ? @ranged : @unranged), $_) while $sth->fetchrow_hashref;

    print $t->process(
        # This might be renamed and will definitely added to the infastructure.
        r => Apache2::RequestUtil->request,

        title => "Material Pricing",
        type  => $type,      # Currently selected
        types => $types,
        list  => $list,      # Currently selected
        lists => $lists,

        pricing => \@ranged,
        unit => { price => $price_unit, ranged => $ranged_unit, },
    );

    return OK;
}

#
# THESE INTERNAL FUNCTIONS SHOULD BELONG TO A SEPERATE MODULE
#

# Update pricing, update material pricing, should both be called update in
# their respective modules and there should be some generalisation to storing
# pricing data as the functions are very, very similar.


sub update_pricing {
    # For ease of understanding we'll process the data in interative steps,
    # sacrificing some speed and memory for the sake of quicker understanding.

    my $r = shift;

    # Simplistic sanity checks.
    my $eid = $r->param('equipment'); $eid =~ tr/0-9//cd;
    die "An integer equipment id is required." unless $eid;

    my $lid = $r->param('pricelist'); $lid =~ tr/0-9//cd;
    die "An integer list id is required." unless $lid;

    my $stid = $r->param('servicetype'); $stid =~ tr/0-9//cd;
    die "An integer service type id is required." unless $stid;

    my $subid = $r->param('sub_type'); $subid =~ tr/0-9//cd; # Optional.
    $subid = undef unless $subid;
    
    # Allowing only pricing fields, seperate the input name components
    # (sid-row-field), then sort the input parameters sid and row.  Getting
    # an array of anon arrays [ sid, row, field, name ] out.
    my @input = sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] }
                map  { local @_ = split /\-/; [ @_, $_ ]          }
                grep { /^\d+-\d+-\w+$/                            }
                $r->param;

    # Use hashes to group records by the uniq. service type, then each row
    # becomes a key, then a final hash of field/value pairs of the data.
    my %set;
    for my $input ( @input ) {
        my ($sid, $row, $field, $i) = @$input;
        $set{$sid}{$row}{$field} = $r->param($i) eq '' ? undef : $r->param($i);
    }

    # Prepare our insert query for quick processing. TODO: Generalise a create
    # insert statement from hash or some kind of DBIXish module.
    my $sth = $dbh->prepare(q{
        INSERT INTO tbl_service_prices (
            lngequipmentindex, lnglistindex, lngserviceindex,
            lngsubservicetype, lngmin, lngmax, dblcost, dblmarkup, dblprice,
            strunits, ysndiscountable )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    });
    my @fields = qw( min max cost markup price unit discountable );

    # We delete all the pricing for the current three-way selection and just
    # insert over it. At some point we may do selective updates but probably
    # not until we store ranges in a different fashion.
    $dbh->do(qq{
        DELETE FROM tbl_service_prices
        WHERE lngequipmentindex    = ?
          AND lnglistindex         = ?
          AND lngserviceindex IN (
            SELECT lngindex FROM tbl_services WHERE lngtype = ? )
          AND (   lngsubservicetype = ? 
              OR (lngsubservicetype IS NULL AND ?::INT IS NULL) )
    }, undef, $eid, $lid, $stid, $subid, $subid);

    # Process the records a row at a time (grouping by service).
    for my $sid ( keys %set ) {
        for my $rec ( values %{ $set{$sid} } ) {
            # As discountable is checked per service (though currently stored
            # per record), we need to look at the zeroeth record for that
            # information. Same for pricing units.
            $rec->{discountable} = $set{$sid}{0}{discountable}
                unless exists $rec->{discountable};

            $rec->{unit} = $set{$sid}{0}{unit}
                unless exists $rec->{unit};

            # Validate the current record, skip if it's invalid (we die in the
            # validate function if there are user input problems). TODO: Trap
            # those errors and handle sensibly.
            $rec = validate_price($rec) or next;

            # TODO: Validate ranges in the larger scope, not just per record.

            # Insert the current record.
            $sth->execute( $eid, $lid, $sid, $subid, @$rec{ @fields } );
       }
    }
    # TODO: Consider VACUUM ANALYSEing the pricing table after a shift.
    return $dbh->commit;
}


sub validate_price {
    # For price and cost, we treat undefined and zero in the same manner,
    # assuming that a 0 cost or price is not intentional. All pricing fields
    # have a hard precision limit of five.

    my $rec = shift; # The passed record reference.

    # As we don't yet have a way to display errors to the user nicely, we'll
    # try to "do what they mean".
    for my $f (qw(min max cost markup price)) {
        # Some basic cleaning incase we have some invalid characters.
        $rec->{$f} =~ tr/0-9.-//cd;

        # All of these should be real numbers, if not they don't count.
        $rec->{$f} = undef unless $rec->{$f} && $rec->{$f} =~ /^-?\d+\.?\d*$/;
    };

    # Skip unless we have at least a price or cost (+0 makes sure it evaluates
    # as a numeric so the string "0.00" doesn't pass).
    return undef unless $rec->{cost}+0 or $rec->{price}+0;

    # The most common occurence is that we either have no data (handled above)
    # or all the data (which skips this).
    unless ($rec->{cost} and $rec->{price} and defined $rec->{markup} ) {
        # If we don't have all the data we make a number of assumptions about
        # missing data; in order to generate any of the missing three (the
        # fact we store all three is useless -- but we do).

        # If markup is defined, set the cost or price based on the other one
        # we do have. Markups have a precision of precision_price + 1 in order
        # to remove rounding errors.
        if (defined $rec->{markup}) { # Clean up (I want Haskell for this :)
            my ($i, $j) = $rec->{cost} ? qw(cost price) : qw(price cost);
            my $p = precision $rec->{$i}; $p = $p > 2 ? $p : 2;

            # We can safely round their markup up past. NO. Actually we can't
            # as they may wish to define a markup to a greater degree of
            # accuracy across the board, then some costs with that accuracy
            # will use it, others won't.
            # $rec->{markup} = round $rec->{markup}, $p + 1;

            $rec->{$j} = ( $i eq 'cost' )
                ? $rec->{$i} * ($rec->{markup} / 100 + 1)
                : $rec->{$i} / ($rec->{markup} / 100 + 1);
            $rec->{$j} = round $rec->{$j}, $p;
        }
        # Here we have either cost, price or both but no markup.
        else {
            # Unless we have a price, set it to the cost.
            $rec->{price} = $rec->{cost}
                unless $rec->{price};
            # Unless we have a cost, set it to the price.
            $rec->{cost} = $rec->{price}
                unless $rec->{cost};

            # Which has the greater precision?
            my $p = do {
                my $i = precision $rec->{cost};
                my $j = precision $rec->{price};
                ($i >= $j) ? $i : $j;
            };

            # Calculate the markup between them (0 if we set one of the above
            # or x if we came in with both) to a precision greater than.
            $rec->{markup} = ( $rec->{price} / $rec->{cost} - 1 ) * 100;
            $rec->{markup} = round $rec->{markup}, $p + 1;
        }
    }

    # If the user has inputed all three fields and they don't match, for now
    # we throw a simple error. TODO: Evaluate with proper consideration to
    # significant digits. TODO: Eventually we need to have it highlight the
    # error rec on the page without saving to the database. TODO: Set back to
    # rounding to a precision of 2 when we have all our rules sorted out.
    die "Data Entry Error: Price != Cost * Markup $rec->{price} != $rec->{cost} * $rec->{markup} \n"
        if int((round $rec->{price}, 2) * 10)
	    != int((round $rec->{cost} * (1 + $rec->{markup} / 100), 2) * 10);

    # Assume (there's that nasty word again) the user transposed max. and min.
    # if max. is less than than min., and correct their error.
    @$rec{ qw(min max) } = @$rec{ qw(max min) }
            if $rec->{max} < $rec->{min} and defined $rec->{max};

    # Discountable is currently stored as a char(1) either 'Y' or 'N' (no
    # nulls) instead of as a boolean. So we have to map our input to that.
    $rec->{discountable} = $rec->{discountable} ? 'Y' : 'N';

    # We're finished processing so we return the record.
    return $rec;
}

sub update_specifications {
    # For ease of understanding we'll process the data in interative steps,
    # sacrificing some speed and memory for the sake of quicker understanding.

    my $r = shift;
    my $sth;
    my %params = map {$_ => $r->param($_)} $r->param;

    # Simplistic sanity checks.
    my $eid = $r->param('equipment'); $eid =~ tr/0-9//cd;
    die "An integer equipment id is required." unless $eid;

    # Generate automatic reference and name if it's not provided.
    $params{'id'} = $eid                          unless $params{'id'};
    $params{'name'} = $r->param('type') ."-$eid" unless $params{'name'};

    # Does the equipment currently exist?
    my $exists = $dbh->selectrow_array(q{
        SELECT lngindex FROM tbl_equipment WHERE lngindex = ?
    }, undef, $eid);

    # For new equipment.
    my $insert = $dbh->prepare(q{
        INSERT INTO tbl_equipment
               (strname, strid, strdescription, strsupplier, strtype, comp_price, lngindex)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    });

    # For updating an existing.
    my $update = $dbh->prepare(q{
        UPDATE tbl_equipment
           SET strname        = ?,
               strid          = ?,
               strdescription = ?,
               strsupplier    = ?,
               strtype        = ?,
			   comp_price	  = ?
        WHERE lngindex = ?
    });

    # Choose to insert or update based on existance.
    $sth = $exists ? $update : $insert;

    $sth->execute(
        (map {$params{$_} or undef} qw(name id description supplier type comp_price)), $eid);

    # Allowing only spec input fields, seperate the input name components
    # (id-row-field), then sort the input parameters id and row. Getting an
    # array of anon arrays [ id, row, field, name ] out.
    my @input = sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] }
                map  { local @_ = split /\-/; [ @_, $_ ]          }
                grep { /^\d+-\d+-\w+$/                            }
                %params;

    # Use hashes to group records by the uniq. service type, then each row
    # becomes a key, then a final hash of field/value pairs of the data.
    my %set;
    for my $input ( @input ) {
        my ($id, $row, $field, $i) = @$input;
        $set{$id}{$row}{$field} = $r->param($i) eq '' ? undef : $params{$i};
    }

    # Prepare our insert query for quick processing. TODO: Generalise a create
    # insert statement from hash or some kind of DBIXish module.
    $sth = $dbh->prepare(q{
        INSERT INTO tbl_equipment_specifications (
            lngequipmentindex, dblmin, dblmax, strvalue, strunits, strname )
        VALUES (?, ?, ?, ?, ?, ( SELECT name
                                 FROM equipment_type_specification
                                 WHERE id = ? ))
    });
    my @fields = qw( min max value unit );

    # We delete all the specs. and replace them due to time constraints and
    # figuring out ranged data. TODO: Cache the statement?
    $dbh->do(q{
        DELETE FROM tbl_equipment_specifications
        WHERE lngequipmentindex = ?
    }, undef, $eid);

    # Process the records a row at a time (grouping by service).
    for my $id ( keys %set ) {
        for my $rec ( values %{ $set{$id} } ) {
            # Zeros are valid data.
            next unless defined $rec->{value} and $rec->{value} ne '';

            # As we don't yet have a way to display errors to the user nicely,
            # we'll try to "do what they mean".
            for my $f (qw(min max)) {
                # Some basic cleaning incase we have some invalid characters.
                $rec->{$f} =~ tr/0-9.-//cd if $rec->{$f};

                # All of these should be real numbers, if not they don't count.
                $rec->{$f} = undef unless $rec->{$f} and $rec->{$f} =~ /^-?\d+\.?\d*$/;
            };

            # For ranges we treat zeros and empty strings as NULLs.
            $rec->{min} = undef unless $rec->{min};
            $rec->{max} = undef unless $rec->{max};

            # Assume (there's that nasty word again) the user transposed max.
            # and min.  if max. is less than than min., and correct their
            # error.
            @$rec{ qw(min max) } = @$rec{ qw(max min) }
            if defined $rec->{max} and defined $rec->{min} and $rec->{max} < $rec->{min};

            # TODO: Validatation! Validation! Validation!

            # Insert the current record.
            $sth->execute( $eid, @$rec{ @fields }, $id );
       }
    }
    # TODO: Consider VACUUM ANALYSEing the specifications.
    return $dbh->commit;
}

# Modify the material pricing in the database based on form input.
sub update_material_pricing {
    # For ease of understanding we'll process the data in interative steps,
    # sacrificing some speed and memory for the sake of quicker understanding.

    my $r = shift;

    # Simplistic sanity checks.
    my $lid = $r->param('pricelist'); $lid =~ tr/0-9//cd;
    die "An integer list id is required." unless $lid;

    my $stid = $r->param('materialtype'); $stid =~ tr/0-9//cd;
    die "An integer service type id is required." unless $stid;

    #find any delete instructions
    my @delete = grep {/^\d+-delete$/} $r->param;
    foreach my $id (@delete) {
      my @list = split(/\-/, $id);
      #delete each id
      $dbh->do(q{
          DELETE FROM tbl_material_prices
          WHERE lngmaterialindex         = ?
      }, undef, $list[0] + 0);
      $dbh->do(q{
          DELETE FROM tbl_materials
          WHERE lngindex         = ?
      }, undef, $list[0] + 0);
    }
    return $dbh->commit if @delete;

    #find any material name updates
    my @material_titles = grep {/^\d+-material_name$/} $r->param;
    foreach my $mat (@material_titles) {
      my @id = split('-', $mat);
      $dbh->do(q{update tbl_materials set strname = ? where lngindex = ?}, undef, $r->param($mat), $id[0]);
    }

    #add new material
    if (my $newmat = $r->param('new_material')) {
      my $newmatid = $newmat;
      $newmatid =~ s/\s/_/g;
      $dbh->do(q{insert into tbl_materials ("lngtype", "strid", "strname") values (?, ?, ?)}, undef, $stid, $newmatid, $newmat);
    }

    # Allowing only pricing fields, seperate the input name components
    # (sid-row-field), then sort the input parameters sid and row.  Getting
    # an array of anon arrays [ mid, row, field, name ] out.
    my @input = sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] }
                map  { local @_ = split /\-/; [ @_, $_ ]          }
                grep { /^\d+-\d+-\w+$/                            }
                $r->param;

    # Use hashes to group records by the uniq. service type, then each row
    # becomes a key, then a final hash of field/value pairs of the data.
    my %set;
    for my $input ( @input ) {
        my ($mid, $row, $field, $i) = @$input;
        $set{$mid}{$row}{$field} = $r->param($i) eq '' ? undef : $r->param($i);
    }

    # Prepare our insert query for quick processing. TODO: Generalise a create
    # insert statement from hash or some kind of DBIXish module.
    my $sth = $dbh->prepare(q{
        INSERT INTO tbl_material_prices (
            lnglistindex, lngmaterialindex,
            lngequipmentindex, lngmin, lngmax, dblcost, dblmarkup, dblprice,
            ysndiscountable )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
    });
    my @fields = qw( equip min max cost markup price discountable);

    # We delete all the pricing for the current three-way selection and just
    # insert over it. At some point we may do selective updates but probably
    # not until we store ranges in a different fashion.
    $dbh->do(q{
        DELETE FROM tbl_material_prices
        WHERE lnglistindex         = ?
          AND lngmaterialindex IN (
            SELECT lngindex FROM tbl_materials WHERE lngtype = ? )
    }, undef, $lid, $stid);

    # Process the records a row at a time (grouping by service).
    for my $mid ( keys %set ) {
        for my $rec ( values %{ $set{$mid} } ) {
            # As discountable is checked per service (though currently stored
            # per record), we need to look at the zeroeth record for that
            # information.
            $rec->{discountable} = $set{$mid}{0}{discountable}
                unless exists $rec->{discountable};

            # Make sure any equipment ID is an int or undef (NULL), then check
            # that it's a valid ID. If it isn't we'll just ignore it. TODO:
            # Let's give them an actual drop down or something.
            $rec->{equip} =~ tr/0-9//cd;
            $rec->{equip} = undef unless attributes($rec->{equip});

            # Validate the current record, skip if it's invalid (we die in the
            # validate function if there are user input problems). TODO: Trap
            # those errors and handle sensibly.
            $rec = validate_price($rec) or next;

            # TODO: Validate ranges in the larger scope, not just per record.
            # Insert the current record.
            $sth->execute( $lid, $mid, @$rec{ @fields } );
       }
    }
    # TODO: Consider VACUUM ANALYSEing the pricing table after a shift.
    return $dbh->commit;
}


# Display a price list for editing/manipulation.
sub pricelist {
    my $r = shift;
    my $t = shift;
       $t->{file} = 'admin/pricelist/pricelist.html'; # The HTML

    # Simplistic sanity checks.
    my $id  = $r->param('id'); $id  =~ tr/0-9//cd;

    if ( $r->method eq 'POST') {
        die "An integer price list ID is required." unless $id;

        # This is neither the preferred nor final dispatch method for things
        # like this. The buttons should post (or a link w/ a get param) to the
        # function directly and that function should do a redirect.
        if ( $r->param('copy') ) {
            my $new = copy_pricelist($id);
            $r->headers_out->set(Location => "/admin/pricelist?id=$new" );
            $r->status(HTTP_MOVED_TEMPORARILY);
            return OK;
        }

        # If the delete button was pressed, delete the equipment and redirect
        # the user to the equipment listing.
        if ( $r->param('delete') ) {
            delete_pricelist($id);
            $r->headers_out->set(Location => "/admin/pricelist");
            $r->status(HTTP_MOVED_TEMPORARILY);
            return OK;
        }

        # If the delete button was pressed, delete the equipment and redirect
        # the user to the equipment listing.
        if ( $r->param('reassign') ) {
            reassign_customers(
                $r->param('from'), $r->param('to'), $r->param('customers'));
            $r->headers_out->set(Location => "/admin/pricelist?id=$id");
            $r->status(HTTP_MOVED_TEMPORARILY);
            return OK;
        }

        # If we're posting to the page then we need to do an update before
        # displaying the updated values.
        update_pricelist( $r ) if defined $r->param('save');
    }

    # Get all other price lists for the side menu and dropdown.
    my $lists = $dbh->selectall_arrayref(q{
        SELECT id, name, currency FROM pricelist ORDER BY currency, name
    }, { Slice => {} });

    # If we don't currently have a list id we're working on, get the first one
    # from our list and send the customer there.
    unless (defined $id) {
        $r->headers_out->set(
            Location => '/admin/pricelist?id=' . $lists->[0]{id} );
        $r->status(HTTP_MOVED_TEMPORARILY);
    }

    # Start making the client happy.
    $r->content_type('text/html; charset=utf-8');

    # Get the currently selected pricelists's basic attributes.
    my $list = $dbh->selectrow_hashref(q{
        SELECT *,
               EXTRACT(month FROM expire_project) AS month,
               EXTRACT(day   FROM expire_project) AS day
        FROM pricelist
        WHERE id = ?
    }, undef, $id);

    # Get all valid currencies.
    my $currency =  $dbh->selectall_arrayref(q{
        SELECT code, name FROM currency ORDER BY code
    }, { Slice => {} });

    # Get all the customer's currently assigned to this price list.
    my $customers = $dbh->selectall_arrayref(q{
        SELECT lngcustomerid AS id, strcompanyname AS name
        FROM tbl_customer
        WHERE lngpricelist = ?
        ORDER BY 2
    }, { Slice => {} }, $id);

    # All the lists except the current are valid for reassigning customers.
    my $reassign = @$customers ? [ grep{ $id != $_->{id} } @$lists ] : undef;

    # Output the template, filling in form variables, and other fun stuff.
    my $f = new HTML::FillInForm;

    print $f->fill( fdat => $list, scalarref => \$t->process(
        r => $r,
        title => "$list->{currency} - $list->{name} Pricelist",
        list     => $list,
        lists    => $lists,
        reassign => $reassign,
        customer => $customers,
        currency => $currency,
    ));

    return OK;
}

sub pricelist_action {
    my $r = shift;

    my ($id, $field, $op, $value) = map {$r->param($_)} qw(id field op value);

    eval {
        # We only allow changes to cost and markup.
        die "Invalid field ($field).\n"
            unless grep {$field eq $_} qw(cost markup);

        # The operation must be one of the three valid ones; assignment, addition,
        # and multiplication. And assignment is valid only for markup. TODO:
        # enable that last check once the JS on the page supports it.
        die "Invalid operation ($op)\n" if not grep {$op eq $_} qw(= + *);
                                      # or ($op eq '=' and $field ne 'markup');

        # The value to apply must be numeric (zero included).
        $value =~ tr/0-9+\.-//cd;
        die "Invalid syntax for numeric value ($value).\n"
            unless $value =~ /^[+-]?\d+(?:\.\d+)?$/;

        # Map the passed names to the full table name.
        my %tables = (
            service  => 'tbl_service_prices',
            material => 'tbl_material_prices',
            paper    => 'tbl_paper_prices',
            shipping => 'tbl_shipping_prices',
        );
        my @tables = grep { defined $_ }
                     @tables{ $r->param('table') };

        # We must have at least one table to perform the operation on.
        die "No valid tables given.\n" unless @tables;

        # If we're doing straight assignment the value is what was passed,
        # otherwise we're applying the operation to the current value.
        my $value = ($op eq '=') ? $value : "dbl$field $op $value";

        # Update the tables.
        for my $table (@tables) {
            $dbh->do(qq{
                UPDATE $table SET dbl$field = $value WHERE lnglistindex = ?
            }, undef, $id);

            # Now recalculate the price based on the changed field (we should
            # never store all three but we do so we have to live with it --
            # except for the shipping pricing as that only has the two).
            # TODO: Work this into the above statement.
            $dbh->do(qq{
                UPDATE $table
                SET dblprice = price(dblcost, dblmarkup)
                WHERE lnglistindex = ?
            }, undef, $id) unless $table eq 'tbl_shipping_prices';
        }
    };
    # If we've encountered any errors rollback and inform the user. TODO:
    # Actually send a message back to the pricelist page on what went on
    # instead of just going to server error.
    if ($@) {
        $dbh->rollback;
        return SERVER_ERROR;
    }
    else    {
        $dbh->commit;
        # Now redirect the user back to the price list page they came from.
        $r->headers_out->set(Location => "/admin/pricelist?id=$id" );
        $r->status(HTTP_MOVED_TEMPORARILY);
        return OK;
    }
}

# Save changes to an existing price list.
sub update_pricelist {
    my $r = shift;

    # Simplistic sanity checks.
    my $id = $r->param('id'); $id =~ tr/0-9//cd;
    die "An integer price list ID is required." unless $id;

    # Get the fields from the form.
    my @args = map { $r->param($_) or undef }
               qw  { name description currency };

    my $discount = $r->param('discount') || 0;
       $discount = 0 unless $discount =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/;
    push @args, $discount;

    # Create an interval from the provided month and day.
    {
        my $month   = $r->param('month');
           $month  =~ tr/0-9//cd;
           $month ||= 0;

        my $day     = $r->param('day');
           $day    =~ tr/0-9//cd;
           $day   ||= 0;

        push @args, "$month months $day days";
    }

    # For updating an existing.
    my $update = $dbh->prepare(q{
        UPDATE pricelist
           SET name           = ?,
               description    = ?,
               currency       = ?,
               discount       = ?,
               expire_project = ?::interval
        WHERE id = ?
    });
    $update->execute(@args, $id);
    $dbh->commit;

    return OK;
}

# Copy a price list, including all pricing; service, material, paper,
# shipping, etc.
sub copy_pricelist {
    my $old = shift; # ID to copy.

    # Define the list of tables to operate on.
    my @tables = (
        { name => 'pricelist',
          pk   => 'id',
          override => [name => "-copy_of-$old"],},
        { name => 'tbl_service_prices',
          fk   => 'lnglistindex'                },
        { name => 'tbl_material_prices',
          fk   => 'lnglistindex'                },
        { name => 'tbl_paper_prices',
          fk   => 'lnglistindex'                },
        { name => 'tbl_shipping_prices',
          fk   => 'lnglistindex'                },
    );

    # Copy the equipment.
    my $new = copy($old, \@tables);
    $dbh->commit;

    return $new;
}

# Delete any given list of price lists.
sub delete_pricelist {
    my @ids = @_;

    die "No price list IDs passed" unless scalar @ids;

    # Don't allow them to delete all (or their last) price list.
    die "Can't delete all price lists.\n"
        if @ids >= $dbh->selectrow_array('SELECT count(*) FROM pricelist');

    # Cascading references will take care of all the dependent table's
    # records. The number of deleted records is returned.
    my $placeholders = join ', ', ('?') x scalar @ids;

    my $rc = $dbh->do(qq{
        DELETE FROM pricelist WHERE id IN ($placeholders)
    }, undef, @ids);
    $dbh->commit;

    # Return the number of records effected.
    return $rc;
}

# Reassigns customers from one price list to another. Returns the number of
# customers reassigned.
sub reassign_customers {
    my $from = shift; # Price list ID to remove customer from
    my $to   = shift; # Price list ID to assing customer to
    my @cids = @_;    # Customers to reassign

    my $placeholders = join ', ', ('?') x scalar @cids;

    my $rc = $dbh->do(qq{
        UPDATE tbl_customer
        SET lngpricelist = ?
        WHERE lngpricelist = ?
          AND lngcustomerid IN ($placeholders)
    }, undef, $to, $from, @cids);
    $dbh->commit;

    return $rc;
}


sub service_types {
    my $r = shift;
    my $t = shift;

    # If the user is POSTing update the current service type.
    if ( $r->method eq 'POST' ) {

        # The selected service type.
        my $id = $r->param('type'); $id =~ tr/0-9//cd;
        die "Can not update overs without a valid service type ID."
            unless $id;

        # Establish defaults for overs if they haven't been defined.
        my $overs_setup   = $r->param('overs_setup')   || 0;
        my $overs_running = $r->param('overs_running') || 0;
        my $name = $r->param('name') || "";
        my $description = $r->param('description') || "";
        my $mvmp_mkrdy = $r->param('mpmv_makerdy') || 0.0;

        $dbh->do(q{
            UPDATE tbl_service_types
            SET lngsetupovers = ?,
                dblrunovers   = ?,
                strname = ?,
                strdescription = ?,
                mvmp_makerdy_markup = ?
            WHERE lngindex = ?
        }, undef, $overs_setup, $overs_running, $name, $description, $mvmp_mkrdy, $id);
        $dbh->commit;

        # Redirect the user back to their requested page (so they can
        # refresh). Not the best way to handle this, but how we're doing it
        # for now.
        $r->method('GET');
        $r->headers_out->set(Location => "/admin/service_types?type=$id");
        $r->status(HTTP_MOVED_TEMPORARILY);
        return HTTP_MOVED_TEMPORARILY;
    }

    # The selected service type.
    my $id = $r->param('type'); $id =~ tr/0-9//cd;

    # Get a list of all the service types we can declare overs on.
    my $types = $dbh->selectall_arrayref(q{
        SELECT lngindex AS id, strname AS name
        FROM tbl_service_types
        ORDER BY strname
    }, { Slice => {} });

    # If we've been supplied a service type use it, otherwise choose one the
    # first one as a default and send the user to that page.
    if (not defined $id) {
        # Make sure we don't redirect forever.
        $id = $types->[0]{id} or die "No bindery service types available";

        # Send the user to the selected page.
        $r->headers_out->set(Location => "/admin/service_types?type=$id");
        $r->status(HTTP_MOVED_TEMPORARILY);
        return 302;
    }

    # Get the currently selected service type's basic and overs info.
    my $type = $dbh->selectrow_hashref(q{
        SELECT lngindex       AS id,
               strid          AS ref,
               strname        AS name,
               strdescription AS description,
               lngsetupovers  AS overs_setup,
               to_char(coalesce(dblrunovers, 0), '90.99') AS overs_running,
               mvmp_makerdy_markup as mpmv_makerdy
        FROM tbl_service_types
        WHERE lngindex = ?
    }, undef, $id);

    # Start making the client happy.
    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'admin/service_types.html';

    # Output the template, filling in form variables, and other fun stuff.
    my $f = new HTML::FillInForm;

    binmode STDOUT, ":utf8";
    print $f->fill( fdat => $type, scalarref => \$t->process(
        r => $r,
        title => 'MV MP Over Options',
        types => $types,
    ));

    return OK;
}

# Display the list of all service types that can be sub-typed and gives an
# interface to modify the existing or add new sub-type labels.
sub sub_service_type {
    my ($r, $t) = @_;

    # Get all the sub-service types and service types they belong to.
    my $sth = $dbh->prepare(q{
        SELECT t.lngindex AS type_id, t.strname AS type_name,
               s.id, s.name, s.description
        FROM tbl_service_types t
             LEFT JOIN sub_service_type s
             ON (t.lngindex = s.service_type)
        WHERE t.ysnsubtype = TRUE
        ORDER BY 2, 1, 4
    });
    $sth->execute;

    my @service_types;
    while (my $rec = $sth->fetchrow_hashref) {
        # Add the current service type if it's new.
        if (!@service_types || $service_types[-1]{id} != $rec->{type_id}) {
            push @service_types, { 
                id        => $rec->{type_id}, 
                name      => $rec->{type_name}, 
                sub_types => [] 
            };
        }
        
        # Add the sub-service type label to it's service type's list.
        push @{ $service_types[-1]{sub_types} }, \%$rec if $rec->{id}
    }
    
    # Output the response.
    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'admin/sub_service_type.html';

    print $t->process(
        r => Apache2::RequestUtil->request,
        title         => 'Sub-Service Types',
        service_types => \@service_types,
    );

    return OK;
}

sub update_sub_service_type {
    my ($r, $t) = @_;

    # Prepared statements.
    my $insert = $dbh->prepare(q{
        INSERT INTO sub_service_type (service_type, name, description) 
        VALUES (?, ?, ?)
    });
    my $update = $dbh->prepare(q{
        UPDATE sub_service_type SET name = ?, description = ? WHERE id = ?
    });
    my $delete = $dbh->prepare(q{
        DELETE FROM sub_service_type WHERE id = ?
    });

    # Process the the form information. TODO - Error checking of any kind.
    for ($r->param) {
        next unless /^name-/;

        # Form fields are in the format sub_type-$field-$type-$id-n.
        my ($type, $id) = (split /-/)[1,2]; 

        my $name = $r->param($_);
        
        s/name/description/;
        my $descr = $r->param($_);

        # An ID of 0 is used for new entries, existing ID should be updated,
        # and a line with and ID but without a name gets deleted.
        if    ( $id && $name) { $update->execute($name, $descr, $id)   }
        elsif (!$id && $name) { $insert->execute($type, $name, $descr) }
        else                  { $delete->execute($id)                  }
    }

    $dbh->commit;

    # Direct the user back to the editing page.
    $r->headers_out->set(
        Location => "/admin/sub_service_type" );
    $r->status(HTTP_MOVED_TEMPORARILY);
    return OK;
}



# Auditting log display. TODO: Searching of any type.
sub audit_log {
    my $r = shift;
    my $t = shift;

    # Simplistic addition of a WHERE clause for when we're looking up things
    # by page or query. To be expanded upon (in a different manner).
    my (@args, $where) = ();
    if ( $r->param('page') ) {
        $where = 'WHERE page = ?';
        push @args, $r->param('page');

        # Due to the way we currently go into some forms without a full set of
        # parameters, we match query string as a pattern. This isn't a great
        # way of doing it, instead the original page should redirect to a full
        # set of params.
        if ($r->param('query')) {
            $where .= q{ AND ( query ~ (? || '[^0-9]') OR query = ? ) };
            push @args, $r->param('query'), $r->param('query');
        }
    }

    # Get the audit log along with the user information.
    my $sth = $dbh->prepare(qq{
        SELECT u.strfirstname AS proname,
               u.strlastname  AS surname,
               a.*
        FROM audit_log a
        LEFT JOIN tbl_customer_users u ON (u.lnguserid = a."user")
        $where
        ORDER BY date DESC, page, "user", ip, hits DESC, query
    });

    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'admin/audit_log.html';

    print $t->process(
        title => 'Audit Log',
        log => $dbh->selectall_arrayref($sth, {Slice=>{}}, @args),
    );

    return OK;
}


#
# These should both go in an equipment module/object.
#

# Given an equipment id, return a hash of basic equipment attributes.
sub attributes {
    my $eid = shift;

    return $dbh->selectrow_hashref(q{
        SELECT e.lngindex       AS eid,
               e.strid          AS id,
               e.strname        AS name,
               e.strdescription AS description,
               t.lngindex       AS type_id,
               t.strid          AS type,
               e.strcategory    AS category,
               e.strsupplier    AS supplier,
               e.comp_price     AS comp_price
        FROM tbl_equipment e, tbl_equipment_type t
        WHERE e.strtype = t.strid
          AND e.lngindex = ?
    }, undef, $eid);
}

# Given an equipment type, reserve a unique id and return a set of default
# attributes for the new equipment.
sub create {
    my $type = shift;

    return $dbh->selectrow_hashref(q{
        SELECT nextval('equipment_index_seq') AS eid,
               lngindex AS type_id,
               strid    AS type
        FROM tbl_equipment_type
        WHERE lngindex = ?
    }, undef, $type);
}


# Delete any given list of equipment.
sub delete_equipment {
    my @eids = @_;

    die "No equipment IDs passed" unless scalar @eids;

    # We should consider asserting the passed arguments are all positvie
    # integers.

    # Before the material's associated with a specific piece of equipment get
    # deleted, we want to see if there are any generic pricing -- not
    # associated with a specific piece of equipment (this should be supplier
    # but isn't) -- and promote our associated pricing to generic pricing if
    # there isn't.

    my $placeholders = join ', ', ('?') x scalar @eids;

    # Cascading references will take care of all the dependent table's
    # records. The number of deleted records is returned.
    my $rc = $dbh->do(qq{
        DELETE FROM tbl_equipment
        WHERE lngindex IN ($placeholders)
    }, undef, @eids);
    $dbh->commit;

    # Return the number of records effected.
    return $rc;
}

# Create a copy of any given piece of equipment including it's specs and
# pricing.
sub copy_equipment {
    my $old = shift; # ID to copy.

    # Define the list of tables to operate on.
    my @tables = (
        { name => 'tbl_equipment',
          pk   => 'lngindex',
          override => [strid => "-copy_of-$old"]   },
        { name => 'tbl_equipment_specifications',
          pk   => 'lngindex',
          fk   => 'lngequipmentindex'              },
        { name => 'service_type_equipment',
          fk   => 'equipment'                      },
        { name => 'tbl_service_prices',
          fk   => 'lngequipmentindex'              },
        { name => 'tbl_material_prices',
          fk   => 'lngequipmentindex'              },
    );

    # Copy the equipment.
    my $new = copy($old, \@tables);
    $dbh->commit;

    return $new;
}

# Create a copy using the defined set of tables.
sub copy {
    my $old = shift; # ID to copy from.
    my $new;         # ID to copy to.

    # In the intersts of forwards compatibility, we'll use the DBI metadata
    # functions to define our queries. These are defined in an array
    # consisting of hashes detailing the name of the table, the primary key
    # (to not copy), and the foreign key field (to copy the new id to).
    my $tables = shift;

    for my $t (@{ $tables }) {
        # Set the array interpolator to a comma.
        local $" = ', ';

        # Properly escape the identifiers.
        my ($table, $pk, $fk) =
            map { $dbh->quote_identifier($_) } @$t{qw(name pk fk)};

        # Query for all the field in the current table.
        my @fields = @{ $dbh->selectcol_arrayref(
            $dbh->column_info(undef, undef, $t->{name}, undef),
            { Columns => [4] }
        )};

        # Limit above list to only those we need to copy.
        @fields = grep { not /^($pk|$fk)$/ }
                  map  { $dbh->quote_identifier($_) }
                       @fields;

        # Unless a foreign key field has been defined, we're processing the
        # primary table so need to get it's last insert id for the dependents.
        unless ( defined $t->{fk} ) {
            my @insert = @fields;

            # If we're working with the primary table there may be other
            # unique fields or sets of fields (natural keys). Current a very
            # very simple override is provided.
            if ( exists $t->{override} ) {
                my ($n, $v) = @{ $t->{override} };
                @insert = map {$_ eq qq|"$n"| ? $_.'||'.$dbh->quote($v) : $_ }
                              @fields;
            }

            $dbh->do(qq{ INSERT INTO $table (@fields)
                         SELECT @insert
                         FROM $table
                         WHERE $pk = $old });
            $new = $dbh->last_insert_id(undef, undef, $t->{name}, $t->{pk});

            # We commonly have installations with old drivers. Remind
            # deployers to check for this.
            die "last_insert_id() is undefined, perhaps DBD::Pg isn't updated?"
                unless defined $new;
        }
        else {
            $dbh->do(qq{ INSERT INTO $table (@fields, $fk)
                         SELECT @fields, $new
                         FROM $table
                         WHERE $fk = $old }); }
    }

    return $new;
}


# A hash of valid units (id/name pairs) is returned for the given service. If
# a boolean range unit is provided.
sub service_unit {
    my $service = shift;
    my $ranged  = shift || 0;

    my $sth = $dbh->prepare_cached(q{
        SELECT u.id, u.name
        FROM unit u, service_unit su
        WHERE u.id = su.unit
          AND su.service = ?
          AND su.ranged  = ?
    });
    # Rework this.
    return $dbh->selectall_arrayref($sth, { Slice => {} }, $service, $ranged);
}

# THE FOLLOWING DON'T BELONG IN THIS MODULE. MOVE THEM WHEN POSSIBLE.

# Given a table, condition, and field/value pairs creates a properly quoted
# and placeholdered (a new verb?) UPDATE statement and execute it.
sub update {
    my $table     = shift; # The table name to operate on (may contain schema)
    my $condition = shift; # A filter (WHERE) condition
    my %data      = @_;    # Field and value pairs

    # Identifiers (schema, table, fields, etc.) are lowercased before they're
    # quoted as some section of the code use mixed case, relying on Pg's case
    # folding of unquoted identifiers. These section should be revised
    # whenever possible.
    my $sql = sprintf "UPDATE %s SET %s",
        $dbh->quote_identifier( lc( $table ) ),
        join ', ', map {$dbh->quote_identifier(lc($_)) . ' = ?'} keys %data
    ;
    # If there's a condition sent include it in the statement.
    $sql .= " WHERE $condition " if defined $condition and $condition ne '';

    my $sth = $dbh->prepare($sql);

    # Change any string NULLs to undef as currently DBD::Pg can't determine
    # proper quoting for them on numeric types.
    for my $k (keys %data) { $data{$k} = undef if $data{$k} eq 'NULL'; }

    # Send the values.
    $sth->execute( values %data );

    # We should think about returning the number of records effected.
    return;
}

# Sets up merchants.
sub merchants {
    my ($r, $t) = @_;

    my $current_merchant = {};
    my $id = $r->param('id') || 0;

    if (defined $r->param('Action') && $r->param('Action') eq 'Save') {
        if ($id) {
            my $sth = $dbh->prepare(q{
                UPDATE
                    payment_merchants
                SET
                    name           = ?,
                    module         = ?,
                    account_number = ?,
                    password 	   = ?
                WHERE
                    id             = ?
            });
            
            $sth->execute(
                $r->param('name'),           $r->param('module'),
                $r->param('account_number'), $r->param('password'),
		$id
            );

            $dbh->do(q{
                UPDATE
                    pricelist
                SET
                    merchant_id = NULL
                WHERE
                    merchant_id = ?
                }, undef, $id
            );
        }
        else {
            ($id) = $dbh->selectrow_array(
                "SELECT nextval('merchant_id_seq')"
            );

            $dbh->do(q{
                INSERT INTO payment_merchants
                    (id, name, module, account_number, password)
                VALUES
                    (?, ?, ?, ?, ?)
                }, undef, $id, $r->param('name'), $r->param('module'),
                $r->param('account_number'), $r->param('password')
            );
        }

        my $sth = $dbh->prepare(q{
            UPDATE
                pricelist
            SET
                merchant_id = ?
            WHERE
                id = ?
        });

        $sth->execute($id, $_) for $r->param('pricelists');

    }

    if ($r->param('d')) {
        $dbh->do(
            "DELETE FROM payment_merchants WHERE id = ?",
            undef, $r->param('d')
        );
    }

    $dbh->commit();

    if ($id) {
        $current_merchant = $dbh->selectrow_hashref(q{
            SELECT
                id, name, module, account_number, password
            FROM
                payment_merchants
            WHERE
                id = ?
            ORDER BY
                name
            }, undef, $id
        );
    }

    my $merchants = $dbh->selectall_arrayref(q{
        SELECT
            id, name, module, account_number, password
        FROM
            payment_merchants
        ORDER BY
            id
        }, { Slice => {} }
    );

    map { $_->{pricelist} = get_pricelists($dbh, $_->{id}); $_ }
       @{ $merchants };

    my $pricelists = $dbh->selectall_arrayref(q{
        SELECT
            id, name
        FROM
            pricelist
        ORDER BY
            id
        }, { Slice => {} }
    );

    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'admin/merchants.html';

    my $merchant_check = $dbh->prepare_cached(q{
        SELECT
            COUNT(*)
        FROM
            pricelist
        WHERE
            merchant_id = ?
        AND
            id = ?
    });

    $Petal::Hash::MODIFIERS->{'in_list:'} = sub {
        my ($hash, $args) = @_;

        my ($pid, $mid) = map { $hash->fetch($_) } split /\s+/, $args;

        return $dbh->selectrow_array($merchant_check, undef, $mid, $pid)
             ? 'selected'
             : undef;
    };

    print $t->process(
        title            => 'Credit Card Merchants',
        r                => $r,
        merchants        => $merchants,
        modules          => [ get_modules('Business::OnlinePayment') ],
        current_merchant => $current_merchant,
        pricelists       => $pricelists,

        # Petal complains if we give it undef instead of just treating it as
        # a zero in a conditional..
        display_fields   => $id > 0 || $r->param('new') ? 1 : 0,
    );

    return OK;
}

sub get_pricelists {
    my ($dbh, $merchant_id) = @_;

    my @pricelists = @{ $dbh->selectcol_arrayref(q{
        SELECT
            name
        FROM
            pricelist
        WHERE
            merchant_id = ?
        }, undef, $merchant_id
    ) };

    return scalar @pricelists ? join(q{, }, @pricelists) : '(none)';
}

# package PQS::Admin::Service;

1; 
