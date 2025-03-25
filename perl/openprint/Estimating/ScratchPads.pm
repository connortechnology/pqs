# Copyright (C) 2007 Isaac Connor <isaac@connortechnology.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA	02110-1301, USA

use strict;
package openprint::Estimating::ScratchPads;

use POSIX qw{ ceil };
use openprint ();
use vars qw( $r %variable $log $dbh %config );
*variable = \%openprint::variable;
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;

require openprint::Estimating::Printing;
require openprint::service;
require sets;

use constant DEBUG => 1;

my %variables = (
	'ddmProjectSize'=>['save','output'],
	'txtFinalWidth'=>['save'],'txtFinalHeight'=>['save'], 
	'txtWidth'=>['save','output'],'txtHeight'=>['save','output'],
	'PageQuantity'=>['save'], 
	'Backing'=>['save','output'],
	'txtSpreadSize'=>['save','output'],'PrintingType'=>['save'],'rdbTemplateType'=>['save'],
	'help'=>['output'],'alert'=>['output', 'save'],
	'ProjectIndex'=>[], 'ServiceIndex'=>[], 'ServiceType'=>[],
	'remaining_pages'=>['output'],'next_group_id'=>['output'],
);
my @signature_variables = (
    'chkCyanSideOne','chkMagentaSideOne','chkYellowSideOne','chkBlackSideOne', 'chkProcessColourSideOne',
    'chkColourCoating1SideOne', 'ColourCoatingType1SideOne', 'ColourCoatingColour1SideOne','ColourCoatingCoverage1SideOne',
    'chkColourCoating2SideOne', 'ColourCoatingType2SideOne', 'ColourCoatingColour2SideOne','ColourCoatingCoverage2SideOne',
    'chkColourCoating3SideOne', 'ColourCoatingType3SideOne', 'ColourCoatingColour3SideOne','ColourCoatingCoverage3SideOne',
    'chkColourCoating4SideOne', 'ColourCoatingType4SideOne', 'ColourCoatingColour4SideOne','ColourCoatingCoverage4SideOne',
    'chkColourCoating5SideOne', 'ColourCoatingType5SideOne', 'ColourCoatingColour5SideOne','ColourCoatingCoverage5SideOne',
    'chkColourCoating6SideOne', 'ColourCoatingType6SideOne', 'ColourCoatingColour6SideOne','ColourCoatingCoverage6SideOne',
    'chkColourCoating7SideOne', 'ColourCoatingType7SideOne', 'ColourCoatingColour7SideOne','ColourCoatingCoverage7SideOne',
    'chkColourCoating8SideOne', 'ColourCoatingType8SideOne', 'ColourCoatingColour8SideOne','ColourCoatingCoverage8SideOne',
    'chkColourCoating9SideOne', 'ColourCoatingType9SideOne', 'ColourCoatingColour9SideOne','ColourCoatingCoverage9SideOne',
    'chkCyanSideTwo','chkMagentaSideTwo','chkYellowSideTwo','chkBlackSideTwo', 'chkProcessColourSideTwo',
    'chkColourCoating1SideTwo', 'ColourCoatingType1SideTwo', 'ColourCoatingColour1SideTwo','ColourCoatingCoverage1SideTwo',
    'chkColourCoating2SideTwo', 'ColourCoatingType2SideTwo', 'ColourCoatingColour2SideTwo','ColourCoatingCoverage2SideTwo',
    'chkColourCoating3SideTwo', 'ColourCoatingType3SideTwo', 'ColourCoatingColour3SideTwo','ColourCoatingCoverage3SideTwo',
    'chkColourCoating4SideTwo', 'ColourCoatingType4SideTwo', 'ColourCoatingColour4SideTwo','ColourCoatingCoverage4SideTwo',
    'chkColourCoating5SideTwo', 'ColourCoatingType5SideTwo', 'ColourCoatingColour5SideTwo','ColourCoatingCoverage5SideTwo',
    'chkColourCoating6SideTwo', 'ColourCoatingType6SideTwo', 'ColourCoatingColour6SideTwo','ColourCoatingCoverage6SideTwo',
    'chkColourCoating7SideTwo', 'ColourCoatingType7SideTwo', 'ColourCoatingColour7SideTwo','ColourCoatingCoverage7SideTwo',
    'chkColourCoating8SideTwo', 'ColourCoatingType8SideTwo', 'ColourCoatingColour8SideTwo','ColourCoatingCoverage8SideTwo',
    'chkColourCoating9SideTwo', 'ColourCoatingType9SideTwo', 'ColourCoatingColour9SideTwo','ColourCoatingCoverage9SideTwo',
    'CyanSpotSideOneCoverage', 'MagentaSpotSideOneCoverage', 'YellowSpotSideOneCoverage', 'BlackSpotSideOneCoverage',
    'CyanSideOneCoverage', 'MagentaSideOneCoverage', 'YellowSideOneCoverage', 'BlackSideOneCoverage',
    'CyanSpotSideTwoCoverage', 'MagentaSpotSideTwoCoverage', 'YellowSpotSideTwoCoverage', 'BlackSpotSideTwoCoverage',
    'CyanSideTwoCoverage', 'MagentaSideTwoCoverage', 'YellowSideTwoCoverage', 'BlackSideTwoCoverage',
    'BleedLeft','BleedRight','BleedTop','BleedBottom','rdbColourBar','txtCropMarkSpace','OverrideAddGrip',
		'ddmRunStyle-', 'ddmPress-', 'PrintingType-', 'StockType-', 'txtPlateChangeQuantity-', 'PageQuantity-',
		'Pages', 'OverrideGroupPageQuantity', 'GroupPageQuantity', 'txtSignatureType',
		'chkOverrideDimensions', 'txtFinalHeight', 'txtFinalWidth', 'txtHeight', 'txtWidth',
		'rdbSpecificStock', 'rdbSuppliedStock',
		'ddmStockBrand', 'txtSpecificStockBrand',
		'ddmStockGroup', 'ddmStockQuality',
		'ddmStockFinish', 'txtSpecificStockFinish',
		'ddmStockColour', 'txtSpecificStockColour',
		'ddmStockWeight', 'txtSpecificStockWeight',
		'txtSpecificStockCalliper', 'StockType',
		'txtSpecificStockWidth', 'txtSpecificStockHeight', 
		'txtCustomMWeight', 'basis_mweight', 'basis_width', 'basis_height', 
		'CustomStockPrice', 'StockPricePerM', 'txtStockGSM','CustomSheetDoubleSided',
		'cuttable', 'perfecting', 'StockGrade', 'minimum_order','sheets_per_package','full_packages',
		'sides_the_same','rdbPressProof','PressApproval',
		);

sub variables {
	my ( $project_id, $service_id, $specs, $incoming_specs ) = @_;
	my @v;
	foreach my $k ( keys %variables ) {
		push @v, $k if sets::isin( 'save', $variables{$k} );
	} # end foreach;
	foreach my $group_id ( groups( $project_id, $incoming_specs ) ) {
		push @v, map { join('', $_,$group_id) } @signature_variables;
	} # end foreach group
	return @v;
} # end sub variables

sub no_outputs {
	my ( $project_id, $service_index, $specs ) = @_;

	my @v;
	foreach my $k ( keys %variables ) {
		push @v, $k, if ! sets::isin( 'output', $variables{$k} );
	} # end foreach;
	#my @no_outputs = openprint::Estimating::Printing::no_outputs( $project_id, $service_index, $specs );
	#foreach my $Group ( groups( $project_id, $specs ) ) {
		## Will come with signature appended
		#push @v, sets::exclude( \@outputs, map { \@no_outputs );
	#} # end foreach Group

	return @v;
} # end sub no_outputs


sub outputs {
	my ( $project_id, $service_index, $specs ) = @_;

	my @v;
	foreach my $k ( keys %variables ) {
		push @v, $k, if sets::isin( 'output', $variables{$k} );
	} # end foreach;

	foreach my $group_id ( groups( $project_id, $specs ) ) {
if ( 0 ) {
		my @outputs = sort { $a cmp $b } openprint::Estimating::Printing::outputs( $project_id, $service_index, $specs, $group_id );
$openprint::log->debug("Outputs for group $group_id @outputs");
		push @v, map { $_.$group_id } @outputs;
}
		if ( ! $$specs{"chkOverrideDimensions$group_id"} ) {
			push @v, map { $_.$group_id } ( 'txtFinalWidth','txtFinalHeight' );
		}
	} # end foreach Group
$openprint::log->debug("Outputs for @v");

	return @v;
} # end sub outputs

sub groups {
	my ( $project_id, $specs ) = @_;
	my @Groups = sql::execute( undef, undef, 'SELECT DISTINCT strvalue FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND strName=?', $project_id, 'Group' );
	if ( ! grep { $_ == 1 } @Groups ) {
		if ( $$specs{Backing} eq 'Printed' ) {
			push @Groups, 1;
		}
	} elsif  ( $$specs{Backing} ne 'Printed' ) {
		@Groups = sets::exclude( [ 1 ], \@Groups );
	} # end if
	if ( ! sets::isin( 2, \@Groups ) ) {
		push @Groups, 2;
	} # end if
	return @Groups;
} # end sub groups


sub calc {
	my ( undef, undef, undef, $project_id, $service_index, $specs ) = @_;

  $$specs{alert} = '';
	my @Groups = groups( $project_id, $specs );

	my $Project = new openprint::Project( $project_id );
	my $remaining_pages = $$specs{PageQuantity};
	my %override_pages;

	foreach my $group_id ( @Groups ) {
#$openprint::log->debug("Group: $group_id, remaining: $remaining_pages, $override_pages{$group_id}");
		next if $override_pages{$group_id};

		if ( exists $$specs{'OverrideGroupPageQuantity'.$group_id} and $$specs{'OverrideGroupPageQuantity'.$group_id} eq 'Y' ) {
			if ( ! $$specs{'GroupPageQuantity'.$group_id} ) {
# We still set override so that it doesn't auto-fill    
				$$specs{alert} .= 'You have overriden the # of pages in group ' . $$specs{"txtSignatureType$group_id"} . ' but not entered the # of pages.<br/>';
				$$specs{Status} = 'uncalculated';
				$$specs{'GroupPageQuantity'.$group_id.'_container'} = { addClassName=>'error' };
			} else {
				$$specs{'GroupPageQuantity'.$group_id.'_container'} = { removeClassName=>'error' };
			}
			$override_pages{$group_id} = $$specs{'GroupPageQuantity'.$group_id};
			$log->debug("Setting override pages for group $group_id to " . $$specs{'GroupPageQuantity'.$group_id} );
		} else {
			$$specs{'GroupPageQuantity'.$group_id.'_container'} = { removeClassName=>'error' };
		} # end if override
		$remaining_pages -= $override_pages{$group_id};
	} # end foreach group
	$openprint::log->debug("Remaining pages $remaining_pages") if DEBUG;

# if there is a Backing, then force it to be non-zero, not sure this is right... will end up with a 49pg pads...
# But we need something or else the backing will take over.
	if ( (! $override_pages{1} ) and ($$specs{OverrideGroupPageQuantity1} ne 'Y' ) and ($$specs{Backing} eq 'Printed') ) {
		$override_pages{1} = 1;
		$remaining_pages -= $override_pages{1};
	} # end if

	foreach my $group_id ( @Groups ) {
		my %sig_specs =	map { $$specs{$_.$group_id} ? ( $_=>$$specs{$_.$group_id } ) : () } @signature_variables;
		my %v = %openprint::Estimating::Printing::variables;
	#FIXME, outputs needs to be initt'd
#$openprint::log->debug("Group: $group_id, remaining: $remaining_pages, $override_pages{$group_id}");
		openprint::Estimating::Printing::get_inkcoverage( $Project, \%sig_specs, \%v );
		openprint::Estimating::Printing::get_colours( \%sig_specs, 'SideOne', \%v );
		openprint::Estimating::Printing::get_colours( \%sig_specs, 'SideTwo', \%v );
		openprint::Estimating::Printing::get_Stocks( $Project, \%sig_specs, \%v );
		openprint::Estimating::Printing::set_size( $Project, \%sig_specs, $specs );

		foreach ( @signature_variables ) {
			next if ! $sig_specs{$_};
			if ( $sig_specs{$_} ne $$specs{ $_.$group_id} ) {
				$$specs{$_.$group_id} = $sig_specs{$_};
				$variables{$_.$group_id} = [] if ! $variables{$_.$group_id};
				push @{$variables{$_.$group_id}}, 'output';
			}
		}

		if ( $$specs{"ddmRunStyle-$group_id"} and $$specs{"ddmPress-$group_id"} ) {
			my $Press = openprint::Equipment->find_one(strid=>$$specs{"ddmPress-$group_id"});
			if ( ! sets::isin( $$specs{"ddmRunStyle-$group_id"}, [ split(',', $Press->specification('Runstyles') ) ] ) ) {
				$$specs{alert} .= "Press $$Press{name} cannot do " . $$specs{"ddmRunStyle-$group_id"}.'<br/>';
			}
		}
    $sig_specs{alert} =~ s/<br\/>$//;
		$$specs{alert} .= $sig_specs{alert} .' for group ' . $group_id . ' ' . $$specs{'txtServiceDescription'.$group_id}. '<br/>' if $sig_specs{alert};

		if ( ! exists $override_pages{$group_id} ) {
			$override_pages{$group_id} = $remaining_pages;
			$remaining_pages = 0;
		} # end if
		$$specs{'GroupPageQuantity'.$group_id} = $override_pages{$group_id};

		if ( 0 and $$specs{'chkOverrideDimensions'.$group_id} ne 'Y' ) {
			# Is this necessary?  I don't think so.
			$$specs{'txtFinalWidth'.$group_id} = $$specs{txtFinalWidth};
			$$specs{'txtFinalHeight'.$group_id} = $$specs{txtFinalHeight};
		} # end if
	} # end foreach group_id

	if ( ! ( $$specs{txtFinalWidth} or $$specs{txtFinalHeight} ) ) {
		$$specs{help} = 'Please select the dimensions.';
		return 'uncalculated';
	} # end if
	$$specs{txtHeight} = $$specs{txtFinalHeight};
	$$specs{txtWidth} = $$specs{txtFinalWidth};

	if ( $$specs{remaining_pages} = $remaining_pages ) {
		my $max_group = 0;
		foreach my $g_id ( @Groups ) {
			if ( $g_id > $max_group ) {
				$max_group = $g_id;
			} # end if
		} # end foreach g_id
		$$specs{next_group_id} = $max_group + 1;
	} else {
		$$specs{next_group_id} = '';
	} # end if

	if ( ( $$specs{txtWidth} < $$specs{txtFinalWidth} ) or ( $$specs{txtHeight} < $$specs{txtFinalHeight} ) ) {
		$$specs{alert} .= 'Flat size cannot be smaller than finished size!';
		return 'uncalculated';
	} # end if

	if ( ! $$specs{PageQuantity} ) {
		$$specs{help} = 'Please enter the # of pages';
		return 'uncalculated';
	} # end if

	if ( ! $$specs{Backing} ) {
		$$specs{help} = 'Please select the backing type.';
		return 'uncalculated';
	} # end if

	return 'calculated';
} # end sub calc

# Returns the # of needed remaining spreads... 
sub status {
	my ( $project_id, $printing_specs, $qty_index ) = @_;

	my $Project = new openprint::Project( $project_id );
	my $services = $Project->services();
	if ( ! $printing_specs ) {
		$printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
		return if ! $printing_specs;
	} # end if

	my $total_pages = $$printing_specs{PageQuantity};
	my %specified_pages;
	my %needed_pages;
	foreach my $ssid ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ssid );
		$specified_pages{$$sig_specs{Group}} += $$sig_specs{"PageQuantity$qty_index"};
		$needed_pages{$$sig_specs{Group}} = $$sig_specs{'GroupPageQuantity'.$qty_index};
	} # end foreach
	my @Groups = sql::execute( undef, undef, 'SELECT DISTINCT strvalue FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND strName=?', $project_id, 'Group' );
	foreach my $Group ( @Groups ) {
		if ( $needed_pages{$Group} > $specified_pages{$Group} ) {
			return $Group;
		} # end if
	} # end foreach
	return;
} # end sub status

sub save {
	my ( $p_id, $s_id, $param ) = @_;
	my $Project = new openprint::Project( $p_id );
	my $Service = $Project->Service( $s_id );
	my $specs = $Service->specs();

	my %needed_pages;
	$needed_pages{'Backing Pages'} = $$param{OverrideGroupPageQuantity1} eq 'Y' ? $$param{GroupPageQuantity1} : ($$param{Backing} eq 'Printed' ? 1 : 0);
	$needed_pages{'Interior Pages'} = ( $$param{PageQuantity} - $needed_pages{'Backing Pages'} );

	my %specified_pages;
	my $max_group;

if ( 0 ) {
	foreach my $k ( keys %$param ) {
		if ( $k =~ /txtSignatureType(\d*)/ ) {
			my $group_id = $1;

			if ( $$param{'GroupPageQuantity'.$group_id} and ! $Project->signatures({Group=>$group_id}) ) {
				$Project->add_signature( undef, 'uncalculated', {
						( $group_id ? (
										txtSignatureType			=> 'Backing Pages',
										txtServiceDescription	=> 'Backing',
										) : (
											txtSignatureType	=> 'Pad Pages',
											txtServiceDescription	=> 'Pad Pages',
											) ),
						Group			=> $group_id,
						PrintingType	=> $$param{PrintingType},
						txtSpreadSize	=> 1,
						} );
			} # end if

			$specified_pages{$$param{$k}} += $$param{'GroupPageQuantity'.$group_id};
			if ( $group_id > $max_group ) {
				$max_group = $group_id;
			} # end if
		} # end if
	} # end foreach param
}

	if ( $$param{Backing} eq 'Printed' ) {
# now add a cover spread if we need one.
# First, see if we have one.
		if ( ! $Project->signatures({type=>'Backing Pages'}) ) {
$log->debug("Adding backing pages");
			my $cover_index = $Project->add_signature( undef, 'uncalculated', {
					txtSignatureType	=> 'Backing Pages',
					txtServiceDescription	=> 'Backing',
					Group	=> 1,
# Used to give each signature a # for reference in proofs, etc.
					PrintingType		=> $$param{PrintingType},
					txtSpreadSize		=> 1,
					} );
# Width and Height will be added on auto-calc
		} # end if

# Prime this for saving later
		if ( ( ! $$param{GroupPageQuantity1} ) and ( $$param{OverrideGroupPageQuantity1} ne 'Y' ) ) {
			$$param{GroupPageQuantity1} = $needed_pages{'Backing Pages'};
		} # end if
	} else {
# Don't need a cover, so get rid of it
		foreach ( $Project->signatures({ type=>'Backing Pages'}) ) {
			openprint::print_project::delete_service( $Project, $_ );
		} # end foreach
		foreach ( $Project->signatures({ Group => 1 }) ) {
			openprint::print_project::delete_service( $Project, $_ );
		} # end foreach
	} # end if Backing

	if ( ! $Project->signatures({ type=>'Pad Pages'}) ) {
# Must have at least 1 interioer signature
		my $print_service_index = $Project->add_signature( undef, 'uncalculated', {
				txtSignatureType	=>	'Pad Pages',
				txtServiceDescription	=> 'Pad Pages',
				Group	=> 2,
				PrintingType	=> $$param{PrintingType},
				txtSpreadSize	=> 1,
				} );
	} # end if
	if ( ( ! $$param{GroupPageQuantity2} ) and ( $$param{OverrideGroupPageQuantity2} ne 'Y' ) ) {
		$$param{GroupPageQuantity2} = $needed_pages{'Pad Pages'};
	} # end if

	# THis could only set sizes.. weird.
	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $$Project{id}, $ss_id );
		my $group_id = $$sig_specs{Group};
		foreach my $k ( @signature_variables ) {
			openprint::service::insert_service_spec( $openprint::log, $openprint::dbh, $$Project{id}, $ss_id, $k, $$specs{$k.$group_id} );
		}
	} # end foreach

	my $services = $Project->services();
	if ( $$services{Padding} ) {
		foreach my $padding_id ( @{$$services{Padding}} ) {
			openprint::service::insert_service_spec( $log, $dbh, $p_id, $padding_id, 'Backing', $$param{Backing} );
			openprint::service::insert_service_spec( $log, $dbh, $p_id, $padding_id, 'PageQuantity', $$param{PageQuantity} );
		} # end foreach
	} # end if

} # end sub save

sub calculate_signatures {
  return openprint::Estimating::MultiPage::calculate_signatures(@_);
}


1;
__END__
