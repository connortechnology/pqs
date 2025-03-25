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

package openprint::Estimating::Aqueous;
use strict;
use warnings;
use vars qw( %ServicePrices %MaterialPrices );
use Data::Dumper;
use constant DEBUG => 0;

%ServicePrices = (
	AqueousMinimumCharge	=> { },
	AqueousMakeReady		=> { },
	'AqueousBlanketCutW&T'	=> { },
	AqueousBlanketCut	=> { },
	BlanketCut	=> { },
	'Aqueous(.*)'	=> { units => [ 'per 1000 impressions', 'per m', 'per hour', 'per side' ] },
);
my %Specifications = (
  'Aqueous Capable' => { values=>['Y','N','When Printing'] },
  'AqueousRunSpeed' => {},
  'Aqueous Double Sided When Perfecting' => {},
  'Aqueous Minimum Weight' => {units=>['gsm']},
  'HasCoater'=> {untis=>['Y','N']},
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
%MaterialPrices = (
'.*Aqueous.*' => { units => [ 'per square foot', 'per square inch', 'per 1000 square feet', 'per m', 'per kg' ] }
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
require openprint::Ink;

use vars qw( @outputs );
use Storable 'dclone';

my %Inks;
my %Services;
my %Materials;

# Offline Aqueous
# Let's assume that each piece of equipment can do 1 coat at a time
# This service doesn't store it's own data, other than price.  It gets the info from the printing service.
#
my @variables = (
	'alert',
	'txtQuantity1','txtQuantity2','txtQuantity3',
	'Markup1', 'Markup2', 'Markup3',
	'txtPrice1','txtPrice2','txtPrice3',
	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
);

sub variables {
	my $p_id = shift;

	my $Project = new openprint::Project($p_id);
	my @v = @variables;
	foreach my $s_s_id ( $Project->signatures() ) {
		my $specs = openprint::service::get_specs_ref($Project, $s_s_id);
		my $form = $$specs{SignatureIndex};
    push @v, 'ColourCoatingTypeOne'.$form, 'ColourCoatingTypeTwo'.$form;

		foreach my $qty_index ( $Project->quantity_indexes() ) {
			push @v, (
				 "ddmEquipment-$form-$qty_index", "chkOverrideEquipment-$form-$qty_index",
				 "txtImposition-$form-$qty_index", "chkOverrideImposition-$form-$qty_index",
				 "txtLayoutWidth-$form-$qty_index", "txtLayoutHeight-$form-$qty_index",
				 "MakeReadyPrice-$form-$qty_index", "OverrideMakeReadyPrice-$form-$qty_index", 
				 "BlanketCutPrice-$form-$qty_index", "OverrideBlanketCutPrice-$form-$qty_index", 
				 "ServicePrice-$form-$qty_index", "OverrideServicePrice-$form-$qty_index", 
				 "MaterialPrice-$form-$qty_index", "OverrideMaterialPrice-$form-$qty_index", 
				 "ImpressionPrice-$form-$qty_index", "OverrideImpressionPrice-$form-$qty_index", 
				 "SignaturePrice-$form-$qty_index", "OverrideSignaturePrice-$form-$qty_index", 
				 );
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
	'alert',
);
sub outputs {
	return @outputs;
}
sub no_outputs {
} # end sub no_outputs

my @no_outputs = (
);

my @all_equipment;

# A function that is smart enough to return true if the project needs perfing/Aqueous, and false if it doesn't.
sub neccessary {
	my ( $Project ) = @_;

	foreach my $sig_id ( $Project->signatures() ) {
		my $Service = $Project->Service( $sig_id );

		if ( signature_needs($Project, $Service->specs()) ) {
			return 1;
		}
	} # end foreach sig_id
	return 0;
} # end sub neccessary

sub get_colours {
  my ( $specs, $side ) = @_;
  my @colours;
  if ( 
      (
       ( defined $$specs{sides_the_same} ) and ( $$specs{sides_the_same} eq 'Y' )
       or
       ( defined $$specs{side_link} ) and ( $$specs{side_link} eq '1' )
      )
      and ( $side eq 'SideTwo' ) ) {
    $side = 'SideOne';
  } # end if

  foreach my $k ( keys %$specs ) {
#$openprint::log->debug("AQ get_colours $k => $$specs{$k}");
    if ( my ( $index ) = $k =~ /^chkColourCoating(\d+)$side/ ) {
      next if ! $$specs{"chkColourCoating$index$side"};
      if ( $$specs{"ColourCoatingType$index$side"} =~ /Aqueous/i ) {
        push @colours, $$specs{"ColourCoatingType$index$side"};
      } # end if
    } # end if
  } # end foreach
  return @colours;
} # end sub get_colours

sub signature_needs {
	my ( $Project, $sig_specs ) = @_;

	return 1 if ( $$sig_specs{SideOneAQ} and @{$$sig_specs{SideOneAQ}} ) or ( $$sig_specs{SideTwoAQ} and @{$$sig_specs{SideTwoAQ}} );

	if ( $$sig_specs{SideOneColours} ) {
		foreach ( @{$$sig_specs{SideOneColours}} ) {
			return 1 if $$_{name} =~ /Aqueous/i;
		} # end foreach colour
	} else {
		$$sig_specs{SideOneAQ} = [ get_colours( $sig_specs, 'SideOne' ) ] if ! $$sig_specs{SideOneAQ};
		return 1 if @{$$sig_specs{SideOneAQ}};
	} # en dif

	if ( $$sig_specs{SideTwoColours} ) {
		foreach ( @{$$sig_specs{SideTwoColours}} ) {
			return 1 if $$_{name} =~ /Aqueous/i;
		} # end foreach colour
	} else {
		$$sig_specs{SideTwoAQ} = [ get_colours( $sig_specs, 'SideTwo' ) ] if ! $$sig_specs{SideTwoAQ};
		return 1 if @{$$sig_specs{SideTwoAQ}};
	} # endif
	return 0;
} # end sub signature_needs

sub init {
	my ( $Project, $service_id, $calc_hash ) = @_;

	%Materials = ();
	%Services = ();
	$Services{AqueousMakeReady} = openprint::Service->find_one(name=>'AqueousMakeReady');
	$Services{AqueousMinimumCharge} = openprint::Service->find_one(name=>'AqueousMinimumCharge');
	$Services{AqueousBlanketCut} = openprint::Service->find_one(name=>'AqueousBlanketCut');
	$Services{'AqueousBlanketCutW&T'} = openprint::Service->find_one(name=>'AqueousBlanketCutW&T');
	$Services{BlanketCut} = openprint::Service->find_one(name=>'BlanketCut');
	%Inks = ();
  my $ServiceType = $Project->ServiceType($service_id);
	@all_equipment = openprint::Equipment->find(
			Specifications => {'Aqueous Capable'=>['Y','When Printing','1 Side']},
      'servicetype_id any' => $ServiceType->id(),
			useinestimating=>1,
			order=>'lower(strName)'
			) if ! @all_equipment;
}

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $status = 'calculated';
	$$specs{alert} = '';

	my $Project = new openprint::Project($project_index);
	init($Project, $service_index, {});

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"Markup$qty_index"} =~ s/[^\d\.\-]//g if $$specs{"Markup$qty_index"};
		$$specs{"txtPrice$qty_index"} =~ s/[^\d\.]//g if $$specs{"txtPrice$qty_index"};
		$$specs{"txtQuantity$qty_index"} =~ s/\D//g if $$specs{"txtQuantity$qty_index"};
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
		if ( $$specs{"txtQuantity$qty_index"} <= 0 ) {
			next;
		} # end if
		$$specs{'hdnBreakdown'.$qty_index} = '';
#sprintf('QTY: %d<br/>',$$specs{"txtQuantity$qty_index"} );

		my $qty = $$specs{"txtQuantity$qty_index"};
		if ( $$specs{txtPressSheetComboItems} ) {
			$$specs{txtPressSheetComboItems} =~ s/\D//g;
			if ( $$specs{txtPressSheetComboItems} ) {
				$qty *= $$specs{txtPressSheetComboItems} 
			} else {
				$$specs{alert} .= 'Combination items is invalid.';
			} # end if
		} # end if

		my %MakeReadies;

		my $GrandTotal = 0;
		foreach my $signature_service_index ( $Project->signatures( { sort=>1 } ) ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
# If any of the signatures doesn't have an imposition, then we are in an incomplete state.
			if ( ! $$sig_specs{'txtImposition'.$qty_index} ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'No imposition was found for printing.<br/>';
				next;
			} # end if
			my $form = $$sig_specs{SignatureIndex};
			$$specs{'hdnBreakdown'.$qty_index} .= "<fieldset><legend>Signature $form: ".($$sig_specs{txtServiceDescription}? $$sig_specs{txtServiceDescription}:'').'</legend>';
			my $Imposition = new openprint::Imposition();
			$Imposition->load( $sig_specs, $qty_index, $Project );
			if ( ! $$Imposition{imposition} ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'Problem loading the imposition. Unable to calculate a price for it.';
				$$specs{alert} .= "Problem loading the imposition for $$sig_specs{SignatureIndex} $$sig_specs{txtServiceDescription}<br/>";
				$status = 'uncalculated';
				next;
			}
			my %results = signature_calc( $Project, $specs, $sig_specs, $qty_index, $Imposition, \%MakeReadies );
# if signature_needs($Project, $sig_specs);
$openprint::log->error(Data::Dumper::Dumper(\%results));
			if ( $results{Equipment} ) {
				$MakeReadies{$results{Equipment}{id}} = {} if ! $MakeReadies{$results{Equipment}{id}};
				foreach my $type ( $results{types} ? @{$results{types}} : () ) {
					$MakeReadies{$results{Equipment}{id}}{$type} = [] if ! $MakeReadies{$results{Equipment}{id}}{$type};
					push @{$MakeReadies{$results{Equipment}{id}}{$type}}, $Imposition->layout_area();
				}
			}
      $$specs{"hdnBreakdown$qty_index"} .= $results{breakdown};
			@outputs = sets::union( @outputs, 
					"ddmEquipment-$form-$qty_index",
					"txtImposition-$form-$qty_index",
					"txtLayoutWidth-$form-$qty_index", "txtLayoutHeight-$form-$qty_index",
					"MakeReadyPrice-$form-$qty_index",
					"BlanketPrice-$form-$qty_index",
					"ServicePrice-$form-$qty_index",
					"MaterialPrice-$form-$qty_index",
					"SignaturePrice-$form-$qty_index",
					"ImpressionPrice-$form-$qty_index",
					);
			foreach my $price_type ( 'MakeReady', 'BlanketCut', 'Service', 'Material', 'Impression' ) {
				if ( (!defined $$specs{"Override${price_type}Price-$form-$qty_index"}) 
						or ($$specs{"Override${price_type}Price-$form-$qty_index"} ne 'Y') ) {
					$$specs{"${price_type}Price-$form-$qty_index"} = sprintf($openprint::config{ProjectMoneyFormat}, $results{$price_type} ? $results{$price_type} : 0);
				} # end if
			} # end foreach price type

			if ( (!defined $$specs{"OverrideSignaturePrice-$form-$qty_index"}) 
					or ($$specs{"OverrideSignaturePrice-$form-$qty_index"} ne 'Y') ) {
				$$specs{"SignaturePrice-$form-$qty_index"} = sprintf($openprint::config{ProjectMoneyFormat}, $results{Total} // 0);
			} # end if

			if ( ( ! defined $$specs{"chkOverrideEquipment-$form-$qty_index"} ) or ( $$specs{"chkOverrideEquipment-$form-$qty_index"} ne 'Y' ) ) {
				$$specs{"ddmEquipment-$form-$qty_index"} = '';
			} # end if
			if ( $results{Status} eq 'uncalculated' ) {
				$status = 'uncalculated';
				if ( $$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' ) {
					$$specs{alert} .= 'The selected equipment can not handle your project.  This may be because the stock is too heavy, or too large.';
				} else {
					$$specs{alert} .= 'No suitable equipment could be found for your project.  This may be because the stock is too heavy, or too large.';
				} # end if
			} else {
				if ( $results{Equipment} ) {
					$$specs{"ddmEquipment-$form-$qty_index"} = $results{Equipment}{id};
					$GrandTotal += $$specs{"SignaturePrice-$form-$qty_index"};
					$$specs{"txtImposition-$form-$qty_index"} = $results{Imposition}{imposition};
					$$specs{"txtLayoutWidth-$form-$qty_index"} = $results{Imposition}->layout_width();
					$$specs{"txtLayoutHeight-$form-$qty_index"} = $results{Imposition}->layout_height();
				} else {
					$$specs{"txtImposition-$form-$qty_index"} = 0;
					$$specs{"txtLayoutWidth-$form-$qty_index"} = 0;
					$$specs{"txtLayoutHeight-$form-$qty_index"} = 0;
				} # end if
			} # end if uncalculated
      $$specs{"hdnBreakdown$qty_index"} .= '</fieldset>';
		} # end foreach signature

		$GrandTotal *= ( 1+$Project->markup()/100 ) if $Project->markup();
		$GrandTotal *= ( 1+$$specs{"Markup$qty_index"}/100 ) if $$specs{"Markup$qty_index"};

		$$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $GrandTotal / $qty );
		if (!$$specs{'OverridePrice'.$qty_index} or ( $$specs{'OverridePrice'.$qty_index} ne 'Y')) {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $GrandTotal );
		} else {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{'txtPrice'.$qty_index} );
		} # end if
	} # end foreach qty

	return $status;
} # end sub calc

sub signature_calc {
	my ( $Project, $specs, $sig_specs, $qty_index, $Imposition, $MakeReadies ) = @_;

	if ( DEBUG ) {
		foreach my $equipment_id ( keys %{$MakeReadies} ) {
			foreach my $type ( keys %{$$MakeReadies{$equipment_id}} ) {
				$openprint::log->debug("Makereadies before aq calc equipment: $equipment_id $type: ".join(',',@{$$MakeReadies{$equipment_id}{$type}}));
			}
		}
		$Imposition->display('AQ::signature_calc');
	}

	my $form = $$sig_specs{SignatureIndex};
	my %bestPrice;
	$bestPrice{Status} = 'uncalculated';
  $bestPrice{breakdown} = '';

	my @front_aq;
	my %front_aq;
	$$sig_specs{SideOneColours} = [openprint::Estimating::Printing::get_colours($sig_specs, 'SideOne')] if ! $$sig_specs{SideOneColours};
	foreach ( @{$$sig_specs{SideOneColours}} ) {
		if (-1 != index($$_{name}, 'Aqueous')) {
			push @front_aq, $_;
			$front_aq{$$_{name}} = $_;
		} # end if
	} # end foreach colour
  if (!@front_aq and $$specs{'ColourCoatingTypeOne'.$form}) {
    push @front_aq, {name=>$$specs{'ColourCoatingTypeOne'.$form}};
    $front_aq{$$specs{'ColourCoatingTypeOne'.$form}} = {name=>$$specs{'ColourCoatingTypeOne'.$form}};
  }

	my @back_aq;
	my %back_aq;
	$$sig_specs{SideTwoColours} = [openprint::Estimating::Printing::get_colours($sig_specs, 'SideTwo')] if ! $$sig_specs{SideTwoColours};
	foreach ( @{$$sig_specs{SideTwoColours}} ) {
		if ( -1 != index($$_{name}, 'Aqueous') ) {
			push @back_aq, $_;
			$back_aq{$$_{name}} = $_;
		} # end if
	} # end foreach colour
  if (!@back_aq and $$specs{'ColourCoatingTypeTwo'.$form}) {
    push @back_aq, {name=>$$specs{'ColourCoatingTypeTwo'.$form}};
    $back_aq{$$specs{'ColourCoatingTypeTwo'.$form}} = {name=>$$specs{'ColourCoatingTypeTwo'.$form}};
  }

	if ( ! ( @front_aq or @back_aq ) ) {
		my ( $caller, undef, $line ) = caller;
		$openprint::log->warn("Doing AQ when not needed @front_aq @back_aq from $caller:$line");
		$bestPrice{Status} = 'calculated';	
		return %bestPrice;
	} # end if

	my %different_types = ( %front_aq, %back_aq );
	my @different_types = keys %different_types;
#sets::union( keys %front_aq, keys %back_aq );
	my @filtered_colours = openprint::Estimating::Printing::filter_colours( @$sig_specs{'SideOneColours','SideTwoColours'} ) if $$Imposition{runstyle} =~ /^Work/;

	# Should include overs
	my $impressions = $$sig_specs{"hdnImpressionQuantity$qty_index"} ? $$sig_specs{"hdnImpressionQuantity$qty_index"} : $$specs{"txtQuantity$qty_index"};
	$openprint::log->debug('Impressions: ' . $$sig_specs{"hdnImpressionQuantity$qty_index"} . ' qty: ' . $$specs{"txtQuantity$qty_index"} ) if DEBUG;
	if ( 
		@{$$sig_specs{SideTwoColours}} 
		and 
		@{$$sig_specs{SideOneColours}} 
		and 
		( $$Imposition{runstyle} eq 'Sheet Work' ) 
	 ) {
		$impressions /= 2;
	}

	my @equipment;	
	if ( (defined $$specs{"chkOverrideEquipment-$form-$qty_index"}) and ( $$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' ) ) {
		@equipment = ( new openprint::Equipment( $$specs{"ddmEquipment-$form-$qty_index"} ) );
	} else {
		@equipment = @all_equipment;
	} # endif

	if ( (defined $$specs{"chkOverrideImposition-$form-$qty_index"}) and ( $$specs{"chkOverrideImposition-$form-$qty_index"} eq 'Y' ) ) {
		if ( ($$specs{"txtImposition-$form-$qty_index"} > $$Imposition{imposition}) or ($$specs{"txtImposition-$form-$qty_index"} <= 0) ) {
			$$specs{alert} .= 'The specified imposition is not possible.<br/>';
			return %bestPrice;
		} # end if
	} # end if

	my @impositions = ();
	@impositions = ( $Imposition->copy() );
	my $Paper = $Imposition->Paper();

	my $AllAqueousMakeReady = $Services{AqueousMakeReady};
	my $AqueousMinimumCharge = $Services{AqueousMinimumCharge};

	my $BlanketCutService = $Services{AqueousBlanketCut};
	$BlanketCutService = $Services{BlanketCut} if ! $BlanketCutService;
	my $BlanketCutServiceWT = $Services{'AqueousBlanketCutW&T'};
	$BlanketCutServiceWT = $BlanketCutService if ! $BlanketCutServiceWT;

	$Materials{Aqueous} = openprint::Material->find_one(name=>'Aqueous') if ! exists $Materials{Aqueous};
	
	foreach my $Equipment ( @equipment ) {
		$openprint::log->debug("AQ Equipment $$Equipment{strid}") if DEBUG;
		my $number_of_colours = $Equipment->specification('Number of Colours');
		my $Aqueous_Capable = $Equipment->specification('Aqueous Capable');
		$$specs{'hdnBreakdown'.$qty_index} .= join(' ',
				'Equipment:', $$Equipment{strid}, $Aqueous_Capable, 'Printing on '.$$sig_specs{'ddmPress'.$qty_index}, '<br/>');

		if ( ($Aqueous_Capable eq 'When Printing') or ($Aqueous_Capable eq '1 Side') ) {
			if ( $$sig_specs{'ddmPress'.$qty_index} ne $$Equipment{strid} ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'Not printing on this press.<br/>';
				next;
			} elsif ( @front_aq and @back_aq and ( $$Imposition{runstyle} eq 'Perfecting' ) and ! $Equipment->specification('Aqueous Double Sided When Perfecting') ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'Cant perfect with double sided AQ.<br/>';
				next;
			} # end if
		}

		if ( my $min_weight = $Equipment->specification('Aqueous Minimum Weight') ) {
			if ( $min_weight > $Paper->gsm() ) {
				$$specs{'hdnBreakdown'.$qty_index} .= "Paper is too light. Paper gsm($$Paper{gsm}) < Minimum weight $min_weight gsm<br/>";
				next;
			} elsif (DEBUG) {
				$openprint::log->debug("Min weight: $min_weight > $$Paper{gsm}");
			}
		} # end if

		my %minimum = $AqueousMinimumCharge->get_price(undef, $Equipment) if $AqueousMinimumCharge;
		my $sheet_width = $Imposition->sheet_width();
		my $sheet_height = $Imposition->sheet_height();

		foreach my $imp ( @impositions ) {
			#$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Imposition: %dx%d+%dx%d=%dout %s:', @$imp{'columns','rows','dutch_columns','dutch_rows','imposition','runstyle'} );
			#next if ! $$imp{imposition};

			my $width = $sheet_width / ( $$Imposition{columns}/$$imp{columns} );
			my $height = $sheet_height / ( $$Imposition{rows}/$$imp{rows} );
			if ( ($width != $sheet_width) or ($height != $sheet_height) ) {
				$$specs{'hdnBreakdown'.$qty_index} .= $sheet_width.'x'.$sheet_height.'=>'.$width.'x'.$height.'<br/>';
			}

			if ( $_ = $Equipment->fits($width, $height, $$sig_specs{txtSpecificStockCalliper}) ) {
				$$specs{'hdnBreakdown'.$qty_index} .= "Doesn't fit. $_<br/>";
				next;
			} # end if

# Make Readies is a hash of array refs, need to copy the arrays as well.
			my $MakeReadies_clone = $MakeReadies ? dclone($MakeReadies) : {};
#map { $_ => [ @{$$MakeReadies{$_}} ] } keys %{$MakeReadies} if $MakeReadies;
			my %Price = (
        MakeReady => 0,
        Service => 0,
        Material => 0,
				BlanketCut	=>	0,
        washups => 0,
			);
			my $run_qty = $impressions;
			$run_qty *= ( $$Imposition{imposition} / $$imp{imposition} ) if $$Imposition{imposition} != $$imp{imposition};
			$Price{impressions} = $run_qty;

			my @types;
			if ( !index($$Imposition{runstyle}, 'Work') ) {
# need to merge any overalls into spots
				foreach my $type ( @different_types ) {
          $openprint::log->debug("$type to W&T front: ".($front_aq{$type} ? $front_aq{$type} : 'none').' back: '.($back_aq{$type} ? $back_aq{$type} : 'none')) if DEBUG;
					if ( ! ( $front_aq{$type} and $back_aq{$type} ) ) {
						$type =~ s/Overall/W&T/;
						push @types, { name => $type, coverage=> $front_aq{$type} ? $front_aq{$type}{coverage}/2 : $back_aq{$type}{coverage}/2 };
					} else {
						push @types, { name => $type, coverage=>($front_aq{$type}{coverage} + $back_aq{$type}{coverage} )/2 };
					} # end if
				} # end foreach
				# In W&T, the impression count is total impressions, so both sides already, so no need to multiply
				#$run_qty *= 2;
			} else {
				@types = (@front_aq, @back_aq);
			} # end if

			$$MakeReadies_clone{$$Equipment{id}} = {} if ! $$MakeReadies_clone{$$Equipment{id}};
			my $mrs = $$MakeReadies_clone{$$Equipment{id}};

			$Price{types} = [ map { $$_{name} } @types ];
			$openprint::log->debug("Types: @{$Price{types}}") if DEBUG;

			my $area = $imp->layout_area();
			foreach my $type ( @types ) {
				my $type_name = $$type{name};

				my %SetupPrice;
				my $colour_total = 0;
				$openprint::log->debug("Makereadies: $$Equipment{id} $$Equipment{strid} this area: ".($area * .90) . " < $area < " . ($area * 1.10) . "$type_name ? " .
						( ($$mrs{$type_name} ) ? join(',', @{$$mrs{$type_name}}) : 'none' ) ) if DEBUG;

				if (
						$$mrs{$type_name} and
						( map { ( (($area * 1.10) > $_) and (($area * .90) < $_) ) ? $_ : () } @{$$mrs{$type_name}} )
					 ) {
					$openprint::log->debug("In Makereadies: $$Equipment{id} $area") if DEBUG;
          $SetupPrice{Total} = 0;
				} else {
					$openprint::log->debug("Not In Makereadies: $$Equipment{id} $area") if DEBUG;
					$Services{$type_name.' MakeReady'} = openprint::Service->find_one(name=>$type_name.' MakeReady') if ! exists $Services{$type_name.' MakeReady'};
					my $MRService = $Services{$type_name.' MakeReady'};
					$MRService = $AllAqueousMakeReady if ! $MRService;
					if ( ! $MRService ) {
						$$specs{'hdnBreakdown'.$qty_index} .= 'No Make Ready Service for ' . $type_name . '<br/>';
					} else {
						%SetupPrice = $MRService->get_price($run_qty, $Equipment);
					} # end if
          $SetupPrice{Total} = $SetupPrice{Price};
					$Price{MakeReady} += $SetupPrice{Total};
					if ( ! $$mrs{$type_name} ) {
						$openprint::log->debug("Adding a washup for $$Equipment{id} $type_name") if DEBUG;
						$Price{washups} += 1;
					}
					$$mrs{$type_name} = [] if ! $$mrs{$type_name};
					push @{$$mrs{$type_name}}, $area;
					$colour_total += $SetupPrice{Price};
				} # end if makereadies
				push @{$Price{SetupPrices}}, \%SetupPrice;
				my %BlanketCutPrice;
				if ((-1 != index($type_name, 'Spot')) or ($$type{coverage} < 100)) {
          if ($BlanketCutService) {
            %BlanketCutPrice = $BlanketCutService->get_price(undef, $Equipment) if $BlanketCutService;
          } else {
            $openprint::log->warn('No blankcut service found');
          }
				} elsif ( -1 != index($type_name, 'W&T') ) {
					%BlanketCutPrice = $BlanketCutServiceWT->get_price(undef, $Equipment) if $BlanketCutServiceWT;
				} # end if type is spot
				if ( %BlanketCutPrice ) {
          $BlanketCutPrice{Total} = $BlanketCutPrice{Price};
					$Price{BlanketCut} += $BlanketCutPrice{Price};
					$colour_total += $BlanketCutPrice{Price};
        } else {
          $BlanketCutPrice{Total} = 0;
				} # end if
				push @{$Price{BlanketCutPrices}}, \%BlanketCutPrice;	

				$Services{$type_name} = openprint::Service->find_one(name=>$type_name) if ! $Services{$type_name};
				my $Service = $Services{$type_name};
				if ( ! $Service ) {
					$$specs{'hdnBreakdown'.$qty_index} = 'No Service for '.$type_name.'<br/>';
					next;
				} # end if

				my %ServicePrice = $Service->get_price($run_qty, $Equipment);
				if ( ! %ServicePrice ) {
          if ($Service = openprint::Service->find_one(name=>'Aqueous')) {
            %ServicePrice = $Service->get_price($run_qty, $Equipment);
          }
        }
				if ( ! %ServicePrice ) {
					$$specs{'hdnBreakdown'.$qty_index} .= 'No Service price for '.$type_name.'<br/>';
					$ServicePrice{Total} = 1000000;
				} # end if
				if ( $ServicePrice{units} eq 'per 1000 impressions' ) {
					%ServicePrice = $Service->get_price($impressions, $Equipment);
					$ServicePrice{Quantity} = $impressions;
					$ServicePrice{Total} = $ServicePrice{Price} * $impressions / 1000;
				} elsif ( ($ServicePrice{units} eq 'per m') or ($ServicePrice{units} eq 'per 1000') ) {
					$ServicePrice{Quantity} = $run_qty;
					$ServicePrice{Total} = $ServicePrice{Price} * $run_qty / 1000;
				} elsif ( $ServicePrice{units} eq 'per hour' ) {
					$ServicePrice{Quantity} = $run_qty;
					my $run_speed = $Equipment->specification('AqueousRunSpeed');
					$ServicePrice{Total} = $ServicePrice{Price} * $run_qty / $run_speed if $run_speed;
        } elsif ( $ServicePrice{units} eq 'per side' ) {
          $ServicePrice{Quantity} = $run_qty;
          $ServicePrice{Total} = $ServicePrice{Price} * $run_qty;
				} else {
					$$specs{'hdnBreakdown'.$qty_index} = "Unknown units ( $ServicePrice{units} ) for $$type{name}<br/>";
          $ServicePrice{Total} = 0;
				} # end if
				push @{$Price{ServicePrices}}, \%ServicePrice;
				$Price{Service} += $ServicePrice{Total};
				$colour_total += $ServicePrice{Total};

				my %MaterialPrice;
				my $material_name = $type_name;
				$material_name =~ s/ ?Spot ?//;
				$material_name =~ s/ ?Overall ?//;
				$material_name =~ s/ ?W&T ?//;
				if ( ! exists $Materials{$material_name} ) {
					$Materials{$material_name} = openprint::Material->find_one(name=>$material_name);
					if ( ! $Materials{$material_name} ) {
						$Materials{$material_name} = $Materials{Aqueous};
					}
				}
				my $Material = $Materials{$material_name};
				if ( ! $Material ) {
					$$specs{'hdnBreakdown'.$qty_index} .= 'No material for aqueous found.<br/>';
				} else {
          my $area;
          if ($$type{coverage}==100) {
            $area = $imp->sheet_width()*$imp->sheet_height() * $run_qty;
          } else {
            $area = $imp->layout_area() * $run_qty;
          }

					%MaterialPrice = $Material->get_price( $run_qty, $Equipment );
					if ( $MaterialPrice{units} eq 'per square inch' ) {
						$area *= $$type{coverage}/100;
						$MaterialPrice{Total} = $MaterialPrice{Price} * $run_qty * $area;
					} elsif ( $MaterialPrice{units} eq 'per square foot' ) {
						$area *= ($$type{coverage}/100) /144;
						$MaterialPrice{Total} = $MaterialPrice{Price} * $area;
					} elsif ( $MaterialPrice{units} eq 'per 1000 square feet' ) {
						$area *= ($$type{coverage}/100) /144;
# area is # of square feet
						$MaterialPrice{Total} = $MaterialPrice{Price} * $area/1000;
					} elsif ( $MaterialPrice{units} eq 'per m' ) {
						$MaterialPrice{Total} = $MaterialPrice{Price} * $run_qty / 1000;
					} elsif ( $MaterialPrice{units} eq 'per kg' ) {
						my $coverage = $$type{coverage}/100;
						$area *= $coverage;
			
						$Inks{$type_name} = openprint::Ink->find_one(name=>$type_name) if ! exists $Inks{$type_name};
						my $Ink = $Inks{$type_name};
						if ( !$Ink ) {
							$openprint::log->error("No ink found for $type_name");
						} else {
							my $grade = $Paper->grade();
							my $Coverage = $Ink->Coverage($Equipment, $grade);
							if ( (!$Coverage) or !$$Coverage{value} ) {
								$openprint::log->error("No Coverage for grade $grade : $$Equipment{strid}");
							} else {
								my $qty = Math::Round::nearest( 0.01, $area/$$Coverage{value} ) if $Coverage and $$Coverage{value};
								%MaterialPrice = $Material->get_price($qty, $Equipment);
								$MaterialPrice{Total} += Math::Round::nearest(0.01, $MaterialPrice{Price} * $qty);
								$MaterialPrice{Breakdown} = sprintf('Coverage %d%% * %sx%s = %d square inches, mileage: %dsquare inches/kg = %.2fkg * $%s%s=$%.2f',
										$coverage*100, 
                    ($$type{coverage}==100?($imp->sheet_width(), $imp->sheet_height()) : ($imp->layout_width(), $imp->layout_height())),
                    $area, $$Coverage{value}, $qty, @MaterialPrice{'Price','units','Total'});
							} # end if coverage
						} # end if ink

					} elsif ( $MaterialPrice{Price} ) {
						$$specs{'hdnBreakdown'.$qty_index} .= "Unknown units for Material $$Material{name} ($MaterialPrice{units})<br/>";
					} # end if
					$Price{Material} += $MaterialPrice{Total};
					$colour_total += $MaterialPrice{Total};
				} # end if
				push @{$Price{MaterialPrices}}, \%MaterialPrice;
			} # end foreach type

			my $ImpressionPrice;
      my $impression_service;
			$Price{Impression} = 0;

      my $has_coater = $Equipment->specification('HasCoater');

      if ((!$has_coater  or $has_coater ne 'Y') and ((@front_aq>1) or (@back_aq>1)) ) {
        if ( !index($$imp{runstyle}, 'Work') ) {
          if ( @filtered_colours > $number_of_colours ) {
            # Then AQ is done as a separate run
            # Don't need to worry about Perfecting or Web
            $impression_service = (@filtered_colours - @types).'ColourImpression';
          } # end if more colours than allow
        } else {
          if ( @front_aq and ( @{$$sig_specs{SideOneColours}} > $number_of_colours ) ) {
            # Have more colours than the press supports, so the AQ is in it's own run
            $impression_service = (@{$$sig_specs{SideOneColours}} - @front_aq).'ColourImpression';
          } elsif ( @back_aq and ( @{$$sig_specs{SideTwoColours}} > $number_of_colours ) ) {
            # Have more colours than the press supports, so the AQ is in it's own run
            $impression_service = (@{$$sig_specs{SideTwoColours}} - @back_aq).'ColourImpression';
          }
        } # end if W&T or not

        if ($impression_service) {
          my $Impression_Service = openprint::Service->find_one(name=>$impression_service);
          if ( ! $Impression_Service ) {
            $openprint::log->error("No service for $impression_service");
          } else {
            $ImpressionPrice = $Impression_Service->get_Price($impressions, $Equipment);
            if ( $$ImpressionPrice{units} eq 'per hour' ) {
              $$sig_specs{Runspeed} = $$sig_specs{"Runspeed$qty_index"} if ! $$sig_specs{Runspeed};
              $Price{Runspeed} = $$sig_specs{Runspeed};

              my $hours = $$ImpressionPrice{quantity} = $run_qty / $$sig_specs{Runspeed};
              $$ImpressionPrice{Total} = Math::Round::nearest(0.01, $$ImpressionPrice{Price} * $hours );
              $Price{Impression} += $$ImpressionPrice{Total};
              push @{$Price{ImpressionPrices}}, $ImpressionPrice;
            } elsif ($$ImpressionPrice{units} eq 'per m') {
              $$ImpressionPrice{Total} = Math::Round::nearest(0.01, $$ImpressionPrice{Price} * $run_qty/1000 );
              $Price{Impression} += $$ImpressionPrice{Total};
              push @{$Price{ImpressionPrices}}, $ImpressionPrice;
            } else {
              $openprint::log->error("Unknown units $$ImpressionPrice{units} on $impression_service on $$Equipment{strid} for quantity $impressions price");
            }
          } # end if have impression service
        }
      }

			foreach my $price_type ( 'MakeReady', 'BlanketCut', 'Service', 'Material', 'Impression', 'Signature' ) {
				if (
						( defined $$specs{"Override${price_type}Price-$form-$qty_index"} )
						and
						( $$specs{"Override${price_type}Price-$form-$qty_index"} eq 'Y' )
					 ) {
					$Price{$price_type} = $$specs{"${price_type}Price-$form-$qty_index"};
				} # end if
			} # end foreach price_type

			$Price{Total} = $Price{MakeReady} + $Price{Service} + $Price{Material} + $Price{BlanketCut};
			$Price{Total} += $Price{Impression} if $Price{Impression};
			if ( %minimum and ( $Price{Total} < $minimum{Price} ) ) {
				$Price{Minimum} = $Price{Total} = $minimum{Price};
			} # end if

			if ( ( ! defined $bestPrice{Total} ) or ( $Price{Total} < $bestPrice{Total} )) {
				%bestPrice = %Price;
				$bestPrice{Equipment} = $Equipment;
				$bestPrice{Imposition} = $imp;
			} # end if
		} # end foreach Imposition
	} # end foreach equipment

	if ( defined $bestPrice{Total} ) {
		$bestPrice{Status} = 'calculated';
	} # end if
	$bestPrice{breakdown} = breakdown(\%bestPrice);

	return %bestPrice;
} # end sub signature_calc

sub breakdown {
	my $Price = shift;
	my $breakdown = $$Price{Imposition}{imposition} . 'out on ' . ($$Price{Equipment} ? $$Price{Equipment}->name() : 'unknown').'<br/>' if $$Price{Imposition};
	for ( my $i = 0; $i < ( $$Price{types} ? scalar @{$$Price{types}} : 0); $i ++ ) {
		my $type = $$Price{types}[$i];
		my $SetupPrice = $$Price{SetupPrices}[$i];
		my $BlanketCutPrice = $$Price{BlanketCutPrices}[$i];
		my $ServicePrice = $$Price{ServicePrices}[$i];
		my $MaterialPrice = $$Price{MaterialPrices}[$i];

		my $colour_total = $$SetupPrice{Total} + $$BlanketCutPrice{Total} + $$ServicePrice{Total} + $$MaterialPrice{Total};
		$$MaterialPrice{Breakdown} = sprintf('$%.4f%s = $%.2f', @$MaterialPrice{'Price','units','Total'}) if !$$MaterialPrice{Breakdown};
		$breakdown .= sprintf(
				'%s MakeReady: $%.2f<br/>Blanket Cut: $%.2f<br/>Service: ($%.2f%s*%d)=$%.2f<br/>Material: %s<br/>Total: $%.2f<br/>',
			$type,
			$$SetupPrice{Price},
      ($$BlanketCutPrice{Price} ? $$BlanketCutPrice{Price} : 0),
			@$ServicePrice{'Price','units','Quantity','Total'},
			$$MaterialPrice{Breakdown}, $colour_total );
	} # end foreach aq type

	foreach my $ImpressionPrice ( $$Price{ImpressionPrices} ? @{$$Price{ImpressionPrices}} : () ) {
		$breakdown .= sprintf('Additional pass: (%d/%dper hour) %.2f%s * %.2f hours = $%.2f<br/>',
				@$Price{'impressions','Runspeed'},
				@$ImpressionPrice{'Price','units','quantity','Total'} );
	} # end foreach
	$breakdown .= 'Washups: '.$$Price{washups}.'<br/>';
	$breakdown .= sprintf('Minimum Charge: $%.2f<br/>', $$Price{Minimum}) if $$Price{Minimum};
	return $breakdown;
} # end sub breakdown

sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;
  #my $Project = new openprint::Project($project_index);
  #my $ServiceType = $Project->ServiceType($service_index);
} # end sub display

# Copies the AQ settings back into the printing service, because that is where we have chosen to store them.
sub save {
	my ( $p_id, $s_id, $params ) = @_;
	my $Project = new openprint::Project( $p_id );
} # end sub

sub summary {
	my ( $Project, $service_index, $specs, $qty_index ) = @_;
  my $summary = '';
  if ($qty_index) {
    foreach my $sig_id ( $Project->signatures( { sort=>1 } ) ) {
      my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
      my $form = $$sig_specs{SignatureIndex};
      if ($$specs{"ddmEquipment-$form-$qty_index"}) {
        $summary .= $$specs{"txtImposition-$form-$qty_index"}.' out';
        $summary .= ' on '.(new openprint::Equipment($$specs{"ddmEquipment-$form-$qty_index"})->name()).'<br/>';
      }
    } # end foreah;
  } else {
		foreach my $s_s_id ( $Project->signatures() ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
			my $form = $$sig_specs{SignatureIndex};
      if (
          ($$specs{'ColourCoatingTypeOne'.$form} and ($$specs{'ColourCoatingTypeOne'.$form} ne 'None'))
          or
          ($$specs{'ColourCoatingTypeTwo'.$form} and ($$specs{'ColourCoatingTypeTwo'.$form} ne 'None'))
         ) {
        $summary .= 'Form '.$form.': '.join(' ',
            ($$specs{'ColourCoatingTypeOne'.$form} and ($$specs{'ColourCoatingTypeOne'.$form} ne 'None') ? $$specs{'ColourCoatingTypeOne'.$form}. ' on front' : ()),
            ($$specs{'ColourCoatingTypeTwo'.$form} and ($$specs{'ColourCoatingTypeTwo'.$form} ne 'None') ? $$specs{'ColourCoatingTypeTwo'.$form}. ' on back' : ()),
            ).
          '<br/>';

      }
    } # end foreach sig
  } # end if qtu
  return $summary;
} # end sub summary

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
					"OverrideBlanketPrice-$form-$qty_index",
					"OverrideServicePrice-$form-$qty_index",
					"OverrideMaterialPrice-$form-$qty_index",
					"OverrideSignaturePrice-$form-$qty_index",
					);
		} # end foreach sig
	} # end if

	return @v;
} # end sub has_overrides

1;
__END__
