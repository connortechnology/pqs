package eprint::www;
use strict;
use warnings;
use utf8;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY);
use Apache2::Request   ();
use Apache2::Log       ();
use Apache2::Cookie    ();

use PQS::DB ();
use PQS::Constants;
use PQS::Error;

use ssi qw($gdb);
require sql;
require misc;
require configuration;
use session;
use Data::Dumper;

require openprint;
require eprint::login;
require openprint::configuration;

use vars qw( $r %variable %session %param %config $log $dbh $starttime );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

use constant MAX_REDIRECTS => 20;
use constant DEBUG => 0;

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
    openprint::Object::init_cache();
    if ( ! $dbh->{AutoCommit} ) {
      $log->error('Uncommited transaction');
    } elsif ( DEBUG ) {
      $log->debug('Finished cleanup');
    } # end if
    $dbh->disconnect();
    $gdb->disconnect;
  } else {
    $log->debug('No dbh at cleanup');
  } # end if
  $openprint::User = new openprint::User;
} # end sub cleanup

sub show_params {
  my $r = session::r;
  map {
    print STDERR " HAVE PARAM: $_ = " . $r->param($_) . "\n";
  } $r->param();
}

sub generate_cookie {
  my ( $r, $log, $dbh ) = @_;

  # Get the domain from Apache config or, failing that, the database.
  my ($user, $pass, $host, $port) = $r->headers_in->{'Host'}
  =~ /(?:([^:]+):([^\@]+)\@)?([^\@:]+)(?::(\d+))?/;

  my $domain = 
  $host
  || $r->dir_config('cookiedomain')
  || configuration::get_value($log, $dbh, 'cookiedomain');
 
  #$log->debug("COokie domain: $domain");

  # Generate and set the cookie.
  my $cookie = Apache2::Cookie->new($r,
    -name    => 'SessionID',
    -value   => misc::gen_session_id(), # Ludicrously small.
    -path    => '/',
    -domain  => $domain
  );
  #print STDERR "Cookie $cookie for $domain Host:".$r->headers_in->{'Host'}." cookiedomain: ".$r->dir_config('cookiedomain')."\n";
  $cookie->bake($r);

  # Return the generated session ID.
  return $cookie->value();
}

# Silly little function that works like an enum. Takes a user type and the
# section and returns true if that user type is allowed in the section.
sub user_allowed {
  my ($user, $section) = @_;
  return if ! $user;

  my %allowed = (
    A => [qw(A    )],
    E => [qw(A E  )],
    C => [qw(A E C)],
  );

  return 1 if grep { $user eq $_ } @{ $allowed{$section} };
}

sub handler {
  my $rec = shift if $ENV{MOD_PERL};

  return NOT_FOUND unless -e $rec->filename;
  return FORBIDDEN unless -r $rec->filename;

  $r = Apache2::Request->new($rec);
  $r->parse;

  session::r($r);
  session::log($r->log);
  $log = $r->log;

  if ( $r->header_only ) {
    $log->debug('Browser only wanted header.');
    return OK;
  }
  $r->push_handlers(PerlCleanupHandler => \&cleanup);

  ssi:$gdb 	 = PQS::DB->connect($r, { ReadOnly => 1 });
  $dbh    = PQS::DB->connect($r, { AutoCommit => 1 });

  session::dbh($dbh);
  my $variable = \%variable;
  my $cookie   = misc::get_cookie($r, $r->log, $dbh, $variable);

  $cookie = generate_cookie($r, $r->log, $dbh) unless $cookie;

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
  #show_params();
  openprint::configuration::init( $r->dir_config() );
  openprint::session_init();

  my ($page, $args, $status);

  word_sub($variable);

  eval {
    my $redirects = 0;

    REDIRECTS:
    {
      if ( $variable->{Redirect} ) {
        ($page, $args) = $variable->{Redirect} =~ /^([^?]+)(?:\?(.*))?$/;

        # Set the new arguments and forces the Apache request object to
        # reparse the parameters. -- stupid, I know.
        if (defined $args) {
          $r->args($args);
        }

        $variable->{Redirect} = '';
      } else {
        $page = $r->uri();
      }
$log->debug("Page $page");
      $variable{uri} = $page;
      $status = parse_page( $r, $r->log, $cookie, $dbh, $variable, $page );
      die "Maximum redirects exceeded" if $redirects > MAX_REDIRECTS;
      $redirects++, redo REDIRECTS if $variable->{Redirect};
    }
  };
  if ($@) {
    my $err = $@;

    $r->log->error($err);

    if (DEBUG) {
      require Error::StackTrace;
      $r->status(SERVER_ERROR);
      $r->content_type('text/html');
      print(Error::StackTrace::trace($r, $err));
      return OK;
    }

    return SERVER_ERROR;
  }

  if ( $status != OK and $status != 200 ) {
    $r->status( $status );
    return $status;
  }

  if ( $variable{ExternalRedirect} ) {
    $log->debug("EXTERNAL REDIRECT $variable{ExternalRedirect}");
    foreach my $key ( 'error', 'warning', 'information' ) {
      if ( $variable{$key} ) {
        $session{$key} = $variable{$key};
      } # end if
    } # end foreach
    $r->headers_out->set(Location=>$variable{ExternalRedirect});
    $r->status(Apache2::Const::REDIRECT);
    #$r->send_http_header;
    $log->debug('Redirecting to ' . $variable{ExternalRedirect} );
    return OK;
  } elsif ( $variable->{Download} ) {
    for my $line (@{ $variable->{File_Data} }) {
      print $line;
    }
  } else {
    my $filename = ssi::get_file_path($r, $page);

    my $fh;
    if (!open $fh, '<', $filename ) {
      $r->log->error("Failed opening $page: $!");
      die "Failed to open $filename: $!";
    }

    # read in the data
    my $file_data = do { local $/ = undef; <$fh> };

    close $fh;

    $file_data = ssi::variable_substitution( $r, $r->log, $dbh, $file_data, $variable);

    #print STDERR "CHECK FILL IN FORM \n";
    if ( $variable->{__FillInForm} ) {
      require HTML::FillInForm;
      #print STDERR "HAVE FILL IN FORM \n";
      my $f = new HTML::FillInForm;
      $file_data = $f->fill(scalarref => \$file_data,
        fdat      => $variable->{__FillInForm} );
    }

    # this is where we actually send the page to the client
    if ( $filename =~ /\.html/ ) {
      $r->content_type(q{text/html; charset=utf-8});
    } elsif ( $filename =~ /\.json/ ) {
      $r->content_type(q{text/javascript; charset=utf-8});
    } elsif ( $filename =~ /\.xml/ ) {
      $r->content_type(q{text/xml; charset=utf-8});
    } elsif ( $filename =~ /\.rss/ ) {
      $r->content_type(q{application/rss+xml; charset=utf-8});
    } # end if

    print $file_data;
  }

  return OK;
}

sub word_sub {
  my ($variable) = @_;
  my ($file_data) = @_;

  my %words = (split ',', eprint::Config->get(General => 'word_sub'));

  map { $variable->{'ws_'.$_}  = $words{$_};
    #print STDERR "CHANGE: $_ to $words{$_} \n";
  } keys %words;
  map { $file_data =~ s/$_/$words{$_}/g;
    #print STDERR "CHANGE: $_ to $words{$_} \n";
  } keys %words;
  return $file_data;
}

sub log_request {
  my $r  = session::r;
  my $dbh = session::dbh;

  my $page = shift;
  my $variable = shift;

  my $ip = '';
  my $userid = $variable->{user_id}; 

  my $params;
  map { $params .=  $_ . '=' . $r->param($_) } $r->param(); 

  my $pid = $r->param('pid');
  my $oid = $r->param('order_id');

  $dbh->do(q{INSERT into log (ip, userid, page, params, pid, oid, reqtime)
    values ( ?, ?,?,?,?,?, now() )  
    }, undef, $ip, $userid, $page, $params, $pid, $oid);
}

sub parse_page {
  my ($r, $log, $cookie, $dbh, $variable, $page) = @_;
  my $status = OK;

  #print STDERR "START PARSE PAGE \n\n";
  # The module dispatches by 'section' based on the uri.
  my @path     = grep { $_ } split '/', $page;
  my $filename = pop @path;

  shift @path if $path[0] eq 'site_specific';
  my $first = @path ? shift @path : '';
  my $second = @path ? shift @path : '';

  #print STDERR "HAVE SECTIONS FIRST: $first SECOND: $second \n";
  if ( $first eq 'notification' ) {
    require eprint::notification;
    eprint::notification::handler( $variable, $page );
  }

  unless ($cookie || $variable->{error}) {
    print STDERR "COOKIE: $cookie : ERROR: $variable->{error} \n\n";
    my $error_page = configuration::get_value($r->log, $dbh, 'errorpage');

    $variable->{error}   = 'Restricted Access';
    $variable->{details} = q{Cookie error};
    $variable->{Redirect} = $error_page;
    return OK;
  }

  # The current section we're in.
  $variable->{section} = $first if defined $first;

  my $section = $first eq 'administrator' ? 'A'
  : $first eq 'employee'      ? 'E'
  : $first eq 'main'          ? 'C'
  :                             undef; # General public area


  # USER AUTHENTICATION/AUTHORIZATION
  #
  # While this section is cleaned up it's still the old code that really has
  # no idea of what authentication then authorization is.

  # Unauthenticated users are redirected here.
  if ($filename eq 'login.html') {

    # This page is only available via redirects so we should have a
    # cookie, if we don't error.
    unless (misc::get_cookie($r, $r->log, $dbh, $variable)) {
      my $error_page = configuration::get_value($r->log, $dbh, 'errorpage');

      $variable->{error}   = 'Cookie Missing.';
      $variable->{details} = q{
      Your browser appears to be missing its cookie. It has already
      been tested for and appears to accept them. Either you have
      turned cookies off, or are unauthorised to be here. Please
      ensure cookies are enabled, and try again.
      };
      $variable->{Redirect} = $error_page;

      return OK;
    }

    #print STDERR "Displaying login\n";
    return eprint::login::login_display($r, $log, $dbh, $cookie, $variable);
  }

  if ($section) {
    # Process a logout without caring about user auth.
    if ($filename =~ /(?:account_)?log_?out\.html/) {
      eprint::login::logout($log, $dbh, $cookie, $section, $variable);
      return OK;
    }

    # Handles idle timeouts and last visit/access times.
    my $status = eprint::login::verify_user($r, $log, $dbh, $cookie, $variable, $section);
    return $status if $variable->{Redirect};

    # Process a login if one is occuring.
    if ($filename eq 'confirmation_login.html' || $filename eq 'login_confirmation.html' ) {
      my $status = eprint::login::verify_login($r, $log, $dbh, $cookie, $variable, $section); 
      check_cart($r, $log, $dbh, $cookie, $variable);
      return $status if $status && $status != OK;
    }

    # Puts user info into $variable (if there even is a user yet).
    eprint::login::get_login_info($log, $dbh, $cookie, $variable, $section);

    if ($section eq 'C') {

      # Something to do with logging in from email links.
      if ($r->param('AutoLogin')) {
        eprint::login::get_login_info($log, $dbh, $cookie, $variable, $r->param('AutoLogin'));
        sql::update($log, $dbh, 'tbl_Logged_In', "strSessionID = '$cookie' AND chrSite = 'C'", 
          lngCustomerID => $variable->{cust_id},
          lngUserID     => $variable->{user_id},
          chrUserType   => $variable->{user_type},
          strEmail      => $variable->{email},
        );
      }

      # Allow admins/employees to act as a proxy for another company.
      if ($r->param('SelectCustomer') && $variable->{user}{type} =~ /^[AE]$/) {
        eprint::login::select_customer($r, $log, $dbh, $cookie, $variable);
      }

    }

    # If the user isn't authorized for this section, check if the page is
    # public otherwise redirect them to a login page.
    unless (user_allowed($variable->{user}{type}, $section)) {
      print STDERR "User not allowed: type: ".$variable->{user}{type}, ' section: '.$section."\n";

      my @public = split /,/, configuration::get_value($log, $dbh, 'public_URIs');

      # We're not a public URI, so direct them to login.
      unless (grep { $page =~ /^$_$/ } @public) {

        my $destination = $r->method eq 'GET'
        ? 'destination=' . misc::get_destination($r, $log, $page)
        : '';

        print STDERR "HAVE DEST: $destination \n";
        $r->status(HTTP_MOVED_TEMPORARILY);
        $r->headers_out->set(
          Location => "/$first/login.html?section=$section;$destination"
        );

        return OK;
      }
    }

  } else {
    eprint::login::get_login_info($log, $dbh, $cookie, $variable, 'C');
  }

  # EXTRA STUFF IN $VARIABLE
  #
  if ((!$section) or ($section ne 'A' && $section ne 'E')) {
    # Add banner ads to the customer side.    


    if ( configuration::get_value($log, $dbh, 'UsesBanners') && !$variable->{BANNER_AD} ) {
      require eprint::banner;
      $variable->{BANNER_AD} = eprint::banner::select_banner($log, $dbh, $variable->{cust_id}, $variable->{user_id});

      # Calls procedure to get the ysnpricingservice,
      # ysnpricingprojectview, ysnpricingquotes from tbl_customer and
      # puts it into the variable hash, for more info see bug 1314
      require eprint::customer;
      @$variable{qw(isServicePricing isProjectViewPricing isQuotePricing)} 
      = eprint::customer::get_pricing_display_info(
        $log, $dbh, $variable->{cust_id}
      );

      require eprint::greetings;
      #Make Greeting available on all pages. Requested by Juile for Dominos.
      $$variable{'USER_CATEGORY_GREETING'} = eprint::greetings::select_user_category_greeting($log, $dbh, $variable->{user_id})
      if $variable->{user_id};
    }
  } else {
    # Adds the current version information (for use in the admin. footer).
    $variable->{pqs_version} = configuration::get_value($log, $dbh, 'BuildVersion');
  }

  log_request($page, $variable);

  # PAGE DISPATCH
  my %section = (
    administrator => \&section_admininistrator,
    employee      => \&section_employee,
    main          => \&section_main,
    site_specific => \&section_main,
    template      => \&section_templating,
    error         => \&section_error,
  );
  my $func = $section{ $first };
  if ($func) {
    $status = $func->($r, $log, $dbh, $variable, $cookie, $page, $second, $filename);
  } else {

    if ( -e $ENV{DOCUMENT_ROOT}.$r->uri ) {
      my ( $proc ) = $filename =~ /^(.*)\.(html|json)$/;
      if ( $proc ) {
        my $module = join('_', ($first, ($second ? $second : ())));
        eval {
          require "openprint/$module.pm";
          if ( my $function = ('openprint::'.$module)->can($proc) ) {
            $log->debug("Running openprint::$module->$proc") if DEBUG;
            $function->();
          } else {
            $log->debug("No function def for $module :: $proc!");
          }
        };
      } else {
        $log->debug("No proc found for $filename");
      } # end if
    } # end if -e $ENV{DOCUMENT_ROOT}.$uri
  }


  eprint::inventory::show_inventory($r, $log, $dbh, $variable)               if $filename eq 'Inventoried.html';

  return $status;
} # end sub parse_page

sub section_error {
}

sub section_templating {
  my ($r, $log, $dbh, $variable, $cookie, $uri, $sub_section, $filename) = @_;

  require eprint::Template;

  my $status;

  $status = eprint::Template::overview($r, $dbh, $variable)     if $filename eq 'main.html';

  $status = eprint::Template::data($r, $dbh, $variable)         if $filename eq 'data.html';
  $status = eprint::Template::upload($r, $dbh, $variable)       if $filename eq 'upload.html';
  $status = eprint::Template::download($r, $dbh, $variable)     if $filename eq 'download.html';

  $status = eprint::Template::view_record($r, $dbh, $variable)  if $filename eq 'record.html';

  $status = eprint::Template::assets($r, $dbh, $variable)       if $filename eq 'assets.html';
  $status = eprint::Template::upload_asset($r, $dbh, $variable) if $filename eq 'asset_upload.html';
  $status = eprint::Template::delete_asset($r, $dbh, $variable) if $filename eq 'asset_delete.html';

  return $status;
}

sub section_admininistrator {
  my ($r, $log, $dbh, $variable, $cookie, $uri, $sub_section, $filename) = @_;

  require eprint::admin_user;
  require eprint::admin_clerical;
  require eprint::admin_paper;
  require eprint::admin_quote;
  require eprint::admin_order;
  require eprint::admin_marketing;
  require eprint::admin_accounting;
  require eprint::admin_colours;
  require eprint::admin_shipping;
  require eprint::docket;
  require eprint::employee_project;
  require eprint::products;

  my $param = map_param();

  if ($sub_section) {
    if ($sub_section eq 'administrator') {
      eprint::login::email_password($r, $log, $dbh, $variable)  if $filename eq 'administrator_password_confirmation.html';
    } elsif ($sub_section eq 'marketing') {
      require eprint::promotion;
      eprint::promotion::list($param, $variable) if $filename eq 'promotions.html';
      eprint::promotion::edit($param, $variable) if  $filename eq 'promotion_edit.html';
    } elsif ($sub_section eq 'mat_inventory') {
      require eprint::mat_inventory;
      eprint::mat_inventory::display($param, $variable);
    } elsif ($sub_section eq 'production') {
      require eprint::admin_project;
      require eprint::admin_service;
      require eprint::admin_material;
      eprint::admin_service::price_list_view($r, $log, $dbh, $variable)                  if $filename eq 'services_price_lists_view.html';
      eprint::admin_material::price_list_view($r, $log, $dbh, $variable)                 if $filename eq 'materials_price_lists_view.html';

      eprint::admin_project::template_import_export($r, $log, $dbh, $variable)           if $filename eq 'project_templates.html';
      eprint::admin_project::template_services_import_export($r, $log, $dbh, $variable)  if $filename eq 'project_services.html';
      eprint::admin_project::types_edit($r, $log, $dbh, $variable)                       if $filename eq 'project_types.html';
      eprint::admin_project::defaults_edit($r, $log, $dbh, $variable)                    if $filename eq 'project_defaults.html';

      eprint::admin_colours::import_export($r, $log, $dbh, $variable)                    if $filename eq 'colour_import_export.html';
      eprint::admin_shipping::zone_import($r, $log, $dbh, $variable)                     if $filename eq 'shipping.html';

      eprint::docket::display($r, $log, $dbh, $variable, undef, undef, undef, 1)         if $filename eq 'proj_docket.html';
      eprint::docket::RFQ($r, $log, $dbh, $variable)                                     if $filename eq 'rfq_preview.html';
      eprint::admin_project::view_project_for_rfq($r, $log, $dbh, $variable)             if $filename eq 'project_view.html';

      use eprint::rfq;

      eprint::rfq::send_rfq($r, $dbh, $variable)                          			if $filename eq 'email_sent.html';
      eprint::rfq::process_rfq($r, $log, $dbh, $variable)                                if $filename eq 'rfq.html';
      eprint::rfq::process_rfq($r, $log, $dbh, $variable)                                if $filename eq 'po.html';

      eprint::rfq::send_po($r, $log, $dbh, $variable)                          		   if $filename eq 'send_po.html';

      eprint::rfq::admin_list($r, $dbh, $variable)                  					if $filename eq 'rfq_list.html';
      eprint::rfq::admin_list($r, $dbh, $variable)                  if $filename eq 'rfq_project_summary.html';
      eprint::rfq::rfq_project_list($r, $dbh, $variable)                  if $filename eq 'rfq_search.html';
      eprint::rfq::bid_history($r, $dbh, $variable) if $filename eq 'bid_history.html';
      eprint::rfq::api_bid($r, $dbh, $variable) 											if $filename eq 'api.html';

      use eprint::time;
      eprint::time::service_list($r, $dbh, $variable)                                                 if $filename eq 'time_service_list.html';
    } elsif ($sub_section eq 'paper') {
      eprint::admin_paper::paper_edit($r, $log, $dbh, $variable)       if $filename eq 'paper.html';
      eprint::admin_paper::paper_prices($r, $log, $dbh, $variable)     if $filename eq 'paper_prices.html';
      eprint::admin_paper::import_export($r, $log, $dbh, $variable)    if $filename eq 'import_export.html';
      eprint::admin_paper::price_list_edit($r, $log, $dbh, $variable)  if $filename eq 'price_list_edit.html';
      eprint::admin_paper::price_list_view($r, $log, $dbh, $variable)  if $filename eq 'price_list_view.html';
    } elsif ($sub_section eq 'stock') {
      my ( $proc ) = $filename =~ /(.*)\.\w*$/;
      if ( $proc ) {
        my $module = join('_', 'administrator', $sub_section);
        eval {
          require "openprint/$module.pm";
          if ( my $function = ('openprint::'.$module)->can($proc) ) {
            $log->debug("Running openprint::$module->$proc") if DEBUG;
            $function->($r, $log, $dbh, $variable );
            $log->error( "Can't $module :: $proc, Reason: $@" ) if $@;
          } else {
            $log->error( "Can't $module :: $proc, Reason: " );
          }
        };
        $log->error( "Can't $module :: $proc, Reason: $@" ) if $@;
      } # end if

    } elsif ($sub_section eq 'managerial') {
      require eprint::credit_application;

      #New Accounting Features
      use eprint::bills;

      eprint::bills::display($param, $variable)                					if $filename eq 'accounting_bills.html';

      eprint::admin_accounting::details($r, $log, $dbh, $variable)                if $filename eq 'accounting_details.html' 
      || $filename eq 'accounting_details_printer_friendly.html';

      eprint::admin_accounting::payment($r, $log, $dbh, $variable)                if $filename eq 'accounting_payments.html';
      eprint::admin_accounting::search($r, $log, $dbh, $variable)                 if $filename eq 'accounting_search.html';

      require eprint::admin_customer;
      eprint::admin_customer::admin_customer_edit($r, $log, $dbh, $variable)      if $filename eq 'company_profiles.html';
      eprint::admin_customer::product_markup($r, $log, $dbh, $variable)      		if $filename eq 'product_markup.html';
      eprint::admin_user::admin_user_edit($r, $log, $dbh, $variable)              if $filename eq 'user_profiles.html';
      eprint::credit_application::credit_application($r, $log, $dbh, $variable)   if $filename eq 'credit_application.html';
      eprint::credit_application::credit_applications($r, $log, $dbh, $variable)  if $filename eq 'credit_applications.html';

      eprint::admin_clerical::currency_edit($r, $log, $dbh, $variable)            if $filename eq 'currency.html';
      eprint::admin_clerical::tax_tables($r, $log, $dbh, $variable)               if $filename eq 'taxes.html';
      eprint::admin_clerical::county_tax_tables($r, $log, $dbh, $variable)        if $filename eq 'county_taxes.html';
      eprint::admin_clerical::tax_stewardship($r, $log, $dbh, $variable)          if $filename eq 'taxes_stewardship.html';
      eprint::admin_clerical::notifications_edit($r, $log, $dbh, $variable)       if $filename eq 'notifications.html';
      eprint::admin_clerical::misc_settings_edit($r, $log, $dbh, $variable)       if $filename eq 'configuration.html';
      eprint::admin_clerical::inventory_locations($r, $log, $dbh, $variable)      if $filename eq 'inventory_locations.html';

    } elsif ($sub_section eq 'reports') {
      require eprint::admin_reports;
      eprint::admin_reports::inventory($r, $log, $dbh, $variable)          		 if $filename eq 'inventory_reports.html';
      eprint::admin_reports::accounting_report($r, $log, $dbh, $variable)          if $filename eq 'reports_accounting.html';
      eprint::admin_reports::stored_report_display($r, $log, $dbh, $variable)      if $filename eq 'reports_custom.html';
      eprint::admin_reports::stored_report_process($r, $log, $dbh, $variable)      if $filename eq 'reports_custom_results.html';
      eprint::admin_reports::order_report($r, $log, $dbh, $variable)               if $filename eq 'reports_orders.html';
      eprint::admin_reports::paypal($r, $log, $dbh, $variable)               		 if $filename eq 'paypal_report.html';
      eprint::admin_reports::project_report($r, $log, $dbh, $variable)             if $filename eq 'reports_projects.html';
      eprint::admin_reports::quotes_report($r, $log, $dbh, $variable)              if $filename eq 'reports_quotes.html';
      eprint::admin_reports::cost_center($r, $log, $dbh, $variable)             	 if $filename eq 'reports_cost_center.html';
      eprint::admin_reports::internal_billing($r, $log, $dbh, $variable)           if $filename eq 'reports_internal_billing.html';
      eprint::docket::service_summary($r, $log, $dbh, $variable)                   if $filename eq 'service_feedback.html';
      eprint::docket::service_summary($r, $log, $dbh, $variable)                   if $filename eq 'docket.html';
      eprint::admin_reports::national_report($r, $log, $dbh, $variable)            if $filename eq 'national_report.html';
      eprint::admin_reports::shipping_report($r, $log, $dbh, $variable)            if $filename eq 'shipping_report.html';
    } elsif ($sub_section eq 'products') {
      eprint::products::list($r, $dbh, $variable) if $filename eq 'products.html';
      eprint::products::category_admin($r, $dbh, $variable) if $filename eq 'categories.html';
      eprint::products::builder($r, $dbh, $variable) if $filename eq 'builder.html';
      eprint::products::kit_select($r, $dbh, $variable) if $filename eq 'kit_select.html';
      eprint::products::price_admin($r, $dbh, $variable) if $filename eq 'price.html';
      eprint::products::discount_admin($r, $dbh, $variable) if $filename eq 'version_discount.html';

    }
  } # end if sub_section

  return OK;
} # end sub section_administrator

sub section_employee {
  my ($r, $log, $dbh, $variable, $cookie, $uri, $sub_section, $filename) = @_;

  require eprint::employee;
  require eprint::employee_project;
  require eprint::employee_support;
  require eprint::employee_quotes;
  require eprint::employee_orders;
  require eprint::banner;
  require eprint::docket;
  require eprint::admin_marketing;

  if ( $sub_section eq 'employee') {
    eprint::employee::user_edit($r, $log, $dbh, $variable)    if $filename eq 'profile.html';
    eprint::login::email_password($r, $log, $dbh, $variable)  if $filename eq 'password_confirmation.html';
  } elsif ( $sub_section eq 'production' ) {
    eprint::employee_orders::orders_report($r, $log, $dbh, $variable)  if $filename eq 'modify_orders.html';
    eprint::employee_quotes::quotes_report($r, $log, $dbh, $variable)  if $filename eq 'modify_quotes.html';
    eprint::employee_project::project_list($r, $log, $dbh, $variable)  if $filename eq 'projects.html';
    eprint::employee_project::view_project($r, $log, $dbh, $variable)  if $filename eq 'project_view.html';
    eprint::print::view_services($r, $log, $dbh, $cookie, $variable)   if $filename eq 'proj_view.html';
    eprint::docket::display($r, $log, $dbh, $variable)                 if $filename eq 'proj_docket.html';

    use eprint::time;
    eprint::time::service_allocation($r, $dbh, $variable)                  			if $filename eq 'time_service_allocation.html';
    eprint::time::time_collection($r, $dbh, $variable)                  			if $filename eq 'time_collection.html';
    eprint::time::punch_history($r, $dbh, $variable)                  				if $filename eq 'time_punch_history.html';
    eprint::time::service_history($r, $dbh, $variable)                  			if $filename eq 'time_service_history.html';
  } elsif ( $sub_section eq 'marketing' ) {
    eprint::banner::banner_action($r, $log, $dbh, $variable)                if $filename eq 'banners.html';
    eprint::admin_marketing::category_edit($r, $log, $dbh, $variable)       if $filename eq 'categories.html';
    eprint::admin_marketing::maillist($r, $log, $dbh, $variable)            if $filename eq 'mail_confirmation.html';
    eprint::admin_marketing::mailinglistmembers($r, $log, $dbh, $variable)  if $filename eq 'mail.html';
    eprint::admin_marketing::view_email($r, $log, $dbh, $variable)          if $filename eq 'view_email.html';

    use eprint::admin_mail;
    eprint::admin_mail::handler($r, $log, $dbh, $variable)       			if $filename eq 'mailing_database.html';
  } elsif ($sub_section eq 'support' ) {
    eprint::employee_support::helpdesk($r, $log, $dbh, $variable)         if $filename eq 'helpdesk.html';
    eprint::employee_support::helpdesk_search($r, $log, $dbh, $variable)  if $filename eq 'helpdesk_search.html';
    eprint::employee_support::rma($r, $log, $dbh, $variable)              if $filename eq 'return.html';
    eprint::employee_support::rma_search($r, $log, $dbh, $variable)       if $filename eq 'returns.html';
  } else {
    my ( $proc ) = $filename =~ /(.*)\.\w*$/;
    if ( $proc ) {
      my $module = join('_', 'employee', $sub_section);
      eval {
        require "openprint/$module.pm";
        if ( my $function = ('openprint::'.$module)->can($proc) ) {
          $log->debug("Running openprint::$module->$proc") if DEBUG;
          $function->($r, $log, $dbh, $variable );
          $log->error( "Can't $module :: $proc, Reason: $@" ) if $@;
        } else {
          $log->error( "Can't $module :: $proc, Reason: " );
        }
      };
      $log->error( "Can't $module :: $proc, Reason: $@" ) if $@;
    } # end if
  }

  return OK;
}

sub section_main {
  my ($r, $log, $dbh, $variable, $cookie, $uri, $sub_section, $filename) = @_;
  my $status = OK;

  require eprint::customer;
  require eprint::inventory;
  require eprint::docket;
  require eprint::project_files;
  require eprint::shopping_list;

  if ($sub_section eq 'account') {
    require eprint::credit_application;
    require eprint::reseller_application;
    eprint::login::login_display($r, $log, $dbh, $cookie, $variable)                        if $filename eq 'account_login.html';
    eprint::login::display_select_customer($r, $log, $dbh, $variable, $variable->{cust_id}) if $filename eq 'account_select_customer.html';
    eprint::login::select_customer($r, $log, $dbh, $cookie, $variable)                      if $filename eq 'confirmation_select_customer.html';
    eprint::login::login_app_display($r, $log, $dbh, $variable)                             if $filename eq 'registration.html';
    eprint::login::login_app_display($r, $log, $dbh, $variable)                             if $filename eq 'user_registration.html';

    eprint::login::login_app_process($r, $log, $dbh, $variable, $cookie)                    if $filename eq 'confirmation_login_application.html';

    eprint::login::cust_edit($r, $log, $dbh, $variable)                                     if $filename eq 'account_edit_company_profile.html';
    eprint::login::user_edit($r, $log, $dbh, $variable)                                     if $filename eq 'user_profile.html';
    eprint::login::login_password($r, $log, $dbh, $variable)                                if $filename eq 'account_password.html';
    eprint::login::email_password($r, $log, $dbh, $variable)                                if $filename eq 'confirmation_password_0.html';
    eprint::login::change_password($r, $log, $dbh, $variable)                               if $filename eq 'confirmation_password_1.html';

    eprint::credit_application::credit_app_display($r, $log, $dbh, $variable)               if $filename eq 'credit_application.html';
    eprint::credit_application::credit_app_process($r, $log, $dbh, $variable)               if $filename eq 'confirmation_credit_application.html';
    eprint::reseller_application::reseller_application_display($r, $log, $dbh, $variable)   if $filename eq 'reseller_application.html';
    eprint::reseller_application::reseller_application_process($r, $log, $dbh, $variable)   if $filename eq 'confirmation_reseller_application.html';
    eprint::customer::product_page($r, $log, $dbh, $variable)                               if $filename eq 'my_products.html';
  } elsif ($sub_section eq 'order') {
    require eprint::order;
    eprint::order::finalise_order($r, $log, $dbh, $cookie, $variable)           if $filename eq 'confirmation_make_order.html';
    eprint::order::history_details($r, $log, $dbh, $variable)                   if $filename eq 'order_history_details.html';
    eprint::order::order_history($r, $log, $dbh, $variable)                     if $filename eq 'order_history.html';
    eprint::order::order_info($r, $log, $dbh, $cookie, $variable)               if $filename eq 'order_info.html';

    eprint::order::history_details($r, $log, $dbh, $variable)                   if $filename eq 'order_invoice_printer_friendly.html';
    eprint::order::packing_slip($variable)                   					if $filename eq 'packing_slip.html';

    eprint::order::quantity_select_display($r, $log, $dbh, $cookie, $variable)  if $filename eq 'order_selection.html';
    eprint::order::verify_order($r, $log, $dbh, $cookie, $variable)             if $filename eq 'order_submit.html';
    eprint::order::reorder_notice($r, $log, $dbh, $cookie, $variable)           if $filename eq 'reorder_notice_printer_friendly.html';
    eprint::order::verify_beanstream($r, $log, $dbh, $cookie, $variable)        if $filename eq 'payment_confirmation.html';
    eprint::order::show_payflow($r, $log, $dbh, $cookie, $variable)        		if $filename eq 'payment.html';
    eprint::order::paypal_error($r, $log, $dbh, $cookie, $variable)        		if $filename eq 'error.html';
    eprint::order::paypal_return($r, $log, $dbh, $cookie, $variable)        	if $filename eq 'paypal_return.html';

  } elsif ($sub_section eq 'quote') {
    require eprint::quote;
    eprint::quote::finalise_quote($r, $log, $dbh, $cookie, $variable)   if $filename eq 'confirmation_make_quote.html';
    eprint::quote::generate_quote($r, $log, $dbh, $cookie, $variable)   if $filename eq 'quote_details.html';
    eprint::quote::show_quote($r, $log, $dbh, $variable)                if $filename eq 'quote_history_details.html';
    eprint::quote::quote_history($r, $log, $dbh, $variable)             if $filename eq 'quote_history.html';
    eprint::quote::user_quote_info($r, $log, $dbh, $cookie, $variable)  if $filename eq 'quote_info.html';
    eprint::quote::show_quote($r, $log, $dbh, $variable)                if $filename eq 'quote_printer_friendly.html';
    eprint::quote::submit_quote($r, $log, $dbh, $cookie, $variable)     if $filename eq 'quote_submit.html';
  } elsif ($sub_section eq 'support') {
    #require eprint::support;
    #eprint::support::userinfo($r, $log, $dbh, $variable)  if $filename eq 'support_help_desk.html';
    #eprint::support::helpdesk($r, $log, $dbh, $variable)  if $filename eq 'confirmation_help_desk.html';
    #eprint::support::userinfo($r, $log, $dbh, $variable)  if $filename eq 'support_returns.html';    
    #eprint::support::rma($r, $log, $dbh, $variable)       if $filename eq 'confirmation_returns.html';
  } elsif ($sub_section eq 'products') {
    require eprint::ProductGroup;

    $status = eprint::ProductGroup::display_category($r, $dbh, $variable) if $filename eq 'display.html';
    $status = eprint::ProductGroup::select_project($r, $dbh, $variable)   if $filename eq 'select.html';
    eprint::qprice::upload($r, $dbh, $variable)							  if $filename eq 'upload_complete.html';
  } elsif ($sub_section eq 'dashboard') {
    require eprint::dashboard;
    my $param = map_param();
    print STDERR "HAVE AP ", Dumper($r->param('actionpid'), scalar $r->param('actionpid') );
    eprint::dashboard::display($variable, $param) if $filename eq 'dashboard.html';
  } elsif ($sub_section eq 'proj') {
    require eprint::print_project;    
    require eprint::print;

    if ($filename eq 'dispatch.html') {
      # TODO Set the headers and return the redirect in dispatch().
      my $location = eprint::print_project::dispatch($r, $log, $dbh, $cookie, $variable);

      $r->status(HTTP_MOVED_TEMPORARILY);
      $r->headers_out->set(Location => $location);
      return OK;
    }

    # Create custom or predefined project.
    eprint::print_project::create_display($r, $log, $dbh, $cookie, $variable)  if $filename eq 'create.html';
    eprint::print_project::edit_display($r, $log, $dbh, $cookie, $variable)    if $filename eq 'edit.html';
    eprint::print_project::display_reuse_project($r, $log, $dbh, $variable)    if $filename eq 'proj_crea_reuse.html';
    eprint::print_project::history_list($r, $log, $dbh, $variable)             if $filename eq 'proj_hist.html';

    eprint::print_project::api_list($r, $log, $dbh, $variable)             	   if $filename eq 'api_hist.html';
    eprint::print_project::api_xml($r, $log, $dbh, $variable)             	   if $filename eq 'req.html';

    eprint::inventory::inventory_list($r, $log, $dbh, $variable)               if $filename eq 'inventory_history.html';
    eprint::inventory::inventory_details($r, $log, $dbh, $variable)            if $filename eq 'inventory_details.html';
    eprint::inventory::checkout_list($r, $log, $dbh, $variable)                if $filename eq 'check_out_history.html';
    require eprint::admin_reports;
    eprint::admin_reports::inventory_usage($r, $log, $dbh, $variable)          if $filename eq 'inventory_reports.html';
    eprint::admin_reports::template_data($r, $log, $dbh, $variable)            if $filename eq 'template_data.html';

    if ($filename eq 'import_export.html') {
      require eprint::Service::Shipping;
      eprint::Service::Shipping::import_export($r, $log, $dbh, $variable);
    }

    # View the project (pricing).
    if ( $filename eq 'view.html' ) {

      # We need to make sure that people are logged in or have a chance
      # to login using all the links from emails sent out.
      unless ($variable->{user_id}) {
        $variable->{Redirect}    = '/error/error_login.html';
        $variable->{Destination} = misc::get_destination($r, $log, $uri);
        return OK;
      } 

      eprint::print::view_services($r, $log, $dbh, $cookie, $variable);
    }

    eprint::print::view_services($r, $log, $dbh, $cookie, $variable)   if $filename eq 'proj_view_printer_friendly.html';
    eprint::print_project::price_breakdown($r, $log, $dbh, $variable)  if $filename eq 'proj_printer_summ_price_breakdown.html';
    eprint::print_project::price_breakdown($r, $log, $dbh, $variable)  if $filename eq 'imposition.html';

    $status = eprint::project_files::display_files($r, $log, $dbh, $variable)    if $filename eq 'files.html';
    $status = eprint::project_files::display_upload($r, $log, $dbh, $variable)   if $filename eq 'upload.html';
    $status = eprint::project_files::actions($r, $log, $dbh, $variable)          if $filename eq 'file_action.html';

    $status = eprint::docket::pdf($r, $log, $dbh, $variable)       if $filename eq 'docket.pdf';
    $status = eprint::docket::display($r, $log, $dbh, $variable, undef, undef, undef, 1, undef)       if $filename =~ /^(?:proj_)?docket(?:|_custom)?.html/;

    $status = eprint::docket::display($r, $log, $dbh, $variable, undef, undef, undef, 1, 1)       if $filename eq 'proj_docket_printer_friendly.html';

    $status = eprint::docket::comment($r, $log, $dbh, $variable)       if $filename eq 'docket_comment.html';

    eprint::print_project::project_notification($r, $dbh, $variable)          if $filename eq 'project_notification.html';

    if ($filename eq 'shipping_labels.html'){
      require eprint::Service::Shipping;
      eprint::Service::Shipping::print_labels($r, $log, $dbh, $variable, $r->param('ServiceIndex'));
    }

    if ($filename eq 'paper_edit.html') {
      require eprint::admin_paper;
      eprint::admin_paper::paper_edit($r, $log, $dbh, $variable);
    }
  } elsif ($sub_section eq 'supplier') {
    require eprint::rfq;
    eprint::rfq::rfq_list($r, $dbh, $variable) if $filename eq 'rfq_history.html';
    eprint::rfq::bid_history($r, $dbh, $variable) if $filename eq 'bid_history.html';
    eprint::rfq::display_rfq($r, $dbh, $variable) if $filename eq 'display_rfq.html';
    eprint::rfq::process_rfq($r, $log, $dbh, $variable, 1)                if $filename eq 'purchase_order.html';
    eprint::rfq::process_rfq($r, $log, $dbh, $variable, 1)                if $filename eq 'purchase_order_printer_friendly.html';
    print STDER "MY FILENAME: $filename \n";

  } elsif ($sub_section eq 'rfq') {
    require eprint::rfq;
    require eprint::admin_project;
    eprint::rfq::process_rfq($r, $log, $dbh, $variable)           if $filename eq 'rfq.html';
    eprint::rfq::admin_list($r, $dbh, $variable)                  if $filename eq 'rfq_list.html';
    eprint::rfq::admin_list($r, $dbh, $variable)                  if $filename eq 'rfq_project_summary.html';
    eprint::rfq::rfq_project_list($r, $dbh, $variable)            if $filename eq 'rfq_search.html';
    eprint::rfq::bid_history($r, $dbh, $variable) 		      if $filename eq 'bid_history.html';
    eprint::docket::RFQ($r, $log, $dbh, $variable)                                     if $filename eq 'rfq_preview.html';
    eprint::admin_project::view_project_for_rfq($r, $log, $dbh, $variable)             if $filename eq 'project_view.html';
    eprint::rfq::send_rfq($r, $dbh, $variable)                          			if $filename eq 'email_sent.html';
  } elsif ($sub_section eq 'files') {
    eprint::project_files::ftp_folder($r, $dbh, $variable)          if $filename eq 'folders.html';
    eprint::project_files::ftp_file($r, $dbh, $variable)           	if $filename eq 'files.html';

  } elsif ($sub_section eq 'shopping_list') {
    eprint::shopping_list::list($r, $dbh, $variable) if $filename eq 'shopping_lists.html';
    eprint::shopping_list::get($r, $dbh, $variable) if $filename eq 'shopping_list.html';
  } elsif ($sub_section eq 'ecommerce') {
    eprint::products::display($r, $dbh, $variable) if $filename eq 'products.html';
    eprint::products::display_categories($r, $dbh, $variable) if $filename eq 'categories.html';
    eprint::products::details($r, $dbh, $variable) if $filename eq 'product_details.html';
    eprint::products::design($r, $dbh, $variable, $cookie) if $filename eq 'design.html';
  }

  #print STDERR "Before menu_options\n";
  menu_options($dbh, $variable);

  #print STDERR "CHECK ASR " . $r->param('run_asr') . "-- \n";
  if ( $r->param('asr') and ( $r->param('asr') eq 'mailing')) {
    require eprint::mailing;
    eprint::mailing::handler($r, $dbh, $variable);
  };

  return $status;
}

sub map_param {
  my $param;
  my $r = session::r;
  #print STDERR "START MAP \n";
  map { 
    my @p = $r->param($_);
    #print STDERR "HAVE PARAM P $_ =  " , $r->param($_)  . "\n";

    if (@p == 1 ) {
      $param->{$_} = shift @p;
    } else {
      $param->{$_} = \@p;
    }
  } $r->param();

  #print STDERR "HAVE PARAM MAPPED", Dumper($param);


  return $param;
}

sub menu_options {
  my ( $dbh, $var) = @_;

  my $cats = PQS::model::categories::get_all();

  #map { push @{$var->{prod_menu}}, $cats->{$_}; } sort keys $cats;
  @{$var->{prod_menu}} = ();

  map { push @{$var->{prod_menu}}, $cats->{$_}; } sort { $a cmp $b } keys %{$cats};
}

sub check_cart {
  my ($r, $log, $dbh, $cookie, $var) = @_;

  my $order_id = $dbh->selectrow_array(q{
    SELECT lngorderid FROM tbl_orders WHERE NOT ysnfinished
    AND lnguserid = ? 
    AND dtmorderdate > Now() - '1 day'::interval
    ORDER by 1 desc
    }, undef, $var->{user_id});

  my $pid = $dbh->selectrow_array(q{
    SELECT p.lngprojectindex FROM tbl_projects p, tbl_order_contents oc
    WHERE p.lngprojectindex = oc.lngprojectindex AND lngorderid = ?
    AND strstatus = 'uncalculated'
    AND dtmcreationdate > Now() - '1 day'::interval
    ORDER by 1 desc
    }, undef, $order_id);

  if ( $pid ) {
    # if there is unfinished project on order, (hybrid)
    $var->{build_page} = "/build?pid=$pid";
  } elsif ( $order_id )  {
    # if there is unfinished order, and projects are finished (hybrid)
    $var->{order_page} = "/main/order/order_submit.html?Return=$order_id";
  } else {
    # we may want to look for there last unfinished project (non hybrid)
  }

  #print STDERR "HAVE ORDER: $order_id PID: $pid - $var->{user_id} \n";
} # end sub check_cart

1;
__END__
