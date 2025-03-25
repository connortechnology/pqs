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

package openprint::Estimating::UVCoating;
use strict;
#use warnings;
use vars qw( %ServicePrices %Specifications);
%ServicePrices = (
	UVCoatingMinimumCharge => {},
	'UV(.*)MakeReady' => {},
);
%Specifications = (
  UVCoatingRunSpeed => {range_units => [ 'gsm' ]},
  'WT UVCoating' => { values=>['Y','N'] },
  'UVCoating Overs' => {range_units => [ 'impressions' ]},
  'UVCoating Capable' => { value=>['Y','N'] },
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

require openprint::service;
require openprint::Material;
require openprint::imposition;
require openprint::Imposition;

use vars qw( $log $dbh %config @outputs );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;

# Offline UVCoating
# Let's assume that each piece of equipment can do 1 coat at a time
# This service doesn't store it's own data, other than price.  It gets the info from the printing service.
#
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
		foreach my $qty_index ( $Project->quantity_indexes() ) {
			push @v, "chkOverrideQty-$$specs{SignatureIndex}",
				 "ddmEquipment-$$specs{SignatureIndex}-$qty_index", "chkOverrideEquipment-$$specs{SignatureIndex}-$qty_index",
				 "txtImposition-$$specs{SignatureIndex}-$qty_index", "chkOverrideImposition-$$specs{SignatureIndex}-$qty_index",
				 "txtLayoutWidth-$$specs{SignatureIndex}-$qty_index", "txtLayoutHeight-$$specs{SignatureIndex}-$qty_index",
				 "MakeReadyPrice-$$specs{SignatureIndex}-$qty_index", "OverrideMakeReadyPrice-$$specs{SignatureIndex}-$qty_index",
         "BlanketPrice-$$specs{SignatureIndex}-$qty_index", "OverrideBlanketPrice-$$specs{SignatureIndex}-$qty_index",
         "ServicePrice-$$specs{SignatureIndex}-$qty_index", "OverrideServicePrice-$$specs{SignatureIndex}-$qty_index",
         "MaterialPrice-$$specs{SignatureIndex}-$qty_index", "OverrideMaterialPrice-$$specs{SignatureIndex}-$qty_index",
         "SignaturePrice-$$specs{SignatureIndex}-$qty_index", "OverrideSignaturePrice-$$specs{SignatureIndex}-$qty_index";
       } # end foreach
	} # end foreach
    return @v;
} # end sub variables

@outputs = (
	'txtUnitPrice1','txtUnitPrice2','txtUnitPrice3',
	'txtPrice1','txtPrice2','txtPrice3',
	'ddmEquipment1', 'ddmEquipment2', 'ddmEquipment3',
	'hdnBreakdown1',
	'hdnBreakdown2',
	'hdnBreakdown3',
	'alert','Status',
);
sub outputs {
	return @outputs;
}
sub no_outputs {
} # end sub no_outputs

my @no_outputs = (
);

my @all_equipment;

# A function that is smart enough to return true if the project needs perfing/UVCoating, and false if it doesn't.
sub neccessary {
	my ( $Project ) = @_;

	foreach my $sig_id ( $Project->signatures() ) {
		my $Service = $Project->Service( $sig_id );

		if ( signature_needs( $Project, $Service->specs() ) ) {
			return 1;
		}
	} # end foreach sig_id
	return 0;
} # end sub neccessary

sub signature_needs {
	my ( $Project, $sig_specs ) = @_;

	foreach ( get_uv_colours( $sig_specs, 'SideOne' ) ) {
		return 1 if $_ =~ /UV/;
	} # end foreach colour

	foreach ( get_uv_colours( $sig_specs, 'SideTwo' ) ) {
		return 1 if $_ =~ /UV/;
	} # end foreach colour
} # end sub signature_needs

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $status = 'calculated';

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();

	@all_equipment = load_equipment();
	if ( ! @all_equipment ) {
		$$specs{alert} = 'We have no equipment for UV Coating.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if

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
		foreach my $signature_service_index ( $Project->signatures( { sort=>1 } ) ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
			my $form = $$sig_specs{SignatureIndex};
			$$specs{'hdnBreakdown'.$qty_index} .= 'Signature ' . $$sig_specs{SignatureIndex} . 'Printed: ' .openprint::service::summary( $Project, $signature_service_index, $qty_index ).'<br/>';
# If any of the signatures doesn't have an imposition, then we are in an incomplete state.
			if ( ! $$sig_specs{'txtImposition'.$qty_index} ) {
				$$specs{alert} .= 'No imposition was found for printing. Please complete the printing estimation first.<br/>';
				next;
			} # end if
			my $Imposition = new openprint::Imposition();
			$Imposition->load( $sig_specs, $qty_index, $Project );
			my %results = signature_calc( $Project, $service_index, $specs, $signature_service_index, $sig_specs, $qty_index, $Imposition, \%MakeReadies );
			$$specs{'hdnBreakdown'.$qty_index} .= $results{Breakdown};

			$MakeReadies{$results{Equipment}{id}} = $$sig_specs{'StockWidth'.$qty_index} * $$sig_specs{'StockHeight'.$qty_index} if $results{Equipment};
			@outputs = sets::union( @outputs, 
        "ddmEquipment-$form-$qty_index", 
        "MakeReadyPrice-$form-$qty_index",
        "BlanketPrice-$form-$qty_index",
        "ServicePrice-$form-$qty_index",
        "MaterialPrice-$form-$qty_index",
        "SignaturePrice-$form-$qty_index",
      );	
      if ( ( ! defined $$specs{"OverrideMakeReadyPrice-$form-$qty_index"} ) or ( $$specs{"OverrideMakeReadyPrice-$form-$qty_index"} ne 'Y' ) ) {
        $$specs{"MakeReadyPrice-$form-$qty_index"} = sprintf($config{ProjectMoneyFormat}, $results{MakeReady} );
      } # end if
      if ( ( ! defined $$specs{"OverrideBlanketPrice-$form-$qty_index"} ) or ( $$specs{"OverrideBlanketPrice-$form-$qty_index"} ne 'Y' ) ) {
				$$specs{"BlanketPrice-$form-$qty_index"} = sprintf($config{ProjectMoneyFormat}, $results{Blanket} );
			} # end if
			if ( ( ! defined $$specs{"OverrideServicePrice-$form-$qty_index"} ) or ( $$specs{"OverrideServicePrice-$form-$qty_index"} ne 'Y' ) ) {
				$$specs{"ServicePrice-$form-$qty_index"} = sprintf($config{ProjectMoneyFormat}, $results{Service} );
			} # end if
			if ( ( ! defined $$specs{"OverrideMaterialPrice-$form-$qty_index"} ) or ( $$specs{"OverrideMaterialPrice-$form-$qty_index"} ne 'Y' ) ) {
				$$specs{"MaterialPrice-$form-$qty_index"} = sprintf($config{ProjectMoneyFormat}, $results{Material} );
			} # end if
			if ( ( ! defined $$specs{"OverrideSignaturePrice-$form-$qty_index"} ne 'Y' ) or ( $$specs{"OverrideSignaturePrice-$form-$qty_index"} ne 'Y' ) ) {
				$$specs{"SignaturePrice-$form-$qty_index"} = sprintf($config{ProjectMoneyFormat}, $results{Total} );
            } # end if

			if ( ( ! defined $$specs{"chkOverrideEquipment-$form-$qty_index"} ) or ( $$specs{"chkOverrideEquipment-$form-$qty_index"} ne 'Y' ) ) {
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
						if ( ! $$services{Cutting} ) {
							$$specs{alert} .= '<br/>You do not have cutting in your project.  Without it, we cannot cut the sheets down to fit on our equipment.';
						} # end if
					} # end if
				} # end if
			} else {
				if ( $results{Equipment} ) {
					$$specs{"ddmEquipment-$form-$qty_index"} = $results{Equipment}->id();
					$GrandTotal += $$specs{"SignaturePrice-$form-$qty_index"};
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

		$$specs{"txtUnitPrice$qty_index"} = sprintf( $config{UnitPriceFormat}, $unit_price );
		if ( ( ! defined $$specs{'OverridePrice'.$qty_index} ) or ( $$specs{'OverridePrice'.$qty_index} ne 'Y' ) ) {
			$$specs{"txtPrice$qty_index"} = sprintf( $config{ProjectMoneyFormat}, $GrandTotal );
		} else {
			$$specs{"txtPrice$qty_index"} = sprintf( $config{ProjectMoneyFormat}, $$specs{'txtPrice'.$qty_index} );
		} # end if
	} # end foreach qty

	return $$specs{Status} = $status;
} # end sub calc

sub cut_imposition {
	my ( $I ) = @_;
	
	my $i1 = $I->copy();
	my @results = ( $i1 );

	if ( $$I{runstyle} eq 'Work & Turn' ) {
		$i1->runstyle( 'SheetWork' );
		$i1->columns( $$i1{columns} / 2 );
		if ( $$I{dutch_columns} ) {
			$i1->dutch_columns( $$i1{dutch_columns} / 2 );
		} # end if
		$i1->quantity( $$i1{quantity} * 2 );
$i1->display('Cut to 1');

	} elsif ( $$I{runstyle} eq 'Work & Tumble' ) {
		$i1->runstyle( 'SheetWork' );
		$i1->rows( $$i1{rows} / 2 );
		$i1->dutch_rows( $$i1{dutch_rows} / 2 ) if $$I{dutch_rows};
		$i1->quantity( $$i1{quantity} * 2 );
$i1->display('Cut to 1');

	} elsif ( $$I{dutch_columns} ) {
		$i1->dutch_rows( 0 );
		$i1->dutch_columns( 0 );

		my $i2 = $I->copy();
		$i2->rows( $$I{dutch_rows} );
		$i2->columns( $$I{dutch_columns} );
		$i2->image_orientation( $$I{image_orientation} == openprint::Imposition::Vertical ? openprint::Imposition::Horizontal : openprint::Imposition::Vertical );
		$i2->dutch_rows( 0 );
		$i2->dutch_columns( 0 );
$i1->display('Cut to 1');
$i2->display('Cut to 2');
		push @results, $i2;
	} elsif ( $I->layout_width() >= $I->layout_height() and $$I{columns} > 1 ) {
	$I->display('Cut columns');
			my $i2 = $I->copy();
			$i1->sheet_width();
			$i2->sheet_width();
			$i1->columns( int($$I{columns} / 2) );
			$i2->columns( $$I{columns} - $$i1{columns} );
			#$i1->sheet_width( Math::Round::nearest( 0.001,$I->sheet_width() / ( $I->columns()/$i1->columns() ) ) );
			#$i2->sheet_width( $I->sheet_width() - $i1->sheet_width() );
	$i1->display('Cut to 1');
	$i2->display('Cut to 2');
			push @results, $i2;
	} elsif ( $I->layout_width() < $I->layout_height() and $$I{rows} > 1 ) {
$I->display('C');
		my $i2 = $I->copy();
		$i1->sheet_width();
		$i2->sheet_width();
		$i1->rows( int($$I{rows} / 2) );
		$i2->rows( $$I{rows} - $$i1{rows} );
		#$i1->sheet_height( sprintf( '%.3f', $I->sheet_height() / ( $I->rows()/$i1->rows() ) ) );
		#$i2->sheet_height( $I->sheet_height() - $i1->sheet_height() );
$i1->display('Cut to 1');
$i2->display('Cut to 2');
		push @results, $i2;
	} elsif ( $I->columns() >= $I->rows() ) {
$I->display('D');
		my $i2 = $I->copy();
		$i1->sheet_width();
		$i2->sheet_width();
		$i1->columns( int($I->columns() / 2) );
		$i2->columns( $I->columns() - $i1->columns() );
		#$i1->sheet_width( sprintf('%.3f',$I->sheet_width() / ( $I->columns()/$i1->columns() ) ) );
		#$i2->sheet_width( $I->sheet_width() - $i1->sheet_width() );
$i1->display('Cut to 1');
$i2->display('Cut to 2');
		push @results, $i2;
	} else {
$I->display('E');
		my $i2 = $I->copy();
		$i1->sheet_width();
		$i2->sheet_width();
		$i1->rows( int($I->rows() / 2) );
		$i2->rows( $I->rows() - $i1->rows() );
		#$i1->sheet_height( sprintf( '%.3f', $I->sheet_height() / ( $I->rows()/$i1->rows() ) ) );
		#$i2->sheet_height( $I->sheet_height() - $i1->sheet_height() );
$i1->display('Cut to 1');
$i2->display('Cut to 2');
		push @results, $i2;
	} # end if
	return @results;
} # end sub cut_imposition

sub get_uv_colours {
	my ( $specs, $side ) = @_;
	my @colours;
	foreach my $k ( keys %$specs ) {
		if ( my ( $index ) = $k =~ /^chkColourCoating(\d+)$side/ ) {
			next if ! $$specs{"chkColourCoating$index$side"};
			my $type = $$specs{"ColourCoatingType$index$side"};
			if ( $type =~ /UV/ ) {
				push @colours, $type;
			} # end if type eq PMS
		} # end if
	} # end foreach
	return @colours;
} # end sub get_colours

sub get_uv_inkcoverage {
	my ( $specs ) = @_;

	my %inkCoverage;
	foreach my $side ( 'SideOne','SideTwo' ) {
		foreach my $k ( keys %$specs ) {
			if ( my ( $index ) = $k =~ /^chkColourCoating(\d+)$side/ ) {
				next if ! $$specs{"chkColourCoating$index$side"};
				my $type = $$specs{"ColourCoatingType$index$side"};
				if ( $type =~ /Overall/ ) {
# Nothing cuz coverage is 100%
					$$specs{'ColourCoatingCoverage'.$index.$side} = 100;
				} # end if
				$inkCoverage{$type} += $$specs{'ColourCoatingCoverage'.$index.$side};
			} # end if
		} # end foreach k
	} # end foreach Side
	return %inkCoverage;
} # end sub get_uv_inkcoverage

sub signature_calc {
    my ( $Project, $service_index, $specs, $signature_service_index, $sig_specs, $qty_index, $Imposition, $MakeReadies ) = @_;

	my %BestPrice = (
			Total => undef,
			MakeReady => 0,
			Service => 0,
			Material => 0,
			Blanket => 0,
			Equipment => undef,
			Breakdown => '',
			Overs => 0,
	);

	my @front_uv = get_uv_colours( $sig_specs, 'SideOne' );
	my @back_uv = get_uv_colours( $sig_specs, 'SideTwo' );
	my %inkCoverage = get_uv_inkcoverage( $sig_specs );

	my @different_types = sets::union( @front_uv, @back_uv );

	#$openprint::log->debug("Signature : $signature_service_index");
	if ( ! ( @front_uv or @back_uv ) ) {
		$BestPrice{Status} = 'calculated';	
		$BestPrice{alert} .= 'There are no UV Coatings specified.';
		return %BestPrice;
	} # end if
	$BestPrice{Status} = 'uncalculated';
	#if ( $Project->Type()->name() eq 'Labels' ) {
		#@BestPrice{'Status','alert'} = ('uncalculated','We cannot UVCoat labels at this time.');
		#return %BestPrice;
	#} # end if

	my $qty = $$specs{"txtQuantity$qty_index"};
	if ( $$specs{txtPressSheetComboItems} ) {
		$qty *= $$specs{txtPressSheetComboItems};
	} # end if
	if ( $$sig_specs{Versions} ) {
		$qty *= $$sig_specs{Versions};
	} # end if

	load_equipment() if ! @all_equipment;
	my @equipment;	
	if ( (defined $$specs{"chkOverrideEquipment-$$sig_specs{SignatureIndex}-$qty_index"}) and ($$specs{"chkOverrideEquipment-$$sig_specs{SignatureIndex}-$qty_index"} eq 'Y') ) {
		@equipment = ( new openprint::Equipment( $$specs{"ddmEquipment-$$sig_specs{SignatureIndex}-$qty_index"} ) );
	} else {
		@equipment = @all_equipment;
	} # endif

	# Start out with the base
	my @Sets_Of_Impositions = ( [ $Imposition ] );
	my $services = $Project->services();
	my $Stock = $Imposition->Paper();

	my $MinimumCharge = openprint::Service->find_one(name=>'UVCoatingMinimumCharge');

	foreach my $Equipment ( @equipment ) {
    if (!defined($Equipment->useinestimating()) and $Equipment->id() != $Imposition->Press()->id()) {
      next;
    }
		my %BestPricePerImposition;
		my %minimum = $MinimumCharge->get_price( undef, $Equipment ) if $MinimumCharge;
		my $BlanketCutPrice;
		my $runspeed = $Equipment->Specification('UVCoatingRunSpeed', $Stock->gsm() );
		my $equipment_id = $$Equipment{id};
		my $equipment_wt = $Equipment->specification('WT UVCoating');

		for ( my $set_index = 0; $set_index < @Sets_Of_Impositions; $set_index += 1 ) {
			my $impositions = $Sets_Of_Impositions[$set_index];
			my %MakeReadies = %$MakeReadies;

			my $complete = 1;
			my $totalPrice = 0;
			my $breakdown = '<table>';

			my %ImpositionPrice;
			$ImpositionPrice{Blanket} = 0;
			$ImpositionPrice{Makeready} = 0;
			$ImpositionPrice{Service} = 0;
			#if ( @$impositions > 1 ) {
				# What is the purpose?  Should be to figure out how to cut the impositions out of the sheet, but that is not what this does.
				#my %results = openprint::Estimating::Cutting::signature_calc_stock_cutting( $Project, {}, $qty_index, { Stock => $Stock, quantity =>  );
				#$ImpositionPrice{Cutting} = $results{Price};
				#$breakdown .= sprintf('Stock cutting cost: %.2f<br/>', $results{Price} );
			#} # end if

			for ( my $imp_index = 0; $imp_index < @$impositions; $imp_index += 1 ) {
				my $imp = $$impositions[$imp_index];
				my $wt = ( $$imp{runstyle} eq 'Work & Turn' or $$imp{runstyle} eq 'Work & Tumble' ) ? 1 : 0;

				#$breakdown .= sprintf( '%dx%d+%dx%d=%dout on %sx%s<br/>',$imp->get('columns','rows','dutch_columns','dutch_rows','imposition'), $Stock->width(), $Stock->height() );
				$breakdown .= '<tr><td colspan="2"><br/>'.$imp->to_string().'</td></tr>';
				$openprint::log->debug('Trying: ' . $breakdown ) if DEBUG;

				if ( ! ( $$imp{rows} * $$imp{columns} ) ) {
					$openprint::log->error('Invalid Imposition in UVCoating');
					$imp->display();
					$complete = 0;
					last;
				} # end if

				if ( $wt and ( (!$equipment_wt )or ( $equipment_wt ne 'Y')) and (sets::intersection( @front_uv, @back_uv ) != sets::union( @front_uv, @back_uv ) ) ) {
					$breakdown .= '<tr><td colspan="2" class="error">Does not support WT UV Coating</td></tr>';
					if ( $$services{Cutting} ) {
						# If we are the last set
						if ( $set_index+1 == @Sets_Of_Impositions ) {
							my @new_imps = @$impositions;
							splice @new_imps, $imp_index, 1, cut_imposition( $new_imps[$imp_index] );		
							push @Sets_Of_Impositions, \@new_imps;
						} # end if
					} else {
						$breakdown .= '<tr><td colspan="2" class="error">Cant cut down W&T because no cutting.  Please add cutting.</td></tr>';
					} # end if
$openprint::log->debug('W&T: ' . $breakdown ) if DEBUG;
					$complete = 0;
					last;
				} # end if

				if ( $_ = equipment_fits( $Equipment, $imp, $Stock ) ) {
					$breakdown .= "<tr><td colspan=\"2\" class=\"error\">Doesn't fit. $_</td></tr>";
$openprint::log->debug('DOESNT: ' . $breakdown ) if DEBUG;
					$complete = 0;
					if ( ! ( $_ =~ /Too small/ ) ) {
						if ( $$services{Cutting} and ( $$imp{imposition} > 1 ) and ( $set_index+1 == @Sets_Of_Impositions ) ) {
							my @new_imps = @$impositions;
							splice @new_imps, $imp_index, 1, cut_imposition( $new_imps[$imp_index] );		
							push @Sets_Of_Impositions, \@new_imps;
						} # end if
					} # end if
					$BestPrice{Breakdown} .= $breakdown;
					last;
				} # end if

				my $run_qty = Math::Round::nearest( 1, $qty * $$imp{quantity} / $$Imposition{imposition} );
				$breakdown .= '<tr><td colspan="2">impressions: ' . $run_qty .'</td></tr>';
		
				if ( my $Overs = $Equipment->Specification('UVCoating Overs', $run_qty ) ) {
          my $overs;
					if ( $$Overs{units} eq 'Sheets' ) {
						$overs = $$Overs{value};
          } elsif ($$Overs{units} eq 'percent') {
						$overs = int($run_qty * $$Overs{value} / 100);
          } else {
            $openprint::log->error('Unknown units in UVCoating Overs');
					} # endif
          $run_qty += $overs;
          $ImpositionPrice{Overs} += $overs;
          $breakdown .= ' Overs: ' . $overs;
				} # end if
				my @types;
				if ( $wt ) {
# need to merge any overalls into spots
					foreach my $type ( @different_types ) {
						if ( ! ( sets::isin( $type, \@front_uv ) and sets::isin( $type, \@back_uv ) ) ) {
							$type =~ s/Overall/Spot/;
						} # end if
						push @types, $type;
					} # end foreach
					$run_qty *= 2;
				} else {
					@types = ( @front_uv, @back_uv );
				} # end if
$openprint::log->debug("Types: @types") if DEBUG;

				# Has total price values for all types
				foreach my $type ( @types ) {
					my $type_total = 0;
					my $setupPrice;
					if ( $MakeReadies{$equipment_id} and (
								(($$sig_specs{'StockWidth'.$qty_index} * $$sig_specs{'StockHeight'.$qty_index} * 1.10 ) > $MakeReadies{$equipment_id} ) and
								(($$sig_specs{'StockWidth'.$qty_index} * $$sig_specs{'StockHeight'.$qty_index} * .90 ) < $MakeReadies{$equipment_id} )
								) ) {
						$setupPrice = 0;
					} else {
						$setupPrice = openprint::service::get_price( $type.'MakeReady', $run_qty, $Equipment );
						$setupPrice = openprint::service::get_price( 'UVCoatingMakeReady', $run_qty, $Equipment ) if ! $setupPrice;
						if ( ! $setupPrice ) {
							$openprint::log->debug('No setup price for '.$type);
							$setupPrice = 0;
						} else {
							$ImpositionPrice{MakeReady} += $setupPrice;
							$type_total += $setupPrice;
						}

						$MakeReadies{$Equipment->id()} = $$sig_specs{'StockWidth'.$qty_index} * $$sig_specs{'StockHeight'.$qty_index};
					} # end if
					$breakdown .= sprintf('<tr><td colspan="2">%s</td></tr><tr><td>MR:</td><td class="Price">$%.2f</td></tr>', $type, $setupPrice );

					if ( $type =~ /Spot/ and $BlanketCutPrice ) {
						$BlanketCutPrice = openprint::service::get_price( 'BlanketCut', undef, $Equipment ) if ! defined $BlanketCutPrice;
						$BlanketCutPrice = 0 if ! defined $BlanketCutPrice;
						$breakdown .= sprintf('<tr><td>BC:</td><td class="Price">$%.2f</td></tr>', $BlanketCutPrice );
						$ImpositionPrice{Blanket} += $BlanketCutPrice;
						$type_total += $BlanketCutPrice;
					} # end if type is spot

					my %ServicePrice = openprint::service::get_price_object( $type, $run_qty, $Equipment );
					if ( ! %ServicePrice ) {
						%ServicePrice = openprint::service::get_price_object( 'UVCoating'.$type, $run_qty, $Equipment );
					} # end if
					if ( ! %ServicePrice ) {
						$openprint::log->debug("No service price for $type");
					} else {
						if ( $ServicePrice{units} eq 'per m' ) {
							$ServicePrice{Total} = $ServicePrice{Price}*$run_qty/1000;
						} elsif ( $ServicePrice{units} eq 'per hour' or $ServicePrice{units} eq '/Hr' or $ServicePrice{units} eq '/hr' ) {
							if ( $runspeed and $$runspeed{value}) {
                if ($$runspeed{units} eq 'inches per hour') {
                  # Feed in with height being the shortest
                  my $length = $Imposition->sheet_height() > $Imposition->sheet_width() ? $Imposition->sheet_width() : $Imposition->sheet_height();
                  #if ( $$Imposition{image_orientation} == openprint::Imposition::Vertical ) {
                  #$length = $Imposition->layout_height();
                  #} else {
                  #$length = $Imposition->layout_width();
                  #} # end if

                  my $inches = $length * $run_qty;
                  my $hours = Math::Round::nearest( 0.01, $inches / $$runspeed{value} );
                  $breakdown .= sprintf('<tr><td>Service: %s image length = %dinches @ %d/Hr = %.1fhours', $length, $inches, $$runspeed{value}, $inches/$$runspeed{value} );
                  $ServicePrice{Total} = $ServicePrice{Price}*$inches/$$runspeed{value}
                } else {
                  $breakdown .= sprintf('<tr><td>Service: %d @ %d/Hr = %.1fhours', $run_qty, $$runspeed{value}, $run_qty/$$runspeed{value} );
                  $ServicePrice{Total} = $ServicePrice{Price}*$run_qty/$$runspeed{value}
                }
							} else {
								$breakdown .= sprintf('<tr><td>No runspeed for %dgsm. Cant use this price.</td></tr>', $Stock->gsm() );
								$ServicePrice{Total} = 1000000;
							} # end if
						} else {
$openprint::log->error("Unknown units on Service Price $ServicePrice{Service} $ServicePrice{units}");
						} # end if
# Div by imposition, but run_qty is already div by impo
#$ServicePrice{Total} /= $imp->imposition();
						$ImpositionPrice{Service} += $ServicePrice{Total};
						$breakdown .= sprintf('@ $%.2f%s</td><td class="Price">%.2f</td></tr>', @ServicePrice{'Price','units','Total'} );
					} # end if

					my %MaterialPrice;
					my $material_name = $type;
					$material_name =~ s/ ?Spot ?//;
					$material_name =~ s/ ?Overall ?//;
					if ( my $Material = openprint::Material->find_one( name=>$material_name) ) {
						%MaterialPrice = $Material->get_price( $run_qty, $Equipment );
						if ( lc $MaterialPrice{units} eq 'per square inch' ) {
							my $area;
							if ( $type =~ /Overall/i ) {
								$area = $imp->sheet_area() * $run_qty;
								$breakdown .= sprintf( '<tr><td>Material: %sx%s = %d sq inches = %d total sq inches', $imp->sheet_width(), $imp->sheet_height(), $imp->sheet_area(), $area );
							} else {
								$area = $imp->object_area() * $run_qty * ($inkCoverage{$type}/100);
								$breakdown .= sprintf( '<tr><td>Material: %sx%s = %d sq inches = %d total sq inches', $imp->object_width(), $imp->object_height(), $imp->object_area(), $area );
							} 
							$MaterialPrice{Total} = $MaterialPrice{Price} * $run_qty * $area;
						} elsif ( lc $MaterialPrice{units} eq 'per square foot' ) {
							my $area;
							if ( $type =~ /Overall/i ) {
								$area = $imp->sheet_area() * $run_qty / 144;
								$breakdown .= sprintf( '<tr><td>Material: %sx%s = %d sq feet = %d total sq feet', $imp->sheet_width(), $imp->sheet_height(), $imp->sheet_area(), $area );
							} else {
								$area = $imp->object_area() * $run_qty * ($inkCoverage{$type}/100) / 144;
								$breakdown .= sprintf( '<tr><td>Material: %sx%s = %d sq feet = %d total sq feet', $imp->object_width(), $imp->object_height(), $imp->object_area(), $area );
							} 
							$MaterialPrice{Total} = $MaterialPrice{Price} * $area;
						} elsif ( lc $MaterialPrice{units} eq 'per m' ) {
							$MaterialPrice{Total} = $MaterialPrice{Price} * $run_qty / 1000;
						} else {
							$MaterialPrice{units} = 'unknown units';
						} # end if
						$breakdown .= sprintf(' @ $%.5f%s ', @MaterialPrice{'Price','units'} );
						$ImpositionPrice{Material} += $MaterialPrice{Total};
						$type_total += $MaterialPrice{Total};
					} # end if
					$breakdown .= sprintf('=</td><td class="Price">$%.2f</td></tr>', $MaterialPrice{Total} );
				} # end foreach type
				#$totalPrice += $ImpositionPrice{Total} + $ImpositionPrice{Cutting};
			} # end foreach imposition
		
			if ( ! $complete ) {
$log->debug("Complete: $breakdown");
				$BestPricePerImposition{Breakdown} = $breakdown;
				next;
			} #
			$ImpositionPrice{Total} += misc::sum( @ImpositionPrice{'MakeReady','Service','Material','Blanket','Cutting'} );
			$breakdown .= sprintf('<tr class="totals"><td>Total:</td><td class="Price">$%.2f</td></tr></table>',
					Math::Round::nearest(0.01,$ImpositionPrice{Total}) );

			if ( ( ! defined $BestPricePerImposition{Total} ) or ( $ImpositionPrice{Total} < $BestPricePerImposition{Total} ) ) {
				%BestPricePerImposition = %ImpositionPrice;
				$BestPricePerImposition{Breakdown} = $breakdown;
			} # end if
		} # end foreach set of impositions
		if ( ! defined $BestPricePerImposition{Total} ) {
			$BestPrice{Breakdown} = 'Equipment: ' . $Equipment->name() . '<br/>' . $BestPricePerImposition{Breakdown};
			$openprint::log->debug("Can't calculate price for $$Equipment{name}");
			next;
		} # end if

		if ( ( defined $$specs{"OverrideMakeReadyPrice-$$sig_specs{SignatureIndex}-$qty_index"} ) and ( $$specs{"OverrideMakeReadyPrice-$$sig_specs{SignatureIndex}-$qty_index"} eq 'Y' ) ) {
			$BestPricePerImposition{MakeReady} = $$specs{"MakeReadyPrice-$$sig_specs{SignatureIndex}-$qty_index"};
		} # end if
		if ( ( defined $$specs{"OverrideBlanketPrice-$$sig_specs{SignatureIndex}-$qty_index"} ) and ( $$specs{"OverrideBlanketPrice-$$sig_specs{SignatureIndex}-$qty_index"} eq 'Y' ) ) {
			$BestPricePerImposition{Blanket} = $$specs{"BlanketPrice-$$sig_specs{SignatureIndex}-$qty_index"};
		} # end if
		if ( ( defined $$specs{"OverrideServicePrice-$$sig_specs{SignatureIndex}-$qty_index"} ) and ( $$specs{"OverrideServicePrice-$$sig_specs{SignatureIndex}-$qty_index"} eq 'Y' ) ) {
			$BestPricePerImposition{Service} = $$specs{"ServicePrice-$$sig_specs{SignatureIndex}-$qty_index"};
		} # end if
		if ( ( defined $$specs{"OverrideMaterialPrice-$$sig_specs{SignatureIndex}-$qty_index"} ) and ( $$specs{"OverrideMaterialPrice-$$sig_specs{SignatureIndex}-$qty_index"} eq 'Y' ) ) {
			$BestPricePerImposition{Material} = $$specs{"MaterialPrice-$$sig_specs{SignatureIndex}-$qty_index"};
		} # end if
		$BestPricePerImposition{Total} = misc::sum( @BestPricePerImposition{'MakeReady','Service','Material','Blanket','Cutting'} );

		if ( %minimum and ( $BestPricePerImposition{Total} < $minimum{Price} ) ) {
			$BestPricePerImposition{Breakdown} .= sprintf('Minimum: $%.2f<br/>', $minimum{Price});
			$BestPricePerImposition{Total} = $minimum{Price};
		} # end if

		if ( ( ! defined $BestPrice{Total} ) or ( $BestPricePerImposition{Total} < $BestPrice{Total} ) ) {
			$BestPrice{Total} = $BestPricePerImposition{Total};
			$BestPrice{MakeReady} = $BestPricePerImposition{MakeReady};
			$BestPrice{Service} = $BestPricePerImposition{Service};
			$BestPrice{Material} = $BestPricePerImposition{Material};
			$BestPrice{Blanket} = $BestPricePerImposition{Blanket};
			$BestPrice{Equipment} = $Equipment;
			$BestPrice{Breakdown} = 'Equipment: ' . $Equipment->name() . '<br/>' . $BestPricePerImposition{Breakdown};
			$BestPrice{Status} = 'calculated';
			$BestPrice{Overs} = $BestPricePerImposition{Overs};
		} # endif
	} # end foreach equipment

	return %BestPrice;
} # end sub signature_calc

sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

	$$variable{Equipment} = [ openprint::Equipment->find( Specifications => {'UVCoating Capable'=>'Y'}, 'useinestimating is null or ='=>1, order=>'lower(strName)') ];
} # end sub display

# Copies the UV settings back into the printing service, because that is where we have chosen to store them.
sub save {
	my ( $p_id, $s_id, $params ) = @_;
	my $Project = new openprint::Project( $p_id );
	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		#openprint::service::insert_service_spec( $openprint::log, $openprint::dbh, $p_id, $ss_id, 'SideOneUVCoatingType', $$params{'SideOneCoatingType-'.$$sig_specs{SignatureIndex}} );
		#openprint::service::insert_service_spec( $openprint::log, $openprint::dbh, $p_id, $ss_id, 'SideTwoUVCoatingType', $$params{'SideTwoCoatingType-'.$$sig_specs{SignatureIndex}} );
	} # end foreach
} # end sub

sub summary {
	return '';
} # end sub summary

sub load_equipment {
	@all_equipment = openprint::Equipment->find(
    Specifications => {'UVCoating Capable'=>'Y'},
    'useinestimating null_or_=' =>1,
    order=>'lower(strName)');
} # end sub load_equipment

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
        "OverrideBlanketPrice-$form-$qty_index",
        "OverrideServicePrice-$form-$qty_index",
        "OverrideMaterialPrice-$form-$qty_index",
        "OverrideSignaturePrice-$form-$qty_index",
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
