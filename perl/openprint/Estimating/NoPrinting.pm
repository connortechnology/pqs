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

package openprint::Estimating::NoPrinting;

use strict;

require sql;
require openprint::print;
require openprint::service;

my @variables = (
  'txtFinalWidth',
'txtFinalHeight',
  'txtWidth',
'txtHeight',
 'ProjectIndex', 'ServiceIndex', 'ServiceType',
 'chkCyanSideOne','chkMagentaSideOne','chkYellowSideOne','chkBlackSideOne', 'chkProcessColourSideOne',
    ( map { ( "chkColourCoating${_}SideOne", "ColourCoatingType${_}SideOne", "ColourCoatingColour${_}SideOne", "ColourCoatingCoverage${_}SideOne" ) } ( 1 .. 20 ) ),
    ( map { ( "chkColourCoating${_}SideTwo", "ColourCoatingType${_}SideTwo", "ColourCoatingColour${_}SideTwo", "ColourCoatingCoverage${_}SideTwo" ) } ( 1 .. 20 ) ),
    'chkCyanSideTwo','chkMagentaSideTwo','chkYellowSideTwo','chkBlackSideTwo', 'chkProcessColourSideTwo',
    'CyanSpotSideOneCoverage', 'MagentaSpotSideOneCoverage', 'YellowSpotSideOneCoverage', 'BlackSpotSideOneCoverage',
    'CyanSideOneCoverage', 'MagentaSideOneCoverage', 'YellowSideOneCoverage', 'BlackSideOneCoverage',
    'CyanSpotSideTwoCoverage', 'MagentaSpotSideTwoCoverage', 'YellowSpotSideTwoCoverage', 'BlackSpotSideTwoCoverage',
    'CyanSideTwoCoverage', 'MagentaSideTwoCoverage', 'YellowSideTwoCoverage', 'BlackSideTwoCoverage',
'rdbSpecificStock', 'rdbSuppliedStock',
    'ddmStockBrand', 'txtSpecificStockBrand',
    'ddmStockGroup', 'ddmStockQuality',
    'ddmStockFinish', 'txtSpecificStockFinish',
    'ddmStockColour', 'txtSpecificStockColour',
    'ddmStockWeight', 'txtSpecificStockWeight',
    'txtSpecificStockCalliper', 'StockType',
    'txtSpecificStockWidth', 'txtSpecificStockHeight',
'sides_the_same',

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

  $$specs{Status} = 'calculated';
  $$specs{alert} = '';

	return 'calculated';
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
