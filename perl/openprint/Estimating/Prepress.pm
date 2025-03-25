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

package openprint::Estimating::Prepress;
use strict;

require openprint::service;
require sql;

my @variables = (
		'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
		'Markup1', 'Markup2', 'Markup3',
        'txtPrice', 'txtPrice1', 'txtPrice2', 'txtPrice3',
        'txtRunTime1', 'txtRunTime2', 'txtRunTime3',
        'txtQuantity',
);

sub variables {
    return @variables;
}

my @no_outputs = (
		'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
		'Markup1', 'Markup2', 'Markup3',
		'ProjectIndex','ServiceIndex','ServiceType',
		'txtQuantity',
);
sub no_outputs {
	return @no_outputs;
}


sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $status = 'calculated';
	my $Project = new openprint::Project( $project_index );
	my $ServiceType = $Project->ServiceType( $service_index );

	if ( $$specs{'txtQuantity'} eq '' ) {	# a zero value is still calculated, just with a zero price.
		$status = 'uncalculated';
	} elsif ( $$specs{'txtQuantity'} < 0.25 and $$specs{'txtQuantity'} > 0 ) {
		$$specs{'txtQuantity'} = 0.25;
	} # end if
	my $price = openprint::service::get_price( $ServiceType->name(), $$specs{'txtQuantity'}, undef );
	$$specs{"txtUnitPrice"} = sprintf( $openprint::config{'UnitPriceFormat'}, $price* (1+$Project->markup()/100) );

	$price *= $$specs{'txtQuantity'};
	$$specs{"txtPrice"} = sprintf( $openprint::config{'ProjectMoneyFormat'}, $price * (1+$Project->markup()/100) );
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"txtUnitPrice$qty_index"} = $$specs{"txtUnitPrice"};
		if ( $$specs{"OverridePrice$qty_index"} ne 'Y' ) {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{'ProjectMoneyFormat'}, $$specs{"txtPrice"} * (1+$$specs{"Markup$qty_index"}/100) );
		} else {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{'ProjectMoneyFormat'}, $$specs{"txtPrice$qty_index"} );
		} # end if
	} # end foreach
	return $$specs{'Status'} = $status;
} # end sub calc

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	if ( $qty_index ) {
	} else {
		if ( $$specs{'ServiceType'} eq 'CDBurning' ) {
			return 1*$$specs{'txtQuantity'}.' cd' . ( $$specs{'txtQuantity'} == 1 ? '' : 's' );
		} elsif ( $$specs{'ServiceType'} eq 'RetrieveFile' ) {
			return 1*$$specs{'txtQuantity'}.' file' . ( $$specs{'txtQuantity'} == 1 ? '' : 's' );
		} else {
			return 1*$$specs{'txtQuantity'}.' hour' . ( $$specs{'txtQuantity'} == 1 ? '' : 's');
		} # end if
	} # end if
	return '';
} # end sub summary

1;
__END__
