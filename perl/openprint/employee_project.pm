package openprint::employee_project;
use strict;
use Date::Calc qw(Add_Delta_Days Date_to_Days check_date );
use MIME::QuotedPrint;

use openprint ();

require openprint::Project;
require openprint::order;
require openprint::service;
require openprint::Equipment;
require openprint::employee_schedule;
require openprint::press_schedule;
require openprint::employee_production;

require sql;
#require openprint::MXML;
#require openprint::JDF;
#require openprint::PaperAllocation;
require openprint::LabelType;
require openprint::Label;
require openprint::PurchaseOrder;
require openprint::PurchaseOrder_Content;
require openprint::PaperInventory;
require openprint::RFIDTag;
require openprint::ScheduledJob;
require openprint::ServiceType_Category;
#require openprint::SignatureCapture;
require openprint::File;
require openprint::User_Notification;
require openprint::Operator_Role;
require openprint::Project_Service_Operator;


use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

sub view {

	my $project_index = $param{ProjectIndex};
	$project_index = $param{project_id} if ! $project_index;
	$project_index = openprint::Project->transform('id', $project_index);
		
	if ( ! $project_index ) {
		if ( $param{Docket} ) {
			$param{Docket} =~ s/\D//g;
			if ( $param{Docket} ) {
				if ( my @Projects = openprint::Project->find(docket=>$param{Docket}) ) {
					$project_index = $Projects[0]->id();
				} # end if
			} # end if
		} elsif ( $param{docket} ) {
			$param{docket} =~ s/\D//g;
			if ( $param{docket} ) {
				if ( my @Projects = openprint::Project->find(docket=>$param{docket}) ) {
					$project_index = $Projects[0]->id();
				} # end if
			} # end if
		} elsif ( $param{order_id} ) {
			$param{order_id} =~ s/\D//g;
			if ( $param{order_id} ) {
				if ( my @Projects = openprint::Project->find('order_id'=>$param{order_id}) ) {
					$project_index = $Projects[0]->id();
				} # end if
			} # end if
		} # end if
	} # end if

	my $Project = $variable{Project} = openprint::Project->find_one( id=>$project_index ) if $project_index;
	if ( ! $Project ) {
		$variable{Project} = new openprint::Project();
		$variable{Order} = new openprint::Order();
		$variable{error} .= "Project $project_index not found.<br/>";
		return;
	} # end if
	my $order_id = $param{OrderID};
	$order_id = $Project->order_id() if ! $order_id;
	if ( $project_index and ( ! $order_id ) and $param{Docket} ) {
		( $order_id ) = sql::execute( $log, $dbh, q{SELECT id FROM Orders WHERE id IN ( SELECT DISTINCT OrderIndex FROM Order_Contents WHERE lngProjectIndex=? ) AND docket=?}, $project_index, $param{Docket} );
	} # end if
	$variable{OrderID} = $order_id;
	my $Order = $variable{Order} = new openprint::Order( $order_id );

	if ( $param{action} eq 'DoNotPayCommission' ) {
		if ( $session{user_type} eq 'A' ) {
			$Order->save({do_not_pay_commission=>1});
			(new openprint::Log())->save({Object=>$Order, action=>'Save', note=>'Mark Order as Do Not Pay Commission'});
		} else {
			$variable{error} .= 'You do not have permission.';
		}
	} elsif ( $param{action} eq 'PayCommission' ) {
		if ( $session{user_type} eq 'A' ) {
			$Order->save({do_not_pay_commission=>0});
			(new openprint::Log())->save({Object=>$Order, action=>'Save', note=>'Mark Order as Ok To Pay Commission'});
		} else {
			$variable{error} .= 'You do not have permission.';
		}
	} elsif ( $param{action} eq 'Change Status' ) {
		foreach my $service_id ( split(',', $param{service_id} ) ) {
			my $Service = $Project->Service( $service_id );
			if ( ! $Service->service_id() ) {
				$variable{error} .= 'Service not found.';
				next;
			} # end if

			if ( $Service->status() eq $param{status} ) {
				$variable{information} .= 'Status not changed.';
				next;
			} # end if

			my $specs = $Service->specs();
			$Project->add_to_log( @session{'company_id','user_id'}, 'Marked ' . ( $$specs{ServiceName} ? $$specs{ServiceName} : $Service->ServiceType()->name() ). ' ' . $param{status} . ' from ' . $Service->status() );
			$variable{error} .= $Service->save({'status'=>$param{status}});
			if ( ! $variable{error} ) {
				$Project->update_status();
			} else {
				$variable{information} .= 'Status changed.';
			} # end if
		} # end foreach service_id
	} elsif ( ( $param{btnFunction} eq 'Rush' ) and ! $Project->rush() ) {
		$Project->rush( 1 );
		$variable{error} .= $Project->save();
		if ( ! $variable{error} ) {
			$Project->add_to_log( @session{'company_id','user_id'}, "Project marked as a rush job." );
			my %info;
			$info{Project} = $Project;
			$info{Docket} = $Project->docket();
			$info{ReplacementText} = misc::load_file( $log, $ENV{DOCUMENT_ROOT} . '/email_content/rush_job_notification.html' );
			$info{ReplacementText} = ssi::variable_substitution( \$info{ReplacementText}, \%info );
			$_ = misc::load_file( $log, $config{SkinPath} . '/email_template.html' );
			$_ = encode_qp( Encode::encode('utf-8', ssi::variable_substitution( \$_, \%info ) ) );
			my @body = ('', $_, 'text/html', 'quoted-printable');
			my $From = new openprint::User( $session{user_id} );
			my @To = openprint::User->find('type'=>['E','A'], 'usergroup any'=>'Production');
			if ( ! sets::isin( $Project->Order()->salesrep_id(), map { $_->id() } @To ) ) {
				push @To, new openprint::User( $Project->Order()->salesrep_id() );
			} # end if

			new openprint::Email()->send(
					FROM	=> $From,
					TO	=> \@To,
					SUBJECT => "Docket $info{Docket} Rushed!",
					ATTACHMENTS=>\@body,
					);
		} # end if
	} elsif ( $param{btnFunction} eq 'No Rush' ) {
		$Project->rush( 0 );
		$variable{error} .= $Project->save();
		$Project->add_to_log( @session{'company_id','user_id'}, "Project marked as a non-rush job." );
	} elsif ( $param{btnFunction} eq 'Export JDF' ) {
		misc::export( $r, $log, \%variable, 'Docket-'.$Project->docket().'.jdf', [$Project->jdf(1.2)->toString()] );
	} elsif ( $param{btnFunction} eq 'Export MXML' ) {
		my $MXML = new openprint::MXML($Project);
		misc::export( $r, $log, \%variable, 'Docket-'.$Project->docket().'-Metrix.mxml', [$MXML->toString()] );
		return;
	} elsif ( $param{btnFunction} eq 'Save' ) {
		my $service_index = $param{ServiceIndex};
		my $Service = $Project->Service( $service_index );
		my $status = $Service->status();
		my $specs = $Service->specs();

		my $ServiceType = $Service->ServiceType();
		my $service_type = $ServiceType->name();

		if ( $service_type eq 'Signature' ) {
			my $complete = is_sig_complete( $Project, $service_index );
$log->debug("Sig complete: $complete");
			if ( $complete ) {
# Run through each of the signatures and if everyone is complete, then set the printing service to complete
				foreach my $signature_service_index ( $Project->signatures() ) {
					next if $signature_service_index == $service_index;
					if ( 'Complete' ne openprint::service::status( $project_index, $signature_service_index ) ) {
						$complete = 0;
						last;
					} # end if
				} # end foreach
			} # end if
$log->debug("Project complete: $complete " . $Service->to_string());

			my $services = $Project->services();
			if ( $$services{''} ) {
				my $ProjectService = $Project->Service( $$services{''}[0] );
				if ( $complete ) {
					$ProjectService->save({ status=>'Complete' });

					$Project->add_to_log( @session{'company_id','user_id'}, 'All signatures complete - marking printing complete.' );
					foreach my $PA ( openprint::PaperAllocation->find(docket=>$Project->docket() ) ) {
						$PA->delete();
						$Project->add_to_log( @session{'company_id','user_id'}, 'Freeing allocated paper: ' . $PA->quantity() . $PA->units() );
					} # end foreach
				} else {
					$ProjectService->save({ status=>'Ordered' });
				} # end if
			} # end if

		} elsif ( sets::isin( $service_type,[ 'Proofs', 'FilmStripping' ] ) ) {

			# Store Usepress
			foreach my $signature_service_index ( $Project->signatures() ) {
				my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
				my $form = $$sig_specs{SignatureIndex};
				next if ( ( ! $param{'UsePress-'.$form} ) or ( $param{'UsePress-'.$form} eq $$sig_specs{UsePress} ) );
				openprint::service::insert_service_spec( $log, $dbh, $project_index, $signature_service_index, 'UsePress', $param{"UsePress-$form"} );
				my $runtime = openprint::service::get_runtime( $Project, $signature_service_index );

				my $Equipment = openprint::Equipment->find_one( strid=>$param{"UsePress-$$sig_specs{SignatureIndex}"} );
				next if ! $Equipment;

				foreach my $Job ( openprint::ScheduledJob->find( 'service_id @>'	=> $signature_service_index ) ) {
					$Job->save({ equipment_id	=> $Equipment->id(), runtime => "$runtime minutes", });
				} # end foreach Job
			} # end foreach signature_service_index

			if ( $service_type eq 'FilmStripping' ) {
				if ( $param{rdbComplete} eq 'Yes' ) {
					if ( ! Date::Calc::check_date( @param{'duedate_year','duedate_month','duedate_day'} ) ) {
						$variable{Redirect} = '/employee/proj/'.$ServiceType->url();
						$variable{error} = 'There was an error saving the DueDate.  Please check that a real date was selected.';
						$param{rdbComplete} = 'No';
					} elsif ( 0 < Date::Calc::Delta_Days( @param{'ddmDueDateYear','ddmDueDateMonth','ddmDueDateDay'}, Date::Calc::Today() ) ) {
						$variable{Redirect} = '/employee/proj/'.$ServiceType->url();
						$variable{error} .= 'You cannot select a date in the past. Please try again.';
						$param{rdbComplete} = 'No';
					} else {
						if ( $param{duedate_year} ) {
							my $duedate = join('-', @param{'duedate_year','duedate_month','duedate_day'} );
							$Project->due_date( $duedate );
							if ( ! $Project->save() ) {
								$Project->add_to_log( @session{'company_id','user_id'}, "Duedate changed to $duedate" );
							} else {
								$variable{error} .= 'Error saving duedate.';
							} # end if
						} # end if

						$Service->save({status=>'Approved'});
					} # end if
				} else { # Not Complete
					if ( $status ne 'Ordered' ) {
# Make sure we don't get approved without complete, because they can't unapprove
						$Project->add_to_log( @session{'company_id','user_id'}, "Marked Filmstripping Ordered from $status" );
						$Service->save({status=>'Ordered'});
					} # end if
				} # end if Complete or NOT
			} elsif ( $service_type eq 'Proofs' ) {
				if ( $param{rdbComplete} ne 'Yes' ) {
	# Make sure we don't get approved without complete, because they can't unapprove
					$param{rdbApproved} = 'N';
					$param{rdbClientApproved} = 'N';
					if ( $status ne 'Ordered' ) {
						$Project->add_to_log( @session{'company_id','user_id'}, "Marked Proofs Ordered from $status" );
						$Service->save({status=>'Ordered'});
					} # end if
				} elsif ( $param{rdbApproved} eq 'Y' ) {
					if ( $param{duedate} and ( $param{duedate} ne $Project->due_date() ) ) {
						$Project->due_date( $param{duedate} );
						if ( ! $Project->save() ) {
							$Project->add_to_log( @session{'company_id','user_id'}, "Duedate changed to $param{duedate}" );
							send_duedate_change_notification( $project_index, $order_id );
						} else {
							$variable{error} .= 'Error saving duedate.';
						} # end if
					} # end if

					if ( (!$variable{error}) and ($status ne 'Approved') ) {
						openprint::employee_production::mark_proofs_approved( $Project, $Service );
						send_proofs_approved_email( $project_index, $order_id );
					} # end if
				} elsif ( $param{rdbClientApproved} eq 'Y' ) {
					if ( $status ne 'Waiting For QA Approval' ) {
						$param{ClientApprovalDate} = Date::Format::time2str( $config{DateTimeFormat}, time );
						$Project->add_to_log( @session{'company_id','user_id'}, "Marked Proofs Waiting for QA Approval from $status" );
						$Service->save({status=>'Waiting For QA Approval'});
						send_proofs_client_approved_email( $project_index, $order_id );
					} # end if
					$param{rdbApproved} = 'N';
				} else { # Just complete
					if ( $status ne 'Waiting For Customer Approval' ) {
						$param{CompleteDate} = Date::Format::time2str( $config{DateTimeFormat}, time );
						if ( $status ne 'Waiting For Customer Approval' ) {
							$Project->add_to_log( @session{'company_id','user_id'}, "Marked Proofs Waiting for Customer Approval from $status" );
							$Service->save({status=>'Waiting For Customer Approval'});
						} # end if
					} # end if
					# Only send if completion date has changed
					my ( $c_date, $complete ) = openprint::service::get_specifications( $log, $dbh, $project_index, $service_index, 'CompletionDate','rdbComplete' );
					if ( $complete ne $param{rdbComplete} and $c_date ne $param{CompletionDate} ) {
						send_proofs_complete_email( $project_index, $order_id );
					} # end if completion date has changed
					$param{rdbApproved} = 'N';
					$param{rdbClientApproved} = 'N';
				} # end if Complete Or NOT
			} # end if Proofs or FilmStrippign
		} else { # A Service, But Not Film Stripping or Proofs
			if ( $param{rdbComplete} eq 'Yes' ) {
				$Service->save({status=>'Complete'});
				my $category = $ServiceType ? $ServiceType->category():'';
				if ( $category eq 'Bindery' ) {
					$_ = q{ SELECT lngServiceIndex FROM tbl_Service_Specifications WHERE lngProjectIndex=?
						 AND strName='ServiceType'
						 AND strValue IN ( SELECT name FROM Service_Types WHERE category = 'Bindery' )
						 AND lngServiceIndex IN ( SELECT lngServiceIndex FROM tbl_Project_Contents WHERE lngProjectIndex=? AND strStatus != 'Complete' ) };
					if ( ! sql::execute( $log, $dbh, $_, $project_index, $project_index ) ) {
# If no more incomplete bindery services, then mark all packaging services complete
						$_ = q{SELECT lngServiceIndex FROM tbl_Service_Specifications WHERE lngProjectIndex=?  AND strName='ServiceType'
							 AND strValue IN ( SELECT name FROM Service_Types WHERE category = 'Packaging' )};
						foreach my $packaging_service_index ( sql::execute( $log, $dbh, $_, $project_index ) ) {
							my $Packaging_Service = $Project->Service( $packaging_service_index );
							$Packaging_Service->save({status=>'Complete'});
						} # end foreach
					}  # end if
				} # end if Bindery
			} elsif ( $service_type ) { # rdbComplete == No
				$Service->save({status=>'Ordered'});
			} # end if Complete or NOT
		} # end if FilmStripping, Proofs or other

		foreach my $Role ( openprint::Operator_Role->find( 'servicetype_id is null or ='=>$$ServiceType{id} ) ) {
			my $Operator = openprint::Project_Service_Operator->find_one( service_id=>$service_index, role_id=>$$Role{id} );
			$Operator = new openprint::Project_Service_Operator() if ! $Operator;

			# TakeOver is only for Proofs
			if ( $param{"TakeOver$$Role{id}"} ) {
# Take Over
				$Project->add_to_log( @session{'company_id','user_id'}, 'Taken Over by '. $openprint::User->name() . ' as ' . $$Role{name} );

				$Operator->save({ service_id=>$service_index, user_id=>$$openprint::User{id}, role_id=>$$Role{id} });
			} elsif ( ( exists $$specs{SignatureIndex} ) and ( exists $param{"operator_id-$$specs{SignatureIndex}-$$Role{id}"} )
					and ( $param{"operator_id-$$specs{SignatureIndex}-$$Role{id}"} != $Operator->id() )
					) {
				$Operator->save({ service_id=>$service_index, user_id=>$param{"operator_id-$$specs{SignatureIndex}-$$Role{id}"}, role_id=>$$Role{id} });
				$Project->add_to_log( @session{'company_id','user_id'}, 'Operator changed to '. $Operator->User()->name() . ' by ' . $openprint::User->name() . ' as ' . $$Role{name} );
			
			} elsif ( exists $param{"operator_id-$$Role{id}"} 
					and ( $param{"operator_id-$$Role{id}"} != $Operator->id() )
					) {
				$Operator->save({ service_id=>$service_index, user_id=>$param{"operator_id-$$Role{id}"}, role_id=>$$Role{id} });
				$Project->add_to_log( @session{'company_id','user_id'}, 'Operator changed to '. $Operator->User()->name() . ' by ' . $openprint::User->name() . ' as ' . $$Role{name} );
			
			} # end if
		} # end foreach Role
		$Service->save({ starttime=> ($param{"PickupDate"} ? $param{"PickupDate"} : 'NOW()') });

# Save info
		my $ac = sql::start_transaction( $dbh );
		my $service_specs = $Service->specs();
		if ( $$service_specs{ProjectType} ) {
			my $complete = 1;

			foreach my $signature_service_index ( $Project->signatures() ) {
				my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );

				foreach my $param ( qw/txtEmployeeName txtEmployeeComments UsedStockBrand UsedStockFinish UsedStockColour UsedStockWeight UsedStockSheetSize UsedSheetQuantity ddmPressCompletionDateMonth ddmPressCompletionDateDay ddmPressCompletionDateYear rdbPressComplete UsedImposition UsedColumns UsedRows UsedDutchColumns UsedDutchRows UsedRunStyle UsePress/ ) {
					next if $$sig_specs{$param} eq $param{"$param-$$sig_specs{SignatureIndex}"};
					openprint::service::insert_service_spec( $log, $dbh, $project_index, $signature_service_index, $param, $param{"$param-$$sig_specs{SignatureIndex}"} );
				} # end foreach

				if ( ! is_sig_complete( $Project, $signature_service_index ) ) {
					$complete = 0;
				} else {
					foreach my $Job ( openprint::ScheduledJob->find( project_id=>$project_index, 'service_id @>'=>$signature_service_index ) ) {
						$Job->delete();
					} # end foreach
					if ( my $Equipment = openprint::Equipment->find_one( strid=>$$sig_specs{UsePress}) ) {
						$Equipment->update_schedule();
					} # end if
				} # end if
			} # end foreach signature_service_index

# There is now a set of press completion buttons for each signature
			if ( $complete ) {
				$Project->status_change( @session{'company_id','user_id'}, 'Printed' );
			} else {
				$Service->save({status=>'Ordered'});
				$Project->add_to_log( @session{'company_id','user_id'}, "Marked Ordered from $status" );
			} #nd if
		} elsif ( $service_type eq 'Signature' ) {
			foreach my $param ( qw/txtEmployeeName txtEmployeeComments UsedStockBrand UsedStockFinish UsedStockColour UsedStockWeight UsedStockSheetSize UsedSheetQuantity ddmPressCompletionDateMonth ddmPressCompletionDateDay ddmPressCompletionDateYear rdbPressComplete UsedImposition UsedColumns UsedRows UsedDutchColumns UsedDutchRows UsedRunStyle UsePress/ ) {
				next if $$service_specs{"$param-$$service_specs{SignatureIndex}"} eq $param{"$param-$$service_specs{SignatureIndex}"};
				openprint::service::insert_service_spec( $log, $dbh, $project_index, $service_index, $param, $param{"$param-$$service_specs{SignatureIndex}"} );
			} # end foreach

			if ( my $Equipment = openprint::Equipment->find_one( strid=>$$service_specs{UsePress} ) ) {
				$Equipment->update_schedule();
			} # end if
		} else {
			my @do_not_save = ( 'btnFunction','ProjectIndex','ServiceIndex','order_id', 'duedate_day','duedate_month','duedate_year','Docket','TakeOver', 'OrderID' );
			foreach my $param ( keys %param ) {
				next if $$service_specs{$param} eq $param{$param};
				next if ( sets::isin_regx( $param, @do_not_save ) );
				openprint::service::insert_service_spec( $log, $dbh, $project_index, $service_index, $param, $param{$param} );
			} # end foreach
		} # end if

		if ( $param{signature} ) {
$log->debug("Saving signature");
			my $Signature = new openprint::SignatureCapture();
			$variable{error} .= $Signature->save({
					image_data	=>	URI::Escape::uri_unescape($param{signature}),
					type		=>	'path',
					project_id	=>	$Project->id(),
					service_id	=>	$service_index,
					});
		} # end if

		$Project->update_status();
		$order_id = $Project->order_id() if ! $order_id;
		if ( $order_id ) {
			my $Order = new openprint::Order( $order_id );
			$Order->update_status( );
		} # end if
		sql::end_transaction( $dbh, $ac );
		$variable{Redirect} = '/employee/proj/'.$ServiceType->url();
	} elsif ( $param{btnFunction} eq 'Shipped' ) {
		$Project->status_change( undef, undef, 'Shipped' );
	} elsif ( $param{btnFunction} eq 'Picked Up' ) {
		$Project->status_change( undef, undef, 'Picked Up' );
	} elsif ( $param{btnFunction} eq 'Complete Printing' ) {
		$Project->status_change( undef, undef, 'Printed' );
	} elsif ( $param{btnFunction} eq 'BinderyComplete' ) {
		$Project->status_change( undef, undef, 'Bindery Complete' );
	} elsif ( $param{btnFunction} eq 'Complete' ) {
		$Project->status_change( undef, undef, 'Complete' );
	} elsif ( $param{btnFunction} eq 'AddToPressSchedule' ) {
		$variable{error} .= openprint::press_schedule::add_project_to_press_schedule( $Project, $param{ServiceIndex} );
	} elsif ( $param{btnFunction} eq 'RemoveFromPressSchedule' ) {
		foreach my $Job ( openprint::ScheduledJob->find( project_id=>$Project->id() ) ) {
			$Job->delete();
		} # end foreach Job
	} elsif ( $param{btnFunction} eq 'Add Service' ) {

		if ( $param{NewServiceType} ) {
			my $ServiceType = new openprint::ServiceType( $param{NewServiceType} );
			my $new_service_index = $Project->add_service( $ServiceType );

			if ( $ServiceType->name() eq 'Signature' ) {
				$_ = q{SELECT MAX(strValue::integer) FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND strName='SignatureIndex'};
				my ( $signature_count ) = sql::execute( $log, $dbh, $_, $project_index );
				openprint::service::insert_service_spec( $log, $dbh, $project_index, $new_service_index, 'txtSignatureType', 'Signature' );
				openprint::service::insert_service_spec( $log, $dbh, $project_index, $new_service_index, 'txtServiceDescription', 'Additional Signature' );
				openprint::service::insert_service_spec( $log, $dbh, $project_index, $new_service_index, 'SignatureIndex', ++$signature_count );
			} # end if
			$Project->add_to_log( @session{'company_id','user_id'}, sprintf( 'Added Service: %s', $ServiceType->name() ) );
		} elsif ( $param{txtServiceName} ) {
			
			my $ServiceType = openprint::ServiceType->find_one( name=>'CustomService');
			if ( $ServiceType ) {

			my $ac = sql::start_transaction( $dbh );

			sql::insert( $log, $dbh, 'tbl_Project_Contents', 'lngProjectIndex', $project_index, 'strStatus', 'Waiting For Customer Approval', 'servicetype_id', $ServiceType->id() );
			$_ = q{SELECT MAX(lngServiceIndex) FROM tbl_Project_Contents WHERE lngProjectIndex=?};
			my ( $service_index ) = sql::execute( $log, $dbh, $_, $project_index );
			sql::insert( $log, $dbh, 'tbl_Service_Specifications', [
						'lngProjectIndex',  $project_index,
						'lngServiceIndex',  $service_index,
						'strName',		  'ServiceType',
						'strValue',		 'CustomService' ]);
			sql::insert( $log, $dbh, 'tbl_Service_Specifications', [
						'lngProjectIndex',  $project_index,
						'lngServiceIndex',  $service_index,
						'strName',		  'txtPrice1',
						'strValue',		 misc::moneyfilter($param{txtPrice}) ]);
			sql::insert( $log, $dbh, 'tbl_Service_Specifications', [
						'lngProjectIndex',  $project_index,
						'lngServiceIndex',  $service_index,
						'strName',		  'txtPrice2',
						'strValue',		 misc::moneyfilter($param{txtPrice}) ]);
			sql::insert( $log, $dbh, 'tbl_Service_Specifications', [
						'lngProjectIndex',  $project_index,
						'lngServiceIndex',  $service_index,
						'strName',		  'txtPrice3',
						'strValue',		 misc::moneyfilter($param{txtPrice}) ]);
			sql::insert( $log, $dbh, 'tbl_Service_Specifications',[
					'lngProjectIndex',  $project_index,
					'lngServiceIndex',  $service_index,
					'strName',		  'ServiceName',
					'strValue',		 $param{txtServiceName}
					] );

			$Project->add_to_log( @session{'company_id','user_id'}, sprintf( 'Added Custom Line: %s, (%.2f)', @param{'txtServiceName','txtPrice'} ) );
			$Project->update_status( );
			$Project->Order()->update_status();

			sql::end_transaction( $dbh, $ac );
			} # end if
		} else {
			$variable{error} .= 'Additional Charge must have either a type or description.<br/>';
		} # end if NewServiceType or txtServiceName
## needs approval
		if ( $Project->docket() ) {
		$variable{ExternalRedirect} = '/employee/project/view.html?docket='.$Project->docket();
		} else {
		$variable{ExternalRedirect} = '/employee/project/view.html?ProjectIndex='.$Project->id();
		} # end if
#		# email CSR
	} elsif ( $param{btnFunction} eq 'AdditionalChargeNotify' ) {
		send_additional_charges_notifications( @param{'OrderID','ProjectIndex'} );
		$variable{information} = 'Additional Charges Email sent.';
	} elsif ( $param{btnFunction} eq 'DeleteServices' ) {
		my $ac = sql::start_transaction( $dbh );
		foreach my $key ( keys %param ) {
			if ( $key =~ /^chkDelete-([,\d]+)$/ ) {
				foreach my $sid ( split(',', $1 ) ) {
					my $Service = $Project->Service($sid);
					$Service->delete();
				} # end foreach
			} # end if
		} # end foreach
		$Project->update_status();
		$Project->Order()->update_status();
		sql::end_transaction( $dbh, $ac );
	} elsif ( $param{btnFunction} eq 'Approve' ) {
		my $Order = new openprint::Order( $param{OrderID} );
		$variable{error} .= $Order->approve();
		if ( ! $variable{error} ) {
			$Project->update_status();
			$Order->update_status();
			$variable{ExternalRedirect} = '/employee/project/view.html?docket='.$Order->docket();
		} # end if
	} # end if

} # end sub view

sub send_additional_charges_notifications {
	my ( $order_id, $project_index, $message, @Notifications ) = @_;
# Email CSR
	my %info;
	$info{ProjectIndex} = $project_index;
	$info{OrderID} = $order_id;
	$info{Message} = $message;

	my $Order = new openprint::Order( $order_id );
	@Notifications = $Order->AdditionalChargeNotifications() if ! @Notifications;
	return 'No one to notify.' if ! @Notifications;

	my $CSR = new openprint::User( $Order->salesrep_id() );
	my $Operator = $openprint::User;

	@info{'CSRFirstName','CSRLastName','CSREmail'} = ( $CSR->firstname(), $CSR->lastname(), $CSR->email() );
	@info{'CustomerFirstName','CustomerLastName','CustomerEmail'} = ( $Order->firstname(), $Order->lastname(), $Order->email() );
	$info{Operator} = $Operator;
	@info{'EmployeeFirstName','EmployeeLastName','EmployeeEmail','EmployeeExtension'} = ( $Operator->firstname(), $Operator->lastname(), $Operator->email(), $Operator->extension() );

	$info{CompletionDate} = Date::Format::time2str( $config{DateTimeFormat}, time );
	my $Project = $info{Project} = new openprint::Project( $project_index );

	my $email_template = misc::load_file( $log, $config{SkinPath} . '/email_template.html' );

	$info{ReplacementText} = ssi::include('/email_content/additional_charges_client_notification.html', \%info );
	$_ = encode_qp( Encode::encode('utf-8', ssi::variable_substitution( \$email_template, \%info ) ) );
	my @body = ('', $_, 'text/html', 'quoted-printable');
	my $results = ( new openprint::Email() )->send(
			FROM	=> $Operator,
			'Return-receipt-to' => sprintf( '"%s %s" <%s>', $Operator->get('firstname','lastname','email') ),
			'Disposition-Notification-To' => sprintf( '"%s %s" <%s>', $Operator->get('firstname','lastname','email') ),
			#CC	  => sprintf( '"%s %s" <%s>', @info{'CSRFirstName','CSRLastName','CSREmail'}),
			TO	  => [ map { $_->User() } @Notifications ],
			#TO		=>	'"Isaac Connor" <iconnor@point-one.com>',
			SUBJECT => 'Additional Charges required',
			ATTACHMENTS	=>	\@body,
			);
	$Project->add_to_log( @session{'company_id','user_id'}, "Additional charges notification : $results." );

	return $results;
} # End sub send_additional_charges_notifications

sub upload_pdfs {
	my $project_index = $param{ProjectIndex};
	my $Project = new openprint::Project( $project_index );

	my $Company = new openprint::Company( $session{company_id} );
	$variable{CompanyName} = $Company->name();

	$variable{Docket} = $Project->docket();
	my $destdir = $config{'PDFS Path'} . "/$variable{CompanyName}";
	if ( ! -e $destdir  ) {
		if ( ! mkdir $destdir ) {
			$log->error("Cannot create company PDFs dir $destdir : Reason: $!" );
		} # end if
	} # end if
	$destdir .= "/$variable{Docket}";
	if ( ! -e $destdir  ) {
		if ( ! mkdir $destdir ) {
			$log->error("Cannot create PDFs dir $destdir : Reason: $!" );
		} # end if
	} # end if

	if ( $param{btnFunction} eq 'Delete' ) {
		my $destdir = $ENV{DOCUMENT_ROOT} . "/pdfs/$project_index";
		foreach my $filename ( $param{chkFiles} ) {
			sql::execute( $log, $dbh, 'DELETE FROM tbl_Project_PDFs WHERE lngProjectIndex=? AND strFileName=?', $project_index, $filename );
			if ( ! unlink "$destdir/$filename" ) {
				$log->debug( "Error deleting file $destdir/$filename");
			} # end if
		} # end foreach

	} elsif ( $param{btnFunction} eq 'Upload Files' ) {
		foreach my $index ( 1 .. 5 ) {

			if ( $r->param('fileUpload'.$index) ) {
				my $filename = $r->param('fileUpload'.$index);
				$filename =~ s/.*[\/\\](.*)/$1/;
				$filename =~ s/ /_/g;
				$log->debug("Filename: $filename");
				if ( ! -e $destdir  ) {
					if ( ! mkdir $destdir ) {
						$log->error("Cannot create dir $destdir : Reason: $!" );
						return misc::error( $log, $dbh, \%variable, "Error creating directory", "I was unable to create a directory to hold the pdf files.   Please contact the administrator" );
					} # end if  
				} elsif ( ! -d $destdir ) {
					$log->error("$destdir exists but is not a directory.");
					return misc::error( $log, $dbh, \%variable, "Error creating directory", "I was unable to create a directory to hold the pdf files.   Please contact the administrator" );
				} # end if

				my $upload = $r->upload('fileUpload'.$index);

				if ( ! $upload->link( "$destdir/$filename" ) ) {
					return misc::error( $log, $dbh, \%variable, 'Error uploading file.', "$!<br/>Please contact the administrator" );
				} # end if

				if ( ! sql::execute( $log, $dbh, 'SELECT * FROM tbl_Project_PDFs WHERE lngProjectIndex=? AND strFileName=?', $project_index, $filename ) ) {
					sql::insert( $log, $dbh, 'tbl_Project_PDFs',[
							'lngProjectIndex',  $project_index,
							'strFileName',	  $filename,
							'strDescription',   $r->param('txtDescription'.$index)
							] );
				} else {
					sql::update( $log, $dbh, 'tbl_Project_PDFs', ['lngProjectIndex=? AND strFileName=?', $project_index, $filename ],
							'strDescription',   $r->param('txtDescription'.$index)
							);

				} # end if
			} # end if
		} # end foreach

	} # end if

	@{$variable{PDFS}} = sql::execute( $log, $dbh, 'SELECT strFileName, strDescription FROM tbl_Project_PDFs WHERE lngProjectIndex=?', $project_index );

	$variable{ProjectIndex} = $project_index; 
} # end sub upload_pdfs

sub send_proofs_complete_email {
	my ( $project_index, $order_id ) = @_;
# Do proofs specific stuff, which for now is send an email.
#Look up Employee info
	my %info;

	my $Project = new openprint::Project( $project_index );
	$order_id = $Project->order_id() if ! $order_id;

	( my $user_index, @info{'DocketNumber','ProjectReference','ProjectIndex'} ) = ( $Project->user_id(), $Project->docket(), $Project->reference(), $project_index );

	my $Order = new openprint::Order( $order_id );
	@info{'CustomerFirstName','CustomerLastName','CustomerEmail'} = ( $Order->firstname(), $Order->lastname(), $Order->email() );

	my $User = new openprint::User( $session{user_id} );
	@info{'EmployeeFirstName','EmployeeLastName','EmployeeEmail','EmployeeExtension'} = ( $User->firstname(), $User->lastname(), $User->email(), $User->extension() );

	$info{CompletionDate} = Date::Format::time2str( $config{DateTimeFormat}, time );

	$info{ReplacementText} = ssi::include( '/email_content/proofs_complete.html', \%info );

	$_ = encode_qp( Encode::encode('utf-8', ssi::include('/email_template.html', \%info ) ) );
	my @body = ('', $_, 'text/html', 'quoted-printable');
	my %mail = (
			SMTP	=> $config{'Mail Server'},
			FROM	=> sprintf( "%s %s <%s>", @info{'EmployeeFirstName','EmployeeLastName','EmployeeEmail'}),
			TO	  => sprintf( "%s %s <%s>", @info{'CustomerFirstName','CustomerLastName','CustomerEmail'}),
			SUBJECT => "Proofs Complete",
			);

#misc::send_email_with_attachment( $log, \%mail, @body );

# Send email to sales rep
#$_ = "SELECT strFirstName, strLastName, strEmail FROM Users WHERE Index=(SELECT lngEmployeeID FROM Orders WHERE LngOrderID='$order_id')";
#my $sales_person_email = sprintf( "%s %s <%s>", sql::execute( $log, $dbh, $_ ) );
#if ( $sales_person_email ne '  <>' ) {
#$info{ReplacementText} = "<!--#include virtual=\"/email_content/proofs_complete-sales_rep.html\"-->";
#$_ = encode_qp( ssi::variable_substitution( \$email_template, \%info ) );
#my @body = ('', $_, 'text/html', 'quoted-printable');
#my %mail = (
#SMTP	=> $config{'Mail Server'},
#FROM	=> sprintf( "%s %s <%s>", @info{'EmployeeFirstName','EmployeeLastName','EmployeeEmail'}),
#TO	  => $sales_person_email,
#SUBJECT => "Docket $info{DocketNumber} Proofs Complete",
#);
#misc::send_email_with_attachment( $log, \%mail, @body );
#} # end if
} # end sub send_proofs_complete_email

sub send_proofs_client_approved_email {
  my ( $project_index, $order_id ) = @_;
# Send email to sales rep
  my %info;
  $info{SecureSiteURL} = $config{ExternalSecureSiteURL};
  $info{siteURL} = $config{ExternalSiteURL};

  my $Project = new openprint::Project( $project_index );
  $order_id = $Project->order_id() if ! $order_id;
  @info{'DocketNumber','ProjectReference','ProjectIndex','OrderID'} = ( $Project->docket(), $Project->reference(), $project_index, $order_id );

  my $Order = new openprint::Order( $order_id );
  @info{'CustomerFirstName','CustomerLastName','CustomerEmail'} = ( $Order->firstname(), $Order->lastname(), $Order->email() );

  @info{'EmployeeFirstName','EmployeeLastName','EmployeeEmail','EmployeeExtension'} = $openprint::User->get(qw(firstname lastname email extension) );

  $info{CompletionDate} = Date::Format::time2str( $config{DateTimeFormat}, time );

  $info{ReplacementText} = ssi::include( '/email_content/proofs_client_approved-sales_rep.html', \%info );
  my $Email = new openprint::Email();
  $Email->html_body( ssi::include( '/email_template.html', \%info ) );

  my $CSR = $Order->CSR();
  my @Users = map { $_->User() } openprint::User_Notification->find( type =>'Proofs Client Approval Notifications', value =>'Yes',
      'company_id is null or =' => $Project->company_id(),
      user_company_id=>[$Project->company_id(), $openprint::User->company_id(), ( $CSR->id() ? $CSR->company_id() : () ) ] );

  if ( ! sets::isin( $CSR->id(), [ map { $_->id() } @Users ] ) ) {
    my $Notification = $CSR->notification('Proofs Client Approval Notifications');
    push @Users, $CSR if (!$Notification) or ( $Notification ne 'No' );
  } # end if

  my $results;
  foreach my $User ( @Users ) {
    next if $User->id() == $session{user_id};
    next if $User->deleted();

    $results .= $Email->send(
        FROM  => $openprint::User,
        TO    => $User,
        SUBJECT => "Docket $info{DocketNumber} $$Order{company_name} - Proofs Client Approved",
        );
  } # end if
  $Project->add_to_log( @session{'company_id','user_id'}, "Proofs client approved email sent to $results" );
} # end sub send_proofs_client_approved_email

sub send_proofs_approved_email {
	my ( $project_index, $order_id ) = @_;
# Send email to sales rep
	my %info;
	$info{SecureSiteURL} = $config{ExternalSecureSiteURL};
	$info{siteURL} = $config{ExternalSiteURL};

	my $Project = new openprint::Project( $project_index );
	$order_id = $Project->order_id() if ! $order_id;
	@info{'DocketNumber','ProjectReference','ProjectIndex','OrderID'} = ( $Project->docket(), $Project->reference(), $project_index, $order_id );
	$info{DueDate} = Date::Format::time2str( $config{DateFormat}, Date::Parse::str2time( $Project->due_date() ) );

	my $Order = new openprint::Order( $order_id );
	@info{'CustomerFirstName','CustomerLastName','CustomerEmail'} = ( $Order->firstname(), $Order->lastname(), $Order->email() );

	@info{'EmployeeFirstName','EmployeeLastName','EmployeeEmail','EmployeeExtension'} = $openprint::User->get(qw(firstname lastname email extension) );

	$info{CompletionDate} = Date::Format::time2str( $config{DateTimeFormat}, time );

	$info{ReplacementText} = ssi::include( '/email_content/proofs_approved-sales_rep.html', \%info );
	my $Email = new openprint::Email();
	$Email->html_body( ssi::include( '/email_template.html', \%info ) );

	my $CSR = $Order->CSR();
	my @Users = map { $_->User() } openprint::User_Notification->find( type =>'Proofs Approval Notifications', value =>'Yes',
			'company_id is null or ='	=> $Project->company_id(),
			user_company_id=>[$Project->company_id(), $openprint::User->company_id(), ( $CSR->id() ? $CSR->company_id() : () ) ] );

	if ( ! sets::isin( $CSR->id(), [ map { $_->id() } @Users ] ) ) {
		my $Notification = $CSR->notification('Proofs Approval Notifications');
		push @Users, $CSR if (!$Notification) or ( $Notification ne 'No' );
	} # end if

	my $results;
	foreach my $User ( @Users ) {
		next if $User->id() == $session{user_id};
		next if $User->deleted();
		
		$results .= $Email->send(
				FROM	=> $openprint::User,
				TO	  => $User,
				SUBJECT => "Docket $info{DocketNumber} $$Order{company_name} - Proofs Approved",
				);
	} # end if
	$Project->add_to_log( @session{'company_id','user_id'}, "Proofs approved email sent to $results" );
} # end sub send_proofs_approved_email

sub send_duedate_change_notification {
	my ( $project_index, $order_id ) = @_;

# Send email to sales rep
	my %info;

	$info{ProjectIndex} = $project_index;
	$info{OrderID} = $order_id;
	my $Order = new openprint::Order( $order_id );

	my $Project = new openprint::Project( $project_index );
	$info{DueDate} = Date::Format::time2str( $config{DateFormat}, Date::Parse::str2time( $Project->due_date() ) );

	my $User = $openprint::User;
	@info{'EmployeeFirstName','EmployeeLastName','EmployeeEmail','EmployeeExtension'} = ( $User->firstname(), $User->lastname(), $User->email(), $User->extension() );
	my $CSR = new openprint::User( $Order->salesrep_id() );
	if ( $CSR->email() and ! $CSR->deleted() ) {
		my $notification = $CSR->notification('Docket Due Date Changes');
		if ( $notification and ( $notification ne 'No' ) ) {
			my $email_template = ssi::slurp_content( '/email_template.html' );
			$info{ReplacementText} = ssi::include( '/email_content/proofs_duedate_change-sales_rep.html', \%info );
			my $results = (new openprint::Email())->send(
					FROM	=> $User,
					TO	  => $CSR,
					SUBJECT => "Docket $info{DocketNumber} DueDate Changed",
					HTML_BODY 	=> ssi::variable_substitution( \$email_template, \%info ),
					);
			$Project->add_to_log( @session{'company_id','user_id'}, "due date changed email sent to $results" );
		} # end if Notifications
	} # end if
} # end sub send_duedate_change_notification

sub is_sig_complete {
	my ( $Project, $signature_service_index ) = @_;

	my $Service = $Project->Service( $signature_service_index );
	my $sig_specs = $Service->specs();
	if ( $param{"rdbPressComplete-$$sig_specs{SignatureIndex}"} ne 'Yes' ) {
		if ( $Service->status() ne 'Ordered' ) {
			$Project->add_to_log( @session{'company_id','user_id'}, "Marking form $$sig_specs{SignatureIndex} incomplete." );
			$Service->save({status=>'Ordered'});
		}
		return 0;
	} # end if
	if ( $Service->status() ne 'Complete' ) {
		$Project->add_to_log( @session{'company_id','user_id'}, "Marking form $$sig_specs{SignatureIndex} complete." );
		$Service->save({status=>'Complete'});
	}

# Remove jobs from the Schedule when marked complete.
	foreach my $Job ( openprint::ScheduledJob->find( project_id => $$Project{id}, 'service_id @>' => $signature_service_index ) ) {
		$Job->delete();
	} # end foreach

	return 1;
} # end sub is_sig_complete

sub docket_sheet {
	openprint::print_project::summary( @_ );
} # end sub docket_sheet
sub summary {
	openprint::print_project::summary( $r, $log, $dbh, \%variable, $param{ProjectIndex} );
} # end sub summary

sub stock_checkout {
	_stock_checkout();
}

sub _stock_checkout {
	my $Order;
	$variable{Project} = new openprint::Project($param{project_id}) if $param{project_id};

	if ( $param{docket} ) {
		$Order = openprint::Order->find_one(docket=>$param{docket});
		if ( ! $Order ) {
			$variable{error} .= 'No docket found for ' . $param{docket} . '<br/>';
			return;
		} # end if
		$variable{Project} = openprint::Project->find_one( docket=>$param{docket} ) if ! $variable{Project};
	} else {
		$log->error("NO docket in _stock_checkout");
		return;
	} # end if
	$variable{Order} = $Order;

	if ( $param{action} eq 'Add' ) {
		$param{skid_id} =~ s/\D//g;
		$param{rfidtag_id} = openprint::RFIDTag->transform( 'id', $param{rfidtag_id} );
		my $Skid;
		if ( $param{skid_id} ) {
			$Skid = openprint::Skid->find_one( id=>$param{skid_id} );
		} elsif ( $param{rfidtag_id} ) {
			my $RFIDTag = openprint::RFIDTag::from_id( $param{rfidtag_id} );
			if ( ! $RFIDTag ) {
				$variable{error} .= 'RFID Tag ' .  $param{rfidtag_id} . ' is not in the system.<br/>';
			} else {
				$Skid = $RFIDTag->Skid();
			} # end if
		} else {
			$variable{error} .='Please scan the barcode on the skid label or rfid tag.<br/>';
		} # end if
		if ( ! ( $Skid and $Skid->id() ) ) {
			$variable{error} .= 'Unknown skid scanned.<br/>';
			return;
		} # end if

		my $add_entry = 1;

		if ( openprint::PaperInventory->find_one( docket => $Order->docket(), skid_id	 =>  $Skid->id() ) ) {
# What about if it was added back in?
			$variable{error} .= 'Skid/Roll has already been checked out for this docket.';
			return;
		}

		if ( $Skid->is_empty() ) {
			my @PI = openprint::PaperInventory->find( skid_id=>$Skid->id(), 'comment like'=>'Checked out%', order=>'updated_on desc');
			if ( @PI ) {
				$variable{error} .= sprintf( '%1$s %2$d has already been checked out', $PI[0]->Skid()->type(), $Skid->id() );
				if ( $PI[0]->docket() ) {
					$variable{error} .= sprintf(' for docket <a href="/employee/project/view.html?docket=%1$d">%1$d</a>', $PI[0]->docket() );
				} # end if
				$variable{error} .= '.<br/>';
			} # end if

			foreach my $PI ( @PI ) {
				if ( ! $PI->docket() ) {
					$PI->save({docket=>$Order->docket()});
					$add_entry = 0;
					# only update the most recent entry
					last;
				} else {
					if ( $PI->docket() == $Order->docket() ) {
						$add_entry = 0;
						last;
					} # end if	
				} # end if
			} # end foreach PI
		} # end if

		if ( $add_entry ) {
			$Skid->checkout( $Order->docket() );
		} # end if add_entry
	} # end if action eq Add
} # end sub _stock_checkout

sub _production_feedback {
	if ( $param{action} eq 'add' ) {
		my $PF= new openprint::ProductionFeedback();
		$variable{error} .= $PF->save({
				project_id	=>	$param{project_id},
				service_id	=>	$param{service_id},
				user_id		=>	$session{user_id},
				starting_on	=>	$param{starting_on},
				ending_on	=>	$param{ending_on},
				comment		=>	$param{comment},
			});
	} # end if
	$variable{project_id} = $param{project_id};
	$variable{Project} = new openprint::Project( $param{project_id} );
	$variable{service_id} = $param{service_id};
} # end sub _production_feedback

sub stock_allocations {
	_stock_allocations();
}

sub _stock_allocations {
	$variable{Order} = openprint::Order->find_one( docket=>$param{docket} );
	if ( $param{action} eq 'delete' ) {
		foreach my $Allocation ( openprint::PaperAllocation->find( id=>[ split(',', $param{allocation_id} ) ] ) ) {
			if ( $Allocation->can_delete() ) {
				if ( $_ = $Allocation->delete() ) {
					$variable{error} .= $_.'<br/>';
				} else {
					$variable{information} .= "Allocation $$Allocation{id} deleted successfully.<br/>";
				}
			} else {
				$variable{error} .= 'You are not authorized to delete this allocation.<br/>';
			}
		}
	}
}

sub _signaturecapture {
	$variable{Signature} = new openprint::SignatureCapture( $param{id} );
}

# service_id may be a comma-separated list of services.  It is assumed that these services are the same type.
sub _status {
	@variable{'ProjectIndex','index'} = @param{'project_id','service_id'};
	my $Project = $variable{Project} = new openprint::Project( $param{project_id} );

	my @service_ids = split(',',$param{service_id});
	my $Service = $Project->Service($service_ids[0]);
	$variable{status} = $Service->status();
	$variable{name} = $Service->ServiceType()->name();
	$variable{name} = 'Printing' if ! $variable{name};

	if ( $param{action} eq 'removefromschedule' ) {
		foreach my $service_id ( @service_ids ) {
			my $Job = openprint::ScheduledJob->find_one(project_id=>$param{project_id}, 'service_id @>'=>$service_id);
			if ( ! $Job ) {
				$variable{error} .= 'Job not found on schedule.';
			} else {
				my @service_ids = sets::exclude( [ $service_id ], $Job->service_id() );
				if ( ! @service_ids ) {
					$variable{error} .= $Job->delete();
				} else {
					$variable{error} .= $Job->save({service_id=>\@service_ids});
				} # end if
				if ( ! $variable{error} ) {
					my @forms;
					foreach my $s_id ( $Job->pertains_id() ? @{$Job->pertains_id()} : () ) {
						my $S = $Project->Service($s_id);
						my $specs = $S->specs();
						push @forms, $$specs{SignatureIndex};
					} # end foreach
			
					$Project->add_to_log( @session{'company_id','user_id'}, "Removed " . $Service->ServiceType->name() . " form @forms from schedule." );
				} # end if
			} # end if
		} # end foreach service_id
	} elsif ( $param{action} eq 'addtoschedule' ) {
		my $NewShift;
    if ( $param{shift_id} and Date::Calc::check_date( map { $param{'starttime_'.$_} } ( 'year', 'month', 'day' ) ) ) {
# We assume that there is a shift, otherwise how can we be scheduling?
      my $starttime_dt = DateTime->new(
          ( map { $_ => $param{'starttime_'.$_} } ( 'year','month','day' ) ),
          hour=>0, minute=>0, second=>0, time_zone=>$openprint::TZ );
      my $endtime_dt = DateTime->new(
          ( map { $_ => $param{'starttime_'.$_} } ( 'year','month','day' ) ),
          hour=>23, minute=>59, second=>59, time_zone=>$openprint::TZ );
      $NewShift = openprint::Shift->find_one(
          'starttime >='  =>  $openprint::parser->format_datetime($starttime_dt),
          'starttime <='  =>  $openprint::parser->format_datetime($endtime_dt),
          ( $param{shift_id} ? ( shift_id       =>  $param{shift_id}) : () ),
          equipment_id    =>  $param{equipment_id},
          );
    } else {
      $log->debug("No valid startdate specified");
    }

		my $Job = new openprint::ScheduledJob();
		$_ = $Job->save({
				project_id			=>  $param{project_id},
				equipment_id 	  =>  $param{equipment_id},
				starttime	 			=>  ( $NewShift ? $NewShift->starttime() : undef ),
				service_id			=>  [ split(',',$param{service_id}) ],
				servicetype_id	=>  $Service->ServiceType->id(),
				});
		if ( $_ ) {
			$variable{error} .= 'Error adding to press schedule: ' . $_;
		} else {
			if ( sets::isin( $variable{name}, 'Printing','Signature' ) ) {
				my $sig_specs = $Service->specs();
				$Job->Project()->add_to_log( @session{'company_id','user_id'}, "Added Form $$sig_specs{SignatureIndex} to schedule for " . $Job->Equipment()->strid() );
			} else {
				$Job->Project()->add_to_log( @session{'company_id','user_id'}, "Added " . $Service->ServiceType->name() . " to schedule." );
			} # end if
			if ( $NewShift ) {
				$Job->bump( undef, $NewShift );
			}
		} # end if

	} # end if
} # end sub _status

# service_id could be a comma-separated list of services
sub _add_to_schedule {
	@variable{'ProjectIndex','index'} = @param{'project_id','service_id'};
	my @service_ids = split(',',$param{service_id});

	my $Service = new openprint::Project_Service( {
			project_id	=>	$param{project_id},
			service_id	=>	$service_ids[0],
			} );
	my $Job = $variable{Job} = new openprint::ScheduledJob();
	$Job->set({
		project_id		=>	$param{project_id},
		service_id		=>	\@service_ids,
		servicetype_id	=>	$Service->ServiceType->id(),
		});
} # end sub _add_to_schedule

sub _status_dropdown {
	my $Project = $variable{Project} = new openprint::Project( $param{project_id} );
	my $Service = $variable{Service} = $Project->Service( $param{service_id} );
} # end sub _status_dropdown

sub _modification_history {
	if ( $param{project_id} ) {
		my $Project = $variable{Project} = new openprint::Project($param{project_id});
	}
		ssi::save_params('/employee/project/modification_log.html', 'project_id', 'operator_id', 'salesrep_id','StartDocket',
			( map { 'action_date_start_'.$_ } ( 'year', 'month', 'day', 'hour','minute' ) ),
			( map { 'action_date_end_'.$_ } ( 'year', 'month', 'day', 'hour','minute' ) ),
			'search',
				);
} # end sub _modification_history

sub modification_log {
	_modification_history();
	ssi::setup_date_select( '/employee/project/modification_log.html', 'action_date_start', -7 );
	ssi::setup_date_select( '/employee/projcet/modification_log.html', 'action_date_end', '' );
} # end sub modification_log

sub production_log {
} # end sub production_log

sub _production_log {
	my $Project = $variable{Project} = new openprint::Project($param{project_id});
	ssi::save_params('/employee/project/view.html?production_log', 'project_id');
} # end sub _production_log

sub _dearchive {
} # end sub _dearchive

sub _additional_charge_notifications {
	require openprint::Order_Notification;

	$variable{formname} = $param{formname};
	my $Project = $variable{Project} = new openprint::Project( $param{project_id} );
	return if ( ! $Project->id() );
	my $Order = $variable{Order} = $Project->Order();
	return if ! $Order->id();

	my %Notifications = map { $_->email(), $_ } $Order->AdditionalChargeNotifications();

	if ( $param{AdditionalEmailRecipients} ) {
		foreach my $email ( split(',',lc $param{AdditionalEmailRecipients}) ) {
			if ( ! $Notifications{$email} ) {
				my $U = openprint::User->find_one(email=>$email);
				if ( ! $U ) {
					$U = new openprint::User();
					$U->save({ email=>$email, company_id=>$Project->company_id() } );	
				} # end if
				my $ON = new openprint::Order_Notification();
				$ON->save({order_id=>$$Project{order_id}, user_id=>$$U{id}});
				$Order->AdditionalChargeNotifications( undef );
				$param{notify_user_id} = ref $param{notify_user_id} eq 'ARRAY' ? [ @{$param{notify_user_id}}, $$U{id} ] : [ $param{notify_user_id}, $$U{id} ];
			} # end if
		} # end foreach email
	} # end if Additional

	if ( $param{action} eq 'Send' ) {
		my @Notifications = openprint::Order_Notification->find(order_id=>$$Project{order_id}, ( $param{notify_user_id} ? ( user_id => $param{notify_user_id} ) : () ) );
		$_ = send_additional_charges_notifications( @$Project{'order_id','id'}, $param{additionalchargecomments}, @Notifications );
		$variable{information} = 'Additional Charges Email sent.' . $_;
	} # end if action 
} # end sub _additional_charge_notifications 

sub _change {
	if ( $param{action} ) {
		if ( $param{action} eq 'setduedate' ) {

			my $Project = openprint::Project->find_one( id=>$param{project_id} );
			if ( ! $Project ) {
					$log->error("Project $param{project_id} not found in set_duedate");
					return;
			} # end if
			$Project->change_due_date($param{duedate});
		} else {
			$log->error("Unrecognized action $param{action} in project _change");
		} # end if action
	} else {
		$log->error("No action in project _change");
	} # end if action
} # end sub _change

sub _related_projects {
}

1;
__END__
