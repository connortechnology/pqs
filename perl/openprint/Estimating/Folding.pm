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

package openprint::Estimating::Folding;
use strict;
use warnings;

use vars qw( %config $log $dbh %ServicePrices @folds %fold_types );

*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
use Data::Dumper;

require POSIX;
require Math::Round;
require openprint::Project;
require openprint::service;
require openprint::ServiceType;
use openprint::Imposition;
require openprint::Estimating::Perforating;
require openprint::Estimating::Collating;

use constant DEBUG => 0;
use constant DEBUG_NEEDS => 0;

my %ServicePrices = (
  FoldingMinimumCharge => {},
  '(.*)MakeReady' => { units => [ '', 'once', 'per form', 'per hour', 'per imposition' ] },
  'Folding' => { units=> ['per hour', 'per lb','per m']},
  '(.*)Fold$' => { units=> ['per hour', 'per lb','per m']},
);
my %Specifications = (
  'Folding Capable' => { values=>['Y','N','When PerfectBound', 'For Pocket Folders', 'When Stitching','When Printing'] },
  'Folding Orientation' => { value=>['Portrait','Landscape'] },
  'Folding MakeReadyTime' => { units => 'minutes' },
  'Folding Runspeed' => {},
  '1out Required Bleed' => {},
  '2out Required Bleed' => {},
  '3out Required Bleed' => {},
  '4out Required Bleed' => {},
  'Maximum Feed Width' => { units => 'inches' }
);

sub ServicePriceConfiguration {
  my $name = shift;
  #$openprint::log->debug("Finding for $name");
  #$openprint::log->debug( Data::Dumper::Dumper(\%ServicePrices));
  return $ServicePrices{$name} if $ServicePrices{$name};
  foreach my $key (keys %ServicePrices) {
    #$openprint::log->debug("Trying $name =~ $key/");
    return $ServicePrices{$key} if ($name =~ /$key/i);
  }
  #$openprint::log->debug("Not found for ($name)");
  return undef;
}
sub SpecificationConfiguration {
  return $Specifications{shift};
}

my @equipment;
my @stitchers;
my %Services;

my @variables = (
	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
	'txtPrice1', 'txtPrice2', 'txtPrice3',
	'Markup1', 'Markup2', 'Markup3',
	'MPrice1', 'MPrice2', 'MPrice3',
	'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
	'txtRunTime1', 'txtRunTime2', 'txtRunTime3',
	'alert',
	);

sub variables {
	my @v = @variables;
	my ( $p_id, $s_id, $old_specs, $specs ) = @_;

	my $Project = new openprint::Project( $p_id );
	foreach my $s_s_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
		my $form = $$sig_specs{SignatureIndex};
		foreach my $qty_index ( $Project->quantity_indexes() ) {
			push @v, (
					"chkOverrideEquipment-$form-$qty_index",
					"ddmEquipment-$form-$qty_index",
					"chkOverrideFold-$form-$qty_index",
					"chkOverrideLimits-$form-$qty_index",
					"Price-$form-$qty_index",
					);
			foreach my $fold_index ( 1 .. 4 ) {
				push @v, map { join('-', $_, $form, $qty_index, $fold_index ) } (
						'FoldPageQty', 'FoldQty',
						'FoldImposition', 'FoldColumns', 'FoldRows',
						'FoldPageColumns','FoldPageRows',
						'FoldType', 'FoldFolds', 'FoldAngles',
						'FoldRunspeed', 'FoldImpressions',
						'OverrideRunspeed',
				);
			} # end foreach
		} # end foreach qty_index
	} # end foreach signature

	return @v;
} # end sub variables

my @no_outputs = (
	'ProjectIndex','ServiceIndex',
	'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
	'ServiceType',
);

sub no_outputs {
	my ( $p_id, $s_id, $outgoing_specs, $incoming_specs ) = @_;
	my @v = @no_outputs;

	my $Project = new openprint::Project( $p_id );
	foreach my $s_s_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
		my $form = $$sig_specs{SignatureIndex};
		foreach my $qty_index ( $Project->quantity_indexes() ) {
			if ( $$outgoing_specs{"chkOverrideFold-$form-$qty_index"} and ( $$outgoing_specs{"chkOverrideFold-$form-$qty_index"} eq 'Y' ) ) {
				foreach my $fold_index ( 1 .. 4 ) {

					if ( $$incoming_specs{"FoldRunspeed-$form-$qty_index-$fold_index"} ) {
						push @v, "FoldRunspeed-$form-$qty_index-$fold_index";
					} # end if

				} # end foraech fold
			} # end if override
			if ( $$incoming_specs{"chkOverrideEquipment-$form-$qty_index"} and ( $$incoming_specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' ) ) {
				push @v, "ddmEquipment-$form-$qty_index";
			} # end if
		} # end foreach qty
	} # end foreach sig
	return @v;
} # end sub outputs
sub outputs {
} # end sub outputs

@folds = (
  'AdditionalFoldTypes',
	'2PanelFold',
	'3PanelFold',
	'3PanelZFold',
	'4PanelFold',
	'4PanelZFold',
	'5PanelFold',
	'5PanelZFold',
	'6PanelFold',
	'6PanelZFold',
	'7PanelFold',
	'7PanelZFold',
	'8PanelFold',
	'8PanelZFold',
	'SingleGateFold',
	'DoubleGateFold',
	'4PageFold',
	'6PageFold',
	'8PageFold',
	'10PageFold',
	'12PageFold',
	'12Page3PanelRollFold',
	'12Page3PanelZFold',
	'16PageFold',
	'18PageFold',
	'20PageFold',
	'24PageFold',
	'28PageFold',
	'30PageFold',
	'32PageFold',
	'36PageFold',
	'40PageFold',
	'42PageFold',
	'44PageFold',
	'48PageFold',
	'56PageFold',
	'60PageFold',
	'64PageFold',
	'72PageFold',
	'PerpendicularSoftFold',
	'ParallelSoftFold',
	'2Panel1Pocket',
	'2Panel1PocketGusset',
	'2Panel2Pocket',
	'2Panel2PocketGusset',
	'3Panel2Pocket',
	'TriFoldDoublePocket',
	'3Panel2PocketGusset',
	'MapFold',
  'Package21Fold',
  'Package30Fold',
  'Package51Fold',
  'Package6Fold',
  'Package62Fold',
  'Package64Fold',
);


%fold_types = (
	'2PanelFold'=> '2 Panel Fold',
	'3PanelFold'=> '3 Panel Fold',
	'3PanelZFold'=> '3 Panel Z Fold',
	'4PanelFold'=> '4 Panel Fold',
	'4PanelZFold'=> '4 Panel Z Fold',
	'5PanelFold'=> '5 Panel Fold',
	'5PanelZFold'=> '5 Panel Z Fold',
	'6PanelFold'=> '6 Panel Fold',
	'6PanelZFold'=> '6 Panel Z Fold',
	'7PanelFold'=> '7 Panel Fold',
	'7PanelZFold'=> '7 Panel Z Fold',
	'8PanelFold'=> '8 Panel Fold',
	'8PanelZFold'=> '8 Panel Z Fold',
	'SingleGateFold'=> 'Single Gate Fold',
	'DoubleGateFold'=> 'Double Gate Fold',
	'4PageFold'=> '4 Page Fold',
	'6PageFold'=> '6 Page Fold',
	'8PageFold'=> '8 Page Fold',
	'10PageFold'=> '10 Page Fold',
	'12PageFold'=> '12 Page Fold',
	'12Page3PanelRollFold'=>	'12 Page 3 Panel Roll Fold',
	'12Page3PanelZFold'=>	'12 Page 3 Panel Z Fold',
	'16PageFold'=> '16 Page Fold',
	'18PageFold'=> '18 Page Fold',
	'20PageFold'=> '20 Page Fold',
	'22PageFold'=> '22 Page Fold',
	'24PageFold'=> '24 Page Fold',
	'28PageFold'=> '28 Page Fold',
	'30PageFold'=> '30 Page Fold',
	'32PageFold'=> '32 Page Fold',
	'36PageFold'=> '36 Page Fold',
	'40PageFold'=> '40 Page Fold',
	'42PageFold'=> '42 Page Fold',
	'44PageFold'=> '44 Page Fold',
	'48PageFold'=> '48 Page Fold',
	'56PageFold'=> '56 Page Fold',
	'60PageFold'=> '60 Page Fold',
	'64PageFold'=> '64 Page Fold',
	'72PageFold'=> '72 Page Fold',
	'2Panel1Pocket'=> 'Single Pocket',
	'2Panel1PocketGusset'=> 'Single Pocket w/Gussets',
	'2Panel2Pocket'=> '2 Pocket',
	'2Panel2PocketGusset'=> '2 Pocket w/Gussets',
	'3Panel2Pocket'=> '3 Panel 2 Pocket',
	'3Panel2PocketGusset'=> '3 Panel 2 Pocket w/Gussets',
	'MapFold'=>'Map Fold',
  'Package21Fold' => 'Package 21',
  'Package30Fold' => 'Package 30',
  'Package51Fold' => 'Package 51',
  'Package6Fold' => 'Package 6',
  'Package62Fold' => 'Package 62',
  'Package64Fold' => 'Package 64',
  'AdditionalFoldTypes' => 'Additional Fold Types',
);
my %short_fold_names = (
  'AdditionalFoldTypes' => 'Adtl Fold',
	'2PanelFold', '2panel',
	'3PanelFold', '3panel',
	'3PanelZFold', '3panelZ',
	'4PanelFold', '4Panel',
	'4PanelZFold', '4PanelZ',
	'5PanelFold', '5Panel',
	'5PanelZFold', '5PanelZ',
	'6PanelFold', '6Panel',
	'6PanelZFold', '6PanelZ',
	'7PanelFold', '7Panel',
	'7PanelZFold', '7PanelZ',
	'8PanelFold', '8Panel',
	'10PanelMapFold', '10 Panel Map Fold',
	'8PanelZFold', '8PanelZ',
	'SingleGateFold', 'Single Gate Fold',
	'DoubleGateFold', 'Double Gate Fold',
	'4PageFold', '4pg',
	'6PageFold', '6pg',
	'8PageFold', '8pg',
	'10PageFold', '10pg',
	'12PageFold', '12pg',
	'12Page3PanelRollFold',	'12pg3PanelRoll',
	'12Page3PanelZFold',	'12pg3PanelZ',
	'16PageFold', '16pg',
	'18PageFold', '18pg',
	'20PageFold', '20pg',
	'22PageFold', '22pg',
	'24PageFold', '24pg',
	'28PageFold', '28pg',
	'30PageFold', '30pg',
	'32PageFold', '32pg',
	'36PageFold', '36pg',
	'40PageFold', '40pg',
	'42PageFold', '42pg',
	'44PageFold', '44pg',
	'48PageFold', '48pg',
	'56PageFold', '56pg',
	'60PageFold', '60pg',
	'64PageFold', '64pg',
	'72PageFold', '72pg',
	'2Panel1Pocket', 'Single Pocket',
	'2Panel1PocketGusset', 'Single Pocket w/Gussets',
	'2Panel2Pocket', '2 Pocket',
	'2Panel2PocketGusset', '2 Pocket w/Gussets',
	'3Panel2Pocket', '3 Panel 2 Pocket',
	'3Panel2PocketGusset', '3 Panel 2 Pocket w/Gussets',
	'MapFold','Map Fold',
  'Package21Fold' => 'Package 21',
  'Package30Fold' => 'Package 30',
  'Package51Fold' => 'Package 51',
  'Package6Fold' => 'Package 6',
  'Package62Fold' => 'Package 62',
  'Package64Fold' => 'Package 64',
);
my %short_signature_types = (
	'Interior Pages' => 'Int',
	'Cover Pages' => 'Cov',
);

sub fold_types {
} # end sub fold_types

sub signature_needs {
	my ( $Project, $specs, $qty_index ) = @_;

	if ( $Project->Type()->name() eq 'Banners' ) {
		$openprint::log->debug("Folding::signature_needs: is a banner") if DEBUG_NEEDS;
		return 0;
	} # end if

	if ( $$specs{rdbTemplateType} ) {
		if ( $$specs{rdbTemplateType} eq 'NoFold' ) {
			return 0;
		}
		if ( $fold_types{$$specs{rdbTemplateType}} ) {
			$openprint::log->warn('FOLDING NEEDED got templatetype!') if DEBUG_NEEDS;
			return 1;
		} else {
			$openprint::log->warn("FOLDING NEEDED $$specs{rdbTemplateType} $fold_types{$$specs{rdbTemplateType}}!") if DEBUG_NEEDS;
		} # end if
	}

	my $services = $Project->services();
	if ( $$services{NoBindery} ) {
		$openprint::log->debug("Folding::signature_needs: NoBidner") if DEBUG_NEEDS;
		return 0;
	} # end if
	if ( $$services{CornerStitching} ) {
		$openprint::log->debug("Folding::signature_needs: CornerStitched") if DEBUG_NEEDS;
		return 0;
	} # end if
	if ( $$services{SaddleStitching} ) {
		$openprint::log->debug("Folding::signature_needs: Stitched") if DEBUG_NEEDS;
		return 1;
	} # end if
	if ( $$specs{pages_supplied} and ($$specs{pages_supplied} eq 'Y') and ($$specs{supplied_format} eq 'Folded') ) {
		$openprint::log->debug("Folding::signature_needs: supplied pages already folded") if DEBUG_NEEDS;
		return 0;
	} # end if

	if ( 0 and $$services{''} ) {
		# Turn this off... Unbound defaults to a spreadsize of 4, so unbound should still mean folding
		my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
		if ( $$printing_specs{rdbTemplateType} eq 'Unbound' ) {
			$openprint::log->debug("Folding::signature_needs: Unbound") if DEBUG_NEEDS;
			return 0;
		} # end if
	} # end if


	if ( $$specs{txtSignatureType} ) {
		my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] ) if $$services{''}[0] and @{$$services{''}};
		if ( $$specs{txtSpreadSize} == 1 ) {
			$openprint::log->warn("Folding not needed: spreadsize==1: $$specs{txtSpreadSize}") if DEBUG_NEEDS;
			return 0;
		} # end if
		if ( $qty_index ) {
			my $page_quantity = $$specs{'PageQuantity'.$qty_index};
			if ( ( $page_quantity == 0 ) or ( $page_quantity == 2 ) ) {
				$openprint::log->warn("Folding not needed: PageQuantity: $page_quantity") if DEBUG_NEEDS;
				return 0;
			} # end if
			if ( 0 and $$printing_specs{rdbTemplateType} eq 'PlasticCoil' ) {
				# Need singltons... anything < 8pg sigs...might as well just cut them out
				if ( $page_quantity < 8 ) {
					return 0
				} # end if
			} # end if
		} else {
			foreach my $qty_index ( $Project->quantity_indexes() ) {
				my $page_quantity = $$specs{'PageQuantity'.$qty_index};
				if ( $page_quantity == 2 ) {
					$openprint::log->warn("Folding not needed: PageQuantity: $page_quantity") if DEBUG_NEEDS;
					return 0;
				} # end if
			} # end foreah qty_index
		} # end if

		$openprint::log->debug('Folding::signature_needs: book sig return 1') if DEBUG_NEEDS;
		return 1;
	} # end if

# This works for books because sigs don't have a txtFinalWidth, etc.
	if ( ($$specs{txtFinalWidth} != $$specs{txtWidth}) or ($$specs{txtFinalHeight} != $$specs{txtHeight}) ) {
		$openprint::log->warn("FOLDING NEEDED dimensions do not match!") if DEBUG_NEEDS;
		return 1;
	} # end if

	return 0;
} # end sub signature_needs

# A function that is smart enough to return true if the project needs folding, and false if it doesn't.
sub neccessary {
	my ( $Project, $Service ) = @_;

	my $ServiceType = openprint::ServiceType->find_one( type=>'Folding' );
  $openprint::log->error('NO Folding!') if !$ServiceType;

	my @blocked = $Project->Type()->blocked_services();
	if ( ( ! $ServiceType ) or sets::isin( $ServiceType->id(), \@blocked ) ) {
		$openprint::log->debug("Folding blocked: blocked: @blocked");
		return 0;
	}
	my $services = $Project->services( );

	if ( $$services{NoBindery} ) {
		$openprint::log->debug(" ** Project is marked as No bindery, Folding not needed ! ** ");
		return 0;
	} # end if
	if ( $$services{PerfectBound} ) {
		$openprint::log->debug(" ** Project is marked as PerfectBound, Folding needed ! ** ");
		return 1;
	} # end if
	if ( 0 and $$services{''} ) {
		# Turn this off... Unbound defaults to a spreadsize of 4, so unbound should still mean folding
		my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
		return 0 if $$printing_specs{rdbTemplateType} eq 'Unbound';
	} # end if

	foreach my $signature_service_index ( $Project->signatures() ) {
		my $specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
		if ( signature_needs( $Project, $specs ) ) {
			return 1;
		} # end if
	} # end foreach
	$openprint::log->debug('FOLDING NOT NEEDED!');
	return 0;
} # end sub neccessary

# Looks at the imposition, and if the width is too small for the fold, tries to pad the image until it can fold, wasting paper, but sometimes this is desireable.

sub has_overrides {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

	my @v;
	if ( $qty_index ) {
		foreach my $s_s_id ( $Project->signatures() ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
			my $form = $$sig_specs{SignatureIndex};
			push @v, "chkOverrideEquipment-$form-$qty_index" if $$specs{"chkOverrideEquipment-$form-$qty_index"};
			push @v, "chkOverrideFold-$form-$qty_index" if $$specs{"chkOverrideFold-$form-$qty_index"};
			foreach my $fold_index ( 1 .. 4 ) {
				push @v, "OverrideRunspeed-$form-$qty_index-$fold_index" if $$specs{"OverrideRunspeed-$form-$qty_index-$fold_index"} and $$specs{"OverrideRunspeed-$form-$qty_index-$fold_index"} eq 'Y';
			}
		} # end foreach
	} # end if

	return @v;
} # end sub has_overrides

sub init {
	my ( $Project, $calc_hash ) = @_;
	$Services{FoldingFoldMakeReady} = openprint::Service->find_one(name=>'FoldingFoldMakeReady');
	$Services{FoldingAngleMakeReady} = openprint::Service->find_one(name=>'FoldingAngleMakeReady');
}

# Finds the different ways to run the job, and returns different impositions
sub impositions {
	my ( $Project, $Imposition, $specs, $sig_specs, $qty_index ) = @_;

	my @imps = ( $Imposition );

	my $services = $Project->services();
	my $Paper = $Imposition->Paper();

	my %find = (
			pages					=>	$Imposition->pages(),
			page_column		=>	$Imposition->page_columns(),
			page_rows			=>	$Imposition->page_rows(),
			page_width		=>	$Imposition->page_width(),
			page_height		=>	$Imposition->page_height(),
			spine_direction	=>	$openprint::Imposition::Orientations{$$Imposition{spine_direction}},
			grain_direction	=>	$Imposition->grain_direction(),
			stitching		=>	($$services{SaddleStitching} or $$services{LoopStitching}) ? 1 : 0,
			perfectbind		=>	$$services{PerfectBound} ? 1 : 0,
			spinepaste		=>	$$services{SpinePaste} ? 1 : 0,
			gsm				=>	$Paper->gsm(),
			imposition		=>	$$Imposition{imposition},
			columns			=>	$$Imposition{columns},
			rows			=>	$$Imposition{rows},
			calliper		=>	$$Paper{calliper},
	);

	my $Fold = $Imposition->Equipment()->Fold(\%find);
	return @imps if $Fold;
	delete $find{page_width};

	# Now look it up without the width
	$Fold = $Imposition->Press()->Fold(\%find);
	return @imps if ! $Fold;

	if ( $Fold->min_width() and $Fold->min_width() > ( $$Imposition{image_orientation} == openprint::Imposition::Vertical ? $Imposition->image_width() : $Imposition->image_height() ) ) {
		my $I = $Imposition->copy();

		if ( $$I{image_orientation} == openprint::Imposition::Vertical ) {
			my $space = $Fold->min_width() - $I->image_width();
			$I->cropmark_left(0) if $space >= $I->cropmark_left();
			$I->cropmark_right(0) if $space >= $I->cropmark_right();
			$I->gutters(0) if $space >= $I->gutters();
			$I->image_width( $Fold->min_width() );
		} else {
			my $space = $Fold->min_width() - $I->image_height();
			$I->cropmark_left(0) if $space >= $I->cropmark_left();
			$I->cropmark_right(0) if $space >= $I->cropmark_right();
			$I->gutters(0) if $space >= $I->gutters();
			$I->image_height( $Fold->min_width() );
		} # end if

		return @imps if ( $Paper->start_width() and $Paper->start_width() < $I->used_width() );
		$Paper->width( $I->used_width() ) if ! $Paper->start_width();
		push @imps, $I;
	} # end if
	return @imps;

} # end sub impositions

sub signature_calc {
	my ( $Project, $sig_specs, $specs, $qty_index, $SignatureImposition, $Signature_Impositions, $calc_hash ) = @_;

	my %results = (
			Price							=>	0,
			MPrice						=>	0,
			Equipment					=>	undef,
			Status						=>	'uncalculated',
			Folds							=>	{},
			FoldedImpositions	=>	[],
			Breakdown					=>	'',
			MakeReadyOvers		=>	0,
			RunOvers					=>	0,
			MakeReadyTime			=>	0,
	);

	if ( !$$SignatureImposition{imposition} ) {
		Carp::cluck('Invalid Imposition');
		$results{Breakdown}	 = 'Invalid Signature passed to Folding';
		return \%results;
	} # end if

	if ( $$sig_specs{txtSignatureType} and ( $SignatureImposition->pages() == 2 ) ) {
		# Does not need folding
		$results{Status}		= 'calculated';
		$results{Breakdown}	= '2 page does not require folding';
		return \%results;
	} # end if

	if ( !( $$sig_specs{txtFinalWidth} and $$sig_specs{txtFinalHeight} ) ) {
		$openprint::log->error("No finished width and height, cannot continue $$Project{id} $qty_index");
		# Does not need folding
		$results{Breakdown} = 'No finished width and height, cannot continue';
		return \%results;
	} # end if

	my $Paper = $$SignatureImposition{Paper};
	my $Press = $$SignatureImposition{Press};
	my $ppt = $Press->specification('Printing Type');
	my $services = $Project->services();
	my $form = $$sig_specs{SignatureIndex};

	my $bestM = 0;
	my $bestPrice = undef;
	my $bestComparison;
	my $bestRunPrice = 0;
	my $bestRunTime = 0;
	my $bestSetupPrice = 0;
	my $bestEquipment;
	my $bestFolds;
	my $bestImpositions;

	$SignatureImposition->display('Signature Imposition:') if DEBUG;

	my $perforating = 0;
	$perforating = openprint::Estimating::Perforating::signature_has_perforation($$calc_hash{PerforatingSpecs}, $sig_specs) if $$calc_hash{PerforatingSpecs};
	my $scoring_signature_needs = openprint::Estimating::Scoring::signature_needs( $Project, $$calc_hash{ScoringSpecs}, $sig_specs, $Paper ) if $$calc_hash{ScoringSpecs};

	my @my_equipment;
	if ( $$specs{"chkOverrideEquipment-$form-$qty_index"} and ( $$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' ) ) {
		#$openprint::log->debug("Overriding Folding Equipment for sig $form to " . $$specs{"ddmEquipment-$form-$qty_index"});
		if ( $$specs{"ddmEquipment-$form-$qty_index"} ) {
			@my_equipment = ( new openprint::Equipment( $$specs{"ddmEquipment-$form-$qty_index"} ) );
		} else {
			$results{Status} = 'calculated';
			$results{Breakdown} = 'Folding Equipment override to nothing';
			return \%results;
		} # end if
	} else {
    my $sheeter = $Press->specification('Sheeter');
		if ($sheeter and ($sheeter eq 'Y')) {
			if ( $$calc_hash{'Folding::signature_calc::equipment'} ) {
				@my_equipment = @{$$calc_hash{'Folding::signature_calc::equipment'}};
			} else {
				@my_equipment = @equipment;
			} # end if
		} else {
			$openprint::log->debug('No sheeter') if DEBUG;
			@my_equipment = @equipment;
		} # end if

		$openprint::log->debug("Press: $$sig_specs{'ddmPress'.$qty_index}" . $$Press{strid} ) if DEBUG;
		my $add = 1;
		my $capable = $Press->specification('Folding Capable');
		if ( $capable and ( $capable ne 'N' ) ) {
			if ( $$services{UVCoating} and openprint::Estimating::UVCoating::signature_needs( $Project, $sig_specs ) ) {
				if ( $$calc_hash{UVCoatingSpecs}{"ddmEquipment-$form-$qty_index"} != $$Press{id} ) {
					$add = 0;
				} # end if
			} # end if
			if ( $$services{Aqueous} and openprint::Estimating::Aqueous::signature_needs( $Project, $sig_specs ) ) {
				if ( $$calc_hash{AqueousSpecs}{"ddmEquipment-$form-$qty_index"} != $$Press{id} ) {
					$add = 0;
				} # end if
			} # end if
			if ($add) {
				@my_equipment = ( $Press, map { $$_{id} == $$Press{id} ? () : $_ } @my_equipment );
			} else {
				# Can't do inline when UV or AQ
				@my_equipment = map { $$_{id} == $$Press{id} ? () : $_ } @my_equipment;
			} # end if
		} # end if
	} # end if override or lookup equipment

	# If the stitching is happening on a piece of equipment that can't handle large signatures, then we need to cut
	# them down instead of folding them. Something like a duplo can do 4pg signatures only, so the cutting service
	# will cut everything down, and we will show the 4pg sigs being folded on the duplo
	if ( DEBUG ) {
		$openprint::log->debug("Doing signature $form");
		foreach my $E ( @my_equipment ) {
			$openprint::log->debug("1 Equipment: " . $E->strid() );
		}
	}

	if (!@my_equipment) {
		$results{alert} .= 'There is no Folding capable equipment.<br/>';
		return \%results;
	} # end if

	#$openprint::log->debug("Makereadies...");
	my %makereadies;

	# We assume that Signature_Impositions is all impos that come before, or maybe after....
	# Here's the problem... if a sig after ours has our fold, then the makeready will be counted here. and so we won't change for makeready.

	foreach my $SigImpo ( @{$Signature_Impositions} ) {
#$SigImpo->display("In Folding::siganture_calc");
		last if $SigImpo == $SignatureImposition;
		# Took this out so that we don't need signature_service_index, so we have to ensure that this service is not in the Signature_Impositions
		#next if $signature_service_index and $$SigImpo{service_id} >= $signature_service_index;
		if ( $$SigImpo{folding_results} ) {
$openprint::log->debug("folds from sigimpo") if DEBUG;
			my $Folds = $$SigImpo{folding_results}{Folds};
			if ( $Folds ) {
				foreach my $key ( keys %$Folds ) {
					my ( $fold_type, $imposition ) = $key =~ /(.*)-(\d+)out$/;
					$makereadies{$$SigImpo{folding_results}{Equipment}{id}} = {} if ! $makereadies{$$SigImpo{folding_results}{Equipment}{id}};
					$makereadies{$$SigImpo{folding_results}{Equipment}{id}}{$fold_type.$imposition} = 1;
				} # end foreach
			} elsif ( DEBUG ) {
				$openprint::log->error('No folds from sigimpo so cant detect makereadies');
				$SigImpo->display();
			} # end if
		} else {
			my $s_specs = $$SigImpo{specs};

			# DO we need this check? I don't see why, we have already ensured that our current sig is not in Signature_Impositions
			#next if $$SigImpo{SignatureIndex} and $$SigImpo{SignatureIndex} == $form;
			foreach my $fold_index ( 1 .. 4 ) {
				if ( $$specs{"FoldQty-$$s_specs{SignatureIndex}-$qty_index-$fold_index"} ) {
					$makereadies{$$specs{"ddmEquipment-$$s_specs{SignatureIndex}-$qty_index"}} = {} if ! $makereadies{$$specs{"ddmEquipment-$$s_specs{SignatureIndex}-$qty_index"}};
					$makereadies{$$specs{"ddmEquipment-$$s_specs{SignatureIndex}-$qty_index"}}{ $$specs{"FoldType-$$s_specs{SignatureIndex}-$qty_index-$fold_index"}.$$specs{"FoldImposition-$$s_specs{SignatureIndex}-$qty_index-$fold_index"} } = 1;
				} # end if
			} # end foreach fold_index
		} # end if
	} # end foreach signature

	# This makready stuff could probably by cached
	if ( DEBUG ) {
		foreach my $k ( keys %makereadies ) {
			my $mrs = $makereadies{$k};
			$openprint::log->debug("Makereadies for equpiment-id:$k : " . (keys %{$mrs}) . " FoldTypes");
		}
	}

	my $width_folds = Math::Round::nearest(1, $$sig_specs{txtWidth}/$$sig_specs{txtFinalWidth})-1;
	if ( $width_folds < 0 ) {
		$openprint::log->debug("Got negative width_folds from Math::Round::nearest( 1, $$sig_specs{txtWidth}/$$sig_specs{txtFinalWidth})-1");
		$width_folds = 0;
	} # end if

	my $height_folds = Math::Round::nearest(1, $$sig_specs{txtHeight}/$$sig_specs{txtFinalHeight})-1;
	if ( $height_folds < 0 ) {
		$openprint::log->debug("Got negative width_folds from Math::Round::nearest( 1, $$sig_specs{txtHeighth}/$$sig_specs{txtFinalHeight})-1");
		$height_folds = 0;
	} # end if
	@$SignatureImposition{'width_folds','height_folds'} = ( $width_folds, $height_folds );
	$openprint::log->debug("Folds: $width_folds x $height_folds from $$sig_specs{txtWidth}/$$sig_specs{txtFinalWidth} and height: $$sig_specs{txtHeight}/$$sig_specs{txtFinalHeight}") if DEBUG;

	if ( ( ! $width_folds ) and ( $$sig_specs{txtWidth} != $$sig_specs{txtFinalWidth} ) ) {
		$width_folds = 1;
	}
	if ( ( ! $height_folds ) and ( $$sig_specs{txtHeight} != $$sig_specs{txtFinalHeight} ) ) {
		$height_folds = 1;
	}

	# What we do is build a set of pieces of the imposition, all of which can be folded. We don't worry about optimality, just possibility.
	my @Set_Of_Impositions;
	my @All_Impositions;
	$$SignatureImposition{page_quantity} = 1;
# IF it's a W&T, we have to cut in half first, so just do it.
	if ( $$SignatureImposition{runstyle} eq 'Work & Turn' ) {
		my $i = $SignatureImposition->copy();
		$$i{runstyle} = 'Sheet Work';
		$$i{start_columns} = $$i{columns};
		$i->columns( $$i{columns}/2 );

		if ( $$i{dutch_columns} ) {
			$i->dutch_columns( $$i{dutch_columns} / 2 );
		}
		$$i{quantity} = 2;
		push @Set_Of_Impositions, $i;
	} elsif ( $$SignatureImposition{runstyle} eq 'Work & Tumble' ) {
		my $i = $SignatureImposition->copy();
		$$i{runstyle} = 'Sheet Work';
		$$i{start_rows} = $$i{rows};
		$i->rows( $$i{rows}/2 );
		if ( $$i{dutch_rows} ) {
			$i->dutch_rows( $$i{dutch_rows} / 2 );
		}
		$$i{quantity} = 2;
		push @Set_Of_Impositions, $i;
	} else {
		my $i = $SignatureImposition->copy();
		$$i{quantity} = 1;
		push @Set_Of_Impositions, $i;
	} # end if

	# Get rid of dutches, which I think can happen on books now.
	if ( $$SignatureImposition{dutch_columns} ) {
		my @Impositions = ();
		foreach my $I ( @Set_Of_Impositions ) {
			if ( $$I{dutch_columns} ) {
				{
					my $i = $I->copy();
					$i->dutch_columns(0);
					$i->dutch_rows(0);
					#$i->quantity(1);
					push @Impositions, $i;
				}
				{
					my $i = $I->copy();
					$i->columns( $$i{dutch_columns} );
					$i->rows( $$i{dutch_rows} );
					$i->dutch_columns(0);
					$i->dutch_rows(0);
					#$i->quantity(1);
					$i->image_orientation($$I{image_orientation} == openprint::Imposition::Vertical ? openprint::Imposition::Horizontal : openprint::Imposition::Vertical);
					push @Impositions, $i;
				}
			} else {
				push @Impositions, $I;
			} # end if
		} # end foreach I

		@Set_Of_Impositions = @Impositions;
		if ( DEBUG ) {
			foreach my $I ( @Impositions ) {
				$I->display('Results from dutch cuts');
			} # end foreach
		} # end if
	} # end if

# Now we have a base set of Maximal Impositions.	Now some of the I's in this set may have an imposition > 1.
# Problem is that we apparently also need to price the situation of doing them 1 out, and everything in between.
	if ( DEBUG ) {
		foreach my $I ( @Set_Of_Impositions ) {
			$I->display('Results after initial cuts qty: ' . $$I{quantity} . 'x ');
		} # end foreach
	} # end if

	@All_Impositions = reduce_impositions( \@Set_Of_Impositions );
	@All_Impositions = remove_duplicates( @All_Impositions );
	if ( DEBUG ) {
		$openprint::log->debug('Sets of Maximum Impositions: # of sets: ' . @All_Impositions);
		foreach my $Set ( @All_Impositions ) {
			$openprint::log->debug("Impositions in set: " . @$Set);
			foreach my $I ( @$Set ) {
				$I->display('quantity '.$I->quantity() );
			} # end foreach I
		} # end foreach set
		$openprint::log->debug(sprintf('Original Sign info: %dx%d*%d,%dout', @$SignatureImposition{'spread_columns','spread_rows','spread_size','imposition'} ) );
	} # end if debug

	my $override_folds = ( $$specs{"chkOverrideFold-$form-$qty_index"} and ( $$specs{"chkOverrideFold-$form-$qty_index"} eq 'Y' ) ) ? 1 : 0;

	if ( $$SignatureImposition{pages} and ($$SignatureImposition{pages} > $$SignatureImposition{spread_size})) {
		@All_Impositions = reduce_pages( \@All_Impositions, $override_folds );
		if ( DEBUG ) {
			$openprint::log->debug('Sets of Maximum Impositions: # of sets: ' . @All_Impositions);
			foreach my $Set ( @All_Impositions ) {
				$openprint::log->debug('Impositions in set: ' . @$Set);
				foreach my $I ( @$Set ) {
					$I->display('pq:' . $$I{page_quantity});
				} # end foreach I
			} # end foreach set
		} # end if debug
	} # end if have pages

	if ( $override_folds ) {
		$openprint::log->error('Checking for Overriden folds') if DEBUG;

		if ( $$sig_specs{txtSignatureType} ) {
			my $override_pages = 0;
			foreach my $index ( 1 .. 4 ) {
				next if ! ( $$specs{"FoldQty-$form-$qty_index-$index"}
						and $$specs{"FoldType-$form-$qty_index-$index"}
						and $$specs{"FoldImposition-$form-$qty_index-$index"} );
        my $pages = 0;
        if ($$specs{"FoldType-$form-$qty_index-$index"} =~ /(\d+)PageFold/) {
          $pages = $1;
        } elsif ($$specs{"FoldType-$form-$qty_index-$index"} eq 'SingleGateFold') {
          $pages = 6;
        } elsif ($$specs{"FoldType-$form-$qty_index-$index"} eq 'DoubleGateFold') {
          $pages = 8;
        }

				$override_pages += $$specs{"FoldQty-$form-$qty_index-$index"} * $pages * $$specs{"FoldImposition-$form-$qty_index-$index"};
      }

			if ( $override_pages > $$SignatureImposition{imposition} * $SignatureImposition->pages() ) {
				$$specs{alert} .= "You seem to be specifying more pages for folding than were printed for form $form quantity $qty_index<br/>";
			} elsif ( $override_pages < $$SignatureImposition{imposition} * $SignatureImposition->pages() ) {
				$$specs{alert} .= "You seem to be specifying fewer pages ($override_pages) for folding than were printed (".($$SignatureImposition{imposition} * $SignatureImposition->pages())." for form $form quantity $qty_index<br/>";
			} # end if
		} # end if SignatureType need to test for too many pages

		my @New_All_Impositions;
SET:		foreach my $Set_Of_Impositions ( @All_Impositions ) {

			# Find out if folds satisfies the overrides
			my %found_by_index;
			my %found_by_FI;
			foreach my $index ( 1 .. 4 ) {
#$openprint::log->debug("OverrideFOld $form-$qty_index-$index (".$$specs{"FoldQty-$form-$qty_index-$index"}.")");
        if (! ( $$specs{"FoldQty-$form-$qty_index-$index"}
              and $$specs{"FoldType-$form-$qty_index-$index"}
              and $$specs{"FoldImposition-$form-$qty_index-$index"} )) {
          if ($$specs{"FoldQty-$form-$qty_index-$index"}
              or $$specs{"FoldType-$form-$qty_index-$index"}
              or $$specs{"FoldImposition-$form-$qty_index-$index"}) {
          $$specs{alert} .= "Fold $index for form $form is not fully specified.<br/>";
          $openprint::log->error('qty: '.$$specs{"FoldQty-$form-$qty_index-$index"}.' type '.$$specs{"FoldType-$form-$qty_index-$index"}. ' impo '.$$specs{"FoldImposition-$form-$qty_index-$index"});
        }
          next;
        }

				my $pages;

				if ( $$sig_specs{txtSignatureType} ) {
					( $pages ) = $$specs{"FoldType-$form-$qty_index-$index"} =~ /(\d+)PageFold/;
				} else {
					if ( $$specs{"FoldImposition-$form-$qty_index-$index"} > $$SignatureImposition{imposition} ) {
						$$specs{alert} .= "You seem to be specifying a higher imposition for folding than was printed for form $form quantity $qty_index<br/>";
					}
				} # end if
				$found_by_index{$index} = 0;
				foreach my $FI ( @$Set_Of_Impositions ) {
					next if $found_by_FI{$FI};

					$FI->display() if DEBUG;
					$openprint::log->debug(qq`Overriden $$specs{"FoldQty-$form-$qty_index-$index"} $$specs{"FoldImposition-$form-$qty_index-$index"}out $$specs{"FoldType-$form-$qty_index-$index"} for form $form`) if DEBUG;

					if ($pages and ( $$FI{pages} != $pages ) ) {
$openprint::log->debug(qq`Wrong type: $$specs{"FoldType-$form-$qty_index-$index"} ne $$FI{pages}pages`) if DEBUG;
						next;

					} elsif ( $$specs{rdbTemplateType} and $fold_types{$$specs{rdbTemplateType}} and ( $$specs{"FoldType-$form-$qty_index-$index"} ne $$specs{rdbTemplateType} ) ) {
$openprint::log->debug(qq`Wrong type: $$specs{"FoldType-$form-$qty_index-$index"} ne $$specs{rdbTemplateType}`) if DEBUG;
						next;
					} elsif ( $$specs{"FoldImposition-$form-$qty_index-$index"} != $$FI{imposition} ) {
#$openprint::log->debug(qq`Wrong imposition: $$specs{"FoldImposition-$form-$qty_index-$index"} != $$FI{imposition}`) if DEBUG;
						next;
					} elsif ( $$specs{"FoldQty-$form-$qty_index-$index"} != $$FI{quantity} ) {
            #$$specs{alert} .= 'Found a fold that matched for form '.$form.' but maybe the quantity of folds is wrong. Should it be '.$$FI{quantity}.'?<br/>' if !$$specs{alert};
#$openprint::log->debug(qq`Wrong qty: $$specs{"FoldQty-$form-$qty_index-$index"} != $$FI{quantity}`) if DEBUG;
						next;
					} # end if
#$FI->display("Found") if DEBUG;
					$found_by_index{$index} = $FI;
					$found_by_FI{$FI} = $index;
				} # end foreach my FI
				if ( ! $found_by_index{$index} ) {
# Didn't find one of the folds.  Give up for now, move on to the next set.
					next SET;
				}
			} # end foreach fold index
			foreach my $FI ( @$Set_Of_Impositions ) {
				if ( ! $found_by_FI{$FI} ) {
# Didn't find all of the folds.  Give up for now, move on to the next set.
					next SET;
				}
			}

# If we got here, then we matched the override
			push @New_All_Impositions, $Set_Of_Impositions;
		} # end foreach Set

		if (!@New_All_Impositions) {
			$openprint::log->error('Didnt find any matching folds for the override');
			$$specs{alert} .= 'Didn\'t find any matching folds for the override<br/>';
			$results{Status} = 'uncalculated';
			return \%results;
# Look for some generic matches and create a new imp
			my $Set;
			my $Override_pages;
			foreach my $index ( 1 .. 4 ) {
				next if ! ( $$specs{"FoldQty-$form-$qty_index-$index"}
						and $$specs{"FoldType-$form-$qty_index-$index"}
						and $$specs{"FoldImposition-$form-$qty_index-$index"} );
				my ( $pages ) = $$specs{"FoldType-$form-$qty_index-$index"} =~ /(\d+)PageFold/;
				my $FI = $SignatureImposition->copy();
				$$FI{pages} = $pages;
				$$FI{imposition} = $$specs{"FoldImposition-$form-$qty_index-$index"};
				$$FI{quantity} = $$specs{"FoldQuantity-$form-$qty_index-$index"};
			}
		} # end if ! @New_All_Impositions
		@All_Impositions = @New_All_Impositions;
	} # end if chkOverrideFolds

	# So that Scoring doesn't recalculate it
	$$SignatureImposition{cut_impositions} = \@All_Impositions;

#FIXME
	my $FoldingFoldMakeReadyService = $Services{FoldingFoldMakeReady};
	my $FoldingAngleMakeReadyService = $Services{FoldingAngleMakeReady};

	my $bestBreakdown;
	# Foreach equipment, figure out which folds are required.
	foreach my $Equipment ( @my_equipment ) {
		my $Breakdown = '<br/><b>Equipment '.$$Equipment{name}.':</b><br/>';
		if ( (!$$Equipment{useinestimating}) and ( $$specs{"chkOverrideEquipment-$form-$qty_index"} ne 'Y' ) ) {
			$Breakdown .= 'Can only be used by override';
      $results{Breakdown} .= $Breakdown;
			next;
		}
		#$openprint::log->debug('2 Equipment '.$Equipment->name()) if DEBUG;
		if ( $$services{NoOfflineBindery} and ( $$sig_specs{'ddmPress'.$qty_index} ne $$Equipment{strid} ) ) {
			$Breakdown .= "No Offline bindery and not printing on $$Equipment{name}.<br/>";
      $results{Breakdown} .= $Breakdown;
			$openprint::log->debug('No Offline Equipment '.$$Equipment{name}) if DEBUG;
			next;
		} # end if
		my $capable = $Equipment->specification('Folding Capable');
		if ( $capable eq 'When PerfectBound' ) {
# Means it's a PerfectBinder, so can only do covers
			if ( $$sig_specs{Group} != 1 ) {
				$Breakdown .= 'Perfect Binder can only fold 4pg cover:<br/>';
        $results{Breakdown} .= $Breakdown;
				next;
			} # end if
		} elsif ( $capable eq 'For Pocket Folders' ) {
      my $is_pocket_folder = $Project->Type()->name() eq 'PresentationFolders' ? 1 : 0;
      if (!$is_pocket_folder) {
        foreach my $sig_id ($Project->signatures()) {
          my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
          $openprint::log->debug("Template type for $sig_id ".$$sig_specs{rdbTemplateType});
          if ($$sig_specs{rdbTemplateType} and sets::isin($$sig_specs{rdbTemplateType}, ['2Panel1Pocket','2Panel2Pocket','3Panel2Pocket','TriFoldDoublePocket'])) {
            $is_pocket_folder = 1;
            last;
          }
        } # end foreach sig
      }
			if (!$is_pocket_folder) {
        $openprint::log->debug("Not doing pocket folders") if DEBUG;
        next;
      }
		} elsif ( $capable eq 'When Binding' ) {
			if ( ! ( $$calc_hash{HasStitching} or $$calc_hash{HasPerfectBound} ) ) {
				$Breakdown .= 'Not binding:<br/>';
        $results{Breakdown} .= $Breakdown;
				next;
			} # end if
			if ( $Equipment->specification('Fold Covers Only') and ( (!$$sig_specs{Group}) or ( $$sig_specs{Group} != 1 ) )) {
				$Breakdown .= 'Stitcher can only fold 4pg cover:<br/>';
        $results{Breakdown} .= $Breakdown;
				next;
			} # end if

		} elsif ( $capable eq 'When Stitching' ) {
			$Breakdown .= 'When Stitching:';
# Means it's a Stitcher, or a Duplo, so can only do covers
			if ( ! $$calc_hash{HasStitching} ) {
				$Breakdown .= 'Not stitching:<br/>';
        $results{Breakdown} .= $Breakdown;
				next;
			} # end if
			if ( $Equipment->specification('Fold Covers Only') and ( (!$$sig_specs{Group}) or ( $$sig_specs{Group} != 1 ) )) {
				$Breakdown .= 'Stitcher can only fold 4pg cover:<br/>';
        $results{Breakdown} .= $Breakdown;
				next;
			} # end if
		} elsif ( $capable =~ /^When Printing( on .*)?$/ ) {
			$Breakdown .= $capable.':';
			if ( $1 ) {
				my $press = $1;
				$press =~ s/^ on //;
				if ( $press ne $$Press{strid} ) {
					$Breakdown .= "Not printing on $$Press{strid}:<br/>";
          $results{Breakdown} .= $Breakdown;
					next;
				}
			} else {

				if ( $$Press{id} != $$Equipment{id} ) {
					$Breakdown .= "Not printing on $$Equipment{name}:<br/>";
          $results{Breakdown} .= $Breakdown;
					next;
				} # end if

				if ( $perforating ) {
					if ( $$specs{"chkOverrideEquipment-$form-$qty_index"} ) {
						$$specs{alert} .= "Perforating while folding inline may cause tearing.<br/>";
					} else {
						$Breakdown .= 'not perforating on this piece of equipment.<br/>';
            $results{Breakdown} .= $Breakdown;
						next;
					} # end if
				} # end if
			} # end if
		} # end if
		if ( $ppt and ( my $pt = $Equipment->specification('PrintingTypes') ) ) {
			if ( ! sets::isin( $ppt, [ split(',',$pt ) ] ) ) {
				$Breakdown .= 'Wrong printing type.<br/>';
        $results{Breakdown} .= $Breakdown;
				next;
			} # end if
		} # end if
		if ( $_ = $Equipment->fits(undef,undef,$$Paper{calliper}) ) {
			$Breakdown .= $_;
      $results{Breakdown} .= $Breakdown;
			next;
		}

		my $orientation = $Equipment->specification('Orientation') || $Equipment->specification('Folding Orientation');

		for ( my $set_index = 0; $set_index < @All_Impositions; $set_index += 1 ) {

			my $Set_Of_Impositions = $All_Impositions[$set_index];
			if ( $$Equipment{id} == $$Press{id} ) {
				if ( scalar @$Set_Of_Impositions != 1 ) {
					$openprint::log->debug("Sets of impos != 1 for $$Equipment{strid}") if DEBUG;
					next;
				} # end if
				next if $$Set_Of_Impositions[0]{quantity} != 1;
				next if $$Set_Of_Impositions[0]{pages} != $$SignatureImposition{pages};
			} elsif ( $capable eq 'When Stitching' ) {
				if ( scalar @$Set_Of_Impositions != 1 ) {
					$openprint::log->debug("Sets of impos != 1 for $$Equipment{strid}") if DEBUG;
					next;
				} # end if
			} # end if
			# At this point, we don't modify the Set_Of_Impositions, we modify the equipment-specific copy of it.
#$openprint::log->debug("Impositions in this set: " . @Impositions );

			# complete signals whether we were able to fold all impositions
			my $complete = 1;

			my %folds;
			if ( DEBUG ) {
				$openprint::log->debug('Impositions in this set: ' . @$Set_Of_Impositions );
				for ( my $imp_index = 0; $imp_index < @$Set_Of_Impositions; $imp_index += 1 ) {
					my $Imposition = $$Set_Of_Impositions[$imp_index];
					$Imposition->display();
				} #end for
			} # end if

			for ( my $imp_index = 0; $imp_index < @$Set_Of_Impositions; $imp_index += 1 ) {
        my $fi_index = $imp_index+1;
				my $Imposition = $$Set_Of_Impositions[$imp_index];

				if ( DEBUG ) {
					$Imposition->display('trying ');
				} # end if

				# This checks to see if the folds line up, should probably be using spine_direction instead
				if ( $$Equipment{id} != $$Press{id} ) {
					if ( $$Imposition{imposition} > 3 and ( $$Imposition{columns} > 1 and $$Imposition{rows} > 1 ) ) {
						$openprint::log->debug("Can't do that impo cuz impo > 3 columns > 1 and rows > 1") if DEBUG;
						$complete = 0;
						last;
					} elsif ( ( $$Imposition{columns} > 1 ) and ( $$Imposition{spine_direction} == openprint::Imposition::Vertical ) ) {
						$openprint::log->debug("Can't do that impovertical and columns $$Imposition{columns} > 1 and spine direction $$Imposition{spine_direction} ==" . openprint::Imposition::Vertical ) if DEBUG;
						$complete = 0;
						last;
					} elsif ( $$Imposition{rows} > 1 and ( $$Imposition{spine_direction} == openprint::Imposition::Horizontal ) ) {
						$openprint::log->debug("Can't do that impo horizontal and rows $$Imposition{rows} > 1") if DEBUG;
						$complete = 0;
						last;
					} # end if
				} # end if is not inline folding

				my $required_bleed = $Equipment->specification($$Imposition{imposition}.'out Required Bleed');
				if ( defined $required_bleed ) {
					if ( $required_bleed > $$Imposition{bleed_size} ) {
						$Breakdown .= 'Requires ' . $required_bleed . ' bleed for ' . $$Imposition{imposition} . q`out Can't fold it this way.<br/><br/>`;
            $results{Breakdown} .= $Breakdown;
						$complete = 0;
						last;
					} else {
					$openprint::log->debug("Bleed Good $$Imposition{bleed_size} > $required_bleed " . $$Imposition{imposition}.'out Required Bleed on ' . $Equipment->strid() ) if DEBUG;
					} # end if
				#} else {
					#$openprint::log->warn("No spec for " . $$Imposition{imposition}.'out Required Bleed on ' . $Equipment->strid() ) if DEBUG;
				} # end if

				#if ( DEBUG and 0 ) {
					#$openprint::log->debug("trying: ");
					#$Imposition->display();
				#} # end if

# Each piece of equipment can do different folds.	So we have to calculate what we can do as well.
				if ( $$Equipment{id} == $$Press{id} ) {
# Special case because we can't cut it in the middle of printing.	This case is basically for web presses
#2107-03-06 actually some presses have dual delivery

					my $Fold = $Equipment->Fold( {
							pages			=>	$Imposition->pages(),
							page_columns	=>	$Imposition->page_columns(),
							page_rows	=>	$Imposition->page_rows(),
							page_width		=>	$$Imposition{page_width},
							page_height		=>	$$Imposition{page_height},
							spine_direction	=>	$openprint::Imposition::Orientations{$$Imposition{spine_direction}},
							grain_direction	=>	$Imposition->grain_direction(),
							stitching		=>	($$services{SaddleStitching} or $$services{LoopStitching}) ? 1 : 0,
							perfectbind		=>	$$services{PerfectBound} ? 1 : 0,
							spinepaste		=>	$$services{SpinePaste} ? 1 : 0,
							gsm				=>	$Paper->gsm(),
							imposition		=>	$$Imposition{imposition},
							columns			=>	$$Imposition{columns},
							rows			=>	$$Imposition{rows},
							calliper		=>	$$Paper{calliper},
							printing_type	=>	$ppt,
							} );
					if ( $Fold ) {
						# Do we need to clone it? we used to set the impo in it, but we don't do that anymore.
						$Fold = $Fold->clone();
						$$Imposition{Fold} = $Fold;

						push @{$folds{$Imposition->pages().'PageFold-'.$$Imposition{imposition}.'out'}}, $Fold;
						$openprint::log->debug(sprintf('Found: %dx%d,%dout', $Imposition->page_columns(), $Imposition->page_rows(), $Imposition->imposition() ) ) if DEBUG;
					} else {
						$Breakdown .= sprintf('Didnt find fold pages: %dx%d=%d %.3fx%.3f %s, %dout %dgsm<br/>', $Imposition->page_columns(), $Imposition->page_rows(), $Imposition->pages(), @$Imposition{'page_width','page_height','image_orientation_text','imposition'}, $Paper->gsm() );
            $results{Breakdown} .= $Breakdown;
						$openprint::log->debug(sprintf('Didnt find: %dx%d %.3fx%.3f %s,%dout', $Imposition->page_columns(), $Imposition->page_rows(), @$Imposition{'page_width','page_height','image_orientation_text','imposition'} ) ) if 1 or DEBUG;
$Imposition->display();
						%folds = ();
						# Last because it's on press, can't do any cut impos.	Not actually True.	Webs can slit it and do dual delivery, fold one, sheet the other. FIXME
						$complete =0;
						last;
					} # end if
				} else { # Not the press
					my $max_feed_width = $Equipment->specification('Maximum Feed Width', $$Imposition{imposition} );
          # Figure out the fold.	Because this isn't the press, we have to figure out how it cuts...
          $openprint::log->debug("Max feed: $max_feed_width") if $max_feed_width and DEBUG;

          my $fold_type = ($$specs{"chkOverrideFold-$form-$qty_index"} ? $$specs{"FoldType-$form-$qty_index-$fi_index"} : $$sig_specs{rdbTemplateType});
          $fold_type //= '';
          $$specs{"chkOverrideFold-$form-$qty_index"} //= '';
$openprint::log->debug("Type: $fold_type for $form-$qty_index-$fi_index ".$$specs{"chkOverrideFold-$form-$qty_index"}) if DEBUG;

					if ($fold_type and $fold_types{$fold_type}) {
						my $rc = $Equipment->fits( $Imposition->layout_width(), $Imposition->layout_height() );
						$openprint::log->debug('Trying to fit ' . $Imposition->layout_width() . 'x' . $Imposition->layout_height() . ' on ' . $Equipment->strid(). ' (' . ($rc ? $rc : '' ).')' ) if DEBUG;
						if ( $rc ) {
							if ((!$$specs{"chkOverrideLimits-$form-$qty_index"}) or ($$specs{"chkOverrideLimits-$form-$qty_index"} ne 'Y')) {
								if ( @my_equipment == 1 ) {
									$Breakdown .= $Imposition->to_string() . "Doesn't fit: $rc<br/>";
                  $results{Breakdown} .= $Breakdown;
								} # end if
								%folds = ();
								last;
							} else {
								$Breakdown .= $Imposition->to_string() . "Doesn't fit: $rc<br/>";
                $results{Breakdown} .= $Breakdown;
								$$specs{alert} .= "Fold for form $form may exceed equipment specifications.<br/>";
							}
						} # end if

						my $Fold = $Equipment->Fold({
							page_columns		=>	$Imposition->page_columns(),
							page_rows				=>	$Imposition->page_rows(),
							page_width			=>	$$sig_specs{txtFinalWidth},
							page_height			=>	$$sig_specs{txtFinalHeight},
							type						=>	$fold_type,
							gsm							=>	$Paper->gsm(),
							calliper				=>	$$Paper{calliper},
							imposition			=>	$$Imposition{imposition},
							columns					=>	$$Imposition{columns},
							rows						=>	$$Imposition{rows},
							printing_type		=>	$ppt,
                stitching		=>	(($$services{SaddleStitching} or $$services{LoopStitching}) ? 1 : 0),
                perfectbind		=>	($$services{PerfectBound} ? 1 : 0),
                spinepaste		=>	($$services{SpinePaste} ? 1 : 0),
							spine_direction	=>	$openprint::Imposition::Orientations{$$Imposition{spine_direction}},
							grain_direction	=>	$Imposition->grain_direction(),
							});

						if ( ! $Fold ) {
							if ( (!$$specs{"chkOverrideLimits-$form-$qty_index"} ) or ($$specs{"chkOverrideLimits-$form-$qty_index"} ne 'Y') ) {
# Don't do this, because we may be printing a 2x2 8pg fold, but this will allow us to fold a parallel 8pg
if ( 0 ) {
							$Fold = $Equipment->Fold({

									page_width			=>	$$sig_specs{txtFinalWidth},
									page_height			=>	$$sig_specs{txtFinalHeight},
                  type						=>	($$specs{"chkOverrideFold-$form-$qty_index-$imp_index"} ? $$specs{"FoldType-$form-$qty_index-$imp_index"} : $$sig_specs{rdbTemplateType}),
									gsm							=>	$Paper->gsm(),
									calliper				=>	$$Paper{calliper},
									imposition			=>	$$Imposition{imposition},
									columns					=>	$$Imposition{columns},
									rows						=>	$$Imposition{rows},
									printing_type		=>	$ppt,
									spine_direction	=>	$openprint::Imposition::Orientations{$$Imposition{spine_direction}},
									});
}
							} else {
							$Fold = $Equipment->Fold({
									page_width			=>	$$sig_specs{txtFinalWidth},
									page_height			=>	$$sig_specs{txtFinalHeight},
									type						=>	$$sig_specs{rdbTemplateType},
									gsm							=>	$Paper->gsm(),
									imposition			=>	$$Imposition{imposition},
									columns					=>	$$Imposition{columns},
									rows						=>	$$Imposition{rows},
									printing_type		=>	$ppt,
									spine_direction	=>	$openprint::Imposition::Orientations{$$Imposition{spine_direction}},
									grain_direction	=>	$Imposition->grain_direction(),
									});
								$$specs{alert} .= "Fold for form $form may exceed equipment specifications.<br/>" if ! $$specs{alert};
							}
						} # end if ! Fold
						if ( $Fold ) {
# Need to check feed width
$openprint::log->debug('Has a fold, doing extra checks') if DEBUG;
							my $failure_reason;
							if ( $max_feed_width ) {
								# If multiple out, we trim inline otherwise trim first.
								# If it has been cut, assume cut to layout size

								# Width_size is the width of the object being fed into the folder, not the Imposition
								my $width_size;
								my $height_size;
								if ( $$Imposition{imposition} == 1 ) {
									$width_size = $$Imposition{object_width};
									$height_size = $$Imposition{object_height};

								} elsif ( $$Imposition{image_orientation} == openprint::Imposition::Vertical ) {
									$width_size = $$SignatureImposition{columns} != $$Imposition{columns} ? $Imposition->layout_width() : $Imposition->sheet_width();
									$height_size = $$SignatureImposition{rows} != $$Imposition{rows} ? $Imposition->layout_height() : $Imposition->sheet_height();
								} else {
									$width_size = $$SignatureImposition{rows} != $$Imposition{rows} ? $Imposition->layout_height() : $Imposition->sheet_height();
									$height_size = $$SignatureImposition{columns} != $$Imposition{columns} ? $Imposition->layout_width() : $Imposition->sheet_width();
								} # end if

								if ( $orientation ) {
									if (
											( $orientation eq 'Portrait' and $Imposition->layout_width() <= $Imposition->layout_height() ) or
											( $orientation eq 'Landscape' and $Imposition->layout_width() >= $Imposition->layout_height() )
										) {
										if ( $width_size >= $max_feed_width ) {
											$failure_reason = "max feed width $width_size > $max_feed_width on width ($$sig_specs{txtWidth}) $orientation.";
										} # end if
									} else {
										if ( $height_size >= $max_feed_width ) {
											$failure_reason = "max feed width $height_size > $max_feed_width on height ($$sig_specs{txtHeight}) $orientation.";
										} # end if
									} # end if
								} else {
# decide whether it's running portrait or landscape basessd on which way the folds go
									$openprint::log->debug("Has max feed width width folds: $width_folds height folds: $height_folds $$sig_specs{txtWidth} $$sig_specs{txtHeight} width_size: $width_size height_size: $height_size max_feed_width: $max_feed_width") if DEBUG;

									# width_folds and height_folds are already rotated
									if ( $width_folds and $height_folds ) {
										if ( $height_size > $max_feed_width and $width_size > $max_feed_width ) {
											$failure_reason = "max feed on both dimensions $max_feed_width .";
										} # end if

									} elsif ( ( $width_folds and ! $height_folds ) ) {
#
#or ( $width_folds == $$Fold{folds} and $height_folds == $$Fold{angles} ) ) {

# If folds are on width, we grip on height...
										if ( $height_size > $max_feed_width ) {
											$failure_reason = "max feed height $height_size > $max_feed_width on height ($$sig_specs{txtHeight}).";
										} # end if
									} elsif ( ( $height_folds and ! $width_folds ) ) {
#or ( $height_folds == $$Fold{folds} and $height_folds == $$Fold{angles} ) ) {
										if ( $width_size > $max_feed_width ) {
											$failure_reason = "to max feed width $width_size > $max_feed_width on width ($$sig_specs{txtWidth}).";
										} # end if
									} else {
										$openprint::log->warn("No fold match width_folds: $width_folds, height_folds: $height_folds Fold:$$Fold{name} folds: $$Fold{folds} angles:$$Fold{angles}") if DEBUG;
									} # end if
								} # end if has an orientation
							} # end if has max_feed_width

							if ( $failure_reason ) {
								if ( $$specs{"chkOverrideLimits-$form-$qty_index"} ne 'Y' ) {
									$Fold = undef;
								} else {
									$$specs{alert} .= "Warning: $failure_reason<br/>";
								}

								$Breakdown .= sprintf( '%s: %d*%dout %s layout: %sx%s StockWeight %.2fgsm calliper:%.4f<br/>',
										$$sig_specs{rdbTemplateType}, @$Imposition{'quantity','imposition'},
										$openprint::Imposition::Orientations{$$Imposition{image_orientation}},
										@$Imposition{'layout_width', 'layout_height'},
										@$Paper{'gsm', 'calliper'} );
								$Breakdown .= "Can't fold that , $failure_reason:<br/>
									gsm				=>	$$Paper{gsm}<br/>
									calliper		=>	$$Paper{calliper}<br/>
									imposition		=>	$$Imposition{imposition}<br/>";
                $results{Breakdown} .= $Breakdown;
							} # end if Fold passwes extra shceks

							if ( $Fold ) {
$openprint::log->debug("Got Fold: " . $Fold->to_string() ) if DEBUG;
								$Fold = $Fold->clone();
								#$Fold->Imposition( $Imposition );
								$$Imposition{Fold} = $Fold;
								push @{$folds{$$sig_specs{rdbTemplateType}.'-'.$$Imposition{imposition}.'out'}}, $Fold;
								next;
							} # end if Fold
						} # end if Fold found

						$complete = 0;

					} else {
            #if (!$complete) {
           # No template, might be a book
						#$Imposition->display("Trying: $$Equipment{name}") if DEBUG;
						$openprint::log->debug(sprintf('Trying %dx%d=%dout spreads: %dx%d=%d %sx%s',
									@$Imposition{'columns','rows','imposition','spread_columns','spread_rows','spreads','image_width','image_height'} ).' on ' . $$Equipment{name}) if DEBUG;

#$Imposition->display('fitting');
						# See if it fits
						my $rc = $Equipment->fits( $Imposition->layout_width(), $Imposition->layout_height() );
						if ( $rc )	{
							if ( !$$specs{"chkOverrideLimits-$form-$qty_index"} or $$specs{"chkOverrideLimits-$form-$qty_index"} ne 'Y' ) {
								if ( @my_equipment == 1 ) {
									$Breakdown .= $Imposition->to_string()."Doesn't fit $rc.<br/>";
                  $results{Breakdown} .= $Breakdown;
								}
								$complete =0;
								last;
							} else {
								$Breakdown .= $Imposition->to_string()."Doesn't fit $rc.<br/>";
                $results{Breakdown} .= $Breakdown;
								$$specs{alert} .= "Fold for form $form may exceed equipment specifications.<br/>";
							}
						} # end if fits

            $openprint::log->debug('Fits') if DEBUG;
            my $fits = '';
            my $Fold = $Equipment->Fold({
                pages			=>	$Imposition->pages(),
                page_columns	=>	$Imposition->page_columns(),
                page_rows	=>	$Imposition->page_rows(),
                page_width		=>	$$Imposition{page_width},
                page_height		=>	$$Imposition{page_height},
                spine_direction	=>	$openprint::Imposition::Orientations{$$Imposition{spine_direction}},
                stitching		=>	(($$services{SaddleStitching} or $$services{LoopStitching}) ? 1 : 0),
                perfectbind		=>	($$services{PerfectBound} ? 1 : 0),
                spinepaste		=>	($$services{SpinePaste} ? 1 : 0),
                gsm						=>	$Paper->gsm(),
                calliper				=>	$$Paper{calliper},
                imposition		=>	$$Imposition{imposition},
                columns				=>	$$Imposition{columns},
                rows					=>	$$Imposition{rows},
                printing_type	=>	$ppt,
                type          =>  $fold_type,
              });
            if ( ( ! $Fold ) and ( $$specs{"chkOverrideLimits-$form-$qty_index"} and ($$specs{"chkOverrideLimits-$form-$qty_index"} eq 'Y')) ) {
							$Fold = $Equipment->Fold({
									pages			=>	$Imposition->pages(),
									page_columns	=>	$Imposition->page_columns(),
									page_rows	=>	$Imposition->page_rows(),
									page_width		=>	$$Imposition{page_width},
									page_height		=>	$$Imposition{page_height},
									spine_direction	=>	$openprint::Imposition::Orientations{$$Imposition{spine_direction}},
									stitching		=>	(($$services{SaddleStitching} or $$services{LoopStitching}) ? 1 : 0),
									perfectbind		=>	($$services{PerfectBound} ? 1 : 0),
									spinepaste		=>	($$services{SpinePaste} ? 1 : 0),
									gsm						=>	$Paper->gsm(),
									imposition		=>	$$Imposition{imposition},
									columns				=>	$$Imposition{columns},
									rows					=>	$$Imposition{rows},
									printing_type	=>	$ppt,
                });
              $$specs{alert} .= "Fold for form $form may exceed equipment specifications.<br/>";
            }
            if ($Fold) {
              if ( $$Fold{page_columns} and $$Fold{page_rows} ) {
                $width_folds = $$Fold{page_columns}-1;
                $height_folds = $$Fold{page_rows}-1;
                $openprint::log->debug("Got new folds $width_folds x $height_folds from Fold") if DEBUG;
              } else {
                $openprint::log->debug('Fold does not have page_rows and page_columns filled in:' . $Fold->to_string() ) if DEBUG;
                $openprint::log->debug("old: $width_folds x $height_folds source: $$sig_specs{txtWidth}/$$sig_specs{txtFinalWidth} x $$sig_specs{txtHeight}/$$sig_specs{txtFinalHeight} ") if DEBUG;
                if ( 1 ) {
                  if ( $$Imposition{image_orientation} == openprint::Imposition::Vertical ) {
                    $width_folds = Math::Round::nearest( 1, $$Imposition{layout_width} / $$Imposition{object_width} )-1 if $$Imposition{object_width};
                    $height_folds = Math::Round::nearest( 1, $$Imposition{layout_height}/ $$Imposition{object_height} )-1 if $$Imposition{object_height};
                    if ($$Imposition{spine} eq 'height') {
                      $height_folds -= 1;
                    } else {
                      $width_folds -= 1;
                    }
                  $openprint::log->debug("new: $width_folds x $height_folds from $$Imposition{layout_width} / $$Imposition{object_width} x $$Imposition{layout_height}/ $$Imposition{object_height}") if DEBUG;
                  } else {
                    $width_folds = Math::Round::nearest( 1, $$Imposition{layout_width} / $$Imposition{object_height} ) if $$Imposition{object_height};
                    $height_folds = Math::Round::nearest( 1, $$Imposition{layout_height}/ $$Imposition{object_width} ) if $$Imposition{object_width};
                    if ($$Imposition{spine} eq 'height') {
                      $width_folds -= 1;
                    } else {
                      $height_folds -= 1;
                    }
                  $openprint::log->debug("new: $width_folds x $height_folds x $$Imposition{layout_width} / $$Imposition{object_height} x $$Imposition{layout_height}/ $$Imposition{object_width}") if DEBUG;
                  }

                  if ( $width_folds < 0 ) {
                    $openprint::log->debug("Got negative width_folds from Math::Round::nearest( 1, $$sig_specs{txtWidth}/$$sig_specs{txtFinalWidth})-1");
                    $width_folds = 0;
                  } # end if
                  if ( $height_folds < 0 ) {
                    $openprint::log->debug("Got negative width_folds from $$Imposition{layout_height}/ $$Imposition{object_height}-1");
                    $height_folds = 0;
                  } # end if
                }
              }

              if ($max_feed_width) {
                if ( $orientation ) {
                  if (
                    ( $orientation eq 'Portrait' and $Imposition->layout_width() <= $Imposition->layout_height() ) or
                    ( $orientation eq 'Landscape' and $Imposition->layout_width() >= $Imposition->layout_height() )
                  ) {
                    if ( $Imposition->layout_width() >= $max_feed_width ) {
                      $fits = "Fold no good due to max feed width ($max_feed_width) on width ($$sig_specs{txtWidth}).";
                      $Fold = undef;
                    } # end if
                  } else {
                    if ( $Imposition->layout_height() >= $max_feed_width ) {
                      $fits = "Fold no good due to max feed width ($max_feed_width) on height ($$sig_specs{txtHeight}).";
                      $Fold = undef;
                    } # end if
                  } # end if
                } else {
                  # decide whether it's running portrait or landscape based on which way the folds go
                  $openprint::log->debug("Has max feed width width_folds: $width_folds height_folds: $height_folds final_width $$sig_specs{txtWidth} final_height $$sig_specs{txtHeight} max_feed $max_feed_width") if DEBUG;
                  if ( ( $width_folds and ! $height_folds )
                    #or ( ((!defined $$Fold{folds}) or ($width_folds == $$Fold{folds})) and ((!defined $$Fold{angles}) or ($height_folds == $$Fold{angles})) and ( $width_folds < $height_folds ) )
                  ) {
                    #$if ( $$Imposition{image_orientation} == openprint::Imposition::Vertical ) {
                    # If folds are on width, we grip on height...
                    if ( $$Imposition{layout_height} >= $max_feed_width ) {
                      $fits = "Fold no good due to max feed width ($max_feed_width). $width_folds x $height_folds size: ($$Imposition{layout_height}).";
                      $Fold = undef;
                    } # end if
                    #$} else {
                    #$if ( $$Imposition{layout_width} >= $max_feed_width ) {
                    #$$fits = "Fold no good due to max feed width ($max_feed_width). $width_folds x $height_folds size: ($$Imposition{layout_width}).";
                    #$$Fold = undef;
                    #$} # end if
                    #$} # end if
                  } elsif (
                    ( $height_folds and ! $width_folds )
                    #or ( (!defined $$Fold{folds}) or ($height_folds == $$Fold{folds})) and ((!defined $$Fold{angles}) or ($width_folds == $$Fold{angles}) )
                  ) {
                    #$if ( $$Imposition{image_orientation} == openprint::Imposition::Vertical ) {
                    #$$openprint::log->debug("Vertical $$Imposition{layout_width} >= $max_feed_width");
                    if ( $$Imposition{layout_width} >= $max_feed_width ) {
                      $fits = "Fold no good due to max feed width ($max_feed_width). $width_folds x $height_folds size: ($$Imposition{layout_width}).";
                      $Fold = undef;
                    } # end if
                    #$} else {
                    #$if ( $$Imposition{layout_height} >= $max_feed_width ) {
                    #$$fits = "Fold no good due to max feed width ($max_feed_width). $width_folds x $height_folds size: ($$Imposition{layout_height}).";
                    #$$Fold = undef;
                    #$} # end if
                    #$} # end if
                  } else {
                    $openprint::log->warn("No fold match width_folds: $width_folds, height_folds: $height_folds Fold:$$Fold{name} folds: $$Fold{folds} angles:$$Fold{angles}") if DEBUG;
                  } # end if
                } # end if has an orientation
                $openprint::log->debug($fits) if $fits and DEBUG;
              } # end if orientation
            } # end if max_feed_width

            if ( $Fold ) {
              $Fold = $Fold->clone();
              $$Imposition{Fold} = $Fold;

              push @{$folds{$$Fold{type}.'-'.$$Imposition{imposition}.'out'}}, $Fold;
              $openprint::log->debug(sprintf('Found: %dx%d %s,%dout', @$Imposition{'page_columns','page_rows','image_orientation','imposition'})) if DEBUG;
              next;
            } elsif ( @my_equipment == 1 ) {
              $Imposition->display('Didnt find:' ) if DEBUG;
              $Breakdown .= sprintf('Didnt find: %dx%d=%dpages %s,%dout %s<br/>', @$Imposition{'page_columns','page_rows','pages'},
                  $openprint::Imposition::Orientations{$$Imposition{spine_direction}}, $$Imposition{imposition}, $fits );
              $results{Breakdown} .= $Breakdown;
              $complete = 0;
            } elsif ( DEBUG ) {
              $Imposition->display('Didnt find fold:' );
              $complete = 0;
            } # end if

						$complete = 0;
						# If we get here, then we couldn't find the fold
						$openprint::log->debug("Couldnt find fold, set_index:$set_index < all_impositions: " . ( @All_Impositions-1 ) ) if DEBUG;
					} # end if template or book

					if ( ! $complete ) {
						%folds = ();
						last;
					} # end if
				} # end if Press or not
			} # end foreach Imposition in the set

			if ( DEBUG ) {
				foreach my $key ( keys %folds ) {
					$openprint::log->debug("DUmp folds $key...");
				}
			}

			if ( ! ($complete and %folds) ) {
				$openprint::log->debug('Not complete or ! folds') if DEBUG;
				next;
			} # end if

			my @Used_Impositions = map { $_->copy() } @{$Set_Of_Impositions};

			my $totalTime = 0;

			my $comparison_cost = 0;
			my $totalPrice;
			my $mprice = 0;

			# This copying of the specs is bad.  We need to make it unncessary.  Scoring, perfing, stitching, etc all use the Folds array now...
			my %fold_specs = %$specs;
			$$calc_hash{FoldingSpecs} = \%fold_specs;
			# Going to assume that there is at least 1 fold, so we only have to clear the others
			foreach my $fold_index ( 2 .. 4 ) {
				delete @fold_specs{
					"FoldType-$form-$qty_index-$fold_index",
					"FoldQty-$form-$qty_index-$fold_index",
					"FoldFold-$form-$qty_index-$fold_index",
					"FoldRows-$form-$qty_index-$fold_index",
				};
			} # end foreach fold_index

			# Used as a flag to tell us not to quit early
			my $undesired = 0;

			$fold_specs{"ddmEquipment-$form-$qty_index"} = $$Equipment{id};

			for ( my $imp_index = 0; $imp_index < @Used_Impositions; $imp_index += 1 ) {
				my $Imposition = $Used_Impositions[$imp_index];
				my $Fold = $$Imposition{Fold};
				my $impo_qty = $$Imposition{quantity};
				my $imposition = $$Imposition{imposition};
				my $fold_index = $imp_index + 1;

        $$Imposition{Folder} = $Equipment;
$openprint::log->debug("Resulting fold: " . $Fold->to_string() ) if DEBUG;

				if ( $$Fold{undesired} ) {
					$comparison_cost += 1000;
					$undesired =1;
				}

				$fold_specs{"FoldType-$form-$qty_index-$fold_index"} = $$Fold{type};
				$fold_specs{"FoldQty-$form-$qty_index-$fold_index"} = $$Imposition{quantity};
				$fold_specs{"FoldPageQty-$form-$qty_index-$fold_index"} = $$Imposition{page_quantity};
				$fold_specs{"FoldImposition-$form-$qty_index-$fold_index"} = $$Imposition{imposition};
				$fold_specs{"FoldColumns-$form-$qty_index-$fold_index"} = $$Imposition{columns};
				$fold_specs{"FoldRows-$form-$qty_index-$fold_index"} = $$Imposition{rows};
				$fold_specs{"FoldPageColumns-$form-$qty_index-$fold_index"} = $$Imposition{page_columns};
				$fold_specs{"FoldPageRows-$form-$qty_index-$fold_index"} = $$Imposition{page_rows};
				$fold_specs{"FoldFolds-$form-$qty_index-$fold_index"} = $$Fold{folds};
				$fold_specs{"FoldAngles-$form-$qty_index-$fold_index"} = $$Fold{angles};

        # specs can be empty if we have added a virtual folding service. FIXME
        my $run_qty = $$SignatureImposition{net_sheets};
        if (!$$SignatureImposition{net_sheets}) {
          $openprint::log->error("No net sheets in Siganture impo");
          $run_qty = $$specs{"txtQuantity$qty_index"} ? $$specs{"txtQuantity$qty_index"} : $Project->quantity($qty_index);
          $run_qty /= $$SignatureImposition{imposition};
        }
        $Breakdown .= 'Printed net sheets '.$run_qty;
        if ($impo_qty != 1) {
          $run_qty = POSIX::ceil($run_qty * $impo_qty);
          $Breakdown .= ' folding '.$run_qty.' sheets';
        }

				$openprint::log->debug("Pricing qindex $qty_index runqty: $run_qty impo qty: $impo_qty mipo: $imposition out qty: ".$$specs{"txtQuantity$qty_index"}." Sig imp: $$SignatureImposition{imposition}out	of fold $$Fold{type} on " . $Equipment->name()) if DEBUG;

        $$Fold{makeready_overs_value} = 0;
        if (!$makereadies{$$Equipment{id}}{$$Fold{type}.$imposition}) {
          if ( $$Fold{makeready_overs} ) {
            my $overs = $$Fold{makeready_overs_value} = $$Fold{makeready_overs_units} eq 'Percent' ? POSIX::ceil($run_qty * ( $$Fold{makeready_overs} /100 )) : $$Fold{makeready_overs};
            $Breakdown .= " MR Overs $$Fold{makeready_overs}$$Fold{makeready_overs_units} = $overs";
          } # end if
        } else {
          $Breakdown .= 'MR Overs 0<br/>';
        }
        $$Fold{run_overs_value} = 0;
				if ( $$Fold{run_overs} ) {
					my $overs = $$Fold{run_overs_value} = $$Fold{run_overs_units} eq 'Percent' ? POSIX::ceil($run_qty * ($$Fold{run_overs}/100)) : $$Fold{run_overs};
          $Breakdown .= " Run Overs $$Fold{run_overs}$$Fold{run_overs_units} = $overs";
				} # end if
        $run_qty += $$Fold{makeready_overs_value} + $$Fold{run_overs_value};
        $Breakdown .= ', total folding overs ='.($$Fold{makeready_overs_value} + $$Fold{run_overs_value});
        if ($impo_qty) {
          $$Fold{makeready_overs_value} = POSIX::ceil($$Fold{makeready_overs_value}/$impo_qty);
          $$Fold{run_overs_value} = POSIX::ceil($$Fold{run_overs_value}/$impo_qty);
        }
        $Breakdown .= ' = '.($$Fold{makeready_overs_value} + $$Fold{run_overs_value}).' press sheets<br/>';
				$$Fold{impressions} = $$Imposition{impressions} = $run_qty;

				my $runspeed;
        if ($$Fold{runspeed_units} eq 'calliper') {
          $runspeed = $Fold->RunSpeed($$Paper{calliper});
        } elsif ( $$Fold{runspeed_units} eq 'gsm') {
          $runspeed = $Fold->RunSpeed($Paper->gsm());
        } elsif ( $$Fold{runspeed_units} eq 'impressions') {
          $runspeed = $Fold->RunSpeed($run_qty);
        } # end if units
				if ( $$specs{"OverrideRunspeed-$form-$qty_index-$fold_index"} and ( $$specs{"OverrideRunspeed-$form-$qty_index-$fold_index"} eq 'Y' ) ) {
					$$runspeed{runspeed} = $$specs{"FoldRunspeed-$form-$qty_index-$fold_index"};
        }
				$fold_specs{"FoldRunspeed-$form-$qty_index-$fold_index"} = $$runspeed{runspeed};
				$fold_specs{"FoldImpressions-$form-$qty_index-$fold_index"} = $run_qty;

				# Why are we doing this?  Did we not already do it?
				if ( ! ( $$Fold{folds} or $$Fold{angles} ) ) {
					$$Fold{folds} = $width_folds;
					$$Fold{angles} = $height_folds;
				} # end if
				my $width = $Imposition->layout_width();

				$Breakdown .= sprintf( '%s %s: %d*%dout %s layout: %sx%s qty: %d StockWeight %.2fgsm calliper:%.4f<br/>',
						$fold_types{$$Fold{type}}, $Fold->link_to(), $impo_qty, @$Imposition{'imposition','image_orientation', 'layout_width', 'layout_height'}, $run_qty, @$Paper{'gsm','calliper'} );

				my $total_MR = 0;
				my %setupPrice = openprint::service::get_price_object($$Fold{type}.'MakeReady', $imposition, $Equipment);
				if (!%setupPrice) {
					$openprint::log->debug('No MakeReady for '.$$Fold{type}.'MakeReady ' . $imposition . ' out on ' . $$Equipment{strid} ) if DEBUG;
					%setupPrice = openprint::service::get_price_object('FoldingMakeReady', $imposition, $Equipment);
					%setupPrice = openprint::service::get_price_object('FoldMakeReady', $imposition, $Equipment) if ! %setupPrice;
				} else {
          $openprint::log->debug('Got MakeReady for ' . $Fold->type().'MakeReady' . ' imp:' . $imposition . ' $'.$setupPrice{Price}.' '.($setupPrice{units} ? $setupPrice{units}:'') ) if DEBUG;
        } # end if
        $Breakdown .= '<table><tr><td class="Description">MR: ';
        if (!$setupPrice{units}){
          if (!$makereadies{$$Equipment{id}}{$$Fold{type}.$imposition}) {
            # This is the most common so test for it first.
            $setupPrice{Total} = $setupPrice{Price} //= 0;
            $setupPrice{units} //= '';
            $total_MR += $setupPrice{Total};
            $Breakdown .= sprintf( '($%1$.2f%2$s=$%3$.2f)', @setupPrice{'Price','units','Total'} );
          }
				} elsif ( $setupPrice{units} eq 'per form' ) {
					$setupPrice{Total} = $setupPrice{Price};
					$total_MR += $setupPrice{Total};
					$Breakdown .= sprintf( '($%1$.2f%2$s=$%3$.2f)<br/>', @setupPrice{'Price','units','Total'} );
				} elsif ( ! $makereadies{$$Equipment{id}}{$$Fold{type}.$imposition} ) {
					if ( $setupPrice{units} eq 'per imposition' ) {
						$setupPrice{Total} = $setupPrice{Price} * $imposition;
						$Breakdown .= sprintf( '($%1$.2f%2$s * %4$d out =$%3$.2f)', @setupPrice{'Price','units','Total'}, $imposition );
					} elsif ( $setupPrice{units} eq 'per hour' ) {
						my $makeready_time = eval($$Fold{makeready_time});
						if ( (! $makeready_time) or $? ) {
              $openprint::log->error('No makeready_time on ' . $Fold->to_string() . ': ' . $? );
						}
						$totalTime += $makeready_time;
						$setupPrice{Total} = $setupPrice{Price} * $makeready_time / 60;
						$Breakdown .= sprintf( '($%1$.2f%2$s * %4$d minutes = $%3$.2f)', @setupPrice{'Price','units','Total'}, $makeready_time );
					} else {
						#$Breakdown .= "Unknown Makeready units($setupPrice{units})<br/>";
#$openprint::log->error("No units set on Fold MR " . $setupPrice{Service}->name() . ' on ' . $Equipment->name() );
						$setupPrice{Total} = $setupPrice{Price};
						$Breakdown .= sprintf( '($%1$.2f%2$s=$%3$.2f)', @setupPrice{'Price','units','Total'} );
					} # end if
					$total_MR += $setupPrice{Total};

					if ( $$Fold{folds} and $FoldingFoldMakeReadyService ) {
						my %FoldMakeReady = $FoldingFoldMakeReadyService->get_price( undef, $Equipment );
						if ( $FoldMakeReady{units} eq 'per fold' ) {
							$FoldMakeReady{Total} = $FoldMakeReady{Price} * ($width_folds);
							$total_MR += $FoldMakeReady{Total};
						} # end if
						$Breakdown .= sprintf( ' + FMR: ($%1$.2f%2$s=$%3$.2f)', @FoldMakeReady{'Price','units','Total'} );
					} # end if

					if ( $$Fold{angles} and $FoldingAngleMakeReadyService ) {
						my %AngleMakeReady = $FoldingAngleMakeReadyService->get_price( undef, $Equipment );
						if ( $AngleMakeReady{units} eq 'per angle' ) {
							$AngleMakeReady{Total} = $AngleMakeReady{Price} * ($height_folds);
							$total_MR += $AngleMakeReady{Total};
						} # end if
						$Breakdown .= sprintf( ' + AMR: ($%1$.2f%2$s=$%3$.2f)', @AngleMakeReady{'Price','units','Total'} );
					} # end if
					$Breakdown .= sprintf( ' =</td><td class="Price">$%.2f</td></tr>', $total_MR );
				} else {
					$Breakdown .= 'Already made ready from another form.</td><td></td></tr>';
				} # end if
				$totalPrice += $total_MR;

# In hours
				my $runTime;
				if (!($runspeed and $$runspeed{runspeed})) {
					$Breakdown .= "No runspeed for $$Fold{type}($$Fold{name}) on $$Equipment{name} Setting to 1/Hr.<br/>";
					$$runspeed{runspeed} = 1;
				} # end if
        if ($$runspeed{units} eq 'inches per hour') {
          $runTime = Math::Round::nearest( 0.0001, $run_qty * $Imposition->object_height()/ $$runspeed{runspeed} );
          $Breakdown .= sprintf('<tr><td>Runspeed: %d * %.2f" @ %d/inches per hour = %d:%d:%d</td></tr>',
            $run_qty, $Imposition->object_height(), $$runspeed{runspeed}, misc::seconds_to_interval( int( 3600*$runTime ) ) );
        } else {
          $runTime = Math::Round::nearest( 0.0001, $run_qty / $$runspeed{runspeed} );
          $Breakdown .= sprintf('<tr><td>Runspeed: %d @ %d/HR = %d:%d:%d</td></tr>',
            $run_qty, $$runspeed{runspeed}, misc::seconds_to_interval( int( 3600*$runTime ) ) );
        }
				$$Imposition{runspeed} = $$runspeed{runspeed};
				$openprint::log->debug("Runspeed: $$Fold{type}($$Fold{name}) : $$Equipment{name} $$runspeed{runspeed} $$Paper{gsm}" ) if DEBUG;

#$Breakdown .= sprintf( '&nbsp;Folds: QTY: %d, %dout Runspeed: %d/Hr = %.2f hours<br/>', $qty, $imposition, $$RunSpeed{runspeed}, $runTime );
# We are assuming at this point, that all these folds are posible on this equipment, so any errors are soft errors
				my %servicePrice = openprint::service::get_price_object( 'Folding'.$imposition.'out', $run_qty, $Equipment );
				if ( ! %servicePrice ) {
					%servicePrice = openprint::service::get_price_object( $$Fold{type}, $run_qty, $Equipment );
					if ( ! %servicePrice ) {
						%servicePrice = openprint::service::get_price_object( 'Folding', $imposition, $Equipment );
					} # end if
				} # end if
				my %AnglePrice = openprint::service::get_price_object( 'FoldingAngle'.$imposition.'up', $run_qty, $Equipment );
				%AnglePrice = openprint::service::get_price_object( 'FoldingAngle', $imposition, $Equipment ) if ! %AnglePrice;

				if ( ! $servicePrice{units} ) {
					$Breakdown .= qq`<tr><td colspan="2">No units given for `.$servicePrice{ServiceName}.' on '.$$Equipment{name}.'</td></tr>';
					$servicePrice{Total} += 1000000;
				} elsif ( $servicePrice{units} eq 'per hour' ) {
					$servicePrice{Total} = $servicePrice{Price} * $runTime;
					$Breakdown .= sprintf('<tr><td>Run: %s $%.2f%s * %.2d:%.2d:%.2d =</td><td class="Price">$%.2f</td></tr>', @servicePrice{'ServiceName','Price','units'}, misc::seconds_to_interval(int $runTime*3600), $servicePrice{Total} );
				} elsif ( $servicePrice{units} eq 'per m' or $servicePrice{units} eq 'per 1000' or $servicePrice{units} eq 'per 1000 sheets') {
					my $Base = $Fold->RunSpeed( 0 );
					if ($Base and int($$Base{runspeed})) {
            # Need adjustment
            my $Adjustment = $$Base{runspeed}/$$runspeed{runspeed};
						$servicePrice{Total} = $servicePrice{Price} * ( $run_qty/1000 ) * $Adjustment;
$openprint::log->debug("Adjusting: Base: " . $$Base{runspeed} . ' actual: ' . $$runspeed{runspeed} . ' calculated: ' . $Adjustment );
						$Breakdown .= sprintf('<tr><td>Run: %s $%.2f%s * %d * %f%% runspeed adjustment =</td><td>$%.2f</td></tr>', @servicePrice{'ServiceName','Price','units'}, $run_qty, $Adjustment*100, $servicePrice{Total} );
					} else {
						$servicePrice{Total} = $servicePrice{Price} * $run_qty/1000;
						$Breakdown .= sprintf('<tr><td>Run: $%.2f%s * %d =</td><td class="Price">$%.2f</td></tr>', @servicePrice{'Price','units'}, $run_qty, $servicePrice{Total} );
					} # end if
				} elsif ( $servicePrice{units} eq 'per inch per m' ) {
					$servicePrice{Total} = $servicePrice{Price} * $width * $run_qty / 1000;
					if ( $height_folds ) {
						if ( ! %AnglePrice ) {
							%AnglePrice = %servicePrice;
						} # end if
						$AnglePrice{Total} = $AnglePrice{Price} * $width * $run_qty / 1000;
					} # end if

					$Breakdown .= sprintf('<tr><td>Run: ($%1$.4f%4$s * %4$s&quot;=$%3$.2f) + (%5$.4f%8$s * %4$s&quot;=%7$.2f) =</td><td class="Price">$%8$.2f</td></tr>', @servicePrice{'Price','units','Total'}, $width, @AnglePrice{'Price','units','Total'}, $servicePrice{Total} );
					$servicePrice{Total} += $AnglePrice{Total};
				} elsif ( $servicePrice{units} eq 'per inch of width per m' ) {
					$servicePrice{Total} = $servicePrice{Price} * $Imposition->image_width() * $run_qty / 1000;
					if ( $height_folds ) {
						if ( ! %AnglePrice ) {
							%AnglePrice = %servicePrice;
						} # end if
						$AnglePrice{Total} = $AnglePrice{Price} * $Imposition->image_width() * $run_qty / 1000;
					} # end if

					$Breakdown .= sprintf('<tr><td>Run: ($%3$.4f%4$s * %6$s&quot;=$%5$.2f) + (%7$.4f%8$s * %6$s&quot;=%9$.2f) =</td><td class="Price">$%10$.2f</td></tr>', undef, $$Fold{name}, @servicePrice{'Price','units','Total'}, $$Imposition{image_width}, @AnglePrice{'Price','units','Total'}, $servicePrice{Total}+$AnglePrice{Total} );
					$servicePrice{Total} += $AnglePrice{Total};
				} elsif ( $servicePrice{units} eq 'per inch per hour' ) {
					$servicePrice{Total} = $servicePrice{Price} * $$sig_specs{txtWidth} * $runTime;
					$Breakdown .= sprintf('<tr><td>Run: $%.4f%s * %d folds * %s&quot; + %d folds * %s&quot; =</td><td class="Price">$%.2f</td></tr>',$$Fold{name}, @servicePrice{'Price','units'}, $width_folds, $$sig_specs{txtWidth}, $height_folds, $$sig_specs{txtHeight}, $servicePrice{Total} );
				} elsif ( %servicePrice ) {
					$Breakdown .= qq`<tr><td>No Units ($servicePrice{units}) given for `.$$Fold{name}.' on '.$$Equipment{name}.',</td></tr>';
					$servicePrice{Total} += 1000000;
				} else {
					$Breakdown .= qq`<tr><td colspan="2">No Price given for `.$$Fold{type}.' on '.$$Equipment{name}.'</td></tr>';
				} # end if

				$mprice += $servicePrice{Total};
				$totalPrice += $servicePrice{Total};

				$totalTime += $runTime * 3600;
				$$Imposition{price} = $totalPrice;
			} # end foreach folded Imposition
			$comparison_cost += $totalPrice;

			my %cutting_results = ( alert=>'', Breakdown=>'', Price=>0 );
			if ($$calc_hash{HasCutting}) {
        #%cutting_results = openprint::Estimating::Cutting::signature_calc_folding_cutting( $Project, $sig_specs, $$calc_hash{cutting_specs}, $qty_index, $Paper, $SignatureImposition, \%fold_specs, $calc_hash );
        #%cutting_results = openprint::Estimating::Cutting::signature_calc( $Project, $sig_specs, $$calc_hash{cutting_specs}, $qty_index, $Paper, $SignatureImposition, \%fold_specs, $calc_hash );
        #$Breakdown .= '<tr><td>Cutting:'.$cutting_results{Status}.' '.$cutting_results{Breakdown}.'</td><td class="Price">$' . sprintf($openprint::config{ProjectMoneyFormat}, $cutting_results{FoldingPrice}) . '</td></tr>';
        #$Breakdown .= '<tr><td>Cutting:'.$cutting_results{Status}.' '.$cutting_results{Breakdown}.'</td><td class="Price">$' . sprintf($openprint::config{ProjectMoneyFormat}, $cutting_results{FoldingPrice}) . '</td></tr>';
        #$$specs{alert} .= $cutting_results{alert} if $cutting_results{alert};
        #$totalPrice += $cutting_results{FoldingPrice};
			} # end if
			$Breakdown .= '<tr><td>Folding total:</td><td class="Price">$' . sprintf($openprint::config{ProjectMoneyFormat}, $totalPrice) . '</td></tr>';
			$$SignatureImposition{Folds} = \@Used_Impositions;
      if ($$calc_hash{HasCollating}) {
				my %collating_results = openprint::Estimating::Collating::internal_calc( $Project, $$calc_hash{CollatingSpecs}, $qty_index, $Signature_Impositions, $calc_hash );
        $Breakdown .= '<tr><td>'.$collating_results{Breakdown}.'</td><td></td></tr>';
        $Breakdown .= '<tr><td>Collating total:</td><td class="Price">$' . sprintf($openprint::config{ProjectMoneyFormat}, $collating_results{Total}) . '</td></tr>';
			  $comparison_cost += $collating_results{Total};
      }
      if ($$calc_hash{HasPerfectBound}) {
        my $perfectbound_part = 0;
        my $perfectbound_specs = $$calc_hash{PerfectBoundSpecs};
        my $perfectbound_results = openprint::Estimating::PerfectBound::signature_calc(
          $Project, $$calc_hash{HasPerfectBound}, $perfectbound_specs, $qty_index, $Signature_Impositions, $calc_hash );
        if ( ! $$perfectbound_results{Equipment} ) {
          $$perfectbound_results{alert} //= '';
          $$perfectbound_results{Breakdown} //= '';
          $Breakdown .= "unable to determine perfectbound equipment: $$perfectbound_results{alert} $$perfectbound_results{Breakdown}<br/>";
          $openprint::log->warn('unable to determine perfectbound equipment: '.$Breakdown) if DEBUG;

          $perfectbound_part = 1000000;
          #$totalPrice += 1000000;
        } elsif ( $$perfectbound_results{Equipment}{id} != $$Equipment{id} and ( $capable eq 'When PerfectBound' ) ) {
          $Breakdown .= 'Not perfectbinding on ' . $$Equipment{strid}.' perfectbinding on '.$$perfectbound_results{Equipment}{strid} .'.<br/>';
          #$Breakdown .= $$stitching_results{Breakdown} . '<br/>';
          $Breakdown .= $$perfectbound_results{alert};
          $perfectbound_part = 1000000;
          $totalPrice += 1000000;
        } else {
          my $Price = $$perfectbound_results{Price};
          $perfectbound_part = $$Price{Price};
          #$Breakdown .= '<tr><td>'.$$stitching_results{Breakdown}.'</td></tr>' if DEBUG;
          $Breakdown .= sprintf('<tr><td>Stitching cost on %s %dout %dpockets</td><td class="Price">$%.2f</td></tr>',
            $$perfectbound_results{Equipment}{name}, @$perfectbound_results{'Imposition','pockets'}, $perfectbound_part );
        } # end if
        #$Breakdown .= $$results{Breakdown}.'<br/>';
        #} elsif ( $$specs{StitchingEquipment}{id} != $$Equipment{id} and $Equipment->specification('Folding Capable') eq 'When Stitching' ) {
        #$Breakdown .= '<tr><td>Not stitching on ' . $$Equipment{strid}.' stitching on '.$$specs{StitchingEquipment}{strid} .'.</td></tr>';
        $comparison_cost += $perfectbound_part;
      } # end if has perfectbound

			my $stitching_part = 0;
			if ( $$calc_hash{HasStitching} ) {
				if ( ! exists $$specs{StitchingCost} ) {
# Add in stitching estimate, based on if the folder is this piece of equipment
					$fold_specs{"Price-$form-$qty_index"} = $totalPrice;
					#$Breakdown .= '<tr><td>Signatures:'.(@$Signature_Impositions+1).'</td></tr>';
					my $stitching_specs;
					if (
							( $capable eq 'When Stitching' or $capable eq 'When Binding' or $capable eq 'When Perfect Bound' )
							and
							(!($$calc_hash{StitchingSpecs}{"chkOverrideEquipment$qty_index"}))
						 ) {
						# Make a copy of the specs so we don't clobber the real specs.  Set the override to this stitcher and see how it calcs.
						$stitching_specs = $$calc_hash{FoldingStitchingSpecs};
						$$stitching_specs{"ddmEquipment$qty_index"} = $$Equipment{id};
#$openprint::log->error("Using temp stitching specs " . $$calc_hash{StitchingSpecs}{"chkOverrideEquipment$qty_index"} . ' override: ' . $$stitching_specs{"chkOverrideEquipment$qty_index"});
					} else {
						$stitching_specs = $$calc_hash{StitchingSpecs};
					} # end if

					my $stitching_results = openprint::Estimating::Stitching::signature_calc(
							$Project, $$calc_hash{HasStitching}, $stitching_specs, $qty_index, $Signature_Impositions, $calc_hash );
					if ( ! $$stitching_results{Equipment} ) {
            $$stitching_results{alert} //= '';
            $$stitching_results{Breakdown} //= '';
						$Breakdown .= "unable to determine stitching equipment: $$stitching_results{alert} $$stitching_results{Breakdown}<br/>";
						$openprint::log->warn('unable to determine stitching equipment: '.$Breakdown) if DEBUG;

						$stitching_part = 1000000;
						#$totalPrice += 1000000;
					} elsif ( $$stitching_results{Equipment}{id} != $$Equipment{id} and ( $capable eq 'When Stitching' ) ) {
						$Breakdown .= 'Not stitching on ' . $$Equipment{strid}.' stitching on '.$$stitching_results{Equipment}{strid} .'.<br/>';
            #$Breakdown .= $$stitching_results{Breakdown} . '<br/>';
						$Breakdown .= $$stitching_results{alert};
						$stitching_part = 1000000;
						$totalPrice += 1000000;
					} else {
						my $Price = $$stitching_results{Price};
						$stitching_part = $$Price{Price};
            #$Breakdown .= '<tr><td>'.$$stitching_results{Breakdown}.'</td></tr>' if DEBUG;
						$Breakdown .= sprintf('<tr><td>Stitching cost on %s %dout %dpockets</td><td class="Price">$%.2f</td></tr>',
								$$stitching_results{Equipment}{name}, @$stitching_results{'Imposition','pockets'}, $stitching_part );
					} # end if
					#$Breakdown .= $$results{Breakdown}.'<br/>';
				} elsif ( $$specs{StitchingEquipment}{id} != $$Equipment{id} and $Equipment->specification('Folding Capable') eq 'When Stitching' ) {
					$Breakdown .= '<tr><td>Not stitching on ' . $$Equipment{strid}.' stitching on '.$$specs{StitchingEquipment}{strid} .'.</td></tr>';
				} else {
					$stitching_part = $$specs{StitchingCost};
					$Breakdown .= sprintf('<tr><td>Stitching cost on %s</td><td class="Price">$%.2f</td></tr>', $$specs{StitchingEquipment}{name}, $stitching_part );
				} # end if
			} # end if has stitching
			$comparison_cost += $stitching_part;
# + $cutting_results{Price};

      if (0) {
      if ( defined $bestComparison ) {
        if ( $comparison_cost > $bestComparison ) {
          $openprint::log->debug("Bailing early because comparison $comparison_cost > best $bestComparison") if DEBUG;
          next;
        } elsif ( DEBUG ) {
          $openprint::log->debug("Not bailing early because comparison $comparison_cost < best $bestComparison");
        }
      }
      }

			if ( $scoring_signature_needs ) {
				$$calc_hash{FoldingSpecs} = \%fold_specs;
				my %scoring_results = openprint::Estimating::Scoring::signature_calc( $Project, $$calc_hash{ScoringSpecs}, $sig_specs, $qty_index, $SignatureImposition, $calc_hash, \@Used_Impositions );
				if ( $scoring_results{Status} eq 'uncalculated' ) {
					$Breakdown .= "<tr><td>Scoring uncalculated $scoring_results{alert}</td><td class=\"Price\">\$1000000</a>";
					$comparison_cost += 1000000;
				} else {
#$Breakdown .= "<tr><td>Scoring cost on $scoring_results{Equipment}{name}</td><td class=\"Price\">\$$scoring_results{Price}</a>";
					$Breakdown .= "<tr><td>Scoring cost on $scoring_results{Equipment}{name}<br/>";
          #$Breakdown .= $scoring_results{Breakdown};
          $Breakdown .= "</td><td class=\"Price\">\$$scoring_results{Price}</td></tr>";
					$comparison_cost += $scoring_results{Price};
				}
			} # end if

			#if ( $cutting_results{Equipment} ) {
				#$Breakdown .= qq`<tr><td>Cutting on $cutting_results{Equipment}{name}</td><td class="Price">$cutting_results{Price}</td></tr>`;
			#} else {
				#$Breakdown .= qq`<tr><td>No Cutting: $cutting_results{alert} $cutting_results{Breakdown}</td><td class="Price">$cutting_results{Price}</td></tr>`;
			#} # end if

			$Breakdown .= '<tr><td>comparison :</td><td class="Price">$' . sprintf('%.2f', Math::Round::nearest(0.01,$comparison_cost) ). ' </td></tr>';
			$Breakdown .= '</table><br/>';

			if ( ( ! defined $bestComparison ) or ( $comparison_cost < $bestComparison ) ) {
$openprint::log->debug("Got better price for qty $qty_index sig $form ".(defined $totalPrice ? $totalPrice : 'undef').' < '.(defined($bestPrice) ? $bestPrice : 'undef')." comparison $comparison_cost < ".(defined($bestComparison) ? $bestComparison : undef).' '.$Equipment->name() ) if DEBUG;
				$bestM = $mprice;
				$bestComparison = $comparison_cost;
				$bestPrice = $totalPrice;
				$bestEquipment = $Equipment;
				$bestRunTime = int($totalTime);
				$bestFolds = \%folds;
				$bestImpositions = \@Used_Impositions;
        $bestBreakdown = $Breakdown;
      } else {
$openprint::log->debug("NotGot better price for qty $qty_index sig $form ".(defined $totalPrice ? $totalPrice : 'undef').' < '.(defined($bestPrice) ? $bestPrice : 'undef')." comparison $comparison_cost < ".(defined($bestComparison) ? $bestComparison : undef).' '.$Equipment->name() ) if DEBUG;
			} # end if
		} # end foreach set of Impositions

		# The idea is that if we find a price on the press, then we are done, cuz nothing else will be better....
		# Can't quit early ... case of digital cover on offset interior, stitched... the stitcher does the cover
		#last if $bestPrice and ( $Equipment->strid() eq $$sig_specs{'ddmPress'.$qty_index} );
	} # end foreach Equipment

	%results = (
		Comparison				=>	$bestComparison,
		Price							=>	$bestPrice,
		MPrice						=>	( $$specs{'txtQuantity'.$qty_index} ? ($bestM/$$specs{'txtQuantity'.$qty_index})*1000 : 0 ),
		Equipment					=>	$bestEquipment,
		Status						=>	$bestEquipment ? 'calculated' : 'uncalculated',
		Folds							=>	$bestFolds,
		Breakdown					=>	$bestBreakdown,
		FoldedImpositions	=>	$bestImpositions,
		MakeReadyTime			=>	0,
		MakeReadyOvers		=>	0,
		RunOvers					=>	0,
		);

	foreach my $FI ( @{$bestImpositions} ) {
		my $Fold = $$FI{Fold};
		if ( ! $$Fold{equipment_id} ) {
			$$Fold{equipment_id} = $$bestEquipment{id};
			$openprint::log->warn('Fold didnt have equipment');
		}
		$FI->Equipment( $Fold->Equipment() );

		$results{MakeReadyTime} = $$Fold{makeready_time} if $results{MakeReadyTime} < $$Fold{makeready_time};
		$results{MakeReadyOvers} += $$Fold{makeready_overs_value} if $$Fold{makeready_overs_value};
		$results{RunOvers} += $$Fold{run_overs_value} if $$Fold{run_overs_value};
	} # end foreach

	return \%results;
} # end sub signature_calc

sub load_equipment {
	my ( $Project ) = @_;
	my $services = $Project->services();

  my $Service = $Project->Service( $$services{Folding}[0] ) if $$services{Folding};
  my @folding_capable;
  if ($Project->Type()->name() eq 'PresentationFolders') {
    push @folding_capable, 'For Pocket Folders';
  } else {
    foreach my $sig_id ($Project->signatures()) {
      my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
      $openprint::log->debug("Template type for $sig_id ".$$sig_specs{rdbTemplateType});
      if ($$sig_specs{rdbTemplateType} and sets::isin($$sig_specs{rdbTemplateType}, ['2Panel1Pocket','2Panel2Pocket','3Panel2Pocket','TriFoldDoublePocket'])) {
        push @folding_capable, 'For Pocket Folders';
        $openprint::log->error("Have pocket folders");
        last;
      }
    } # end foreach sig
  }

	push @folding_capable, 'When PerfectBound' if $$services{PerfectBound};
	push @folding_capable, 'When Stitching' if ( $$services{SaddleStitching} or $$services{LoopStitching} );
	push @folding_capable, 'When Printing';
	push @folding_capable, 'Y';
	@equipment = openprint::Equipment->find( 'useinestimating is null or ='=>1,
# 'servicetype_id any'=>$Service->servicetype_id(),
Specifications=>{'Folding Capable'=>\@folding_capable}
 ) if $Service;
} # end sub load_equipment

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	if (!$project_index or !$service_index) {
		$log->debug('calc_folding called without ProjectIndex or ServiceIndex!');
		return;
	} # end if

	# sig_calc overwrites $$specs{Status}, so we keep our own copy
	my $status = 'calculated';
	$$specs{alert} = '';

	my $Project = new openprint::Project( $project_index );
	if ( ! neccessary( $Project ) ) {
		$$specs{alert} .= 'Folding is not needed.';
	} # end if
	my $services = $Project->services();
	my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );

	my $calc_hash = {};
  $$calc_hash{ProjectSpecs} = $printing_specs;
	if ( $$services{SaddleStitching} ) {
		%{$$calc_hash{StitchingSpecs}} = %{openprint::service::get_specs_ref( $Project, $$services{SaddleStitching}[0] )};
		$$calc_hash{HasStitching} = $$services{SaddleStitching}[0];
	} elsif ( $$services{LoopStitching} ) {
		%{$$calc_hash{StitchingSpecs}} = %{openprint::service::get_specs_ref( $Project, $$services{LoopStitching}[0] )};
		$$calc_hash{HasStitching} = $$services{LoopStitching}[0];
	} elsif ( $$services{PerfectBound} and $$services{PerfectBound}[0]) {
		%{$$calc_hash{PerfectBoundSpecs}} = %{openprint::service::get_specs_ref( $Project, $$services{PerfectBound}[0] )};
		$$calc_hash{HasPerfectBound} = $$services{PerfectBound}[0];
	}
	if ( $$calc_hash{HasStitching} ) {
		#This is a copy used as a temp space for overriding the stitcher
		%{$$calc_hash{FoldingStitchingSpecs}} = %{$$calc_hash{StitchingSpecs}};
		$$calc_hash{FoldingStitchingSpecs}{"chkOverrideEquipment1"} = 'Y';
		$$calc_hash{FoldingStitchingSpecs}{"chkOverrideEquipment2"} = 'Y';
		$$calc_hash{FoldingStitchingSpecs}{"chkOverrideEquipment3"} = 'Y';
	} # end if
	foreach my $service ( 'UVCoating', 'Aqueous', 'Cutting', 'Scoring', 'Folding', 'Collating' ) {
		if ( $$services{$service} and @{$$services{$service}} ) {
			$$calc_hash{"Has$service"} = $$services{$service}[0];
			$$calc_hash{"${service}Specs"} = openprint::service::get_specs_ref( $Project, $$services{$service}[0] );
		}
	} # end foreach
  if ($$calc_hash{HasCutting}) {
    openprint::Estimating::Cutting::init( $Project, $calc_hash );
  }
	if ( $$services{Scoring} ) {
		openprint::Estimating::Scoring::init( $Project, $calc_hash );
	}
	if ( $$services{Perforating} and @{$$services{Perforating}} ) {
		$$calc_hash{PerforatingSpecs} = openprint::service::get_specs_ref( $Project, $$services{Perforating}[0] );
	} # end if

	init($Project, $calc_hash);
	load_equipment( $Project );
	$openprint::log->debug("Have Equipment " . join(',', map { $_->strid() } @equipment ) ) if DEBUG;

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"txtPrice$qty_index"} =~ s/[^\d\.]//g if $$specs{"txtPrice$qty_index"};
		$$specs{"Markup$qty_index"} =~ s/[^\d\.\-]//g if $$specs{"Markup$qty_index"};
		$$specs{"txtQuantity$qty_index"} =~ s/[^\d\.]//g if $$specs{"txtQuantity$qty_index"};
		if ( ! $$specs{"txtQuantity$qty_index"} ) {
			$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
			if ( @{$$services{Folding}} > 1 ) {
				foreach my $s_id ( @{$$services{Folding}} ) {
					next if $s_id >= $service_index;
					my $folding_specs = openprint::service::get_specs_ref( $Project, $s_id );
					$$specs{"txtQuantity$qty_index"} -= $$folding_specs{'txtQuantity'.$qty_index};
				} # end foreach
			} # end if
			@no_outputs = sets::exclude( ['txtQuantity'.$qty_index], \@no_outputs );
		} else {
			@no_outputs = sets::union( 'txtQuantity'.$qty_index, @no_outputs );
		} # end if
		next if ! int $$specs{"txtQuantity$qty_index"};
		$$specs{'hdnBreakdown'.$qty_index} = '';

		my $price = 0;
		my $mprice = 0;

		my @signatures = $Project->signatures( { sort => 1 } );
$openprint::log->debug("Signatures: @signatures") if DEBUG;
		my @Signature_Impositions;
		my %Impositions;
		foreach my $sig_id ( @signatures ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
			my $form = $$sig_specs{SignatureIndex};
			if ( ! $$sig_specs{'txtImposition'.$qty_index} ) {
				$openprint::log->debug("No imp in signature $form") if DEBUG;
				next;
			} # end if
			my $i = new openprint::Imposition();
			$i->load( $sig_specs, $qty_index, $Project );
			$$i{Folds} = [ get_Folds( $specs, $i, $qty_index ) ];
			push @Signature_Impositions, $i;
      $i->display() if DEBUG;

			$Impositions{$sig_id} = $i;
			$$i{service_id} = $sig_id;

			if ( (!$$specs{"chkOverrideFold-$form-$qty_index"}) or ($$specs{"chkOverrideFold-$form-$qty_index"} ne 'Y') ) {
				foreach my $index ( 1 .. 4 ) {
					foreach my $k (
					"FoldType-$form-$qty_index-$index",
					"FoldQty-$form-$qty_index-$index",
					"FoldPageQty-$form-$qty_index-$index",
					"FoldPageColumns-$form-$qty_index-$index",
					"FoldPageRows-$form-$qty_index-$index",
					"FoldImposition-$form-$qty_index-$index",
					"FoldColumns-$form-$qty_index-$index",
					"FoldRows-$form-$qty_index-$index",
					"FoldFolds-$form-$qty_index-$index",
					"FoldAngles-$form-$qty_index-$index",
					) {
            $$specs{$k} = '';
				};
				$$specs{"FoldRunspeed-$form-$qty_index-$index"} = '' if (!$$specs{"OverrideRunspeed-$form-$qty_index-$index"}) or $$specs{"OverrideRunspeed-$form-$qty_index-$index"} ne 'Y';
				} # end for
			} # end if
		} # end foreach signature

		foreach my $signature_service_index ( @signatures ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
			my $form = $$sig_specs{SignatureIndex};
			$$specs{'hdnBreakdown'.$qty_index} .= "<fieldset><legend>Signature: $form ";
      $$specs{'hdnBreakdown'.$qty_index} .= $$sig_specs{txtSignatureType} if $$sig_specs{txtSignatureType};
      $$specs{'hdnBreakdown'.$qty_index} .= ' Ref: '.$$sig_specs{txtServiceDescription} if $$sig_specs{txtServiceDescription};
      $$specs{'hdnBreakdown'.$qty_index} .= ':</legend>';
			$$specs{'hdnBreakdown'.$qty_index} .= openprint::service::summary( $Project, $signature_service_index ) . '<br/>';
			#$$specs{'hdnBreakdown'.$qty_index} .= openprint::service::summary( $Project, $signature_service_index, $qty_index ) . '<br/>';

			if ( ! $$sig_specs{'txtImposition'.$qty_index} ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'No imposition.</fieldset>';
$openprint::log->debug("No imposition for form $form") if DEBUG;
				next;
			} # endif

			if ( (! signature_needs( $Project, $sig_specs, $qty_index ) ) and ( $$specs{"chkOverrideFold-$form-$qty_index"} ne 'Y' ) ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'Not needed.</fieldset>';
$openprint::log->debug("Not needed for form $form") if DEBUG;
				next;
			} # end if

			my $Imposition = $Impositions{$signature_service_index};
			$$specs{'hdnBreakdown'.$qty_index} .= $Imposition->to_string();

      my $results = signature_calc( $Project, $sig_specs, $specs, $qty_index, $Imposition, \@Signature_Impositions, $calc_hash );
    #$openprint::log->debug( Data::Dumper::Dumper($results) );
      #my %results = signature_calc( $Project, $sig_specs, $specs, $qty_index, $Imposition, [ sets::exclude( [ $Imposition ], \@Signature_Impositions ) ], $calc_hash );
      $$specs{'hdnBreakdown'.$qty_index} .= $$results{Breakdown} if $$results{Breakdown};
      #$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<br/>MR Waste: %d, Run Waste: %d<br/>', @$results{'MakeReadyOvers','RunOvers'} );
      $$specs{"Price-$form-$qty_index"} = $$results{Price};
      $price += $$results{Price} if $$results{Price};
      $mprice += $$results{MPrice};
      if ( $$results{Equipment} ) {
        if ( (!$$specs{"chkOverrideEquipment-$form-$qty_index"}) or ($$specs{"chkOverrideEquipment-$form-$qty_index"} ne 'Y') ) {
          $$specs{"ddmEquipment-$form-$qty_index"} = $$results{Equipment}->id();
        } else {
          @no_outputs = sets::exclude( [ "ddmEquipment-$form-$qty_index" ], \@no_outputs );
        } # end if

        my $index = 1;
        $$Imposition{Folds} = $$results{FoldedImpositions};
$log->debug("# of FOlded Impositions in results" . @{$$results{FoldedImpositions}} );
        foreach my $FI ( @{$$results{FoldedImpositions}} ) {
          my $Fold = $$FI{Fold};
          my $fold_type = $Fold->type();

          if ( 0 and DEBUG ) {
            $openprint::log->debug("Foldtype: $fold_type " . $$FI{imposition} . "out $$Fold{name} $$Fold{folds} $$Fold{angles}" );
            $Imposition->display(" Runspeed: $$FI{runspeed}");
          }
          $$specs{"FoldType-$form-$qty_index-$index"} = $fold_type;
          $$specs{"FoldQty-$form-$qty_index-$index"} = $$FI{quantity};
          $$specs{"FoldPageQty-$form-$qty_index-$index"} = $$FI{page_quantity};
          $$specs{"FoldPageColumns-$form-$qty_index-$index"} = $$FI{page_columns};
          $$specs{"FoldPageRows-$form-$qty_index-$index"} = $$FI{page_rows};
          $$specs{"FoldImposition-$form-$qty_index-$index"} = $$FI{imposition};
          $$specs{"FoldColumns-$form-$qty_index-$index"} = $$FI{columns};
          $$specs{"FoldRows-$form-$qty_index-$index"} = $$FI{rows};
          $$specs{"FoldFolds-$form-$qty_index-$index"} = $Fold->folds();
          $$specs{"FoldAngles-$form-$qty_index-$index"} = $Fold->angles();
          $$specs{"FoldRunspeed-$form-$qty_index-$index"} = $$FI{runspeed};
          $index += 1;
        } # end foreach fold
      } else {
        if ( ! $$specs{"chkOverrideEquipment-$form-$qty_index"} ) {
          $$specs{"ddmEquipment-$form-$qty_index"} = '';
        } elsif ( $$specs{"ddmEquipment-$form-$qty_index"} ) {
          $status = 'uncalculated';
          $$specs{alert} .= "Unable to fold form $form qty $qty_index<br/>";
        } # end if
      } # end if
      if ( $$results{Status} eq 'uncalculated' ) {
        $status = 'uncalculated';
      } # end if
			$$specs{'hdnBreakdown'.$qty_index} .= '</fieldset>';
		} # end foreach signature
		if ( $status eq 'uncalculated' and ! $$specs{alert} ) {
			$$specs{alert} .= 'Unable to fold for qty '.$qty_index.'.<br/>';
		} # end if

		if ( $$specs{'Markup'.$qty_index} ) {
			my $markup = 1+$$specs{'Markup'.$qty_index}/100;
$openprint::log->warn("Applying markup: $markup from specs " . $$specs{'Markup'.$qty_index} );
			$price *= $markup;
			$mprice *= $markup;
		}
		if ( $Project->markup() ) {
			my $markup = 1+$Project->markup()/100;
$openprint::log->warn("Applying markup: $markup from project $$Project{markup}");
			$price *= $markup;
			$mprice *= $markup;
		}

		if ( (!$$specs{'OverridePrice'.$qty_index}) or ($$specs{'OverridePrice'.$qty_index} ne 'Y') ) {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $price);
		} else {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"} );
		} # end if
		$$specs{"MPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $mprice );
	} # end foreach qty
	$log->debug(" END FOLDING!!!!!!!!!!!!!!!!!! $status");
	return $$specs{Status} = $status;
} # end sub calc

sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

	my $Project = new openprint::Project( $project_index );

	load_equipment($Project);
	@{$$variable{EquipmentArray}} = map { $_->id(), $_->name() } @equipment;
} # end sub display

sub signature_summary {
	my ( $Project, $service_index, $specs, $qty_index, $s_id, $sig_specs ) = @_;
	$specs = openprint::service::get_specs_ref( $Project, $service_index ) if ! $specs;
	$sig_specs = openprint::service::get_specs_ref( $Project, $s_id ) if ! $sig_specs;
	my $form = $$sig_specs{SignatureIndex};
	if ( $qty_index ) {
		if ( ! $$sig_specs{"txtImposition$qty_index"} ) {
			return '';
		} # end if
		my @folds;
		if ( ( defined $$specs{"chkOverrideEquipment-$form-$qty_index"} ) and ( $$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' ) and ! $$specs{"ddmEquipment-$form-$qty_index"} ) {
			return 'not folded';
		} elsif ( $$specs{"ddmEquipment-$form-$qty_index"} ) {
			my $Equipment = new openprint::Equipment( $$specs{"ddmEquipment-$form-$qty_index"} );
			foreach my $fold_index ( 1 .. 4 ) {
				next if ! $$specs{"FoldQty-$form-$qty_index-$fold_index"};
				push @folds, sprintf('%1$d %3$s %2$dout', @$specs{
						"FoldQty-$form-$qty_index-$fold_index",
						"FoldImposition-$form-$qty_index-$fold_index",
						"FoldType-$form-$qty_index-$fold_index"} );
			} # end foreach
			my $html = join('<br/>', ( ' on ' . $Equipment->name() ), sort { $a cmp $b } @folds);
			my $Press = openprint::Equipment->find_one( strid => $$sig_specs{"ddmPress$qty_index"} );
      if ( $Press and ( $$Press{id} != $$Equipment{id} ) ) {
        my $type = $Equipment->specification('Type');
        if ($type and $type eq 'Folder') {
          #and ($Press->specification('Folding Capable') eq 'When Printing')
          $html .= '<br/><span class="warning">Folding Offline</span>';
        }
      }
      return $html;
		} # end if
	} # end if
	return '';
} # end sub signature_summary

sub overview_signature_summary {
	my ( $Project, $service_index, $specs, $qty_index, $s_id, $sig_specs ) = @_;
	$specs = openprint::service::get_specs_ref( $Project, $service_index ) if ! $specs;
	$sig_specs = openprint::service::get_specs_ref( $Project, $s_id ) if ! $sig_specs;
	if ( ! $$sig_specs{"txtImposition$qty_index"} ) {
		return '';
	} # end if
	my $form = $$sig_specs{SignatureIndex};
	my @folds;
	if (
			( defined $$specs{"chkOverrideEquipment-$form-$qty_index"} )
			and
			( $$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' )
			and
			! $$specs{"ddmEquipment-$form-$qty_index"}
		 ) {
		return 'not folded';
	} elsif ( $$specs{"ddmEquipment-$form-$qty_index"} ) {
		my $Equipment = new openprint::Equipment( $$specs{"ddmEquipment-$form-$qty_index"} );
		foreach my $fold_index ( 1 .. 4 ) {
			next if ! $$specs{"FoldQty-$form-$qty_index-$fold_index"};
			push @folds, sprintf('%1$d %3$s %2$dout', @$specs{
					"FoldQty-$form-$qty_index-$fold_index",
					"FoldImposition-$form-$qty_index-$fold_index"},
					$short_fold_names{$$specs{"FoldType-$form-$qty_index-$fold_index"}},
					);
		} # end foreach
		my $html = join('<br/>', sort { $a cmp $b } @folds);
		#my $Press = openprint::Equipment->find_one( strid => $$sig_specs{"ddmPress$qty_index"} );
		#if ( $Press and ( $$Press{id} != $$Equipment{id} ) 
				#and ( $Equipment->specification('Type') eq 'Folder' )
##and ($Press->specification('Folding Capable') eq 'When Printing')
			 #) {
		#}
		return $html;
	} # end if
	return '';
} # end sub overview_signature_summary

sub is_offline {
	my ( $Project, $qty_index ) = @_;

	my $services = $Project->services();
	if ( ! $$services{Folding} ) {
		return 0;
	}

	foreach my $sig_id ( $Project->signatures() ) {
		my $fold_specs = openprint::service::get_specs_ref( $Project, $$services{Folding}[0] );
		my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
		my $form = $$sig_specs{SignatureIndex};

		if ( ! $$sig_specs{"txtImposition$qty_index"} ) {
			next;
		} # end if
		if ( ( defined $$fold_specs{"chkOverrideEquipment-$form-$qty_index"} )
				and
				( $$fold_specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' )
				and
				! $$fold_specs{"ddmEquipment-$form-$qty_index"}
			 ) {
			next;
		}
		if ( $$fold_specs{"ddmEquipment-$form-$qty_index"} ) {
			my $Equipment = new openprint::Equipment( $$fold_specs{"ddmEquipment-$form-$qty_index"} );
			my $Press = openprint::Equipment->find_one( strid=>$$sig_specs{"ddmPress$qty_index"} );
			if ( $Press and ( $$Press{id} != $$Equipment{id} ) 
and ( $Equipment->specification('Type') eq 'Folder' )
#and ($Press->specification('Folding Capable') eq 'When Printing' )
 ) {
				return 1;
			}
		} # end if
	} # end foreach sig
	return 0;
} # end sub is_offline

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	if ( $qty_index ) {
		my $html;
		my $cur_sig_specs;
		my @signatures = $Project->signatures( { sort=>1 } );

		for ( my $sig_index = 0; $sig_index < @signatures; $sig_index += 1 ) {
			my $s_s_id = $signatures[$sig_index];
			my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
			my $form = $$sig_specs{SignatureIndex};
			if ( ! $$sig_specs{"txtImposition$qty_index"} ) {
				next;
			} # end if

			my $Imposition1 = new openprint::Imposition();
			$Imposition1->load( $sig_specs, $qty_index, $Project );

			my $sig_count = 1;

			if ( $sig_index < @signatures - 1 ) {
				for ( my $sig_index2 = $sig_index + 1; $sig_index2 < @signatures; $sig_index2 += 1 ) {
					my $sig_specs2 = openprint::service::get_specs_ref( $Project, $signatures[$sig_index2] );
					my $Imposition2 = new openprint::Imposition();
					$Imposition2->load( $sig_specs, $qty_index, $Project );
					if ( openprint::Estimating::Printing::compare_signatures( $Project, $sig_specs, $sig_specs2, $qty_index )
						and compare_folds( $specs, $Imposition1, $Imposition2, $qty_index )
						) {
						$sig_count += 1;
					} else {
						last;
					} # end if
				} # end for
				splice @signatures, $sig_index+1,$sig_count-1 if $sig_count > 1;
			}
			my $summary = signature_summary( $Project, $service_id, undef, $qty_index, $s_s_id, undef );
			if ( $sig_count > 1 ) {
				$html .= ($sig_count) . ' Forms ' . ($$sig_specs{txtServiceDescription} ? $$sig_specs{txtServiceDescription} :'');
			} else {
				$html .= 'Form ' . $form . ($$sig_specs{txtServiceDescription} ? ' ' . $$sig_specs{txtServiceDescription} : '');
			} # end if
			$html .= ' ' . ( $summary eq 'not folded' ? $summary : ' ' . $summary ) . "\n";
		} # end foreach
		return $html;
	} # end if

	return '';
} # end sub summary

sub overview_summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	my $html;
	my $cur_sig_specs;
	my @signatures = $Project->signatures( { sort=>1 } );

	for ( my $sig_index = 0; $sig_index < @signatures; $sig_index += 1 ) {
		my $s_s_id = $signatures[$sig_index];
		my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
		if ( ! $$sig_specs{"txtImposition$qty_index"} ) {
			next;
		} # end if
		my $form = $$sig_specs{SignatureIndex};

		my $Imposition1 = new openprint::Imposition();
		$Imposition1->load( $sig_specs, $qty_index, $Project );

		my $sig_count = 1;

		if ( $sig_index < @signatures - 1 ) {
			for ( my $sig_index2 = $sig_index + 1; $sig_index2 < @signatures; $sig_index2 += 1 ) {
				my $sig_specs2 = openprint::service::get_specs_ref( $Project, $signatures[$sig_index2] );
				my $Imposition2 = new openprint::Imposition();
				$Imposition2->load( $sig_specs, $qty_index, $Project );
				if ( openprint::Estimating::Printing::compare_signatures( $Project, $sig_specs, $sig_specs2, $qty_index )
						and compare_folds( $specs, $Imposition1, $Imposition2, $qty_index )
					 ) {
					$sig_count += 1;
				} else {
					last;
				} # end if
			} # end for
			splice @signatures, $sig_index+1,$sig_count-1 if $sig_count > 1;
		}
		my $summary = overview_signature_summary( $Project, $service_id, undef, $qty_index, $s_s_id, undef );
		next if (!$summary) or ($summary eq 'not folded');

		if ( $sig_count > 1 ) {
			$html .= $sig_count . ' Forms ';
 #. $short_signature_types{$$sig_specs{txtServiceDescription}};
		} else {
			$html .= 'Form ' . $form . ' ';
# . $short_signature_types{$$sig_specs{txtServiceDescription}};
		} # end if
		$html .= ' ' . $summary.'<br/>';
	} # end foreach
	return $html;
} # end sub schedule_summary

sub runspeed {
	my ( $Project, $Service, $Equipment, $qty_index, $sig_id ) = @_;
	my $specs = $Service->specs();
	my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
	my $form = $$sig_specs{SignatureIndex};
	my $speed;
	foreach my $type ( keys %fold_types ) {
#$openprint::log->debug("Looking for Folding $sig_id runspeed $type-Qty-$form-$qty_index: $speed");
		if ( $$specs{"$type-Qty-$form-$qty_index"} ) {
			$speed = $Equipment->specification( $type.'RunSpeed' );
			last if $speed;
		}# end if
	}# end foreach
#$openprint::log->debug("Folding runspeed: ($speed)");
	if ( ! $speed ) {
		my $Imposition = new openprint::Imposition;
		$Imposition->load( $sig_specs, $qty_index, $Project );
		#$openprint::log->debug("Getting fold from imposition: " . $Imposition->pages() );
		if ( $Imposition->pages() ) {
			$speed = $Equipment->specification( $Imposition->pages().'PageSignatureFoldRunSpeed' );
		} # end if
	} # end if
	if ( ! $speed ) {
		if ( $$sig_specs{rdbTemplateType} and $fold_types{$$sig_specs{rdbTemplateType}} ) {
			#$openprint::log->debug("Getting fold from template: " . $$sig_specs{rdbTemplateType} );
			$speed = $Equipment->specification( $$sig_specs{rdbTemplateType}.'PageSignatureFoldRunSpeed' );
		}
	} # end if
	return $speed;
} # end sub runspeed

sub runtime {
	my ( $Project, $Service, $Equipment, $qty_index, $impressions, $speed, $pertains_to ) = @_;

	my $specs = $Service->specs();
	my $runTime;
	$pertains_to = [ $Project->signatures() ] if ! $pertains_to;
	foreach my $sig_id ( ref $pertains_to eq 'ARRAY' ? @{$pertains_to} : $pertains_to ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
		my $form = $$sig_specs{SignatureIndex};
		$Equipment = new openprint::Equipment( $$specs{"ddmEquipment-$form-$qty_index"} );
# Make ready
		$runTime += $Equipment->specification( 'Station Make Ready' ) * 60;

		foreach my $name ( keys %$specs ) {
			if ( $name =~ /^txt(\w*)Qty$/ ) {
				my $type = $1;
				my $quantity = $$specs{$name} * $impressions;
				if ( $quantity > 0 ) {
					$speed = $Equipment->specification( $type.'RunSpeed' ) if ! $speed;
					$openprint::log->debug("Folding runspeed for $type: $speed");
					if ( $speed ) {
						$runTime += $quantity * 3600 / $speed; # Convert to seconds, units is typically per hour
					} # end if
				} # end if
			} # end if
		} # end foreach spec name
	} # end foreach sig_id
	return $runTime;
} # end sub runtime

sub remove_duplicates {
	my %Results;
	foreach my $Set ( @_ ) {
		my $string = join(',', map { join('-', @$_{'quantity','columns','rows','page_columns','page_rows'}) } @{$Set} );
		$openprint::log->debug("String representing set $string results: ".(exists($Results{$string})?$Results{$string}:'none')) if DEBUG;
		next if $Results{$string};
		$Results{$string} = $Set;
	}
	return values %Results;
}
# The purpose is to cut any Impos > 1 into singletons
# Will also generate sets based on cutting pages

sub reduce_impositions {
	my ( $impositions ) = @_;
	my @results = ( $impositions );

	# Find the max impo, so on each iteration, we generate a set of impositions with only the max's cut up
	my $max_impo = 1;
	foreach my $i ( @$impositions ) {
		$max_impo = $$i{imposition} if $$i{imposition} > $max_impo;
	} # end foreach

	if ( $max_impo > 1 ) {
		my @new = @$impositions;
		for ( my $i = 0; $i < @new; $i += 1 ) {
			if ( $new[$i]{imposition} == $max_impo ) {
				foreach my $cuts ( cut_imposition( $new[$i] ) ) {
					my @new_impositions = @new;
					splice @new_impositions, $i, 1, @$cuts;
					@new_impositions = compact_impositions( @new_impositions ) if @new_impositions > 1;
					push @results, reduce_impositions( \@new_impositions );
				} # end foreach cuts
			} # end if
		} # end foreach I

	} # end if

	return @results;

} # end sub reduce_impositions

sub reduce_pages {
	my ( $sets_of_impositions, $override ) = @_;

	# First include the original sets
	my @results = @$sets_of_impositions;
	my %results;

	# Now cut pages;
	for( my $index = 0; $index < @results; $index += 1 ) {
		my $set = $results[$index];
		for ( my $i = 0; $i < @$set; $i += 1 ) {
			if ( ( $$set[$i]{pages} / $$set[$i]{spread_size} ) > 1 ) {
				my @cut = cut_spreads( $$set[$i], $override );
				if ( 0 and DEBUG ) {
$openprint::log->debug("# of sets in results " . @cut);
					foreach my $Set ( @cut ) {
						$log->debug("# in set: " . @{$Set});
						foreach my $I ( @{$Set} ) {
							$I->display("Results from cut_spreads");
						} # end foreach I
					}
				}
				foreach my $cut ( @cut ) {
					my @new = @$set;
					splice @new, $i, 1, @$cut;
					#$i += @$cut-1;
					@new = compact_impositions( @new );
#foreach ( @new ) {
	#$_->display('new set');
#}
					my $key = join("\n",map{$_->to_string()} openprint::imposition::sort(@new));
					if ( ! exists $results{$key} ) {
						$results{$key} = 1;
						push @results, \@new;
#} elsif ( DEBUG ) {
#$openprint::log->debug("Skipping $key");
					}
				}
			} # end if
		} # end foreach impositoin in the set
	} # end foreach set in the results

	return @results;

} # end sub reduce_pages

sub cut_imposition {
  my ( $I ) = @_;

  my @results;
	$openprint::log->debug(sprintf("0 Cutting imposition down from %dx%d=%dout", @$I{'columns','rows','imposition'}) ) if DEBUG;

  if ( $$I{spread_size} >= 4 ) {
    if ( ( $$I{image_orientation} == openprint::Imposition::Horizontal ) and ( $$I{rows} > 1 ) ) {
      $openprint::log->debug(sprintf("1 Cutting imposition down from %dx%d=%dout to %d %dx1=%d ", @$I{'columns','rows','imposition'}, @$I{'rows','columns','columns'} ) ) if DEBUG;
# For folding purposes, can only fold where spines are aligned
      push @results, [ map { my $i = $I->copy(); $i->rows(1); $i; } ( 1 .. $$I{rows} ) ];
    }

    if ( ( $$I{image_orientation} == openprint::Imposition::Vertical ) and ( $$I{columns} > 1 ) ) {
      $openprint::log->debug(sprintf("2 Cutting imposition down from %dx%d=%dout to %d 1x%d=%d ", @$I{'columns','rows','imposition'}, @$I{'columns','rows','rows'} ) ) if DEBUG;
      push @results, [ map { my $i = $I->copy(); $i->columns(1); $i; } ( 1 .. $$I{columns} ) ];
    }
  }

	if ( $$I{columns} > 1 ) {
##( $$I{columns} > $$I{rows} ) or ( ( $$I{columns} == $$I{rows} ) and ( $$I{image_orientation} == openprint::Imposition::Vertical ) ) ) {
		my ( $i1, $i2 ) = ( $I->copy(), $I->copy() );
		if ( ! ( $$I{columns} % 2 ) ) {
			$i1->columns($$I{columns}/2);
			$i1->quantity( $i1->quantity() * 2 );
			push @results, [ $i1 ];

			my $pieces = $$I{columns} / 2;
			if ( $pieces > 2 ) {
				$i2->columns($$I{columns}/$pieces);
				$i2->quantity( $i2->quantity() * $pieces );
				$openprint::log->debug(sprintf("3 Cutting imposition down from %dx%d=%dout to %dx%d=%d and %dx%d=%d", @$I{'columns','rows','imposition'}, @$i1{'columns','rows','imposition'}, @$i2{'columns','rows','imposition'} ) ) if DEBUG;
				push @results, [ $i2 ];
			}
		} else {
			$i1->columns(int($$I{columns}/2 ));
			$i2->columns( $$I{columns} - $$i1{columns} );
			$openprint::log->debug(sprintf("4 Cutting imposition down from %dx%d=%dout to %dx%d=%d and %dx%d=%d", @$I{'columns','rows','imposition'}, @$i1{'columns','rows','imposition'}, @$i2{'columns','rows','imposition'} ) ) if DEBUG;
			push @results, [ $i1, $i2 ];
		}
  }
	if ( $$I{rows} > 1 ) {
    my ( $i1, $i2 ) = ( $I->copy(), $I->copy() );
		if ( ! ( $$I{rows} % 2 ) ) {
			$i1->rows($$I{rows}/2);
			$i1->quantity( $i1->quantity() * 2 );
			push @results, [ $i1 ];

			my $pieces = $$I{rows} / 2;
			if ( $pieces > 2 ) {
				$i2->rows( $$I{rows} / $pieces );
				$i2->quantity( $i2->quantity() * $pieces );
				$openprint::log->debug(sprintf("5 Cutting imposition down from %dx%d=%dout to %dx%d=%d and %dx%d=%d", @$I{'columns','rows','imposition'}, @$i1{'columns','rows','imposition'}, @$i2{'columns','rows','imposition'} ) ) if DEBUG;
				push @results, [ $i2 ];
			}
		} else {
			$i1->rows(int $$I{rows}/2);
			$i2->rows( $$I{rows} - $$i1{rows} );
			$openprint::log->debug(sprintf("6 Cutting imposition down from %dx%d=%dout to %dx%d=%d and %dx%d=%d", @$I{'columns','rows','imposition'}, @$i1{'columns','rows','imposition'}, @$i2{'columns','rows','imposition'} ) ) if DEBUG;
			push @results, [ $i1, $i2 ];
		}
  } # end if
  return @results;
} # end sub cut_imposition

sub cut_spreads {
	my ( $I, $override ) = @_;

	my @results;

	my $min_spread_size = $$I{spread_size}/2 > 1 ? $$I{spread_size}/2 : 4;

$I->display("Min spread size: $min_spread_size dir($$I{spine_direction}) " . $openprint::Imposition::Orientations{$$I{spine_direction}} . " spread cols: $$I{spread_columns} spread_rows $$I{spread_rows}" ) if DEBUG;

	# Something like doing 16pg as 2 8pgs, why are we not handling the horizontal case?
	if ( $$I{spine_direction} == openprint::Imposition::Vertical and int($$I{spread_rows}) and ( ($$I{spread_rows} % 2) == 0 ) ) {
		my $i1 = $I->copy();

		# So becomes pages/2, imposition * 2, page quantity * 2, meaning if it is now 4pg 2out, it is in fact 8pages.
		$i1->spread_rows( $$i1{spread_rows} / 2 );
    #$i1->rows( $$i1{rows} * 2 );
    $$i1{quantity} *= 2;
		$$i1{page_quantity} = $$i1{page_quantity} * 2;
		$i1->image_height( $$I{image_height}/$$I{spread_rows} );
		$openprint::log->debug(sprintf('SPECIAL Cutting Vertical pages down from quantity q%d x %d pages %dout to q%d x %d pages %dout pq(%d)',
					$I->quantity(), $I->pages(), $$I{imposition},
					$i1->quantity(), $i1->pages(), $$i1{imposition}, $$I{page_quantity} ) ) if DEBUG;
		push @results, [ $i1 ];
	} elsif ( $$I{spine_direction} == openprint::Imposition::Horizontal and int($$I{spread_columns}) and ( ($$I{spread_columns} % 2) == 0 ) ) {
		my $i1 = $I->copy();

    # So becomes pages/2, imposition * 2, page quantity * 2, meaning if it is now 4pg 2out, it is in fact 8pages.
    $i1->spread_columns( $$i1{spread_columns} / 2 );
    #$i1->columns( $$i1{columns} * 2 );
    $$i1{quantity} *= 2;
    $$i1{page_quantity} = $$i1{page_quantity} * 2;
    $i1->image_height( $$I{image_height}/$$I{spread_columns} );
    $openprint::log->debug(sprintf('SPECIAL Cutting Horizontal pages down from quantity %d x %d pages %dout to q%d x %d pages %dout pq(%d)',
          $I->quantity(), $I->pages(), $$I{imposition},
          $i1->quantity(), $i1->pages(), $$i1{imposition}, $$I{page_quantity} ) ) if DEBUG;
    push @results, [ $i1 ];
	}

	if (
		( ( $$I{spine_direction} == openprint::Imposition::Vertical ) and ( $$I{spread_rows} > 1 ) )
		or
		( $$I{spread_rows} >= $min_spread_size )
		) {

		if ( $$I{spread_rows} % 2 ) {

			# First option, all singletons, since we are going to be called recursively... is this neccessary?
			my $i1 = $I->copy();
			$i1->spread_rows(1);
			$i1->quantity( $$i1{quantity} * $$I{spread_rows} );
			$$i1{page_quantity} = $$i1{page_quantity} * $$I{spread_rows};
			if ( $$I{image_orientation} == openprint::Imposition::Vertical ) {
				$i1->image_height( $$I{image_height}/$$I{spread_rows} );
			} else {
				$i1->image_width( $$I{image_width}/$$I{spread_rows} );
			} # endif

			$openprint::log->debug(sprintf('2232 Cutting pages down from %d@%d pages to %d@%d pages pq(%d) by cutting spread_rows from %d to 1', $I->quantity(), $I->pages(), $i1->quantity(), $i1->pages(), @$I{'page_quantity','spread_rows'} ) ) if DEBUG;
			push @results, [ $i1 ];

			my $i2 = $I->copy();
			$i2->spread_rows( int($$i2{spread_rows} / 2) );
			if ( $$i2{spread_rows} > 1 ) {
				#my $i2_quantity = int($$I{spread_rows}/$$i2{spread_rows});
				#$i2->quantity( $I->quantity() * $i2_quantity );
				#$i2->page_quantity( $I->page_quantity() * $i2_quantity );
				my $i3 = $I->copy();
				$i3->spread_rows( $$I{spread_rows} - $$i2{spread_rows} ); #* $i2_quantity ) );
#$i3->quantity( $I->quantity() * int($I->spread_rows()/$i2->spread_rows()) );
				if ( $$I{image_orientation} == openprint::Imposition::Vertical ) {
					$i2->image_height( $$I{image_height}*$$i2{spread_rows}/$$I{spread_rows} );
					$i3->image_height( $$I{image_height}*$$i3{spread_rows}/$$I{spread_rows} );
				} else {
					$i2->image_width( $$I{image_width}*$$i2{spread_rows}/$$I{spread_rows} );
					$i3->image_width( $$I{image_width}*$$i3{spread_rows}/$$I{spread_rows} );
				} # endif
				$openprint::log->debug(sprintf('2251 Cutting pages down from q%d@%dpg to q%d@%dpg and ',
							$I->quantity(), $I->pages(),
							$i2->quantity(), $i2->pages(),
							$i3->quantity(), $i3->pages(),
							) ) if DEBUG;
				push @results, [ $i2, $i3 ];
			} # end if

		} else {
			# Just cut in half
			my $i1 = $I->copy();
			$i1->spread_rows( $$i1{spread_rows}/2 );
			if ( $$I{image_orientation} == openprint::Imposition::Vertical ) {
				$i1->image_height( $$i1{image_height}/2 );
			} else {
				$i1->image_width( $$i1{image_width}/2 );
			}
			$i1->quantity( $$i1{quantity} * 2 );
			$$i1{page_quantity} = $$i1{page_quantity} * 2;
			$openprint::log->debug(sprintf('2265 Cutting pages down from qty %d*%d,pq:%d to %d*%d,pq:%d',
						$I->quantity(),$I->pages(), $$I{page_quantity}, $i1->quantity(), $i1->pages(), $$i1{page_quantity} ) ) if DEBUG;
			push @results, [ $i1 ];

			if ( $override and ( $$I{quantity} >= 2 ) ) {
				if ( $$I{quantity} % 2 ) {
					# Cut in roughly half, or just break one off? maybe both
					my $i3 = $I->copy();
					my $amount = int( $I->quantity() / 2 );
					$i3->quantity( $amount );
					$$i3{page_quantity} = $amount;

					my $i4 = $i1->copy();
					$i4->quantity( $I->quantity() - (  $amount* 2 ) );
					$$i4{page_quantity} = $$i4{page_quantity} - ( 2 * $amount );
					push @results, [ $i3, $i4 ];
					if ( DEBUG ) {
						$openprint::log->error(sprintf('Cutting pages down uneven pages %d to %d by cutting spread columns %d to %d',
									$i3->pages(), $i4->pages(), $$i3{spread_columns}, $$i4{spread_columns} ) );
						$i3->display();
						$i4->display();
					}

				} else {
					my $i3 = $I->copy();
					$i3->quantity( $i3->quantity()/2 );
					$$i3{page_quantity} /= 2 if $$i3{page_quantity} > 1;

					my $i4 = $i1->copy();
					$i4->quantity( $I->quantity() );
					$$i4{page_quantity} = $$i4{page_quantity} / 2 if $$i4{page_quantity} > 1;
					push @results, [ $i3, $i4 ];
					if ( DEBUG ) {
						$openprint::log->error(sprintf('Cutting pages down uneven pages %d to %d by cutting spread columns %d to %d',
									$i3->pages(), $i4->pages(), $$i3{spread_columns}, $$i4{spread_columns} ) );
						$i3->display();
						$i4->display();
					}
				}
			}
			# Now do just cutting one of them in half
		} # end if
	}  # end if rows > 1

	if (
		( ( $$I{spine_direction} == openprint::Imposition::Horizontal ) and ( $$I{spread_columns} > 1 ) )
		or
		( $$I{spread_columns} >= $min_spread_size )
		) {

		if ( $$I{spread_columns} % 2 ) {

			if ( openprint::Imposition::Horizontal == $$I{spine_direction} ) {
				# Cut into singles
				my $i1 = $I->copy();
				$i1->spread_columns(1);
				$i1->quantity( $i1->quantity() * $$I{spread_columns} );
				$$i1{page_quantity} = $$i1{page_quantity} * $$I{spread_columns};
				if ( $$I{image_orientation} == openprint::Imposition::Vertical ) {
					$i1->image_width( $$I{image_width}/$$I{spread_columns} );
				} else {
					$i1->image_height( $$I{image_height}/$$I{spread_columns} );
				}
				$openprint::log->debug(sprintf('2279 Cutting pages down from %d@%dpg to %d@%dpg by cutting spread columns from %d to 1',
							$I->quantity(), $I->pages(), $i1->quantity(), $i1->pages(), $$I{spread_columns} ) ) if DEBUG;
				push @results, [ $i1 ];
			}

			# Cut in half unevenly
			my $i2 = $I->copy();
			$i2->spread_columns( int($$i2{spread_columns} / 2) );
			if ( $$i2{spread_columns} > 1 ) {
				# Not Just duplicating the singleton case
				#my $i2_quantity = int($$I{spread_columns}/$$i2{spread_columns});
				#$i2->quantity( $$I{quantity} * $i2_quantity );
				#$$i2{page_quantity} = $$I{page_quantity} * $i2_quantity;
				my $i3 = $I->copy();
				$i3->spread_columns( $$I{spread_columns} - $$i2{spread_columns} ); #* $i2_quantity ) );
				$openprint::log->debug(sprintf('2324 Cutting pages down from q%d x %d pages to q%d x %d pages and q%d x %d pages',
							$I->quantity(), $I->pages(),
							$i2->quantity(), $i2->pages(),
							$i3->quantity(), $i3->pages(),
							) ) if DEBUG;
				if ( $$I{image_orientation} == openprint::Imposition::Vertical ) {
					$i2->image_width( $$I{image_width}*$$i2{spread_columns}/$$I{spread_columns} );
					$i3->image_width( $$I{image_width}*$$i3{spread_columns}/$$I{spread_columns} );
				} else {
					$i2->image_height( $$I{image_height}*$$i2{spread_columns}/$$I{spread_columns} );
					$i3->image_height( $$I{image_height}*$$i3{spread_columns}/$$I{spread_columns} );
				} # end if
				push @results, [ $i2, $i3 ];
			} # end if
		} else {
			my $i1 = $I->copy();
			$i1->spread_columns( $$i1{spread_columns}/2 );

			# Image width is not rotated, it is relative to the object, not the sheet
			if ( $$I{image_orientation} == openprint::Imposition::Vertical ) {
				$i1->image_width( $$i1{image_width}/2 );
			} else {
				$i1->image_height( $$i1{image_height}/2 );
			}
			$i1->quantity( $$i1{quantity} * 2 );
			$$i1{page_quantity} = $$i1{page_quantity} * 2;
			if ( DEBUG ) {
				$openprint::log->error(sprintf('Cutting pages down from %d to %d by cutting spread columns %d to %d',
							$I->pages(), $i1->pages(), $$I{spread_columns}, $$i1{spread_columns} ) );
				$I->display();
				$i1->display();
			}
			push @results, [ $i1 ];

			if ( $override and ( $$I{quantity} >= 2 ) ) {
				if ( $$I{quantity} % 2 ) {
# Cut in roughly half, or just break one off? maybe both
					my $i3 = $I->copy();
					my $amount = int( $$I{quantity} / 2 );
					$i3->quantity( $amount );
					$$i3{page_quantity} = $amount;

					my $i4 = $i1->copy();
					$i4->quantity( $$i4{quantity} - ( $amount * 2 ) );
					$$i4{page_quantity} = $$i4{page_quantity} - ( 2 * $amount );
					push @results, [ $i3, $i4 ];

					if ( DEBUG ) {
						$openprint::log->error(sprintf('Cutting pages down uneven pages pq(%s) %d to pq(%s) %d by cutting spread columns %d to %d',
									$$i3{page_quantity}, $i3->pages(), $$i4{page_quantity}, $i4->pages(), $$i3{spread_columns}, $$i4{spread_columns} ) );
						$i3->display();
						$i4->display();
					}
					$i3 = $I->copy();
					$amount = $i3->quantity() - $amount;
					$i3->quantity( $amount );
					$$i3{page_quantity} = $amount;

					$i4 = $i1->copy();
					$i4->quantity( $$i4{quantity} - ( $amount* 2 ) );
					$$i4{page_quantity} = $$i4{page_quantity} - ( 2 * $amount );
					push @results, [ $i3, $i4 ];
					if ( DEBUG ) {
						$openprint::log->error(sprintf('Cutting pages down uneven pages %d to %d by cutting spread columns %d to %d',
									$i3->pages(), $i4->pages(), $$i3{spread_columns}, $$i4{spread_columns} ) );
						$i3->display();
						$i4->display();
					}

				} else {

					my $i3 = $I->copy();
					$i3->quantity( $i3->quantity()/2 );
					$$i3{page_quantity} /= 2 if $$i3{page_quantity} > 1;

					my $i4 = $i1->copy();
					$i4->quantity( $I->quantity() );
					$$i4{page_quantity} /= 2 if $$i4{page_quantity} > 1;
					push @results, [ $i3, $i4 ];
					if ( DEBUG ) {
						$openprint::log->error(sprintf('Cutting pages down uneven pages pq(%s) %d to pq(%s) %d by cutting spread columns %d to %d',
									$$i3{page_quantity}, $i3->pages(), $$i4{page_quantity}, $i4->pages(), $$i3{spread_columns}, $$i4{spread_columns} ) );
						$i3->display();
						$i4->display();
					}
				} # end if even quantity
      } # end if override and quantity >= 2

		} # end if
	} # end if
	return @results;
} # end cut_spreads

# Takes an array of impositions(Folds) and merges duplicates.
sub compact_impositions {
	my @results;
	while ( @_ ) {
		my $Imposition = shift @_;
		$Imposition = $Imposition->copy();
		push @results, $Imposition;

		for ( my $index = 0; $index < @_; $index += 1 ) {
			if ( $$Imposition{imposition} == $_[$index]{imposition} and $$Imposition{spreads} == $_[$index]{spreads} ) {
				$$Imposition{quantity} += $_[$index]->quantity();
				splice @_, $index, 1;
				$index -= 1;
			} # end if
		} # end for each index
	} # end while @_
	return @results;
} # end sub compact_impositions

sub save {
} # end sub save

sub load_Impositions {
#sub load_Impositions($$$) {
$openprint::log->error("Called load_Impositions");
	my ( $folding_specs, $sig_specs, $qty_index ) = @_;

	my $form = $$sig_specs{SignatureIndex};
	my @results;
	foreach my $fold_index ( 1 .. 4 ) {
		next if ! $$folding_specs{"FoldQty-$form-$qty_index-$fold_index"};

		my $imp = new openprint::Imposition();
		$imp->columns( $$folding_specs{"FoldColumns-$form-$qty_index-$fold_index"} );
		$imp->rows( $$folding_specs{"FoldRows-$form-$qty_index-$fold_index"} );

		$imp->type( $$folding_specs{"FoldType-$form-$qty_index-$fold_index"} );
		my ( $pages ) = $$folding_specs{"FoldType-$form-$qty_index-$fold_index"} =~ /^(\d+)PageFold$/;
		$imp->pages( $pages );
		$imp->quantity( $$folding_specs{"FoldQty-$form-$qty_index-$fold_index"} );
		push @results, $imp;
	} # end foreach fold_index
	return @results;
} # end sub load_Impositions

sub get_Folds {
	my ( $folding_specs, $sig_specs, $qty_index ) = @_;
	my @folds;

	my $Source_Imposition;
	if ( ref $sig_specs eq 'openprint::Imposition' ) {
		$Source_Imposition = $sig_specs;
		$sig_specs = $$Source_Imposition{specs};
	} else {
		$Source_Imposition = new openprint::Imposition();
		$Source_Imposition->load( $sig_specs, $qty_index );
	} # end if
	return () if !$$Source_Imposition{imposition};

  #if ( DEBUG ) {
  #foreach my $k ( sort { $a cmp $b } keys %$folding_specs ) {
  #$openprint::log->debug($k.'=>'.(defined $$folding_specs{$k} ? $$folding_specs{$k} : 'undef'));
  #}
  #}
	my $form = $$sig_specs{SignatureIndex};
	if ( ! $$folding_specs{"ddmEquipment-$form-$qty_index"} ) {
$openprint::log->debug('Has no equipment_id') if DEBUG;
		return ();
	} # end if has equipment

	my $Folder = new openprint::Equipment($$folding_specs{"ddmEquipment-$form-$qty_index"});
	my $services = $$Source_Imposition{Project}->services();
  my $Paper = $$Source_Imposition{Paper};

	foreach my $fold_index ( 1 .. 4 ) {
		my $fold_qty = $$folding_specs{join('-','FoldQty',$form,$qty_index,$fold_index)};
		next if ! $fold_qty;

		my $fold_type = $$folding_specs{join('-','FoldType',$form,$qty_index,$fold_index)};
		next if ! $fold_type;

		my $Imposition = $Source_Imposition->copy();
		$Imposition->dutch_columns( 0 ); # Can't have dutch
		$Imposition->dutch_rows( 0 ); # Can't have dutch
		$Imposition->columns( $$folding_specs{"FoldColumns-$form-$qty_index-$fold_index"} );
		$Imposition->rows( $$folding_specs{"FoldRows-$form-$qty_index-$fold_index"} );
		$Imposition->quantity( $fold_qty );
		$$Imposition{page_columns} = $$folding_specs{"FoldPageColumns-$form-$qty_index-$fold_index"} if $$folding_specs{"FoldPageColumns-$form-$qty_index-$fold_index"};
		$$Imposition{page_rows} = $$folding_specs{"FoldPageRows-$form-$qty_index-$fold_index"} if $$folding_specs{"FoldPageRows-$form-$qty_index-$fold_index"};

		$$Imposition{impressions} = $$folding_specs{"FoldImpressions-$form-$qty_index-$fold_index"};
		$$Imposition{impressions} = ( ( $$folding_specs{"txtQuantity$qty_index"} / $$Source_Imposition{imposition} ) * $$Imposition{quantity} ) if ! $$Imposition{impressions};
		$$Imposition{Folder} = $Folder;
		$Imposition->Press($Folder);

		$Paper = $$Imposition{Paper};
$openprint::log->debug($Paper->to_string());

		my $find = {
			type 			=>	$fold_type,
      #pages			=>	$Imposition->pages(),
      ( $$Imposition{page_columns} ? ( page_columns	=> $$Imposition{page_columns} ) : () ),
      ( $$Imposition{page_rows} ? ( page_rows		=>	$$Imposition{page_rows} ) : () ),
      page_width		=>	$$Imposition{page_width},
      page_height		=>	$$Imposition{page_height},
			spine_direction	=>	$openprint::Imposition::Orientations{$$Imposition{spine_direction}},
			gsm							=>	$Paper->gsm(),
			imposition			=>	$$Imposition{imposition},
			columns					=>	$$Imposition{columns},
			rows						=>	$$Imposition{rows},
			calliper				=>	$$Paper{calliper},
			stitching		=>	($$services{SaddleStitching} or $$services{LoopStitching}) ? 1 : 0,
			perfectbind		=>	$$services{PerfectBound} ? 1 : 0,
			spinepaste		=>	$$services{SpinePaste} ? 1 : 0,
#printing_type	=>	$ppt,
		};
		my $Fold = $Folder->Fold( $find );
		if ( (!$Fold) and ( $$folding_specs{"chkOverrideLimits-$form-$qty_index"} and $$folding_specs{"chkOverrideLimits-$form-$qty_index"} eq 'Y' ) ) {
			delete $$find{calliper};
			$Fold = $Folder->Fold( $find );
		}
		if ( ! $Fold ) {
			if ( $$folding_specs{"chkOverrideFold-$form-$qty_index"} and $$folding_specs{"chkOverrideFold-$form-$qty_index"} eq 'Y' ) {
				$openprint::log->debug('Was overriden');
			} else {
				$_ = Data::Dumper::Dumper($find);
				$openprint::log->error("Cant get fold! on form $form qty $qty_index dmEquiment was " . $$folding_specs{"ddmEquipment-$form-$qty_index"}." " . $Folder->to_string() . $_);
				#$_ = Data::Dumper::Dumper($folding_specs);
				#$openprint::log->error("CAnt get fold! on " . $Folder->to_string() . $_);
#Carp::cluck( "CAnt get fold! $form-$qty_index-$fold_index on " . $Folder->to_string() ."\n". $_ . join("\n", map { $_ . '=>' . $openprint::param{$_} } sort keys %openprint::param ));
			} # end if
		} else {
			$openprint::log->debug('Got Fold: '.$Fold->to_string()) if DEBUG;
			$$Imposition{Fold} = $Fold;

			if ( $$Source_Imposition{page_columns} and $$Source_Imposition{page_rows} and $$Imposition{page_columns} and $$Imposition{page_rows} ) {
				if ( $$Imposition{image_orientation} == openprint::Imposition::Vertical ) {
			#$openprint::log->debug("adjusting image_width from $$Imposition{image_width} / ( $$Source_Imposition{page_columns} / $$Imposition{page_columns} )");
					$Imposition->image_width( $$Imposition{image_width} / ( $$Source_Imposition{page_columns} / $$Imposition{page_columns} ) );
			#$openprint::log->debug("adjusting image_height from $$Imposition{image_height} / ( $$Source_Imposition{page_rows} / $$Imposition{page_rows} )");
					$Imposition->image_height( $$Imposition{image_height} / ( $$Source_Imposition{page_rows} / $$Imposition{page_rows} ) );
				} else {
			#$openprint::log->debug("Horizontal adjusting image_width from $$Imposition{image_width} / ( $$Source_Imposition{page_rows} / $$Imposition{page_rows} )");
					$Imposition->image_width( $$Imposition{image_width} / ( $$Source_Imposition{page_rows} / $$Imposition{page_rows} ) );
			#$openprint::log->debug("adjusting image_height from $$Imposition{image_height} / ( $$Source_Imposition{page_columns} / $$Imposition{page_columns} )");
					$Imposition->image_height( $$Imposition{image_height} / ( $$Source_Imposition{page_columns} / $$Imposition{page_columns} ) );
				}
			} else {
				$openprint::log->warn('Unable to adjust image size');
			}

			if ( $Fold->pages() ) {
				$$Imposition{pages} = $$Fold{pages};
				$$Imposition{page_quantity} = $$folding_specs{"FoldPageQty-$form-$qty_index-$fold_index"};
				if ( ! $$Imposition{page_quantity} ) {
					$$Imposition{page_quantity} = $Source_Imposition->pages() / $Fold->pages();
				} # end if
			} # end if

			push @folds, $Imposition;
		} # end if Found fold
#$folding_imposition->display('Fold ' . $$folding_specs{"FoldType-$form-$qty_index-$fold_index"} ) if DEBUG;
	} # end foreach fold_index

  $openprint::log->error("Got no specified folds for sig $form : " . $Source_Imposition->to_string() ) if ! @folds;
	return @folds;
} # end sub get_Folds

sub compare_folds {
	my ( $specs, $sig_specsA, $sig_specsB, $qty_index ) = @_;

	my @FoldsA = get_Folds( $specs, $sig_specsA, $qty_index );
	my @FoldsB = get_Folds( $specs, $sig_specsB, $qty_index );
	if ( @FoldsA != @FoldsB ) {
		$openprint::log->debug("Fold count different") if DEBUG;
		return 0
	}

	if ( $FoldsA[0]{Folder} and $FoldsB[0]{Folder} and ( $FoldsA[0]{Folder}{id} != $FoldsB[0]{Folder}{id} ) ) {
		$openprint::log->debug("Folder different") if DEBUG;
		return 0 ;
	} else {
		$openprint::log->debug("Folder same $FoldsA[0]{Folder}{id} = $FoldsB[0]{Folder}{id}") if DEBUG;
	}
	return 1;
}

1;
__END__
