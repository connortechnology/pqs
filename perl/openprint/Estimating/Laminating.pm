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

package openprint::Estimating::Laminating;
use strict;
use warnings;
$Data::Dumper::Maxdepth = 1;

use openprint::Imposition;
require openprint::Equipment;
require openprint::service;

require sql;
use vars qw( %ServicePrices %MaterialPrices %Specifications %MaterialSpecifications);
%ServicePrices = (
  LaminatingMinimumCharge => { units=>[] },
  LaminatingMakeReady => { units => [] },
  Laminating => {
    units => ['per m','per 1000', 'per hour', 'per inch', 'per linear inch'],
    range_units => [ 'per 1000', 'per square foot', 'per m square inches' ],
  },
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
  '.*Laminate.*' => {
    units => [ 'per square foot', 'per m square inches' ],
    range_units => [ 'per square foot', 'per m square inches' ],
  }
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
  'Laminating Count' => { units => ['Net Sheets', 'Gross Sheets'], range_units=>[] },
  'Laminating Waste'  => { units => 'Percent' },
  'Laminating Style' => { values => [ 'Sheet','Final Pieces' ] },
  #'Laminating Capable' => { values => [ 'Y'|'N' ] },
  'Laminating Sides' => { values => ['Both', 'Single'] },
  'Maximum Sheet Width' => { units => 'Inches' },
  'Maximum Sheet Length' => { units => 'Inches' },
  'Minimum Sheet Width' => { units => 'Inches' },
  'Minimum Sheet Length' => { units => 'Inches' },
  'Maximum Calliper' => { units => 'Inches' },
  'Minimum Calliper' => { units => 'Inches' },
  'Run Speed.*' => { units => 'inches per hour' },
);

sub SpecificationConfiguration {
  my $name = shift;
  return $Specifications{$name} if $Specifications{$name};
  return undef;
}

%MaterialSpecifications = (
  '.*Laminate.*' => {
    'Run Speed' => { units => ['inches per hour'] },
  },
);

sub MaterialSpecificationsConfiguration {
  if (@_) {
    my $name = shift;
    return $MaterialSpecifications{$name} if $MaterialSpecifications{$name};
    foreach my $key (keys %MaterialSpecifications) {
      return $MaterialSpecifications{$key} if ($name =~ /$key/i);
    }
    $openprint::log->debug(" $name => $MaterialSpecifications{$name}");
    return undef;
  }
  return \%MaterialSpecifications;
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
    my $sig_specs = openprint::service::get_specs_ref($Project, $s_s_id);
    my $form = $$sig_specs{SignatureIndex} || $$sig_specs{Form} || 1;
    push @v, (
      "txtWidth-$form", "txtHeight-$form", "chkOverrideDimensions-$form",
      "sheet_width-$form", "sheet_height-$form", "override_sheetsize-$form",
      "calliper-$form", "override_calliper-$form",
      "TypeFront-$form", "TypeBack-$form",
      "film_width-$form", "override_film_width-$form",
      "custom_film_width-$form",
    );
    foreach my $qty_index ( $Project->quantity_indexes() ) {
      push @v, (
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
  #'ddmEquipment1', 'ddmEquipment2', 'ddmEquipment3',
	'alert', 'Status',
	'hdnBreakdown1', 'hdnBreakdown2', 'hdnBreakdown3',
);

sub outputs {
  my $p_id = shift;
  my @o = @outputs;
  my $Project = new openprint::Project($p_id);
  foreach my $s_s_id ( $Project->signatures() ) {
    my $sig_specs = openprint::service::get_specs_ref($Project, $s_s_id);
    my $form = $$sig_specs{SignatureIndex} || $$sig_specs{Form} || 1;
    push @o, (
      "txtWidth-$form", "txtHeight-$form",
      "calliper-$form",
      "TypeFront-$form","TypeBack-$form",
      "film_width-$form",
    );
    foreach my $qty_index ( $Project->quantity_indexes() ) {
        push @o, (
          "ddmEquipment-$form-$qty_index",
        );
      }
    }
	return @o;
}

my $MakeReady;
my $Service;
my @all_equipment;
my $ServiceType;

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $Project = new openprint::Project( $project_index );
  my $services = $Project->services();
  $ServiceType = $Project->ServiceType($service_index);
  if (ref $specs ne 'HASH') {
    my ( $caller, undef, $line ) = caller;
    $openprint::log->error("Invalid call structure from $caller:$line");
	( $log, $dbh, $variable, $project_index, $service_index, undef, $specs ) = @_;
  }
  $log->debug(Data::Dumper::Dumper($specs));

  $$specs{alert} = '';

  my $print_service_id = $Project->get_print_container();
  my $printing_specs = openprint::service::get_specs_ref($Project, $print_service_id);

  my $has_lamination = 0;
  my @sigs = $Project->signatures({ sort=>1 });
  foreach my $signature_service_id (@sigs) {
    my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_id );
    my $form = $$sig_specs{SignatureIndex} || $$sig_specs{Form} || 1;
    $form = $$sig_specs{Form} || 1 if $form > 10;
    my $stock = openprint::Paper::load_from_signature( $Project, $sig_specs, 1 );

    $$specs{"override_film_width-$form"} //= '';
    $$specs{'chkOverrideDimensions-'.$form} //= '';
    $$specs{'override_sheetsize-'.$form} //= '';
    $$specs{'override_calliper-'.$form} //= '';

    if ($$specs{'chkOverrideDimensions-'.$form} ne 'Y') {
      if ($$sig_specs{final_width} and $$sig_specs{final_height}) {
        @$specs{'txtWidth-'.$form,'txtHeight-'.$form} = @$sig_specs{'final_width','final_height'};
      } elsif (!$$sig_specs{'txtWidth'}) {
        @$specs{'txtWidth-'.$form,'txtHeight-'.$form} = @$printing_specs{'final_width','final_height'};
      } else {
        @$specs{'txtWidth-'.$form,'txtHeight-'.$form} = @$sig_specs{'txtWidth','txtHeight'};
      }
    }
    if ($$specs{'override_sheetsize-'.$form} ne 'Y') {
      $$specs{'sheet_width-'.$form} = $stock->width();
      $$specs{'sheet_height-'.$form} = $stock->height();
    } else {
      $stock->width($$specs{'sheet_width-'.$form});
      $stock->height($$specs{'sheet_height-'.$form});
    }

    if ($$specs{'override_calliper-'.$form} ne 'Y') {
      $$specs{"calliper-$form"} = $stock->calliper();
      $$specs{"calliper_pt-$form"} = $stock->calliper() * 1000;
      $$specs{"calliper_mm-$form"} = $stock->calliper() * 25.4;
    } # end if

    if ( $$specs{'LaminatingType-'.$form} ) {
      $$specs{"TypeFront-$form"} = $$specs{"TypeBack-$form"} = $$specs{'LaminatingType-'.$form};
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

  @all_equipment = openprint::Equipment->find(
    'servicetype_id any' => $ServiceType->id(),
    useinestimating=>1,
    order=>'lower(strName)');

  if (!@all_equipment) {
    $$specs{alert} = 'We have no laminating equipment.';
    return $$specs{Status} = 'uncalculated';
  } # end if

	$$specs{Status} = 'calculated';

	$MakeReady = openprint::Service->find_one( name=>$$specs{ServiceType}.'MakeReady' );
	$Service = openprint::Service->find_one( name=>$$specs{ServiceType} );

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"Markup$qty_index"} =~ s/[^\d\.\-]//g if $$specs{"Markup$qty_index"};
		$$specs{"txtPrice$qty_index"} =~ s/[^\d\.]//g if $$specs{"txtPrice$qty_index"};
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
    $$specs{"hdnBreakdown$qty_index"} = '';
		my $qty = int $$specs{"txtQuantity$qty_index"};
		next if ! $qty;

    my %totalPrice = (
      Price => 0,
      UnitPrice => 0,
      MPrice => 0,
      breakdown => '',
    );

    foreach my $signature_service_id (@sigs) {
      my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_id );
      my $form = $$sig_specs{SignatureIndex} || $$sig_specs{Form} || 1;
      $form = $$sig_specs{Form} || 1 if $form > 10;

      if ((!$$specs{"TypeFront-$form"}) and (!$$specs{"TypeBack-$form"})) {
        #$$specs{'hdnBreakdown'.$qty_index} .= " not doing lamination on form $form<br/>";
        next;
      }
      my $imposition = new openprint::Imposition();
      $imposition->load( $sig_specs, $qty_index, $Project );
      my $stock = $imposition->Paper();
      $$stock{calliper} = $$specs{"calliper-$form"}; # Overrides done earlier

      $$specs{'hdnBreakdown'.$qty_index} .= 'Signature ' . $form . ' printed: ' .openprint::service::summary( $Project, $signature_service_id, $qty_index ).'. Imposition image dimensions are '.$$imposition{layout_width}.'&quot; x '.$$imposition{layout_height}.'&quot;<br/>';
      if (!$$imposition{imposition}) {
        $$specs{'hdnBreakdown'.$qty_index} .= 'No imposition loaded.<br/>';
        next;
      }
      my %sig_price = signature_calc($Project, $specs, $qty_index, $imposition);
      if (%sig_price) {
        if ($sig_price{total} < $MinimumCharge{Price}) {
          $sig_price{breakdown} .= sprintf('<br/>Using minimum charge: $%.2f<br/>', $MinimumCharge{Price} );
          $sig_price{total} = $MinimumCharge{Price};
        } # endif
      } else {
        $$specs{Status} = 'uncalculated';
      } # end if

      if ($sig_price{film_width}) {
        $$specs{"film_width-$form"} = $sig_price{film_width};
      } else {
        $log->error("No film width in price?");
      }

      if ($sig_price{Equipment}) {
        $$specs{"ddmEquipment-$form-$qty_index"} = $sig_price{Equipment}->id();
        $totalPrice{Price} += $sig_price{total};
        $totalPrice{MPrice} += $sig_price{MPrice};
      }
      $totalPrice{alert} .= $sig_price{alert} if $sig_price{alert};
      $totalPrice{breakdown} .= $sig_price{breakdown} if $sig_price{breakdown};
    } # end foreach signature

    $$specs{'hdnBreakdown'.$qty_index} .= $totalPrice{breakdown};
    $$specs{alert} .= $totalPrice{alert} if $totalPrice{alert};
    
		if ((!$$specs{"OverridePrice$qty_index"}) or ($$specs{"OverridePrice$qty_index"} ne 'Y')) {
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
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"} // 0 );
			$$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{"txtUnitPrice$qty_index"} // 0 );
		} # endif
    $totalPrice{MPrice} *= (1+$Project->markup()/100) if $Project->markup();
		$$specs{"MPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $totalPrice{MPrice} );
	} # end foreach qty_index
	return $$specs{Status};
} # end sub calc

sub signature_calc {
  my ($Project, $specs, $qty_index, $imposition) = @_;

  my $sig_specs = $$imposition{specs};
  my $form = $$sig_specs{SignatureIndex} || $$sig_specs{Form} || 1;
	my $qty = int $$specs{"txtQuantity$qty_index"};

  my %sig_price = (
    breakdown => '',
    alert => '',
    total => 0,
    MPrice => 0,
  );

  my @equipment = ();
  if ($$specs{"chkOverrideEquipment-$form-$qty_index"} and ($$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' and $$specs{"ddmEquipment-$form-$qty_index"})) {
    @equipment = openprint::Equipment->find(id=>$$specs{"ddmEquipment-$form-$qty_index"});
  } else {
    @equipment = @all_equipment;
  } # end if
  if (!@equipment) {
    $sig_price{alert} .= 'No equipment found for form '.$form.' quantity '.$qty_index.'.<br/>';
    return %sig_price;
  }

  my %best_equipment_price;
  my %equipment_price;

  foreach my $equipment (@equipment) {
    %equipment_price = %sig_price;
    $equipment_price{Equipment} = $equipment;

    my $error = '';

    my $style = $equipment->specification('Laminating Style') // 'Final Pieces';
    if ($style eq 'Final Pieces') {
      if ( 
        (my $reason1 = $equipment->fits( $$specs{"txtWidth-$form"}, undef, $$specs{"calliper-$form"}, ) ) and
        (my $reason2 = $equipment->fits( $$specs{"txtHeight-$form"}, undef, $$specs{"calliper-$form"} ) ) 
      ) {
        $error .= 'For ' . $equipment->name() . ': '. $reason1  . '<br/>' . $reason2;
      } # end if
    } else { # Sheets
      if ( (my $reason1 = $equipment->fits( undef, undef, $$specs{"calliper-$form"} ))) {
        $error .= 'For ' . $equipment->name() . ': '. $reason1  . '<br/>';
      } # end if
    }

    if ($error) {
      $equipment_price{breakdown} .= $error; # WHY
      %best_equipment_price = %equipment_price if !%best_equipment_price;
      next;
    }

    my $sides = $equipment->specification('Laminating Sides') // 'Single';
    if ((( !$$specs{"TypeFront-$form"}) or (!$$specs{"TypeBack-$form"})) and ( $sides eq 'Both' ) ) {
      if ( $$specs{"chkOverrideEquipment-$form-$qty_index"} and ($$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y')) {
        $equipment_price{alert} .= 'The chosen laminator must do both sides.  You have chosen no lamination for one of the sides.<br/>';
      } # end if
      next;
    } # end if

    my $maximum_sheet_width = $equipment->specification('Maximum Sheet Width') // '';
    my $maximum_sheet_length= $equipment->specification('Maximum Sheet Length') // '';

    my $Speed = $equipment->Specification('Laminating Run Speed') || $equipment->Specification('Run Speed');

    $equipment_price{breakdown} .= sprintf('Equipment: %s max Width: %s&quot; Length: %s&quot;'.( $Speed ? ' base runspeed: '.$Speed->value().$Speed->units():'').'<br/>',
      $equipment->name(), $maximum_sheet_width, $maximum_sheet_length);

    my $film_width_options = $equipment->specification('Laminate Width') // '';
    my @film_widths = sort { $b <=> $a } map { $_ =~ s/[^\d\.]//; $_ } split(',', $film_width_options) if $film_width_options;

    if (!@film_widths) {
      $openprint::log->error("Laminate widths on $$equipment{name}: @film_widths from $film_width_options");
    } else {
      $openprint::log->debug("Laminate widths on $$equipment{name}: @film_widths from $film_width_options");
    }

    if ($$specs{"override_film_width-$form"} eq 'Y') {
      if ($$specs{"custom_film_width-$form"}) {
        @film_widths = map { $_ =~ s/[^\d\.]//; $_ } ($$specs{"custom_film_width-$form"});
      } else {
        #if ($film_width_options) {
        #if ($$specs{"film_width-$form"} and !sets::isin($$specs{"film_width-$form"}, \@film_widths)) {
        #$equipment_price{breakdown} .= "Equipment forced laminate width ".$$specs{"film_width-$form"}." is not in @film_widths<br/>";
        #next;
        #}
        #}
        @film_widths = map { $_ =~ s/[^\d\.]//; $_ } ($$specs{"film_width-$form"});
      }
    }

    my %best_laminate_price;
    my %laminate_price;
    foreach my $film_width (@film_widths) {
      %laminate_price = %equipment_price;

      my $impo = get_laminating_imposition($equipment, $imposition, $specs, \%laminate_price, $qty, $film_width);
      if ($impo) {
        $laminate_price{breakdown} .= 'Laminate width is '.($$specs{"override_film_width-$form"} eq 'Y'?'overriden to ':'').$film_width .'&quot;<br/>';
        %laminate_price = get_price($equipment, $impo, \%laminate_price, $qty);
      } else {
        $openprint::log->debug("No impo for film width $film_width");
      }

      if (!$best_laminate_price{total} or ($laminate_price{total} and ($best_laminate_price{total} > $laminate_price{total}))) {
        #$openprint::log->debug("Have better laminate price: $best_laminate_price{total} > $laminate_price{total} on $film_width $laminate_price{breakdown}");
        %best_laminate_price = %laminate_price;
      } # end if
      last if $laminate_price{total}; # HACK, have valid, widest
    } # end foreach film_width
    $openprint::log->debug("best laminate price: ".Data::Dumper::Dumper(\%best_laminate_price));

    if ((!%best_equipment_price) or ($best_laminate_price{total} and ($best_equipment_price{total} > $best_laminate_price{total}))) {
      #$openprint::log->debug("Have better equipment price: $best_equipment_price{total} > $best_laminate_price{total} on $$equipment{name}");
      %best_equipment_price = %best_laminate_price;
    } # end if
  } # end foreach equipment

  return %best_equipment_price;
} # end sub signature_calc

sub get_price {
  my ($equipment, $imposition, $price, $qty) = @_;

  my %price = %{$price}; # make a copy
  my $area = $$imposition{area};
  my $laminate_area = $$imposition{laminate_area};
  my $width = $$imposition{width};
  my $length = $$imposition{length};
  my $film_width = $price{film_width} = $$imposition{film_width};
  my $sheets = $$imposition{sheets};
  my $style = $equipment->specification('Laminating Style') // 'Final Pieces';
  my $sides = $equipment->specification('Laminating Sides') // 'Single';

  my $FrontMaterial = openprint::Material->find_one(name=>$$imposition{TypeFront}) if $$imposition{TypeFront};
  my $BackMaterial = openprint::Material->find_one(name=>$$imposition{TypeBack}) if $$imposition{TypeBack};

  my %SetupPrice = $MakeReady->get_price(undef, $equipment) if $MakeReady;
  $price{total} += $SetupPrice{Price};
  $price{breakdown} .= '<table>';
  my $setup_overs = $$imposition{setup_overs};
  my $run_overs = $$imposition{run_overs};

  my $inches_per_hour;
  my $Speed = $equipment->Specification('Laminating Run Speed') || $equipment->Specification('Run Speed');
  if ( $Speed ) {
    if ( lc $$Speed{units} eq 'inches per hour' ) {
      $inches_per_hour = $$Speed{value};
    } else {
      $price{breakdown} .= "Unknown speed units $$Speed{units}<br/>";
      $inches_per_hour = 720;
    } # end if
  } else {
    $price{breakdown} .= 'No base Run Speed set<br/>';
    $openprint::log->error(Data::Dumper::Dumper($Speed));
    $inches_per_hour = 720;
  } # end if

  $price{breakdown} .= '<tr><td class="desc">Impressions: net: '.$qty.' + setup overs: '.$setup_overs->to_breakdown().' + run overs: '.$run_overs->to_breakdown().' = '.$$imposition{sheets}.'</td><td></td></tr>';
  my $linear_length = Math::Round::nearest(0.01, $length * $sheets);
  $price{breakdown} .= '<tr><td class="desc">Laminate length: '.$length.'&quot; * '.$sheets.' sheets = '.Number::Format::format_number($linear_length).'&quot;</td><td class="Price"></td></tr>';
  $price{breakdown} .= '<tr><td colspan="2" class="desc">Laminate quantity using '.$length.'" x '.$film_width.'" * '.$sheets.' sheets '.
  ($$imposition{waste}{total} ? ' + '.$$imposition{waste}->to_breakdown().' waste' : '').' = '.Number::Format::format_number($laminate_area).' square inches</td></tr>';
  $price{breakdown} .= sprintf('<tr><td class="desc">Setup: </td><td class="Price">$%.2f</td><tr>', $SetupPrice{Price});

  my %ServicePrice = $Service->get_price( undef, $equipment ) if $Service;
  if (%ServicePrice) {
    if ($ServicePrice{range_units} eq 'per 1000' or $ServicePrice{range_units} eq 'per m') {
      %ServicePrice = $Service->get_price( $qty, $equipment );
    } elsif ($ServicePrice{range_units} eq 'per square foot') {
      %ServicePrice = $Service->get_price( $area/144, $equipment );
    } elsif ($ServicePrice{range_units} eq 'per m square inches') {
      %ServicePrice = $Service->get_price( $area/1000, $equipment );
    }
  } # end if %ServicePrice

  if ( %ServicePrice ) {
    $ServicePrice{units} //= '';
    $ServicePrice{units} = lc $ServicePrice{units};

    if ( $ServicePrice{units} eq 'per m' or $ServicePrice{units} eq 'per 1000') {
      $ServicePrice{Total} = ($ServicePrice{Price} * $qty)/1000;
      if ($$imposition{TypeFront} and $$imposition{TypeBack} and $sides eq 'Single') {
        $ServicePrice{Total} *= 2;
        $price{breakdown} .= sprintf('<tr><td class="desc">Service: $%1$s %2$s * %4$f * 2 sides</td><td class="Price">$%3$.2f</td></tr>',
          @ServicePrice{'Price','units','Total'}, $qty );
      } else {
        $price{breakdown} .= sprintf('<tr><td class="desc">Service: $%1$s %2$s * %4$f</td><td class="Price">$%3$.2f</td></tr>',
          @ServicePrice{'Price','units','Total'}, $qty );
      }
      $price{MPrice} += $ServicePrice{Price};
    } elsif ( $ServicePrice{units} eq 'per inch' or $ServicePrice{units} eq 'per linear inch') {
      $ServicePrice{Total} = Math::Round::nearest(0.01, $ServicePrice{Price} * $linear_length);
      if ($sides eq 'Single') {

        if ($$imposition{TypeFront}) {
          my $front_inches_per_hour = $inches_per_hour;
          my $front_speed = $FrontMaterial->Specification('Run Speed', undef, $equipment)
            || $equipment->Specification('Run Speed '.$FrontMaterial->name())
            || $equipment->Specification('Run Speed '.$FrontMaterial->description())
            ;
          if ( $front_speed ) {
          $openprint::log->debug("front speed".Data::Dumper::Dumper($front_speed));
            if ( lc $$front_speed{units} eq 'inches per hour' ) {
              $front_inches_per_hour = $$front_speed{value};
            } else {
              $price{breakdown} .= "Unknown speed units on $$FrontMaterial{name}: $$front_speed{units}<br/>";
            } # end if
          } # end if

          my %FrontServicePrice = %ServicePrice;
          $price{breakdown} .= sprintf('<tr><td class="desc">Service Front: $%1$s %2$s * %4$s linear inches @%5$d%6$s</td><td class="Price">$%3$.2f</td></tr>',
            @FrontServicePrice{'Price','units','Total'},
            Number::Format::format_number($linear_length),
            $front_inches_per_hour, 'inches per hour',
          );
        }
        if ($$imposition{TypeBack}) {
          my $back_inches_per_hour = $inches_per_hour;
          my $back_speed = $BackMaterial->Specification('Run Speed', undef, $equipment)
            || $equipment->Specification('Run Speed '.$BackMaterial->name())
            || $equipment->Specification('Run Speed '.$BackMaterial->description())
            ;
          if ( $back_speed ) {
          $openprint::log->debug("back speed".Data::Dumper::Dumper($back_speed));
            if ( lc $$back_speed{units} eq 'inches per hour' ) {
              $back_inches_per_hour = $$back_speed{value};
            } else {
              $price{breakdown} .= "Unknown speed units on $$BackMaterial{name}: $$back_speed{units}<br/>";
            } # end if
          } # end if
          my %BackServicePrice = %ServicePrice;
          $price{breakdown} .= sprintf('<tr><td class="desc">Service Back: $%1$s %2$s * %4$s linear inches @%5$d%6$s</td><td class="Price">$%3$.2f</td></tr>',
            @BackServicePrice{'Price','units','Total'},
            Number::Format::format_number($linear_length),
            $back_inches_per_hour, 'inches per hour',
          );
          $ServicePrice{Total} += $BackServicePrice{Total};
          $ServicePrice{Price} += $BackServicePrice{Price};
        }
      } else {
        $price{breakdown} .= sprintf('<tr><td class="desc">Service %5$s: $%1$s %2$s * %4$s linear inches</td><td class="Price">$%3$.2f</td></tr>',
          @ServicePrice{'Price','units','Total'},
          Number::Format::format_number($linear_length),
          (($$imposition{TypeFront} and $$imposition{TypeBack}) ? 'both sides' : '')
        );
      } # end if sides

      $price{MPrice} += Math::Round::nearest( 0.01, $ServicePrice{Price} * ($length * 1000 / $$imposition{imposition}));
    } elsif ( $ServicePrice{units} eq '/Hr' or $ServicePrice{units} eq 'per hour') {

      if ($style ne 'Sheet' ) {
        my $hours = Math::Round::nearest( 0.01, $length * ( $qty / $$imposition{imposition} ) / $inches_per_hour );
        $ServicePrice{Total} = Math::Round::nearest( 0.01, $ServicePrice{Price} * $hours );
        if ($sides eq 'Single' and $$imposition{TypeFront} and $$imposition{TypeBack}) {
          $price{breakdown} .= sprintf('<tr><td class="desc">Service: Front $%1$.2f %2$s * %4$.2fhours</td><td class="Price">$%3$.2f</td></tr>',
            @ServicePrice{'Price','units','Total'}, $hours);
          $price{breakdown} .= sprintf('<tr><td class="desc">Service: Back $%1$.2f %2$s * %4$.2fhours</td><td class="Price">$%3$.2f</td></tr>',
            @ServicePrice{'Price','units','Total'}, $hours);
          $ServicePrice{Total} *= 2;
          $ServicePrice{Price} *= 2;
        } else {
          $price{breakdown} .= sprintf('<tr><td class="desc">Service: Both sides $%1$.2f %4$s * %2$.2fhours</td><td class="Price">$%3$.2f</td></tr>',
            @ServicePrice{'Price','units','Total'}, $hours);
        }
        $price{MPrice} += Math::Round::nearest( 0.01, $ServicePrice{Price} * ( $length * ( 1000 / $$imposition{imposition} ) ) / $inches_per_hour );
      } else {
        my $hours = Math::Round::nearest(0.01, $length * $sheets / $inches_per_hour);
        $price{breakdown} .= "Runtime = length $length * $sheets / $inches_per_hour<br/>";
        $ServicePrice{Total} = Math::Round::nearest( 0.01, $ServicePrice{Price} * $hours );
        if ($sides eq 'Single' and $$imposition{TypeFront} and $$imposition{TypeBack}) {
          $price{breakdown} .= sprintf('<tr><td class="desc">Service: Front $%1$.2f %2$s * %4$.2fhours</td><td class="Price">$%3$.2f</td></tr>',
            @ServicePrice{'Price','units','Total'}, $hours);
          $price{breakdown} .= sprintf('<tr><td class="desc">Service: Back $%1$.2f %2$s * %4$.2fhours</td><td class="Price">$%3$.2f</td></tr>',
            @ServicePrice{'Price','units','Total'}, $hours);
          $ServicePrice{Total} *= 2;
          $ServicePrice{Price} *= 2;
        } else {
          $price{breakdown} .= sprintf('<tr><td class="desc">Service: Both sides: $%1$.2f %2$s * %4$.2fhours</td><td class="Price">$%3$.2f</td></tr>',
            @ServicePrice{'Price','units','Total'}, $hours);
        }
        $price{MPrice} += Math::Round::nearest( 0.01, $ServicePrice{Price} * ( $length * ( 1000 / $$imposition{imposition} ) ) / $inches_per_hour );
      }
    } else {
      $price{breakdown} .= "<tr><td class=\"warn\">Unknown units ($ServicePrice{units}) for $ServicePrice{ServiceType}</td><td class=\"Price\"></td></tr>";
    } # end if
    $price{total} += $ServicePrice{Total};
  } else {
    $price{breakdown} .= "<tr><td class=\"warn\">No Service price for ".__PACKAGE__.'</td><td class="Price"></td></tr>';
  } # end if

  if ( $$imposition{TypeFront} ) {
    my $FrontMaterialPrice;
    if (my $FrontMaterial = $$imposition{FrontMaterial}) {
      $FrontMaterialPrice = $FrontMaterial->get_Price( $area, $equipment );
      $FrontMaterialPrice->units();
      if ( ! $FrontMaterialPrice ) {
        #if ( $$specs{"chkOverrideEquipment$qty_index"} eq 'Y' ) {
          $$price{alert} .= "There is no price for $$FrontMaterial{description} on $$equipment{name}.<br/>";
          #} # end if

        next;
      } # end if
      if ( $$FrontMaterialPrice{units} eq 'per square foot' ) {
        $$FrontMaterialPrice{Total} = $$FrontMaterialPrice{Price} * $laminate_area / 144;
        $price{breakdown} .= sprintf('<tr><td class="desc">Material on Front: $%1$.6f %2$s * %4$s square feet</td><td class="Price">$%3$.2f</td></tr>',
          @$FrontMaterialPrice{'Price','units','Total'},
          Number::Format::format_number($laminate_area/144) );
      } elsif ( $$FrontMaterialPrice{units} eq 'per m square inches' ) {
        $$FrontMaterialPrice{Total} = $$FrontMaterialPrice{Price} * $laminate_area / 1000;
        $price{breakdown} .= sprintf('<tr><td class="desc">Material on Front: $%1$.5f %2$s * %4$s square inches</td><td class="Price">$%3$.2f</td></tr>',
          @$FrontMaterialPrice{'Price','units','Total'},
          Number::Format::format_number($laminate_area) );
      } else {
        $price{breakdown} .= sprintf('<tr><td colspan="2">Material on Front: unknown units: (%s)</td></tr>', $FrontMaterialPrice->to_string() );
      } # end if
      $price{total} += $$FrontMaterialPrice{Total};
      $price{MPrice} += ( 1000 / $$imposition{imposition} ) * $$FrontMaterialPrice{Total}/$sheets;
    } else {
      $price{breakdown} .= sprintf('<tr><td colspan="2">No Material found for Front: (%s)</td></tr>', $$imposition{TypeFront} );
    } # end if Material Found
  } # end if TypeFront

  if ( $$imposition{TypeBack}) {
    my $BackMaterialPrice;
    if ( my $BackMaterial = $$imposition{BackMaterial}) {
      $BackMaterialPrice = $BackMaterial->get_Price( $area, $equipment );
      if ( ! $BackMaterialPrice ) {
        #if ( $$specs{"chkOverrideEquipment$qty_index"} eq 'Y' ) {
          $price{alert} .= "There is no price for $$BackMaterial{description} on $$equipment{name}.<br/>";
          #} # end if
        next;
      } # end if
      if ( $$BackMaterialPrice{units} eq 'per square foot' ) {
        $$BackMaterialPrice{Total} = $$BackMaterialPrice{Price} * $laminate_area / 144;
        $price{breakdown} .= sprintf('<tr><td class="desc">Material on Back: $%1$.5f %2$s * %4$s square feet</td><td class="Price">$%3$.2f</td></tr>',
          @$BackMaterialPrice{'Price','units','Total'},
          Number::Format::format_number($laminate_area/144) );
      } elsif ( $$BackMaterialPrice{units} eq 'per m square inches' ) {
        $$BackMaterialPrice{Total} = $$BackMaterialPrice{Price} * $laminate_area / 1000;
        $price{breakdown} .= sprintf('<tr><td class="desc">Material on Back: $%1$.5f %2$s * %4$s square inches</td><td class="Price">$%3$.2f</td></tr>',
          @$BackMaterialPrice{'Price','units','Total'},
          Number::Format::format_number($laminate_area) );
      } else {
        $price{breakdown} .= sprintf('<tr><td class="warn" colspan="2">Material on Back: unknown units: (%s)</td></tr>', $$BackMaterialPrice{units} );
      } # end if
      $price{total} += $$BackMaterialPrice{Total};
      $price{MPrice} += ( 1000 / $$imposition{imposition} ) * $$BackMaterialPrice{Total}/$sheets;
    } else {
      $price{breakdown} .= sprintf('<tr><td class="warn" colspan="2">No Material found for Back: (%s)</td></tr>', $$imposition{TypeBack} );
    } # end if Material Found
  } # end if TypeFront

  $price{breakdown} .= sprintf('<tr class="totals"><td class="desc">Total:</td><td class="Price">$%.2f</td></tr></table><br/>', $price{total} );
  return %price;
} # end sub get_price($equipment, $imposition);

sub get_laminating_imposition {
  my ($equipment, $sig_imposition, $specs, $price, $qty, $film_width) = @_;

  my $length;
  my $layout_width;

  my $width;
  my $imposition = $sig_imposition->copy();
  my $form = $sig_imposition->form();
  $openprint::log->debug("DOING film width: $film_width form $form");
  $$imposition{film_width} = $film_width;
  @$imposition{'TypeFront','TypeBack'} = @$specs{"TypeFront-$form","TypeBack-$form"};
  $$imposition{FrontMaterial} = openprint::Material->find_one(name=>$$imposition{TypeFront});
  $$imposition{BackMaterial} = openprint::Material->find_one(name=>$$imposition{TypeBack});

  my $sheets = $qty; # Gross vs Net
  my $setup_overs = $equipment->Specification('Laminating Setup Overs');

  if ($setup_overs) {
    $setup_overs = $setup_overs->clone();
    if ($$setup_overs{units} eq 'Percent') {
      $$setup_overs{total} = $qty * ($$setup_overs{value}/100);
    } else {
      $$setup_overs{total} = 1*$$setup_overs{value};
    }
  } else {
    $setup_overs = new openprint::EquipmentSpecification();
    $setup_overs->set({value=>'', units=>'', total=>0});
  }
  $$imposition{setup_overs} = $setup_overs;

  my $run_overs = $equipment->Specification('Laminating Run Overs');
  if ($run_overs) {
    $run_overs = $run_overs->clone();
    $$run_overs{value} //= 0;
    if ($$run_overs{units} eq 'Percent') {
      $$run_overs{total} = $qty * ($$run_overs{value}/100);
    } else {
      $$run_overs{total} = 1*$$run_overs{value};
    }
  } else {
    $run_overs = new openprint::EquipmentSpecification();
    $run_overs->set({value=>'', units=>'', total=>0});
  }
  $$imposition{run_overs} = $run_overs;

  my $maximum_sheet_width = $equipment->specification('Maximum Sheet Width') // '';
  my $maximum_sheet_length= $equipment->specification('Maximum Sheet Length') // '';
  my $margin = $equipment->specification('Laminating Margin') // 0.125;
  if ($film_width > $maximum_sheet_width) {
    $$price{alert} .= "Film width $film_width&quot; must be less than maximum Sheet width $maximum_sheet_width&quot;<br/>";
    return;
  }
  my $waste = $$imposition{waste} = $equipment->Specification('Laminating Waste');

  my $style = $equipment->specification('Laminating Style') // 'Final Pieces';
  if ($style eq 'Final Pieces') {
    # So we can do multiple items at once, as many as will fit in the width of the laminator.
    # We need a certain amount of space between the items.  I suspect that this should be an 
    # input, not a fixed value, but for now we will make it fixed.
    
    my $item_width = $$specs{"txtWidth-$form"} += 2*$margin;
    my $item_height = $$specs{"txtHeight-$form"} += 2*$margin;
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

    return undef if ! $$imposition{imposition};
    if ( $$imposition{image_orientation} == openprint::Imposition::Vertical ) {
      $length = $item_height * $$imposition{rows};
      $width = $item_width * $$imposition{columns};
      $$price{breakdown} .= sprintf('Items across: %d at a time<br/> material length = height %.2d * %d = %.2d inches, style:%s<br/>', $imposition->columns(),
        $item_height, $imposition->rows(), $length,
        $style );
      $sheets = POSIX::ceil($qty / $$imposition{columns});
      $$price{breakdown} .= "sheets $sheets = qty $qty / $$imposition{columns}<br/>";
    } else {
      $length = $item_width * $$imposition{rows};
      $width = $item_height * $$imposition{columns};
      $$price{breakdown} .= sprintf('Items across: %d at a time<br/> material length = width %.2d * %d = %.2d inches, style:%s<br/>', $imposition->rows(),
        $item_width, $imposition->rows(), $length,
        $style );
      $sheets = POSIX::ceil($qty / $$imposition{rows});
      $$price{breakdown} .= "sheets $sheets = qty $qty / $$imposition{rows}<br/>";
    } # end if
  } else { # Full Sheet

    $_ = equipment_fits($equipment, $imposition, $imposition->Paper);
    if ($_) {
      $$price{alert} .= 'Doesn\'t fit.'.$_.'<br/>';
      return undef;
    } # end if

    my $count = $equipment->specification('Laminating Count');
    if ($count eq 'Net Sheets') {
      $sheets = $$imposition{net_sheets};
    } else {
      $sheets = $$imposition{impressions} ? $$imposition{impressions} : $$imposition{net_sheets};
    }
    $sheets = $qty if ! $sheets;
    $$imposition{sheets} = $sheets = $sheets + $$setup_overs{total} + $$run_overs{total};

    # Prefer using the larger of height/width as the "Width"

    if ($imposition->sheet_width() > $imposition->sheet_height()) {
      $width = $imposition->sheet_width();
      $length = $imposition->sheet_height();
      $layout_width = $imposition->layout_width();

      if (
        ($width < $maximum_sheet_width)
          and
        ($width - $margin >= $film_width) # sheet larger than film
        #and
        #($layout_width + $margin <= $film_width) # layout < film
      ) {
        $$imposition{length} = $length;
        $$imposition{width} = $width;
        $$imposition{area} = $length * $width * $sheets;
        my $laminate_area = $$imposition{laminate_area} = $length * $film_width * $sheets;
        if ($waste) {
          if (lc $$waste{units} eq 'percent') {
            $$waste{total} = int($laminate_area * $$waste{value}/100);
            $laminate_area += $$waste{total};
            $$imposition{laminate_area} = $laminate_area;
          }
        }

        $openprint::log->debug("Returning impo $sheets sheets using $width as width, $length as length $layout_width as layout width area: $$imposition{laminate_area}");
        return $imposition;
      }
    } # else

    $length = $imposition->sheet_width();
    $width = $imposition->sheet_height();
    $layout_width = $imposition->layout_height();
    if (
      ($width < $maximum_sheet_width)
        and
      ($width - $margin >= $film_width)
      #and
      #($layout_width + $margin <= $film_width)
    ) {
      $$imposition{length} = $length;
      $$imposition{width} = $width;
      $$imposition{area} = $length * $width * $sheets;
      my $laminate_area = $$imposition{laminate_area} = $length * $film_width * $sheets;
      if ($waste) {
        if (lc $$waste{units} eq 'percent') {
          $$waste{total} = int($laminate_area * $$waste{value}/100);
          $laminate_area += $$waste{total};
          $$imposition{laminate_area} = $laminate_area;
        }
      }

      $openprint::log->debug("Returning B impo using $width as width, $length as $length");
      return $imposition;
    }

    if ($$imposition{sheet_width} < $maximum_sheet_width) {
      if ($$imposition{sheet_width} - $margin < $film_width) {
        $$price{alert} .= "Laminate width $film_width must be at least ".2*$margin." inches less than the sheet width $$imposition{sheet_width}<br/>";
      }
      if ($$imposition{layout_width} + $margin > $film_width) {
        $$price{alert} .= "Laminate width $film_width must be at least ".2*$margin." inches greater than the layout width $$imposition{layout_width}<br/>";
      }
    }
    if ($$imposition{sheet_height} < $maximum_sheet_width) {
      if ($$imposition{sheet_height} - $margin < $film_width) {
        $$price{alert} .= "Laminate width $film_width must be at least ".2*$margin." inches less than the sheet height $$imposition{sheet_height}<br/>";
      }
      if ($$imposition{layout_height} + $margin > $film_width) {
        $$price{alert} .= "Laminate width $film_width must be at least ".2*$margin." inches greater than the layout height $$imposition{layout_height}<br/>";
      }
    }
    if ($$specs{"override_film_width-$form"} eq 'Y') {
      $$imposition{length} = $length;
      $$imposition{width} = $width;
      $$imposition{area} = $length * $width * $sheets;
      my $laminate_area = $$imposition{laminate_area} = $length * $film_width * $sheets;
      if ($waste) {
        if (lc $$waste{units} eq 'percent') {
          $$waste{total} = int($laminate_area * $$waste{value}/100);
          $laminate_area += $$waste{total};
          $$imposition{laminate_area} = $laminate_area;
        }
      }
      return $imposition;
    }
    return undef;
  } # end style
  return $imposition;
} # end sub get_laminating_imposition

#($r->log, $dbh, $service->{type}, $pid, $sid, $specs, $variable)
sub display {
	my ( $log, $dbh, $type, $project_index, $service_index, $specs, $variable ) = @_;

	my $Project = new openprint::Project( $project_index );
  $ServiceType = $Project->ServiceType($service_index);

  my %page;
	my @equipment = openprint::Equipment->find('servicetype_id any' => $ServiceType->id(), useinestimating=>1, order=>'strName');
	foreach my $qty_index ( $Project->quantity_indexes() ) {	
    $page{'ddmEquipment'.$qty_index} = ssi::make_drop_down( [ map { $_->strid(), $_->name() } @equipment ], $$variable{'ddmEquipment'.$qty_index} );

    my @sigs = $Project->signatures({ sort=>1 });
    foreach my $signature_service_id (@sigs) {
      my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_id );
      my $form = $$sig_specs{SignatureIndex} || $$sig_specs{Form} || 1;
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
  foreach my $signature_service_id (@sigs) {
    my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_id );
    my $form = $$sig_specs{SignatureIndex} || $$sig_specs{Form} || 1;

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
  my ( $equipment, $I, $Stock ) = @_;
  if ( ( $_ = $equipment->fits( $I->sheet_width(), $I->sheet_height() ) ) and ( $_ = $equipment->fits( $I->layout_width(), $I->layout_height() ) ) ) {
    return $_;
  }
  if ( my $min_calliper = $equipment->specification( 'Minimum Calliper')) {
    if ( $min_calliper > $$Stock{calliper} ) {
      return "Calliper too thin stock calliper $$Stock{calliper} < minimum($min_calliper).";
    }
  }
  if ( my $max_calliper = $equipment->specification('Maximum Calliper')) {
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
      my $form = $$sig_specs{SignatureIndex} || $$sig_specs{Form} || 1;
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
