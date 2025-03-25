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

package openprint::Estimating::Coating;
use strict;
use warnings;
use vars qw( %ServicePrices %Specifications);
%ServicePrices = (
	CoatingMinimumCharge => {},
	'(AqueousOffline|UVCoating)' => { units=>['per m', 'per side', 'per hour']},
	'(AqueousOffline|UVCoating)MakeReady' => {},
);
%Specifications = (
  CoatingRunSpeed => {range_units => [ 'gsm' ]},
  'WT Coating' => { values=>['Y','N'] },
  'Coating Overs' => {range_units => [ 'impressions' ]},
  'Coating Capable' => { value=>['Y','N'] },
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
  my $name = shift;
  return $Specifications{$name} if $Specifications{$name};
  return undef;
}

my %MaterialPrices = (
'.*' => { units => [ 'per square foot', 'per square inch', 'per 1000 square feet', 'per m', 'per kg' ] }
);
sub MaterialPriceConfiguration {
  my $name = shift;
  return $MaterialPrices{$name} if $MaterialPrices{$name};
  foreach my $key (keys %MaterialPrices) {
    return $MaterialPrices{$key} if ($name =~ /$key/i);
  }
  return undef;
}

require openprint::service;
require openprint::Material;
require openprint::imposition;
require openprint::Imposition;

use vars qw( $log $dbh %config @outputs );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;

# Offline Coating
# Let's assume that each piece of equipment can do 1 coat at a time
use constant DEBUG => 1;

my @variables = (
	'txtQuantity1','txtQuantity2','txtQuantity3',
	'txtPrice1','txtPrice2','txtPrice3',
	'Markup1', 'Markup2', 'Markup3',
	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
);

sub variables {
	my $p_id = shift;

	my $Project = new openprint::Project( $p_id );
  my @v = @variables;
  foreach my $s_s_id ( $Project->signatures() ) {
    my $specs = openprint::service::get_specs_ref( $Project, $s_s_id );
    my $form = $$specs{SignatureIndex};
    foreach my $qty_index ( $Project->quantity_indexes() ) {
      push @v, map { $_.'-'.$form } qw(sides type),
        map { $_.'-'.$form.'-'.$qty_index } qw(
            ddmEquipment chkOverrideEquipment
            SheetWidth SheetHeight);
    } # end foreach qty
  } # end foreach sig
  return @v;
} # end sub variables

@outputs = (
	'txtUnitPrice1','txtUnitPrice2','txtUnitPrice3',
	'MPrice1','MPrice2','MPrice3',
	'txtPrice1','txtPrice2','txtPrice3',
	'hdnBreakdown1', 'hdnBreakdown2', 'hdnBreakdown3',
	'alert','Status',
);
sub outputs {
	return @outputs;
}
sub no_outputs {
} # end sub no_outputs

my @no_outputs = (
);

# A function that is smart enough to return true if the project needs perfing/Coating, and false if it doesn't.
sub neccessary {
	my ( $Project ) = @_;

	return 0;
} # end sub neccessary

my @all_equipment;
my @coatings;

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $status = 'calculated';
  $$specs{alert} = '';

	my $Project = new openprint::Project( $project_index );
  my $service_type = $Project->ServiceType($service_index);


	@all_equipment = openprint::Equipment->find(
    'servicetype_id any'=>$service_type->id(),
    'useinestimating null_or_=' =>1,
    order=>'lower(strName)');
	if (!@all_equipment) {
		$$specs{alert} = 'We have no equipment for '.$service_type->description().'<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if

  @coatings = openprint::Material->find('servicetype_id any'=>$service_type->id(), 
#'name ilike'=>$service_type->name().'%'
      ) if !@coatings;

  my @signatures = $Project->signatures( { sort=>1 } );
  foreach my $signature_service_index (@signatures) {
    my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
    my $form = $$sig_specs{SignatureIndex};
    if (!$$specs{'sides-'.$form}) {
      $$specs{alert} .= 'Please select the sides to be coated<br/>';
      return $$specs{Status} = 'uncalculated';
    }
    if (@coatings>1) {
      if (!$$specs{'type-'.$form}) {
        $$specs{alert} .= 'Please select the type of coating for form '.$form.'<br/>';
        return $$specs{Status} = 'uncalculated';
      }
    }
  }

  foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"txtPrice$qty_index"} =~ s/[^\d\.]//g if $$specs{"txtPrice$qty_index"};
		$$specs{"txtQuantity$qty_index"} =~ s/[^\d\.]//g if $$specs{"txtQuantity$qty_index"};
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
		if ( $$specs{"txtQuantity$qty_index"} <= 0 ) {
			next;
		} # end if
		$$specs{'hdnBreakdown'.$qty_index} = sprintf('QTY: %d<br/>',$$specs{"txtQuantity$qty_index"} );

    my $qty = $$specs{"txtQuantity$qty_index"};
    if ( $$specs{txtPressSheetComboItems} ) {
      $qty *= $$specs{txtPressSheetComboItems};
    } # end if

    my %MakeReadies;
    my $GrandTotal = 0;
    foreach my $signature_service_index (@signatures) {
      my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
      my $form = $$sig_specs{SignatureIndex};
      $$specs{'hdnBreakdown'.$qty_index} .= 'Signature ' . $$sig_specs{SignatureIndex} . 'Printed: ' .openprint::service::summary( $Project, $signature_service_index, $qty_index ).'<br/>';

# If any of the signatures doesn't have an imposition, then we are in an incomplete state.
      if ( ! $$sig_specs{'txtImposition'.$qty_index} ) {
        $$specs{alert} .= 'No imposition was found for printing. Please complete the printing estimation first.<br/>';
#next;
      } # end if

      my $imposition = new openprint::Imposition();
      $imposition->load( $sig_specs, $qty_index, $Project );
      if (!$$specs{'OverrideSheetSize-'.$form.'-'.$qty_index} or $$specs{'OverrideSheetSize-'.$form.'-'.$qty_index} ne 'Y') {
        @$specs{'SheetWidth-'.$form.'-'.$qty_index,'SheetHeight-'.$form.'-'.$qty_index} = ($imposition->sheet_width(), $imposition->sheet_height());
      } else {
        $imposition->sheet_width($$specs{'SheetWidth-'.$form.'-'.$qty_index});
        $imposition->sheet_height($$specs{'SheetHeight-'.$form.'-'.$qty_index});
      }

      my %results = signature_calc( $Project, $service_index, $specs, $signature_service_index, $sig_specs, $qty_index, $imposition, \%MakeReadies);
      $$specs{'hdnBreakdown'.$qty_index} .= $results{Breakdown};

      if ((!defined $$specs{"chkOverrideEquipment-$form-$qty_index"} ) or ( $$specs{"chkOverrideEquipment-$form-$qty_index"} ne 'Y' ) ) {
        $$specs{"ddmEquipment-$form-$qty_index"} = '';
      } # end if
      if ( $results{Status} eq 'uncalculated' ) {
        $status = 'uncalculated';
        if ( $$specs{"chkOverrideEquipment-$form-$qty_index"} and ( $$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' ) ) {
          $$specs{alert} = 'The selected equipment can not handle your project.  This may be because the stock is too heavy, or too large.';
        } else {
          $$specs{alert} = $results{alert};
          if ( ! $$specs{alert} ) {
            $$specs{alert} .= 'No suitable equipment could be found for your project.  This may be because the stock is too heavy, or too large.';
          } # end if
        } # end if
      } else {
        if ( $results{Equipment} ) {
          $$specs{"ddmEquipment-$form-$qty_index"} = $results{Equipment}->id();
          $GrandTotal += $results{Total};
        } # end if
      } # end if uncalculated
    } # end foreach signature

    my $unit_price = ( $GrandTotal / $qty );
    my $price = $GrandTotal;

    if ( $Project->markup() ) {
      my $markup = (1+$Project->markup()/100);
      $unit_price *= $markup;
      $GrandTotal *= $markup;
    }
    if ( $$specs{"Markup$qty_index"} ) {
      my $markup = (1+$$specs{"Markup$qty_index"}/100);
      $unit_price *= $markup;
      $GrandTotal *= $markup;
    }

    $$specs{"MPrice$qty_index"} = sprintf( $config{UnitPriceFormat}, $unit_price * 1000 );
    $$specs{"txtUnitPrice$qty_index"} = sprintf( $config{UnitPriceFormat}, $unit_price );
    if ( ( ! defined $$specs{'OverridePrice'.$qty_index} ) or ( $$specs{'OverridePrice'.$qty_index} ne 'Y' ) ) {
      $$specs{"txtPrice$qty_index"} = sprintf( $config{ProjectMoneyFormat}, $GrandTotal );
    } else {
      $$specs{"txtPrice$qty_index"} = sprintf( $config{ProjectMoneyFormat}, $$specs{'txtPrice'.$qty_index} );
    } # end if
  } # end foreach qty

  return $$specs{Status} = $status;
} # end sub calc

sub signature_calc {
  my ( $Project, $service_index, $specs, $signature_service_index, $sig_specs, $qty_index, $imposition, $MakeReadies ) = @_;

  my $service_type = $Project->ServiceType($service_index);
  my $form = $$sig_specs{SignatureIndex};
  my $sides = $$specs{'sides-'.$form};

  my %BestPrice = (
      Total => undef,
      MakeReady => 0,
      Service => 0,
      Material => 0,
      Equipment => undef,
      Breakdown => '',
      Overs => 0,
      Status => 'uncalculated',
      );

  my $qty = $$specs{"txtQuantity$qty_index"};
  if ( $$specs{txtPressSheetComboItems} ) {
    $qty *= $$specs{txtPressSheetComboItems};
  } # end if
  if ( $$sig_specs{Versions} ) {
    $qty *= $$sig_specs{Versions};
	} # end if

	my @equipment;	
	if ( (defined $$specs{"chkOverrideEquipment-$$sig_specs{SignatureIndex}-$qty_index"}) and ($$specs{"chkOverrideEquipment-$$sig_specs{SignatureIndex}-$qty_index"} eq 'Y') ) {
		@equipment = ( new openprint::Equipment( $$specs{"ddmEquipment-$$sig_specs{SignatureIndex}-$qty_index"} ) );
	} else {
		@equipment = @all_equipment;
	} # endif

	# Start out with the base
	my $Stock = $imposition->Paper();

	my $MinimumCharge = openprint::Service->find_one(name=>$service_type->name().'MinimumCharge');
  my %coatings = map { $_->name(), $_ } @coatings;

	foreach my $Equipment ( @equipment ) {
		my %minimum = $MinimumCharge->get_price( undef, $Equipment ) if $MinimumCharge;
		my $BlanketCutPrice;
		my $runspeed = $Equipment->Specification($service_type->name().'RunSpeed', $Stock->gsm());
		my $equipment_id = $$Equipment{id};

    my %MakeReadies = %$MakeReadies;

    my %Price = (
        Blanket => 0,
        Makeready => 0,
        Service => 0,
        Breakdown => '<table>',
        Equipment => $Equipment,
        Overs => 0,
        );

    if ( $_ = equipment_fits( $Equipment, $imposition, $Stock ) ) {
      $Price{Breakdown} .= "<tr><td colspan=\"2\" class=\"error\">Doesn't fit. $_</td></tr>";
      next;
    } # end if

    my $run_qty = Math::Round::nearest( 1, $qty / $$imposition{imposition} );
    $Price{Breakdown} .= '<tr class="run_qty"><td colspan="2">sheets: '.$run_qty.'</td></tr>';

    if (my $Overs = $Equipment->Specification($service_type->name().' Overs', $run_qty)) {
      my $overs;
      if ( $$Overs{units} eq 'Sheets' ) {
        $overs = $$Overs{value};
      } elsif ($$Overs{units} eq 'percent') {
        $overs = int($run_qty * $$Overs{value} / 100);
      } else {
        $openprint::log->error('Unknown units in Coating Overs');
      } # endif
      $run_qty += $overs;
      $Price{Overs} += $overs;
      $Price{Breakdown} .= '<tr><td colspan="2"> Overs: ' . $overs.'</td></tr>';
    } # end if

    my $setupPrice;
    if ( $MakeReadies{$equipment_id} and (
          (($$imposition{sheet_width} * $$imposition{sheet_height} * 1.10 ) > $MakeReadies{$equipment_id} ) and
          (($$imposition{sheet_width} * $$imposition{sheet_height} * .90 ) < $MakeReadies{$equipment_id} )
          ) ) {
      $setupPrice = 0;
    } else {
      $setupPrice = openprint::service::get_price( $service_type->name().'MakeReady', $run_qty, $Equipment );
      if (!$setupPrice) {
        $openprint::log->debug('No setup price for '.$service_type->name());
        $setupPrice = 0;
      } else {
        $Price{MakeReady} += $setupPrice;
      }

      $MakeReadies{$Equipment->id()} = $$imposition{sheet_width} * $$imposition{sheet_height};
    } # end if
    $Price{Breakdown} .= sprintf('<tr class="makeready"><td>Make Ready:</td><td class="Price">$%.2f</td></tr>', $setupPrice);

    my %ServicePrice = openprint::service::get_price_object( $service_type->name(), $run_qty, $Equipment );
    if (!%ServicePrice) {
      $openprint::log->debug('No service price for '.$service_type->name());
      $ServicePrice{Total} = 0;
    } else {
      $Price{Breakdown} .= '<tr><td>Service: ';
      if ($ServicePrice{units} eq 'per m') {
        $ServicePrice{Total} = $ServicePrice{Price}*$run_qty/1000;
      } elsif ($ServicePrice{units} eq 'per side') {
        $ServicePrice{Total} = $ServicePrice{Price}*$run_qty*$sides;
      } elsif ( $ServicePrice{units} eq 'per hour' or $ServicePrice{units} eq '/Hr' or $ServicePrice{units} eq '/hr' ) {
        if ( $runspeed and $$runspeed{value}) {
          if ($$runspeed{units} eq 'inches per hour') {
# Feed in with height being the shortest
            my $length = $imposition->sheet_height() > $imposition->sheet_width() ? $imposition->sheet_width() : $imposition->sheet_height();
            my $inches = $length * $run_qty;
            my $hours = Math::Round::nearest( 0.01, $inches / $$runspeed{value} );
            $Price{Breakdown} .= sprintf('%s image length = %dinches @ %d/Hr = %.1fhours', $length, $inches, $$runspeed{value}, $inches/$$runspeed{value} );
            $ServicePrice{Total} = $ServicePrice{Price}*$inches/$$runspeed{value}
          } else {
            $Price{Breakdown} .= sprintf('%d @ %d/Hr = %.1fhours', $run_qty, $$runspeed{value}, $run_qty/$$runspeed{value} );
            $ServicePrice{Total} = $ServicePrice{Price}*$run_qty/$$runspeed{value}
          }
        } else {
          $Price{Breakdown} .= sprintf('No runspeed for %dgsm. Cannot use this price.<br/>', $Stock->gsm() );
          $ServicePrice{Total} = 1000000;
        } # end if
      } else {
        $openprint::log->error("Unknown units on Service Price $ServicePrice{Service} $ServicePrice{units}");
      } # end if
      $Price{Service} += $ServicePrice{Total};
      $Price{Breakdown} .= sprintf(' @ $%.2f%s</td><td class="Price">$%.2f</td></tr>', @ServicePrice{'Price','units','Total'} );
    } # end if

    my $Material;
    my %MaterialPrice;
    if (@coatings) {
      $$specs{"type-$form"} = $coatings[0]->name() if @coatings==1;
      $Material = $coatings{$$specs{"type-$form"}};
    } else {
      my $material_name = $service_type->name();
      $material_name =~ s/Offline//g;
      $Material = openprint::Material->find_one(name=>$material_name);
    } # end if

    if ($Material) {
      $Price{Breakdown} .= '<tr><td>Material ('.$Material->description().') :';
      %MaterialPrice = $Material->get_price( $run_qty, $Equipment );
      if ( lc $MaterialPrice{units} eq 'per square inch' ) {
        my $area = $imposition->sheet_area() * $run_qty * $sides;
        $Price{Breakdown} .= sprintf( '%sx%s = %d sq inches * %d sides = %d total sq inches',
            $imposition->sheet_width(), $imposition->sheet_height(), $imposition->sheet_area(), $sides, $area );
        $MaterialPrice{Total} = $MaterialPrice{Price} * $run_qty * $area;
      } elsif ( lc $MaterialPrice{units} eq 'per square foot' ) {
        my $area = $imposition->sheet_area() * $run_qty * $sides / 144;
        $Price{Breakdown} .= sprintf( ' %sx%s = %d sq inches * %dsheets * %d sides = %d total sq feet',
            $imposition->sheet_width(), $imposition->sheet_height(), $imposition->sheet_area(), $run_qty, $sides, $area );
        $MaterialPrice{Total} = $MaterialPrice{Price} * $area;
      } elsif ( lc $MaterialPrice{units} eq 'per 100 square feet' ) {
        my $area = $imposition->sheet_area() * $run_qty * $sides *1000/ 144;
        $Price{Breakdown} .= sprintf( ' %sx%s = %d sq inches * %dsheets * %d sides = %d total sq feet',
            $imposition->sheet_width(), $imposition->sheet_height(), $imposition->sheet_area(), $run_qty, $sides, $area );
      } elsif ( lc $MaterialPrice{units} eq 'per m' ) {
        $MaterialPrice{Total} = $MaterialPrice{Price} * $run_qty / 1000;
      } elsif ( $MaterialPrice{units} eq 'per kg' ) {
        my $area = $imposition->sheet_area() * $run_qty * $sides;
        my $grade = $Stock->grade();
        my $Coverage = $Material->Specification('Coverage', $grade);
        if ( (!$Coverage) or !$$Coverage{value} ) {
          $openprint::log->error("No Coverage for grade $grade");
        } else {
          my $qty = Math::Round::nearest( 0.01, $area/$$Coverage{value} ) if $Coverage and $$Coverage{value};
          %MaterialPrice = $Material->get_price($qty, $Equipment);
          $MaterialPrice{Total} += Math::Round::nearest(0.01, $MaterialPrice{Price} * $qty);
          $MaterialPrice{Breakdown} = sprintf('Coverage %sx%s = %d square inches, mileage: %dsquare inches/kg = %.2fkg * $%s%s=$%.2f',
              $imposition->sheet_width(), $imposition->sheet_height(),
              $area, $$Coverage{value}, $qty, @MaterialPrice{'Price','units','Total'});
        } # end if coverage
      } else {
        $MaterialPrice{units} = 'unknown units';
      } # end if
      $Price{Breakdown} .= sprintf(' @ $%.5f%s ', @MaterialPrice{'Price','units'} );
      $Price{Material} += $MaterialPrice{Total};
    } else {
      $MaterialPrice{Total} = 0; 
    } # end if
    $Price{Breakdown} .= sprintf('=</td><td class="Price">$%.2f</td></tr>', $MaterialPrice{Total} );

    $Price{Total} += misc::sum( @Price{'MakeReady','Service','Material'} );
    $Price{Breakdown} .= sprintf('<tr class="totals"><td>Total:</td><td class="Price">$%.2f</td></tr></table>',
        Math::Round::nearest(0.01, $Price{Total}) );
    $Price{Status} = 'calculated';

    if ( ( ! defined $BestPrice{Total} ) or ( $Price{Total} < $BestPrice{Total} ) ) {
      %BestPrice = %Price;
    } # end if
    if ( ! defined $BestPrice{Total} ) {
      $BestPrice{Breakdown} = 'Equipment: ' . $Equipment->name() . '<br/>' . $BestPrice{Breakdown};
      $openprint::log->debug("Can't calculate price for $$Equipment{name}");
      next;
    } # end if

    if ( ( defined $$specs{"OverrideMakeReadyPrice-$$sig_specs{SignatureIndex}-$qty_index"} ) and ( $$specs{"OverrideMakeReadyPrice-$$sig_specs{SignatureIndex}-$qty_index"} eq 'Y' ) ) {
      $BestPrice{MakeReady} = $$specs{"MakeReadyPrice-$$sig_specs{SignatureIndex}-$qty_index"};
    } # end if
    if ( ( defined $$specs{"OverrideBlanketPrice-$$sig_specs{SignatureIndex}-$qty_index"} ) and ( $$specs{"OverrideBlanketPrice-$$sig_specs{SignatureIndex}-$qty_index"} eq 'Y' ) ) {
      $BestPrice{Blanket} = $$specs{"BlanketPrice-$$sig_specs{SignatureIndex}-$qty_index"};
    } # end if
    if ( ( defined $$specs{"OverrideServicePrice-$$sig_specs{SignatureIndex}-$qty_index"} ) and ( $$specs{"OverrideServicePrice-$$sig_specs{SignatureIndex}-$qty_index"} eq 'Y' ) ) {
      $BestPrice{Service} = $$specs{"ServicePrice-$$sig_specs{SignatureIndex}-$qty_index"};
    } # end if
    if ( ( defined $$specs{"OverrideMaterialPrice-$$sig_specs{SignatureIndex}-$qty_index"} ) and ( $$specs{"OverrideMaterialPrice-$$sig_specs{SignatureIndex}-$qty_index"} eq 'Y' ) ) {
      $BestPrice{Material} = $$specs{"MaterialPrice-$$sig_specs{SignatureIndex}-$qty_index"};
    } # end if
    $BestPrice{Total} = misc::sum( @BestPrice{'MakeReady','Service','Material','Blanket','Cutting'} );

    if ( %minimum and ( $BestPrice{Total} < $minimum{Price} ) ) {
      $BestPrice{Breakdown} .= sprintf('Minimum: $%.2f<br/>', $minimum{Price});
      $BestPrice{Total} = $minimum{Price};
    } # end if
  } # end foreach equipment

  return %BestPrice;
} # end sub signature_calc

sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;
	my $Project = new openprint::Project( $project_index );
  my $service_type = $Project->ServiceType($service_index);

	$$variable{Equipment} = [ openprint::Equipment->find(
      'servicetype_id any' => $service_type->id(),
      'useinestimating is null or ='=>1,
      order=>'lower(strName)') ];
} # end sub display

sub summary {
	return '';
} # end sub summary

sub has_overrides {
  my ( $Project, $service_id, $specs, $qty_index ) = @_;
  $specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

  my @v;
  if ( $qty_index ) {
    push @v, map { ($$specs{$_.$qty_index} and ($$specs{$_.$qty_index} eq 'Y')) ? $_.$qty_index : () } ( 'OverridePrice' );
    foreach my $s_s_id ( $Project->signatures() ) {
      my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
      my $form = $$sig_specs{SignatureIndex};
      push @v, map { ($$specs{$_} and ($$specs{$_} eq 'Y')) ? $_ : () } (
        "chkOverrideEquipment-$form-$qty_index",
        "chkOverrideImposition-$form-$qty_index",
        "OverrideMakeReadyPrice-$form-$qty_index",
        "OverrideServicePrice-$form-$qty_index",
        "OverrideMaterialPrice-$form-$qty_index",
      );
    } # end foreach sig
  } # end if

  return @v;
} # end sub has_overrides

sub equipment_fits {
	my ( $Equipment, $I, $Stock ) = @_;
	if ( ( $_ = $Equipment->fits( $I->sheet_width(), $I->sheet_height() ) ) and ( $_ = $Equipment->fits( $I->layout_width(), $I->layout_height() ) ) ) {
		return $_;
	}
	if ( ( my $minimum_calliper ) = $Equipment->specification( 'Minimum Calliper', $I->sheet_width()*$I->sheet_height()) ) {
		if ( $minimum_calliper > $$Stock{calliper} ) {
			return "Calliper too thin stock calliper $$Stock{calliper} < minimum($minimum_calliper).";
		}
	}
}

1;
__END__
