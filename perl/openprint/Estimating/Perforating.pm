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

package openprint::Estimating::Perforating;
use strict;
#use warnings;

require openprint::service;
require openprint::Service;
require openprint::Material;
require openprint::imposition;
require openprint::Imposition;

use constant DEBUG => 0;

use vars qw( %ServicePrices %Specifications);
%ServicePrices = (
  PerforatingMinimumCharge => { range_units => [''], units=>['']},
  PerforatingMakeReady => { range_units => [''], units=>['']},
  PerforatingMakeReadySimple => { range_units => [''], units=>['']},
  PerforatingMakeReadyAverage => { range_units => [''], units=>['']},
  PerforatingMakeReadyComplex => { range_units => [''], units=>['']},
  Perforating => { range_units=>['impressions'], units=> ['per hour', 'per m']},
);
%Specifications = (
  'RunSpeed' => {range_units => [ 'calliper'], units=>'per hour'},
  'Perforating Overs' => {range_units => [ 'impressions' ], units=>['percent']},
  'Perforating Capable' => { value=>['Y','N', 'When Printing', 'When Folding', 'When Stitching' ] },
);

sub ServicePriceConfiguration {
  my $name = shift;
  return $ServicePrices{$name} if $ServicePrices{$name};
  foreach my $key (keys %ServicePrices) {
    return $ServicePrices{$key} if $name eq$key;
  }
  return undef;
}
sub SpecificationConfiguration {
  return $Specifications{shift};
}


my @all_equipment;
my @stitchers;
my %Materials;

my @variables = (
  'alert', 'complexity',
	'txtQuantity1','txtQuantity2','txtQuantity3',
  'txtPrice1','txtPrice2','txtPrice3',
	'MPrice1', 'MPrice2', 'MPrice3',
	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
	'Markup1', 'Markup2', 'Markup3',
	'hdnBreakdown1', 'hdnBreakdown2', 'hdnBreakdown3',
);
sub variables {
	my $p_id = shift;
	my @v = @variables;

	my $Project = new openprint::Project( $p_id );
	foreach my $signature_service_index ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
		
		foreach my $qty_index ( $Project->quantity_indexes() ) {
			push @v, (
				 "txtVerticalQty-$$sig_specs{SignatureIndex}", "VerticalTeeth-$$sig_specs{SignatureIndex}",
				 "txtHorizontalQty-$$sig_specs{SignatureIndex}", "HorizontalTeeth-$$sig_specs{SignatureIndex}",
				 "ddmEquipment-$$sig_specs{SignatureIndex}-$qty_index", "chkOverrideEquipment-$$sig_specs{SignatureIndex}-$qty_index",
				 "txtImposition-$$sig_specs{SignatureIndex}-$qty_index", "chkOverrideImposition-$$sig_specs{SignatureIndex}-$qty_index",
				 "txtLayoutWidth-$$sig_specs{SignatureIndex}-$qty_index", "txtLayoutHeight-$$sig_specs{SignatureIndex}-$qty_index",
				 );
		} # end foreach qty_index
	} # end foreach signature_service_index
	return @v;
} # end sub variables

my @no_output = (
	'Markup1', 'Markup2', 'Markup3', 'complexity',
);

sub no_outputs {
	my ( $p_id, $s_id, $specs, $new_specs ) = @_;
	my $Project = new openprint::Project( $p_id );

	my @v = @no_output;

	foreach my $signature_service_index ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );

		foreach my $qty_index ( $Project->quantity_indexes() ) {

		push @v, (
				"txtVerticalQty-$$sig_specs{SignatureIndex}", "VerticalTeeth-$$sig_specs{SignatureIndex}",
				"txtHorizontalQty-$$sig_specs{SignatureIndex}", "HorizontalTeeth-$$sig_specs{SignatureIndex}",
				"chkOverrideEquipment-$$sig_specs{SignatureIndex}-$qty_index",
				( $$new_specs{"chkOverrideEquipment-$$sig_specs{SignatureIndex}-$qty_index"} eq 'Y' ? "ddmEquipment-$$sig_specs{SignatureIndex}-$qty_index" : () ),
				"chkOverrideImposition-$$sig_specs{SignatureIndex}-$qty_index",
				( $$new_specs{"chkOverrideImposition-$$sig_specs{SignatureIndex}-$qty_index"} eq 'Y' ? "txtImposition-$$sig_specs{SignatureIndex}-$qty_index" : () ),
					);
		} # end foreach qty_index
	} # end foreach signature
	return @v;
}

sub signature_has_perforation {
	my ( $specs, $sig_specs ) = @_;
	return 1 if $$specs{"txtVerticalQty-$$sig_specs{SignatureIndex}"} or $$specs{"txtHorizontalQty-$$sig_specs{SignatureIndex}"};
	return 0;
} # end sub signature_has_perforation

# A function that is smart enough to return true if the project needs perfing, and false if it doesn't.
sub neccessary {
	my ( $Project ) = @_;

  $Project = new openprint::Project( $Project ) if ref $Project ne 'openprint::Project';
	return 1 if ( $Project->signatures({'type'=>'PerfReplyCard'}) );
#
    #my %services = $Project->get_services( );
    #if ( $services{NoBindery} ) {
        #$log->debug(" ** Project is marked as No bindery, Perforating not needed ! ** ");
        #return 0;
    #} # end if

	#$log->debug("PERF NOT NEEDED!");
	return 0;
} # end sub neccessary


sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $status = 'calculated';
	my $Project = new openprint::Project( $project_index );
  $$specs{alert} = '';

	$log->debug('BEGIN PERFING!!!!!!!!!!!!!!!!!!') if DEBUG;

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"Markup$qty_index"} =~ s/[^\d\.\-]//g if $$specs{"Markup$qty_index"};
		$$specs{"txtPrice$qty_index"} =~ s/[^\d\.]//g if $$specs{"txtPrice$qty_index"};
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
		if ( ! $$specs{"txtQuantity$qty_index"} > 0 ) {
			next;
		} # end if

		$$specs{'hdnBreakdown'.$qty_index} = qq`QTY $qty_index ( $$specs{"txtQuantity$qty_index"} )<br/>`;
		my $qty = $$specs{"txtQuantity$qty_index"};
		if ( $$specs{txtPressSheetComboItems} ) {
			$qty *= $$specs{txtPressSheetComboItems};
		} # end if

		my $qtyTotal = 0;
		my $price = 0;
		my $mprice = 0;

		foreach my $signature_service_index ( $Project->signatures() ) {
			my $Signature_Service = $Project->Service( $signature_service_index );
      my $sig_specs = $Signature_Service->specs();

# If any of the signatures doesn't have an imposition, then we are in an incomplete state.
			if ( ! $$sig_specs{'txtImposition'.$qty_index} ) {
				if ( $$Signature_Service{status} ne 'calculated' ) {
					$$specs{alert} = 'Printing calculations are not complete.';
					$status = 'uncalculated';
				}
				next;
			} # end if
			my $form = $$sig_specs{SignatureIndex};

			my $Imposition = new openprint::Imposition();
			$Imposition->load( $sig_specs, $qty_index, $Project );
			$$specs{'hdnBreakdown'.$qty_index} .= "Signature: $form " . ( $$sig_specs{txtServiceDescription} ? $$sig_specs{txtServiceDescription} : '' ) . '<br/>';
			$$specs{'hdnBreakdown'.$qty_index} .=  $Imposition->to_string() . '<br/>';
			$$specs{'hdnBreakdown'.$qty_index} .=  $Imposition->Paper()->to_string() . '<br/>';

			my %Price = signature_calc( $Project, $service_index, $specs, $signature_service_index, $sig_specs, $qty_index, $Imposition );
			if ( ! ( $$specs{"txtVerticalQty-$form"} or $$specs{"txtHorizontalQty-$form"} ) ) {
				$$specs{"txtImposition-$form-$qty_index"} = 0;
				$$specs{"txtLayoutWidth-$form-$qty_index"} = 0;
				$$specs{"txtLayoutHeight-$form-$qty_index"} = 0;
				next;
			} # end if
      $$specs{alert} .= $Price{alert};
			$$specs{'hdnBreakdown'.$qty_index} .= $Price{Breakdown};
			$qtyTotal += $$specs{"txtVerticalQty-$form"};
			$qtyTotal += $$specs{"txtHorizontalQty-$form"};

			if ( $Price{Equipment} ) {
				$$specs{"ddmEquipment-$form-$qty_index"} = $Price{Equipment}->id();
				if ( $Price{Imposition} ) {
					$$specs{"txtImposition-$form-$qty_index"} = $Price{Imposition}{imposition};
					$$specs{"txtLayoutWidth-$form-$qty_index"} = $Price{Imposition}->layout_width();
					$$specs{"txtLayoutHeight-$form-$qty_index"} = $Price{Imposition}->layout_height();
				} # end if
				$status = $Price{Status};
			} else {
				$$specs{"ddmEquipment-$form-$qty_index"} = '' if $$specs{"chkOverrideEquipment-$form-$qty_index"} ne 'Y';
				$$specs{"txtImposition-$form-$qty_index"} = 0;
				$$specs{"txtLayoutWidth-$form-$qty_index"} = 0;
				$$specs{"txtLayoutHeight-$form-$qty_index"} = 0;
				$status = 'uncalculated';
				if ( $$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' ) {
					$$specs{alert} = 'The selected equipment can not handle your project. This may be because the stock is too heavy, or too large.' if !$$specs{alert};
				} else {
					$$specs{alert} = 'No suitable equipment could be found for your project. This may be because the stock is too heavy, or too large.' if !$$specs{alert};
				} # end if
        next;
			} # end if
      $price += $Price{SetupPrice} + $Price{ServicePrice}{Total} + $Price{VerticalPrice}{Total} + $Price{HorizontalPrice}{Total};
			$mprice += ( ( $Price{ServicePrice}{Total} + $Price{VerticalPrice}{Total} + $Price{HorizontalPrice}{Total} ) / $qty ) * 1000;
		} # end foreach signature

		my $unitPrice = 0;

		if ( $qtyTotal ) {
			$unitPrice = $price / $qty if $qty;
		} else {
			$$specs{alert} .= 'Please specify # of perfs for quantity ' . $qty_index . '<br/>';
			$status = 'uncalculated';
		} # end if
		$$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $unitPrice * (1+$Project->markup()/100) );
		$$specs{"MPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $mprice*(1+$$specs{"Markup$qty_index"}/100)*(1+$Project->markup()/100) );
		if ( $$specs{"OverridePrice$qty_index"} ne 'Y' ) {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $price*(1+$$specs{"Markup$qty_index"}/100)*(1+$Project->markup()/100) );
		} else {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"} );
		} # end if
	} # end foreach quantities

	$log->debug('END PERFING!!!!!!!!!!!!!!!!!!') if DEBUG;
	return $$specs{Status} = $status;
} # end sub calc

sub signature_calc {
	my ( $Project, $service_index, $specs, $signature_service_index, $sig_specs, $qty_index, $imposition ) = @_;

	$specs = openprint::service::get_specs_ref( $Project, $service_index ) if ! $specs;
	$sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index ) if ! $sig_specs;

	my $services = $Project->services();
	my $printing_specs = openprint::service::get_specs_ref($Project, $$services{''}[0]) if $$services{''};

	my $form = $$sig_specs{SignatureIndex};

	my %Results = (
      alert => '',
			Status => 'calculated',
			Breakdown	 => '',
			);

	#@$specs{"txtWidth-$form", "txtHeight-$form"} = @$sig_specs{'txtWidth','txtHeight'};
	if ( $$sig_specs{txtSignatureType} and ( $$sig_specs{txtSignatureType} eq 'PerfReplyCard' ) and ! ( $$specs{"txtVerticalQty-$form"} or $$specs{"txtHorizontalQty-$form"} ) ) {
		$$specs{"txtVerticalQty-$form"} = 1;
		@no_output = sets::exclude( [ "txtVerticalQty-$form" ], \@no_output );
	} # end if

	my $rule_qty = $$specs{"txtVerticalQty-$form"} + $$specs{"txtHorizontalQty-$form"};
	if ( ! $rule_qty ) {
		return %Results;
	} # end if

	my $scoring_service_index = $$services{Scoring}[0] if $$services{Scoring};
	my $cutting_service_index = $$services{Cutting}[0] if $$services{Cutting};
# Can only use the stitcher for scoring if we are stitching.  There are also thickness constraints
	my $stitching_service_index = $$services{SaddleStitching}[0] if $$services{SaddleStitching};
# Can only use the stitcher for scoring if we are stitching.  There are also thickness constraints
	$stitching_service_index = $$services{LoopStitching}[0] if ( ! $stitching_service_index) and $$services{LoopStitching};

	if (!@all_equipment) {
		@all_equipment = openprint::Equipment->find( Specifications => {'Perforating Capable'=>['Y','When Printing', 'When Folding']}, useinestimating=>1 );
	} # end if

	@stitchers = openprint::Equipment->find( Specifications => {'Stitching Capable'=>'Y'}, useinestimating=>1 ) if ! @stitchers;
	my @equipment;

	if ( $$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' ) {
		if ( $$specs{"ddmEquipment-$form-$qty_index"} ) {
			@equipment = openprint::Equipment->find( id=>$$specs{"ddmEquipment-$form-$qty_index"} );
		} else {
			$Results{alert} .= 'Please select the equipment.<br/>';
      $Results{Status} = 'uncalculated';
			return %Results;
		} # end if
		#$openprint::log->debug("Overriding Equipment to: " . $$specs{"ddmEquipment-$$sig_specs{SignatureIndex}-$qty_index"} ) if DEBUG;
	} elsif ( ! $stitching_service_index ) {
		@equipment = sets::exclude( \@stitchers, \@all_equipment );
	} else {
		@equipment = @all_equipment;
  } # end if

  my @complexityoptions = map { openprint::Service->find_one(name=>'PerforatingMakeReady'.$_) ? $_ : () } ( 'Simple','Average', 'Complex' );
  if (@complexityoptions and ! $$specs{complexity}) {
    $Results{alert} .= 'Please select the complexity.<br/>';
    $Results{Status} = 'uncalculated';
    return %Results;
  } # end if

	if ( ! $imposition ) {
		$openprint::log->error('Really shouldn\'t be loading imposition here, too slow');
		$imposition = new openprint::Imposition();
		$imposition->load( $sig_specs, $qty_index );
	} # end if

	if ( (defined $$specs{"chkOverrideImposition-$form-$qty_index"}) and ( $$specs{"chkOverrideImposition-$form-$qty_index"} eq 'Y' ) ) {
		if ( $$specs{"txtImposition-$form-$qty_index"} > $$imposition{imposition} or $$specs{"txtImposition-$form-$qty_index"} <= 0 ) {
			$Results{alert} .= 'The specified imposition is not possible.<br/>';
			$Results{Status} = 'uncalculated';
			return %Results;
		} # end if
	} # end if

	my @cut_impositions = ( $imposition );
	if ( $cutting_service_index ) {
		my @imps = openprint::imposition::get_all_impositions( @cut_impositions );
		$openprint::log->debug('How many impositions do we get? ' . @imps ) if DEBUG;
		if ( DEBUG ) {
			foreach my $i ( @imps ) {
				$i->display('Cut impo');
			}
		}
		for ( my $i = 0; $i < @imps; $i += 1 ) {
			if ( $$imposition{imposition} % $imps[$i]{imposition} ) {
				next;
			}
			if ( (!$$specs{"chkOverrideImposition-$form-$qty_index"}) or ( $$specs{"chkOverrideImposition-$form-$qty_index"} ne 'Y' )
					or ( $$specs{"txtImposition-$form-$qty_index"} == $imps[$i]{imposition} )
			   ) {
				push @cut_impositions, $imps[$i];
			} # end if
			for ( my $j = $i + 1; $j < @imps; $j += 1 ) {
				if ( $imps[$i]{imposition} == $imps[$j]{imposition} and $imps[$i]{rows} == $imps[$j]{rows} ) {
					splice @imps, $j, 1;
					$j -= 1;
				} # end if
			} # end foreach
		} # end foreach
	} # end if has cutting

	if ( DEBUG ) {
		foreach my $i ( @cut_impositions ) {
			$i->display('Cut impo');
		}
	}

	my ( $scor_equipment, $scor_imposition );
	if ( $scoring_service_index ) {
		my $score_specs = openprint::service::get_specs_ref( $Project, $scoring_service_index );

		( $scor_equipment, $scor_imposition ) = @$score_specs{"ddmEquipment-$form-$qty_index", "txtImposition-$form-$qty_index"};
		if ( ( $$score_specs{"txtVerticalQty-$form"} or $$score_specs{"txtHorizontalQty-$form"} ) and ! $scor_equipment ) {
			$openprint::log->debug("No equipment selected for scoring.  Quitting.") if DEBUG;
			$Results{alert} = 'Scoring calculations are not complete.  Your project contains a scoring service.  It must be completed before the Perforating service.';
			$Results{Status} = 'uncalculated';
			return %Results;
		} # end if
	} # end if

	my $rule_name = 'PerforatingRule'.( $$specs{"VerticalTeeth-$form"}?$$specs{"VerticalTeeth-$form"}.' Tooth' : '');

	$Materials{$rule_name} = openprint::Material->find_one( name=>$rule_name ) if ! exists $Materials{$rule_name};

	my $Rule = $Materials{$rule_name};
	if ( ! $Rule ) {
		if ( $$specs{"VerticalTeeth-$form"} and ( $$specs{"VerticalTeeth-$form"} >= 25 ) ) {
			$rule_name = 'PerforatingRule Micro Perf';
			$Materials{$rule_name} = openprint::Material->find_one( name=>$rule_name ) if ! exists $Materials{$rule_name};
			$Rule = $Materials{$rule_name};
		} else {
			$rule_name = 'PerforatingRule';
			$Materials{$rule_name} = openprint::Material->find_one( name=>$rule_name ) if ! exists $Materials{$rule_name};
			$Rule = $Materials{$rule_name};
		} # end if
	} # end if

	my $wheel_name = 'PerforatingWheel'.( $$specs{"HorizontalTeeth-$form"}?$$specs{"HorizontalTeeth-$form"}.' Tooth' : '' );
	$Materials{$wheel_name} = openprint::Material->find_one( name=>$wheel_name ) if ! exists $Materials{$wheel_name};

	my $Wheel = $Materials{$wheel_name};
	if ( ! $Wheel ) {
		if ( $$specs{"HorizontalTeeth-$form"} and ( $$specs{"HorizontalTeeth-$form"} >= 25 ) ) {
			$wheel_name = 'PerforatingWheel Micro Perf';
			$Materials{$wheel_name} = openprint::Material->find_one( name=>$wheel_name ) if ! exists $Materials{$wheel_name};
			$Wheel = $Materials{$wheel_name};
		} else {
			$wheel_name = 'PerforatingWheel';
			$Materials{$wheel_name} = openprint::Material->find_one( name=>$wheel_name ) if ! exists $Materials{$wheel_name};
			$Wheel = $Materials{$wheel_name};
		} # end if
	} # end if
	$Wheel = $Rule if ! $Wheel;

	foreach my $Equipment ( @equipment ) {
		my $Horizontal_Material = $Rule;
		my $Vertical_Material = $Wheel;

		my $type = $Equipment->specification('Type');
		$Results{Breakdown} .= sprintf('<br/>Equipment: %s, ', $Equipment->name() . ' type: ' . $type . ' ' );
		my $max_feed_width = $Equipment->specification('Maximum Feed Width');
		$Results{Breakdown} .= "Maximum Feed Width: $max_feed_width<br/>" if $max_feed_width;
		my $orientation = $Equipment->specification('Orientation');

		my @impositions = ();
		if ( $type eq 'Press' ) {
			if ( ( $Equipment->specification('WTPerforation') ne 'Y' ) and $$sig_specs{'ddmRunStyle'.$qty_index} =~ /^Work/ ) {
				$Results{Breakdown} .= 'Cant do an inline perf when W&T.<br/>';
				if ( $$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' ) {
					$$specs{alert} = 'Can\'t do an inline perf when W&T.  After saving, printing will be recalculated.';
					$Results{Equipment} = $Equipment;
					$Results{Status} = 'uncalculated';
					return %Results;	
				} # end if
				next;
			} # end if
			$Vertical_Material = $Rule;
			@impositions = ($imposition);
		} elsif ( ( $Equipment->specification('Cross Perforating / Scoring') eq 'N' ) and $$specs{"txtHorizontalQty-$form"} and $$specs{"txtVerticalQty-$form"} ) {
			if ( $$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' ) {
				$$specs{alert} = 'Doesnt support cross Perfing<br/>';
				$Results{Equipment} = $Equipment;
				$Results{Status} = 'uncalculated';
				return %Results;	
			} # end if
			next;
		} else {
			@impositions = @cut_impositions;
		} # end if
		if ( $$services{NoOfflineBindery} and ( $$sig_specs{'ddmPress'.$qty_index} ne $$Equipment{strid} ) ) {
			$Results{Breakdown} .= "No Offline bindery and not printing on $$Equipment{name}.<br/>";
			next;
		} # end if
		if ( ($Equipment->specification('Perforating Capable') eq 'When Printing' ) and ( $$sig_specs{'ddmPress'.$qty_index} ne $Equipment->strid() ) ) {
			$Results{Breakdown} .= "Not printing on $$Equipment{name}.<br/>";
			next;
		} # end if

		my $Runspeed = $Equipment->Specification('PerfScoreRunSpeed');
		$Runspeed = $Equipment->Specification('Perforating Runspeed') if ! $Runspeed;
		my $MaxRunSpeed = $Equipment->Specification('PerfScoreMaximumRunSpeed');


    my $mr_service = 'PerforatingMakeReady'. ($$specs{complexity} ? $$specs{complexity} : '');
		my $setupPrice = openprint::service::get_price($mr_service, undef, $Equipment);
		$Results{Breakdown} .= sprintf('Setup: $%.2f<br/>', $setupPrice);
		my $max_impo = $Equipment->specification('Maximum Perforation Imposition');

		my $CylinderCount = $Equipment->specification('Perforating # of Cylinders');
		$Results{Breakdown} .= join( '', 'Cylinder Count: ', $CylinderCount, '<br/>' ) if defined $CylinderCount;

		foreach my $I ( @impositions ) {
			$Results{Breakdown} .= 'Imposition: ' . $I->to_string() . '<br/>';
 
			if ( $max_feed_width ) {
				if ( $orientation ) {
					$Results{Breakdown} .= 'Has orientation setting.<br/>';
					if (
							( $orientation eq 'Portrait' and $I->layout_width() <= $I->layout_height() ) or
							( $orientation eq 'Landscape' and $I->layout_width() >= $I->layout_height() )
						 ) {
						if ( $I->layout_width() >= $max_feed_width ) {
							$Results{Breakdown} .= "Perf no good due to max feed width($max_feed_width) on width ($$sig_specs{txtWidth}).<br/>";
							next;
						} # end if
					} else {
						if ( $I->layout_height() >= $max_feed_width ) {
							$Results{Breakdown} .= "Perf no good due to max feed width($max_feed_width) on width ($$sig_specs{txtHeight}).<br/>";
							next;
						} # end if
					} # end if
				} else {
					if ( $$specs{"txtVerticalQty-$form"} and $$specs{"txtHorizontalQty-$form"} ) {
# Do nothing, we already know it fits on the machine, and it has to go one way or another.
						$Results{Breakdown} .= 'Running either way because scores both ways.<br/>';
					} elsif ( $$specs{"txtVerticalQty-$form"} ) {
						if ( $$I{image_orientation} == openprint::Imposition::Vertical ) {
							$Results{Breakdown} .= 'Running ' . $I->layout_width() . ' ' . $$I{image_orientation} . ' on feed of ' . $max_feed_width . '<br/>';
							if ( $I->layout_width() >= $max_feed_width ) {
								$Results{Breakdown} .= "Perf no good due to max feed width($max_feed_width) on width (".$I->layout_width().").<br/>";
								next;
							} # end if
						} else {
							$Results{Breakdown} .= 'Running ' . $I->layout_height() . ' on feed of ' . $max_feed_width . '<br/>';
						} # end if
					} elsif ( $$specs{"txtHorizontalQty-$form"} ) {
						if ( $$I{image_orientation} == openprint::Imposition::Horizontal ) {
							$Results{Breakdown} .= 'Running ' . $I->layout_height() . ' on feed of ' . $max_feed_width . '<br/>';
							if ( $I->layout_height() >= $max_feed_width ) {
								$Results{Breakdown} .= "Perf no good due to max feed width($max_feed_width) on width (".$I->layout_height().").<br/>";
								next;
							} # end if
						} else {
							$Results{Breakdown} .= 'Running ' . $I->layout_width() . ' on feed of ' . $max_feed_width . '<br/>';
						} # end if
					} else {
						$Results{Breakdown} .= 'Running ' . $I->layout_height() . ' on feed of ' . $max_feed_width . '<br/>';
					} # end if
				} # end if orientation or not
			} # end if max_feed)wudetg

			if ( $max_impo and ( $$I{imposition} > $max_impo ) ) {
				$Results{Breakdown} .= sprintf('Too many out %d > max imposition (%d)<br/>', $$I{imposition}, $max_impo );
				next;
			} # end if
			my ( $width, $height ) = ( ( $$imposition{imposition} == $$I{imposition} ) ? ( $I->sheet_width(), $I->sheet_height() ) : ( $I->layout_width(), $I->layout_height() ) );


# If it's a press, then we can assume that it fits.
			if (  
				( $_ = $Equipment->fits( $width, $height, $$sig_specs{txtSpecificStockCalliper} ) ) or 
				( $_ = fits_on_equipment( $Equipment, $width, $height, $$sig_specs{txtSpecificStockCalliper} ) )
				 ) {
				$Results{Breakdown} .= "$_<br/>";
				next;
			} # end if

      my $qty = $$sig_specs{"hdnImpressionQuantity$qty_index"} * ($$imposition{imposition} / $$I{imposition});
      #$Results{Breakdown} .=$$sig_specs{"hdnImpressionQuantity$qty_index"}." * ($$imposition{imposition} / $$I{imposition}) = $qty<br/>";
      if ( $$imposition{runstyle} eq 'Sheet Work' and $imposition->sides() == 2 ) {
        $qty /= 2;
      }
			my %servicePrice;

			if ( $scor_equipment and ( $scor_equipment eq $$Equipment{strid} ) and ( $scor_imposition == $$I{imposition} ) ) {
				$Results{Breakdown} .= 'Same equipment as scoring, no service price needed.<br/>';
			} else {
				%servicePrice = openprint::service::get_price_object( 'Perforating', $qty, $Equipment );
				#%servicePrice = openprint::service::get_price_object( 'Perforating', $rule_qty, $Equipment );
# I don't know if we should be multiplying by this or not.. how many perfs can a given piece of equipment do in an impression?
#$servicePrice *= $$specs{"txtQty-$signature_index"};
			} # end if

			my $runspeed = 0;

			if ( $$Runspeed{units} eq 'Percent' ) {
				if ( ! $$sig_specs{'Runspeed'.$qty_index} ) {
					$openprint::log->error("No perfing runspeed on $$Equipment{strid}");
				}
				$runspeed = int( $$sig_specs{'Runspeed'.$qty_index} - ( $$sig_specs{'Runspeed'.$qty_index} * $$Runspeed{value}/100 ) );
			} else {
				$runspeed = $$Runspeed{value};
			} # end if
			if ( $MaxRunSpeed and ( $$MaxRunSpeed{value} < $runspeed ) ) {
				$runspeed = $$MaxRunSpeed{value};
			} # end if

			if ( $servicePrice{units} eq 'per m' ) {
				$servicePrice{Total} = $servicePrice{Price} * $qty / 1000;
				$Results{Breakdown} .= sprintf('Service: $%1$.2f%2$s * %4$d/1000 = $%3$.2f<br/>', @servicePrice{'Price','units','Total'}, $qty);
			} elsif ( $servicePrice{units} eq 'per hour' ) {
				if ( $runspeed ) {
					my $hours = Math::Round::nearest( 0.01, ( $qty / $$I{imposition} ) / $runspeed );
					$servicePrice{Total} = $servicePrice{Price} * $hours;
					$Results{Breakdown} .= sprintf('Service: $%1$.2f%2$s @ %4$d%5$s = %6$s hours = $%3$.2f<br/>', @servicePrice{'Price','units','Total'}, $Equipment->specification('PerfScoreRunSpeed'), 'Per Hour', $hours );
				} else {
					$Results{Breakdown} .= 'no runspeed';
				} # end if
      } else {
        $openprint::log->error('Invalid units '.$servicePrice{units}.' on Perforating on '.$$Equipment{strid});
        $Results{Breakdown} .= 'Invalid units '.$servicePrice{units}.' on Perforating on '.$$Equipment{strid}.'<br/>';
        $$specs{alert} .= 'Invalid units '.$servicePrice{units}.' on Perforating on '.$$Equipment{strid}.'<br/>';
			} # end if
# Div by imposition
			#$servicePrice /= $$imposition{imposition} if $$imposition{imposition};

			my $totalPrice = $setupPrice + $servicePrice{Total};

			my $horizontal_rules = 0;
			my $horizontal_length = 0;
			my %horizontal_price;
			my $remaining_inches = 0;

			if ( $$I{image_orientation} == openprint::Imposition::Vertical and $$specs{"txtHorizontalQty-$form"} ) {
				$horizontal_rules = $$specs{"txtHorizontalQty-$form"} * $$I{rows};
				$horizontal_length = $horizontal_rules * $width;
				$horizontal_length *= $CylinderCount if $CylinderCount;

				$Results{Breakdown} .= $$specs{"txtHorizontalQty-$form"} . ' x ' . $$I{rows} . ' rows = ' . $horizontal_rules . ' horizontal rules * ' . $width . ' = ' . $horizontal_length . 'inches of rule.<br/>';

			} elsif ( $$I{image_orientation} == openprint::Imposition::Horizontal and  $$specs{"txtVerticalQty-$form"} ) {
				$horizontal_rules = $$specs{"txtVerticalQty-$form"} * $$I{rows};
				$horizontal_length = $horizontal_rules * $width;
				$horizontal_length *= $CylinderCount if $CylinderCount;
				$Results{Breakdown} .= $$specs{"txtVerticalQty-$form"} . ' x ' . $$I{rows} . ' rows = ' . $horizontal_rules . ' horizontal rules * ' . $width . 'inches = ' . $horizontal_length . 'inches of rule.<br/>';
			} # end if

			my $vertical_rules = 0;
			my $vertical_length = 0;
			my %vertical_price;
			
			if ( $$I{image_orientation} == openprint::Imposition::Vertical and  $$specs{"txtVerticalQty-$form"} ) {
				$vertical_rules = $$specs{"txtVerticalQty-$form"} * $$I{columns};
				$vertical_length = $vertical_rules * $height;
				$vertical_length *= $CylinderCount if $CylinderCount;
				$Results{Breakdown} .= $$specs{"txtVerticalQty-$form"} . ' x ' . $$I{columns} . ' columns = ' . $vertical_rules . ' vertical rules * ' . $height . 'inches = ' . $vertical_length . 'inches of rule.<br/>';
			} elsif ( $$I{image_orientation} == openprint::Imposition::Horizontal and $$specs{"txtHorizontalQty-$form"} ) {
				$vertical_rules = $$specs{"txtHorizontalQty-$form"} * $$I{columns};
				$vertical_length = $vertical_rules * $height;
				$vertical_length *= $CylinderCount if $CylinderCount;
				$Results{Breakdown} .= $$specs{"txtHorizontalQty-$form"} . ' x ' . $$I{columns} . ' columns = ' . $vertical_rules . ' vertical rules * ' . $height . 'inches = ' . $vertical_length . 'inches of rule.<br/>';
			} # end if

			if ( $Horizontal_Material and ( $$Horizontal_Material{id} == $$Vertical_Material{id} ) ) {
				$Results{Breakdown} .= 'Rule: ' . $Horizontal_Material->to_string().'<br/>' if DEBUG;
				my $length = $vertical_length + $horizontal_length;
				my $rules = $vertical_rules + $horizontal_rules;
				my $Package_Qty = $Horizontal_Material->Specification('Package Quantity');
				if ( $Package_Qty ) {
					$Results{Breakdown} .= 'Package Quantity: ' . $$Package_Qty{value}.$$Package_Qty{units}.'<br/>';
				} # end if
				%horizontal_price = $Horizontal_Material->get_price( $rules, $Equipment );
				if ( $horizontal_price{units} eq 'per rule' or $horizontal_price{units} eq 'each' ) {
					$horizontal_price{Total} = $horizontal_price{Price} * $rules;
					$Results{Breakdown} .= $$Horizontal_Material{name}.sprintf(': $%1$.2f%2$s * %4$d rules=$%3$.2f<br/>', @horizontal_price{'Price','units','Total'}, $rules );
				} elsif ( $horizontal_price{units} eq 'per inch' ) {
					$horizontal_price{Total} = $horizontal_price{Price} * $length;
					$Results{Breakdown} .= $$Horizontal_Material{name}.sprintf(': $%1$.2f%2$s * %4$.2finches=$%3$.2f<br/>', @horizontal_price{'Price','units','Total'}, $length );
				} elsif ( $horizontal_price{units} eq 'per foot' ) {
					$horizontal_price{Total} = $horizontal_price{Price} * ($length/12);
					$Results{Breakdown} .= $$Horizontal_Material{name}.sprintf('Rule: $%1$.2f%2$s * %4$.2ffeet=$%3$.2f<br/>', @horizontal_price{'Price','units','Total'}, $length/12 );
					if ( $Package_Qty ) {
						if ( $$Package_Qty{units} eq 'feet' ) {
							$Results{Breakdown} .= POSIX::ceil(($length/12) / $$Package_Qty{value} ) . 'packages<br/>';
						} elsif ( $$Package_Qty{units} eq 'inches' ) {
							$Results{Breakdown} .= POSIX::ceil(($length) / $$Package_Qty{value} ) . 'packages<br/>';
						} else {
							$Results{Breakdown} .= 'Unknown units in package qty, ' . $$Package_Qty{units} . '<br/>';
							$openprint::log->error('Unknown units in package qty, ' . $$Package_Qty{units} . '<br/>');
						} # end if
					} # end if
				} elsif ( $horizontal_price{units} eq 'per package' ) {
					my $package_qty;
					if ( $$Package_Qty{units} eq 'feet' ) {
						$Results{Breakdown} .= sprintf( 'Needed %.2f feet', $length / 12  );
						$package_qty = POSIX::ceil( ( $length / 12 ) / $$Package_Qty{value} );
					} elsif ( $$Package_Qty{units} eq 'inches' ) {
						$Results{Breakdown} .= sprintf( 'Needed %d inches', POSIX::ceil($length) );
						$package_qty = POSIX::ceil( $length / $$Package_Qty{value} );
						$remaining_inches = ( $$Package_Qty{value} * $package_qty ) - $length;
					} # end if

					$horizontal_price{Total} = Math::Round::nearest( 0.01, $horizontal_price{Price} * $package_qty );
					$Results{Breakdown} .= $$Horizontal_Material{name}.sprintf(': $%1$.2f%2$s * %4$d packages = $%3$.2f<br/>', @horizontal_price{'Price','units','Total'}, $package_qty );
				} else {
					$Results{Breakdown} .= "Unknown units set on rule price ($horizontal_price{units})<br/>";
				} # end if
				$totalPrice += $horizontal_price{Total};
			} else {

			#$openprint::log->debug("Horizontal: $horizontal_rule");	
				if ( $horizontal_rules ) {
					if ( $Horizontal_Material ) {
						my $Package_Qty = $Horizontal_Material->Specification( 'Package Quantity' );
						if ( $Package_Qty ) {
							$Results{Breakdown} .= 'Package Quantity: ' . $$Package_Qty{value}.$$Package_Qty{units}.'<br/>';
						} # end if
						%horizontal_price = $Horizontal_Material->get_price( $horizontal_rules, $Equipment );
						if ( $horizontal_price{units} eq 'per rule' or $horizontal_price{units} eq 'each' ) {
							$horizontal_price{Total} = $horizontal_price{Price} * $horizontal_rules;
							$Results{Breakdown} .= $Horizontal_Material->name().sprintf(': $%1$.2f%2$s * %4$d rules=$%3$.2f<br/>', @horizontal_price{'Price','units','Total'}, $horizontal_rules );
						} elsif ( $horizontal_price{units} eq 'per inch' ) {
							$horizontal_price{Total} = $horizontal_price{Price} * $horizontal_length;
							$Results{Breakdown} .= $Horizontal_Material->name().sprintf(': $%1$.2f%2$s * %4$.2finches=$%3$.2f<br/>', @horizontal_price{'Price','units','Total'}, $horizontal_length );
						} elsif ( $horizontal_price{units} eq 'per foot' ) {
							$horizontal_price{Total} = $horizontal_price{Price} * ($horizontal_length/12);
							$Results{Breakdown} .= $Horizontal_Material->name().sprintf('Rule: $%1$.2f%2$s * %4$.2ffeet=$%3$.2f<br/>', @horizontal_price{'Price','units','Total'}, $horizontal_length/12 );
							if ( $Package_Qty ) {
								if ( $$Package_Qty{units} eq 'feet' ) {
									$Results{Breakdown} .= POSIX::ceil(($horizontal_length/12) / $$Package_Qty{value} ) . 'packages<br/>';
								} elsif ( $$Package_Qty{units} eq 'inches' ) {
									$Results{Breakdown} .= POSIX::ceil(($horizontal_length) / $$Package_Qty{value} ) . 'packages<br/>';
								} else {
									$Results{Breakdown} .= 'Unknown units in package qty, ' . $$Package_Qty{units} . '<br/>';
									$openprint::log->error('Unknown units in package qty, ' . $$Package_Qty{units} . '<br/>');
								} # end if
							} # end if
						} elsif ( $horizontal_price{units} eq 'per package' ) {
							my $package_qty;
							if ( $$Package_Qty{units} eq 'feet' ) {
								$Results{Breakdown} .= sprintf( 'Needed %.2f feet', $horizontal_length / 12  );
								$package_qty = POSIX::ceil( ( $horizontal_length / 12 ) / $$Package_Qty{value} );
							} elsif ( $$Package_Qty{units} eq 'inches' ) {
								$Results{Breakdown} .= sprintf( 'Needed %d inches', POSIX::ceil($horizontal_length) );
								$package_qty = POSIX::ceil( $horizontal_length / $$Package_Qty{value} );
								$remaining_inches = ( $$Package_Qty{value} * $package_qty ) - $horizontal_length;
							} # end if
		
							$horizontal_price{Total} = Math::Round::nearest( 0.01, $horizontal_price{Price} * $package_qty );
							$Results{Breakdown} .= $Horizontal_Material->name().sprintf(': $%1$.2f%2$s * %4$d packages = $%3$.2f<br/>', @horizontal_price{'Price','units','Total'}, $package_qty );
						} else {
							$Results{Breakdown} .= "Unknown units set on rule price ($horizontal_price{units})<br/>";
						} # end if
					} else {
						#$Results{Breakdown} .= "No price for $$Horizontal_Material{name}";
						$Results{Breakdown} .= "No price for Horizontal Rule";
					} # end if
					$totalPrice += $horizontal_price{Total};
				} # end if horizontal_rules

			#$openprint::log->debug("Vertical: $vertical_rule");	
				if ( $vertical_rules ) {
					if ( $Vertical_Material ) {
						my $Package_Qty = $Vertical_Material->Specification('Package Quantity');
						if ( $Package_Qty ) {
							$Results{Breakdown} .= 'Package Quantity: ' . $$Package_Qty{value}.$$Package_Qty{units}.' per package<br/>';
						} # end if
						%vertical_price = $Vertical_Material->get_price($vertical_rules, $Equipment);
						if ( $vertical_price{units} eq 'per rule' or $vertical_price{units} eq 'each' ) {
							$vertical_price{Total} = $vertical_price{Price} * $vertical_rules;
							$Results{Breakdown} .= $Vertical_Material->name().sprintf(': $%1$.2f%2$s * %4$d wheels=$%3$.2f<br/>', @vertical_price{'Price','units','Total'}, $vertical_rules );
						} elsif ( $vertical_price{units} eq 'per inch' ) {
							$vertical_price{Total} = Math::Round::nearest( $vertical_price{Price} * $vertical_length );
							$Results{Breakdown} .= $$Vertical_Material{name}.sprintf(': $%1$.2f%2$s * %4$.2finches=$%3$.2f<br/>', @vertical_price{'Price','units','Total'}, $vertical_length );
							if ( $Package_Qty ) {
								if ( $$Package_Qty{units} eq 'feet' ) {
									$Results{Breakdown} .= POSIX::ceil(($vertical_length/12) / $$Package_Qty{value} ) . 'packages<br/>';
								} elsif ( $$Package_Qty{units} eq 'inches' ) {
									$Results{Breakdown} .= POSIX::ceil(($vertical_length) / $$Package_Qty{value} ) . 'packages<br/>';
								} else {
									$Results{Breakdown} .= 'Unknown units in package qty, ' . $$Package_Qty{units} . '<br/>';
									$openprint::log->error('Unknown units in package qty, ' . $$Package_Qty{units} . '<br/>');
								} # end if
							} # end if
						} elsif ( $vertical_price{units} eq 'per foot' ) {
							$vertical_price{Total} = Math::Round::nearest( 0.01, $vertical_price{Price} * ( $vertical_length/12 ) );
							$Results{Breakdown} .= $$Vertical_Material{name}.sprintf(': $%1$.2f%2$s * %4$.2ffeet=$%3$.2f<br/>', @vertical_price{'Price','units','Total'}, $vertical_length/12 );
							if ( $Package_Qty ) {
								if ( $$Package_Qty{units} eq 'feet' ) {
									$Results{Breakdown} .= POSIX::ceil(($vertical_length/12) / $$Package_Qty{value} ) . 'packages<br/>';
								} elsif ( $$Package_Qty{units} eq 'inches' ) {
									$Results{Breakdown} .= POSIX::ceil(($vertical_length) / $$Package_Qty{value} ) . 'packages<br/>';
								} else {
									$Results{Breakdown} .= 'Unknown units in package qty, ' . $$Package_Qty{units} . '<br/>';
									$openprint::log->error('Unknown units in package qty, ' . $$Package_Qty{units} . '<br/>');
								} # end if
							} # end if
						} elsif ( $vertical_price{units} eq 'per package' ) {
							my $package_qty;
								
							if ( $$Package_Qty{units} eq 'feet' ) {
								$Results{Breakdown} .= sprintf( 'Needed %.2f feet', POSIX::ceil($vertical_length/12) );
								if ( $$Wheel{id} == $$Rule{id} ) {
									$vertical_length -= 12 * $remaining_inches;
								} # end if
								$package_qty = POSIX::ceil( ( $vertical_length / 12 ) / $$Package_Qty{value} );
							} elsif ( $$Package_Qty{units} eq 'inches' ) {
								$Results{Breakdown} .= sprintf( 'Needed %d inches', POSIX::ceil($vertical_length) );
								if ( $$Wheel{id} == $$Rule{id} ) {
									$vertical_length -= $remaining_inches;
								} # end if
								$package_qty = POSIX::ceil( $vertical_length / $$Package_Qty{value} );
							} # end if
		
							$vertical_price{Total} = Math::Round::nearest( 0.01, $vertical_price{Price} * $package_qty );
							$Results{Breakdown} .= $Vertical_Material->name().sprintf(': $%1$.2f%2$s * %4$d packages = $%3$.2f<br/>', @vertical_price{'Price','units','Total'}, $package_qty );
						} else {
							$Results{Breakdown} .= "Unknown units set on wheel price ($vertical_price{units})<br/>";
$openprint::log->error("Unknown units on ". $Vertical_Material->to_string());
						} # end if
					} else {
						$Results{Breakdown} .= 'No material for Vertical Wheel<br/>';
						#$Results{Breakdown} .= "No price set for $$Vertical_Material{name}<br/>";
					} # end if
					$totalPrice += $vertical_price{Total};
				} # end if
			} # end if Vertcail_Material == $Horizontal_Matirla

			$totalPrice = int($totalPrice);
			$Results{Breakdown} .= sprintf('Total: $%.2f<br/>', $totalPrice );

			if ( $totalPrice < $Results{Price} or ! exists $Results{Price} ) {
				$Results{Price} = $totalPrice;
				$Results{SetupPrice} = $setupPrice;
				$Results{ServicePrice} = \%servicePrice;
				$Results{HorizontalPrice} = \%horizontal_price;
				$Results{VerticalPrice} = \%vertical_price;
				$Results{Equipment} = $Equipment;
				$Results{Imposition} = $I;
				$Results{Runspeed} = $runspeed;
				$openprint::log->debug("Selected best: $I $$Equipment{strid}") if DEBUG;
			} # end if
		} # end foreach imposition
	} # end foreach equipment
	if ( $Results{Equipment} ) {
		$Results{Status} = 'calculated';
	} else {
		$Results{Status} = 'uncalculated';
	} # end if
	return %Results;
} # end sub signature_calc

sub get_specs {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();

	@{$$variable{Equipment}} = openprint::Equipment->find( 'Specifications' => {'Perforating Capable'=>['Y','When Printing']}, 'useinestimating'=>1,'order'=>'strName');

	if ( $$services{Folding} ) {
		push @{$$variable{Equipment}}, openprint::Equipment->find( 'Specifications' => {'Perforating Capable'=>'When Folding'}, 'useinestimating'=>1,'order'=>'strName');
	} # end if

} # end sub get_specs

sub fits_on_equipment {
    my ( $Equipment, $width, $height, $calliper ) = @_;

    if ( my $min_perf_size = $Equipment->specification( 'Minimum Perforation Size') ) {
		if ( $width < $min_perf_size ) {
			return "Doesn't fit width minimum";
		} # end if

		if ( $height < $min_perf_size ) {
			return "Doesn't fit height minimum";
		} # end if
	}
    if ( my $max_perf_size = $Equipment->specification('Maximum Perforation Size') ) {
		if ( $width > $max_perf_size ) {
			return "Doesn't fit width maximum";
		} # end if

		if ( $height > $max_perf_size ) {
			return "Doesn't fit height max";
		} # end if
	}
	if ( my $min_perf_calliper = $Equipment->specification( 'Minimum Perforation Calliper') ) {
		if ( $calliper < $min_perf_calliper ) {
			return "Calliper too small Calliper: ($calliper), Min: $min_perf_calliper ";
		} # end if
	} # end if
	if ( my $max_perf_calliper = $Equipment->specification('Maximum Perforation Calliper') ) {
		if ( $calliper > $max_perf_calliper ) {
			return "Calliper too big Calliper: ($calliper), Min: $max_perf_calliper ";
		} # end if
	} # end if
    return;

} # end sub fits_on_equipment

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	my $html = '';

	if ( $qty_index ) {
	} else {
		foreach my $sig_id ( $Project->signatures() ) {
			my $Service = $Project->Service( $sig_id );
			my $sig_specs = $Service->specs();
			my $form = $$sig_specs{SignatureIndex};
			next if ! ( $$specs{"txtVerticalQty-$form"} and $$specs{"txtHorizontalQty-$form"} );
			$html .= 'Form ' . $form;
			$html .= $$sig_specs{txtServiceDescription} if $$sig_specs{txtServiceDescription};
			$html .= ': ';
			$html .= sprintf('%d Vertical %d Horizontal', @$specs{"txtVerticalQty-$form","txtHorizontalQty-$form"} );
			$html .= '<br/>';
		} # end foreach
		return $html;
	} # end if

	return '';
} # end sub summary

sub save {
} # end sub save

sub has_overrides {
    my ( $Project, $service_id, $specs ) = @_;
    $specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

    my @v;
    foreach my $s_s_id ( $Project->signatures() ) {
        my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
        foreach my $qty_index ( $Project->quantity_indexes() ) {
            push @v, "chkOverrideEquipment-$$sig_specs{'SignatureIndex'}-$qty_index" if $$specs{"chkOverrideEquipment-$$sig_specs{'SignatureIndex'}-$qty_index"};
            push @v, "chkOverrideImposition-$$sig_specs{'SignatureIndex'}-$qty_index" if $$specs{"chkOverrideImposition-$$sig_specs{'SignatureIndex'}-$qty_index"};
        } # end foreach
    } # end foreach

    return @v;

} # end sub has_overrides

1;
__END__
