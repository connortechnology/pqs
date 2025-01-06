package eprint::Service::Handler;
use strict;
use warnings;
use utf8;

use Apache2::Const qw(:common :http :methods);
use Apache2::Request   ();
use Apache2::Log       ();

use JSON::XS 2.0     qw(encode_json);
use HTML::FillInForm ();

use PQS::DB ();
use PQS::Constants;
use PQS::Error;

use eprint::service qw(:status :calc);
use eprint::project qw(:state project_info);
use ssi             ();
use session;

require configuration;
require misc;
require eprint::login;
require eprint::banner;
require openprint;

use vars qw( $r %variable %session %param %config $log $dbh $starttime );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;


use constant SERVICE_PAGE_PATH  => '/main/proj';
use constant PROJECT_BUILD_PAGE => '/build';
use constant PROJECT_VIEW_PAGE  => '/main/proj/proj_view.html';

sub handler {
    $r = Apache2::Request->new(shift,
        POST_MAX        => 8096,
        DISABLE_UPLOADS => 1,
    );
    my $variable = {};

    # Process the request params.
    $r->parse;

    session::r($r);
    session::log($r->log);
    $log = $r->log;

    if (!( $r->method_number == M_GET || $r->method_number == M_POST)) {
      print STDERR "Invalid method ".$r->method_number." get:".M_GET.' post:'.M_POST."\n";
      return HTTP_METHOD_NOT_ALLOWED;
    }

    # If the customer isn't valid and logged in, they can't use us.
    my $cookie = misc::get_cookie();
    if (!defined $cookie || $cookie eq '') {
      $r->headers_out->set(Location => '/main/account/account_login.html');
      $r->status(Apache2::Const::REDIRECT); #302
      return Apache2::Const::OK;
    }

    my $dbh = PQS::DB->connect($r);  # TODO Use RO session for GETs
    session::dbh($dbh);

    #%openprint::param = %{$variable->{param}} = map {$_ => $r->param($_)} $r->param();
    # Here we copy the param data into a hash that is sligthly more useful to use.  Wish we didn't have to do this.
    foreach my $key ( $r->param ) {

      my @values = $r->param($key);
      $key = substr($key,0,-2) if (substr($key, -2, 2) eq '[]');
      if ( @values > 1 ) {
        $param{$key} = \@values;
        #$log->debug("Parameter $key is ARRAY(" . join(',',@{$param{$key}}) . ')' );
      } else {
        my $x = $values[0];
        if (utf8::decode($x)) {
          $param{$key} = $x;
        } else {
          $param{$key} = $values[0];
        }
        #$log->debug("Parameter $key is (" . $param{$key} . ") ref: " . ref $param{$key} );
      } # end if
    } # end foreach
    foreach my $key ( sort keys %param ) {
      if ( ref $param{$key} eq 'ARRAY' ) {
        $log->debug('Parameter '.$key.' is ARRAY(' . join(',', @{$param{$key}}) . ')');
      } else {
        $log->debug('Parameter '.$key.' is ('.$param{$key}.')');# . (utf8::is_utf8($param{$key})||0) );
        #$log->debug("Parameter $key is (" . $param{$key} . ")" . (utf8::is_utf8($param{$key})||0) );
      } # end if
    } # end foreach


    my $customer_id = eprint::login::get_login_info( # Populates $variable
        $r->log, $dbh, $cookie, $variable, 'C'
    );
    if (!$customer_id) {
      $r->headers_out->set(Location => '/main/account/account_login.html');
      $r->status(Apache2::Const::REDIRECT); #302
      $dbh->disconnect;
      return Apache2::Const::OK;
    }

    # Determine if we're a known service for processing.
    my $service = uri_to_service($r, $dbh);

    $dbh->disconnect and return NOT_FOUND unless $service;

	#map { print STDERR "HAVE PARAM: $_ = " . $r->param($_) . " \n"; } $r->param();

    my $pid = $r->param('pid') or die "Invalid PID";
    my $sid = $r->param('sid') or die "Invalid SID";

    # Make sure the service exists in the project.
    unless ($dbh->selectrow_array(q{
                SELECT true 
                FROM tbl_project_contents 
                WHERE lngprojectindex = ?
                  AND lngserviceindex = ?
            }, undef, $pid, $sid))
    {
print STDERR "Service not found for $pid/$sid\n";
if ($dbh->selectrow_array('SELECT true from tbl_projects WHERE lngprojectindex=?', undef, $pid)) {
      $r->headers_out->set(Location => '/main/proj/proj_view.html?pid='.$pid);
      $r->status(Apache2::Const::REDIRECT); #302
      $dbh->disconnect;
      return Apache2::Const::OK;
    }

        $dbh->disconnect;
        return NOT_FOUND;
    }

    # To view/edit this service the user must be allowed to edit the project
    # as a whole and if the project has locked service (fixed price) the
    # service must be in the allowed list (or the user is staff).
    my $allowed = allowed_services($dbh, $pid);

    if (! project_allowed($dbh, $pid, $variable)
        || (    has_locked_services($dbh, $pid) 
             && !exists $allowed->{ $service->{id} } 
             && !$variable->{is_staff} ) )
    {
print STDERR "Forbidden for $pid\n";
        $dbh->disconnect;
        return FORBIDDEN; 
    }
    
    # Generate and send the response.
    eval { response($r, $dbh, $variable, $pid, $sid, $service) };

    # If there's a problem with the request, log the error and optionally send
    # a stacktrace if we're in debugging mode.
    if ($@) {
        my $err = $@;

        $dbh->rollback;
        $dbh->disconnect;
    
        $r->log_error($err);
                
        if (DEBUG) {
            require Error::StackTrace;
            $r->status(SERVER_ERROR);
            $r->content_type('text/html');
            print Error::StackTrace::trace($r, $err);
            return OK;
        }
      
        return SERVER_ERROR;
    }
  
    $dbh->disconnect;

    return OK;
}

# Map the uri to a valid service type, return a hash ref of it's attributes.
sub uri_to_service {
  my ($r, $dbh) = @_;

  # Get the requested service from the URI.
  my $location = $r->location;
  my $service_type  = $r->uri;
  $service_type  =~ s/$location\/?//i;
  $service_type  =~ tr/a-zA-Z0-9_-//cd;

  return undef unless $service_type;

  # Look up the service type.
  my $service = $dbh->selectrow_hashref(q{
    SELECT lngindex    AS id,     strid       AS type,
    strname     AS name,   strcategory AS category,
    strmodule   AS module, lngdep      AS level,
    strurl      AS page
    FROM tbl_service_types
    WHERE strmodule IS NOT NULL
    AND lower(strid) = ?
    }, undef, lc($service_type));

  return undef unless $service->{id};

  return load_service_type($service);
}

# Show the page if we're doing a GET with just PID and SID, return an JSON
# object if we're doing a pricing GET, or save the service if we're POSTing.
sub response {
    my ($r, $dbh, $variable, $pid, $sid, $service) = @_;

    my @params = $r->param;
    
    # Just display the page.
    if (@params <= 2) {
        my $page = show($r, $dbh, $variable, $pid, $sid, $service);

        $dbh->rollback; # Display should never alter DB.

        $r->content_type('text/html');
        print $$page;
    }
    else {
        my $form   = param_hashref($r);
        my $specs  = { %$form };
        my $status = price($r->log, $dbh, $variable, $pid, $sid, $service, $specs);

        # AJAX pricing request.
        if ($r->method_number == M_GET) {
            $dbh->rollback; # GET requests don't save.

            $specs->{status} = $status; # Send client the status

            my $response = encode_json(
                $status eq 'calculated' 
                    ? $specs : 
                    { status => $status, error => $specs->{error} }
            );

            $r->content_type('application/json; charset=utf-8');
            print $response;
        }
        # Form submission (save).
        else {
            # Save the service, set it's state, and continue the project.
            save($r->log, $dbh, $pid, $sid, $service, $form, $specs);
            set_status($r->log, $dbh, $pid, $status, $sid);
            
            recalc_dependencies($r->log, $dbh, $pid, $sid);

            $dbh->commit;

            my $location = $status eq 'calculated' 
                ? PROJECT_BUILD_PAGE : PROJECT_VIEW_PAGE;

			$location .= "?pid=$pid";

			$location = $r->param('Location') if $r->param('Location');

            $r->headers_out->set(Location => "$location");
            $r->status(HTTP_MOVED_TEMPORARILY);
        }
    }
    return;
}

# Build a hash from the passed form elements.
sub param_hashref {
    my ($r) = @_;

    my %args;
    for my $field ($r->param) {
        my @values = $r->param($field);

        $args{$field} = @values == 1 ? $values[0] : \@values;
    }

    return \%args;
}

# Display the service's page.
sub show {
    my ($r, $dbh, $variable, $pid, $sid, $service) = @_;

    # Set standard information for every service page.
    $variable->{pid}     = $pid;
    $variable->{sid}     = $sid;
    $variable->{service} = $service;
    $variable->{project} = project_info($dbh, $pid);

    # Display the banner advert.
    if ( configuration::get_value($r->log, $dbh, 'UsesBanners') ) {
        $variable->{BANNER_AD} = eprint::banner::select_banner(
            $r->log, $dbh, @$variable{qw(cust_id user_id)}
        );
    }
    
    # Display/hide pricing based on customer default.
    $variable->{isServicePricing} = $dbh->selectrow_array(q{
            SELECT ysnpricingservices
            FROM tbl_customer
            WHERE lngcustomerid = ?
        }, undef, $variable->{cust_id});
    
    # Load the specs from the db.
    my $specs = $variable->{spec} = get_specs($dbh, $pid, $sid, $service);

    # If the service has a display() function run it an populate variable with
    # it's return.
    my $display = $service->{can}->('display');
    my $page = $display 
        ? $display->($r->log, $dbh, $service->{type}, $pid, $sid, $specs, $variable)
        : {};
    
    $variable->{$_} = $page->{$_} for keys %$page;

    # Open the template page.
    my $path = $r->document_root . SERVICE_PAGE_PATH;
    
    open my $fh, '<', "$path/$service->{page}" or die "Can't find file: $path/$service->{page} -- $!";
    my $html = do { local $/ = undef; <$fh> };
    close $fh or die "Can't close file: $!";

    use eprint::www;
    eprint::www::word_sub($variable);

    # Create the page from the template.
    $html = ssi::variable_substitution($r, $r->log, $dbh, $html, $variable);

    # Fill in the form with any user specs.
    my $f = HTML::FillInForm->new();
    $html = $f->fill(fdat => $specs, scalarref => \$html);

    return \$html; # Don't copy the large string (yet again).
}

1;
