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

package openprint::Estimating::Lamination;
use strict;
use warnings;

use openprint::Imposition;
require openprint::Equipment;
require openprint::service;

require sql;
use vars qw( %ServicePrices %MaterialPrices %Specifications);
%ServicePrices = (
LaminationMinimumCharge => { units=>[] },
LaminationMakeReady => { units => [] },
Lamination => { units => ['per m','per hour', 'per inch'] },
);

sub ServicePriceConfiguration {
  my $name = shift;
  return $ServicePrices{$name} if $ServicePrices{$name};
  foreach my $key (keys %ServicePrices) {
    return $ServicePrices{$key} if ($name =~ /$key/i);
  }
  return undef;
}

%MaterialPrices = (
'.*Laminate.*' => { units => [ 'per square foot', 'per m square inches' ] }
);
sub MaterialPriceConfiguration {
  my $name = shift;
  return $MaterialPrices{$name} if $MaterialPrices{$name};
  foreach my $key (keys %MaterialPrices) {
    return $MaterialPrices{$key} if ($name =~ /$key/i);
  }
  return undef;
}

%Specifications = (
  'Laminating Count' => { units => ['Net Sheets', 'Gross Sheets'] },
  'Laminating Waste'  => { units => 'Percent' },
  'Laminating Style' => { values => [ 'Sheet','Final Pieces' ] },
  'Laminating Capable' => { values => [ 'Y'|'N' ] },
  'Laminating Sides' => { values => ['Both', 'Single'] },
  'Maximum Sheet Width' => { units => 'Inches' },
  'Maximum Sheet Length' => { units => 'Inches' },
  'Minimum Sheet Width' => { units => 'Inches' },
  'Minimum Sheet Length' => { units => 'Inches' },
  'Maximum Calliper' => { units => 'Inches' },
  'Minimum Calliper' => { units => 'Inches' },
  'Run Speed' => { units => 'inches per hour' },
);

sub SpecificationConfiguration {
  my $name = shift;
  return $Specifications{$name} if $Specifications{$name};
  return undef;
}

my @variables = (
  'alert',
	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
	'Markup1', 'Markup2', 'Markup3',
	'txtPrice1', 'txtPrice2', 'txtPrice3',
	'txtUnitPrice1', 'txtUnitPrice2', 'txtUnitPrice3',
	'MPrice1', 'MPrice2', 'MPrice3',
	'hdnBreakdown1', 'hdnBreakdown2', 'hdnBreakdown3',
);

sub variables {
  my $p_id = shift;

  my $Project = new openprint::Project($p_id);
  my @v = @variables;
  foreach my $s_s_id ( $Project->signatures() ) {
    my $specs = openprint::service::get_specs_ref($Project, $s_s_id);
    my $form = $$specs{SignatureIndex} // 1;
    foreach my $qty_index ( $Project->quantity_indexes() ) {
      push @v, (
        "txtWidth-$form", "txtHeight-$form", "chkOverrideDimensions-$form",
        "calliper-$form", "override_calliper-$form",
        "TypeFront-$form", "TypeBack-$form",
         "ddmEquipment-$form-$qty_index", "chkOverrideEquipment-$form-$qty_index",
       );
     }
   }

	return @v;
} # end sub variables

my @outputs = (
	'txtWidth','txtHeight',
	'txtPrice1', 'txtPrice2', 'txtPrice3',
	'MPrice1', 'MPrice2', 'MPrice3',
	'txtUnitPrice1', 'txtUnitPrice2', 'txtUnitPrice3',
	'ddmEquipment1', 'ddmEquipment2', 'ddmEquipment3',
	'alert', 'Status',
	'hdnBreakdown1', 'hdnBreakdown2', 'hdnBreakdown3',
);

sub outputs {
  my $p_id = shift;
  my @o = @outputs;
  my $Project = new openprint::Project($p_id);
  foreach my $s_s_id ( $Project->signatures() ) {
    my $specs = openprint::service::get_specs_ref($Project, $s_s_id);
    my $form = $$specs{SignatureIndex} // 1;
    foreach my $qty_index ( $Project->quantity_indexes() ) {
      push @o, (
        "txtWidth-$form", "txtHeight-$form",
        "calliper-$form",
        "TypeFront-$form","TypeBack-$form",
        "ddmEquipment-$form-$qty_index",
      );
      }
    }
	return @o;
}

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $type, $specs ) = @_;

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();
  $$specs{alert} = '';

  my $has_lamination = 0;
  my @sigs = $Project->signatures({ sort=>1 });
  foreach my $signature_service_index (@sigs) {
    my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
    my $form  = $$sig_specs{SignatureIndex} // 1;
    my $stock = openprint::Paper::load_from_signature( $Project, $sig_specs, 1 );

    if ( (!$$specs{'chkOverrideDimensions-'.$form}) or ($$specs{'chkOverrideDimensions-'.$form} ne 'Y')) {
      if ($$sig_specs{final_width} and $$sig_specs{final_height}) {
        @$specs{'txtWidth-'.$form,'txtHeight-'.$form} = @$sig_specs{'final_width','final_height'};
      } else {
        @$specs{'txtWidth-'.$form,'txtHeight-'.$form} = @$sig_specs{'txtWidth','txtHeight'};
      }
      $$specs{"calliper-$form"} = $stock->calliper();
    } # end if

    if ( $$specs{'LaminationType-'.$form} ) {
      $$specs{"TypeFront-$form"} = $$specs{"TypeBack-$form"} = $$specs{'LaminationType-'.$form};
    } else {
      $$specs{"TypeFront-$form"} = $$specs{TypeFront} if $$specs{TypeFront} and ! $$specs{"TypeFront-$form"};
      $$specs{"TypeBack-$form"} = $$specs{Typeback} if $$specs{TypeBack} and !$$specs{"TypeBack-$form"};
    } # end if
    $$specs{'TypeFront-'.$form} = '' if $$specs{'TypeFront-'.$form} and $$specs{'TypeFront-'.$form} eq 'None';
    $$specs{'TypeBack-'.$form} = '' if $$specs{'TypeBack-'.$form} and $$specs{'TypeBack-'.$form} eq 'None';
    $has_lamination = 1 if $$specs{'TypeFront-'.$form} or $$specs{'TypeBack-'.$form};

    $$specs{alert} .= "Please enter object width for form $form.<br/>" if ! $$specs{'txtWidth-'.$form};
    $$specs{alert} .= "Please enter object height for form $form.<br/>" if ! $$specs{'txtHeight-'.$form};
    $$specs{alert} .= "Please enter object calliper for form $form.<br/>" if ! $$specs{'calliper-'.$form};
  } # end foreach signature
  $$specs{alert} .= 'Please select lamination types for at least one signature or remove lamination from the project.<br/>' if ! $has_lamination;

	if ( $$specs{alert} ) {
		foreach my $qty_index ( $Project->quantity_indexes() ) {
			$$specs{'txtPrice'.$qty_index} = '';
			$$specs{'MPrice'.$qty_index} = '';
			$$specs{'txtUnitPrice'.$qty_index} = '';
		} # end foreach qty_index
		return $$specs{Status} = 'uncalculated';
	} # end if

  my %MinimumCharge = openprint::service::get_price_object( $$specs{ServiceType}.'MinimumCharge', undef, undef );
  $MinimumCharge{Price} //= 0;

  my @all_equipment = openprint::Equipment->find(
    Specifications => {
      'Laminating Capable'=>'Y'
    },
    useinestimating=>1,
    order=>'lower(strName)');

  if (!@all_equipment) {
    $$specs{alert} = 'We have no laminating equipment.';
    return $$specs{Status} = 'uncalculated';
  } # end if

	$$specs{Status} = 'calculated';

	my $MakeReady = openprint::Service->find_one( name=>$$specs{ServiceType}.'MakeReady' );
	my $Service = openprint::Service->find_one( name=>$$specs{ServiceType} );

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"Markup$qty_index"} =~ s/[^\d\.\-]//g if $$specs{"Markup$qty_index"};
		$$specs{"txtPrice$qty_index"} =~ s/[^\d\.]//g if $$specs{"txtPrice$qty_index"};
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
		my $qty = int $$specs{"txtQuantity$qty_index"};
		next if ! $qty;

    my %totalPrice = (
      MPrice => 0
    );

    foreach my $signature_service_index (@sigs) {
      my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
      my $form  = $$sig_specs{SignatureIndex} // 1;
      if ((!$$specs{"TypeFront-$form"}) and (!$$specs{"TypeBack-$form"})) {
        #$$specs{'hdnBreakdown'.$qty_index} .= " not doing lamination on form $form<br/>";
        next;
      }
      my $imposition = new openprint::Imposition();
      $imposition->load( $sig_specs, $qty_index, $Project );
      my $stock = $imposition->Paper();
      $$stock{calliper} = $$specs{"calliper-$form"};

      $$specs{'hdnBreakdown'.$qty_index} .= 'Signature ' . $form . ' printed: ' .openprint::service::summary( $Project, $signature_service_index, $qty_index ).'<br/>';
      if (!$$imposition{imposition}) {
        $$specs{'hdnBreakdown'.$qty_index} .= 'No imposition loaded.<br/>';
        next;
      }

      my %bestPrice;
      my @equipment = ();
      if ($$specs{"chkOverrideEquipment-$form-$qty_index"} and ($$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' and $$specs{"ddmEquipment-$form-$qty_index"})) {
        @equipment = openprint::Equipment->find(id=>$$specs{"ddmEquipment-$form-$qty_index"});
      } else {
        @equipment = @all_equipment;
      } # end if
      if (!@equipment) {
        $$specs{alert} .= 'No equipment found for form '.$form.' quantity '.$qty_index.'.<br/>';
      }

      foreach my $Equipment (@equipment) {
        my $style = $Equipment->specification('Laminating Style') // '';

        my $error = '';
        if ((!$style) or ($style eq 'Final Pieces')) {
          if ( 
            (my $reason1 = $Equipment->fits( $$specs{"txtWidth-$form"}, undef, $$specs{"calliper-$form"}, ) ) and
            (my $reason2 = $Equipment->fits( $$specs{"txtHeight-$form"}, undef, $$specs{"calliper-$form"} ) ) 
          ) {
            $error .= 'For ' . $Equipment->name() . ': '. $reason1  . '<br/>' . $reason2;
          } # end if
        } else {
          if ( 
            (my $reason1 = $Equipment->fits( undef, undef, $$specs{"calliper-$form"} ))
          ) {
            $error .= 'For ' . $Equipment->name() . ': '. $reason1  . '<br/>';
          } # end if
        }

        if ($error) {
          $$specs{"hdnBreakdown$qty_index"} .= $error;
          next;
        }

        my $sides = $Equipment->specification('Laminating Sides') // '';
        if ((( !$$specs{"TypeFront-$form"}) or (!$$specs{"TypeBack-$form"})) and ( $sides eq 'Both' ) ) {
          if ( $$specs{"chkOverrideEquipment-$form-$qty_index"} and ($$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y')) {
            $$specs{alert} .= 'The chosen laminator must do both sides.  You have chosen no lamination for one of the sides.<br/>';
          } # end if
          next;
        } # end if
        my $maximum_sheet_width = $Equipment->specification('Maximum Sheet Width') // '';
        my $maximum_sheet_length= $Equipment->specification('Maximum Sheet Length') // '';
        my $laminate_width = $Equipment->specification('Laminate Width');
        $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Equipment: %s max Width: %s Length: %s<br/>',
            $Equipment->name(), $maximum_sheet_width, $maximum_sheet_length);
        my $sheets = 0;

        # So we can do multiple items at once, as many as will fit in the width of the laminator.
        # We need a certain amount of space between the items.  I suspect that this should be an 
        # input, not a fixed value, but for now we will make it fixed.
        my $item_width = $$specs{"txtWidth-$form"};
        my $item_height = $$specs{"txtHeight-$form"};

        my $length;
        my $width;
        if (!$style or ($style eq 'Final Pieces')) {
          $imposition = new openprint::Imposition();
          # How many can we fit in the width?
          my $imposition1 = int( $maximum_sheet_width / $item_width );
          my $imposition2 = int( $maximum_sheet_width / $item_height );
          if ( $imposition2 > $imposition1 ) {
            $imposition->rows($qty/$imposition2);
            $imposition->columns($imposition2);
            $imposition->image_orientation(openprint::Imposition::Horizontal);
          } elsif ( $imposition1 ) {
            $imposition->rows($qty/$imposition1);
            $imposition->columns($imposition1);
            $imposition->image_orientation(openprint::Imposition::Vertical);
          }
          if ( $$imposition{image_orientation} == openprint::Imposition::Vertical ) {
            $length = $item_height * $imposition->rows();
            $width = $item_width * $imposition->columns();
          } else {
            $length = $item_width * $imposition->rows();
            $width = $item_height * $imposition->columns();
          } # end if
          $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Items across: ( %s x %s ) %d style:%s<br/>', $item_width, $item_height, $imposition->columns(), $style );
          next if ! $$imposition{imposition};
          $sheets = $qty;
        } else {
          $_ = equipment_fits($Equipment, $imposition, $stock);
          if ($_) {
            $$specs{'hdnBreakdown'.$qty_index} .= 'Doesn\'t fit.'.$_.'<br/>';
            next;
          } # end if
          if ($imposition->sheet_width() > $maximum_sheet_width) {
            $length = $imposition->sheet_width();
            $width = $imposition->sheet_height();
          } elsif ($imposition->sheet_height() > $maximum_sheet_width) {
            $length = $imposition->sheet_height();
            $width = $imposition->sheet_width();
          } else {
            # They both fit, use the shorter
            ($length, $width) = ($imposition->sheet_width() > $imposition->sheet_height ? 
              ($imposition->sheet_height(), $imposition->sheet_width()) : 
              ($imposition->sheet_width(), $imposition->sheet_height())
            );
          }
          my $count = $Equipment->specification('Laminating Count');
          if ($count eq 'Net Sheets') {
            $sheets = $$imposition{net_sheets};
          } else {
            $sheets = $$imposition{impressions} ? $$imposition{impressions} : $$imposition{net_sheets};
          }
          $sheets = $qty if ! $sheets;
        }
        my $waste = $Equipment->Specification('Laminating Waste');
        if ($waste) {
          if ($$waste{units} eq 'percent') {
            $sheets += int($sheets * $$waste{value}/100);
          }
        }

        $width = $laminate_width if $laminate_width;
        my $area = $length * $width * $sheets;
        $$specs{'hdnBreakdown'.$qty_index} .= 'Using '.$length.'" x '.$width.'" * '.$sheets.' sheets = '.$area.' square inches<br/>';

        my %SetupPrice = $MakeReady->get_price(undef, $Equipment ) if $MakeReady;
        my $price = $SetupPrice{Price};
        $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Setup: $%.2f<br/>', $SetupPrice{Price});

        my $MPrice = 0;

        my %ServicePrice = $Service->get_price( undef, $Equipment ) if $Service;
        if ( %ServicePrice ) {
          $ServicePrice{units} //= '';

          if ( $ServicePrice{units} eq 'per m' ) {
            $ServicePrice{Total} = ($ServicePrice{Price} * $qty)/1000;
            $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service: $%1$.2f %2$s * %4$f = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $qty );
            $MPrice += $ServicePrice{Price};
          } elsif ( $ServicePrice{units} eq 'per inch' ) {
            my $linear_length = Math::Round::nearest(0.01, $length * $sheets);
            #$$specs{'hdnBreakdown'.$qty_index} .= "Linear length $length * $sheets = $linear_length inches<br/>";
            $ServicePrice{Total} = Math::Round::nearest( 0.01, $ServicePrice{Price} * $linear_length );
            $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service: $%1$.2f %2$s * %4$d inches = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $linear_length);
            $MPrice += Math::Round::nearest( 0.01, $ServicePrice{Price} * ($length * 1000 / $$imposition{imposition}));
          } elsif ( $ServicePrice{units} eq '/Hr' or $ServicePrice{units} eq 'per hour') {
            my $inches_per_hour;
            my $Speed = $Equipment->Specification( 'Run Speed' ) ;
            if ( $Speed ) {
              if ( lc $$Speed{units} eq 'inches per hour' ) {
                $inches_per_hour = $$Speed{value};
              } else {
                $$specs{'hdnBreakdown'.$qty_index} .= "Unknown speed units ($$Speed{units}<br/>";
                $inches_per_hour = 720;
              } # end if
            } else {
              $$specs{'hdnBreakdown'.$qty_index} .= 'No speed set<br/>';
              $inches_per_hour = 720;
            } # end if

            if ($style ne 'Sheet' ) {
              my $hours = Math::Round::nearest( 0.01, $length * ( $qty / $$imposition{imposition} ) / $inches_per_hour );
              $ServicePrice{Total} = Math::Round::nearest( 0.01, $ServicePrice{Price} * $hours );
              if ($sides eq 'Single' and $$specs{"TypeFront-$form"} and $$specs{"TypeBack-$form"}) {
                $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service: Front $%1$.2f %2$s * %4$.2fhours = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $hours);
                $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service: Back $%1$.2f %2$s * %4$.2fhours = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $hours);
                $ServicePrice{Total} *= 2;
                $ServicePrice{Price} *= 2;
              } else {
                $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service: Both sides $%1$.2f %4$s * %2$.2fhours = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $hours);
              }
              $MPrice += Math::Round::nearest( 0.01, $ServicePrice{Price} * ( $length * ( 1000 / $$imposition{imposition} ) ) / $inches_per_hour );
            } else {
              my $hours = Math::Round::nearest(0.01, $length * $sheets / $inches_per_hour);
              $$specs{'hdnBreakdown'.$qty_index} .= "Runtime = length $length * $sheets / $inches_per_hour<br/>";
              $ServicePrice{Total} = Math::Round::nearest( 0.01, $ServicePrice{Price} * $hours );
              if ($sides eq 'Single' and $$specs{"TypeFront-$form"} and $$specs{"TypeBack-$form"}) {
                $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service: Front $%1$.2f %2$s * %4$.2fhours = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $hours);
                $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service: Back $%1$.2f %2$s * %4$.2fhours = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $hours);
                $ServicePrice{Total} *= 2;
                $ServicePrice{Price} *= 2;
              } else {
                $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service: Both sides: $%1$.2f %2$s * %4$.2fhours = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $hours);
              }
              $MPrice += Math::Round::nearest( 0.01, $ServicePrice{Price} * ( $length * ( 1000 / $$imposition{imposition} ) ) / $inches_per_hour );
            }
          } else {
            $$specs{'hdnBreakdown'.$qty_index} .= "Unknown units ($ServicePrice{units}) for $$specs{ServiceType}<br/>";
          } # end if
          $price += $ServicePrice{Total};
        } else {
          $$specs{'hdnBreakdown'.$qty_index} .= "No Service price for $$specs{ServiceType}<br/>";
        } # end if
        if ( $$specs{"TypeFront-$form"}) {
          my $FrontMaterialPrice;
          if ( my $FrontMaterial = openprint::Material->find_one(name=>$$specs{"TypeFront-$form"} ) ) {
            $FrontMaterialPrice = $FrontMaterial->get_Price( $area, $Equipment );
            if ( ! $FrontMaterialPrice ) {
              if ( $$specs{"chkOverrideEquipment$qty_index"} eq 'Y' ) {
                $$specs{alert} .= "There is no price for $$FrontMaterial{description} on $$Equipment{name}.<br/>";
              } # end if

              next;
            } # end if
            if ( $$FrontMaterialPrice{units} eq 'per square foot' ) {
              $$FrontMaterialPrice{Total} = $$FrontMaterialPrice{Price} * $area / 144;
              $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Material on Front: $%1$.6f %2$s * %4$.2f square feet = $%3$.2f<br/>', @$FrontMaterialPrice{'Price','units','Total'}, $area/144 );
            } elsif ( $$FrontMaterialPrice{units} eq 'per m square inches' ) {
              $$FrontMaterialPrice{Total} = $$FrontMaterialPrice{Price} * $area / 1000;
              $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Material on Front: $%1$.2f %2$s * %4$.2f inches = $%3$.2f<br/>', @$FrontMaterialPrice{'Price','units','Total'}, $area/1000 );
            } else {
              $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Material on Front: unknown units: (%s)<br/>', $FrontMaterialPrice->to_string() );
            } # end if
            $price += $$FrontMaterialPrice{Total};
            $MPrice += ( 1000 / $$imposition{imposition} ) * $$FrontMaterialPrice{Total}/$sheets;
          } else {
            $$specs{'hdnBreakdown'.$qty_index} .= sprintf('No Material found for Front: (%s)<br/>', $$specs{"TypeFront-$form"} );
          } # end if Material Found
        } # end if TypeFront

        if ( $$specs{"TypeBack-$form"}) {
          my %BackMaterialPrice;
          if ( my $BackMaterial = openprint::Material->find_one(name=>$$specs{"TypeBack-$form"} ) ) {
            %BackMaterialPrice = $BackMaterial->get_price( $area, $Equipment );
            if ( ! %BackMaterialPrice ) {
              if ( $$specs{"chkOverrideEquipment$qty_index"} eq 'Y' ) {
                $$specs{alert} .= "There is no price for $$BackMaterial{description} on $$Equipment{name}.<br/>";
              } # end if
              next;
            } # end if
            if ( $BackMaterialPrice{units} eq 'per square foot' ) {
              $BackMaterialPrice{Total} = $BackMaterialPrice{Price} * $area / 144;
              $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Material on Back: $%1$.2f %2$s * %4$.2f square feet = $%3$.2f<br/>', @BackMaterialPrice{'Price','units','Total'}, $area/144 );
            } elsif ( $BackMaterialPrice{units} eq 'per m square inches' ) {
              $BackMaterialPrice{Total} = $BackMaterialPrice{Price} * $area / 1000;
              $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Material on Back: $%1$.2f %2$s * %4$.2f square inches = $%3$.2f<br/>', @BackMaterialPrice{'Price','units','Total'}, $area/1000 );
            } else {
              $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Material on Front: unknown units: (%s)<br/>', $BackMaterialPrice{units} );
            } # end if
            $price += $BackMaterialPrice{Total};
            $MPrice += ( 1000 / $$imposition{imposition} ) * $BackMaterialPrice{Total}/$sheets;
          } else {
            $$specs{'hdnBreakdown'.$qty_index} .= sprintf('No Material found for Back: (%s)<br/>', $$specs{"TypeBack-$form"} );
          } # end if Material Found
        } # end if TypeFront

        $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Total: $%.2f<br/><br/>', $price );

        if ((!$bestPrice{Price}) or ($bestPrice{Price} > $price)) {
          $bestPrice{Price} = $price;
          $bestPrice{MPrice} = $MPrice;
          $bestPrice{Equipment} = $Equipment;
        } # end if
      } # end foreach equipment

      if (%bestPrice) {
        if ($bestPrice{Price} < $MinimumCharge{Price}) {
          $$specs{'hdnBreakdown'.$qty_index} .= sprintf('<br/>Using minimum charge: $%.2f<br/>', $MinimumCharge{Price} );
          $bestPrice{Price} = $MinimumCharge{Price};
        } # endif
      } else {
        $$specs{Status} = 'uncalculated';
        $bestPrice{Price} = 0;
      } # end if
      if ($bestPrice{Equipment}) {
        $$specs{"ddmEquipment-$form-$qty_index"} = $bestPrice{Equipment}->id();
        $totalPrice{Price} += $bestPrice{Price};
        $totalPrice{MPrice} += $bestPrice{MPrice};
      }
    } # end foreach signature

		if ((!$$specs{"OverridePrice$qty_index"}) or ( $$specs{"OverridePrice$qty_index"} ne 'Y')) {
      $totalPrice{Price} //= 0;
      $totalPrice{UnitPrice} = $totalPrice{Price}/$qty;
			if ( $$specs{"Markup$qty_index"} ) {
				$totalPrice{Price} *= 1+$$specs{"Markup$qty_index"}/100;
				$totalPrice{UnitPrice} *= 1+$$specs{"Markup$qty_index"}/100;
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Using %s%% markup = $%.2f<br/>', $$specs{"Markup$qty_index"}, $totalPrice{Price} );
			}
			if ( $Project->markup() ) {
				$totalPrice{Price} *= 1+$Project->markup()/100;
				$totalPrice{UnitPrice} *= 1+$Project->markup()/100;
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Using %s%% project markup = $%.2f<br/>', $Project->markup(), $totalPrice{Price} );
			} 
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $totalPrice{Price} );
      $$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $totalPrice{UnitPrice} );
		} else {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"} );
			$$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{"txtUnitPrice$qty_index"} );
		} # endif
    $totalPrice{MPrice} *= (1+$Project->markup()/100) if $Project->markup();
		$$specs{"MPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $totalPrice{MPrice} );
	} # end foreach qty_index
	return $$specs{Status};
} # end sub calc

#($r->log, $dbh, $service->{type}, $pid, $sid, $specs, $variable)
sub display {
	my ( $log, $dbh, $type, $project_index, $service_index, $specs, $variable ) = @_;

	my $Project = new openprint::Project( $project_index );

  my %page;
	my @equipment = openprint::Equipment->find( 'Specifications' => {'Laminating Capable'=>'Y'}, 'useinestimating'=>1,'order'=>'strName');
	foreach my $qty_index ( $Project->quantity_indexes() ) {	
    $page{'ddmEquipment'.$qty_index} = ssi::make_drop_down( [ map { $_->strid(), $_->name() } @equipment ], $$variable{'ddmEquipment'.$qty_index} );

    my @sigs = $Project->signatures({ sort=>1 });
    foreach my $signature_service_index (@sigs) {
      my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
      my $form  = $$sig_specs{SignatureIndex} // 1;
      if (!$$specs{"override_calliper-$form"} or $$specs{"override_calliper-$form"} ne 'Y') {
        my $imposition = new openprint::Imposition();
        $imposition->load( $sig_specs, $qty_index, $Project );
        my $stock = $imposition->Paper();
        $$specs{"calliper-$form"} = $stock->calliper();
      }
    } # end foreach sig
	} # end foreach qty_index

  return \%page;
} # end sub display

sub summary {
	my ( $Project, $service_index, $specs, $qty_index ) = @_;
  my $summary = '';
  my @sigs = $Project->signatures({ sort=>1 });
  foreach my $signature_service_index (@sigs) {
    my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
    my $form  = $$sig_specs{SignatureIndex};

    if ($$specs{"TypeFront-$form"} or $$specs{"TypeBack-$form"}) {
      $summary .= (@sigs > 1) ? 'Form '.$form.' ': '';
      if ($qty_index) {
        my $equipment = openprint::Equipment->find_one(id=>$$specs{'ddmEquipment-'.$form.'-'.$qty_index});
        $summary .= 'on '.$equipment->name().'<br/>' if $equipment;
      } else {
        $summary .= join(', ', 
          ($$specs{"TypeFront-$form"} ? $$specs{"TypeFront-$form"}.' on front' : ()),
          ($$specs{"TypeBack-$form"} ? $$specs{"TypeBack-$form"}.' on back' : ()),
        ).'<br/>';
      }
    }
  }
  return $summary;
} # end sub summary

sub save {
} # end sub save

sub equipment_fits {
  my ( $Equipment, $I, $Stock ) = @_;
  if ( ( $_ = $Equipment->fits( $I->sheet_width(), $I->sheet_height() ) ) and ( $_ = $Equipment->fits( $I->layout_width(), $I->layout_height() ) ) ) {
    return $_;
  }
  if ( my $min_calliper = $Equipment->specification( 'Minimum Calliper')) {
    if ( $min_calliper > $$Stock{calliper} ) {
      return "Calliper too thin stock calliper $$Stock{calliper} < minimum($min_calliper).";
    }
  }
  if ( my $max_calliper = $Equipment->specification('Maximum Calliper')) {
    if ( $max_calliper < $$Stock{calliper} ) {
      return "Calliper too thick stock calliper $$Stock{calliper} > maximum($max_calliper).";
    }
  }
  return;
}

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
        "chkOverrideDimensions-$form",
      );
    } # end foreach sig
  } # end if
  return @v;
} # end sub has_overrides

1;
__END__
