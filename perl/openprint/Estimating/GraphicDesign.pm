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

package openprint::Estimating::GraphicDesign;
use strict;

require openprint::service;
require sql;

my @variables = (
    'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
    'Markup1', 'Markup2', 'Markup3',
    'txtPrice', 'txtPrice1', 'txtPrice2', 'txtPrice3',
    'txtRunTime1', 'txtRunTime2', 'txtRunTime3',
    'GraphicDesign', 'Override_GraphicDesign',
    'Logos', 'Illustrations', 'ProductPhotos', 'CopyWriting',
);

sub variables {
    return @variables;
}

my @no_outputs = (
		'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
		'Markup1', 'Markup2', 'Markup3',
		'ProjectIndex','ServiceIndex','ServiceType',
		'GraphicDesign',
);
sub no_outputs {
	return @no_outputs;
}

# Determine the default graphic design hours for the project.
sub get_design_hours {
  my ($Project) = @_;

  my $services = $Project->services();
  my $type = $Project->Type();

  my @signatures = $Project->signatures();

  my ($width, $height, $template, @side_two, $pages);
  if ($type->type() ne 'SinglePage') {
    my $printing_specs = openprint::service::get_specs_ref($Project, $$services{''}[0]) if $$services{''};
    ($width, $height, $template) = @$printing_specs{'txtWidth','txtHeight','rdbTemplateType'};
#detects a second side by looking for either the two sides being linked or a colour for the second side
    @side_two = openprint::Estimating::Printing::get_colours($printing_specs, 'SideTwo');
    $pages = $$printing_specs{txtTotalPageQuantity};
  } else {
    my $sig_specs = openprint::service::get_specs_ref($Project, $signatures[0]);
    ($width, $height, $template) = @$sig_specs{'txtWidth','txtHeight','rdbTemplateType'};
#detects a second side by looking for either the two sides being linked or a colour for the second side
    @side_two = openprint::Estimating::Printing::get_colours($sig_specs, 'SideTwo');
    $pages = @signatures;
  }

  my $sided = @side_two ? 'Double' : 'Single';

  my ($hours) = sql::execute($openprint::log, $openprint::dbh, "
      SELECT dblDesignHours${sided}Side 
      FROM ProjectTemplate 
      WHERE strprojecttype=? AND type=? AND dblFlatWidth=? AND dblFlatHeight=?",
      $type->name(), $template, $width, $height);
  $openprint::log->debug("GET DESIGN HOURS: $sided, $template -- $width x $height = $hours | @side_two ");

# If we don't have design hours for that particular template, try
# using the custom template.
  if (!$hours || $hours <= 0) {
# Hours per square inch.
    ($hours) = sql::execute($openprint::log, $openprint::dbh, "SELECT dblDesignHours${sided}Side 
        FROM ProjectTemplate
        WHERE strprojecttype = ? AND type='Custom'
        ", $type->name());
    return undef unless $hours;

    $hours *= $width * $height;
  }
# divide by 2 because the flat dimesions = 2 Pages. TODO Is this correct?
  $hours *= $pages / 2 if $pages > 1;
  return $hours;
}

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $status = 'calculated';
	my $Project = new openprint::Project( $project_index );
	my $ServiceType = $Project->ServiceType( $service_index );

  # Enter in hours on the first pass through.
  $$specs{GraphicDesign} = get_design_hours($Project) unless $specs->{Override_GraphicDesign};

	if ( $$specs{'GraphicDesign'} eq '' ) {	# a zero value is still calculated, just with a zero price.
		$status = 'uncalculated';
	} elsif ( $$specs{'GraphicDesign'} < 0.25 and $$specs{'GraphicDesign'} > 0 ) {
		$$specs{'GraphicDesign'} = 0.25;
	} # end if
	my $price = openprint::service::get_price( $ServiceType->name(), $$specs{'GraphicDesign'}, undef );
	$$specs{"txtUnitPrice"} = sprintf( $openprint::config{'UnitPriceFormat'}, $price* (1+$Project->markup()/100) );

	$price *= $$specs{'GraphicDesign'};
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

sub display {
  my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;
  my $Project = new openprint::Project( $project_index );

  $$variable{Default_GraphicDesign} = get_design_hours($Project);
}

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	if ( $qty_index ) {
	} else {
		if ( $$specs{'ServiceType'} eq 'CDBurning' ) {
			return 1*$$specs{'GraphicDesign'}.' cd' . ( $$specs{'GraphicDesign'} == 1 ? '' : 's' );
		} elsif ( $$specs{'ServiceType'} eq 'RetrieveFile' ) {
			return 1*$$specs{'GraphicDesign'}.' file' . ( $$specs{'GraphicDesign'} == 1 ? '' : 's' );
		} else {
			return 1*$$specs{'GraphicDesign'}.' hour' . ( $$specs{'GraphicDesign'} == 1 ? '' : 's');
		} # end if
	} # end if
	return '';
} # end sub summary

1;
__END__
