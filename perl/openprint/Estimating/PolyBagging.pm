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

package openprint::Estimating::PolyBagging;
use strict;

require openprint::Project;
require openprint::service;

require sql;

my @variables = (
		'txtPrice1', 'txtPrice2', 'txtPrice3',
		'Markup1', 'Markup2', 'Markup3',
		'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
		'Inserts',
);

sub variables {
    return @variables;
}


sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $Project = new openprint::Project( $project_index );

	if ( $$specs{'Inserts'} eq '' ) {
		$$specs{'alert'} .= 'Please specify how many additional items are to be placed in each bag.';
		return $$specs{'Status'} = 'uncalculated';
	} # end if

	my $pockets = 1 + $$specs{'Inserts'};

	my @Equipment = openprint::Equipment->find('strid'=>'PolyBagger');
	if ( ! @Equipment ) {
		$$specs{'alert'} .= 'No PolyBagger in equipment list.';
		return $$specs{'Status'} = 'uncalculated';
	} # end if
	my $Equipment = $Equipment[0];

	my %MRPrice = openprint::service::get_price_object( 'PolyBaggingMakeReady', $pockets );
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		my $qty = $Project->quantity($qty_index) + $Equipment->specification( 'Make Ready Waste', $pockets );
		my $RunWaste = $Equipment->Specification( 'Run Waste', $pockets );
		if ( $$RunWaste{'units'} eq 'Percent' ) {
			$qty += $qty * $$RunWaste{'value'}/100;
		} # end if
		$$specs{'hdnBreakdown'.$qty_index} .= 'Pockets: '. $pockets .'<br/>';
		$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Qty: %d + MR Waste %d + Run Waste %d%s = %d<br/>', 
				$Project->quantity($qty_index), 
				$Equipment->specification( 'Make Ready Waste', $pockets ), 
				@$RunWaste{'value','units'},
				$qty );

		my %Price = openprint::service::get_price_object( 'PolyBagging'.$pockets.'Pocket', $qty );
		if ( ! %Price ) {
			$$specs{'alert'} .= 'No price for PolyBagging'.$pockets.'Pocket.<br/>';
			next;
		} # end if
		if ( $Price{'units'} eq 'per m' ) {
			$Price{'Total'} = $Price{'Price'} * $qty/1000;
			$$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{'UnitPriceFormat'}, $Price{'Price'}/1000 );
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('$%.2fMR + $%.2f%s * %d = $%.2f<br/>', $MRPrice{'Price'}, @Price{'Price','units'}, $qty, $MRPrice{'Price'} + $Price{'Total'} ); 
		} else {
			$$specs{'alert'} .= 'Unknown units ('.$Price{'units'}.') on service price.<br/>';
		} # end if
		if ( $$specs{"OverridePrice$qty_index"} ne 'Y' ) {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{'ProjectMoneyFormat'}, ($MRPrice{'Price'} + $Price{'Total'})*(1+$$specs{"Markup$qty_index"}/100)*(1+$Project->markup()/100) );
		} else {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{'ProjectMoneyFormat'}, $$specs{"txtPrice$qty_index"} );
		} # end if
	} # end foreach
	return $$specs{'Status'} = 'calculated';
} # end sub calc

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	if ( $qty_index ) {
		return '';
	} # end if
	return;
} # end sub summary

1;
__END__
