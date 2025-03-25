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

package openprint::Estimating::NoBindery;

use strict;

my @variables = (
);

sub variables {
	return @variables;
} # end sub variables

my @no_output = (
);

sub no_outputs {
	return @no_output;
}

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	return 'calculated';
} # end sub calc


sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

} # end sub display
sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	return '';

} # end sub summary
sub has_overrides {
}

1;
__END__
