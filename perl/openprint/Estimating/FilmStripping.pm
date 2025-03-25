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

package openprint::Estimating::FilmStripping;

use strict;

require sql;
require openprint::print;
require openprint::service;

my @variables = (
		'OverridePrice1', 'OverridePrice1', 'OverridePrice1',
		'Markup1', 'Markup1', 'Markup1',
        'txtPrice1', 'txtPrice2', 'txtPrice3',
        'txtNegativeQuantity1', 'txtNegativeQuantity3', 'txtNegativeQuantity2',
		'chkOverrideNegativeQuantity',
);

sub variables {
	return @variables;
} # end sub variables

my @no_output = (
	'chkOverrideNegativeQuantity',
	'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
		'OverridePrice1', 'OverridePrice1', 'OverridePrice1',
		'Markup1', 'Markup1', 'Markup1',
	'ProjectIndex','ServiceIndex','ServiceType',
);

sub no_outputs {
	return @no_output;
}

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;
	my $status = 'calculated';

	my $Project = new openprint::Project( $project_index );

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"Markup$qty_index"} =~ s/[^\d\.\-]//g;
		$$specs{"txtPrice$qty_index"} =~ s/[^\d\.]//g;
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
		next if ! $$specs{'txtQuantity'.$qty_index};
		if ( $$specs{'chkOverrideNegativeQuantity'.$qty_index} ne 'Y' ) {
			@no_output = sets::exclude( ['txtNegativeQuantity'.$qty_index], \@no_output );
			$$specs{'txtNegativeQuantity'.$qty_index} = 0;
			foreach my $service_index ( $Project->signatures() ) {
				( $_ ) = openprint::service::get_specifications( $log, $dbh, $project_index, $service_index, 'txtPlateQuantity'.$qty_index);
				$$specs{'txtNegativeQuantity'.$qty_index} += $_;
			} # end foreach
			if ( ! $$specs{'txtNegativeQuantity'.$qty_index} ) {
				$$specs{'alert'} .= "No plates found for quantity $qty_index<br/>";
				$status = 'uncalculated';
			} # end if
		} else {
			@no_output = sets::union( 'txtNegativeQuantity'.$qty_index, @no_output );
		} # end if
		my $service_price = openprint::service::get_price( 'FilmStripping', $$specs{'txtNegativeQuantity'.$qty_index}, undef );
		$$specs{'txtUnitPrice'.$qty_index} = sprintf($openprint::config{'UnitPriceFormat'}, $service_price * (1+$Project->markup()/100) );
		if ( $$specs{"OverridePrice$qty_index"} ne 'Y' ) {
			$$specs{'txtPrice'.$qty_index} = sprintf($openprint::config{'ProjectMoneyFormat'}, ($service_price * $$specs{'txtNegativeQuantity'.$qty_index})*(1+$$specs{"Markup$qty_index"}/100) * (1+$Project->markup()/100) );
		} else {
			$$specs{'txtPrice'.$qty_index} = sprintf($openprint::config{'ProjectMoneyFormat'}, $$specs{"txtPrice$qty_index"} );
		} # end if
	} # end foreach

	return $status;
} # end sub calc

sub summary {
	return '';
}

1;
__END__
