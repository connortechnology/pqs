use strict;
package openprint::print_project;

use openprint ();
use vars qw( $r $log $dbh %session %param %variable );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*session = \%openprint::session;
*param = \%openprint::param;
*variable = \%openprint::variable;

require sql;
require openprint::account;
require openprint::service;
require openprint::ServiceType;
require openprint::ProjectType;
require openprint::ProjectType_Default;
require openprint::Project_Service;
require openprint::Project;
require openprint::Currency;
require openprint::User;
require openprint::logs;
require openprint::Estimating::MultiPage;
require Math::Round;

# Projects are like Orders, in that you can have several in here, but only ONE of them may be unfinished.

sub insert_project_type {
	my ( $r, $log, $dbh, $project_index, $project_type_id ) = @_;

	my $ProjectType = openprint::ProjectType->find_one(name=>$project_type_id);
	if ( !$ProjectType ) {
		$log->error( "Couldn't get project index for $project_type_id" );
		return;
	} # end if

	# Make this all one transaction...
	my $ac = sql::start_transaction( $dbh );

	sql::insert( $log, $dbh, 'tbl_Project_Contents', [
		'lngProjectIndex',	$project_index,
		'strStatus',	'uncalculated' ] );
	$_ = q{SELECT MAX(lngServiceIndex) FROM tbl_Project_Contents WHERE lngProjectIndex=?};
	my ( $service_index ) = sql::execute( $log, $dbh, $_, $project_index );
	sql::insert( $log, $dbh, 'tbl_Service_Specifications', [
		'lngProjectIndex',	$project_index,
		'lngServiceIndex',	$service_index,
		'strName',			'ProjectType',
		'strValue',		 $ProjectType->name(),
		] );

	my @defaults = map { $$_{name}, $$_{value} } openprint::ProjectType_Default->find(
			'projecttype_id is null or ='=> $ProjectType->id(), 
			'order'=>'projecttype_id NULLS FIRST' );

	if ( $session{user_id} ) {
		$_ = q{SELECT name, value FROM User_Service_Defaults WHERE servicetype_id IS NULL AND user_id=?};
		push @defaults, sql::execute( $log, $dbh, $_, $session{user_id} );
	} # end if
	
	if ( $param{txtConventionalPlates} == 1 ) {
		push @defaults, 'rdbPlates','Conventional';
	} else {
		push @defaults, 'rdbPlates','CTP';
	} # end if

	push @defaults, 'SignatureIndex', '0';
	my %defaults = @defaults;
	foreach my $key ( keys %defaults ) {
		openprint::service::insert_service_spec( $log, $dbh, $project_index, $service_index, $key, $defaults{$key}, 1 );
	} # end while
	my $Project = new openprint::Project( $project_index );
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		openprint::service::insert_service_spec( $log, $dbh, $project_index, $service_index, "txtQuantity$qty_index", $Project->quantity($qty_index), 1 );
	} # end foreach
	sql::end_transaction( $dbh, $ac );
	delete $$Project{Services};
	delete $$Project{signatures};
	return $service_index;
} # end sub insert_project_type

sub add_service {
# THis is an external wrapper for insert_service
	my ( $r, $log, $dbh, $variable, $project_index, @services ) = @_;
	my $Project = new openprint::Project( $project_index );
	# refresh the services
	my $services = $Project->services(undef);
	foreach my $service_id ( @services ) {
		if ( ! $$services{$service_id} ) {
			$Project->add_service( $service_id );
		} # end if
	} # end foreach
} # end sub add_service


sub get_incomplete_services_in_category {
	my ( $Project, $category ) = @_;

	if ( $category eq 'Printing' ) {
		my $services = $Project->services();

		if ( $$services{Signature} ) {
			foreach my $index ( @{$$services{Signature}} ) {
				# I switched this from ne calculated to handle statuses like ordered, complete, etc.
				if ( openprint::service::status( $Project->id(), $index ) eq 'uncalculated' ) {
					return $index;
				} # end if
			} # end foreach
		} # end if
		return;
	} else {
		my @ServiceTypes = openprint::ServiceType->find(category=>$category);
		return map { $_->service_id() } openprint::Project_Service->find(
				servicetype_id => [ map { $_->id() } @ServiceTypes ],
				project_id		 => $$Project{id},
				status				 => 'uncalculated'
				);
	} # end if
} # end sub get_incomplete_services_in_category

sub get_redirect_for_service {
	my ( $log, $dbh, $project_index, $service_index ) = @_;

	my $ServiceType = new openprint::ServiceType( sql::execute( undef, undef, q{SELECT servicetype_id FROM tbl_Project_Contents WHERE lngProjectIndex=? AND lngServiceIndex=?}, $project_index, $service_index ) );
	return '/main/project/'.$ServiceType->url();

} # end sub get_redirect_for_service

sub choose_service {
	my ( $log, $dbh, $project_index ) = @_;

	my @incomplete_services = sql::execute( $log, $dbh,
			"SELECT lngServiceIndex FROM tbl_Project_Contents WHERE lngProjectIndex=?
			AND (strStatus IS NULL or strStatus ='uncalculated')", $project_index );
	if ( ! @incomplete_services ) {
		# Quick shortcut.	If there aren't any, then stop looking.
		$log->debug("***************** NO IMCOMPLETE SERVICES FOUND ***********************");
		return ( '', '' );
	} # end if

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();

	# get the printing service
	if ( $$services{''} ) {
		$log->debug("Have a printing service");
		my $status = openprint::service::status( $Project->id(), $$services{''}[0] );
		
		# if the printing service is unfinished, return it.
		# the no url test will only occurr for the "no printing required" project type :)
		if ( $status eq 'uncalculated' ) {
			$log->debug("Printing service status $status uncalcaulted");
			return ( $$services{''}[0], '/main/project/'.$Project->Type()->url() ) if $Project->Type()->url();
			$log->debug("Project Type does not have a url");
			if ( ! $$services{Signature} ) {
				# There are no signatures, so .... 
				return (undef,undef);
			} # end if
		} else {
			$log->debug("Printing service status ($status)");
		} # end if
	} else {
		$log->debug("No printing service?");
	} # end if

	$log->debug("****** GETTING INCOMPLETE PRINTING SERVICES ********");
	foreach my $service_index ( get_incomplete_services_in_category( $Project, 'Printing' ) ) {
		$log->debug("****** SERVICE: $service_index is incomplete ********");
		my $url = get_redirect_for_service( $log, $dbh, $project_index, $service_index );
		return ( $service_index, $url ) if $url ne '';
	} # end while
	$log->debug("****** FOUND NO INCOMPLETE PRINTING SERVICES ********");
	
	$_ = "SELECT strValue, lngServiceIndex FROM tbl_Service_Specifications WHERE lngProjectIndex=?".
		" AND strName='ServiceType' AND strValue != 'Signature' AND lngServiceIndex IN (".join(',',@incomplete_services).")";
	my @project_services = sql::execute( $log, $dbh, $_, $project_index );

	foreach my $ServiceType ( openprint::ServiceType->find('url is null'=>0, 'url !='=>'', order=>'sorting') ) {
		if ( $$services{$ServiceType->name()} ) {
			my @incomplete = sets::intersection( @incomplete_services, @{$$services{$ServiceType->name()}} );
			if ( @incomplete ) {
				return ( $incomplete[0], '/main/project/'.$ServiceType->url() );
			} # end if	
		} # end if
	} # end foreach ServiceType

	return ( '', '' );
} # end sub choose_service

# What the hell does this function do?
# As far as I can tell, it get's called if the ContinueProject param is Y, or if someone hits the continue project button on project view.	What it does is pick an uncalculated service using choose_service, and that's about it.	Just a little glue to hold things together.	Unfortunately the glue is ugly, and I'm not sure why it's needed.	It might not be needed anymore.
# The glue basiscally makes it look like someone clicked on the service link on the project view page, so it sets params ProjectIndex,and ServiceIndex, and sets the redirect.
sub continue_project {
	my ( $Project ) = @_;
	my $incoming_service_index = $param{ServiceIndex};

	if ( $variable{Redirect} ne '' ) {
		$log->debug('END PROJECT CONTINUE REDIRECT IS ALREADY '.$variable{Redirect});
		return;
	}
	$log->debug('STARTING continue_project');

	my ( $service_index, $redirect ) = choose_service($log, $dbh, $$Project{id}, $incoming_service_index);

	if ( ! $service_index ) {
			$log->debug('No service_index for '.$Project->to_string());
		my $type = $Project->Type()->type();
		if ( !$type ) {
			$log->debug('No type for '.$Project->to_string());
			return;
		} else {
			my $module = 'openprint::Estimating::'.$type;
			if ( my $function = $module->can('status') ) {
				foreach my $qty_index ( $Project->quantity_indexes() ) {
					if ( $_ = $function->( $$Project{id}, undef, $qty_index ) ) {
						$log->debug($type. ' status says we need another sig of type '.$_);
						my @sigs = $Project->signatures({Group=>$_});
						my $src_id = pop @sigs;
						my $src_specs = openprint::service::get_specs_ref( $Project, $src_id );
						$service_index = $Project->copy_signature( $src_specs );
						( $service_index, $redirect ) = choose_service( $log, $dbh, $$Project{id} );
						last;
					} else {
						$log->debug("Multpage status says we ok for qty $qty_index");
					} # end if
				} # end foreach
			} else {
				$log->debug("Dont have a status function for $module");
			} # end if
		} # end if !type
	} # end if ! $service_index

	if ( $redirect ne '' and $service_index != $incoming_service_index ) {
#plugin new service.
		$variable{ExternalRedirect} = $redirect . '?'.join('&', 'ProjectIndex='.$$Project{id}, 'ServiceIndex='.$service_index);;
	} # end if

	$log->debug('END PROJECT CONTINUE REDIRECT IS '.$variable{ExternalRedirect});
} # end sub continue_project 

sub try_to_delete_project {
	my ( $log, $dbh, $variable, $project_index ) = @_;
	my $error = '';
	my $delete = 1;

	my $Project = new openprint::Project( $project_index );
	my $proj_reference = $Project->reference();

	if (($$openprint::User{type} ne 'A' ) and ($Project->company_id() != $session{company_id})) {
		$error .= "Project $proj_reference does not belong to you.	Not deleted.<br/>";
		$delete = 0;
	} # end if
	$_ = "SELECT orders.id FROM Orders,Order_Contents WHERE orders.id=Order_Contents.OrderIndex AND lngProjectIndex=? AND Orders.status_id != (SELECT id FROM order_statuses WHERE name ='Incomplete')";
	( $_ ) = sql::execute( $log, $dbh, $_, $project_index );
	if ( $_ ) {
		$error .= "Project $proj_reference is in order <a href=\"/main/order/history_details.html?order_id=$_\">$_</a>.	You must delete the order before you can delete the project.<br/>";
		$delete = 0;
	} # end if
	$_ = "SELECT Quotes.id FROM Quotes,tbl_Quote_Details WHERE Quotes.id=tbl_Quote_Details.quote_id AND project_id=? AND Quotes.strStatus != 'Incomplete'";
	( $_ ) = sql::execute( $log, $dbh, $_, $project_index );
	if ( $_ ) {
		$error .= "Project $proj_reference is in quote <a href=\"/main/quote/history_details.html?quote_id=$_\">$_</a>.	You must delete the quote before you can delete the project.<br/>";
		$delete = 0;
	} # end if
	if ( $delete ) {
		$Project->delete();
	} # end if
	return $error;
} # end sub try_to_delete_project

sub view_pdfs {
	my ( $r, $log, $dbh, $variable ) = @_;

	my $project_index = $param{ProjectIndex};
	$_ = "SELECT strFileName, strDescription FROM tbl_Project_PDFs WHERE lngProjectIndex=?";
	@{$$variable{PDFS}} = sql::execute( $log, $dbh, $_, $project_index );

	$$variable{ProjectIndex} = $project_index;
} # end sub view_pdfs

# Returns an array of pairs (ServiceIndex, ProductIndex)
sub get_services_in_category {
	my ( $log, $dbh, $project_index, $category) = @_;
	my @services;

	if ( $category eq 'Printing' ) {
#The entire point of this is to sort the signature groups
		if ( my @ServiceTypes = openprint::ServiceType->find('name'=>'Signature') ) {
			$_ = "SELECT lngServiceIndex FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND strName = 'txtSignatureType' AND strValue IN ('Interior Pages','Gate Folded Pages','Cover Pages') ORDER BY lngServiceIndex";
			my @signatures = sql::execute( $log, $dbh, $_, $project_index );
			
			while ( @signatures ) {
				push @services, shift @signatures, $ServiceTypes[0];
			} # end while
		} # end if
	} else { 
		my @ServiceTypes = openprint::ServiceType->find('category'=>$category);
		@services = map { $_->service_id(), $_->servicetype_id() } openprint::Project_Service->find( 'servicetype_id'=>[ map { $_->id() } @ServiceTypes ], 'project_id'=>$project_index );
	} # end if
	return @services;
} # end sub get_services_in_category

sub summary {
	my ( $r, $log, $dbh, $variable, $project_index ) = @_;
	my ( @services );

	$log->debug("************************* START OF PROJECT SUMMARY **********************************");

	$project_index = $param{ProjectIndex} if ! $project_index;
	if ( ! $project_index ) {
		$$variable{Project} = new openprint::Project();
		$$variable{Order} = new openprint::Order();
		return;
	} # end if

	my $Project = $$variable{Project} = new openprint::Project( $project_index );
	$$variable{Order} = $Project->Order();
	$$variable{OrderId} = $Project->order_id();
	my $services = $Project->services();
	$$variable{Services} = $services;

	if ( $$services{''} and @{$$services{''}} ) {
		my $ProjectType = $Project->Type();
		# print service comes first
		@$variable{'ProjectTypeName','ProjectTypeURL'} = ( $ProjectType->name(), $ProjectType->url() );

		@services = ( $$services{''}[0], 'Printing', $$variable{ProjectTypeURL} );

		openprint::print_project::get_service_specifications( $r, $log, $dbh, $variable, $project_index, $$services{''}[0] );
	} else {
		Carp::cluck( "No ProjectService in Project $$Project{id}");
	} # end if

	foreach my $sig_id ( $Project->signatures( { sort => 1 } ) ) {
		my $Service = $Project->Service( $sig_id );
		my $Type = $Service->ServiceType();
		push @services, $sig_id, $Type->name(), $Type->url();
	} # end foreach signature

	foreach my $ServiceCategory ( openprint::ServiceType_Category->find( order=>'sorting,name') ) {
		foreach my $ServiceType ( openprint::ServiceType->find( category_id=>$$ServiceCategory{id}, order=>'sorting' ) ) {
			next if ! $$services{$$ServiceType{name}};
			next if $ServiceType->name() eq 'Signature';
			foreach my $s_id ( @{$$services{$$ServiceType{name}}} ) {
				my $Service = $Project->Service( $s_id );
				push @services, $s_id, $ServiceType->name(), $ServiceType->url();
			} # end foreach
		} # end foreach
	} # end foreach signature
	$$variable{SERVICES} = \@services;
	
	$$variable{TOTAL1} = Math::Round::nearest( 0.01, $Project->price1() );
	$$variable{TOTAL2} = Math::Round::nearest( 0.01, $Project->price2() );
	$$variable{TOTAL3} = Math::Round::nearest( 0.01, $Project->price3() );

	$$variable{UNITPRICE1} = $$variable{txtQuantity1} ? sprintf( "%.2f", $$variable{TOTAL1}/$$variable{txtQuantity1} ) : '0.00';
	$$variable{UNITPRICE2} = $$variable{txtQuantity2} ? sprintf( "%.2f", $$variable{TOTAL2}/$$variable{txtQuantity2} ) : '0.00';
	$$variable{UNITPRICE3} = $$variable{txtQuantity3} ? sprintf( "%.2f", $$variable{TOTAL3}/$$variable{txtQuantity3} ) : '0.00';

	$$variable{ProjectIndex} = $project_index;
	$$variable{NoPriceBreakDown} = $param{NoPriceBreakDown};

	@{$$variable{PrintingServices}} = $Project->signatures();
	# new stuff

	$$variable{ProofServiceIndex}	= $$services{Proofs} ? $$services{Proofs}[0] : $$services{FilmStripping}[0];
	if ( ! $$variable{ProofServiceIndex} ) {
		Carp::cluck( "No ProofServiceIndex in Project $$Project{id}");
	} # end if

	my $Currency = openprint::Currency::get_current();
	if ( $Currency ) {
		@$variable{'Currency','CurrencyName', 'CurrencySymbol'} = ( $Currency, $Currency->name(), $Currency->symbol() );
	} # end if
} # end sub summary

sub get_proof_colours {
# this function is used for summary pages in employee and admin sections.
	my ( $r, $log, $dbh, $variable, $project_index, $service_index, $proof_index ) = @_;

	$$variable{chkProcessColourSideOne} = '';
	$$variable{chkProcessColourSideTwo} = '';
	$$variable{chkBlackColourSideOne} = '';
	$$variable{chkBlackColourSideTwo} = '';

	$_ = 'SELECT lngServiceIndex FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND strName=? AND strValue=?';
	my ($index) = sql::execute( undef, undef, $_, $project_index, 'SignatureIndex',$proof_index );

	my %specs = openprint::service::get_specifications_pairs( $log, $dbh, $project_index, $index );
	foreach my $key ( keys %specs ) {
		if ( $key =~ /Colour/ and $specs{$key} =~ /Black/ ) {
			$$variable{$key} = $specs{$key};
		} # end if
	} # end foreach
} # end sub


sub get_service_specifications {
# this function is used for summary pages in employee and admin sections.
	my ( $r, $log, $dbh, $variable, $project_index, $service_index ) = @_;

	if ( $project_index and $service_index ) {
		$$variable{txtServiceDescription} = '';
		$$variable{ddmRunStyle} = '';
		$$variable{ServiceName} = '';

		my $Project = new openprint::Project( $project_index );

		# Get the Product Index
		my ( $service_type_id ) = openprint::service::get_specifications( $log, $dbh, $project_index, $service_index, 'ServiceType' );

		if ( ! $service_type_id ) {
# Maybe it's a project type
			my $PT = $Project->Type();
			$$variable{ServiceTypeID} = $PT->name();
			$$variable{ServiceTypeName} = 'Printing';
		} else {
			my $Service = $Project->Service( $service_index );
			$$variable{ServiceType} = $Service->ServiceType();
			@$variable{'ServiceTypeID','ServiceTypeName'} = ( $$variable{ServiceType}->name(), $$variable{ServiceType}->description() ) if $$variable{ServiceType};
		} # end if

		# Do Specific Stuff
		if ( $service_type_id eq 'Perforating' ) {
			my $specs = openprint::service::get_specs_ref( $Project, $service_index );
			foreach my $name ( keys %$specs ) {
				$$variable{$name} = $$specs{$name};
			} # end foreach
			require openprint::Estimating::Perforating;
			openprint::Estimating::Perforating::get_specs( $log, $dbh, $variable, $project_index, $service_index );
		} elsif ( $service_type_id eq 'Scoring' ) {
			my $specs = openprint::service::get_specs_ref( $Project, $service_index );
			foreach my $name ( keys %$specs ) {
				$$variable{$name} = $$specs{$name};
			} # end foreach
			require openprint::Estimating::Scoring;
			openprint::Estimating::Scoring::get_specs( $log, $dbh, $variable, $project_index, $service_index );
		} elsif ( $service_type_id eq 'Proofs' ) {
			my $specs = openprint::service::get_specs_ref( $Project, $service_index );
			foreach ( keys %$specs ) {
				$$variable{$_} = $$specs{$_};
			} # end foreach
			openprint::Estimating::Proofs::get_proof_specs( $log, $dbh, $variable, $project_index, $service_index );
		} elsif ( $service_type_id ) {
			my $specs = openprint::service::get_specs_ref( $Project, $service_index );
			foreach ( keys %$specs ) {
				$$variable{$_} = $$specs{$_};
			} # end foreach
		} else {
			my $specs = openprint::service::get_specs_ref( $Project, $service_index );
			my $side_one_colours = 0;
			my $side_two_colours = 0;
			foreach my $name ( keys %$specs ) {
				#$log->debug("Setting: $name:($value)");
				$$variable{$name} = $$specs{$name};
				if ( $name =~ /ProcessColourSideOne/ ) {
					$side_one_colours += 4 if $$specs{$name};
				} elsif ( $name =~ /chkBlackSideOne/ or $name =~/txtSpecialSideOneColour\d/ ) {
					$side_one_colours++ if $$specs{$name};
				} elsif ( $name =~ /ProcessColourSideTwo/ ) {
					$side_two_colours += 4 if $$specs{$name};;
				} elsif ( $name =~ /chkBlackSideTwo/ or $name =~/txtSpecialSideTwoColour\d/ ) {
					$side_two_colours++ if $$specs{$name};;
				} # end if
			} # end while
			$$variable{SideOneColours} = $side_one_colours;
			$$variable{SideTwoColours} = $side_two_colours;

			$$variable{"hdnPaperTotal1"} = sprintf("%.2f",$$variable{"hdnPaperTotal1"});
			$$variable{"hdnPaperTotal2"} = sprintf("%.2f",$$variable{"hdnPaperTotal2"});
			$$variable{"hdnPaperTotal3"} = sprintf("%.2f",$$variable{"hdnPaperTotal3"});
		} # end if
		$$variable{ServiceTypeName} = $$variable{ServiceName} if $$variable{ServiceName} ne '';

		$$variable{ProjectIndex} = $project_index;
	} else {
		$log->debug(" *********** PROBLEM HERE Project Index: $project_index AND Service Index: $service_index **********************");
	} # end if
} # End sub get_service_specifications

sub create_edit_process {
	my $Project;

	$param{quantity1} =~ s/\D//g;
	$param{quantity2} =~ s/\D//g;
	$param{quantity3} =~ s/\D//g;

	my $error = '';
	$error .= 'No quantities specified.<br/>' if $param{quantity1} eq '' and $param{quantity2} eq '' and $param{quantity3} eq '';
	$error .= 'Invalid Quantity 1.<br/>' if $param{quantity1} and ! int $param{quantity1};
	$error .= 'Invalid Quantity 2.<br/>' if $param{quantity2} and ! int $param{quantity2};
	$error .= 'Invalid Quantity 3.<br/>' if $param{quantity3} and ! int $param{quantity3};
	if ( ! $error ) {
		$Project = new openprint::Project( int $param{ProjectIndex} );
		$error .= $Project->save() if ! $Project->id();
	} # end if
	if ( $error ne '' ) {
		$variable{Redirect} = '/main/project/create_edit.html';
		$variable{error} = 'Error saving project';
		$variable{details} = $error;
		foreach ( keys %param ) {
			$variable{$_} = $param{$_};
		} # end foreach
		return;
	} # end if
	my $recalculate;
	my $project_index = $session{project_id} = $Project->id();
	$Project->lock();
	my @changes = $Project->changes( \%param );

	my $services = $Project->services();
	my @service_ids = sort map { $$services{$_} ? @{$$services{$_}} : () } keys %$services;

	foreach my $qty_index ( 1 .. 3 ) {
		if ( $param{"quantity$qty_index"} != $Project->quantity($qty_index) ) {
			if ( ! $param{"quantity$qty_index"} ) { # Project has a quantity, we are deleting it
				foreach my $service_id ( @service_ids ) {
					foreach my $spec ( map { $_.$qty_index } ( 'txtPrice','txtUnitPrice','txtQuantity' ) ) {
						openprint::service::delete_service_spec( $project_index, $service_id, $spec );
					} # end foreach
				} # end foreach
			} else {
				$recalculate = 1;

				foreach my $service_id ( @service_ids ) {
					openprint::service::insert_service_spec( $log, $dbh, 
							$project_index, $service_id, 'txtQuantity'.$qty_index, int $param{"quantity$qty_index"} );
				} # end foreachs ervice
			} # end if has quantity
			$Project->quantity( $qty_index, int $param{"quantity$qty_index"} );
		} # end if quantity change
	} # end foreach qty_index

	$Project->currency_id( $session{Currency_id} ) if ! $Project->currency_id();
	$Project->set({
			reference	=>$param{reference},
			comments 	=> $param{comments},
			mode			=>	$param{rdbMode},
			design		=>	$param{ddmDesign},
			programs	=>	$param{chkPrograms},
			other_programs	=>	$param{txtOtherPrograms},
			reprint		=>	$param{reprint},
			reprint_reason	=>	$param{reprint_reason},
			reprint_description	=>	$param{reprint_description},
			});

	# This will likely never happen, because the act of cilcking on the different project type changes it.
	my $ProjectType = openprint::ProjectType->find_one( name => $param{rdbProjectType} ) if $param{rdbProjectType};
	$ProjectType = openprint::ProjectType->find_one( id => $param{project_type_id} ) if $param{project_type_id};
	if ( ! $ProjectType and ! $Project->type_id() ) {
		$log->error("No Project Types for $param{rdbProjectType} $param{project_type_id}");
	}
	my $OldProjectType = $Project->Type();
# Handle ProjectType
	if ( (!$OldProjectType) or ( $ProjectType and ( $OldProjectType->id() != $ProjectType->id() ) ) ) {
		#$log->debug("Different project type, changing $$OldProjectType{name} to $$ProjectType{name}");
		$recalculate = 1;
		$error .= $Project->change_ProjectType( $ProjectType );
	} else {
		$error .= $Project->save();
	} # end if

	# take care of the Graphic Design service
	if ( $param{rdbGraphicDesign} eq 'Y' ) {
		push @{$$services{GraphicDesign}}, $Project->add_service('GraphicDesign') if ! $$services{GraphicDesign};
	} # end if

	my %statuses = sql::execute( $log, $dbh,
			'SELECT lngserviceindex, strstatus FROM tbl_Project_Contents WHERE lngprojectindex=?', $project_index);
	foreach my $ServiceType ( openprint::ServiceType->find(create_visible=>1) ) {
		if ( $ServiceType->type() eq 'CustomService' ) {
			$log->error("CustomService is visible in project create.");
			next;
		} # end if
		if ( $param{'chkServices'.$ServiceType->name()} eq $ServiceType->name() ) {
			if ( ! $$services{$ServiceType->name()} ) {	
				push @{$$services{$ServiceType->name()}}, $Project->add_service($ServiceType->name());
				$recalculate = 1;
			} # end if
		} else {
			if ( $$services{$ServiceType->name()} ) {
				foreach my $s_id ( @{$$services{$ServiceType->name()}} ) {
					if ( $statuses{$s_id} ne 'Completed' ) {
						delete_service( $Project, $s_id );
					} # end if
				} # end foreach
				delete $$services{$ServiceType->name()};
				$recalculate = 1;
			} # end if
		} # end if
	} # end foreach
	if ( ! ( $$services{Proofs} or $$services{NoPrinting} ) ) {
		push @{$$services{Proofs}}, $Project->add_service('Proofs');
		$recalculate = 1;
	} # end if

	$Project->add_to_log( @session{'company_id','user_id'}, 'Edited: '.join('<br/>', @changes) );

	if ( $ProjectType->type() eq 'MultiPage' ) {
		my $book_type = $Project->get_book_type();
		if ( $book_type ) {
			my $project_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
			if ( $book_type ne $$project_specs{rdbTemplateType} ) {
				$Project->add_to_log( @session{'company_id','user_id'}, "Changed book type from $$project_specs{rdbTemplateType} to $book_type" );
				openprint::service::insert_service_spec( $log, $dbh, $project_index, $$services{''}[0], 'rdbTemplateType', $book_type );
				$recalculate = 1;	
			} # end if
		} # end if
	}
	
# August 6 2019: Moved the unlock above the calc.  If we die during recalc our saved info wont be committed. 
# I think the chance of two people working on the project at the same time is unlikely enough to allow this.
	$Project->unlock();
  $Project->recalculate() if $recalculate;

	return $Project->id();
} # end sub create_edit_process

sub del_service {
	# THis is an external wrapper 
	my ( $r, $log, $dbh, $variable, $project_id, $service_name ) = @_;
	my $Project = new openprint::Project( $project_id );
	my $services = $Project->services();
	if ( $$services{$service_name} ) {
		foreach my $service_id ( @{$$services{$service_name}} ) {
			delete_service( $Project, $service_id );
		} # end foreach
	} # end if
} # end sub del_service

sub delete_service {
	my ( $Project, $service_id ) = @_;
	my $Service = $Project->Service( $service_id );
	return $Service->delete();
} # end sub delete_service

sub reuse_project {
	my ( $project_index ) = @_;

	my $Project = new openprint::Project($project_index);
	if ( ! $Project->id() ) {
		$variable{error} .= "Source project $project_index could not be found.";
		return;
	} # end if
	my $NewProject = $Project->copy();
	$variable{error} .= $NewProject->save({
		( map { exists $param{'quantity'.$_} ? ( 'quantity'.$_	=>	$param{'quantity'.$_} ) : ()  } ( 1 .. 3 ) ),
		( map { exists $param{$_} ? ( $_ => $param{$_} ) : () } ( 'reference', 'comments','reprint','reprint_reason' ) ),
		due_date => undef,
		user_id	=>	$session{user_id},
		status	=> ( sets::isin( $Project->status(), [ 'Unordered', 'Pending Deposit', 'In Prepress', 'Proofs Out', 'Approved', 'Printed', 'Complete','Shipped','Picked Up' ] ) ? 'Unordered' : 'uncalculated' ),
		( $param{company_id} ? ( company_id => $param{company_id} ) : () ),
	} );

	$session{project_id} = $NewProject->id();

	$Project->add_to_log( @session{'company_id','user_id'}, 'Reused to project '.$NewProject->id() );

	if ( $param{company_id} and $param{company_id} != $session{company_id} ) {
		openprint::switch_company( new openprint::Company( $param{company_id} ) ) if sets::isin( $session{user_type}, ['A','E'] );
	} # end if
	$NewProject->add_to_log( @session{'company_id','user_id'}, 'Reused from project '.$Project->id() );

	# Make this all one transaction... Don't need locking because a reload would get a different projectindex
	my $ac = sql::start_transaction( $dbh );
	my $services = $NewProject->services();
	my @service_ids = map { $$services{$_} ? @{$$services{$_}} : () } keys %$services;

	if ( $Project->quantity1() != $NewProject->quantity1() ) {
		if ( ! $NewProject->quantity1() ) { # Project has a quantity, we are deleting it
			foreach my $service_id ( @service_ids ) {
				foreach my $spec ( 'txtPrice1','txtUnitPrice1','txtQuantity1' ) {
					openprint::service::delete_service_spec( $NewProject->id(), $service_id, $spec );
				} # end foreach
			} # end foreach
		} else {
			foreach my $service_id ( @service_ids ) {
				openprint::service::insert_service_spec( $log, $dbh, $NewProject->id(), $service_id, 'txtQuantity1', $NewProject->quantity1() );
			} # end foreach
		} # end if has
	} # end if

	if ( $NewProject->quantity2() != $Project->quantity2() ) {
		if ( ! $NewProject->quantity2() ) {
			foreach my $service_id ( @service_ids ) {
				foreach my $spec ( 'txtPrice2','txtUnitPrice2','txtQuantity2' ) {
					openprint::service::delete_service_spec( $NewProject->id(), $service_id, $spec );
				} # end foreach
			} # end foreach
		} else {
			foreach my $service_id ( @service_ids ) {
				openprint::service::insert_service_spec( $log, $dbh, $NewProject->id(), $service_id, 'txtQuantity2', $NewProject->quantity2() );
			} # end foreach
		} # end if
	} # end if

	if ( $NewProject->quantity3() != $Project->quantity3() ) {
		if ( ! $NewProject->quantity3() ) {
			foreach my $service_id ( @service_ids ) {
				foreach my $spec ( 'txtPrice3','txtUnitPrice3','txtQuantity3' ) {
					openprint::service::delete_service_spec( $NewProject->id(), $service_id, $spec );
				} # end foreach
			} # end foreach
		} else {
			foreach my $service_id ( @service_ids ) {
				openprint::service::insert_service_spec( $log, $dbh, $NewProject->id(), $service_id, 'txtQuantity3', $NewProject->quantity3() );
			} # end foreach
		} # end if
	} # end if
	sql::end_transaction( $dbh, $ac );

	if ( $param{upgrade_ink_coverages} eq 'Y' ) {
		my $services = $NewProject->services();
		my $printing_Service = $NewProject->Service($$services{''}[0]) if $$services{''} and @{$$services{''}};
		
		foreach my $sig_id ( $NewProject->signatures() ) {
			my $Service = $NewProject->Service($sig_id);
			my $sig_specs = $Service->specs();
			my @colours = (
					openprint::Estimating::Printing::get_colours($sig_specs, 'SideOne'),
					openprint::Estimating::Printing::get_colours($sig_specs, 'SideTwo'),
					);
			foreach my $c ( @colours ) {
				if ( $$c{type} eq 'CMYK' ) {
					if (
							($$c{coverage} == $openprint::config{OldDefaultInkCoverage})
							and
							($$c{coverage} != $openprint::config{DefaultInkCoverage})
				 ) {
						$openprint::log->debug("Update $$c{coverage_key} from $$c{coverage} to $openprint::config{DefaultInkCoverage}");
						openprint::service::insert_service_spec( $log, $dbh, $NewProject->id(), $sig_id,
								$$c{coverage_key}, $openprint::config{DefaultInkCoverage});
						if ( $$sig_specs{Group} and $printing_Service ) {
							openprint::service::insert_service_spec( $log, $dbh, $NewProject->id(), $printing_Service->service_id(),
									$$c{coverage_key}.$$sig_specs{Group}, $openprint::config{DefaultInkCoverage});

						}
					} else {
						$openprint::log->debug("Not Update $$c{coverage_key} to $openprint::config{DefaultInkCoverage}");
					}
				} else {
					$log->debug("Unknown type $$c{type}");
				}
			} # end foreach colour
		} # end foreach sig
		
	} # end if upgrade_ink_coverages

	if ( 
			( $param{upgrade_ink_coverages} eq 'Y' ) 
			or ( $NewProject->currency_id() != $openprint::Currency->id() )
			or ( $NewProject->quantity1() and ( $Project->quantity1() != $NewProject->quantity1() ) )
			or ( $NewProject->quantity2() and ( $Project->quantity2() != $NewProject->quantity2() ) )
			or ( $NewProject->quantity3() and ( $Project->quantity3() != $NewProject->quantity3() ) )
			or ( $param{recalculate} == 1 )
	   ) {
		$NewProject->recalculate();
	} # endif
	return $NewProject->id();
} # end sub reuse_project

1;
__END__
