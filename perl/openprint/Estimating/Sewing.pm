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

package openprint::Estimating::Sewing;
use strict;

require openprint::service;

my @variables = (
	'txtPrice1', 'txtPrice2', 'txtPrice3',
	'txtUnitPrice1', 'txtUnitPrice2', 'txtUnitPrice3',
	'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
	'Quantity', 'OverrideQuantity',
	'EdgeLeft','EdgeRight','EdgeTop','EdgeBottom',
	'HemWidth',
);

sub variables {
	my ( $p_id, $s_id, $old_specs, $specs ) = @_;
	return @variables;
} # end sub variables

my @outputs = (
	'hdnBreakdown1', 'hdnBreakdown2', 'hdnBreakdown3',
	'txtPrice1', 'txtPrice2', 'txtPrice3',
	'txtUnitPrice1', 'txtUnitPrice2', 'txtUnitPrice3',
	'Override',
);

sub outputs {
	my ( $p_id, $s_id, $specs ) = @_;
	if ( $$specs{OverrideQuantity} eq 'Y' ) {
		return sets::exclude( ['Quantity'], \@outputs );
	} else {
		return @outputs;
	} # end if
} # end sub get_output

my @no_outputs = (
	'ProjectIndex', 'ServiceIndex', 'txtQuantity1','txtQuantity2','txtQuantity3',
	'ServiceType','Quantity','OverrideQuantity',
);

sub no_outputs {
	my ( $p_id, $s_id, $specs ) = @_;
	if ( $$specs{OverrideQuantity} eq 'Y' ) {
		return @no_outputs;
	} else {
		return sets::exclude( ['Quantity'], \@no_outputs );
	} # end if
} # end sub no_outputs

sub neccessary {
	my ( $Project ) = @_;

    my $services = $Project->services();
    if ( $$services{NoBindery} ) {
        $openprint::log->debug(" ** Project is marked as No bindery, Sews not needed ! ** ");
        return 0;
    } # end if
	if ( $$services{''} ) {
		my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
		if ( $$printing_specs{hemmed} eq 'Y' ) {
			return 1;
		} # end if
		if ( $$printing_specs{pockets} eq 'Y' ) {
			return 1;
		} # end if
	} # end if
	foreach my $sig_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
		if ( $$sig_specs{hemmed} eq 'Y' ) {
			return 1;
		} # end if
		if ( $$sig_specs{pockets} eq 'Y' ) {
			return 1;
		} # end if
	} # end foreach sig

	return 0;
} # end sub neccessary

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

$log->debug("Sewing!!!!!!!!!!!!!!!!!!");

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();
	my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] ) if $$services{''};
	my $sig_specs = openprint::service::get_specs_ref( $Project, $$services{Signature}[0] ) if $$services{Signature};
	if ( ! ( $$specs{EdgeLeft} or $$specs{EdgeRight} or $$specs{EdgeTop} or $$specs{EdgeBottom} ) ) {
		$$specs{EdgeLeft} = 'Left';
		$$specs{EdgeRight} = 'Right';
		$$specs{EdgeTop} = 'Top';
		$$specs{EdgeBottom} = 'Bottom';
	} # end if
	if ( $$specs{OverrideQuantity} ne 'Y' ) {
		$$specs{Quantity} = 0;
		$$specs{Quantity} += $$sig_specs{txtFinalWidth} if $$specs{EdgeTop};
		$$specs{Quantity} += $$sig_specs{txtFinalWidth} if $$specs{EdgeBottom};
		$$specs{Quantity} += $$sig_specs{txtFinalHeight} if $$specs{EdgeLeft};
		$$specs{Quantity} += $$sig_specs{txtFinalHeight} if $$specs{EdgeRight};
	} # end if
	if ( ! $$specs{Quantity} ) {
		$$specs{alert} .= 'Please enter the # of inches to be sewn.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if

	foreach ( outputs( $project_index, $service_index, $specs) ) {
		delete $$specs{$_};
	} # end foreach

	my $makeReadyPrice = openprint::service::get_price( 'SewingMakeReady', undef, undef );
	my $minimumCharge = openprint::service::get_price( 'SewingMinimumCharge', undef, undef );

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"txtQuantity$qty_index"} = int( $$specs{"txtQuantity$qty_index"} );
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};

		my $price = 0;
		my $unitPrice = 0;
		$$specs{'hdnBreakdown'.$qty_index} = '';
		$$specs{'hdnBreakdown'.$qty_index}  .= 'MakeReady: $' . sprintf( '%.2f', $makeReadyPrice ) . '<br/>';
		$$specs{'hdnBreakdown'.$qty_index}  .= 'MinimumCharge: $' . sprintf( '%.2f', $minimumCharge ) . '<br/>';

		my $qty = $$specs{"txtQuantity$qty_index"} * $$specs{Quantity};
		my %servicePrice = openprint::service::get_price_object( 'Sewing', $qty, undef );
		if ( ! %servicePrice ) {
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf( 'No service price.<br/>' );
		} else {
			if ( sets::isin( $servicePrice{units}, ['', 'per m', 'per 1000'] ) ) {
				$servicePrice{Total} = $qty * $servicePrice{Price} / 1000;
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf( 'Service: $%.2f %s = $%.2f<br/>', @servicePrice{'Price','units','Total'} );
			} elsif ( sets::isin( $servicePrice{units}, ['per inch'] ) ) {
				$servicePrice{Total} = $qty * $servicePrice{Price};
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf( 'Service: $%1$.2f%2$s * %4$dinches * %5$d = $%3$.2f<br/>', @servicePrice{'Price','units','Total'}, @$specs{'Quantity','txtQuantity'.$qty_index} );
			} elsif ( sets::isin( $servicePrice{units}, ['per foot'] ) ) {
				$servicePrice{Total} = $qty/12 * $servicePrice{Price};
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf( 'Service: $%1$.2f%2$s * %4$.2ffeet * %5$d = $%3$.2f<br/>', @servicePrice{'Price','units','Total'}, $$specs{Quantity}/12,$$specs{'txtQuantity'.$qty_index} );
			} else {
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf( "unknown units for service price $servicePrice{units}<br/>" );
			} # end if
		} # end if
		$price = $makeReadyPrice + $servicePrice{Total};
		if ( my $Material = openprint::Material->find_one('name'=>'Thread') ) {
			my %materialPrice = $Material->get_price( $qty * $$specs{Quantity}, undef );
			if ( %materialPrice ) {
				$materialPrice{Total} = $materialPrice{Price} * $$specs{Quantity} * $qty;
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf( 'Material: $%.2f %s * %d * %d = $%.2f<br/>', @materialPrice{'Price','units'}, $$specs{txtArea}, $qty, $materialPrice{Total} );
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

	return $$specs{Status} = 'calculated';
} # end sub calc

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	
	if ( $qty_index ) {
		
	} else {
		return $$specs{Quantity} . ' inches ' . join(' ', @$specs{'EdgeTop','EdgeBottom','EdgeLeft','EdgeRight'}).'.';
	} # end if
} # end sub summary

sub save {
	my ( $project_id, $service_id, $specs ) = @_;
	my $Project = new openprint::Project( $project_id );
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	my $services = $Project->services();
	my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] ) if $$services{''} and @{$$services{''}};
	foreach my $spec ( 'EdgeLeft','EdgeRight','EdgeTop','EdgeBottom','HemWidth' ) {
		if ( $$printing_specs{$spec} ne $$specs{$spec} ) {
			openprint::service::insert_service_spec( $openprint::log, $openprint::dbh, $Project->id(), $$services{''}[0], $spec, $$specs{$spec} );
		} # end if
	} # end foreach spec
} # end sub save

1;
__END__
