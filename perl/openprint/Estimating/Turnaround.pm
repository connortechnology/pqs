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

package openprint::Estimating::Turnaround;
use strict;

require openprint::service;

require sql;
require misc;

my @variables = (
		'txtPrice1',
        'txtPrice2',
        'txtPrice3',
		'TurnaroundDays',
);

sub variables {
    return @variables;
}


sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $Project = new openprint::Project( $project_index );
	my $ProjectType = $Project->Type();

	if ( $$specs{TurnaroundDays} eq '' ) {
		$$specs{alert} = 'Please select the turnaround time.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if

	my ( $min, $max ) = split('-', $$specs{TurnaroundDays} );
$log->debug("Min: $min Max: $max");

$log->debug("Looking up basic pricing for $min for " . $ProjectType->name() );
	my %Price = openprint::service::get_price_object( 'Turnaround'.$ProjectType->name(), $min );
	if ( ! %Price ) {
$log->debug("Looking up basic pricing for $min");
		%Price = openprint::service::get_price_object( 'Turnaround', $min );
	} # end if
	
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		if ( $Price{units} eq 'percent' ) {
			my ( $price ) = misc::sum( sql::execute( $log, $dbh, qq{SELECT strValue FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex != ? and strName='txtPrice$qty_index'}, $project_index, $service_index ) );
			$$specs{"txtPrice$qty_index"} = $price * $Price{Price}/100;
$log->debug("Price: $price * $Price{Price}/100 = " . $$specs{"txtPrice$qty_index"} );
		} else {
			$$specs{"txtPrice$qty_index"} = $Price{Price};
		} # end if
		$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"} );
	} # end foreach
	return $$specs{Status} = 'calculated';
} # end sub calc_prepress
sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	if ( $qty_index ) {
		return '';
	} # end if
	return sprintf('%s day%s.',$$specs{TurnaroundDays}, $$specs{TurnaroundDays} == 1 ? '' : 's' );
} # end sub summary
sub project_summary {
	my ( $Project, $service_id, $specs ) = @_;
	return sprintf(' in %s day%s.',$$specs{TurnaroundDays}, $$specs{TurnaroundDays} == 1 ? '' : 's' );
} # end sub project_summary

sub save {
} # end sub save
sub has_overrides {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	return;
}
1;
__END__
