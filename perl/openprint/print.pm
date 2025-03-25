use strict;
use warnings;
package openprint::print;

use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

require sql;
require openprint::main_project;
require openprint::print_project;
require openprint::service;
require openprint::Currency;

require openprint::Estimating::Skids;
require openprint::Estimating::Shipping;
require openprint::Estimating::Stitching;
require openprint::Estimating::Padding;
require openprint::Estimating::MultiPage;
require openprint::Estimating::SinglePage;

# Adds completed/edited services, and then displays the status of the project
sub print_prices {
	my ( $r, $log, $dbh, $cookie, $variable ) = @_;

	my $service_index = $$variable{ServiceIndex};
	$service_index = $param{ServiceIndex} if ! $service_index;
	if ( $service_index ) {
		my @service_ids = split(',', $service_index);
		$service_index = $service_ids[0];
	}
	my $project_index = $$variable{ProjectIndex};
	$project_index = $param{ProjectIndex} if ! $project_index;
	$project_index = $session{project_id} if ! $project_index;
	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();

  $$variable{Cutting} = $$services{Cutting} ? 'YES' : 'NO';
  $$variable{Folding} = $$services{Folding} ? 'YES' : 'NO';
  $$variable{NoPrinting} = $$services{NoPrinting};

	$$variable{Mode} = $Project->mode();

	@{$$variable{RunStyleOptions}} = ( 'Sheet Work', 'Sheet Work', 'Work & Turn', 'Work & Turn', 'Work & Tumble', 'Work & Tumble', 'Perfecting','Perfecting','Web','Web');
} # end sub print_prices

# all this function does is the special code when coming from a book service
# it adds all the necceessary signatures, etc.
# It assumes that the book code has already been saved.
sub multipage_signatures {
	my ( $param, $log, $dbh, $variable, $project_index, $service_index ) = @_;

#deprecate
return;

	my $ac = sql::start_transaction( $dbh );
	my $Project = new openprint::Project( $project_index );
	$Project->lock();
	my $services = $Project->services();
	$service_index = $$services{''}[0] if ! $service_index;

    $openprint::log->debug(" **** STARTING MULTIPAGE SIGNATURES FUNCTION **** ");

	if ( ! $$param{txtSpreadSize} ) {
		# now we have finished the first step for a new book, and have a basic signature set in place.
		if ( $$param{rdbTemplateType} eq 'PerfectBound' ) {
			# Insanity code:  Perfect Bound requires different cover.
			$$param{rdbCover} = 'Different';
			$$param{txtSpreadSize} = $openprint::config{PerfectBindSpreadSize} ? $openprint::config{PerfectBindSpreadSize} : 2;
		} elsif ( $$param{rdbTemplateType} eq 'SpinePaste' ) {
			# Insanity code:  Perfect Bound requires different cover.
			$$param{rdbCover} = 'Self';
			$$param{txtSpreadSize} = 2;
		} elsif ( sets::isin( $$param{rdbTemplateType}, ['SaddleStitching', 'LoopStitching'] ) ) {
			$$param{txtSpreadSize} = 4;
		} elsif ( sets::isin( $$param{rdbTemplateType}, ['CornerStitching', 'Cerlox', 'PlasticCoil','MetalCoil', 'Unbound'] ) ) {
			$$param{txtSpreadSize} = 2;
		} elsif ( $Project->Type()->name() eq 'MultiPage' ) {
			$openprint::log->warn("Unknown Bindery Type: $$param{rdbTemplateType}" );
			$$param{txtSpreadSize} = 4;
		} else {
			$openprint::log->warn("Unknown Bindery Type: $$param{rdbTemplateType}" );
			$$param{txtSpreadSize} = 2;
		} # end if
		openprint::service::insert_service_spec( $log, $dbh, $project_index, $service_index, 'txtSpreadSize', $$param{txtSpreadSize} );
	} # end if

	my $max_group;
	my %needed_pages;
	$needed_pages{'Cover Pages'} = $$param{OverrideGroupPageQuantity1} eq 'Y' ? $$param{GroupPageQuantity1} : ($$param{rdbCover} eq 'Different' ? 4 : 0);
	$needed_pages{'Gate Folded Pages'} = $$param{txtGateFoldedPageQuantity};
	$needed_pages{'Interior Pages'} = ( $$param{txtTotalPageQuantity} - $needed_pages{'Cover Pages'} ) - $needed_pages{'Gate Folded Pages'};

	my %specified_pages;

	if ( $$param{rdbCover} eq 'Different' ) {
# now add a cover spread if we need one.
# First, see if we have one.
		if ( ! $Project->signatures({'type'=>'Cover Pages'}) ) {
			push @{$$services{Signature}}, $Project->add_signature( undef, undef, {
						'txtSignatureType'=>'Cover Pages',
						'txtServiceDescription'=>'Cover',
						'Group'	=>	1,
						'PrintingType'=>$$param{PrintingType},
						'txtSpreadSize'	=>	4,
						} );
			$specified_pages{'Cover Pages'} = 4;
		} # end if

		# Prime this for saving later
		if ( ( ! $$param{GroupPageQuantity1} ) and ( $$param{OverrideGroupPageQuantity1} ne 'Y' ) ) {
			$$param{GroupPageQuantity1} = $needed_pages{'Cover Pages'};
		} # end if
	} else {
# Don't need a cover, so get rid of it
		foreach ( $Project->signatures({'type'=>'Cover Pages'}) ) {
			openprint::print_project::delete_service( $Project, $_ );
		} # end foreach
		foreach ( $Project->signatures({'Group'=>1}) ) {
			openprint::print_project::delete_service( $Project, $_ );
		} # end foreach
	} # end if Self or Different Cover


	foreach my $k ( keys %$param ) {
		if ( $k =~ /^txtSignatureType(\d*)/ ) {
			my $group_id = $1;
$log->debug("group $group_id");
			next if $group_id == 1 and $$param{rdbCover} ne 'Different';

			if ( $$param{'GroupPageQuantity'.$group_id} and ! $Project->signatures({'Group'=>$group_id}) ) {
				$log->debug("adding special group $group_id");
				my $print_service_index = $Project->add_signature( undef, undef, {
						#'txtSignatureType'=>'Interior Pages',
						#'txtServiceDescription'=>'Interior Pages',
						'Group'	=>	$group_id,
						'PrintingType'=>$$param{PrintingType},
						'txtSpreadSize'	=>	$$param{txtSpreadSize},
						} );
				push @{$$services{Signature}}, $print_service_index;
			} # end if

			$specified_pages{$$param{$k}} += $$param{'GroupPageQuantity'.$group_id};
			if ( $group_id > $max_group ) {
				$max_group = $group_id;
			} # end if
		} # end if
	} # end foreach param
	$max_group = 3 if $max_group < 3; # Reserver 1, 2, 3 for Cover, Interior, Gate
	$openprint::log->debug("Max group: $max_group");

# On each call to this, we save, then check to see if there are any unspecified signatures

	# Now, make sure that we have all the gate spreads that we need
	my @gate_spread_services = $Project->signatures({'type'=>'Gate Folded Pages'});
	my $need_gate_spreads = int($$param{txtGateFoldedSpreadQuantity}) - scalar @gate_spread_services;
	while ( $need_gate_spreads > 0 ) {
		push @{$$services{Signature}}, $Project->add_signature( undef, undef, {
				'txtSignatureType'=>'Gate Folded Pages',
				'txtServiceDescription'=>'Gate Folded Pages',
				'Group'	=>	3,
				'PrintingType'=>$$param{PrintingType},
				} );
		$need_gate_spreads -= 1;
	} # end while need_gate_spreads

	if ( ! $Project->signatures({'type'=>'Interior Pages'}) ) {
# Must have at least 1 interioer signature
		$log->debug('add interiorpages');
		my $print_service_index = $Project->add_signature( undef,  undef, {
				'txtSignatureType'=>'Interior Pages',
				'txtServiceDescription'=>'Interior Pages',
				'Group'	=>	2,
				'PrintingType'=>$$param{PrintingType},
				'txtSpreadSize'	=>	$$param{txtSpreadSize},
				} );
		$specified_pages{'Interior Pages'} = $needed_pages{'Interior Pages'};
	} # end if
	if ( ( ! $$param{GroupPageQuantity2} ) and ( $$param{OverrideGroupPageQuantity2} ne 'Y' ) ) {
		$$param{GroupPageQuantity2} = $needed_pages{'Interior Pages'};
	} # end if

	foreach my $ss_id ( $Project->signatures() ) {
		if ( $ss_id == $service_index ) {
			$log->error("No signatures in multipage! Means we found the project service in the list of signatures");
			next;
		} # end if
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		my $group_id = $$sig_specs{Group};
		if ( $group_id == 1 ) {
			# Presentation Folder Cover -> Make sure required services like Die Cutting and Gluing are present
			if ( sets::isin( $$param{'rdbTemplateType'.$group_id}, ['2Panel1Pocket','2Panel2Pocket','TriFoldDoublePocket'] ) ) {
				if ( my $ProjectType = openprint::ProjectType->find_one('name'=>'PresentationFolders') ) {
					foreach my $ServiceType ( $ProjectType->required_ServiceTypes() ) {
						if ( ! $$services{$ServiceType->name()} ) {
							push @{$$services{$ServiceType->name()}}, $Project->add_service( $ServiceType );
						} # end if
					} # end foreach servicetype
				} # end if
			} # end if
		} # end if

		# We have to do this for simple printing.  Simple printing calls here, but doesn't have these fields, so it clears out the defaults!
		foreach my $spec ( 
				'txtSignatureType','pages_supplied','supplied_format','rdbPressProof', 'ProofApproval',
				'ddmStockBrand','ddmStockFinish','ddmStockColour','ddmStockWeight','ddmStockQuality','ddmStockGroup',
				'txtSpecificStockBrand','txtSpecificStockFinish','txtSpecificStockColour','txtSpecificStockWeight',
				'txtSpecificStockWidth','txtSpecificStockHeight','txtSpecificStockCalliper',
				'rdbSuppliedStock','rdbSpecificStock','StockType',
				'CustomSheetDoubleSided', 'CustomStockPrice','txtCustomMWeight','txtStockGSM','CustomStockPriceUnits','StockPricePerM',
				'basis_width','basis_height','basis_mweight','StockGrade',
				'minimum_order', 'sheets_per_package',

				'CyanSpotSideOneCoverage', 'MagentaSpotSideOneCoverage', 'YellowSpotSideOneCoverage', 'BlackSpotSideOneCoverage',
				'CyanSideOneCoverage', 'MagentaSideOneCoverage', 'YellowSideOneCoverage', 'BlackSideOneCoverage',
				'CyanSpotSideTwoCoverage', 'MagentaSpotSideTwoCoverage', 'YellowSpotSideTwoCoverage', 'BlackSpotSideTwoCoverage',
				'CyanSideTwoCoverage', 'MagentaSideTwoCoverage', 'YellowSideTwoCoverage', 'BlackSideTwoCoverage',
				'ColourCoatingType1SideOne', 'ColourCoatingColour1SideOne','ColourCoatingCoverage1SideOne',
				'ColourCoatingType2SideOne', 'ColourCoatingColour2SideOne','ColourCoatingCoverage2SideOne',
				'ColourCoatingType3SideOne', 'ColourCoatingColour3SideOne','ColourCoatingCoverage3SideOne',
				'ColourCoatingType4SideOne', 'ColourCoatingColour4SideOne','ColourCoatingCoverage4SideOne',
				'ColourCoatingType5SideOne', 'ColourCoatingColour5SideOne','ColourCoatingCoverage5SideOne',
				'ColourCoatingType6SideOne', 'ColourCoatingColour6SideOne','ColourCoatingCoverage6SideOne',
				'ColourCoatingType7SideOne', 'ColourCoatingColour7SideOne','ColourCoatingCoverage7SideOne',
				'ColourCoatingType8SideOne', 'ColourCoatingColour8SideOne','ColourCoatingCoverage8SideOne',
				'ColourCoatingType9SideOne', 'ColourCoatingColour9SideOne','ColourCoatingCoverage9SideOne',

				'ColourCoatingType1SideTwo', 'ColourCoatingColour1SideTwo','ColourCoatingCoverage1SideTwo',
				'ColourCoatingType2SideTwo', 'ColourCoatingColour2SideTwo','ColourCoatingCoverage2SideTwo',
				'ColourCoatingType3SideTwo', 'ColourCoatingColour3SideTwo','ColourCoatingCoverage3SideTwo',
				'ColourCoatingType4SideTwo', 'ColourCoatingColour4SideTwo','ColourCoatingCoverage4SideTwo',
				'ColourCoatingType5SideTwo', 'ColourCoatingColour5SideTwo','ColourCoatingCoverage5SideTwo',
				'ColourCoatingType6SideTwo', 'ColourCoatingColour6SideTwo','ColourCoatingCoverage6SideTwo',
				'ColourCoatingType7SideTwo', 'ColourCoatingColour7SideTwo','ColourCoatingCoverage7SideTwo',
				'ColourCoatingType8SideTwo', 'ColourCoatingColour8SideTwo','ColourCoatingCoverage8SideTwo',
				'ColourCoatingType9SideTwo', 'ColourCoatingColour9SideTwo','ColourCoatingCoverage9SideTwo',
				'rdbColourBar','txtCropMarkSpace',
				'GroupPageQuantity','OverrideGroupPageQuantity','txtServiceDescription','rdbTemplateType',
				'rdbPanels','PocketSize','chkPocketLeft','chkPocketCenter','chkPocketRight',
				'txtWidth','txtHeight','txtFinalWidth','txtFinalHeight','chkOverrideDimensions','txtQuantity1','txtQuantity2','txtQuantity3',
				) {
#$log->debug("Group $type : $spec " .$$param{$spec.$group_id});
			
			openprint::service::insert_service_spec( $log, $dbh, $Project->id(), $ss_id, $spec, $$param{$spec.$group_id} ) if exists $$param{$spec.$group_id};
		} # end foreach spec
		foreach my $spec ( 
				'chkCyanSideOne','chkMagentaSideOne','chkYellowSideOne','chkBlackSideOne', 'chkProcessColourSideOne',
				( map { 'chkColourCoating'.$_.'SideOne' } ( 1 .. 9 ) ),
				'chkCyanSideTwo','chkMagentaSideTwo','chkYellowSideTwo','chkBlackSideTwo', 'chkProcessColourSideTwo',
				( map { 'chkColourCoating'.$_.'SideTwo' } ( 1 .. 9 ) ),
				'BleedLeft','BleedRight','BleedTop','BleedBottom',
				'full_packages',
				'sides_the_same',
		) {
			openprint::service::insert_service_spec( $log, $dbh, $Project->id(), $ss_id, $spec, $$param{$spec.$group_id} );
		} # end foreach spec
	} # end foreach signature

	my $old_bindery_type = $Project->get_book_type();
	if ( $old_bindery_type and ($$param{rdbTemplateType} ne $old_bindery_type) and $$services{$old_bindery_type} ) {
		foreach ( @{$$services{$old_bindery_type}} ) {
			openprint::print_project::delete_service( $Project, $_ );
		} # end foreach
		delete $$services{$old_bindery_type};
	} # end if

	if ( ! $$services{NoBindery} ) {
$log->debug("No Nobindery");
		if ( $$param{rdbTemplateType} ) {
# Insert the desired Bindery Type
			if ( ( ! $$services{$$param{rdbTemplateType}} ) and openprint::ServiceType->find_one( name=> $$param{rdbTemplateType} ) ) {
				next if $$services{$$param{rdbTemplateType}};
				push @{$$services{$$param{rdbTemplateType}}}, $Project->add_service( $$param{rdbTemplateType} );
			} # end if

			if ( sets::isin( $$param{rdbTemplateType}, ('SaddleStitching','LoopStitching','PerfectBound','Unbound') ) ) {
# Saddle and Loop Stitching requires Folding
				push @{$$services{Folding}}, $Project->add_service( 'Folding' ) if ! $$services{Folding};
				push @{$$services{Cutting}}, $Project->add_service( 'Cutting' ) if ! $$services{Cutting};
			} # end if
		} # end if
	} # end if
	$Project->unlock();
	sql::end_transaction( $dbh, $ac );
} # end sub multipage_signatures

sub publication_pages {
	my ( $r, $log, $dbh, $variable ) = @_;
    my $service_index = $param{ServiceIndex};
    my $project_index = $param{ProjectIndex};
	$project_index = $session{project_id} if ! $project_index;
	$log->debug("********************************** STARTING MULTIPAGE PUBLICATION PAGES *******************************");

	@{$$variable{RunStyleOptions}} = ( 'Sheet Work', 'Sheet Work', 'Work & Turn', 'Work & Turn', 'Work & Tumble', 'Work & Tumble', 'Perfecting','Perfecting','Web','Web');
	
	my $Project = new openprint::Project( $project_index );
	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		my $type = $$sig_specs{Group};
$log->error("No Group!") if ! $type;
		foreach my $spec ( 
				'ddmStockBrand','ddmStockFinish','ddmStockColour','ddmStockWeight','ddmStockGroup','ddmStockQuality',
				'txtSpecificStockBrand','txtSpecificStockFinish','txtSpecificStockColour','txtSpecificStockWeight',
				'txtSpecificStockWidth','txtSpecificStockHeight','txtSpecificStockCalliper',
				'rdbSuppliedStock','rdbSpecificStock','StockType',
				'CustomSheetDoubleSided', 'CustomStockPrice','txtCustomMWeight','txtStockGSM','CustomStockPriceUnits','StockPricePerM',
				'basis_width','basis_height','basis_mweight','StockGrade',
				'minimum_order', 'sheets_per_package', 'full_packages',
				'chkCyanSideOne','chkMagentaSideOne','chkYellowSideOne','chkBlackSideOne', 'chkProcessColourSideOne',
				'chkColourCoating1SideOne', 'ColourCoatingType1SideOne', 'ColourCoatingColour1SideOne','ColourCoatingCoverage1SideOne',
				'chkColourCoating2SideOne', 'ColourCoatingType2SideOne', 'ColourCoatingColour2SideOne','ColourCoatingCoverage2SideOne',
				'chkColourCoating3SideOne', 'ColourCoatingType3SideOne', 'ColourCoatingColour3SideOne','ColourCoatingCoverage3SideOne',
				'chkColourCoating4SideOne', 'ColourCoatingType4SideOne', 'ColourCoatingColour4SideOne','ColourCoatingCoverage4SideOne',
				'chkColourCoating5SideOne', 'ColourCoatingType5SideOne', 'ColourCoatingColour5SideOne','ColourCoatingCoverage5SideOne',
				'chkColourCoating6SideOne', 'ColourCoatingType6SideOne', 'ColourCoatingColour6SideOne','ColourCoatingCoverage6SideOne',
				'chkColourCoating7SideOne', 'ColourCoatingType7SideOne', 'ColourCoatingColour7SideOne','ColourCoatingCoverage7SideOne',
				'chkColourCoating8SideOne', 'ColourCoatingType8SideOne', 'ColourCoatingColour8SideOne','ColourCoatingCoverage8SideOne',
				'chkColourCoating9SideOne', 'ColourCoatingType9SideOne', 'ColourCoatingColour9SideOne','ColourCoatingCoverage9SideOne',
				'chkCyanSideTwo','chkMagentaSideTwo','chkYellowSideTwo','chkBlackSideTwo', 'chkProcessColourSideTwo',
				'chkColourCoating1SideTwo', 'ColourCoatingType1SideTwo', 'ColourCoatingColour1SideTwo','ColourCoatingCoverage1SideTwo',
				'chkColourCoating2SideTwo', 'ColourCoatingType2SideTwo', 'ColourCoatingColour2SideTwo','ColourCoatingCoverage2SideTwo',
				'chkColourCoating3SideTwo', 'ColourCoatingType3SideTwo', 'ColourCoatingColour3SideTwo','ColourCoatingCoverage3SideTwo',
				'chkColourCoating4SideTwo', 'ColourCoatingType4SideTwo', 'ColourCoatingColour4SideTwo','ColourCoatingCoverage4SideTwo',
				'chkColourCoating5SideTwo', 'ColourCoatingType5SideTwo', 'ColourCoatingColour5SideTwo','ColourCoatingCoverage5SideTwo',
				'chkColourCoating6SideTwo', 'ColourCoatingType6SideTwo', 'ColourCoatingColour6SideTwo','ColourCoatingCoverage6SideTwo',
				'chkColourCoating7SideTwo', 'ColourCoatingType7SideTwo', 'ColourCoatingColour7SideTwo','ColourCoatingCoverage7SideTwo',
				'chkColourCoating8SideTwo', 'ColourCoatingType8SideTwo', 'ColourCoatingColour8SideTwo','ColourCoatingCoverage8SideTwo',
				'chkColourCoating9SideTwo', 'ColourCoatingType9SideTwo', 'ColourCoatingColour9SideTwo','ColourCoatingCoverage9SideTwo',
				'CyanSpotSideOneCoverage', 'MagentaSpotSideOneCoverage', 'YellowSpotSideOneCoverage', 'BlackSpotSideOneCoverage',
				'CyanSideOneCoverage', 'MagentaSideOneCoverage', 'YellowSideOneCoverage', 'BlackSideOneCoverage',
				'CyanSpotSideTwoCoverage', 'MagentaSpotSideTwoCoverage', 'YellowSpotSideTwoCoverage', 'BlackSpotSideTwoCoverage',
				'CyanSideTwoCoverage', 'MagentaSideTwoCoverage', 'YellowSideTwoCoverage', 'BlackSideTwoCoverage',
				'BleedLeft','BleedRight','BleedTop','BleedBottom','rdbColourBar','txtCropMarkSpace',
				'GroupPageQuantity','txtServiceDescription',
				'txtSignatureType','rdbTemplateType','pages_supplied','supplied_format','rdbPressProof','PressApproval',
				'rdbPanels','PocketSize','chkPocketLeft','chkPocketCenter','chkPocketRight',
				'txtWidth','txtHeight','chkOverrideDimensions','txtQuantity1','txtQuantity2','txtQuantity3',
	'sides_the_same',
				) {
			$$variable{$spec.$type} = $$sig_specs{$spec} if $$sig_specs{$spec} and ! $$variable{$spec.$type};
#$openprint::log->debug("$spec . $type = $$variable{$spec.$type}");
		} # end foreach spec
	} # end foreach ss_id

	if ( ! $$variable{rdbTemplateType} ) {
		$$variable{rdbTemplateType} = $Project->get_book_type();
	} # end if

} # end sub publication_pages

sub get_insert_specs {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;
	$log->debug("************************** GETTING INSERT SPECS **************************");
	if ( $$variable{txtInsertQuantity} eq '' ) {
		$_ = "SELECT strValue FROM tbl_Service_Specifications WHERE lngProjectIndex='$project_index' AND strName='txtInsertQuantity'";
		( $$variable{txtInsertQuantity} ) = sql::execute( $log, $dbh, $_ );
	} # end if
	for (my $x = 1; $x <= $$variable{txtInsertQuantity}; $x += 1 ) {
		push @{$$variable{INSERTS}}, $x, $$variable{"txtInsertPage1$x"}, $$variable{"txtInsertPage2$x"}, $$variable{"txtFinalWidth$x"}, $$variable{"txtFinalHeight$x"};
	} # end for
	$$variable{txtPockets} = $$variable{SignatureCount} + $$variable{txtInsertQuantity};

} # end sub

sub get_finished_weight {
	my ( $project_index ) = @_; 
	my $project_weight;

require openprint::Estimating::Printing;
	my $Project = new openprint::Project( $project_index );
	# We do a weird thing with qty_index here, becasue all quantities should have the same weight, but may be calculated diferent ways, so we run through them until we get a valid weight.

# calculate project weight
	foreach my $qty_index ( $Project->quantity_indexes() ) {

		foreach my $signature_service_index ( $Project->signatures() ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
			next if $$sig_specs{txtSignatureType} and ! $$sig_specs{'PageQuantity'.$qty_index};
			next if ! $$sig_specs{'txtImposition'.$qty_index};
			my $sig_weight = openprint::Estimating::Printing::get_weight( $Project, $sig_specs, $qty_index );
			if ( ! $sig_weight ) {
				# unable to get weight for a sig, must recalc printing service
$openprint::log->debug("Unable to get sig_weight for signature $$sig_specs{SignatureIndex}");
				return 0;
			} # end if
			$project_weight += $sig_weight;
		} # end foreach signature_service_index
		last;
	} # end foreach qty_index
	#$openprint::log->debug("Project Weight: $project_weight : Marked Up: ". $project_weight * (1+$openprint::config{WeightMarkup}/100));
	
	# This 1.1 was actually requested by Amin.  So it was pretty random, but then I thought abotu it, and our weight calculations don't take into account the weight of the ink, etc... so it may actually be not too off.... would love to see some real figures on it.
	return $project_weight * (1+$openprint::config{WeightMarkup}/100);
} # end sub get_finished_weight

# Finished calliper for books will be calculated from the first qty.  All three should be the same.
sub get_finished_calliper { 
	my ( $project_index ) = @_; 
	my $Project = new openprint::Project( $project_index );
	return $Project->calliper();
} # end sub get_finished_calliper

sub get_quantities {
	my ( $variable, $project_index) = @_;
	if ( ! $$variable{QUANTITIES} ) {
		my $Project = new openprint::Project( $project_index );
		my @qty_indexes = $Project->quantity_indexes();
		foreach my $qty_index ( @qty_indexes ) {
			$$variable{QUANTITIES} .= " quantities[$qty_index] = '".$$Project{"quantity$qty_index"}."'; \n";
			$$variable{"QUANTITY$qty_index"} = $$Project{"quantity$qty_index"};
			$$variable{"txtQuantity$qty_index"} = $$Project{"quantity$qty_index"};
		} # end for
		
		if ( @qty_indexes == 1 ) {
			$$variable{Columns} = 'One';
		} elsif ( @qty_indexes == 2 ) {
			$$variable{Columns} = 'Two';
		} elsif ( @qty_indexes == 3 ) {
			$$variable{Columns} = 'Three';
		} # end if
	} # end if
} # end sub get_quantities

1;
__END__
