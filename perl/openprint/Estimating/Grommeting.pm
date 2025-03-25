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

package openprint::Estimating::Grommeting;
use strict;

require sql;
require openprint::service;

	#'ServiceType',
	#'rdbGrommetingType',
my @variables = (
	'txtPrice1', 'txtPrice2', 'txtPrice3',
	'txtUnitPrice1', 'txtUnitPrice2', 'txtUnitPrice3',
	'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
	'Quantity',
);

sub variables {
	return @variables;
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
	'ServiceType','Quantity',
);

sub no_outputs {
	return @no_outputs;
};

sub neccessary {
	my ( $Project ) = @_;

    my $services = $Project->services();

    if ( $$services{NoBindery} ) {
        $openprint::log->debug(" ** Project is marked as No bindery, Grommets not needed ! ** ");
        return 0;
    } # end if
	my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] ) if $$services{''};
	if ( $$printing_specs{grommets} ) {
		return 1;
	} # end if

	return 0;
} # end sub neccessary

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $status = 'calculated';

$log->debug("Grommeting!!!!!!!!!!!!!!!!!!");

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();

	foreach ( @outputs ) {
		delete $$specs{$_};
	} # end foreach

	if ( ! $$specs{Quantity} ) {
		if ( $$services{''} ) {
			my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
			$$specs{Quantity} = $$printing_specs{grommets};
			@outputs = sets::union( @outputs, 'Quantity' );
			@no_outputs = sets::exclude( ['Quantity'], \@no_outputs );
		} # end if
	} else {
		@no_outputs = sets::union( @no_outputs, 'Quantity' );
		@outputs = sets::exclude( ['Quantity'], \@outputs );
	} # end if
	if ( (!defined $$specs{Quantity}) or ( $$specs{Quantity} eq '' ) ) {
		$$specs{alert} = 'Please enter the # of grommets per item.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if

	my $makeReadyPrice = openprint::service::get_price( 'GrommetingMakeReady' );
	my $minimumCharge = openprint::service::get_price( 'GrommetingMinimumCharge' );
	my $GrommetingService = openprint::Service->find_one( name=>'Grommeting' );
	my $Material = openprint::Material->find_one( name=>'Grommets');

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"txtQuantity$qty_index"} = int( $$specs{"txtQuantity$qty_index"} );
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};

		my $price = 0;
		my $unitPrice = 0;
		$$specs{'hdnBreakdown'.$qty_index} = '';
		$$specs{'hdnBreakdown'.$qty_index}  .= 'MakeReady: $' . sprintf( '%.2f', $makeReadyPrice ) . '<br/>';
		$$specs{'hdnBreakdown'.$qty_index}  .= 'MinimumCharge: $' . sprintf( '%.2f', $minimumCharge ) . '<br/>';

		my $qty = $$specs{"txtQuantity$qty_index"};
		my %servicePrice = $GrommetingService->get_price( $qty * $$specs{Quantity}, undef ) if $GrommetingService;
		if ( sets::isin( $servicePrice{units}, ['', 'per m', 'per 1000'] ) ) {
			$servicePrice{Total} = $qty * $$specs{Quantity} * $servicePrice{Price} / 1000;
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf( 'Service: $%.2f %s = $%.2f<br/>', @servicePrice{'Price','units','Total'} );
		} # end if
		$price = $makeReadyPrice + $servicePrice{Total};
		if ( $Material ) {
			my %materialPrice = $Material->get_price( $qty * $$specs{Quantity}, undef );
			if ( %materialPrice ) {
				$materialPrice{Total} = $materialPrice{Price} * $$specs{Quantity} * $qty;
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf( 'Material: $%.2f %s * %d grommets * %d = $%.2f<br/>', @materialPrice{'Price','units'}, $$specs{Quantity}, $qty, $materialPrice{Total} );
			} else {
				$$specs{'hdnBreakdown'.$qty_index} .= 'No Material Price.<br/>';
			} # end if
			$price += $materialPrice{Total};
		} else {
			$$specs{'hdnBreakdown'.$qty_index} .= 'No Material.<br/>';
		} # end if

		if ( $minimumCharge > 0 and $price < $minimumCharge ) {
			$price = $minimumCharge;
		} # end if
		$unitPrice = $price / $qty;
		$$specs{"txtUnitPrice$qty_index"} = sprintf( '%.2f', $unitPrice * (1+$Project->markup()/100) );
		$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $price * (1+$Project->markup()/100) );
	} # end foreach

	return $status;
} # end sub calc

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	
	if ( $qty_index ) {
		
	} else {
		return $$specs{Quantity} . ' grommets per item.';
	} # end if
} # end sub summary

sub save {
	my ( $project_id, $service_id, $specs ) = @_;
	my $Project = new openprint::Project( $project_id );
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	my $services = $Project->services();
	my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] ) if $$services{''} and @{$$services{''}};
	if ( $$printing_specs{grommets} != $$specs{Quantity} ) {
		openprint::service::insert_service_spec( $openprint::log, $openprint::dbh, $Project->id(), $$services{''}[0], 'grommets', $$specs{Quantity} );
		foreach my $sig_id ( $Project->signatures() ) {
			openprint::service::insert_service_spec( $openprint::log, $openprint::dbh, $Project->id(), $sig_id, 'grommets', $$specs{Quantity} );
		}
	} # end if
} # end sub save

1;
__END__
