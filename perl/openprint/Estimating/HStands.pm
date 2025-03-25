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

package openprint::Estimating::HStands;

use strict;

require sql;
require openprint::service;

use constant DEBUG => 1;

my @variables = (
		'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
		'Markup1', 'Markup2', 'Markup3',
		'txtPrice1', 'txtPrice2', 'txtPrice3',
		'hdnBreakdown1', 'hdnBreakdown2', 'hdnBreakdown3',
		'alert','Status',
);

sub variables {
	return @variables;
} # end sub variables

my @no_output = (
	'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
	'ProjectIndex','ServiceIndex','ServiceType',
	'Markup1',	'Markup2',	'Markup3',	
);

sub no_outputs {
	return @no_output;
}

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;
	my $status = 'calculated';

	my $Project = new openprint::Project( $project_index );

	my $HStand_Service = openprint::Service->find_one(name=>'HStands');
	if ( ! $HStand_Service ) {
		if ( DEBUG ) {
			$openprint::log->error("No HStand service found.");
		}
	}
	my $HStand_Material = openprint::Material->find_one(name=>'HStands');
	if ( ! $HStand_Material ) {
		if ( DEBUG ) {
			$openprint::log->error("No HStand material found.");
		}
	}

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"Markup$qty_index"} =~ s/[^\d\.\-]//g;
		$$specs{"txtPrice$qty_index"} =~ s/[^\d\.]//g;
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};

		my $unit_price = 0;
		my $total_price = 0;

		my $ServicePrice;
		if ( $HStand_Service ) {
			$ServicePrice = $HStand_Service->get_Price( $$specs{"txtQuantity$qty_index"} );
			if ( $ServicePrice ) {
				$$ServicePrice{Total} = $$ServicePrice{Price} * $$specs{"txtQuantity$qty_index"};
				$unit_price += $$ServicePrice{Price};
				$total_price += $$ServicePrice{Total};
			}
			$$specs{"hdnBreakdown$qty_index"} .= sprintf('Service: %1$.f%2$s * %4$d = %3$.2f<br/>', @$ServicePrice{'Price','units','Total'}, $$specs{"txtQuantity$qty_index"} );
		} # end if Service
		my $MaterialPrice;
		if ( $HStand_Material ) {
			$MaterialPrice = $HStand_Material->get_Price( $$specs{"txtQuantity$qty_index"} );
			if ( $MaterialPrice ) {
				$$MaterialPrice{Total} = $$MaterialPrice{Price} * $$specs{"txtQuantity$qty_index"};
				$unit_price += $$MaterialPrice{Price};
				$total_price += $$MaterialPrice{Total};
			}
			$$specs{"hdnBreakdown$qty_index"} .= sprintf('Materials: %1$.f%2$s * %4$d = %3$.2f<br/>', @$MaterialPrice{'Price','units','Total'}, $$specs{"txtQuantity$qty_index"} );
			
		} # end if Service

		if ( $$specs{"Markup$qty_index"} ) {
			my $markup = (1+$$specs{"Markup$qty_index"}/100);
			$unit_price *= $markup;
			$total_price *= $markup;
		}

		if ( $Project->markup() ) {
			my $markup = (1+$Project->markup()/100);
			$unit_price *= $markup;
			$total_price *= $markup;
		}

		$$specs{'txtUnitPrice'.$qty_index} = $unit_price;
		if ( $$specs{"OverridePrice$qty_index"} ne 'Y' ) {
			$$specs{'txtPrice'.$qty_index} = sprintf($openprint::config{'ProjectMoneyFormat'}, $total_price );
		} else {
			$$specs{'txtPrice'.$qty_index} = sprintf($openprint::config{'ProjectMoneyFormat'}, $$specs{"txtPrice$qty_index"} );
		} # end if
	
		$$specs{'txtUnitPrice'.$qty_index} = sprintf($openprint::config{'UnitPriceFormat'}, $$specs{'txtUnitPrice'.$qty_index} );
	} # end foreach

	return $status;
} # end sub calc


sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

} # end sub display

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	return '';
} # end sub summary

1;
__END__
