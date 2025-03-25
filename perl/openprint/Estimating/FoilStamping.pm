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

package openprint::Estimating::FoilStamping;
use strict;
use warnings;
use POSIX qw( ceil );
use constant DEBUG => 1;

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
			 'FoilStamping' ,'Needed', 'MakeReadyComplexity',
			 'rdbSuppliedDie','Foil',
       'txtDieWidth','txtDieHeight',
       'chkOverrideDimensions',
			 );
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

	my %Total = ( Imposition => $Imposition, Status => 'calculated', alert=>'' );
	my $form = $$sig_specs{SignatureIndex};

	my $MakeReadyService = openprint::Service->find_one( name => 'FoilStamping'.$$specs{'MakeReadyComplexity-'.$form}.'MakeReady' ) if $$specs{'MakeReadyComplexity-'.$form};
	$MakeReadyService = openprint::Service->find_one( name => 'FoilStamping'.$$specs{'rdbFoilStamping-'.$form}.'MakeReady' ) if (!$MakeReadyService) and $$specs{'rdbFoilStamping-'.$form};
	$MakeReadyService = openprint::Service->find_one( name => 'FoilStampingMakeReady' ) if ! $MakeReadyService;

	if ( $MakeReadyService ) {
		my $MakeReady = $MakeReadyService->get_Price( undef, $Equipment );
		if ( $$MakeReady{units} eq 'per hour' ) {
			my $MRHours = $Equipment->Specification( $$specs{ServiceType}.$$specs{'MakeReadyComplexity-'.$form}.'MakeReadyTime' ) if $$specs{'MakeReadyComplexity-'.$form};
			$MRHours = $Equipment->Specification( $$specs{ServiceType}.'MakeReadyTime' ) if !$MRHours;
			$Total{MakeReadyTime} = $MRHours;
			if ( $MRHours and $$MRHours{value} ) {
				$$MakeReady{Total} = Math::Round::nearest( 0.01, $$MakeReady{Price} * $$MRHours{value} );
			} else {
				$Total{alert} .= 'No MakeReadyTime set for ' . $$specs{ServiceType} . ' on ' . $Equipment->name() . '<br/>';
				$openprint::log->error( $Total{alert} );
				$$MakeReady{Total} = $$MakeReady{Price};
			} # end if
		} else {
			$$MakeReady{Total} = $$MakeReady{Price};
		}
		$Total{MPrice} = 0;
		$Total{MakeReady} = $MakeReady;
		$Total{Total} += $$MakeReady{Total};
	} # en dif

	my %DiePrice;

	if ( $$specs{'rdbSuppliedDie-'.$form} eq 'Y' ) {
		# if customer is supplying die, then there is no die cost.
		#$log->debug(" ** Customer is Supplying Die ** ");
	} else { 
		if ( $$sig_specs{rdbTemplateType} ) {
# check for a standard die.
			if ( my $Material = openprint::Material->find_one( name =>$$sig_specs{rdbTemplateType}.'Die') ) {
				%DiePrice = $Material->get_price( undef, $Equipment );
			} # end if
		} # end if
		if ( ( ! %DiePrice ) and $$specs{'rdbFoilStamping-'.$form} ) {
			if ( my $Material = openprint::Material->find_one( name=>'FoilStamping'.$$specs{'rdbFoilStamping-'.$form}.'Die') ) {
				%DiePrice = $Material->get_price( undef, $Equipment );
			} # end if
		} # end if
		if ( ! %DiePrice ) {
			if ( my $Material = openprint::Material->find_one( name=>'FoilStampingDie') ) {
                %DiePrice = $Material->get_price( undef, $Equipment );
            } # end if
		}
			
		if ( (defined $$specs{'OverrideDiePrice'.$qty_index}) and ( $$specs{'OverrideDiePrice'.$qty_index} eq 'Y' ) ) {
			$DiePrice{Price} = $$specs{'DiePrice'.$qty_index};
		} # end if
		if ( ! $DiePrice{Price} ) {
			$Total{alert} .= 'Please enter the price of the die.<br/>';
			$Total{Status} = 'uncalculated';
		} else {
			$Total{Total} += $DiePrice{Price};
		} # end if has die price
	} #end if supplied die

	$Total{DiePrice} = \%DiePrice;

	my $impressions = ceil( ( $$specs{"txtQuantity$qty_index"} / $$Signature_Imposition{imposition} ) ) * $Imposition->quantity();
	
	if ( my $Overs = $Equipment->Specification('FoilStamping Overs') ) {
		my $overs;
		if ( $$Overs{units} eq 'Percent' ) {
			$overs = int( $impressions * ($$Overs{value}/100) );
		} elsif ( $$Overs{units} eq 'Sheets' ) {
			$overs = int( $$Overs{value} );
		} # end if
		$Total{Overs} = $overs;
		$impressions += $overs;
	} # end if
	$Total{Impressions} = $impressions;

# this is the price for actual embossing, priced by impressions.
	my $Service = openprint::Service->find_one( name=>'FoilStamping'.$$specs{'rdbFoilStamping-'.$form} );
	$Service = openprint::Service->find_one( name=>'FoilStamping' ) if ! $Service;

	my %ServicePrice = $Service->get_price( $impressions, $Equipment );
	if ( $ServicePrice{units} eq 'per m' ) {
		$ServicePrice{Total} = $impressions * $ServicePrice{Price} / 1000;
	} elsif ( $ServicePrice{units} eq 'per hour' ) {
		my $Runspeed = $Equipment->Specification('Runspeed', $Imposition->Paper()->calliper());
		$Total{Runspeed} = $Runspeed;
		if ( $Runspeed and $$Runspeed{value} ) {
			my $hours = $impressions / $$Runspeed{value};
			$ServicePrice{Total} = Math::Round::nearest( 0.01, $hours * $ServicePrice{Price} );
		} else {
			$Total{alert} .= 'No runspeed for calliper ' . $Imposition->Paper()->calliper() . ' on '  . $Equipment->name() . '<br/>';
			$openprint::log->error($$specs{alert});
		} # end if
	} elsif ( $ServicePrice{units} eq 'per impression' ) {
		$ServicePrice{Total} = $impressions * $ServicePrice{Price};
	} else {
		$$specs{alert} .= "Invalid units on Service price for $$Service{name}<br/>";
	} # end if

	$Total{ServicePrice} = \%ServicePrice;
	$Total{Total} += $ServicePrice{Total};
	$Total{MPrice} += ( $ServicePrice{Total} / $impressions ) * 1000;


	if ( $$specs{Foil} ) {
		my $Material = openprint::Material->find_one(name=>$$specs{Foil} );
		if ($Material ) {
			my %FoilPrice = $Material->get_price( $impressions );
			if ( %FoilPrice ) {
				if ( $FoilPrice{units} eq 'per m' ) {
					$FoilPrice{Total} = $FoilPrice{Price} * $impressions / 1000;
				} elsif ( $FoilPrice{units} eq 'each' ) {
					$FoilPrice{Total} = $FoilPrice{Price} * $impressions;
				} else {
					$Total{alert} .= "Invalid units on Foil price<br/>";
				}
				$Total{FoilPrice} = \%FoilPrice;
				$Total{Total} += $FoilPrice{Total};
				$Total{MPrice} += ( $FoilPrice{Total} / $impressions ) * 1000;
			} else {
				$Total{alert} .= "No price found for $impressions on $$Material{name}<br/>";
			}
		} else {
			$Total{alert} .= "Foil material not found.<br/>";
		}
	}

	$Total{UnitPrice} = $Total{Total} / $$specs{"txtQuantity$qty_index"} if $$specs{"txtQuantity$qty_index"};
    return %Total;

} # end sub calc_price

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $status = 'calculated';
	my $Project = new openprint::Project( $project_index );
  my $ServiceType = $Project->ServiceType($service_index);

	my @signatures_needing = ();

	$$specs{alert} = '';

	foreach my $signature_service_index ( $Project->signatures( { sort=>1 }) ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
		my $form = $$sig_specs{SignatureIndex};
	
		if ( ! $$specs{"Needed-$form"} ) {
			if ( sets::isin( $$sig_specs{rdbTemplateType}, ['2Panel1Pocket','2Panel2Pocket','TriFoldDoublePocket'] ) ) {
				$$specs{"Needed-$form"} = 'Y';
			} elsif ( $Project->signatures() == 1 ) {
				$$specs{"Needed-$form"} = 'Y';
			} else {
				$$specs{"Needed-$form"} = 'N';
			} # end if
		} # end if
			
		if ( $$specs{"Needed-$form"} eq '' ) {
			$$specs{alert} .= 'Please select whether embossing is required for signature ' . $form . '.<br/>';
			return $$specs{Status} = 'uncalculated';
		} elsif ( $$specs{"Needed-$form"} eq 'N' ) {
			next;
		} # end if
		push @signatures_needing, $signature_service_index;

		if ( exists $$specs{rdbSuppliedDie} and ! exists $$specs{'rdbSuppliedDie-'.$form} ) {
			$$specs{'rdbSuppliedDie-'.$form} = $$specs{rdbSuppliedDie};
		} # end if
		if ( ! $$specs{'rdbSuppliedDie-'.$form} ) {
			$$specs{alert} .= 'Please select whether the die is to be supplied by the customer or not for signature ' . $form . '.<br/>';
			return $$specs{Status} = 'uncalculated';
		} # end if
		if ( ! $$specs{'rdbFoilStamping-'.$form} ) {
			if ( $$sig_specs{rdbTemplateType} eq '2Panel2Pocket' ) {
				$$specs{'rdbFoilStamping-'.$form} = 'Average';
			} elsif ( $$sig_specs{rdbTemplateType} eq '2Panel1Pocket' ) {
				$$specs{'rdbFoilStamping-'.$form} = 'Simple';
			} else {
				$$specs{'rdbFoilStamping-'.$form} = 'Complex';
			} # end if
		} # end if
		if ( ( $$specs{'rdbSuppliedDie-'.$form} eq 'N' ) and ( ! $$specs{'rdbFoilStamping-'.$form} ) ) {
			$$specs{alert} .= 'Please select the complexity of the die.<br/>';
			return 'uncalculated';
		} # end if
		if ( (!defined $$specs{'chkOverrideDimensions-'.$form}) or ( $$specs{'chkOverrideDimensions-'.$form} ne 'Y' ) ) {
			@$specs{"txtDieWidth-$form","txtDieHeight-$form"} = @$sig_specs{'txtWidth','txtHeight'};
		} # end if
		if ( ! ( $$specs{'txtDieWidth-'.$form} or $$specs{'txtDieHeight-'.$form} ) ) {
			$$specs{alert} .= 'Please enter the die dimensions.<br/>';
			return 'uncalculated';
		} # end if
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

			$$specs{'hdnBreakdown'.$qty_index} .= "Form $form: ".($$sig_specs{txtServiceDescription} ? $$sig_specs{txtServiceDescription}: '').'<br/>';
			my $Imposition = new openprint::Imposition();
			$Imposition->load( $sig_specs, $qty_index, $Project );
			$$specs{'hdnBreakdown'.$qty_index} .= 'Printed: ' . $Imposition->to_string() . '<br/>';

			my %results = signature_calc( $Project, $ServiceType, $signature_service_index, $sig_specs, $specs, $qty_index, $Imposition );
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
					if ( $$Price{DiePrice} ) {
						$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr><td>DiePrice: </td><td class="Price">$%.2f</td></tr>', $$Price{DiePrice}{Price});
						$totalDiePrice += $Price->{DiePrice}{Price};
					} # end if
					if ( $$Price{ServicePrice}{units} eq 'per hour' ) {
					$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr><td>Service: $%1$.2f%2$s * (%4$d impressions/%5$d per hour) = </td><td class="Price">$%3$.2f</td></tr>', @{$$Price{ServicePrice}}{'Price','units','Total'}, $$Price{Impressions}, $$Price{Runspeed}{value} );
					} else {
						$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr><td>Service: $%1$.2f%2$s * %4$d impressions = </td><td class="Price">$%3$.2f</td></tr>', @{$$Price{ServicePrice}}{'Price','units','Total'}, $$Price{Impressions} );
					} # end if
					if ( $$Price{FoilPrice} ) {
						$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr><td>%5$s: $%1$.2f%2$s * %4$d impressions = </td><td class="Price">$%3$.2f</td></tr>', @{$$Price{FoilPrice}}{'Price','units','Total'}, $$Price{Impressions}, $$specs{Foil} );
					}

					$totalUnitPrice += $Price->{UnitPrice};
					$totalMPrice += $Price->{MPrice};

					@$specs{
						"ImpQty-$form-$qty_index-$imp_index",
						"ImpOut-$form-$qty_index-$imp_index",
						"ImpColumns-$form-$qty_index-$imp_index",
						"ImpRows-$form-$qty_index-$imp_index"} =
						$I->get('quantity','imposition','columns','rows');
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
		if ( sets::isin( $$sig_specs{rdbTemplateType}, ['2Panel1Pocket','2Panel2Pocket','TriFoldDoublePocket'] ) ) {
			return 1;
		} # end if
		my $ServiceType = openprint::ServiceType->find_one(type=>'FoilStamping');
		if ( $ServiceType ) {
			if ( sets::isin( $ServiceType->id(), [ $Project->Type()->required_services() ] ) ) {
				return 1;
			} # end if
		} else {
			$openprint::log->error("No ServiceType for FoilStamping");
		}
	} # end if
	return $$specs{"Needed-$form"} eq 'Y' ? 1 : 0;
} # end sub signature_needs

sub signature_calc {
	my ( $Project, $ServiceType, $signature_service_index, $sig_specs, $specs, $qty_index, $Imposition ) = @_;

	my $form = $$sig_specs{SignatureIndex};

	@$specs{"txtWidth-$form", "txtHeight-$form"} = @$sig_specs{'txtWidth','txtHeight'};

	my %results = ( Status=>'uncalculated' );

	my @equipment;
	if ( (defined $$specs{"chkOverrideEquipment-$form-$qty_index"}) and ( $$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' ) ) {
		@equipment = ( new openprint::Equipment( $$specs{"ddmEquipment-$form-$qty_index"} ) );
	} else {
		@equipment = openprint::Equipment->find( useinestimating=>1, 'servicetype_id any'=>$ServiceType->id(), 
#Specifications=>{'Die Cutting Capable'=>'Y'}
        );
	} # end if

	my $services = $Project->services();
	my @Sets_of_Impositions;

	if ( (defined $$specs{"OverrideImposition-$form-$qty_index"}) and ( $$specs{"OverrideImposition-$form-$qty_index"} eq 'Y' ) ) {
		$openprint::log->debug("Overriding impositions");

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
		for ( my $Set_index = 0; $Set_index < @Sets_of_Impositions; $Set_index += 1 ) {
			my $Set_of_Impositions =  $Sets_of_Impositions[$Set_index];
			my @Impositions = openprint::imposition::sort( @{$Set_of_Impositions} );

			my %price;
			$price{Prices} = [];
			my $complete = 1;
			for( my $impo_index = 0; $impo_index < @Impositions; $impo_index += 1 ) {
				my $imposition = $Impositions[$impo_index];

				my $width = $imposition->layout_width();
				my $height = $imposition->layout_height();
				if ( $_ = $Equipment->fits( $width, $height, $$sig_specs{txtSpecificStockCalliper} ) ) {
					if ( 1 == @equipment ) {
						$results{breakdown} .= "Doesn't fit. $_<br/>";
					} # end if
					if ( $$imposition{imposition} > 1 and ! $$specs{"OverrideImposition-$form-$qty_index"} ) {
            my @cut = openprint::imposition::cut( $imposition );
            if ( @cut ) {
              splice ( @Impositions, $impo_index, 1, openprint::imposition::cut( $imposition ) );
              push @Sets_of_Impositions,  \@Impositions;
            }
					} # end if
					$complete = 0;
					last;
				} # end if
				my %p = calc_price( $specs, $Equipment, $qty_index, $imposition, $sig_specs, $Imposition );
				push @{$price{Prices}}, \%p;
				$price{Total} += $p{Total};
			} # end foreach imposition
			next if ! $complete;

			if ( (! $results{Total} ) or ( $price{Total} < $results{Total} ) ) {
				$results{Equipment} = $Equipment;
				@{$results{Prices}} = @{$price{Prices}};
				$results{Overs} = $price{Overs};
				$results{Total} = $price{Total};
			} # end if

		} # end foreach sets_of_impositions
	} # end foreach equipment
	$results{Status} = 'calculated' if $results{Equipment};
	return %results;
} # end sub signature_calc

sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;	

	my $ServiceType = openprint::ServiceType->find_one(type=>'FoilStamping');
	$$variable{Equipment} = [ openprint::Equipment->find(order=>'lower(strname)', useinestimating=>1,'servicetype_id @>'=>$ServiceType->id() ) ];
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
        my @folds;
        my $Equipment = new openprint::Equipment( $$specs{"ddmEquipment-$form-$qty_index"} );
        foreach my $imp_index ( 1 .. 4 ) {
            next if ! $$specs{"ImpQty-$form-$qty_index-$imp_index"};
            push @folds, sprintf('%1$d @ %2$dout', @$specs{"ImpQty-$form-$qty_index-$imp_index","ImpOut-$form-$qty_index-$imp_index"},
					);
        } # end foreach
        return join('<br/>', ( ' on ' . $Equipment->name() ), sort { $a cmp $b } @folds);
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
                $html .= ($sig_count) . ' Forms ' . $$sig_specs{txtServiceDescription} ;
            } else {
                $html .= 'Form ' . $form . ' ' . $$sig_specs{txtServiceDescription};
            } # end if
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

			if ( (defined $$specs{'rdbSuppliedDie-'.$form} ) and ( $$specs{'rdbSuppliedDie-'.$form} eq 'Y' ) ) {
				$summary .= 'Customer supplies die' . ( @signatures > 1 ? ' for form '.$form : '' ).'<br/>';
			} else {
				$summary .= $Owner->name() . ' supplies die'.( @signatures > 1 ? ' for form '.$form : '' ).'<br/>';
			} # end if
			if ( $$specs{"Foil-$form"} ) {
				$summary .= 'with ' . $$specs{"Foil-$form"} . '<br/>';
			}
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
            push @v, map { $$specs{$_} ? $_ : () } (
                    "chkOverrideEquipment-$form-$qty_index",
                    "chkOverrideImposition-$form-$qty_index",
                    "OverrideMakeReadyPrice-$form-$qty_index",
                    "OverridePrice-$form-$qty_index",
                    "OverrideDiePrice-$form-$qty_index",
                    "OverrideServicePrice-$form-$qty_index",
                    );
        } # end foreach sig
    } # end if

    return @v;

} # end sub has_overrides

sub neccessary {
	my ( $Project ) = @_;
	return 0;
} # end sub neccessary

1;
__END__
