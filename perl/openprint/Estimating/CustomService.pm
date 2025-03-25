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

package openprint::Estimating::CustomService;

use strict;

require sql;
require openprint::service;

my @variables = (
		'txtPrice1', 'txtPrice2', 'txtPrice3',
		'Price', 'Units',
    'ServiceName',
);

sub variables {
	return @variables;
} # end sub variables

my @no_output = (
	'Hours1', 'Hours2', 'Hours3','Units',
	'ProjectIndex','ServiceIndex','ServiceType',
);

sub no_outputs {
	return @no_output;
}

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;
	my $status = $$specs{Status} = 'calculated';

	my $Project = new openprint::Project( $project_index );

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		my $price;
		if ( lc $$specs{'Units'} eq 'per item' ) {
			$price = $$specs{'Price'.$qty_index} * $Project->quantity($qty_index);
		} elsif ( lc $$specs{'Units'} eq 'per m' ) {
			$price = $$specs{'Price'.$qty_index} * $Project->quantity($qty_index)/1000;
		} else { # Flat
			next;
		} # end if
		$$specs{'txtPrice'.$qty_index} = sprintf($openprint::config{'ProjectMoneyFormat'}, $price );
	} # end foreach

	return $status;
} # end sub calc


sub display {
	#my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

} # end sub display

sub summary {
	#my ( $Project, $service_id, $specs, $qty_index ) = @_;
	#$specs = openprint::service::get_specs_ref( $Project, $service_id );
	#if ( ! $qty_index ) {
		#return $$specs{'ServiceName'};
	#} # end if
	return '';
}
sub has_overrides {
	return ();
}

1;
__END__
