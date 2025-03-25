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

package openprint::Estimating::PerfectBound;
use strict;
use warnings;

use constant DEBUG => 0;

require openprint::Equipment;
require openprint::service;
require openprint::Project;

my @Equipment;

my %variables = (
		ProjectIndex=>[],ServiceIndex=>[],
		hdnBreakdown1=>['output'],hdnBreakdown2=>['output'],hdnBreakdown3=>['output'],
		txtQuantity1=>['save'], txtQuantity2=>['save'], txtQuantity3=>['save'],
		ServiceType=>[],
		alert=>['save','output'],
		txtInsertQuantity=>['save','output'],chkOverrideInsertQuantity=>['save'],
		txtCalliper=>['save','output'], OverrideCalliper=>['save'],
		Imposition1=>['save','output'], Imposition2=>['save','output'], Imposition3=>['save','output'],
		ddmEquipment1=>['save','output'], ddmEquipment2=>['save','output'], ddmEquipment3=>['save','output'],
		OverridePockets1=>['save'], OverridePockets2=>['save'], OverridePockets3=>['save'],
		chkOverrideEquipment1=>['save'], chkOverrideEquipment2=>['save'], chkOverrideEquipment3=>['save'],
		rdbGateFoldFit=>['save'],
		txtUnitPrice1=>['output'], txtUnitPrice2=>['output'], txtUnitPrice3=>['output'],
		txtPrice1=>['save','output'], txtPrice2=>['save','output'], txtPrice3=>['save','output'],
		MPrice1=>['save','output'], MPrice2=>['save','output'], MPrice3=>['save','output'],
		txtRunTime1=>['save'], txtRunTime2=>['save'], txtRunTime3=>['save'],
		glue_id => ['save'], override_glue_id => ['save'],
		Markup1=>['save'], Markup2=>['save'], Markup3=>['save'],
		OverridePrice1=>['save'], OverridePrice2=>['save'], OverridePrice3=>['save'],
		);

my @possible_pages = ( 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40 );

sub variables {
  my ( $p_id, $s_id, $old_specs, $specs ) = @_;
  my $Project = new openprint::Project( $p_id );
	my @v;
	foreach my $k ( keys %variables ) {
		push @v, $k, if sets::isin( 'save', $variables{$k} );
	} # end foreach;
	if ( $$specs{txtInsertQuantity} ) {
		foreach my $insert_id ( 1 .. int $$specs{txtInsertQuantity} ) {
			push @v, 'txtInsertPage1-'.$insert_id, 'txtInsertPage2-'.$insert_id;
		} # end foreach
	} # end if
	foreach my $qty_index ( $Project->quantity_indexes()  ) {
		foreach my $k ( @possible_pages ) {
			push @v, 'txtSignatureQty'.$k.'Page-'.$qty_index;
		} # end foreach
	} # end foreach

	return @v;
} # end sub variables

sub neccessary {
  my ( $Project ) = @_;

  my $services = $Project->services();

  if ( $$services{NoBindery} ) {
		return 0;
	} # end if

  my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] ) if $$services{''} and $$services{''}[0];

	if ( $$printing_specs{rdbTemplateType} and ( $$printing_specs{rdbTemplateType} eq 'PerfectBound' ) ) {
		return 1;
  } # end if

  return 0;  
} # end sub neccessary

sub signature_calc {
  my ( $Project, $service_index, $specs, $qty_index, $Impositions, $calc_hash ) = @_;

	my %results = (
			alert 	 	=>  '',
			Breakdown	=>	'',
			Status 		=>  'uncalculated',
			);

  my $services = $Project->services();
  my $printing_specs = $$calc_hash{ProjectSpecs};
  my $folding_specs = $$calc_hash{FoldingSpecs};

 #Need to figure out which dimension the spine bisects
	if ( $$printing_specs{spine} ) {
		if ( $$printing_specs{spine} eq 'width' ) {
			@$specs{'Width','Height'} = @$printing_specs{'txtFinalHeight','txtFinalWidth'};
		} else {
			@$specs{'Width','Height'} = @$printing_specs{'txtFinalWidth','txtFinalHeight'};
		} # end if
	} elsif ( ( $$printing_specs{txtFinalWidth} == $$printing_specs{txtWidth} ) and ( $$printing_specs{txtFinalHeight} != $$printing_specs{txtHeight} ) ) {
		@$specs{'Width','Height'} = @$printing_specs{'txtFinalHeight','txtFinalWidth'};
	} elsif ( ( $$printing_specs{txtFinalWidth} != $$printing_specs{txtWidth} ) and ( $$printing_specs{txtFinalHeight} == $$printing_specs{txtHeight} ) ) {
		@$specs{'Width','Height'} = @$printing_specs{'txtFinalWidth','txtFinalHeight'};
	} else {
		@$specs{'Width','Height'} = @$printing_specs{'txtFinalWidth','txtFinalHeight'};
		$$specs{alert} .= 'Unable to determine spine direction. Calculations may be invalid.';
	} # end if
# FIXME should not include cover
	$$specs{txtCalliper} = $Project->calliper() if ! $$specs{txtCalliper};

#my %printed_impositions;
	my $imposition = 2;
	my $pockets = $$specs{"txtPockets$qty_index"} = 0;

	if ( $$specs{override_glue_id} and ( $$specs{override_glue_id} eq 'Y' ) ) {
	} else {
		my @Materials = openprint::Material->find( category=>'PerfectBound Glue');
		if ( @Materials ) {
# Auto guess glue type
      MATERIAL: foreach my $Material ( @Materials ) {
        my $stock_grand_recommendation = $Material->specification('Recommended For Stock Grade');
        if ($stock_grand_recommendation) {
          my %stock_grades = map { $_ => $_ } split(',', $stock_grand_recommendation);
          foreach my $I ( @$Impositions ) {
            my $sig_specs = $$I{specs};
            next if $$sig_specs{txtSignatureType} eq 'Cover Pages';

            my $Paper = openprint::Paper::load_from_signature( $Project, $sig_specs, $qty_index );
            if ($stock_grades{$$Paper{grade}}) {
              $$specs{glue_id} = $$Material{id};
              last MATERIAL;
            } # end if
					} # end if
				} # end foreach Material
			} # end foreach sig
		} # end if   Materials
	} # end if override

	if ( (!defined $$specs{'OverridePockets'.$qty_index}) or ($$specs{'OverridePockets'.$qty_index} ne 'Y') ) {
		foreach my $pages ( @possible_pages ) {
			$$specs{'txtSignatureQty'.$pages.'Page-'.$qty_index} = 0;
		} # end foreach
	} # end if

	foreach my $I ( @$Impositions ) {
		$I->display('In PerfectBi:') if DEBUG;
		my $sig_specs = $$I{specs};
    next if $$sig_specs{txtSignatureType} eq 'Cover Pages';
		my $form = $$sig_specs{SignatureIndex};
#$printed_impositions{$$I{imposition}} = !undef;
		if ( ! $$I{Folds} ) {
			$openprint::log->error('No folds in imposition, generating');
			$I->display('No Folds') if DEBUG;
			$$I{Folds} = [ openprint::Estimating::Folding::get_Folds( $folding_specs, $I, $qty_index, $Project ) ] if $folding_specs;
		} # end if

		if ( ! ( $$I{Folds} and @{$$I{Folds}} ) ) {
			$openprint::log->error('No folds in imposition, guess 1') if DEBUG;
			$$specs{'txtSignatureQty'.$I->pages().'Page-'.$qty_index} += 1;
			$pockets += 1;
# This doesn't really make sense.  If we are doing printing estimation, then the folding probably isn't going to match.  
		} else {
			foreach my $FI ( @{$$I{Folds}} ) {
				my $Fold = $$FI{Fold};
				$openprint::log->debug("Fold pq($$FI{page_quantity}) pages($$FI{pages}) ($$Fold{name}) Pockets: $pockets " . $Fold->to_string()) if DEBUG;
				if ( $$FI{imposition} < $imposition ) {
					$results{Breakdown} .= "Setting perfectbound imposition to $$FI{imposition} out because Folding imposition is $$FI{imposition}out<br/>";
					$imposition = $$FI{imposition};
				}
#if ( ! $$I{Folder} ) {
#$I->display("Has no folder");
#$$I{Folder} = $$FI{Folder};
#}
				if ( $$specs{'txtSignatureQty'.$FI->pages().'Page-'.$qty_index} ) {
					$$specs{'txtSignatureQty'.$FI->pages().'Page-'.$qty_index} += $$FI{page_quantity};
				} else {
					$$specs{'txtSignatureQty'.$FI->pages().'Page-'.$qty_index} = $$FI{page_quantity};
				}
				$pockets += $$FI{page_quantity};
			} # end foreach Fold
		}
		if ( $imposition > 1 ) {
			if ($$I{imposition} % 2 ) {
				$I->display("Setting imposition to 1 due to odd impositions") if DEBUG;
				$results{Breakdown} .= "Setting imposition to 1 due to odd impositions<br/>";
				$imposition = 1;
			} elsif ($$I{image_orientation} == openprint::Imposition::Vertical and $$I{rows} % 2 ) {
				$I->display("Setting imposition to 1 due to Vertial and odd rows") if DEBUG;
				$results{Breakdown} .= "Setting imposition to 1 due to vertical and odd rows<br/>";
				$imposition = 1;
			} elsif ( ($$I{image_orientation} == openprint::Imposition::Horizontal ) and ( $$I{columns} % 2 ) ) {
				$I->display("Setting imposition to 1 due to Horizal and odd cols") if DEBUG or 1;
				$results{Breakdown} .= "Setting imposition to 1 due to Horizontal and odd cols<br/>";
				$imposition = 1;
			} elsif ( ( $$I{runstyle} eq 'Work & Turn' or $$I{runstyle} eq 'Work & Tumble' ) and ($$I{imposition}%4) ) {
				$I->display("Setting imposition to 1 due to W&T impo not % 4 ") if DEBUG;
				$imposition = 1;
			} # end if
		} # end if
	} # end foreach Imposition
	$results{Breakdown} .= qq`# of Pockets needed: $pockets<br/>`;

	if ( $$specs{'OverrideImposition'.$qty_index} ) {
		if ( $imposition < $$specs{'Imposition'.$qty_index} ) {
			$results{alert} .= "Can't stitch $$specs{'Imposition'.$qty_index} out";
			foreach my $I ( @$Impositions ) {
				if ( ($$I{FoldingImposition} and $$I{FoldingImposition} % 2 ) ) {
					$results{alert} .= ' Folding not multiple of 2out<br/>';
				} # end if
				if ( $$I{imposition} % 2 ) {
					$results{alert} .= ' imposition not multiple of 2out<br/>';
				} # end if
				if ( ($$I{image_orientation} == openprint::Imposition::Vertical and $$I{rows} % 2 ) ) {
					$results{alert} .= ' vertical and rows not multiple of 2out<br/>';
				} # end if
				if ( $$I{image_orientation} == openprint::Imposition::Horizontal and $$I{columns} % 2 ) {
					$results{alert} .= ' horizontal and cols not multiple of 2out<br/>';
				} # end if
			} # end foreach
			$results{Status} = 'uncalculated';
			return \%results;
		} else {
			$imposition = $$specs{'Imposition'.$qty_index};
		} # end if
	} # end if

	my %error;
	my @equipment = ();

	if ( ( defined $$specs{"chkOverrideEquipment$qty_index"} ) and ( $$specs{"chkOverrideEquipment$qty_index"} eq 'Y' ) ) {
		if ( ! $$specs{"ddmEquipment$qty_index"} ) {
			$results{alert} .= 'Please select a piece of equipment to bind your job.<br/>';
		} else {
			@equipment = ( new openprint::Equipment( $$specs{"ddmEquipment$qty_index"} ) );
			if ( ! $equipment[0]->id() ) {
				$results{alert} .= 'Your selected equipment was not found. Please select another.<br/>';
			} # end if
		} # end if
	} else {
		if ( $$calc_hash{'PerfectBound::signature_calc::equipment'} ) {
#$results{Breakdown} .= 'Using cached equipment';
			@equipment = @{$$calc_hash{'PerfectBound::signature_calc::equipment'}};
		} else {
#$results{Breakdown} .= 'getting freshequipment';
			@{$$calc_hash{'PerfectBound::signature_calc::equipment'}} = @equipment = get_equipment( $specs, \%error, $Impositions );
		} # end if
	} # end if

	my $bestPrice;
	my $bestEquipment;
	my $I = $$Impositions[0];
	my $sig_specs = $$I{specs};
	my $Press = $I->Press();
	my $form = $$sig_specs{SignatureIndex};
	$$specs{"txtPockets$qty_index"} = $pockets;

	while ( ! $bestPrice and $imposition ) {
		$$specs{'Imposition'.$qty_index} = $imposition;

		foreach my $Equipment ( @equipment ) {
			$results{Breakdown} .= 'On ' . $$Equipment{name}.'<br/>';
			if ( ( $_ = $Equipment->specification('PerfectBind Maximum Quantity') ) and ( $_ < $$specs{"txtQuantity$qty_index"} ) ) {
				$results{Breakdown} .= $$Equipment{name} . ' has a maximum quantity of ' . $_ . '.<br/>';
        $$specs{alert} .= $$Equipment{name} . ' has a maximum quantity of ' . $_ . '.<br/>' if @equipment == 1;
				next;
			} # end if
			if ( $$services{NoOfflineBindery} ) {
				if ( $$Press{id} != $$Equipment{id} ) {
					$results{Breakdown} .= "No Offline bindery and not printing on $$Equipment{name}.<br/>";
          $$specs{alert} .= "No Offline bindery and not printing on $$Equipment{name}.<br/>" if @equipment == 1;
					next;
				} # end if
			} # end if

			my $max_spine_length = $Equipment->specification('Maximum Spine Length', $imposition );
			if ( $max_spine_length and ( $$specs{Height} > $max_spine_length ) ) {
				$results{Breakdown} .= sprintf('Spine Too big. Spine: %s, Maximum: %s<br/>', $$specs{Height}, $max_spine_length );
        if (@equipment == 1) {
          $$specs{alert} .= sprintf('Spine Too big. Spine: %s, Maximum: %s<br/>', $$specs{Height}, $max_spine_length );
        }
				next;
			} # end if
			my $min_spine_length = $Equipment->specification('Minimum Spine Length', $imposition );
			if ( $min_spine_length and ( $$specs{Height} < $min_spine_length ) ) {
				$results{Breakdown} .= sprintf('Spine Too small. Spine: %s, Minimum: %s<br/>', $$specs{Height}, $min_spine_length );
        if (@equipment == 1) {
          $results{alert} .= sprintf('Spine Too small. Spine: %s, Minimum: %s<br/>', $$specs{Height}, $min_spine_length );
        }
				next;
			} # end if
			my $sizes = $Equipment->specification('PerfectBindFinalSizes');
			if ( $sizes ) {
				my @sizes = map { [ split('x',$_) ] } split(',',$sizes);
				my $found = 0;
				foreach my $size ( @sizes ) {
					my ( $width, $height ) = @{$size};
					if ( 
							( $width == $$specs{Width} and $height == $$specs{Height} ) 	
						 ) {
					$found = 1;
					last;
					} # end if
				} # end foreach
				if ( ! $found ) {
					$results{Breakdown} .= "Book size not in allowed sizes: $sizes<br/>";
					next;
				}
			} # end if sizes	

			if ( $Equipment->specification('Type') eq 'Press' ) {
				if ( $$Press{id} != $$Equipment{id} ) {
					$results{Breakdown} .= 'Press not the same: ' . $$Press{name} . ' != ' . $$Equipment{name} . '<br/>';
					next;
				} # end if
				if ( $$folding_specs{"ddmEquipment-$form-$qty_index"} and ( $$folding_specs{"ddmEquipment-$form-$qty_index"} != $$Equipment{id} ) ) {
					$results{Breakdown} .= 'Folder not the same: ' . new openprint::Equipment( $$folding_specs{"ddmEquipment-$form-$qty_index"} )->name(). ' != ' . $$Equipment{name} . '<br/>';
					next;
				} # end if
			} # end if

			my $price = get_price( $Equipment, $specs, $qty_index );
			if ( $folding_specs and ( defined $$folding_specs{"Price-$form-$qty_index"} ) ) {
				$$price{ComparisonPrice} = $$price{Price} + $$folding_specs{"Price-$form-$qty_index"};
			} else {
				$$price{ComparisonPrice} = $$price{Price};
			} # end if
			if ( ( ! $bestPrice ) or $$price{ComparisonPrice} < $$bestPrice{ComparisonPrice} ) {
				$bestEquipment = $Equipment;
				$bestPrice = $price;
			} # end if
		} # end foreach Equipment
		if ( $imposition > 1 and ! $bestPrice ) {
			if ( ( defined $$specs{'OverrideImposition'.$qty_index} ) and ( $$specs{'OverrideImposition'.$qty_index} eq 'Y' ) ) {
				last;
			} # end if
			$imposition -= 1;
		} else {
# Assume 2out is better than 1out
			last;
		} # endif
	} # while ! bestPrice and imposition

	if ( $bestPrice ) {
    $results{pockets} = $pockets;
		$results{Imposition} = $$bestPrice{Imposition};
		$results{Equipment} = $bestEquipment;
		$results{Status} = 'calculated';
		$results{Price} = $bestPrice;
		$results{total} = $$bestPrice{Price};
	} else {
		$results{Status} = 'uncalculated';
	} # end if
	return \%results;
} # end sub signature_calc

sub get_equipment {
	my ( $specs, $error, $Impositions ) = @_;

	my @possible_equipment;
	my @all_equipment = openprint::Equipment->find( Specifications => {'PerfectBound Capable'=>['Y','When Printing']}, useinestimating=>1,order=>'strName');

	foreach my $Equipment ( @all_equipment ) {
		if ( $_ = $Equipment->specification('Maximum Spread Width') and ( $$specs{Width} > $_ ) ) {
			$$error{$$Equipment{id}} .= ': Too big.<br/>';
			next;
		} # end if
		if ( $_ = $Equipment->specification('Minimum Spread Width') and ( $$specs{Width} < $_ ) ) {
			$$error{$$Equipment{id}} .= ': Too small.<br/>';
			next;
		} # end if
		if ( $$specs{txtCalliper} > 0 ) {
			if ( $_ = $Equipment->specification('MaximumPerfectBound Calliper') and ( $$specs{txtCalliper} > $_ ) ) {
				$$error{$$Equipment{id}} .= ": Too thick. $$specs{txtCalliper} > $_ <br/>";
				next;
			} # end if
			if ( $_ = $Equipment->specification('MinimumPerfectBound Calliper') and ( $$specs{txtCalliper} < $_ ) ) {
				$$error{$$Equipment{id}} .= ": Too thin $$specs{txtCalliper} < $_ .<br/>";
				next;
			} # end if
		} else {
			$openprint::log->warn("No calliper in Perfecting::get_equipment");
		} # end if
		if ( $Equipment->specification('PerfectBound Capable') eq 'When Printing' ) {
			my $flag = 0;
			foreach my $I ( @{$Impositions} ) {
				if ( $I->Press()->id() ne $Equipment->id() ) {
					$flag = 1;
					$$error{$$Equipment{id}} .= ': Project must also be printed on it.<br/>';
					last;
				} # end if
			} # end foreach
			next if $flag;
		} # end if
		push @possible_equipment, $Equipment;
	} # end foreach equipment
	return @possible_equipment;
} # end sub get_equipment

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $Project = new openprint::Project( $project_index );

	$$specs{alert} = '';
	my $services = $Project->services();
	if ( ! $$services{Folding} ) {
		$$specs{alert} .= 'Project must be folded.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if
	my $calc_hash = {};
	if ( $$services{Folding} ) {
		$$calc_hash{FoldingSpecs} = openprint::service::get_specs_ref( $Project, $$services{Folding}[0] );
	} # end if

	my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
	$$calc_hash{ProjectSpecs} = $printing_specs;
	my @signatures = $Project->signatures();

	if ( (!$$specs{OverrideCalliper}) or ($$specs{OverrideCalliper} ne 'Y') ) {
		foreach my $qty_index ( $Project->quantity_indexes() ) {
			$$specs{txtCalliper} = 0;
			foreach my $signature_service_index ( @signatures ) {
				my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
# All but the cover
				next if $$sig_specs{Group} == 1;
				next if ! $$sig_specs{"txtImposition$qty_index"};
				my $calliper = $$sig_specs{'PageQuantity'.$qty_index} ? ($$sig_specs{'PageQuantity'.$qty_index}/2) * $$sig_specs{txtSpecificStockCalliper} : $$sig_specs{txtSpecificStockCalliper};
				$$specs{txtCalliper} += $calliper;
			} # end foreach
			last if $$specs{txtCalliper};
		} # end foreach
		$$specs{txtCalliper} = Math::Round::nearest( 0.0001, $$specs{txtCalliper} );
	} # end if

# Need to figure out which dimension the spine bisects
	@$specs{'Width','Height'} = @$printing_specs{'txtFinalWidth','txtFinalHeight'};
	if ( $$printing_specs{txtFinalWidth} == $$printing_specs{txtWidth} ) {
		@$specs{'Width','Height'} = @$printing_specs{'txtFinalHeight','txtFinalWidth'};
	} # end if

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
		next if ! $$specs{'txtQuantity'.$qty_index};
		$$specs{'txtPrice'.$qty_index} =~ s/[^\d\.]//g if $$specs{'txtPrice'.$qty_index};
		$$specs{"Markup$qty_index"} =~ s/[^\d\.\-]//g if $$specs{"Markup$qty_index"};
		$$specs{'txtUnitPrice'.$qty_index} = sprintf( $openprint::config{UnitPriceFormat}, 0 );
		$$specs{'hdnBreakdown'.$qty_index} .= 'Interior Calliper: ' . $$specs{txtCalliper} . '<br/>';
		$$specs{'hdnBreakdown'.$qty_index} .= "Face Trim: $$specs{Width} Spine Length: $$specs{Height}<br/>";

		if ( (!defined $$specs{'OverridePockets'.$qty_index}) or ($$specs{'OverridePockets'.$qty_index} ne 'Y') ) {
			foreach my $pages ( 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48 ) {
				$$specs{'txtSignatureQty'.$pages.'Page-'.$qty_index} = '';
			} # end foreach

			$$specs{"txtPockets$qty_index"} = 0;

			foreach my $signature_service_index ( @signatures ) {
				my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
				next if $$sig_specs{txtSignatureType} eq 'Cover Pages';
				next if ! $$sig_specs{"txtImposition$qty_index"};

				if ( ! $$sig_specs{'txtImposition'.$qty_index} ) {
					$$specs{'hdnBreakdown'.$qty_index} .= "Signature $$sig_specs{SignatureIndex} has no imposition.<br/>";
					next;
				} # end if
				if ( ! $$sig_specs{txtSpreadSize} ) {
					$$specs{'hdnBreakdown'.$qty_index} .= "Signature $$sig_specs{SignatureIndex} has no spread size.<br/>";
					next;
				} # end if
				if ( ! $$sig_specs{'PageQuantity'.$qty_index} ) {
					$$specs{'hdnBreakdown'.$qty_index} .= "Signature $$sig_specs{SignatureIndex} has no pages.<br/>";
					next;
				} # end if
			} # end foreach signature
		} # end if

		my $bestPrice;
		my @Impositions;
		foreach my $signature_service_index ( @signatures ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
			next if ! $$sig_specs{"txtImposition$qty_index"};
			my $Imposition = new openprint::Imposition();
			$Imposition->load( $sig_specs, $qty_index, $Project );
			$$Imposition{Folds} = [ openprint::Estimating::Folding::get_Folds( $$calc_hash{FoldingSpecs}, $Imposition, $qty_index ) ];
			push @Impositions, $Imposition;
		} # end foreach signature_service_index

		my %error;
		my @Equipment = get_equipment( $specs, \%error, \@Impositions );
		if ( 0 ) {
			if ( ! @Equipment ) {
				$$specs{alert} .= 'We are unable to automatically provide a price for Perfect Binding.  You may enter your own price in the price fields, or contact your CSR for a quote.';
				foreach my $qty_index ( $Project->quantity_indexes() ) {
					my $qty = $$specs{'txtQuantity'.$qty_index};
#$openprint::log->debug("QTY: $qty " . $$specs{'txtPrice'.$qty_index});
					if ( $qty and ! (1*$$specs{'txtPrice'.$qty_index}) ) {
#$openprint::log->debug("uncalc");
						return $$specs{Status} = 'uncalculated';
					} # end if
				} # end foreach
#$openprint::log->debug("calc");
				return $$specs{Status} = 'calculated';
			} # end if ! @Equipment
		} # end if ! @Equipment

		$$calc_hash{'PerfectBound::signature_calc::equipment'} = \@Equipment;
		my %results = %{signature_calc( $Project, $service_index, $specs, $qty_index, \@Impositions, $calc_hash )};
		$$specs{Status} = $results{Status};
		$$specs{'hdnBreakdown'.$qty_index} .= $results{Breakdown};
		$$specs{alert} .= $results{alert} if $results{alert};
		my %price = %{$results{Price}} if $results{Price};

		if ( $results{Status} eq 'calculated' ) {
			$$specs{"ddmEquipment$qty_index"} = $results{Equipment}{id};
			$$specs{'Imposition'.$qty_index} = $results{Imposition};
			$$specs{'hdnBreakdown'.$qty_index} .= 'Number of Passes: '.scalar @{$price{Passes}}.'<br/>';
			$$specs{'hdnBreakdown'.$qty_index} .= "Imposition: $price{Imposition}out<br/>";
			$$specs{'hdnBreakdown'.$qty_index} .= 'Run Discount' . $price{'RunCost Discount'}.'%<br/>' if $price{'RunCost Discount'};
			$$specs{'hdnBreakdown'.$qty_index} .= 'Imposition Discount: '. $price{'Imposition Discount'} .'%<br/>' if $price{'Imposition Discount'};
			$$specs{'hdnBreakdown'.$qty_index} .= 'Spine Length Discount: ' . $price{'SpineLength Discount'} . '%<br/>' if $price{'SpineLength Discount'};
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Calliper Markup %d%<br/>', $price{'Calliper Markup'} ) if $price{'Calliper Markup'};
      my $pass = 1;
      foreach my $pass_price (@{$price{Passes}}) {
        $$specs{'hdnBreakdown'.$qty_index} .= 'Pass '.$pass.' ' .$$pass_price{Pockets}.' pockets<br/>' if @{$price{Passes}}>1;
        #$$specs{'hdnBreakdown'.$qty_index} .= 'Quantity ' . $$specs{'txtQuantity'.$qty_index}.'+'.$$pass_price{overs}.' overs = '.($$specs{'txtQuantity'.$qty_index}+$$pass_price{overs}).'<br/>' if $$pass_price{overs};
        #$$specs{'hdnBreakdown'.$qty_index} .= 'Estimated Run Time: @'.$price{RunSpeed}.'/Hr = '. Math::Round::nearest( 0.1, $price{RunTime} ) . ',<br/>' if $price{RunSpeed};
        my $MakeReadyPrice = $$pass_price{MakeReadyPrice};
			  $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Make Ready: $%.2f%s = $%.2f', @$MakeReadyPrice{qw(Price units Total)}).'<br/>' if $MakeReadyPrice;
        my $PocketMakeReadyPrice = $$pass_price{PocketMakeReadyPrice};
			  $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Pocket Make Ready: $%.2f%s * %dpockets = $%.2f', @$PocketMakeReadyPrice{qw(Price units Pockets Total)}).'<br/>' if $PocketMakeReadyPrice;

        if ( my $servicePrice = $$pass_price{ServicePrice} ) {
          if ($$servicePrice{units} eq 'per 1000' or $$servicePrice{units} eq 'per m') {
            $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service: %s $%.2f%s * %d = $%.2f<br/>', $$servicePrice{Service}->name(), @$servicePrice{'Price','units','quantity','Total'});
          } else {
            $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service: %s $%.2f%s %d@%d per hour = %.2fhours = $%.2f<br/>',
              $$servicePrice{Service}->name(), @$servicePrice{'Price','units','quantity','RunSpeed','RunTime','Total'});
          }
        } # end if
        $pass ++;
			}
      if ($price{GluePrice}) {
        my $gluePrice = $price{GluePrice};
        $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Glue: %s $%.2f%s=$%.2f<br/>', $$gluePrice{Material}->name(), @$gluePrice{'Price','units','Total'});
      }
			$$specs{'hdnBreakdown'.$qty_index} .= 'Total: $'. sprintf('%.2f', Math::Round::nearest(0.01,$price{Price})).'<br/><br/>';
			$$specs{'hdnBreakdown'.$qty_index} .= 'Comparison: $'. sprintf('%.2f', Math::Round::nearest(0.01,$price{ComparisonPrice})).'<br/><br/>';
		} else {
			foreach my $press_id ( keys %error ) {
				my $Equipment = new openprint::Equipment( $press_id );
				$$specs{'hdnBreakdown'.$qty_index} .= 'For ' . $Equipment->name() . ': ' .  $error{$press_id};
			} # end foreach
			$$specs{"ddmEquipment$qty_index"} = '' if ( ! $$specs{'chkOverrideEquipment'.$qty_index} ) or ( $$specs{'chkOverrideEquipment'.$qty_index} ne 'Y' );
			$$specs{'Imposition'.$qty_index} = '' if ( ! $$specs{'OverrideImposition'.$qty_index} ) or ( $$specs{'OverrideImposition'.$qty_index} ne 'Y' );
		} # end if

		if ( ! defined $price{Price} ) {
			$price{Price} = 0;
			$price{MPrice} = 0;
		}

		if ( $$specs{"Markup$qty_index"} ) {
			$price{MPrice} *= (1+$$specs{"Markup$qty_index"}/100);
			$price{Price} *= (1+$$specs{"Markup$qty_index"}/100);
		} # end if
		if ( $Project->markup() ) {
			$price{MPrice} *= (1+$Project->markup()/100);
			$price{Price} *= (1+$Project->markup()/100);
		} # end if
		if ( ( defined $$specs{'OverridePrice'.$qty_index} ) and ( $$specs{'OverridePrice'.$qty_index} eq 'Y' ) ) {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{'txtPrice'.$qty_index} );
		} else {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $price{Price} );
		} # end if
		$$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $price{Price}/$$specs{"txtQuantity$qty_index"} );
		$$specs{"MPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $price{MPrice} );
		$$specs{"txtRunTime$qty_index"} = $price{RunTime};
	} # end foreach qty_index

	$log->debug(" END Perfect Bound!!!!!!!!!!!!!!!!!! status: $$specs{Status}");
	return $$specs{Status};
} # end sub calc

sub get_price {
	my ( $Equipment, $specs, $qty_index ) = @_;

	my %price = (
			Equipment  => $Equipment,
			MakeReady => 0,
			Service  => 0,
			Insert  => 0,
			Price    => 0,
			RunTime  => 0,
			Passes  => [],
			MPrice  => 0,
			Waste    => 0,  
			Imposition => $$specs{'Imposition'.$qty_index},
      Quantity => $$specs{'txtQuantity'.$qty_index},
			);

	my $qty = $$specs{'txtQuantity'.$qty_index};

  my $Overs = $Equipment->Specification('PerfectBind Overs');
  if (my $Overs = $Equipment->Specification('PerfectBind Overs')) {
    my $overs = 0;
    if ( $$Overs{units} eq 'percent' ) {
      $overs = int( $qty * ($$Overs{value}/100) );
    } elsif ( $$Overs{units} eq 'sheets' ) {
      $overs = int( $$Overs{value} );
    } else {
      $openprint::log->error("Unknown units $$Overs{units} in PerfectBinding Overs on $$Equipment{name}");
    } # end if
    $price{Overs} = $Overs;
    $price{overs} = $overs;
    $qty += $overs;
    $price{Quantity} += $overs;
  } else {
    $openprint::log->error("No overs");
  } # end if

#$openprint::log->debug($price{Imposition} . ' on ' .$Equipment->name() . ' max imp: ' . $Equipment->specification('Maximum Imposition'));
	if ( $_ = $Equipment->specification('Maximum Imposition') and ( $_ < $$specs{'Imposition'.$qty_index} ) ) {
		$price{Imposition} = 1;
#$openprint::log->debug("Maximum Imposition: " . $Equipment->specification('Maximum Imposition')  ) if DEBUG;
	} elsif ( $_ = $Equipment->specification('Maximum Spine Length',$price{Imposition}) and ( $_ < $$specs{Height} ) ) {
#$openprint::log->debug("Maximum Spine Length: $$specs{Height} > " . $Equipment->specification('Maximum Spine Length',$price{Imposition})  ) if DEBUG;
		$price{Imposition} = 1;
	} # end if

  my $maxPockets = $Equipment->specification('Number of Pockets');
  my $neededPockets = $$specs{"txtPockets$qty_index"};
  my $pocket_make_ready_time = $Equipment->specification( 'Pocket Make Ready' );

  # Calculate Full Passes
	if ( $maxPockets and ( $neededPockets > $maxPockets ) ) {
    my %MakeReady = openprint::service::get_price_object( $$specs{ServiceType}.'MakeReady'. $maxPockets.'Pockets', $price{Imposition}, $Equipment );
    if ( ! %MakeReady ) {
      %MakeReady = openprint::service::get_price_object( $$specs{ServiceType}.'MakeReady', $maxPockets, $Equipment );
    } # end if
    $MakeReady{Total} = $MakeReady{Price};
    my %pocketMakeReadyPrice = openprint::service::get_price_object( $$specs{ServiceType}.'PocketMakeReady', $maxPockets, $Equipment );
    if (%pocketMakeReadyPrice) {
      $pocketMakeReadyPrice{Pockets} = $maxPockets;
      $pocketMakeReadyPrice{Total} = $pocketMakeReadyPrice{Price} * $maxPockets;
    }

    $price{RunTime} += $maxPockets * $pocket_make_ready_time if $pocket_make_ready_time;
    # Loaded here, so we don't do it in the loop many times
		my %servicePrice;
		if ( ! ( %servicePrice = openprint::service::get_price_object( $$specs{ServiceType}.$maxPockets.'Pockets', $qty, $Equipment ) ) ) {
			%servicePrice = openprint::service::get_price_object( $$specs{ServiceType}, $maxPockets, $Equipment );
		} # end if

		my $unitsPerHour = $servicePrice{RunSpeed} = $Equipment->specification( 'Units Per Hour', $maxPockets );
		my $runtime = $servicePrice{RunTime} = $unitsPerHour ? $qty/$unitsPerHour : 0; # in hours
    $price{RunTime} += $runtime * 360; #seconds
    $servicePrice{quantity} = $qty;

		my $loopbreak_pockets = $neededPockets;
		while ($neededPockets > $maxPockets) {
			if ( $servicePrice{units} eq 'per m' or $servicePrice{units} eq 'per 1000') {
				$servicePrice{Total} = $servicePrice{Price} * $qty/1000;
				$price{Service} += $servicePrice{Total};
			} elsif ( $servicePrice{units} eq 'each' ) {
				$servicePrice{Total} = $servicePrice{Price} * $qty;
				$price{Service} += $servicePrice{Total};
			} elsif ( $servicePrice{units} =~ /per hour/i ) {
        if (!$runtime) {
          $$specs{alert} .= 'Per hour pricing but no runtime calculated! Check Units Per Hour settings on '.$Equipment->name().'</br>';
        }
				$servicePrice{Total} = $servicePrice{Price} * $runtime;
				$price{Service} += $servicePrice{Total}
			} else {
				$openprint::log->error("Unknown Unit Type: ($servicePrice{units}) on $$specs{ServiceType}");
			} # end if
			$price{MPrice} += ( $servicePrice{Total} / $qty ) * 1000;
      $price{MakeReady} += $MakeReady{Price}; # if %MakeReady and $MakeReady{Price};
      $price{MakeReady} += $pocketMakeReadyPrice{Total};

# The minus 1 is because the result of the first pass, takes up one pocket
			$neededPockets -= ( $maxPockets - 1 );
			last if $neededPockets == $loopbreak_pockets;
      push @{$price{Passes}}, {
        Pockets => $maxPockets,
        MakeReadyPrice => \%MakeReady,
        ServicePrice => \%servicePrice,
        PocketMakeReadyPrice => \%pocketMakeReadyPrice,
      };
		} # end while
	} # end if

# Calculate Last Pass
  my %MakeReady = openprint::service::get_price_object( $$specs{ServiceType}.'MakeReady'. $neededPockets.'Pockets', $price{Imposition}, $Equipment );
  if ( ! %MakeReady ) {
    %MakeReady = openprint::service::get_price_object( $$specs{ServiceType}.'MakeReady', $neededPockets, $Equipment );
  } # end if
  $price{MakeReady} += $MakeReady{Price}; # if %MakeReady and $MakeReady{Price};
  $MakeReady{Total} = $MakeReady{Price};
  my %pocketMakeReadyPrice = openprint::service::get_price_object( $$specs{ServiceType}.'PocketMakeReady', $neededPockets, $Equipment );
  if (%pocketMakeReadyPrice) {
    $pocketMakeReadyPrice{Pockets} = $neededPockets;
    $pocketMakeReadyPrice{Total} = $pocketMakeReadyPrice{Price} * $neededPockets;
    $price{MakeReady} += $pocketMakeReadyPrice{Total};
  }
	my %servicePrice;
	if ( ! ( %servicePrice = openprint::service::get_price_object( $$specs{ServiceType}.$neededPockets.'Pockets', $qty, $Equipment ) ) ) {
		%servicePrice = openprint::service::get_price_object( $$specs{ServiceType}, $neededPockets, $Equipment );
	} # end if
	if ( %servicePrice and $servicePrice{Price} ) {
    $servicePrice{quantity} = $qty;
		my $unitsPerHour = $servicePrice{RunSpeed} = $Equipment->specification( 'Units Per Hour', $neededPockets );
		my $runtime = $servicePrice{RunTime} = $unitsPerHour ? $qty/$unitsPerHour : 0; # in hours
    $price{RunTime} += $runtime * 360;
		if ( $servicePrice{units} eq 'per m' or $servicePrice{units} eq 'per 1000') {
			$servicePrice{Total} = $servicePrice{Price} * $qty/1000;
			$price{Service} += $servicePrice{Total};
		} elsif ( $servicePrice{units} eq 'each' ) {
			$servicePrice{Total} = $servicePrice{Price} * $qty;
			$price{Service} += $servicePrice{Total};
		} elsif ( $servicePrice{units} =~ 'per hour' ) {
      if (!$runtime) {
        $$specs{alert} .= 'Per hour pricing but no runtime calculated! Check Units Per Hour settings on '.$Equipment->name().'</br>';
      }
			$servicePrice{Total} = $servicePrice{Price} * $runtime;
			$price{Service} += $servicePrice{Total}
		} else {
			$openprint::log->error("Unknown Unit Type: $servicePrice{units} for $$specs{ServiceType} range($neededPockets) equipment(".$Equipment->strid().")");
		} # end if
		$price{MPrice} += ( $servicePrice{Total} / $qty ) * 1000;
		push @{$price{Passes}}, {
      Pockets => $neededPockets,
      MakeReadyPrice => \%MakeReady,
      ServicePrice => \%servicePrice,
      PocketMakeReadyPrice => \%pocketMakeReadyPrice,
    }
  } # end if

	if ( $$specs{glue_id} ) {
		my $Material = new openprint::Material( $$specs{glue_id} );
		my %GluePrice = $Material->get_price( $$specs{"txtQuantity$qty_index"}, undef );
    if (%GluePrice) {
      if ( $GluePrice{units} eq 'per square inch' ) {
        $GluePrice{Total} = $GluePrice{Price} * $$specs{Width} * $$specs{txtCalliper} * $$specs{"txtQuantity$qty_index"};
        $price{GluePrice} = \%GluePrice;
      $price{MPrice} += ( $GluePrice{Total} / $qty ) * 1000;
      } elsif ( $GluePrice{units} eq 'per square foot' ) {
        $GluePrice{Total} = $GluePrice{Price} * $$specs{Width} * $$specs{txtCalliper} * $$specs{"txtQuantity$qty_index"} / 144;
        $price{GluePrice} = \%GluePrice;
      $price{MPrice} += ( $GluePrice{Total} / $qty ) * 1000;
      } else {
        # one time?!
        $GluePrice{Total} = $GluePrice{Price};
        $price{GluePrice} = \%GluePrice;
      } # end if
      $price{Glue} = $Material;
      $price{Price} += $GluePrice{Total};
    }
	} # end if Glues

	if ( $$specs{txtInsertQuantity} and ( $$specs{txtInsertQuantity} > 0 ) ) {
		$price{Insert} = openprint::service::get_price( $$specs{ServiceType}.'Insert', $$specs{txtInsertQuantity}, $Equipment) * $$specs{txtInsertQuantity};
# Convert to cost per thousand
		$price{Insert} = ($price{Insert}*$qty)/1000;
		$price{Price} += $price{Insert};
	} # end if

	my $gateFolds = $$specs{'txtSignatureQtySingleGateFolded'.$qty_index} + $$specs{'txtSignatureQtyDoubleGateFolded'.$qty_index} if $$specs{'txtSignatureQtySingleGateFolded'.$qty_index} and $$specs{'txtSignatureQtyDoubleGateFolded'.$qty_index};
	if ( $gateFolds and ( $gateFolds > 0 ) and ( $$specs{rdbGateFoldFit} eq 'Exact' ) ) {
		$price{Service} += openprint::service::get_price( $$specs{ServiceType}, $gateFolds, $Equipment );
		$price{MakeReady} += $MakeReady{Price} + ( $pocketMakeReadyPrice{Price} * ( $gateFolds + 1 ) );
	} # end if

	$price{'Calliper Markup'} = $Equipment->specification( 'Calliper Price Adjustment', $$specs{txtCalliper} );
	$price{Service} *= ( 1 + $price{'Calliper Markup'}/100) if $price{'Calliper Markup'};

	$price{'RunCost Discount'} = $Equipment->specification( 'RunCost Discount', $$specs{"txtQuantity$qty_index"} );
	$price{Service} *= ( 1 - $price{'RunCost Discount'}/100) if $price{'RunCost Discount'};

	$price{'Imposition Discount'} = $Equipment->specification( 'Imposition Discount', $price{Imposition} );
	$price{Service} *= ( 1 - $price{'Imposition Discount'}/100) if $price{'Imposition Discount'};

	if ( my $Spec = $Equipment->Specification('Make Ready Waste', $neededPockets ) ) {
		if ( $$Spec{units} eq 'Sheets' ) {
			$price{Waste} = $$Spec{value};
			if ( $$Spec{units} eq 'Percent' ) {
				$price{Waste} = $qty*($$Spec{value}/100);
			} # end if
		} # end if
	} # end if
	if ( my $Spec = $Equipment->Specification('Run Waste', $neededPockets ) ) {
		if ( $$Spec{units} eq 'Sheets' ) {
			$price{Waste} += $$Spec{value};
			if ( $$Spec{units} eq 'Percent' ) {
				$price{Waste} += $qty*($$Spec{value}/100);
			} # end if
		} # end if
	} # end if

	$price{Price} += $price{MakeReady} + $price{Service};
#$openprint::log->debug($price{Imposition} . ' on ' .$Equipment->name() . ' max imp: ' . $Equipment->specification('Maximum Imposition') . 'Discount: ' . $Equipment->specification( 'Imposition Discount', $price{Imposition} ) . ' ' . $price{Price} ) if DEBUG;
	return \%price;
} # end sub get_price

sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

	$$variable{Equipment} = [ openprint::Equipment->find( Specifications => {'PerfectBound Capable'=>['Y','When Printing']}, useinestimating=>1,order=>'strName') ];

} # end sub display

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	if ( $qty_index ) {
		if ( $$specs{'Imposition'.$qty_index} ) {
			return $$specs{'Imposition'.$qty_index} .'out';
		} # end if
	} # end if

	if ( $$specs{glue_id} ) {
		my $Material = new openprint::Material( $$specs{glue_id} );
		return 'Using ' . $Material->description();
	} # end if
	return '';
} # end sub summary

sub runtime {
	my ( $p_id, $s_id, $specs, $qty_index ) = @_;

	return 0 if ! $$specs{'ddmEquipment'.$qty_index};
	my @Equipment = openprint::Equipment->find( id => $$specs{'ddmEquipment'.$qty_index} );
	return 0 if @Equipment != 1;

	my $Equipment = $Equipment[0];

	my $runTime;

# Count the # of signatures
	my $pockets = 0;
	foreach my $spec ( keys %$specs ) {
		if ( $spec =~ /^txtSignatureQty(.*)$/ ) {
			$pockets += int($$specs{$spec});
		} # end if
	} # end foreach

	$pockets += int( $$specs{txtInsertQuantity} );
	my $gateFolds = int($$specs{txtSignatureQtySingleGateFolded} ) + int($$specs{txtSignatureQtyDoubleGateFolded});
	if ( $$specs{rdbGateFoldFit} eq 'Exact' ) {
		$pockets -= $gateFolds;
	} # end if

	my $maxPockets = $Equipment->specification( 'Number of Pockets' );
	my $makereadytime = $Equipment->specification( 'Pocket Make Ready' ) * 60;
#$openprint::log->debug("MakeReadyTime: $makereadytime");
	$runTime += $pockets * $makereadytime;

# Calculate Full Passes
	if ( $pockets > $maxPockets ) {
# Loaded here, so we don't do it in the loop many times
		if ( my $unitsPerHour = $Equipment->specification( 'Units Per Hour', $maxPockets ) ) {
			$runTime += ($$specs{"txtQuantity$qty_index"}*3600/$unitsPerHour) * int ( $pockets / $maxPockets );
			$pockets = $pockets % $maxPockets;
		} # end if
	} # end if

# Calculate Last Pass
	if ( my $unitsPerHour = $Equipment->specification( 'Units Per Hour', $pockets ) ) {
		$runTime += $$specs{"txtQuantity$qty_index"}*3600/$unitsPerHour; # in seconds
	} # end if
	return $runTime;
} # end sub get_runtime

sub save {
} # end sub save

sub has_overrides {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

	my @v;
	if ( ! $qty_index ) {
		push @v, 'override_glue_id' if $$specs{override_glue_id};
	} else {
			push @v, "chkOverrideEquipment$qty_index" if $$specs{"chkOverrideEquipment$qty_index"};
			push @v, "OverrideImposition$qty_index" if $$specs{"OverrideImposition$qty_index"};
			push @v, "OverridePockets$qty_index" if $$specs{"OverridePockets$qty_index"};
			push @v, "OverridePrice$qty_index" if $$specs{"OverridePrice$qty_index"};
	} # end if

	return @v;
} # end sub has_overrides

1;
__END__
