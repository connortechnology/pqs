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

package openprint::Estimating::Mounting;
use POSIX qw{ ceil };
use strict;

require openprint::service;

require sql;

my @variables = (
	'txtFinalWidth','txtFinalHeight','chkOverrideDimensions',
	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
	'Markup1', 'Markup2', 'Markup3',
	'txtPrice1', 'txtPrice2', 'txtPrice3',
	'txtUnitPrice1', 'txtUnitPrice2', 'txtUnitPrice3',
	#'ddmEquipment1', 'ddmEquipment2', 'ddmEquipment3',
	'MountingType',
);

sub variables {
	return @variables;
} # end sub variables

my @outputs = (
	'txtFinalWidth','txtFinalHeight',
	'txtPrice1', 'txtPrice2', 'txtPrice3',
	'txtUnitPrice1', 'txtUnitPrice2', 'txtUnitPrice3',
	#'ddmEquipment1', 'ddmEquipment2', 'ddmEquipment3',
	'alert',
	'Status',
	'hdnBreakdown1', 'hdnBreakdown2', 'hdnBreakdown3',
);

sub outputs {
	return @outputs;
} # end sub outputs

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $Project = new openprint::Project( $project_index );
	my %services = $Project->get_services();
	if ( ! $services{''} ) {
		$$specs{'alert'} .= 'No Project Service!<br/>';
		return $$specs{'Status'} = 'uncalculated';
	} # end if

	my $printing_specs = openprint::service::get_specs_ref( $project_index, $services{''}[0] );
	if ( $$specs{'chkOverrideDimensions'} ne 'Y' ) {
		@$specs{'txtFinalWidth','txtFinalHeight'} = @$printing_specs{'txtFinalWidth','txtFinalHeight'};
	} # end if

	if ( ! 
			( $$specs{'MountingType'} and $$specs{'txtFinalWidth'} and $$specs{'txtFinalHeight'} )
	   ) {
		$$specs{'txtPrice1'} = '';
		$$specs{'txtPrice2'} = '';
		$$specs{'txtPrice3'} = '';
		$$specs{'txtUnitPrice1'} = '';
		$$specs{'txtUnitPrice2'} = '';
		$$specs{'txtUnitPrice3'} = '';
		return $$specs{'Status'} = 'uncalculated';
	} # end if

	my %MinimumCharge = openprint::service::get_price_object( $$specs{'ServiceType'}.'MinimumCharge', undef, undef );
	my %MaterialPrice;
	if ( my $Material = openprint::Material->find_one('name'=>$$specs{'MountingType'}) ) {
		%MaterialPrice = $Material->get_price( undef, undef );
	} # end if

	# So we can do multiple items at once, as many as will fit in the wiwdth of the laminator.  We need a certain amount of space between the items.  I suspect that this should be an input, not a fixed value, but for now we will make it fixed.
	my $item_width = $$specs{'txtFinalWidth'};
	my $item_height = $$specs{'txtFinalHeight'};

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
		my $qty = int $$specs{"txtQuantity$qty_index"};
		next if ! $qty;

		my %bestPrice;

		my %ServicePrice = openprint::service::get_price_object( $$specs{'ServiceType'}, undef, undef );
		my %SetupPrice = openprint::service::get_price_object( $$specs{'ServiceType'}.'MakeReady', undef, undef );

		my $price = $SetupPrice{'Price'};
		$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Setup: $ %.2f<br/>', $SetupPrice{'Price'});
		if ( $ServicePrice{'units'} eq 'per m' ) {
			my $serviceprice = ($ServicePrice{Price} * $qty)/1000;
			$price += $serviceprice;
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service: $ %.2f %s * %f = $ %.2f<br/>', @ServicePrice{'Price','units'}, $qty, $serviceprice );
		} # end if
		if ( $MaterialPrice{'units'} eq 'per square foot' ) {
			my $area = $$specs{'txtFinalWidth'} * $$specs{'txtFinalHeight'};

# have to reload price to get one with quantity discounts
			if ( my $Material = openprint::Material->find_one('name'=>$$specs{'MountingType'}) ) {
				%MaterialPrice = $Material->get_price( $area, undef );
			} # end if
			my $materialprice = $MaterialPrice{Price} * $area;
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf("\tMaterial: \$ %.2f \%s * \%.2f square feet = \$ %.2f\n", @MaterialPrice{'Price','units'}, $area, $materialprice );
			$price += $materialprice;
		} else {
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf("\tMaterial: unknown units: \%s\n", $MaterialPrice{'units'} );
		} # end if
		if ( ( ! $bestPrice{'Price'} ) or $bestPrice{'Price'} > $price ) {
			$bestPrice{'Price'} = $price;
		} # end if
		$bestPrice{'Price'} = $MinimumCharge{Price} if $bestPrice{'Price'} < $MinimumCharge{Price};

		if ( $$specs{"OverridePrice$qty_index"} ne 'Y' ) {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{'ProjectMoneyFormat'}, 
					$bestPrice{'Price'}*(1+$$specs{"Markup$qty_index"}/100) * (1+$Project->markup()/100) );
		} else {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{'ProjectMoneyFormat'}, $$specs{"txtPrice$qty_index"} );
		} # end if
		$$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{'UnitPriceFormat'}, ( $bestPrice{'Price'}/$qty ) * (1+$Project->markup()/100) );
	} # end foreach qty_index
	return $$specs{'Status'} = 'calculated';
} # end sub calc

1;
__END__
