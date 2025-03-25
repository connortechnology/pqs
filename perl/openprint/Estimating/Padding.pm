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

package openprint::Estimating::Padding;
use strict;

require openprint::service;
require openprint::Material;
require openprint::Paper;
require openprint::Project;

require sql;

my %ServicePrices = (
  PaddingChargeMinimum => {},
  'Padding(.*)MakeReady' => { units => [ ] },
  'Padding' => { units=> ['per pad', 'per m']},
);
my %Specifications = (
  'Padding Capable' => { values=>['Y','N'] },
  'Padding MakeReadyTime' => { units => 'minutes' },
  'Padding Runspeed' => {},
  'Padding Overs' => { units => ['sheets','percent']},
  'Maximum Calliper'  => {units=>'Inches'},
  'Maximum Sheet Length' => {units=>'Inches'},
  'Maximum Sheet Width' => {units=>'Inches'},
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
    'ddmEquipment1', 'ddmEquipment2','ddmEquipment3',
    'chkOverrideEquipment1', 'chkOverrideEquipment2','chkOverrideEquipment3',
		'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
		'Markup1', 'Markup2', 'Markup3',
    'txtPrice1', 'txtPrice2', 'txtPrice3',
    'txtUnitPrice1', 'txtUnitPrice2', 'txtUnitPrice3',
    'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
		'PageQuantity',
		'Backing',
		'rdbDTape',
		'glue_id','override_glue_id',
);

sub variables {
    return @variables;
}

my @no_output = (
	'ProjectIndex','ServiceIndex','ServiceType',
	'PageQuantity',
	'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
	'Backing',
	'rdbDTape','override_glue_id',
	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
	'Markup1', 'Markup2', 'Markup3',
);

sub no_outputs {
	return @no_output;
} # end sub no_outputs

sub has_overrides {
  my ( $Project, $service_id, $specs, $qty_index ) = @_;
  $specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

  my @v;
  if ( $qty_index ) {
    push @v, map { ( $$specs{$_.$qty_index} and $$specs{$_.$qty_index} ne 'N' ) ? $_ : () } (
        'OverridePrice',
        );
  } # end if

  return @v;

} # end sub has_overrides


sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();
	my $status = 'calculated';
	my $ProjectService = $Project->Service( $service_index );

	if ( ! $$services{''} ) {
		$$specs{alert} .= 'Unable to find Project Service.<br/>';
		return 'uncalculated';
	} # end if
	# Pull from printing service
	my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );

	if ( ! $$specs{Backing} ) {
		$$specs{Backing} = $$printing_specs{Backing};
		@no_output = sets::exclude( ['Backing'], \@no_output );
	} else {
		@no_output = sets::union(@no_output, 'Backing');
	} # end if
	if ( ! $$specs{Backing} ) {
		$$specs{alert} = 'Please select your backing type.';
		return $$specs{Status} = 'uncalculated';
	} # end if
	if ( ! $$specs{PageQuantity} ) {
		if ( $$printing_specs{PageQuantity} ) {
			$$specs{PageQuantity} = $$printing_specs{PageQuantity};
			@no_output = sets::exclude( ['PageQuantity'], \@no_output );
		} else {
			my $Paper = openprint::Paper::load_from_signature( $Project, $printing_specs, 1 );
			if ( ! ( $Paper->id() or $$Paper{custom} ) ) {
				my @sigs = $Project->signatures();
				if ( @sigs ) {
					my $sig_specs = openprint::service::get_specs_ref( $Project,$sigs[0] );
					$Paper = openprint::Paper::load_from_signature( $Project, $sig_specs, 1 );
				} # end if
			} # end if
			
			if ( $Paper and $Paper->parts() ) {
				$$specs{PageQuantity} = $Paper->parts();
				@no_output = sets::exclude( ['PageQuantity'], \@no_output );
			} # end if
		} # end if
	} else {
		@no_output = sets::union(@no_output, 'PageQuantity');
	} # end if
	if ( ! $$specs{PageQuantity} ) {
		$$specs{alert} = 'Please select how many pages each pad will have.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if
	if ( $Project->Type()->name() eq 'ScratchPads' ) {
		if ( $$specs{PageQuantity} < $openprint::config{MinimumPagesWithoutCounting} ) {
			if ( ! $$services{Counting} ) {
				$_ = $Project->add_service( 'Counting' );
				openprint::service::internal_calc( $log, $dbh, $variable, $project_index, $_, 'Counting' ) if $_;
			} # end if
		} # end if
	} # end if

	my @Materials = openprint::Material->find(category=>'Padding Glue');
	if ( $$specs{override_glue_id} eq 'Y' ) {
	} else {
		my $Paper;
		foreach my $qty_index ( $Project->quantity_indexes() ) {
			$Paper = openprint::Paper::load_from_signature( $Project, $printing_specs, $qty_index );
			last;
		} # end foreach
		foreach my $Material ( @Materials ) {
			if ( sets::isin( $Paper->grade(), misc::trim(split(',',$Material->specification('Recommended For Stock Grade'))) ) ) {	
				$$specs{glue_id} = $Material->id();
			} # end if
		} # end foreach Material
	} # end if

	my $ProjectType = $Project->Type();
	my $Service = openprint::Service->find_one(name=>'Padding'.$ProjectType->name());
	$Service = openprint::Service->find_one(name=>'Padding') if ! $Service;
	my $Material = openprint::Material->find_one( name=>'CardboardBacking') if $$specs{Backing} eq 'Cardboard';


  my $minimumCharge;
	if ( ! ( $minimumCharge = openprint::service::get_price( 'Padding'.$ProjectType->name().'ChargeMinimum' ) ) ) {
		$minimumCharge = openprint::service::get_price( 'PaddingChargeMinimum' );
	} # end if

  my $calliper = 0;
  my @signatures = $Project->signatures();
# Single page item, if there are multiple signatures, it is due to multiple versions
  my $signature_service_index = $signatures[0];
  my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
  if ( $$sig_specs{txtSpecificStockCalliper} ) {
    $calliper = $$sig_specs{txtSpecificStockCalliper};
  } else {
    my $Paper = openprint::Paper::load_from_signature( $Project, $sig_specs );
    $calliper = $Paper->calliper();
  } # end if
  $calliper *= $$specs{PageQuantity} * $calliper;

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{'txtPrice'.$qty_index} = '' if (!$$specs{'OverridePrice'.$qty_index}) or ($$specs{'OverridePrice'.$qty_index} ne 'Y');
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
		next if ! $$specs{"txtQuantity$qty_index"};
    my $base_qty = $$specs{"txtQuantity$qty_index"};
    if ( ( $ProjectType->name() eq 'ScratchPads' ) and ( ! $$printing_specs{PageQuantity} ) ) {
      #$qty /= int( $$specs{PageQuantity} );
    } elsif ( ( $ProjectType->name() eq 'NCR' ) and ( ! $$printing_specs{PageQuantity} ) ) {
      $base_qty *= int( $$specs{PageQuantity} );
    } # end if
		$$specs{'hdnBreakdown'.$qty_index} .= "Minimum Charge: $minimumCharge<br/>";

    my $best_price;
    my @equipment;
    if ( (defined $$specs{"chkOverrideEquipment$qty_index"}) and ( $$specs{"chkOverrideEquipment$qty_index"} eq 'Y' ) ) {
      @equipment = ( new openprint::Equipment( $$specs{"ddmEquipment$qty_index"} ) );
    } else {
      @equipment = openprint::Equipment->find( useinestimating=>1, 'servicetype_id any'=>$ProjectService->servicetype_id() );
      @equipment = (new openprint::Equipment()) if ! @equipment;
    } # end if
    foreach my $equipment (@equipment) {
      $$specs{'hdnBreakdown'.$qty_index} .= "<b>$$equipment{name}</b><br/>";
      my $max_width = $equipment->specification('Maximum Sheet Width') || 40;
      my $maximum_thickness =$equipment->specification('Maximum Calliper') || 4;
      if (0) {
        my $max_imp = $equipment->specification('Maximum Padding Imposition');

        my $padding_imposition = $max_imp == 1 ? 1
        : $$printing_specs{txtFinalWidth} ? POSIX::floor($max_width / $$printing_specs{txtFinalWidth})
        : 0;

        if ( $padding_imposition < 1) {
          $$specs{'hdnBreakdown'.$qty_index} .= "Imposition $padding_imposition > Maximum $max_imp<br/>";
          next;
        } elsif ($calliper * $$specs{PageQuantity} > $maximum_thickness) {
          $$specs{'hdnBreakdown'.$qty_index} .= "Too thick $calliper > $maximum_thickness<br/>";
          next;
        }
      }

      my $qty = $base_qty;
      if ( my $Overs = $equipment->Specification('Padding Overs') ) {
        my $overs = 0;
        if ( $$Overs{units} eq 'sheets' ) {
          $overs = int($$Overs{value});
        } elsif ( $$Overs{units} eq 'percent' ) {
          $overs = int($qty * $$Overs{value}/100);
        } else {
          $openprint::log->error("Invalid units on Padding Overs $$Overs{units} on $$equipment{name}");
        } # end if
        $qty += $overs;
        $$specs{'hdnBreakdown'.$qty_index} .= $base_qty.'sheets + '.$$Overs{value}.$$Overs{units}.' = '.$overs.' overs = '.$qty.'<br/>';
      } # end if

      my $price = 0;

      my %MR = openprint::service::get_price_object( 'Padding'.$ProjectType->name().'MakeReady', $qty, $equipment );
      if ( ! %MR ) {
        %MR = openprint::service::get_price_object( 'PaddingMakeReady', $qty, $equipment );
      } # end if
      if ( %MR ) {
        $MR{Total} = $MR{Price};
        $price += $MR{Total};
        $$specs{'hdnBreakdown'.$qty_index} .= sprintf('MakeReady: $%.2f%s=$%.2f<br/>', @MR{'Price','units','Total'});
      } # end if

      my %ServicePrice = $Service->get_price( $qty, $equipment ) if $Service;
      if ( ! %ServicePrice ) {
        $log->debug('No price');
        $status = 'uncalculated';
        $$specs{alert} = 'We print press sheets only for pads - please ask a trade bindery to estimate the finishing.';
        $$specs{"txtPrice$qty_index"} = sprintf( '%.2f', 0 );
        $$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, 0 );
        next;
      } elsif ( sets::isin( $ServicePrice{units}, [ 'per pad', 'each' ] ) ) {
        $ServicePrice{Total} = $ServicePrice{Price} * $qty;
        $$specs{'hdnBreakdown'.$qty_index} .= sprintf('ServicePrice: $%1$.2f%2$s * %4$d = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $qty );
      } elsif ( $ServicePrice{units} eq 'per m' ) {
        $ServicePrice{Total} = $ServicePrice{Price} * $qty / 1000;
        $$specs{'hdnBreakdown'.$qty_index} .= sprintf('ServicePrice: $%1$.2f%2$s * %4$d = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $qty );
      } else {
        $$specs{'hdnBreakdown'.$qty_index} .= 'Unknown units for padding service.<br/>';
      } # end if
      $price += $ServicePrice{Total};

      if ( $Material ) {
        my %CardboardPrice = $Material->get_price( $qty, undef );
        if ( $CardboardPrice{units} eq 'per square inch' ) {
          $CardboardPrice{Total} = Math::Round::nearest( 0.01, $CardboardPrice{Price} * $$printing_specs{txtFinalWidth} * $$printing_specs{txtFinalHeight} * $$specs{"txtQuantity$qty_index"} );
          $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Cardboard Price: $%1$.2f%2$s * %4$sx%5$s = $%3$.2f<br/>', @CardboardPrice{'Price','units','Total'}, @$printing_specs{'txtFinalWidth','txtFinalHeight'} );
        } elsif ( $CardboardPrice{units} eq 'per square foot' ) {
          $CardboardPrice{Total} = Math::Round::nearest( 0.01, $CardboardPrice{Price} * ($$printing_specs{txtFinalWidth} * $$printing_specs{txtFinalHeight}/144) * $$specs{"txtQuantity$qty_index"} );
          $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Cardboard Price: $%1$.2f%2$s * %4$sx%5$s = $%3$.2f<br/>', @CardboardPrice{'Price','units','Total'}, @$printing_specs{'txtFinalWidth','txtFinalHeight'} );
        } elsif ( $CardboardPrice{units} eq 'per pad' or $CardboardPrice{units} eq 'each') {
          $CardboardPrice{Total} = $qty * $CardboardPrice{Price};
          $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Cardboard Price: $%1$.2f%2$s * %4$s = $%3$.2f<br/>', @CardboardPrice{'Price','units','Total'}, $qty );
        } else {
          $$specs{'hdnBreakdown'.$qty_index} .= 'Unknown units for cardboard.<br/>';
        } # end if
        $price += $CardboardPrice{Total};
      } # end if Material

      if ( $$specs{rdbDTape} eq 'Y' ) {
        if (my $DTapeMRService = openprint::Service->find_one(name=>'PaddingDTapeMakeReady')) {
          my $DTapeMRPrice = $DTapeMRService->get_Price($qty, undef);
          $$DTapeMRPrice{Total} = $$DTapeMRPrice{Price};
          $$specs{'hdnBreakdown'.$qty_index} .= sprintf('DTape MakeReady Price: $%1$.2f%2$s = $%3$.2f<br/>', @$DTapeMRPrice{'Price','units','Total'} );
        }
        if (my $DTapeService = openprint::Service->find_one(name=>'PaddingDTape')) {
          my $DTapePrice = $DTapeService->get_Price($qty, undef);
          $$DTapePrice{Total} = $$DTapePrice{Price} * $qty;
          $$specs{'hdnBreakdown'.$qty_index} .= sprintf('DTape Service Price: $%1$.2f%2$s = $%3$.2f<br/>', @$DTapePrice{'Price','units','Total'} );
        }
        if ( my $Material = openprint::Material->find_one(name=>'DTape') ) {
          my %DTapePrice = $Material->get_price( $qty, undef );
          $DTapePrice{Total} = $DTapePrice{Price} * $$printing_specs{txtFinalWidth};
          $$specs{'hdnBreakdown'.$qty_index} .= sprintf('DTape Price: $%1$.2f%2$s = $%3$.2f<br/>', @DTapePrice{'Price','units','Total'} );
          $price += $DTapePrice{Total};
        } # end if
      } # end if
      if ( $$specs{glue_id} ) {
        my $calliper = get_finished_calliper( $Project, $specs );
        my $Material = new openprint::Material( $$specs{glue_id} );
        my %GluePrice = $Material->get_price( $$specs{"txtQuantity$qty_index"}, undef );
        if ( $GluePrice{units} eq 'per square inch' ) {
          $GluePrice{Total} = $GluePrice{Price} * $$printing_specs{txtFinalWidth} * $calliper * $$specs{"txtQuantity$qty_index"};
          $$specs{'hdnBreakdown'.$qty_index} .= sprintf('%1$s Price: $%2$.2f%3$s * %5$.2f * %6$.4f =$%4$.2f<br/>', $Material->description(), @GluePrice{'Price','units','Total'}, $$printing_specs{txtFinalWidth}, $calliper );
        } elsif ( $GluePrice{units} eq 'per square foot' ) {
          $GluePrice{Total} = $GluePrice{Price} * $$printing_specs{txtFinalWidth} * $calliper * $$specs{"txtQuantity$qty_index"} / 144;
          $$specs{'hdnBreakdown'.$qty_index} .= sprintf('%1$s Price: $%2$.2f%3$s * %5$.2f * %6$.4f =$%4$.2f<br/>', $Material->description(), @GluePrice{'Price','units','Total'}, $$printing_specs{txtFinalWidth}, $calliper );
        } # end if
        $price += $GluePrice{Total};
      } # end if Glues
      if (!$best_price or $best_price > $price) {
        $best_price = $price;
        $$specs{'ddmEquipment'.$qty_index} = $equipment->id();
      }
    } # end foreach Equipment

		$best_price = $minimumCharge if $best_price < $minimumCharge;
    if ($Project->markup()) {
      $best_price *= (1+$Project->markup()/100);
    }
    if ($$specs{"Markup$qty_index"}) {
      $best_price *= (1+$$specs{"Markup$qty_index"}/100);
    }

		$$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $best_price/$base_qty );

		if ( (!$$specs{"OverridePrice$qty_index"}) or ($$specs{"OverridePrice$qty_index"} ne 'Y')) {
$openprint::log->error("Not overriding");
			$$specs{"txtPrice$qty_index"} = sprintf($openprint::config{ProjectMoneyFormat}, $best_price);
		} else {
$openprint::log->error("overriding to ".$$specs{"txtPrice$qty_index"});
			$$specs{"txtPrice$qty_index"} = sprintf($openprint::config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"});
		} # end if
	} # end foreach
	return $$specs{Status} = $status;
} # end sub calc

sub summary {
    my ( $Project, $service_id, $specs, $qty_index ) = @_;
    $specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
    my $text = '';
    if ( $qty_index ) {
		return '';		
	} # end if
	$text .= $$specs{PageQuantity} . ' pages per pad';
	my $Material = new openprint::Material( $$specs{glue_id} );
	$text .= ' using ' . $Material->description();
	if ( $$specs{Backing} ne 'None' ) {
		$text .= ' +' . $$specs{Backing};
	} else {
		$text .= ' no backing';
	} # end if
	if ( $$specs{rdbDTape} eq 'Y' ) {
		$text .= ' +DTape';
	} # end if
	return $text;
} # end sub summary

sub save {
	my ( $p_id, $s_id, $param ) = @_;
	my $Project = new openprint::Project( $p_id );
	my $services = $Project->services();

	my $recalc = 0;
	
	foreach my $sig_id ( $$services{''}[0], $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
		if ( ( $$param{PageQuantity} != $$sig_specs{PageQuantity} ) or ( $$param{Backing} ne $$sig_specs{Backing} ) ) {
			openprint::service::insert_service_spec( $openprint::log, $openprint::dbh, $Project->id(), $sig_id, 'PageQuantity', $$param{PageQuantity} );
			openprint::service::insert_service_spec( $openprint::log, $openprint::dbh, $Project->id(), $sig_id, 'Backing', $$param{Backing} );
			$recalc = 1;
		} # end if
	} # end foreach sig
	if ( $recalc ) {
		openprint::Estimating::MultiPage::calculate_signatures( $Project );
		openprint::service::auto_calculate( $Project );
	} # end if recalc
} # end sub save

sub get_finished_calliper { 
	my ( $Project, $specs ) = @_; 

	my $services = $Project->services();

	my $finished_calliper;
    foreach my $signature_service_index ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
		$finished_calliper += $$specs{PageQuantity} * $$sig_specs{txtSpecificStockCalliper};
	} # end foreach
	return $finished_calliper;
} # end sub get_finished_calliper

sub display {
} # end sub display

sub neccessary {
  my ( $Project, $Service ) = @_;
$openprint::log->error($Project->Type()->type());
  if ($Project->Type()->type() eq 'ScratchPads') {
    return 1;
  }
  return 0;
} # end sub neccessary

1;
__END__
