package openprint::main_project;
use strict;
use warnings;
use openprint ();
use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

require openprint::Project;
require openprint::print_project;
require openprint::service;
require JSON;

sub sign_off {
	require Authen::Captcha;
	if ( $param{btnFunction} eq 'Approve Project' ) {
		my $Captcha = new Authen::Captcha(
				data_folder => $config{SkinPath}.'/tmp',
				output_folder => $config{SkinPath}.'/images/captcha'
				);
		if ( 1 == $Captcha->check_code( $param{Captcha}, $param{MD5SUM} ) ) {
			$variable{Approved} = 1;
			# Transitions from Waiting for Customer Approval to Waiting for QA Approval
			#eprint::project::set_status( $log, $dbh, $variable, $param{'ProjectIndex'), 'Waiting for QA Approval' };
			my $Project = new openprint::Project( $param{ProjectIndex} );
			my $services = $Project->services();
			my $proofs_service_index = $$services{Proofs} ? $$services{Proofs}[0] : $$services{FilmStripping}[0];

			my $name = $param{Name};
			my $when = sprintf('%.4d-%.2d-%.2d %.2d:%.2d:%.2d', Date::Calc::Today_and_Now() );
			$Project->add_to_log( @session{'company_id','user_id'}, "Client Approval by $name at $when" );
			openprint::service::insert_service_spec( $log, $dbh, $param{ProjectIndex}, $proofs_service_index, 'rdbClientApproved', 'Y' );
			openprint::service::insert_service_spec( $log, $dbh, $param{ProjectIndex}, $proofs_service_index, 'ClientApprovalDate', $when );
		} else {
			$variable{Name} = $param{Name};
			$variable{error} = 'Validation Code incorrect.	Please try again.';
			$variable{ExternalRedirect} = '/main/project/sign_off.html?ProjectIndex='.$param{ProjectIndex};
		} # end if
	} # end if
	$variable{ExternalRedirect} = '/main/project/view.html?ProjectIndex='.$param{ProjectIndex};
} # end sub sign_off

sub history {

	if ( $param{btnFunction} ) {
		if ( $param{btnFunction} eq 'Delete Project' ) {
			if ( $param{project_id} ) {
				foreach my $project_id ( ref $param{project_id} eq 'ARRAY' ? @{$param{project_id}} : $param{project_id} ) {
					$variable{error} .= openprint::print_project::try_to_delete_project( $log, $dbh, \%variable, $project_id );
				} # end foreach project_id
			} elsif ( $param{ProjectIndex} ) {
				$variable{error} .= openprint::print_project::try_to_delete_project( $log, $dbh, \%variable, $param{ProjectIndex} );
			} # end if
			$variable{ExternalRedirect} = '/main/project/history.html';
			return;
		} elsif ( $param{btnFunction} eq 'Reuse Project' ) {
			foreach my $project_id ( ref $param{project_id} eq 'ARRAY' ? @{$param{project_id}} : $param{project_id} ) {
				openprint::print_project::reuse_project( $project_id );
			} # end if
			$variable{ExternalRedirect} = '/main/project/history.html';
			return;
		} elsif ( $param{btnFunction} eq 'Reset' ) {
			foreach my $k ( keys %session ) {
				if ( $k =~ /^\/main\/project\/history.html/ ) {
					delete $session{$k};
				} # end if
			} # end foreach k
			%param = ();
		} # end if
	} # end if btnfunction

	# Doing it here will set the defaults if neccessary, but then they will get overriden by the saev_params below.	This is neccessary because save_params will update lastupdated.
	ssi::setup_date_select( '/main/project/history.html', 'created_on_start', -180 );
	ssi::setup_date_select( '/main/project/history.html', 'created_on_end', 0 );
	ssi::setup_date_select( '/main/project/history.html', 'updated_on_start', -14 );
	ssi::setup_date_select( '/main/project/history.html', 'updated_on_end', 0 );
	if ( ! exists $session{'/main/project/history.html?ddmStatus'} ) {
		$session{'/main/project/history.html?ddmStatus'} = join(',', ( 'uncalculated','Unordered','Pending Deposit','Ordered','In Prepress','Proofs Out','Waiting For Customer Approval','Waiting For QA Approval','Approved','Printed','Complete','Waiting For Pickup','Picked Up','Shipped','Calculating' ) );
	} # end if
	if ( ! exists $session{'/main/project/history.html?company_id'} ) {
		$session{'/main/project/history.html?company_id'} = $session{company_id};
	} # end if

	_history();
} # end sub history

sub _history {
	ssi::save_params( '/main/project/history.html', 
			'ddmStatus', 'type_id', 'predefined', 'company_id', 'user_id', 'servicetype_id','salesrep_id',
			'reference', 'project_id',
			'created_on_start_year', 'created_on_start_month','created_on_start_day', 
			'created_on_end_year', 'created_on_end_month','created_on_end_day', 
			'updated_on_start_year', 'updated_on_start_month','updated_on_start_day', 
			'updated_on_end_year', 'updated_on_end_month','updated_on_end_day', 
			);
} # end sub _history 

sub _update {
	my $project_id = $param{project_id} if $param{project_id} and ! $param{ProjectIndex};
	my $Project = $variable{Project} = new openprint::Project( $project_id );
	if ( $param{action} ) {
		if ( $param{action} eq 'update' ) {
			if ( $param{field} eq 'reference' ) {
				if ( ! $Project->save( { reference => $param{value} } ) ) {
					$variable{PageContent} = $Project->reference();
				} # end if successful save
			} #end if reference
		} # end if update
	} # end if action
} # end sub _update

sub view {
	my $project_id = $param{ProjectIndex};
	$project_id = $param{project_id} if $param{project_id} and ! $param{ProjectIndex};


  $session{ShowAllSignatures} = $param{ShowAllSignatures} if exists $param{ShowAllSignatures};
	$variable{ProjectIndex} = $project_id;
	my $Project = $variable{Project} = new openprint::Project($project_id);
	my $save = 0;

  if ( exists($param{quote_level}) and ( $param{quote_level} != $Project->style_id() ) ) {
    $Project->style_id( $param{quote_level} );
    $save = 1;
  } elsif ( ( ! $Project->style_id() ) and $openprint::User->quote_level() ) {
    # Set default
    $Project->style_id( $openprint::User->quote_level() );
    $save = 1;
  } # end if
  # A new project will have no quantities, so no quantity_indexes, so this is an error check
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		if ( $$Project{'price'.$qty_index} != $Project->price($qty_index,undef) ) {
      $log->error("Prices have changed in project $project_id");
			$save = 1;
			last;
		} # end if
	} # end foreach
	$Project->save() if $save;

	# I put these here because the don't need a project index
	if ( defined $param{btnFunction} ) {
		if ( $param{btnFunction} eq 'Save Project' ) {
			$log->debug("*** Time to Save Project - View Services Function ***");
			$project_id = openprint::print_project::create_edit_process( $r, $log, $dbh, \%variable );
			return if $variable{Redirect}; # Redirects on error
			$Project = new openprint::Project( $project_id );
			#my $services = $Project->services();
      # We already did recalc in create_edit_process... aug 6 2019
			# Display any resulting uncalculated services
			openprint::print_project::continue_project($Project);
			return if $variable{ExternalRedirect};
		} elsif ( $param{btnFunction} eq 'Delete Project' ) {
			$variable{error} .= openprint::print_project::try_to_delete_project( $log, $dbh, \%variable, $project_id );
			if ( ! $variable{error} ) {
				$variable{ExternalRedirect} = '/main/project/history.html';
				return;
			} # end if
		} elsif ( $param{btnFunction} eq 'Undelete Project' ) {
			my $Project = new openprint::Project( $project_id );
			$variable{error} .= $Project->undelete();
		} # end if
	} # end if defined btnFunction

	$project_id = $session{project_id} if ! $project_id;
	if ( ! $project_id ) {
		$variable{Project} = new openprint::Project();
		return;
	} # end if

	$Project = $variable{Project} = new openprint::Project( $project_id );
  return if !$$Project{id};
	my $services = $Project->services();
	my $Service = $Project->Service( $param{ServiceIndex} ) if $param{ServiceIndex};

	$log->debug(" **** STARTING VIEW SERVICES FUNCTION * Project $project_id( $$Project{id} ) *** $session{company_id}");

	# FIXME SHOULD USE can_edit
	if ( ( $Project->company_id() == $session{company_id} ) or sets::isin( $session{user_type}, ['E','A'] ) ) {

		if ( defined $param{btnFunction} ) {
			if ( $param{btnFunction} eq 'Export JDF' ) {
				misc::export( $r, $log, \%variable, 'Docket-'.$Project->docket().'.jdf', [$Project->jdf()->toString()] );
			} elsif ( $param{btnFunction} eq 'Make Predefined' ) {
				$Project->predefined( 1 );
				$variable{error} .= $Project->save();
			} elsif ( $param{btnFunction} eq 'Save Service' ) {
				# Update the 'current project'
				$session{project_id} = $project_id;
				$log->debug("** Save Service in View Services Function **");

				my $service_index = $param{ServiceIndex};
				if ( ! $Service ) {
					$variable{error} .= $param{ServiceType} . ' service ' . $service_index . ' is no longer in project. It may have been removed while you were editing it.  Your changes may not have been saved.<br/>';
					$variable{ExternalRedirect} = '/main/project/view.html?project_id='.$project_id;
					return;
				} # end if

				openprint::service::save_service( $r, $log, $dbh, $Project->id(), $service_index );
				my $new_status = $param{Status} ? $param{Status} : 'calculated';
				$Service->save({ status=>$new_status }) if (!$Service->status()) or ( ( $Service->status() ne $new_status ) and ( $Service->status() ne 'Completed' ) );

				if ( (!$Project->currency_id()) or ($Project->currency_id() != $openprint::Currency->id())) {
					$Project->add_to_log( @session{'company_id','user_id'}, 'Currency changed from '.$Project->Currency()->name() . ' to '. $openprint::Currency->name() );
					$Project->currency_id( $openprint::Currency->id() );
				} # end if

				$Project->lock();
        my $project_type = $Project->Type()->type();
        if ($project_type) {
          my $calc = ('openprint::Estimating::'.$project_type)->can('calc');
          if ($calc) {
            my $s = openprint::service::internal_calc( $log, $dbh, \%variable, $project_id, $$services{''}[0], $project_type);
            if ( $$s{Status} ne 'calculated' ) {
              $log->error("Error calculating Project service");
              # Don't want to redirect because it would be annoying.  Just go to view.
            } else {
              $calc = ('openprint::Estimating::'.$project_type)->can('calculate_signatures');
              $calc->($Project) if $calc;
            }
          } else {
            $log->error("No calc for $project_type");
          }
        } else {
          $log->error("Unable to determine project type");
        }
        #openprint::service::auto_calculate($Project, $service_index);
				$Project->update_status();
				$Project->unlock();
		
				$Project->summary(undef);
				$Project->save( { calculated_on => 'NOW()' } );
        $variable{ExternalRedirect} = $Project->url_to();
        #openprint::print_project::continue_project($Project);
				return if $variable{ExternalRedirect};
			} elsif ( $param{btnFunction} eq 'Modify Project' ) {
				my $service_name = $param{txtServiceName} ? $param{txtServiceName} : 'Adjustment';
				my $CurrentCurrency = openprint::Currency::get_current();
				my $ProjectCurrency = $Project->Currency();
				my $conversion_rate = $CurrentCurrency->conversions( $ProjectCurrency->id() );

				if ( my $ServiceType = openprint::ServiceType->find_one( name=>'CustomService' ) ) {
					my $service_id = $Project->add_service( $ServiceType, {
						( $param{txtPrice1} ? ( txtPrice1 => $conversion_rate * misc::moneyfilter($param{txtPrice1} ) ) : () ),
						( $param{txtPrice2} ? ( txtPrice2 => $conversion_rate * misc::moneyfilter($param{txtPrice2} ) ) : () ),
						( $param{txtPrice3} ? ( txtPrice3 => $conversion_rate * misc::moneyfilter($param{txtPrice3} ) ) : () ),
						ServiceName => $service_name }, { status=>'calculated' } );
 
					$Project->add_to_log( @session{'company_id','user_id'}, sprintf( 'Adding Custom Line: %s, (%s)', $service_name, join(',', map { $param{$_} ? $param{$_} : () } ('txtPrice1','txtPrice2','txtPrice3') ) ) );
        } else {
          $variable{error} .= "THere is no custom service in the system!<br/>";

				} # end if has Customer Service type

			} elsif ( $param{btnFunction} eq 'Delete Services' ) {
				foreach my $service_id ( ref $param{service_id} eq 'ARRAY' ? $param{service_id} : ( $param{service_id} ) ) {
					my $Service = $Project->Service( $service_id );
					$variable{error} .= $Service->delete();
					if ( $Service->Type()->name() eq 'Cutting' ) {
						if ( $$services{UVCoating} ) {
							openprint::service::internal_calc( $log, $dbh, \%variable, $project_id, $$services{UVCoating}[0], 'UVCoating' );
						} # end if
						if ( $$services{BulkSkids} ) {
							openprint::service::internal_calc( $log, $dbh, \%variable, $project_id, $$services{BulkSkids}[0], 'Skids' );
						} # end if
					} # end if
				} # end if
			} elsif ( $param{btnFunction} eq 'Recalculate Project' ) {
				if ( exists $param{markup} ) {
					$param{markup} =~ s/[^\d\.\-]//mg;
					$Project->markup( $param{markup} );
					$Project->save();
				} # end if
				$session{project_id} = $project_id;
				$Project->currency_id( $session{Currency_id} );
				$Project->recalculate();
				openprint::print_project::continue_project($Project);
				return if $variable{ExternalRedirect};
			} elsif ( $param{btnFunction} eq 'Continue Project' ) {
				$session{project_id} = $project_id;
				$Project->currency_id( $session{Currency_id} );
				$Project->recalculate();
				openprint::print_project::continue_project($Project);
				return if $variable{ExternalRedirect};
			} elsif ( $param{btnFunction} eq 'Reuse Project' ) {
				$project_id = openprint::print_project::reuse_project( $project_id );
				$Project = new openprint::Project( $project_id );
			} # end if
			if ( ! $variable{Redirect} ) {
				$Project->update_status();
				$variable{ExternalRedirect} = '/main/project/view.html?project_id='.$project_id;
				return;
			} # end if
		} # end if btnFunction defined
		if ( defined $param{remove} and ( $param{remove} ne '' ) ) {
			foreach my $s_id ( split(',', $param{remove} ) ) {
				my $PS = $Project->Service( $s_id );
				next if ! $PS->service_id();
				my $ServiceType = $PS->ServiceType();
				if ( sets::isin( $ServiceType->name(), ['Proofs'] ) and ( @{$$services{$ServiceType->name()}} == 1 ) ) {
					$variable{error} .= 'Proofs cannot be removed from the project.<br/>';
					next;
				} elsif ( ! $ServiceType->allow_delete() ) {
					$variable{error} .= $ServiceType->name() . ' cannot be removed from the project.<br/>';
					next;
				} # end if
				my $specs = $PS->specs();
				$variable{error} .= $PS->delete();
				if ( $ServiceType->name() eq 'Signature' ) {
					openprint::service::internal_calc( $log, $dbh, \%variable, $project_id, $$services{''}[0], $Project->Type()->type() );
				} elsif ( $ServiceType->name() eq 'Cutting' ) {
					if ( $$services{UVCoating} ) {
						openprint::service::internal_calc( $log, $dbh, \%variable, $project_id, $$services{UVCoating}[0], 'UVCoating' );
					} # end if
          if ( $$services{BulkSkids} ) {
            openprint::service::internal_calc( $log, $dbh, \%variable, $project_id, $$services{BulkSkids}[0], 'Skids' );
          } # end if
				} # end if
			} # end foreach s_id
			$session{project_id} = $project_id;
			$Project->summary(undef);
			$Project->save();
			$Project->update_status();
			$variable{ExternalRedirect} = '/main/project/view.html?project_id='.$Project->id();
		} elsif ( ( defined $param{calc} ) and $param{calc} ) {
			$log->debug("Recalculating $param{calc}");
			openprint::service::internal_calc( $log, $dbh, \%variable, $project_id, $r->param('calc') );
			$Project->summary(undef);
			$Project->save();
			$Project->update_status();
			$variable{ExternalRedirect} = '/main/project/view.html?project_id='.$project_id;
			return;
		} # end if

		if ( $param{ContinueProject} and $param{ContinueProject} ne 'Incomplete Form' ) {
			$log->debug('*** Continue Project called From View Services ( view.html ) Function ***');
			openprint::print_project::continue_project($Project);
		} # end if 
	} # end if can_edit
} # end sub view

sub _copy_popup {
} # end sub _copy_popup

sub create_edit {
	my $project_index = $param{ProjectIndex};

	my $Project = $variable{Project} = openprint::Project->find_one( id=>$project_index );
	if ( ! $Project ) {
		$Project = $variable{Project} = new openprint::Project();
		if ( $project_index ) {
			$variable{error} .= "Project $param{ProjectIndex} was not found.  A new Project will be created.<br/>";
		}
	}

	@variable{'txtProjectReference','ddmDesign','txtComments','txtQuantity1','txtQuantity2','txtQuantity3','rdbMode','chkPrograms','txtOtherPrograms'} = (
		$Project->reference(), $Project->design(), $Project->comments(), $Project->quantity1(), $Project->quantity2(), $Project->quantity3(), $Project->mode(), $Project->programs(), $Project->other_programs() 
	);

	my $services = $Project->services();
	@{$variable{SelectedServices}} = keys %{$services};
#$log->debug("Services: " . join(',',@{$variable{SelectedServices}}) );

	$variable{ProjectIndex} = $$Project{id};
} # end sub create_edit

sub _calc {
	if ( $param{ProjectIndex} and $param{action} ) {
		my $Project = new openprint::Project( $param{ProjectIndex} );
		if ( $param{ProjectIndex} and ! $$Project{id} ) {
			$log->debug("No project $param{ProjectIndex} found");
		}
		if ( $param{action} eq 'add_service' ) {
      my $services = $Project->services();
      foreach my $service_name ( ref $param{service_name} eq 'ARRAY' ? @{$param{service_name}} : split(',',$param{service_name}) ) {
        next if $$services{$service_name};
        $Project->add_service( $service_name );
      } # end foreach service_name
    } elsif ( $param{action} eq 'del service' ) {
      my $services = $Project->services();
      foreach my $service_name ( ref $param{service_name} eq 'ARRAY' ? @{$param{service_name}} : split(',',$param{service_name}) ) {
        next if ! $$services{$service_name};
        foreach ( @{$$services{$service_name}} ) {
          my $Service = new openprint::Project_Service( { project_id=>$$Project{id}, service_id=>$_ } );
          $Service->delete();
        } # end foreach service_id
      } # end foreach service_name
    } # end if
  } # end if
} # end sub _calc

sub calc {
	my $debug = @_ ? $_[0] : 1;
	my $Project = undef;
	if ( $param{ProjectIndex} ) {
		$Project = openprint::Project->find_one( id=>$param{ProjectIndex} );
	}
  $Project = new openprint::Project() if !$Project;
	my $service;
	if ( $param{ServiceIndex} ) {
		$service = $Project->Service( $param{ServiceIndex} );
    $log->debug("Get service from ServiceIndex".$service);
	}
	if ((!$service) and $param{ServiceType}) {
    $log->error("Reconstucting ServiceType");
		$service = new openprint::Project_Service();
		$service->set({ project_id=>$Project->id(), service_type=>openprint::ServiceType->transform(name=>$param{ServiceType}) } );
	}

  if (!($service and $service->service_type())) {
    $log->error("Unable to determine service type");
    return (alert=>'Unable to determine service type.');
  }
  my $module = $service->ServiceType()->module() || $service->service_type();
  $log->debug("$module from ".Data::Dumper::Dumper($service->ServiceType()));
  $module = 'openprint::Estimating::'.$module if $module !~ /openprint::Estimating/;
	eval {
    my $path = $module;
    $path =~ s/::/\//g;
    # FIXME potential security problem here, need to sanitise service_type
		require $path.'.pm';
	};
  if ($@) {
    $log->error("Error requiring $module: $@");
    return (alert=>"Unable to load code for $module.");
  }
	$param{method} = 'calc' if ! $param{method};
# Not sure this is a good idea, but its neccessary for printing... why is it neccessary?
  # I think soas to populte the cache with live values instead of whats in the db
	$openprint::service::specs_cache{$param{ServiceIndex}} = \%param if $param{ServiceIndex};
	my %specs = %param;
	if (my $function = $module->can( $param{method})) {
		$log->debug("Can do $module -> $param{method}");
		$specs{Status} = $function->( $log, $dbh, \%variable, @param{'ProjectIndex','ServiceIndex'}, \%specs );
	} else {
		$log->error("Cant do $param{method} for $module");
	} # end if

	my @vars;
	if ( my $function = $module->can( 'outputs' ) ) {
		@vars = sort $function->( @param{'ProjectIndex', 'ServiceIndex'}, \%specs );
		$log->debug("outputs @vars") if $debug;
	} # end if
	if ( ! @vars ) {
		@vars = keys %specs;
		$log->debug("no outputs, so using keys @vars") if $debug;
	} # end if
	if ( my $function = $module->can( 'no_outputs' ) ) {
		my @no_outputs = sort $function->( @param{'ProjectIndex','ServiceIndex'}, \%specs , \%param );
		$log->debug("$module ::no_outputs: @no_outputs)") if $debug;
		@vars = sets::exclude( \@no_outputs, \@vars );

		foreach my $key ( @no_outputs ) {
			$log->debug("Deleting key $key in no_outputs ") if $debug;
			delete $specs{$key};
		} # end foreach
	} # end if
	foreach my $key ( 'method', 'ContinueProject' ) {
		$log->debug("Deleting key $key in standard no_outputs ") if $debug;
		delete $specs{$key};
	} # end foreach
	if ( $debug ) {
		foreach my $key ( sort keys %specs ) {
			$log->debug("values still in specs $key => ".(defined $specs{$key} ? $specs{$key} : 'undef'));
		} # end foreach
	} # end if debug
	if ( 0 and $debug ) {
		foreach my $key ( sort { $a cmp $b } keys %specs ) {
      next if $key eq 'alert';
			if ( (exists $param{$key}) and ($specs{$key} eq $param{$key}) ) {
				$log->debug("Deleting $key cuz it's the same $key = $param{$key}");
				delete $specs{$key};
# This prevents us from turning off services in create_calc
			} elsif ( ! defined $specs{$key} ) {
				# Send back empty strings, but not nulls
			#} elsif ( ( ! exists $param{$key}) and ! $specs{$key} ) {
				#$log->debug("Deleting $key cuz it's not in params and its empty");
				delete $specs{$key};
			#} elsif ( ref $specs{$key} ) {
				#$log->error("Got a non-scalar in specs! $key => $specs{$key}");
				#delete $specs{$key};
			} # end if
		} # end foreach
		foreach my $key ( sort { $a cmp $b } keys %specs ) {
			$log->debug("Outputting $key = $specs{$key}");
		} # end foreach
	} else {
		foreach my $key ( keys %specs ) {
			next if ref $specs{$key};
      next if $key eq 'alert';

			if ( (exists $param{$key}) and (exists $specs{$key}) and ( 
						( (!$specs{$key}) and (!$param{$key}) ) # both not defined or ''
						or ( $specs{$key} and $param{$key} and ( $specs{$key} eq $param{$key} ) )
						) ) {
				delete $specs{$key};
			} elsif ( ! defined $specs{$key} ) {
				delete $specs{$key};
				# Send back empty strings, but not nulls
# This prevents us from turning off services in create_calc
			#} elsif ( ( ! exists $param{$key}) and ! $specs{$key} ) {
				#delete $specs{$key};

			} else {
				#$log->debug("Got changed $key => $param{$key} != $specs{$key}");
				#delete $specs{$key};
			} # end if
		} # end foreach
	} # end if debug
	return %specs;
} # end sub calc

sub reuse {

	my $Project = $variable{Project} = new openprint::Project($param{project_id});
	$variable{ProjectIndex} = $Project->id();
	if ( $Project->reference() ) {
		$Project->reference('Copy of ' . $Project->reference());
	} else {
		$Project->reference('Copy of project # ' . $param{project_id});
	} # end if

} # end sub

sub docket_sheet {
	openprint::print_project::summary( $r, $log, $dbh, \%variable );
} # end sub docket_sheet

sub _view_log {
}
sub _service_dump {
}

sub summary {
	openprint::print_project::summary( $r, $log, $dbh, \%variable );
}
1;
__END__
