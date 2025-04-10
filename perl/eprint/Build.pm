package eprint::Build;
use strict;
use warnings;

use Apache2::Const qw(:common :http);
use Apache2::Log       ();
use Apache2::Request   ();
use Data::Dumper;

use PQS::DB           ();
use PQS::Constants;
use PQS::Error;
use PQS::Object::project;
use session;

require misc;
require eprint::login;
require eprint::project;

require openprint;

use vars qw( $r %variable %session %param %config $log $dbh $starttime );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;


# Locations of pages of interest.
use constant SERVICE_PAGE_BASE   => '/service/';
use constant PROJECT_VIEW_PAGE   => '/main/proj/view.html';
use constant NOTIFICATION_PAGE   => '/main/proj/project_notification.html';
use constant ORDER_PAGE          => '/main/order/order_submit.html';
use constant QUOTE_PAGE          => '/main/quote/quote_submit.html';

sub cleanup {
  if ( $r->connection->aborted( ) ) {
    $log->debug('Was aborted');
  } elsif ( DEBUG ) {
    $log->debug('cleanup');
  } # end if
  %openprint::variable = ();
  %openprint::param = ();
  if ( $dbh ) {
    $session{lastupdated} = time;
    untie %session;
    if ( ! $dbh->{AutoCommit} ) {
      $log->error('Uncommited transaction');
    } elsif ( DEBUG ) {
      $log->debug('Finished cleanup');
    } # end if
    $dbh->disconnect();
  } else {
    $log->debug('No dbh at cleanup');
  } # end if
} # end sub cleanup

# The build project handler calculates and manages services in the project.
# It's not a page but a redirect dispatch that sends the user to either an
# uncalculated service they need to modify or the project view page in the
# case of an error or the project being complete.
sub handler {
    $r        = Apache2::Request->new(shift);
    my $variable = {};

    # Process the request params.
    $r->parse;

    $dbh = PQS::DB->connect($r);
    session::r($r);
    session::log($r->log);
    $log = $r->log;


    # If the customer isn't valid and logged in, they can't use us.
    my $cookie = misc::get_cookie();
    return FORBIDDEN if !defined $cookie || $cookie eq '';

    session::dbh($dbh);
    openprint::configuration::init( $r->dir_config() );
    openprint::session_init();
    $r->push_handlers(PerlCleanupHandler => \&cleanup);

    my $customer_id = eprint::login::get_login_info( # Populates $variable
        $log, $dbh, $cookie, $variable, 'C'
    );

    $dbh->disconnect and return FORBIDDEN unless $customer_id;
    
    # Project exists and the user is allowed to access it?
    my $pid = $r->param('pid'); 
       $pid =~ tr/0-9//cd;

    my $allowed = eprint::project::project_allowed($dbh, $pid, $variable);

    $dbh->disconnect and return NOT_FOUND unless $pid && defined $allowed;
    $dbh->disconnect and return FORBIDDEN unless $allowed;

    # The starting level can be overriden for recalculates
    my $level = $r->param('level'); 
       $level =~ tr/0-9//cd if defined $level;

    # Start building the project.
    my $page = eval { build($r->log, $dbh, $pid, $variable, $level) };
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

map {
	print STDERR "HAVE PARAM  $_ =>".$r->param($_)." \n";
} $r->param();

    # If build returned a service page go to it, otherwise go directly to an
    # order (if that flag was set and we calculated correctly) or the project
    # view .
	my ($cto, $ctq) = $dbh->selectrow_array(q{ SELECT create_to_order, create_to_quote FROM tbl_projects WHERE lngprojectindex = ?  }, undef, $pid);

	# If our quote is complete then we no longer need to process it.
	$ctq = 0 if $ctq && $dbh->selectrow_array(q{
		SELECT q.lngquoteid FROM tbl_quotes q, tbl_quote_details qd 
		WHERE strstatus = 'Complete' AND q.lngquoteid = qd.lngquoteid
		AND qd.lngprojectindex = ?
	}, undef, $pid);

	# If our order is complete then we no longer need to process it.
	$cto = 0 if $cto && $dbh->selectrow_array(q{
		SELECT o.lngorderid FROM tbl_orders o, tbl_order_contents oc 
		WHERE strstatus = 'Complete' AND o.lngorderid = oc.lngorderid
		AND oc.lngprojectindex = ?
	}, undef, $pid);

  #print STDERR "********HAVE CTO: $cto CTQ: $ctq *********\n";
  my $to_order = ( $r->param('create_to_order') || $cto )  && eprint::project::project_state($dbh, $pid) eq 'Unordered';

	my $mail_page = $dbh->selectrow_array(q{ SELECT mail_type FROM tbl_projects WHERE lngprojectindex = ?  }, undef, $pid );

  #print STDERR "VARIABLE: ", Dumper( $mail_page, $to_order, $page, $variable);
    
    $page = $page eq 'notification' ? NOTIFICATION_PAGE . "?pid=$pid"
		  : $page     ? SERVICE_PAGE_BASE . $page 
          : $to_order ? ORDER_PAGE . "?btnFunction=Process Order;ProjectIndex=$pid"
          : $ctq 	  ? QUOTE_PAGE . "?btnFunction=Process Quote;ProjectIndex=$pid"
          :             PROJECT_VIEW_PAGE . "?pid=$pid";

	my $cpid = $dbh->selectrow_array(q{SELECT copy_pid FROM tbl_projects WHERE lngprojectindex = ?}, undef, $pid);

if ( $cpid ) {
  print STDERR "HAVE COPY PID: $cpid FROM PROJECT: $pid \n";
  if ( $cpid == 22317 ) {
    $page = '/site_specific/customers/products/local/menu_english.html';
    eprint::order::add_project_to_order( $r->log, $dbh, $cookie, $variable, $pid);

  } elsif ( $cpid == 22318 ) {
    $page = '/site_specific/customers/products/local/menu_english.html';
    eprint::order::add_project_to_order( $r->log, $dbh, $cookie, $variable, $pid);

  } elsif ( $cpid == 22319 ) {
    $page = '/site_specific/customers/products/local/menu_english.html';
    eprint::order::add_project_to_order( $r->log, $dbh, $cookie, $variable, $pid);

  } elsif ( $cpid == 22315 ) {
    $page = '/site_specific/customers/products/local/menu_french.html';
    eprint::order::add_project_to_order( $r->log, $dbh, $cookie, $variable, $pid);

  } elsif ( $cpid == 22322 ) {
    $page = '/site_specific/customers/products/local/menu_bi.html';
    eprint::order::add_project_to_order( $r->log, $dbh, $cookie, $variable, $pid);
  }
}

    $dbh->commit; # Save our changes.
    $dbh->disconnect;

    if (DEBUG && 0) {
        $r->content_type('text/html');
        $r->print(qq{ <a href="$page">$page</a> } );
    }
    else {
      print STDERR "Location $page " .Apache2::Const::HTTP_SEE_OTHER."\n";
        $r->headers_out->set(Location => $page);
        $r->status(Apache2::Const::HTTP_SEE_OTHER);
        return OK;
    }
}


use eprint::project       qw( get_type      check_for_service      is_complete
                              get_template  template_service_types );
use eprint::print_project qw(insert_service remove_service);
use eprint::service       qw(:all);

# The posisition where non-dependent services will be calculated.
use constant NON_DEPENDENT_LEVEL => 10;

sub build {
  my ($log, $dbh, $pid, $variable, $start) = @_;

  # Get the service types suggested for the project type and template, we'll check their needs as the service type comes up.
  my %template = template_service_types($log, $dbh, $pid);

  print STDERR "BUILD TEMPLATE", Dumper(\%template);

  # Find our current place in the dependency levels.
  my $level = current_level($dbh, $pid) || 0;
  print STDERR "BUILD LEVEL $level\n";
  # We can override our start level to lower than the current (recalc).
  if (defined $start && ($start < $level || $start == 0)) {
    $level = $start;
    print STDERR "reset\n";
    reset_to_level($log, $dbh, $pid, $level);
  }

  # Process the service types at or above the current level.
  my $sth = $dbh->prepare(q{
    SELECT lngindex    AS id,     strid       AS type,
    strname     AS name,   strcategory AS category,
    strmodule   AS module, lngdep      AS level,
    strurl      AS page,
    CASE WHEN lngdep IS NULL THEN } . NON_DEPENDENT_LEVEL . q{
    ELSE lngdep END AS sorted
    FROM tbl_service_types
    WHERE strmodule IS NOT NULL
    AND ( CASE WHEN lngdep IS NULL THEN } . NON_DEPENDENT_LEVEL . q{
    ELSE lngdep 
    END >= ? )
    ORDER BY sorted, lngdep
    });
  $sth->execute($level);

  my $unfinished; # Keep track of the first unfinished service.

  SERVICE_TYPE:
  while (my $service = $sth->fetchrow_hashref) {
    my $type     = $service->{type};
    print STDERR "SERVICE $type\n";

    # If we have any unfinished (uncalc, error) services we can't advance
    # to the next dependency level (non-dependent are immune).
    last SERVICE_TYPE if defined($level) && defined($service->{level}) && $unfinished && ($service->{level} > $level);

    $level = $service->{level} if $service->{level};

    # Load the service module and see if it's needed in the project.
    eval { 
      $service = load_service_type($service);
      $service->{is_needed} = needed($log, $dbh, $pid, $service, $template{$type});
      print STDERR "$$service{type} is needed $$service{is_needed}\n";
    };
    if ($@) {
      # If we can't properly process the module we'll mark the service # in an error state (inserting it if it's not already present.
      my @sids = check_for_service($log, $dbh, $pid, $type) || insert_service($log, $dbh, $pid, $type, {
          user_requested => 0,
          need_level     => NEEDED,
        });

      set_status($log, $dbh, $pid, 'error', @sids);

      if (DEBUG) { print STDERR $@ }
      else       { warn "Inserting $service->{type} in error state for $pid ", $@ }

      if   ($service->{level}) { last SERVICE_TYPE }
      else                     { next SERVICE_TYPE } # No dependencies.
    }
    # Add a service if we're needed and none exist.
    elsif ($service->{is_needed} && !service_exists($dbh, $pid, $type)) {
      my $sid = insert_service($log, $dbh, $pid, $type, { 
          user_requested => 0,
          need_level     => $service->{is_needed},
        });

      # Override service defaults with template ones if they exist.
      insert_service_specs( $log, $dbh, $pid, $sid, %{ $template{$type}{specs} }) if exists $template{$type}{specs};
    }

    SERVICE:
    while (my $sid = next_service($log, $dbh, $pid, $type)) { 

      # TODO Should we skip the service if it's on the starting level # and already calculated (or if it's non-dependent)? ie. no need # to recalculate it.

      # Remove the service if it's no longer needed in the project (and # isn't user requested).
      if (!$service->{is_needed} && !user_requested($dbh, $sid)) {
        if (!$dbh->do(q{ DELETE FROM tbl_project_contents WHERE lngserviceindex = ?  AND NOT ysnuserrequested }, undef, $sid)) {
          print STDERR "Error ".$dbh->errstr()."\n";
        }

        next SERVICE;
      }

      # Get the specs and price the service. FIX
      my $status = process($log, $dbh, $variable, $pid, $sid, $service);

      # Track the first unfinished service we find.
      if ($status eq 'uncalculated') {
        $unfinished = { sid => $sid, type => $service->{type} };

        last SERVICE_TYPE;
      }
      elsif ($status eq 'error' && $service->{level}) {
        # Set rest of services to a consistant state.
        recalc_dependencies($log, $dbh, $pid, $sid);

        undef $unfinished; # Clear our uncalculated tracking.
        last SERVICE_TYPE;
      }
    }
  }
  $sth->finish;
  print STDERR "GO BUILD \n";
  # If we have an uncalculated service, handle the dependent services then
  # send the user to it's page to supply the information it's missing.
  if ($unfinished) {
    recalc_dependencies($log, $dbh, $pid, $unfinished->{sid});

    $dbh->do(q{ UPDATE tbl_projects SET strstatus = 'uncalculated' WHERE lngprojectindex = ?  }, undef, $pid);
    my $prod = $dbh->selectrow_array(q{ SELECT product FROM tbl_projects WHERE lngprojectindex = ?  }, undef, $pid); 

    if ($prod && ($unfinished->{type} ne 'Shipping')) {
      return "notification" unless $variable->{user_id} == 2;
    } else {
      return "$unfinished->{type}?pid=$pid;sid=$unfinished->{sid}";
    }

    return "$unfinished->{type}?pid=$pid;sid=$unfinished->{sid}";
  } else {
    # Change the project status if we've just completed it.
    $dbh->do(q{ UPDATE tbl_projects SET strstatus = 'Unordered' WHERE lngprojectindex = ? AND strStatus = 'uncalculated' }, undef, $pid) if is_complete($log, $dbh, $pid);
  }


  my $p = new PQS::Object::project($pid);
  $p->update_status; 

  return; # Go to the default location
}

# See if the service exists in the project. NOTE: check_for_service() isn't
# used as it's slower due to the sort.
sub service_exists {
    my ($dbh, $pid, $service_type) = @_;
    my $bool;

    my $sth = $dbh->prepare_cached(q{
        SELECT true 
        FROM tbl_project_contents
        WHERE lngprojectindex = ?
          AND strservicetype = ?
    });
    $sth->execute($pid, $service_type);
    $sth->bind_col(1, \$bool);
    $sth->fetch;
    $sth->finish;

    return $bool;
}

# Select the level of the first non-calculated service in the project.
sub current_level {
    my ($dbh, $pid) = @_;

    # We handle anything outside of the dependency level
    my $nondep = NON_DEPENDENT_LEVEL;

    # The first uncalculated service if any.
    my $first = $dbh->selectrow_array(qq{
        SELECT CASE WHEN t.lngdep IS NULL THEN $nondep ELSE t.lngdep END
        FROM tbl_service_types t, tbl_project_contents p
        WHERE t.strmodule IS NOT NULL
           AND t.strid = p.strservicetype
           AND p.strstatus = 'uncalculated'
           AND p.lngprojectindex = ?
        ORDER BY 1, t.lngdep
        LIMIT 1
    }, undef, $pid);

    # Start at last level that has a calculated service (if no uncalculated).
    my $last = $dbh->selectrow_array(qq{
        SELECT CASE WHEN t.lngdep IS NULL THEN $nondep ELSE t.lngdep END
        FROM tbl_service_types t, tbl_project_contents p
        WHERE t.strmodule IS NOT NULL
           AND t.strid = p.strservicetype
           AND p.strstatus = 'calculated'
           AND p.lngprojectindex = ?
        ORDER BY 1 DESC, t.lngdep
        LIMIT 1
    }, undef, $pid) || 0;

    return defined $first && $first < $last ? $first : $last;
}

# Reset the project to a given level.
sub reset_to_level {
    my ($log, $dbh, $pid, $level) = @_;

    # If we're completely recalculating the project we'll reset it's "expire
    # date" (very kludgy) to the current date plus the default time allowed by
    # the customer's pricelist.
    if ($level == 0) {
        $dbh->do(q{
            UPDATE tbl_projects
            SET dtmexpiredate = CURRENT_DATE + (
                SELECT expire_project
                FROM pricelist p, tbl_customer c
                WHERE p.id = c.lngpricelist
                  AND c.lngcustomerid = tbl_projects.lngcustomerid )
            WHERE lngprojectindex = ?
        }, undef, $pid);
    }

    # Note: we should be safe with setting all to uncalculated as the
    # dependency levels will all be correctly set before we exit the
    # transaction.
    $dbh->do(q{
        UPDATE tbl_project_contents 
        SET strstatus = 'uncalculated'
        FROM tbl_service_types
        WHERE lngprojectindex = ?
          AND lngdep >= ?
          AND strservicetype = strid
    }, undef, $pid, $level);

    return;
}

# Some services are essential for the completion of a project, even if they
# were not automatically added or user selected. Eg. Kiss Cutting for a
# certain type of label template (template based), or cutting may be necessary
# if the selected press sheets need to be cut down to fit the press.
sub needed {
    my ($log, $dbh, $pid, $service, $template) = @_;

    # Template need is determined by the project type and template
    # specifications.
    my $need = $template->{required} || NOT_NEEDED;

    # If we're already needed (highest state) that's all there is to it.
    return $need if $need == NEEDED;
       
    # Does the service think it's needed?
    my $func      = $service->{can}->('necessary');
    my $necessary = $func->($log, $dbh, $pid, $service->{type}) 
        if defined $func;

    # TODO: Eventually these functions should return a need
    # state but  for now we use it as a boolean.
    $necessary = $necessary ? NEEDED : NOT_NEEDED;

    return ($necessary > $need) ? $necessary : $need; # Highest need wins.
}

# Is the given service user requested?
sub user_requested {
    my ($dbh, $sid) = @_;

    return $dbh->selectrow_array(q{
        SELECT ysnuserrequested 
        FROM tbl_project_contents 
        WHERE lngserviceindex = ?
    }, undef, $sid);
}

# Get the next service of the given type that needs attention. Note: Used instead
# of checking once as 
sub next_service {
    my ($log, $dbh, $pid, $type) = @_;

    # my @sids = grep { get_status($log, $dbh, $_) ne 'calculated' }
    #                 check_for_service($log, $dbh, $pid, $type);
    #
    # return $sids[0];

    my $sth = $dbh->prepare_cached(q{
        SELECT lngserviceindex 
        FROM tbl_project_contents
        WHERE strstatus <> 'calculated'
          AND lngprojectindex = ?
          AND strservicetype  = ?
        ORDER BY dtmlastmodified DESC, lngserviceindex DESC
        LIMIT 1
    });

    return $dbh->selectrow_array($sth, undef, $pid, $type);
}


# Get the specs and price the given service.
sub process {
    my ($log, $dbh, $variable, $pid, $sid, $service) = @_;

    my $status = eval {
        set_need($dbh, $sid, $service->{is_needed}); # Set (new) need level.

        my $form  = get_specs($dbh, $pid, $sid, $service, 1); # User defined
        my $specs = get_specs($dbh, $pid, $sid, $service);    # All specs
        print STDERR "process $sid ".Data::Dumper::Dumper($specs)."\n";

        # Price the service.
        my $state = price($log, $dbh, $variable, $pid, $sid, $service, $specs, 1);

        # Save the specifications and pricing.
        save($log, $dbh, $pid, $sid, $service, $form, $specs) 
            if $state eq 'calculated';

        $state;
    };
    if ($@) {
        $dbh->rollback;
        
        if (DEBUG) {
            set_status($log, $dbh, $pid, 'error', $sid);
            print STDERR $@;
        }
        
        warn "Failed to process $service->{type} ($sid)";
        
        $status = 'error';
    }
    elsif ($status eq 'uncalculated' && !$service->{page}) {
        # If the service doesn't have a page the user can't fix an
        # uncalculated service, so it's an error.
        warn "$service->{type} ($sid) without page won't calculate.";

        $status = 'error';
    }
    
    set_status($log, $dbh, $pid, $status, $sid); # Mark the service.
        
    # If we're debugging rethrow the error. 
    if ($@ && DEBUG) {
        recalc_dependencies($log, $dbh, $pid, $sid); # Force consistent state.
        $dbh->commit;
        die $@;
    }

    #$dbh->commit; # Save the service.

    return $status;
}

1;
