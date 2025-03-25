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

package openprint::Estimating::ChannelLetters;
use strict;

require sql;
require openprint::service;
require POSIX;

	#'ServiceType',
	#'rdbChannelLettersType',
my @variables = (
	'letters','letter_height','letter_font',
	'can_finish',
	'include_leds','led_colour','led_density','led_quantity','led_power_supply','led_install',

	'txtWidth','txtHeight',

	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
	'Markup1', 'Markup2', 'Markup3',
	'txtPrice1', 'txtPrice2', 'txtPrice3',
	'txtUnitPrice1', 'txtUnitPrice2', 'txtUnitPrice3',
	'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
	'alert', 
	'hdnBreakdown1',
	'hdnBreakdown2',
	'hdnBreakdown3',

);

my %font_sizes = (
	Helvetica	=>	{
		9 => {
			width	=>	9.1875,
		},
		12	=> {
			width	=>	10.5,
		},
		15	=> {
			width	=>	13.125,
		},
		18	=> {
			width	=>	14.5,
		},
		24	=> {
			width	=>	21,
		},
	},
	'Times Bold'=>  {
        9 => {
           width   =>  8.75,
        },
        12  => {
            width   =>  11.75,
        },
        15  => {
            width   =>  14.5,
        },
        18  => {
            width   =>  17.1875,
        },
        24  => {
            width   =>  23,
        },
    },
);

sub variables {
	my ( $p_id, $s_id, $old_specs, $specs ) = @_;
	my @v = @variables;
	#my $Project = new openprint::Project( $p_id );
	#foreach my $ss_id ( $Project->signatures() ) {
		#my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
	#} # end foreach signature
	return @v;
} # end sub variables

my @outputs = (
	'hdnBreakdown1', 'hdnBreakdown2', 'hdnBreakdown3',
	'txtPrice1', 'txtPrice2', 'txtPrice3',
	'txtUnitPrice1', 'txtUnitPrice2', 'txtUnitPrice3',
);

sub get_outputs {
	return @outputs;
} # end sub get_output

my @no_outputs = (
	'ProjectIndex', 'ServiceIndex', 'txtQuantity1','txtQuantity2','txtQuantity3',
	'ServiceType',
	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
	'Markup1', 'Markup2', 'Markup3',
);

sub no_outputs {
	my ( $p_id, $s_id, $specs ) = @_;
	my @o = @no_outputs;

	my $Project = new openprint::Project( $p_id );
	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		#push @o, ( "chkOverrideArea-$$sig_specs{'SignatureIndex'}", );
	} # end foreach signature
	return @o;
};

sub neccessary {
	my ( $log, $dbh, $project_index ) = @_;

	my $Project = new openprint::Project( $project_index );
    my $services = $Project->services();

    if ( $$services{'NoBindery'} ) {
        $log->debug(" ** Project is marked as No bindery, Cutting not needed ! ** ");
        return 0;
    } # end if

    if ( $Project->Type()->name() eq 'PresentationFolders' ) {
        return 1;
    } # end if
	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		if ( sets::isin( $$sig_specs{'rdbTemplateType'}, ['2Panel1Pocket','2Panel2Pocket','TriFoldDoublePocket'] ) ) {
			return 1;
		} # end if
	} # end foreach signature

	return 0;
} # end sub neccessary

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;
$openprint::log->debug("CHannelLetters:");

	my $status = 'calculated';
	$$specs{alert} = '';

foreach my $k ( keys %$specs ) {
$openprint::log->debug("$k => $$specs{$k}");
}

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();

	s/^\s+//, s/\s+$// for $$specs{letters};
	if ( ! $$specs{letters} ) {
		$$specs{alert} .= 'Please enter the letters of your sign.<br/>';
		return $$specs{Status} = 'uncalculated';
	}
	if ( ! $$specs{letter_height} ) {
		$$specs{alert} .= 'Please enter the height of your upper-case letters.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if
	if ( ! $$specs{letter_font} ) {
		$$specs{alert} .= 'Please select the font of your sign.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if

	my $LED_Material;
	if ( $$specs{include_leds} eq 'Y' ) {
		if ( ! sets::isin( $$specs{led_density}, [ 'high','medium','low' ] ) ) {
			$$specs{alert} .= 'Please select the density of LEDs.<br/>';
			return $$specs{Status} = 'uncalculated';
		} # end if
		$LED_Material = openprint::Material->find_one(name=>'LED');
	} # end if
	my $font_specs = $font_sizes{$$specs{letter_font}}{$$specs{letter_height}};
	my $font_width = $$font_specs{width};
	if ( ! $font_width ) {
		$$specs{alert} .= 'Unable to determine font size.  Please call for pricing.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if


	my $makeReadyPrice = openprint::service::get_price( 'ChannelLettersMakeReady', undef, undef );
	my $minimumCharge = openprint::service::get_price( 'ChannelLettersMinimumCharge', undef, undef );

	my $uppercase_letters = $$specs{letters};
	$uppercase_letters =~ s/[^A-Z]//g;

	my $lowercase_letters= $$specs{letters};
	$lowercase_letters =~ s/[^a-z]//g;

	my $other_letters = $$specs{letters};
	$other_letters =~ s/[^A-Za-z]//g;
	my $num_letters = length( $$specs{letters} );

	$$specs{txtHeight} = $$specs{letter_height};
	$$specs{txtWidth} = $num_letters * $font_width;

	my $CanMaterial = openprint::Material->find_one(name=>join('', 'ChannelLetterCan',@$specs{'letter_font','letter_size'} ) );
	$CanMaterial = openprint::Material->find_one(name=>join('', 'ChannelLetterCan',@$specs{'letter_font'} ) ) if ! $CanMaterial;
	$CanMaterial = openprint::Material->find_one(name=>'ChannelLetterCan' ) if ! $CanMaterial;
	my $FaceMaterial = openprint::Material->find_one(name=>join('', 'ChannelLetterFace',@$specs{'letter_font','letter_size'} ) );
	$FaceMaterial = openprint::Material->find_one(name=>join('', 'ChannelLetterFace',@$specs{'letter_font'} ) ) if ! $FaceMaterial;
	$FaceMaterial = openprint::Material->find_one(name=>'ChannelLetterFace' ) if ! $CanMaterial;


	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"txtQuantity$qty_index"} = int( $$specs{"txtQuantity$qty_index"} );
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
		next if ! $$specs{"txtQuantity$qty_index"};
		$$specs{"Markup$qty_index"} =~ s/[^\d\.\-]//g;
		$$specs{"txtPrice$qty_index"} =~ s/[^\d\.]//g;
		my $price = 0;
		my $unitPrice = 0;
		$$specs{'hdnBreakdown'.$qty_index} = '<fieldset><legend>Letter Pricing</legend><table>';
		$$specs{'hdnBreakdown'.$qty_index}  .= '<tr><td>MakeReady:</td><td class="Price">$' . sprintf( '%.2f', $makeReadyPrice ) . '</td></tr>';
		$$specs{'hdnBreakdown'.$qty_index}  .= '<tr><td>MinimumCharge:</td><td class="Price">$' . sprintf( '%.2f', $minimumCharge ) . '</td></tr>';

		my $qty = $$specs{"txtQuantity$qty_index"};
		my %servicePrice = openprint::service::get_price_object( 'ChannelLetters', $qty, undef );
		if ( sets::isin( $servicePrice{'units'}, ['', 'per m', 'per 1000'] ) ) {
			$servicePrice{'Total'} = $qty * $servicePrice{'Price'} / 1000;
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf( '<tr><td>Service:$%.2f %s =</td><td class="Price">$%.2f</td></tr>', @servicePrice{'Price','units','Total'} );
		} # end if
		$price = $makeReadyPrice + $servicePrice{'Total'};

		if ( $CanMaterial ) {
			my $CanPrice = $CanMaterial->get_Price( $num_letters * $qty );
			if ( $CanPrice ) {
				$$CanPrice{Total} = $$CanPrice{Price} * $num_letters * $qty;
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr><td>Can Price: %1$.2f%2$s * %4$d =</td><td class="Price">$%3$.2f</td></tr>', @$CanPrice{'Price','units','Total'}, $num_letters * $qty );
				$price += $$CanPrice{Total};
			} else {
				$$specs{'hdnBreakdown'.$qty_index} .= '<tr><td colspan="2" class="warning">No price for Cans</td></tr>';
			}
		}
		if ( $FaceMaterial ) {
			my $FacePrice = $FaceMaterial->get_Price( $num_letters * $qty );
			if ( $FacePrice ) {
				$$FacePrice{Total} = $$FacePrice{Price} * $num_letters * $qty;
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr><td>Face Price: $%1$.2f%2$s * %4$d = </td><td class="Price">$%3$.2f</td></tr>', @$FacePrice{'Price','units','Total'}, $num_letters * $qty );
				$price += $$FacePrice{Total};
			} else {
				$$specs{'hdnBreakdown'.$qty_index} .= '<tr><td class="warning" colspan="2">No price for Face</td></tr>';
			}
		}
		$$specs{'hdnBreakdown'.$qty_index} .= '</table></fieldset>';

		if ( $$specs{include_leds} eq 'Y' ) {
$log->debug("Inlcuding leds");
			$$specs{'hdnBreakdown'.$qty_index} .= '<fieldset><legend>LED Pricing</legend><table>';
			my $led_area = Math::Round::nearest(1,$$specs{letter_height} * $font_width * $num_letters ) / 2;
			$$specs{'hdnBreakdown'.$qty_index} .= '<tr><td colspan="2">Number of letters; ' . $num_letters . '</td></tr>';
			$$specs{'hdnBreakdown'.$qty_index} .= '<tr><td colspan="2">Letter area = ' . $font_width . 'x'.$$specs{letter_height} . ' / 2 = ' . $led_area . 'square inches</td></tr>';
			if ( $$specs{led_density} eq 'high' ) {
				$$specs{led_quantity} = POSIX::ceil( $led_area );
			} elsif ( $$specs{led_density} eq 'medium' ) {
				$$specs{led_quantity} = POSIX::ceil( $led_area / 4 );
			} elsif ( $$specs{led_density} eq 'low' ) {
				$$specs{led_quantity} = POSIX::ceil( $led_area / 9 );
			} # end if include_leds
			if ( $LED_Material ) {
				my $Price = $LED_Material->get_Price( $$specs{led_quantity} );
				if ( $$Price{units} eq 'per roll' ) {
					my $length_feet = $LED_Material->Specification('Length');
					if ( $$length_feet{units} eq 'inches' ) {
$openprint::log->debug("adusting to feed" . $length_feet->to_string() );
						$$length_feet{value} *= 12;
						$$length_feet{units} = 'feet';
					}
					my $leds_per_foot = $LED_Material->Specification('leds per foot');
					if ( $$length_feet{value} and $leds_per_foot and $$leds_per_foot{value} ) {
						my $leds_per_roll = $$length_feet{value} * $$leds_per_foot{value};
						$$specs{'hdnBreakdown'.$qty_index} .= '<tr><td>LEDS per roll: ' . $$length_feet{value} .' feet per roll *'. $$leds_per_foot{value} . ' leds per foot ='.$leds_per_roll . ' leds per roll</td></tr>';
						my $rolls = POSIX::ceil( $$specs{led_quantity} / $leds_per_roll );
						$$Price{Total} = $$Price{Price} * $rolls;
						$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr><td>LED Price: $%1$.2f%2$s * %4$d rolls = </td><td class="Price">$%3$.2f</td></tr>', @$Price{'Price','units','Total'}, $rolls );
						$price += $$Price{Total};
					} else {
						$$specs{alert} .= 'Unable to calculate # of Leds<br/>';
					$openprint::log->error("Unable to calculate on LEDS " . $Price->to_string() );
					} # end if
				} elsif ( $$Price{units} eq 'each' ) {
					$$Price{Total} = $$Price{Price} * $$specs{led_quantity};
					$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr><td>LED Price: $%1$.2f%2$s * %4$d rolls = </td><td class="Price">$%3$.2f</td></tr>', @$Price{'Price','units','Total'}, $$specs{led_quantity} );
					$price += $$Price{Total};
				} else {
					$openprint::log->error("Unknown units on LEDS " . $Price->to_string() );
				} # end if
			} # end if
			if ( $$specs{led_power_supply} eq 'Y' ) {
				my $watts = $LED_Material->Specification('Watts');
				if ( $watts and $$watts{value} ) {
					if ( $$watts{units} eq 'per led' ) {
						my $total_watts = $$specs{led_quantity} * $$watts{value};
						$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr><td>Power needed: %dwatts</td></tr>', $total_watts );

						my $best_PS = undef;
						foreach my $PS ( openprint::Material->find( category=>'LED Power Supplies' ) ) {
							my $ps_watts = $PS->Specification('Watts');
							if ( ! ( $ps_watts and $$ps_watts{value} ) ) {
								$openprint::log->error("No watts for " . $PS->to_string() );
								next;
							} 
							my $ps_quantity = POSIX::ceil( $total_watts / $$ps_watts{value} );
							my $PS_Price = $PS->get_Price( $ps_quantity );
							$$PS_Price{Total} = $$PS_Price{Price} * $ps_quantity;
							if ( ( ! defined $best_PS ) or ( $$PS_Price{Total} < $$best_PS{price} ) ) {
								$$best_PS{price} = $PS_Price;
								$$best_PS{PS} = $PS;
								$$best_PS{quantity} = $ps_quantity;
							}
						} # end foraech PS
						if ( $best_PS ) {
							my $PS_Price = $$best_PS{price};
							$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<tr><td>Power Supply:%5$s $%1$.2f%2$s * %4$d = </td><td class="Price">$%3$.2f</td></tr>', @$PS_Price{'Price','units','Total'}, $$best_PS{quantity}, $$best_PS{PS}->name() );
						} else {
							$openprint::log->error("Unable to determine PS");
						}
					} 
				} else {
					$openprint::log->error("Unable to get watts units on LEDS " );
				} 	
			} # end if
			$$specs{'hdnBreakdown'.$qty_index} .= '</table></fieldset>';
		} # end if include_leds

		if ( $minimumCharge > 0 and $price < $minimumCharge ) {
			$price = $minimumCharge;
		} # end if
		$unitPrice = $price / $qty;
		$$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{'UnitPriceFormat'}, $unitPrice * (1+$Project->markup()/100) );
		if ( $$specs{"OverridePrice$qty_index"} ne 'Y' ) {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{'ProjectMoneyFormat'}, $price*(1+$$specs{"Markup$qty_index"}/100)*(1+$Project->markup()/100) );
		} else {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{'ProjectMoneyFormat'}, $$specs{"txtPrice$qty_index"} );
		} # end if
	} # end foreach qty_index

	return $$specs{Status} = $status;
} # end sub calc

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	if ( $qty_index ) {
		return '';
	} # end if

	return '';
} # end sub summary

sub display {
} # end sub display

sub save {
} # end sub save
1;

__END__
