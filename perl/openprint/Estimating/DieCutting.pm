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

package openprint::Estimating::DieCutting;
use strict;
use warnings;
use POSIX qw( ceil );
use constant DEBUG => 0;

use vars qw( %ServicePrices %Specifications);
%ServicePrices = (
  DieCuttingMinimumCharge => { range_units => [''], units => [''] },
  DieCuttingAverageMakeReady => {range_units => [''],  units => ['', 'per hour']},
  DieCuttingSimpleMakeReady => {range_units => [''],  units => ['', 'per hour']},
  DieCuttingComplexMakeReady => {range_units => [''],  units => ['', 'per hour']},
  DieCuttingAverage => { range_units => ['calliper','impressions'], units=> ['per hour', 'per m']},
  DieCuttingSimple => { range_units => ['calliper','impressions'], units=> ['per hour', 'per m']},
  DieCuttingComplex => { range_units => ['calliper','impressions'], units=> ['per hour', 'per m']},
  DieCuttingRuleBendingSimple => { range_units => [''], units => ['per bend'] },
  DieCuttingRuleBendingAverage => { range_units => [''], units => ['per bend'] },
  DieCuttingRuleBendingComplex => { range_units => [''], units => ['per bend'] },
  KissCuttingMinimumCharge => { range_units => [''], units => [''] },
  KissCuttingAverageMakeReady => {range_units => [''],  units => ['', 'per hour']},
  KissCuttingSimpleMakeReady => {range_units => [''],  units => ['', 'per hour']},
  KissCuttingComplexMakeReady => {range_units => [''],  units => ['', 'per hour']},
  KissCuttingAverage => { range_units => ['calliper','impressions'], units=> ['per hour', 'per m']},
  KissCuttingSimple => { range_units => ['calliper','impressions'], units=> ['per hour', 'per m']},
  KissCuttingComplex => { range_units => ['calliper','impressions'], units=> ['per hour', 'per m']},
  KissCuttingRuleBendingSimple => { range_units => [''], units => ['per bend'] },
  KissCuttingRuleBendingAverage => { range_units => [''], units => ['per bend'] },
  KissCuttingRuleBendingComplex => { range_units => [''], units => ['per bend'] },
);
%Specifications = (
  RunSpeed => {range_units => ['calliper','impressions'], units=>'per hour'},
  'DieCutting Overs' => {range_units => [ 'impressions' ], units=>['percent']},
  'DieCutting Capable' => { value=>['Y','N'] },
  'DieCutting W&T'  => { value=>['Y','N'] },
  'KissCutting Overs' => {range_units => [ 'impressions' ], units=>['percent']},
  'KissCutting Capable' => { value=>['Y','N'] },
  'KissCutting W&T'  => { value=>['Y','N'] },
);

sub ServicePriceConfiguration {
  my $name = shift;
  return $ServicePrices{$name} if $ServicePrices{$name};
  foreach my $key (keys %ServicePrices) {
    return $ServicePrices{$key} if $name eq $key;
  }
  return undef;
}
sub SpecificationConfiguration {
  return $Specifications{shift};
}


require openprint::Equipment;
require openprint::service;

use vars qw( $log $dbh );
*log = \$openprint::log;
*dbh = \$openprint::dbh;

my @variables = (
	'txtQuantity1','txtQuantity2','txtQuantity3',
	'OverridePrice1','OverridePrice2','OverridePrice3',
	'Markup1','Markup2','Markup3',
	'txtPrice1','txtPrice2','txtPrice3',
	'MPrice1','MPrice2','MPrice3',
	'DiePrice1','DiePrice2','DiePrice3', 
	'OverrideDiePrice1', 'OverrideDiePrice2', 'OverrideDiePrice3',
  'hdnBreakdown1','hdnBreakdown2','hdnBreakdown3',
	'alert',
);

sub variables {
	my ( $p_id, $s_id, $old_specs, $specs ) = @_;

	my @v = @variables;
	my $Project = new openprint::Project( $p_id );
	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		my $form = $$sig_specs{SignatureIndex};
		push @v, map { "$_-$form" } ( 'txtWidth', 'txtHeight', 
			 'Complexity' ,'Needed',
			 'rdbSuppliedDie','txtDieCutPunches',
       'txtDieWidth','txtDieHeight',
        'chkOverrideDimensions',
			 'txtSteelRuleLength', 'txtDieCutBends', 'txtDueCutPunches', 'txtHoleClearingHoles' );
		foreach my $qty_index ( $Project->quantity_indexes() ) {
			push @v,map { "$_-$form-$qty_index" } (
				 'ddmEquipment', 'chkOverrideEquipment',
				 'txtImposition', 'OverrideImposition',
				 'txtLayoutWidth', 'txtLayoutHeight',
				 );
			foreach my $imp_index ( 1 .. 4 ) {
				push @v, map { join('-', $_, $form, $qty_index, $imp_index ) } ( 'ImpOut','ImpColumns','ImpRows','ImpQty' );
			} # end foreach imp_index
		} # end foreach qty_index
	} # end foreach signatures
	return @v;
} # end sub variables

my @output = (
		);

sub outputs {
	return @output;
} # end sub get_output

my @no_outputs = (
	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
	'Markup1','Markup2','Markup3',
	'txtQuantity1','txtQuantity2','txtQuantity3',
);

sub no_outputs {
	return @no_outputs;
}

sub calc_price {
  my ( $specs, $Equipment, $qty_index, $Imposition, $sig_specs, $Signature_Imposition ) = @_;

	my %Total = ( Imposition => $Imposition, Status => 'calculated', alert=>'', Total=>0, MPrice=>0 );
	my $form = $$sig_specs{SignatureIndex};
  my $complexity = $$specs{'Complexity-'.$form} || '';

	my $MakeReadyService = openprint::Service->find_one(name => 'DieCutting'.$complexity.'MakeReady');
	$MakeReadyService = openprint::Service->find_one(name => 'DieCuttingMakeReady') if (!$MakeReadyService) and $complexity;

	if ( $MakeReadyService ) {
		my $MakeReady = $MakeReadyService->get_Price( undef, $Equipment );
    if (!$$MakeReady{units}) {
			$$MakeReady{Total} = $$MakeReady{Price};
		} elsif ( $$MakeReady{units} eq 'per hour' ) {
			my $MRHours = $Equipment->Specification($$specs{ServiceType}.$complexity.'MakeReadyTime');
			$MRHours = $Equipment->Specification( $$specs{ServiceType}.'MakeReadyTime' ) if (!$MRHours) and $complexity;
			$Total{MakeReadyTime} = $MRHours;
			if ( $MRHours and $$MRHours{value} ) {
				$$MakeReady{Total} = Math::Round::nearest( 0.01, $$MakeReady{Price} * $$MRHours{value} );
			} else {
				$Total{alert} .= 'No MakeReadyTime set for ' . $$specs{ServiceType} . ' on ' . $Equipment->name() . '<br/>';
				$openprint::log->error( $Total{alert} );
				$$MakeReady{Total} = $$MakeReady{Price};
			} # end if
		} else {
      $Total{alert} .= "Unknown units $$MakeReady{units} on $$MakeReadyService{name}<br/>";
			$$MakeReady{Total} = $$MakeReady{Price};
		}
		$Total{MPrice} = 0;
		$Total{MakeReady} = $MakeReady;
		$Total{Total} += $$MakeReady{Total};
	} # en dif

	my %DiePrice;

	if ( $$specs{'rdbSuppliedDie-'.$form} and ( $$specs{'rdbSuppliedDie-'.$form} eq 'Y' ) ) {
		# if customer is supplying die, then there is no die cost.
		#$log->debug(" ** Customer is Supplying Die ** ");
	} else { 
		if ( $$sig_specs{rdbTemplateType} ) {
# check for a standard die.
			if ( my $Material = openprint::Material->find_one( name =>$$sig_specs{rdbTemplateType}.'Die') ) {
				%DiePrice = $Material->get_price( undef, $Equipment );
			} # end if
		} # end if
		if ( ( ! %DiePrice ) and $complexity ) {
			if ( my $Material = openprint::Material->find_one( name=>$complexity.'Die') ) {
				%DiePrice = $Material->get_price( undef, $Equipment );
			} # end if
		} # end if
			
		if ( ! %DiePrice ) {
      my $bends = int($$specs{'txtDieCutBends-'.$form} // 0);
      if ( $bends > 0 ) {
        my $BendingService = openprint::Service->find_one(name=>'DieCuttingRuleBending'.$complexity);
        $BendingService = openprint::Service->find_one(name=>'DieCuttingRuleBending') if ! $BendingService;
        my %BendingPrice = $BendingService->get_price($bends*$$Imposition{imposition}, undef);
        if ( %BendingPrice ) {
          $BendingPrice{bends} = $bends;
          $BendingPrice{imposition} = $$Imposition{imposition};
          $BendingPrice{Total} = $BendingPrice{Price} * $bends * $$Imposition{imposition};
          $DiePrice{BendingPrice} = \%BendingPrice;
          $DiePrice{Price} += $BendingPrice{Total};
        }
      }
#$die_price += $bending_price;
#$log->debug(" ** Adding Bending Cost: $bending_price For $$specs{txtDieCutBends} Bends, MakeReady Total: $make_ready ** ");
      if ( $$specs{'txtSteelRuleLength-'.$form} ) {
        if ( my $Material = openprint::Material->find_one( name=>'DieCuttingDieRule') ) {
          my %SteelRulePrice = $Material->get_price( $$specs{'txtSteelRuleLength-'.$form}*$$Imposition{imposition}, undef );
          if ( %SteelRulePrice ) {
            $SteelRulePrice{Total} = $SteelRulePrice{Price} * $$specs{'txtSteelRuleLength-'.$form}*$$Imposition{imposition};
            $DiePrice{Price} += $SteelRulePrice{Total};
          }
        } # end if
			} # end if
#$die_price += $steel_rule_price;
#$log->debug(" ** Adding Rule Cost: $steel_rule_price For $$specs{txtSteelRuleLength} Inches, MakeReady Total: $make_ready ** ");
#
      my $punches = int($$specs{'txtDieCutPunches-'.$form} // 0);
			if ( $punches > 0) {
##punches are optional
				if ( my $Material = openprint::Material->find_one( name=>'DieCutPunch') ) {
					my %PunchPrice = $Material->get_price( $punches*$$Imposition{imposition}, $Equipment );
					$PunchPrice{Total} = $PunchPrice{Price} * $punches * $$Imposition{imposition};
          $PunchPrice{punches} = $punches;
          $PunchPrice{imposition} = $$Imposition{imposition};
          $DiePrice{PunchPrice} = \%PunchPrice;
					$DiePrice{Price} += $PunchPrice{Total};
				} # end if
#$die_price += $punch_price;
#$log->debug(" ** Adding Punch Cost: $punch_price For $$specs{txtDieCutPunches} Punches, MakeReady Total: $make_ready ** ");
			} # end if punches
		} # end if rule & bend 
		if ( (defined $$specs{'OverrideDiePrice'.$qty_index}) and ( $$specs{'OverrideDiePrice'.$qty_index} eq 'Y' ) ) {
			$DiePrice{Price} = $$specs{'DiePrice'.$qty_index};
		} # end if
		if ( ! $DiePrice{Price} ) {
			$Total{alert} .= 'Please enter the price of the die for quantity '.$qty_index.'.<br/>';
			$Total{Status} = 'uncalculated';
		} else {
			$Total{Total} += $DiePrice{Price};
		} # end if has die price
	} #end if supplied die

	$Total{DiePrice} = \%DiePrice;

	my $impressions = ceil( ( $$specs{"txtQuantity$qty_index"} / $$Signature_Imposition{imposition} ) ) * $Imposition->quantity();
	if (my $Overs = $Equipment->Specification('DieCutting Overs')) {
		my $overs;
		if ( lc $$Overs{units} eq 'percent' ) {
			$overs = int( $impressions * ($$Overs{value}/100) );
		} elsif ( $$Overs{units} eq 'sheets' ) {
			$overs = int( $$Overs{value} );
    } else {
      $openprint::log->error("Unknown units $$Overs{units} in DieCutting Overs");
		} # end if
		$Total{Overs} = $overs;
		$impressions += $overs;
	} # end if
	$Total{Impressions} = $impressions;

  my $service_name = 'DieCutting'.$complexity;

	my %ServicePrice = openprint::service::get_price_object($service_name, $impressions, $Equipment);
	if (!%ServicePrice and $complexity) {
    $service_name = 'DieCutting';
		%ServicePrice = openprint::service::get_price_object( 'DieCutting', $impressions, $Equipment );
	} # end if

  if (!%ServicePrice) {
    $Total{alert} .= "No service price found for $service_name on $$Equipment{strid}<br/>";
    $ServicePrice{Total} = 0;
  } else {
    $ServicePrice{Total} = 0;
    if (!$ServicePrice{units}) {
      $Total{alert} .= "No units set on $ServicePrice{ServiceName}, defaulting to per 1000<br/>";
      $ServicePrice{Total} = $impressions * $ServicePrice{Price} / 1000;
    } elsif ( $ServicePrice{units} eq 'per m' or $ServicePrice{units} eq 'per 1000 impressions') {
      $ServicePrice{Total} = $impressions * $ServicePrice{Price} / 1000;
    } elsif ( $ServicePrice{units} eq 'per hour' ) {
      my $Runspeed = $Equipment->Specification('RunSpeed');
      if (!$Runspeed) {
        $Total{alert} .= 'No RunSpeed on '.$$Equipment{name}.'<br/>';
      } else {
        if (!$$Runspeed{range_units} or ($$Runspeed{range_units} eq 'calliper')) {
          $Runspeed = $Equipment->Specification('RunSpeed', $Imposition->Paper()->calliper());
        } elsif ($$Runspeed{range_units} eq 'impressions') {
          $Runspeed = $Equipment->Specification('RunSpeed', $impressions);
        } else {
          $Total{alert} .= 'Invalid range units '.$$Runspeed{range_units}. ' for Runspeed on '.$$Equipment{name}.'<br/>';
        }
        $Total{Runspeed} = $Runspeed;
        if ( $Runspeed and $$Runspeed{value} ) {
          my $hours = $impressions / $$Runspeed{value};
          $ServicePrice{Total} = Math::Round::nearest(0.01, $hours * $ServicePrice{Price});
        } elsif (!$$Runspeed{range_units} or ($$Runspeed{range_units} eq 'calliper')) {
          $Total{alert} .= 'No runspeed('.$$Runspeed{name}.') for calliper ' . $Imposition->Paper()->calliper() . ' on '  . $Equipment->name() . '<br/>';
          $openprint::log->error($Total{alert});
        } elsif ($$Runspeed{range_units} eq 'impressions') {
          $Total{alert} .= 'No runspeed for ' . $impressions . 'impressions on '  . $Equipment->name() . '<br/>';
          $openprint::log->error($Total{alert});
        } # end if
      } # end if
    } else {
      $Total{alert} .= 'Unknown units '.$ServicePrice{units}.' on service '.$ServicePrice{ServiceName}.'<br/>';
    } # end if
  } # end if

	$Total{ServicePrice} = \%ServicePrice;
	$Total{Total} += $ServicePrice{Total};
	$Total{MPrice} += ( $ServicePrice{Total} / $impressions ) * 1000;
# the extra services are priced by qty, not impressions.
#if ( $folding eq 'Y' ) {
#my $folding_price =  openprint::service::get_price( 'HandFolding'.$die_complexity ,$qty, '') / 1000; 
#$run_price += $qty * $folding_price;
#} # end fi

	if ( $$specs{'txtHoleClearingHoles-'.$form} and ( $$specs{'txtHoleClearingHoles-'.$form} > 0 ) ) {
		my $hole_qty = $$specs{'txtHoleClearingHoles-'.$form} * $$Imposition{imposition};
		my %HoleClearingPrice = openprint::service::get_price_object( 'HoleClearing', $$specs{'txtHoleClearingHoles-'.$form} * $$specs{"txtQuantity$qty_index"}, $Equipment ); 
		$HoleClearingPrice{Total} = $impressions * $HoleClearingPrice{Price} * $hole_qty;
		if ( lc $HoleClearingPrice{units} eq 'per m' ) {
			$HoleClearingPrice{Total} /= 1000;
		} # end if
		$Total{HoleClearingPrice} = \%HoleClearingPrice;
		$Total{Total} += $HoleClearingPrice{Total};
		$Total{MPrice} += ( $HoleClearingPrice{Total} * $$specs{'txtHoleClearingHoles-'.$form} / $impressions ) * 1000;
		#$$specs{'hdnBreakdown'.$qty_index} .= sprintf('&nbsp;&nbsp;Hole Clearing: $%.2f %s * %d impressions * %d holes = $%.2f<br/>', @HoleClearingPrice{'Price','units'}, $impressions, $hole_qty, $HoleClearingPrice{Total});
	} # end if

	$Total{UnitPrice} = $Total{Total} / $$specs{"txtQuantity$qty_index"} if $$specs{"txtQuantity$qty_index"};
  return %Total;
} # end sub calc_price

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $status = 'calculated';
	my $Project = new openprint::Project( $project_index );

	my @signatures_needing = ();

	$$specs{alert} = '';

	foreach my $signature_service_index ( $Project->signatures( { sort=>1 }) ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
		my $form = $$sig_specs{SignatureIndex};
	
		if ( ! $$specs{"Needed-$form"} ) {

			if ( $$sig_specs{rdbTemplateType} and sets::isin( $$sig_specs{rdbTemplateType},
          ['2Panel1Pocket', '2Panel1PocketGusset',
            '2Panel2Pocket','Panel2PocketGusset',
            'TriFoldDoublePocket', 'TriFoldDoublePocketGusset',
          ]
        ) ) {
				$$specs{"Needed-$form"} = 'Y';
			} elsif ( $Project->signatures() == 1 ) {
				$$specs{"Needed-$form"} = 'Y';
			} else {
				$$specs{"Needed-$form"} = 'N';
			} # end if
		} # end if
			
		if ( $$specs{"Needed-$form"} eq '' ) {
			$$specs{alert} .= 'Please select whether die cutting is required for signature ' . $form . '.<br/>';
			return $$specs{Status} = 'uncalculated';
		} elsif ( $$specs{"Needed-$form"} eq 'N' ) {
			next;
		} # end if
		push @signatures_needing, $signature_service_index;

		if ( exists $$specs{rdbSuppliedDie} and ! exists $$specs{'rdbSuppliedDie-'.$form} ) {
			$$specs{'rdbSuppliedDie-'.$form} = $$specs{rdbSuppliedDie};
		} # end if
		if ( $$specs{"Needed-$form"} eq 'Y' and ! $$specs{'rdbSuppliedDie-'.$form} ) {
			$$specs{alert} .= 'Please select whether the die is to be supplied by the customer or not for signature ' . $form . '.<br/>';
			return $$specs{Status} = 'uncalculated';
		} # end if

    my @complexityoptions = map { openprint::Service->find_one(name=>'DieCutting'.$_) ? $_ : () } ( 'Simple','Average', 'Complex' );
    if (@complexityoptions) {
      if ( ! $$specs{'Complexity-'.$form} ) {
        if ($$sig_specs{rdbTemplateType}) {
          if (sets::isin($$sig_specs{rdbTemplateType}, ['2Panel1Pocket', '2Panel1PocketGusset', '2Panel2Pocket','Panel2PocketGusset' ])) {
            $$specs{'Complexity-'.$form} = 'Simple';
          } elsif (sets::isin($$sig_specs{rdbTemplateType},[ 'TriFoldDoublePocket', 'TriFoldDoublePocketGusset' ])) {
            $$specs{'Complexity-'.$form} = 'Complex';
          } elsif (sets::isin($$sig_specs{rdbTemplateType},[ 'Package6Fold','Package21Fold','Package30Fold','Package51Fold' ])) {
            $$specs{'Complexity-'.$form} = 'Average';
          } elsif (sets::isin($$sig_specs{rdbTemplateType},[ 'Package62Fold','Package64Fold' ])) {
            $$specs{'Complexity-'.$form} = 'Complex';
          } else {
            $$specs{'Complexity-'.$form} = 'Average';
          }
        } # end if
      } # end if
      if (!$$specs{'Complexity-'.$form}) {
        $$specs{alert} .= 'Please select the complexity of the die.<br/>';
        return 'uncalculated';
      } # end if
    } # end if

		if ($$specs{'rdbSuppliedDie-'.$form} eq 'N') {
      if ( (!defined $$specs{'chkOverrideDimensions-'.$form}) or ( $$specs{'chkOverrideDimensions-'.$form} ne 'Y' ) ) {
        @$specs{"txtDieWidth-$form","txtDieHeight-$form"} = @$sig_specs{'txtWidth','txtHeight'};
      } # end if
      if ( ! ( $$specs{'txtDieWidth-'.$form} or $$specs{'txtDieHeight-'.$form} ) ) {
        $$specs{alert} .= 'Please enter the die dimensions.<br/>';
        return 'uncalculated';
      } # end if
# now we have to make a custom die
      if ( $$specs{'Complexity-'.$form} eq 'Simple' ) {
        $$specs{'txtSteelRuleLength-'.$form} = 6;
      } elsif ( $$specs{'Complexity-'.$form} eq 'Average' ) {
        $$specs{'txtSteelRuleLength-'.$form} = 9;
      } elsif ( $$specs{'Complexity-'.$form} eq 'Complex' ) {
        $$specs{'txtSteelRuleLength-'.$form} = 12;
      } # end if

      if ( ! $$specs{'txtSteelRuleLength-'.$form} ) {
        $log->debug(" ** Required Data Missing for Custom Die, Rule Length: $$specs{'txtSteelRuleLength-'.$form} Bends: $$specs{'txtDieCutBends-'.$form} ** ");
        return 'uncalculated';
      } # end if
    } # end if supplied die
	} # end foreach signature

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"txtQuantity$qty_index"} = $Project->quantity( $qty_index ) if ! $$specs{"txtQuantity$qty_index"};
		my $qty = $$specs{"txtQuantity$qty_index"};

		my $totalPrice = 0;
		my $totalUnitPrice = 0;
		my $totalMPrice = 0;
		my $totalDiePrice = 0;

		foreach my $signature_service_index ( @signatures_needing ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
			next if ! $$sig_specs{'txtImposition'.$qty_index};
			my $form = $$sig_specs{SignatureIndex};

			$$specs{'hdnBreakdown'.$qty_index} .= "Form $form: ".( $$sig_specs{txtServiceDescription} ? $$sig_specs{txtServiceDescription} : '' ) .'<br/>';
			my $Imposition = new openprint::Imposition();
			$Imposition->load( $sig_specs, $qty_index, $Project );
			$$specs{'hdnBreakdown'.$qty_index} .= 'Printed: ' . $Imposition->to_string() . '<br/>';

			my %results = signature_calc( $Project, $signature_service_index, $sig_specs, $specs, $qty_index, $Imposition );
			$$specs{'hdnBreakdown'.$qty_index} .= $results{breakdown} if $results{breakdown};
			$$specs{alert} .= $results{alert} if $results{alert};
			if ( $results{Equipment} ) {
				$$specs{"ddmEquipment-$form-$qty_index"} = $results{Equipment}->id();
				$$specs{'hdnBreakdown'.$qty_index} .= 'Equipment: '.$results{Equipment}->strid().'<br/>';
				#$$specs{"txtImposition-$form-$qty_index"} = $results{Imposition}->imposition();
				my $imp_index = 1;
				foreach my $Price ( @{$results{Prices}} ) {
					my $I = $$Price{Imposition};

					# This should be a different string from above, or maybe the same if it wasn't cut.
					$$specs{'hdnBreakdown'.$qty_index} .= $I->to_string() . '<br/><table>';
					if ( $$Price{MakeReady}{units} ) {
					if ( $$Price{MakeReady}{units} eq 'per hour' ) {
						$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr><td>MakeReady: $%1$.2f%2$s * %4$s%5$s = </td><td class="Price">$%3$.2f</td></tr>', @{$$Price{MakeReady}}{'Price','units','Total'}, @{$$Price{'MakeReadyTime'}}{'value','units'} );
					} else {
						$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr><td>MakeReady: $%.2f%s = </td><td class="Price">$%.2f</td></tr>', @{$$Price{MakeReady}}{'Price','units','Total'} );
					}
					} else {
						$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr><td>MakeReady: </td><td class="Price">$%.2f</td></tr>', $$Price{MakeReady}{Price});
					} # endif
					if ( $$Price{DiePrice} and $$Price{DiePrice}{Price} ) {
						$$specs{'hdnBreakdown'.$qty_index} .= '<tr><td>DiePrice: ';
            if ($$Price{DiePrice}{BendingPrice}) {
              my $bendingPrice = $$Price{DiePrice}{BendingPrice};
              $$specs{'hdnBreakdown'.$qty_index} .= sprintf('bends: $%.2f%s * %d * %dout = $%.2f',
                  @$bendingPrice{'Price','units','bends','imposition','Total'});
            }
            if ($$Price{DiePrice}{PunchPrice}) {
              my $punchPrice = $$Price{DiePrice}{PunchPrice};
              $$specs{'hdnBreakdown'.$qty_index} .= ' + ' if $$Price{DiePrice}{BendingPrice};
              $$specs{'hdnBreakdown'.$qty_index} .= sprintf('punches: $%.2f%s * %d * %d out = $%.2f',
                  @$punchPrice{'Price','units','punches','imposition','Total'});
            }
            $$specs{'hdnBreakdown'.$qty_index} .= sprintf('</td><td class="Price">$%.2f</td></tr>', $$Price{DiePrice}{Price});
						$totalDiePrice += $Price->{DiePrice}{Price};
					} else {
						$$specs{'hdnBreakdown'.$qty_index} .= '<tr><td>DiePrice: </td><td class="Price">$0.00</td></tr>';
					} # end if
          if ($$Price{ServicePrice}{Service}) {
            if ( $$Price{ServicePrice}{units} eq 'per hour' ) {
            $$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr><td>Service: $%1$.2f%2$s * (%4$d impressions (includes %6$d overs) /%5$d per hour) = </td><td class="Price">$%3$.2f</td></tr>',
              @{$$Price{ServicePrice}}{'Price','units','Total'}, $$Price{Impressions}, $$Price{Runspeed}{value}, $$Price{Overs} );
            } else {
              $$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr><td>Service: $%1$.2f%2$s * %4$d impressions = </td><td class="Price">$%3$.2f</td></tr>', @{$$Price{ServicePrice}}{'Price','units','Total'}, $$Price{Impressions} );
            } # en dif
          } # end if have service price
					$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr><td>Hole Clearing: $%1$.2f%2$s * %5$d holes * %6$dout * %4$d impressions = </td><td class="Price">$%3$.2f</td></tr>', @{$$Price{HoleClearingPrice}}{'Price','units','Total'}, $$Price{Impressions}, $$specs{"txtHoleClearingHoles-$form"}, $I->imposition() ) if exists $$Price{HoleClearingPrice};

					$totalUnitPrice += $Price->{UnitPrice};
					$totalMPrice += $Price->{MPrice};

					@$specs{
						"ImpQty-$form-$qty_index-$imp_index",
						"ImpOut-$form-$qty_index-$imp_index",
						"ImpColumns-$form-$qty_index-$imp_index",
						"ImpRows-$form-$qty_index-$imp_index"} =
						@$I{'quantity','imposition','columns','rows'};
					$imp_index += 1;
					$$specs{alert} .= $$Price{alert};
					$status = 'uncalculated' if $$Price{Status} eq 'uncalculated';
				} # end foreach Imposition
				foreach $imp_index ( $imp_index .. 4 ) {
					@$specs{
						"ImpQty-$form-$qty_index-$imp_index",
						"ImpOut-$form-$qty_index-$imp_index",
						"ImpColumns-$form-$qty_index-$imp_index",
						"ImpRows-$form-$qty_index-$imp_index"} = ('','','','');
				} # end foreach $imp_index

				$totalPrice += $results{Total};


				if ( $$specs{'Markup'.$qty_index} ) {
					$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr class="totals"><td>Total: $%.2f * %s%% = </td><td class="Price">$%.2f</td></tr>', $results{Total},$$specs{'Markup'.$qty_index}, $totalPrice*(1+$$specs{'Markup'.$qty_index}/100));
				} else {
					$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr class="totals"><td>Total:</td><td class="Price">$%.2f</td></tr>', $results{Total} );
				} # end if
				$$specs{'hdnBreakdown'.$qty_index} .= '</table>';
			} # end if Equipment
		} # end foreach Signature
	
		if ( ( !defined $$specs{'OverrideDiePrice'.$qty_index}) or ($$specs{'OverrideDiePrice'.$qty_index} ne 'Y') ) {
			$$specs{"DiePrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $totalDiePrice );
		} # end if
		if ( $$specs{'Markup'.$qty_index} ) {
			my $markup_amount = (1+$$specs{'Markup'.$qty_index}/100);
			$totalPrice *= $markup_amount;
			$totalUnitPrice *= $markup_amount;
			$totalMPrice *= $markup_amount;
		} # end if
		if ( $Project->markup() ) {
			my $markup_amount = (1+$Project->markup()/100);
			$totalPrice *= $markup_amount;
			$totalUnitPrice *= $markup_amount;
			$totalMPrice *= $markup_amount;
		} 
		if ( (!defined $$specs{'OverridePrice'.$qty_index}) or ( $$specs{'OverridePrice'.$qty_index} ne 'Y' ) ) {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $totalPrice );
			@no_outputs = sets::exclude( ["txtPrice$qty_index"], \@no_outputs );
		} else {
			@no_outputs = sets::union( "txtPrice$qty_index", @no_outputs );
		} # end if
		$$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $totalUnitPrice );
		$$specs{"MPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $totalMPrice );

	} # end foreach qty

	return $status;
} # end sub calc

sub signature_needs {
	my ( $Project, $specs, $sig_specs ) = @_;
	my $form = $$sig_specs{SignatureIndex};
#$log->debug("Diecutting::signatureNeeds: for sig $form : Needed: ($$specs{'Needed-'.$form})" );
	if ( ! $$specs{"Needed-$form"} ) {
		if ( $$sig_specs{rdbTemplateType} and sets::isin( $$sig_specs{rdbTemplateType}, ['2Panel1Pocket','2Panel2Pocket','TriFoldDoublePocket'] ) ) {
			return 1;
		} # end if
		my $ServiceType = openprint::ServiceType->find_one(type=>'DieCutting');
		if ( $ServiceType ) {
			if ( sets::isin( $ServiceType->id(), [ $Project->Type()->required_services() ] ) ) {
				return 1;
			} # end if
		} else {
			$openprint::log->error("No ServiceType for DieCutting");
		}
	} # end if
	return ($$specs{"Needed-$form"} and ( $$specs{"Needed-$form"} eq 'Y' ) ) ? 1 : 0;
} # end sub signature_needs

sub signature_calc {
	my ( $Project, $signature_service_index, $sig_specs, $specs, $qty_index, $Imposition ) = @_;

	my $form = $$sig_specs{SignatureIndex};

	@$specs{"txtWidth-$form", "txtHeight-$form"} = @$sig_specs{'txtWidth','txtHeight'};

	my %results = ( Status=>'uncalculated' );

	my @equipment;
	if ( (defined $$specs{"chkOverrideEquipment-$form-$qty_index"}) and ( $$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' ) ) {
		@equipment = ( new openprint::Equipment( $$specs{"ddmEquipment-$form-$qty_index"} ) );
	} else {
		@equipment = openprint::Equipment->find( useinestimating=>1, Specifications=>{'DieCutting Capable'=>'Y'} );
	} # end if
  if (!@equipment) {
    $results{alert} .= 'No equipment was found for die cutting.<br/>';
    $results{Status} = 'uncalculated';
    return %results;
  }

	my $services = $Project->services();
	my @Sets_of_Impositions;

	if ( (defined $$specs{"OverrideImposition-$form-$qty_index"}) and ( $$specs{"OverrideImposition-$form-$qty_index"} eq 'Y' ) ) {
		$openprint::log->debug("Overriding impositions") if DEBUG;

		my @override_impos;
		foreach my $index ( 1 .. 4 ) {
			next if ! $$specs{"ImpQty-$form-$qty_index-$index"};
			my $I = $Imposition->copy();
			$I->quantity( $$specs{"ImpQty-$form-$qty_index-$index"} );
			$I->imposition( $$specs{"ImpOut-$form-$qty_index-$index"} );
			$I->columns( $$specs{"ImpColumns-$form-$qty_index-$index"} );
			$I->rows( $$specs{"ImpRows-$form-$qty_index-$index"} );
			$I->Paper( $Imposition->Paper() );
			push @override_impos, $I;
			$I->display('Override');
		} # end foreach
		@Sets_of_Impositions = ( \@override_impos );
		my $overriden_count = misc::sum( map { $_->quantity() * $_->imposition() } @override_impos );
		if ( $overriden_count != $Imposition->quantity() * $Imposition->imposition() ) {
			$results{alert} .= "Overriden imposition count ($overriden_count) does not match printed imposition count (".$Imposition->quantity() * $Imposition->imposition().") for form $form quantity $qty_index (".$$specs{"txtQuantity$qty_index"}.").<br/>";
		} else {
			$openprint::log->debug(" override count: $overriden_count $$Imposition{quantity} * $$Imposition{imposition}");
		} # end if
	} else {
		@Sets_of_Impositions = ( [ $Imposition ] );
	} # end if Overrides

	foreach my $Equipment ( @equipment ) {
		if ( $$specs{"txtHoleClearingHoles-$form"} and ( $$specs{"txtHoleClearingHoles-$form"} > 0 ) and 
        ( ( $_ = $Equipment->specification('HoleClearing Capable') ) and ( $_ ne 'Y' ) ) ) {
			$results{breakdown} .= 'Doesnt do hole clearing.<br/>';
			next;
		} # end if

		for ( my $Set_index = 0; $Set_index < @Sets_of_Impositions; $Set_index += 1 ) {
			my $Set_of_Impositions =  $Sets_of_Impositions[$Set_index];
			my @Impositions = openprint::imposition::sort( @{$Set_of_Impositions} );

			my %price = (Prices => [], Status=>'uncalculated');
			my $complete = 1;
			for( my $impo_index = 0; $impo_index < @Impositions; $impo_index += 1 ) {
				my $imposition = $Impositions[$impo_index];

				my $width = $imposition->layout_width();
				my $height = $imposition->layout_height();
				if ( $_ = $Equipment->fits( $width, $height, $$sig_specs{txtSpecificStockCalliper} ) ) {
          $openprint::log->debug("Reason $$Equipment{name} $_");
					if ( 1 == @equipment and $$specs{"OverrideImposition-$form-$qty_index"}) {
						$results{breakdown} .= "Doesn't fit. $_<br/>";
					} # end if
					if ( ( $$imposition{imposition} > 1 ) and ! $$specs{"OverrideImposition-$form-$qty_index"} ) {
            my @cuts = openprint::imposition::cut( $imposition );
            if ( @cuts ) {
              splice ( @Impositions, $impo_index, 1, @cuts );
              push @Sets_of_Impositions,  \@Impositions;
            }
					} # end if
					$complete = 0;
					last;
				} # end if
        if ($$imposition{runstyle} eq 'Work & Turn' or $$imposition{runstyle} eq 'Work & Tumble') {
          my $do_wt = $Equipment->specification('DieCutting W&T');
          if ($do_wt and $do_wt eq 'N') {
            my @cuts = openprint::imposition::cut( $imposition );
            if ( @cuts ) {
              splice ( @Impositions, $impo_index, 1, @cuts );
              push @Sets_of_Impositions,  \@Impositions;
            }
            $complete = 0;
            last;
					} # end if
        }
				my %p = calc_price( $specs, $Equipment, $qty_index, $imposition, $sig_specs, $Imposition );
        if ($p{Status} eq 'uncalculated') {
          $price{Status} = 'uncalculated';
          #$imposition->display('uncalculated');
        }
				push @{$price{Prices}}, \%p;
				$price{Total} += $p{Total};
			} # end foreach imposition

      if (!$complete) {
        $openprint::log->debug("Incomplete") if DEBUG;
        next 
      }

			if (
        (! $results{Total}) or ( ($price{Total} < $results{Total}) and ($price{Status} ne 'uncalculated' or $results{Status} eq 'uncalculated') )) {
				$results{Equipment} = $Equipment;
				@{$results{Prices}} = @{$price{Prices}};
				$results{Overs} = $price{Overs};
				$results{Total} = $price{Total};
        $results{Status} = $price{Status};
      } else {
        $openprint::log->debug("Not using $price{Status}");
			} # end if

		} # end foreach sets_of_impositions
	} # end foreach equipment
	return %results;
} # end sub signature_calc

sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;	

	$$variable{Equipment} = [ openprint::Equipment->find(order=>'lower(strname)', useinestimating=>1,Specifications=>{'DieCutting Capable'=>'Y'} ) ];

	if ( $$variable{rdbTemplateTypePresentationFolderStandard1Pocket} or $$variable{rdbTemplateTypePresentationFolderStandard2Pocket} ) {
		$$variable{ShowPresentationFolderDieCutting} = 'Y';
	} # end if

} # end sub display

sub signature_summary {
  my ( $Project, $service_index, $specs, $qty_index, $s_id, $sig_specs ) = @_;
  $specs = openprint::service::get_specs_ref( $Project, $service_index ) if ! $specs;
  $sig_specs = openprint::service::get_specs_ref( $Project, $s_id ) if ! $sig_specs;
  my $form = $$sig_specs{SignatureIndex};
  if ( $qty_index ) {
    if ( ! $$sig_specs{"txtImposition$qty_index"} ) {
      return '';
    } # end if
    if ($$specs{'Needed-'.$form} and ($$specs{'Needed-'.$form} eq 'Y')) {
      my @folds;
      my $Equipment = new openprint::Equipment( $$specs{"ddmEquipment-$form-$qty_index"} );
      foreach my $imp_index ( 1 .. 4 ) {
        next if ! $$specs{"ImpQty-$form-$qty_index-$imp_index"};
        push @folds, sprintf('%1$d @ %2$dout', @$specs{"ImpQty-$form-$qty_index-$imp_index","ImpOut-$form-$qty_index-$imp_index"},
        );
      } # end foreach
      return join('<br/>', ( ' on ' . $Equipment->name() ), sort { $a cmp $b } @folds) if @folds;
    }
  } # end if
} # end sub signature_summary

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	#$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	if ( $qty_index ) {
		my $html;
        my @signatures = $Project->signatures( { sort=>1 } );

        for ( my $sig_index = 0; $sig_index < @signatures; $sig_index += 1 ) {
            my $s_s_id = $signatures[$sig_index];
            my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
            my $form = $$sig_specs{SignatureIndex};
			if ( ! $$sig_specs{"txtImposition$qty_index"} ) {
				next;
			} # end if
            my $sig_count = 1;

            if ( $sig_index < @signatures - 1 ) {
                for ( my $sig_index2 = $sig_index + 1; $sig_index2 < @signatures; $sig_index2 += 1 ) {
                    my $sig_specs2 = openprint::service::get_specs_ref( $Project, $signatures[$sig_index2] );
                    if ( openprint::Estimating::Printing::compare_signatures( $Project, $sig_specs, $sig_specs2, $qty_index ) ) {
                        $sig_count += 1;
                    } else {
                        last;
                    } # end if
                } # end for
                splice @signatures, $sig_index+1,$sig_count-1 if $sig_count > 1;
            }
            my $summary = signature_summary( $Project, $service_id, undef, $qty_index, $s_s_id, undef );
            if ( $sig_count > 1 ) {
                $html .= ($sig_count) . ' Forms';
            } else {
                $html .= 'Form ' . $form;
            } # end if
			if ( $$sig_specs{txtServiceDescription} ) {
				$html .= ' ' . $$sig_specs{txtServiceDescription};
			}
			$html .= $summary . "\n";
        } # end foreach
        return $html;
	} else {
		my $summary;
		my $Owner = new openprint::Company( $openprint::config{owner_id} );
		my @signatures = $Project->signatures();

		foreach my $signature ( @signatures ) {
			my $Service = $Project->Service($signature);
			my $sig_specs = $Service->specs();
			my $form = $$sig_specs{SignatureIndex};

      if ($$specs{'Needed-'.$form} and ($$specs{'Needed-'.$form} eq 'Y')) {
        if ( (defined $$specs{'rdbSuppliedDie-'.$form} ) and ( $$specs{'rdbSuppliedDie-'.$form} eq 'Y' ) ) {
          $summary .= 'Customer supplies die' . ( @signatures > 1 ? ' for form '.$form : '' ).'<br/>';
        } else {
          $summary .= $Owner->name() . ' supplies die'.( @signatures > 1 ? ' for form '.$form : '' ).'<br/>';
        } # end if
			} # end if
		} # end foreach
		return $summary;
	} # end if

	return '';
} # end sub summary

sub save {
} # end sub save

sub has_overrides {
    my ( $Project, $service_id, $specs, $qty_index ) = @_;
    $specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

    my @v;
    if ( $qty_index ) {
        foreach my $s_s_id ( $Project->signatures() ) {
            my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
            my $form = $$sig_specs{SignatureIndex};
            push @v, map { ( $$specs{$_} and ( $$specs{$_} ne 'N' ) ) ? $_ : () } (
                    "chkOverrideEquipment-$form-$qty_index",
                    "OverrideImposition-$form-$qty_index",
                    "OverrideMakeReadyPrice-$form-$qty_index",
                    "OverridePrice$qty_index",
                    "OverrideDiePrice-$form-$qty_index",
                    "OverrideServicePrice-$form-$qty_index",
                    );
        } # end foreach sig
    } # end if

    return @v;

} # end sub has_overrides

sub neccessary {
	my ( $Project ) = @_;
  foreach my $service_type ( $Project->Type()->required_ServiceTypes()) {
    return 1 if $service_type->type() eq 'DieCutting';
  }
  foreach my $signature_service_index ( $Project->signatures( { sort=>1 }) ) {
    my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
    my $form = $$sig_specs{SignatureIndex};

    if ( $$sig_specs{rdbTemplateType} and sets::isin( $$sig_specs{rdbTemplateType},
        ['2Panel1Pocket', '2Panel1PocketGusset',
          '2Panel2Pocket','Panel2PocketGusset',
          'TriFoldDoublePocket', 'TriFoldDoublePocketGusset',
        ]
      ) ) {
      return 1;
    }
  } # end foreach sig

	return 0;
} # end sub neccessary

sub load_Impositions {
  my ( $Imposition, $specs, $form, $qty_index ) = @_;

  my @impos;
  my @results;
  foreach my $imp_index ( 1 .. 4 ) {
    next if ! $$specs{"ImpQty-$form-$qty_index-$imp_index"};

    my $imp = $Imposition->copy();
    $imp->columns( $$specs{"ImpColumns-$form-$qty_index-$imp_index"} );
    $imp->rows( $$specs{"ImpRows-$form-$qty_index-$imp_index"} );
    my $paper = $$imp{Paper};
    $paper->width( $$paper{width} / ($$Imposition{columns} / $$imp{columns}));
    $paper->height( $$paper{height} / ($$Imposition{rows} / $$imp{rows}));


    #$imp->type( $$specs{"ImpType-$form-$qty_index-$imp_index"} );
    #my ( $pages ) = $$specs{"ImpType-$form-$qty_index-$fold_index"} =~ /^(\d+)PageFold$/;
    #$imp->pages( $pages );
    $imp->quantity( $$specs{"ImpQty-$form-$qty_index-$imp_index"} );
    $imp->display("impressions: ".$imp->impressions());
    $imp->impressions($imp->impressions() * ($$Imposition{imposition}/$$imp{imposition}));
    push @impos, $imp;
  } # end foreach imp_index
  my $quantity = $$specs{"txtQuantity$qty_index"};

  #if ( @impos == 1 ) {
    #$impos[0]{impressions} = int( $quantity / $impos[0]{imposition} );
    #$impos[0]{impressions} = int( $quantity / ( $impos[0]{quantity} * $impos[0]{imposition} ) );
    #} else {
    #my $parts = misc::sum( map { $$_{imposition} * $$_{quantity} } @impos );
    #foreach my $I ( @impos ) {
      #$$I{impressions} = int( ($quantity / $parts ) * $$_{imposition} * $$_{quantity} );
      #$$I{impressions} = int( ($quantity / $parts ) * $$_{imposition} * $$_{quantity} );
      #} # end foreach I
      #} # end if
  return @impos;
} # end sub load_Impositions

1;
__END__
