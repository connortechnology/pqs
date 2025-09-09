use strict;
package openprint::www;
use utf8;
use open ( ':encoding(UTF-8)', ':std' );

use constant Debug => 1;

#use Benchmark;
#use diagnostics;

use Apache2::Request ();
use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::Connection ();
use Apache2::RequestUtil ();
use APR::URI ();
use Apache2::Const -compile => qw(REDIRECT HTTP_INTERNAL_SERVER_ERROR OK DECLINED HTTP_NOT_FOUND HTTP_FORBIDDEN);# Offers OK, Error,etc for web server.
use Apache2::Log ();
use Time::HiRes qw{ time gettimeofday tv_interval }; 

require openprint::login;
require openprint::usergroup;
require openprint::Page_Setting;

require sql;
require openprint::misc;
require openprint::ssi;
require configuration;

require openprint::Object;
require openprint::Currency;
require openprint::Authorization;
require openprint::pricing;
require openprint::service;

require openprint;
use vars qw( $r %variable %session %param %config $log $dbh $starttime );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

sub warn {
	$r->log->error('Warning: '.$_[0]);
}

sub cleanup {
	if ( $r->connection->aborted( ) ) {
		$log->debug('Was aborted');
    #} elsif ( Debug ) {
    #$log->debug('cleanup');
	} # end if
	%openprint::variable = ();
	%openprint::param = ();
	if ( $dbh ) {
		$session{lastupdated} = time;
		untie %session;
    %openprint::page_session = ();
		openprint::pricing::clear_cache();
		openprint::service::init_cache();
		$openprint::Service::cached = 0;
		$openprint::Material::cached = 0;
		openprint::Object::init_cache();
		if ( ! $dbh->{AutoCommit} ) {
			$log->error('Uncommited transaction');
      #} elsif ( Debug ) {
      #$log->debug('Finished cleanup');
		} # end if
		$dbh->disconnect();
    $dbh = undef;
	} else {
		$log->debug('No dbh at cleanup');
	} # end if
} # end sub cleanup

sub handler {
	my $request = shift;
	$r = Apache2::Request->new( $request );
	$log	= $r->log;
  $SIG{__WARN__} = \&warn;

	# Don't do any caching.	This makes the back button not work.
	$r->no_cache(1);

	$starttime = gettimeofday();
	$log->debug( "Beginning of Request: $ENV{HTTP_USER_AGENT} Page: " . $r->uri() );

	$request->push_handlers(PerlCleanupHandler => \&cleanup);
	my $page = $r->uri();
	$log->debug('Beginning of Request: Page: '.$page);

	%param = ();
	# Here we copy the param data into a hash that is sligthly more useful to use.	Wish we didn't have to do this.
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
	}	# end foreach

	$dbh = sql::open_sql( $log, 
			database	=> $r->dir_config('db_name'),
			driver		=> $r->dir_config('db_driver'), 
			host		  => $r->dir_config('db_host'),
			port		  => $r->dir_config('db_port'),
			login		  => $r->dir_config('db_user'),
			password	=> $r->dir_config('db_password'),
			);

	my $lastpage = '';

	# This one has to go here, because it loads data, the others clear data, so they can go after the requires
	configuration::init( $r->dir_config() );
	openprint::session_init();
	openprint::usergroup::init_cache();
	if ( $dbh ) {

    if ( !$session{user_id} and !openprint::User->find_one(type=>'A') ) {
      if (!openprint::Company->find_one()) {
        $page = '/administrator/managerial/company_profiles.html';
      } else {
        $page = '/administrator/managerial/user_profiles.html';
      }
			$session{user_type} = 'A';
		} else {

			my $PageSetting = openprint::Page_Setting::get( $page );
			$PageSetting = new openprint::Page_Setting() if ! $PageSetting;
			$variable{PageSetting} = $PageSetting;

      # determine if they are allowed to see this page or not.
			if (!$PageSetting->can_view()) {
        openprint::login::save_destination();
				$log->debug('No good, need login');
				if ($page =~ /^.*\/_/) {
					$r->content_type(q{text/javascript; charset=utf-8});
					$r->print( q`window.location='/error/error_login.html';` );
					return Apache2::Const::OK;
				} else {
					if ($page =~ /employee/) {
						$page = '/employee/account/login.html';
					} else {
						$page = '/error/error_login.html';
					} # end if
				} # end if
				$variable{Destination} = openprint::misc::get_destination( $r, $r->uri() );
#$r->headers_out->set(Location=>'/error/error_login.html');
#$r->status(Apache2::Const::REDIRECT);
			} # end if
		} # end if

		foreach my $o ( split(',', $config{Cached_Objects} ) ) {
      eval {
        ('openprint::'.$o)->init_cache();
      };
		} # end foreach

		# Just does timeout
		openprint::login::verify_user( $r, $log, $dbh, $session{_session_id}, \%variable );
		$page = $variable{Redirect} if $variable{Redirect};	

		while ( $page and $lastpage ne $page ) {
			# This is for loop detection
			$lastpage = $page;
			$variable{uri} = $page;
			parse_page($page);
			if ( (exists $variable{Redirect}) and $variable{Redirect} ) {
				$openprint::log->debug("Redirect: $variable{Redirect}");
				$page = $variable{Redirect};
				$variable{Redirect} = '';
			} # end if
		} # end while
	} # end if
  return output($page, $lastpage);
} # end sub handler

sub output {
  my $page = shift;
  my $lastpage = shift;

	if ( ! $variable{Download} ) {
		if ( $lastpage =~ /\.html/ ) {
			$r->content_type(q{text/html; charset=utf-8});
		} elsif ( $lastpage =~ /\.json/ ) {
			$r->content_type(q{application/json; charset=utf-8});
		} elsif ( $lastpage =~ /\.xml/ ) {
			$r->content_type(q{text/xml; charset=utf-8});
		} elsif ( $lastpage =~ /\.rss/ ) {
			$r->content_type(q{application/rss+xml; charset=utf-8});
		} # end if
	} # end if

	if ( $variable{ExternalRedirect} ) {
		foreach my $key ( 'error', 'warning', 'information' ) {
			if ( $variable{$key} ) {
				$session{$key} = $variable{$key};
			} # end if
		} # end foreach

    my $redirect = $variable{ExternalRedirect};
    if ($config{url_base} and ($variable{ExternalRedirect} =~ /^\/administrator/) and ($variable{ExternalRedirect} !~ /^$config{url_base}/)) {
      $redirect = $config{url_base}.$variable{ExternalRedirect};
    }

    $r->headers_out->set(Location=>$redirect);
		$r->status(Apache2::Const::REDIRECT);
		#$r->send_http_header;
		$log->debug('Redirecting to ' . $redirect );
	} elsif ( exists $variable{Download} and $variable{Download} ) {
		if ( ref $variable{Download} eq 'ARRAY' ) {
			foreach ( @{$variable{Download}} ) {
				$r->print( $_ );
			}
		} else {
			$r->print( $variable{Download} );
		}
	} else {
		$variable{SiteTitle} = $config{SiteTitle};
		$variable{siteURL} = $config{siteURL};
		$variable{SecureSiteURL} = $config{SecureSiteURL} ? $config{SecureSiteURL} : $variable{siteURL};
		$variable{PageTitle} = $config{SiteTitle} .' - ' . $page;

	#$log->debug( "Before loading content: ($page) Elapsed time: " . sprintf('%.4f', tv_interval([$starttime])*1000).' usecs' );
		if ( ! exists $variable{PageContent} ) {
			my $content;
			if ( -e ( my $path = join('/', $config{SkinPath}, 'html', $page )) ) {
				$content = openprint::misc::load_file( $log, $path );
				if ( ! $content ) {
					$log->error("Found no content at $path");
				} # end if
			} elsif ( -e ( my $path = join('/', $config{SkinPath}, $page )) ) {
        $log->error("Deprecated SkinPath layout! $path");
				$content = openprint::misc::load_file( $log, $path );
				if ( ! $content ) {
					$log->error("Found no content at $path");
				} # end if
			} elsif ( -e $ENV{DOCUMENT_ROOT} . $page ) {
				$content = openprint::misc::load_file( $log, $ENV{DOCUMENT_ROOT} . $page );
				if ( ! $content ) {
					$log->error("Found no content at $ENV{DOCUMENT_ROOT}$page instead of $config{SkinPath}/$page");
				} # end if
      } else {
        $log->debug("Path not found $page at ". $ENV{DOCUMENT_ROOT} . $page);
			} # end if
			$variable{PageContent} = $content;
		} else {
$log->debug("PageContent is $variable{PageContent}");
		} # end if
		my $template;
		my @page_path = split('/', $page);
		my $filename = pop @page_path;
		# _ signifies a page fragment, so don't load layout
		if ( substr($filename, 0, 1) ne '_' ) {
			my $file = join('/', $config{SkinPath}, 'layouts', @page_path, $filename);
			#$log->debug("Looking for $file");
			if ( -e $file ) {
				$template = openprint::misc::load_file( $log, $file );
        $log->debug('Found template at '.$file) if Debug;
			} else {
        while ( @page_path ) {
          $file = join('/', $config{SkinPath}, 'layouts', @page_path, 'default.html');
          if ( -e $file ) {
            $template = openprint::misc::load_file($log, $file);
            last;
          } # end if
          pop @page_path;
        } # end while
			} # end if
		} # end if _
		$log->debug("After finding template: ($page) Elapsed time: " . sprintf('%.4f', tv_interval([$starttime])*1000).' usecs') if Debug;

    if ($config{CSP}) {
      $config{CSP_NONCE} = '';
      my @chars = ('A'..'Z', 'a'..'z', '0' .. '9');
      $config{CSP_NONCE} .= $chars[rand @chars] for 1 .. 16;
      $r->headers_out->{'Content-Security-Policy'} = "script-src 'unsafe-inline' 'unsafe-eval' 'self' $config{CSP} nonce-$config{CSP_NONCE}";
    }

		local $|=1;
		if ( ! $r->connection()->aborted() ) {
			if ( $template ) {
#$log->debug("parsing template! $template");
				$r->print( openprint::ssi::variable_substitution( \$template, \%variable ) );
			} else {

#$log->warn("No template!" . $r->content_type());
				$variable{PageContent} = openprint::ssi::variable_substitution( \$variable{PageContent}, \%variable ) if $variable{PageContent} ne '';
				$log->warn('Content: '.$variable{PageContent}) if Debug;
$log->debug( "Before printing: ($page) Elapsed time: " . sprintf('%.4f', tv_interval([$starttime])*1000).' usecs' . length( $variable{PageContent} ) ) if Debug;
				$r->print( $variable{PageContent} );
$log->debug( "After printing: ($page) Elapsed time: " . sprintf('%.4f', tv_interval([$starttime])*1000).' usecs' ) if Debug;
			} # end if
		} else {
			$log->debug('Aborted');
		} # end if
	} # end if

	$log->debug('Elapsed seconds: ' . sprintf('%.4f', tv_interval([$starttime])*1000).' usecs');
	return Apache2::Const::OK;
} # end sub handler

sub call_mod_for_uri {
  my $uri = shift;

	# This deals with things like /account/login.html//balhblahblah.php
	my ($real_uri) = $uri =~ /^\/openprint\/([^\.]+\.[^\.]+)/i;
	my @thing = split( '/', ($real_uri?$real_uri:$uri));
  shift @thing while $thing[0] eq 'openprint' or ! $thing[0];
  $openprint::log->debug("URI: $uri real:$real_uri thing:@thing");
	my $filename = pop @thing;
	my @path = @thing;
	my $first = shift @thing if @thing;
	my $first = shift @thing if @thing and !$first;
	my $second = shift @thing if @thing;
	my $third = shift @thing if @thing;
	my $fourth = shift @thing if @thing;
  $log->debug("url $uri First: $first Second: $second Third: $third Filename: $filename");

  if ( -e $ENV{DOCUMENT_ROOT}.$uri or -e $ENV{DOCUMENT_ROOT}.'/openprint'.$uri ) {
    my ( $proc ) = $filename =~ /^(.*)\.(html|json|xml|rss)$/;
    if ( $proc ) {
      my $module = join('_', map { lc $_ } @path);
      #$module .= '_'.$second if $second;
      $log->debug("Module is $module");
      eval {
        require "openprint/$module.pm"; 
        if ( my $function = ('openprint::'.$module)->can($proc) ) {
          $function->($r, $log, $dbh, \%variable);
          $log->debug("calling of require $module :: $proc, filename is $filename");
        } else {
          $log->error("Eval error of require $module :: $proc, can't do function");
        }
      };
      $log->error( "Eval error of require $module Reason: " . $@ ) if $@;
    } else {
      $log->error("No proc in filename $uri");
    } # end if
  } else {
    $log->debug("No firstSo or non-existant $uri first: $first ");
  } # end if
}

sub parse_page {
	my $uri = shift;
	my $status;

	# This deals with things like /account/login.html//balhblahblah.php
	my ($real_uri) = $uri =~ /^\/openprint\/([^\.]+\.[^\.]+)/i;
	my @thing = split( '/', ($real_uri?$real_uri:$uri));
  shift @thing while ($thing[0] eq 'openprint' or ! $thing[0]) and @thing;
  $openprint::log->debug("URI: $uri real:$real_uri thing:@thing");
	my $filename = pop @thing;
	my @path = @thing;
	my $first = shift @thing if @thing;
  #$first = shift @thing while $first eq '' or $first eq 'openprint' and @thing;
	my $second = shift @thing if @thing;
	my $third = shift @thing if @thing;
	my $fourth = shift @thing if @thing;
  $log->debug("url $uri First: $first Second: $second Third: $third Filename: $filename");

	if ( $filename eq 'getfile.html' ) {
		my $sourceDir = $config{ProjectFilesPath} . handlers::upload::get_destdir();
		$variable{Download} = openprint::misc::load_file( $log, $sourceDir.$param{path}.'/'.$variable{Download});
		$r->headers_out->{'Content-Disposition'} = "attachment; filename=\"$param{filename}\"";
		$r->content_type( "application/octet-stream; name=\"$param{filename}\"" );
		return;
	} elsif ( $first eq 'administrator' ) {
		$status = Apache2::Const::OK;

		# This needs special treatment.
		if ( $filename eq 'login_confirmation.html' ) {
			openprint::login::verify_login( $r, $log, $dbh, $session{_session_id}, \%variable, 'A' );
			return $status if $variable{Redirect};	
		} # end if

		if ( $second eq 'account' ) {
			if ( $filename eq 'logout.html' ) {
				openprint::login::logout( $log, $dbh, \%variable, $session{_session_id}, 'A' );
			} # end if
			openprint::login::email_password( $r, $log, $dbh, \%variable )			if $filename eq 'password_confirmation.html';
		} elsif ( $first ) {
			my ( $proc ) = $filename =~ /(.*)\.\w*$/;
			if ( $proc ) {
				my $module = join('_',@path);
				eval {
					require "openprint/$module.pm";
					('openprint::'.$module)->$proc( $r, $log, $dbh, \%variable );
				};
				$log->error( "Eval error of require $module :: $proc, Reason: " . $@ ) if $@;
			} # end if
		} # end if		

	} elsif ( $first eq 'employee' ) {
		if ( $second eq 'proj' ) {
			if ( $param{docket} ) {
				$param{docket} = openprint::Project->transform(docket=>$param{docket});
				my @Projects = openprint::Project->find(docket=>$param{docket});
				if ( !@Projects ) {
					$variable{error} ='No projects found for docket ' . $param{docket}.'<br/>';
					return;
				} elsif ( @Projects > 1 ) {
					$variable{error} ='Multiple projects found for docket ' . $param{docket}.'<br/>';
					my $rowclass = '';
					foreach my $Project ( @Projects ) {
						$variable{error} .= qq`<div$rowclass><a href="$variable{uri}?project_id=$$Project{id}">$$Project{id}</a> $$Project{reference}</div>`; 
						$rowclass = $rowclass ? '' : ' class="colRow"';
					}
					return;
				}
				$param{ProjectIndex} = $Projects[0]->id();
			} elsif ( $param{project_id} ) {
				$param{ProjectIndex} = $param{project_id};
			}

			require openprint::print;
			require openprint::print_project;
			require openprint::employee_production;

			@variable{'ProjectIndex','ServiceIndex','OrderID'} = @param{'ProjectIndex','ServiceIndex','OrderID'};
			
			my $Project = $variable{Project} = new openprint::Project($variable{ProjectIndex});
			@variable{'ddmDueDate','OrderedQuantityIndex'} = ( $variable{Project}->due_date(), $variable{Project}->ordered_quantity_index() );
			$variable{QTYIndex} = $variable{OrderedQuantityIndex};
			$variable{DocketNumber} = $variable{Project}->docket();

			$variable{Employee} = $openprint::User->name();
			if ( $variable{ServiceIndex} ) {
				$variable{Service} = $variable{Project}->Service($variable{ServiceIndex});
			}
			
			if ( $filename eq 'proofs.html' or $filename eq 'FilmStripping.html' ) {
				if ( ! $param{ServiceIndex} ) {
					my $services = $Project->services();
					if ( $$services{Proofs} ) {
						$variable{ServiceIndex} =	$param{ServiceIndex} = $$services{Proofs}[0];
					} else {
						$variable{error} .= 'No Proofs service found in project ' . $Project->id() . '<br/>';
						return;
					}
				}
			}
			openprint::print_project::get_service_specifications( $r, $log, $dbh, \%variable, @param{'ProjectIndex','ServiceIndex'} ) if $param{ServiceIndex} and $filename ne 'multipage_signatures.html';

			#if ( $third eq 'prin' ) {	
				my ( $proc ) = $filename =~ /(.*)\.\w*$/;
				if ( $proc ) {
					my $module = join('_',@path);
					eval {
						require "openprint/$module.pm";
						if ( my $function = ('openprint::'.$module)->can('init') ) {
							$log->debug("Running openprint::$module->init") if Debug;
							$function->($r, $log, $dbh, \%variable);
						} else {
							$log->debug('No function for init') if Debug;
						}
						if ( my $function = ('openprint::'.$module)->can($proc) ) {
							$log->debug("Running openprint::$module->$proc") if Debug;
							$function->($r, $log, $dbh, \%variable );
						} else {
							$log->warn("No function for $proc");
						}
					}; # end eval
					$log->error("Eval error of require $module :: $proc, Reason: $@") if $@;
				} # end if proc
			#} # end if prin
		} else {
      call_mod_for_uri($uri);
		} # end if
	} elsif ( $first and sets::isin($first, ['content', 'account']) ) {
		my ( $proc ) = $filename =~ /(.*)\.\w*$/;
		if ( $proc ) {
			my $module = join('_',@path);
			require "openprint/$module.pm";
			$log->debug("Calling $module :: $proc");
			if ( my $function = ('openprint::'.$module)->can($proc) ) {
				$function->($r, $log, $dbh, \%variable );
			} else {
				$log->error( "Eval error: $module cant $proc, Reason: " );
			}
		} # end if
	} elsif ( $first eq 'main' ) { # main
		if ( $second eq 'project' ) {
      openprint::pricing::init_cache();
			require openprint::print;
			require openprint::print_project;

      # eprint support
      $param{ServiceIndex} = $param{sid} if !$param{ServiceIndex} and $param{sid};
      $param{ProjectIndex} = $param{pid} if !$param{ProjectIndex} and $param{pid};

			if ( ( defined $third ) or sets::isin($filename, ['Paper.html','Bundling.html','HStands.html']) ) {
				if ( $param{ServiceIndex} and ! $variable{ServiceIndex} ) {
					my @service_ids = split(',', $param{ServiceIndex} );
					$variable{ServiceIndex} = $service_ids[0];
				} # end if
				$variable{ProjectIndex} = $openprint::param{ProjectIndex} if ! $variable{ProjectIndex};
				$variable{ProjectIndex} = $openprint::param{project_id} if ! $variable{ProjectIndex};
				$variable{ProjectIndex} = $openprint::session{project_id} if ! $variable{ProjectIndex};
				my $Project = $variable{Project} = new openprint::Project( $variable{ProjectIndex} );
				my $Currency = openprint::Currency::get_current();
				@variable{'CurrencyName','CurrencySymbol'} = ( $Currency->name(), $Currency->symbol() );
				my $project_index = $variable{ProjectIndex};
				my $service_index = $variable{ServiceIndex};

				# Things like UPS Shipping might not actually have a service
				openprint::print::get_quantities( \%variable, $project_index );
				if ( $project_index and $service_index ) {
					my $Service = $variable{Service} = $variable{Project}->Service( $service_index );
					if ( !$Service->service_id() ) {
						$variable{error} .= 'Unable to load data for service. Perhaps it was removed.<br/>';
						$variable{ExternalRedirect} = $Project->url_to();
					} else {
						my $specs = $Service->specs();
						@variable{keys %$specs} = values %$specs;
						$variable{ServiceType} = $Service->ServiceType();
						@variable{'ServiceTypeID','ServiceTypeName','ServiceTypeType'} = $variable{ServiceType}->get('name','description','type') if $variable{ServiceType};
					} # end if
				} # end if project_id and service_id
				$variable{ProjectType} = $variable{Project}->Type();
				# This could happen if the ServiceSpecs clobbered it
				if ( ! $variable{ServiceIndex} ) {
					$variable{ServiceIndex} = $service_index;
				} # end if

				if ( $third eq 'prin' ) {
					$log->debug("** START OF MAIN:PROJ:PRIN * ($project_index) ($service_index)");
					if ( $filename eq 'multipage_signatures.html' ) {
						$status = openprint::print::print_prices( $r, $log, $dbh, $session{_session_id}, \%variable );
					} elsif ( $filename eq 'prin_multi.html' ) {
						$status = openprint::print::publication_pages( $r, $log, $dbh, \%variable );
					} elsif ( $filename eq 'ScratchPads.html' ) {
						$status = openprint::print::publication_pages( $r, $log, $dbh, \%variable );
					} elsif ( $filename =~ /^(.*)\.(html|json)$/ ) {
						my $proc = $1;
						my $module = join('_', @path);
						require 'openprint/'.$module.'.pm';
						if ( my $function = ('openprint::'.$module)->can($proc) ) {
							$function->($r, $log, $dbh, \%variable );
						} else {
							$log->debug("$module :: $proc is not a function");
						}
						$status = openprint::print::print_prices( $r, $log, $dbh, $session{_session_id}, \%variable );
					} else {
						$status = openprint::print::print_prices( $r, $log, $dbh, $session{_session_id}, \%variable );
					} # end if
				} elsif ($third eq 'prep') {

					if ( $filename eq 'scanning.html' ) {
						require openprint::Estimating::Scanning;
						openprint::Estimating::Scanning::display( $log, $dbh, \%variable, $project_index, $service_index );
					} elsif ( $filename eq 'proofs.html' ) {
						require openprint::Estimating::Proofs;
						openprint::Estimating::Proofs::display($log, $dbh, \%variable, $project_index, $service_index);
					} # end if

				} elsif ($third eq 'bind') {
					if ( $filename eq 'folding.html' ) {
						require openprint::Estimating::Folding;
						openprint::Estimating::Folding::display( $log, $dbh, \%variable, $project_index, $service_index );
					} elsif ( $filename eq 'cutting.html' ) {
						require openprint::Estimating::Cutting;
						openprint::Estimating::Cutting::display( $log, $dbh, \%variable, $project_index, $service_index );
					} elsif ( $filename eq 'perforating.html' ) {
						require openprint::Estimating::Perforating;
						openprint::Estimating::Perforating::get_specs( $log, $dbh, \%variable, $project_index, $service_index );
					} elsif ( $filename eq 'scoring.html' ) {
						openprint::Estimating::Scoring::get_specs( $log, $dbh, \%variable, $project_index, $service_index );
					} elsif ( $filename eq 'stitching.html' ) {
						require openprint::Estimating::Stitching;
						openprint::Estimating::Stitching::display( $log, $dbh, \%variable, $project_index, $service_index );
					} elsif ( $filename eq 'drilling.html' ) {
						require openprint::Estimating::Drilling;
						openprint::Estimating::Drilling::display( $log, $dbh, \%variable, $project_index, $service_index );
					} elsif ( $filename eq 'collating.html' ) {
						require openprint::Estimating::Collating;
						openprint::Estimating::Collating::display( $log, $dbh, \%variable, $project_index, $service_index );
					} elsif ( $filename =~ /^(\w*).html$/ ) {
						my $module = $1;
						$module = $variable{ServiceType}->type() if $variable{ServiceType} and $variable{ServiceType}->type();
              
            eval {
              require "openprint/Estimating/$module.pm";
              if ( my $function = ('openprint::Estimating::'.$module)->can('display') ) {
                $function->($log, $dbh, \%variable, $project_index, $service_index );
              } else {
                $log->error( "Eval error of require(bind) openprint::Estimating::$module display() :: Reason: $?" );
              }
            };
						$log->error( "Eval error of require $module Reason: " . $@ ) if $@;

					} # end if
				} elsif ($third eq 'spec') {
					if ( $filename =~ /^(\w*).html$/ ) {
            my $module = $1;
            eval {
              require "openprint/Estimating/$module.pm";
              if ( my $function = ('openprint::Estimating::'.$module)->can('display') ) {
                $function->($log, $dbh, \%variable, $project_index, $service_index );
              } else {
                $log->error("No display function for $module");
              }
						};
						$log->error( "Eval error of require $module Reason: " . $@ ) if $@;
					} # end if
				} elsif ($third eq 'pack') {
					if ( $filename eq 'pack_by_weight.html' ) {
						openprint::Estimating::Skids::display( $log, $dbh, \%variable, $project_index, $service_index );
					} elsif ( $filename eq 'pack_by_quantity.html' ) {
						require openprint::Estimating::ShrinkWrapping;
						openprint::Estimating::ShrinkWrapping::display( \%variable, $variable{Project}, $service_index );
					} # end if
				} elsif ($third eq 'shipping') {
		
					if ( $filename =~ /^(\w*).html$/ ) {
						my $module = $1;
						eval {
							$log->debug("Require $module");
							require "openprint/Estimating/$module.pm";
							if ( my $function = ("openprint::Estimating::$module")->can( 'display' ) ) {
								$function->( $project_index, $service_index, \%variable );
							} else {
								$log->debug("No display function $module.pm");
							}
						}; 
						$log->error( "Eval error of require $module Reason: " . $@ ) if $@;
					} else {
            call_mod_for_uri($uri);
					}
				} # end if main:project:$third
			} else {
        call_mod_for_uri($uri);

				openprint::print_project::view_pdfs( $r, $log, $dbh, \%variable )				if $filename eq 'proj_view_pdf.html';
				openprint::print_project::summary( $r, $log, $dbh, \%variable )					if $filename eq 'docket_sheet.html';
			} # end if defined third
		} else {
      call_mod_for_uri($uri);
		} # end if main:$second

  } else {
    call_mod_for_uri($uri);
	} # end if $first

	return $status;
}


1;
__END__
