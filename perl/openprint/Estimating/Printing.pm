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

# TODO:
# Setup for cover only needs to be done once

package openprint::Estimating::Printing;
use strict;
use warnings;
use Data::Dumper;
use Storable 'dclone';
use POSIX qw(ceil);
use List::Util qw(sum);
use openprint ();
use vars qw( %config $log $dbh %ServicePrices %Specifications);
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;

require sql;
require misc;

my $threading = 0;
#use threads;
use constant DEBUG => 1;
use constant DEBUG_PLATES => 0;
use constant DEBUG_VERSIONS => 1;
use constant DEBUG_PRESSES => 0;
use constant DEBUG_FILTERING => 0;
use constant DEBUG_INITIAL_FILTERING => 0;
use constant DEBUG_AFTER_FILTERING => 0;
use constant DEBUG_PRICE_DECISIONS => 0;
use constant DEBUG_INKS => 0;
use constant DEBUG_STOCK => 0;
use constant COMPARISON_LOG => 0;
use constant USE_PRICE_CACHE => 1;
use constant DEBUG_IMPOSITIONS => 0;

%ServicePrices = (
	Roll2Sheet => {
		units	=> [ 'per m' ],
		},
	SuppliedSheet	=>	 {
		units	=> [ 'per 100lbs', 'per sheet', 'per m' ],
		},
	SuppliedRoll	=>	 {
		units	=> [ 'per 100lbs', 'per sheet', 'per m' ],
		},
	Film	=> { },
	'Version Setup'	=> { units=> [ 'each', 'total' ] },
	BlanketCut	=> { },
	Washup		=> { units=> [ 'each' ] },
	WebSetup	=> { units => [ ] },
	PerfectingSetup	=> { units => [ ] },
	'Work & TurnSetup'	=> { units => [ ] },
	'Work & TumbleSetup'	=>	{ units=> [] },
	'Sheet WorkSetup'		=>	{ units=> [] },
	PressRunChargeMinimum	=>	{ units=> [] },
	'\d*ColourImpression'		=>	{ units=> [ 'per impression', 'per hour' ] },
	'PressUnitMakeReady(.*)'		=>	{ units => [ 'stock calliper - per plate', 'per job', 'per form', 'total', 'per side'] },
	PlateMakeReady					=>	{ units => [ 'per hour', 'per plate' ] },
	# Re-enable when someone uses
	#PlateMakeReadyWeb					=>	{ units => [ 'per hour', 'per plate' ] },
	#PlateMakeReadyWeb1Sided					=>	{ units => [ 'per hour', 'per plate' ] },
	#PlateMakeReadyWeb2Sided					=>	{ units => [ 'per hour', 'per plate' ] },
	#PlateMakeReadyPerfecting					=>	{ units => [ 'per hour', 'per plate' ] },
	#'PlateMakeReadyWork & Turn'					=>	{ units => [ 'per hour', 'per plate' ] },
	#'PlateMakeReadyWork & Tumble'					=>	{ units => [ 'per hour', 'per plate' ] },
	#'PlateMakeReadySheet Work'					=>	{ units => [ 'per hour', 'per plate' ] },
);

sub ServicePriceConfiguration {
  return $ServicePrices{shift};
}
%Specifications = (
  'Colour Bar Size' => { units => ['Inches'] },
  'Default Colour Proof' => {},
  'Default Layout Proof' => {},
  'Envelope Capable' => { units => ['Y/N'] },
  'Grip' => { units => 'Inches' },
  'Gutter' => { units => 'Inches' },
  'MakeReadyOvers Rate' => { units => ['sheets per colour']},
  'Maximum Calliper' => { units => ['Inches'] },
  'Maximum Image Area Length' => { units => ['Inches'] },
  'Maximum Image Area Width' => { units => ['Inches'] },
  'Maximum Plate Impressions' => { units => [''] },
  'Maximum Sheet Length' => { units => ['Inches'] },
  'Maximum Sheet Width' => { units => ['Inches'] },
  'Minimum Sheet Length' => { units => ['Inches'] },
  'Minimum Sheet Width' => { units => ['Inches'] },
  'Number of Colours' => { units => [] },
  'Overs' => { units => [], values=>['','All'] },
  'Plate Size' => { units => [ 'Inches' ]},
  'Plate Type' => { values => [ 'Convential', 'CTP', 'DI' ]},
  'Press Run Overs' => { range_units => [] },
  'Runstyles'=> { values=>['Sheet Work', 'Work & Turn', 'Work & Tumble', 'Perfecting', 'Web'] },

);
sub SpecificationConfiguration {
  return $Specifications{shift};
}


my $master_time;
my %special_colours;

my %folding_cache;
my %Papers;
my %Presses;
my %Press_Values;

sub load_presses {
	%Presses = map { $$_{strid}, $_ } openprint::Equipment->find( 'category any'=>'Printing', 'useinestimating is null or ='=>1 );
	%Press_Values = map { $_->specification('Value') ? ( $$_{id} => $_->specification('Value') ) : () } values %Presses;
}
#Indexed by group
my %Estimating_Setup;

my %Services;
my %Materials;

my $do_initial_filtering = 1;
my $max_recursion_depth = 3;
my %filtered_imposition_cache;
my $use_filtered_imposition_cache = 0;
my $calc_other_groups = 1;
my $third_level_filtering = 1;

my %stitching_cache;
my %price_cache;
my %other_group_cache;

my $PaperServiceType;

my $GripperMakeReadyService;

#use warnings;
my $ImpositionServiceType;

require openprint::print_project;
require openprint::service;
require openprint::Equipment;
require openprint::imposition;
use openprint::Imposition;
require openprint::Paper;
require openprint::Estimating::Paper;
require openprint::Estimating::DieCutting;
require openprint::Estimating::Folding;
require openprint::Estimating::Scoring;
require openprint::Estimating::Perforating;
require openprint::Estimating::Cutting;
require openprint::Estimating::Stitching;
require openprint::Estimating::PerfectBound;
require openprint::Estimating::SpinePaste;
require openprint::Estimating::UVCoating;
require openprint::Estimating::Aqueous;
require openprint::Estimating::Numbering;
require openprint::Estimating::Proofs;
require openprint::Estimating::Imposition;
require openprint::Equipment;
require openprint::Material;
require openprint::ServiceCategory;
require openprint::Ink;

use Time::HiRes qw{ time gettimeofday tv_interval }; 

my @process_colours = ( 'Cyan','Magenta','Yellow','Black','Cyan Spot Colour','Yellow Spot Colour','Magenta Spot Colour','Black Spot Colour' );
my %process_colours_short = (
		'Cyan'		=>'C',
		'Magenta'	=>'M',
		'Yellow'	=>'Y',
		'Black'		=>'K',
		);

# These are use to tell the code which variables to save
# There are other values in teh actual specs hash, but htey are either transitory or should never be changed
my %variables = (
	alert=>['save','output'],
	ProjectIndex=>[], ServiceIndex=>[], ServiceType=>[], btnFunction=>[], callback=>[],SignatureIndex=>[],
	Impositions=>[], 'Additional Impositions1'=>[], 'Additional Impositions2'=>[], 'Additional Impositions3'=>[],
	hdnBreakdown1=>['save','output'], hdnBreakdown2=>['save','output'], hdnBreakdown3=>['save','output'],
	txtSignatureType => ['save'],
	txtServiceDescription	=> ['save'],
	txtEmployeeComments	=>	['save'],
	txtPrice1 => ['save','output'], txtPrice2 => ['save','output'], txtPrice3 => ['save','output'],
	Markup1 => ['save'], Markup2 => ['save'], Markup3 => ['save'],
	OverridePrice1 => ['save'], OverridePrice2 => ['save'], OverridePrice3 => ['save'],
	MPrice1 => ['save','output'], MPrice2 => ['save','output'], MPrice3 => ['save','output'],
  side_link => ['save'],
	SideOneColours		=>	 [],
	SideTwoColours		=>	 [],
	chkCyanSideOne => ['save'],
	chkMagentaSideOne => ['save'],
	chkYellowSideOne	=> ['save'],
	chkBlackSideOne 	=> ['save'],
	chkProcessColourSideOne 		=>	['save'],
	CyanSpotSideOneCoverage		=>	['save'],
	MagentaSpotSideOneCoverage	=>	['save'],
	YellowSpotSideOneCoverage		=>	['save'],
	BlackSpotSideOneCoverage		=>	['save'],

	CyanSideOneCoverage	=>	['save'],
	MagentaSideOneCoverage	=>	['save'],
	YellowSideOneCoverage	=>	['save'],
	BlackSideOneCoverage	=>	['save'],
	chkColourCoating1SideOne => ['save'], ColourCoatingType1SideOne => ['save'], ColourCoatingColour1SideOne => ['save'],ColourCoatingCoverage1SideOne => ['save'],
	ColourCoatingPrice1SideOne => ['save'], ColourCoatingMileage1SideOne => ['save'],

	chkColourCoating2SideOne => ['save'], ColourCoatingType2SideOne => ['save'], ColourCoatingColour2SideOne => ['save'],ColourCoatingCoverage2SideOne => ['save'],
	ColourCoatingPrice2SideOne => ['save'], ColourCoatingMileage2SideOne => ['save'],
	chkColourCoating3SideOne => ['save'], ColourCoatingType3SideOne => ['save'], ColourCoatingColour3SideOne => ['save'],ColourCoatingCoverage3SideOne => ['save'],
	ColourCoatingPrice3SideOne => ['save'], ColourCoatingMileage3SideOne => ['save'],
	chkColourCoating4SideOne => ['save'], ColourCoatingType4SideOne => ['save'], ColourCoatingColour4SideOne => ['save'],ColourCoatingCoverage4SideOne => ['save'],
	ColourCoatingPrice4SideOne => ['save'], 
	ColourCoatingMileage4SideOne => ['save'],
	chkColourCoating5SideOne => ['save'], ColourCoatingType5SideOne => ['save'], ColourCoatingColour5SideOne => ['save'],ColourCoatingCoverage5SideOne => ['save'],
	ColourCoatingPrice5SideOne => ['save'], 
	ColourCoatingMileage5SideOne => ['save'],
	chkColourCoating6SideOne => ['save'], ColourCoatingType6SideOne => ['save'], ColourCoatingColour6SideOne => ['save'],ColourCoatingCoverage6SideOne => ['save'],
	ColourCoatingPrice6SideOne => ['save'], 
	ColourCoatingMileage6SideOne => ['save'],
	chkColourCoating7SideOne => ['save'], ColourCoatingType7SideOne => ['save'], ColourCoatingColour7SideOne => ['save'],ColourCoatingCoverage7SideOne => ['save'],
	ColourCoatingPrice7SideOne => ['save'], 
	ColourCoatingMileage7SideOne => ['save'],
	chkColourCoating8SideOne => ['save'], ColourCoatingType8SideOne => ['save'], ColourCoatingColour8SideOne => ['save'],ColourCoatingCoverage8SideOne => ['save'],
	ColourCoatingPrice8SideOne => ['save'], 
	ColourCoatingMileage8SideOne => ['save'],
	chkColourCoating9SideOne => ['save'], ColourCoatingType9SideOne => ['save'], ColourCoatingColour9SideOne => ['save'],ColourCoatingCoverage9SideOne => ['save'],
	ColourCoatingPrice9SideOne => ['save'], 
	ColourCoatingMileage9SideOne => ['save'],

	CyanSpotSideTwoCoverage	=>	['save'],
	MagentaSpotSideTwoCoverage	=>	['save'],
	YellowSpotSideTwoCoverage	=>	['save'],
	BlackSpotSideTwoCoverage	=>	['save'],

	CyanSideTwoCoverage	=>	['save'],
	MagentaSideTwoCoverage	=>	['save'],
	YellowSideTwoCoverage	=>	['save'],
	BlackSideTwoCoverage	=>	['save'],

	chkCyanSideTwo => ['save'],chkMagentaSideTwo => ['save'],chkYellowSideTwo => ['save'],chkBlackSideTwo => ['save'],
	chkProcessColourSideTwo => ['save'],
	chkColourCoating1SideTwo => ['save'], ColourCoatingType1SideTwo => ['save'], ColourCoatingColour1SideTwo => ['save'],ColourCoatingCoverage1SideTwo => ['save'],
	ColourCoatingPrice1SideTwo => ['save'], 
	ColourCoatingMileage1Sidetwo => ['save'],
	chkColourCoating2SideTwo => ['save'], ColourCoatingType2SideTwo => ['save'], ColourCoatingColour2SideTwo => ['save'],ColourCoatingCoverage2SideTwo => ['save'],
	ColourCoatingPrice2SideTwo => ['save'], 
	ColourCoatingMileage2Sidetwo => ['save'],
	chkColourCoating3SideTwo => ['save'], ColourCoatingType3SideTwo => ['save'], ColourCoatingColour3SideTwo => ['save'],ColourCoatingCoverage3SideTwo => ['save'],
	ColourCoatingPrice3SideTwo => ['save'], 
	ColourCoatingMileage3Sidetwo => ['save'],
	chkColourCoating4SideTwo => ['save'], ColourCoatingType4SideTwo => ['save'], ColourCoatingColour4SideTwo => ['save'],ColourCoatingCoverage4SideTwo => ['save'],
	ColourCoatingPrice4SideTwo => ['save'], 
	ColourCoatingMileage4Sidetwo => ['save'],
	chkColourCoating5SideTwo => ['save'], ColourCoatingType5SideTwo => ['save'], ColourCoatingColour5SideTwo => ['save'],ColourCoatingCoverage5SideTwo => ['save'],
	ColourCoatingPrice5SideTwo => ['save'], 
	ColourCoatingMileage5Sidetwo => ['save'],
	chkColourCoating6SideTwo => ['save'], ColourCoatingType6SideTwo => ['save'], ColourCoatingColour6SideTwo => ['save'],ColourCoatingCoverage6SideTwo => ['save'],
	ColourCoatingPrice6SideTwo => ['save'], 
	ColourCoatingMileage6Sidetwo => ['save'],
	chkColourCoating7SideTwo => ['save'], ColourCoatingType7SideTwo => ['save'], ColourCoatingColour7SideTwo => ['save'],ColourCoatingCoverage7SideTwo => ['save'],
	ColourCoatingPrice7SideTwo => ['save'], 
	ColourCoatingMileage7Sidetwo => ['save'],
	chkColourCoating8SideTwo => ['save'], ColourCoatingType8SideTwo => ['save'], ColourCoatingColour8SideTwo => ['save'],ColourCoatingCoverage8SideTwo => ['save'],
	ColourCoatingPrice8SideTwo => ['save'], 
	ColourCoatingMileage8Sidetwo => ['save'],
	chkColourCoating9SideTwo => ['save'], ColourCoatingType9SideTwo => ['save'], ColourCoatingColour9SideTwo => ['save'],ColourCoatingCoverage9SideTwo => ['save'],
	ColourCoatingPrice9SideTwo => ['save'], 
	ColourCoatingMileage9Sidetwo => ['save'],
	sides_the_same	=> ['save'],
	ddmBleedSize1 => ['save','output'], ddmBleedSize2 => ['save','output'], ddmBleedSize3 => ['save','output'],
	chkOverrideBleedSize1=>['save'], chkOverrideBleedSize2=>['save'], chkOverrideBleedSize3=>['save'],
	OverrideAddGrip	=> ['save'],

	BleedLeft => ['save'], BleedRight => ['save'], BleedTop => ['save'], BleedBottom => ['save'],
	rdbColourBar => ['save','output'], txtCropMarkSpace => ['save'],
	ddmStockQuality	=>	['save'],
	ddmStockGroup	=>	['save'],
	ddmStockBrand => ['save'], txtSpecificStockBrand => ['save'], 
	ddmStockFinish => ['save'], txtSpecificStockFinish => ['save'], 
	ddmStockColour => ['save'], txtSpecificStockColour => ['save'],
	ddmStockWeight => ['save'], txtSpecificStockWeight=>['save'],
	txtSpecificStockCalliper => ['save','output'], txtSpecificStockWidth => ['save'], txtSpecificStockHeight => ['save'], CustomSheetDoubleSided => ['save'],
  CustomStockPrice => ['save'], StockPricePerM=> ['save'],
  txtCustomMWeight => ['save'],txtStockGSM => ['save','output'],
	perfecting=>['save'],
	basis_width=>['save'],basis_height=>['save'],basis_mweight=>['save'],
	StockGrade	=> ['save'],	
	txtUnspecifiedPageQuantity1 => ['output'], PageQuantity1 => ['save','output'],
	txtUnspecifiedPageQuantity2 => ['output'], PageQuantity2 => ['save','output'],
	txtUnspecifiedPageQuantity3 => ['output'], PageQuantity3 => ['save','output'],
	minimum_order=>['save'],sheets_per_package=>['save'],full_packages=>['save'],
	chkOverridePageQuantity1 => ['save'], chkOverridePageQuantity2 => ['save'], chkOverridePageQuantity3 => ['save'],
	SpreadRows1 => ['save','output'],SpreadCols1 => ['save','output'],
	SpreadRows2 => ['save','output'],SpreadCols2 => ['save','output'],
	SpreadRows3 => ['save','output'],SpreadCols3 => ['save','output'],
	ddmStockSheetSize => ['save'],ddmStockSheetSize1 => ['save','output'], ddmStockSheetSize2 => ['save','output'], ddmStockSheetSize3 => ['save','output'],
	ddmStockSize	=>	['save'],
	ddmRunStyle=>['save'], ddmRunStyle1 => ['save','output'], ddmRunStyle2 => ['save','output'], ddmRunStyle3 => ['save','output'],
	ddmPress1 => ['save','output'], ddmPress2 => ['save','output'], ddmPress3 => ['save','output'], 
	PrintingType1 => ['save','output'], PrintingType2 => ['save','output'], PrintingType3 => ['save','output'], 
	PrintingTypes => [],

	rdbPlateType1 => ['save','output'], rdbPlateType2 => ['save','output'], rdbPlateType3 => ['save','output'],
	PlateID1 => ['save','output'], PlateID2 => ['save','output'], PlateID3 => ['save','output'],
	txtPlateQuantity1 => ['save','output'], txtPlateQuantity2 => ['save','output'], txtPlateQuantity3 => ['save','output'], 
	BlankPlateQuantity1 => ['save','output'], BlankPlateQuantity2 => ['save','output'], BlankPlateQuantity3 => ['save','output'], 
	txtPlateChangeQuantity1 => ['save'], txtPlateChangeQuantity2 => ['save'], txtPlateChangeQuantity3 => ['save'], 
	PlateChangeType1 => ['save'], PlateChangeType2 => ['save'], PlateChangeType3 => ['save'], 
#
	PerPlateCost1 => ['save','output'], PerPlateCost2 => ['save','output'], PerPlateCost3 => ['save','output'],
	PlateTotalCost1 => ['save','output'], PlateTotalCost2	=> ['save','output'], PlateTotalCost3 => ['save','output'],
	PlateMakeReady1 =>	['save','output'], PlateMakeReady2 => ['save','output'], PlateMakeReady3 => ['save','output'],
	PerPlateMkRd1 =>	['save','output'], PerPlateMkRd2 => ['save','output'], PerPlateMkRd3 => ['save','output'],
	RunChargeTotal1 =>	['save','output'], RunChargeTotal2 => ['save','output'], RunChargeTotal3 => ['save','output'],
	OverSetup1 =>	['save','output'], OverSetup2 => ['save','output'], OverSetup3 => ['save','output'],
	OverrideSetup1 =>	['save'], OverrideSetup2 => ['save'], OverrideSetup3 => ['save'],
	OverRun1 =>	['save','output'], OverRun2 => ['save','output'], OverRun3 => ['save','output'],
	OverrideRun1 =>	['save'], OverrideRun2 => ['save'], OverrideRun3 => ['save'],
	OverTotal1 =>	['save','output'], OverTotal2 => ['save','output'], OverTotal3 => ['save','output'],
	PressWashPrice1 =>	['save','output'], PressWashPrice2 => ['save','output'], PressWashPrice3 => ['save','output'],
	PressWashCharge1 =>	['save','output'], PressWashCharge2 => ['save','output'], PressWashCharge3 => ['save','output'],
	PressWashes1 =>	['save','output'], PressWashes2 => ['save','output'], PressWashes3 => ['save','output'],
	ImpositionCharge1 =>	['save','output'], ImpositionCharge2 => ['save','output'], ImpositionCharge3 => ['save','output'],
	PageCharge1 =>	['save','output'], PageCharge2 => ['save','output'], PageCharge3 => ['save','output'],
	SteppingCharge1 =>	['save','output'], SteppingCharge2 => ['save','output'], SteppingCharge3 => ['save','output'],
	InkTotalCharge1 =>	['save','output'], InkTotalCharge2 => ['save','output'], InkTotalCharge3 => ['save','output'],
	StockSetupCharge1	=> ['save','output'], StockSetupCharge2	=> ['save','output'], StockSetupCharge3	=> ['save','output'],
#

	txtPressSheetQty1 => ['save','output'], txtPressSheetQty2 => ['save','output'], txtPressSheetQty3 => ['save','output'],
	Roll2SheetMakeReady1 => ['save','output'], Roll2SheetMakeReady2	=> ['save','output'], Roll2SheetMakeReady3	=> ['save','output'],
	Roll2SheetRunCharge1 => ['save','output'], Roll2SheetRunCharge2	=> ['save','output'], Roll2SheetRunCharge3	=> ['save','output'],
	dutch1=> ['save'], dutch2 => ['save'], dutch3 => ['save' ],
	chkOverrideImposition1 => ['save'], chkOverrideImposition2 => ['save'], chkOverrideImposition3 => ['save'],
	OverrideImpositionLayout1 => ['save'], OverrideImpositionLayout2 => ['save'], OverrideImpositionLayout3 => ['save'],
	txtImposition=>['save'],txtImposition1 => ['save','output'], txtImposition2 => ['save','output'], txtImposition3 => ['save','output'],
	txtImageWidth1 => ['save','output'], txtImageWidth2 => ['save','output'], txtImageWidth3 => ['save','output'],
	txtImageHeight1 => ['save','output'], txtImageHeight2 => ['save','output'], txtImageHeight3 => ['save','output'],
	txtLayoutWidth1 => ['save','output'], txtLayoutWidth2 => ['save','output'], txtLayoutWidth3 => ['save','output'],
	txtLayoutHeight1 => ['save','output'], txtLayoutHeight2 => ['save','output'], txtLayoutHeight3 => ['save','output'],
	hdnImpositionRows=>['save'],hdnImpositionRows1 => ['save','output'], hdnImpositionRows2 => ['save','output'], hdnImpositionRows3 => ['save','output'],
	hdnImpositionColumns=>['save'],hdnImpositionColumns1 => ['save','output'], hdnImpositionColumns2 => ['save','output'], hdnImpositionColumns3 => ['save','output'],
	hdnImpositionDutchRows=>['save'],hdnImpositionDutchRows1 => ['save','output'], hdnImpositionDutchRows2 => ['save','output'], hdnImpositionDutchRows3 => ['save','output'],
	hdnImpositionDutchColumns=>['save'],hdnImpositionDutchColumns1 => ['save','output'], hdnImpositionDutchColumns2 => ['save','output'], hdnImpositionDutchColumns3 => ['save','output'],
	dutch_orientation1	=>	['save'],
	dutch_orientation2	=>	['save'],
	dutch_orientation3	=>	['save'],
	txtQuantity1 => ['save'], txtQuantity2 => ['save'], txtQuantity3 => ['save'], 
	hdnImpressionQuantity1 => ['save','output'], hdnImpressionQuantity2 => ['save','output'], hdnImpressionQuantity3 => ['save','output'], 
	rdbPressProof => ['save'],
	PressApproval => ['save'],
	txtMWeight1 => ['save','output'], txtMWeight2 => ['save','output'], txtMWeight3 => ['save','output'],
	paper_id1	=>	['save','output'], paper_id2	=>	['save','output'], paper_id3	=> ['save','output'],
	hdnSuppliedStockWidth1 => ['save','output'], hdnSuppliedStockWidth2 => ['save','output'], hdnSuppliedStockWidth3 => ['save','output'],
	hdnSuppliedStockHeight1 => ['save','output'], hdnSuppliedStockHeight2 => ['save','output'], hdnSuppliedStockHeight3 => ['save','output'],
	StockWidth=>['save'],StockWidth1 => ['save','output'], StockWidth2 => ['save','output'], StockWidth3 => ['save','output'],
	StockHeight=>['save'],StockHeight1 => ['save','output'], StockHeight2 => ['save','output'], StockHeight3 => ['save','output'],
	OverrideStockWidth1 => ['save'], OverrideStockWidth2 => ['save'], OverrideStockWidth3 => ['save'],
	OverrideStockHeight1 => ['save'], OverrideStockHeight2 => ['save'], OverrideStockHeight3 => ['save'],
	RotateSheet1 => ['save'], RotateSheet3 => ['save'], RotateSheet2 => ['save'],
	CutOff1 => ['save','output'], CutOff2 => ['save','output'], CutOff3 => ['save','output'],
	OverrideCutOff1 => ['save'], OverrideCutOff2 => ['save'], OverrideCutOff3 => ['save'],
	StockType => ['save','output'],StockType1 => ['save','output'], StockType2 => ['save','output'], StockType3 => ['save','output'],
	OverrideStockType1	=>	['save'], OverrideStockType2	=>	['save'], OverrideStockType3	=>	['save'],
	hdnImageOrientation1 => ['save','output'], hdnImageOrientation2 => ['save','output'], hdnImageOrientation3 => ['save','output'], 
	hdnNetSheetCount1 => ['save','output'], hdnNetSheetCount2 => ['save','output'], hdnNetSheetCount3 => ['save','output'],
	StockQuantity1 => ['save','output'], StockQuantity2 => ['save','output'], StockQuantity3 => ['save','output'],
	Runspeed1 => ['save','output'], Runspeed2 => ['save','output'], Runspeed3 => ['save','output'],
	RunspeedOverride1 => ['save'], RunspeedOverride2 => ['save'], RunspeedOverride3 => ['save'],
	RunTime1 => ['save','output'], RunTime2 => ['save','output'], RunTime3 => ['save','output'],
	txtWidth => ['save'], txtHeight => ['save'], txtFinalWidth => ['save'], txtFinalHeight => ['save'],
	chkOverrideDimensions	=> ['save'],
	txtFinishedCalliper => ['save','output'], 
	PageQuantity => ['save'], # for Scratch Pads
# Presentation Folders
	rdbPanels => ['save'],PocketSize => ['save'],chkPocketLeft => ['save'],chkPocketCenter => ['save'],chkPocketRight => ['save'],
	rdbSuppliedStock => ['save'], rdbSpecificStock => ['save'],rdbTemplateType => ['save'],
	chkOverrideRunStyle1 => ['save'], chkOverrideRunStyle2 => ['save'], chkOverrideRunStyle3 => ['save'],
	chkOverrideSheetSize1 => ['save'], chkOverrideSheetSize2 => ['save'], chkOverrideSheetSize3 => ['save'],
	chkOverridePress1 => ['save'], chkOverridePress2 => ['save'], chkOverridePress3 => ['save'],
	OverridePrintingType1 => ['save'], OverridePrintingType2 => ['save'], OverridePrintingType3 => ['save'],
	Versions => ['save'],Versions1=>['save','output'], Versions2=>['save','output'], Versions3=>['save','output'],
	OverrideVersions1=>['save'], OverrideVersions2=>['save'], OverrideVersions3=>['save'],
	versions => ['save'],
  Version_Descriptions => ['output'],
	ddmProjectSize => ['save'],
	ScreenType => ['save'],
	rdbGrainDirection1 => ['save','output'], rdbGrainDirection2 => ['save','output'], rdbGrainDirection3 => ['save','output'],
	MatchGrain1 => ['save'], MatchGrain2 => ['save'], MatchGrain3 => ['save'], 
	chkOverrideGrainDirection1 => ['save'], chkOverrideGrainDirection2 => ['save'], chkOverrideGrainDirection3 => ['save'],
	txtPressSheetComboItems=>['save'],
	txtSpreadSize => ['save'],OverrideSpreadSize => ['save'],
	Group => ['save'], GroupPageQuantity => ['save'], OverrideGroupPageQuantity => [ 'save' ],
	PaperMessage1=>['output'], PaperMessage2=>['output'], PaperMessage3=>['output'],

# These two are for when the customer is supplying the pages. The first just says whether the pages are supplied, the second tells us whether they are supplying sheets or folded signatures.
	pages_supplied=>['save'],
	supplied_format=>['save'],
# Banners
	grommets => ['save'], grommeting => ['save'],
	pockets	=>	['save'],
	hemmed	=>	['save'],
	EdgeLeft => ['save'], EdgeRight => ['save'], EdgeTop => ['save'], EdgeBottom=>['save'],
	HemWidth	=>	['save'],
);

my @qty_override_keys = (
				'chkOverrideBleedSize',
				'chkOverridePageQuantity',
				'chkOverrideImposition',
				'OverrideImpositionLayout',
				'chkOverrideRunStyle',
				'OverrideCutOff',
				'chkOverrideSheetSize',
				'chkOverridePress',
				'OverridePrintingType',
				'OverrideStockType',
				'chkOverrideGrainDirection',
				'OverrideVersions',
				'OverridePrice',
				'OverrideSetup',
				'OverrideRun',
				'RunspeedOverride',
				'chkOverridePlateType',
);
my @override_keys = (
				'chkOverrideDimensions',
				'OverrideAddGrip',
				'OverrideSpreadSize',
);

sub variables {
	my ( $project_index, $service_index, $specs, $new_specs ) = @_;

	my @v;
	foreach my $k ( keys %variables ) {
		push @v, $k if sets::isin( 'save', $variables{$k} );
	} # end foreach;

	if ($new_specs) {
		foreach my $side ( 'SideOne','SideTwo' ) {
			foreach my $k ( keys %$new_specs ) {
	$log->debug("Variables: $side $k old: $$specs{$k} new: $$new_specs{$k}");
				if ( my ( $index ) = $k =~ /^ColourCoating(\d+)$side/ ) {
	$log->debug("Saving $side $k $$new_specs{$k} $index");
					push @v, 'chkColourCoating'.$index.$side;
					push @v, 'ColourCoatingType'.$index.$side;
					push @v, 'ColourCoatingColour'.$index.$side;
					push @v, 'ColourCoatingCoverage'.$index.$side;
					push @v, 'ColourCoatingPrice'.$index.$side;
					push @v, 'ColourCoatingMileage'.$index.$side;
				} # end if
			} # end foreach k
		} # end foreach side
		my $Project = new openprint::Project( $project_index );
		if ( $$new_specs{versions} and ($$new_specs{versions} > 0) and ($$new_specs{versions} < 10)) {
			foreach my $version ( 1 .. $$new_specs{versions} ) {
        $openprint::log->debug("Version: $version");
				push @v, "version-$version-description";
				foreach my $qty_index ( $Project->quantity_indexes() ) {
					push @v, "version-$version-quantity$qty_index";
				} # end foreach qty_index
			} # end foreach version
		} # end if
	} # end if
	return @v;
} # end sub variables

sub no_outputs {
	my ( $project_index, $service_index, $specs, $new_specs, $v ) = @_;
	$v = \%variables if ! $v;

	my @v;
	foreach my $k ( keys %{$v} ) {
		push @v, $k if ! grep { $_ eq 'output' } @{ $$v{$k} };
	} # end foreach

	foreach my $side ( 'SideOne','SideTwo' ) {
		foreach my $colour ( 'Cyan','Magenta','Yellow','Black' ) {
			if ( $$specs{'chk'.$colour.$side} ) {
				@v = sets::exclude( [ $colour.'Spot'.$side.'Coverage' ], \@v );
			} # end if
		} # end foreach
		if ( $$specs{'chkProcessColour'.$side} ) {
			@v = sets::exclude( [ map { $_ .$side.'Coverage' } ( 'Cyan','Magenta','Yellow','Black' ) ], \@v );
		} # end if

		foreach my $k ( keys %$specs ) {
			if ( my ( $index ) = $k =~ /^chkColourCoating(\d+)$side/ ) {
				next if ! $$specs{"chkColourCoating$index$side"};
				@v = sets::exclude( [ 'ColourCoatingCoverage'.$index.$side ], \@v );
			} # end if
		} # end foreach
	} # end foreach Side

	return @v;
} # end sub no_outputs

sub outputs {
	my ( $project_index, $service_index, $specs, $new_specs, $v ) = @_;
	$v = \%variables if ! $v;
	my @v;
	foreach my $k ( keys %{$v} ) {
		push @v, $k if grep { $_ eq 'output' } @{ $$v{$k} };
	} # end foreach
	return @v;
} # end sub outputs

sub get_unspecified_pages {
	my ( $Project, $service_index, $specs, $qty_index ) = @_;
$log->debug("In get_unspecified_pages Project: $$Project{id}, service_id: $service_index, Group: $$specs{Group}, qty_index: $qty_index") if DEBUG;

	my $specified_pages = 0;
	foreach my $ssid ( $Project->signatures( { Group=>$$specs{Group} } ) ) {
		if ( $service_index and ( $ssid >= $service_index ) ) {
			$log->debug("Our index: $service_index ( $ssid >= $service_index ) next") if DEBUG;
			next;
		} # end if
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ssid );
		$specified_pages += $$sig_specs{"PageQuantity$qty_index"};
		#$log->debug(" $service_index ( $ssid >= $service_index ) Not next pages: ". $$sig_specs{"PageQuantity$qty_index"});
	} # end foreach

	$log->debug("Unspec: Qty$qty_index Group: $$specs{Group} GPQ:$$specs{GroupPageQuantity} - S$specified_pages = U" . ($$specs{GroupPageQuantity} - $specified_pages) ) if DEBUG;
	$_ = $$specs{GroupPageQuantity} - $specified_pages;
	return 0 if $_ < 1;
	return $_;
} # end sub get_unspecified_pages

sub get_unspecified_versions {
	my ( $Project, $service_index, $printing_specs, $specs, $qty_index ) = @_;
  $log->debug("Un get_unspecified_versions Project: $Project, service_id: $service_index, $printing_specs, $specs, qty_index: $qty_index") if DEBUG;

	my $specified = 0;
	foreach my $ssid ( $Project->signatures( { Group=>$$specs{Group} } ) ) {
		if ( $service_index and ( $ssid >= $service_index ) ) {
			#$log->debug(" $service_index ( $ssid >= $service_index ) next");
			next;
		} # end if
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ssid );
		$specified += $$sig_specs{"Versions$qty_index"};
		#$log->debug(" $service_index ( $ssid >= $service_index ) Not next pages: ". $$sig_specs{"PageQuantity$qty_index"});
	} # end foreach ssid

	$log->debug("Unspec: Qty$qty_index Group: $$specs{Group} versions:$$specs{versions} - S$specified = U" . ($$specs{versions} - $specified) ) if DEBUG;
	return $$specs{versions} - $specified;
} # end sub get_unspecified_versions

sub setup_project {
	my ( $Project, $service_index, $services, $specs, $side_one_colours, $side_two_colours, $Paper ) = @_;

	my %project = (
			txtSpreadSize	=>	$$specs{txtSpreadSize},
			ComboItems		=>	$$specs{txtPressSheetComboItems},
			'Add Grip Width'=>	$$specs{GripWidth},
			'Add Grip Height'=>	$$specs{GripHeight},
			'Add Colour Bar'=>	$$specs{rdbColourBar},
			image_width		=>	$$specs{txtWidth},
			image_height	=>	$$specs{txtHeight},
			txtWidth		=>	$$specs{txtWidth},
			txtHeight		=>	$$specs{txtHeight},
			txtFinalWidth	=>	$$specs{txtFinalWidth},
			txtFinalHeight	=>	$$specs{txtFinalHeight},
			BleedLocations	=>	join(',', map { $$specs{$_} ? $$specs{$_} : () } ('BleedBottom','BleedTop','BleedLeft','BleedRight')),
			Calliper		=>	$$specs{txtSpecificStockCalliper},
			CropMarkSpace	=>	$$specs{txtCropMarkSpace},
			);

	my $CoatingsCategory = openprint::ServiceCategory->find_one( name => 'Coating' );
	my %coatings = map { $_->name(), 1 } $CoatingsCategory->Services() if $CoatingsCategory;

	# Split out colours vs coatings, but Varnish is not a coating like AQ
  # It only runs on press, requires a plate but no blanket.

	$project{side_one_colours} = [];
	$project{side_one_coatings} = [];
	foreach my $c ( @$side_one_colours ) {
		if ( $coatings{$$c{name}} and ! ( $$c{name} =~ /Varnish/i ) ) {
			push @{$project{side_one_coatings}}, $c;
		} else {
			push @{$project{side_one_colours}}, $c;
		} # end if
	} # end foreach
	$project{side_two_colours} = [];
	$project{side_two_coatings} = [];
	foreach my $c ( @$side_two_colours ) {
		if ( $coatings{$$c{name}} and ! ( $$c{name} =~ /Varnish/i ) ) {
			push @{$project{side_two_coatings}}, $c;
		} else {
			push @{$project{side_two_colours}}, $c;
		} # end if
	} # end foreach

	$project{print_sides} = 1;
	if ( ( @{$project{side_one_colours}} > 0 ) and ( @{$project{side_two_colours}} > 0 ) ) {
		$project{print_sides} = 2;
	} # end if
#$log->debug("SIdes: $project{print_sides} : " . @{$project{side_one_colours}} . ',' . @{$project{side_two_colours}} );

	$project{side_one_colour_names} = [ map { $$_{name} } @{$side_one_colours} ];
	$project{side_two_colour_names} = [ map { $$_{name} } @{$side_two_colours} ];
	# Don't need to exclude coatings because they have already been cut out.
	@{$project{non_process_colours}} = sets::exclude( \@process_colours, [ map { $$_{name} } ( @{$side_one_colours}, @{$side_two_colours} ) ] );

	$project{combined_colours} = [ @{$project{side_one_colours}}, @{$project{side_two_colours}} ];
	$project{combined_coatings} = [ @{$project{side_one_coatings}}, @{$project{side_two_coatings}} ];

	#$project{inkCoverage} = $inkCoverage;

	# Filtered colours are for W&T
	my @filtered_colours = filter_colours( $project{side_one_colours}, $project{side_two_colours} );

	my %mixed_colours;
	my %washed_colours;

  $project{sorted_signatures} = [ $Project->signatures( { sort=>1 } ) ];
	foreach my $index ( @{$project{sorted_signatures}} ) {
		last if $index == $service_index;
		my $sig_specs = openprint::service::get_specs_ref( $Project, $index );
		next if $$sig_specs{pages_supplied} and ($$sig_specs{pages_supplied} eq 'Y');

		if ( $$sig_specs{Group} and ! exists $project{"Group$$sig_specs{Group}Specs"} ) {
			my $group_specs = $project{"Group$$sig_specs{Group}Specs"} = {};

			my @sig_side_one_colours = get_colours($sig_specs, 'SideOne');
			my @sig_side_two_colours = get_colours($sig_specs, $$sig_specs{side_link} ? 'SideOne' : 'SideTwo');
			foreach my $Colour ( @sig_side_one_colours, @sig_side_two_colours ) {
				$mixed_colours{$$Colour{name}} = 1;
				foreach my $qty_index ( $Project->quantity_indexes() ) {
$log->debug("Setting washed colours $$Colour{name}.'-'.$$sig_specs{'ddmPress'.$qty_index}.'-'.$qty_index} $index $$sig_specs{SignatureIndex}") if DEBUG_INKS;
					$washed_colours{$$Colour{name}.'-'.$$sig_specs{'ddmPress'.$qty_index}.'-'.$qty_index} += 1;
				} # end foreach
			} # end foreach
			#my %inkCoverage = get_inkcoverage( $Project, $sig_specs );
			#$$group_specs{inkCoverage} = \%inkCoverage;
		} 
	} # end for each
	if ( DEBUG_INKS ) {
		foreach my $k ( keys %washed_colours ) {
			$log->debug("Washed colours $k => $washed_colours{$k}");
		}
	}
	$project{mixed_colours} = \%mixed_colours;
	$project{washed_colours} = \%washed_colours;
	$project{filtered_colours} = \@filtered_colours;
	$project{filtered_coatings} = [ filter_colours( $project{side_one_coatings}, $project{side_two_coatings} ) ];

	if ( @{$project{filtered_colours}} or @{$project{filtered_coatings}} ) {
		foreach my $C ( openprint::Ink->find( 'name in'=>[ ( map { $$_{name} } @{$project{filtered_colours}}) , ( map { $$_{name} } @{$project{filtered_coatings}} ) ] ) ) {
			push @{$special_colours{$$C{name}}}, $C;
		} # end foreach C
	} # end if
	# Make sure all our colours are in the special colours hash
	my $PMSInkMixService = $Services{PMSInkMix};
	foreach my $real_colour ( sort { $$a{name} cmp $$b{name} } @filtered_colours ) {
		my $colour;
		if ( $$real_colour{type} eq 'PMS' ) {
			# Name is supposed to be the PMS #, so strip everything out.	casual quotes will use PMS 1,2,3 which are not actual PMS numbers
			$colour = $$real_colour{name};
			#$colour =~ s/\D//g;
		} elsif ( $$real_colour{name} =~ /^(\w+) Spot Colour$/ ) {
			$colour = $1;
		} elsif ( $$real_colour{name} =~ /Aqueous/ ) {
			next;
		} elsif ( $$real_colour{name} =~ /(Spot|Overall)/ ) {
			$colour = $$real_colour{name};
			$colour =~ s/ (Spot|Overall)//ig;
		#} elsif ( $$real_colour{name} =~ /PMS/ ) {
			#$colour = $$real_colour{name};
		} else { 
			$colour = $$real_colour{name};
		} # end if
$log->debug("Doing colour $$real_colour{type} $$real_colour{name} =>$colour") if DEBUG_INKS;

		if (!$special_colours{$colour}) {
			my $Ink = openprint::Ink->find_one(name=>$colour);
			$log->debug("Adding special colour for ($colour) $Ink") if DEBUG_INKS;
			if ( !$Ink and ($$real_colour{type} eq 'PMS') ) {
				$Ink = openprint::Ink->find_one(name=>'PMSInk');
					$log->debug("Adding PMS special colour for $colour have: $Ink") if DEBUG_INKS;
			}
			if ( !$Ink ) {
        $log->debug("Creating special ink for $colour");
				# Some PMS or other ink that we don't have in the system, since CMYK are in teh system (we assume), washes can be 1
				$Ink = new openprint::Ink();
				$$Ink{pmsid} = $colour;
				$$Ink{name} = $$real_colour{name};
				if ( !sets::isin( $colour, \@process_colours ) ) {
					$$Ink{mix_service_id} = $PMSInkMixService->id() if $PMSInkMixService;
					$$Ink{mix} = 1;
					$$Ink{washups} = 1;
					my $Material = $Materials{$colour.'Ink'};
					$Material = $Materials{PMSInk} if ! $Material and $$real_colour{type} eq 'PMS';
					$$Ink{material_id} = $Material->id() if $Material;
				} # end if
			} # end if found Ink
			$special_colours{$colour} = [ $Ink ];
		} # end if
	} # end foreach
	$project{special_colours} = \%special_colours;

	$project{'Sheet WorkColours'} = [ @{$project{side_one_colours}}, @{$project{side_one_coatings}}, (
( $$specs{sides_the_same} eq 'Y' ) ? () :	@{$project{side_two_colours}},@{$project{side_two_coatings}} ) ];

	$project{WebColours} = [ @{$project{side_one_colours}}, @{$project{side_one_coatings}}, @{$project{side_two_colours}},@{$project{side_two_coatings}} ];
	$project{PerfectingColours} = [ @{$project{side_one_colours}}, @{$project{side_one_coatings}}, @{$project{side_two_colours}},@{$project{side_two_coatings}} ];
	$project{'Work & TurnColours'} = [ @{$project{filtered_colours}},@{$project{filtered_coatings}} ];
	$project{'Work & TumbleColours'} = [ @{$project{filtered_colours}},@{$project{filtered_coatings}} ];

	foreach my $service ( 'Folding','Scoring','Perforating','DieCutting','Cutting','Numbering','Proofs' ) {
		if ( $$services{$service} and @{$$services{$service}} ) {
			$$specs{'Has'.$service} = $project{'Has'.$service} = $$services{$service}[0];
      $project{$service.'Service'} = $Project->Service($$services{$service}[0]);
			%{$project{$service.'Specs'}} = %{openprint::service::get_specs_ref( $Project, $$services{$service}[0] )};
		} # end if	
	} # end foreach

	@project{'NoBindery','NoOfflineBindery'} = @$services{'NoBindery','NoOfflineBindery'};
	$project{Binding} = $Project->get_book_type();
	if ( !$$services{NoBindery} ) {
		$project{NeedFolding} = openprint::Estimating::Folding::signature_needs( $Project, $specs );
    $project{NeedDieCutting} = openprint::Estimating::DieCutting::signature_needs( $Project, $project{DieCuttingSpecs}, $specs );
		if ($project{NeedDieCutting}) {
#$log->debug("Need DieCutting: $project{NeedDieCutting}");
			$project{NeedScoring} = 0;
		} else {
			$project{NeedScoring} = openprint::Estimating::Scoring::signature_needs( $Project, $project{ScoringSpecs}, $specs, $Paper );
			if ( $project{NeedScoring} ) {
				my $form = $$specs{SignatureIndex};
				if ( (!defined $project{ScoringSpecs}{"chkOverrideQty-$form"}) or ( $project{ScoringSpecs}{"chkOverrideQty-$form"} ne 'Y' ) ) {
					openprint::Estimating::Scoring::get_scores( $Project, $project{ScoringSpecs}, $specs, $Paper );
				} # end if
				openprint::Estimating::Scoring::init( $Project, \%project );
			} # end if
		} # end if
	} else {
		$project{NeedDieCutting} = 0;
		$project{NeedScoring} = 0;
		$project{NeedFolding} = 0;
	} # end if
	openprint::Estimating::Cutting::init($Project, \%project);
	openprint::Estimating::Folding::init($Project, \%project) if $project{NeedFolding};
	$project{NeedUVCoating} = openprint::Estimating::UVCoating::signature_needs( $Project, $specs );
	$project{NeedAqueous} = openprint::Estimating::Aqueous::signature_needs( $Project, $specs );
	@$specs{'NeedFolding','NeedScoring','NeedDieCutting'} = @project{'NeedFolding','NeedScoring','NeedDieCutting'};

	# These aer questionable: Should not modify a project in calculation
	if ( $project{NeedUVCoating} ) {
		if ( ! $$services{UVCoating} ) {
			push @{$$services{UVCoating}}, $Project->add_service( 'UVCoating' );
		} # end if	
		$project{HasUVCoating} = $$services{UVCoating}[0];
		%{$project{UVCoatingSpecs}} = %{openprint::service::get_specs_ref( $Project, $$services{UVCoating}[0] )};
	} # end if	

  if ( $project{NeedAqueous} ) {
    if ( ! $$services{Aqueous} ) {
      $$services{Aqueous} = [];
      $_ = $Project->add_service('Aqueous');
      push @{$$services{Aqueous}}, $_ if $_;
    } # end if	
    if (!@{$$services{Aqueous}} and !$$services{AqueousInline} and openprint::ServiceType->find_one(name=>'AqueousInline')) {
      $_ = $Project->add_service('AqueousInline');
      push @{$$services{Aqueous}}, $_ if $_;
    }

    if (@{$$services{Aqueous}}) {
      $project{HasAqueous} = $$services{Aqueous}[0];
      openprint::Estimating::Aqueous::init($Project, $project{HasAqueous}, \%project);
      my $aq_specs = openprint::service::get_specs_ref( $Project, $$services{Aqueous}[0] );
      %{$project{AqueousSpecs}} = %{$aq_specs};

      my @sorted_sigs = @{$project{sorted_signatures}};

      foreach my $qty_index ( $Project->quantity_indexes() ) {
        my $aq_mrs = $project{"AqueousMakeReadies$qty_index"} = {};

        foreach my $sig_id ( @sorted_sigs ) {
          last if $sig_id == $service_index;
          my $s_specs = openprint::service::get_specs_ref( $Project, $sig_id );
          my @aq_colours = sets::union(
              openprint::Estimating::Aqueous::get_colours( $s_specs, 'SideOne' ),
              openprint::Estimating::Aqueous::get_colours( $s_specs, $$s_specs{side_link} ? 'SideOne' : 'SideTwo' ),
              );

          my $form = $$s_specs{SignatureIndex};
          my $equipment_id = $$aq_specs{"ddmEquipment-$form-$qty_index"};

          $$aq_mrs{$equipment_id} = {} if ! $$aq_mrs{$equipment_id};
          foreach my $colour ( @aq_colours ) {
            if ( $colour =~ /Aqueous/ ) {
              $$aq_mrs{$equipment_id}{$colour} = [] if ! $$aq_mrs{$equipment_id}{$colour};
              push @{$$aq_mrs{$equipment_id}{$colour}}, $$aq_specs{"txtLayoutWidth-$form-$qty_index"} * $$aq_specs{"txtLayoutHeight-$form-$qty_index"};
            } # end if
          } # end foreach colour
        } # end foreach sig

        $log->debug("AQUEOUS MR $qty_index " . join(',', keys %{$aq_mrs} ));
        foreach my $equipment_id ( keys %{$aq_mrs} ) {
          foreach my $type ( keys %{$$aq_mrs{$equipment_id}} ) {
            $log->debug("AQUEOUS MR qty_index:$qty_index equipment:$equipment_id type: $type" . join(',',@{$$aq_mrs{$equipment_id}{$type}}) );
          }
        }
      }
    } elsif ( $$services{Aqueous} and @{$$services{Aqueous}} ) {
      $project{HasAqueous} = $$services{Aqueous}[0];
      %{$project{AqueousSpecs}} = %{openprint::service::get_specs_ref( $Project, $$services{Aqueous}[0] )};
    } # end if	
  }

	if ( $$services{SaddleStitching} ) {
		%{$project{StitchingSpecs}} = %{openprint::service::get_specs_ref( $Project, $$services{SaddleStitching}[0] )};
		$project{HasStitching} = $$services{SaddleStitching}[0];
		openprint::Estimating::Stitching::init($Project, \%project);
	} elsif ( $$services{LoopStitching} ) {
		%{$project{StitchingSpecs}} = %{openprint::service::get_specs_ref( $Project, $$services{LoopStitching}[0] )};
		$project{HasStitching} = $$services{LoopStitching}[0];
		openprint::Estimating::Stitching::init($Project, \%project);
	} # end if
	if ( $project{HasStitching} ) {
		%{$project{FoldingStitchingSpecs}} = %{$project{StitchingSpecs}};
    $project{FoldingStitchingSpecs}{"chkOverrideEquipment1"} = 'Y';
    $project{FoldingStitchingSpecs}{"chkOverrideEquipment2"} = 'Y';
    $project{FoldingStitchingSpecs}{"chkOverrideEquipment3"} = 'Y';
	}

	%{$project{SpinePasteSpecs}} = %{openprint::service::get_specs_ref( $Project, $$services{SpinePaste}[0] )} if $$services{SpinePaste};
	if ( $$services{PerfectBound} ) {
		$project{HasPerfectBound} = $$services{PerfectBound}[0];
		%{$project{PerfectBoundSpecs}} = %{openprint::service::get_specs_ref( $Project, $$services{PerfectBound}[0] )};
		$project{PerfectBindCoverGutter} = $config{PerfectBindCoverGutter} if $$specs{Group} == 1;
	} # end if

	$project{ProjectSpecs} = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
	openprint::Estimating::Imposition::init( $Project );

	return \%project;
} # end sub setup_project

# This used to just return the names, while mangling the variable hash
# Now it will return an array of hash refs, which may someday become Objects
sub get_colours {
	my ( $specs, $side, $v ) = @_;
	#my ( $caller, undef, $line ) = caller;
#$log->debug("Called get_colours from $caller : $line");
	my @colours;
	if ((
        ( defined $$specs{sides_the_same} ) and ( $$specs{sides_the_same} eq 'Y' )
        or
        ( defined $$specs{side_link} ) and ( $$specs{side_link} eq '1' )
        and ( $side eq 'SideTwo' )
      )
     ) {
		$side = 'SideOne';
	} # end if

	$v = \%variables if ! $v;

	foreach my $colour ( 'Cyan','Magenta','Yellow','Black' ) {
		if ( $$specs{'chk'.$colour.$side} ) {
			push @colours, { 
				type	=>	'CMYK',
				name	=>"$colour Spot Colour",
				coverage => $$specs{$colour.'Spot'.$side.'Coverage'},
				coverage_key	=> $colour.'Spot'.$side.'Coverage',
			};
		} # end if
	} # end foreach

	if ( $$specs{'chkProcessColour'.$side} ) {
		push @colours, map { { 
			type	=>	'CMYK',
			name => $_,
			coverage=>$$specs{$_.$side.'Coverage'},
			coverage_key	=> $_.$side.'Coverage',
		} } ( 'Cyan','Magenta','Yellow','Black' );
	} # end if

	foreach my $index ( 1 .. $config{SpecialColourQuantity} ) {
    if (! $$specs{"chkColourCoating$index$side"} ) {
      $log->debug("No chkColourCoating for $index $side") if DEBUG_INKS;
      next ;
    }
    my $c = {
      type => $$specs{"ColourCoatingType$index$side"},
    };
    next if ! $$c{type};
    next if $$specs{'ColourCoatingColour'.$index.$side} and ( $$specs{'ColourCoatingColour'.$index.$side} eq 'None' );
    #$log->debug("Found Colour $index.$side $signature $type");
    if ( $$c{type} =~ /^PMS/ ) {
      if ( ! $$specs{'ColourCoatingColour'.$index.$side} ) {
        $$specs{'ColourCoatingColour'.$index.$side} = "PMS $index";
        $$v{'ColourCoatingColour'.$index.$side} = [ sets::union( 'output', @{$$v{'ColourCoatingColour'.$index.$side}} ) ];
      } #end if
      $$c{name} = $$specs{'ColourCoatingColour'.$index.$side};
    } else {
      # Non-PMS doesn't enter the Colour NAME
      $$specs{'ColourCoatingColour'.$index.$side} = '';
      $$v{'ColourCoatingColour'.$index.$side} = [ sets::union( 'output', @{$$v{'ColourCoatingColour'.$index.$side}} ) ];
      $$c{name} = $$c{type};
    } # end if type eq PMS
    $$c{coverage} = $$specs{'ColourCoatingCoverage'.$index.$side};
    $$c{coverage_key} = 'ColourCoatingCoverage'.$index.$side;
    push @colours, $c;
	} # end foreach index
	return @colours;
} # end sub get_colours

sub get_inkcoverage {
	my ( $Project, $specs, $v ) = @_;
	my ( $caller, undef, $line ) = caller;
$log->debug("Inkcoverage from $caller : $line");
	$v = \%variables if ! $v;
	my $ProjectTypeName = $Project->Type()->name();
	my $DefaultInkCoverage = $openprint::config{'DefaultInkCoverage'.$ProjectTypeName} ? 
		$openprint::config{'DefaultInkCoverage'.$ProjectTypeName} : $openprint::config{DefaultInkCoverage};

	my %inkCoverage;
	foreach my $side ( 'SideOne','SideTwo' ) {
		foreach my $colour ( 'Cyan','Magenta','Yellow','Black' ) {
			my $key = $colour.'Spot'.$side.'Coverage';
			if ( $$specs{'chk'.$colour.$side} ) {
				$$specs{$key} =~ s/[^\d\.]//g;
				if ( ! $$specs{$key} ) {
					$$specs{$key} = $DefaultInkCoverage;
					$$specs{$key} =~ s/[^\d\.]//g;
					$$v{$key} = [ sets::union( 'output', @{$$v{$key}} ) ];
				} else {
					$$v{$key} = [ sets::exclude( ['output'], $$v{$key} ) ];
				} # end if
				$inkCoverage{$colour.' Spot Colour'} += $$specs{$key};
			} # end if
		} # end foreach
		if ( $$specs{'chkProcessColour'.$side} ) {
			foreach my $colour ( 'Cyan','Magenta','Yellow','Black' ) {
				my $key = $colour.$side.'Coverage';
				my $c = $$specs{$key};
				$c =~ s/[^\d\.]//g;
				if ( ! $c ) {
$log->debug("$key => $c and set output $DefaultInkCoverage;");
					$c = $DefaultInkCoverage;
					$c =~ s/[^\d\.]//g if $c;
				} # end if
				if ( $c ne $$specs{$key} ) {
					$$v{$key} = [ sets::union( 'output', @{$$v{$key}} ) ];
					$$specs{$key} = $c;
$log->debug("$key => $c and set output");
				} # end if
				$inkCoverage{$colour} += $$specs{$key};
			} # end foreach CMYK
		} else {
			$log->debug("No process for $side");
		} # end if Process

		foreach my $index ( 1 .. $config{SpecialColourQuantity} ) {
		#foreach my $k ( keys %$specs ) {
# checked on
			#if ( my ( $index ) = $k =~ /^chkColourCoating(\d+)$side/ ) {
				next if ! $$specs{"chkColourCoating$index$side"};
				my $type = $$specs{"ColourCoatingType$index$side"};
				next if ! $type;

				my $coverage_key = 'ColourCoatingCoverage'.$index.$side;
				$$specs{$coverage_key} =~ s/[^\d\.]//g if $$specs{$coverage_key};

				if ( $type =~ /Overall/ ) {
					# Nothing cuz coverage is 100%
					$$specs{$coverage_key} = 100;
					#$log->warn("Overall for $index $side $signature " . $$specs{'ColourCoatingCoverage'.$index.$side.$signature} .' ' . int($$specs{'ColourCoatingCoverage'.$index.$side.$signature}) );
				} elsif ( ! int($$specs{$coverage_key}) ) {
					# What we are doing here is detecting an empty coverage value and populating it with the default
					#$log->warn("Coverage for $index $side $type key:$coverage_key specs:".$$specs{$coverage_key}.' '.int($$specs{$coverage_key}));
					$type =~ s/ /_/g;
					my $coverage;
					if ( $openprint::config{"Default${type}Coverage$ProjectTypeName"} ) {
						$log->debug("Got default for $type ProjectTypeName");
						$coverage = $openprint::config{"Default${type}Coverage$ProjectTypeName"};
					} elsif ( $openprint::config{"Default${type}Coverage"} ) {
						$log->debug('Got default for '.$type);
						$coverage = $openprint::config{"Default${type}Coverage"};
					} else {
						$log->debug('Using regular default instead of '.$type);
						$coverage = $DefaultInkCoverage;
					}
					$$specs{$coverage_key} = $coverage;
					$$v{$coverage_key} = [ sets::union( 'output', @{$$v{$coverage_key}} ) ];
				} else {
#$log->warn("Coverage for $index $side $signature " . $$specs{'ColourCoatingCoverage'.$index.$side.$signature} .' removing from outputs' );
					$$v{$coverage_key} = [ sets::exclude( ['output'], $$v{$coverage_key} ) ];
				} # end if
				if ( $type =~ /PMS/ ) {
					$inkCoverage{$$specs{'ColourCoatingColour'.$index.$side}} += $$specs{$coverage_key};
				} else {
					$inkCoverage{$type} += $$specs{$coverage_key};
				} # end if
		} # end foreach k
	} # end foreach Side
	return %inkCoverage;
} # end sub get_inkcoverage

sub get_versions {
	my ( $specs, $qty_index ) = @_;
	my @versions;
	foreach my $version ( 1 .. $$specs{versions} ) {
		push @versions, 
			 {
				 index 		=> $version,
				 description	=> $$specs{"version-$version-description"},
				 quantity		=> $$specs{"version-$version-quantity$qty_index"},
			 };
	} # end foreach version
	@versions = sort { $$a{quantity} <=> $$b{quantity} } @versions;
	return @versions;
} # end sub get_versions

sub get_Stocks {
	my ( $Project, $specs, $v ) = @_;
	$v = \%variables if ! $v;

	my @Papers;
	if ( $$specs{rdbSpecificStock} eq 'Y' ) {
		if ( ! $$specs{txtSpecificStockCalliper} ) {
			$$specs{alert} .= 'Please enter the stock calliper';
			return @Papers;
		} # end if
		if ( ! $$specs{CustomStockPrice} ) {
			$$specs{alert} .= 'Please enter the stock cost in order to achieve an accurate imposition.';
			# Maybe don't need to return... since it can calculate... although the result will likely be bizarre
			#return @Papers;
		} # end if
		if ( ( ! $$specs{StockGrade} ) and $$specs{txtSpecificStockFinish} ) {
			if ( $$specs{txtSpecificStockFinish} =~ /gloss/i ) {
				$$specs{StockGrade} = 1;
			} elsif ( $$specs{txtSpecificStockFinish} =~ /matte/i ) {
				$$specs{StockGrade} = 2;
			} elsif ( $$specs{txtSpecificStockFinish} =~ /offset/i ) {
				$$specs{StockGrade} = 4;
			} else {
				$$specs{StockGrade} = 3;
			} # end if
			$$v{StockGrade} = [ sets::union( 'output', @{$$v{StockGrade}} ) ];
		} else {
			$$v{StockGrade} = [ sets::exclude( ['output'], $$v{StockGrade} ) ];
		} # end if
		if ( ! $$specs{StockGrade} ) {
			$$specs{alert} .= 'Please select the grade of stock';
			return @Papers;
		} # end if
		$$specs{StockType} =~ s/^\s*(\w*)\s*$/$1/;
		if ( ! $$specs{StockType} ) {
			$$specs{alert} .= 'Please select the stock format';
			return @Papers;
		} elsif ( $$specs{StockType} eq 'Roll' ) {
			if ( ! $$specs{txtStockGSM} ) {
				$$specs{alert} .= 'Please enter the stock gsm';
				return @Papers;
			} # end if

		} elsif ( $$specs{StockType} eq 'Sheet' ) {
			if ( ! ( $$specs{txtCustomMWeight} or $$specs{txtStockGSM} ) ) {
				$$specs{alert} .= 'Please enter the stock mweight or gsm';
				return @Papers;
			} # end if
			if ( ! $$specs{txtSpecificStockWidth} ) {
				$$specs{alert} .= 'Please enter the width of the stock';
				return @Papers;
			} # end if
			if ( ! $$specs{txtSpecificStockHeight} ) {
				$$specs{alert} .= 'Please enter the height of the stock';
				return @Papers;
			} # end if
		} # end if
    if ($$specs{txtSpecificStockWeight} and ($$specs{txtSpecificStockWeight} =~ /(\d+)\s?pt/i)) {
      if ($$specs{txtSpecificStockCalliper} != $1/1000) {
        $$specs{alert} .= "Is your calliper correct? $$specs{txtSpecificStockCalliper} != $$specs{txtSpecificStockWeight}<br/>";
      }
    }
		my $Paper = openprint::Paper::load_from_signature( $Project, $specs );
#$log->debug( $Paper->id_string() );
		push @Papers, $Paper;
		foreach my $k ( 'txtSpecificStockCalliper', 'txtSpecificStockWidth','txtSpecificStockHeight','txtCustomMWeight','txtCustomStockPrice', 'txtStockGSM','txtSpecificStockBrand','txtSpecificStockFinish','txtSpecificStockColour','txtSpecificStockWeight' ) {
			$$v{$k} = [ sets::exclude( ['output'], $$v{$k} ) ];
		} # end foreach
		if ( ( ! $$specs{txtCustomMWeight} and $Paper->gsm() ) ) {
			$$v{txtCustomMWeight} = [ sets::union( 'output', @{$$v{txtCustomMWeight}} ) ];
			$$specs{txtCustomMWeight} = $Paper->mweight();
		} # end if
		if ( ( ! $$specs{basis_mweight} and $Paper->gsm() ) ) {
			$$v{basis_mweight} = [ sets::union( 'output', @{$$v{basis_mweight}} ) ];
			$$specs{basis_mweight} = $Paper->basis_mweight();
		} elsif ( $$v{basis_mweight} and( @{$$v{basis_mweight}} > 1 ) ) {
			# Always has save
			$$v{basis_mweight} = [ sets::exclude( ['output'], $$v{basis_mweight} ) ];
		} # end if
		if ( ! $$specs{txtStockGSM} ) {
			$$v{txtStockGSM} = [ sets::union( 'output', @{$$v{txtStockGSM}} ) ];
			$$specs{txtStockGSM} = $Paper->gsm();
		} # end if
		if ( $$specs{txtStockGSM} < 10 ) {
			$$specs{alert} .= 'GSM is too low.';
			return ();
		} # end if
		if ( int($Paper->gsm()) != int($Paper->gsm(undef)) ) {
			$$specs{alert} .= "GSM ($$specs{txtStockGSM}) and calculated gsm ($$Paper{gsm}) are different.  Please double check that everything is ok.";
			#return ();
		}
	} else {
		$$v{txtStockGSM} = [ sets::union( 'output', @{$$v{txtStockGSM}} ) ];

		my $project_type_name = $Project->Type()->name();
		my @StockOptions = misc::trim(split(',', $openprint::config{$project_type_name.'StockOptions'} )) if $openprint::config{$project_type_name.'StockOptions'};
		@StockOptions = misc::trim(split (',', $openprint::config{StockOptions} )) if ( ! @StockOptions ) and $openprint::config{StockOptions};
		@StockOptions = ( 'Brand','Finish','Colour','Weight' ) if ! @StockOptions;

		my @RequiredStockOptions = misc::trim(split (',', $openprint::config{$project_type_name.'RequiredStockOptions'} )) if $openprint::config{$project_type_name.'RequiredStockOptions'};
		@RequiredStockOptions = misc::trim(split (',', $openprint::config{RequiredStockOptions} )) if ( ! @RequiredStockOptions ) and $openprint::config{RequiredStockOptions};
		@RequiredStockOptions = @StockOptions if ! @RequiredStockOptions;

		foreach my $option ( @RequiredStockOptions ) {
			if ( ! $$specs{'ddmStock'.$option} ) {
				$$specs{alert} .= 'Please select a stock ' . lc $option.'<br/>';
				return @Papers;
			} # end if
		} # end foreach option
		if ( $$specs{ddmStockSheetSize} ) {
			@$specs{'ddmStockWidth','ddmStockHeight'} = $$specs{ddmStockSheetSize} =~ /^([\d\.]+)"?\s*x?\s*([\d\.]+)?"?\s*$/;
		} elsif ( $$specs{ddmStockSize} ) {
			@$specs{'ddmStockWidth','ddmStockHeight'} = $$specs{ddmStockSize} =~ /^([\d\.]+)"?\s*x?\s*([\d\.]+)?"?\s*$/;
		}
		@Papers = openprint::Paper->find( 
				( $$specs{ddmStockGroup} ? ( group=> $$specs{ddmStockGroup} ) : () ),
				( $$specs{ddmStockBrand} ? ( brand=> $$specs{ddmStockBrand} ) : () ),
				( $$specs{ddmStockFinish} ? ( finish=>$$specs{ddmStockFinish} ) : () ),
				( $$specs{ddmStockColour} ? ( colour=>$$specs{ddmStockColour} ) : () ),
				( $$specs{ddmStockWeight} ? ( weight=>$$specs{ddmStockWeight} ) : () ),
				( $$specs{ddmStockQuality} ? ( quality=>$$specs{ddmStockQuality} ) : () ),
				( exists $$specs{ddmStockWidth} ? ( width=>$$specs{ddmStockWidth} ) : () ),
				( exists $$specs{ddmStockHeight} ? ( height=>$$specs{ddmStockHeight} ) : () ),
				'project_type_id any'=>$Project->type_id(),
				( ( $openprint::usergroup::groups_cache{'Roll Estimating'} and ! $openprint::User->in_Group('Roll Estimating') ) ? ( type=>'Sheet' ) : () ),
				);
		if ( !@Papers ) {
			$log->warn('no papers');
			$$specs{alert} .= 'Unable to find any stocks matching your specifications.<br/>';
			return @Papers;
		} elsif ( DEBUG ) {
			$log->debug('Got for papers: ' . @Papers);
		} # end if

		# Load this here, so that later cloning will copy the prices as well.
		if ( @Papers ) {
			my %PaperPrices = misc::make_hash_from_array('paper_id',
					openprint::PaperPrice->find(paper_id=>[ map { $$_{id} } @Papers ]) );
			
			foreach my $P ( @Papers ) {
				$$P{Supplied} = $P;
				if ( $PaperPrices{$$P{id}} ) {
					$P->Prices($PaperPrices{$$P{id}});
				} else {
					$openprint::log->warn('No prices for ' . $P->to_string());
				}
			} # end foreach

			@$specs{'txtSpecificStockBrand','txtSpecificStockFinish','txtSpecificStockColour','txtSpecificStockWeight','StockGrade','txtSpecificStockCalliper'} = $Papers[0]->get('brand','finish','colour','weight','grade', 'calliper');
		} # end if Papers
		foreach my $k ( 'txtSpecificStockCalliper', 'txtSpecificStockWidth','txtSpecificStockHeight','txtCustomMWeight','txtCustomStockPrice', 'txtStockGSM','txtSpecificStockBrand','txtSpecificStockFinish','txtSpecificStockColour','txtSpecificStockWeight','StockGrade' ) {
			$$v{$k} = [ sets::union( 'output', @{$$v{$k}} ) ];
		} # end foreach
	} # end if Specific stock

	if ( ! @Papers ) {
		$$specs{alert} .= 'There was a problem loading the specified paper.';
	} # end if

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		next if ! $$specs{'chkOverrideSheetSize'.$qty_index};

		if (!($$specs{'OverrideStockWidth'.$qty_index} or $$specs{'OverrideStockHeight'.$qty_index})) {
			@$specs{'OverrideStockWidth'.$qty_index, 'OverrideStockHeight'.$qty_index} = split( 'x', $$specs{'ddmStockSheetSize'.$qty_index} );
$log->debug('size: ' . $$specs{'ddmStockSheetSize'.$qty_index} . ' width: ' . $$specs{'OverrideStockWidth'.$qty_index} . ' height: ' . $$specs{'OverrideStockHeight'.$qty_index} ) if DEBUG;
		} # end if
		my $found = 0;

		# The reason for the reverse is that if we have already added a stock, then we will find it slightly quicker.
		foreach my $P ( reverse @Papers ) {
      #$log->debug("Paper $qty_index " . $P->width() .'x'.$P->height() . ' ' . "$$specs{'OverrideStockWidth'.$qty_index }x$$specs{'OverrideStockHeight'.$qty_index}" );
			if ( $P->width() == $$specs{'OverrideStockWidth'.$qty_index} and $P->height() == $$specs{'OverrideStockHeight'.$qty_index} ) {
        #$log->debug('found it'); 
				$found = 1;
				# Don't need to add it, because it's already in @Papers
				last;
			} # end if
		} # end foreach

		if ( ! $found ) {
			# Find ones that are an even cut
			my @Pblah = @Papers;	
			foreach my $P ( @Pblah ) {
				next if ! $P->cuttable();
				
				my $width_factor1 = $$P{start_width} / $$specs{'OverrideStockWidth'.$qty_index} if $$specs{'OverrideStockWidth'.$qty_index};
				my $height_factor1 = $$P{start_height} / $$specs{'OverrideStockHeight'.$qty_index} if $$specs{'OverrideStockHeight'.$qty_index};

				if ( $$P{type} eq 'Roll' ) {
					next if $$specs{'OverrideStockHeight'.$qty_index};
					next if $$P{start_width};
				} elsif ( $$P{type} eq 'Sheet' ) {
# Don't cut sheets into rolls
					next if ! $$specs{'OverrideStockHeight'.$qty_index};
					next if ! $$specs{'OverrideStockWidth'.$qty_index};
if ( 1 ) {
					my $width_factor2 = $$P{start_height} / $$specs{'OverrideStockWidth'.$qty_index};
					my $height_factor2 = $$P{start_width} / $$specs{'OverrideStockHeight'.$qty_index};
					if ( ! (
								( $width_factor1 == int($width_factor1) and $height_factor1 == int($height_factor1) ) or
								( $width_factor2 == int($width_factor2) and $height_factor2 == int($height_factor2) )
							) ) {
						$log->debug("No good: $qty_index " . $P->to_string() . ' '. ($$P{start_width} % $$specs{'OverrideStockWidth'.$qty_index}) . 'x' . ($$P{start_height} % $$specs{'OverrideStockHeight'.$qty_index} ) );

						next;
					} # end if
} else {
					if ( ! ( $width_factor1 == int($width_factor1) and $height_factor1 == int($height_factor1) ) ) {
						next;
					} # end if
}
				} # end if
				$found = 1;
$log->debug( 'Found stock to cut: ' . $P->id_string() . ' for ' . $$specs{'OverrideStockWidth'.$qty_index} . 'x' . $$specs{'OverrideStockHeight'.$qty_index} );
				my $P2 = $P->clone();
# Make sure gsm has calculated
				$P2->gsm();
				if ( ( $width_factor1 == int($width_factor1) and $height_factor1 == int($height_factor1) ) ) {
					# Fits normally
				} else {
					# Is a rotation, because we reject any stock that doesn't cut nicely one way or the other.
					$P2->grain_direction( $P2->grain_direction() eq 'width' ? 'height' : 'width' );
				} # end if
				$P2->width( $$specs{'OverrideStockWidth'.$qty_index} );
				$P2->height( $$specs{'OverrideStockHeight'.$qty_index} );
				if ( $P2->type() ne 'Roll' ) {
					$P2->mweight( 0 );
				} else {
					$$P2{start_width} = $$specs{'OverrideStockWidth'.$qty_index};
				} # end if
				push @Papers, $P2;
			} # end foreach Paper
		} # end if found

		if ( !$found ) {
$log->debug('No well cut Stock found how many papers to consider: ' . scalar @Papers ) if DEBUG;
			my @cut_Papers;
			foreach my $P ( @Papers ) {
$log->debug('Considering: ' . $P->id_string() ) if DEBUG;
# Don't cut rolls into sheets
				next if ! $P->cuttable();
				if ( $$P{type} eq 'Roll' ) {
					next;
				} elsif ( $$P{type} eq 'Sheet' ) {
# Don't cut sheets into rolls
					next if ! $$specs{'OverrideStockHeight'.$qty_index};
# Must be big enough to cut
					next if ( ! ( 
								( $P->start_width() >= $$specs{'OverrideStockWidth'.$qty_index} and $P->start_height() >= $$specs{'OverrideStockHeight'.$qty_index} )
                #or 
                #( $P->start_width() >= $$specs{'OverrideStockHeight'.$qty_index} and $P->start_height() >= $$specs{'OverrideStockWidth'.$qty_index} )
								) );

				} else {
					$log->error('WTF Type of Stock? '.$$P{type});
					next;
				} # end if
				my $P2 = $P->clone();

# Make sure gsm has calculated
				$P2->gsm();
				$P2->width( $$specs{'OverrideStockWidth'.$qty_index} );
				$P2->height( $$specs{'OverrideStockHeight'.$qty_index} );
				if ( $P2->type() ne 'Roll' ) {
					$P2->mweight( 0 );
				} else {
					$$P2{start_width} = $$specs{'OverrideStockWidth'.$qty_index};
				} # end if
				push @cut_Papers, $P2;
				$found = 1;
			} # end foreach paper
			if ( ! $found ) {
				# Can happen as you type in the sheet size
				$log->debug('Never found a stock') if DEBUG;
			} else {
				$log->debug('Have a stock') if DEBUG;
			} # end if
			push @Papers, @cut_Papers;
		} # end if found

	} # end foreach qty_index

	foreach my $P ( @Papers ) {
		#$P->Prices();
		$log->debug('Base Paper: ' . $P->to_string() . ' Minimum: ' . $P->minimum_order() ) if DEBUG_STOCK;
		$Papers{$P->id_string()} = $P->clone() if $P->width();
	} # end foreach

	return map { $_->clone() } @Papers;
} # end sub get_Stocks

sub get_impositions {
	my ( $Project, $specs, $project, $qty, $qty_index, $Presses, $Papers, $Overrides ) = @_;
	my %impositions;

	if ( $$specs{'OverridePrintingType'.$qty_index} and ( $$specs{'OverridePrintingType'.$qty_index} eq 'Y' ) ) {
		$variables{'PrintingType'.$qty_index} = [ sets::exclude( ['output'], $variables{'PrintingType'.$qty_index} ) ];
	} else {
		$variables{'PrintingType'.$qty_index} = [ sets::union( 'output', @{$variables{'PrintingType'.$qty_index}} ) ];
	} # end if
	$$project{txtSpreadSize} = $$specs{txtSpreadSize};
	my $ProjectTypeName = $Project->Type()->name();
	$$project{Quantity} = $qty;

	# This is interesting
	if ( $openprint::session{user_type} eq 'A' or $openprint::session{user_type} eq 'E' ) {
		if ( $$specs{'chkOverrideRunStyle'.$qty_index} ) {
			$$project{OverrideRunStyle} = $$specs{'ddmRunStyle'.$qty_index} 
		} # end if
		if ( $$specs{'chkOverrideImposition'.$qty_index} ) {
			$$project{OverrideImposition} = $$specs{"txtImposition".$qty_index};
		} # end if
	} # end if

# add all the impositions for each press
$log->debug('get_impositions: Presses to consider: ' . join(',', map { $$_{strid} } @$Presses)) if DEBUG_IMPOSITIONS;
	foreach my $Press ( @$Presses ) {
		if ( DEBUG_IMPOSITIONS and $$specs{'chkOverridePress'.$qty_index} and $$specs{"ddmPress$qty_index"} ) {
			if ( $$specs{"ddmPress$qty_index"} ne $$Press{strid} ) {
$log->debug("Skipping cuz ddmPress$qty_index ne $$Press{strid}");
				next;
			} else {
$log->debug("not Skipping cuz ddmPress$qty_index eq $$Press{strid}");
			} 
		} # end if
		my $printing_type = $Press->specification('Printing Type');
		if ( ( $$project{ProjectSpecs}{"PrintingType-$$specs{Group}"} ) and ( $$project{ProjectSpecs}{"PrintingType-$$specs{Group}"} ne $printing_type ) ) {
			$log->warn("QTY $qty_index Press $$Press{strid} Printing Type ($printing_type) is not the book overriden type " . $$project{ProjectSpecs}{"PrintingType-$$specs{Group}"} ) if DEBUG_IMPOSITIONS;
			next;
		} # end if

		if ( ( defined $$specs{'OverridePrintingType'.$qty_index} ) and ( $$specs{'OverridePrintingType'.$qty_index} eq 'Y' ) ) {
			if ( $printing_type ne $$specs{'PrintingType'.$qty_index} ) {
				$log->warn("QTY $qty_index Press $$Press{strid} Printing Type ($printing_type) is not the overriden type " . $$specs{'PrintingType'.$qty_index} ) if DEBUG_IMPOSITIONS;
				next;
			} else {
				$log->warn("QTY $qty_index Press $$Press{strid} Printing Type ($printing_type) IS the overriden type " . $$specs{'PrintingType'.$qty_index} ) if DEBUG_IMPOSITIONS;
			} # end if
    } elsif ( $$project{ProjectSpecs}{"PrintingType-$$specs{Group}"} and ( $$project{ProjectSpecs}{"PrintingType-$$specs{Group}"} eq $printing_type) ) {
      $log->warn("QTY $qty_index Press $$Press{strid} Printing Type ($printing_type) IS the overriden type " . $$project{ProjectSpecs}{'PrintingType-'.$$specs{Group}} ) if DEBUG_IMPOSITIONS;
		} else {
      # FIXME, fix what?
      #$log->error("For press $$Press{strid} $printing_type ".join(',', $$specs{PrintingTypes} ? @{$$specs{PrintingTypes}} : ('none') ));
			if ( $$specs{PrintingTypes} and $printing_type and ! sets::isin( $printing_type, $$specs{PrintingTypes} ) ) {
				if ( $$specs{'chkOverridePress'.$qty_index} and ( $$specs{'ddmPress'.$qty_index} eq $$Press{strid} ) ) {
					$$specs{alert} .= 'Press ' . $$Press{strid} . " Printing Type ($printing_type) is not in PrintingTypes	". join(',', @{$$specs{PrintingTypes}} ) . '<br/>';
          next;
        } elsif ( $$project{ProjectSpecs}{"ddmPress-$$specs{Group}"} and ( $$project{ProjectSpecs}{"ddmPress-$$specs{Group}"} eq $$Press{strid} ) ) {
					$$specs{alert} .= 'Press ' . $$Press{strid} . " Printing Type ($printing_type) is not in PrintingTypes	". join(',', @{$$specs{PrintingTypes}} ) . '<br/>';
				} elsif ( $$specs{'OverridePrintingType'.$qty_index} and ( $printing_type eq $$specs{'PrintingType'.$qty_index} ) ) {
					$$specs{alert} .= 'Press ' . $$Press{strid} . " Printing Type ($printing_type) is not in PrintingTypes	". join(',', @{$$specs{PrintingTypes}} ) . '<br/>';
				} else {
          $log->debug("Skipping $$Press{strid} because of printintype") if DEBUG_IMPOSITIONS;
					next;
				} # end if
			} # end if
		} # end if
# If we have a plate type override, then make sure that this press can do it.
		if ( $$specs{'chkOverridePlateType'.$qty_index} and ( $Press->specification('Plate Type') ne $$specs{'rdbPlateType'.$qty_index} ) ) {
			$log->warn("Press Plate Type ");
			next;
		} # end if
    if (!$$project{HasFolding}) {
      my $sheeter = $Press->specification('Sheeter');
      if ($sheeter and ($sheeter ne 'Y')) {
        $log->error("No Sheeter on $$Press{strid} ".(defined $sheeter?$sheeter :'undef'));
        next;
      }
		} # end if

		my @side_one_colours = @{$$project{side_one_colours}};
		my @side_two_colours = @{$$project{side_two_colours}};
		# If we need a varnish, varnish can be done inline if the press has enough units, or in a second pass.	
		# The second pass requires washes for all other units as a second pass, so that tends to be not likely.
		my @side_one_varnishes = map { ( $$_{name} =~ /Varnish/ ) ? $$_{name} : () } ( @{$$project{side_one_coatings}}, @{$$project{side_one_colours}} );
		my @side_two_varnishes = map { ( $$_{name} =~ /Varnish/ ) ? $$_{name} : () } ( @{$$project{side_two_coatings}}, @{$$project{side_two_colours}} );
		my $varnish_capable = $Press->specification('Varnish Capable');

		my @side_one_aq = map { ( $$_{name} =~ /Aqueous/ ) ? $$_{name} : () } ( @{$$project{side_one_coatings}}, @{$$project{side_one_colours}} );
		my @side_two_aq = map { ( $$_{name} =~ /Aqueous/ ) ? $$_{name} : () } ( @{$$project{side_two_coatings}}, @{$$project{side_two_colours}} );
		my $aq_capable = $Press->specification('Aqueous Capable');

		if ( 0 ) {
			if ( $varnish_capable eq 'Y' ) {
				push @side_one_colours, @side_one_varnishes;
				push @side_two_colours, @side_two_varnishes;
			} elsif ( $varnish_capable eq '1 Side' ) {
				push @side_one_colours, @side_one_varnishes;
				push @side_two_colours, @side_two_varnishes;
			} # end if
		}
		if ( 0 ) {
			$log->debug("$$Press{strid} Side One varnishes @side_one_varnishes");
			$log->debug("$$Press{strid} Side Two varnishes @side_two_varnishes");
			$log->debug("$$Press{strid} Side One colours @side_one_colours");
			$log->debug("$$Press{strid} Side Two colours @side_two_colours");
		} # end if
		my $number_of_colours = $Press->specification('Number of Colours');
		$$project{Runstyles} = $Press->specification('Runstyles');
		if ( ! $$project{Runstyles} ) {
			$log->warn("No runstyles set on $$Press{strid}, defaulting to sheet work");
      $$project{Runstyles} = 'Sheet Work';
		}
    %{$$project{RunstylesHash}} = map { $_ => $_ } split(',',$$project{Runstyles});
    foreach my $style ( keys %{$$project{RunstylesHash}}) {
      if (!sets::isin($style, $Specifications{Runstyles}{values})) {
        $$specs{alert} .= 'Invalid runstyle for '.$Press->name().' '.$style.'. Valid values are:'.join(',', @{$Specifications{Runstyles}{values}}).'<br/>';
      }
    }
		if (DEBUG_IMPOSITIONS and $$specs{"chkOverrideRunStyle$qty_index"}) {
      if (!$$project{RunstylesHash}{$$specs{"ddmRunStyle$qty_index"}}) {
        $log->warn("Press $$Press{strid} does not do ".$$specs{"ddmRunStyle$qty_index"});
        next;
      }
			$$project{Runstyles} = $$specs{"ddmRunStyle$qty_index"};
		} 
# This perfecting stuff: default to on, turn off if press can't do it, or the job is single sided.
		my $do_perfecting = 1;
		if ( $$project{print_sides} == 1 ) {
			$do_perfecting = 0;
			$log->debug("** One sided:	Perfect	***") if DEBUG_IMPOSITIONS;
		} elsif ( 
				( (!($number_of_colours%2)) and ( (@side_one_colours > int($number_of_colours/2)) or (@side_two_colours > int($number_of_colours/2)) ) )
				or
				( ($number_of_colours%2) and ( (@side_one_colours > int($number_of_colours/2)+1) or (@side_two_colours > int($number_of_colours/2)+1) ) )
				or ( @side_one_colours == int($number_of_colours/2)+1 and @side_two_colours == int($number_of_colours/2)+1 )
				) {
			$log->debug("** Too many colours to Perfect on $$Press{strid} $number_of_colours @side_one_colours, @side_two_colours***") if DEBUG_IMPOSITIONS;
			$do_perfecting = 0;
		} elsif ( ! sets::isin('Perfecting', [ split(',',$$project{Runstyles} ) ] ) ) {
			$log->debug("** $$Press{strid} Can't Perfect - Perfecting not in runstyles ***") if DEBUG_IMPOSITIONS;
			$do_perfecting = 0;
		} elsif ( @side_one_varnishes or @side_two_varnishes  ) {
			if ( ( $varnish_capable eq '1 Side' ) and (
				( ! ( @side_one_varnishes and @side_two_varnishes ) ) and 
				( ( @side_one_colours - @side_one_varnishes ) <= int($number_of_colours/2) ) and 
				( ( @side_two_colours - @side_two_varnishes ) <= int($number_of_colours/2) ) ) 
			) {
				$log->debug("** Can do 1 sided varnish perfecting but @side_one_varnishes @side_two_varnishes ***");
			} else {
				#$log->debug(( @side_one_colours - @side_one_varnishes ) . ' <= ' . int($number_of_colours/2)) if DEBUG;
				#$log->debug(( @side_two_colours - @side_two_varnishes ) . ' <= ' . int($number_of_colours/2)) if DEBUG;
				$log->debug("** Too many colours to	Perfect	***") if DEBUG_IMPOSITIONS;
				$do_perfecting = 0;
			} 
		} elsif (@side_one_aq or @side_two_aq) {
			if ( @side_one_aq and @side_two_aq and ! $Press->specification('Aqueous Double Sided When Perfecting') ) {
        $log->debug("** Too many aq colours to Perfect ***") if DEBUG_IMPOSITIONS;
        $do_perfecting = 0;
			} elsif ( 
					( ( @side_one_colours - @side_one_aq ) > int($number_of_colours/2) ) or
					( ( @side_two_colours - @side_two_aq ) > int($number_of_colours/2) ) )
			{
				$log->debug("** Too many aq colours to Perfect ***") if DEBUG_IMPOSITIONS;
				$do_perfecting = 0;
      }

		} elsif ( ( $_ = $Press->specification('Maximum Calliper Perfecting') ) and ( $$specs{txtSpecificStockCalliper} > $_ ) ) {
			$do_perfecting = 0;
			$log->debug("** Too thick to:	Perfect	***") if DEBUG_IMPOSITIONS;
		} # end if

		my $do_work_turn = $$project{print_sides} == 2 ? 1 : 0;
    $openprint::log->debug("Do W&T $do_work_turn because sides: $$project{print_sides}");
		if ( $do_work_turn ) {
# Coatings like AQ are done in a separate pass.	So we don't count them in this check
			if ( ! $$Papers[0]->doublesided() ) {
				$log->debug('No W&T due to doublesided' . $$Papers[0]->brand() );
				$do_work_turn = 0;
			} elsif ( $$project{filtered_colours}
					and ( @{$$project{filtered_colours}} > $number_of_colours )
					and ( $Press->specification('Multipass', $$Papers[0]->gsm() ) ne 'Y' ) ) {
				$log->debug("No W&T on $$Press{strid} due to multipass colors:".(scalar@{$$project{filtered_colours}})." > $number_of_colours " . $$Papers[0]->gsm() );
				$do_work_turn = 0;
			} elsif ( $$specs{sides_the_same} eq 'Y' ) {
        if (
          ($$specs{chkOverrideRunStyle1} and $$specs{chkOverrideRunStyle1} eq 'Y')
            or
          ($$specs{chkOverrideRunStyle2} and $$specs{chkOverrideRunStyle2} eq 'Y')
            or
          ($$specs{chkOverrideRunStyle3} and $$specs{chkOverrideRunStyle3} eq 'Y')
        ) {

        } else {
          # No point in doing W&T, should just do sheetwork
          $do_work_turn = 0;
        }
			} # end if
		} # end if

# not all of the presses have a gutter spec so we will continue to use Grip for Width and Height
		if ( ! sets::isin( $ProjectTypeName, [ 'Envelopes', 'NCR' ] ) ) {
			$$project{Grip} = $Press->specification('Grip') if ! $$specs{OverrideAddGrip};
			$$project{Gutter} = $Press->specification('Gutter') if ! $$specs{OverrideAddGrip};
			if ( $$specs{'chkOverrideBleedSize'.$qty_index} ) {
				$$project{BleedSize} = $$specs{'ddmBleedSize'.$qty_index};
				$variables{'ddmBleedSize'.$qty_index} = [ sets::exclude( ['output'], $variables{'ddmBleedSize'.$qty_index} ) ];
			} else {
				$$project{BleedSize} = $Press->specification('Default Bleed Size'.$ProjectTypeName );
				$$project{BleedSize} = $Press->specification('Default Bleed Size' ) if ! $$project{BleedSize};
				$variables{'ddmBleedSize'.$qty_index} = [ sets::union( 'output', @{$variables{'ddmBleedSize'.$qty_index}} ) ];
			} # end if

# PMS
			if ( ! $$specs{rdbColourBar} ) {
				if ( @{$$project{non_process_colours}} ) {
					$$project{'Add Colour Bar'} = $Press->specification('Colour Bar Default');
				} else {
					$$project{'Add Colour Bar'} = $Press->specification('Process Colour Bar Default');
				} # end if
        $$project{'Add Colour Bar'} = 'Y' if ! $$project{'Add Colour Bar'}; # default to on
			} # end if
			if ( $$project{'Add Colour Bar'} and ( $$project{'Add Colour Bar'} eq 'Y' ) ) {
				if ( @{$$project{non_process_colours}} ) {
					$$project{colour_bar_size} = $Press->specification('Colour Bar Size');
				} else {
					$$project{colour_bar_size} = $Press->specification('Process Colour Bar Size');
					if ( !$$project{colour_bar_size} ) {
						$$project{colour_bar_size} = $Press->specification('Colour Bar Size');
					}
				} # end if
				$$project{Perfecting_colour_bar_size} = $Press->specification('Perfecting Colour Bar Size');
        $$project{Perfecting_colour_bar_size} = $$project{colour_bar_size} if !$$project{Perfecting_colour_bar_size};
			} else {
				$$project{colour_bar_size} = 0;
			} # end if
			$$project{'Colour Bar Orientation'} = $Press->specification('Colour Bar Orientation');
			if ( $do_perfecting ) {
				$$project{'Perfecting Single Gutter Size'} = $Press->specification('Perfecting Single Gutter Size');
				$$project{'Perfecting Double Gutter Size'} = $Press->specification('Perfecting Double Gutter Size');
			} # end if
		} else {
			$$project{colour_bar_size} = 0;
		} # end if Envelopes
		$$project{Orientation} = $Press->specification('Orientation');
    if (!$$project{Orientation}) {
      my $max_image_width = $Press->specification('Maximum Image Width');
      my $max_image_length = $Press->specification('Maximum Image Length');
      if ($max_image_width and $max_image_length) {
        if ($max_image_width > $max_image_length) {
          $$project{Orientation} = 'Landscape';
        } else {
          $$project{Orientation} = 'Portrait';
        }
      }
    } # end if ! orientation
		$$project{dutch} = 1; # default to on
		if ( $$specs{"dutch$qty_index"} and ( $$specs{"dutch$qty_index"} eq 'N' ) ) {
			$$project{dutch} = 0;
		} elsif ( $_ = $Press->Specification('Dutch') and $$_{value} eq 'N' ) {
			$$project{dutch} = 0;
		} elsif ($$specs{txtSignatureType} or $$project{HasDieCutting} or $$project{HasPerforating} or $$project{HasScoring}) {
			$$project{dutch} = 0;
		} # end if
		$$project{PerfectingDutchByDefault} = $Press->specification('PerfectingDutchByDefault');

		my @impositions;

		$_ = $Press->specification('Use Cut Stocks');
#$log->debug($$Press{strid} . ' Use cut stocks: ' . $_ );
		my $use_cut_stocks = ( $_ and ( $_ eq 'N' ) ) ? 0 : 1;
		my $co = $Press->specification('Cut Off');
		my @cut_offs;
		if ( $co ) {
			@cut_offs = reverse sort split( ',', $co );
		} elsif ( my $min = $Press->specification('Cut Off Minimum') ) {
			my $increment = $Press->specification('Cut Off Increment');
			my $cut_off = $Press->specification('Cut Off Maximum');
			while ( $cut_off >= $min ) {
				push @cut_offs, $cut_off;
# Neccessary due to floating point arithmetic errors
        # # Really?  This is just add/sub.  multi/div would be a problem
        #$cut_off = Math::Round::nearest(0.00001, $cut_off - $increment );
				$cut_off = $cut_off - $increment;
			} # end while cutoff > min
		} # end if
$log->debug("Cut Offs for Press $$Press{strid} @cut_offs");
		my %feeds = map { $_, 1 } split(',',$_ ) if $_ = $Press->specification('Feed');
		$$Press{Feeds} = \%feeds;
		my $maximum_sheet_width = $Press->specification('Maximum Sheet Width') or 0;
		my $maximum_sheet_length = $Press->specification('Maximum Sheet Length');
		my $minimum_sheet_width = $Press->specification('Minimum Sheet Width');
		my $minimum_sheet_length = $Press->specification('Minimum Sheet Length');
		my $maximum_roll_width = $Press->specification('Maximum Roll Width');
		my $minimum_roll_width = $Press->specification('Minimum Roll Width');
		my $runstyles = $Press->specification('Runstyles');
		my $runstyles_roll = $Press->specification('RunstylesRoll');
		$runstyles_roll = $runstyles if ! $runstyles_roll;
		my $runstyles_sheet = $Press->specification('RunstylesSheet');
		$runstyles_sheet = $runstyles if ! $runstyles_sheet;
if ( DEBUG_IMPOSITIONS and $$specs{"chkOverrideRunStyle$qty_index"} ) {
	$runstyles_sheet = $runstyles_roll = $runstyles = $$specs{"ddmRunStyle$qty_index"};
}
		my $roll2sheet_minimum_weight = $Press->Specification('Roll2Sheet Minimum Weight');

		my %sheetsizes;
		my @Papers = @{$Papers};

		if ( my $sheets = $Press->specification('SheetSizes') ) {
			my @Sheets = map { $_->type eq 'Roll' ? () : $_ } @Papers;
			my %available_sheets;
			foreach my $Paper ( @Sheets ) {
				$available_sheets{join('x',$Paper->width(),$Paper->height())} = 1;
			} # end foreach Paper
			my @extra_sheets;

			my @sheets = split(',', $sheets );
			foreach my $sheet ( @sheets ) {
				my ( $width, $height ) = split('x', $sheet);
				$sheetsizes{$sheet} = 1;
				$sheetsizes{join('x',$height,$width)} = 1;
				if ( ! $available_sheets{$sheet} ) {
					foreach my $Paper ( @Sheets ) {
						next if ! $Paper->cuttable();
						next if $Paper->width() < $width;
						next if $Paper->height() < $height;
						my $P = $Paper->clone();
						$P->cut( $width, $height );
						push @extra_sheets, $P;
						$Papers{$P->id_string()} = $P->clone() if ! $Papers{$P->id_string()};
					} # end foreach P
					$available_sheets{$sheet} = 1;
				} # end if
				if ( ! $available_sheets{join('x',$height,$width)} ) {
					foreach my $Paper ( @Sheets ) {
						next if ! $Paper->cuttable();
						next if $Paper->width() < $height;
						next if $Paper->height() < $width;
						my $P = $Paper->clone();
						$P->cut( $height, $width );
						push @extra_sheets, $P;
						$Papers{$P->id_string()} = $P->clone() if ! $Papers{$P->id_string()};
					} # end foreach P
					$available_sheets{join('x',$height,$width)} = 1;
				} # end if
			} # end foreach
			push @Papers, @extra_sheets;
			if ( 0 and DEBUG_IMPOSITIONS ) {
				foreach my $P ( @extra_sheets ) {
					$log->debug("Extra: " . $P->to_string() );
				} # end foreach P
				foreach my $P ( @{$Papers} ) {
					$log->debug("Sheets " . $P->to_string() );
				} # end foreach P
			} # end if DEBUG
		} # end if
    if ( 0 and DEBUG_IMPOSITIONS ) {
      foreach my $P ( @Papers ) {
        $log->debug("Stocks: " . $P->to_string() );
      } # end foreach P
    } 
		my %imps;
		foreach my $Paper ( @Papers ) {
#Paper might have different calliperso# Is this needed anymore
			#$$project{Calliper} = $$Paper{calliper};
			if (DEBUG_IMPOSITIONS and $$Overrides{"chkOverrideSheetSize$qty_index"} and $$specs{"ddmStockSheetSize$qty_index"} ) {

				my ( $width, $height ) = split('x', $$specs{"ddmStockSheetSize$qty_index"} );
				if ( $width and ( $width != $$Paper{width} ) ) {
	$log->debug("Skipping cuz not desired width: $$Paper{width}x$$Paper{height} != $width") if DEBUG_IMPOSITIONS;
					next;
				} 
				if ( $height and ( $height != $$Paper{height} ) ) {
	$log->debug("Skipping cuz not desired height $$Paper{width}x$$Paper{height} != $height") if DEBUG_IMPOSITIONS;
					next;
				} 
				$log->debug("Have acceptable sheet $width x $height") if DEBUG_IMPOSITIONS;
			} 

			if ( $$specs{Group} ) {
				if ( ( $$project{ProjectSpecs}{"StockType-$$specs{Group}"} ) and ( $$project{ProjectSpecs}{"StockType-$$specs{Group}"} ne $$Paper{type} )) {
					if ( DEBUG_IMPOSITIONS ) {
						$log->debug("Not overriden stock stype: " . $Paper->to_string() );
					} # end if
					next;
				} # end if
			} # end if
			if ( ( $$specs{'OverrideStockType'.$qty_index} and ( $$specs{'OverrideStockType'.$qty_index} eq 'Y' ) ) and ( $$Paper{type} ne $$specs{'StockType'.$qty_index} ) ) {
				if ( DEBUG_IMPOSITIONS ) {
					$log->debug("Not overriden stock stype: " . $Paper->to_string() );
				} # end if
				next;
			} # end if
			if ( $$specs{PreviousStockType} and ( $$Paper{type} ne $$specs{PreviousStockType} ) ) {
				$log->debug("Not consider paper cuz it's not the previous stock type " . $$Paper{type} .' ' .$$specs{PreviousStockType} ) if DEBUG;
				next;
			} # end if
			my @imps;

			if ( %feeds and ! $feeds{$$Paper{type}} ) {
				if ( DEBUG_IMPOSITIONS ) {
					$log->debug('Not in feeds: ' . $Paper->to_string() . ' on ' . $$Press{strid} );
				} # end if
				next;
			} # end if

			if ( $$Paper{type} eq 'Roll' ) {
				
				$$project{Runstyles} = $runstyles_roll;
				if ( $$Paper{width} ) {
					if ( $maximum_sheet_width and ( $$Paper{width} > $maximum_sheet_width ) ) {
						$log->debug("Stock width $$Paper{width} > max sheet width $maximum_sheet_width") if DEBUG_IMPOSITIONS;
						next;
					} # end if
					if ( $$Paper{width} < $minimum_sheet_width ) {
						$log->debug("Stock width $$Paper{width} < min sheet width $minimum_sheet_width") if DEBUG_IMPOSITIONS;
						next;
					} # end if
					if ( $maximum_roll_width and ( $$Paper{width} > $maximum_roll_width ) ) {
						$log->debug("Stock width $$Paper{width} > max roll width $maximum_roll_width") if DEBUG_IMPOSITIONS;
						next;
					} # end if
				} # end if
#$log->debug('blah'.$Paper->to_string());
				if ( $roll2sheet_minimum_weight and $feeds{Sheet} ) {
					if ( $$roll2sheet_minimum_weight{units} eq 'gsm' and $$roll2sheet_minimum_weight{value} > $Paper->gsm() ) {
						$log->debug("Stock gsm $$Paper{gsm} < min roll2sheet weight $$roll2sheet_minimum_weight{value}") if DEBUG_IMPOSITIONS;
						next;
					} # end if
				} # end if

				my $P = $Paper->clone();
				my @i;

				if ( @cut_offs ) {
					# We need to do some initial filtering here.	
					my %paper_impositions;
					foreach my $cut_off ( @cut_offs ) {
            if ( DEBUG_IMPOSITIONS and $$Overrides{"OverrideCutOff$qty_index"} and $$specs{"CutOff$qty_index"}
                and (0+$$specs{"CutOff$qty_index"} != 0+$cut_off)) {
              $log->debug("Next cuz Cut off $cut_off != ".$$specs{"CutOff$qty_index"} . ' '.(0+$$specs{"CutOff$qty_index"}).'!='.(0+$cut_off) . ' ' . ((0+$$specs{"CutOff$qty_index"} != 0+$cut_off)));
              next;
            } else {
              $log->debug("Not Next cuz Cut off $cut_off != ".$$specs{"CutOff$qty_index"});
						}
						$$project{'Cut Off'} = $cut_off;
						my @temp_imps = openprint::imposition::get_imposition( $project, $do_work_turn, $do_perfecting, $$specs{versions}, $P, $Press );
if ( DEBUG_IMPOSITIONS ) {
$log->error("Got " . @temp_imps . " for " . $P->to_string() );
foreach my$i( @temp_imps ) {
$i->display( 'Returned from get_imposition' );
}
}
						foreach my $i ( @temp_imps ) {
							my $AP = $$i{Paper};
							if ( $maximum_roll_width and ( $$AP{width} > $maximum_roll_width ) ) {
								$log->debug("Next due to maximum roll width $$AP{width} > $maximum_roll_width ") if DEBUG_IMPOSITIONS;
								next;
							}
#$i->display('doig');
							my $key = join( ',', @$i{'imposition','columns','runstyle','grain_direction','image_orientation'} );
							if ( ! $paper_impositions{$key} ) {
								push @{$paper_impositions{$key}}, $i;
							} else {
								my $add = 1;
								if ( ! $do_initial_filtering ) {
								} elsif ( ( defined $$specs{'OverrideCutOff'.$qty_index} ) and ( $$P{height} == $$specs{"CutOff$qty_index"} ) and ( $$specs{'OverrideCutOff'.$qty_index} eq 'Y' ) ) {
									# Shouldn't really do this here.
                  $i->display('Not adding because cut off is overriden');
								} else {
								
									my $iarea = $AP->area();
									for ( my $imp_index = 0; $imp_index < @{$paper_impositions{$key}}; $imp_index += 1 ) {
										my $j = $paper_impositions{$key}[$imp_index];
										my $B = $$j{Paper};
										next if $$AP{type} ne $$B{type};

										next if ( (defined $$specs{'OverrideCutOff'.$qty_index} ) and ( $$specs{'OverrideCutOff'.$qty_index} eq 'Y' ) and ( $$B{height} == $$specs{"CutOff$qty_index"} ) );
										my $jarea = $B->area();
										if ( $iarea < $jarea ) {
if ( DEBUG_INITIAL_FILTERING ) {
	$j->display('1 dumping');
	$i->display('1 for');
}
											splice @{$paper_impositions{$key}}, $imp_index, 1;
											$imp_index -= 1;
	#$i->display('1 for');
										} elsif ( $jarea < $iarea ) {
if ( DEBUG_INITIAL_FILTERING ) {
	$i->display('2 dumping');
	$j->display('2 for');
}
											$add = 0;
											last;
										} # end if
									} # end for
								} # end if
								if ( $add ) {
									push @{$paper_impositions{$key}}, $i;
									$Papers{$P->id_string()} = $P->clone() if ! $Papers{$P->id_string()};
								} # end if
							} #end if	
						} # end foreach i

					} # end foreach cut_off
					push @i, map { @{$_} } values %paper_impositions;
				} else {
					my @temp_imps = openprint::imposition::get_imposition( $project, $do_work_turn, $do_perfecting, $$specs{versions}, $P, $Press );
					push @i, @temp_imps;
					if ( DEBUG_IMPOSITIONS ) {
						$log->error('Got ' . @temp_imps . ' for ' . $P->to_string() );
						foreach my$i( @temp_imps ) {
							$i->display( 'Returned from get_imposition' );
						}
					}
				} # end if
				if ( $$P{start_width} ) {
					push @imps, @i;
				} else {

					# IF it's a custom paper, then also cut it down
					foreach my $i ( @i ) {
						my $i2 = $i->copy();
						my $P2 = $$i2{Paper}->clone();

						if ( ! $$P2{width} ) {
							$log->error('Setting width to '.$i2->used_width());
							$P2->width( $i2->used_width() )
						}
						$Papers{$P2->id_string()} = $P2->clone() if ! $Papers{$P2->id_string()};
						while ( $$i2{columns} ) {
							push @imps, $i2;
							if ( $$i2{columns} > 1 ) {
								$i2 = $i2->copy();
								$i2->columns( $$i2{columns}-1 );
								openprint::imposition::check_setup( $i2, $project );
								if ( $minimum_sheet_width and ($$P2{width} < $minimum_sheet_width) ) {
									$log->debug("Paper width $$P2{width} < $minimum_sheet_width minimum sheet width") if DEBUG_IMPOSITIONS;
									$i2->columns(0);
								} elsif ( DEBUG ) {
									$log->debug("Paper width $$P2{width} > $minimum_sheet_width minimum sheet width") if DEBUG_IMPOSITIONS;
								}
								$i2->columns(0) if $minimum_roll_width and ($$P2{width} < $minimum_roll_width);
								if ( $$i2{imposition} ) {
									$P2->width( $i2->used_width() );
									$Papers{$P2->id_string()} = $P2->clone() if ! $Papers{$P2->id_string()};
								}
							} else {
								last;
							} # end if columns > 1
						} # end while
					} # end foreach
				} # end if start_width or cut for all sizes
			} else { # Sheet
				if ( ! ( $$Paper{width} and $$Paper{height} ) ) {
					$log->debug($$Press{strid}." : Sheetfed but doesn't have width and height Not using " . $Paper->to_string() ) if DEBUG_IMPOSITIONS;
					next;
				}
				if ( (!$use_cut_stocks) and $Paper->is_cut() ) {
					$log->debug($$Press{strid}." : Not using " . $Paper->to_string() . " because its cut." . $use_cut_stocks ) if DEBUG_IMPOSITIONS;
					next;
				} # end if
				if ( $printing_type eq 'Digital' and ! $Paper->digital() ) {
					$log->debug("Not using " . $Paper->to_string() . " because not digital." ) if DEBUG;
					next;
				} # end if
				if ( %sheetsizes and ! $sheetsizes{join('x', $Paper->width(),$Paper->height())} ) {
					$log->debug("Not using " . $Paper->to_string() . " because not in sheetsizes. for $$Press{strid}" ) if DEBUG_IMPOSITIONS;
					next;
				} # end if
				$log->debug("using " . $Paper->to_string() . ' is good must be in sheetsizes.' ) if DEBUG_IMPOSITIONS;

				$$project{Runstyles} = $runstyles_sheet;

				my $P = $Paper->clone();

# Cut to fit on press
				if ( ( $maximum_sheet_width and $maximum_sheet_length ) and 
						( $P->width() > $maximum_sheet_width or $P->height() > $maximum_sheet_length )
						and
						( $P->width() > $maximum_sheet_length or $P->height() > $maximum_sheet_width )
					) {
					if ( ! $P->cuttable() ) {
						$log->debug("Stock no good, can't be cut." . $P->to_string() );
						next;
					}
					if ( ! $use_cut_stocks ) {
						$log->debug("Stock no good, not using cut stocks." . $P->to_string() );
						next;
					} # en dif
					while (
							( $P->width() > $maximum_sheet_width or $P->height() > $maximum_sheet_length )
							and
							( $P->width() > $maximum_sheet_length or $P->height() > $maximum_sheet_width )
							) {
						$P->cut();
$log->debug("Cutting to " . $P->to_string() ) if DEBUG_IMPOSITIONS;
					} # end while
				} # end if

# Keep cutting while the sheet still fits on the press.	I originally thought that we shouldn't do this, because why would you want to run a half sheet if a full sheet fits?	The answer: small jobs, that due to overs requires the same sheets whether you run full or half.	So by running half, you need half the # of real sheets.
				while (
						( $P->width() >= $minimum_sheet_width and $P->height() >= $minimum_sheet_length )
						or
						( $P->width() >= $minimum_sheet_length and $P->height() >= $minimum_sheet_width )
						) {

					if ( ! ( 
								( $P->width() >= $$specs{txtWidth} and $P->height() >= $$specs{txtHeight} ) 
								or ( $P->height() >= $$specs{txtWidth} and $P->width() >= $$specs{txtHeight} ) 
							) ) {
						$log->debug("Next paper because it's too small for the item" . $P->width() . 'x' . $P->height() . ' => ' . $$specs{txtWidth} . 'x' . $$specs{txtHeight} ) if DEBUG;
						last;
					} # end if

					my @i = openprint::imposition::get_imposition( $project, $do_work_turn, $do_perfecting, $$specs{versions}, $P, $Press );
					if ( DEBUG_IMPOSITIONS ) {
						$log->debug("Got " . @i . " impositions on $$Press{strid} " . $P->to_string() );
						foreach my $i ( @i ) {
							$i->display("initial for $$Press{strid}");
						}
					}
					last if ! @i;
					push @imps, @i;
					foreach my $i ( @i ) {
						my $P2 = $$i{Paper};
						$Papers{$P2->id_string()} = $P2 if ! $Papers{$P2->id_string()};
					} # end if
					last if ! $use_cut_stocks;
					last if ! $P->cuttable();
					$P = $P->clone();
					$P->cut();
				} # end while cutting it
			} # end if Web or Sheet

			if ( @imps ) {
				if ( $do_initial_filtering ) {

					foreach my $i ( @imps ) {
						my $key = join(',',@$i{'imposition','runstyle','image_orientation'});
						if ( ! $imps{$key} ) {
							$imps{$key} = [ $i ];
	if ( DEBUG_INITIAL_FILTERING ) {
	$i->display('STARTING');
	}
							next;
						} # end if
						my $add = 1;
						my $Aarea = $$i{Paper}->area();
						if ( DEBUG_INITIAL_FILTERING ) {
							$i->display('STARTING A');
						}
						if ( $$Overrides{"chkOverrideSheetSize$qty_index"} or $$Overrides{"OverrideCutOff$qty_index"} ) {
						} else {
							for ( my $imp_index = 0; $imp_index < @{$imps{$key}}; $imp_index += 1 ) {
								my $B = $imps{$key}[$imp_index];
								my $Barea = $$B{Paper}->area();
								if ( $Aarea < $Barea ) {
									if ( DEBUG_INITIAL_FILTERING ) {
										$B->display("DROPPING B");
										$i->display("KEEPPING A");
									}
									splice @{$imps{$key}}, $imp_index, 1;
									$imp_index -= 1;
								} elsif ( $Aarea > $Barea ) {
									if ( DEBUG_INITIAL_FILTERING ) {
										$i->display("NOT ADDING");
									}
									$add = 0;
									last;
								} # end if
							} # end foreach B
						} # end if
						if ( $add ) {
							push @{$imps{$key}}, $i;
						} # end if
					} # end foreach i

					my @b = map { @{$_} } values %imps;
					$log->warn('1st imps: ' . @imps . ' down to ' . @b) if DEBUG_INITIAL_FILTERING;
					push @impositions, @b;
					%imps = ();
				} else {
					push @impositions, @imps;
				} # end if
			} # end if @imps

		} # end foreach Paper

if ( $do_initial_filtering ) {
		# Used in filtering
		my %dutches;
		if ( DEBUG_INITIAL_FILTERING ) {
			$log->debug('Impositions before filtering on ' . $$Press{strid} . ' ' . @impositions . ' impositions' . ( sprintf('%.4f', tv_interval( [$master_time])*1000) ) .' usecs');
			foreach my $i ( @impositions ) {
				$i->display();
			}
		}

		my $have_perfecting = 0;
		my $prefer_perfecting = $Press->specification('Prefer Perfecting');

		my $max_imposition = 0;
		foreach my $imp ( @impositions ) {
			$max_imposition = $$imp{imposition} if $$imp{imposition} > $max_imposition;
			if ( (!$have_perfecting) and $$imp{runstyle} eq 'Perfecting' ) {
				$have_perfecting = 1;
			}
		} # end foraech
		$max_imposition = int( $max_imposition / 4 );

		foreach my $imp ( @impositions ) {
			if ( $$imp{imposition} < $max_imposition ) {
$imp->display("Less than $max_imposition") if DEBUG_INITIAL_FILTERING;
				next;
			} # end if
			if ( $have_perfecting 
					and ( $$imp{runstyle} eq 'Work & Turn' or $$imp{runstyle} eq 'Work & Tumble' )
					and ( $prefer_perfecting eq 'Y' ) 
					and ( ! ($$specs{"chkOverrideRunStyle$qty_index"} and ($$specs{"chkOverrideRunStyle$qty_index"} eq 'Y') ) )
				 ) {
				$imp->display('Have Perfecting so dont do W&T') if DEBUG_INITIAL_FILTERING;
				next;
			} # end if
			
			my $A = $$imp{Paper};

			my $a_stock_minimum = $$specs{"txtQuantity$qty_index"} / $$imp{imposition};
			my $a_stock_lbs;
			if ( $$A{type} eq 'Sheet' ) {
				$a_stock_minimum = ceil( $a_stock_minimum / $A->factor() );
				$a_stock_lbs = Math::Round::nearest(0.01, $a_stock_minimum * $A->Supplied()->area() * $A->wpsi() );
			} else {
				$a_stock_lbs = Math::Round::nearest(0.01, $a_stock_minimum * $A->area() * $A->wpsi() );
			}
			$$imp{stock_lbs} = $a_stock_lbs;

			my $add = 1;
			if ( $$imp{dutch_columns} ) {
				if ( $openprint::imposition::blocks{$$imp{imposition}} ) {
					# If we have a similar imposition, without dutch, then do not consider the dutch
					foreach my $arrangement ( $openprint::imposition::blocks{$$imp{imposition}} ) {
						my $str = join(',', @$arrangement, '', '', @$imp{'runstyle','image_orientation','bleed_size'}, $$A{digital} );
						#my $str = ntf('%dx%d+%dx%d-%s-%s-%s', @$arrangement, 0, 0, @$imp{'runstyle','image_orientation','bleed_size'}, $$A{digital} );

						if ( $imps{$str} ) {
							foreach my $I ( @{$imps{$str}} ) {
								if ( $$I{Paper}->area() <= $A->area() ) {
									$add = 0;
	$imp->display("Found non-dutch") if DEBUG_INITIAL_FILTERING;
								} # end if
							} # end foreach
						} # end if
					} # end foreach arrangement
				} else {
					$log->warn("NO blocks for $$imp{imposition} when dutch");
				} # end if
				if ( $add ) {
					push @{$dutches{$$imp{imposition}}}, $imp;
				}
			} elsif ( $dutches{$$imp{imposition}} ) {
				# Non-dutch, so check for a dutch to kick out.
				for ( my $dutch_index = 0; $dutch_index < @{$dutches{$$imp{imposition}}}; $dutch_index += 1 ) {
					my $dutch_imp = $dutches{$$imp{imposition}}[$dutch_index];
					if ( $$dutch_imp{Paper}->area() >= $A->area() ) {
						$dutch_imp->display('kicking out dutch') if DEBUG_INITIAL_FILTERING;
						my $str = join(',', @$dutch_imp{'columns','rows','dutch_columns','dutch_rows','runstyle','image_orientation','bleed_size', $$dutch_imp{Paper}->digital() } );
						#my $str = sprintf('%dx%d+%dx%d-%s-%s-%s-%s', @$dutch_imp{'columns','rows','dutch_columns','dutch_rows','runstyle','image_orientation','bleed_size', $$dutch_imp{Paper}->digital() } );
						if ( $imps{$str} ) {
							for ( my $index = 0; $index < @{$imps{$str}}; $index += 1 ) {
								splice @{$imps{$str}}, $index, 1;
								$index -= 1;
							} # end foreach
						} else {
							$log->debug("No other duteches to remove") if DEBUG_INITIAL_FILTERING;
						} # end if
						splice @{$dutches{$$imp{imposition}}}, $dutch_index, 1;
						$dutch_index -= 1;
					} # end if
				} # end foreach dutch_imp
			} # end if
			next if ! $add;

			my $str = join(',', @$imp{'columns','rows','dutch_columns','dutch_rows','runstyle','image_orientation','bleed_size'}, $$A{digital}, $$A{type} );
			#my $str = sprintf('%dx%d+%dx%d-%s-%s-%s-%s', @$imp{'columns','rows','dutch_columns','dutch_rows','runstyle','image_orientation','bleed_size'}, $$A{digital} );
#$log->error("A $$A{width}x$$A{height} " . join(',', @{$$Overrides{"OverrideStockWidth$qty_index"}} ) . ' heights: ' . join(',', @{$$Overrides{"OverrideStockHeight$qty_index"}} ) );
			if ( $$Overrides{'chkOverrideSheetSize'.$qty_index} 
					and sets::isin( $$A{width}, $$Overrides{"OverrideStockWidth$qty_index"} )
					and ( ( $$A{type} eq 'Roll' ) or sets::isin( $$A{height}, $$Overrides{"OverrideStockHeight$qty_index"} ) )
				) {
# If it matches the override, the consider it no matter what
#$imp->display("Leeping because of Overrides");

			} elsif ( $$Overrides{'OverrideCutOff'.$qty_index} and sets::isin( $$A{height}, $$Overrides{"CutOff$qty_index"} ) ) {
#$add = 1;
			} elsif ( $imps{$str} ) {

				my $APrice = $$imp{PaperPrice} = $A->get_price( service=>'Material', weight=> $a_stock_lbs );
$imp->display('Comparing A QTY $' . $$imp{PaperPrice}{'100lb Price'}. " for $a_stock_lbs" ) if DEBUG_INITIAL_FILTERING;

				# Can't do any decisions based on absolute price or qty, because we just don't know how much paper we need
				for ( my $j = 0; $j < @{$imps{$str}}; $j += 1 ) {
					my $I = $imps{$str}[$j];
					my $B = $$I{Paper};

					if ( $$Overrides{'chkOverrideSheetSize'.$qty_index} and 
							sets::isin( $$B{width}, $$Overrides{"OverrideStockWidth$qty_index"}) and 
							( $$B{type} eq 'Roll' or sets::isin( $$B{height}, $$Overrides{"OverrideStockHeight$qty_index"} ) ) 
						) {
						last;
					} elsif ( ($$Overrides{'OverrideCutOff'.$qty_index} and ( $$Overrides{'OverrideCutOff'.$qty_index} eq 'Y' ) ) and sets::isin( $$B{height}, $$Overrides{"CutOff$qty_index"} ) ) {
						last;
					} # end if
					$$I{PaperPrice} = $B->get_price( service=>'Material', weight=> $$I{stock_lbs} ) if ! $$I{PaperPrice};
					my $BPrice = $$I{PaperPrice};

if ( ( ! $BPrice ) or ( ! $$BPrice{'100lb Price'} ) ) {
$log->debug("NO 100lbPrice for $$I{stock_lbs} ");
}
$I->display('Comparing B QTY $' . $$BPrice{'100lb Price'} ) if DEBUG_INITIAL_FILTERING;
#if ( ! $$I{PaperPrice} ) {
#$log->error("No price for stock ".$B->to_string() ) if ! ( $B->custom() or $B->supplied() );
#} elsif ( ( ! $$BPrice{'100lb Price'} ) and ( ! $$B{custom} ) and ( ! $$B{supplied} ) ) {
#$log->error("No 100lb price for stock ".$B->to_string() );
#$log->error("No 100lb price for stock ".$B->get_price( service=>'Material')->to_string() );
#}

					if (
							( $B->area() >= $A->area() )
							and
							( ( $$B{minimum_order} >= $$A{minimum_order} ) or ( $a_stock_lbs > $$A{minimum_order} ) )
							and
							( $$BPrice{'100lb Price'} >= $$APrice{'100lb Price'} )
							and
							( $B->is_cut() or ! $A->is_cut() )
							and 
							( ( !$$B{start_width} ) or $$A{start_width} ) # Prefer non custom rolls
							and 
							( $B->waste() > $A->waste() )
						) {
 if ( DEBUG_INITIAL_FILTERING ) {
$log->debug("removing B larger");
$log->debug('Area: ' . $B->area() . ' >= ' . $A->area());
$log->debug('Minimum Order: ' . $B->minimum_order() . ' >= ' . $A->minimum_order() . ' ' . $a_stock_lbs . ' > ' . $$A{minimum_order} );
$log->debug('Wate: ' . $B->waste() . ' >= ' . $A->waste());
}

						splice @{$imps{$str}}, $j, 1;
						$j -= 1;
					} elsif (
							( $B->area() <= $A->area() )
							and
							( ( $B->minimum_order() <= $A->minimum_order() ) or ( $$B{minimum_order} < $$B{stock_lbs} ) ) 
							and
							( $$BPrice{'100lb Price'} <= $$APrice{'100lb Price'} )
							and
							( ( ! $B->is_cut() ) or $A->is_cut() )
							and 
							( ( $$B{start_width} ) or ( ! $$A{start_width} ) ) # Prefer non custom rolls
							and 
							( $B->waste() < $A->waste() )
						) {
						$add = 0;
$log->debug('removing A larger') if DEBUG_INITIAL_FILTERING;
						last;
					} else {
$log->debug("Doing nothing, keeping all add:$add") if DEBUG_INITIAL_FILTERING;
					} # end if
				} # end for
			} # end if overriden or not or cached
			if ( $add ) {
				push @{$imps{$str}}, $imp;
				$Papers{$$imp{Paper}->id_string()} = $$imp{Paper} if ! $Papers{$$imp{Paper}->id_string()};
			} # end if
		} # end foreach imposition

		@impositions = map {@{$_}} values %imps;

if ( 0 ) {
		# This is ok, because we are on the same press
		%imps = ();
		my $bump_count = 0;
		foreach my $I ( @impositions ) {
			my $Paper = $$I{Paper};
			my $key = join(',', $$Paper{type}, $Paper->area(), @$I{'pages','image_orientation','imposition','runstyle'} );
			if ( ! ( $imps{$key} and @{$imps{$key}} ) ) {
				$imps{$key} = [ $I ];
				next;
			} # end if
			my $add = 1;
			for ( my $i = 0; $i < @{$imps{$key}}; $i += 1 ) {
				my $B = $imps{$key}[$i];
				if ( $$I{runstyle} eq 'Perfecting' and sets::isin( $$B{runstyle}, [ 'Sheet Work','Work & Turn', 'Work & Tumble' ] ) ) {
					splice @{$imps{$key}}, $i, 1;
					$i -= 1;
					$bump_count += 1;
				} elsif ( $$B{runstyle} eq 'Perfecting' and sets::isin( $$I{runstyle}, [ 'Sheet Work','Work & Turn', 'Work & Tumble' ] ) ) {
					$add = 0;
					last;
				} # end if
			} # end for each imp
			if ( $add ) {
				push @{$imps{$key}}, $I;
			} else {
				$bump_count += 1;
			}
		} # end foreach I
		$log->debug("Initial Bumped $bump_count for Perfecting vs Sheet Work") if DEBUG_INITIAL_FILTERING or 1;

		@impositions = map {@{$_}} values %imps;
}
		%imps = ();
		if ( DEBUG_INITIAL_FILTERING ) {
			$log->debug("After filtering by Perfecting vs Sheetwork");
			foreach my $I ( openprint::imposition::sort ( @impositions ) ) {
				$I->display("After filtering by paper and runstyle");
			}
		}

} # end if do_initial_filtering
#$log->debug("After filtering qty: $qty_index, Press: $$Press{strid} " . ( sprintf('%.4f', tv_interval( [$master_time])*1000) ) .' usecs' );
		if ( DEBUG or DEBUG_INITIAL_FILTERING ) {
			$log->warn('Impositions after initial filtering for '. $$Press{strid} . ': ' . @impositions . ' time: ' . ( sprintf('%.4f', tv_interval( [$master_time])*1000) ) .' usecs');
			foreach my $I ( openprint::imposition::sort( @impositions ) ) {
				$I->display('QTY $' );
			} # end foreach
		} # end if

		if ( ! @impositions ) {
			if ( $$specs{'chkOverridePress'.$qty_index} and ( $$Press{strid} eq $$specs{'ddmPress'.$qty_index} ) ) {
				if ( $Press->specification('Printing Type') eq 'Digital' ) {
					my $digital = 0;
					foreach my $P (@$Papers) {
						$digital = 1 if $P->digital();
					} # end foreach P	
					if ( ! $digital ) {
						$$specs{alert} .= 'Paper is not suitable for digital printing.<br/>';
					} # end if
				} # end if
			} # end if
		} # end if ! impositions

		#foreach my $imp ( @impositions ) {
			#$$imp{inkCoverage} = $$project{inkCoverage};
		#}

		$impositions{$Press->strid()} = \@impositions if @impositions;
	} # end foreach Press

	return %impositions;
} # end sub get_impositions

sub set_size {
	my ( $Project, $specs, $printing_specs ) = @_;

	my $Type = $Project->Type();
	if ( $$Type{name} eq 'Banners' ) {
		my $width = $$specs{txtFinalWidth};
		my $height = $$specs{txtFinalHeight};

		if ( $$specs{pockets} eq 'Y' ) {
			$width += $$specs{PocketSize};
			$width += $$specs{PocketSize};
		} # end if

		if ( $$specs{hemmed} eq 'Y' ) {
			$width += $$specs{HemWidth} if $$specs{EdgeLeft};
			$width += $$specs{HemWidth} if $$specs{EdgeRight};
			$height += $$specs{HemWidth} if $$specs{EdgeTop};
			$height += $$specs{HemWidth} if $$specs{EdgeBottom};
		} # end if

		if ( $width != $$specs{txtWidth} ) {
			$$specs{txtWidth} = $width;
			$variables{txtWidth} = [ sets::union( 'output', @{$variables{txtWidth}} ) ];
		} else {
			$variables{txtWidth} = [ sets::exclude( ['output'], $variables{txtWidth} ) ];
		} # end if

		if ( $$specs{txtFinalHeight} > $height ) {
			$height = $$specs{txtFinalHeight};
		} # end if

		if ( $height != $$specs{txtHeight} ) {
			$$specs{txtHeight} = $height;
			$variables{txtHeight} = [ sets::union( 'output', @{$variables{txtHeight}} ) ];
		} else {
			$variables{txtHeight} = [ sets::exclude( ['output'], $variables{txtHeight} ) ];
		} # end if

	} elsif ( $$Type{name} eq 'ScratchPads' ) {
# Technically, something like a coil bound could be 2pg spread, just need two of them.  
		if ( ! $$specs{OverrideSpreadSize} ) {
			$$specs{txtSpreadSize} = 1;
			$variables{txtSpreadSize} = [ sets::union( 'output', @{$variables{txtSpreadSize}} ) ];
		} # end if
		if ( $$specs{ddmProjectSize} ne 'Custom' and $$Type{type} eq 'ScratchPads' ) {
			$$specs{txtWidth} = $$printing_specs{txtWidth} if $$printing_specs{txtWidth};
			$$specs{txtHeight} = $$printing_specs{txtHeight} if $$printing_specs{txtHeight};
			$$specs{txtFinalWidth} = $$printing_specs{txtFinalWidth} if $$printing_specs{txtFinalWidth} ;
			$$specs{txtFinalHeight} = $$printing_specs{txtFinalHeight} if $$printing_specs{txtFinalHeight};
		} else {
			$variables{txtWidth} = [ sets::exclude( ['output'], $variables{txtWidth} ) ];
			$variables{txtHeight} = [ sets::exclude( ['output'], $variables{txtHeight} ) ];
			$variables{txtFinalWidth} = [ sets::exclude( ['output'], $variables{txtFinalWidth} ) ];
			$variables{txtFinalHeight} = [ sets::exclude( ['output'], $variables{txtFinalHeight} ) ];
		}

	} elsif ( $$Type{name} eq 'PresentationFolders' ) {
		if ( $$specs{ddmProjectSize} ne 'Custom' ) {
#$log->debug("Auto calc dimensions");
# auto calc flat dimensions
			$$specs{txtWidth} = $$specs{txtFinalWidth} * $$specs{rdbPanels};
			my $pockets;
			if ( $$specs{rdbPanels} == 2 ) {
				$$specs{chkPocketCenter} = '';
				$variables{chkPocketCenter} = [ sets::exclude( ['output'], $variables{chkPocketCenter} ) ];
			} # end if
			if ( $$specs{chkPocketLeft} ) {
				$$specs{txtWidth} += 0.75;
				$pockets += 1;
			} # end if
			if ( $$specs{chkPocketRight} ) {
				$$specs{txtWidth} += 0.75;
				$pockets += 1;
			} # end if
			if ( $$specs{chkPocketCenter} ) {
				$pockets += 1;
			} # end if
			$$specs{rdbTemplateType} = sprintf( '%dPanel%dPocket', $$specs{rdbPanels}, $pockets );
			$$specs{txtHeight} = $$specs{txtFinalHeight} + $$specs{PocketSize};
			$variables{txtWidth} = [ sets::union( 'output', @{$variables{txtWidth}} ) ];
			$variables{txtHeight} = [ sets::union( 'output', @{$variables{txtHeight}} ) ];
			#$log->debug("WIdth: $$specs{txtWidth} ");
			#$log->debug("Heightth: $$specs{txtHeight} ");
		} else {
			$variables{txtWidth} = [ sets::exclude( ['output'], $variables{txtWidth} ) ];
			$variables{txtHeight} = [ sets::exclude( ['output'], $variables{txtHeight} ) ];
			$variables{rdbTemplateType} = [ sets::exclude( ['output'], $variables{rdbTemplateType} ) ];
		} # end if
	} elsif ( $$specs{txtSignatureType} ) {
		if ( $$specs{txtSignatureType} eq 'Gate Folded Pages' ) {
			if ( $$specs{rdbTemplateType} eq 'SingleGateFold' ) {
				if ( ! $$specs{chkOverrideDimensions} ) {
					if ( ! $$specs{txtWidth} ) {
						$$specs{txtWidth} = $$printing_specs{txtWidth}*1.5;
						$variables{txtWidth} = [ sets::union( 'output', @{$variables{txtWidth}} ) ];
					} else {
						$variables{txtWidth} = [ sets::exclude( ['output'], $variables{txtWidth} ) ];
					} # end if
					if ( ! $$specs{txtHeight} ) {
						$$specs{txtHeight} = $$printing_specs{txtHeight};
						$variables{txtHeight} = [ sets::union( 'output', @{$variables{txtHeight}} ) ];
					} else {
						$variables{txtHeight} = [ sets::exclude( ['output'], $variables{txtHeight} ) ];
					} # end if
				} # end if
				if ( ! $$specs{txtSpreadSize} ) {
					$$specs{txtSpreadSize} = 6;
					$variables{txtSpreadSize} = [ sets::union( 'output', @{$variables{txtSpreadSize}} ) ];
				} # end if
			} elsif ( $$specs{rdbTemplateType} eq 'DoubleGateFold' ) {
				if ( ! $$specs{chkOverrideDimensions} ) {
					if ( ! $$specs{txtWidth} ) {
						$$specs{txtWidth} = $$printing_specs{txtWidth}*2;
						$variables{txtWidth} = [ sets::union( 'output', @{$variables{txtWidth}} ) ];
					} else {
						$variables{txtWidth} = [ sets::exclude( ['output'], $variables{txtWidth} ) ];
					} # end if
					if ( ! $$specs{txtHeight} ) {
						$$specs{txtHeight} = $$printing_specs{txtHeight};
					} else {
						$variables{txtHeight} = [ sets::exclude( ['output'], $variables{txtHeight} ) ];
					} # end if
				} # end if
				if ( ! $$specs{txtSpreadSize} ) {
					$$specs{txtSpreadSize} = 8;
					$variables{txtSpreadSize} = [ sets::union( 'output', @{$variables{txtSpreadSize}} ) ];
				} # end if
			} # end if
		} elsif ( $$specs{txtSignatureType} eq 'Cover Pages' ) {

			# Technically, something like a coil bound could be 2pg spread, just need two of them.	
			if ( ! $$specs{OverrideSpreadSize} ) {
        if ( $$specs{rdbTemplateType} eq 'SingleGateFold' ) {
          $$specs{txtSpreadSize} = 6;
        } elsif ( $$specs{rdbTemplateType} eq 'DoubleGateFold' ) {
          $$specs{txtSpreadSize} = 8;
        } else {
          $$specs{txtSpreadSize} = ( $$specs{GroupPageQuantity} > 6 ? 4 : $$specs{GroupPageQuantity} );
        }
        $variables{txtSpreadSize} = [ sets::union( 'output', @{$variables{txtSpreadSize}} ) ];
			} else {
				if ( $$specs{txtSpreadSize} > $$specs{GroupPageQuantity} ) {
					$$specs{GroupPageQuantity} = $$specs{txtSpreadSize};
				} # end if
			} # end if
			#$log->debug("SpreadSize: $$specs{txtSpreadSize}");
			if ( ! $$specs{chkOverrideDimensions} ) {
				if ( $$specs{rdbTemplateType} and sets::isin($$specs{rdbTemplateType}, ['2Panel1Pocket','2Panel2Pocket','TriFoldDoublePocket'] ) ) {
					$$specs{txtWidth} = $$printing_specs{txtFinalWidth} * $$specs{rdbPanels};
					my $pockets = 0;
					if ( $$specs{rdbPanels} == 2 ) {
						$$specs{chkPocketCenter} = '';
						$variables{chkPocketCenter} = [ sets::exclude( ['output'], $variables{chkPocketCenter} ) ];
					} # end if
					if ( $$specs{chkPocketLeft} ) {
						$$specs{txtWidth} += 0.75;
						$pockets += 1;
					} # end if
					if ( $$specs{chkPocketRight} ) {
						$$specs{txtWidth} += 0.75;
						$pockets += 1;
					} # end if
					if ( $$specs{chkPocketCenter} ) {
						$pockets += 1;
					} # end if
					$$specs{txtHeight} = $$printing_specs{txtFinalHeight} + $$specs{PocketSize};
				} elsif ( $$specs{txtSpreadSize} > 1 ) {
					if ( $$printing_specs{spine} eq 'height' ) {
					$$specs{txtWidth} = $$printing_specs{txtFinalWidth}*$$specs{txtSpreadSize}/2;
					$$specs{txtHeight} = $$printing_specs{txtFinalHeight};
$log->debug("Using spine ehgiht");
					} else {
						$$specs{txtWidth} = $$printing_specs{txtFinalWidth};
						$$specs{txtHeight} = $$printing_specs{txtFinalHeight} *$$specs{txtSpreadSize}/2;
					}
				} else {
					$$specs{txtWidth} = $$printing_specs{txtFinalWidth};
					$$specs{txtHeight} = $$printing_specs{txtFinalHeight};
				} # end if
				$$specs{txtFinalHeight} = $$printing_specs{txtFinalHeight} if ! $$specs{txtFinalHeight};

				if ( $$printing_specs{rdbTemplateType} and ( $$printing_specs{rdbTemplateType} eq 'PerfectBound' ) ) {
          # Perfect bound requires more width on the cover to cover the caliper	of the interior pages
					my $finished_calliper = 0;
					my @Groups = sql::execute( undef, undef, 'SELECT DISTINCT strvalue FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND strName=?', $Project->id(), 'Group' );
					foreach my $group_id ( @Groups ) {
						# Don't include the cover
						next if $group_id == 1;
						foreach my $ss_id ( $Project->signatures({ Group=>$group_id}) ) {
							# Each group has at least 1 sig in it
							my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );

							$finished_calliper += $$sig_specs{GroupPageQuantity} * $$sig_specs{txtSpecificStockCalliper} /2;
							last;
						} # end foreach signature in the group
					} # end foreach group
					if ( ! $finished_calliper ) {
						$$specs{alert} .= 'No calliper found for interior pages.  Spread Width will be incorrect';
					}
$openprint::log->debug("Doing Perfect bound ifinished calliper is $finished_calliper");

					$$specs{txtWidth} = Math::Round::nearest( 0.0001, ceil(($$specs{txtWidth} + $finished_calliper + 2*$config{PerfectBindGlueSpace})*10000)/10000);
				} else {
					$$specs{txtWidth} = Math::Round::nearest( 0.001, ceil($$specs{txtWidth}*1000)/1000);
				} # end if
			} # end if
			$$specs{txtFinalWidth} = $$printing_specs{txtFinalWidth};
			$$specs{txtFinalHeight} = $$printing_specs{txtFinalHeight};
		} else { # not folder, not cover
			if ( !$$specs{OverrideSpreadSize} ) {
				if ( $$Type{name} eq 'ScratchPads' ) {
					$$specs{txtSpreadSize} = 1;
				} else {
					if ( $$printing_specs{rdbTemplateType} eq 'SaddleStitching' or $$printing_specs{rdbTemplateType} eq 'LoopStitching' ) {
						$$specs{txtSpreadSize} = ( $$specs{GroupPageQuantity} > 6 ? 4 : $$specs{GroupPageQuantity} );
					} elsif ( $openprint::config{$$printing_specs{rdbTemplateType}.'SpreadSize'} ) {
						$$specs{txtSpreadSize} = $openprint::config{$$printing_specs{rdbTemplateType}.'SpreadSize'};
					} elsif ( $$printing_specs{rdbTemplateType} eq 'Unbound' ) {
						$$specs{txtSpreadSize} = 2;
					} elsif ( $$printing_specs{rdbTemplateType} eq 'PerfectBound' or $$printing_specs{rdbTemplateType} eq 'PerfectBinding') {
						if ( $openprint::config{PerfectBindSpreadSize} ) {
							$$specs{txtSpreadSize} = $openprint::config{PerfectBindSpreadSize};
						} else {
							$$specs{txtSpreadSize} = 2;
						} # end if
					} elsif ( $$printing_specs{rdbTemplateType} eq 'CornerStitching' or $$printing_specs{rdbTemplateType} eq 'SpinePaste' ) {
						$$specs{txtSpreadSize} = 2;
					} elsif ( $$specs{GroupPageQuantity} % 4 ) {
						$$specs{txtSpreadSize} = 2;
					} else {
						$$specs{txtSpreadSize} = 4;
					} # end if
				} # end if
				$variables{txtSpreadSize} = [ sets::union( 'output', @{$variables{txtSpreadSize}} ) ];
			} # end if

			if ( !$$specs{chkOverrideDimensions} ) {
				if ( $$specs{txtSpreadSize} == 4 ) {
					if ( $$printing_specs{spine} eq 'height' ) {
						$$specs{txtWidth} = $$printing_specs{txtFinalWidth} * 2;
						$$specs{txtHeight} = $$printing_specs{txtFinalHeight};
$log->debug("Using spine height");
					} else {
						$$specs{txtWidth} = $$printing_specs{txtFinalWidth};
						$$specs{txtHeight} = $$printing_specs{txtFinalHeight} * 2;
					} # end if
				} elsif ( $$specs{txtSpreadSize} == 2 ) {
					@$specs{'txtWidth','txtHeight'} = @$printing_specs{'txtFinalWidth','txtFinalHeight'};
				} elsif ( $$specs{txtSpreadSize} == 6 ) {
					if ( $$printing_specs{spine} eq 'height' ) {
						$$specs{txtWidth} = $$printing_specs{txtFinalWidth} * 3;
						$$specs{txtHeight} = $$printing_specs{txtFinalHeight};
						$log->debug("Using spine height");
					} else {
						$$specs{txtWidth} = $$printing_specs{txtFinalWidth};
						$$specs{txtHeight} = $$printing_specs{txtFinalHeight} * 3;
					} # end if

				} else {
					$log->debug("Unknown spreadsize $$specs{txtSpreadSize}");
					$$specs{txtWidth} = $$printing_specs{txtFinalWidth};
					$$specs{txtHeight} = $$printing_specs{txtFinalHeight};
				} # end if
				@$specs{'txtFinalWidth','txtFinalHeight'} = @$printing_specs{'txtFinalWidth','txtFinalHeight'};
			} # end if
		} # end if Spread Type
	} else { # not a book
# If no spreadsize, then we are likely not a book, and the spread size is 2
		#$$specs{txtSpreadSize} = 2 if ! $$specs{txtSpreadSize};
		if ( $$specs{txtFinalWidth} and $$specs{txtFinalHeight} ) {
			$$specs{txtSpreadSize} = 2*Math::Round::nearest( 1, $$specs{txtWidth}/$$specs{txtFinalWidth})*Math::Round::nearest( 1, $$specs{txtHeight}/$$specs{txtFinalHeight} );
		} # end if
#$variables{txtWidth} = [ sets::exclude( ['output'], $variables{txtWidth} ) ];
#$variables{txtHeight} = [ sets::exclude( ['output'], $variables{txtHeight} ) ];
	} # end if

	if ( $$Type{name} and ( $$Type{name} eq 'Envelopes' or $$Type{name} eq 'NCR' ) ) {
		if ( $$specs{rdbSpecificStock} ne 'Y' ) {
			if ( $$specs{ddmStockSheetSize} ) {
				@$specs{'txtWidth','txtHeight'} = $$specs{ddmStockSheetSize} =~ /^([\d\.]+)"?\s*x?\s*([\d\.]+)?"?\s*$/;
			} elsif ( $$specs{ddmStockSize} ) {
				@$specs{'txtWidth','txtHeight'} = $$specs{ddmStockSize} =~ /^([\d\.]+)"?\s*x?\s*([\d\.]+)?"?\s*$/;
			} else {
				my @Papers = openprint::Paper->find(
						( $$specs{ddmStockGroup} ? ( group=> $$specs{ddmStockGroup} ) : () ),
						( $$specs{ddmStockBrand} ? ( brand=> $$specs{ddmStockBrand} ) : () ),
						( $$specs{ddmStockFinish} ? ( finish=>$$specs{ddmStockFinish} ) : () ),
						( $$specs{ddmStockColour} ? ( colour=>$$specs{ddmStockColour} ) : () ),
						( $$specs{ddmStockWeight} ? ( weight=>$$specs{ddmStockWeight} ) : () ),
						( $$specs{ddmStockQuality} ? ( quality=>$$specs{ddmStockQuality} ) : () ),
						'project_type_id any'=>$Project->type_id(),
						);
	#$log->debug("# of papers: " . @Papers );
				my %sizes;
				foreach my $Paper ( @Papers ) {
					$sizes{(1*$$Paper{width}).'x'.(1*$$Paper{height})} = $Paper;
				} # end foreach Paper	
				my @keys = keys %sizes;
	#$log->debug("# of sizes: " . @keys );
				if ( 1 == @keys ) {
					@$specs{'txtWidth','txtHeight'} = ( $sizes{$keys[0]}->width(), $sizes{$keys[0]}->height() );	
				} # end if
			} # end if
		} else {
			@$specs{'txtWidth','txtHeight'} = @$specs{'txtSpecificStockWidth','txtSpecificStockHeight'};
		} # end if
		@$specs{'txtFinalWidth','txtFinalHeight'} = @$specs{'txtWidth','txtHeight'};
	} # end if

	if ( ! $$specs{chkOverrideDimensions} ) {
		$variables{txtWidth} = [ sets::union( 'output', @{$variables{txtWidth}} ) ];
		$variables{txtHeight} = [ sets::union( 'output', @{$variables{txtHeight}} ) ];
		$variables{txtFinalWidth} = [ sets::union( 'output', @{$variables{txtFinalWidth}} ) ];
		$variables{txtFinalHeight} = [ sets::union( 'output', @{$variables{txtFinalHeight}} ) ];
	} else {
		$variables{txtWidth} = [ sets::exclude( ['output'], $variables{txtWidth} ) ];
		$variables{txtHeight} = [ sets::exclude( ['output'], $variables{txtHeight} ) ];
		$variables{txtFinalWidth} = [ sets::exclude( ['output'], $variables{txtFinalWidth} ) ];
		$variables{txtFinalHeight} = [ sets::exclude( ['output'], $variables{txtFinalHeight} ) ];
	} # end if
} # end sub set_size

sub get_overrides {
	my ( $Project, $specs ) = @_;

	my %Overrides;
	foreach my $index ( $Project->signatures({ Group=>$$specs{Group}}) ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $index );
		foreach my $qty_index ( $Project->quantity_indexes() ) {
			if ( $$sig_specs{'chkOverrideSheetSize'.$qty_index} ) {
				$Overrides{'chkOverrideSheetSize'.$qty_index} = 'Y';
# Technically, the dropdown and txtinputs should have values
				if ( ! $$sig_specs{"ddmStockSheetSize$qty_index"} ) {
#$log->error("NO ddm Stock SheetSize for $qty_index sig $index !");
				} elsif ( ! $$sig_specs{"OverrideStockWidth$qty_index"} ) {

          if ( @$sig_specs{"OverrideStockWidth$qty_index"} = $$sig_specs{"ddmStockSheetSize$qty_index"} =~ /^([\d\.]+)("? Roll)?x?\s*$/ ) {
          } elsif (
            @$sig_specs{"OverrideStockWidth$qty_index","OverrideStockHeight$qty_index"} = $$sig_specs{"ddmStockSheetSize$qty_index"} =~ /^([\d\.]+)"?\s*x\s*([\d\.]+)"?\s*$/ ) {
				} else {
					$log->error( "Failure to parse ddmStockSheetSize$qty_index: ".$$sig_specs{"ddmStockSheetSize$qty_index"});
					$$sig_specs{'chkOverrideSheetSize'.$qty_index} = '';
				}
				} # end if
				push @{$Overrides{"OverrideStockWidth$qty_index"}}, $$sig_specs{"OverrideStockWidth$qty_index"};
				push @{$Overrides{"OverrideStockHeight$qty_index"}}, $$sig_specs{"OverrideStockHeight$qty_index"};
			} # end if
			if ( $$sig_specs{"chkOverrideImposition$qty_index"} ) {
				push @{$Overrides{"chkOverrideImposition$qty_index"}}, $$sig_specs{"txtImposition$qty_index"};
			} # end if
			if ( $$sig_specs{"OverrideCutOff$qty_index"} ) {
				$Overrides{"OverrideCutOff$qty_index"} = 'Y';
				push @{$Overrides{"CutOff$qty_index"}}, $$sig_specs{"CutOff$qty_index"};
			} # end if
		} # end foreach
	} # end foreach
	return %Overrides;
} # end sub get_overrides

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	# Must clear these
	%filtered_imposition_cache = ();
	$master_time = gettimeofday();
#$log->debug("Starting Printing::calc");

	if ( ! $project_index or ! $service_index ) {
		$log->debug("No Project Index ($project_index) or Service_index ($service_index)" );
		return $$specs{Status} = 'uncalculated';
	} # end if
	$$specs{Status} = 'calculated';
	$$specs{alert} = '';
	$$specs{information} = '';
  delete $$specs{Impositions};

	if ( ( defined $$specs{PageQuantity} ) and $$specs{PageQuantity} =~ /[^\d\.]/ ) {
		$variables{PageQuantity} = [ sets::exclude( ['output'], $variables{PageQuantity} ) ];
		$$specs{PageQuantity} =~ s/[^\d\.]//g;
	} # end if

	my $Project = new openprint::Project( $project_index );
	my $ProjectType = $Project->Type();
	my $services = $Project->services();
	my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );

	$PaperServiceType = openprint::ServiceType->find_one(name=>'Paper');
	$ImpositionServiceType = openprint::ServiceType->find_one(name=>'Imposition');

# First, clean up all inputs
  $$specs{Group} //= '';
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		my $qty = $$specs{"txtQuantity$qty_index"};
		$qty =~ s/\D//g;
		$qty = $Project->quantity( $qty_index ) if ! $qty;

		if ( $qty != $$specs{"txtQuantity$qty_index"} ) {
			$$specs{"txtQuantity$qty_index"} = $qty;
			$variables{"txtQuantity$qty_index"} = [sets::union( 'output', @{$variables{"txtQuantity$qty_index"}} ) ];
		} else {
			$variables{"txtQuantity$qty_index"} = [sets::exclude( ['output'], $variables{"txtQuantity$qty_index"} ) ];
		} # end if

		# Go through every override and delete it if it isn't a Y
		foreach my $k ( @qty_override_keys, 'UnspecifiedVersions' ) {
			if ( ( ! defined $$specs{$k.$qty_index} ) or ( $$specs{$k.$qty_index} ne 'Y' ) ) {
				delete $$specs{$k.$qty_index};
			} # end if
		} # end foreach
		foreach my $k ( 'pages_supplied' ) {
			if ( ( ! defined $$specs{$k} ) or ( $$specs{$k} ne 'Y' ) ) {
				delete $$specs{$k};
			} # end if
		} # end foreach

		foreach my $k ( 'UnspecifiedVersions' ) {
			if ( ! defined $$specs{$k.$qty_index} ) {
				delete $$specs{$k.$qty_index};
			} # end if
		} # end foreach

		foreach my $k ( 'txtSignatureType', 'ScreenType', 'Group', @override_keys ) {
			delete $$specs{$k} if ! defined $$specs{$k};
		} # end foreach

		foreach my $k ( 'txtPlateChangeQuantity' ) {
			my $key = $k.$qty_index;
			next if ! exists $$specs{$key};
			if ( $$specs{$key} =~ /[^\d\-]/ ) {
				$variables{$key} = [ sets::union( 'output', @{$variables{$key}} ) ];
				$$specs{$key} =~ s/[^\d\-]//g;
			} else {
				$variables{$key} = [ sets::exclude( ['output'], $variables{$key} ) ];
			} # end if
		} # end foreach

		# This could be done in variables FIXME
		if ( $$specs{'OverrideSetup'.$qty_index} ) {
			$variables{"OverSetup$qty_index"} = [sets::exclude( ['output'], $variables{"OverSetup$qty_index"} ) ];
		} else {
			$$specs{'OverrideSetup'.$qty_index} = '';
			$variables{"OverSetup$qty_index"} = [ sets::union( 'output', @{$variables{'OverSetup'.$qty_index}} ) ];
		} # end if

		if ( $$specs{'OverrideRun'.$qty_index} ) {
			$variables{"OverRun$qty_index"} = [sets::exclude( ['output'], $variables{"OverRun$qty_index"} ) ];
		} else {
			$$specs{'OverrideRun'.$qty_index} = '';	
			$variables{"OverRun$qty_index"} = [ sets::union( 'output', @{$variables{'OverRun'.$qty_index}} ) ];
		} # end if

	} # end foreach qty_index

#$log->debug("Side one @side_one_colours twp: @side_two_colours");
	my %inkCoverage = get_inkcoverage( $Project, $specs );

	my @side_one_colours = get_colours( $specs, 'SideOne' );
	my @side_two_colours = get_colours( $specs, $$specs{side_link} ? 'SideOne' : 'SideTwo' );
	$$specs{SideOneColours} = \@side_one_colours;
	$$specs{SideTwoColours} = \@side_two_colours;

	if ( ($$ProjectType{name} eq 'PresentationFolders') 
			or ( 
				( $$specs{Group} and ( $$specs{Group} == 1 ) ) 
				and ( $$specs{rdbTemplateType} and sets::isin($$specs{rdbTemplateType}, ['2Panel1Pocket','2Panel2Pocket','TriFoldDoublePocket'] ) )
			   ) 
	   ) {
		if ( $$specs{rdbPocketSize} and ( $$specs{rdbPocketSize} ne 'Other' ) ) {
			$$specs{PocketSize} = $$specs{rdbPocketSize};	
			$variables{PocketSize} = [ sets::union( 'output', @{$variables{PocketSize}} ) ];
		} else {
			$variables{PocketSize} = [ sets::exclude( ['output'], $variables{PocketSize} ) ];
		} # end if
		if ( ! ( $$specs{rdbPanels} or $$specs{txtFinalWidth} or $$specs{txtFinalHeight} or $$specs{PocketSize} ) ) {
			return $$specs{Status} = 'uncalculated';
		} elsif ( ! ( $$specs{chkPocketCenter} or $$specs{chkPocketLeft} or $$specs{chkPocketRight} ) ) {
			$$specs{alert} .= 'Please select where you would like the pockets.';
			return $$specs{Status} = 'uncalculated';
		} # end if
	} # end if

	set_size( $Project, $specs, $printing_specs );
	if ( $$specs{txtFinalWidth} and ! ( $$specs{txtFinalWidth} =~ /^(?=.+)(?:[1-9]\d*|0)?(?:\.\d+)?$/ ) ) {
		$$specs{alert} .= 'The finished width is invalid. Please correct it.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if
	if ( $$specs{txtFinalHeight} and ! ( $$specs{txtFinalHeight} =~ /^(?=.+)(?:[1-9]\d*|0)?(?:\.\d+)?$/ ) ) {
		$$specs{alert} .= 'The finished height is invalid. Please correct it.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if

	if ( ! ( $$specs{txtWidth} and $$specs{txtHeight} ) ) {
		$$specs{alert} .= 'Please enter width and height<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if

	if ( $$ProjectType{name} eq 'PressSheetCombination' ) {
		@$specs{'txtFinalWidth','txtFinalHeight'} = @$specs{'txtWidth','txtHeight'};
	} # end if

	if ( ! $$specs{txtSignatureType} ) {
		if ( ! ( $$specs{txtFinalWidth} and $$specs{txtFinalHeight} ) ) {
			$$specs{alert} .= 'Please enter finished width and height<br/>';
			return $$specs{Status} = 'uncalculated';
		} # end if
	} # end if

	if ( ! ( $$specs{txtWidth} =~ /^(?=.+)(?:[1-9]\d*|0)?(?:\.\d+)?$/ ) ) {
		$$specs{alert} .= 'The flat width is invalid. Please correct it.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if
	if ( ! ( $$specs{txtHeight} =~ /^(?=.+)(?:[1-9]\d*|0)?(?:\.\d+)?$/ ) ) {
		$$specs{alert} .= 'The flat height is invalid. Please correct it.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if
	if ( $$specs{txtFinalWidth} and ( $$specs{txtWidth} < $$specs{txtFinalWidth} ) ) {
		$$specs{alert} .= 'Flat Width must be greater than Final Width.<br/>';
		return $$specs{Status} = 'uncalculated';
	} elsif ( $$specs{txtFinalHeight} and ( $$specs{txtHeight} < $$specs{txtFinalHeight} ) ) {
		$$specs{alert} .= 'Flat Height must be greater than Final Height.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if

	if ( ( ! $$specs{txtSignatureType} ) and ! ( $$specs{txtFinalHeight} and $$specs{txtFinalWidth} ) ) {
		$$specs{alert} .= 'Please enter the finished dimensions.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if

	my @quantity_indexes = reverse( $Project->quantity_indexes() );

	foreach my $qty_index ( @quantity_indexes ) {
		if ( $$specs{"chkOverrideImposition$qty_index"} and ! $$specs{"txtImposition$qty_index"} ) {
			$$specs{alert} .= "Please enter the desired imposition for quantity $qty_index.<br/>";
		} # end if
		if ( $$specs{"OverrideImpositionLayout$qty_index"} ) {
			
			$variables{"hdnImpositionColumns$qty_index"} = [ sets::exclude( ['output'], $variables{"hdnImpositionColumns$qty_index"} ) ];
			$variables{"hdnImpositionRows$qty_index"} = [ sets::exclude( ['output'], $variables{"hdnImpositionRows$qty_index"} ) ];
			$variables{"hdnImpositionDutchColumns$qty_index"} = [ sets::exclude( ['output'], $variables{"hdnImpositionDutchColumns$qty_index"} ) ];
			$variables{"hdnImpositionDutchRows$qty_index"} = [ sets::exclude( ['output'], $variables{"hdnImpositionDutchRows$qty_index"} ) ];
			if ( ! ( $$specs{"hdnImpositionColumns$qty_index"} and $$specs{"hdnImpositionRows$qty_index"} ) ) {
				$$specs{alert} .= "Please enter the desired imposition layout for quantity $qty_index.<br/>";
			} # end if
			if ( $$specs{"chkOverrideImposition$qty_index"} ) {
				if ( $$specs{"hdnImpositionColumns$qty_index"} * $$specs{"hdnImpositionRows$qty_index"} + $$specs{"hdnImpositionDutchColumns$qty_index"} * $$specs{"hdnImpositionDutchRows$qty_index"} != $$specs{"txtImposition$qty_index"} ) {

					$$specs{alert} .= "Overriden layout must add up to overriden Imposition.<br/>";
				} # end if
			} # end if
		} else {
			$variables{"hdnImpositionColumns$qty_index"} = [ sets::union( 'output', @{$variables{"hdnImpositionColumns$qty_index"}} ) ];
			$variables{"hdnImpositionRows$qty_index"} = [ sets::union( 'output', @{$variables{"hdnImpositionRows$qty_index"}} ) ];
			$variables{"hdnImpositionDutchColumns$qty_index"} = [ sets::union( 'output', @{$variables{"hdnImpositionDutchColumns$qty_index"}} ) ];
			$variables{"hdnImpositionDutchRows$qty_index"} = [ sets::union( 'output', @{$variables{"hdnImpositionDutchRows$qty_index"}} ) ];
		} # end if
		if ( $$specs{"chkOverrideRunStyle$qty_index"} and $$specs{"ddmRunStyle$qty_index"} ) {
			if ( ( $$specs{"ddmRunStyle$qty_index"} ne 'Sheet Work' ) and ! ( @side_one_colours and @side_two_colours ) ) {
				$$specs{alert} .= "Single sided job overriden to double sided imposition.<br/>";
			}
			if ( $$specs{"chkOverridePress$qty_index"} and $$specs{"ddmPress$qty_index"} ) {
				my $Press = openprint::Equipment->find_one(strid=>$$specs{"ddmPress$qty_index"});
				if ( !$Press ) {
					$$specs{alert} .= "Press " . $$specs{"ddmPress$qty_index"} ." no longer exists<br/>";
				} elsif ( ! sets::isin( $$specs{"ddmRunStyle$qty_index"}, [ split(',', $Press->specification('Runstyles') ) ] ) ) {
					$$specs{alert} .= "Press $$Press{name} cannot do " . $$specs{"ddmRunStyle$qty_index"}.'<br/>';
				}
			} # end if also overriden press
		}
	} # end foreach qty_index
	if ( $$specs{alert} ) {
		$log->debug("Returning early alert($$specs{alert})") if DEBUG;
		return $$specs{Status} = 'uncalculated';
	} elsif ( DEBUG ) {
		$log->debug("NOT Returning early");
	}

	if ( ! ( $$services{NoPrinting} or @side_one_colours or @side_two_colours ) ) {
		$$specs{alert} .= 'Please choose the colours to be printed.<br/>';
		return $$specs{Status} = 'uncalculated';
	} elsif ( DEBUG ) {
		$log->debug("NOT Returning early");
	} # end if

	my @Papers = get_Stocks( $Project, $specs );
	if ( ! @Papers ) {
    $$specs{alert} .= 'There was a problem loading the specified paper.';
		$log->debug("No paper: $$specs{alert}");
		return $$specs{Status} = 'uncalculated';
	} elsif ( DEBUG ) {
		$log->debug('Not Returning early due to paper');
	} # end if

	if ( $$services{NoPrinting} ) {
		foreach my $k ('txtImposition','ddmRunStyle','hdnImpositionColumns','hdnImpositionRows','hdnImpositionDutchColumns','hdnImpositionDutchRows','StockWidth','StockHeight' ) {
			foreach my $qty_index ( $Project->quantity_indexes() ) {
				$$specs{"$k$qty_index"} = $$specs{$k};
			} # end foreach
		} # end foreach K
		return $$specs{Status} = 'calculated';
	} # end if

	# For caching
	%Services = map { $$_{name}, $_ } openprint::Service->find();
	$openprint::Service::cached = 1;
	$GripperMakeReadyService = $Services{GripperMakeReady};

	%Materials = map { $$_{name}, $_ } openprint::Material->find();
	$openprint::Material::cached = 1;

	load_presses();
	my $project = setup_project( $Project, $service_index, $services, $specs, \@side_one_colours, \@side_two_colours, $Papers[0] );
	if ( $$project{NeedFolding} ) {
		if ( (
					( $$specs{txtFinalHeight} * $$specs{txtFinalWidth} ) == ( $$specs{txtHeight} * $$specs{txtWidth} ) 
					) and ! $$specs{txtSignatureType} ) {
			$$specs{alert} .= 'Folding is needed, but your finished and flat dimensions are the same!<br/>';
			return $$specs{Status} = 'uncalculated';
		} else {
$log->debug("$$specs{txtFinalHeight} * $$specs{txtFinalWidth} == ( $$specs{txtHeight} * $$specs{txtWidth} ) and ! $$specs{txtSignatureType}") if DEBUG;
		} # end if
	} else {
		if ( (
					( $$specs{txtFinalHeight} * $$specs{txtFinalWidth} ) != ( $$specs{txtHeight} * $$specs{txtWidth} ) 
					) and ! $$specs{txtSignatureType} ) {
			$$specs{alert} .= 'Folding is not required but dimensions are different.  Be sure this is what you want!<br/>';
		}
	}
	openprint::Estimating::Folding::load_equipment($Project);
	openprint::Estimating::Cutting::load_equipment($Project);
$log->debug("Before select presses: " . ( sprintf('%.4f', tv_interval( [$master_time])*1000) ) .' usecs' );
	%Presses = map { $$_{strid}, $_ } openprint::Equipment->find(
			'category any'=>'Printing',
			'useinestimating is null or ='=>1
			);
	my %presses = select_presses( $Project, \@Papers, $specs, $project );
	my @possible_presses;
	foreach my $press_id ( keys %presses ) {
		if ( ! $presses{$press_id} ) {
			push @possible_presses, new openprint::Equipment($press_id);
		} elsif ( DEBUG ) {
			$log->debug("Press: $presses{$press_id} " . new openprint::Equipment($press_id)->strid() );
		} # end if
	} # end foreach
	if ( ! @possible_presses ) {
		$$specs{alert} .= 'There were no possible presses. Your project may be too large for us.<br/>';
		foreach my $press_id ( keys %presses ) {
			$$specs{alert} .= new openprint::Equipment($press_id)->strid() . ' : ' . $presses{$press_id} . '</br>';
		} # end foreach
		return $$specs{Status} = 'uncalculated';
	} elsif ( DEBUG ) {
		$log->debug('Presses: ' . join(',', map { $_->strid() } @possible_presses));
	} # end if
	@possible_presses = sort { $$a{strid} cmp $$b{strid} } @possible_presses;
$log->debug('after sorting presses: ' . ( sprintf('%.4f', tv_interval( [$master_time])*1000) ) .' usecs there are ' . @possible_presses);

	my @available_printingtypes = sets::union( map { $_->specification('Printing Type') } @possible_presses );
  $log->debug("Available printing types: @available_printingtypes");

#$log->debug("Master time before qty: " . ( sprintf('%.4f', tv_interval( [$master_time])*1000) ) .' usecs' );
	my %threads;
	my %prices;

	foreach my $qty_index ( @quantity_indexes ) {
		if ( (!$$specs{'OverridePrice'.$qty_index}) or ( $$specs{'OverridePrice'.$qty_index} ne 'Y' ) ) {
			$$specs{"txtPrice$qty_index"} = 0;
		} else {
			$$specs{"txtPrice$qty_index"} =~ s/[^\d\.]//g;
		} # end if
		my $qty = $$specs{"txtQuantity$qty_index"};
		$qty = $Project->quantity($qty_index) if $qty eq '';
		if ( ! $qty ) {
			$log->error("There must be a qty here for qty $qty_index!");
			next;
		} # end if

		if ( $$specs{PageQuantity} ) {
			$qty *= $$specs{PageQuantity};
			$$specs{'hdnBreakdown'.$qty_index} .= " * $$specs{PageQuantity} pages = $qty: ";
		} # end if
		if ( $$specs{txtNameQuantity} ) {
			$qty *= $$specs{txtNameQuantity};
			$$specs{'hdnBreakdown'.$qty_index} .= " * $$specs{txtNameQuantity} names = $qty: ";
		} # end if

# Figure out how many spreads we need!
		if ( $$specs{txtSignatureType} ) {
#$log->debug("Master time before get_unspecified_pages: " . ( sprintf('%.4f', tv_interval( [$master_time])*1000) ) .' usecs' );
			$$specs{'txtUnspecifiedPageQuantity'.$qty_index} = get_unspecified_pages( $Project, $service_index, $specs, $qty_index );
#$log->debug("Master time after get_unspecified_pages: " . ( sprintf('%.4f', tv_interval( [$master_time])*1000) ) .' usecs' );
			if ( $$specs{'txtUnspecifiedPageQuantity'.$qty_index} > 1500 ) {
				$$specs{alert} .= 'There are far too many pages required. We will not be able to calculate this.<br/>';
				return $$specs{Status} = 'uncalculated';
			} # end if
			$log->debug("Unspecified pages for $qty_index: $$specs{'txtUnspecifiedPageQuantity'.$qty_index}");
		} elsif ( $$specs{versions} ) {
			$$specs{'UnspecifiedVersions'.$qty_index} = get_unspecified_versions( $Project, $service_index, $printing_specs, $specs, $qty_index );
			$$specs{'UnspecifiedVersions'.$qty_index} = 0 if $$specs{'UnspecifiedVersions'.$qty_index} < 0;
			$log->debug("Unspecified versions for $qty_index: $$specs{'UnspecifiedVersions'.$qty_index}");
		} # end if

#$log->debug("Master time before Previous Stock Type and Grain: " . ( sprintf('%.4f', tv_interval( [$master_time])*1000) ) .' usecs' );
		# We have to match the stock type and grain direction of previous sigs
		delete $$specs{PreviousPress};
		delete $$specs{PreviousStockType};
		delete $$specs{PreviousGrainDirection};
		foreach my $index ( $Project->signatures({ type=>$$specs{txtSignatureType} }) ) {
			next if $index >= $service_index;
			my $sig_specs = openprint::service::get_specs_ref( $Project, $index );
			if ( compare_signatures_no_results( $Project, $sig_specs, $specs ) ) {
				$$specs{PreviousPress} = $$sig_specs{'ddmPress'.$qty_index};
				$log->debug("Have previous press $$specs{PreviousPress} for group $$specs{Group}") if DEBUG and $$specs{PreviousPress};
				$$specs{PreviousStockType} = $$sig_specs{'StockType'.$qty_index};
				$$specs{PreviousGrainDirection} = $$sig_specs{'rdbGrainDirection'.$qty_index};
				last;
			}
		} # end foreach
#$log->debug("Master time after Previous Stock Type and Grain: " . ( sprintf('%.4f', tv_interval( [$master_time])*1000) ) .' usecs' );

		$$specs{PrintingTypes} = get_printing_types( $Project, $service_index, $printing_specs, $specs, $qty_index, \@available_printingtypes );
		if ( DEBUG ) {
			if ( $$specs{PrintingTypes} ) {
				$log->debug("Printing TYpes for qty$qty_index " . join(',', @{$$specs{PrintingTypes}}));
			} else {
				$log->debug('No printing types in specs');
			} # end if
			$log->debug('after get printing_types: ' . ( sprintf('%.4f', tv_interval( [$master_time])*1000) ) .' usecs' );
		} # end if

		$$project{roll2sheetcharged} = 0;
		my %previous_forms_cache;
		my %PaperCounts;
		my %PlateCounts;
#$log->debug("Master time after platecounts,roll2sheetsetup,etc, previous forms cache: " . ( sprintf('%.4f', tv_interval( [$master_time])*1000) ) .' usecs' );
		setup_counts( $Project, $service_index, $specs, $qty_index, $project, \%previous_forms_cache, \%PaperCounts, \%PlateCounts );

		if ( $$specs{'chkOverridePress'.$qty_index} ) {
			$variables{'ddmPress'.$qty_index} = [ sets::exclude( ['output'], $variables{'ddmPress'.$qty_index} ) ];
			if ( ! $$specs{'ddmPress'.$qty_index} ) {
#$log->error("No overriden press!");
				$$specs{alert} .= 'Please specify the desired press.<br/>';
				return $$specs{Status} = 'uncalculated';
			} # end if

			my $OverridePress = $Presses{$$specs{'ddmPress'.$qty_index}};
			if (! $OverridePress ) {
				$$specs{alert} .= 'Cant find the press that you have chosen.';
				return $$specs{Status} = 'uncalculated';
			} # end if

			if ( $presses{$OverridePress->id()} ) {
				$$specs{alert} .= 'The press that you have chosen is not appropriate for the following reason: ' .$presses{$OverridePress->id()};
				return $$specs{Status} = 'uncalculated';
			} # end if
		} else {
			$variables{'ddmPress'.$qty_index} = [ sets::union( 'output', @{$variables{'ddmPress'.$qty_index}} ) ];
			if ( $$printing_specs{"ddmPress-$$specs{Group}"} ) {
				my $OverridePress = $Presses{$$printing_specs{"ddmPress-$$specs{Group}"}};
				if ( !$OverridePress ) {
					$$specs{alert} .= 'The press ' . $$printing_specs{"ddmPress-$$specs{Group}"} . ' no longer exists'; 
					return $$specs{Status} = 'uncalculated';
				} elsif ( $presses{$OverridePress->id()} ) {
					$$specs{alert} .= 'The press that you have chosen '.$OverridePress->name() . ' is not appropriate for the following reason: ' .$presses{$OverridePress->id()};
					return $$specs{Status} = 'uncalculated';
				} # end if
			}
		} # end if

		if ( $$specs{'chkOverrideRunStyle'.$qty_index} ) {
			$variables{'ddmRunStyle'.$qty_index} = [ sets::exclude( ['output'], $variables{'ddmRunStyle'.$qty_index} ) ];
		} else {
			$variables{'ddmRunStyle'.$qty_index} = [ sets::union( 'output', @{$variables{'ddmRunStyle'.$qty_index}} ) ];
		} # end if
#$log->debug("SignatureType: $$specs{txtSignatureType} Group: $$specs{Group} " . $$specs{'txtUnspecifiedPageQuantity'.$qty_index});
		if ( $Project->Type()->name() eq 'ScratchPads' ) {
			# I do not understand this, but I assume it has something to do with separate backer
# 2017-01-06 So if the interior pages have 50 pages.... then txtUnspecifiedPageQuantity will be 50.... so this will multiply the # needed...
			$qty *= $$specs{'txtUnspecifiedPageQuantity'.$qty_index} if $$specs{'txtUnspecifiedPageQuantity'.$qty_index};
# 2017-01-06 But then why wipe this out?
			#$$specs{'txtUnspecifiedPageQuantity'.$qty_index} = 1;
		} # end if

		if ( $$specs{GroupPageQuantity} and ! $$specs{'txtUnspecifiedPageQuantity'.$qty_index} ) {
			$$specs{"txtImposition$qty_index"} = '';
			$$specs{"ddmRunStyle$qty_index"} = '';
			$$specs{"PageQuantity$qty_index"} = 0;
			$$specs{information} .= "No more pages need to be specified for quantity $qty_index.";
			$prices{$qty_index} = {};
			$prices{$qty_index}{complete} = 1;
			$prices{$qty_index}{Imposition} = new openprint::Imposition();
			#$prices{$qty_index}{Press} = new openprint::Equipment();
			$prices{$qty_index}{Paper} = new openprint::Paper();
			$prices{$qty_index}{Imposition}->Paper( $prices{$qty_index}{Paper} );
			$prices{$qty_index}{Imposition}->Press( $prices{$qty_index}{Press} );
			@{$prices{$qty_index}{Impositions}} = ();
			next;
		} # end if

		my %Overrides = get_overrides( $Project, $specs );
#$log->debug(Data::Dumper::Dumper( \%Overrides ) );

#$log->debug("before get_impositions: " . ( sprintf('%.4f', tv_interval( [$master_time])*1000) ) .' usecs' );
		my %impositions = get_impositions( $Project, $specs, $project, $qty, $qty_index, \@possible_presses, \@Papers, \%Overrides );
#$log->debug("after get_impositions: " . ( sprintf('%.4f', tv_interval( [$master_time])*1000) ) .' usecs' );

		convert_impositions( $Project, $project, $specs, $qty_index, \%impositions );
		if ( DEBUG_IMPOSITIONS ) {
			foreach my $press ( keys %impositions ) {
				foreach my $I ( @{$impositions{$press} } ) {
					$I->display("Initial converted_impositions");
				}
			}
		}
		
		if ( ! values %impositions ) {
			$$specs{alert} .= 'There were no possible impositions for your specifications.<br/>';
			return $$specs{Status} = 'uncalculated';
		} # end if

    # Used for setups, etc.  
    my @previous_signatures = map { $_ < $service_index ? $_ : () } sort { $a <=> $b } sort $Project->signatures();

		# These are passed along for consideration in get_project_price.	Hence they should only occur after the current service, right?
		my @signatures = map { $_ > $service_index ? $_ : () } sort { $a <=> $b } sort $Project->signatures({ Group=>$$specs{Group}});

		# These used to be calculated for Perfect Bound (and SaddleStitching).	Doing it here means it only happens once.
		my @other_impositions;
		foreach my $sig_id ( $Project->signatures() ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
# Don't try to load uncalculated sigs.	They can't count, might turn it 1 out
			next if ! $$sig_specs{'txtImposition'.$qty_index};

			# Why are we leaving out cover?	Maybe because binders tend to have a special spot for the cover.
			#next if $$sig_specs{Group} == 1;
			next if ( ($$sig_specs{Group} == $$specs{Group}) and ($sig_id >= $service_index) );
			my $I = new openprint::Imposition();
			$I->load( $sig_specs, $qty_index, $Project );
			push @other_impositions, $I;					
			if ( $$project{FoldingSpecs} ) {
				$$I{Folds} = [ openprint::Estimating::Folding::get_Folds( $$project{FoldingSpecs}, $I, $qty_index ) ];
			}
		} # end foreach sig_id
		if ( DEBUG ) {
		foreach my $I ( @other_impositions ) {
			$I->display("Initial other_impositions Group $$specs{Group}");
		}
		} 

		my %sig_specs = %{$specs};
		%stitching_cache = ();
		%price_cache = ();
		%other_group_cache = ();

		my @versions = get_versions( $specs, $qty_index ) if $$specs{versions};
#$log->debug("versions: @versions");
		$prices{$qty_index} = get_project_price( $Project, $service_index, $project, \%sig_specs, $qty, $qty_index,
      \@possible_presses, $printing_specs, \@versions, \%PlateCounts, \%PaperCounts,
      @$project{'washed_colours','mixed_colours',"AqueousMakeReadies$qty_index"},
      \%previous_forms_cache, \@signatures, \%impositions, \@other_impositions, undef, 0 );
	} # end foreach quantity

  if ($$specs{versions} ) {
    my $html = '<table> <tr> <th class="Id">#</th><th class="Description">Description</th>';
    foreach my $qty_index ( $Project->quantity_indexes() ) {
      $html .= '<th class="Quantity">Quantity ' . $qty_index . '</th>';
    } # end foreach
    $html .= '</tr>';
    my %total_qty = 0;
    foreach my $qty_index ( $Project->quantity_indexes() ) {
      foreach my $version ( 1 .. $$specs{versions} ) {
        $total_qty{$qty_index} += $$specs{"version-$version-quantity$qty_index"};
      } # end foreach version
      $openprint::log->debug("Totals: " . $total_qty{$qty_index} );
    } # end foreach

    foreach my $version ( 1 .. $$specs{versions} ) {
      $html .= sprintf('
          <tr>
          <td class="Id">%1$d</td>
          <td class="Description"><input type="text" name="version-%1$d-description" id="version-%1$d-description" value="%2$s" /></td>',
          $version, $$specs{"version-$version-description"} );
      foreach my $qty_index ( $Project->quantity_indexes() ) {
        $$specs{"version-$version-quantity$qty_index"} = 0 if $$specs{"version-$version-quantity$qty_index"} < 0;
        #if ( ! $$specs{"version-$version-quantity$qty_index"} ) {
          #$$specs{"version-$version-quantity$qty_index"} = $Project->quantity($qty_index) - $total_qty{$qty_index};
          #$$specs{"version-$version-quantity$qty_index"} = 0 if $$specs{"version-$version-quantity$qty_index"} <0;
          #$total_qty{$qty_index} += $$specs{"version-$version-quantity$qty_index"};
        #} # end if

        $html .= sprintf('<td class="Quantity"><input type="text" name="version-%1$d-quantity%2$d" id="version-%1$d-quantity%2$d" value="%3$d" on_input_this="version_qty_change" oninput="calc(\'f1\');"/></td>', $version, $qty_index, $$specs{"version-$version-quantity$qty_index"} );
      } # end foreach qty_index
      $html .= '</tr>';
    } # end foreach version
    $html .= '<tr class="totals"><td class="Id">&nbsp;</td><td class="Description">Remaining</td>';
    foreach my $qty_index ( $Project->quantity_indexes() ) {
      my $remaining = $Project->quantity( $qty_index ) - $total_qty{$qty_index};
      $html .= '<td class="Quantity'.($remaining?' error':'').'">'.$remaining.'</td>';
      if ($remaining) {
        $$specs{alert} .= "Version information is not complete for quantity $qty_index<br/>";
        $$specs{Status} = 'uncalculated';
      }
    } # end foreach qty
    $html .= '</tr></table>';

    $$specs{Version_Descriptions} = $html;
  }

	foreach my $qty_index ( @quantity_indexes ) {
		my $qty = $Project->quantity($qty_index);
		next if (! defined $qty) or ! int $qty;

		$qty *= $$specs{PageQuantity} if $$specs{PageQuantity};
		$qty *= $$specs{txtNameQuantity} if $$specs{txtNameQuantity};

		if ( !$prices{$qty_index}) {
			$$specs{alert} .= "Unable to calculate a price for printing for qty $qty_index.<br/>";
			$$specs{Status} = 'uncalculated';
      delete $$specs{'ddmPress'.$qty_index} if (!$$specs{'chkOverridePress'.$qty_index});
      delete $$specs{'ddmRunStyle'.$qty_index} if (!$$specs{'chkOverrideRunStyle'.$qty_index});
			next;
		} # end if

		my $best_price = $prices{$qty_index};
		$$specs{alert} .= $$best_price{alert} if $$best_price{alert};

		my $Imposition = $$best_price{Imposition};
		if ( ! $Imposition ) {
			$log->error("No imposition in best_price for qty $qty_index");
			$$specs{alert} .= "Unable to calculate a price for printing for qty $qty_index.<br/>";
      delete $$specs{'ddmPress'.$qty_index} if (!$$specs{'chkOverridePress'.$qty_index});
      delete $$specs{'ddmRunStyle'.$qty_index} if (!$$specs{'chkOverrideRunStyle'.$qty_index});
			$$specs{Status} = 'uncalculated';
			next;
		} else {
			$Imposition->display("Chosen impo for qty $qty_index");
		} # end if
		if ( $$Imposition{imposition} > $qty ) {
			$$specs{alert} .= "It is cheaper to print " . $$Imposition{imposition}.'.	You may wish to increase your quantity.<br/>';
		} # end if

		if ( !$$Imposition{runspeed} ) {
			$$specs{alert} .= "No runspeed for qty $qty_index.<br/>";
			$$specs{Status} = 'uncalculated';
			next;
		}
		my $Paper = $$Imposition{Paper};
    $Imposition->layout_width(undef);

		$$specs{'hdnBreakdown'.$qty_index} = breakdown($best_price, $specs);
		shift @{$$best_price{Impositions}};

		$log->debug('Additional Impositions in best price ' . @{ $$best_price{Impositions} } ) if DEBUG;
		my $price;
		my $stock_breakdown = $$best_price{'Paper Breakdown'};
		my $stitching_breakdown = $$best_price{'Stitching Breakdown'};
		foreach my $I ( @{ $$best_price{Impositions} } ) {
			$price = shift @{$$best_price{prices}};
$I->display("The price for this impo is $price left " . @{$$best_price{prices}});
			$$I{price} = $price;
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf( '<br/><b>Additional Signature %dpages %dout %s on %sx%s on %s</b><br/>', @$I{'pages', 'imposition', 'runstyle'}, $$I{Paper}{width}, $$I{Paper}{height}, $$I{Press}{strid} );
			$$specs{'hdnBreakdown'.$qty_index} .= breakdown( $price, $$I{specs} );
			$stock_breakdown = $$price{'Paper Breakdown'} if $$price{'Paper Breakdown'};
			$stitching_breakdown = $$price{'Stitching Breakdown'} if $$price{'Stitching Breakdown'};
		} # end foreach
    if ( ! $stock_breakdown ) {
      $log->error("No stock breakdown $stock_breakdown for $qty_index");
    } 

		$price = $best_price if ! $price;

		my $last_sig_price = $$price{prices}[ @{$$price{prices}} -1 ];
		#$log->warn("Final Prices:"	. @{$$price{prices}}	);

		$$specs{'hdnBreakdown'.$qty_index} .= join('', 
				( $stitching_breakdown ? $stitching_breakdown : '' ),
				( defined $$best_price{'SpinePaste Breakdown'} ? $$best_price{'SpinePaste Breakdown'} : '' ),
				( defined $$best_price{'PerfectBound Breakdown'} ? $$best_price{'PerfectBound Breakdown'} : '' ),
				$stock_breakdown,
				sprintf('Comparison Cost: $%.2f<br/>', $$best_price{ComparisonCost}),
				( defined $$best_price{'Comparison Log'} ? sprintf('Comparison Log: %s total: %s<br/>', @$best_price{'Comparison Log','ComparisonCost'}) : '' ),
			);

		$Imposition->save( $specs, $qty_index );
		@{$$specs{'Additional Impositions'.$qty_index}} = @{$$best_price{Impositions}};
if ( 1 ) {
					if ( $$best_price{Impositions} ) {
					foreach my $I ( reverse @{ $$best_price{Impositions} } ) {
					$I->display( "Results: $qty_index " );
					} # end while
					} 
}
		# Pop off the first one, because it's ours
		#shift @{$$specs{'Additional Impositions'.$qty_index}};

		save_price( $Project, $specs, $best_price, $Imposition, $qty_index );
		if ( $$specs{txtSignatureType} ) {
			if ( $$specs{'chkOverridePageQuantity'.$qty_index} ) {
				$variables{'PageQuantity'.$qty_index} = [ sets::exclude( ['output'], $variables{'PageQuantity'.$qty_index} ) ];
			} else {
				$variables{'PageQuantity'.$qty_index} = [ sets::union( 'output', @{$variables{'PageQuantity'.$qty_index}} ) ];
			} # end if
			if ( $$specs{'txtUnspecifiedPageQuantity'.$qty_index} < 0 ) {
				$$specs{alert} .= "QTY $qty_index: There are ".(-1*$$specs{'txtUnspecifiedPageQuantity'.$qty_index}). ' more pages specified than are required.	Please correct this situation.<br/>';
			} # end if
		} # end if
		if ( $Paper->message() ) {
			my $paper_message = ssi::variable_substitution( \$Paper->message(), { Project=>$Project, Stock=>$Paper, qty_index=>$qty_index } );
			if ( ! ( $$project{HasAqueous} or $$specs{AqueousMessage} ) ) {
				$$specs{AqueousMessage} = 1;
				$$specs{popup} .= $paper_message;
			} # end if
			$$specs{'PaperMessage'.$qty_index} = $paper_message;
		} # end if
		$$specs{"ImpositionImage$qty_index"} = $Imposition->to_svg();
$log->debug("Master time after qty: $qty_index" . ( sprintf('%.4f', tv_interval( [$master_time])*1000) ) .' usecs' ) if DEBUG;
	} # end foreach quantity

	# This is down here because it is a function of the results...
	$$specs{NeedCutting} = openprint::Estimating::Cutting::signature_needs( $Project, $$project{CuttingSpecs}, $specs ) if ! $$project{HasCutting};
  $log->debug("Leaving Printing::calc status: $$specs{Status}");
  if ($$specs{Status} eq 'uncalculated' and !$$specs{alert}) {
    $$specs{alert} = 'We were unable to calculate.<br/>';
    $log->debug("Leaving Printing::calc status: $$specs{Status} $$specs{alert}");
  }
	return $$specs{Status};
} # end sub calc

sub save_price( $$$$$ ) {
	my ( $Project, $specs, $price, $Imposition, $qty_index ) = @_;

	my $Press = $Imposition->Press();
	my $Paper = $Imposition->Paper();
	my $qty = $Project->quantity($qty_index);

	$$specs{'ddmBleedSize'.$qty_index} = $$Imposition{bleed_size};
	if ( $Press and $$Press{strid} ) {
#$log->debug("Press: $Press" . join(',', map { $_.'=>'.$$Press{$_} } keys %$Press ) );
		$$specs{'ddmPress'.$qty_index} = $$Press{strid};
		$$specs{'rdbPlateType'.$qty_index} = $Press->specification('Plate Type');
	} # end if Press

	if ( $Paper->id() ) {
		$$specs{'txtMWeight'.$qty_index} = $Paper->mweight() ? $Paper->mweight() : $Paper->wpsi() * $$Paper{width} * $$Paper{height} * 1000;
		$$specs{'paper_id'.$qty_index} = $Paper->id();
		$$specs{txtStockGSM} = $Paper->gsm();
		$$specs{txtSpecificStockCalliper} = $$Paper{calliper};
	} # end if
	if ( $$Paper{type} eq 'Roll' ) {
		$$specs{'ddmStockSheetSize'.$qty_index} = $$Paper{width};
		$$specs{'txtPressSheetQty'.$qty_index} = $$price{'Stock Weight'}.'lbs';
		$$specs{'minimum_stock_size'.$qty_index} = $Imposition->used_width().'&quot;';
		$$specs{'StockQuantity'.$qty_index} = $$price{'Stock Weight'};
		$$specs{'hdnNetSheetCount'.$qty_index} = $$price{'Net Sheet Count'};
	} elsif ( $$Paper{type} eq 'Sheet' ) {
		$$specs{'ddmStockSheetSize'.$qty_index} = $$Paper{width}.'x'.$$Paper{height};
    #$$specs{'ddmStockSheetSize'.$qty_index} = $$Paper{width} . '" x ' . $$Paper{height}.'"';
		$$specs{'txtPressSheetQty'.$qty_index} = $$price{'Gross Sheet Count'} .'sheets';
		$$specs{'hdnNetSheetCount'.$qty_index} = $$price{'Net Sheet Count'};
		$$specs{'StockQuantity'.$qty_index} = $$price{'Gross Sheet Count'};
		$$specs{'minimum_stock_size'.$qty_index} = sprintf('%s&quot; x %s&quot;', $Imposition->used_width(), $Imposition->used_height() );
	} else {
		$$specs{'ddmStockSheetSize'.$qty_index} = '';
		$$specs{'txtPressSheetQty'.$qty_index} = 0;
		$$specs{'hdnNetSheetCount'.$qty_index} = 0;
		$$specs{'StockQuantity'.$qty_index} = 0;
		#$$specs{alert} = 'Error: Unknown stock type.';
	} # end if
#$$specs{'hdnPaperPrice'.$qty_index} = $price{'Paper Price'};
	$$specs{'hdnSuppliedStockWidth'.$qty_index} = $$Paper{start_width};
	$$specs{'hdnSuppliedStockHeight'.$qty_index} = $$Paper{start_height};
	$$specs{'StockWidth'.$qty_index} = $$Paper{width};
	$$specs{'StockHeight'.$qty_index} = $$Paper{height};
	$$specs{'StockType'.$qty_index} = $$Paper{type};

	if ( my $plate_setup = $$price{'Plate Costs'} ) {
		$$specs{'txtPlateQuantity'.$qty_index} = $$plate_setup{'Plate Count'};
		$$specs{'BlankPlateQuantity'.$qty_index} = $$plate_setup{'Blank Plates'};
		$$specs{'PlateID'.$qty_index} = $$plate_setup{'Plate ID'};
	} # end if
#
	$$specs{'PerPlateCost'.$qty_index} = $$price{'Plate Cost'};
	$$specs{'PlateTotalCost'.$qty_index} = $$price{'Plate Price'};
	$$specs{'PlateMakeReady'.$qty_index} = $$price{'Plate Total'};

	$$specs{'RunChargeTotal'.$qty_index} = $$price{'Run Total'};
	$$specs{'PressWashPrice'.$qty_index} = $$price{'Press Wash Price'};
	$$specs{'PressWashCharge'.$qty_index} = $$price{'Press Wash Total'};
	$$specs{'PressWashes'.$qty_index} = $$price{'Press Washes'};

	if ( my $stock_qt = $$price{'Stock Quantity'} ) {
		$$specs{'OverSetup'.$qty_index} = $$stock_qt{'Initial Setup Overs'};
		$$specs{'OverRun'.$qty_index} = $$stock_qt{'Run Overs'}{total};
		$$specs{'OverTotal'.$qty_index} = $$stock_qt{'Total Overs'};
	} # end if
	$$specs{'ImpositionCharge'.$qty_index} = $$price{'Imposition Total'};
	if ( my $PageCharge = $$price{'Page Charge'} ) {
		$$specs{'PageCharge'.$qty_index} = $$PageCharge{Total};
	} # end if
	if ( my $SteppingCharge = $$price{'Stepping Charge'} ) {
		$$specs{'SteppingCharge'.$qty_index} = $$SteppingCharge{Total};
	} # end if
	$$specs{'InkTotalCharge'.$qty_index} = $$price{'Ink Price'};

	$$specs{'Roll2SheetMakeReady'.$qty_index} = $$price{Roll2SheetMakeReady};
	$$specs{'Roll2SheetRunCharge'.$qty_index} = $$price{Roll2SheetRunCharge};
	$$specs{'StockSetupCharge'.$qty_index} = $$price{StockSetup};
	$$specs{'hdnImpressionQuantity'.$qty_index} = $$price{Impressions};
#$$specs{'RunTime'.$qty_index} = $price{RunTime};
	$$specs{'Runspeed'.$qty_index} = $$price{Runspeed};

	if ( ( ! defined $$specs{'OverridePrice'.$qty_index} ) or $$specs{'OverridePrice'.$qty_index} ne 'Y' ) {
		if ( $$specs{pages_supplied} and ( $$specs{pages_supplied} eq 'Y' ) ) {
			$$specs{'txtPrice'.$qty_index} = sprintf($openprint::config{ProjectMoneyFormat}, 0 );
		} else {
			my $total_price = $$price{'Total Cost'};
			$total_price *= (1+$$specs{'Markup'.$qty_index}/100) if $$specs{'Markup'.$qty_index};
			$total_price *= (1+$Project->markup()/100) if $Project->markup();
			$$specs{'txtPrice'.$qty_index} = sprintf($openprint::config{ProjectMoneyFormat}, $total_price );
		} # end if
	} else {
		$$specs{'txtPrice'.$qty_index} = sprintf($openprint::config{ProjectMoneyFormat}, $$specs{'txtPrice'.$qty_index} );
	} # end if
	my $unitprice = $$price{'Total Cost'} / $qty;
	$unitprice *= 1+$Project->markup()/100 if $Project->markup();
	$$specs{'txtUnitPrice'.$qty_index} = sprintf($openprint::config{UnitPriceFormat}, $unitprice );
	my $mprice = $$price{'Impression MPrice'} / $$Imposition{imposition} if $$Imposition{imposition};
	my $rate = ($$price{'Run Overs'}{total}/$qty)*1000;
	my $ink = ($$price{'Ink Price'}/$qty)*1000;

	$mprice = $rate * ($mprice + $ink);
	if ( $_ = $$specs{'Markup'.$qty_index} ) {
		$mprice *= (1+($_/100));
	}
	if ( $_ = $Project->markup() ) {
		$mprice *= (1+($_/100));
	}

	$$specs{'MPrice'.$qty_index} = Math::Round::nearest( 0.01, $mprice );
#$log->debug("MPrice: Rate: $rate Impression: $price{'Impression MPrice'}/$$Imposition{imposition}=$mprice, Ink: (($price{'Ink Price'}/$qty)*1000 )=$ink, PaperM: $price{'Paper 1000 Price'}");

	if ( $Project->Type()->name() eq 'ScratchPads' ) {
# $qty was multiplied by this earlier, so the signature should represent all pages.
		$$specs{'PageQuantity'.$qty_index} = $$specs{'txtUnspecifiedPageQuantity'.$qty_index};
		$$specs{'txtUnspecifiedPageQuantity'.$qty_index} = 0;
	}elsif ( $$specs{txtSignatureType} ) {
		#if ( ! ( ( defined $$specs{'chkOverridePageQuantity'.$qty_index} ) and ( $$specs{'chkOverridePageQuantity'.$qty_index} eq 'Y' ) ) ) {
			$$specs{'PageQuantity'.$qty_index} = $$Imposition{pages};
		#} else {
			#$log->debug(
		#} # end if
		$$specs{'txtUnspecifiedPageQuantity'.$qty_index} -= $$specs{'PageQuantity'.$qty_index};
	} elsif ( DEBUG ) {
		$log->debug("No txtSignatureType");
	} # end if
} # end sub save_price

sub breakdown {
	my ( $price, $specs ) = @_;

	if ( ! $$price{Imposition} ) {
		$log->debug("No imposition in breakdown Price:$price imposition:$$price{Imposition}");
		foreach my $k ( keys %{$price} ) {
			$log->debug("price key $k => $$price{$k}");
		} # end foreach
		return '';
	} # end if

	my $Imposition = $$price{Imposition};
	my $Paper = $$Imposition{Paper};
	my $Press = $$Imposition{Press};
	my $stock_qty = $$price{'Stock Quantity'};

	my $breakdown = '';
	$breakdown .= openprint::Estimating::Imposition::signature_summary( $Imposition, $$price{'Imposition Price'} ) if $$price{'Imposition Price'} and $ImpositionServiceType;
	$breakdown .= sprintf('%s Colour Bar %f %s, Bleed: %s Orientation: %s<br/>', ( $Press ? $$Press{strid} : '' ), @$Imposition{'colour_bar_size','colour_bar_orientation','bleed_size'},
		$Imposition->image_orientation_text() );
	$breakdown .= '<b>Setups</b><br/>';
	if ( $$price{GripperSetup} ) {
		$breakdown .= sprintf('Gripper Setup: $%.2f<br/>', $$price{GripperSetup}{Price} );
	}
	$breakdown .= $$price{'Setup Breakdown'};
	$breakdown .= sprintf('Roll2Sheet Charge: $%.2f<br/>', $$price{Roll2SheetMakeReady} ) if $$price{Roll2SheetMakeReady};
	$breakdown .= sprintf('Stock Setup: $%1$.2f<br/>', $$price{StockSetup} ) if $$price{StockSetup};
  if ( $$price{SuppliedPaperPrice} and ($$openprint::User{type} ne 'C' ) ) {
    my $SuppliedPaperPrice = $$price{SuppliedPaperPrice};
    if ( $$SuppliedPaperPrice{units} eq 'per 100lbs' ) {
      $breakdown .= sprintf('Supplied Stock Handling Charge: $%1$.2f%2$s * %4$d/100 = $%3$.2f<br/>',
        @$SuppliedPaperPrice{'Price','units','Total'}, $$price{'Stock Weight'});
    } elsif ( $$SuppliedPaperPrice{units} eq 'per sheet' ) {
      $breakdown .= sprintf('Supplied Stock Handling Charge: $%1$.2f%2$s * %4$d = $%3$.2f<br/>',
        @$SuppliedPaperPrice{'Price','units','Total'}, $$price{'Gross Sheet Count'});
    } elsif ( $$SuppliedPaperPrice{units} eq 'per m' ) {
      $breakdown .= sprintf('Supplied Stock Handling Charge: $%1$.2f%2$s * %4$d/1000 = $%3$.2f<br/>',
        @$SuppliedPaperPrice{'Price','units','Total'}, $$price{'Gross Sheet Count'});
    } elsif ( $$SuppliedPaperPrice{units} eq 'total' ) {
      $breakdown .= sprintf('Supplied Stock Handling Charge: $%1$.2f%2$s = $%3$.2f<br/>',
        @$SuppliedPaperPrice{'Price','units','Total'});
    } # end if
  }
  if ( $$Imposition{versions} ) {
    my $VersionPrice = $$price{'Version Price'};	
    my $version_qty = 0;
    foreach my $v (@{$$price{versions}}) {
      $version_qty += 1 if $$Imposition{versions}{$$v{index}};
#$breakdown .= $$price{versions};
      #if ($$price{versions} and $$price{versions}{$v_index}) {
        $breakdown .= 'Includes '.$$Imposition{versions}{$$v{index}}.'out of '.$$v{description}.'<br/>';
      #}
    }
    $breakdown .= sprintf('Version Charge: $%1$.2f %2$s for %4$d versions = $%3$.2f<br/>', @$VersionPrice{'Price','units','Total'}, $version_qty );

	} # end if
	$breakdown .= openprint::Estimating::Imposition::signature_summary( $Imposition, $$price{'Imposition Price'} ) if $$price{'Imposition Price'} and ! $ImpositionServiceType;

	if ( defined $$price{'Runstyle Charge'} ) {
		my $RunStyleCharge = $$price{'Runstyle Charge'};
		$breakdown .= sprintf('%s Charge: $%.2f<br/>', @$RunStyleCharge{'ServiceName','Price'} );
	}
	$breakdown .= sprintf($$Imposition{runstyle}.' Dry Cost:$%.2f<br/>', @$price{'WorkTurn Dry Charge'} ) if $$price{'WorkTurn Dry Charge'};
	$breakdown .= sprintf('Press Wash Charge: $%.2f * %d washes = $%.2f<br/>', @$price{'Press Wash Price','Press Washes','Press Wash Total'}) if $$price{'Press Washes'};
	$breakdown .= sprintf('Plate Make Ready: $%.2f%s * %dplates * %d runs = $%.2f<br/>', @$price{'Plate Setup Price','Plate Setup Units','Plate Setup Count', 'Plate Runs', 'Plate Total'} );
	$breakdown .= sprintf('Setup Total: $%.2f<br/><b>Run Charges:</b><br/>', $$price{'Setup Total'} );
	$breakdown .= sprintf('Roll2Sheet Charge: $%1$.2f%2$s=%3$.2f<br/>', @$price{'Roll2SheetRunCost','Roll2SheetUnits','Roll2SheetRunCharge'} ) if $$price{Roll2SheetRunCharge};
  if (!@{$$price{'Run Prices'}}) {
    $breakdown .= '<span class="warning">No run prices?</span><br/>';
  } else {
    foreach my $run_price ( @{$$price{'Run Prices'}} ) {
      if ( $_ = $Press->Specification('Charge for setup overs') and $$_{value} eq 'N' ) {
        $breakdown .= sprintf('%s %s %d/(%d Per Hour) * $%.2f%s = $%.2f<br/>',
            @$run_price{'side','ServiceName'}, ( $$run_price{impressions}-$$stock_qty{'Setup Overs'} ),@$run_price{'run_speed','Price','units','Total'} );
      } else {
        $breakdown .= sprintf('%s %s %d/(%d Per Hour) * $%.2f%s = $%.2f<br/>',
            @$run_price{'side','ServiceName','impressions','run_speed','Price','units','Total'} );
      } # end if
    } # end foreach run price /pass
  }

	$breakdown .= sprintf('Minimum Run Charge: $%.2f<br/>', $$price{'Minimum Run Charge'} ) if $$price{'Minimum Run Charge'} and ( $$price{'Minimum Run Charge'} == $$price{'Run Total'} );
	$breakdown .= sprintf('Run Charge Total:$%.2f<br/>', $$price{'Run Total'} );
	$breakdown .= '<b>Material Charges:</b><br/>';
	if ( my $plate_costs = $$price{'Plate Costs'} ) { 
		if ( $$plate_costs{'Plate ID'} ) {
		$breakdown .= sprintf( 'Plates: %d %s * $%.2f per plate = $%.2f<br/>', @$plate_costs{'Plate Count','Plate ID'}, @$price{'Plate Cost','Plate Price'});
		$breakdown .= sprintf( 'Blank Plates: %d plates * $%.2f per plate = $%.2f<br/>', @$plate_costs{'Blank Plates','Blank Price'}, $$plate_costs{'Blank Price'} * $$plate_costs{'Blank Plates'}) if defined $$plate_costs{'Blank Plates'};
		}
	} # end if

	if ( $stock_qty ) {
		my $RunOvers = $$price{'Run Overs'};
		$breakdown .= sprintf('<b>Overs:</b><br/>
<table class="overs">
  <tr><td>Initial Setups:</td><td>%s*%d=</td><td class="value">%d</td></tr>
  <tr><td>Additional Setups:</td><td>%d*%d=</td><td class="value">%d</td></tr>
  <tr><td> Run:</td><td> %dimpressions @ %.2f %s =</td><td class="value">%d</td></tr>',
					@$stock_qty{
          'Initial Setup Rate','Initial Setup Count','Initial Setup Overs',
          'Additional Setup Rate','Additional Setup Count','Additional Setup Overs'},
					@$RunOvers{'impressions','value','units','total'},
        );
    $breakdown .= '<tr class="fm"><td>FM:</td><td></td><td class="value">'.$$stock_qty{'FM Overs'}.'</td></tr>' if $$stock_qty{'FM Overs'};
    $breakdown .= sprintf('<tr><td>Additional Plate:</td><td>%d * %d changes (minimum %d) =</td><td class="value">%d</td></tr>
  <tr><td>Bindery:</td><td>',
					@$stock_qty{'Additional Plate Overs Rate','Plate Changes',
          'Additional Plate Overs Minimum','Additional Plate Overs',
          }
 );
		$breakdown .= ' Folding: MR '.$$stock_qty{FoldingMakeReadyOvers}. ' + Run '.$$stock_qty{FoldingRunOvers}.'</br>' if $$stock_qty{FoldingMakeReadyOvers} or $$stock_qty{FoldingRunOvers};
		$breakdown .= ' Cutting: ' . $$stock_qty{CuttingOvers}.'</br>' if $$stock_qty{CuttingOvers};
		$breakdown .= ' Scoring: '.$$stock_qty{ScoringOvers}.'<br/>' if $$stock_qty{ScoringOvers};
		$breakdown .= ' DieCutting: ' . $$stock_qty{DieCuttingOvers}.'<br/>' if $$stock_qty{DieCuttingOvers};
		$breakdown .= ' UV Coating: ' . $$stock_qty{UVOvers}.'<br/>' if $$stock_qty{UVOvers};
    $breakdown .= '</td><td class="value">'.$$stock_qty{'BinderyOvers'}.'</td></tr>';
		$breakdown .= '<tr class="totals"><td>Total Overs:</td><td></td><td class="value"> ' . $$stock_qty{'Total Overs'}.'</td></tr>';
		$breakdown .= '<tr ><td>Net Sheets:</td><td></td><td class="value"> ' . $$stock_qty{'Net Sheet Count'}.'</td></tr>';
		$breakdown .= '<tr ><td>Gross Sheets:</td><td></td><td class="value"> ' . $$stock_qty{'Gross Sheet Count'}.'</td></tr>';
    $breakdown .= '</table>';
		$breakdown .= ' Used Minimum Overs ' if $$stock_qty{'Minimum Overs'} and ( $$stock_qty{'Minimum Overs'} == $$stock_qty{'Total Overs'} );
		$breakdown .= '<br/>';
	} # end if
	if ( $Paper->type() ne 'Roll' ) {
		$breakdown .= sprintf( '%sx%s starting %sx%s<br/>', $Paper->width(), $Paper->height(), $Paper->start_width(), $Paper->start_height() );
		$breakdown .= "Paper: $$price{'Gross Sheet Count'} sheets @".$Paper->mweight() . 'M = ' . $$price{'Gross Sheet Count'} * $Paper->mweight()/1000 . 'lbs<br/>';
		$breakdown .= " minimum order adjustment $$price{minimum_order}sheets<br/>" if $$price{minimum_order};
	} elsif ( $Paper->width() ) {
		$breakdown .= sprintf('Paper: %sx%s -> %sx%s * %.6flbs/sq inch = %.6f lbs per sheet (%d gsm, %sPT) Total: %slbs<br/>', $Paper->start_width(), $Paper->start_height(), $Paper->width(), $Paper->height(), $Paper->wpsi(), $Paper->width() * $Paper->height()* $Paper->wpsi(), $Paper->gsm(), 1000*$Paper->calliper(), $$price{'Stock Weight'} );
	} # end if
	$breakdown .= $$price{'Ink breakdown'};
	$breakdown .= sprintf('Ink Total: $%.2f<br/>', $$price{'Ink Price'} );
	$breakdown .= sprintf('Total: $%.2f<br/>', $$price{'Total Cost'} );
	$breakdown .= join('', 
			( defined $$price{'Proofs Breakdown'} ? $$price{'Proofs Breakdown'} : '' ),
			( defined $$price{'UVCoating Breakdown'} ? $$price{'UVCoating Breakdown'} : '' ),
			( defined $$price{'Aqueous Breakdown'} ? $$price{'Aqueous Breakdown'} : '' ),
			( defined $$price{'Cutting Breakdown'} ? $$price{'Cutting Breakdown'} : '' ),
			( defined	$$price{'Numbering Breakdown'} ? $$price{'Numbering Breakdown'} : '' ),
			( defined $$price{'DieCutting Breakdown'} ? $$price{'DieCutting Breakdown'} : '' ),
			( defined $$price{'Folding Breakdown'} ? $$price{'Folding Breakdown'} : '' ),,
			( defined $$price{'Scoring Breakdown'} ? 'Scoring: '.$$price{'Scoring Breakdown'} : '' ),
			( defined $$price{'Perforating Breakdown'} ? $$price{'Perforating Breakdown'} : '' ),
			);

	return $breakdown;
} # end sub breakdown

# impositions is a hash of imps for each press
sub calculate_impositions {
	my ( $Project, $sig_specs, $qty_index, $qty, $PaperCounts, $versions, $project, $impositions ) = @_;
	my $filter_time = gettimeofday() if DEBUG_FILTERING;

	my @impositions;
	my $needed_pages = 0;
	if ( $Project->Type()->name() eq 'ScratchPads' ) {
		$needed_pages = 0;
	} elsif ( $$sig_specs{txtSignatureType} ) {
$log->debug("Group $$sig_specs{Group} unspecd " . $$sig_specs{'txtUnspecifiedPageQuantity'.$qty_index} . ' wanted: ' . $$project{ProjectSpecs}{"PageQuantity-$$sig_specs{Group}"} ) if DEBUG;
		if ( $$sig_specs{'chkOverridePageQuantity'.$qty_index} ) {
			$needed_pages = int( $$sig_specs{'PageQuantity'.$qty_index} );
$log->debug("Using overriden page quantity $needed_pages");
		} elsif ( $$project{ProjectSpecs}{"PageQuantity-$$sig_specs{Group}"} and 
				( $$project{ProjectSpecs}{"PageQuantity-$$sig_specs{Group}"} <= $$sig_specs{'txtUnspecifiedPageQuantity'.$qty_index} )
				) {
			$needed_pages = $$project{ProjectSpecs}{"PageQuantity-$$sig_specs{Group}"};
		} else {
			$needed_pages = $$sig_specs{'txtUnspecifiedPageQuantity'.$qty_index};
		} # end if
		if ( !$needed_pages ) {
			$log->debug('calculate_impositions with no needed_pages!!!! ' . $$sig_specs{'txtUnspecifiedPageQuantity'.$qty_index});
			return ();
		}
		if ( $needed_pages < 2 ) {
			$log->warn("Bailing early cuz can't do less than a 2pg signature");
			return ();
		}
	} # end if
	$log->debug("calculate _impositions: Needed pages: $needed_pages") if DEBUG;

	my $filter_press = '';
	if ( $$sig_specs{"chkOverridePress$qty_index"} ) {
		$filter_press = $$sig_specs{"ddmPress$qty_index"};
		$log->debug('Have Override Press ' . $filter_press . ' from chkOverride');
  } elsif ($$project{ProjectSpecs}{"ddmPress-$$sig_specs{Group}"}) {
		$filter_press = $$project{ProjectSpecs}{"ddmPress-$$sig_specs{Group}"};
		$log->debug('Have Override Press ' . $filter_press . ' from book specs');
	} elsif ( $$sig_specs{PreviousPress} ) {
		$filter_press = $$sig_specs{PreviousPress};
		$log->debug("Have PreviousPress $$sig_specs{PreviousPress} from $$sig_specs{SignatureIndex}");
	}

	foreach my $strid ( $filter_press ? $filter_press : keys %{$impositions} ) {
		if ( ! ( $$impositions{$strid} and @{$$impositions{$strid}} ) ) {
		  $log->debug("calculate_impositions: No impositions for $strid");
			next;
		}
		my $Press = $Presses{$strid};

		if ( ! $Press ) {
			$log->error("No Press for $strid");
			next;
		} # end if

		if ( (!defined $$Press{useinestimating}) and (
					(!$$sig_specs{"chkOverridePress$qty_index"}) and ( ! ( $$project{ProjectSpecs}{"ddmPress-$$sig_specs{Group}"}  and ( $$project{ProjectSpecs}{"ddmPress-$$sig_specs{Group}"} eq $strid ) ) )
)
) {
			$log->debug("Not doing $$Press{strid} because it is not overriden") if DEBUG;
			next;
		}

		if ( $$sig_specs{PrintingTypes} 
			and ( !$$sig_specs{"chkOverridePress$qty_index"} )
      and ( !$$project{ProjectSpecs}{"ddmPress-$$sig_specs{Group}"} )
			and ( !$$sig_specs{"OverridePrintingType$qty_index"} )
			and ( !$$project{ProjectSpecs}{"PrintingType-$$sig_specs{Group}"} )
			) {
			my $printing_type = $Press->specification('Printing Type');
			if ( $printing_type and ! sets::isin( $printing_type, $$sig_specs{PrintingTypes} ) ) {
				next;
        #} else {
        #$log->error("NO skipping because of PrintingTypes press $$Press{strid} sig:$$sig_specs{PrintingTypes} type: $printing_type");
			} # end if
      #} else {
      #$log->error("NO skipping because of PrintingTypes press $$Press{strid} sig:$$sig_specs{PrintingTypes}");
		} # end if

		my @press_impositions = @{ $$impositions{$strid} };
		if ( DEBUG_FILTERING ) {
			$log->debug("QTY_index: $qty_index before filtering impositions count:" . @press_impositions . ' on press: ' . $Press->strid());
			foreach my $imp ( openprint::imposition::sort( @press_impositions ) ) {
				$imp->display();
			} # end foreach
		} # end if

		if ( $needed_pages ) {
			my %max_impositions;
			foreach my $I ( @press_impositions ) {
				next if $needed_pages < $$I{pages};
				$max_impositions{$$I{pages}} = $$I{imposition} if (!exists $max_impositions{$$I{pages}}) or $$I{imposition} > $max_impositions{$$I{pages}};
			} # end foreach
			my @keys = keys %max_impositions;
			my $max_pages;
			if ( @keys ) {
				$log->debug("Max pages: @keys") if DEBUG_FILTERING;
				$max_pages = sets::max( @keys );
				#$log->debug(" needed pages $needed_pages max: $max_pages spreadsize: $$project{txtSpreadSize} press $$Press{strid} impositions: " . @press_impositions);
				$max_pages = Math::Round::nearest(1, $max_pages / 3 );
				$max_pages = $$project{txtSpreadSize} if $max_pages < $$project{txtSpreadSize};
        $max_pages -= 1 if $max_pages %2;
				$log->debug("Max pages: $max_pages") if DEBUG_FILTERING;
			} else {
				$max_pages = $$project{txtSpreadSize};
				$log->warn("No Max pages setting to $max_pages");
			}

			foreach my $pages ( @keys ) {
				$max_impositions{$pages} = int($max_impositions{$pages} / 4 );
			} # end foreach

			foreach my $I ( @press_impositions ) {
				next if $needed_pages < $$I{pages};
				if ( $max_impositions{$$I{pages}} > $$I{imposition}) {
# Only do this if not sheet size overrides
					$I->display("Max imposition! for $$I{pages} is $max_impositions{$$I{pages}} > $$I{imposition} ") if DEBUG_FILTERING;
					next;
				} 
				if (($max_pages > $$I{pages}) and ( !$$sig_specs{'chkOverridePageQuantity'.$qty_index}) ) {
					$I->display("Max pages: max $max_pages >= imp " . $$I{pages} ) if DEBUG_FILTERING;
					next;
				} # end if
				push @impositions, $I;
			} # end foreach 
		} else {
			push @impositions, @press_impositions;
		} # end if needed_pages

	} # end foreach press

	if (!@impositions) {
		$log->debug('No impsoitions!');
		return ();
	} 

	if ( $$sig_specs{'chkOverrideSheetSize'.$qty_index} ) {
		if ( ! $$sig_specs{"ddmStockSheetSize$qty_index"} ) {
			$log->debug("NO ddm Stock SheetSize for $qty_index!") if DEBUG_FILTERING;
		} elsif ( ! $$sig_specs{"OverrideStockWidth$qty_index"} ) {
			if ( $$sig_specs{"StockType$qty_index"} eq 'Roll' ) {
				@$sig_specs{"OverrideStockWidth$qty_index"} = $$sig_specs{"ddmStockSheetSize$qty_index"} =~ /^([\d\.]+)("? Roll)?\s*$/;
			} else {
				@$sig_specs{"OverrideStockWidth$qty_index","OverrideStockHeight$qty_index"} = $$sig_specs{"ddmStockSheetSize$qty_index"} =~ /^([\d\.]+)"?\s*x?\s*([\d\.]+)?"?\s*$/;
			} # end if
			if ( ! $$sig_specs{"OverrideStockWidth$qty_index"} ) {
				$log->error( "Failure to parse ".$$sig_specs{"ddmStockSheetSize$qty_index"});
				$$sig_specs{'chkOverrideSheetSize'.$qty_index} = '';
			}
		} # end if
	}

	my @results;

	if ( $$sig_specs{txtSpreadSize} == 2 ) {
		foreach my $imp ( @impositions ) {
			if ( $$imp{pages} > 4 and ( $needed_pages % $$imp{pages} == 2 ) ) {
				if ( DEBUG_FILTERING ) {
					$imp->display("DROPPING BECUASE it leaves a 2pg");
				}
				next;
			}
			push @results, $imp;
		}
		if ( ! @results ) {
			$log->debug('no non-2pg options available');
		} else {
			@impositions = @results;
			@results = ();
		}
	}			

	my %grain_direction_imps;

	foreach my $imp ( @impositions ) {
		if ( $$project{ProjectSpecs}{"ddmRunStyle-$$sig_specs{Group}"} and ( $$project{ProjectSpecs}{"ddmRunStyle-$$sig_specs{Group}"} ne $$imp{runstyle} ) ) {
			$log->debug("Doesn't match book runstyle override " . $$imp{runstyle} . ' != ' . $$project{ProjectSpecs}{"ddmRunStyle-$$sig_specs{Group}"} ) if DEBUG_FILTERING;
			next;
		}
		if ( (exists $$sig_specs{'chkOverrideRunStyle'.$qty_index}) and ( $$sig_specs{'chkOverrideRunStyle'.$qty_index} eq 'Y' ) and ( $$imp{runstyle} ne $$sig_specs{'ddmRunStyle'.$qty_index} ) ) {
			$log->debug("Doesn't match runstyle override " . $$imp{runstyle} . ' != ' . $$sig_specs{'ddmRunStyle'.$qty_index}) if DEBUG_FILTERING;
			next;
		} # end if

		my $Paper = $imp->Paper();
		if ( (exists $$sig_specs{'chkOverrideSheetSize'.$qty_index}) and ( $$sig_specs{'chkOverrideSheetSize'.$qty_index} eq 'Y' ) ) {
			if ( 
					( $$Paper{width} != $$sig_specs{"OverrideStockWidth$qty_index"} ) or 
					( $$sig_specs{"OverrideStockHeight$qty_index"} and ( $$Paper{height} != $$sig_specs{"OverrideStockHeight$qty_index"} ) )) {
				$imp->display('Not overriden sheet size! ' . $$sig_specs{"OverrideStockWidth$qty_index"} . 'x' . $$sig_specs{"OverrideStockHeight$qty_index"} ) if DEBUG_FILTERING;
				next;
			} else {
#$imp->display('Accepted stock! ' . $$sig_specs{"OverrideStockWidth$qty_index"} . 'x' . $$sig_specs{"OverrideStockHeight$qty_index"} );
			} # end if
		} # end if
		if ( (exists $$sig_specs{'OverrideCutOff'.$qty_index}) and ( $$sig_specs{'OverrideCutOff'.$qty_index} eq 'Y' ) ) {
			if ( $$Paper{height} != $$sig_specs{"CutOff$qty_index"} ) {
				$imp->display('Not overriden cutoff! ' ) if DEBUG_FILTERING;
				next;
			} # end if
		}	# end if

		if ( ( $$sig_specs{'MatchGrain'.$qty_index} and ( $$sig_specs{'MatchGrain'.$qty_index} eq 'Y' ) ) and $$sig_specs{PreviousStockWidth} and $$Paper{width} > $$sig_specs{PreviousStockWidth} ) {
			$imp->display("PreviousStockWidth: $$sig_specs{PreviousStockWidth} < " . $Paper->to_string() ) if DEBUG_FILTERING;
			next;
		} # end if

		if ( $$sig_specs{PreviousStockType} and ( $$Paper{type} ne $$sig_specs{PreviousStockType} ) ) {
			$imp->display("PreviousStockType: $$sig_specs{PreviousStockType} ne " . $Paper->to_string() ) if DEBUG_FILTERING;
			next;
		} # end if

		if ( $$sig_specs{'chkOverrideGrainDirection'.$qty_index}  and ( $$sig_specs{'chkOverrideGrainDirection'.$qty_index} eq 'Y' ) ) {
			if ( $$imp{dutch_columns} ) {
				$imp->display("Has Dutch") if DEBUG_FILTERING;
				next;
			} # end if
#$log->debug("Grain Direction override: " . $imp->grain_direction() . " ne " . $$sig_specs{'rdbGrainDirection'.$qty_index} ) if $imp->grain_direction() ne $$sig_specs{'rdbGrainDirection'.$qty_index};
			if ( $$sig_specs{'rdbGrainDirection'.$qty_index} eq 'Long' ) {

				$imp->display("Grain override") if DEBUG_FILTERING;
				if ( ( $imp->grain_direction() eq 'width' ) and ( $imp->object_width() < $imp->object_height() ) ) {
					$imp->display("Grain override next") if DEBUG_FILTERING;
					next;
				} elsif ( ( $imp->grain_direction() eq 'height' ) and ( $imp->object_width() > $imp->object_height() ) ) {
					$imp->display("Grain override next") if DEBUG_FILTERING;
					next;
				}	# end if
			} elsif ( $$sig_specs{'rdbGrainDirection'.$qty_index} eq 'Short' ) {
				if ( ( $imp->grain_direction() eq 'width' ) and ( $imp->object_width() > $imp->object_height() ) ) {
					$imp->display("Grain needs short ") if DEBUG_FILTERING;
					next;
				} 
				if ( ( $imp->grain_direction() eq 'height' ) and ( $imp->object_width() < $imp->object_height() ) ) {
					$imp->display("Grain needs short ") if DEBUG_FILTERING;
					next;
				} # end if
			} elsif ( $$sig_specs{'rdbGrainDirection'.$qty_index} and ( $imp->grain_direction() ne $$sig_specs{'rdbGrainDirection'.$qty_index} ) ) {
				$imp->display("Grain needs	" . $$sig_specs{'rdbGrainDirection'.$qty_index} ) if DEBUG_FILTERING;
				next;
			} # end if
		} elsif ( 
$$sig_specs{PreviousGrainDirection} and ( $imp->grain_direction() ne $$sig_specs{PreviousGrainDirection} ) ) {
			if ( ($$sig_specs{'MatchGrain'.$qty_index} and ($$sig_specs{'MatchGrain'.$qty_index} eq 'Y')) or ( $grain_direction_imps{join(',',$qty_index, @$imp{'imposition','columns','runstyle'})} ) ) {
				$imp->display("PreviousGrainDirection: $$sig_specs{PreviousGrainDirection} ne " . $imp->grain_direction() ) if DEBUG_FILTERING;
				next;
			}
		} # end if

		if ( $needed_pages > 0 ) {
			if ( $$sig_specs{PreviousImposition} and ( $$sig_specs{PreviousImposition} > $$imp{imposition} ) ) {
				$imp->display("Previous Imposition") if DEBUG_FILTERING;
				next;
			} # end if
			if ( $$project{ProjectSpecs}{"PageQuantity-$$sig_specs{Group}"} and
        ( $$project{ProjectSpecs}{"PageQuantity-$$sig_specs{Group}"} <= $$sig_specs{'txtUnspecifiedPageQuantity'.$qty_index} ) ) {
				if ( $$imp{pages} != $$project{ProjectSpecs}{"PageQuantity-$$sig_specs{Group}"} ) {
					$imp->display('Doesnt match group page quantity override want: ' . $$project{ProjectSpecs}{"PageQuantity-$$sig_specs{Group}"} ) if DEBUG_FILTERING;
					next;
				} # end if
			} # end if
			if ( $$sig_specs{'chkOverridePageQuantity'.$qty_index}  and ( $$sig_specs{'chkOverridePageQuantity'.$qty_index} eq 'Y' ) ) {
				if ( $$imp{pages} != $$sig_specs{'PageQuantity'.$qty_index} ) {
					$imp->display('Doesnt match page quantity override want: ' . $$sig_specs{'PageQuantity'.$qty_index}) if DEBUG_FILTERING;
					next;
				} # end if
			} # end if chkOverridePageQuantity
		} # end if needed_pages
		push @results, $imp;
		$imp->display('Good') if DEBUG_FILTERING;
	} # end foreach imp

# Now filter by imposition
	if ( $$sig_specs{'chkOverrideImposition'.$qty_index} and ( $$sig_specs{'chkOverrideImposition'.$qty_index} eq 'Y' ) ) {
		$log->debug("Override Imposition: $qty_index, " . $$sig_specs{'txtImposition'.$qty_index}) if DEBUG_FILTERING;

		my @results2;
		foreach my $strid ( $$sig_specs{"chkOverridePress$qty_index"} ? ( $$sig_specs{"ddmPress$qty_index"} ) : keys %{$impositions} ) {

			my @press_impositions = map { $$_{Press}{strid} eq $strid ? $_ : ()  } @results;

			my @matching_impositions = map { $$_{imposition} == $$sig_specs{'txtImposition'.$qty_index} ? $_ : () } @press_impositions;
			if ( DEBUG_FILTERING ) {
				if ( @matching_impositions ) {
					foreach my $i ( @matching_impositions ) {
						$i->display("Matched");
					}
				}else{
					foreach my $i ( @press_impositions ) {
						$i->display("Not Matched");
					}
				}
			}
			if ( ! @matching_impositions ) {

				$log->debug( " Didn't find the desired imposition, so cutting them down.");
				my @lesser_imps = map { $$_{imposition} > $$sig_specs{'txtImposition'.$qty_index} ? $_ : () } @press_impositions;
				while ( @lesser_imps and ! @matching_impositions ) {
					@lesser_imps = map { $$_{imposition} >= $$sig_specs{'txtImposition'.$qty_index} ? $_ : () } openprint::imposition::decrease_imposition( @lesser_imps );
					@matching_impositions = map { $$_{imposition} == $$sig_specs{'txtImposition'.$qty_index} ? $_ : () } @lesser_imps;
					$log->debug( " matching imps: " . @matching_impositions );
					foreach ( @matching_impositions ) {
						$_->display("After cutting:" . $$sig_specs{'txtImposition'.$qty_index} );
					}
				} # end while

			} # end if
			push @results2, @matching_impositions;
		} # end foreach Press
		@results = @results2;
	} else {
		$log->debug("NOT Override Imposition: $qty_index, " . $$sig_specs{'txtImposition'.$qty_index} . ' ' . $$sig_specs{'chkOverrideImposition'.$qty_index} ) if DEBUG_FILTERING;
		if ( $$sig_specs{'txtQuantity'.$qty_index} and @results ) {
			my $needs_smaller = 1;
			foreach my $I ( @results ) {
				if ( $$I{imposition} <= $$sig_specs{'txtQuantity'.$qty_index} ) {
					$needs_smaller = 0;
					last;
				} # end if
			} # end foreach I
			if ( $needs_smaller ) {
				$log->debug("Need smaller impositions, we have " . @results ) if DEBUG;
				my @lesser = @results;
				
				do {
					@lesser = openprint::imposition::decrease_imposition( @lesser );
					@results = map { $$_{imposition} <= $$sig_specs{'txtQuantity'.$qty_index} ? $_ : () } @lesser;
				} until ( @results );
				$log->debug("Needed smaller impositions, we have " . @results ) if DEBUG;
	if ( 0 ) {
				foreach my $I ( openprint::imposition::get_all_impositions( @results ) ) {
					if ( $I->imposition() <= $$sig_specs{'txtQuantity'.$qty_index} ) {
						push @results, $I;
					} # end if
				} # end foreach I
	}
			} # end if
		} # end if quantity
	} # end if
	if ( $$sig_specs{"OverrideImpositionLayout$qty_index"} and ( $$sig_specs{"OverrideImpositionLayout$qty_index"} eq 'Y' ) ) {
		my @filtered_impos = map {(	
				$$_{columns} == $$sig_specs{"hdnImpositionColumns$qty_index"} and
				$$_{rows} == $$sig_specs{"hdnImpositionRows$qty_index"} and
				int($$_{dutch_columns}) == int($$sig_specs{"hdnImpositionDutchColumns$qty_index"}) and
				int($$_{dutch_rows}) == int($$sig_specs{"hdnImpositionDutchRows$qty_index"}) ) ? $_ : () 
		} @results;
		if ( ! @filtered_impos ) {
			foreach my $i ( @results ) {
				if ( 
						$$i{columns} >= $$sig_specs{"hdnImpositionColumns$qty_index"} and
						$$i{rows} >= $$sig_specs{"hdnImpositionRows$qty_index"} and
						int($$i{dutch_columns}) >= int($$sig_specs{"hdnImpositionDutchColumns$qty_index"}) and
						int($$i{dutch_rows}) >= int($$sig_specs{"hdnImpositionDutchRows$qty_index"}) )	{
					my $i2 = $i->copy();
					$i2->columns( $$sig_specs{"hdnImpositionColumns$qty_index"} );
					$i2->rows( $$sig_specs{"hdnImpositionRows$qty_index"} );
					$i2->dutch_columns( $$sig_specs{"hdnImpositionDutchColumns$qty_index"} );
					$i2->dutch_rows( $$sig_specs{"hdnImpositionDutchRows$qty_index"} );
					push @filtered_impos, $i2;
				} # end if
			} # end foreach i
		} # end if
		@results = @filtered_impos;
	} # end if $$sig_specs{"OverrideImpositionLayout$qty_index"} eq 'Y'
			
	if ( DEBUG_FILTERING ) {
    $openprint::log->debug("After first round of filtering");
		foreach my $I ( @results ) {
			$I->display("After first round of filtering");
		}
	}


	# Filter by press value, so... all other things being the same, just size of press.
	my %imps = ();
	if ( (!$$sig_specs{"chkOverridePress$qty_index"}) and ( @results > 1 ) ) {
		my $bump_count = 0;
		foreach my $I ( @results ) {
			my $Paper = $$I{Paper};
			my $Press = $$I{Press};
			my $AValue = $Press_Values{$$Press{id}};

			my $key = join(',', @$Paper{'width','height'}, @$I{'pages','page_columns','image_orientation','imposition','columns','runstyle'} );
			if ( ! ( $imps{$key} and @{$imps{$key}} ) ) {
				$imps{$key} = [ $I ];
				next;
			} # end if
			my $add = 1;
			if ( $AValue ) {
				for ( my $i = 0; $i < @{$imps{$key}}; $i += 1 ) {
					my $B = $imps{$key}[$i];
					my $BPress = $$B{Press};
					my $BValue = $Press_Values{$$BPress{id}};
					if ( $BValue ) {
						my $BPaper = $$B{Paper};
						if ( $BValue > $AValue and ( $Paper->area() <= $BPaper->area() ) ) {
							splice @{$imps{$key}}, $i, 1;
							$i -= 1;
							$bump_count += 1;
						} elsif ( $BValue < $AValue and ( $BPaper->area() <= $Paper->area() ) ) {
							$add = 0;
							last;
						} # end if
					} else {
						$log->error("1 No Value set for $$BPress{strid}");
					} # end if	
					
				} # end for B
			} else {
				$log->error("2 No Value set for $$Press{strid}");
			} # en dif
			if ( $add ) {
				push @{$imps{$key}}, $I;
			} else {
				$bump_count += 1;
			}
		} # end foreach I

		$log->debug("Bumped $bump_count for Press") if DEBUG_FILTERING;
		$bump_count = 0;
		@results = map {@{$_}} values %imps;
	} # end if

	%imps = ();
	if ( DEBUG_FILTERING ) {
		$log->debug('After filtering by Press');
		foreach my $I ( @results ) {
			$I->display('After filtering by Press');
		}
	}

	# Filter dutches, which don't happen for books
	if ( ( ! $needed_pages ) and ( @results > 1 ) ) {
		my $bump_count = 0;
		$log->debug("about to filter Dutch for @results") if DEBUG;
		foreach my $I ( @results ) {
#$I->display() if DEBUG;
			my $Paper = $$I{Paper};
			my $Press = $$I{Press};
#$I->display( "after paper and press" ) if DEBUG;

			my $key = join(',', $Paper->area(), $$I{imposition}, $$I{runstyle}, $$Press{strid} );
			if ( ! $imps{$key} ) {
				$imps{$key} = [ $I ];
				next;
			} # end if
			my $add = 1;
			for ( my $i = 0; $i < @{$imps{$key}}; $i += 1 ) {
				my $B = $imps{$key}[$i];
				if ( $$B{dutch_columns} and ! $$I{dutch_columns} ) {
					splice @{$imps{$key}}, $i, 1;
					$i -= 1;
					$bump_count += 1;
				} elsif ( $$I{dutch_columns} and ! $$B{dutch_columns} ) {
					$add = 0;
					last;
				} # end if
			} # end for B
			if ( $add ) {
				push @{$imps{$key}}, $I;
			} else {
				$bump_count += 1;
			} # end if
		} # end foreach I

		$log->debug("Bumped $bump_count for Dutch") if $bump_count;
		
		$bump_count = 0;
		@results = map {@{$_}} values %imps;
		%imps = ();
		if ( DEBUG_FILTERING ) {
			$log->debug("Afgter filtering by dutch");
			foreach my $I ( @results ) {
				$I->display("After filtering by dutch");
			}
		}
	} # end if SpreadL

	foreach my $imp ( @results ) {
		my $add = 1;
		my $Paper = $$imp{Paper};
#$imp->display('Filtering:');

# My thoughts here:	have to base it purely on this sig. Need to look up price by total, but compare based just on this sig.
		# in initial filtering, we loaded up stock_lbs, not stock_qty, so this will run every time.
		if ( ! $$imp{stock_qty} ) {
			my $stock_qty = POSIX::ceil( $qty/$$imp{imposition} );
			if ( $needed_pages > 0 and $$sig_specs{"txtUnspecifiedPageQuantity$qty_index"} > $$imp{pages} ) {
				$stock_qty *= int( $$sig_specs{"txtUnspecifiedPageQuantity$qty_index"} / $$imp{pages} );
			} # end if
			my $lookup_stock_qty = $stock_qty;

			if ( $$Paper{type} eq 'Roll' ) {
				# Convert to weight
				$stock_qty = int( $stock_qty * $Paper->area() * $Paper->wpsi() );

				if ( ! exists $$PaperCounts{$Paper->id_string()} ) {
					$lookup_stock_qty = $stock_qty;
					if ( DEBUG ) {
						$log->debug("No stock in papercounts for " . $Paper->id_string());
						foreach my $k ( keys %{$PaperCounts} ) {
							$log->debug("PaperCounts: $k => $$PaperCounts{$k}");
						}
					}
				} else {
					$lookup_stock_qty = $stock_qty + $$PaperCounts{$Paper->id_string()};
				}

	#$log->debug("Roll stock_weight $stock_qty Lookup impressioions: $lookup_stock_qty");
#$imp->display(" qty in paper counts. " . $$PaperCounts{$Paper->id_string()} );
#if ( ! $$PaperCounts{$Paper->id_string()} ) {
	#$log->debug("This: " . $Paper->id_string() );
	#foreach my $k ( keys %{$PaperCounts} ) {
#$log->debug("Paper Counts: $k => $$PaperCounts{$k}");
	#} # end 
#}
			if ( $lookup_stock_qty < $Paper->minimum_order_weight() ) {
				$stock_qty = $lookup_stock_qty = $Paper->minimum_order_weight();
			} # end if
			} else { # Sheet
				
				# Sheets can be cut, so we need to price them based on the Supplied sheet
				my $SuppliedPaper = $Paper->Supplied();

				$stock_qty /= $Paper->factor(); # Convert to supplied sheets?
				$lookup_stock_qty /= $Paper->factor(); # Convert to supplied sheets?

				if ( ! exists $$PaperCounts{$SuppliedPaper->id_string()} ) {
					if ( DEBUG ) {
						$log->debug("No stock in papercounts for " . $SuppliedPaper->id_string());
						foreach my $k ( keys %{$PaperCounts} ) {
							$log->debug(" $k => $$PaperCounts{$k}");
						}
					}
				} else {
					$lookup_stock_qty += $$PaperCounts{$SuppliedPaper->id_string()};
				}
	#$log->debug("Sheets $stock_qty Lookup impressioions: $lookup_stock_qty");
				my $conversion = $SuppliedPaper->area() * $SuppliedPaper->wpsi();
				$stock_qty = POSIX::ceil( $stock_qty * $conversion );
				$lookup_stock_qty = POSIX::ceil( $lookup_stock_qty * $conversion );

				if ( $lookup_stock_qty < $SuppliedPaper->minimum_order_weight() ) {
					$stock_qty = $lookup_stock_qty = $SuppliedPaper->minimum_order_weight();
				} # end if
	#$log->debug("Sheet weight $stock_qty Lookup impressioions: $lookup_stock_qty");
			} # end if
			$$imp{old_stock_qty} = $$imp{stock_qty};
			$$imp{stock_qty} = $stock_qty;
			$$imp{lookup_stock_qty} = $lookup_stock_qty;
		} # end if ! stock_qty

#foreach my $k ( keys %{$PaperCounts} ) {
#$log->debug("Whats in papercounts: $k $$PaperCounts{$k}");
#} # end foreach

		my $SmallerPrice;
    if ( ! int($$imp{stock_qty}) ) {
      $log->error("Noo stock qty: ($$imp{stock_qty}) " . $Paper->to_string() );
      $imp->display("qty: $qty unspec ". $$sig_specs{"txtUnspecifiedPageQuantity$qty_index"} );
    }
    #if ( $$imp{PaperPrice} ) {
			#$SmallerPrice = $$imp{PaperPrice};
		#} else {
		$$imp{PaperPrice} = $SmallerPrice = $Paper->get_price( weight=>$$imp{stock_qty}, lookup_qty => $$imp{lookup_stock_qty}, service=>'Material' ) if (!$$imp{old_stock_qty}) or $$imp{old_stock_qty} != $$imp{stock_qty};
		#} # end if

		if ( $needed_pages > 0 ) {
			my $str = join(',', $$imp{Press}{id}, @$imp{'pages','spread_columns','spread_rows','columns','rows','runstyle','image_orientation','bleed_size'}, $$Paper{type} );
			if ( $imps{$str} ) {
				for ( my $j = 0; $j < @{$imps{$str}}; $j += 1 ) {
					my $I = $imps{$str}[$j];
					$I->display('Considering B') if DEBUG_FILTERING;
					my $P = $$I{Paper};

					if ( $$sig_specs{'chkOverrideSheetSize'.$qty_index} and ($$sig_specs{'chkOverrideSheetSize'.$qty_index} eq 'Y') and ( $$P{width} == $$sig_specs{"OverrideStockWidth$qty_index"}) and ( $$P{height} == $$sig_specs{"OverrideStockHeight$qty_index"} )) {
						next;
					} elsif ( $$sig_specs{'OverrideCutOff'.$qty_index} and ($$sig_specs{'OverrideCutOff'.$qty_index} eq 'Y') and ( $$P{height} == $$sig_specs{"CutOff$qty_index"} ) ) {
						next;
					} # end if
					my $BiggerPrice = $$I{PaperPrice};
					if ( DEBUG_FILTERING ) {
						$imp->display("Comparing A mino weight:" . $Paper->minimum_order_weight() . 'Price: ' . $$SmallerPrice{'100lb Price'} . ' total: ' . $$SmallerPrice{'100lb Total'} . ' cut' . $Paper->is_cut() . ' factor: ' . $Paper->factor() . ' stock_qty: ' . $$imp{stock_qty} . ' lookup_stock_qty' . $$imp{lookup_stock_qty} );
						$I->display("Comparing B mino weight:". $P->minimum_order_weight() . ' Price: ' . $$BiggerPrice{'100lb Price'} . ' total: ' . $$BiggerPrice{'100lb Total'} .' cut ' . $P->is_cut() . ' factor: ' . $P->factor() . ' stock_qty: ' . $$I{stock_qty}. ' lookup_stock_qty' . $$I{lookup_stock_qty} );
					} 
					#if ( ( ! ( $$sig_specs{'txtUnspecifiedPageQuantity'.$qty_index} % $$imp{pages} ) )
							#and ( $P->factor() <= $Paper->factor() )
							#and ( $$BiggerPrice{'100lb Total'} >= $$SmallerPrice{'100lb Total'} )
						#) {
## There won't be any additional signatures, so we can compare directly on value
						#splice @{$imps{$str}}, $j, 1;
						#$j -= 1;
						#if ( DEBUG_FILTERING	or 1) {
							#$log->debug( "Dropping weird	Bigger $$BiggerPrice{'100lb Total'} " . $P->minimum_order_weight() . " $$SmallerPrice{'100lb Total'}" . $Paper->minimum_order_weight() );
							#$I->display( 'B' );
							#$imp->display( 'A' );
						#} # end if DEBUG

					#} elsif ( ( $P->area() >= $Paper->area() )
					# I Think this is basically.. if the price difference is so huge... just drop it.
					if ( $$BiggerPrice{'100lb Total'} > 10 * $$SmallerPrice{'100lb Total'} ) {
						splice @{$imps{$str}}, $j, 1;
						$j -= 1;
						if ( DEBUG_FILTERING ) {
							$log->debug( "10 Dropping B on price $$BiggerPrice{'100lb Total'} " . $P->minimum_order_weight() . " $$SmallerPrice{'100lb Total'}" . $Paper->minimum_order_weight() );
							$I->display();
							$imp->display();
						} # end if
					} elsif ( 10*$$BiggerPrice{'100lb Total'} < $$SmallerPrice{'100lb Total'} ) {
							$add = 0;
							if ( DEBUG_FILTERING ) {
								$log->debug( "10 Dropping A on price 100lb: $$BiggerPrice{'100lb Total'} minorderweight:" . $P->minimum_order_weight() . " $$SmallerPrice{'100lb Total'}" . $Paper->minimum_order_weight() );
								$I->display();
								$imp->display();
							} # end if
							last;

					} elsif ( ( $P->area() >= $Paper->area() )
							#and ( $P->factor() <= $Paper->factor() )
							and ( $P->minimum_order_weight() >= $Paper->minimum_order_weight() or $Paper->minimum_order_weight() > $$imp{lookup_stock_qty} )
							and ( $$BiggerPrice{'100lb Total'} >= $$SmallerPrice{'100lb Total'} )
							and ( $P->is_cut() or ! $Paper->is_cut() )
							) {
						splice @{$imps{$str}}, $j, 1;
						$j -= 1;
						if ( DEBUG_FILTERING ) {
							$log->debug( "Dropping B price:$$BiggerPrice{'100lb Total'} lookupweight: $$I{lookup_stock_qty} minorderweight:" . $$I{Paper}->minimum_order_weight() . " smaller price; $$SmallerPrice{'100lb Total'} lookupweight: $$imp{lookup_stock_qty} minorderweight:" . $Paper->minimum_order_weight() );
							$I->display('B');
							$imp->display('A');
						} # end if
					} elsif ( ( $P->area() <= $Paper->area() )
							#and ( $P->factor() >= $Paper->factor() )
							and ( $P->minimum_order_weight() <= $Paper->minimum_order_weight() or $P->minimum_order_weight() < $$I{lookup_stock_qty} )
							and ( $$BiggerPrice{'100lb Total'} <= $$SmallerPrice{'100lb Total'} )
							and ( ( ! $P->is_cut() ) or ( $Paper->is_cut() ) )
							) {
							$add = 0;
							if ( DEBUG_FILTERING ) {
								$log->debug( "Dropping A 100lb:$$BiggerPrice{'100lb Total'} lookupweight: $$I{lookup_stock_qty} minorderweight:" . $$I{Paper}->minimum_order_weight() . " $$SmallerPrice{'100lb Total'} lookupweight: $$imp{lookup_stock_qty} minorderweight:" . $Paper->minimum_order_weight() );
								$I->display('B');
								$imp->display('A');
							} # end if
							last;
						} elsif ( DEBUG_FILTERING ) {
							$log->debug( "Not Dropping B: $$BiggerPrice{'100lb Total'} A $$SmallerPrice{'100lb Total'}");
							$I->display();
							$imp->display();
						} # end if

					} # end if
				} # end for

			push @{$imps{$str}}, $imp if $add;
		} else { # No SpreadLayout
# if not multipage... can make a relatively definit determination about stock qty... not exact... but better.

			my $str = join('-', @$imp{'imposition','columns','rows','runstyle','image_orientation','bleed_size'}, $imp->Press()->id() );
			if ( $imps{$str} ) {
				for ( my $j = 0; $j < @{$imps{$str}}; $j += 1 ) {
					my $I = $imps{$str}[$j];
					my $P = $$I{Paper};

					my $BiggerPrice = $$I{PaperPrice};
					if ( DEBUG_FILTERING ) {
						$imp->display("Comparing A mino weight:" . $Paper->minimum_order_weight() . 'Price: ' . $$SmallerPrice{'100lb Price'} . ' total: ' . $$SmallerPrice{'100lb Total'} . ' cut' . $Paper->is_cut() . ' factor: ' . $Paper->factor() . ' stock_qty: ' . $$imp{stock_qty} . ' lookup_stock_qty' . $$imp{lookup_stock_qty} );
						$I->display("Comparing B mino weight:". $P->minimum_order_weight() . ' Price: ' . $$BiggerPrice{'100lb Price'} . ' total: ' . $$BiggerPrice{'100lb Total'} .' cut ' . $P->is_cut() . ' factor: ' . $P->factor() . ' stock_qty: ' . $$I{stock_qty}. ' lookup_stock_qty' . $$imp{lookup_stock_qty} );
					} 

					if ( ($$sig_specs{'chkOverrideSheetSize'.$qty_index} and ($$sig_specs{'chkOverrideSheetSize'.$qty_index} eq 'Y'))
							and ( $P->width() == $$sig_specs{"OverrideStockWidth$qty_index"} )
							and ( (! $$sig_specs{"OverrideStockHeight$qty_index"} ) or $P->height() == $$sig_specs{"OverrideStockHeight$qty_index"} )) {
						next;
					} elsif ( ( $$sig_specs{'OverrideCutOff'.$qty_index} and ( $$sig_specs{'OverrideCutOff'.$qty_index} eq 'Y' ) ) and ( $P->height() == $$sig_specs{"CutOff$qty_index"} ) ) {
						next;
					} # end if
					if ( ( $P->area() >= $Paper->area() )
							and ( $P->factor() <= $Paper->factor() )
							and ( $P->minimum_order_weight() >= $Paper->minimum_order_weight() )
							and ( (1*$$BiggerPrice{'100lb Total'}) >= (1*$$SmallerPrice{'100lb Total'}) )
							and ( ! ( ( ! $P->is_cut() ) and $Paper->is_cut() ) )
						) {
						splice @{$imps{$str}}, $j, 1;
						if ( DEBUG_FILTERING ) {
							$log->debug( "Dropping B $$BiggerPrice{'100lb Total'} $$SmallerPrice{'100lb Total'}");
							$I->display('B');
							$imp->display('A');
						}

						$j -= 1;
					} elsif ( ( $P->area() < $Paper->area() )
							and ( $P->factor() >= $Paper->factor() )
							and ( $P->minimum_order_weight() <= $Paper->minimum_order_weight() )
							and ( (1*$$BiggerPrice{'100lb Total'}) <= (1*$$SmallerPrice{'100lb Total'}) )
							and ( ( ! $P->is_cut() ) or ( $Paper->is_cut() ) )
							) {
						if ( DEBUG_FILTERING ) {
							$log->debug( "Dropping A $$BiggerPrice{'100lb Total'} $$SmallerPrice{'100lb Total'}");
							$imp->display();
						}
						$add = 0;
						last;
					} elsif ( DEBUG_FILTERING ) {
						$log->debug( "Not Dropping $$BiggerPrice{'100lb Total'} $$SmallerPrice{'100lb Total'} add: $add");
						$I->display();
						$imp->display();
					} # end if
				} # end for
			} # end if overriden or not or cached
			push @{$imps{$str}}, $imp if $add;
		} # end if ServerLaoutout
	} # end foreach imp
	@results = map {@{$_}} values %imps;
	if ( DEBUG_FILTERING ) {
		$log->debug("Afgter filtering by paper # of results: " . @results );
		foreach my $I ( @results ) {
			$I->display("After filtering by paper");
		}
	}
	if ( ! $$project{NeedAqueous} ) {
		my %undesireables = map { $_ => 1 } ( 'Sheet Work','Work & Turn','Work & Tumble' );
		%imps = ();
		my $bump_count = 0;
		foreach my $I ( @results ) {
			my $Paper = $$I{Paper};
			my $key = join(',', $Paper->area(), $$I{pages}, $$I{image_orientation}, $$I{imposition}, $$I{runstyle}, $I->Press()->id() );
			if ( ! ( $imps{$key} and @{$imps{$key}} ) ) {
				$imps{$key} = [ $I ];
				next;
			} # end if
			my $add = 1;
			for ( my $i = 0; $i < @{$imps{$key}}; $i += 1 ) {
				my $B = $imps{$key}[$i];
				if ( ($$I{runstyle} eq 'Perfecting') and $undesireables{$$B{runstyle}} ) {
					splice @{$imps{$key}}, $i, 1;
					$i -= 1;
					$bump_count += 1;
				} elsif ( ($$B{runstyle} eq 'Perfecting') and $undesireables{$$I{runstyle}} ) {
					$add = 0;
					last;
				} # end if
			} # end for each imp
			if ( $add ) {
				push @{$imps{$key}}, $I;
			} else {
				$bump_count += 1;
			} # end if
		} # end foreach I
		$log->debug("Bumped $bump_count for Perfecting vs Sheet Work") if DEBUG_FILTERING;
	} # end if

	if ( $third_level_filtering and !$$sig_specs{"chkOverrideImposition$qty_index"} ) {
		@results = map {@{$_}} values %imps;
		if ( DEBUG_FILTERING ) {
			foreach my $I ( @results ) {
				$I->display("After second round of filtering");
			}
		}
		%imps = ();
		my $bump_count = 0;
# Now need to look at each paper and filter out small impositions
# Can also look at cases where same roll width, different cut off... but less impo... seems to me we want to maximize plate usage
		foreach my $I ( @results ) {
			my $Paper = $$I{Paper};
			my $key = join('-',@$Paper{'width','height','minimum_order'}, @$I{'pages','image_orientation','runstyle'}, $I->Press()->id() );

			if ( ! ( $imps{$key} and @{$imps{$key}} ) ) {
				$imps{$key} = [ $I ];
				next;
			} # end if

			my $add = 1;
			for ( my $i = 0; $i < @{$imps{$key}}; $i += 1 ) {
				my $B = $imps{$key}[$i];
				if ( ( $$B{imposition} < $$I{imposition} ) and ( $$B{dutch_columns} or ! $$I{dutch_columns} ) ) {
					splice @{$imps{$key}}, 0, 1;
					$i -= 1;
					$bump_count += 1;
					next;
				} elsif ( ( $$B{imposition} > $$I{imposition} ) and ( $$I{dutch_columns} or ! $$B{dutch_columns} ) ) {
					$add = 0;
					last;
				} # end if
			} # end for
			if ( $add ) {
				push @{$imps{$key}}, $I;
			} else {
				$bump_count += 1;
			}
		} # end foreach I
		$log->debug("Bumped $bump_count impos in 3rd filtering") if DEBUG_FILTERING;
		$bump_count = 0;
if ( 0 ) {
		@results = map {@{$_}} values %imps;
		%imps = ();
		foreach my $I ( @results ) {
$I->display("Considering");
			my $Paper = $$I{Paper};
			my $key = join('-',@$Paper{'width','minimum_order'}, @$I{'pages','image_orientation','runstyle', 'columns'} );
			if ( ! ( $imps{$key} and @{$imps{$key}} ) ) {
				$imps{$key} = [ $I ];
				next;
			} # end if
			my $add = 1;
			for ( my $i = 0; $i < @{$imps{$key}}; $i += 1 ) {
				my $B = $imps{$key}[$i];

				if ( $$B{imposition} < $$I{imposition} ) {
					my $paper_factor = Math::Round::nearest( 1, $Paper->height() / $B->Paper()->height() );
					my $impo_factor = $$I{imposition} / $$B{imposition};
					if ( $paper_factor > $impo_factor ) {
$B->display("Bumping B paper_factor $paper_factor impo factor: $impo_factor ") if DEBUG_FILTERING;
						splice @{$imps{$key}}, 0, 1;
						$i -= 1;
						$bump_count += 1;
						next;
					} 
				} elsif ( $$B{imposition} > $$I{imposition} ) {
					my $paper_factor = Math::Round::nearest( 1, $B->Paper()->height() / $Paper->height() );
					my $impo_factor = $$B{imposition} / $$I{imposition};
					if ( $paper_factor > $impo_factor ) {
$I->display("Bumping A paper_factor $paper_factor impo factor: $impo_factor ") if DEBUG_FILTERING;
						$add = 0;
							last;
					} # en dif
				} # end if
			} # end for	
			if ( $add ) {
				push @{$imps{$key}}, $I;
			} else {
				$bump_count += 1;
			}
		} # end foreach I
		$log->debug("Bumped $bump_count impos in 4th filtering");
}
	} # end if 3rd
	@impositions = map {@{$_}} values %imps;

	$log->debug("Press Impositions after filtering: " . @impositions . sprintf(' %.4f', tv_interval( [$filter_time])*1000) ) if DEBUG_FILTERING;
	if ( ( $$sig_specs{versions} and ( $$sig_specs{versions} > 1 ) ) and ( @impositions < 30 ) ) {
		$log->debug("Calling do_versions, # of imps: " . @impositions ) if DEBUG_VERSIONS;
		@impositions = openprint::imposition::do_versions( $versions, \@impositions );
		$log->debug("Back from do_versions, # of imps: " . @impositions ) if DEBUG_VERSIONS;
	} # end if
# Gives us both inline and offline folding options
#if ( $$project{HasFolding} and ( $_ = $Press->Specification('Folding Capable') ) and ( $_ eq 'Y' ) ) {
#@impositions = map { openprint::Estimating::Folding::impositions( $Project, $_, $$project{FoldingSpecs}, $sig_specs, $qty_index ) } @impositions;
#$log->debug("Impositions for Press: " . $$Press{strid} . ' after folding:' . @impositions) if DEBUG;
#} # end if Folding

	if ( DEBUG_FILTERING ) {

		$log->debug($qty_index.'UPQ:'.$$sig_specs{'txtUnspecifiedPageQuantity'.$qty_index} . ' # ' . @impositions );
		foreach my $imp ( @impositions ) {
			$imp->display();
		} # end foreach
	} # end if
	return @impositions;
} # end sub calculate_impositions

sub get_new_specs {
	my ( $Project, $service_index, $service_specs, $signatures, $qty_index, $upq, $previous_forms_cache, $hash_key ) = @_;
	my $s_id = $service_index;
	my %new_specs;

	if ( $s_id ) {

		if ( 0 ) {
# Look for overrides first. 
			for ( my $j = 0; $j < @$signatures; $j += 1 ) {
# This code can theortically unsort the sognatures, so we shouldn't really have special cases for when the s_id is greater than the current one.
				if ( $$signatures[$j] != $s_id ) {
#$log->debug("Consider sig in overrides $s_id");
					my $sig_specs2 = openprint::service::get_specs_ref( $Project, $$signatures[$j] );
					foreach my $override ( 'chkOverridePageQuantity','chkOverrideImposition', 'chkOverridePress','chkOverrideRunStyle' ) {
						if ( ( defined $$sig_specs2{$override.$qty_index} ) and ( $$sig_specs2{$override.$qty_index} eq 'Y' ) ) {
							$s_id = $$signatures[$j];
							splice @$signatures, $j, 1;
							%new_specs = %{$sig_specs2};
#$log->debug("Found sig in overrides $override $s_id");
							last;
						} # end if
					} # end foreach override
					last if $s_id != $service_index;
				} else {
					splice @$signatures, $j, 1;
					$j -= 1;
				} # end if
			} # end foreach
		}

# If we get here, @signatures has been cleaned out, and no overrides found.
		#if ( ( $s_id == $service_index ) and @$signatures ) {
		if ( @$signatures ) {
			$s_id = shift @$signatures;
			%new_specs = %{openprint::service::get_specs_ref( $Project, $s_id )};
# Not neccessary to empty the overrides, because we went looking for them above, and didn't find them
#$log->debug("Found sig without	overrides $s_id");
		} # end if
	} # end if s_id, meaning dealing with existing sigs
# If we didn't get a new s_id, then we are using fake services
	if ( $s_id == $service_index ) {
		$s_id = 0;

		%new_specs = %$service_specs;
		$new_specs{SignatureIndex} += 100;
# These will only have an effect if we get down to call get_project_price. If we get there, we are looking at a smaller # of pages, so might want a different press.
# Mostly want the same press due to colour matching
		$new_specs{'chkOverrideImposition'.$qty_index} = '';
		$new_specs{'chkOverridePageQuantity'.$qty_index} = '';
		$new_specs{'chkOverridePress'.$qty_index} = '';
		$new_specs{'chkOverrideRunStyle'.$qty_index} = '';
		$new_specs{'chkOverrideSheetSize'.$qty_index} = '';
	} 
#elsif ( ( defined $new_specs{'chkOverridePageQuantity'.$qty_index} ) and ( $new_specs{'chkOverridePageQuantity'.$qty_index} eq 'Y' ) and ( $new_specs{'PageQuantity'.$qty_index} > $upq ) ) {
#if ( $new_specs{PreviousPress} ) {
		#$log->error("Have previous press $new_specs{PreviousPress} in get_new_specs");
#}
		#$new_specs{'chkOverridePageQuantity'.$qty_index} = '';
	#} # end if

# Need to update these too.	
	$new_specs{'PreviousForms'.$qty_index} = $$previous_forms_cache{$hash_key} ? $$previous_forms_cache{$hash_key} : 0;
	$new_specs{'txtUnspecifiedPageQuantity'.$qty_index} = $upq;
#$log->debug("Setting upq to $upq");
	$new_specs{ServiceIndex} = $s_id;
	return \%new_specs;
} # end sub get_new_specs

sub get_project_price {
	if ( $openprint::r ) {
		$openprint::r->print("\n");
		if ( $openprint::r->connection()->aborted() ) {
			$log->warn('ABORTED');
			return {};
		} # end if
	} # end if
	my ( $Project, $service_index, $project, $source_sig_specs, $qty, $qty_index, $possible_presses, $printing_specs, $versions, $PlateCounts, $PaperCounts, $washed_colours, $mixed_colours, $aq_makereadies, $previous_forms_cache, $signatures, $impositions, $other_impositions, $best_price, $recursion_depth ) = @_;
	my %best_price = $best_price ? %{$best_price} : ();
	$log->debug("Best price: $recursion_depth starting get_project_price: ($best_price{ComparisonCost}) ($best_price{ComparisonCost}) UPQ " . $$source_sig_specs{'txtUnspecifiedPageQuantity'.$qty_index} ) if DEBUG_FILTERING;

	my $services = $Project->services();
	my $txtUnspecifiedPageQuantity = $$source_sig_specs{'txtUnspecifiedPageQuantity'.$qty_index};

	my $previous_press = $$source_sig_specs{PreviousPress};
	my %sig_specs = %{$source_sig_specs};

	#my @Is = openprint::imposition::sort( calculate_impositions( $Project, $sig_specs, $qty_index, $qty, $PaperCounts, $versions, $project, $impositions ) );
	my @Is = calculate_impositions( $Project, $source_sig_specs, $qty_index, $qty, $PaperCounts, $versions, $project, $impositions );
  if (!@Is) {
    $log->error('No impositions from calculate_impositions') if DEBUG;
    if ($$project{ProjectSpecs}{"PageQuantity-$sig_specs{Group}"}) {
      return {alert=>'No impositions matched the overriden page quantity('.$$project{ProjectSpecs}{"PageQuantity-$sig_specs{Group}"}.') for this group.<br/>'};
    } elsif ($sig_specs{'chkOverridePageQuantity'.$qty_index}  and ( $sig_specs{'chkOverridePageQuantity'.$qty_index} eq 'Y')) {
      return {alert=>'No impositions matched the overriden page quantity ('.$sig_specs{'PageQuantity'.$qty_index}.').<br/>'};
    }
	}
	if ( DEBUG or DEBUG_AFTER_FILTERING ) {
		$log->debug('@ of impositions: ' . @Is );
		foreach my $I ( @Is ) {
			$I->display("Before calculation: depth: $recursion_depth # of sigs: " . @Is);
		} # end while
	}
#$log->debug("calculated_impositions: $$Press{strid} " . ( sprintf('%.4f', tv_interval( [$time])*1000) ) .' usecs' );
	foreach my $base_imp ( @Is ) {
# Imp still gets modified in calc_price, Folding adds Folder member
# But if we alraedy know how to fold this impo... then.....
		$$base_imp{Project} = $Project;
		my $imp = $base_imp->copy();
		my $Press = $imp->Press();
		
		$$imp{specs} = \%sig_specs;
		$sig_specs{PreviousPress} = $previous_press;
		$sig_specs{'ddmRunStyle'.$qty_index} = $$imp{runstyle};
		$sig_specs{'ddmPress'.$qty_index} = $$Press{strid};
		$sig_specs{'PageQuantity'.$qty_index} = $$imp{pages};
		# It's ok to do this, because $$specs is either a copy, or will be reset before being returned
		$sig_specs{'SpreadRows'.$qty_index} = $$imp{spread_rows};
		$sig_specs{'SpreadCols'.$qty_index} = $$imp{spread_columns};
		$sig_specs{'hdnImageOrientation'.$qty_index} = ( $$imp{image_orientation} == openprint::Imposition::Vertical ? 'Vertical' : 'Horizontal' );
		$sig_specs{"PageQuantity$qty_index"} = $$imp{pages};
		my $Paper = $$imp{Paper};
		$sig_specs{txtStockGSM} = $$Paper{gsm};
		$sig_specs{txtSpecificStockCalliper} = $$Paper{calliper};

		my %previous_forms_cache = %$previous_forms_cache;
		my $hash_key = join(',', $$Press{strid}, $$imp{runstyle}, $$imp{pages}, $$imp{imposition}, $$imp{columns} );
		if ( $previous_forms_cache{$hash_key} ) {
			$sig_specs{'PreviousForms'.$qty_index} = $previous_forms_cache{$hash_key};
			$previous_forms_cache{$hash_key} += 1;
		} else {
			$sig_specs{'PreviousForms'.$qty_index} = 0;
			$previous_forms_cache{$hash_key} = 1;
		}

		my %PlateCounts = %$PlateCounts;
		my %washed_colours = %$washed_colours;
		my %mixed_colours = %$mixed_colours;
		my %PaperCounts = %$PaperCounts;
		my %aq_makereadies = %{ dclone $aq_makereadies} if $aq_makereadies;

    # other_impositions are ones that come after us... so this is weird.
		my @total_impositions = @$other_impositions;

		# This is suspect is it?	other_impos doesn't get modified. sig_specs{mpositions} gets populated before recurse
		push @total_impositions, @{$sig_specs{Impositions}} if $sig_specs{Impositions};
		push @total_impositions, $imp;

		my $do_final_pricing = 1;

    $openprint::log->debug("1 @{$other_impositions} imp $imp $base_imp");
		my $price = calc_price( $Project, $service_index, $imp, $project, $services, \%sig_specs, $qty, $qty_index, \%PlateCounts, \%washed_colours, \%mixed_colours, \%aq_makereadies, \@total_impositions );
    $$price{versions} = $versions;
		if (!$$price{complete}) {
			if ( DEBUG ) {
				$imp->display( 'Couldnt calculate initial price: ' . $$price{alert} );
			} # end if
			next;
		} # end if

		$PlateCounts{$$price{'Plate Costs'}{'Plate ID'}} += $$price{'Plate Costs'}{'Plate Count'};
		$PlateCounts{'Blank'.$$price{'Plate Costs'}{'Plate ID'}} += $$price{'Plate Costs'}{'Blank Plates'};
		$PaperCounts{$Paper->id_string()} += $$price{'Stock Qty'};
# Gets done later on, why do it here?	Maybe to fuill in plate costs... or to use them in best_price calcs...
# I put this back on Sept 17th because for a 16+8, it didn't have the plate costs. Technically it should be done later when all plates are accounted for
# Why doesn't the same lines down below do the job?
# Because the one dowre runs when Unspecified Pages % pages is 0.	with a 16+8 it's not.
# THis should happen down below

		if ( 1 ) {
			my $results = plate_cost( $price, \%PlateCounts );
			$$price{'Total Cost'} += $$results{Price};
			$$price{ComparisonCost} += $$results{Price};
			$$price{'Comparison Log'} .= 'Plates ' . $$results{Price} . ' total: ' . $$price{ComparisonCost} .'<br/>' if COMPARISON_LOG;
			$$price{PlateCost} = $$results{Price};
		} # end if

		if ( %best_price and ( $best_price{ComparisonCost} <= $$price{ComparisonCost} ) ) {
			if ( DEBUG_PRICE_DECISIONS or $sig_specs{Group} == 1 ) {
				$imp->display( "Too expensive $best_price{ComparisonCost} <= $$price{ComparisonCost}" );
				if ( $sig_specs{Impositions} ) {
					foreach my $I ( reverse @{ $sig_specs{Impositions} } ) {
						$I->display( "THIS" );
					} # end while
				} 
				if ( $best_price{Impositions} ) {
					foreach my $I ( reverse @{ $best_price{Impositions} } ) {
						$I->display( "BEST" );
					} # end while
				} 
			} # end if
			next; # next Impo
		} # end if

# This price hash only contains the calculating imps.	Non-group imps are in other_impositions
		$$price{sig_count} = 1;
		$$price{Imposition} = $imp;
		$$price{upq} = $txtUnspecifiedPageQuantity ? $txtUnspecifiedPageQuantity - $$imp{pages} : 0;
		if ( $Project->Type()->type() eq 'ScratchPads' ) {
			$$price{upq} = 0;
		}
		$$price{Impositions} = [ $imp ];
    $$price{versions} = $versions;
		#push @total_impositions, $imp;

		if ( (defined $sig_specs{"UnspecifiedVersions$qty_index"} ) and ( $sig_specs{"UnspecifiedVersions$qty_index"} > $$imp{version_qty} ) ) {

			my $remaining_versions = $sig_specs{"UnspecifiedVersions$qty_index"} - $$imp{version_qty};
			$imp->display("Need more sigs for $remaining_versions versions ");
			my @signatures = @$signatures;
			my $newimp = $base_imp->copy();

			while ( $remaining_versions >= $$imp{version_qty} ) {
        $imp->display("Need more sigs for $remaining_versions versions ");
				my $new_specs = get_new_specs( $Project, $service_index, \%sig_specs, \@signatures, $qty_index, undef, \%previous_forms_cache, $hash_key );
				$$new_specs{"UnspecifiedVersions$qty_index"} = $remaining_versions;
				$$newimp{specs} = $new_specs;

				my $sig_price = calc_price( $Project, $$new_specs{ServiceIndex}, $newimp, $project, $services, $new_specs, $qty, $qty_index, \%PlateCounts, \%washed_colours, \%mixed_colours, \%aq_makereadies, \@total_impositions );
				$$sig_price{sig_count} = 1;
#my $sig_price = get_project_price( $Project, $$new_specs{ServiceIndex}, $project, $service_specs, $new_specs, $qty, $qty_index, $possible_presses, $printing_specs, $versions, \%PlateCounts, \%PaperCounts, \%washed_colours, \%previous_forms_cache, \@signatures, $impositions, $other_impositions, undef, $recursion_depth + 1 );

				$PaperCounts{$Paper->id_string()} += $$sig_price{'Stock Qty'};
				$PlateCounts{$$sig_price{'Plate Costs'}{'Plate ID'}} += $$sig_price{'Plate Costs'}{'Plate Count'};
				$PlateCounts{'Blank'.$$sig_price{'Plate Costs'}{'Plate ID'}} += $$sig_price{'Plate Costs'}{'Blank Plates'};
				$$price{ComparisonCost} += $$sig_price{ComparisonCost};
				$$price{'Comparison Log'} .= 'signature ' . $$sig_price{ComparisonCost} . ' total: ' . $$sig_price{ComparisonCost} .'<br/>' if COMPARISON_LOG;

				$$sig_price{Imposition} = $newimp;
				push @total_impositions, $newimp;
				push @{$$price{Impositions}}, $newimp;
				$remaining_versions -= $$newimp{version_qty};
				push @{$$price{prices}}, $sig_price;
				if ( ! $$imp{version_qty} ) {
$imp->display('no versions');
					$log->error('Should not get no versions. '.$sig_specs{"UnspecifiedVersions$qty_index"}.' '.$$imp{version_qty});
          last;
} else {
					$log->debug('Get versions. '.$sig_specs{"UnspecifiedVersions$qty_index"}.' '.$$imp{version_qty});
				} # end if
			} # end while versions

			if ( $remaining_versions ) {
				if ( %best_price and ( $best_price{ComparisonCost} <= $$price{ComparisonCost} ) ) {
					if ( DEBUG_PRICE_DECISIONS or $sig_specs{Group} == 1 ) {
						$imp->display( "2 Too expensive $best_price{ComparisonCost} <= $$price{ComparisonCost}" );
						if ( $sig_specs{Impositions} ) {
							foreach my $I ( reverse @{ $sig_specs{Impositions} } ) {
								$I->display( "THIS" );
							} # end while
						} 
						if ( $best_price{Impositions} ) {
							foreach my $I ( reverse @{ $best_price{Impositions} } ) {
								$I->display( "BEST" );
							} # end while
						} 
					} # end if
					next; # next Impo
				} # end if
				my $new_specs = get_new_specs( $Project, $service_index, \%sig_specs, \@signatures, $qty_index, undef, \%previous_forms_cache, $hash_key );
				$$new_specs{"UnspecifiedVersions$qty_index"} = $remaining_versions;

				$log->warn("Recursing cuz need another $remaining_versions");
				my $price_cache_key = join(',', $qty_index, $$Press{strid}, $$imp{runstyle}, $$imp{version_qty} );

				if ( ! $price_cache{$price_cache_key} ) {
					$$new_specs{PrintingTypes} = [ $Press->specification('Printing Type') ];
					$$new_specs{PreviousStockType} = $$Paper{type};
					$$new_specs{PreviousGrainDirection} = $imp->grain_direction();

					my @new_possible_presses;
					foreach my $p ( @$possible_presses ) {
						if ( $p->specification('Number of Colours') < $Press->specification('Number of Colours') ) {	
							push @new_possible_presses, $p;
						} # end if
					} # end foreach 
$openprint::log->error("Versions $versions");
					$price_cache{$price_cache_key} = 
						get_project_price( $Project, $$new_specs{ServiceIndex}, $project, $new_specs, $qty, $qty_index, \@new_possible_presses, $printing_specs, $versions, \%PlateCounts, \%PaperCounts, \%washed_colours, \%mixed_colours, \%aq_makereadies, \%previous_forms_cache, \@signatures, $impositions, $other_impositions, undef, $recursion_depth + 1 );
				} # end if ! $price_cache
				my $sig_price = $price_cache{$price_cache_key};

				$log->warn("Back fr Recursing cuz need another $remaining_versions");
				if ( $$sig_price{Imposition} ) {
					my $newimp = $$sig_price{Imposition};

					$PaperCounts{$Paper->id_string()} += $$sig_price{'Stock Qty'};
					$PlateCounts{$$sig_price{'Plate Costs'}{'Plate ID'}} += $$sig_price{'Plate Costs'}{'Plate Count'};
					$PlateCounts{'Blank'.$$sig_price{'Plate Costs'}{'Plate ID'}} += $$sig_price{'Plate Costs'}{'Blank Plates'};
					$$price{ComparisonCost} += $$sig_price{ComparisonCost};
					$$price{'Comparison Log'} .= 'signature ' . $$sig_price{ComparisonCost} . '<br/>' if COMPARISON_LOG;

					push @total_impositions, $newimp;
					push @{$$price{Impositions}}, $newimp;
					$remaining_versions -= $$newimp{version_qty};
					push @{$$price{prices}}, $sig_price;
					if ( ! $$newimp{version_qty} ) {
						$log->error('Should not get no versions. '.$sig_specs{"UnspecifiedVersions$qty_index"}.' '.$$imp{version_qty});
#last;
					} # end if
				} else {
					$log->error('recurses didnt work out');
					$$price{complete} = 0;
				} # end if
			} # end while versions

		} elsif ( $$price{upq} ) {
			$imp->display( $recursion_depth . ' UPQ: ' . $txtUnspecifiedPageQuantity . ' real upq ' . $$price{upq}) if DEBUG;

			my $new_specs;
# UPQ can be negative on single-page items
				if ( ( $$price{upq} > 0 ) and $$imp{pages} ) {
					my @signatures = @$signatures;
#$log->debug("Initial Signatures @signatures");
					my $last_sig_price = int($$price{ComparisonCost});

					$imp = $base_imp->copy();
					$new_specs = get_new_specs( $Project, $service_index, \%sig_specs, \@signatures, $qty_index, $$price{upq}, \%previous_forms_cache, $hash_key );
					$$imp{specs} = $new_specs;

					# This is used solely for proofs
					my $sig_count = 1;

					while ( $$price{upq} >= $$imp{pages} ) {
						if ( 
								( ((!$$new_specs{'chkOverridePageQuantity'.$qty_index}) or ( $$new_specs{'chkOverridePageQuantity'.$qty_index} ne 'Y') ) or ($$new_specs{'PageQuantity'.$qty_index} == $$imp{pages}) ) and
								( ((!$$new_specs{'chkOverrideImposition'.$qty_index}) or ( $$new_specs{'chkOverrideImposition'.$qty_index} ne 'Y') ) or ($$new_specs{'txtImposition'.$qty_index} == $$imp{imposition}) ) and
								( ((!$$new_specs{'chkOverridePress'.$qty_index}) or ($$new_specs{'chkOverridePress'.$qty_index} ne 'Y')) or ($$new_specs{'ddmPress'.$qty_index} eq $Press->strid()) ) and
								( ((!$$new_specs{'chkOverrideRunStyle'.$qty_index}) or ($$new_specs{'chkOverrideRunStyle'.$qty_index} ne 'Y')) or ($$new_specs{'ddmRunStyle'.$qty_index} eq $$imp{runstyle}) )
							) {
if ( 0 ) {
foreach my $k ( keys %washed_colours ) {
$log->debug("$k => $washed_colours");
}
}
							my $sig_price = calc_price( $Project, $$new_specs{ServiceIndex}, $imp, $project, $services, $new_specs, $qty, $qty_index, \%PlateCounts, \%washed_colours, \%mixed_colours, \%aq_makereadies, \@total_impositions );
							$imp->display( $recursion_depth . ' UPQ: ' . $$price{upq} . ' first level calc_price' ) if DEBUG;
							$$sig_price{Imposition} = $imp;
							$$sig_price{sig_count} = 1;

							$PlateCounts{$$sig_price{'Plate Costs'}{'Plate ID'}} += $$sig_price{'Plate Costs'}{'Plate Count'};
# Blanks get re-used
							#$PlateCounts{'Blank'.$$sig_price{'Plate Costs'}{'Plate ID'}} += $$sig_price{'Plate Costs'}{'Blank Plates'};
							if ( 1 ) {
								my $results = plate_cost( $sig_price, \%PlateCounts );
								$$sig_price{'Total Cost'} += $$results{Price};
								$$sig_price{ComparisonCost} += $$results{Price};
								$$sig_price{'Comparison Log'} .= 'plates ' . $$results{Price} . '<br/>' if COMPARISON_LOG;
								$$sig_price{PlateCost} = $$results{Price} ;
							}

							if ( ( int($$sig_price{ComparisonCost}) == $last_sig_price ) and ( 
										( ! $sig_specs{'txtPlateChangeQuantity'.$qty_index} and ! $$new_specs{'txtPlateChangeQuantity'.$qty_index} )
										or
										( $sig_specs{'txtPlateChangeQuantity'.$qty_index} and $$new_specs{'txtPlateChangeQuantity'.$qty_index} and $sig_specs{'txtPlateChangeQuantity'.$qty_index} == $$new_specs{'txtPlateChangeQuantity'.$qty_index} )
										) ) {
								my $sigs = int($$price{upq}/$$imp{pages});
#$log->debug("Sigs: $sigs: signatures( @signatures )");
								#$PaperCounts{$$Paper{id_string}} = 0 if ! defined $PaperCounts{$Paper->id_string()};
								foreach ( 1 .. $sigs ) {
									$$price{ComparisonCost} += $$sig_price{ComparisonCost};
									$$price{'Comparison Log'} .= 'signature ' . $_ .' ' . $$sig_price{ComparisonCost} .' total: ' . $$price{ComparisonCost}.'<br/>' if COMPARISON_LOG;
							
									$PaperCounts{$$Paper{id_string}} += $$sig_price{'Stock Qty'};
									push @{$$price{Impositions}}, $imp;
									push @{$$price{prices}}, $sig_price;
									push @total_impositions, $imp;
									$previous_forms_cache{$hash_key} += 1;

									$$price{upq} -= $$imp{pages};
									if ( $$price{upq} ) {
	# Doesn't really matter about upq, because we aren't calculating on these sigs.
										$imp = $imp->copy();
										$new_specs = get_new_specs( $Project, $service_index, \%sig_specs, \@signatures, $qty_index, $$price{upq}, \%previous_forms_cache, $hash_key );
										$$imp{specs} = $new_specs;
									} else {
										$new_specs = undef;
									}

									$$sig_price{'Comparison Log'} .= 'plates ' . $$sig_price{PlateCost} . '<br/>' if COMPARISON_LOG;
									#$$sig_price{ComparisonCost} += $$sig_price{PlateCost};
									$PlateCounts{$$sig_price{'Plate Costs'}{'Plate ID'}} += $$sig_price{'Plate Costs'}{'Plate Count'};
									$sig_count += 1;
									last if (!$new_specs) or ( ! ( (!$sig_specs{'txtPlateChangeQuantity'.$qty_index} and ! $$new_specs{'txtPlateChangeQuantity'.$qty_index} ) or ( $sig_specs{'txtPlateChangeQuantity'.$qty_index} and $$new_specs{'txtPlateChangeQuantity'.$qty_index} and $$new_specs{'txtPlateChangeQuantity'.$qty_index} == $sig_specs{'txtPlateChangeQuantity'.$qty_index} ) ) );
								} # end foreach
#$log->debug("New upq: $$price{upq}");
							} else {
#$log->debug("Got diff comparison cost");
								$$price{ComparisonCost} += $$sig_price{ComparisonCost};
								$$price{'Comparison Log'} .= 'signature ' . $$sig_price{ComparisonCost} . '<br/>' if COMPARISON_LOG;
								$last_sig_price = int($$sig_price{ComparisonCost});
								$PaperCounts{$Paper->id_string()} += $$sig_price{'Stock Qty'};
								push @{$$price{Impositions}},$imp;
								push @{$$price{prices}}, $sig_price;
								push @total_impositions, $imp;
								$$price{upq} -= $$imp{pages};
#$log->debug("New upq: $$price{upq}");
								$previous_forms_cache{$hash_key} += 1;
								$sig_count += 1;

								# Copying the base_imp, means that we lose our folds.
								$imp = $imp->copy();
								$new_specs = get_new_specs( $Project, $service_index, \%sig_specs, \@signatures, $qty_index, $$price{upq}, \%previous_forms_cache, $hash_key );
								$$imp{specs} = $new_specs;
							} # end if
							$imp->display( $recursion_depth . ' UPQ: ' . $$price{upq} . ' after first level calc_price' ) if DEBUG;

# This is here so that we don't allocate another when recursing
						} else {
							last;
						} # end if specs are acceptable
					} # end while upq > imp->pages

# Doing this here, and down below means we may be doing it twice per sig
					if ( $$project{HasProofs} ) {
#my $proofs_time = gettimeofday();
# Add proof costs.	Proofs only depends on colours, equipment so doesn't need to be part of the rest of calc
						my %Results = openprint::Estimating::Proofs::signature_calc( $Project, $$project{ProofsSpecs}, \%sig_specs, $qty_index, undef, undef, $Press, $imp );
#$log->debug( 'Proofs Calc: ' . sprintf('%.4f', tv_interval( [$proofs_time])*1000) );
						$$price{ComparisonCost} += $sig_count * $Results{Total};
						$$price{'Comparison Log'} .= 'proofs for ' . $sig_count . 'sigs. '. $sig_count * $Results{Total} . ' total: ' . $$price{ComparisonCost} . '<br/>' if COMPARISON_LOG;
						$$price{'Proofs Breakdown'} .= $Results{Breakdown};
					} else {
$log->error("No proofs>!");
					} # end if

#$imp->display("Actually calculating this imp count $$price{sig_count} \$$$price{ComparisonCost} Proofs: $$results{Price}") if ! $recursion_depth;
#$log->debug( breakdown( $price, $sig_specs ) ) if ! $recursion_depth;

					if ( $$price{upq} ) {
						if ( 0 and ( $$price{upq} == 2 ) and %best_price ) {
							$$price{complete} = 0;
							$$price{ComparisonCost} += 10000000;
							$$price{Breakdown} .= 'Unable to calculate additional 2pg signatures.<br/>';
$log->error("'Unable to calculate additional 2pg signatures" );
							next;
						}
							
						if ( ! $new_specs ) {
# new_specs is notnull when we encountered an unmatching ovveride
							$imp = $base_imp->copy();
							$new_specs = get_new_specs( $Project, $service_index, \%sig_specs, \@signatures, $qty_index, $$price{upq}, \%previous_forms_cache, $hash_key );
							$$imp{specs} = $new_specs;
						} # end if
						
						$do_final_pricing = 0;
						my $sig_price = {};
						if ( $recursion_depth >= $max_recursion_depth ) {
							$imp->display('Recursion Depth :' . $recursion_depth ) if DEBUG;
							$$sig_price{alert} .= 'Too deep ' . $recursion_depth;
							$$sig_price{complete} = 0;
						} else {

							my $price_cache_key = join(',', keys %PaperCounts, $qty_index, $$Press{strid}, $$price{upq}, $$imp{runstyle}, $$Paper{type}, $$Paper{width}, $$imp{imposition}, $$imp{columns}, $$imp{image_orientation} );
#$log->error("key: $price_cache_key");
							#my $price_cache_key = join(',', keys %PaperCounts, $qty_index, $$Press{strid}, $$price{upq}, $$imp{runstyle}, $$Paper{type}, $$Paper{width},$$Paper{height} );
#$imp->display("Recursing need $$price{upq} more pages");
							if ( ! $price_cache{$price_cache_key} ) {
#foreach my $k ( sort keys %price_cache ) {
	#$log->error("NOT IN $k");
#}
#$imp->display("Recursing need $$price{upq} more pages actually");
# Not identical, so clear this so we get charged setups, etc

								$$new_specs{'PreviousForms'.$qty_index} = 0;
$log->debug("Doing full calc when UPQ: >= Pages:" . $$imp{pages} . ' PageQuantity:' . $$new_specs{'PageQuantity'.$qty_index} ) if $$price{upq} >= $$imp{pages} or 0;

								$$new_specs{PrintingTypes} = [ $Press->specification('Printing Type') ];
								if ( (!$$new_specs{'chkOverridePress'.$qty_index}) or ( $$new_specs{'chkOverridePress'.$qty_index} ne 'Y' ) ) {
									$$new_specs{PreviousPress} = $$Press{strid};
									#$log->debug("Setting press to $$Press{strid} was ($$new_specs{PreviousPress}) recursion depth($recursion_depth) $new_specs");
								}
								$$new_specs{PreviousStockType} = $$Paper{type};
								$$new_specs{PreviousStockWidth} = $$Paper{width};
								$$new_specs{PreviousGrainDirection} = $imp->grain_direction();
								if ( $$imp{Folder} and ( $$Press{id} == $$imp{Folder}->id() ) ) {
#This is used in Folding to tell it not to mix impositions when inline folded
									$$new_specs{PreviousImposition} = $$price{FoldingImposition};
								} # end if	
								$$new_specs{Impositions} = [ ( $sig_specs{Impositions} ? @{$sig_specs{Impositions}} : () ), @{$$price{Impositions}} ];

								if ( DEBUG_PLATES ) {
									foreach my $k ( keys %PlateCounts ) {
										$log->debug("PLATES beforerecursion: $k=> $PlateCounts{$k}");
									} # end foreach
								} # end if
								my @new_possible_presses;
								foreach my $p ( @$possible_presses ) {
									if ( $p->specification('Number of Colours') <= $Press->specification('Number of Colours') ) {	
										push @new_possible_presses, $p;
									} # end if
								} # end foreach 
								$price_cache{$price_cache_key} = 
									get_project_price( $Project, $$new_specs{ServiceIndex}, $project, $new_specs, $qty, $qty_index, \@new_possible_presses, $printing_specs, $versions, \%PlateCounts, \%PaperCounts, \%washed_colours, \%mixed_colours, \%aq_makereadies, \%previous_forms_cache, \@signatures, $impositions, $other_impositions, undef, $recursion_depth + 1 );
							} # end if
							%{$sig_price} = %{$price_cache{$price_cache_key}};
#$log->debug("Prices: $sig_price $price_cache{$price_cache_key}");
							$price_cache{$price_cache_key} = undef if ! USE_PRICE_CACHE;

# get_project_price is recursive so we are done
							if ( ( ! $$sig_price{complete} ) or ( ! $$sig_price{Imposition} ) ) {
$log->warn("Unable to calculate additional signatures  imp pages: " . $$imp{pages} . ' of upq: ' . $$price{upq}. ' alert: ' . ($$sig_price{alert}?$$sig_price{alert}:'') );
$imp->display('[warn]');
								$$price{complete} = 0;
								$$price{ComparisonCost} += 10000000;
								$$price{Breakdown} .= 'Unable to calculate additional signatures.<br/>';
							delete $price_cache{$price_cache_key};
							} # end if cache
						} # end if too deep

# get_project_price is recursive so we are done
						if ( ( ! $$sig_price{complete} ) or ( ! $$sig_price{Imposition} ) ) {
							$log->debug("Unable to calculate additional signatures Complete: $$sig_price{complete}, imp pages: " . $$imp{pages} . ' of upq: ' . $$price{upq} . 'Spread size:' . $sig_specs{txtSpreadSize} . ' alert: ' . $$sig_price{alert}) if DEBUG;
							$$price{complete} = 0;
							$$price{ComparisonCost} += 10000000;
							$$price{Breakdown} .= 'Unable to calculate additional signatures.<br/>';
						} else {
							if ( $$sig_price{Impositions} ) {
								push @{$$price{Impositions}}, @{$$sig_price{Impositions}};
								push @total_impositions, @{$$sig_price{Impositions}};
							} # end if
							push @{$$price{prices}}, $sig_price;
							if ( $$sig_price{prices} ) {
								# Happens only when the sub price repesents more than 1 sig
								push @{$$price{prices}}, @{$$sig_price{prices}};
							} # end if

# Don't add stock weight because we likely have a different stock anyways.
							$PaperCounts{$$sig_price{Imposition}{Paper}->id_string()} += $$sig_price{'Stock Qty'};
							$PlateCounts{$$sig_price{'Plate Costs'}{'Plate ID'}} += $$sig_price{'Plate Costs'}{'Plate Count'};
#$log->debug("Adding $$sig_price{'Plate Costs'}{'Plate ID'} $$sig_price{'Plate Costs'}{'Plate Count'}" );
							$PlateCounts{'Blank'.$$sig_price{'Plate Costs'}{'Plate ID'}} += $$sig_price{'Plate Costs'}{'Blank Plates'};
							$$price{ComparisonCost} += $$sig_price{ComparisonCost};
							$$price{'Comparison Log'} .= 'signature ' . $$sig_price{ComparisonCost} . '<br/>' if COMPARISON_LOG;
						} # end if sig_price complete

						# Since recursive... it should have taken care of all needed pages.
						$$price{upq} = 0;

					} # end if upq

				} else { # upq and pages

# either a brochure type or all pages are calculated.
					if ( $$project{HasProofs} ) {
# Add proof costs.	Proofs only depends on colours, equipment so doesn't need to be part of the rest of calc
						my %Results = openprint::Estimating::Proofs::signature_calc( $Project, $$project{ProofsSpecs}, \%sig_specs, $qty_index, undef, undef, $Press, $imp );
						$$price{ComparisonCost} += $$price{sig_count} * $Results{Total};
						$$price{'Comparison Log'} .= 'proofs ' . $$price{sig_count} * $Results{Total} . '<br/>' if COMPARISON_LOG;
						$$price{'Proofs Breakdown'} .= $Results{Breakdown};
					} # end if
				} # end if UnspecifiedPageQuanitty
			} else {
					if ( $$project{HasProofs} ) {
# Add proof costs.	Proofs only depends on colours, equipment so doesn't need to be part of the rest of calc
						my %Results = openprint::Estimating::Proofs::signature_calc( $Project, $$project{ProofsSpecs}, \%sig_specs, $qty_index, undef, undef, $Press, $imp );
						$$price{ComparisonCost} += $$price{sig_count} * $Results{Total};
						$$price{'Comparison Log'} .= 'proofs ' . $$price{sig_count} * $Results{Total} . '<br/>' if COMPARISON_LOG;
						$$price{'Proofs Breakdown'} .= $Results{Breakdown};
					} # end if
			} # end if versions vs unspecifiedpages

			if ( $best_price{complete} and ! $$price{complete} ) {
				if ( DEBUG or 0 ) {
					$imp->display('Incomplete Price');
				} # end if
				next;
			} # end if

#upq is always 0 here
#if ( ! $recursion_depth ) {
# I know we keep flip flopping.... so for the moment I am doing
# Do we do thhis stuff at the tail of the recursion, or when we are back. I don't know.
# Let's try at the tail.

#if ( $txtUnspecifiedPageQuantity - $$imp{pages} ) ) {
#$log->debug("$recursion_depth : At tail? $txtUnspecifiedPageQuantity - ( $$price{sig_count} * $$imp{pages} ) " . ( $txtUnspecifiedPageQuantity - ( $$price{sig_count} * $$imp{pages} ) ) );

			if ( $recursion_depth == 0 ) {
				if ( $$price{PlateCost} ) {
					# They may be added into the Comparison cost in one of the sub prices
					$$price{'Comparison Log'} .= 'plate adj -' . $$price{PlateCost} . ' total: ' . $$price{ComparisonCost}.'<br/>' if COMPARISON_LOG;
					$$price{ComparisonCost} -= $$price{PlateCost};
					$$price{'Total Cost'} -= $$price{PlateCost};
				}

				if ( DEBUG_PLATES ) {
					foreach my $k ( keys %PlateCounts ) {
						$log->debug("PLATES: $k=> $PlateCounts{$k}");
					} # end foreach
				} # end if

				my $results = plate_cost( $price, \%PlateCounts );
				$$price{PlateCost} = $$results{Price};
				$$price{'Total Cost'} += $$results{Price};
				$$price{'Comparison Log'} .= 'plate adj ' . $$results{Price} . ' total: ' . $$price{ComparisonCost} . '<br/>' if COMPARISON_LOG;
				$$price{ComparisonCost} += $$results{Price};
				$$price{'Comparison Log'} .= 'plate adj done total: ' . $$price{ComparisonCost} . '<br/>' if COMPARISON_LOG;

				foreach my $p ( @{$$price{prices}} ) {
					# This should fill in the place costs line of the breakdown
					if ( $$p{PlateCost} ) {
						# They may be added into the Comparison cost in one of the sub prices
						$$price{ComparisonCost} -= $$p{PlateCost};
						$$price{'Comparison Log'} .= 'sub plate adj -' . $$p{PlateCost} . '<br/>' if COMPARISON_LOG;
						$$p{'Total Cost'} -= $$p{PlateCost};
					} 
					my $r = plate_cost( $p, \%PlateCounts );
					$$price{ComparisonCost} += $$p{sig_count} * $$p{PlateCost};
					$$price{'Comparison Log'} .= 'sub plate adj '. $$p{sig_count} . ' ' . $$p{sig_count} *$$p{PlateCost}	. '<br/>' if COMPARISON_LOG;
					$$p{'Total Cost'} += $$r{Price};
					$$p{PlateCost} = $$r{Price};
				} # end foreach price

				if ( ( $$Paper{type} eq 'Roll' ) and $$Press{Feeds}{Sheet} ) {
# Add Roll2SheetSetup
					if ( ! $$project{roll2sheetcharged} ) {
						my $R2SMR = $Services{Roll2SheetMakeReady};

						if ( $R2SMR ) {
							if ( my $R2SMRPrice = $R2SMR->get_Price( $Paper->gsm(), $Press ) ) {
								$$price{Roll2SheetMakeReady} = $$R2SMRPrice{Price};
								$$price{ComparisonCost} += $$price{Roll2SheetMakeReady};
								$$price{'Comparison Log'} .= 'rol2sheetmr ' . $$price{Roll2SheetMakeReady} . '<br/>' if COMPARISON_LOG;
								$$price{'Total Cost'} += $$price{Roll2SheetMakeReady};
								$$price{'Setup Total'} += $$price{Roll2SheetMakeReady};
							} # end if
						} # end if
					} # end if
# Add Roll2SheetRun
					my $Roll2SheetService = $Services{Roll2Sheet};
					my %R2SPrice;

					if ( $Roll2SheetService and ( %R2SPrice = $Roll2SheetService->get_price( $$price{Impressions}, $Press ) ) ) {
						if ( $R2SPrice{units} eq 'per m' ) {
							$$price{Roll2SheetRunCharge} = Math::Round::nearest(0.01,$R2SPrice{Price} * $$price{Impressions}/1000);
						} else {
							$log->error("Unknown units on Roll2SheetRunCharge ( $R2SPrice{units} for $$Press{strid}");
						} # end if
						$$price{Roll2SheetUnits} = $R2SPrice{units};
						$$price{Roll2SheetRunCost} = $R2SPrice{Price};
						$$price{ComparisonCost} += $$price{Roll2SheetRunCharge};
						$$price{'Comparison Log'} .= 'roll2sheetrun ' . $$price{Roll2SheetRunCharge} . '<br/>' if COMPARISON_LOG;
						$$price{'Total Cost'} += $$price{Roll2SheetRunCharge};
						$$price{'Run Total'} += $$price{Roll2SheetRunCharge};
					} # end if Has Roll2Sheet Price
				} # end if Roll & has sheeter
			} # end if recursion == 0
#$log->debug("UPQ $txtUnspecifiedPageQuantity $$price{sig_count} * $$imp{pages} ");

			if ( $do_final_pricing ) {
				if ( $$price{PlateCost} ) {
# They may be added into the Comparison cost in one of the sub prices
					$$price{'Comparison Log'} .= 'plate adj -' . $$price{PlateCost} . ' total: ' . $$price{ComparisonCost} . '<br/>' if COMPARISON_LOG;
					$$price{ComparisonCost} -= $$price{PlateCost};
					$$price{'Total Cost'} -= $$price{PlateCost};
					$$price{'Comparison Log'} .= 'plate adj done total: ' . $$price{ComparisonCost} . '<br/>' if COMPARISON_LOG;
				}
				my $results = plate_cost( $price, \%PlateCounts );
				$$price{PlateCost} = $$results{Price};
				$$price{ComparisonCost} += $$results{Price};
				$$price{'Total Cost'} += $$price{PlateCost};
				if ( COMPARISON_LOG ) {
					$$price{'Comparison Log'} .= 'plate adj +' . $$results{Price} . ' total: ' . $$price{ComparisonCost} . '<br/>';
					$$price{'Comparison Log'} .= 'plate adj done total: ' . $$price{ComparisonCost} . '<br/>';
				}

# I don't think this is appropriate anymore
#$$price{ComparisonCost} += $$price{sig_count} * $$results{Price};

				my @paper_strings = sort { $a cmp $b } keys %PaperCounts;
				if ( ( 1 == @paper_strings ) and ( $Paper->id_string() ne $paper_strings[0] ) ) {
					$log->error("Different paper in count versus imposition: $paper_strings[0] ne " . $$imp{Paper}->id_string() );
				} elsif ( DEBUG ) {
					$log->warn("Paper Counts");
					foreach my $k ( @paper_strings ) { $log->debug( "$k => $PaperCounts{$k} factor" . $Papers{$k}->factor() ); } # end 
				}

				my $do_stock_cutting = 0;

				foreach my $paper_string ( @paper_strings ) {
					my $Paper = $Papers{$paper_string};
					if ( ! $Paper ) {
						$log->error("No Paper Object for $paper_string");
						foreach my $paper_string ( keys %Papers ) { $log->error("$paper_string $Papers{$paper_string}"); } 
						$$price{ComparisonCost} += 1000000;
						$$price{'Comparison Log'} .= 'Bad paper + 1000000 total: ' . $$price{ComparisonCost} . '<br/>' if COMPARISON_LOG;
						$$price{'Paper Breakdown'} .= 'Unable to calculate price for ' . $paper_string.'</br>';
						next;
					} elsif ( $paper_string ne $Paper->id_string() ) {
						$log->error("Different paper in count versus imposition: $paper_string ne " . $Paper->id_string() );
					} # end if
	
					if ( $Paper->full_packages() ) {
						if ( my $qty_per_package = $Paper->sheets_per_package() ) {
							$PaperCounts{$paper_string} = $qty_per_package * ceil( $PaperCounts{$paper_string}/$qty_per_package );
						} # end if
					} # end if

#$log->debug("Pricing Paper: Minimum Order: " . $Paper->minimum_order() );
					if ( $Paper->minimum_order() ) {
# Assume sheets for sheets, lbs for Rolls
						if ( $Paper->minimum_order() > $PaperCounts{$paper_string} ) {
							$PaperCounts{$paper_string} = $Paper->minimum_order();
						} # end if
					} # end if
					my $supplied_weight;
					my $supplied_sheets;
					my $Supplied = $Paper->Supplied();
					my $paper_price;

					if ( $$Paper{type} eq 'Sheet' ) {
						if ( $Paper->is_cut() ) {
							$do_stock_cutting = 1;
						} # end if
						$supplied_sheets = ceil($PaperCounts{$paper_string}/$Paper->factor());
						$supplied_weight = Math::Round::nearest( 0.1, $supplied_sheets * Math::Round::nearest(0.001, $Supplied->sheet_weight() ) );
						if ( ! $supplied_weight ) {
							$log->error("Sheet No supplied wight: $supplied_sheets $paper_string factor: " . $Paper->factor() . ' sheet weight: ' . $Supplied->sheet_weight() );
						} # end if
						$paper_price = $Supplied->get_price( sheets=>$supplied_sheets, service=>'Material' );
					} else {
						$supplied_weight = Math::Round::nearest( 0.1, $PaperCounts{$paper_string}/$Paper->factor() );
						$paper_price = $Supplied->get_price( weight=>$supplied_weight, service=>'Material' );
					} # end if

					$$paper_price{Total} = Math::Round::nearest( 0.01, $$paper_price{'100lb Price'} * $supplied_weight / 100 );
					$$price{ComparisonCost} += $$paper_price{Total};
					$$price{'Comparison Log'} .= 'Paper Costs +'.$$paper_price{Total}.' total: ' . $$price{ComparisonCost} . '<br/>' if COMPARISON_LOG;
					if ( defined($$Paper{available_to_order}) and ( $$Paper{available_to_order} > 1 ) ) {
						if ( $$Paper{available_to_order} < ( $$Paper{type} eq 'Sheet' ? $supplied_sheets : $supplied_weight ) ) {
							$$price{'Paper Breakdown'} .= $Supplied->to_string() . ' does not have enough available. Only ' . $$Paper{available_to_order} . $Paper->units() . ' left.<br/>';
							$$price{alert} .= $Supplied->to_string() . ' does not have enough available. Only ' . $$Paper{available_to_order} . $Paper->units() . ' left.<br/>';
							$$price{ComparisonCost} += 1000000;
							$$price{'Comparison Log'} .= 'Paper not available +1000000 total: ' . $$price{ComparisonCost} . '<br/>' if COMPARISON_LOG;
						} # end if
					} # end if
					$$price{'Stock Total'} += $$paper_price{Total};
					$log->error('No factor') if ! $Paper->factor();
					$log->error('No width' . $Paper->to_string() ) if ! $Paper->width();

					if ( $Supplied->wpsi() ) {
						if ( $Supplied->width() ) {
							$$price{'Paper Breakdown'} .= sprintf('Stock: %s %s %s %s, %slbs * %.2f/100lbs = $%.2f<br/>', 
								( $$Paper{type} eq 'Sheet' ? $supplied_sheets.'sheets' : ( $supplied_weight.'lbs '. Math::Round::nearest(0.01, ($supplied_weight / $Supplied->wpsi() ) / $Supplied->width() ) . ' linear feet' ) ), 
								$Paper->id_string(),
								( $Supplied->sheets_per_package() ? 'SPP:'.$Supplied->sheets_per_package() : '' ),
								( $Supplied->minimum_order() ? 'minimum:'.$Supplied->minimum_order() : '' ),
								$supplied_weight, @$paper_price{'100lb Price','Total'} );
						} else {
							$$price{'Paper Breakdown'} .= 'Stock has no width...<br/>';
						} # end if
					} else {
						$$price{'Paper Breakdown'} .= 'No wpsi for stock ' . $Paper->to_string() . '</br>';
					} # end if
				} # end foreach Paper in PaperCounts

				#$log->debug($$price{'Paper Breakdown'}) if DEBUG;
				#$log->debug("Comparison: $$price{ComparisonCost}");
				if ( $do_stock_cutting and $$project{HasCutting} ) {
					my @Stocks = map { ( $Papers{$_} and $Papers{$_}->is_cut() ) ? { Stock => $Papers{$_}, quantity=>$PaperCounts{$_} } : () } keys %PaperCounts;
					my %cutting_results = openprint::Estimating::Cutting::signature_calc_stock_cutting( $Project, $$project{CuttingSpecs}, $qty_index, \@Stocks );
					$$price{'Cutting Breakdown'} .= "Stock Cutting Price: \$$cutting_results{Price} $cutting_results{alert}<br/>$cutting_results{Breakdown}<br/>";
					$$price{ComparisonCost} += $cutting_results{Price};
					$$price{'Comparison Log'} .= 'cutting: +'.$cutting_results{Price}.' total: ' . $$price{ComparisonCost} . '<br/>' if COMPARISON_LOG;
				} # end if

        if ( ! $PaperServiceType ) {

					my $paper_string = $Paper->id_string();

					if ( $Paper->full_packages() ) {
						if ( my $sheets_per_package = $Paper->sheets_per_package() ) {
							$PaperCounts{$paper_string} = $sheets_per_package * ceil( $PaperCounts{$paper_string}/$sheets_per_package );
						} # end if
					} # end if

#$log->debug("Pricing Paper: Minimum Order: " . $Paper->minimum_order() );
					if ( $Paper->minimum_order() ) {
# Assume sheets for sheets, lbs for Rolls
						if ( $Paper->minimum_order() > $PaperCounts{$paper_string} ) {
							$PaperCounts{$paper_string} = $Paper->minimum_order();
						} # end if
					} # end if
					my $supplied_weight;
					my $supplied_sheets;
					my $Supplied = $Paper->Supplied();
					my $paper_price;

					if ( $$Paper{type} eq 'Sheet' ) {
						$supplied_sheets = ceil($PaperCounts{$paper_string}/$Paper->factor());
						$supplied_weight = ceil( $supplied_sheets * $Supplied->sheet_weight() );
						$paper_price = $Supplied->get_price( sheets=>$supplied_sheets, service=>'Material' );
					} else {
						$supplied_weight = ceil( $PaperCounts{$paper_string}/$Paper->factor() );
						$paper_price = $Supplied->get_price( weight=>$supplied_weight, service=>'Material' );
					} # en dif

					$$paper_price{Total} = Math::Round::nearest( 0.01, $$paper_price{'100lb Price'} * $$price{'Stock Weight'} / 100 );
					@$price{'Paper Cost', 'Paper Price', 'Stock Total'} = @$paper_price{'100lb Cost', '100lb Price', 'Total'};
					$$price{'Total Cost'} += $$price{'Stock Total'};
				} # end if

				if ( ! $$project{stocksetupcharged} ) {
					if ( my $StockSetupPrice = $Paper->get_price( weight=>$$price{'Stock Weight'}, service=>'Setup', equipment_id=>$Press->id() ) ) {
						$$price{StockSetup} = $$StockSetupPrice{price};
						$$price{'Total Cost'} += $$StockSetupPrice{price};
					} # end if
				} # end if
			} # end if do_final_pricing

			if ( $recursion_depth == 0 ) {
				if ( $sig_specs{txtSignatureType} ne 'Cover Pages' ) {

# The idea is to only calc these on the last sig
#FIXME if we cache the price for the subsig and do the stitching calc then, we may use a 1out stitching price.
# but then what about self cover books

					if ( $$project{HasStitching} ) {
						my $results;
						my $starttime = [gettimeofday()] if DEBUG;

						$log->debug("Stitching::signature_calc: recursion_depth; $recursion_depth do_final_pricing: $do_final_pricing total imps: " . @total_impositions) if DEBUG;
						$results = openprint::Estimating::Stitching::signature_calc($Project, @$project{'HasStitching','StitchingSpecs'}, $qty_index, \@total_impositions, $project);
						if ( $$results{Status} eq 'uncalculated' ) {
							$$price{'Stitching Breakdown'} .= 'Stitching error: '.$$results{alert}.'<br/>';
#$price{'Stitching Breakdown'} .= "Stitching error: $$results{alert} <br/>" . $$project{StitchingSpecs}{'hdnBreakdown'.$qty_index};
							$$price{ComparisonCost} += 10000000; # Can't stich this on
								$$price{'Comparison Log'} .= 'Stitching: +10000000 <br/>' if COMPARISON_LOG;
							$$price{'Stitching Cost'} = 10000000;
							$log->debug("After Stitching $$price{ComparisonCost} $$price{'Stitching Cost'} uncalculated") if DEBUG;
						} else {
							my $Price = $$results{Price};
							$$price{'Stitching Breakdown'} .= sprintf('Stitching (%s) %s %dout on %s Price: $%.2f<br/>',
									@$results{'Status','alert','Imposition'},$$results{Equipment}{name}, $$Price{Price});
							$$price{'Stitching Breakdown'} .= "breakdown(<br/>$$results{Breakdown})<br/>";
							$$price{'Stitching Cost'} = $$Price{Price};
							$$price{ComparisonCost} += $$Price{Price};
							$$price{'Comparison Log'} .= 'Stitching: $' .	$$Price{Price} . '<br/>' if COMPARISON_LOG;
#$stitching_cache{scalar @all_impositions} = $results;
							$log->debug("After Stitching $$price{ComparisonCost} $$price{'Stitching Cost'} $$results{Breakdown}") if DEBUG;
						} # end if
						$log->debug('Stitching Calc: ' . Math::Round::nearest(0.0001, tv_interval($starttime)*1000).' msecs') if DEBUG;

					} elsif ( $$services{PerfectBound} ) {
						my $starttime = [gettimeofday()] if DEBUG;
						my $results = openprint::Estimating::PerfectBound::signature_calc( $Project, $$project{HasPerfectBound}, $$project{PerfectBoundSpecs}, $qty_index, \@total_impositions, $project );
						$log->debug( 'Perfectbinding Calc: ' . sprintf('%.4fsecs', (gettimeofday()-$starttime)*1000) . ' secs' ) if DEBUG;
						if ( $$results{Status} eq 'uncalculated' ) {
							$$price{'PerfectBound Breakdown'} .= "PerfectBound error: $$results{alert}<br/>" if $$results{alert};
							$$price{ComparisonCost} += 1000000;
							$$price{'Comparison Log'} .= 'PerfectBound: 100000<br/>';
							$$price{'PerfectBound Cost'} = 1000000;
						} else {
							$$price{'PerfectBound Breakdown'} .= sprintf('PerfectBound (%dout) Price: $%.2f<br/>%s<br/>', @$results{'Imposition','total','alert'} );
							$$price{'PerfectBound Cost'} = $$results{total};
							$$price{ComparisonCost} += $$results{total};
							$$price{'Comparison Log'} .= 'PerfectBound: ' . $$results{total} . '<br/>';
						} # end if
					} # end if Stitching or PerfectBound
				} # end if not Cover
			} # end if recursion_depth == 0

			if ( $do_final_pricing ) {

				if ( $calc_other_groups and ($sig_specs{txtSignatureType} eq 'Cover Pages') ) {
					# Layout can affect stitching
					#my $other_group_cache_key = $$Press{id}; #join(',', $$Press{id}, $$imp{imposition}, $$imp{columns} );
					my $other_group_cache_key = join(',', $$Press{id}, @$imp{'imposition','columns'} );
					if ( ! $other_group_cache{$other_group_cache_key} ) {
# When doing the cover, need to calc additional sigs as well.
# Add calculations for other Groups
						$log->debug("Calculating Additional Signatures for other group $other_group_cache_key group $sig_specs{Group}") if DEBUG;
						if ( DEBUG ) {
							$log->debug(' %other_group_cache ');
							foreach my $k ( keys %other_group_cache ) {
								$log->debug("pressid impo columns $k => ");
							}
						}
						my @sigs = sort $Project->signatures({Group=>2, sort=>1});
						if ( @sigs ) {
							my $Group = 2;
							if ( !$Estimating_Setup{$Group} ) {
								my $Setup = $Estimating_Setup{$Group} = {};

								my $Service = $$Setup{Service} = $Project->Service($sigs[0]);

								%{$$Setup{specs}} = %{$Service->specs()};
								my $subsig_specs = $$Setup{specs};
								if ( $$subsig_specs{txtSignatureType} eq 'Cover Pages' ) {
									$log->error("subsig type: $$subsig_specs{txtSignatureType}");
								} else {
									set_size($Project, $$Setup{specs}, $printing_specs);
									$$Setup{side_one_colours} = [ get_colours($$Setup{specs}, 'SideOne') ];
									$$Setup{side_two_colours} = [ get_colours($$Setup{specs}, $$Setup{specs}{side_link} ? 'SideOne' : 'SideTwo') ];
									foreach my $q_index ( $Project->quantity_indexes() ) {
										$$subsig_specs{'txtUnspecifiedPageQuantity'.$q_index} = get_unspecified_pages($Project, $sigs[0], $subsig_specs, $q_index);
										$log->error("Subsig upq " . $$subsig_specs{'txtUnspecifiedPageQuantity'.$q_index});
									}
									$$Setup{Stocks} = [ get_Stocks( $Project, $$Setup{specs} ) ];
									if ( @{$$Setup{Stocks}} ) {

										my %Overrides = get_overrides( $Project, $subsig_specs );
										$$Setup{Overrides} = \%Overrides;

										my $new_project = $$Setup{project} = setup_project( $Project, $sigs[0], $Project->services(), @$Setup{'specs','side_one_colours', 'side_two_colours'}, $$Setup{Stocks}[0] );
                    #$log->error("PreviousPress from $$subsig_specs{PreviousPress} ");
# This isn't perfect, as we may actually need a stock setup charge for the other group
										$$new_project{stocksetupcharged} = $$project{stocksetupcharged};

# May also need to adjust paper_counts

										my %presses = select_presses( $Project, @$Setup{'Stocks', 'specs', 'project'} );
										$$Setup{presses} = \%presses;
# POssible_presses is not global
										my @possible_presses = map { $presses{$_} ? () : new openprint::Equipment($_) } keys %presses;
#foreach my $press_id ( keys %presses ) {
#my $E = new openprint::Equipment( $press_id );
#$imp->display("Presses for other group: $press_id $$E{strid} $presses{$press_id}");
#if ( ! $presses{$press_id} ) {
#push @possible_presses, new openprint::Equipment($press_id);
#} # end if
#} # end foreach
										if ( @possible_presses ) {
											@possible_presses = sort { $$a{strid} cmp $$b{strid} } @possible_presses;
											$$Setup{possible_presses} = \@possible_presses;
											my @available_printingtypes = sets::union(map { $_->specification('Printing Type') } @possible_presses);
											$$Setup{specs}{PrintingTypes} = get_printing_types( $Project, $sigs[0], $printing_specs, $$Setup{specs}, $qty_index, \@available_printingtypes, $imp );
$imp->display("PrintingTYpes for other group: " . join(',', @{$$Setup{specs}{PrintingTypes}} ) ) if $$Setup{specs}{PrintingTypes};
											my %sub_impositions = get_impositions($Project, $$Setup{specs}, $new_project, $qty, $qty_index, \@possible_presses, $$Setup{Stocks}, \%Overrides);
											convert_impositions($Project, @$Setup{'project','specs'}, $qty_index, \%sub_impositions);

#$log->debug("other groups: Unspecified [ages:".$subsig_specs{'txtUnspecifiedPageQuantity'.$qty_index} );
											if ( %sub_impositions ) {
												my %sub_previous_forms_cache;
												my @o_impositions;
												foreach my $i ( $imp, @{$other_impositions} ) {
													next if $$i{specs}{Group} == $Group;
													push @o_impositions, $i;
													my $Press = $i->Press();
													my $hash_key = join(',', $$Press{strid}, $$i{runstyle}, $$i{pages}, $$i{imposition}, $$i{columns});
													$sub_previous_forms_cache{$hash_key} += 1;
													$log->debug("$$Press{strid}, $$i{runstyle}, $$i{pages}, $$i{imposition}, $$i{columns} = $sub_previous_forms_cache{$hash_key}" ) if DEBUG;
												} # end foreach previous_imp
												$$Setup{previous_forms_cache} = \%sub_previous_forms_cache;
												$$Setup{other_impositions} = \@o_impositions;
} else {
$log->warn("No sub impositions");
											}
											$$Setup{impositions} = \%sub_impositions;
} else {
$log->warn("No possible presses");

										} # end if possible_presses
									} # end if has Stocks
								} # end if inside is also cover
} else {
$log->debug("Have estimating setup");
							} # end if have Estimating_Setup

							my $Setup = $Estimating_Setup{$Group};

							if ( !($$Setup{impositions} and %{$$Setup{impositions}}) ) {
								$$price{Breakdown} .= 'Unable to calculate impositions for additional signatures.<br/>';
								$$price{'Comparison Log'} .= 'Additiona Sigs due to no impositions: 1000000<br/>' if COMPARISON_LOG;
								$$price{ComparisonCost} += 1000000;
								$log->warn('Unable to calculate impositions for additional signatures.<br/>');
							} else {
								my @Papers = @{$$Setup{Stocks}};
								if ( @Papers ) {
									my $sig_price = get_project_price(
											$Project, $sigs[0], @$Setup{'project', 'specs'}, $qty, $qty_index,
											$$Setup{possible_presses}, $printing_specs, $versions, \%PlateCounts,
											\%PaperCounts, \%washed_colours, \%mixed_colours, \%aq_makereadies,
											$$Setup{previous_forms_cache}, \@sigs, @$Setup{'impositions','other_impositions'}, {}, 0);
									$other_group_cache{$other_group_cache_key} = $sig_price;

									$log->debug('Setting other group cache' . %other_group_cache);
									foreach my $k ( keys %other_group_cache ) {
										$log->debug("other_group_cache $k => ");
									}
								} else {	
									$$price{'Comparison Log'} .= 'Additional Sigs due to no papers: 1000000<br/>' if COMPARISON_LOG;
									$$price{ComparisonCost} += 1000000;
									$log->warn("Unable to calculate impositions for additional signatures.<br/>");
								} # end if
							}
						} else {
							$log->warn('No sigs for group 2?');
						} # end if has other sigs
					} elsif ( DEBUG ) {
						$log->debug('Using cached price');
					} # end if ! $other_group_cache
					my $sig_price = $other_group_cache{$other_group_cache_key};
					if ( $sig_price and $$sig_price{Imposition} ) {
						$$price{ComparisonCost} += $$sig_price{ComparisonCost};
						if ( COMPARISON_LOG ) {
						#$log->debug("Calculating Additional Signatures for other group success CC: $$sig_price{ComparisonCost}");
							$$price{'Comparison Log'} .= breakdown($sig_price) if DEBUG;
							$$price{'Comparison Log'} .= 'Other sig: ' . $$sig_price{ComparisonCost} . '<br/>';
							$$price{'Comparison Log'} .= $$sig_price{'Comparison Log'} . '<br/>';
						}
		#$$price{'itionalSignature Breakdown'} .= breakdown( $sig_price, $sig_specs );
					} else {
						$log->error('Calculating Additional Signatures for other group failure') if DEBUG;
						$$price{Breakdown} .= 'Unable to calculate additional signatures.<br/>';
						$$price{ComparisonCost} += 10000000;
						$$price{'Comparison Log'} .= 'Additional Sigs: 1000000<br/>' if COMPARISON_LOG;
					} # end if
				} # end if Group == Cover Pages
			} # end if ! upq

			if ( $$price{ComparisonCost} < 0 ) {
				$log->error("Negative price! $best_price{ComparisonCost} <= $$price{ComparisonCost}");
			} elsif ( %best_price and ( $best_price{ComparisonCost} < $$price{ComparisonCost} ) ) {
				if ( DEBUG_PRICE_DECISIONS ) {
					$log->debug("Resulting price worst than best: $best_price{ComparisonCost} <= $$price{ComparisonCost}");
					$imp->display($recursion_depth.'Worst than best');
					my $breakdown = breakdown( $price, \%sig_specs );
					my $stitching_breakdown = $$price{'Stitching Breakdown'};
					foreach my $sig_price ( @{$$price{prices}} ) {
						$stitching_breakdown = $$sig_price{'Stitching Breakdown'} if $$sig_price{'Stitching Breakdown'}; 
					} # end foreach

					$breakdown .= join('',
							( defined $$price{'SpinePaste Breakdown'} ? $$price{'SpinePaste Breakdown'} : '' ),
							( defined $$price{'PerfectBound Breakdown'} ? $$price{'PerfectBound Breakdown'} : '' ),
							( defined $$price{'Paper Breakdown'} ? $$price{'Paper Breakdown'} : '' ),
							( defined $stitching_breakdown ? $stitching_breakdown : '' ),
							( defined $$price{'Comparison Log'} ? sprintf('Comparison Log: %s total: $%.2f<br/>', @$price{'Comparison Log','ComparisonCost'}) : '' ),
							);
					$log->debug( 'this: ' . $breakdown );
					$best_price{Imposition}->display('best dpeth: ' . $recursion_depth . ' group: ' . $sig_specs{Group} );
					$breakdown = breakdown( \%best_price, $best_price{specs} );
					$breakdown .= join('',
							( defined $best_price{'SpinePaste Breakdown'} ? $best_price{'SpinePaste Breakdown'} : '' ),
							( defined $best_price{'PerfectBound Breakdown'} ? $best_price{'PerfectBound Breakdown'} : '' ),
							( defined $best_price{'Paper Breakdown'} ? $best_price{'Paper Breakdown'} : '' ),
							( defined $stitching_breakdown ? $stitching_breakdown : '' ),
							( defined $best_price{'Comparison Log'} ? sprintf('Comparison Log: %s total: $%.2f<br/>', @best_price{'Comparison Log','ComparisonCost'}) : '' ),
							);
					$log->debug('best: ' . $breakdown);
				}
			} else {

				if ( DEBUG_PRICE_DECISIONS ) {
					$imp->display("Depth: $recursion_depth Group: $sig_specs{Group} New best price chosen: $best_price{ComparisonCost} >= $$price{ComparisonCost}");
					if ( %best_price ) {
						my $stitching_breakdown = $best_price{'Stitching Breakdown'};
						foreach my $sig_price ( @{$best_price{prices}} ) {
							$stitching_breakdown = $$sig_price{'Stitching Breakdown'} if $$sig_price{'Stitching Breakdown'}; 
						} # end foreach
						my $breakdown = breakdown( \%best_price, \%sig_specs );
						$breakdown .= join('',
								( defined $best_price{'SpinePaste Breakdown'} ? $best_price{'SpinePaste Breakdown'} : '' ),
								( defined $best_price{'PerfectBound Breakdown'} ? $best_price{'PerfectBound Breakdown'} : '' ),
								( defined $best_price{'Paper Breakdown'} ? $best_price{'Paper Breakdown'} : '' ),
								( defined $stitching_breakdown ? $stitching_breakdown : '' ),
								( defined $best_price{'Comparison Log'} ? sprintf('Comparison Log: %s total: $%.2f<br/>', @best_price{'Comparison Log','ComparisonCost'}) : '' ),
								);

						$log->debug('best: '.$breakdown);
						foreach my $I ( @{ $best_price{Impositions} } ) {
							$I->display($recursion_depth. 'OLD BEST:');
						} # end while
					} else {
						$log->debug('No previous best');
					} # end if
				}
		#keep track of the best price we have found so far.
				%best_price = %{$price};
				$$imp{Price} = $$price{ComparisonCost};

				#if ( ! $recursion_depth ) {

				#$log->debug( breakdown( \%best_price, $sig_specs ) );
				#if ( $best_price{Impositions} ) {
				#$best_price{'AdditionalSignature Breakdown'} = '';
				#my @impositions = @{$best_price{Impositions} };
				#shift @impositions;
				#if ( @impositions ) {
				#my @prices = @{$best_price{prices}};
				#foreach my $I ( @impositions ) {
				#$best_price{'AdditionalSignature Breakdown'} .= sprintf( '<br/><b>Additional Signature %dpages %dout %s on %sx%s on %s</b><br/>', @$I{'pages', 'imposition', 'runstyle'}, $I->Paper()->width(), $I->Paper()->height(), $I->Press()->strid() );
				#my $price = shift @prices;
				##$best_price{'AdditionalSignature Breakdown'} .= breakdown( $price, $$I{specs} );
				#} # end foreach
				#} # end if @impositions
				#} # end if
				#$best_price{Breakdown} = breakdown( \%best_price, $sig_specs );
				#} # end if
				if ( DEBUG_PRICE_DECISIONS ) {
					my $breakdown = breakdown( \%best_price, \%sig_specs );
					my $stitching_breakdown = $best_price{'Stitching Breakdown'};
					foreach my $sig_price ( @{$best_price{prices}} ) {
						$stitching_breakdown = $$sig_price{'Stitching Breakdown'} if $$sig_price{'Stitching Breakdown'}; 
					} # end foreach
					$breakdown .= join("",
							( defined $best_price{'SpinePaste Breakdown'} ? $best_price{'SpinePaste Breakdown'} : '' ),
							( defined $best_price{'PerfectBound Breakdown'} ? $best_price{'PerfectBound Breakdown'} : '' ),
							( defined $best_price{'Paper Breakdown'} ? $best_price{'Paper Breakdown'} : '' ),
							( defined $stitching_breakdown ? $stitching_breakdown : 'No Stitching' ),
							( defined $best_price{'Comparison Log'} ? sprintf('Comparison Log: %s total: $%.2f<br/>', @best_price{'Comparison Log','ComparisonCost'}) : '' ),
							);
					$breakdown =~ s/<br\/>/\n/g;
					$log->debug( 'new: ' . $breakdown );
					foreach my $I ( @{ $best_price{Impositions} } ) {
						$I->display( $recursion_depth . "NEW BEST qty_index: $qty_index:" );
					} # end while
				} # DEBUG_PRICE_DECISIONS
			} # end if better or worse price
		} # end foreach imposition
	if ( ! %best_price ) {
		$log->debug("Returning from get_project_price with no best price $recursion_depth");
		return {};
	} # end if
	if ( DEBUG_PRICE_DECISIONS or $sig_specs{txtSignatureType} eq 'Cover Pages' and ! $recursion_depth ) {
		$best_price{Imposition}->display( "Depth: $recursion_depth Group: $$source_sig_specs{Group} Returning: qty_index: $qty_index :" );
		if ( $best_price{Impositions} ) {
			foreach my $I ( reverse @{ $best_price{Impositions} } ) {
				$I->display( join('', map { ' ' } ( 1 .. $recursion_depth ) ) . "FINAL BEST: qty_index: $qty_index :" );
			} # end while
		} 
	}# DEBUG_PRICE_DECISIONS
	return \%best_price;
} # end sub get_project_price

# All this does is get the price of the plates.	Not special.

# I don't think we are supposed to add to Comparison Costs, 
sub plate_cost {
	my %results;

	my ( $price, $PlateCounts ) = @_;
	my $plate_costs = $$price{'Plate Costs'};
	$results{Price} = 0;

	my %plate_price;
	if ( $$plate_costs{'Plate ID'} ) {
		my $Material = $Materials{$$plate_costs{'Plate ID'}};
		if ( $Material ) {
			%plate_price = $Material->get_price( $$PlateCounts{$$plate_costs{'Plate ID'}}, undef );
			$$price{'Plate Cost'} = $plate_price{Price};
			$$price{'Plate Price'} = $plate_price{Price} * $$plate_costs{'Plate Count'};
			$results{Price} = Math::Round::nearest(0.01, $plate_price{Price} * $$plate_costs{'Plate Count'} );

			if ( $$plate_costs{'Plate Type'} eq 'Conventional' ) {
				my $area = $Material->specification('area');
				my $qty = $area * $$PlateCounts{$$plate_costs{'Plate ID'}};
				$$price{'Film Cost'} = openprint::service::get_price( 'Film', $qty ) * $qty;
				$results{Price} += $$price{'Film Cost'};
			} # end if
		} # end if

		if ( $$plate_costs{'Blank Plates'} ) {
			$$price{txtBlankPlateQuantity} = $$plate_costs{'Blank Plates'};
			if ( my $Blank = $Materials{'Blank'.$$plate_costs{'Plate ID'}} ) {
				my %blank_plate_price = $Blank->get_price( $$PlateCounts{'Blank'.$$plate_costs{'Plate ID'}}, undef );
				$$plate_costs{'Blank Price'} = $blank_plate_price{Price};
				$$price{'Blank Plate Price'} = Math::Round::nearest(0.01, $$plate_costs{'Blank Plates'} * $$plate_costs{'Blank Price'} );
				$results{Price} += $$price{'Blank Plate Price'};
			} else {
				$$plate_costs{'Blank Price'} = 0;
				$$price{'Blank Plate Price'} = 0;
			}
		} else {
			$$plate_costs{'Blank Price'} = 0;
			$$price{'Blank Plate Price'} = 0;
		} # end if
	} # end if
	return \%results;
} # end sub plate_cost

# Takes and Imposition object, and calculates a Price Object.
# Does not need to take folding or Cutting into account, as those were chosen separately
sub calc_price {
	#my $aq_time = [gettimeofday()];
	my ( $Project, $service_index, $Imposition, $project, $services, $specs, $qty, $qty_index, $PlateCounts, $washed_colours, $mixed_colours, $aq_makereadies, $other_impositions ) = @_;

	my $Paper = $$Imposition{Paper};
	my $Press = $$Imposition{Press};

	my %price;
	$price{Imposition} = $Imposition;
	$price{ComparisonCost} = 0;

	my @colours = ();
	$price{'WorkTurn Dry Charge'} = 0;

#$log->debug("\n\n************ START OF CALC PRINT PRICE QTY: $qty 1: @$side_one_colours, @$side_two_colours CAL: $paper_calliper DT: $dry_trap	STYLE: $run_style ********* \n\n\n");
	my ( $is_sheetwork, $is_perfecting, $is_wt );
	if ( $$Imposition{runstyle} eq 'Sheet Work' or $$Imposition{runstyle} eq 'Web' ) {
		$is_sheetwork = 1;
		$is_perfecting = 0;
		$is_wt = 0;
		@colours = ( @{$$project{side_one_colours}}, @{$$project{side_one_coatings}} );
		if ( ( $$specs{sides_the_same} eq 'Y' ) and ( $$Imposition{runstyle} eq 'Sheet Work' ) ) {
		} else {
			push @colours, @{$$project{side_two_colours}}, @{$$project{side_two_coatings}};
		} # end if

	} elsif ( $$Imposition{runstyle} =~ /^Work/ ) {
		$is_sheetwork = 0;
		$is_perfecting = 0;
		$is_wt = 1;

		my $WTDryPrice;
		if ( $Services{$$Imposition{runstyle}.' Drying'} ) {
			$WTDryPrice = $Services{$$Imposition{runstyle}. ' Drying'}->get_Price( $$Paper{grade}, $Press );
		} elsif ( $Services{WTDrying} ) {
			$WTDryPrice = $Services{WTDrying}->get_Price( $$Paper{grade}, $Press );
		}
		if ( $WTDryPrice ) {
			$price{'WorkTurn Dry Charge'} = $$WTDryPrice{Price};
		} # end if 
		@colours = ( @{$$project{filtered_colours}},@{$$project{filtered_coatings}} );
	} elsif ( $$Imposition{runstyle} eq 'Perfecting' ) {
#$log->debug("************ WE HAVE PERFECTING ****************");
		$is_sheetwork = 1;
		$is_perfecting = 1;
		$is_wt = 0;
		@colours = ( @{$$project{side_one_colours}}, @{$$project{side_one_coatings}} );
		if ( $$specs{sides_the_same} ne 'Y' ) {
			push @colours, @{$$project{side_two_colours}},@{$$project{side_two_coatings}};
		} # end if
	} else {
		$log->error("\n\n\n********* UNKNOWN RUNSTYLE($$Imposition{runstyle}): in function 'calc_price' ****************\n\n\n");
	} # end if

	my $imposition = $$Imposition{imposition};
	if ( defined $$specs{"UnspecifiedVersions$qty_index"} and ($$specs{"UnspecifiedVersions$qty_index"} >= 1 ) ) {
		if ( ( defined $$specs{"OverrideVersions$qty_index"} ) and ( $$specs{"OverrideVersions$qty_index"} eq 'Y' ) ) {
			if ( $$specs{"Versions$qty_index"} > $imposition ) {
				if ( DEBUG ) {
					$log->debug("Incomplete due to required versions more than imposition when overriden.");
				}
				$price{complete} = 0;
				return;
			} # end if
      #FIXME: Should just kill the imposition
			#$$Imposition{versions} = $$specs{"Versions$qty_index"};
		} else {
# When W&T, each half has to be a multiple of the versions
			if ( $is_wt ) {
				$imposition = int($imposition/2);
				if ( $imposition < $$specs{"UnspecifiedVersions$qty_index"} ) {
#i.e. if imp = 12 and ver = 30 then only 10 of the slots get used.
					$imposition = $$specs{"UnspecifiedVersions$qty_index"} / ceil($$specs{"UnspecifiedVersions$qty_index"} / $imposition);
				} else {
#i.e. if imp = 72 and ver = 30 then only 60 of the slots get used.
					$imposition = int($imposition / $$specs{"UnspecifiedVersions$qty_index"}) * $$specs{"UnspecifiedVersions$qty_index"};
				} # end 
				$imposition *= 2;
			} else {
# if we have a multiple version project, we may need to adjust the sheet count because, we may	not be able to use all of the slots.
				if ( $imposition < $$specs{"UnspecifiedVersions$qty_index"} ) {
#i.e. if imp = 12 and ver = 30 then only 10 of the slots get used.
# I don't think we should do this.	For example 111 versions needed, impo 63 out. versions should be 63
#$imposition = $$specs{"UnspecifiedVersions$qty_index"} / ceil($$specs{"UnspecifiedVersions$qty_index"} / $imposition);
				} else {
#i.e. if imp = 72 and ver = 30 then only 60 of the slots get used.
					$imposition = int($imposition / $$specs{"UnspecifiedVersions$qty_index"}) * $$specs{"UnspecifiedVersions$qty_index"};
				} # end 
			} # end 
			if ( $imposition < $$specs{"UnspecifiedVersions$qty_index"} ) {
				#$$Imposition{versions} = $imposition;
			} else {
				#$$Imposition{versions} = $$specs{"UnspecifiedVersions$qty_index"};
			} # end if
		} # end if
		my $VersionService = $Services{'Version Setup'};
		my %VersionCharge = $VersionService->get_price( $$Imposition{version_qty} ) if $VersionService;
		if ( %VersionCharge ) {
			if ( $VersionCharge{units} eq 'each' ) {
				$VersionCharge{Total} = $VersionCharge{Price}*$$Imposition{version_qty};
			} elsif ( $VersionCharge{units} eq 'total' ) {
				$VersionCharge{Total} = $VersionCharge{Price};
			} else {
				$log->error("unknown units	$VersionCharge{units} for VersionCharge");
			} # end if
			$price{'Version Charge'} = Math::Round::nearest( 0.01, $VersionCharge{Total} );
			$price{'Version Price'} = \%VersionCharge;
		} # end if
	} else {
		$price{'Version Charge'} = 0;
	} # end if UnspecifiedVersions

	my $net_sheets = $qty;
	$net_sheets = ceil($net_sheets / $imposition);
	#$net_sheets *= $$Imposition{versions} if $$Imposition{versions}; # qty is already adjusted, not sure this is valid anymore
	$net_sheets *= $$Paper{parts} if $$Paper{parts};

#Initially we calculate based on colours, but really we need to calculate based on plates, which we will do once we figure out how many plates we need.
	my $num_colours = scalar @colours;
	my $min_overs = $Press->specification('Overs Minimum '.$Paper->material(), $num_colours) if $Paper->material();
	$min_overs = $Press->specification('Overs Minimum', $num_colours) if ! $min_overs;
	$min_overs = 0 if ! defined $min_overs;
	my $overs = 0;

	my $setup_rate;
	if ( $$project{print_sides} == 1 ) {
		$setup_rate = $Press->specification('MakeReady Overs Rate One Side', $num_colours);
	} else {
		$setup_rate = $Press->specification('MakeReady Overs Rate ' . $$Imposition{runstyle}, $num_colours);
	} # end if
	$setup_rate = $Press->specification('MakeReady Overs Rate ' . $Paper->material(), $num_colours) if ! $setup_rate and $Paper->material();
	$setup_rate = $Press->specification('MakeReady Overs Rate', $num_colours) if ! $setup_rate;

	my $is_Roll2Sheet = $$Imposition{is_roll2sheet} = ( ($$Paper{type} eq 'Roll') and $$Press{Feeds}{Sheet} ) ? 1 : 0;
	my $roll2sheet_setup_overs_rate = $Press->specification('Roll2Sheet Additional Setup Overs') if $is_Roll2Sheet;
 
	$setup_rate *= ( 1 + ( $roll2sheet_setup_overs_rate / 100 ) ) if $roll2sheet_setup_overs_rate;

	my $roll2sheet_run_overs_rate = $Press->specification('Roll2Sheet Additional Run Overs') if $is_Roll2Sheet;

	my $setup_overs;
	if ( $$specs{'OverrideSetup'.$qty_index} and ( $$specs{'OverrideSetup'.$qty_index} eq 'Y' ) ) {
		$setup_overs = $$specs{'OverSetup'.$qty_index};
	} elsif ( $setup_rate ) {
    $openprint::log->debug("Have setup_rate?! $setup_rate");
		$setup_overs = int($setup_rate * $num_colours);
	} else {
		$setup_overs = $Press->specification('MakeReady Overs '.$$Imposition{runstyle}, $num_colours);
		$setup_overs = $Press->specification('MakeReady Overs', $num_colours) if ! $setup_overs;
    $openprint::log->debug('No MakeReady Overs?!') if ! $setup_overs;
	} # end if

	#$setup_overs *= ( 1 + ( $roll2sheet_setup_overs_rate / 100 ) ) if $roll2sheet_setup_overs_rate;

	if ( $$specs{'OverrideRun'.$qty_index} and ( $$specs{'OverrideRun'.$qty_index} eq 'Y' ) ) {
		$price{'Run Overs'} = { impressions=>$net_sheets, value=>$$specs{'OverRun'.$qty_index}, units=>'overriden sheets', total=>$$specs{'OverRun'.$qty_index} };
	} else {
# Should include bindery overs, but not setups, because the setup overs do the same job as the Run Overs
		my $PressRunOvers = $Press->Specification('Press Run Overs', $net_sheets);
		if ( $PressRunOvers ) {
			if ( ( $$specs{txtSignatureType} eq 'Cover Pages' ) and ( $_ = $Press->Specification('Covers Overs Percentage') ) ) {
				$PressRunOvers = $PressRunOvers->copy();# Need to copy otherwise value will grow
				$$PressRunOvers{value} *= ( 1 + ($$_{value} / 100) ) if $$_{value};
			}
			if ( $$PressRunOvers{units} eq 'Press Sheets' ) {
				$$PressRunOvers{total} = $$PressRunOvers{value};
			} else {
				#Percentage
				$$PressRunOvers{total} = int($$PressRunOvers{value}/100 * $net_sheets);
			}
			$price{'Run Overs'} = { impressions=>$net_sheets, value=>$$PressRunOvers{value}, units=>$$PressRunOvers{units}, total=>$$PressRunOvers{total} };
		} else {
			$price{'Run Overs'} = { impressions=>$net_sheets, value=>0, units=>'', total=>0};
		}
    my $run_overs_minimum = $Press->Specification('Press Run Overs Minimum');
    if ($run_overs_minimum and ($$PressRunOvers{total} < $$run_overs_minimum{value})) {
      $price{'Run Overs'}{total} = $$run_overs_minimum{value};
    }
  } # end if
  my $run_overs = $price{'Run Overs'}{total};

	my $fm_overs = 0;
	if ( $$specs{ScreenType} and ( $$specs{ScreenType} eq 'FM' ) ) {
		$fm_overs = $Press->specification('FM Screening Additional Overs', undef);
		$fm_overs = 0 if ! defined $fm_overs;
		$setup_overs += $fm_overs;
	} # end if

	my $plate_changes = 0;
	if ( $$project{ProjectSpecs}{"txtPlateChangeQuantity-$$specs{Group}"} ) {
		if ( $$project{ProjectSpecs}{"PlateChangeType-$$specs{Group}"} ) {
			if ( $$project{ProjectSpecs}{"PlateChangeType-$$specs{Group}"} eq '1/0' ) {
				$plate_changes += $$project{ProjectSpecs}{"txtPlateChangeQuantity-$$specs{Group}"};
			} elsif ( $$project{ProjectSpecs}{"PlateChangeType-$$specs{Group}"} eq '1/1' ) {
				$plate_changes += 2 * $$project{ProjectSpecs}{"txtPlateChangeQuantity-$$specs{Group}"};
			} elsif ( $$project{ProjectSpecs}{"PlateChangeType-$$specs{Group}"} eq '4/0' ) {
				$plate_changes += 4 * $$project{ProjectSpecs}{"txtPlateChangeQuantity-$$specs{Group}"};
			} elsif ( $$project{ProjectSpecs}{"PlateChangeType-$$specs{Group}"} eq '4/4' ) {
				$plate_changes += 8 * $$project{ProjectSpecs}{"txtPlateChangeQuantity-$$specs{Group}"};
			}
		} else {
			$plate_changes += $$project{ProjectSpecs}{"txtPlateChangeQuantity-$$specs{Group}"};
			$price{alert} .= 'Please select the type of plate change.<br/>';
		}
	} # end if project platechanges

	if ( $$specs{'txtPlateChangeQuantity'.$qty_index} ) {
		if ( my $type = $$specs{'PlateChangeType'.$qty_index} ) {
			if ( $type eq '1/0' ) {
				$plate_changes += 1 * $$specs{'txtPlateChangeQuantity'.$qty_index};
			} elsif ( $type eq '1/1' ) {
				$plate_changes += 2 * $$specs{'txtPlateChangeQuantity'.$qty_index};
			} elsif ( $type eq '4/0' ) {
				$plate_changes += 4 * $$specs{'txtPlateChangeQuantity'.$qty_index};
			} elsif ( $type eq '4/4' ) {
				$plate_changes += 8 * $$specs{'txtPlateChangeQuantity'.$qty_index};
			}
		} else {
			$plate_changes += $$specs{'txtPlateChangeQuantity'.$qty_index};
			$price{alert} .= 'Please select the type of plate change.<br/>';
		}
	}
	
	my $additional_overs = 0;
	my $additional_overs_rate = 0;
	if ( $plate_changes ) {
		$additional_overs_rate = $Press->specification('Additional Plate Overs');
		$additional_overs_rate *= ( 1 + ( $roll2sheet_setup_overs_rate / 100 ) ) if $roll2sheet_setup_overs_rate;

		$additional_overs += ( $plate_changes * $additional_overs_rate );
		my $minimum = $Press->specification('Additional Plate Overs Minimum');
		$price{'Additional Plate Overs Minimum'} = $minimum;
		$additional_overs = $minimum if $minimum > $additional_overs;
	} # end if
	$overs = $additional_overs;

  my $all_overs = $Press->Specification('Overs');
	if ( $all_overs and ($$all_overs{value} eq 'All') ) {
		$overs += ceil($setup_overs + $run_overs);
	} else {
		$overs += ceil(($setup_overs > $run_overs) ? $setup_overs : $run_overs);
	} # end if
	$overs = $min_overs if $overs < $min_overs;

	my $impressions = $net_sheets + $overs;
	$impressions *= 2 if $$project{print_sides} == 2 and $is_wt;
# or ( $$Imposition{runstyle} eq 'Sheet Work' ) );

	my $max_impression_quantity = $Press->specification('Maximum Impression Quantity', $$Paper{calliper});
	if ( $max_impression_quantity and (
				($max_impression_quantity < $impressions)
				or ( $$Imposition{runstyle} eq 'Sheet Work' and $$project{print_sides} == 2 and $max_impression_quantity < $impressions*2 )
					) ) {
		$log->debug("Next cuz of maximum impression quantity $max_impression_quantity : $impressions") if DEBUG;
		return \%price;
	#} else {
		#$log->debug("NOT Next cuz of maximum impression quantity $max_impression_quantity : $impressions" ) if DEBUG;
	} # end if
	$$specs{'hdnImpressionQuantity'.$qty_index} = $impressions;
#$log->debug("Impressions $impressions overs: $overs setup: $setup_overs run: $run_overs");

	my $RunSpeed = $price{RunSpeed} = $Press->Specification('Run Speed '.$$Imposition{runstyle});
	$RunSpeed = $price{RunSpeed} = $Press->Specification('Run Speed') if ! $price{RunSpeed};
  if ($$specs{'RunspeedOverride'.$qty_index} and ($$specs{'RunspeedOverride'.$qty_index} eq 'Y')) {
    $$RunSpeed{value} = $$specs{'Runspeed'.$qty_index}
  }
  if ($$RunSpeed{range_units} eq 'calliper') {
    $RunSpeed = $price{RunSpeed} = $Press->Specification($$RunSpeed{name}, $$Paper{calliper});
  }

	my $std_speed = $price{StandardRunSpeed} = $Press->Specification('Standard Run Speed ' . $$Imposition{runstyle} );
	$price{StandardRunSpeed} = $std_speed = $Press->Specification('Standard Run Speed') if ! $std_speed;
	$std_speed = $price{RunSpeed} if ! $std_speed;

  if ( $RunSpeed ) {
    my $run_speed;
    if ($$specs{'RunspeedOverride'.$qty_index} and ($$specs{'RunspeedOverride'.$qty_index} eq 'Y')) {
      $run_speed = $$specs{'Runspeed'.$qty_index};
    } elsif ($$RunSpeed{units} eq 'per hour') {

      $run_speed = $$RunSpeed{value};
    } elsif ( $$RunSpeed{units} =~ /^Per (.+) Per Hour$/ ) {
      my $unit = $1;
      if ( $unit =~ /([\d\.]+)x([\d\.]+)/ ) {
        my $area = $1*$2;
        if ( ! $$Imposition{object_width} * $$Imposition{object_height} ) {
          $log->debug("Runspeed for $$Imposition{object_width} * $$Imposition{object_height} on $$Press{id}");
        } else {
          $run_speed = int( $$RunSpeed{value} * $area/($$Imposition{object_width} * $$Imposition{object_height}) );
#$log->debug("Runspeed = $$std_speed{value} $$std_speed{units} * $area / ( $$Imposition{object_width} * $$Imposition{object_height}) = $run_speed");
        } # end if
#$log->debug("Have runspeed $$std_speed{value}, area: $area, $run_speed");
      } else {
        $log->warn("Unknown Per setting $unit");
      } # end if
    } elsif ( lc $$RunSpeed{units} eq 'impressions' ) {
      $run_speed = $Press->specification($$RunSpeed{name}, $impressions);

      if (!$run_speed) {
        $log->debug("No run speed on $$Press{strid} for $$RunSpeed{units} $impressions") if DEBUG;
        $run_speed = $$RunSpeed{value};
      } # end if

    } elsif ( lc $$RunSpeed{units} eq 'calliper' ) {
      $run_speed = $Press->specification($$RunSpeed{name}, $$Paper{calliper});

      if ( ! $run_speed ) {
        $log->debug("No run speed on $$Press{strid} for $$RunSpeed{units} " . ($$RunSpeed{units} eq 'Calliper' ? $$Paper{calliper} : $Paper->gsm() ) ) if DEBUG;
        $run_speed = $$RunSpeed{value};
      } # end if
      #$log->debug("Std Runspeed by calliper($$Paper{calliper}): $run_speed on $$Press{strid}");
    } else {
			$run_speed = $Press->specification($$RunSpeed{name}, $$Paper{gsm});
    } # end if

		if ( $is_Roll2Sheet and my $roll2sheet_slowdown = $Press->Specification('Roll2Sheet Slowdown') ) {
			if ( $$roll2sheet_slowdown{units} eq 'Percent' ) {
$log->debug("Slowing down runspeed due to roll2sheet $run_speed *= ( 1-($$roll2sheet_slowdown{value}/100));") if DEBUG;
				$run_speed *= ( 1-($$roll2sheet_slowdown{value}/100));
$log->debug("Slowing down runspeed due to roll2sheet $run_speed *= ( 1-($$roll2sheet_slowdown{value}/100));") if DEBUG;

			} else {
				$log->error("Unknown units on roll2sheet slowdown");
			}
		}
		$$specs{"Runspeed$qty_index"} = $$specs{Runspeed} = $price{Runspeed} = $run_speed;
  } else {
    # No std_speed?!
		$log->error("No runspeed on $$Press{id}");
  }

	$$Imposition{runspeed} = $$specs{Runspeed};
$log->debug("Initial Runspeed: standard: $$RunSpeed{value}$$RunSpeed{units} actual: $$specs{Runspeed}") if DEBUG;

	my $folding_results;

# Has to be NEED because they always leave folding out, and it chooses dumb impositions
	if ( $$project{NeedFolding} ) {
		my $time = gettimeofday() if DEBUG;
		if ( $$Imposition{folding_results} ) {
			$folding_results = $$Imposition{folding_results};
			$log->debug("Using cached folding");
		} else {
#my @all_impositions = ( @{$other_impositions}, $Imposition );
			$folding_results = openprint::Estimating::Folding::signature_calc( $Project, $specs, $$project{FoldingSpecs}, $qty_index, $Imposition, $other_impositions, $project );
			$price{folding_results} = $$Imposition{folding_results} = $folding_results;
		} # end if

		delete $$Imposition{Folder};
		if ( $$folding_results{Status} eq 'uncalculated' ) {
# a 2 pg doesn't need folding, it's not an error
# or ( ( ! $$folding_results{Equipment} ) and ( $$project{FoldingSpecs}{"chkOverrideEquipment-$$specs{SignatureIndex}-$qty_index"} ne 'Y' ) ) ) {
# do not want an invalid fold style to win out unless there are no other valid signatures.
			$price{'Folding Breakdown'} .= sprintf('Unable to fold<br/>'.$$folding_results{Breakdown});
			$price{ComparisonCost} += 10000000; 

			# WHy are we doing this?	
			if ( ( ! $$project{FoldingSpecs}{"chkOverrideEquipment-$$specs{SignatureIndex}-$qty_index"} ) or ( $$project{FoldingSpecs}{"chkOverrideEquipment-$$specs{SignatureIndex}-$qty_index"} ne 'Y' ) ) {
				$$project{FoldingSpecs}{"ddmEquipment-$$specs{SignatureIndex}-$qty_index"} = '';
			} # end if
			$$Imposition{Folds} = [];
		} else {
			if ( $$folding_results{Equipment} ) {

				# Scoring needs this.
				$$project{FoldingSpecs}{"ddmEquipment-$$specs{SignatureIndex}-$qty_index"} = $$folding_results{Equipment}{id};
				
				if ( $$folding_results{Equipment}{id} == $$Press{id} ) {

					my $FI = $$folding_results{FoldedImpositions}[0];
					if ( ! $FI ) {
						$log->error('WTF FI is empty! maybe caching issue? Fold equipment is FI: ' . $FI);
						
					} elsif ( ! $$FI{Equipment} ) {
						$log->error("WTF Equipment in Fold is empty! maybe caching issue? Fold equipment is " . $$FI{Equipment} . ' FI: ' . $FI->to_string() );
					} elsif ( $$FI{Equipment}{id} != $$Press{id} ) {
						$log->error('WTF Equipment in Fold is not the press, but the folding results equipment is. maybe caching issue? Fold equipment is ' . $$FI{Equipment}->strid() . ' FI: ' . $FI->to_string() );
					} else {
            $FI->display( "Runspeed: $$FI{runspeed}") if DEBUG;
            $$folding_results{RunSpeed} = $$FI{runspeed}; # For spine paste
            #$log->debug("Runspeed: $folding_results{RunSpeed}");
            if ($$specs{'RunspeedOverride'.$qty_index} and ($$specs{'RunspeedOverride'.$qty_index} eq 'Y')) {
            } else {
              $$specs{Runspeed} = $price{Runspeed} = $$FI{runspeed} if $$FI{runspeed};
            }
					} # end if
				} # end if
				$$Imposition{Folder} = $$folding_results{Equipment};
#$$Imposition{FoldingCost} = $folding_results{Price};

				$$Imposition{Folds} = $$folding_results{FoldedImpositions};
				foreach my $FI ( @{$$folding_results{FoldedImpositions}} ) {
					my $Fold = $$FI{Fold};
					$price{'Folding Breakdown'} .= sprintf('Folding %d %s (%d out) %d/hr Price: $%.2f on %s<br/>', $FI->quantity(), $Fold->name(), @$FI{'imposition','runspeed','price'}, $Fold->Equipment()->name() );
				} # end foreach
				$price{'Folding Breakdown'} .= sprintf('Folding total: $%.2f<br/>', $$folding_results{Price} ) if @{$$folding_results{FoldedImpositions}} > 1;
				#$price{'Folding Breakdown'} .= $$folding_results{Breakdown};
			} # end if
			$price{ComparisonCost} += $$folding_results{Price};
		} # end if
		if ( DEBUG and tv_interval([$time])*1000 > 10 ) {
			$log->debug("Folding Calculation time: " . ( sprintf('%.4f', tv_interval( [$time])*1000) ) .' usecs' );
			$Imposition->display('Slow Folding');
			$log->debug( $$folding_results{Breakdown} );
		} # end if
		$price{FoldingImposition} = $$folding_results{Imposition};
		$$Imposition{FoldingImposition} = $$folding_results{Imposition};
#$log->debug("FOlding IMPOSITION $folding_results{Imposition}");

		$price{'Comparison Log'} .= 'Folding: ' . $$folding_results{Comparison} . ' total: ' . $price{ComparisonCost} .'<br/>' if COMPARISON_LOG;
		#$price{'Comparison Log'} .= "Folding: " . $$folding_results{Comparison} . ' total: ' . $price{ComparisonCost} .'<br/>' if COMPARISON_LOG;
	} # end if NeedFolding

	if ( $$services{SpinePaste} ) {
		if ( $$Imposition{pages} < $$specs{'txtUnspecifiedPageQuantity'.$qty_index} ) {
			$price{'SpinePaste Breakdown'} .= 'SpinePaste error: Must be 1 signature<br/>';
			$price{ComparisonCost} += 1000000; # Can't SP this on
				$price{'SpinePaste Cost'} = 1000000;
			$price{alert} = 'SpinePaste error: Must be 1 signature';
			return \%price;
		} # end if
	#my $starttime = gettimeofday();

		my $results = openprint::Estimating::SpinePaste::signature_calc( $Project, $service_index, $Imposition, $$project{SpinePasteSpecs}, $qty_index, $folding_results );
		if ( $$results{Status} eq 'uncalculated' ) {
			$price{'SpinePaste Breakdown'} .= "SpinePaste error: $$results{alert}<br/>";
			$price{ComparisonCost} += 1000000; # Can't SP this on
				$price{'SpinePaste Cost'} = 1000000;
		} else {
			$price{'SpinePaste Breakdown'} .= sprintf('SpinePaste MR: %dminutes RS: %d/hr Price: $%.2f<br/>%s<br/>', @$results{'MakeReadyTime','RunSpeed','Price','alert'} );
			$price{'SpinePaste Cost'} = $$results{Price};
			$price{ComparisonCost} += $$results{Price};
	#$log->debug( 'Stitching Calc: ' . sprintf('%.4f', tv_interval( [$starttime])*1000) );
			if ( $$results{Equipment}{id} == $$Press{id} ) {
				$price{Runspeed} = $$specs{Runspeed} = $$results{RunSpeed} if $$results{RunSpeed} and ( $$results{RunSpeed} < $price{Runspeed} );
			} # end if
		} # end if
	} # end if

	my %diecutting_results;
#$log->debug("Need DieCutting $$project{NeedDieCutting}");
	if ( $$project{HasDieCutting} and $$project{NeedDieCutting} ) {
		%diecutting_results = openprint::Estimating::DieCutting::signature_calc( $Project, $service_index, $specs, $$project{DieCuttingSpecs}, $qty_index, $Imposition );
		if ( $diecutting_results{Status} eq 'uncalculated' ) {
			$price{'DieCutting Breakdown'} .= "DieCutting error: $diecutting_results{alert} $diecutting_results{alert} <br/>";
			$price{ComparisonCost} += 1000000; 
		} else {
			$price{'DieCutting Breakdown'} .= sprintf('DieCutting Price: $%.2f on %s<br/>', $diecutting_results{Total}, $diecutting_results{Equipment} ? $diecutting_results{Equipment}->name() : '' );
			$price{ComparisonCost} += $diecutting_results{Total};
		} # end if
	} else {
		$diecutting_results{Overs} = 0;
	} # end if

	my $numbering_results;
	if ( $$project{HasNumbering} ) {
		$numbering_results = openprint::Estimating::Numbering::signature_calc( $Project, $$project{NumberingService}, $$project{NumberingSpecs}, $specs, $qty_index, $Imposition );
#foreach my $k ( keys %scoring_results ) {
#$log->debug("Scoring: $k => $scoring_results{$k}");
#}
		if ( ! $numbering_results ) {
			$price{'Numbering Breakdown'} .= 'Numbering error: no calculation<br/>';
			$price{ComparisonCost} += 1000000; 
		} elsif ( $$numbering_results{Status} eq 'uncalculated' ) {
			$price{'Numbering Breakdown'} .= "Numbering error: $$numbering_results{alert} $$numbering_results{Breakdown}".'<br/>';
			$price{ComparisonCost} += 1000000; 
		} else {
			foreach my $NumberingImposition ( @{$$numbering_results{Impositions}} ) {
			$price{'Numbering Breakdown'} .= sprintf('Numbering Price: %dout $%.2f on %s<br/>', $NumberingImposition->imposition(), $$numbering_results{Total}, $$numbering_results{Equipment} ? $$numbering_results{Equipment}->name() : '' );
			} # end foreach
			$price{ComparisonCost} += $$numbering_results{Total};
		} # end if
	} # end if

	my %scoring_results;
	if ( $$project{HasScoring} and $$project{NeedScoring} ) {
# NeedScoring is set by signature_needs, so why call it again?
	#if ( $$project{HasScoring} and $$project{NeedScoring} and openprint::Estimating::Scoring::signature_needs( $Project, $$project{ScoringSpecs}, $specs, $Paper ) ) {
		%scoring_results = openprint::Estimating::Scoring::signature_calc( $Project, $$project{ScoringSpecs}, $specs, $qty_index, $Imposition, $project );
#foreach my $k ( keys %scoring_results ) {
#$log->debug("Scoring: $k => $scoring_results{$k}");
#}
		if ( $scoring_results{Status} eq 'uncalculated' ) {
			$price{'Scoring Breakdown'} .= "Scoring error: $scoring_results{alert} $scoring_results{Breakdown} <br/>";
			$price{ComparisonCost} += 1000000; 
		} elsif ( $scoring_results{Impositions} ) {
			$price{'Scoring Breakdown'} .= sprintf('Scoring Price: %s on %s $%.2f<br/>', join(',', map { $_->to_string() } @{$scoring_results{Impositions}} ), ($scoring_results{Equipment} ? $scoring_results{Equipment}->name() : ''), $scoring_results{Price} );
			#$log->error("Scoring is calculated $price{'Scoring Breakdown'}");
			$price{ComparisonCost} += $scoring_results{Price};
			if ( $scoring_results{Equipment} and ( $scoring_results{Equipment}{id} == $$Press{id} ) and $scoring_results{Runspeed} ) {
				if ( $scoring_results{Runspeed} =~ /(.*)\%/ ) {
					$price{Runspeed} *= (1+$1/100);
					$$specs{Runspeed} = $price{Runspeed};
				} else {
					$$specs{Runspeed} = $price{Runspeed} = $scoring_results{Runspeed} if $price{Runspeed} > $scoring_results{Runspeed};
				} # end if
			} # end if
			#$scoring_results{Overs} = ceil( $scoring_results{Overs} / ( $$Imposition{imposition}/$scoring_results{Imposition}->imposition() ) ) if $scoring_results{Imposition}->imposition();
		} else {
			$log->error('Scoring is not uncalculated but no Imposition '.$scoring_results{Breakdown});
		} # end if
	#} else {
			#$log->error("Scoring is not being done");
	} # end if

	if ( $$project{HasPerforating} ) {
		my %perforating_results = openprint::Estimating::Perforating::signature_calc( $Project, @$project{'HasPerforating','PerforatingSpecs'}, $service_index, $specs, $qty_index, $Imposition );
		if ( $perforating_results{Status} eq 'uncalculated' ) {
			$price{'Perforating Breakdown'} .= "Perforating error: $perforating_results{alert} $$project{PerforatingSpecs}{alert} " . $perforating_results{Breakdown} . '<br/>';
			$price{ComparisonCost} += 1000000; 
		} else {
			$price{'Perforating Breakdown'} .= sprintf('Perforating Price: %.2f speed: %s on %s<br/>', @perforating_results{'Price','Runspeed'}, ( $perforating_results{Equipment} ? $perforating_results{Equipment}->name() : 'no press' ) );
			$price{ComparisonCost} += $perforating_results{Price};
			if ( $perforating_results{Equipment} and ($perforating_results{Equipment}{id} == $$Press{id}) and $perforating_results{Runspeed} ) {
				if ( $perforating_results{Runspeed} =~ /(.*)\%/ ) {
					$price{Runspeed} *= (1+$1/100);
					$$specs{Runspeed} = $price{Runspeed};
				} else {
					$$specs{Runspeed} = $price{Runspeed} = $perforating_results{Runspeed} if $price{Runspeed} > $perforating_results{Runspeed};
				} # end if
			} # end if
		} # end if
	} # end if

	my %uv_results;
	if ( $$project{HasUVCoating} ) {
		my $starttime = [gettimeofday()] if DEBUG or 1;
		%uv_results = openprint::Estimating::UVCoating::signature_calc( $Project, @$project{'HasUVCoating','UVCoatingSpecs'}, $service_index, $specs, $qty_index, $Imposition, {} );
		$log->debug( 'UVCoating Calc: ' . sprintf('%.4f', tv_interval($starttime)*1000) . ' msecs' ) if DEBUG or 1;
		if ( $uv_results{Status} eq 'uncalculated' ) {
			$price{'UVCoating Breakdown'} .= "UV error: $uv_results{alert} $$project{UVCoatingSpecs}{alert} " . $$project{UVCoatingSpecs}{'hdnBreakdown'.$qty_index} . '<br/>';
			$price{ComparisonCost} += 1000000; 
		} elsif ( $uv_results{Equipment} ) {
			$price{'UVCoating Breakdown'} = sprintf('UVCoating Price: $%.2f on %s<br/>', $uv_results{Total}, $uv_results{Equipment}->name() );
			$price{ComparisonCost} += $uv_results{Total};
		} # end if
	} else {
		$uv_results{Overs} = 0;
	} # end if UVCoating
# Now add in cutting costs to the comparison
# Cutting has to go up here, because it adds overs.ABut we will calculate pre-press stock cutting afterwards
	$price{'Cutting Overs'} = 0;
	if ( $$project{HasCutting} ) {
#my $time = gettimeofday();
		my %cutting_results = openprint::Estimating::Cutting::signature_calc( $Project, $specs, $$project{CuttingSpecs}, $qty_index, $Paper, $Imposition, $$project{FoldingSpecs}, $project );
		
#$log->debug("Elapsed cutting time:" . ( sprintf('%.4f', tv_interval( [$time])*1000) ) .' usecs' );
		if ( $cutting_results{Status} eq 'uncalculated' ) {
			$price{'Cutting Breakdown'} .= "Cutting error: $cutting_results{alert}<br/>";
		} else {
			$price{'Cutting Breakdown'} .= sprintf('Cutting Price: $%.2f<br/>', $cutting_results{Price});
			$price{'Cutting Breakdown'} .= $cutting_results{Breakdown};
			#$price{'Cutting Breakdown'} .= ' on '. $cutting_results{Equipment}->name() if $cutting_results{Equipment};
			$price{'Cutting Breakdown'} .= '<br/>';

#$price{'Cutting Breakdown'} .= $$project{CuttingSpecs}{'hdnBreakdown'.$qty_index}.'<br/>';
			$price{ComparisonCost} += $cutting_results{Price};
			$price{ComparisonCost} += $cutting_results{FoldingPrice};
			$price{'Comparison Log'} .= "Cutting : $cutting_results{Price} PreFolding: $cutting_results{FoldingPrice} total: $price{ComparisonCost}<br/>" if COMPARISON_LOG;
			$price{'Cutting Overs'} = $cutting_results{overs};
		} # end if
	#} else {
		#$log->debug("Has no cutting") if DEBUG;
	} # end if

	# Now we know the bindery overs
	my $bindery_overs;
  if ( $all_overs and ($$all_overs{value} eq 'All') ) {
    $bindery_overs = ceil($$folding_results{MakeReadyOvers}+$$folding_results{RunOvers}+$scoring_results{Overs}+$uv_results{Overs}+$diecutting_results{Overs}+$price{'Cutting Overs'});
  } else {
    $bindery_overs = ceil(sets::max( $$folding_results{MakeReadyOvers} + $$folding_results{RunOvers}, $scoring_results{Overs}, $uv_results{Overs}, $diecutting_results{Overs}, $price{'Cutting Overs'} ));
  }
	$bindery_overs = 0 if ! defined $bindery_overs;
	$bindery_overs *= $Paper->parts() if $Paper->parts();
	$overs = $bindery_overs if $bindery_overs > $overs;
	$overs = $min_overs if $min_overs and ( $overs < $min_overs );

	my $gross_sheets = $net_sheets + $overs;
	$impressions = $gross_sheets;
#$log->debug("Imperssions : gross sheets: $gross_sheets") if DEBUG;
	$impressions *= 2 if $$Imposition{sides} == 2 and $is_wt;
# or ( $$Imposition{runstyle} eq 'Sheet Work' ) );
#$log->debug("Imperssions $impressions : gross sheets: $gross_sheets");

	my $min_impression_quantity = $Press->specification('Minimum Impression Quantity', $$Paper{calliper} );
	if ( $min_impression_quantity and ( $min_impression_quantity > $impressions ) ) {
		$price{alert} = "Next cuz of minimum impression quantity $min_impression_quantity: $impressions";
		return \%price;
	} # end if

	# We copy these so that we can add to them while considering side two, and for future sigs?
	my $plate_count = 0;
	my ($plate_type,$plate_size,$max_impressions) = (
			$Press->specification('Plate Type'),
			$Press->specification('Plate Size'),
			$Press->specification('Maximum Plate Impressions'),
			);
	if ( $max_impressions ) { $max_impressions = int($max_impressions); } else { $max_impressions = 250000; }
	my $plate_runs = ceil($impressions/$max_impressions);

	my $plate_id = ( $plate_size and $plate_size ) ? $plate_size . '-' . $plate_type . 'Plate' : '';
	my %plate_setup = (
			'Plate Type', ($plate_type?$plate_type:''),
			'Plate ID', $plate_id, 
			'Plate Runs', $plate_runs ); # if $plate_size and $plate_type;
	
	my @colours_no_coatings = filter_coatings_from_colours(\@colours);

if ( 1 ) {
	$plate_count += scalar @colours_no_coatings;
} else {
	foreach my $Colour ( @colours_no_coatings ) {
		my $real_colour = $$Colour{name};
		my $key = join('-',$real_colour,$$Press{strid},$qty_index);
		$plate_count += 1;
	} # end foreach Colour
}
	
	$plate_setup{'Setup Plate Count'} = $plate_count;
	$plate_setup{'Plate Changes'} = $plate_changes;

	$plate_count *= $plate_runs;
	$plate_count += $plate_changes;
	my $blanks_needed = 0;
	my $require_blank_plates = $Press->specification('Require Blank Plates');
	if ( defined $require_blank_plates ) {
		my $press_colours = $Press->specification('Number of Colours');
		if ( $require_blank_plates eq 'Y' ) {
			if ( $$Imposition{runstyle} eq 'Web' ) {
				$blanks_needed = ( $press_colours - @{$$project{side_two_colours}} ) + ( $press_colours - @{$$project{side_two_colours}} );
			} else {
				$blanks_needed = ($press_colours - @colours);
			} # end if
		} elsif ( @{$$project{non_process_colours}} and ( $require_blank_plates eq 'When Non-Process' ) ) {
			$blanks_needed = ($press_colours - @colours);
		} # end if
		$blanks_needed -= $$PlateCounts{'Blank'.$plate_id} if $$PlateCounts{'Blank'.$plate_id};
		$blanks_needed = 0 if $blanks_needed < 0;
		$plate_setup{'Blank Plates'} = $blanks_needed;
	} else {
		$plate_setup{'Blank Plates'} = 0;
	} # end if defined require_blank_plates
	$plate_setup{'Plate Count'} = $plate_count;
#$Imposition->display("Plate Count $plate_count");


	$price{'Plate Costs'} = \%plate_setup;
	$price{rdbPlates} = $plate_setup{'Plate Type'};
	$price{'Plate Total'} = 0;
	$price{'Plate Runs'} = $plate_setup{'Plate Runs'};

	my $press_setup = 0;

	if ( $GripperMakeReadyService ) {
		my $charge = 1;
		foreach my $other_I ( @{$other_impositions} ) {
      $openprint::log->debug("$other_I");
			last if $other_I == $Imposition;
			my $P = $$other_I{Paper};
			if ( $$P{calliper} == $$Paper{calliper} and $$other_I{Press}{id} == $$Press{id} ) {
				$charge = 0;
				last;
			} # end if
		} # end foreach other_I
		if ( $charge ) {	
			$price{GripperSetup} = $GripperMakeReadyService->get_Price($$Paper{calliper}, $Press);
			$press_setup += $price{GripperSetup}{Price};
		} # end if
	}

	if ( $$Imposition{runstyle} eq 'Sheet Work' ) {
		if ( @{$$project{side_one_colours}} and @{$$project{side_two_colours}} ) {
			my $press_setup_front = press_setup_cost( $project, $plate_changes, $plate_setup{'Plate Runs'}, $$project{side_one_colours}, $$Paper{calliper}, $qty_index, $Imposition, $other_impositions );
			$press_setup += $press_setup_front->{Total};
			$price{'Setup Breakdown'} .= sprintf('%d units * $%.2f%s = $%.2f<br/>', @$press_setup_front{'Unit Count','Price','units','Total'} );
			$price{'Plate Total'} += $$press_setup_front{'Plate Total'};
			@price{'Plate Setup Price','Plate Setup Count','Plate Setup Units'} = @$press_setup_front{'Plate Price','Plate Count','Plate Units'};
			if ( ( !$$press_setup_front{units} ) or ( $$press_setup_front{units} ne 'total' and $$press_setup_front{units} ne 'per job' ) ) {
				my $back_press_setup = press_setup_cost( $project, 0, $plate_setup{'Plate Runs'}, $$project{side_two_colours}, $$Paper{calliper}, $qty_index, $Imposition, $other_impositions );
				$press_setup += $$back_press_setup{Total};
				$price{'Setup Breakdown'} .= sprintf('%d units * $%.2f%s = $%.2f<br/>', @$back_press_setup{'Unit Count','Price','units','Total'} );
				$price{'Plate Total'} += $$back_press_setup{'Plate Total'};
				$price{'Plate Setup Count'} += $$back_press_setup{'Plate Count'};
			} # end if
		} elsif ( @{$$project{side_one_colours}} ) {
			my $press_setup_front = press_setup_cost( $project, $plate_changes, $plate_setup{'Plate Runs'}, $$project{side_one_colours}, $$Paper{calliper}, $qty_index, $Imposition, $other_impositions );
			$press_setup += $$press_setup_front{Total};
			$price{'Setup Breakdown'} .= sprintf('%d units * $%.2f%s = $%.2f<br/>', @$press_setup_front{'Unit Count','Price','units','Total'} );
			$price{'Plate Total'} += $$press_setup_front{'Plate Total'};
			@price{'Plate Setup Price','Plate Setup Count','Plate Setup Units'} = @$press_setup_front{'Plate Price','Plate Count','Plate Units'};
		} elsif ( @{$$project{side_two_colours}} ) {
			my $press_setup_back = press_setup_cost( $project, $plate_changes, $plate_setup{'Plate Runs'}, $$project{side_two_colours}, $$Paper{calliper}, $qty_index, $Imposition, $other_impositions );
			$press_setup += $$press_setup_back{Total};
			$price{'Setup Breakdown'} .= sprintf('%d units * $%.2f%s = $%.2f<br/>', @$press_setup_back{'Unit Count','Price','units','Total'} );
			$price{'Plate Total'} += $$press_setup_back{'Plate Total'};
			@price{'Plate Setup Price','Plate Setup Count','Plate Setup Units'} = @$press_setup_back{'Plate Price','Plate Count','Plate Units'};
		} # end if
	} elsif ( $$Imposition{runstyle} eq 'Web' or $$Imposition{runstyle} eq 'Perfecting' ) {
		my $press_setup_cost = press_setup_cost( $project, $plate_changes, $plate_setup{'Plate Runs'}, $$project{combined_colours}, $$Paper{calliper}, $qty_index, $Imposition, $other_impositions );
		$press_setup += $$press_setup_cost{Total};
		$price{'Setup Breakdown'} .= sprintf('%d units * $%.2f%s = $%.2f<br/>', @$press_setup_cost{'Unit Count','Price','units','Total'} );
		@price{'Plate Setup Price','Plate Setup Count','Plate Setup Units'} = @$press_setup_cost{'Plate Price','Plate Count','Plate Units'};
		$price{'Plate Total'} += $$press_setup_cost{'Plate Total'};
	} else {
		my $press_setup_cost = press_setup_cost( $project, $plate_changes, $plate_setup{'Plate Runs'}, $$project{filtered_colours}, $$Paper{calliper}, $qty_index, $Imposition, $other_impositions );
		$press_setup += $$press_setup_cost{Total};
		$price{'Setup Breakdown'} .= sprintf('%d units * $%.2f%s = $%.2f<br/>', @$press_setup_cost{'Unit Count','Price','units','Total'} );
		$price{'Plate Total'} += $$press_setup_cost{'Plate Total'};
		@price{'Plate Setup Price','Plate Setup Count','Plate Setup Units'} = @$press_setup_cost{'Plate Price','Plate Count','Plate Units'};
	} # end if
	my $setup_cost = $press_setup + $price{'WorkTurn Dry Charge'} + $price{'Plate Total'} + $price{'Version Charge'};


# Recalculate Overs, etc using Plate Count now
	if ( $$project{print_sides} == 1 ) {
		$setup_rate = $Press->specification( 'MakeReady Overs Rate One Side', $plate_setup{'Plate Count'} );
		$setup_rate = $Press->specification( 'MakeReady Overs Rate '.$Paper->material(), $plate_setup{'Plate Count'} ) if ! $setup_rate;
	} else {
		$setup_rate = $Press->specification( 'MakeReady Overs Rate '.$Paper->material(), $plate_setup{'Plate Count'} );
		$setup_rate = $Press->specification( 'MakeReady Overs Rate '.$$Imposition{runstyle}, $plate_setup{'Plate Count'} ) if ! $setup_rate;
	} # end if
	$setup_rate = $Press->specification( 'MakeReady Overs Rate', $plate_setup{'Plate Count'} ) if ! $setup_rate;
	$setup_rate = 0 if ! defined $setup_rate;

	my $initial_setup_rate = $setup_rate;
	$initial_setup_rate *= ( 1 + ( $roll2sheet_setup_overs_rate / 100 ) ) if $roll2sheet_setup_overs_rate;

	# Shouldn't need ceil.	Rate is an integer
  my $initial_setup_overs;
  if ($initial_setup_rate) {
    $initial_setup_overs = ceil( $plate_setup{'Setup Plate Count'} * $initial_setup_rate );
    #$openprint::log->debug("Initial overs from rate $initial_setup_overs $initial_setup_rate");
  } else {
    $initial_setup_overs = $Press->specification( 'MakeReady Overs ' . $Paper->material(), $plate_setup{'Plate Count'} );
    $initial_setup_overs = $Press->specification( 'MakeReady Overs ' . $$Imposition{runstyle}, $plate_setup{'Plate Count'} ) if ! $initial_setup_overs;
    $initial_setup_overs = $Press->specification( 'MakeReady Overs', $plate_setup{'Plate Count'} ) if ! $initial_setup_overs;
    #$openprint::log->debug("Initial overs from flat $initial_setup_overs $initial_setup_rate");
	} # end if

	my $total_overs = 0;

	if ( $all_overs and ($$all_overs{value} eq 'All') ) {
		$total_overs += ceil( $run_overs + $setup_overs );
	} else {
		$total_overs += ceil( ( $setup_overs > $run_overs ) ? $setup_overs : $run_overs );
	} # end if
	$total_overs += $additional_overs;
	$total_overs += ( $bindery_overs - $total_overs ) if $bindery_overs > $total_overs;

	$min_overs = $Press->specification( 'Overs Minimum ' . $Paper->material(), $plate_setup{'Plate Count'} );
#$log->debug("Overs min " . $Paper->material() . " $min_overs");
	$min_overs = $Press->specification( 'Overs Minimum', $plate_setup{'Plate Count'} ) if ! $min_overs;
	$min_overs = 0 if ! defined $min_overs;
	$total_overs = $min_overs if $total_overs < $min_overs;

	$gross_sheets = $net_sheets + $total_overs;
	$impressions = $gross_sheets;
	my $colour_impressions = $gross_sheets;
	if ( $is_wt ) {
# Same sheets, go through twice, colours merged.
		$colour_impressions *= 2;
		$impressions *= 2;
	#} elsif ( $$Imposition{sides} == 2 and $$Imposition{runstyle} eq 'Sheet Work' ) {
		#$impressions *= 2;
	}
	my $additional_setup_count = $plate_setup{'Plate Count'} - $plate_setup{'Setup Plate Count'};
	my $additional_setup_overs = 0;
	my $additional_setup_rate = 0;

	if ( $additional_setup_count ) {
		$additional_setup_rate = $Press->specification('MakeReady Overs Additional Setup Rate');
		$additional_setup_rate = $setup_rate if ! $additional_setup_rate;
		$additional_setup_rate *= ( 1 + ( $roll2sheet_setup_overs_rate / 100 ) ) if $roll2sheet_setup_overs_rate;
		$additional_setup_overs = ceil( $additional_setup_rate * $additional_setup_count );
	}

	if ( $$specs{'OverrideSetup'.$qty_index} and ( $$specs{'OverrideSetup'.$qty_index} eq 'Y' ) ) {
		$setup_overs = $$specs{'OverSetup'.$qty_index};
	} else {
		if ( $setup_rate ) {
			$setup_overs = $initial_setup_overs;

#+ $additional_setup_overs;
		} else {
			$setup_overs = $Press->specification( 'MakeReady Overs ' . $Paper->material(), $plate_setup{'Plate Count'} );
			$setup_overs = $Press->specification( 'MakeReady Overs ' . $$Imposition{runstyle}, $plate_setup{'Plate Count'} ) if ! $setup_overs;
			$setup_overs = $Press->specification( 'MakeReady Overs', $plate_setup{'Plate Count'} ) if ! $setup_overs;
		} # end if
		$setup_overs += $fm_overs + $additional_setup_overs;
	} # end if

	$total_overs = 0;

	if ( $_ = $Press->Specification('Overs') and $$_{value} eq 'All' ) {
		$total_overs += ceil( $run_overs + $setup_overs );
	} else {
		$total_overs += ceil( ( $setup_overs > $run_overs ) ? $setup_overs : $run_overs );
	} # end if
	$total_overs += $additional_overs;
	$total_overs += $bindery_overs;
  #$total_overs += ( $bindery_overs - $total_overs ) if $bindery_overs > $total_overs;

	$min_overs = $Press->specification( 'Overs Minimum ' . $Paper->material(), $plate_setup{'Plate Count'} );
#$log->debug("Overs min " . $Paper->material() . " $min_overs");
	$min_overs = $Press->specification( 'Overs Minimum', $plate_setup{'Plate Count'} ) if ! $min_overs;
	$min_overs = 0 if ! defined $min_overs;
	$total_overs = $min_overs if $total_overs < $min_overs;

	$gross_sheets = $net_sheets + $total_overs;
	$impressions = $gross_sheets;
	$colour_impressions = $gross_sheets;
	if ( $is_wt ) {
# Same sheets, go through twice, colours merged.
		$colour_impressions *= 2;
		$impressions *= 2;
	#} elsif ( $$Imposition{sides} == 2 and $$Imposition{runstyle} eq 'Sheet Work' ) {
		#$impressions *= 2;
	}

	if ( $max_impression_quantity and ($max_impression_quantity < $impressions ) ) {
		$log->debug("Next cuz of maximum impression quantity $max_impression_quantity : $impressions" ) if DEBUG;
		return \%price;
	}
	my $weight = $gross_sheets * $Paper->sheet_weight();
	if ( $Paper->type() eq 'Roll' and my $Waste = $Press->Specification('Waste Stock') ) {
		if ( $$Waste{units} eq 'Inches' ) {
			$weight += $$Waste{value} * $$Paper{width} * $Paper->wpsi();
		} # end if
	} # end if
	$weight = Math::Round::nearest( .01, $weight );

	my %sheet_qty = (
			Impressions				=>	$impressions, 
			'Gross Sheet Count'			=>	$gross_sheets, 
			'Net Sheet Count'			=>	$net_sheets,
			'Initial Setup Count'		=> $plate_setup{'Setup Plate Count'},
			'Initial Setup Rate'		=> $initial_setup_rate,
			'Initial Setup Overs'		=> ( $$specs{'OverrideSetup'.$qty_index} and ( $$specs{'OverrideSetup'.$qty_index} eq 'Y' ) ) ? $$specs{'OverSetup'.$qty_index} : $initial_setup_overs,
			'Additional Setup Count'	=> $additional_setup_count,
			'Additional Setup Rate'		=> $additional_setup_rate,
			'Additional Setup Overs'	=> $additional_setup_overs,
'Additional Plate Overs Minimum'	=> $price{'Additional Plate Overs Minimum'},
			'Run Overs'					=>	$price{'Run Overs'},
			'Additional Plate Overs'	=>	$additional_overs,
			'Additional Plate Overs Rate'	=>	$additional_overs_rate,
			'Total Overs'				=>	$total_overs,
			Weight					=>	$weight,
			'FM Overs'					=>	$fm_overs,
			FoldingMakeReadyOvers		=>	( $$folding_results{MakeReadyOvers} ? $$folding_results{MakeReadyOvers} : 0 ),
			FoldingRunOvers			=>	( $$folding_results{RunOvers} ? $$folding_results{RunOvers} : 0 ),
			ScoringOvers				=>	$scoring_results{Overs},
			DieCuttingOvers			=>	$diecutting_results{Overs},
			UVOvers					=>	$uv_results{Overs},
			BinderyOvers				=>	$bindery_overs,
			CuttingOvers				=>	$price{'Cutting Overs'},
			'Minimum Overs'				=>	$min_overs,
			'Plate Changes'				=>	$plate_changes,
			);
	$price{'Stock Quantity'} = \%sheet_qty;
  $$Imposition{gross_sheets} = $price{'Gross Sheet Count'} = $sheet_qty{'Gross Sheet Count'};
	$$Imposition{net_sheets} = $price{'Net Sheet Count'} = $sheet_qty{'Net Sheet Count'};
	$price{'Stock Weight'} = $sheet_qty{Weight};
	$price{'Stock Qty'} = $$Paper{type} eq 'Sheet' ? $sheet_qty{'Gross Sheet Count'} : $sheet_qty{Weight};

	$$specs{"txtPressSheetQty$qty_index"} = $gross_sheets;

  if ( $$specs{rdbSuppliedStock} eq 'Y' ) {
    if ( my $SuppliedService = $Services{'Supplied'.$$Paper{type}} ) {
      if ( my %SuppliedPaperPrice = $SuppliedService->get_price( undef, undef ) ) {
        #$openprint::log->debug("Supplied Service units $SuppliedPaperPrice{units} : " . join(',', map { $_.'=>'.$SuppliedPaperPrice{$_} } keys %SuppliedPaperPrice));
        if ( $SuppliedPaperPrice{range_units} and ($SuppliedPaperPrice{range_units} eq 'per 100lbs') ) {
          %SuppliedPaperPrice = $SuppliedService->get_price($price{'Stock Weight'}/100, undef);
          #$openprint::log->debug("Supplied Service units for " . ($$price{'Stock Weight'}/100)." $SuppliedPaperPrice{units} : " . join(',', map { $_.'=>'.$SuppliedPaperPrice{$_} } keys %SuppliedPaperPrice));
        }
        if ( $SuppliedPaperPrice{units} eq 'per 100lbs' ) {
          $SuppliedPaperPrice{Total} = $SuppliedPaperPrice{Price} * $price{'Stock Weight'} / 100;
        } elsif ( $SuppliedPaperPrice{units} eq 'per sheet' ) {
          $SuppliedPaperPrice{Total} = $SuppliedPaperPrice{Price} * $price{'Gross Sheet Count'};
        } elsif ( $SuppliedPaperPrice{units} eq 'per m' ) {
          $SuppliedPaperPrice{Total} = $SuppliedPaperPrice{Price} * $price{'Gross Sheet Count'}/1000;
        } elsif ( $SuppliedPaperPrice{units} eq 'total' ) {
          $SuppliedPaperPrice{Total} = $SuppliedPaperPrice{Price};
        } # end if
        $price{SuppliedPaperPrice} = \%SuppliedPaperPrice;
        $price{ComparisonCost} += $SuppliedPaperPrice{Total};
        $price{'Comparison Log'} .= 'SuppliedPaper: +'.$SuppliedPaperPrice{Total} . '<br/>' if COMPARISON_LOG;
        $price{'Total Cost'} += $SuppliedPaperPrice{Total};
        #@$price{'Stock Total'} = $SuppliedPaperPrice{Total};
      } # end if
    } # end if
  }
	# Remarked it out because colours is the mix of the colours... so sheet work, it will appear in there twice...w&t, just once
	#$impressions /= $$project{print_sides} if (sets::isin($$Imposition{runstyle},['Sheet Work','Work & Turn','Work & Tumble'] ));
#$log->debug("Colours: @colours");
	$price{'Ink Price'} = 0;

	#$colour_impressions = POSIX::ceil( $colour_impressions/2 ) if $$Imposition{sides} == 2;
#$log->debug("Impressions: $colour_impressions sides: $$Imposition{sides}");

 $price{'Ink breakdown'} .= sprintf( 'Image area: %s x %s x %d spreads x %dout x %s impressions = %s square inches<br/>', 
		 @$Imposition{'object_width','object_height', 'spreads','imposition'}, 
		 $colour_impressions, 
		 $Imposition->object_area() * $colour_impressions  );

	foreach my $Colour ( @colours_no_coatings ) {
		
		my $real_colour = $$Colour{name};
$log->debug("Colour: $real_colour impressions $colour_impressions $$Imposition{runstyle} Coverage $$Colour{coverage}%") if DEBUG_INKS;
		my $colour;

		$price{'Ink breakdown'} .= $real_colour;
		my $grade = $Paper->grade();
		$grade = 4 if ! $grade;
		my %ink_price;

		if ( $real_colour =~ /Varnish/ ) {
			$colour = $real_colour;
			if ( $$Imposition{runstyle} eq 'Web' ) {
				$colour =~ s/ (Spot|Overall)//g;
			} elsif ( $is_wt ) {
				if ( ($real_colour =~ /Overall/) and ! (
							sets::isin($real_colour, $$project{side_one_colour_names})
							and
							sets::isin($real_colour, $$project{side_two_colour_names} )
							) ) {
					$real_colour =~ s/Overall/Spot/;
				} # end if
			} # end if

$log->debug("Varnish $real_colour") if DEBUG_INKS;
# MPI Brendan says Varnish uses a plate, not a blanket
			if ( 0 and ($real_colour =~ /Spot/) ) {
				# Add Blanket Cut
				my $BlanketCutService = $Services{$real_colour.' BlanketCut'};
				$BlanketCutService = $Services{$real_colour} if ! $BlanketCutService;
				if ( $BlanketCutService ) {
					my %BlanketCut = $BlanketCutService->get_price( undef, $Press );
					%BlanketCut = openprint::service::get_price_object( 'BlanketCut', undef, $Press ) if ! %BlanketCut;
					if ( %BlanketCut ) {
						$price{'Ink breakdown'} .= ' Blanket: $'. $BlanketCut{Price}.' ';
						$ink_price{BlanketCut} = \%BlanketCut;
						$ink_price{Total} = $BlanketCut{Price};
					} # end if
				} # end if
			} # end if
		} elsif ( $real_colour =~ /^(\w+) Spot Colour$/ ) {
			$colour = $1;
      $log->debug("Have $colour spot colour");
		} elsif ( $real_colour =~ /PMS/i ) {
			$colour = $real_colour;
			#$colour =~ s/\D//g; # Just the PMS #
		} else { 
			$colour = $real_colour;
		} # end if
		my $key = join('-',$colour,$$Press{strid},$qty_index);

# Each Ink/Coating has MakeReady, Mix, Material, Service
		if ( ! ( $real_colour =~ /Varnish/ and $$washed_colours{$key} ) ) {
			my %InkMakeReady = openprint::service::get_price_object( $real_colour.' MakeReady', undef, $Press );
			if ( %InkMakeReady ) {
				$price{'Ink breakdown'} .= sprintf(' MR: %.2f', $InkMakeReady{Price} );
				$ink_price{MakeReady} = \%InkMakeReady;
				$ink_price{Total} += $InkMakeReady{Price};
			} # end if
		} # end if

		my $Ink;

		foreach my $C ( @{$special_colours{$colour}} ) {
			if ( ( ! ( $$C{grades} and scalar @{$$C{grades}} ) ) or sets::isin($grade, $C->grades()) ) {
        $log->debug("Found ink $$C{name}") if DEBUG_INKS;
				$Ink = $C;
				last;
			} # end if
		} # end foreach

		if ( !$Ink ) {
			$log->error("Didnt find ink real ($real_colour) ($colour) ($grade) in colours hash, must be a grade problem");
			foreach my $k ( keys %special_colours ) {
			foreach my $C ( @{$special_colours{$k}} ) {
				$log->error($k . ' => ' . $C->to_string() );
			} # end foreach C
			} # end foreach C
			next;
		} elsif ( DEBUG_INKS ) {
			$log->debug('Got INK: '.$Ink->to_string());
		} # end if

		my $InkService = ($Ink->Service() and $Ink->Service()->id()) ? $Ink->Service() : $Services{$real_colour};
		my %InkService;
		if ( $InkService and %InkService = $InkService->get_price( $colour_impressions, $Press ) ) {
			if ( $InkService{units} eq 'per m' ) {
				$InkService{Total} = $InkService{Price} * $colour_impressions/1000;
			} else {
				$price{'Ink breakdown'} .= 'unknown units for mix service for '.$real_colour.' ' . $InkService{units} .'<br/>';
				$log->error('unknown units for ' . $real_colour );
			} # end if
			$ink_price{ServicePrice} = \%InkService;
			$ink_price{Total} += $InkService{Total};
			$price{'Ink breakdown'} .= sprintf(' Run: $%1$.2f%2$s * %4$d/1000 = $%3$.2f = $%5$.2f', @InkService{'Price','units','Total'}, $colour_impressions, $ink_price{Total} );
    } else {
      $log->debug("No ink service found for $$Ink{name}") if DEBUG_INKS;
		} # end if

# Washed_colours contains each colour used in the other signatures
		if ( $$Ink{washups} and (
				( ! $$washed_colours{$key} ) or 
				( 
				 ( $$Imposition{runstyle} eq 'Perfecting' ) and 
				 ( $$washed_colours{$key} < 2 ) and
				 sets::isin($real_colour, $$project{side_one_colour_names}) and 
				 sets::isin($real_colour, $$project{side_two_colour_names}) 
				)
			) ) {
			
			if ( $$Imposition{runstyle} eq 'Web' and $$washed_colours{$key} ) {
				# On web, top and bottom are considered 1 wash, so will only wash a colour once.
			} else {
				$price{'Press Washes'} += $$Ink{washups};
				$$washed_colours{$key} += $$Ink{washups};
			}
			$log->debug("Press Washes: $key $price{'Press Washes'} colour: $real_colour Washups: " . $$Ink{washups}) if DEBUG_INKS;
		} # end if
#
#$log->debug("Special Colour: $real_colour $$inkCoverage{$real_colour}") if DEBUG_INKS;

		my %mix_price;
		if ( $$Ink{mix_service_id} ) {
			if ( $$Ink{mix} and ! $$mixed_colours{$real_colour} ) {
$log->debug("$real_colour needs mixing") if DEBUG_INKS;
				%mix_price = $Ink->Mix_Service()->get_price(undef,$Press);
$log->debug("Mix Price for $real_colour $mix_price{Price}") if DEBUG_INKS;
				$price{'Ink breakdown'} .= ' Mix: $' . 1*$mix_price{Price};
				$ink_price{Mix} = \%mix_price;
				$ink_price{Total} += $mix_price{Price};
				$$mixed_colours{$real_colour} = 1;
			} else {
$log->debug("Was mixed") if DEBUG_INKS;
			} # end if
		} # end if mix_service_id

		my $InkMaterial;
		if ( $$Ink{material_id} ) {
			$InkMaterial = $Ink->Material();
			my %material_price = $InkMaterial->get_price( undef, $Press );
			$ink_price{Material} = \%material_price;
			my $coverage = $$Colour{coverage}/100;

			if ( %material_price ) {
				# object_area  includes imposition and spreads
				my $area = $Imposition->object_area() * $colour_impressions * $coverage;
				if ( $qty < $$Imposition{imposition} ) {
# * $colour_impressions ) {
					$area *= $qty / $$Imposition{imposition};
				}
$log->debug("Area $area = $$Imposition{object_area} * Impressions($colour_impressions) * Coverage($coverage) ") if DEBUG_INKS;

			# Not exactly sure about this, but keeping it to make topknotch keep the same prices.	Will have to do more testing and thinking
			# Thoughts:	if the colour is on both sides, then the coverage is increased, so the area needs to be descreased.
			#$area /= 2 if $Imposition->runstyle() eq 'Sheet Work' and $$specs{sides_the_same} ne 'Y';
			# if it's sheetwork, then the colours array has two copies of process colours, but when calculating ink coverages, we have been adding up the coverages to get mrre... .	so we need to decrease the area.	
			# TOpknotch doesn't charge for ink, so it's safe to remove
	#$log->debug("Area: $area Impressions: $impressions " . $Imposition->object_area() );

				if ( $material_price{units} eq 'per cartridge' ) {
					my $Coverage = $Ink->Coverage($Press, $grade);
					my $qty = Math::Round::nearest( 0.0001, $area/$$Coverage{value} ) if $Coverage and $$Coverage{value};
					%material_price = $InkMaterial->get_price( $qty, $Press );
					$ink_price{Material} = \%material_price;
					$material_price{Total} += Math::Round::nearest( 0.01, $material_price{Price} * $qty );
					$ink_price{Total} += $material_price{Total};
					$price{'Ink breakdown'} .= sprintf(' mileage: %d sq in per cartridge, %.2fsq in means %.4f * $%s%s=$%.2f = $%.2f', $$Coverage{value}, $area, $qty, @material_price{'Price','units','Total'}, $ink_price{Total});
        } elsif ( $material_price{units} eq 'per can' ) {
					my $Coverage = $Ink->Coverage($Press, $grade);
					my $qty = POSIX::ceil($area/$$Coverage{value}) if $Coverage and $$Coverage{value};
					%material_price = $InkMaterial->get_price( $qty, $Press );
					$ink_price{Material} = \%material_price;
					$material_price{Total} += Math::Round::nearest( 0.01, $material_price{Price} * $qty );
					$ink_price{Total} += $material_price{Total};
					$price{'Ink breakdown'} .= sprintf(' %d%% = %d square inches, mileage: %dsquare inches/can = %d cans * $%s%s=$%.2f = $%.2f',
            $coverage*100, $area, $$Coverage{value}, $qty, @material_price{'Price','units','Total'}, $ink_price{Total});
				} elsif ( $material_price{units} eq 'per kg' ) {
					my $Coverage = $Ink->Coverage($Press, $grade);
					if ( ( ! $Coverage ) or ! $$Coverage{value} ) {
						$log->debug("No Coverage for grade $grade Press: $$Press{strid}");
					}
					my $qty = Math::Round::nearest( 0.01, $area/$$Coverage{value} ) if $Coverage and $$Coverage{value};
					%material_price = $InkMaterial->get_price( $qty, $Press );
					$material_price{Total} += Math::Round::nearest( 0.01, $material_price{Price} * $qty );
					$ink_price{Material} = \%material_price;
					$ink_price{Total} += $material_price{Total};
					$price{'Ink breakdown'} .= sprintf(' %d%% = %d square inches, mileage: %dsquare inches/kg = %.2fkg * $%s%s=$%.2f = $%.2f', $coverage*100, $area, $$Coverage{value}, $qty, @material_price{'Price','units','Total'}, $ink_price{Total});
				} elsif ( $material_price{units} eq 'per square foot' ) {
					$area /= 144;
					$material_price{Total} += Math::Round::nearest( 0.01, $material_price{Price} * $area );
					$ink_price{Total} += $material_price{Total};
					$price{'Ink breakdown'} .= sprintf(' Grade: %d, %.2f sq feet * $%s%s = $%.2f', $grade, $area, @material_price{'Price','units','Total'} );
				} elsif ( $material_price{units} eq 'per unit' ) {
					my $sheets_per_ink_unit = 750000;
					my $p = Math::Round::nearest( 0.01, $material_price{Price} * ($area/$sheets_per_ink_unit) / $$project{print_sides} );
					$ink_price{Total} += $p;
					$price{'Ink breakdown'} .= sprintf(' %d%% %s sq inches * $%s%s / %d sheets per unit = $%.2f = $%.2f', $coverage*100, Number::Format::format_number($area), @material_price{'Price','units'}, $sheets_per_ink_unit, $p, $ink_price{Total} );
				} elsif ( $material_price{units} eq 'per square inch' ) {
					my $p = Math::Round::nearest( 0.01, $material_price{Price} * $area );
					$ink_price{Total} += $p;
					$price{'Ink breakdown'} .= sprintf(' Grade: %d, %d sq inches * $%s%s = $%.2f = $%.2f', $grade, $area, @material_price{'Price','units'}, $p, $ink_price{Total} );
				} elsif ( $material_price{units} eq 'per m' ) {
					my $p = Math::Round::nearest( 0.01, $material_price{Price} * $impressions/1000 );
					$ink_price{Total} += $p;
					$price{'Ink breakdown'} .= sprintf( ' %d * $%.2f%s = %.2f', $colour_impressions, @material_price{'Price','units'}, $p );
				} elsif ( $material_price{units} eq 'per impression' ) {
					my $p = Math::Round::nearest( 0.01, $material_price{Price} * $colour_impressions );
					$ink_price{Total} += $p;
					$price{'Ink breakdown'} .= ' ' . $colour_impressions . " * $material_price{Price}$material_price{units} = " . $p;
				} else {
					$log->error("Unknown units for $colour: $material_price{units}" . $$Press{strid} );
          $price{'Ink breakdown'} .= "<div class=\"warning\"> Unknown units for material $colour: $material_price{units} $$Press{strid}</div>";
				} # end if
			} # end if material_price
    } else {
      $log->debug("No material id for $colour ".$Ink->to_string());
		} # end if material_id

		if ( ! %ink_price ) {
			$price{'Ink breakdown'} .= ' no price<br/>';
			next;
		}	
		$price{'Ink Price'} += $ink_price{Total} if $ink_price{Total};
		$price{'Ink breakdown'} .= '<br/>';
	} # end foreach colour/coating

	if ( $_ = $Press->specification('Charge for setup overs') and $$_{value} eq 'N' ) {
		$impressions -= $setup_overs;
	} # end if

	my $run_prices;
	if ( $is_wt ) {
		#my @c = filter_coatings_from_colours( \@colours );
		$run_prices = get_run_prices( $impressions, scalar(@{$$project{filtered_colours}}), 0, $Imposition, $Press, \%price ); 
	} else {
		$run_prices = get_run_prices( $impressions, scalar @{$$project{side_one_colours}}, scalar @{$$project{side_two_colours}}, $Imposition, $Press, \%price );
	} # end if
	#$price{Runspeed} = $$specs{Runspeed} = $$run_price{run_speed};

	my $PreviousForms = $$specs{'PreviousForms'.$qty_index} ? $$specs{'PreviousForms'.$qty_index}+1 : 1;

	if ( $plate_setup{'Plate Type'} ne 'Conventional' ) {
		my $ImpositionPrice = openprint::Estimating::Imposition::signature_calc( $Project, $Imposition, $PreviousForms, $qty_index );
		$price{'Imposition MakeReady'} = $$ImpositionPrice{MakeReady}{Price} // 0;
		$price{'Imposition Total'} = $$ImpositionPrice{Total} // 0;
		$price{'Imposition Price'} = $ImpositionPrice;
		 if ( ! $ImpositionServiceType ) {
			$setup_cost += $price{'Imposition Total'};
		} else {
			$price{ComparisonCost} += $price{'Imposition Total'};
		} # end if
	} # end if Plate Type Conventional

	my $RunStyleService = $Services{$$Imposition{runstyle}.'Setup'};

	if ( $RunStyleService and my %RunStylePrice = $RunStyleService->get_price(undef, $Press) ) {
		$price{'Runstyle Charge'} = \%RunStylePrice;
		$setup_cost += $RunStylePrice{Price};
	} # end if


	my $run_cost = List::Util::sum(map { $$_{Total} } @{$run_prices});
	$price{'Run Prices'} = $run_prices;

	if ( $$Imposition{sides} == 2 and $$Imposition{runstyle} eq 'Sheet Work' ) {
		$impressions *= 2;
	}
	$price{Impressions} = $impressions;
	$$specs{'hdnImpressionQuantity'.$qty_index} = $impressions;
	$$specs{'ddmPress'.$qty_index} = $$Press{strid};
	# Used to be hasAQ.. but that doesn't make any sense.	Must be NeedAQ.
	if ( $$project{NeedAqueous} ) {
    my %aq_results;
    if (DEBUG) {
      my $aq_time = gettimeofday();
      %aq_results = openprint::Estimating::Aqueous::signature_calc(
        $Project, $$project{AqueousSpecs}, $specs, $qty_index, $Imposition, $aq_makereadies );

      my $aq_elapsed = sprintf('%.4f seconds', (gettimeofday() - $aq_time)*1000);
      $log->debug("AQ elapsed: $aq_elapsed") if DEBUG;
    } else {
      %aq_results = openprint::Estimating::Aqueous::signature_calc(
        $Project, $$project{AqueousSpecs}, $specs, $qty_index, $Imposition, $aq_makereadies );
    }
$price{'Aqueous Breakdown'} .= $$project{AqueousSpecs}{'hdnBreakdown'.$qty_index};
		if ( $aq_results{Status} eq 'uncalculated' ) {
			$price{'Aqueous Breakdown'} .= "AQ error: $aq_results{alert} $$project{AqueousSpecs}{alert} ".
				$$project{AqueousSpecs}{'hdnBreakdown'.$qty_index} . '<br/>';
			$price{ComparisonCost} += 1000000; 
		} elsif ( $aq_results{Equipment} ) {
			foreach my $type ( $aq_results{types} ? @{$aq_results{types}} : () ) {
				$$aq_makereadies{$aq_results{Equipment}{id}} = {} if ! $$aq_makereadies{$aq_results{Equipment}{id}};
				$$aq_makereadies{$aq_results{Equipment}{id}}{$type} = [] if ! $$aq_makereadies{$aq_results{Equipment}{id}}{$type};
				push @{$$aq_makereadies{$aq_results{Equipment}{id}}{$type}}, $aq_results{Imposition}->layout_area();
			}

			$price{'Aqueous Breakdown'} = 'Aqueous: ' . $aq_results{breakdown};
#sprintf(
					#'Aqueous Price: %dout MR $%.2f + BC: $%.2f + Service $%.2f + Material $%.2f = $%.2f on %s<br/>',
					#$aq_results{Imposition}{imposition},
					#@aq_results{'MakeReady','BlanketCut','Service','Material','Total'},
					#$aq_results{Equipment}{name} );
			$price{ComparisonCost} += $aq_results{Total};
			$price{'Press Washes'} += $aq_results{washups};
#$openprint::log->error("AQ washups: $aq_results{washups}");
		} else {
$log->warn("Something wrong in AQ");
		} # end if
	} # end if Aqueous
	if ( $price{'Press Washes'} and $Services{WashUp} ) {
		my $WashPrice = $Services{WashUp}->get_Price(undef, $Press);
		$price{'Press Wash Price'} = $$WashPrice{Price};
		$price{'Press Wash Total'} = $price{'Press Washes'} * $$WashPrice{Price};
		$setup_cost += $price{'Press Wash Total'};
	} # end if
	$price{ComparisonCost} += $setup_cost;
	$price{'Setup Total'} += $setup_cost;
#$log->debug("Setup Cost $setup_cost = $press_setup + $price{'WorkTurn Dry Charge'} + $price{'Plate Total'} + $price{'Press Wash Total'} + $price{'Version Charge'} + $price{'Imposition Total'}");

	$price{'Press Setup'} = $press_setup;
	$price{'Impression MPrice'} = List::Util::sum( map { $$_{MPrice} } @{$run_prices} );

	$price{'Minimum Run Charge'} = openprint::service::get_price('PressRunChargeMinimum', undef, $Press);

	if ( $run_cost < $price{'Minimum Run Charge'} ) {
		$run_cost = $price{'Minimum Run Charge'};
	} # end if
	$price{'Run Total'} = $run_cost;
	$price{ComparisonCost} += $run_cost;
	$price{ComparisonCost} += Math::Round::nearest( 0.01, $price{'Ink Price'} );
#$log->debug("Comparison Cost: $price{ComparisonCost}");
	$price{'Total Cost'} = $run_cost + $setup_cost + $price{'Ink Price'};

	$price{complete} = 1;
#my $aq_elapsed = sprintf('%.4f', tv_interval($aq_time)*1000);
##$log->warn("AQ elapsed: $aq_elapsed");
	return \%price;
} # end sub calc_price

sub select_presses {
# this function returns a hash of the presses with their reasons for not being used.

	my ( $Project, $Papers, $specs, $project ) = @_;
#$log->debug("**** Start of select_press. Inputs: Project $project_index ****");

# we do not have to check Image Size here because the the imposition code will take care of that later on.
# it may be a little faster to eliminate the press now but i'm not sure.

# we do not need to do any Perfecting checks because imposition code will create or no create perfecting.

# Inline Perfing & Scoring is done as a sperate run, so it dosn't affect our printing press choice.
# Same with UV, AQ etc.

	my $side_one_colours = $$project{side_one_colours};
	my $side_two_colours = $$project{side_two_colours};
	my %results;
	my $varnish = 0;
	my $aqueous = 0;
#$log->debug(" *** CHECKING FOR VANISH *** ");
	foreach my $colour (@{$$project{'$side_one_coatings'}}, @{$$project{side_two_coatings}} ) {
		if ( $$colour{name} =~ /Varnish/ ) {
#$log->debug(" ** HAVE VARNISH **" );
			$varnish = 1;
		} elsif ( $$colour{name} =~ /Aqueous/ ) {
#$log->debug(" ** HAVE Aqueous **" );
			$aqueous = 1;
		} # end if
	} # end if
	#my $CoatingsCategory = openprint::ServiceCategory->find_one( name => 'Coating' );
	#my @Coatings = map { $_->name() } $CoatingsCategory->Services() if $CoatingsCategory;
	#my @side_one_colours = sets::exclude( \@Coatings, $side_one_colours );
	#my @side_two_colours = sets::exclude( \@Coatings, $side_one_colours );
	my $ProjectType = $Project->Type();

	if ( ! %Presses ) {
		$log->error("Nothing in presses");
	}
	foreach my $Press ( values %Presses ) {
$log->debug("Considering $$Press{strid}") if DEBUG_PRESSES;
		my $press_id = $Press->id();

		my ( $min_object_width, $min_object_length ) = ( $Press->specification( 'Minimum Object Width'), $Press->specification('Minimum Object Length') );

		if ( $min_object_width and $min_object_length ) {
			if ( ( $min_object_width > $$specs{txtWidth} and $min_object_length > $$specs{txtHeight} ) or ( $min_object_length > $$specs{txtWidth} and $min_object_width > $$specs{txtHeight} ) ) {
				$results{$press_id} = 'Project is too small for press';
				next;
			} # end if
		} # end if

		my ( $max_width, $max_length ) = ( $Press->specification( 'Maximum Sheet Width'), $Press->specification('Maximum Sheet Length') );

		if ( $max_width and $max_length ) {
			if ( ( $max_width < $$specs{txtWidth} or $max_length < $$specs{txtHeight} ) and ( $max_length < $$specs{txtWidth} or $max_width < $$specs{txtHeight} ) ) {
				$results{$press_id} = 'Project does not fit on press';
				next;
			} # end if
		} # end if

		if ( ( $$specs{ScreenType} and ( $$specs{ScreenType} eq 'FM' ) ) and $Press->specification('FM Screening Capable') ne 'Y' ) {
			$results{$press_id} = "Can't do FM Screening";
			next;
		} # end if

		if ( $_ = $Press->specification('ProjectTypes') ) {
			my ( @allowed, @disallowed );

			foreach my $type ( split(',',$_) ) {
				if ( $type =~ /^\!(.+)$/ ) {
					push @disallowed, $1;
				} else {
					push @allowed, $type;
				} # end if
			} # end foreach type
			if ( @disallowed and sets::isin( $$ProjectType{name}, \@disallowed ) ) {
				$results{$press_id} = "Press is set to not do " . $$ProjectType{name};
				next;
			} # end if
			if ( @allowed and ! sets::isin( $$ProjectType{name}, \@allowed ) ) {
				$results{$press_id} = "Press is not set to do " . $$ProjectType{name};
				next;
			} # end if
		} # end if

		if ($$ProjectType{name} eq 'Envelopes') {
       if ($Press->specification('Envelope Capable') ne 'Y') {
         $results{$press_id} = "Failed Envelope Check";
         next;
       }
    } elsif ($Press->specification('Envelope Only') eq 'Y') {
			$results{$press_id} = 'Is envelope only';
			next;
		} # end if

		my $paper_ok = 0;
		my $Paper;

		foreach $Paper ( @$Papers ) {
			my $max_calliper = $Press->specification('Maximum Calliper', $$Paper{grade} );
			if ( $max_calliper and ( $$Paper{calliper} > $max_calliper ) ) {
				$results{$press_id} = "Press $press_id Failed Calliper Check.	Maximum calliper is $max_calliper";
				next;
			} # end if
			my $min_calliper = $Press->specification('Minimum Calliper', $$Paper{grade} );
			if ( $min_calliper and ( $$Paper{calliper} < $min_calliper ) ) {
				$results{$press_id} = "Press $press_id Failed Minimum Calliper Check.	Minimum calliper is $min_calliper";
				next;
			} # end if
			my $max_gsm = $Press->specification('Maximum GSM', $Paper->gsm() );
			if ( $max_gsm and ( $$Paper{gsm} > $max_gsm ) ) {
				$results{$press_id} = "Press $press_id Failed gsm Check.	Maximum gsm is $max_gsm";
				next;
			} # end if
			my $min_gsm = $Press->specification('Minimum GSM', $Paper->gsm() );
			if ( $min_gsm and ( $$Paper{gsm} < $min_gsm ) ) {
				$results{$press_id} = "Press $press_id Failed gsm Check.	Minimum gsm is $min_gsm";
				next;
			} # end if
			if ( ( $$Paper{type} eq 'Roll' ) and $Press->specification('Minimum Basis Weight') and $Paper->basis_mweight() < $Press->specification('Minimum Basis Weight') ) {
				$results{$press_id} = "Failed Minimum Basis Weight Check **" . $Paper->basis_mweight() . ' < ' . $Press->specification('Minimum Basis Weight');
				next;
			} # end if
			$paper_ok = 1;
			last;
		} # end foreach Paper

		if ( ! $paper_ok ) {
			next;
		} # end if

		$Paper = $$Papers[0] if ! $Paper;

		my $printing_type = $Press->specification('Printing Type');
		if ( ! $printing_type ) {
			$log->error("Printing Type not set on $$Press{strid}");
		} elsif ( $printing_type eq 'Digital' ) {
# Digital only support Process, no PMS, etc...
			if ( ( scalar @$side_one_colours == 1 ) and ( ! sets::isin( $$project{side_one_colour_names}[0], ['Black', 'Black Spot Colour'] ) ) ) {
				$results{$press_id} = "Digital doesn't do non-black: $$side_one_colours[0]";
				next;
			} # end if
			if ( ( scalar @$side_two_colours == 1 ) and ( ! sets::isin( $$project{side_two_colour_names}[0], ['Black', 'Black Spot Colour'] ) ) ) {
				$results{$press_id} = "Digital doesn't do non-black: $$side_two_colours[0]";
				next;
			} # end if

			if ( scalar @$side_one_colours > 1 and scalar @$side_one_colours < 4 ) {
				$results{$press_id} = "Digital doesn't do non-process";
				next;
			} # end if
			if ( scalar @$side_one_colours > 4 ) {
				$results{$press_id} = "Digital doesn't do non-process";
				next;
			} # end if
			if ( scalar @$side_two_colours > 1 and scalar @$side_two_colours < 4 ) {
				$results{$press_id} = "Digital doesn't do non-process";
				next;
			} # end if
			if ( scalar @$side_two_colours > 4 ) {
				$results{$press_id} = "Digital doesn't do non-process";
				next;
			} # end if
			if ( ( scalar @$side_one_colours == 4 ) and sets::intersection( @{$$project{side_one_colour_names}}, 'Cyan', 'Magenta', 'Yellow','Black' ) != 4 ) {
				$results{$press_id} = "Digital doesn't do non-process";
				next;
			} # end if
			if ( ( scalar @$side_two_colours == 4 ) and sets::intersection( @{$$project{side_two_colour_names}}, 'Cyan', 'Magenta', 'Yellow','Black' ) != 4 ) {
				$results{$press_id} = "Digital doesn't do non-process";
				next;
			} # end if
			if ( $openprint::usergroup::groups_cache{'Digital Estimating'} and ! openprint::usergroup::is_user_in( ['Digital Estimating'], $openprint::session{user_id} ) ) {
				$results{$press_id} = "You are not authorized for estimating on Digital presses.";
				next;
			} # end if
		} elsif ( ( $printing_type eq 'Web' ) and $openprint::usergroup::groups_cache{'Web Estimating'} and ! openprint::usergroup::is_user_in( ['Web Estimating'], $openprint::session{user_id} ) ) {
			$results{$press_id} = "You are not authorized for estimating on Web presses.";
			next;
		} elsif ( $press_id == 108 and ! sets::isin( $openprint::session{user_type}, [ 'E', 'A' ] ) ) {
			$results{$press_id} = "You are not authorized for estimating on this press.";
			next;
		} # end if

		my $number_of_colours = $Press->specification('Number of Colours');
		if ( ! $number_of_colours ) {
			$log->error("Press $$Press{strid} has no Number of Colours");
		}

    my $multipass = $Press->specification('Multipass', $Paper->gsm());
		if ( ( @$side_one_colours > $number_of_colours or @$side_two_colours > $number_of_colours ) and ( !$multipass or ( $multipass ne 'Y' ) ) ) {
			$results{$press_id} = 'Too many colours and no multipass.';
			next;
		} elsif ( $_ = $Press->specification('Web Press') and ( $_ eq 'Y' ) ) {
			if ( @$side_one_colours > $number_of_colours ) {
				$results{$press_id} = 'Too many colours for web.';
				next;
			} elsif ( @$side_two_colours > $number_of_colours ) {
				$results{$press_id} = 'Too many colours for web.';
				next;
			} # end if
		} elsif ( $side_one_colours and @$side_two_colours and ($printing_type ne 'Digital') and $Press->specification('Runstyles') eq 'Sheet Work' and $Press->specification('Multipass', $Paper->gsm()) ne 'Y' ) {
			# Something like an inkjet that can only do 1 sided
			$results{$press_id} = 'Can only do 1 sided jobs.';
			next;
		} # end if

		if ( $varnish ) {
			if ( $Press->specification('Varnish Capable') ne 'Y' ) {
				$results{$press_id} = 'Failed varnish check.';
				next;
			} # end if
		} # end if
		if ( my $stocknames = $Press->specification('StockBrands') ) {
			my ( @allowed, @disallowed );
			foreach ( split(',', $stocknames) ) {
				if ( $_ =~ /^\!(.+)$/ ) {
					push @disallowed, $1;
				} else {
					push @allowed, $_;
				} # end if
			} # end foreach
	
			if ( @allowed and ! sets::isin( $Paper->brand(), \@allowed ) ) {
				$results{$press_id} = 'Not suitable for this stock.';
				next;
			} # end if
			if ( @disallowed and sets::isin( $Paper->brand(), \@disallowed ) ) {
				$results{$press_id} = 'Not suitable for this stock.';
				next;
			} # end if
		} # end if
		if ( my $stockmaterials = $Press->specification('StockMaterials') ) {
			my ( @allowed, @disallowed );
			foreach ( split(',', $stockmaterials) ) {
				if ( $_ =~ /^\!(.+)$/ ) {
					push @disallowed, $1;
				} else {
					push @allowed, $_;
				} # end if
			} # end foreach
	
			if (@allowed and (!$Paper->material() or !sets::isin( $Paper->material(), \@allowed ))) {
				$results{$press_id} = 'Not suitable for this stock.';
				next;
			} # end if
			if (@disallowed and $Paper->material() and sets::isin($Paper->material(), \@disallowed)) {
				$results{$press_id} = 'Not suitable for this stock.';
				next;
			} # end if
		} # end if
		$results{$press_id} = '';
	} # end while

	return %results;
} # end sub select_press

sub get_run_prices {
	my ( $impressions, $side_one_colours, $side_two_colours, $Imposition, $Press, $price ) = @_;


	my @run_prices;
	my $max_colours = $Press->specification('Number of Colours');

	my $impression_service = 'ColourImpression';

	if ( $$Imposition{runstyle} eq 'Web' or $$Imposition{runstyle} eq 'Perfecting' ) {
# A web does both sides at once, and cannot do multipass
		$impression_service = join('',$$Imposition{runstyle},'Impression',$side_one_colours,'/',$side_two_colours);
		my $Impression_Service = $Services{$impression_service};
		my $RunPrice;
		if ( ! ( $Impression_Service and $RunPrice = $Impression_Service->get_Price($impressions, $Press) ) ) {
			if ( $side_one_colours != $side_two_colours ) {
				# Try back then front
				$impression_service = join('',$$Imposition{runstyle},'Impression',$side_two_colours,'/',$side_one_colours);
				$Impression_Service = $Services{$impression_service};
			}
			if ( ! ( $Impression_Service and $RunPrice = $Impression_Service->get_Price( $impressions, $Press ) ) ) {
				$Impression_Service = $Services{$$Imposition{runstyle}.'Impression'};
				$RunPrice = $Impression_Service->get_Price( $impressions, $Press ) if $Impression_Service;
			} # end if
		} # end if
		$$RunPrice{side} = 'Front & Back';
		$$RunPrice{impressions} = $impressions;
		push @run_prices, $RunPrice;
		
	} else {
		if ( $side_one_colours ) {
			my $full_runs = int($side_one_colours / $max_colours);
			if ( $full_runs ) {
				my $run_colours = $side_one_colours > $max_colours ? $max_colours : $side_one_colours;
				my $Impression_Service = $Services{$run_colours.$impression_service};
				my $RunPrice = $Impression_Service->get_Price( $impressions, $Press );
				$$RunPrice{Passes} = $full_runs;
				$$RunPrice{impressions} = $impressions;
				$$RunPrice{side} = 'Front';
				foreach ( 1 .. $full_runs ) {
					push @run_prices, $RunPrice;
				}
			} # end if

			my $mod_colours = $side_one_colours % $max_colours;
			if ( $mod_colours ) {
				my $Impression_Service = $Services{$mod_colours.$impression_service};
				if ( ! $Impression_Service ) {
					$log->error("No service for $mod_colours.$impression_service");
				} else {
					my $RunPrice = $Impression_Service->get_Price( $impressions, $Press );
					$$RunPrice{Passes} = 1;
					$$RunPrice{impressions} = $impressions;
					$$RunPrice{side} = 'Front';
					push @run_prices, $RunPrice;
				}
			} # end if mod_colours
		} # end if side one colours

#$log->debug(" ** SIDE ONE RUNNING PRICE $running_price **");
		if ( $side_two_colours ) {
			my $full_runs = int($side_two_colours / $max_colours);
			if ( $full_runs ) {
				my $run_colours = $side_two_colours > $max_colours ? $max_colours : $side_two_colours;
				my $Impression_Service = $Services{$run_colours.$impression_service};
				my $RunPrice = $Impression_Service->get_Price( $impressions, $Press );
				$$RunPrice{impressions} = $impressions;
				$$RunPrice{side} = 'Back';
				foreach ( 1 .. $full_runs ) {
					push @run_prices, $RunPrice;
				}
			} # end if
#
			my $mod_colours = $side_two_colours % $max_colours;
			if ( $mod_colours ) {
				my $Impression_Service = $Services{$mod_colours.$impression_service};
				my $RunPrice = $Impression_Service->get_Price( $impressions, $Press );
				$$RunPrice{impressions} = $impressions;
				$$RunPrice{side} = 'Back';
				push @run_prices, $RunPrice;
			} # end if
		} # end if side_two_colours
	} # end if web perfecting or other

  # now work out the press run speed

	# There should be either a Standard Run Speed

	my $run_speed = $$price{Runspeed};
	my $std_speed = $$price{StandardRunSpeed};
	my $Paper = $$Imposition{Paper};
	
	my $speed_mod;
	if ( $std_speed ) {
		if ( $std_speed and ( $$std_speed{units} =~ /^Per (.+) Per Hour$/ ) ) {
			my $unit = $1;
			if ( $unit =~ /([\d\.]+)x([\d\.]+)/ ) {
				my $area = $1*$2;
				if ( ! $$Imposition{object_width} * $$Imposition{object_height} ) {
					$log->debug("Runspeed for $$Imposition{object_width} * $$Imposition{object_height} on $$Press{id}");
				} else {
					$run_speed = int( $$std_speed{value} * $area/($$Imposition{object_width} * $$Imposition{object_height}) );
					#$log->debug("Runspeed = $$std_speed{value} $$std_speed{units} * $area / ( $$Imposition{object_width} * $$Imposition{object_height}) = $run_speed");
				} # end if
				#$log->debug("Have runspeed $$std_speed{value}, area: $area, $run_speed");
			} else {
				$log->warn("Unknown Per setting $unit");
			} # end if
		} else {
	# Only load this if not already specified by some inline bindery service
      if ( ! $run_speed ) {
				$run_speed = $Press->specification( $$std_speed{name}, (lc $$std_speed{units} eq 'calliper' ? $$Paper{calliper} : $$Paper{gsm} ) );
      } elsif ( DEBUG ) {
        $log->debug("Not looking up run speed because already specified");
      }
			if ( ! $run_speed ) {
				$log->debug("No run sped on $$Press{strid} for $$std_speed{units} " . ($$std_speed{units} eq 'Calliper' ? $$Paper{calliper} : $Paper->gsm() ) ) if DEBUG;
				$run_speed = $$std_speed{value};
			} # end if
		} # end if
	} else {
		$log->debug("No standard speed on $$Press{strid} have runspeed $run_speed") if DEBUG;
	} # end if

	if ( $$Imposition{runstyle} eq 'Perfecting' and ! $$Paper{perfecting} ) {
		my $Outside_Wheel_Size = $Press->specification('Outside Slow Down Wheel Size');
$log->debug("Checking for slowdown wheel size: $Outside_Wheel_Size") if DEBUG;
		if ( $Outside_Wheel_Size ) {
			my $Slow_Down = $Press->Specification('Outside Wheel Slow Down');
$log->debug("Have slowdown wheel size: $Outside_Wheel_Size layout_wdith: " . $Imposition->layout_width() . ' paper width: ' . $Imposition->sheet_width() ) if DEBUG;
			if ( $Imposition->layout_width() + $Outside_Wheel_Size > $Imposition->sheet_width() ) {
				if ( $$Slow_Down{units} eq 'Percent' ) {
					
					$run_speed *= 1-($$Slow_Down{value} / 100);
$log->debug("Speed_mod has become $speed_mod") if DEBUG;
				} else {
$log->error("Unknown units on Outside Wheel Slow Down ($$Slow_Down{units})");
				} # end if
			} # end if
		} # end if
	} # end if

	if ( $std_speed and ( $run_speed != $$std_speed{value} ) ) {
		$speed_mod = Math::Round::nearest(.001, $$std_speed{value} / $run_speed);
		#$log->debug("1Press ".$$Press{strid}." Calliper: $$Paper{calliper} gsm: $$Paper{gsm} ($running_price) ($run_price{units}) STD: ($$std_speed{value}) RUN ($run_speed), mod: $speed_mod,	std/run: " . ( $speed_mod ? $run_speed/$speed_mod : $std_speed/$run_speed ) ) if DEBUG;
	}
	my $SheetLengthMarkup = $Press->Specification('SheetLengthMarkup',$$Paper{height});
	my $SheetWidthMarkup = $Press->Specification('SheetWidthMarkup',$$Paper{width});

	foreach my $run_price ( @run_prices ) {
		$$run_price{run_speed} = $run_speed;

		if ( $$run_price{units} and sets::isin( $$run_price{units}, ['per m','per 1000 impressions', 'per 1000'] ) ) {
			if ( $speed_mod ) {
				$$run_price{Price} *= $speed_mod;
			} # end if
#$log->warn(" ** FINAL	RUNNING PRICE $running_price **") if DEBUG or 1;
			$$run_price{Total} = ($$run_price{Price} * $impressions)/1000;
			$$run_price{MPrice} = $$run_price{Price};
		} elsif ( $$run_price{units} eq 'per impression' ) {
			if ( $speed_mod ) {
				$$run_price{Price} *= $speed_mod;
			} # end if
#$log->warn(" ** FINAL	RUNNING PRICE $running_price **") if DEBUG or 1;
			$$run_price{Total} = ($$run_price{Price} * $impressions);
			$$run_price{MPrice} = $$run_price{Price} * 1000;

		} elsif ( $$run_price{units} eq 'per hour' ) {
			if ( $$run_price{range_units} and ( $$run_price{range_units} eq 'total impressions' ) and $side_one_colours and $side_two_colours ) {
				my $r_price = $$run_price{Service}->get_Price( $impressions*2, $Press );
				$$run_price{Price} = $$r_price{Price};
			}
			if ( $run_speed ) {
				if ( int($run_speed) ) {
# In Minutes, not hours
					$$run_price{RunHours} = $impressions / $run_speed;
					$$run_price{RunTime} = int ( 60 * $impressions / $run_speed );
				} else {
					$log->error(" Bogus value for runspeed: $run_speed in get_run_price on $$Press{strid}");
				} # end if
			} # end if
			$$run_price{Total} = $$run_price{Price} * $$run_price{RunHours};
			$$run_price{MPrice} = ( $$run_price{Total} / $impressions ) * 1000;
		} else {
			$log->warn("Unknown Units for $$Imposition{runstyle} ($side_one_colours/$side_two_colours) $impression_service: ($impressions imps) ($$run_price{units}) on " . $$Press{strid} );
		} # end if
		if ( $SheetLengthMarkup ) {
			if ( $$SheetLengthMarkup{units} eq 'Percent' ) {
				$$run_price{Price} *= 1 + ($$SheetLengthMarkup{value}/100);
				$$run_price{MPrice} *= 1 + ($$SheetLengthMarkup{value}/100);
				$$run_price{Total} *= 1 + ($$SheetLengthMarkup{value}/100);
			} else {
				$log->debug("Unknown units for SheetLengthMarkup for $$Paper{height}");
			}
		}
		if ( $SheetWidthMarkup ) {
			if ( $$SheetWidthMarkup{units} eq 'Percent' ) {
				$$run_price{Price} *= 1 + ($$SheetWidthMarkup{value}/100);
				$$run_price{MPrice} *= 1 + ($$SheetWidthMarkup{value}/100);
				$$run_price{Total} *= 1 + ($$SheetWidthMarkup{value}/100);
			} else {
				$log->debug("Unknown units for SheetWidthMarkup for $$Paper{width}");
			}
		}
	} # end foreach run_price
#$log->debug("Impresion price: $run_price{Cost} $run_price{units} = $run_price{Price}");
	return \@run_prices;
} # end sub get_run_prices

# This is called once perside, or just once for W&T
sub press_setup_cost {
	my ( $project, $plate_change_qty, $plate_runs, $colours, $calliper, $qty_index, $Imposition, $other_impositions ) = @_;

	my $Press = $$Imposition{Press};
  my $specs = $$Imposition{specs};

	# These are pre-filtered in setup_project now
	my $setup_count = @$colours;
  my $unit_count = $setup_count;

	my %Price;

	$Price{'Setup Count'} = $setup_count + ( $plate_change_qty ? $plate_change_qty : 0 );
	if ( ! ( %Price = openprint::service::get_price_object( 'PressUnitMakeReady'.$$Imposition{runstyle}, undef, $Press ) ) ) {
		%Price = openprint::service::get_price_object('PressUnitMakeReady', undef, $Press);
	} # end if
  #$Imposition->display("Sigature index $$specs{SignatureIndex}");
  if ($Price{units} eq 'per press per unit') {
    my @previous_impositions = map { $$_{specs}{SignatureIndex} < $$specs{SignatureIndex} ? $_ : () } @{$other_impositions};
    #foreach (@{$other_impositions}) {
    #$_->display('Sig Index:'.$$_{specs}{SignatureIndex});
    #if (($_ != $Imposition) and ($$_{specs}{SignatureIndex} == $$specs{SignatureIndex})) {
    #$parent_imposition = $_;
    #last;
    #} elsif ($$_{specs}{SignatureIndex} < $$specs{SignatureIndex}) {
    #push @previous_impositions, $_;
    #}
    #}
    #if ($parent_imposition) {
    #$unit_count = 0;
    #$Price{Total} = 0;
    #} else {
    if (@previous_impositions) {
      #$log->error("Previous impositions: " . @previous_impositions);

      foreach my $prev_i (@previous_impositions) {
        my $sig_specs = $$prev_i{specs};
        if ($$prev_i{Press}->id() == $$Press{id} and $$prev_i{runstyle} eq $$Imposition{runstyle}) {
          $unit_count = 0;
          #my @prev_colours = ($prev_i->colours('SideOne'), $prev_i->colours('SideTwo'));
          #$log->error("Prev colours: @prev_colours");

          #my %prev_colours = map { $$_{name} => $_ } @prev_colours;
          ##$log->error("Prev: ".join(',', keys %prev_colours));
          #foreach my $c (@$colours) {
          #$log->error("Colour $$c{name} $prev_colours{$$c{name}}");
          #if ($prev_colours{$$c{name}} or $prev_colours{$$c{name}.' Spot Colour'}) {
          #$unit_count -= 1;
          #}
          #}
          %Price = openprint::service::get_price_object( $Price{ServiceName}, $unit_count, $Press );
          #$log->warn("Charging $Price{Price} setup for $$specs{SignatureIndex}");
          $Price{Total} = $unit_count * $Price{Price};
          last;
          #} else {
          #$log->error("Previous imp with index $$sig_specs{SignatureIndex} <=> $$specs{SignatureIndex} has press ".$$prev_i{Press}->strid().' ours is '.$$Press{strid});
        } # end if
      } #end 
    } # end if parent
    if (!exists $Price{Total}) {
      %Price = openprint::service::get_price_object( $Price{ServiceName}, $unit_count, $Press );
      #$log->warn("Charging $Price{Price} setup for $$specs{SignatureIndex}");
      $Price{Total} = $unit_count * $Price{Price};
    }

  } elsif ( $Price{units} eq 'stock calliper - per plate' ) {
		%Price = openprint::service::get_price_object( 'PressUnitMakeReady', $calliper, $Press );
		$Price{Total} = $Price{Price} * $unit_count;
	} elsif ( $Price{units} eq 'per job' ) {
		
		my $Project = $$Imposition{Project};
		if ( $Project ) {
			my @signatures = @{$$project{sorted_signatures}};
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signatures[0] );
			if ( $$sig_specs{SignatureIndex} == $$specs{SignatureIndex} ) {
				# Do the charge.	
				#$log->warn("Charging $Price{Price} setup for $$specs{SignatureIndex}");
				$Price{Total} = $Price{Price};
			} # end if
		} else {
			$log->error('No Project in imposition');
		} # end if
	} elsif ( $Price{units} eq 'per form' ) {
		my $specs = $$Imposition{specs};
#$log->debug("PressMakeRady per form: previous forms: " . ( $$specs{'PreviousForms'.$qty_index} + 1 ) );
		%Price = openprint::service::get_price_object( 'PressUnitMakeReady', $$specs{"PreviousForms$qty_index"}, $Press);
		$Price{Total} = $Price{Price};
	} elsif ( $Price{units} eq 'total' ) {
		if ( ! ( %Price = openprint::service::get_price_object( 'PressUnitMakeReady'.$$Imposition{runstyle}, $unit_count, $Press ) ) ) {
			%Price = openprint::service::get_price_object( 'PressUnitMakeReady', $unit_count, $Press );
		} # end if
		
		$Price{Total} = $Price{Price};
	} elsif ( $Price{units} eq 'per side' ) {
		if ( ! ( %Price = openprint::service::get_price_object( 'PressUnitMakeReady'.$$Imposition{runstyle}, $unit_count, $Press ) ) ) {
			%Price = openprint::service::get_price_object( 'PressUnitMakeReady', $unit_count, $Press );
		} # end if
		
	} else { # Per Unit
		if ( ! ( %Price = openprint::service::get_price_object( 'PressUnitMakeReady'.$$Imposition{runstyle}, $unit_count, $Press ) ) ) {
			%Price = openprint::service::get_price_object( 'PressUnitMakeReady', $unit_count, $Press );
		} # end if
		$Price{Total} = $Price{Price} * $unit_count;
	} # end if
	if ( $Price{units} =~ /per run/i ) {
		$Price{Total} *= $plate_runs if $plate_runs;
		#$Price{Total} *= $plate_change_qty if $plate_change_qty;
	} # end if
	$Price{'Press Setup'} = $Price{Total};
	$Price{'Unit Count'} = $unit_count;


	my $plates = $setup_count;
	$plates *= $plate_runs if $plate_runs;
	$plates += $plate_change_qty if $plate_change_qty;
	$Price{'Plate Count'} = $plates;
	# No on is using these at this time. We can re-enable when someone does.
	#my %PlateSetupPrice = openprint::service::get_price_object( 'PlateMakeReady'.$$Imposition{runstyle}.$$Imposition{sides}.'Sided', undef, $Press );
	#%PlateSetupPrice = openprint::service::get_price_object( 'PlateMakeReady'.$$Imposition{runstyle}, undef, $Press ) if ! %PlateSetupPrice;
	#%PlateSetupPrice = openprint::service::get_price_object( 'PlateMakeReady', undef, $Press ) if ! %PlateSetupPrice;
	my %PlateSetupPrice = openprint::service::get_price_object( 'PlateMakeReady', undef, $Press );
	if ( %PlateSetupPrice ) {
		my $units = $PlateSetupPrice{units};
		if ( $units eq 'per hour' ) {
			my $time = $Press->specification('Plate Setup Time') * $plates / 60;
			$Price{'Plate Total'} = $PlateSetupPrice{Price} * $time;
		} elsif ( $units eq 'per plate' ) {
			%PlateSetupPrice = openprint::service::get_price_object( $PlateSetupPrice{ServiceName}, $plates, $Press );
			if ( ! %PlateSetupPrice ) {
				$log->error("Error getting PlateMakeReady for $$Press{strid} for $plates plates runs: $plate_runs setup count: $setup_count change: $plate_change_qty");
			} # end if
			$Price{'Plate Units'} = $PlateSetupPrice{units};
			$Price{'Plate Price'} = $PlateSetupPrice{Price};
			$Price{'Plate Total'} = $PlateSetupPrice{Price} * $plates;
		} else {
			$log->error("No Plate Make Ready Units ($units) for plates on $$Press{strid} defaulting to pre plate");
			%PlateSetupPrice = openprint::service::get_price_object( $PlateSetupPrice{ServiceName}, $plates, $Press );
			if ( ! %PlateSetupPrice ) {
				$log->error("Error getting PlateMakeReady for $$Press{strid} for $plates plates runs: $plate_runs setup count: $setup_count change: $plate_change_qty");
			} # end if
			$Price{'Plate Units'} = $PlateSetupPrice{units};
			$Price{'Plate Price'} = $PlateSetupPrice{Price};
			$Price{'Plate Total'} = $PlateSetupPrice{Price} * $plates;
		} # end if units
	} else {
		$Price{'Plate Units'} = '';
		$Price{'Plate Price'} = 0;
		$Price{'Plate Total'} = 0;
	} # end if has a platesetupprice

	return \%Price;
} # end sub press_setup_cost

# This is only called for work and turn
sub filter_colours {
	my ( $front, $back ) = @_;
	#my @filtered_colours = @{$front} if $front;
	my %filtered_colours = map { my %c = %{$_}; ( $$_{name}, \%c ) } @{$front};
	my @colour_names = map { $$_{name} } @{$front};

	foreach my $Colour ( @{$back} ) {
		if ( ! $filtered_colours{$$Colour{name}} ) {
			#push @filtered_colours, $Colour;
			push @colour_names, $$Colour{name};
			$filtered_colours{$$Colour{name}} = $Colour;
		} else {
			$filtered_colours{$$Colour{name}}{coverage} = ( $filtered_colours{$$Colour{name}}{coverage} + $$Colour{coverage}) / 2;
		} # end if
	} # end foreach
	return @filtered_colours{@colour_names};
} # end sub

sub compare_signatures_runstyle {
	my ( $Project, $sig1, $sig2, $qty_index, $exclude ) = @_;
	foreach my $q_i ( $qty_index ? ( $qty_index ) : ( $Project->quantity_indexes() ) ) {
		foreach my $k ( 'ddmRunStyle', 'ddmPress','PageQuantity','txtImposition','ddmBleedSize','txtPlateChangeQuantity', 'Versions',
				'chkOverrideBleedSize',
				'chkOverridePageQuantity',
				'chkOverrideImposition',
				'chkOverrideRunStyle',
				'OverrideCutOff',
				'chkOverrideSheetSize',
				'chkOverridePress',
				'OverridePrintingType',
				'chkOverrideGrainDirection',
				'OverrideVersions',
) {

			my $key = $k.$q_i;

			if ( ! ( ( (!$$sig1{$key}) and (! $$sig2{$key}) ) or ( $$sig1{$key} and $$sig2{$key} and ( $$sig1{$key} eq $$sig2{$key} ) )) ) {
			#if ( ( $$sig1{$k} and ! $$sig2{$k} ) or ( $$sig2{$k} and ! $$sig1{$k} ) or ( $$sig1{$key.$q_i} ne $$sig2{$key.$q_i} ) ) {
#$log->debug("Not the same $key $$sig1{ServiceIndex} $$sig2{ServiceIndex} $$sig1{$key.$q_i} $$sig2{$key.$q_i} $$sig1{SignatureIndex} $$sig2{SignatureIndex}");
				return 0;
			} # end if
		} # end if
	} # end foreach q_i
	foreach my $key (
			'txtWidth','txtHeight',
			'chkProcessColourSideOne', 'chkProcessColourSideTwo',
			'chkCyanSideOne','chkMagentaSideOne','chkYellowSideOne','chkBlackSideOne',
			'chkCyanSideTwo','chkMagentaSideTwo','chkYellowSideTwo','chkBlackSideTwo',
			'ColourCoatingType1SideOne', 'ColourCoatingColour1SideOne', 'ColourCoatingCoverage1SideOne',
			'ColourCoatingType2SideOne', 'ColourCoatingColour2SideOne', 'ColourCoatingCoverage2SideOne',
			'ColourCoatingType3SideOne', 'ColourCoatingColour3SideOne', 'ColourCoatingCoverage3SideOne',
			'ColourCoatingType4SideOne', 'ColourCoatingColour4SideOne', 'ColourCoatingCoverage4SideOne',
			'ColourCoatingType5SideOne', 'ColourCoatingColour5SideOne', 'ColourCoatingCoverage5SideOne',
			'ColourCoatingType6SideOne', 'ColourCoatingColour6SideOne', 'ColourCoatingCoverage6SideOne',
			'ColourCoatingType7SideOne', 'ColourCoatingColour7SideOne', 'ColourCoatingCoverage7SideOne',
			'ColourCoatingType8SideOne', 'ColourCoatingColour8SideOne', 'ColourCoatingCoverage8SideOne',
			'ColourCoatingType1SideTwo', 'ColourCoatingColour1SideTwo', 'ColourCoatingCoverage1SideTwo',
			'ColourCoatingType2SideTwo', 'ColourCoatingColour2SideTwo', 'ColourCoatingCoverage2SideTwo',
			'ColourCoatingType3SideTwo', 'ColourCoatingColour3SideTwo', 'ColourCoatingCoverage3SideTwo',
			'ColourCoatingType4SideTwo', 'ColourCoatingColour4SideTwo', 'ColourCoatingCoverage4SideTwo',
			'ColourCoatingType5SideTwo', 'ColourCoatingColour5SideTwo', 'ColourCoatingCoverage5SideTwo',
			'ColourCoatingType6SideTwo', 'ColourCoatingColour6SideTwo', 'ColourCoatingCoverage6SideTwo',
			'ColourCoatingType7SideTwo', 'ColourCoatingColour7SideTwo', 'ColourCoatingCoverage7SideTwo',
			'ColourCoatingType8SideTwo', 'ColourCoatingColour8SideTwo', 'ColourCoatingCoverage8SideTwo',
			'BleedLeft','BleedRight','BleedTop','BleedBottom',
			) {
		next if $exclude and sets::isin( $key, $exclude );
		if ( ! ( (!$$sig1{$key} and ! $$sig2{$key} ) or ( $$sig1{$key} and $$sig2{$key} and $$sig1{$key} eq $$sig2{$key} ) ) ) {
		#if ( ($$sig1{$key} and ! $$sig2{$key} ) or ( $$sig2{$key} and ! $$sig1{$key} ) or ( $$sig1{$key} ne $$sig2{$key} ) ) {
#$log->debug("Not the same $key $$sig1{ServiceIndex} $$sig2{ServiceIndex} $$sig1{$key} ne $$sig2{$key}");
			return 0;
		} # end if
	} # end foreach
	return 1;
}

# Returns 1 if the same, 0 if ! the same
sub compare_signatures_no_results {
	my ( $Project, $sig1, $sig2, $exclude ) = @_;
	foreach my $key (
			'Group', 'rdbSuppliedStock','rdbSpecificStock','txtEmployeeComments',
			) {
		next if $exclude and sets::isin( $key, $exclude );
		if ( ! ( (!$$sig1{$key} and ! $$sig2{$key} ) or ( $$sig1{$key} and $$sig2{$key} and ( $$sig1{$key} eq $$sig2{$key} ) ) ) ) {
$log->debug("Not the same $key $$sig1{ServiceIndex} $$sig2{ServiceIndex} $$sig1{$key} ne $$sig2{$key}") if DEBUG;
			return 0;
		} # end if
	} # end foreach
	if ( $$sig1{rdbSpecificStock} eq 'Y' ) {
		foreach my $key (
				'CustomStockPrice','StockType',
				'txtSpecificStockBrand','txtSpecificStockFinish','txtSpecificStockColour',
				'txtSpecificStockWidth', 'txtSpecificStockHeight',
				) {
			next if $exclude and sets::isin( $key, $exclude );
			if ( $$sig1{$key} ne $$sig2{$key} ) {
				$log->debug("Not the same $key $$sig1{ServiceIndex} $$sig2{ServiceIndex} $$sig1{$key} ne $$sig2{$key}");
				return 0;
			} # end if
		} # end foreach
		if ( $$sig1{StockType} eq 'Roll' ) {
			foreach my $key ( 'basis_width', 'basis_height', 'basis_mweight' ) {
				next if $exclude and sets::isin( $key, $exclude );
				if ( $$sig1{$key} ne $$sig2{$key} ) {
					$log->debug("Not the same $key $$sig1{ServiceIndex} $$sig2{ServiceIndex} $$sig1{$key} ne $$sig2{$key}");
					return 0;
				} # end if
			} # end foreach
		} else {
			foreach my $key ('txtCustomMWeight') {
				next if $exclude and sets::isin( $key, $exclude );
				if ( $$sig1{$key} ne $$sig2{$key} ) {
					$log->debug("Not the same $key $$sig1{ServiceIndex} $$sig2{ServiceIndex} $$sig1{$key} ne $$sig2{$key}");
					return 0;
				} # end if
			} # end foreach
		} # end if
	} else {
		foreach my $key (
				'ddmStockBrand', 'ddmStockFinish', 'ddmStockColour', 'ddmStockWeight',
				) {
			next if $exclude and sets::isin( $key, $exclude );
			if ( $$sig1{$key} ne $$sig2{$key} ) {
				$log->debug("Not the same $key $$sig1{ServiceIndex} $$sig2{ServiceIndex} $$sig1{$key} ne $$sig2{$key}");
				return 0;
			} # end if
		} # end foreach
	} # end if
	return 1;
} # end sub compare_signatures_noresults
# compares two signature services in terms of their inputs, and returns true if equal, false if not
sub compare_signatures {
	my ( $Project, $sig1, $sig2, $qty_index, $exclude ) = @_;
	return 0 if ! compare_signatures_runstyle( $Project, $sig1, $sig2, $qty_index, $exclude );
	return compare_signatures_no_results( $Project, $sig1, $sig2, $exclude );
#foreach my $key ( 'txtStockGSM' ) {
#if ( sprintf('%.0f', $$sig1{$key}) ne sprintf('%.0f', $$sig2{$key}) ) {
##$log->debug("Not the same $key $$sig1{ServiceIndex} $$sig2{ServiceIndex} $$sig1{$key} ne $$sig2{$key}");
#return 0
#} # end if
#} # end foreach

} # end sub compare_signatures

sub runtime {
	my ( $Project, $specs, $Equipment, $impressions, $runspeed ) = @_;

	my $qty_index = $Project->ordered_quantity_index();
	my %time;

	if ( ! $Equipment ) {
		if ( ! $$specs{UsePress} ) {
			$$specs{UsePress} = $$specs{'ddmPress'.$qty_index};
		} # end if
		$Equipment = openprint::Equipment->find_one( strid=>$$specs{UsePress} );
	} # end if
	if ( ! $Equipment ) {
		$log->error("No equipment found for $$specs{UsePress}");
		return %time;
	} # end if

	my @side_one_colours = get_colours( $specs, 'SideOne' );
	my @side_two_colours = get_colours( $specs, $$specs{side_link} ? 'SideOne' : 'SideTwo' );
	my @colours;
	if ( $$specs{'ddmRunStyle'.$qty_index} and ( $$specs{'ddmRunStyle'.$qty_index} eq 'Work & Turn' or $$specs{'ddmRunStyle'.$qty_index} eq 'Work & Tumble' ) ) {
		@colours = filter_colours(\@side_one_colours, \@side_two_colours);
	} else {
		@colours = ( @side_one_colours, @side_two_colours );
	} # end if

	$time{Setup} = 0;

	$time{Setup} += 60*$Equipment->specification('Setup Time') if @side_one_colours;
	$time{Setup} += 60*$Equipment->specification('Setup Time') if @side_two_colours;
	$time{Setup} += 60*$Equipment->specification('Wash Up Time Per Colour') * @colours;

	$runspeed = runspeed( $Project, $specs, $qty_index, $Equipment ) if ! $runspeed;
	$impressions = $$specs{'hdnImpressionQuantity'.$qty_index} if ! $impressions;
	if ( $runspeed ) {
		$time{Run} += int ( 3600 * $impressions / $runspeed );
	} # end if
	$time{Total} = $time{Setup} + $time{Run};
#$log->debug("Total: $time{Setup} + $time{Run} = $time{Total} => " . misc::seconds2hms( $time{Total} ) );
	return \%time;
} # end sub runtime

sub runspeed {
	my ( $Project, $sig_specs, $qty_index, $Equipment ) = @_;

	my $runspeed;
	if ( ! $Equipment ) {
#$log->debug("SIGSPECS $sig_specs, PROJECT: $Project ");
		my $equipment_name = $$sig_specs{UsePress} ? $$sig_specs{UsePress} : $$sig_specs{'ddmPress'.$qty_index};
		if ( ! $equipment_name ) {
			$log->error( "No equipmnet in sig for qty $qty_index" );
			return;
		} # end if
		$Equipment = openprint::Equipment->find_one(strid=>$equipment_name);
		if ( ! $Equipment ) {
			$log->error( "Equipment $equipment_name not found in runspeed" );
			return;
		} # end if
	} # end if

	my $Imposition = new openprint::Imposition();
	$Imposition->load( $sig_specs, $qty_index, $Project );
	my $Paper = $Imposition->Paper();
	my $form = $$sig_specs{SignatureIndex};

	if ( $Equipment->specification('Folding Capable') eq 'When Printing' ) {
		my $services = $Project->services();
		if ( $$services{Folding} ) {
			my $fold_specs = openprint::service::get_specs_ref( $Project, $$services{Folding}[0] );

			if ( $$fold_specs{'ddmEquipment-'.$$sig_specs{SignatureIndex}.'-'.$qty_index} == $Equipment->id() ) {
				$runspeed = int($$fold_specs{"FoldRunspeed-$form-$qty_index-1"});
				if ( ! $runspeed ) {
					my @Folds = openprint::Estimating::Folding::get_Folds($fold_specs, $Imposition, $qty_index);
					if ( @Folds ) {
						my $Fold = $Folds[0];
						$runspeed = int($Fold->runspeed($$Fold{runspeed_units} eq 'calliper' ? $$Paper{calliper} : $$Paper{gsm}));
					}
				}
			} # end if Folding inline
		} # end if has Folding
	} # end if Press supports Folding

	if ( !$runspeed ) {
		my $RunSpeed = $Equipment->Specification('Run Speed '.$$Imposition{runstyle});
		$RunSpeed = $Equipment->Specification('Run Speed') if ! $RunSpeed;
		if ( $RunSpeed ) {
			if ( lc $$RunSpeed{units} eq 'calliper' ) {
				$runspeed = $Equipment->specification($$RunSpeed{name}, $$Paper{calliper});
				$log->debug("Found runspeed for $$Equipment{strid}: $runspeed on calliper:" . $$Paper{calliper} );
			} elsif (lc $$RunSpeed{units} eq 'impressions' ) {
				$runspeed = int($Equipment->specification($$RunSpeed{name}, $$sig_specs{'hdnImpressionQuantity'.$qty_index}) );
				$log->debug("Found runspeed for $$Equipment{strid}: $runspeed on gsm:" . $Paper->gsm());
			} else {
				$runspeed = int($Equipment->specification($$RunSpeed{name}, $Paper->gsm()) );
				$log->debug("Found runspeed for $$Equipment{strid}: $runspeed on gsm:" . $Paper->gsm());
			}
		} else {
			$runspeed = int($Equipment->specification('Standard Run Speed', $Paper->gsm()));
		}
	} # end if
	return $runspeed;
} # end sub runspeed

sub get_weight {
	my ( $Project, $specs, $qty_index ) = @_;

	my $Paper = openprint::Paper::load_from_signature( $Project, $specs, $qty_index );
	my $sig_weight = $$specs{txtWidth} * $$specs{txtHeight} * $Paper->wpsi();

	my $weight = $sig_weight;
	if ( $$specs{PageQuantity} ) {
# For Scratch Pads
		$weight *= $$specs{PageQuantity};
	} elsif ( $$specs{'PageQuantity'.$qty_index} ) {
		if ( ! $$specs{txtSpreadSize} ) {
			$$specs{txtSpreadSize} = 4;
			$log->error("Unset Spreadsize");
			foreach my $k ( keys %$specs ) {
				$log->error("$k=>$$specs{$k}");
			} # end foreach
		} # end if
		$weight *= $$specs{'PageQuantity'.$qty_index}/$$specs{txtSpreadSize};
	} # end if
# This is business cards, etc.
#$log->debug("Get_weight: Spreadsize($$specs{txtSpreadSize} ($$specs{'PageQuantity'.$qty_index} > 0 ? $$specs{'PageQuantity'.$qty_index} : 1 ) * ( $$specs{txtWidth} * $$specs{txtHeight} ) * ".$Paper->gsm().'gsm '.$Paper->wpsi() . '=='.$Paper->wpsi(undef)." wpsi = $sig_weight * $$specs{'PageQuantity'.$qty_index} = " . $weight);
	return $weight;
} # end sub get_weight

sub group_summary {
} # end sub group_summary

sub summary {
	my ( $Project, $service_index, $specs, $qty_index ) = @_;

	my $services = $Project->services();
	my $printing_specs = openprint::service::get_specs_ref($Project, $$services{''}[0]) if $$services{''};

	if ( $qty_index ) {
		return '' if ! $$specs{'txtImposition'.$qty_index};
		my $html;
		if ( $Project->Type()->name() ne 'PresentationFolders' ) {
			$html .= $$specs{'PageQuantity'.$qty_index} ? $$specs{'PageQuantity'.$qty_index}.'pg ' : '';
		} # end if
		$html .= $$specs{'txtImposition'.$qty_index}.'out ';
		$html .= '<span class="RunStyle '.$$specs{"PrintingType$qty_index"}.' '.$$specs{'ddmRunStyle'.$qty_index}.'">';
		if ( $$specs{"PrintingType$qty_index"} eq 'Digital' ) {
			$html .= 'Digital';
		} else {
			$html .= $$specs{'ddmRunStyle'.$qty_index} eq 'Web' ? $$specs{'StockWidth'.$qty_index} . '" Web' : ssi::html_escape($$specs{'ddmRunStyle'.$qty_index}) ;
		} # end if
		$html .= '</span>';
	
		$html .= ' ' . $$specs{"Versions$qty_index"}.' versions' if $$specs{versions};
		$html .= ' on '. $$specs{'ddmPress'.$qty_index} if $$specs{'ddmPress'.$qty_index}; # and $openprint::User->email() =~ /^iconnor/;

		my $plate_changes = 0;
		if ( $$specs{Group} and $$printing_specs{"txtPlateChangeQuantity-$$specs{Group}"} ) {
			$plate_changes += $$printing_specs{"txtPlateChangeQuantity-$$specs{Group}"};
			$html .= sprintf(' with %d %s plate change%s',
					@$printing_specs{"txtPlateChangeQuantity-$$specs{Group}","PlateChangeType-$$specs{Group}"},
					( $$printing_specs{"txtPlateChangeQuantity-$$specs{Group}"} == 1 ? '' : 's')
					);
		}
		if ( $$specs{'txtPlateChangeQuantity'.$qty_index} ) {
			$plate_changes += $$specs{'txtPlateChangeQuantity'.$qty_index};
			$html .= sprintf(' with %d %s plate change%s',
					@$specs{'txtPlateChangeQuantity'.$qty_index,'PlateChangeType'.$qty_index},
					( $$specs{"txtPlateChangeQuantity$qty_index"} == 1 ? '' : 's' )
					);
		}
		if ( $plate_changes ) {
			$html .= sprintf(' = %d plates', $$specs{'txtPlateQuantity'.$qty_index} );
		}

#if ( 1 ) {
# Have Stock summary line now
		if ( $$services{NoPrinting} ) {
			$html .= sprintf(' %s" x %s"', @$specs{'StockWidth'.$qty_index,'StockHeight'.$qty_index});
		} else {
			#$html .= ' Stock Qty: ' . $$specs{'txtPressSheetQty'.$qty_index};
			if ( $$specs{'StockType'.$qty_index} eq 'Roll' ) {
				if ( $$specs{'ddmRunStyle'.$qty_index} ne 'Web' ) {
					$html .= sprintf( ' on %s" Roll.	Cut Off: %s"',	1*$$specs{'StockWidth'.$qty_index},1*$$specs{'StockHeight'.$qty_index});
				} # end if
			} else {
				$html .= sprintf(' on %s" x %s"', 1*$$specs{'StockWidth'.$qty_index}, 1*$$specs{'StockHeight'.$qty_index});
			} # end if
		} # end if
		if ( 0 and sets::isin( $openprint::session{user_type}, [ 'E', 'A' ] ) ) {
			if ( $$services{Folding} and @{$$services{Folding}} ) {
				$html .= "\nfolded " . openprint::Estimating::Folding::signature_summary( $Project, $$services{Folding}[0], undef, $qty_index, $service_index, undef );
			} # end if
			if ( $$services{Scoring} and @{$$services{Scoring}} ) {
				my $scoring_specs = openprint::service::get_specs_ref( $Project, $$services{Scoring}[0] );
				my $Paper = openprint::Paper::load_from_signature( $Project, $specs, $qty_index );
				if ( openprint::Estimating::Scoring::signature_needs( $Project, $scoring_specs, $specs, $Paper ) ) {
					$html .= "\nscored " . openprint::Estimating::Scoring::signature_summary( $Project, $$services{Scoring}[0], undef, $qty_index, $service_index, undef );
				} # end if
			} # end if
		} # end if
		if ( (!$$specs{'MatchGrain'.$qty_index}) or ( $$specs{'MatchGrain'.$qty_index} ne 'Y') ) {
			$html .= '<br/>Do not match grain<br/>';
		} # end if
		if ( ! $$specs{"Runspeed$qty_index"} ) {
			$html .= '<span class="error"><br/>No runspeed!</span>';
		}

		return $html;
	} else { # ! qty_index
		my $dimensions = '';
		if ( $$specs{txtSignatureType} ) {
if ( 0 ) {
			if ( $$specs{txtSignatureType} eq 'Cover Pages' ) {
				$dimensions .= sprintf( '%s&quot;x%s&quot; ', @$specs{'txtFinalWidth','txtFinalHeight'});
			} else {
				$dimensions .= sprintf( '%s&quot;x%s&quot; ', @$printing_specs{'txtFinalWidth','txtFinalHeight'});
			} # end if
} else {
				$dimensions .= sprintf( '%s&quot;x%s&quot; -> %s&quot;x%s&quot; ',
						@$specs{'txtWidth','txtHeight','txtFinalWidth','txtFinalHeight'});
}
		} elsif ( ( $$specs{txtFinalWidth} and $$specs{txtFinalHeight} ) and ( $$specs{txtFinalWidth} != $$specs{txtWidth} or $$specs{txtFinalHeight} != $$specs{txtHeight} ) ) {
			if ( $$services{Folding} and @{$$services{Folding}} ) {
				$dimensions .= sprintf( '%s&quot;x%s&quot; folded to %s&quot;x%s&quot; ',
						@$specs{'txtWidth','txtHeight','txtFinalWidth','txtFinalHeight'});
			} elsif ( $$services{Sewing} and @{$$services{Sewing}} ) {
				$dimensions .= sprintf( '%s&quot;x%s&quot; hemmed to %s&quot;x%s&quot; ',
						@$specs{'txtWidth','txtHeight','txtFinalWidth','txtFinalHeight'});
			} else {
				$dimensions .= sprintf( '%s&quot;x%s&quot; -> %s&quot;x%s&quot; ',
						@$specs{'txtWidth','txtHeight','txtFinalWidth','txtFinalHeight'});
			} # end if
		} else {
			$dimensions .= sprintf( '%s&quot;x%s&quot; ', @$specs{'txtWidth','txtHeight'});
		} # end if

		my $string = join(' ', ($$specs{txtServiceDescription} ? $$specs{txtServiceDescription} . ':' : ''), $dimensions );
		if ( ! $$services{NoPrinting} ) {
			$string .= get_colour_description($Project, $specs) . ' on '.get_stock_description($specs);
    }

		if ( $$specs{pages_supplied} and ( $$specs{pages_supplied} eq 'Y' ) ) {
			$string .= ' pages supplied by customer as ';
			if ( $$specs{supplied_format} eq 'Sheets' ) {
				$string .= ' flat sheets.';
			} elsif ( $$specs{supplied_format} eq 'Folded' ) {
				$string .= ' folded pages.';
			} # end if
		} # end if
		if ( $Project->Type()->name() eq 'PresentationFolders' ) {
			my @pockets = map { $$specs{"chkPocket$_"} ? lc $_ : () } ( 'Left', 'Center', 'Right' );
			$string .= '<br/>' . $$specs{rdbPanels} . ' panels ' . ( $$specs{PocketSize} ? $$specs{PocketSize} . '&quot; ' : '' ) . ' pocket'.(@pockets == 1 ? '' : 's').' on ' . join( ',', @pockets );
		} # end if
		my $special_string = join(', ',
				( $$specs{OverrideAddGrip} ? ' no image in grip or sides' : () ),
				( ($$specs{rdbColourBar} and ( $$specs{rdbColourBar} eq 'N' ) ) ? ' no colour bar' : () ),
				( ( $$specs{BleedLeft} and $$specs{BleedRight} and $$specs{BleedTop} and $$specs{BleedBottom} ) ? '' : 'no bleed on ' . join(', ', map { $$specs{"Bleed$_"} ? '': $_ } ( 'Top','Bottom','Left','Right' ) ) ),
				( (exists $$specs{txtCropMarkSpace} ) ? () : 'no crop marks' ),
		);
    $string .= '<br/>' . $special_string if $special_string;
		if ( $$specs{PressApproval} and ( $$specs{PressApproval} eq 'Y' ) ) {
			$string .= '<br/>Customer wants press approval';
		}
		return $string.'<br/>';
	} # end if qty_index
} # end sub summary

sub get_stock_description {
  my $specs = shift;
  my $string = join('',
    ( ( $$specs{rdbSuppliedStock} and ( $$specs{rdbSuppliedStock} eq 'Y' ) ) ? '<b>Customer Supplied</b>' : '' ),
    ( ( $$specs{rdbSpecificStock} and ( $$specs{rdbSpecificStock} eq 'Y' ) ) ? '<b>Custom:</b>' .
      join(', ', @$specs{'txtSpecificStockBrand','txtSpecificStockFinish','txtSpecificStockColour','txtSpecificStockWeight'} ) :
      join(', ', @$specs{'ddmStockBrand','ddmStockFinish','ddmStockColour','ddmStockWeight'} ),
    ) );

  if ( $openprint::config{Show_Stock_Calliper} ne 'N' ) {
    if ( ! ( $$specs{ddmStockWeight} =~ /([\d\.]+)\s*PT/ ) ) {
      if ( $$specs{txtSpecificStockCalliper} ) {
        $string .= ' ' . ($$specs{txtSpecificStockCalliper} * 1000).'PT';
      } # end if
    } else {
      my $c = $$specs{txtSpecificStockCalliper}*1000;
      if ( $1 ne $c ) {
        $log->debug("$1 is !- $$specs{txtSpecificStockCalliper} c1($c)");
        $string .= ' (' .$c.'PT)';
      } # end if
    } # end if
  } # end if show stock calliper
  $string .= ' ' . int($$specs{txtStockGSM}).'gsm' if $openprint::config{Show_Stock_GSM} ne 'N';
  return $string;
}

sub save {
	my ( $p_id, $s_id, $param ) = @_;
	my $Project = new openprint::Project( $p_id );
	my $services = $Project->services();
$log->debug("Printing::save");

	if ( $$services{Padding} ) {
		foreach my $padding_id ( @{$$services{Padding}} ) {
			openprint::service::insert_service_spec( $log, $openprint::dbh, $p_id, $padding_id, 'PageQuantity', $$param{PageQuantity} );
		} # end foreach
	} # end if adding
	if ( $$services{Grommeting} ) {
		foreach my $s_id ( @{$$services{Grommeting}} ) {
			openprint::service::insert_service_spec( $log, $openprint::dbh, $p_id, $s_id, 'Quantity', $$param{grommets} );
		} # end foreach
	} # end if
	if ( $$param{hemmed} and ( $$param{hemmed} eq 'Y' ) ) {
		if ( ! $$services{Sewing} ) {
			$$services{Sewing}[0] = $Project->add_service( 'Sewing' );
		}
		foreach my $s_id ( @{$$services{Sewing}} ) {
			foreach my $spec ( 'EdgeLeft','EdgeRight','EdgeTop','EdgeBottom','HemWidth' ) {
				openprint::service::insert_service_spec( $log, $openprint::dbh, $p_id, $s_id, $spec, $$param{$spec} );
			} # end foreach
		} # end foreach
	} # end if hemmed

	if ( $$services{''} and @{$$services{''}} ) {
		my $project_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );

    my $sig_specs = openprint::service::get_specs_ref( $Project, $s_id );
    if ( $$sig_specs{Group} ) {
      $log->debug("Group $$sig_specs{Group}");

      # Save things like colours, stock, etc.
      foreach my $key ( @openprint::Estimating::MultiPage::signature_variables ) {
        $log->debug("Saving to multipage $key$$sig_specs{Group} => $$param{$key}");
        if ( exists $$param{$key} ) {
          openprint::service::insert_service_spec( $log, $openprint::dbh, $$Project{id}, $$services{''}[0], $key.$$sig_specs{Group}, $$param{$key} );
        }
      } # end foreach key

      # So, if we just edited NOT the first sig in the group, and it's a bit different, so create a new group?
      my @sigs = sort { $a <=> $b } $Project->signatures({ Group=>$$sig_specs{Group} });
      if ( $s_id != $sigs[0] ) {
        $log->debug("Not first");
        my $first_sig_specs = openprint::service::get_specs_ref( $Project, $sigs[0] );
        if ( ! compare_signatures_no_results( $Project, $first_sig_specs, $sig_specs ) ) {
          # Split into a new group
          $_ = q{SELECT MAX(strValue::integer) FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND strName='Group'};
          my ( $new_group ) = sql::execute( $log, $dbh, $_, $Project->id() );
          $new_group += 1;
          $log->debug("New group is $new_group");
          my $pages = $$sig_specs{txtSpreadSize};
          foreach my $qty_index ( $Project->quantity_indexes() ) {
            $pages = $$sig_specs{"PageQuantity$qty_index"} if $$sig_specs{"PageQuantity$qty_index"} > $pages;
          } # end foreach
          my $new_pages = $$first_sig_specs{GroupPageQuantity}-$pages;

          $log->debug("Old pages $$first_sig_specs{GroupPageQuantity} - this pages: $pages ");
          openprint::service::insert_service_spec( $log, $openprint::dbh, $p_id, $s_id, 'GroupPageQuantity', $pages );

          foreach my $key ( @openprint::Estimating::MultiPage::signature_variables ) {
            openprint::service::insert_service_spec( $log, $openprint::dbh, $p_id, $$services{''}[0], $key.$new_group, $$project_specs{$key.$$sig_specs{Group}} );
          }	
          openprint::service::insert_service_spec( $log, $openprint::dbh, $p_id, $$services{''}[0], 'GroupPageQuantity'.$$sig_specs{Group}, $$first_sig_specs{GroupPageQuantity}-$pages );
          openprint::service::insert_service_spec( $log, $openprint::dbh, $p_id, $$services{''}[0], 'GroupPageQuantity'.$new_group, $pages );
          openprint::service::insert_service_spec( $log, $openprint::dbh, $p_id, $$services{''}[0], 'OverrideGroupPageQuantity'.$new_group, 'Y' );

          foreach my $sig_id ( @sigs ) {
            next if $sig_id == $s_id;
            openprint::service::insert_service_spec( $log, $openprint::dbh, $p_id, $sig_id, 'GroupPageQuantity', $new_pages );
          } # end foreach sig_id
          openprint::service::insert_service_spec( $log, $openprint::dbh, $p_id, $s_id, 'Group', $new_group );
        } # end if
      } # end if not the first sig in the group

    } else {
      $log->debug("No group");
    } # end if Group
  } else {
    $log->error("No project service in project $$Project{id}");
  } # end if
} # end sub save

sub get_colour_description_no_coverage {
  my ( $Project, $specs ) = @_;

  my @front_coatings = ();
  my $front_pms = 0;

  my @back_coatings = ();
  my $coatings = '';
  my $back_pms = 0;

  my $side = 'SideOne';
  my $ProjectTypeName = $Project->Type()->name();

  foreach my $k ( keys %$specs ) {
    if ( my ( $index ) = $k =~ /^chkColourCoating(\d+)$side/ ) {
      next if ! $$specs{"chkColourCoating$index$side"};

      my $type = $$specs{"ColourCoatingType$index$side"};
      next if ! $type;
      next if $$specs{"chkColourCoatingColour$index$side"} and ( $$specs{"chkColourCoatingColour$index$side"} eq 'None' );
      if ( $type =~ /Aqueous/ or $type =~ /Varnish/ or $type =~ /UV/ ) {
        if ( $$specs{"ColourCoatingCoverage$index$side"} != 100) {
          push @front_coatings, 'Spot '. $$specs{"ColourCoatingType$index$side"}. ' @ '.$$specs{"ColourCoatingCoverage$index$side"} .'%';
        } else {
          push @front_coatings , $$specs{"ColourCoatingType$index$side"};
        }
      } elsif ( $type =~ /PMS/i ) {
        $front_pms += 1;
        $log->debug("Adding PMS for $type chkColourCoating$index$side");
      } else {
        if ( $$specs{"ColourCoatingCoverage$index$side"} != 100) {
          push @front_coatings, 'Spot '. $$specs{"ColourCoatingType$index$side"}. ' @ '.$$specs{"ColourCoatingCoverage$index$side"} .'%';
        } else {
          push @front_coatings, $$specs{"ColourCoatingType$index$side"}; 	#line added to show other types june-18-2008
        }
      } # end if
    } # end if
  } # end foreach

  if ( $front_pms ) {
    unshift @front_coatings, $front_pms.'PMS';
  } # end if

  unshift @front_coatings, map { $$specs{'chk'.$_.$side} ? $_ : () } ( 'Cyan','Magenta','Yellow','Black' );
  if ( $$specs{'chkProcessColour'.$side} ) {
    unshift @front_coatings, '4C'; 
  }

  if ( (defined $$specs{sides_the_same}) and ( $$specs{sides_the_same} eq 'Y' ) ) {
    @back_coatings = @front_coatings;
    $back_pms = $front_pms;
    $coatings .= ' back the same as front';
  } elsif ((defined $$specs{side_link}) and $$specs{side_link}) {
    @back_coatings = @front_coatings;
    $back_pms = $front_pms;
  } else {
		$side = 'SideTwo';

		foreach my $k ( keys %$specs ) {
			if ( my ( $index ) = $k =~ /^chkColourCoating(\d+)$side/ ) {
				next if ! $$specs{"chkColourCoating$index$side"};
				my $type = $$specs{"ColourCoatingType$index$side"};
				next if ! $type;
				next if $$specs{"chkColourCoatingColour$index$side"} and ( $$specs{"chkColourCoatingColour$index$side"} eq 'None' );

				if ( $type =~ /Aqueous/ or $type =~ /Varnish/ or $type =~ /UV/ ) {
#Changes made on june-19-2008
#						$back_coatings .= '+'.$$specs{"ColourCoatingColour$index$side"};
					push @back_coatings, $$specs{"ColourCoatingType$index$side"};
				} elsif ( $type =~ /PMS/i ) {
					$back_pms += 1;
				} else {
					push @back_coatings, $$specs{"ColourCoatingType$index$side"};
				} # end if
			} # end if
		} # end foreach
		if ( $back_pms ) {
			unshift @back_coatings, $back_pms.'PMS';
		} # end if
		unshift @back_coatings, map { $$specs{'chk'.$_.$side} ? $_ : () } ( 'Cyan','Magenta','Yellow','Black' );
		if ( $$specs{'chkProcessColour'.$side} ) {
			unshift @back_coatings, '4C';
		} # end if Process
	} # end if
	return join('+', @front_coatings).'/'.(@back_coatings?join('+',@back_coatings):'0').' ' . $coatings;
} # end sub get_colour_description_no_coverage

sub get_colour_description {
	my ( $Project, $specs ) = @_;

	my @front_coatings = ();
	my $front_pms = 0;

	my @back_coatings = ();
	my $coatings = '';
	my $back_pms = 0;

	my $side = 'SideOne';
	my $ProjectTypeName = $Project->Type()->name();
	my $CMYK_Ink_Coverage = $openprint::config{'DefaultInkCoverage'.$ProjectTypeName} ?
		$openprint::config{'DefaultInkCoverage'.$ProjectTypeName} : $openprint::config{DefaultInkCoverage};

	foreach my $k ( keys %$specs ) {
		if ( my ( $index ) = $k =~ /^chkColourCoating(\d+)$side/ ) {
			next if ! $$specs{"chkColourCoating$index$side"};

			my $type = $$specs{"ColourCoatingType$index$side"};
			next if ! $type;
			next if $$specs{"chkColourCoatingColour$index$side"} and ( $$specs{"chkColourCoatingColour$index$side"} eq 'None' );
			if ( $type =~ /Aqueous/ or $type =~ /Varnish/ or $type =~ /UV/ ) {
        if ( $$specs{"ColourCoatingCoverage$index$side"} != 100) {
          push @front_coatings, 'Spot '. $$specs{"ColourCoatingType$index$side"}. ' @ '.$$specs{"ColourCoatingCoverage$index$side"} .'%';
        } else {
          push @front_coatings , $$specs{"ColourCoatingType$index$side"};
        }
			} elsif ( $type =~ /PMS/i ) {
				$front_pms += 1;
$log->debug("Adding PMS for $type chkColourCoating$index$side");
			} else {
				push @front_coatings, $$specs{"ColourCoatingType$index$side"}; 	#line added to show other types june-18-2008
			} # end if
		} # end if
	} # end foreach

	if ( $front_pms ) {
		unshift @front_coatings, $front_pms.'PMS';
	} # end if

	unshift @front_coatings, map { $$specs{'chk'.$_.$side} ? $_ . ( $$specs{$_.'Spot'.$side.'Coverage'} != $CMYK_Ink_Coverage ? ' ' . $$specs{$_.'Spot'.$side.'Coverage'}.'%' : '')    : () } ( 'Cyan','Magenta','Yellow','Black' );
	if ( $$specs{'chkProcessColour'.$side} ) {
		unshift @front_coatings, join(' ', '4C', 
				map { 
				( $$specs{$_.$side.'Coverage'} != $CMYK_Ink_Coverage ) ?
				'<span class="warning">'. $process_colours_short{$_}.$$specs{$_.$side.'Coverage'}.'%</span>'
				: ()
				} ('Cyan','Magenta','Yellow','Black')
				);
	}

	if ( (defined $$specs{sides_the_same}) and ( $$specs{sides_the_same} eq 'Y' ) ) {
		@back_coatings = @front_coatings;
		$back_pms = $front_pms;
		$coatings .= ' back the same as front';
  } elsif ((defined $$specs{side_link}) and $$specs{side_link}) {
    @back_coatings = @front_coatings;
    $back_pms = $front_pms;
	} else {
		$side = 'SideTwo';

		foreach my $k ( keys %$specs ) {
			if ( my ( $index ) = $k =~ /^chkColourCoating(\d+)$side/ ) {
				next if ! $$specs{"chkColourCoating$index$side"};
				my $type = $$specs{"ColourCoatingType$index$side"};
				next if ! $type;
				next if $$specs{"chkColourCoatingColour$index$side"} and ( $$specs{"chkColourCoatingColour$index$side"} eq 'None' );

				if ( $type =~ /Aqueous/ or $type =~ /Varnish/ or $type =~ /UV/ ) {
          if ( $$specs{"ColourCoatingCoverage$index$side"} != 100) {
            push @back_coatings, 'Spot '. $$specs{"ColourCoatingType$index$side"}. ' @ '.$$specs{"ColourCoatingCoverage$index$side"} .'%';
          } else {
            push @back_coatings, $$specs{"ColourCoatingType$index$side"};
          }
				} elsif ( $type =~ /PMS/i ) {
					$back_pms += 1;
				} else {
					push @back_coatings, $$specs{"ColourCoatingType$index$side"};
				} # end if
			} # end if
		} # end foreach
		if ( $back_pms ) {
			unshift @back_coatings, $back_pms.'PMS';
		} # end if
		unshift @back_coatings, map { $$specs{'chk'.$_.$side} ? $_ . ( $$specs{$_.'Spot'.$side.'Coverage'} != $CMYK_Ink_Coverage ? ' ' . $$specs{$_.'Spot'.$side.'Coverage'}.'%' : '')    : () } ( 'Cyan','Magenta','Yellow','Black' );
		if ( $$specs{'chkProcessColour'.$side} ) {
			unshift @back_coatings, join(' ', '4C',
				map {
				( $$specs{$_.$side.'Coverage'} != $CMYK_Ink_Coverage ) ?
				'<span class="warning">' . $process_colours_short{$_}.$$specs{$_.$side.'Coverage'}.'%</span>'
				: ()
				} ('Cyan','Magenta','Yellow','Black')
				);
		} # end if Process
	} # end if
	return join('+', @front_coatings).'/'.(@back_coatings?join('+',@back_coatings):'0').' ' . $coatings;
} # end sub get_colour_description

sub filter_coatings_from_colours {
	my @c;
	foreach my $c ( @{$_[0]} ) {
		if ( !( 
					#($$c{name} =~ /Varnish/i) or
 ($$c{name} =~ /Aqueous/i) or ($$c{name} =~ /UV/i)
				) ) {
			push @c, $c;
		} # end if
	} # end foreach c
	return @c;
} # end sub filter_coatings_from_colours

sub get_printing_types {
	my ( $Project, $service_index, $printing_specs, $specs, $qty_index, $available_printingtypes, $cover_imposition ) = @_;
	# Generally only care if having different signature groups.  
	return if ! $$specs{txtSignatureType};
	my $results = undef;

	my %available_types = map { $_, $_ } @{$available_printingtypes};

	$log->debug('available: ' . join(',', @{$available_printingtypes}) ) if DEBUG;
	if ( $$printing_specs{PrintingType} and $available_types{$$printing_specs{PrintingType}} ) {
		$results = [ $$printing_specs{PrintingType} ];
$log->debug('PT: ' . join(',', @{$$specs{PrintingTypes}} ) ) if DEBUG;
	} else {

		if ( $$specs{txtSignatureType} eq 'Cover Pages' ) {
# FIgure out printing types
#$log->debug("We are cover");
			# If this is the cover, then we should ignore the interior pages, except for if there is an override.
			foreach my $index ( $Project->signatures({ type =>'Interior Pages' }) ) {
				my $sig_specs = openprint::service::get_specs_ref($Project, $index);
				if ( $$sig_specs{'PrintingType'.$qty_index} and $available_types{ $$sig_specs{'PrintingType'.$qty_index} } and ( $$sig_specs{'OverridePrintingType'.$qty_index} and ( $$sig_specs{'OverridePrintingType'.$qty_index} eq 'Y' ) ) ) {
					if ( $$sig_specs{'PrintingType'.$qty_index} eq 'Digital' ) {
						$results = ['Digital', 'Sheetfed'];
					} elsif ( $$sig_specs{'PrintingType'.$qty_index} eq 'Waterless' ) {
						$results = [ 'Waterless', 'Offset' ];
					} elsif ( $$sig_specs{'PrintingType'.$qty_index} eq 'Offset' ) {
						$results = ['Offset', 'Waterless'];
					} elsif ( $$sig_specs{'PrintingType'.$qty_index} eq 'Sheetfed' ) {
						$results = ['Sheetfed', 'Web'];
					} elsif ( $$sig_specs{'PrintingType'.$qty_index} eq 'Web' ) {
						$results = ['Sheetfed', 'Web'];
					} else {
						$log->warn('Unknown printing type: '.$$sig_specs{'PrintingType'.$qty_index} );
					} # end if
				} # end if
$openprint::log->debug("get printing type from sig $index " . $$sig_specs{'PrintingType'.$qty_index} . ($results ? join(',',@$results) : ' none'));
				last if $results;
			} # end foreach

		} elsif ( $$specs{txtSignatureType} eq 'Interior Pages' ) {
# if the cover is digital, then we need digital
# if another interior spread is digital, then we need digital
# if the cover is offset, then we need offset
# if the cover is waterless, then we can do waterless, or offset
$log->debug("We are interior $service_index") if DEBUG;
			#foreach my $index ( sort { $a <=> $b } $Project->signatures({Group=>$$specs{Group}}) ) {
			my @sigs = $Project->signatures({type=>'Interior Pages'});
			return if @sigs <= 1;

			foreach my $index ( sort { $a <=> $b } @sigs ) {
$log->debug("Looking at interior sig $index == $service_index") if DEBUG;

				next if $index == $service_index;
				my $sig_specs = openprint::service::get_specs_ref($Project, $index);
				if ( ! $$sig_specs{SignatureIndex} ) {
					$log->error("Next because no SignatureIndex at interior sig $index == $service_index");
					next;
				}
				next if ( ( $index > $service_index ) and ( (!$$sig_specs{'OverridePrintingType'.$qty_index}) or ( $$sig_specs{'OverridePrintingType'.$qty_index} ne 'Y' ) ) );
$log->debug("Getting prnting types from $$sig_specs{SignatureIndex} group: $$sig_specs{Group}") if DEBUG;

				if ( $available_types{$$sig_specs{'PrintingType'.$qty_index}} ) {
					if ( $$sig_specs{'PrintingType'.$qty_index} eq 'Digital' ) {
						$results = ['Digital'];
					} elsif ( $$sig_specs{'PrintingType'.$qty_index} eq 'Waterless' ) {
						$results = [ 'Waterless', 'Offset' ];
					} elsif ( $$sig_specs{'PrintingType'.$qty_index} eq 'Offset' ) {
						$results = ['Offset'];
					} elsif ( $$sig_specs{'PrintingType'.$qty_index} eq 'Web' ) {
						$results = ['Web'];
					} elsif ( $$sig_specs{'PrintingType'.$qty_index} eq 'Sheetfed' ) {
						$results = ['Sheetfed'];
					} else {
$log->warn("Unknown printing type in sig $$sig_specs{SignatureIndex} : " . $$sig_specs{'PrintingType'.$qty_index} );
					} # end if
				} # end if

				if ($results) {
					$log->debug("Printing Type Results: @$results") if DEBUG;
					return $results;
				} # end if
			} # end foreach interior sig index

			my $cover_type;
			if ( $cover_imposition ) {
				$cover_type = $cover_imposition->Press()->specification('Printing Type');
			} elsif ( ! ( $$specs{PrintingTypes} and $$specs{'OverridePrintingType'.$qty_index} ) ) {
				my $cover_specs;
				foreach my $index ( $Project->signatures({ type=>'Cover Pages'}) ) {
					$cover_specs = openprint::service::get_specs_ref( $Project, $index );
					last;
				} # end foreach
				if ( $cover_specs ) {
					if ( $available_types{ $$cover_specs{'PrintingType'.$qty_index} } ) {
						$cover_type = $$cover_specs{'PrintingType'.$qty_index};
					} # end if
				} # end if
			} # end if PrintingTypes
			if ( $cover_type ) {
				if ( $cover_type eq 'Digital' ) {
					$results = ['Digital', 'Sheetfed'];
				} elsif ( $cover_type eq 'Waterless' ) {
					$results = [ 'Waterless', 'Offset' ];
				} elsif ( $cover_type eq 'Offset' ) {
					$results = ['Offset'];
				} elsif ( $cover_type eq 'Web' ) {
					$results = ['Sheetfed', 'Web'];
				} elsif ( $cover_type eq 'Sheetfed' ) {
					$results = ['Sheetfed', 'Web', 'Digital'];
				} # end if
			} # end if
		} # end if Spread Type
	} # end if printing_specs{PrintingType}
  if ($results) {
		$log->debug("Printing Type Results: @$results") if DEBUG;
	}
	return $results;
} # end sub get_printing_types

 
sub has_overrides {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

	if ( $qty_index ) {
		return () if (exists $$specs{'txtUnspecifiedPageQuantity'.$qty_index} and ($$specs{'txtUnspecifiedPageQuantity'.$qty_index} <= 0 ) ) and ! $$specs{"txtImposition$qty_index"};
		return map { (defined $$specs{$_.$qty_index} and ( $$specs{$_.$qty_index} eq 'Y' ) ) ? $_ : () } @qty_override_keys;
	} else {
		return map { (defined $$specs{$_} and ( $$specs{$_} eq 'Y' ) ) ? $_ : () } @override_keys;
	} # end if
} # end sub has_overrides

sub convert_impositions {
	my ( $Project, $project, $specs, $qty_index, $impositions ) = @_;

	my $SpreadLayout = 0;
	if ( $Project->Type()->name() eq 'ScratchPads' ) {
		$SpreadLayout = 0;
	} elsif ( $$specs{txtSignatureType} ) {
		if ( ! $$project{txtSpreadSize} ) {
			$log->error("No spread size in calculate_impositions.");
			$$project{txtSpreadSize} = 4;
		} # end if
		if ( $$specs{'chkOverridePageQuantity'.$qty_index} and ( $$specs{'chkOverridePageQuantity'.$qty_index} eq 'Y' ) ) {
			$SpreadLayout = int( $$specs{'PageQuantity'.$qty_index} / $$project{txtSpreadSize} );
			$log->debug("Calcing SpreadLayout as overriden upq: $$specs{'PageQuantity'.$qty_index} / spreadsize:$$project{txtSpreadSize} = layout$SpreadLayout") if DEBUG;
		} elsif ( $$project{ProjectSpecs}{"PageQuantity-$$specs{Group}"} and ( $$project{ProjectSpecs}{"PageQuantity-$$specs{Group}"} <= $$specs{'txtUnspecifiedPageQuantity'.$qty_index} ) ) {
			$SpreadLayout = int( $$project{ProjectSpecs}{"PageQuantity-$$specs{Group}"} / $$project{txtSpreadSize} );
			$log->debug("Calcing SpreadLayout as overriden upq: ".$$project{ProjectSpecs}{"PageQuantity-$$specs{Group}"}." / spreadsize:$$project{txtSpreadSize} = layout$SpreadLayout");
		} else {
			$SpreadLayout = int( $$specs{'txtUnspecifiedPageQuantity'.$qty_index} / $$project{txtSpreadSize} );
			$log->debug("Calcing SpreadLayout as upq: $$specs{'txtUnspecifiedPageQuantity'.$qty_index} / spreadsize:$$project{txtSpreadSize} = layout$SpreadLayout") if DEBUG_FILTERING;
		} # end if
	} # end if
	if ( $SpreadLayout > 1 ) {
# ecause convert will consider all smaller spreadlayouts as well, we really only need to do this once, and can simply filter out any that are larger than we need.
		foreach my $press ( keys %$impositions ) {
			$$impositions{$press} = [ openprint::imposition::convert_impositions( $SpreadLayout, $$project{txtSpreadSize}, $$project{ProjectSpecs}{spine}, $$impositions{$press} ) ];

			if ( my $dont_do_pages = $Presses{$press}->specification('DontDoPages') ) {
        my %dont_do_pages = map { $_, $_ } split(',', $dont_do_pages);
        if ( %dont_do_pages ) {
          $$impositions{$press} = [ map { $dont_do_pages{$$_{pages}} ? () : $_ } @{$$impositions{$press}} ];
        } # end if
      } # end ifo

		} # end foreach press
	} # end if spreadylayout

}

sub setup_counts {
	my ( $Project, $service_index, $specs, $qty_index, $project, $previous_forms_cache, $PaperCounts, $PlateCounts ) = @_;

	foreach my $index ( $Project->signatures({ sort=>1 }) ) {
		if ( $index >= $service_index ) {
			$log->debug("setup_counts: Next sig $index >= $service_index") if DEBUG;
			next;
		}
# Get plates in each previous signature, so we can get qty discounts
		my $sig_specs = openprint::service::get_specs_ref($Project, $index);
		if ( $$sig_specs{pages_supplied} and ( $$sig_specs{pages_supplied} eq 'Y') ) {
			$log->debug("skipping sig $$sig_specs{SignatureIndex} in setup_counts because pages supplied = $$sig_specs{pages_supplied}") if DEBUG;
			next;
		} elsif ( $$specs{txtSignatureType} eq 'Cover Pages' and $$sig_specs{txtSignatureType} ne 'Cover Pages' ) {
			$log->debug('We are cover pages but sig is not') if DEBUG;
			next;
		} 
		if ( DEBUG ) {
			$log->debug("Not Next sig $index >= $service_index and $$specs{Group} == $$sig_specs{Group} $$sig_specs{txtSignatureType}");
		} # end if
		$$PlateCounts{$$sig_specs{'PlateID'.$qty_index}} += $$sig_specs{'txtPlateQuantity'.$qty_index} if $$sig_specs{'txtPlateQuantity'.$qty_index};
		$$PlateCounts{'Blank'.$$sig_specs{'PlateID'.$qty_index}} += $$sig_specs{'BlankPlateQuantity'.$qty_index} if $$sig_specs{'BlankPlateQuantity'.$qty_index};
		$$project{roll2sheetcharged} = 1 if $$sig_specs{'Roll2SheetCharge'.$qty_index};
		$$project{stocksetupcharged} = 1 if $$sig_specs{'StockSetupCharge'.$qty_index};
		my $hash_key = join(',', @$sig_specs{'ddmPress'.$qty_index,'ddmRunStyle'.$qty_index,'PageQuantity'.$qty_index,'txtImposition'.$qty_index,'hdnImpositionColumns'.$qty_index} );
		$$previous_forms_cache{$hash_key} += 1;
		if ( $$sig_specs{'StockQuantity'.$qty_index} ) {
			my $Paper = openprint::Paper::load_from_signature( $Project, $sig_specs, $qty_index );
			if ( $Paper->width() ) {
				$$PaperCounts{$Paper->id_string()} += $$sig_specs{'StockQuantity'.$qty_index};
				$Papers{$Paper->id_string()} = $Paper if ! $Papers{$Paper->id_string()};
			} else {
				$log->debug("Loaded paper with no width and height from sig $index " . $Paper->to_string() );
			}
		} else {
			$log->debug("No stock quantity for form $$sig_specs{SignatureIndex}");
		} # end if
	} # end foreach $index

	if ( DEBUG ) {
		$log->debug('Stock counts before calc: ');
		foreach my $k ( sort keys %{$PaperCounts} ) {
			$log->debug("Stock counts before calc: $k $$PaperCounts{$k}");
		}
	}
	if ( ! $$project{stocksetupcharged} ) {
# Check to see if there even are any stock setup prices.	If not, don't both estimating them later
		if ( ! openprint::PaperPrice->find(service=>'Setup') ) {
			$$project{stocksetupcharged} = 1;
		} # end if
	} # end if
} # end sub setup_counts
1;
__END__
