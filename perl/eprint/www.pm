package eprint::www;
use strict;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY);
use Apache2::Request   ();
use Apache2::Log       ();
use Apache2::Cookie    ();
use HTML::FillInForm  ();

use PQS::DB ();
use PQS::Constants;
use PQS::Error;

use ssi qw($gdb);
use sql ();
use misc;
use configuration;
use session;

require eprint::login;

use constant MAX_REDIRECTS => 20;


sub generate_cookie {
    my ( $r, $log, $dbh ) = @_;

    # Get the domain from Apache config or, failing that, the database.
    my ($user, $pass, $host, $port) = $r->headers_in->{'Host'}
        =~ /(?:([^:]+):([^\@]+)\@)?([^\@:]+)(?::(\d+))?/;

    my $domain = $host
              || $r->dir_config('cookiedomain')
              || configuration::get_value($log, $dbh, 'cookiedomain');

	
    # Generate and set the cookie.
    my $cookie = Apache2::Cookie->new($r,
            -name    => 'SessionID',
            -value   => misc::gen_session_id(), # Ludicrously small.
            -path    => '/',
            -domain  => $domain
    );



    $cookie->bake($r);

    # Return the generated session ID.
    return $cookie->value();
}

# Silly little function that works like an enum. Takes a user type and the
# section and returns true if that user type is allowed in the section.
sub user_allowed {
    my ($user, $section) = @_;

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

    my $r = Apache2::Request->new($rec);
    $r->parse;

    session::r($r);
    session::log($r->log);

    if ( $r->header_only ) {
        $r->log->debug("Browser only wanted header.");
        return OK;
    }


	ssi:$gdb 	 = PQS::DB->connect($r, { ReadOnly => 1 });
    my $dbh      = PQS::DB->connect($r, { AutoCommit => 1 });
    session::dbh($dbh);
    my $variable = {};
    my $cookie   = misc::get_cookie($r, $r->log, $dbh, $variable);

    $cookie = generate_cookie($r, $r->log, $dbh)
        unless $cookie;

    %{$variable->{param}} = map {$_ => $r->param($_)} $r->param();

print STDERR "HAVE COOKIE: $cookie\n";

    my ($page, $args, $status);
    
    word_sub ($variable);

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
            }
            else {
                $page = $r->uri();
            }

            $status = parse_page( $r, $r->log, $cookie, $dbh, $variable, $page );

            die "Maximum redirects exceeded" if $redirects > MAX_REDIRECTS;

            $redirects++, redo REDIRECTS if $variable->{Redirect};
        }
    };
    if ($@) {
        my $err = $@;

        $dbh->disconnect;

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
        $dbh->disconnect;
        $r->status( $status );
        return $status;
    }

    if ( $variable->{Download} ) {
        for my $line (@{ $variable->{File_Data} }) {
            print $line;
        }
    }
    else {

print STDERR "HERE I AM, WWW 1 \n\n";
		my $filename = ssi::get_file_path($r, $page);

        my $fh;

        if (!open $fh, '<', $filename ) {
            $dbh->disconnect;
            $r->log->error("Failed opening $page: $!");
            die "Failed to open $filename: $!";
        }

        # read in the data
        my $file_data = do { local $/ = undef; <$fh> };

        close $fh;

        $file_data = ssi::variable_substitution(
            $r, $r->log, $dbh, $file_data, $variable
        );

print STDERR "CHECK FILL IN FORM \n";
        if ( $variable->{__FillInForm} ) {
print STDERR "HAVE FILL IN FORM \n";
            my $f = new HTML::FillInForm;
            $file_data = $f->fill(scalarref => \$file_data,
                                  fdat      => $variable->{__FillInForm} );
        }

        # this is where we actually send the page to the client
        $r->content_type('text/html');
        print( $file_data );
    }

print STDERR "END REQUEST \n\n\n\n\n";

    $dbh->disconnect;
    $gdb->disconnect;

    return OK;
}

sub word_sub {
	my ($variable) = @_;
	my ($file_data) = @_;

	my %words = (split ',', eprint::Config->get(General => 'word_sub'));

	map { $variable->{'ws_'.$_}  = $words{$_}; print STDERR "CHANGE: $_ to $words{$_} \n"; } keys %words;
	map { $file_data =~ s/$_/$words{$_}/g; print STDERR "CHANGE: $_ to $words{$_} \n"; } keys %words;
	return $file_data;
}


sub parse_page {
    my ($r, $log, $cookie, $dbh, $variable, $page) = @_;
    my ($status);
	use XML::Simple;

print STDERR "START PARSE PAGE \n\n";

    unless ($cookie || $variable->{error}) {
		print STDERR "COOKIE: $cookie : ERROR: $variable->{error} \n\n";
		my $error_page = configuration::get_value($r->log, $dbh, 'errorpage');

		$variable->{error}   = 'Restricted Access';
		$variable->{details} = q{
		   This site can only be accessed from:
		   <a href='http://online.dominos.ca'>http://online.dominos.ca</a>
		};

		$variable->{Redirect} = $error_page;

		return OK;
     }

    # The module dispatches by 'section' based on the uri.
    my @path     = grep { $_ } split '/', $page;
    my $filename = pop @path;
    
    shift @path if $path[0] eq 'site_specific';

    
    my ($first, $second) = @path;
    
    print STDERR "HAVE SECTIONS FIRST: $first SECOND: $second \n";

    # The current section we're in.
    $variable->{section} = $first if defined $first;

    my $section = $first eq 'administrator' ? 'A'
                : $first eq 'employee'      ? 'E'
                : $first eq 'main'          ? 'C'
                :                             undef; # General public area


    # USER AUTHENTICATION/AUTHORIZATION
    #
    # While this section is cleaned up it's still the old code that really has
    # no idea of what authentication then autorization is.

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

        return eprint::login::login_display($r, $log, $dbh, $cookie, $variable);
    }

    if ($section) {
        # Process a logout without caring about user auth.
        if ($filename =~ /(?:account_)?log_?out\.html/) {
            eprint::login::logout($log, $dbh, $cookie, $section, $variable);
            return OK;
        }

        # Handles idle timeouts and last visit/access times.
        my $status = eprint::login::verify_user(
            $r, $log, $dbh, $cookie, $variable, $section
        );
        return $status if $variable->{Redirect};

        # Process a login if one is occuring.
        if (   $filename eq 'confirmation_login.html' 
            || $filename eq 'login_confirmation.html' ) 
        {
            
            my $status = eprint::login::verify_login(
                $r, $log, $dbh, $cookie, $variable, $section); 
			
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

            my @public = split /,/, configuration::get_value($log, $dbh, 'public_URIs');
use Data::Dumper;
print STDERR "HAVE PUBLIC FOR PAGE: $page" , Dumper(\@public);

            # We're not a public URI, so direct them to login.
            unless (grep { $page =~ /^$_$/ } @public) {

                my $destination = $r->method eq 'GET'
                    ? 'destination=' . misc::get_destination($r, $log, $page)
                    : '';

                $r->status(HTTP_MOVED_TEMPORARILY);
                $r->headers_out->set(
                    Location => "/$first/login.html?section=$section;$destination"
                );

                return OK;
            }
        }

    }
    else {
       eprint::login::get_login_info($log, $dbh, $cookie, $variable, 'C');
    }

    # EXTRA STUFF IN $VARIABLE
    #
    if ($section ne 'A' && $section ne 'E') {
        # Add banner ads to the customer side.    


        if ( configuration::get_value($log, $dbh, 'UsesBanners') && !$variable->{BANNER_AD} ) {
            require eprint::banner;

            $variable->{BANNER_AD} 
                = eprint::banner::select_banner(
                    $log, $dbh, $variable->{cust_id}, $variable->{user_id}
            );

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
			$$variable{'USER_CATEGORY_GREETING'} = 
				eprint::greetings::select_user_category_greeting($log, $dbh, $variable->{user_id})
				if $variable->{user_id};

        }
    }
    else {
        # Adds the current version information (for use in the admin. footer).
        $variable->{pqs_version} 
            = configuration::get_value($log, $dbh, 'BuildVersion');
    }


    

    # PAGE DISPATCH
    #
    my %section = (
        administrator => \&section_admininistrator,
        employee      => \&section_employee,
        main          => \&section_main,
        site_specific => \&section_main,
        template      => \&section_templating,
    );
    my $func = $section{ $first };

    $status = $func->($r, $log, $dbh, $variable, $cookie, $page, $second, $filename) 
        if $func;

    eprint::inventory::show_inventory($r, $log, $dbh, $variable)               if $filename eq 'Inventoried.html';

    return $status;
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

    require eprint::admin_customer;
    require eprint::admin_user;
    require eprint::admin_project;
    require eprint::admin_service;
    require eprint::admin_clerical;
    require eprint::admin_paper;
    require eprint::admin_quote;
    require eprint::admin_order;
    require eprint::admin_material;
    require eprint::admin_marketing;
    require eprint::admin_accounting;
    require eprint::admin_colours;
    require eprint::admin_shipping;
    require eprint::admin_reports;
    require eprint::docket;
    require eprint::employee_project;
    require eprint::products;

print STDERR "SUB: $sub_section F: $filename \n";
    if ($sub_section eq 'administrator') {
        eprint::login::email_password($r, $log, $dbh, $variable)  if $filename eq 'administrator_password_confirmation.html';
    } 
    elsif ($sub_section eq 'production') {
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
    } 
    elsif ($sub_section eq 'paper') {
        eprint::admin_paper::paper_edit($r, $log, $dbh, $variable)       if $filename eq 'paper.html';
        eprint::admin_paper::paper_prices($r, $log, $dbh, $variable)     if $filename eq 'paper_prices.html';
        eprint::admin_paper::import_export($r, $log, $dbh, $variable)    if $filename eq 'import_export.html';
        eprint::admin_paper::price_list_edit($r, $log, $dbh, $variable)  if $filename eq 'price_list_edit.html';
        eprint::admin_paper::price_list_view($r, $log, $dbh, $variable)  if $filename eq 'price_list_view.html';

    } 
    elsif ($sub_section eq 'managerial') {
        require eprint::credit_application;

        eprint::admin_accounting::details($r, $log, $dbh, $variable)                if $filename eq 'accounting_details.html' 
                                                                                    || $filename eq 'accounting_details_printer_friendly.html';
        eprint::admin_accounting::payment($r, $log, $dbh, $variable)                if $filename eq 'accounting_payments.html';
        eprint::admin_accounting::search($r, $log, $dbh, $variable)                 if $filename eq 'accounting_search.html';
        
        eprint::admin_customer::admin_customer_edit($r, $log, $dbh, $variable)      if $filename eq 'company_profiles.html';
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
           
    } 
    elsif ($sub_section eq 'reports') {
        eprint::admin_reports::inventory($r, $log, $dbh, $variable)          		 if $filename eq 'inventory_reports.html';
        eprint::admin_reports::accounting_report($r, $log, $dbh, $variable)          if $filename eq 'reports_accounting.html';
        eprint::admin_reports::stored_report_display($r, $log, $dbh, $variable)      if $filename eq 'reports_custom.html';
        eprint::admin_reports::stored_report_process($r, $log, $dbh, $variable)      if $filename eq 'reports_custom_results.html';
        eprint::admin_reports::order_report($r, $log, $dbh, $variable)               if $filename eq 'reports_orders.html';
        eprint::admin_reports::project_report($r, $log, $dbh, $variable)             if $filename eq 'reports_projects.html';
        eprint::admin_reports::quotes_report($r, $log, $dbh, $variable)              if $filename eq 'reports_quotes.html';
        eprint::admin_reports::cost_center($r, $log, $dbh, $variable)             	 if $filename eq 'reports_cost_center.html';
        eprint::admin_reports::internal_billing($r, $log, $dbh, $variable)           if $filename eq 'reports_internal_billing.html';
        eprint::docket::service_summary($r, $log, $dbh, $variable)                   if $filename eq 'service_feedback.html';
        eprint::docket::service_summary($r, $log, $dbh, $variable)                   if $filename eq 'docket.html';
        eprint::admin_reports::national_report($r, $log, $dbh, $variable)            if $filename eq 'national_report.html';
        eprint::admin_reports::shipping_report($r, $log, $dbh, $variable)            if $filename eq 'shipping_report.html';
    }
    elsif ($sub_section eq 'products') {
      eprint::products::list($r, $dbh, $variable) if $filename eq 'products.html';
      eprint::products::category_admin($r, $dbh, $variable) if $filename eq 'categories.html';
      eprint::products::builder($r, $dbh, $variable) if $filename eq 'builder.html';
      eprint::products::kit_select($r, $dbh, $variable) if $filename eq 'kit_select.html';
      eprint::products::price_admin($r, $dbh, $variable) if $filename eq 'price.html';
      eprint::products::discount_admin($r, $dbh, $variable) if $filename eq 'version_discount.html';
      
    }

    return;
}


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
    } 
    elsif ( $sub_section eq 'production' ) {
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
    } 
    elsif ( $sub_section eq 'marketing' ) {
        eprint::banner::banner_action($r, $log, $dbh, $variable)                if $filename eq 'banners.html';
        eprint::admin_marketing::category_edit($r, $log, $dbh, $variable)       if $filename eq 'categories.html';
        eprint::admin_marketing::maillist($r, $log, $dbh, $variable)            if $filename eq 'mail_confirmation.html';
        eprint::admin_marketing::mailinglistmembers($r, $log, $dbh, $variable)  if $filename eq 'mail.html';
        eprint::admin_marketing::view_email($r, $log, $dbh, $variable)          if $filename eq 'view_email.html';

		use eprint::admin_mail;
        eprint::admin_mail::handler($r, $log, $dbh, $variable)       			if $filename eq 'mailing_database.html';

    } 
    elsif ($sub_section eq 'support' ) {
        eprint::employee_support::helpdesk($r, $log, $dbh, $variable)         if $filename eq 'helpdesk.html';
        eprint::employee_support::helpdesk_search($r, $log, $dbh, $variable)  if $filename eq 'helpdesk_search.html';
        eprint::employee_support::rma($r, $log, $dbh, $variable)              if $filename eq 'return.html';
        eprint::employee_support::rma_search($r, $log, $dbh, $variable)       if $filename eq 'returns.html';
    }

    return;
}


sub section_main {
    my ($r, $log, $dbh, $variable, $cookie, $uri, $sub_section, $filename) = @_;
    my $status;

    require eprint::credit_application;
    require eprint::reseller_application;
    require eprint::customer;
    require eprint::order;
    require eprint::quote;
    require eprint::support;
    require eprint::print_project;    
    require eprint::print;
    require eprint::inventory;
    require eprint::docket;
    require eprint::project_files;
    require eprint::shopping_list;
print STDERR "MAIN -- SUB : $sub_section file: $filename \n";
   
    if ($sub_section eq 'account') {
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
    } 
    elsif ($sub_section eq 'order') {
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

    } 
    elsif ($sub_section eq 'quote') {
        eprint::quote::finalise_quote($r, $log, $dbh, $cookie, $variable)   if $filename eq 'confirmation_make_quote.html';
        eprint::quote::generate_quote($r, $log, $dbh, $cookie, $variable)   if $filename eq 'quote_details.html';
        eprint::quote::show_quote($r, $log, $dbh, $variable)                if $filename eq 'quote_history_details.html';
        eprint::quote::quote_history($r, $log, $dbh, $variable)             if $filename eq 'quote_history.html';
        eprint::quote::user_quote_info($r, $log, $dbh, $cookie, $variable)  if $filename eq 'quote_info.html';
        eprint::quote::show_quote($r, $log, $dbh, $variable)                if $filename eq 'quote_printer_friendly.html';
        eprint::quote::submit_quote($r, $log, $dbh, $cookie, $variable)     if $filename eq 'quote_submit.html';
    } 
    elsif ($sub_section eq 'support') {
        eprint::support::userinfo($r, $log, $dbh, $variable)  if $filename eq 'support_help_desk.html';
        eprint::support::helpdesk($r, $log, $dbh, $variable)  if $filename eq 'confirmation_help_desk.html';
        eprint::support::userinfo($r, $log, $dbh, $variable)  if $filename eq 'support_returns.html';    
        eprint::support::rma($r, $log, $dbh, $variable)       if $filename eq 'confirmation_returns.html';
    } 
    elsif ($sub_section eq 'products') {
        require eprint::ProductGroup;

        $status = eprint::ProductGroup::display_category($r, $dbh, $variable) if $filename eq 'display.html';
        $status = eprint::ProductGroup::select_project($r, $dbh, $variable)   if $filename eq 'select.html';
		eprint::qprice::upload($r, $dbh, $variable)							  if $filename eq 'upload_complete.html';
    }
    elsif ($sub_section eq 'dashboard') {

	use eprint::dashboard;
	my $param;
       	map { $param->{$_} = $r->param($_) } $r->param();

        eprint::dashboard::display($variable, $param) if $filename eq 'dashboard.html';

	}
    elsif ($sub_section eq 'proj') {

        if ($filename eq 'dispatch.html') {
            # TODO Set the headers and return the redirect in dispatch().
            my $location
                = eprint::print_project::dispatch($r, $log, $dbh, $cookie, $variable);

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
		use eprint::admin_reports;
        eprint::admin_reports::inventory_usage($r, $log, $dbh, $variable)          if $filename eq 'inventory_reports.html';
        eprint::admin_reports::template_data($r, $log, $dbh, $variable)            if $filename eq 'template_data.html';

		use eprint::Service::Shipping;
        eprint::Service::Shipping::import_export($r, $log, $dbh, $variable)        if $filename eq 'import_export.html';

        # View the project (pricing).
        if ( $filename eq 'proj_view.html' ) {

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
        $status = eprint::docket::display($r, $log, $dbh, $variable, undef, undef, undef, 1)       if $filename =~ /^(?:proj_)?docket(?:_printer_friendly|_custom)?.html/;
        $status = eprint::docket::comment($r, $log, $dbh, $variable)       if $filename eq 'docket_comment.html';

        eprint::print_project::project_notification($r, $dbh, $variable)          if $filename eq 'project_notification.html';

        if ($filename eq 'shipping_labels.html'){
            require eprint::Service::Shipping;
            eprint::Service::Shipping::print_labels($r, $log, $dbh, $variable, $r->param('ServiceIndex'));
        }
    }
    elsif ($sub_section eq 'supplier') {
        require eprint::rfq;
        eprint::rfq::rfq_list($r, $dbh, $variable) if $filename eq 'rfq_history.html';
        eprint::rfq::bid_history($r, $dbh, $variable) if $filename eq 'bid_history.html';
        eprint::rfq::display_rfq($r, $dbh, $variable) if $filename eq 'display_rfq.html';
        eprint::rfq::process_rfq($r, $log, $dbh, $variable, 1)                if $filename eq 'purchase_order.html';
        eprint::rfq::process_rfq($r, $log, $dbh, $variable, 1)                if $filename eq 'purchase_order_printer_friendly.html';
print STDER "MY FILENAME: $filename \n";
    
    }
    elsif ($sub_section eq 'rfq') {
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
    }
    elsif ($sub_section eq 'files') {
        eprint::project_files::ftp_folder($r, $dbh, $variable)          if $filename eq 'folders.html';
        eprint::project_files::ftp_file($r, $dbh, $variable)           	if $filename eq 'files.html';
    
    }
    elsif ($sub_section eq 'shopping_list') {
      eprint::shopping_list::list($r, $dbh, $variable) if $filename eq 'shopping_lists.html';
      eprint::shopping_list::get($r, $dbh, $variable) if $filename eq 'shopping_list.html';
    }
    elsif ($sub_section eq 'ecommerce') {
    	eprint::products::display($r, $dbh, $variable) if $filename eq 'products.html';
    	eprint::products::details($r, $dbh, $variable) if $filename eq 'product_details.html';
    	eprint::products::design($r, $dbh, $variable, $cookie) if $filename eq 'design.html';
	}

	menu_options($dbh, $variable);
    
    
print STDERR "CHECK ASR " . $r->param('run_asr') . "-- \n";
	if ( $r->param('asr') eq 'mailing' ) {
		use eprint::mailing;
		eprint::mailing::handler($r, $dbh, $variable);
	};

    return $status;
}

sub menu_options {
	my ( $dbh, $var) = @_;

	my $cats = PQS::model::categories::get_all();

	#map { push @{$var->{prod_menu}}, $cats->{$_}; } sort keys $cats;
	map { push @{$var->{prod_menu}}, $cats->{$_}; } sort keys $cats;
	
	

#	print STDERR "HAVE CATS: ", Dumper($var->{prod_menu}, $cats);
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

print STDERR "HAVE ORDER: $order_id PID: $pid - $var->{user_id} \n";

}

1;
