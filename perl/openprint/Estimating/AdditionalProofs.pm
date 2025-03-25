# Copyright (C) 2007 Isaac Connor <isaac@connortechnology.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA
use strict;

package openprint::Estimating::AdditionalProofs;
use POSIX qw( ceil );
use openprint ();
use vars qw( $log $dbh );
*log = \$openprint::log;
*dbh = \$openprint::dbh;

require sql;
require openprint::service;
require openprint::Estimating::Printing;

use constant DEBUG => 0;
my @variables = (
		'txtPrice',
		'CustomProofSpecs',
		'RequireColourProofs',
		'alert',
		);

sub variables {
	my ( $p_id, $s_id, $old_specs, $specs ) = @_;

	my $Project = new openprint::Project( $p_id );
	my @v = @variables;
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		push @v, 'txtPrice'.$qty_index;
	} # end foreach qty_index

	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		my $signature_index = $$sig_specs{'SignatureIndex'};
		foreach my $key ( keys %{$specs} ) {
			if ( $key =~ /^txtProofIndex-$signature_index-(\d+)-(\d+)$/ ) {
				my ( $proof_index, $qty_index ) = ( $1, $2 );

				push @v,	(
						"txtProofWidth-$signature_index-$proof_index-$qty_index",
						"txtProofHeight-$signature_index-$proof_index-$qty_index", 
						"txtProofQuantity-$signature_index-$proof_index-$qty_index",
						"ddmProofType-$signature_index-$proof_index-$qty_index",
						"txtProofUnitPrice-$signature_index-$proof_index-$qty_index",
						"txtProofIndex-$signature_index-$proof_index-$qty_index",
						"chkOverride-$signature_index-$proof_index-$qty_index",
						);
			} # end if
		} # end foreach key
	} # end foreach signature
	return @v;
} # end sub variables

sub outputs {
	my ( $p_id, $s_id, $specs ) = @_;

	my $Project = new openprint::Project( $p_id );
	my @v;
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		push @v, 'txtPrice'.$qty_index, "hdnBreakdown$qty_index";
	} # end foreach qty_index

	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		my $signature_index = $$sig_specs{'SignatureIndex'};
		foreach my $key ( keys %{$specs} ) {
			if ( $key =~ /^txtProofIndex-$signature_index-(\d+)-(\d+)$/ ) {
				my ( $proof_index, $qty_index ) = ( $1, $2 );

				push @v,	(
						"txtProofWidth-$signature_index-$proof_index-$qty_index",
						"txtProofHeight-$signature_index-$proof_index-$qty_index", 
						"txtProofQuantity-$signature_index-$proof_index-$qty_index",
						"ddmProofType-$signature_index-$proof_index-$qty_index",
						"txtProofUnitPrice-$signature_index-$proof_index-$qty_index",
						"txtProofIndex-$signature_index-$proof_index-$qty_index",
						"chkOverride-$signature_index-$proof_index-$qty_index",
						);
			} # end if
		} # end foreach key
	} # end foreach signature
	return @v;
} # end sub outputs

sub no_outputs {
} # end sub no_outputs

sub get_indexes {
	my ( $specs, $qty_index, $indexes, $types ) = @_;
	foreach my $key ( keys %{$specs} ) {
		if ( $key =~ /^txtProofIndex-(\d+)-(\d+)-$qty_index$/ ) {
			push @{$$indexes{$1}}, $$specs{$key};
			push @{$$types{$1}}, $$specs{"ddmProofType-$1-$2-$qty_index"};
		} # end if
	} # end foreach
} # end sub get_indexes

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $status = 'calculated';

	$log->debug("START PROOFS!!!!!!!!!!!!!!!!!! ($project_index) ($service_index)") if DEBUG;
	my $Project = new openprint::Project( $project_index );

	my @signature_service_indices = $Project->signatures();
	my $minCharge = openprint::service::get_price( 'ProofsMinimumCharge', undef, undef );

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"txtPrice$qty_index"} = '';
		my $totalPrice = 0;
		my $totalQuantity = 0;

		my %proof_indexes;
		my %proof_types;
		my %proof_totals;
		$$specs{'hdnBreakdown'.$qty_index} = "QTY: $qty_index<br/>";
		get_indexes( $specs, $qty_index, \%proof_indexes, \%proof_types );

		# First, build a hash containing the quantities of each proof.  The reason for this is to honour quantity discounts.
		foreach my $signature_service_index ( @signature_service_indices ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );

			my $signature_index = $$sig_specs{'SignatureIndex'};

			$$specs{'hdnBreakdown'.$qty_index} .= "Signature $signature_index<br/>";
			if ( ! $$sig_specs{'txtImposition'.$qty_index} ) {
				# Remove it so we don't have to test for it later
				$$specs{'hdnBreakdown'.$qty_index} .= 'No proofs needed because there is no imposition';
				next;
			} # end if
			my $Imposition = new openprint::Imposition();
			$Imposition->load( $sig_specs, $qty_index, $Project );
			my $Equipment = $Imposition->Press();
			$$specs{'hdnBreakdown'.$qty_index} .= $Imposition->to_string().'</br>';

			if ( ( ! sets::isin( 1, $proof_indexes{$signature_index} ) ) and $openprint::config{'Add_Default_Layout_Proof'} eq 'Y' ) {
				push @{$proof_indexes{$signature_index}}, 1;
			} # end if
			if ( ( ! sets::isin( 2, $proof_indexes{$signature_index} ) ) and $openprint::config{'Add_Default_Colour_Proof'} eq 'Y' ) {
				push @{$proof_indexes{$signature_index}}, 2;
			} # end if
			if ( ( ! sets::isin( 3, $proof_indexes{$signature_index} ) ) and ( ( $openprint::config{'Add_Default_Press_Proof'} eq 'Y' ) or ( $Equipment and $Equipment->specification('Require Press Proof') eq 'Y' ) ) ) {
				push @{$proof_indexes{$signature_index}}, 3;
			} # end if
				
			foreach my $proof_index ( @{$proof_indexes{$signature_index}} ) {
				if ( $$specs{"chkOverride-$signature_index-$proof_index-$qty_index"} ne 'Y' ) {
					if ( $proof_index == 1 ) {
						insert_layout_proof( $sig_specs, 1, $qty_index, $specs, $Imposition );
					} elsif ( $proof_index == 2 ) {
						insert_colour_proof( $Project, $sig_specs, 2, $qty_index, $specs );
					} elsif ( $proof_index == 3 ) {
						insert_press_proof( $Project, $sig_specs, 3, $qty_index, $specs, $Imposition );
					} # end if
				} else {
					if ( ($proof_index == 1) and ($$specs{"ddmProofType-$signature_index-$proof_index-$qty_index"} eq 'DigitalDylux') and ( $$specs{"txtProofQuantity-$signature_index-$proof_index-$qty_index"} < $openprint::config{'ForceDigitalDyluxQuantity'} ) ) {
						$$specs{'alert'} .= "We require Dylux Proofs<br/>";
						insert_layout_proof( $sig_specs, 1, $qty_index, $specs, $Imposition );
					} # end if
				} # end if

				my ( $quantity, $type ) = @$specs{
					"txtProofQuantity-$signature_index-$proof_index-$qty_index",
						"ddmProofType-$signature_index-$proof_index-$qty_index",
				};
				if ( ! $proof_totals{$type} ) {
					$proof_totals{$type} = { Quantity => 0, Price => 0 };
				} # end if
				$proof_totals{$type}{Quantity} += $quantity;
				$totalQuantity += $quantity;
			} # end foreach my $proof_index
		} # end foreach my $signature_service_index

		foreach my $signature_service_index ( @signature_service_indices ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
			if ( ! $$sig_specs{'txtImposition'.$qty_index} ) {
				# Remove it so we don't have to test for it later
				$$specs{'hdnBreakdown'.$qty_index} .= 'No proofs needed because there is no imposition';
				next;
			} # end if
			my $Imposition = new openprint::Imposition();
			$Imposition->load( $sig_specs, $qty_index, $Project );
			my $Equipment = $Imposition->Equipment();
			my %Results = signature_calc( $Project, $specs, $sig_specs, $qty_index, \%proof_indexes, \%proof_totals, $Equipment, $Imposition );
			$totalPrice += $Results{Total};
			$$specs{"hdnBreakdown$qty_index"} .= $Results{'Breakdown'};
			$status = $Results{status} if $Results{status};
		} # end foreach my $signature_service_index

		if ( $minCharge and ( $totalPrice < $minCharge ) and $totalQuantity ) {
			$totalPrice = $minCharge;
		} # end if

		$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{'ProjectMoneyFormat'}, $totalPrice * (1+$Project->markup()/100) );
	} # end foreach qty_index

	$log->debug("PROOFS!!!!!!!!!!!!!!!!!!") if DEBUG;
	return $$specs{'Status'} = $status;
} # end sub calc

sub signature_calc {
	my ( $Project, $specs, $sig_specs, $qty_index, $indexes, $totals, $Equipment, $Imposition ) = @_;

	my %Results;
	#return %Results if ! $$sig_specs{'txtImposition'.$qty_index};

	my $signature_index = $$sig_specs{'SignatureIndex'};
	if ( ! $Equipment ) {
		$openprint::log->debug("Looking up equipment in Proofs: signature_calc");
		$Equipment = openprint::Equipment->find_one( strid => $$sig_specs{'ddmPress'.$qty_index} );
		if ( ! $Equipment ) {
			$openprint::log->warn("Proofs: signature_calc: No equipment for " . $$sig_specs{'ddmPress'.$qty_index} );
			return %Results;
		}
	}

	$$indexes{$signature_index} = [] if ! $$indexes{$signature_index};

	if ( ( ! sets::isin( 1, $$indexes{$signature_index} ) ) and $openprint::config{'Add_Default_Layout_Proof'} eq 'Y' ) {
		push @{$$indexes{$signature_index}}, 1;
	} # end if
	if ( ( ! sets::isin( 2, $$indexes{$signature_index} ) ) and $openprint::config{'Add_Default_Colour_Proof'} eq 'Y' ) {
		push @{$$indexes{$signature_index}}, 2;
	} # end if
	if ( ( ! sets::isin( 3, $$indexes{$signature_index} ) ) and $openprint::config{'Add_Default_Press_Proof'} eq 'Y' ) {
		push @{$$indexes{$signature_index}}, 3;
	} # end if

$log->debug("Proof indexes " . join(',', @{$$indexes{$signature_index}}  ) ) if DEBUG;
	foreach my $proof_index ( @{$$indexes{$signature_index}} ) {
		if ( $$specs{"chkOverride-$signature_index-$proof_index-$qty_index"} ne 'Y' ) {
			if ( $proof_index == 1 ) {
				insert_layout_proof( $sig_specs, 1, $qty_index, $specs, $Imposition );
			} elsif ( $proof_index == 2 ) {
				insert_colour_proof( $Project, $sig_specs, 2, $qty_index, $specs );
			} elsif ( $proof_index == 3 ) {
				insert_press_proof( $Project, $sig_specs, 3, $qty_index, $specs, $Imposition );
			} # end if
		} else {
			if ( ($proof_index == 1) and ($$specs{"ddmProofType-$signature_index-$proof_index-$qty_index"} eq 'DigitalDylux') and ( $$specs{"txtProofQuantity-$signature_index-$proof_index-$qty_index"} < $openprint::config{'ForceDigitalDyluxQuantity'} ) ) {
				$$specs{'alert'} .= 'We require Dylux Proofs<br/>';
				insert_layout_proof( $sig_specs, 1, $qty_index, $specs, $Imposition );
			} # end if
		} # end if

		my ( $quantity, $type ) = @$specs{
			"txtProofQuantity-$signature_index-$proof_index-$qty_index",
				"ddmProofType-$signature_index-$proof_index-$qty_index",
		};
		if ( ! ( $type and $quantity ) ) {
			if ( DEBUG ) {
				$log->debug("Next because to type or quantity for sig $signature_index proof $proof_index qty $qty_index ty[pe: $type qty: $quantity");
			} # end if
			next;
		} # end if
		
		my $ProofService = openprint::Service->find_one( name=>$type );

		my %MakeReady = openprint::service::get_price_object( $type.'MakeReady', $$totals{$type}{Quantity}, undef );
		$$specs{"MRPrice-$signature_index-$proof_index-$qty_index"} = $MakeReady{'Price'};
		my %price;
		if ( $ProofService ) {
			if ( $type eq 'PressProof' ) {
				%price = $ProofService->get_price( $$totals{$type}{Quantity}, $Equipment );
			} else {
				%price = $ProofService->get_price( $$totals{$type}{Quantity} );
			} # end if
		} # end if
		$$specs{"ServicePrice-$signature_index-$proof_index-$qty_index"} = $price{Price};
		$$specs{"ServiceUnits-$signature_index-$proof_index-$qty_index"} = $price{units};

		$Results{'Breakdown'} .= "Proof: $proof_index: Quantity: $quantity, Type: $type ";
		if ( $price{'units'} eq 'per square inch' ) {
			$Results{status} = 'uncalculated' if ! $$specs{"txtProofWidth-$signature_index-$proof_index-$qty_index"} * $$specs{"txtProofHeight-$signature_index-$proof_index-$qty_index"};
			$price{'Total'} = Math::Round::nearest( 0.01,
					$price{'Price'} * $$specs{"txtProofWidth-$signature_index-$proof_index-$qty_index"} * $$specs{"txtProofHeight-$signature_index-$proof_index-$qty_index"} * $quantity );
			$Results{'Breakdown'} .= sprintf('MR: %.2f + %d * %sx%s * $%.2f%s=$%.2f<br/>', $MakeReady{Price}, $quantity, $$specs{"txtProofWidth-$signature_index-$proof_index-$qty_index"},$$specs{"txtProofHeight-$signature_index-$proof_index-$qty_index"}, @price{'Price','units','Total'} );
		} elsif ( $price{'units'} eq 'per square foot' ) {
			$Results{status} = 'uncalculated' if ! $$specs{"txtProofWidth-$signature_index-$proof_index-$qty_index"} * $$specs{"txtProofHeight-$signature_index-$proof_index-$qty_index"};
			$price{'Total'} = $price{'Price'} * $$specs{"txtProofWidth-$signature_index-$proof_index-$qty_index"} * $$specs{"txtProofHeight-$signature_index-$proof_index-$qty_index"} / 144 * $quantity;
			$Results{'Breakdown'} .= sprintf('MR: %.2f + %d * %sx%s * $%.2f%s=$%.2f<br/>', $MakeReady{Price}, $quantity, $$specs{"txtProofWidth-$signature_index-$proof_index-$qty_index"},$$specs{"txtProofHeight-$signature_index-$proof_index-$qty_index"}, @price{'Price','units','Total'} );
		} else {
			$price{Total} = $price{Price} * $quantity;
			$Results{'Breakdown'} .= sprintf('MR: %.2f + %d*$%.2f%s=$%.2f<br/>', $MakeReady{Price}, $quantity, @price{'Price','units','Total'} );
		} # end if
		$$specs{"txtProofUnitPrice-$signature_index-$proof_index-$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $price{Total} );
		$Results{'Total'} += $price{Total} + $MakeReady{Price};
	} # end foreach my $proof_index
	$Results{Total} = Math::Round::nearest(0.01,$Results{Total});
	return %Results;
} # end sub signature_calc

sub delete_proofs {
	my ( $Project, $service_index, $signature_service_index, $qty_index ) = @_;

	my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
	my $signature_index = $$sig_specs{'SignatureIndex'};
	$_ = 'SELECT COUNT(strValue) FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName LIKE?';
	my ( $number_of_proofs ) = sql::execute( undef, undef, $_, $Project->id(), $service_index, "txtProofQuantity-$signature_index-%-$qty_index" );
	$number_of_proofs = 3 if $number_of_proofs < 3;

	foreach my $proof_index ( 1 .. $number_of_proofs ) {
		sql::execute( undef, undef, q{DELETE FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName=?}, $Project->id(), $service_index, "txtProofQuantity-$signature_index-$proof_index-$qty_index" );
		sql::execute( undef, undef, q{DELETE FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName=?}, $Project->id(), $service_index, "txtProofWidth-$signature_index-$proof_index-$qty_index" );
		sql::execute( undef, undef, q{DELETE FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName=?}, $Project->id(), $service_index, "txtProofHeight-$signature_index-$proof_index-$qty_index" );
		sql::execute( undef, undef, q{DELETE FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName=?}, $Project->id(), $service_index, "ddmProofType-$signature_index-$proof_index-$qty_index" );
	} # end foreach

} # end sub delete_proofs

# Deletes stale data, and inserts default Proofs For the supplied signature
sub insert_proofs {
	my ( $Project, $service_index, $signature_service_index, $qty_index ) = @_;

	my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
	my $Imposition = new openprint::Imposition();
	$Imposition->load( $sig_specs, $qty_index, $Project );
	my $specs = openprint::service::get_specs_ref( $Project, $service_index );

	my $ac = sql::start_transaction( $dbh );
	delete_proofs( $Project, $service_index, $signature_service_index, $qty_index );
	my @scanning_indices;
	my $services = $Project->services();

	if ( $$services{'Scanning'} ) {
		foreach my $index ( @{$$services{'Scanning'}} ) {
			my $scanning_specs = openprint::service::get_specs_ref( $Project, $index );
			if ( $$scanning_specs{'rdbRandomProof'} eq 'Yes' ) {
				push @scanning_indices, $index;
			} # end if
		} # end foreach scanning index
	} # end if Scanning

	if ( sets::isin( $signature_service_index, \@scanning_indices ) ) {
		insert_scanning_proof( $Project, $signature_service_index, 1, $qty_index, $specs );
	} else {
		insert_colour_proof( $Project, $sig_specs, 1, $qty_index, $specs );
		insert_layout_proof( $sig_specs, 2, $qty_index, $specs, $Imposition );
	} # end if
	sql::end_transaction( $dbh, $ac );

} # end sub insert_proofs

sub insert_scanning_proof {
	my ( $Project, $scanning_service_index, $proof_index, $qty_index, $specs ) = @_;

	my $sig_specs = openprint::service::get_specs_ref( $Project, $scanning_service_index );
	insert_new_proof( $specs, $proof_index, undef, @$sig_specs{'txtQuantity','txtScanWidthFinal','txtScanHeightFinal'}, 'EpsonProof', $qty_index );
} # end sub insert_scanning_proof

sub insert_press_proof($$$$$$) {
	my ( $Project, $sig_specs, $proof_index, $qty_index, $specs, $Imposition ) = @_;
	$$sig_specs{SideOneColours} = [openprint::Estimating::Printing::get_colours( $sig_specs, 'SideOne' )] if ! $$sig_specs{SideOneColours};
	$$sig_specs{SideTwoColours} = [openprint::Estimating::Printing::get_colours( $sig_specs, 'SideTwo' )] if ! $$sig_specs{SideTwoColours};
	my $quantity = 0;
	if ( sets::isin( $$sig_specs{'ddmRunStyle'.$qty_index}, ['Web','Sheet Work','Perfecting'] ) ) {
		$quantity += 1 if @{$$sig_specs{SideOneColours}};
		$quantity += 1 if @{$$sig_specs{SideTwoColours}};
	} else {
		$quantity += 1 if @{$$sig_specs{SideOneColours}} or @{$$sig_specs{SideTwoColours}};
	} # end if
	insert_new_proof( $specs, $proof_index, $$sig_specs{'SignatureIndex'}, $quantity, $Imposition->sheet_width(), $Imposition->sheet_height(), 'PressProof', $qty_index );
} # end sub insert_press_proof

sub insert_colour_proof($$$$$) {
	my ( $Project, $sig_specs, $proof_index, $qty_index, $specs ) = @_;

	#$log->debug("*** Inserting Colour Proof *******");
	my $Equipment = openprint::Equipment->find_one( strid=>$$sig_specs{'ddmPress'.$qty_index} ) if $$sig_specs{'ddmPress'.$qty_index};

	my ( $default_proof_type ) = $Equipment->specification( 'Default Colour Proof' ) if $Equipment;
	my $quantity = 0;

	if ( $default_proof_type ) {
		if ( 
				( $$specs{'RequireColourProofs'} eq 'Y' )  or (
					($$specs{'RequireColourProofs'} ne 'N') and $$sig_specs{'chkProcessColourSideOne'} ) ) {
			$quantity += 1;
		} # end if
		if ( 
				( $$specs{'RequireColourProofs'} eq 'Y' )  or (
					($$specs{'RequireColourProofs'} ne 'N') and $$sig_specs{'chkProcessColourSideTwo'} ) ) {
			$quantity += 1;
		} # end if

		# we need extra proofs for business cards.
		if ( $$sig_specs{'txtNameQuantity'} > 1 ) {
			$quantity *= $$sig_specs{'txtNameQuantity'};
		} # end if
		if ( $$sig_specs{'PageQuantity'.$qty_index} ) {
			$quantity *= $$sig_specs{'PageQuantity'.$qty_index} / $$sig_specs{'txtSpreadSize'} if $$sig_specs{'txtSpreadSize'};
		} # end if

		if ( $$specs{'RequireColourProofs'} eq 'N' ) {
			$quantity = 0;
		} # end if
	} # end if

# only if project requires 4 colour process.
	insert_new_proof( $specs, $proof_index, $$sig_specs{'SignatureIndex'}, $quantity, @$sig_specs{'txtWidth', 'txtHeight'}, $default_proof_type, $qty_index );
} # end sub insert_colour_proof

sub insert_layout_proof {
	my ( $sig_specs, $proof_index, $qty_index, $specs, $Imposition ) = @_;

	#my ( $caller, undef, $line ) = caller;
#$openprint::log->debug("Called insert_layout_proof from $caller : $line");
#$Imposition->display('insert_layout_proof');
	my $Equipment = $Imposition->Press();
	if ( ! $Equipment ) {
		$openprint::log->error("No equipment in insert_layout_proof");
	} # end if
	$Equipment = openprint::Equipment->find_one( strid=>$$sig_specs{'ddmPress'.$qty_index} ) if ! $Equipment;
	if ( ! $Equipment ) {
		$openprint::log->error("No equipment in insert_layout_proof");
	} # end if

	my $quantity = 0;
	my ( $default_proof_type ) = $Equipment->specification( 'Default Layout Proof' ) if $Equipment;
	if ( ! $default_proof_type ) {
		$openprint::log->debug("No Default Layout Proof for " . $Equipment->strid() ) if DEBUG and $Equipment;
	} else {
		$$sig_specs{SideOneColours} = [openprint::Estimating::Printing::get_colours( $sig_specs, 'SideOne' )] if ! $$sig_specs{SideOneColours};
		$$sig_specs{SideTwoColours} = [openprint::Estimating::Printing::get_colours( $sig_specs, 'SideTwo' )] if ! $$sig_specs{SideTwoColours};

		if ( sets::isin( $$Imposition{'runstyle'}, ['Web','Sheet Work', 'Perfecting'] ) ) {
			$quantity += 1 if @{$$sig_specs{SideOneColours}};
			$quantity += 1 if @{$$sig_specs{SideTwoColours}};
		} else {
			$quantity += 1 if @{$$sig_specs{SideOneColours}} or @{$$sig_specs{SideTwoColours}};
		} # end if
	} # end if

	insert_new_proof( $specs, $proof_index, $$sig_specs{'SignatureIndex'}, $quantity, $Imposition->sheet_width(), $Imposition->sheet_height(), $default_proof_type, $qty_index );

} # end sub insert_layout_proof

sub insert_new_proof {
    my ( $specs, $proof_index, $signature_index, $qty, $width, $height, $type, $qty_index ) = @_;
	$$specs{"txtProofQuantity-$signature_index-$proof_index-$qty_index"} = $qty;
	$$specs{"txtProofWidth-$signature_index-$proof_index-$qty_index"} = 1*$width;
	$$specs{"txtProofHeight-$signature_index-$proof_index-$qty_index"} = 1*$height;
	$$specs{"ddmProofType-$signature_index-$proof_index-$qty_index"} = $type;
	$$specs{"txtProofIndex-$signature_index-$proof_index-$qty_index"} = $proof_index;
} # end sub insert_new_proof

sub load_proof_info {
    my ( $Project, $service_index, $signature_index, $qty_index, $specs ) = @_;

    my @proof_info = ();

	$specs = openprint::service::get_specs_ref( $Project, $service_index ) if ! $specs;

	my @proofs;
	foreach my $key ( keys %$specs ) {
		if ( $key =~ /^txtProofIndex-$signature_index-\d+-$qty_index$/ ) {
			push @proofs, $$specs{$key};
		} # end if
	} # end foreach
	foreach my $proof_index ( sort @proofs ) {
        my ( $quantity, $width, $height, $type ) = @$specs{
                "txtProofQuantity-$signature_index-$proof_index-$qty_index",
                "txtProofWidth-$signature_index-$proof_index-$qty_index",
                "txtProofHeight-$signature_index-$proof_index-$qty_index",
                "ddmProofType-$signature_index-$proof_index-$qty_index"
                };
		push @proof_info, $proof_index, $quantity, 1*$width, 1*$height, $type, ssi::make_drop_down( [ map { $_->name(), $_->description() } openprint::Service->find('category'=>'Proofs') ], $type );
    } # end foreach
    return @proof_info;
} # end sub load_proof_info

sub get_proof_specs {
    my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();

	my $specs = openprint::service::get_specs_ref( $Project, $service_index );
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		my %proof_indexes;
		foreach my $key ( keys %$specs ) {
#$openprint::log->debug("key $key");
			if ( $key =~ /^txtProofIndex-(\d+)-(\d+)-$qty_index$/ ) {
				push @{$proof_indexes{$1}}, $$specs{$key};
			} # end if
		} # end foreach

		foreach my $signature_service_index ( $Project->signatures() ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
			my $signature_index = $$sig_specs{'SignatureIndex'};
			if ( ! $$sig_specs{'txtImposition'.$qty_index} ) {
				$log->warn("No imposition in signature $signature_index") if DEBUG;
				next;
			} # end if
			my $Imposition = new openprint::Imposition();
			$Imposition->load( $sig_specs, $qty_index, $Project );
			my $Equipment = $Imposition->Press();
			$Imposition->display( "For sig $signature_index") if DEBUG;

			if ( ( ! sets::isin( 1, $proof_indexes{$signature_index} ) ) and $openprint::config{'Add_Default_Layout_Proof'} eq 'Y') {
				push @{$proof_indexes{$signature_index}}, 1;
				$openprint::log->debug("ADDING Layout Proof to $signature_index") if DEBUG;
				insert_layout_proof( $sig_specs, 1, $qty_index, $specs, $Imposition );
			} # end if
			if ( ( ! sets::isin( 2, $proof_indexes{$signature_index} ) ) and $openprint::config{'Add_Default_Colour_Proof'} eq 'Y') {
				push @{$proof_indexes{$signature_index}}, 2;
				$openprint::log->debug("ADDING Colour Proof to $signature_index") if DEBUG;
				insert_colour_proof( $Project, $sig_specs, 2, $qty_index, $specs );
			} # end if
			if ( ! sets::isin( 3, $proof_indexes{$signature_index} ) ) {
				if ( ( $openprint::config{'Add_Default_Press_Proof'} eq 'Y' ) or ( $Equipment and $Equipment->specification('Require Press Proof') eq 'Y' ) ) {
					push @{$proof_indexes{$signature_index}}, 3;
					$log->debug("Adding Press Proof");
					insert_press_proof( $Project, $sig_specs, 3, $qty_index, $specs, $Imposition );
				} elsif ( DEBUG ) {
$log->debug("Press proof not needed");
				} # end if
			} elsif ( DEBUG ) {
$log->debug("Already had press proof");
			} # end if

				@{$$variable{'Proofs-'.$signature_index.'-'.$qty_index}} = ();
			foreach my $proof_index ( sort @{$proof_indexes{$signature_index}} ) {
				my ( $quantity, $width, $height, $type ) = @$specs{
					"txtProofQuantity-$signature_index-$proof_index-$qty_index",
						"txtProofWidth-$signature_index-$proof_index-$qty_index",
						"txtProofHeight-$signature_index-$proof_index-$qty_index",
						"ddmProofType-$signature_index-$proof_index-$qty_index"
				};
				push @{$$variable{'Proofs-'.$signature_index.'-'.$qty_index}},
					 $proof_index, $quantity, 1*$width, 1*$height, $type, ssi::make_drop_down( [ map { $_->name(), $_->description() } openprint::Service->find('category'=>'Proofs') ], $type );
			} # end foreach

		} # end foreach signature
	} # end foreach qty_index
    @{$$variable{'SignatureGroups'}} = ();
    foreach my $signature_service_index ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
		push @{$$variable{'SignatureGroups'}}, @$sig_specs{'SignatureIndex', 'txtServiceDescription'};
	} # end foreach signature

# Now do scanning
	if ( $$services{'Scanning'} ) {
		foreach my $index ( @{$$services{'Scanning'}} ) {
			my $scanning_specs = openprint::service::get_specs_ref( $Project, $index );
			if ( $$scanning_specs{'rdbRandomProof'} eq 'Yes' ) {
# add a scanning proof
				push @{$$variable{'SignatureGroups'}}, $$scanning_specs{'SignatureIndex'}, 'Scanning Proof';
				@{$$variable{'Proofs'.$$scanning_specs{'SignatureIndex'}}} = load_proof_info( $Project, $service_index, $$scanning_specs{'SignatureIndex'} );
			} # end if
		} # end foreach scanning service
	} # end if

} # end sub get_proof_specs

sub save_proof_specs {
    my ( $r, $log, $dbh, $variable, $project_index, $service_index ) = @_;

    $log->debug("In Save Proof Specs" );

# First off, slap everything in, just like every other service
	#openprint::service::save_service( $r, $log, $dbh, $project_index, $service_index );
	my @v = variables( $project_index, $service_index, openprint::service::get_specs_ref($Project, $service_idex), \%openprint::param );
	my $ac = sql::start_transaction( $dbh );
	foreach my $key (@v) {
		if ( ! exists $openprint::param{$key} ) {
			openprint::service::delete_service_spec( $project_index, $service_index, $key );
		} else {
			openprint::service::insert_service_spec( $log, $dbh, $project_index, $service_index, $key, $openprint::param{$key}, 0 );
		} # end if
	} # end foreach
	sql::end_transaction( $dbh, $ac );

	my $redirect = 0;

# Now check to see if we need to add more proofs, and redirect back
	foreach my $key ( keys %openprint::param ) {
		if ( $key =~ /rdbAdditional-(\d*)-(\d*)/ ) {
			if ( $openprint::param{$key} eq 'Yes' ) {
				my $signature_index = $1;

				my $ac = sql::start_transaction( $dbh );
				$_ = 'SELECT lngServiceIndex FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND strName=? AND strValue=?';
				my ( $signature_service_index ) = sql::execute( $log, $dbh, $_, $project_index, 'SignatureIndex',$signature_index );

				foreach my $qty_index ( 1 .. 3 ) {
					$_ = 'SELECT MAX(strValue::integer) FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName LIKE ?';
					my ( $proof_index ) = sql::execute( $log, $dbh, $_, $project_index, $service_index, "txtProofIndex-$signature_index-%-$qty_index" );
					$proof_index += 1;
					$proof_index = 4 if $proof_index < 4;

					openprint::service::insert_service_spec( $log, $dbh, $project_index, $service_index, "txtProofQuantity-$signature_index-$proof_index-$qty_index", 1 );
					openprint::service::insert_service_spec( $log, $dbh, $project_index, $service_index, "txtProofWidth-$signature_index-$proof_index-$qty_index", '' );
					openprint::service::insert_service_spec( $log, $dbh, $project_index, $service_index, "txtProofHeight-$signature_index-$proof_index-$qty_index", '' );
					openprint::service::insert_service_spec( $log, $dbh, $project_index, $service_index, "ddmProofType-$signature_index-$proof_index-$qty_index", '' );
					openprint::service::insert_service_spec( $log, $dbh, $project_index, $service_index, "txtProofIndex-$signature_index-$proof_index-$qty_index", $proof_index );
				} # end foreach

				sql::end_transaction( $dbh, $ac );

				$redirect = 1;
			} # end if
		} # end if
	} # end foreach

	if ( $redirect ) {
		( $_ ) = sql::execute( $log,  $dbh, 'SELECT strDetailedURL FROM Service_Types WHERE name=?', 'Proofs');
		$$variable{'Redirect'} = '/main/project/'.$_;
	} else {
		if ($r->param('txtPrice1') > 0 || $r->param('txtPrice2') > 0 || $r->param('txtPrice3') > 0 ) {
			sql::update( $log, $dbh, 'tbl_Project_Contents', ['lngProjectIndex=? AND lngServiceIndex=?', $project_index, $service_index ], 'strStatus', 'calculated');
		} # end if
	} # end if
} # end sub save_proof_specs

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	if ( $qty_index ) {
		my %proof_totals;
		foreach my $ss_id ( $Project->signatures() ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
			if ( ! $$sig_specs{'txtImposition'.$qty_index} ) {
				next;
			} # end if
			my $signature_index = $$sig_specs{'SignatureIndex'};
			foreach my $key ( keys %{$specs} ) {
				if ( my ($proof_index) = $key =~ /^txtProofIndex\-$signature_index\-(\d+)\-$qty_index$/ ) {
					next if ! $$specs{"ddmProofType-$signature_index-$proof_index-$qty_index"};

					if ( my $Service = openprint::Service->find_one( name=>$$specs{"ddmProofType-$signature_index-$proof_index-$qty_index"}) ) {
						if ( sets::isin( $$specs{"ddmProofType-$signature_index-$proof_index-$qty_index"}, [ 'PressProof', 'PDFProof' ] ) ) {
							my $desc = sprintf('</td><td class="type">%s', $Service->description() );
							$proof_totals{$desc} += $$specs{"txtProofQuantity-$signature_index-$proof_index-$qty_index"};
						} else {
							my $desc = sprintf('%s&quot;x%s&quot;</td><td class="type">%s', @$specs{
									"txtProofWidth-$signature_index-$proof_index-$qty_index",
									"txtProofHeight-$signature_index-$proof_index-$qty_index"}, $Service->description() );
							$proof_totals{$desc} += $$specs{"txtProofQuantity-$signature_index-$proof_index-$qty_index"};
						} # end if
					} # end if
				} # end if
			} # end foreach key
		} # end foreach signature
		if ( ! %proof_totals ) {
			return '';
		} # end if
		my $summary = '<table class="ProofsSummary">';
		foreach my $k ( sort keys %proof_totals ) {
			next if ! $proof_totals{$k};
			$summary .= '<tr><td class="quantity">'.$proof_totals{$k}.'</td><td class="size">'.$k.'</td></tr>';
		} # end foreach
		return $summary.'</table>';
	} # end if qty_index
	return '';
} # end sub summary

sub signature_summary {
    my ( $Project, $service_id, $specs, $qty_index, $ss_id ) = @_;
    $specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
    if ( $qty_index ) {
        my %proof_totals;
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		if ( ! $$sig_specs{'txtImposition'.$qty_index} ) {
			next;
		} # end if
		my $signature_index = $$sig_specs{'SignatureIndex'};
		foreach my $key ( keys %{$specs} ) {
			if ( my ($proof_index) = $key =~ /^txtProofIndex\-$signature_index\-(\d+)\-$qty_index$/ ) {
				if ( my $Service = openprint::Service->find_one( name=>$$specs{"ddmProofType-$signature_index-$proof_index-$qty_index"}) ) {
					if ( sets::isin( $$specs{"ddmProofType-$signature_index-$proof_index-$qty_index"}, [ 'PressProof', 'PDFProof' ] ) ) {
						my $desc = sprintf('</td><td class="type">%s', $Service->description() );
						$proof_totals{$desc} += $$specs{"txtProofQuantity-$signature_index-$proof_index-$qty_index"};
					} else {
						my $desc = sprintf('%s&quot;x%s&quot;</td><td class="type">%s', @$specs{
								"txtProofWidth-$signature_index-$proof_index-$qty_index",
								"txtProofHeight-$signature_index-$proof_index-$qty_index"}, $Service->description() );
						$proof_totals{$desc} += $$specs{"txtProofQuantity-$signature_index-$proof_index-$qty_index"};
					} # end if
				} # end if
			} # end if
		} # end foreach key
        if ( ! %proof_totals ) {
            return '';
        } # end if
        my $summary = '<table class="ProofsSummary">';
        foreach my $k ( keys %proof_totals ) {
            next if ! $proof_totals{$k};
            $summary .= '<tr><td class="quantity">'.$proof_totals{$k}.'</td><td class="size">'.$k.'</td></tr>';
        } # end foreach
        return $summary.'</table>';
    } # end if qty_index
    return '';
} # end sub signature_summary

sub breakupsummary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	my $Currency = openprint::Currency::get_current();
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	if ( $qty_index ) {
		my %proof_totals;
		my %proof_tot;
		my %Totprice;
		foreach my $ss_id ( $Project->signatures() ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
			my $signature_index = $$sig_specs{'SignatureIndex'};
			foreach my $key ( keys %{$specs} ) {
				if ( my ($proof_index) = $key =~ /^txtProofIndex-$signature_index-(\d*)-$qty_index$/ ) {
					my $Service = openprint::Service->find_one('name'=>$$specs{"ddmProofType-$signature_index-$proof_index-$qty_index"});
					if ( $Service ) {	
						my $desc = sprintf('<td align="left">%s&quot;x%s&quot;</td><td align="left">%s', @$specs{
								"txtProofWidth-$signature_index-$proof_index-$qty_index",
								"txtProofHeight-$signature_index-$proof_index-$qty_index"}, $Service->description() );
						my $qty      = $$specs{"txtProofQuantity-$signature_index-$proof_index-$qty_index"};
						if ( $qty != 0 ) {
							$proof_totals{$desc} += $$specs{"txtProofQuantity-$signature_index-$proof_index-$qty_index"};
							my $Uprice   = $$specs{"txtProofUnitPrice-$signature_index-$proof_index-$qty_index"};
							my $type = @$specs{"ddmProofType-$signature_index-$proof_index-$qty_index"};
							if ( ! $proof_tot{$type} ) {
								$proof_tot{$type} = { Quantity => 0, Price => 0 };
							} # end if
							$proof_tot{$type}{Quantity} += $qty;
							my %MkReady  = openprint::service::get_price_object( $type.'MakeReady', $proof_tot{$type}{Quantity}, undef );
							$Totprice{$desc} += ($Uprice*$qty) + $MkReady{Price};
						} # end if
					} # end if
				} # end if
			} # end foreach key
		} # end foreach signature
##		my $summary = '<table class = "insideservice" style="width:auto;table-layout:auto;">';
		my $summary = '<table>';

		foreach my $k ( keys %proof_totals ) {
			next if ! $proof_totals{$k};
			$summary .= '<tr><td>'.$proof_totals{$k}.'&nbsp;&nbsp;&nbsp;</td>'.$k.'&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>';
			$summary .= '<td class="Price">'.sprintf('%s%.2f',$Currency->symbol(), $Totprice{$k}).'</td></tr>';
		} # end foreach
		return $summary.'</table>';
	} # end if qty_index
	return '';
} # end sub breakupsummary


sub project_summary {
	my ( $Project, $service_id, $specs ) = @_;
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

	my %types;

	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		my $signature_index = $$sig_specs{'SignatureIndex'};
		foreach my $key ( keys %{$specs} ) {
			if ( my ($proof_index, $qty_index) = $key =~ /^txtProofIndex-$signature_index-(\d*)-(\d*)$/ ) {
				next if ! $$specs{"ddmProofType-$signature_index-$proof_index-$qty_index"};
				next if ! $$specs{"txtProofQuantity-$signature_index-$proof_index-$qty_index"};
				if ( my $Service = openprint::Service->find_one('name'=>$$specs{"ddmProofType-$signature_index-$proof_index-$qty_index"}) ) {
					$types{$Service->description()} = 1;
				} # end if
			} # end if
		} # end foreach key
	} # end foreach signature
	return ' ' . join(',', keys %types) . '<br/>' if %types;
  return '';
} # end sub project_summary

sub has_overrides {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

	my @v;

	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		my $signature_index = $$sig_specs{SignatureIndex};
		foreach my $key ( keys %{$specs} ) {
			if ( $key =~ /^txtProofIndex-$signature_index-(\d+)-$qty_index$/ ) {
				my ( $proof_index ) = ( $1 );
				if ( $$specs{"chkOverride-$signature_index-$proof_index-$qty_index"} ) {
					push @v,    "chkOverride-$signature_index-$proof_index-$qty_index";
				} # end if
			} # end if
		} # end foreach key
	} # end foreach signature
    return @v;
} # end sub has_overrides


1;
__END__
