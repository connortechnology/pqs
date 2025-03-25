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

package openprint::Estimating::Spiral;
use strict;

require openprint::service;
require openprint::Material;
require openprint::Project;

my %Specifications = (
  'Run Speed' => { },
  '(\w+) ?Overs' => { units => [ 'sheets', 'percent' ] },
);

# Stripping tends to be a manual process.  There are tools to help...
my %ServicePrices = (
  '(\w+)PunchingMinimumCharge' => {},
  '(\w)PunchingMakeReady' => { units => [ 'per hour' ] },
  '\w+' => { units=> ['per m', 'each']},
);

sub ServicePriceConfiguration {
  my $name = shift;
  return $ServicePrices{$name} if $ServicePrices{$name};
  foreach my $key (keys %ServicePrices) {
    return $ServicePrices{$key} if ($name =~ /$key/i);
  }
  return undef;
}
sub SpecificationConfiguration {
  return $Specifications{shift};
}


my @variables = (
  'alert',
  'hdnBreakdown1', 'hdnBreakdown2', 'hdnBreakdown3',
	'Markup1', 'Markup2', 'Markup3',
	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
	'txtPrice1', 'txtPrice2', 'txtPrice3',
	'MPrice1', 'MPrice2', 'MPrice3',
	'txtUnitPrice1', 'txtUnitPrice2', 'txtUnitPrice3',
	'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
	'ServiceType', 'Status',
	'txtRunTime1', 'txtRunTime2', 'txtRunTime3',
	'chkOverrideFinalHeight','txtFinalHeight',
	'chkOverrideFinishedCalliper','txtFinishedCalliper',
	'chkOverrideMaterialLength', 'txtMaterialLength',
  'acetate_front', 'acetate_back',
  'chkOverrideEquipment1', 'chkOverrideEquipment2', 'chkOverrideEquipment3',
  'ddmEquipment1', 'ddmEquipment2', 'ddmEquipment3',
	);

sub variables {
    return @variables;
} # end sub variables

sub neccessary {
	my ( $Project ) = @_;

	$Project = new openprint::Project( $Project ) if ref $Project ne 'openprint::Project';
	my $services = $Project->services();

	my $printing_service_index = $$services{''}[0] if $$services{''};
	my $specs = openprint::service::get_specs_ref( $Project, $printing_service_index );
	if (
    $$specs{rdbTemplateType} eq 'DoubleLoopWire'
      or
    $$specs{rdbTemplateType} eq 'MetalCoil'
      or
    $$specs{rdbTemplateType} eq 'PlasticCoil'
      or
    $$specs{rdbTemplateType} eq 'Cerlox'
  ) {
		return 1;
	} # end if

	return 0;
} # end sub neccessary

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $status = 'calculated';
  $$specs{alert} = '';

$log->debug("SPIRAL!!!!!!!!!!!!!!!!!!");
	# Currently there is no equipmnet for spiral
	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();
	my $ServiceType = $Project->ServiceType( $service_index );
	my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );

	if ( $$specs{chkOverrideFinalHeight} ne 'Y' ) {
		@$specs{txtFinalHeight} = $$printing_specs{txtFinalHeight};
	} # end if

	my $ProjectType = $Project->Type();

	if ( $$specs{chkOverrideFinishedCalliper} ne 'Y' ) {
		$$specs{txtFinishedCalliper} = openprint::print::get_finished_calliper( $project_index );
	} else {
		$$specs{txtFinishedCalliper} =~ s/[^\d\.]//g;
	} # end if

	my $PunchingService = openprint::Service->find_one( name => $ServiceType->name().'Punching');
	my $CoilingService = openprint::Service->find_one( name => $ServiceType->name().'Inserting' );
	$CoilingService = openprint::Service->find_one( name => $ServiceType->name() ) if !$CoilingService;
	my $Material = openprint::Material->find_one( name=>$ServiceType->name() );
  my $AcetateFront = openprint::Material->find_one(name=>'Clear Acetate Front');
  my $AcetateBack = openprint::Material->find_one(name=>'Black Acetate Back');

  my @all_equipment = openprint::Equipment->find(
    'servicetype_id any' => $ServiceType->id(),
    useinestimating=>1,order=>'strName');
  if (!@all_equipment) {
    $$specs{alert} .= 'We have no equipment for '.$ServiceType->name().'.<br/>';
    return $$specs{Status} = 'uncalculated';
  } # end if

  foreach my $qty_index ( $Project->quantity_indexes() ) {
    $$specs{"Markup$qty_index"} =~ s/[^\d\.\-]//g if $$specs{"Markup$qty_index"};
		$$specs{"txtPrice$qty_index"} =~ s/[^\d\.\-]//g if $$specs{"txtPrice$qty_index"};
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
		$$specs{"txtQuantity$qty_index"} = int( $$specs{"txtQuantity$qty_index"} );
    my $base_qty = $$specs{"txtQuantity$qty_index"};
    next if ! $base_qty;

    if ( $$specs{chkOverrideMaterialLength} ne 'Y' ) {
      $$specs{txtMaterialLength} = $$specs{txtFinalHeight} * $$specs{"txtQuantity$qty_index"};
    } # end if

    my @equipment = ();
    if ( $$specs{"chkOverrideEquipment$qty_index"} eq 'Y' ) {
      @equipment = ( new openprint::Equipment( $$specs{"ddmEquipment$qty_index"} ) );
    } else {
      @equipment = @all_equipment;
    } # end if

    my %bestPrice;

    foreach my $equipment ( @equipment ) {
      $$specs{'hdnBreakdown'.$qty_index} .= 'Equipment ' . $equipment->name().':<br/>';

      my %price = (
        equipment => $equipment,
        quantity => $base_qty,
        total => 0,
        mprice => 0,
        breakdown => '',
      );

      my $qty = $base_qty;
      $price{breakdown} = '';
      if ( my $Overs = $equipment->Specification('Overs') ) {
        my $overs = 0;
        if ( $$Overs{units} eq 'sheets' ) {
          $overs = int($$Overs{value});
        } elsif ( $$Overs{units} eq 'percent' ) {
          $overs = int($qty * $$Overs{value}/100);
        } else {
          $openprint::log->error("Invalid units on Overs $$Overs{units} on $$equipment{name}");
        } # end if
        $qty += $overs;
        $price{overs} = $overs;
        $price{Overs} = $Overs;
        $price{quantity} = $qty;
        if ($$Overs{units} eq 'percent' ) {
          $price{breakdown} .= $base_qty.' + '.$$Overs{value}.'% = '.$price{overs}.' overs = '.$price{quantity}.'<br/>';
        } else {
          $price{breakdown} .= $base_qty.' + '.$$Overs{value}.$$Overs{units}.' = '.$price{overs}.' overs = '.$price{quantity}.'<br/>';
        }
      } # end if

      my $makeReadyPrice = $price{make_ready} = openprint::service::get_price( $ServiceType->name().'PunchingMakeReady', undef, $equipment );
      my $minimumCharge = $price{minimum_charge} = openprint::service::get_price( $ServiceType->name().'PunchingMinimumCharge', undef, $equipment );
      $price{breakdown} .= sprintf('MakeReady: $%.2f<br/>', $makeReadyPrice );
      $price{breakdown} .= 'MinimumCharge: ' . sprintf('$%.2f<br/>', $minimumCharge ) if $minimumCharge;

      my %PunchingPrice;
			if ( $PunchingService ) {
				%PunchingPrice = $PunchingService->get_price($qty, $equipment);
				if ( $PunchingPrice{units} eq 'per m' ) {
					$PunchingPrice{Total} = Math::Round::nearest( 0.01, $PunchingPrice{Price} * $qty / 1000 );
        } elsif ( $PunchingPrice{units} eq 'each' ) {
					$PunchingPrice{Total} = Math::Round::nearest( 0.01, $PunchingPrice{Price} * $qty );
				} else {
          $price{alert} .= 'Invalid units '.$PunchingPrice{units}.' on '.$PunchingPrice{ServiceName}.'<br/>';
					$PunchingPrice{Total} = Math::Round::nearest( 0.01, $PunchingPrice{Price} * $qty );
				} # end if
				$price{breakdown} .= 'Punching: '.sprintf( '$%.4f%s = $%.2f<br/>', @PunchingPrice{'Price','units','Total'} );
			} # end if

			my %CoilingPrice;
			if ( $CoilingService ) {
				%CoilingPrice = $CoilingService->get_price( $qty, $equipment );
				if ( $CoilingPrice{units} eq 'per m' ) {
					$CoilingPrice{Total} = Math::Round::nearest( 0.01, $CoilingPrice{Price} * $qty / 1000 );
        } elsif ( $CoilingPrice{units} eq 'each' or $CoilingPrice{units} eq 'per unit') {
					$CoilingPrice{Total} = Math::Round::nearest( 0.01, $CoilingPrice{Price} * $qty );
				} else {
					$openprint::log->error("Unknown units for $$ServiceType{name} $CoilingPrice{units}");
				} # end if
				$price{breakdown} .= $CoilingPrice{Service}->description().': ' . sprintf( '$%.4f%s = $%.2f<br/>', @CoilingPrice{'Price','units','Total'} );
			} # end if CoilingService

			$price{total} = $makeReadyPrice + $PunchingPrice{Total} + $CoilingPrice{Total};

			if ( $Material ) {
				my %MaterialPrice = $Material->get_price( $$specs{txtFinishedCalliper}, $equipment );
				if ( $MaterialPrice{units} eq 'project calliper-per 36 inches' ) {
					$MaterialPrice{Total} = Math::Round::nearest( 0.01, ( $MaterialPrice{Price} /36 ) * $$specs{txtMaterialLength} );
				} elsif ( $MaterialPrice{units} eq 'project calliper-per inch' ) {
					$MaterialPrice{Total} = Math::Round::nearest( 0.01, $MaterialPrice{Price} * $$specs{txtMaterialLength} );
				} elsif ( $MaterialPrice{units} eq 'per inch' ) {
					$MaterialPrice{Total} = Math::Round::nearest( 0.01, $MaterialPrice{Price} * $$specs{txtMaterialLength} );
				} elsif ( $MaterialPrice{units} eq 'each' ) {
					$MaterialPrice{Total} = Math::Round::nearest( 0.01, $MaterialPrice{Price} * $qty);
				} else {
					$price{breakdown} .= 'Unknown units for material<br/>';
				} # end if
				$price{breakdown} .= 'Material: '.$Material->description().' '. sprintf( '$%.2f%s = $%.2f<br/>', @MaterialPrice{qw(Price units Total)});
				$price{total} += $MaterialPrice{Total};
				$price{mprice} += $MaterialPrice{Total};
			} else {
				$price{breakdown} .= 'No material found';
			} # end if

      if ($AcetateFront and $$specs{acetate_front} and ($$specs{acetate_front} eq 'Y')) {
        my %AcetateFrontPrice = $AcetateFront->get_price($qty, $equipment);
				if ($AcetateFrontPrice{units} eq 'each') {
					$AcetateFrontPrice{Total} = Math::Round::nearest( 0.01, $AcetateFrontPrice{Price} * $qty);
          $price{mprice} += $AcetateFrontPrice{Price} * 1000;
        } elsif ($AcetateFrontPrice{units} eq 'per m') {
					$AcetateFrontPrice{Total} = Math::Round::nearest( 0.01, $AcetateFrontPrice{Price} * $qty/1000);
          $price{mprice} += $AcetateFrontPrice{Price};
				} else {
					$price{breakdown} .= 'Unknown units for '.$AcetateFront->description().'<br/>';
				} # end if
        $price{breakdown} .= $AcetateFront->description().': ' . sprintf('$%.2f%s = $%.2f<br/>', @AcetateFrontPrice{qw(Price units Total)});
        $price{total} += $AcetateFrontPrice{Total};
      }
      if ($AcetateBack and $$specs{acetate_back} and ($$specs{acetate_back} eq 'Y')) {
        my %AcetateBackPrice = $AcetateBack->get_price($qty, $equipment);
				if ($AcetateBackPrice{units} eq 'each') {
					$AcetateBackPrice{Total} = Math::Round::nearest( 0.01, $AcetateBackPrice{Price} * $qty);
          $price{mprice} += $AcetateBackPrice{Price} * 1000;
        } elsif ($AcetateBackPrice{units} eq 'per m') {
					$AcetateBackPrice{Total} = Math::Round::nearest( 0.01, $AcetateBackPrice{Price} * $qty/1000);
          $price{mprice} += $AcetateBackPrice{Price};
				} else {
					$price{breakdown} .= 'Unknown units for '.$AcetateBack->description().'<br/>';
				} # end if
        $price{breakdown} .= $AcetateBack->description().': ' . sprintf('$%.2f%s = $%.2f<br/>', @AcetateBackPrice{qw(Price units Total)});
        $price{total} += $AcetateBackPrice{Total};
      }
	
			if ( $minimumCharge > 0 and $price{total} < $minimumCharge ) {
				$price{total} = $minimumCharge;
			} # end if
			$price{mprice} += $PunchingPrice{Total} + $CoilingPrice{Total};
			$price{mprice} = ( $price{mprice} / $qty ) * 1000;
			$price{breakdown} .= 'Qty: ' . $base_qty . sprintf(': Total: $%.2f<br/>',$price{total});
      if ((!%bestPrice) or ($bestPrice{total} > $price{total})) {
        %bestPrice = %price;
      }
		} # end foreach equipment

    $$specs{'hdnBreakdown'.$qty_index} .= $bestPrice{breakdown};
    $$specs{'ddmEquipment'.$qty_index} .= $bestPrice{equipment}->id();
		$$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, ($bestPrice{total}/$bestPrice{quantity}) * (1+$Project->markup()/100) );
		$$specs{"MPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $bestPrice{mprice} *(1+$$specs{"Markup$qty_index"}/100)*(1+$Project->markup()/100) );
		if ( $$specs{"OverridePrice$qty_index"} ne 'Y' ) {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $bestPrice{total}*(1+$$specs{"Markup$qty_index"}/100)*(1+$Project->markup()/100) );
		} else {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"} );
		} # end if
	} # end foreach qty_index

	$log->debug("END SPIRAL!!!!!!!!!!!!!!!!!!");
	return $$specs{Status} = $status;
} # end sub calc

sub breakdown {
}

sub display {
}

sub summary {
  my ( $Project, $service_id, $specs, $qty_index ) = @_;
  $specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
  my $summary = '';
  if (!$qty_index) {
    my $AcetateFront = openprint::Material->find_one(name=>'Clear Acetate Front');
    if ($AcetateFront and $$specs{acetate_front} and ($$specs{acetate_front} eq 'Y')) {
      $summary .= 'With '.$AcetateFront->description().'<br/>';
    }
    my $AcetateBack = openprint::Material->find_one(name=>'Black Acetate Back');
    if ($AcetateBack and $$specs{acetate_back} and ($$specs{acetate_back} eq 'Y')) {
      $summary .= 'With '.$AcetateBack->description().'<br/>';
    }
    return $summary;
  } # end if qty_index
} # end sub summary

sub has_overrides {
  my ( $Project, $service_id, $specs, $qty_index ) = @_;
  $specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

  my @v;
  push @v, map { $$specs{$_} ? $_ : () } ( 'chkOverrideFinalHeight', 'chkOverrideFinishedCalliper', 'chkOverrideMaterialLength' );
  if ( $qty_index ) {
    push @v, map { $$specs{$_.$qty_index} ? $_.$qty_index : () } ( 'OverridePrice' );
  } # end if

  return @v;

} # end sub has_overrides

sub save {
  my ( $p_id, $s_id, $param ) = @_;
  my $Project = new openprint::Project( $p_id );
  my $services = $Project->services();

  foreach my $spec ('acetate_front','acetate_back') {
    openprint::service::insert_service_spec( $openprint::log, $openprint::dbh, $Project->id(), $$services{''}[0], $spec, $$param{$spec} );
  }
} # end sub save

1;
__END__
