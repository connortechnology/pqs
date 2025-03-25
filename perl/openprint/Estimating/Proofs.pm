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
use warnings;

package openprint::Estimating::Proofs;
use POSIX qw( ceil );
use openprint ();
use vars qw( $log $dbh );
*log = \$openprint::log;
*dbh = \$openprint::dbh;

require sql;
require openprint::service;
require openprint::Estimating::Printing;
use Data::Dumper;


use constant DEBUG => 0;
my @variables = (
		'txtPrice',
		'CustomProofSpecs',
		'RequireColourProofs',
		'RequirePressProofs',
		'alert',
		);
my %ProofServices;

sub variables {
	my ( $p_id, $s_id, $old_specs, $specs ) = @_;

	my $Project = new openprint::Project( $p_id );
	my @v = @variables;
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		push @v, 'txtPrice'.$qty_index;
	} # end foreach qty_index

	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		my $form = $$sig_specs{SignatureIndex};
		foreach my $key ( keys %{$specs} ) {
			if ( $key =~ /^txtProofIndex\-$form\-(\d+)\-(\d+)$/ ) {
				my ( $proof_index, $qty_index ) = ( $1, $2 );

				push @v, map { join('-', $_, $form, $proof_index, $qty_index) }
				(
				 'txtProofWidth',
				 'txtProofHeight',
				 'txtProofQuantity',
				 'ddmProofType',
				 'txtProofUnitPrice',
				 'txtProofIndex',
				 'chkOverride',
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
		my $form = $$sig_specs{SignatureIndex};
		foreach my $key ( keys %{$specs} ) {
			if ( $key =~ /^txtProofIndex\-$form\-(\d+)\-(\d+)$/ ) {
				my ( $proof_index, $qty_index ) = ( $1, $2 );

				push @v,	(
						"txtProofWidth-$form-$proof_index-$qty_index",
						"txtProofHeight-$form-$proof_index-$qty_index", 
						"txtProofQuantity-$form-$proof_index-$qty_index",
						"ddmProofType-$form-$proof_index-$qty_index",
						"txtProofUnitPrice-$form-$proof_index-$qty_index",
						"txtProofIndex-$form-$proof_index-$qty_index",
						"chkOverride-$form-$proof_index-$qty_index",
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
		if ( $key =~ /^txtProofIndex\-(\d+)\-(\d+)\-$qty_index$/ ) {
      $openprint::log->debug($key);
			$$indexes{$1}[$$specs{$key}] = $$specs{$key};
			push @{$$types{$1}}, $$specs{"ddmProofType-$1-$2-$qty_index"};
		} # end if
	} # end foreach
if ( DEBUG ) {
$openprint::log->debug(Data::Dumper::Dumper($indexes));
}
} # end sub get_indexes

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $status = 'calculated';
  $$specs{alert} = '';

	$log->debug("START PROOFS!!!!!!!!!!!!!!!!!! ($project_index) ($service_index)") if DEBUG;
	my $Project = new openprint::Project($project_index);
  my $ServiceType = $Project->ServiceType($service_index);

	my @signature_service_indices = $Project->signatures();
	my $minCharge = openprint::service::get_price('ProofsMinimumCharge', undef, undef);
	%ProofServices = map { $_->name(), $_ } openprint::Service->find(servicetype_id=>$ServiceType->id());#category=>'Proofs');

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"txtPrice$qty_index"} = '';
		my $totalPrice = 0;
		my $totalQuantity = 0;

		my %proof_indexes;
		my %proof_types;
		my %proof_totals;
		$$specs{'hdnBreakdown'.$qty_index} = '';
		get_indexes($specs, $qty_index, \%proof_indexes, \%proof_types);

		# First, build a hash containing the quantities of each proof.  The reason for this is to honour quantity discounts.
		foreach my $signature_service_index ( @signature_service_indices ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );

			my $form = $$sig_specs{SignatureIndex};

			$$specs{'hdnBreakdown'.$qty_index} .= "Signature $form<br/>";
			if ( ! $$sig_specs{'txtImposition'.$qty_index} ) {
				# Remove it so we don't have to test for it later
				$$specs{'hdnBreakdown'.$qty_index} .= 'No proofs needed because there is no imposition';
				next;
			} # end if
			my $Imposition = new openprint::Imposition();
			$Imposition->load($sig_specs, $qty_index, $Project);
			my $Equipment = $Imposition->Press();
			$$specs{'hdnBreakdown'.$qty_index} .= $Imposition->to_string().'</br>';

			if ( ( !$proof_indexes{$form}[1] ) and ($openprint::config{Add_Default_Layout_Proof} eq 'Y') ) {
				$proof_indexes{$form}[1] = 1;
			} # end if
			if ( ( !$proof_indexes{$form}[2] ) and ($openprint::config{Add_Default_Colour_Proof} eq 'Y') ) {
				$proof_indexes{$form}[2] = 2;
			} # end if
			if ( ( !$proof_indexes{$form}[3] ) and ( 
				( $openprint::config{Add_Default_Press_Proof} and ($openprint::config{Add_Default_Press_Proof} eq 'Y') )
				or 
				( $Equipment and ($_ = $Equipment->specification('Require Press Proof')) and ( $_ eq 'Y') ) 
				or 
				($_ = $Project->Company()->add_press_proofs() and $_->value() and ($_->value() eq 'Y') ) 
				) ) {
				$proof_indexes{$form}[3] = 3;
			} # end if
				
			foreach my $proof_index ( @{$proof_indexes{$form}} ) {
				next if !($proof_index and $proof_indexes{$form}[$proof_index]);

				if ( (!$$specs{"chkOverride-$form-$proof_index-$qty_index"}) or ($$specs{"chkOverride-$form-$proof_index-$qty_index"} ne 'Y') ) {
					if ( $proof_index == 1 ) {
						insert_layout_proof( $sig_specs, 1, $qty_index, $specs, $Imposition );
					} elsif ( $proof_index == 2 ) {
						insert_colour_proof( $Project, $sig_specs, 2, $qty_index, $specs, $Imposition );
					} elsif ( $proof_index == 3 ) {
						insert_press_proof( $Project, $sig_specs, 3, $qty_index, $specs, $Imposition );
					} # end if
				} else {
					if ( ($proof_index == 1) and ($$specs{"ddmProofType-$form-$proof_index-$qty_index"} eq 'DigitalDylux') and ( $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"} < $openprint::config{ForceDigitalDyluxQuantity} ) ) {
						$$specs{alert} .= "We require Dylux Proofs<br/>";
						insert_layout_proof( $sig_specs, 1, $qty_index, $specs, $Imposition );
					} # end if
				} # end if

				my ( $quantity, $type ) = @$specs{
					"txtProofQuantity-$form-$proof_index-$qty_index",
						"ddmProofType-$form-$proof_index-$qty_index",
				};
        if ($type) {
          if ( ! $proof_totals{$type} ) {
            $proof_totals{$type} = { Quantity => 0, Price => 0 };
          } # end if
          $proof_totals{$type}{Quantity} += $quantity;
				  $totalQuantity += $quantity;
        }
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
			my $Equipment = $Imposition->Press();
			my %Results = signature_calc( $Project, $specs, $sig_specs, $qty_index, \%proof_indexes, \%proof_totals, $Equipment, $Imposition );
			$totalPrice += $Results{Total};
			$$specs{"hdnBreakdown$qty_index"} .= $Results{Breakdown};
			$status = $Results{status} if $Results{status};
		} # end foreach my $signature_service_index

		if ( $minCharge and ( $totalPrice < $minCharge ) and $totalQuantity ) {
			$totalPrice = $minCharge;
		} # end if

		$totalPrice *= (1+$Project->markup()/100) if $Project->markup();
		$$specs{"txtPrice$qty_index"} = sprintf($openprint::config{ProjectMoneyFormat}, $totalPrice);
	} # end foreach qty_index

	$log->debug('PROOFS!!!!!!!!!!!!!!!!!!') if DEBUG;
	return $$specs{Status} = $status;
} # end sub calc

sub signature_calc {
	my ( $Project, $specs, $sig_specs, $qty_index, $indexes, $totals, $Equipment, $Imposition ) = @_;

	my %Results = ( Breakdown => '' );
	#return %Results if ! $$sig_specs{'txtImposition'.$qty_index};

	my $form = $$sig_specs{SignatureIndex};
	if ( !$Equipment ) {
		$openprint::log->error('Looking up equipment in Proofs: signature_calc');
		$Equipment = openprint::Equipment->find_one(strid => $$sig_specs{'ddmPress'.$qty_index});
		if ( !$Equipment ) {
			$openprint::log->warn('Proofs: signature_calc: No equipment for ' . $$sig_specs{'ddmPress'.$qty_index});
			return %Results;
		}
	}

	$$indexes{$form} = [] if ! $$indexes{$form};
	$log->debug('Proof indexes '.join(',', map { $_ ? $_ : () } @{$$indexes{$form}})) if DEBUG;

	if ( ( ! $$indexes{$form}[1] ) and ($openprint::config{Add_Default_Layout_Proof} eq 'Y') ) {
		$$indexes{$form}[1] = 1;
	} # end if
	if ( ( ! $$indexes{$form}[2] ) and ($openprint::config{Add_Default_Colour_Proof} eq 'Y') ) {
		$$indexes{$form}[2] = 2;
	} # end if
	$$specs{RequirePressProofs} = '' if ! defined $$specs{RequirePressProofs};
	if ( ( ! $$indexes{$form}[3] ) and  
			( (!$$specs{RequirePressProofs}) or ($$specs{RequirePressProofs} ne 'N') ) and (
				( $$specs{RequirePressProofs} and ($$specs{RequirePressProofs} eq 'Y') ) 
				or
				( $openprint::config{Add_Default_Press_Proof} and ($openprint::config{Add_Default_Press_Proof} eq 'Y') ) 
				or 
				( $$sig_specs{rdbPressProof} and ($$sig_specs{rdbPressProof} eq 'Y') )
				or
				($_ = $Project->Company()->add_press_proofs() and $_->value() and ($_->value() eq 'Y') ) 
	   ) ) {
		$$indexes{$form}[3] = 3;
	} # end if
	$log->debug('Proof indexes '.join(',', map { $_ ? $_ : () } @{$$indexes{$form}})) if DEBUG;

	%ProofServices = map { $_->name(), $_ } openprint::Service->find(category=>'Proofs') if !%ProofServices;

	foreach my $proof_index ( @{$$indexes{$form}} ) {
		next if ! ($proof_index and $$indexes{$form}[$proof_index]);
		if (
				(!$$specs{"chkOverride-$form-$proof_index-$qty_index"})
				or
				( $$specs{"chkOverride-$form-$proof_index-$qty_index"} ne 'Y')
			 ) {
			if ( $proof_index == 1 ) {
				insert_layout_proof($sig_specs, 1, $qty_index, $specs, $Imposition);
			} elsif ( $proof_index == 2 ) {
				insert_colour_proof($Project, $sig_specs, 2, $qty_index, $specs, $Imposition);
			} elsif ( $proof_index == 3 ) {
				insert_press_proof($Project, $sig_specs, 3, $qty_index, $specs, $Imposition);
			} # end if
		} else {
			if ( ($proof_index == 1)
					and
					($$specs{"ddmProofType-$form-$proof_index-$qty_index"} eq 'DigitalDylux')
					and
					($$specs{"txtProofQuantity-$form-$proof_index-$qty_index"} < $openprint::config{ForceDigitalDyluxQuantity})
				 ) {
				$$specs{alert} .= 'We require Dylux Proofs<br/>';
				insert_layout_proof($sig_specs, 1, $qty_index, $specs, $Imposition);
			} # end if
		} # end if

		my ( $quantity, $type ) = @$specs{
			"txtProofQuantity-$form-$proof_index-$qty_index",
				"ddmProofType-$form-$proof_index-$qty_index",
		};
		if ( !($type and $quantity) ) {
			if ( DEBUG ) {
				$log->debug("Next because no type or quantity for sig $form proof $proof_index qty_index $qty_index type $type qty $quantity");
			} # end if
			next;
		} # end if
		
		my $ProofService = $ProofServices{$type};

		my %MakeReady = openprint::service::get_price_object($type.'MakeReady', $$totals{$type}{Quantity}, undef);
		if ( !%MakeReady ) {
			$MakeReady{Price} = 0;
		}
		$$specs{join('-','MRPrice',$form,$proof_index,$qty_index)} = $MakeReady{Price};
		my %price;
		if ( $ProofService ) {
      $openprint::log->debug("Proofs service: $$ProofService{name}");
			if ( $type eq 'PressProof' ) {
				%price = $ProofService->get_price($$totals{$type}{Quantity}, $Equipment);
			} else {
				%price = $ProofService->get_price($$totals{$type}{Quantity});
			} # end if
		} # end if
    $price{Price} = 0 if ! defined $price{Price};
		$price{units} = 'each' if ! $price{units};
		$$specs{join('-','ServicePrice',$form,$proof_index,$qty_index)} = $price{Price};
		$$specs{join('-','ServiceUnits',$form,$proof_index,$qty_index)} = $price{units};

		$Results{Breakdown} .= "Proof: $proof_index: Quantity: $quantity, Type: $type ";
		if ( $price{units} eq 'per square inch' ) {
			$Results{status} = 'uncalculated' if ! $$specs{"txtProofWidth-$form-$proof_index-$qty_index"} * $$specs{"txtProofHeight-$form-$proof_index-$qty_index"};
			$price{Total} = Math::Round::nearest( 0.01,
					$price{Price} * $$specs{"txtProofWidth-$form-$proof_index-$qty_index"} * $$specs{"txtProofHeight-$form-$proof_index-$qty_index"} * $quantity );
			$Results{Breakdown} .= sprintf('MR: %.2f + %d * %sx%s * $%.2f%s=$%.2f<br/>', $MakeReady{Price}, $quantity, $$specs{"txtProofWidth-$form-$proof_index-$qty_index"},$$specs{"txtProofHeight-$form-$proof_index-$qty_index"}, @price{'Price','units','Total'} );
		} elsif ( $price{units} eq 'per square foot' ) {
			$Results{status} = 'uncalculated' if ! $$specs{"txtProofWidth-$form-$proof_index-$qty_index"} * $$specs{"txtProofHeight-$form-$proof_index-$qty_index"};
			$price{Total} = $price{Price} * $$specs{"txtProofWidth-$form-$proof_index-$qty_index"} * $$specs{"txtProofHeight-$form-$proof_index-$qty_index"} / 144 * $quantity;
			$Results{Breakdown} .= sprintf('MR: %.2f + %d * %sx%s * $%.2f%s=$%.2f<br/>', $MakeReady{Price}, $quantity, $$specs{"txtProofWidth-$form-$proof_index-$qty_index"},$$specs{"txtProofHeight-$form-$proof_index-$qty_index"}, @price{'Price','units','Total'} );
		} elsif ($price{units} eq 'each' or lc($price{units})eq 'per proof') {
			$price{Total} = $price{Price} * $quantity;
			$Results{Breakdown} .= sprintf('MR: $%.2f + %d*$%.2f%s=$%.2f<br/>', $MakeReady{Price}, $quantity, @price{'Price','units','Total'} );
    } else {
			$price{Total} = $price{Price} * $quantity;
			$Results{Breakdown} .= sprintf('MR: %.2f + %d*$%.2f%s=$%.2f<br/>', $MakeReady{Price}, $quantity, @price{'Price','units','Total'} );
      $Results{Breakdown} .= '<div class="error">Warning unsupported units for '.$ProofService->description().'</div>';
		} # end if
		$$specs{"txtProofUnitPrice-$form-$proof_index-$qty_index"} = sprintf($openprint::config{ProjectMoneyFormat}, $price{Total});
		$Results{Total} += $price{Total} + $MakeReady{Price};
	} # end foreach my $proof_index
	$Results{Total} = Math::Round::nearest(0.01, $Results{Total});
	return %Results;
} # end sub signature_calc

sub delete_proofs {
	my ( $Project, $service_index, $signature_service_index, $qty_index ) = @_;

	my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
	my $form = $$sig_specs{SignatureIndex};
	$_ = 'SELECT COUNT(strValue) FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName LIKE?';
	my ( $number_of_proofs ) = sql::execute( undef, undef, $_, $Project->id(), $service_index, "txtProofQuantity-$form-%-$qty_index" );
	$number_of_proofs = 3 if $number_of_proofs < 3;

	foreach my $proof_index ( 1 .. $number_of_proofs ) {
		sql::execute( undef, undef, q{DELETE FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName=?}, $Project->id(), $service_index, "txtProofQuantity-$form-$proof_index-$qty_index" );
		sql::execute( undef, undef, q{DELETE FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName=?}, $Project->id(), $service_index, "txtProofWidth-$form-$proof_index-$qty_index" );
		sql::execute( undef, undef, q{DELETE FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName=?}, $Project->id(), $service_index, "txtProofHeight-$form-$proof_index-$qty_index" );
		sql::execute( undef, undef, q{DELETE FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName=?}, $Project->id(), $service_index, "ddmProofType-$form-$proof_index-$qty_index" );
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

	if ( $$services{Scanning} ) {
		foreach my $index ( @{$$services{Scanning}} ) {
			my $scanning_specs = openprint::service::get_specs_ref( $Project, $index );
			if ( $$scanning_specs{rdbRandomProof} eq 'Yes' ) {
				push @scanning_indices, $index;
			} # end if
		} # end foreach scanning index
	} # end if Scanning

	if ( sets::isin( $signature_service_index, \@scanning_indices ) ) {
		insert_scanning_proof( $Project, $signature_service_index, 1, $qty_index, $specs );
	} else {
		insert_colour_proof( $Project, $sig_specs, 1, $qty_index, $specs, $Imposition );
		insert_layout_proof( $sig_specs, 2, $qty_index, $specs, $Imposition );
	} # end if
	sql::end_transaction( $dbh, $ac );

} # end sub insert_proofs

sub insert_scanning_proof {
	my ( $Project, $scanning_service_index, $proof_index, $qty_index, $specs ) = @_;

	my $sig_specs = openprint::service::get_specs_ref( $Project, $scanning_service_index );
	insert_new_proof( $specs, $proof_index, undef, @$sig_specs{'txtQuantity','txtScanWidthFinal','txtScanHeightFinal'}, 'EpsonProof', $qty_index );
} # end sub insert_scanning_proof

sub insert_press_proof {
	my ( $Project, $sig_specs, $proof_index, $qty_index, $specs, $Imposition ) = @_;
	$$sig_specs{SideOneColours} = [openprint::Estimating::Printing::get_colours( $sig_specs, 'SideOne' )] if ! $$sig_specs{SideOneColours};
	$$sig_specs{SideTwoColours} = [openprint::Estimating::Printing::get_colours( $sig_specs, 'SideTwo' )] if ! $$sig_specs{SideTwoColours};
	my $quantity = 0;
	if ( (!$$specs{RequirePressProofs}) or ($$specs{RequirePressProofs} ne 'N') ) {
		if ( sets::isin( $$sig_specs{'ddmRunStyle'.$qty_index}, ['Web','Sheet Work','Perfecting'] ) ) {
			$quantity += 1 if @{$$sig_specs{SideOneColours}};
			$quantity += 1 if @{$$sig_specs{SideTwoColours}};
		} else {
			$quantity += 1 if @{$$sig_specs{SideOneColours}} or @{$$sig_specs{SideTwoColours}};
		} # end if
	} # end if
	insert_new_proof( $specs, $proof_index, $$sig_specs{SignatureIndex}, $quantity, $Imposition->sheet_width(), $Imposition->sheet_height(), 'PressProof', $qty_index );
} # end sub insert_press_proof

sub insert_colour_proof {
	my ( $Project, $sig_specs, $proof_index, $qty_index, $specs, $Imposition ) = @_;

	$$sig_specs{SideOneColours} = [openprint::Estimating::Printing::get_colours( $sig_specs, 'SideOne' )] if ! $$sig_specs{SideOneColours};
	$$sig_specs{SideTwoColours} = [openprint::Estimating::Printing::get_colours( $sig_specs, 'SideTwo' )] if ! $$sig_specs{SideTwoColours};

	#$log->debug("*** Inserting Colour Proof *******");
	my $Equipment = $Imposition->Press();
	if ( ! $Equipment ) {
		$openprint::log->error('No equipment in insert_layout_proof');
		$Equipment = openprint::Equipment->find_one( strid=>$$sig_specs{'ddmPress'.$qty_index} ) if $$sig_specs{'ddmPress'.$qty_index};
		if ( ! $Equipment ) {
			$openprint::log->error('No equipment in insert_layout_proof');
		} # end if
	} # end if

	my $quantity = 0;
	my ( $default_proof_type ) = $Equipment->specification( 'Default Colour Proof' ) if $Equipment;
	if ( $default_proof_type ) {
		if ($$specs{RequireColourProofs} and ($$specs{RequireColourProofs} eq 'Y')) {
			$quantity += 1 if @{$$sig_specs{SideOneColours}};
			$quantity += 1 if @{$$sig_specs{SideTwoColours}};
    } elsif (!$$specs{RequireColourProofs} or $$specs{RequireColourProofs} ne 'N') {
			$quantity += 1 if $$sig_specs{chkProcessColourSideOne};
			$quantity += 1 if $$sig_specs{chkProcessColourSideTwo};
		} # end if

		# we need extra proofs for business cards.
		if ( $$sig_specs{txtNameQuantity} and ( $$sig_specs{txtNameQuantity} > 1) ) {
			$quantity *= $$sig_specs{txtNameQuantity};
		} # end if
    if ($Project->Type()->type() eq 'MultiPage') {
      if ( $$sig_specs{'PageQuantity'.$qty_index} and ( $$sig_specs{'PageQuantity'.$qty_index} > 1) ) {
        $quantity *= $$sig_specs{'PageQuantity'.$qty_index} / $$sig_specs{txtSpreadSize} if $$sig_specs{txtSpreadSize};
      } # end if
		} # end if

		if ( $$specs{RequireColourProofs} and($$specs{RequireColourProofs} eq 'N')) {
			$quantity = 0;
		} # end if
	} # end if

# only if project requires 4 colour process.
	insert_new_proof( $specs, $proof_index, $$sig_specs{SignatureIndex}, $quantity, @$sig_specs{'txtWidth', 'txtHeight'}, $default_proof_type, $qty_index );
} # end sub insert_colour_proof

sub insert_layout_proof {
	my ( $sig_specs, $proof_index, $qty_index, $specs, $Imposition ) = @_;

	#my ( $caller, undef, $line ) = caller;
#$openprint::log->debug("Called insert_layout_proof from $caller : $line");
#$Imposition->display('insert_layout_proof');
	my $Equipment = $Imposition->Press();
	if ( ! $Equipment ) {
		$openprint::log->error("No equipment in insert_layout_proof");
		$Equipment = openprint::Equipment->find_one( strid=>$$sig_specs{'ddmPress'.$qty_index} ) if $$sig_specs{'ddmPress'.$qty_index};
		if ( ! $Equipment ) {
			$openprint::log->error("No equipment in insert_layout_proof");
		} # end if
	} # end if

	my $quantity = 0;
	my ( $default_proof_type ) = $Equipment->specification('Default Layout Proof') if $Equipment;
	if ( ! $default_proof_type ) {
		$openprint::log->debug('No Default Layout Proof for ' . $Equipment->strid() ) if DEBUG and $Equipment;
	} else {
		$$sig_specs{SideOneColours} = [openprint::Estimating::Printing::get_colours($sig_specs, 'SideOne')] if ! $$sig_specs{SideOneColours};
		$$sig_specs{SideTwoColours} = [openprint::Estimating::Printing::get_colours($sig_specs, 'SideTwo')] if ! $$sig_specs{SideTwoColours};

		if ( sets::isin( $$Imposition{runstyle}, ['Web','Sheet Work', 'Perfecting'] ) ) {
			$quantity += 1 if @{$$sig_specs{SideOneColours}};
			$quantity += 1 if @{$$sig_specs{SideTwoColours}};
		} else {
			$quantity += 1 if @{$$sig_specs{SideOneColours}} or @{$$sig_specs{SideTwoColours}};
		} # end if
	} # end if

	insert_new_proof( $specs, $proof_index, $$sig_specs{SignatureIndex}, $quantity, $Imposition->sheet_width(), $Imposition->sheet_height(), $default_proof_type, $qty_index );

} # end sub insert_layout_proof

sub insert_new_proof {
	my ( $specs, $proof_index, $form, $qty, $width, $height, $type, $qty_index ) = @_;
	$$specs{"txtProofQuantity-$form-$proof_index-$qty_index"} = $qty;
	$$specs{"txtProofWidth-$form-$proof_index-$qty_index"} = defined($width) ? 1*$width : '';
	$$specs{"txtProofHeight-$form-$proof_index-$qty_index"} = defined($height) ? 1*$height : '';
	$$specs{"ddmProofType-$form-$proof_index-$qty_index"} = $type;
	$$specs{"txtProofIndex-$form-$proof_index-$qty_index"} = $proof_index;
} # end sub insert_new_proof

sub load_proof_info {
	my ( $Project, $service_index, $form, $qty_index, $specs ) = @_;

	my @proof_info = ();

	$specs = openprint::service::get_specs_ref( $Project, $service_index ) if ! $specs;

	my @proofs;
	foreach my $key ( keys %$specs ) {
		if ( $key =~ /^txtProofIndex-$form-\d+-$qty_index$/ ) {
			push @proofs, $$specs{$key};
		} # end if
	} # end foreach
	foreach my $proof_index ( sort @proofs ) {
		my ( $quantity, $width, $height, $type ) = @$specs{
			"txtProofQuantity-$form-$proof_index-$qty_index",
				"txtProofWidth-$form-$proof_index-$qty_index",
				"txtProofHeight-$form-$proof_index-$qty_index",
				"ddmProofType-$form-$proof_index-$qty_index"
		};
		push @proof_info, $proof_index, $quantity, 1*$width, 1*$height, $type;
    #, ssi::make_drop_down( [ map { $_->name(), $_->description() } openprint::Service->find('category'=>'Proofs') ], $type );
	} # end foreach
	return @proof_info;
} # end sub load_proof_info

sub get_proof_specs {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

	my $Project = new openprint::Project($project_index);
	my $services = $Project->services();
	my @service_dropdown = map { $_->name(), $_->description() } openprint::Service->find(category=>'Proofs');

	my $specs = openprint::service::get_specs_ref($Project, $service_index);
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		my %proof_indexes;
		foreach my $key ( keys %$specs ) {
#$openprint::log->debug("key $key");
			if ( $key =~ /^txtProofIndex-(\d+)-(\d+)-$qty_index$/ ) {
				$proof_indexes{$1}[$$specs{$key}] = $$specs{$key};
			} # end if
		} # end foreach

		foreach my $signature_service_index ( $Project->signatures() ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
			my $form = $$sig_specs{SignatureIndex};
			if ( ! $$sig_specs{'txtImposition'.$qty_index} ) {
				$log->warn("No imposition in signature $form") if DEBUG;
				next;
			} # end if
			my $Imposition = new openprint::Imposition();
			$Imposition->load($sig_specs, $qty_index, $Project);
			my $Equipment = $Imposition->Press();
			$Imposition->display( "For sig $form") if DEBUG;

			if ( (!$proof_indexes{$form}[1]) and $openprint::config{Add_Default_Layout_Proof} and ($openprint::config{Add_Default_Layout_Proof} eq 'Y') ) {
				$proof_indexes{$form}[1] = 1;
				$openprint::log->debug("ADDING Layout Proof to $form") if DEBUG;
				insert_layout_proof($sig_specs, 1, $qty_index, $specs, $Imposition);
			} # end if
			if ( (!$proof_indexes{$form}[2]) and $openprint::config{Add_Default_Colour_Proof} and ($openprint::config{Add_Default_Colour_Proof} eq 'Y') ) {
				$proof_indexes{$form}[2] = 2;
				$openprint::log->debug("ADDING Colour Proof to $form") if DEBUG;
				insert_colour_proof($Project, $sig_specs, 2, $qty_index, $specs, $Imposition);
			} # end if
			if (
					( !$proof_indexes{$form}[3] )
					and
					( (!$$specs{RequirePressProofs}) or ($$specs{RequirePressProofs} ne 'N') )
				 ) {
				if ( 
						( $openprint::config{Add_Default_Press_Proof} and ($openprint::config{Add_Default_Press_Proof} eq 'Y') )
						or
						( $Equipment and ($_ = $Equipment->specification('Require Press Proof')) and ( $_ eq 'Y') ) 
						or 
						( ($_ = $Project->Company()->add_press_proofs()) and $_->value() and ($_->value() eq 'Y') ) 
					 ) {
					$proof_indexes{$form}[3] = 3;
					$log->debug('Adding Press Proof');
					insert_press_proof($Project, $sig_specs, 3, $qty_index, $specs, $Imposition);
				} elsif ( DEBUG ) {
					$log->debug('Press proof not needed');
				} # end if
			} elsif ( DEBUG ) {
				$log->debug('Already had press proof');
			} # end if

			@{$$variable{'Proofs-'.$form.'-'.$qty_index}} = ();
			next if ! $proof_indexes{$form};
			foreach my $proof_index ( sort map { $_ ? $_ : () } @{$proof_indexes{$form}} ) {
				my ( $quantity, $width, $height, $type ) = @$specs{map{join('-',$_,$form,$proof_index,$qty_index)}
					('txtProofQuantity', 'txtProofWidth', 'txtProofHeight', 'ddmProofType')
				};
#$openprint::log->debug("Have $quantity $width x $height $type for form $form qty $qty_index");
				push @{$$variable{'Proofs-'.$form.'-'.$qty_index}},
						 $proof_index, $quantity, 1*$width, 1*$height, $type,
             #ssi::make_drop_down(\@service_dropdown, $type);
           ;
			} # end foreach proof

		} # end foreach signature
	} # end foreach qty_index

	@{$$variable{SignatureGroups}} = ();
	foreach my $signature_service_index ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref($Project, $signature_service_index);
		push @{$$variable{SignatureGroups}}, @$sig_specs{'SignatureIndex', 'txtServiceDescription'};
	} # end foreach signature

# Now do scanning
	if ( $$services{Scanning} ) {
		foreach my $index ( @{$$services{Scanning}} ) {
			my $scanning_specs = openprint::service::get_specs_ref($Project, $index);
			if ( $$scanning_specs{rdbRandomProof} eq 'Yes' ) {
# add a scanning proof
				push @{$$variable{SignatureGroups}}, $$scanning_specs{SignatureIndex}, 'Scanning Proof';
				@{$$variable{'Proofs'.$$scanning_specs{SignatureIndex}}} = load_proof_info( $Project, $service_index, $$scanning_specs{SignatureIndex} );
			} # end if
		} # end foreach scanning service
	} # end if

} # end sub get_proof_specs

sub save {
	my ( $project_index, $service_index, $new_specs ) = @_;

	$log->debug('In Save Proof Specs');

	my $Project = new openprint::Project($project_index);
	my $Service = $Project->Service($service_index);

	if ( $$new_specs{RequirePressProofs} and ($$new_specs{RequirePressProofs} eq 'N') ) {
		foreach my $sig_id ( $Project->signatures() ) {
			openprint::service::insert_service_spec($openprint::log, $openprint::dbh, $project_index, $sig_id, 'rdbPressProof', '');
		}
	}

	my $redirect = 0;

# Now check to see if we need to add more proofs, and redirect back
	foreach my $key ( keys %{$new_specs} ) {
		if ( $key =~ /rdbAdditional-(\d*)-(\d*)/ ) {
			if ( $$new_specs{$key} eq 'Yes' ) {
				my $form = $1;

				my $ac = sql::start_transaction($openprint::dbh);
				$_ = 'SELECT lngServiceIndex FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND strName=? AND strValue=?';
				my ( $signature_service_index ) = sql::execute(undef, undef, $_, $project_index, 'SignatureIndex', $form);

				foreach my $qty_index ( $Project->quantity_indexes() ) {
					my ( $proof_index ) = sql::execute(undef, undef,
							'SELECT MAX(strValue::integer) FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=? AND strName LIKE ?',
							$project_index, $service_index, "txtProofIndex-$form-%-$qty_index");
					$proof_index += 1;
					$proof_index = 4 if $proof_index < 4;

					openprint::service::insert_service_spec($openprint::log, $openprint::dbh, $project_index, $service_index, "txtProofQuantity-$form-$proof_index-$qty_index", 1 );
					openprint::service::insert_service_spec($openprint::log, $openprint::dbh, $project_index, $service_index, "txtProofWidth-$form-$proof_index-$qty_index", '' );
					openprint::service::insert_service_spec($openprint::log, $openprint::dbh, $project_index, $service_index, "txtProofHeight-$form-$proof_index-$qty_index", '' );
					openprint::service::insert_service_spec($openprint::log, $openprint::dbh, $project_index, $service_index, "ddmProofType-$form-$proof_index-$qty_index", '' );
					openprint::service::insert_service_spec($openprint::log, $openprint::dbh, $project_index, $service_index, "txtProofIndex-$form-$proof_index-$qty_index", $proof_index );
				} # end foreach

				sql::end_transaction($openprint::dbh, $ac);

				$redirect = 1;
			} # end if
		} # end if
	} # end foreach

	if ( $redirect ) {
		$openprint::variable{Redirect} = '/main/project/'.$Service->ServiceType()->url();
	} else {
		if ( $$new_specs{'txtPrice1'} > 0 || $$new_specs{'txtPrice2'} > 0 || $$new_specs{'txtPrice3'} > 0 ) {
			$Service->save({status=>'calculated'});
		} # end if
	} # end if
} # end sub save

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
			my $form = $$sig_specs{SignatureIndex};
			foreach my $key ( keys %{$specs} ) {
				if ( my ($proof_index) = $key =~ /^txtProofIndex\-$form\-(\d+)\-$qty_index$/ ) {
					next if ! $$specs{"ddmProofType-$form-$proof_index-$qty_index"};
          next if ! $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"};

					if ( my $Service = openprint::Service->find_one(name=>$$specs{"ddmProofType-$form-$proof_index-$qty_index"}) ) {
						if ( sets::isin( $$specs{"ddmProofType-$form-$proof_index-$qty_index"}, [ 'PressProof', 'PDFProof' ] ) ) {
              my $desc = sprintf('</td><td class="type">%s', $Service->description() );
              $proof_totals{$desc} += $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"};
						} else {
							my $desc = sprintf('%s&quot;x%s&quot;</td><td class="type">%s', @$specs{
									"txtProofWidth-$form-$proof_index-$qty_index",
									"txtProofHeight-$form-$proof_index-$qty_index"}, $Service->description() );
							$proof_totals{$desc} += $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"};
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
		my $form = $$sig_specs{SignatureIndex};
		foreach my $key ( keys %{$specs} ) {
			if ( my ($proof_index) = $key =~ /^txtProofIndex\-$form\-(\d+)\-$qty_index$/ ) {
				if ( my $Service = openprint::Service->find_one( name=>$$specs{"ddmProofType-$form-$proof_index-$qty_index"}) ) {
					if ( sets::isin( $$specs{"ddmProofType-$form-$proof_index-$qty_index"}, [ 'PressProof', 'PDFProof' ] ) ) {
						my $desc = sprintf('</td><td class="type">%s', $Service->description() );
						$proof_totals{$desc} += $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"};
					} else {
						my $desc = sprintf('%s&quot;x%s&quot;</td><td class="type">%s', @$specs{
								"txtProofWidth-$form-$proof_index-$qty_index",
								"txtProofHeight-$form-$proof_index-$qty_index"}, $Service->description() );
						$proof_totals{$desc} += $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"} if $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"};
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
			my $form = $$sig_specs{SignatureIndex};
			foreach my $key ( keys %{$specs} ) {
				if ( my ($proof_index) = $key =~ /^txtProofIndex-$form-(\d*)-$qty_index$/ ) {
					my $Service = openprint::Service->find_one('name'=>$$specs{"ddmProofType-$form-$proof_index-$qty_index"});
					if ( $Service ) {	
						my $desc = sprintf('<td align="left">%s&quot;x%s&quot;</td><td align="left">%s', @$specs{
								"txtProofWidth-$form-$proof_index-$qty_index",
								"txtProofHeight-$form-$proof_index-$qty_index"}, $Service->description() );
						my $qty = $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"} // 0;
						if ( $qty != 0 ) {
							$proof_totals{$desc} += $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"};
							my $Uprice   = $$specs{"txtProofUnitPrice-$form-$proof_index-$qty_index"};
							my $type = @$specs{"ddmProofType-$form-$proof_index-$qty_index"};
							if ( ! $proof_tot{$type} ) {
								$proof_tot{$type} = { Quantity => 0, Price => 0 };
							} # end if
							$proof_tot{$type}{Quantity} += $qty;
							my %MkReady  = openprint::service::get_price_object( $type.'MakeReady', $proof_tot{$type}{Quantity}, undef );
							$Totprice{$desc} += ($Uprice*$qty) + ($MkReady{Price}//0);
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
		my $form = $$sig_specs{SignatureIndex};
		foreach my $key ( keys %{$specs} ) {
			if ( my ($proof_index, $qty_index) = $key =~ /^txtProofIndex-$form-(\d*)-(\d*)$/ ) {
				next if ! $$specs{"ddmProofType-$form-$proof_index-$qty_index"};
				next if ! $$specs{"txtProofQuantity-$form-$proof_index-$qty_index"};
				if ( my $Service = openprint::Service->find_one('name'=>$$specs{"ddmProofType-$form-$proof_index-$qty_index"}) ) {
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

	# None of our overrides are quantity independent
	return if ! $qty_index;

	$specs = openprint::service::get_specs_ref($Project, $service_id) if ! $specs;

	my @v;

	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		my $form = $$sig_specs{SignatureIndex};
		foreach my $key ( keys %{$specs} ) {
			if ( $key =~ /^txtProofIndex-$form-(\d+)-$qty_index$/ ) {
				my ( $proof_index ) = ( $1 );
				if ( $$specs{"chkOverride-$form-$proof_index-$qty_index"} ) {
					push @v, "chkOverride-$form-$proof_index-$qty_index";
				} # end if
			} # end if
		} # end foreach key
	} # end foreach signature
    return @v;
} # end sub has_overrides

sub status {
	my ( $Project, $service_id, $specs ) = @_;
	$specs = openprint::service::get_specs_ref($Project, $service_id) if !$specs;

	my $status;
	if ( $$specs{rdbApproved} and ($$specs{rdbApproved} eq 'Yes') ) {
		$status = 'Approved';
	} elsif ( $$specs{rdbClientApproved} and ($$specs{rdbClientApproved} eq 'Y') ) {
		$status = 'Waiting For QA Approval';
	} elsif ( $$specs{rdbComplete} and ($$specs{rdbComplete} eq 'Yes') ) {
		$status = 'Proofs out';
	} else {
		$status = 'Ordered'
	}	
	return $status;
} # end sub status

1;
__END__
