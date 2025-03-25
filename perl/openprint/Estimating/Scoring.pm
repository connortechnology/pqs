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
use warnings;

package openprint::Estimating::Scoring;

require openprint::service;
require openprint::Material;
require openprint::imposition;
require openprint::Paper;

require openprint::Estimating::Folding;
require openprint::Equipment;

use constant DEBUG => 0;

use vars qw( %ServicePrices %Specifications);
%ServicePrices = (
  ScoringMinimumCharge => { range_units=>[''], units=>['']},
  'ScoringMakeReady' => { range_units=>[''], units=>['']},
  'Scoring' => { range_units=>['impressions'], units=> ['per hour', 'per m']},
);
%Specifications = (
  'PerfScoreRunSpeed' => {range_units => [ 'calliper'], units=>'per hour'},
  'Perf Score Run Speed' => {range_units => [ 'calliper'], units=>'per hour'},
  'RunSpeed' => {range_units => [ 'calliper'], units=>'per hour'},
  'Scoring Overs' => {range_units => [ 'impressions' ], units=>['percent']},
  'Scoring Capable' => { value=>['Y','N', 'For Pocket Folders', 'When PerfectBound', 'When Stitching' ] },
);

sub ServicePriceConfiguration {
  my $name = shift;
  return $ServicePrices{$name} if $ServicePrices{$name};
  foreach my $key (keys %ServicePrices) {
    return $ServicePrices{$key} if ($name =~ /$key/i);
  }
  return undef;
}
sub SpecificationConfiguration {
  return $Specifications{shift};
}

my @variables = (
		'txtQuantity1','txtQuantity2','txtQuantity3',
		'txtPrice1','txtPrice2','txtPrice3',
		'MPrice1','MPrice2','MPrice3',
		'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
		'Markup1', 'Markup2', 'Markup3',
		'alert',
		);

my @all_equipment;
my $Rule;
my $Wheel;
my $Die;
my $ScoringService;
my $ScoringWithoutFoldingService;
my $ScoringMakeReadyService;
my $ScoringMakeReadyWithoutFoldingService;

my $folding_service_index;

sub variables {
	my @v = @variables;
	my $p_id = shift;

	my $Project = new openprint::Project( $p_id );
	foreach my $s_s_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
		my $form = $$sig_specs{SignatureIndex};

		foreach my $qty_index ( $Project->quantity_indexes() ) {
			push @v, map { join('-', $_, $form ) } ( 'txtWidth', 'txtHeight',
					'txtVerticalQty', 'txtHorizontalQty', 'chkOverrideQty' );
			push @v, map { join('-', $_, $form, $qty_index ) } ( 
					'ddmEquipment', 'chkOverrideEquipment',
					'txtImposition', 'chkOverrideImposition',
					'txtLayoutWidth', 'txtLayoutHeight',
					);
			foreach my $imp_index ( 1 .. 4 ) {
				push @v, map { join('-', $_, $form, $qty_index, $imp_index ) } ( 'ImpOut','ImpColumns','ImpRows','ImpQty' );
			} # end foreach imp_index
		} # end foreach
	} # end foreach
	return @v;
} # end sub variables

my @no_outputs = (
		);

sub outputs {
} # end sub outputs

sub has_overrides {
	my ( $Project, $service_id, $specs ) = @_;
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

	my @v;
	foreach my $s_s_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
		foreach my $qty_index ( $Project->quantity_indexes() ) {
			push @v, "chkOverrideEquipment-$$sig_specs{SignatureIndex}-$qty_index" if $$specs{"chkOverrideEquipment-$$sig_specs{SignatureIndex}-$qty_index"};
			push @v, "chkOverrideImposition-$$sig_specs{SignatureIndex}-$qty_index" if $$specs{"chkOverrideImposition-$$sig_specs{SignatureIndex}-$qty_index"};
		} # end foreach
	} # end foreach

	return @v;

} # end sub has_overrides

sub init {
	my ( $Project, $calc_hash ) = @_;

	my @capabilities = ('Y','When Printing');
	push @capabilities, 'For Pocket Folders' if $Project->Type()->name() eq 'PresentationFolders';
	push @capabilities, 'When Folding' if $$calc_hash{FoldingSpecs};
	push @capabilities, 'When PerfectBound' if $$calc_hash{PerfectBoundSpecs};
	push @capabilities, 'When Stitching' if $$calc_hash{StitchingSpecs};

	@all_equipment = openprint::Equipment->find( Specifications => {'Scoring Capable'=>\@capabilities}, useinestimating=>1, order=>'strName');
	$Rule = openprint::Material->find_one( name=>'ScoringRule');
	$Wheel = openprint::Material->find_one( name=>'ScoringWheel');
	$Die = openprint::Material->find_one( name=>'Score');

	$ScoringService = openprint::Service->find_one(name=>'Scoring');
	$ScoringWithoutFoldingService = openprint::Service->find_one(name=>'ScoringWithoutFolding');
	$ScoringMakeReadyService = openprint::Service->find_one(name=>'ScoringMakeReady');
	$ScoringMakeReadyWithoutFoldingService = openprint::Service->find_one(name=>'ScoringMakeReadyWithoutFolding');
	my $services = $Project->services();
	$folding_service_index = ( $$services{Folding} and $$services{Folding}[0] ) ? $$services{Folding}[0] : 0;
}
sub signature_needs {
	my ( $Project, $specs, $sig_specs, $Paper ) = @_;

	my $form = $$sig_specs{SignatureIndex};
  if ( $specs ) {
    if ( (defined $$specs{"chkOverrideQty-$form"}) and ( $$specs{"chkOverrideQty-$form"} eq 'Y' ) ) {
      if ( ( $$specs{"txtVerticalQty-$form"} or $$specs{"txtHorizontalQty-$form"} ) ) {
        return 1;
      } # end if
    } # end if
	} # end if

  # If it's not needing folding, then it doesn't need to be scored
	if ( ! openprint::Estimating::Folding::signature_needs( $Project, $sig_specs ) ) {
    $openprint::log->debug("NeedFolding is not true form $form $$sig_specs{txtWidth}x$$sig_specs{txtHeight} : $$sig_specs{txtFinalWidth}x$$sig_specs{txtFinalHeight}");
		return 0;
	} # end if
  my $book_type = $Project->get_book_type();
  if ($book_type and sets::isin($book_type, ['Spiral','MetalCoil','PlasticCoil','DoubleLoopWire','Cerlox','Unbound'])) {
		return 0;
  }
	if ( !$$sig_specs{txtSignatureType}
			or ( $$sig_specs{txtSignatureType} eq '' ) 
			or ( $$sig_specs{txtSignatureType} eq 'Cover Pages' ) 
			or ( $$sig_specs{txtSignatureType} eq 'Gate Folded Pages' ) 
      or ($$sig_specs{txtSignatureType} and $$sig_specs{GroupPageQuantity} and ($$sig_specs{GroupPageQuantity} == 6))
			or ( $$sig_specs{txtSignatureType} and ( ! $Project->signatures({type=>'Cover Pages'}) ) and ( $form == 1 ) )
			) {
		if ( ! $Paper ) {
			$openprint::log->error('Loading paper in Scoring::signature_needs');
			$Paper = openprint::Paper::load_from_signature( $Project, $sig_specs );
		}
    $openprint::log->debug( "Score Required for form $form!: ".($$Paper{id} ? $$Paper{id} : 'Custom').' '.$Paper->score_required() );
		if ( $Paper->score_required() ) {
			return 1;
		} # end if
	} # end if
#$log->debug("Scoringn is not needed! ($$specs{txtSignatureType}) ($$specs{SignatureIndex})");
	return 0;
} # end sub signature_needs

# A function that is smart enough to return true if the project needs perfing/scoring, and false if it doesn't.
sub neccessary {
	my ( $Project ) = @_;

	my $services = $Project->services( );
	if ( $$services{NoBindery} ) {
#$log->debug(" ** Project is marked as No bindery, Scoring not needed ! ** ");
		return 0;
	} # end if
	if ( $$services{DieCutting} ) {
#$log->debug(" ** Project hash DueCutting bindery, Scoring not needed ! ** ");
		return 0;
	} # end if
  my $book_type = $Project->get_book_type();
  if ($book_type and sets::isin($book_type, ['Spiral','MetalCoil','PlasticCoil','DoubleLoopWire','Cerlox','Unbound'])) {
		return 0;
  }

  # Only need scoring if it's being folded.
	if ( $$services{Folding} and @{$$services{Folding}} ) {
		my $specs = openprint::service::get_specs_ref( $Project, $$services{Scoring}[0] ) if $$services{Scoring};
		foreach my $signature_service_index ( $Project->signatures() ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
			my $Paper = openprint::Paper::load_from_signature( $Project, $sig_specs );

			if ( signature_needs( $Project, $specs, $sig_specs, $Paper ) ) {
				return 1;
			} # end if
		} # end foreach
	} # end if

	return 0;
} # end sub neccessary

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $status = 'calculated';
	$$specs{alert} = '';

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();

	if ( $$services{DieCutting} and @{$$services{DieCutting}} ) {
		$$specs{alert} .= 'Assuming that scoring is done as part of DieCutting. Not calculating. Remove DieCutting to calculate Scoring.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # en dif

	my $calc_hash = {};
	if ( $$services{SaddleStitching} ) {
		$$calc_hash{StitchingSpecs} = openprint::service::get_specs_ref( $Project, $$services{SaddleStitching}[0] );
		$$calc_hash{HasStitching} = $$services{SaddleStitching}[0];
	} elsif ( $$services{LoopStitching} ) {
		$$calc_hash{StitchingSpecs} = openprint::service::get_specs_ref( $Project, $$services{LoopStitching}[0] );
		$$calc_hash{HasStitching} = $$services{LoopStitching}[0];
	} # end if
	foreach my $service ( 'Cutting', 'Folding', 'PerfectBound' ) {
		if ( $$services{$service} and @{$$services{$service}} ) {
			$$calc_hash{"Has$service"} = $$services{$service}[0];
			$$calc_hash{"${service}Specs"} = openprint::service::get_specs_ref( $Project, $$services{$service}[0] );
		}
	} # end foreach

	init( $Project, $calc_hash );

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{'txtPrice'.$qty_index} =~ s/[^\d\.]//g if $$specs{'txtPrice'.$qty_index};
		$$specs{'Markup'.$qty_index} =~ s/[^\d\.\-]//g if $$specs{'Markup'.$qty_index};
		$$specs{"txtQuantity$qty_index"} =~ s/[^\d\.\-]//g if $$specs{"txtQuantity$qty_index"};
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
		if ( ! ( $$specs{"txtQuantity$qty_index"} > 0 ) ) {
			next;
		} # end if
		my $qty = $$specs{"txtQuantity$qty_index"};

		$$specs{'hdnBreakdown'.$qty_index} = '';

		my $qtyTotal = 0;
		my $price = 0;

		foreach my $signature_service_index ( $Project->signatures( { sort=> 1 }) ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
			my $form = $$sig_specs{SignatureIndex};
			$qty = $$specs{"txtQuantity$qty_index"};
			if ( $$sig_specs{Versions} ) {
				$qty *= $$sig_specs{Versions};
			} # end if
			$$specs{'hdnBreakdown'.$qty_index} .= "<fieldset><legend>Signature $form: ".
      ($$sig_specs{txtServiceDescription} ? $$sig_specs{txtServiceDescription}:'').'</legend>';
			if ( ! $$sig_specs{'txtImposition'.$qty_index} ) {
				$$specs{'hdnBreakdown'.$qty_index} .= "No imposition for signature $$sig_specs{SignatureIndex}";
				next;
			} # end if
			my $Imposition = new openprint::Imposition();
			$Imposition->load( $sig_specs, $qty_index, $Project );
			$$Imposition{Folds} = [ openprint::Estimating::Folding::get_Folds( $$calc_hash{FoldingSpecs}, $Imposition, $qty_index ) ];

			$$specs{'hdnBreakdown'.$qty_index} .= $Imposition->to_string() . '<br/>';
			$$specs{'hdnBreakdown'.$qty_index} .= $Imposition->Paper()->to_string() . '<br/>';

      if (!$$specs{"chkOverrideImposition-$form-$qty_index"}) {
        foreach my $imp_index (1 .. 4) {
          @$specs{
          "ImpQty-$form-$qty_index-$imp_index",
          "ImpOut-$form-$qty_index-$imp_index",
          "ImpColumns-$form-$qty_index-$imp_index",
          "ImpRows-$form-$qty_index-$imp_index"} = ('','','','');
        } # end foreach 
      } # end if

			if ( (!defined $$specs{"chkOverrideQty-$form"}) or ( $$specs{"chkOverrideQty-$form"} ne 'Y' ) ) {
				get_scores( $Project, $specs, $sig_specs, $Imposition->Paper() );
			} # end if
			my %Price = signature_calc( $Project, $specs, $sig_specs, $qty_index, $Imposition, $calc_hash );
			$status = $Price{Status} if $Price{Status} eq 'uncalculated';
			if ( $Price{Equipment} ) {
				$$specs{"ddmEquipment-$form-$qty_index"} = $Price{Equipment}->id();
#$$specs{"txtImposition-$$sig_specs{SignatureIndex}-$qty_index"} = $Price{Imposition}->imposition();
#$$specs{"txtLayoutWidth-$$sig_specs{SignatureIndex}-$qty_index"} = $Price{Imposition}->layout_width();
#$$specs{"txtLayoutHeight-$$sig_specs{SignatureIndex}-$qty_index"} = $Price{Imposition}->layout_height();
					my $imp_index = 1;
					foreach my $I ( @{$Price{Impositions}} ) {
						$I->Equipment( $Price{Equipment} );
						@$specs{
            "ImpQty-$form-$qty_index-$imp_index",
            "ImpOut-$form-$qty_index-$imp_index",
            "ImpColumns-$form-$qty_index-$imp_index",
            "ImpRows-$form-$qty_index-$imp_index"} =
            @$I{'quantity','imposition','columns','rows'};
            $imp_index += 1;
          } # end foreach 
          if ( ! $$specs{"chkOverrideImposition-$form-$qty_index"} ) {
            foreach my $imp_index ($imp_index .. 4) {
              @$specs{
              "ImpQty-$form-$qty_index-$imp_index",
              "ImpOut-$form-$qty_index-$imp_index",
              "ImpColumns-$form-$qty_index-$imp_index",
              "ImpRows-$form-$qty_index-$imp_index"} =('','','','');
            }
          } # end if
			} else {
				$$specs{"ddmEquipment-$form-$qty_index"} = '' if (!$$specs{"chkOverrideEquipment-$form-$qty_index"}) or ($$specs{"chkOverrideEquipment-$form-$qty_index"} ne 'Y');
#$$specs{"txtImposition-$$sig_specs{SignatureIndex}-$qty_index"} = 0;
#$$specs{"txtLayoutWidth-$$sig_specs{SignatureIndex}-$qty_index"} = 0;
#$$specs{"txtLayoutHeight-$$sig_specs{SignatureIndex}-$qty_index"} = 0;
				if ( $Price{Status} eq 'uncalculated' ) {
					if ( $$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' ) {
						$$specs{alert} .= "QTY $qty_index: The selected equipment ".$$specs{"ddmEquipment-$form-$qty_index"}." can not handle your project.	This may be because the stock is too heavy, or too large.";
					} else {
						$$specs{alert} .= "QTY $qty_index: No suitable equipment could be found for your project.	This may be because the stock is too heavy, or too large.";
					} # end if
				} # end if
			} # end if
			$$specs{'hdnBreakdown'.$qty_index} .= $Price{Breakdown}.'</fieldset>';
			$$specs{alert} .= $Price{alert} if $Price{alert};

			if (
          (!defined($$specs{"txtVerticalQty-$form"}) or $$specs{"txtVerticalQty-$form"} eq '')
          and
          (!defined($$specs{"txtHorizontalQty-$form"}) or $$specs{"txtHorizontalQty-$form"} eq '')
         ) {
				$$specs{alert} .= 'Please specify # of scores for form ' . $form;
				$status = 'uncalculated';
			} else {
				$qtyTotal += $$specs{"txtVerticalQty-$form"} if $$specs{"txtVerticalQty-$form"};
				$qtyTotal += $$specs{"txtHorizontalQty-$form"} if $$specs{"txtHorizontalQty-$form"};
			} # end if
			$price += $Price{Price} if $Price{Price};
			$status = 'uncalculated' if $Price{Status} eq 'uncalculated';
		} # end foreach signature


		my $unitPrice = 0;

		if ( $qtyTotal ) {
			$unitPrice = $price / $qty if $qty;
    } else {
      $$specs{alert} .= 'Please specify # of scores or remove scoring from project.<br/>' if ! $$specs{alert};
      $status = 'uncalculated';
		} # end if

		if ( $Project->markup() ) {
			my $markup = 1+$Project->markup()/100;
			$unitPrice *= $markup;
			$price *= $markup;
		}
		if ( $$specs{"Markup$qty_index"} ) {
			my $markup = 1+$$specs{"Markup$qty_index"}/100;
			$unitPrice *= $markup;
			$price *= $markup;
		}

		$$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $unitPrice );
		$$specs{"MPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $unitPrice * 1000 );

		if ( (!$$specs{"OverridePrice$qty_index"} ) or ( $$specs{"OverridePrice$qty_index"} ne 'Y') ) {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $price );
		} else {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"} );
		} # end if
  } # end foreach qty_index

	return $$specs{Status} = $status;
} # end sub calc

sub signature_calc {
	my ( $Project, $specs, $sig_specs, $qty_index, $SignatureImposition, $calc_hash, $Used_Impositions ) = @_;
	my %Results = (
			Status		=>	'calculated',
			Breakdown	=>	'',
			alert			=>	'',
			);
	my $form = $$sig_specs{SignatureIndex};

	my $score_qty = ($$specs{"txtVerticalQty-$form"}?$$specs{"txtVerticalQty-$form"}:0) + ($$specs{"txtHorizontalQty-$form"}?$$specs{"txtHorizontalQty-$form"}:0);
	$Results{Breakdown} .= "# of Scores: $score_qty<br/>";
	return %Results if ! $score_qty;

	@$specs{"txtWidth-$form", "txtHeight-$form"} = @$sig_specs{'txtWidth','txtHeight'};
	$Results{Status} = 'uncalculated';
	my $qty = $$specs{"txtQuantity$qty_index"};
	if ( $$specs{txtPressSheetComboItems} ) {
		$qty *= $$specs{txtPressSheetComboItems};
	} # end if
	if ( $$sig_specs{Versions} ) {
		$qty *= $$sig_specs{Versions};
	} # end if
	return %Results if ! $qty;

	my @Folds;
	if ( $$SignatureImposition{Folds} ) {
		@Folds = @{$$SignatureImposition{Folds}};
	} elsif ( $$calc_hash{FoldingSpecs} ) {
		my ( $caller, undef, $line ) = caller;
		$openprint::log->error("Getting Folds from folding in Scoring, but really should have already had them in the Imposition from $caller:$line");
		@Folds = openprint::Estimating::Folding::get_Folds( $$calc_hash{FoldingSpecs}, $sig_specs, $qty_index );
	} # end if

	if ( DEBUG ) {
		$SignatureImposition->display('Original sig');
		foreach my $Fold ( @Folds ) {
			$Fold->display('Fold');
		} 
	} # end if

	my @equipment;	
	if ( $$specs{"chkOverrideEquipment-$form-$qty_index"} and ($$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y') ) {
		@equipment = openprint::Equipment->find( id=>$$specs{"ddmEquipment-$form-$qty_index"} );
		$openprint::log->debug('Overriding Equipment to: ' . $$specs{"ddmEquipment-$form-$qty_index"} ) if DEBUG;
	} else {
		if (!@all_equipment) {
			$openprint::log->warn('This should have been already done');
			init( $Project, $calc_hash );
		}
		@equipment = @all_equipment;
	} # endif

# Get the impositions to consider
	if ( ! $$SignatureImposition{imposition} ) {
		$openprint::log->error('Scoring passed an invalid imposition');
		$Results{alert} .= 'Unable to load the imposition.  This likely is because printing has not finished calculating.<br/>';
		return $Results{Status};
	} # end if

#if ( $$specs{"chkOverrideImposition-$$sig_specs{SignatureIndex}-$qty_index"} eq 'Y' ) {
#if ( $$specs{"txtImposition-$$sig_specs{SignatureIndex}-$qty_index"} > $imposition->imposition() or $$specs{"txtImposition-$$sig_specs{SignatureIndex}-$qty_index"} <= 0 ) {
#$$specs{alert} = "The specified imposition is not possible.";
#return %Results;
##} # end if
#} # end if
# What we do is build a set of pieces of the imposition, all of which can be folded. We don't worry about optimality, just possibility.
	my @Sets_of_Impositions;
	my @All_Impositions;

  if ( ! $$SignatureImposition{cut_impositions} ) {

# IF it's a W&T, we have to cut in half first, so just do it.
		if ( $$SignatureImposition{runstyle} eq 'Work & Turn' ) {
			my $i = $SignatureImposition->copy();
			$i->runstyle('Sheet Work');
			$i->start_columns( $$i{columns} );
			$i->columns( $$i{columns}/2 );
			$$i{quantity} = 2;
			push @Sets_of_Impositions, $i;
		} elsif ( $$SignatureImposition{runstyle} eq 'Work & Tumble' ) {
			my $i = $SignatureImposition->copy();
			$i->runstyle('Sheet Work');
			$i->start_rows( $$i{rows} );
			$i->rows( $$i{rows}/2 );
			$$i{quantity} = 2;
			push @Sets_of_Impositions, $i;
		} else {
			my $i = $SignatureImposition->copy();
			$$i{quantity} = 1;
			push @Sets_of_Impositions, $i;
		} # end if


# Get rid of dutches
		if ( $$SignatureImposition{dutch_columns} ) {
			my @Impositions = ();
			my $modified = 0;
			foreach my $I ( @Sets_of_Impositions ) {
				if ( $$I{dutch_columns} ) {
					{
						my $i = $I->copy();
						$i->dutch_columns(0);
						$i->dutch_rows(0);
						$$i{quantity}=1;
						push @Impositions, $i;
					}
					{
						my $i = $I->copy();
						$i->columns( $i->dutch_columns() );
						$i->rows( $i->dutch_rows() );
						$i->dutch_columns(0);
						$i->dutch_rows(0);
						$$i{quantity} = 1;
						$i->image_orientation($$I{image_orientation} == openprint::Imposition::Vertical ? openprint::Imposition::Horizontal : openprint::Imposition::Vertical);
						push @Impositions, $i;
					}
					$modified = 1;
				} else {
					push @Impositions, $I;
				} # end if
			} # end foreach

			@Sets_of_Impositions = @Impositions if $modified;
			if ( DEBUG ) {
				foreach my $I ( @Impositions ) {
					$I->display('Results from dutch cuts');
				} # end foreach
			} # end if
		} # end if dutch


		@All_Impositions = openprint::Estimating::Folding::reduce_impositions( \@Sets_of_Impositions );
    if (@Folds and (@Folds > 1 or $Folds[0]{quantity} > 1)) {
      push @All_Impositions, [@Folds];
    }
		@All_Impositions = openprint::Estimating::Folding::remove_duplicates( @All_Impositions );
		if ( DEBUG ) {
			$openprint::log->debug('Sets of Maximum Impositions: ' . @All_Impositions);
			foreach my $Set ( @All_Impositions ) {
				$openprint::log->debug('Impositions in set: ' . @$Set);
				foreach my $I ( @$Set ) {
					$I->display('quantity '.$I->quantity() );
				} # end foreach I
			} # end foreach set
			$openprint::log->debug(sprintf('Original Sign info: %dx%d*%d,%dout', @$SignatureImposition{'spread_columns', 'spread_rows', 'spread_size', 'imposition'}));
		} # end if debug

# Store for use by other parts like perforating
		@{$$SignatureImposition{cut_impositions}} = @All_Impositions;
	} else {
		@All_Impositions = @{$$SignatureImposition{cut_impositions}};
	} # end if overrideImpositions

	if ((defined $$specs{"chkOverrideImposition-$form-$qty_index"}) and ( $$specs{"chkOverrideImposition-$form-$qty_index"} eq 'Y' ) ) {
		$openprint::log->debug('Overriding impositions');
    # Look in sets of impositions for a cut that matches
    my $matched = 0;
    foreach my $set (@All_Impositions) {
      my @matched;
      foreach my $index ( 1 .. 4 ) {
        my $imp_qty = $$specs{join('-','ImpQty',$form,$qty_index,$index)};
        next if ! $imp_qty;
        foreach my $imp (@{$set}) {
          if ($$imp{quantity} == $imp_qty and $$imp{imposition} == $$specs{"ImpOut-$form-$qty_index-$index"}) {
            push @matched, $imp;
          }
        }
      }
      if (@matched == @{$set}) {
        @All_Impositions = ( \@matched );
        $matched = 1;
        last;
      }
    }
    if (!$matched) {
      my @override_impos;
      foreach my $index ( 1 .. 4 ) {
        my $imp_qty = $$specs{join('-','ImpQty',$form,$qty_index,$index)};
        next if ! $imp_qty;
        my $I = $SignatureImposition->copy();
        $I->quantity( $imp_qty );
        $I->imposition( $$specs{"ImpOut-$form-$qty_index-$index"} );
        $I->columns( $$specs{"ImpColumns-$form-$qty_index-$index"} ) if $$specs{"ImpColumns-$form-$qty_index-$index"} < $I->columns();
        $I->rows( $$specs{"ImpRows-$form-$qty_index-$index"} ) if $$specs{"ImpRows-$form-$qty_index-$index"} < $I->rows();

        push @override_impos, $I;
        $I->display('Override');
      } # end foreach
      @All_Impositions = ( \@override_impos );
      my $overriden_count = misc::sum( map { $_->quantity() * $_->imposition() } @override_impos );
      if ( $overriden_count != $SignatureImposition->quantity() * $SignatureImposition->imposition() ) {
        $Results{alert} .= "Overriden imposition count ($overriden_count) does not match printed imposition count (".$SignatureImposition->quantity() * $SignatureImposition->imposition().") for form $form quantity $qty_index (".$$specs{"txtQuantity$qty_index"}.").<br/>";
      } else {
        $openprint::log->debug(" override count: $overriden_count $$SignatureImposition{quantity} * $$SignatureImposition{imposition}");
      } # end if
    }
  } # end if overriden Imposition

EQUIPMENT: foreach my $Equipment ( @equipment ) {
		 $Results{Breakdown} .= "<br/>Equipment: $$Equipment{name}, ";
		 my $type = $Equipment->specification('Type');
		 if ( ! $type ) {
			 $Results{Breakdown} .= "No type for $$Equipment{name}. Please set it in equipment specifications.<br/>";
       $type = 'Folder';
			 #next;
		 }
		 my $capable = $Equipment->specification('Scoring Capable');

		 if ( $capable eq 'When Folding' ) {
			 if ( ! $$calc_hash{FoldingSpecs} ) {
				 $Results{Breakdown} .= 'Not being folded.<br/>';
				 if ( $$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' ) {
					 $Results{alert} .= 'Not being folded.<br/>';
				 } # end if
				 next;
			 } 
			 if ( $$calc_hash{FoldingSpecs}{"ddmEquipment-$form-$qty_index"} != $$Equipment{id} ) {
#FIXME Folder might already be set in the imposition
				 my $Folder = new openprint::Equipment( $$calc_hash{FoldingSpecs}{"ddmEquipment-$form-$qty_index"} );
				 $Results{Breakdown} .= "Form $form qty $qty_index not being folded on $$Equipment{strid}. Is being folded on $$Folder{strid}.<br/>";
				 if ( $$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' ) {
					 $Results{alert} .= 'Not being folded on this.<br/>';
				 } # end if
				 next;
			 } # end if
		 } elsif ( ( $capable eq 'When Printing' ) and ( $$Equipment{strid} ne $$sig_specs{'ddmPress'.$qty_index} ) ) {
			 $Results{Breakdown} .= "Not printing on $$Equipment{name}.<br/>";
			 next;
		 } # end if

		 if ( $type eq 'Stitcher' ) {
			 if ( ! $$calc_hash{StitchingSpecs} ) {
				 $Results{Breakdown} .= 'Not being stitched.<br/>';
				 next;
			 } # end if
			 if ( $$calc_hash{StitchingSpecs}{"ddmEquipment$qty_index"} and $$calc_hash{StitchingSpecs}{"ddmEquipment$qty_index"} != $Equipment->id() ) {
				 $Results{Breakdown} .= 'Not stitching on this.<br/>';
				 next;
			 } # end if
			 if ( $$sig_specs{txtSignatureType} ne 'Cover Pages' ) {
				 $Results{Breakdown} .= 'Stitcher can only score cover.<br/>';
				 next;
			 }
       if ($$sig_specs{GroupPageQuantity} and ($$sig_specs{GroupPageQuantity} != 4)) {
         $Results{Breakdown} .= 'Stitcher can only score 4pg.<br/>';
         next;
       }
		 } elsif ( $type eq 'PerfectBinder' ) {
			 if ( ! $$calc_hash{PerfectBoundSpecs} ) {
				 next ;
			 } 
       if ( $$calc_hash{PerfectBoundSpecs}{"ddmEquipment$qty_index"} and $$calc_hash{PerfectBoundSpecs}{"ddmEquipment$qty_index"} != $Equipment->id() ) {
         $Results{Breakdown} .= 'Not binding on this.<br/>';
         next;
       } # end if
       if ( $$sig_specs{txtSignatureType} ne 'Cover Pages' ) {
         $Results{Breakdown} .= 'PerfectBinder can only score cover.<br/>';
         next;
       }
       if ($$sig_specs{GroupPageQuantity} and ($$sig_specs{GroupPageQuantity} != 4)) {
         $Results{Breakdown} .= 'PerfectBinder can only score 4pg.<br/>';
         next;
       }
		 } elsif ( $type eq 'Press' ) {
			 if ( $$sig_specs{'ddmRunStyle'.$qty_index} eq 'Work & Turn' or $$sig_specs{'ddmRunStyle'.$qty_index} eq 'Work & Tumble' ) {
				 $Results{Breakdown} .= 'Cant do an inline score when W&T.<br/>';
				 next;
			 } # end if
		 } # end if type

		 if ( $$calc_hash{NoOfflineBindery} and ( $$sig_specs{'ddmPress'.$qty_index} ne $$Equipment{strid} ) ) {
			 $Results{Breakdown} .= "No Offline bindery and not printing on $$Equipment{name}.<br/>";
			 next;
		 } # end if

		 my $totalPrice;
		 my @impositions = ();
     my $minimumCharge = openprint::service::get_price('ScoringMinimumCharge', undef, $Equipment) || 0;

# FIXME, needs to be same folder
		 if ( ( $type eq 'Folder' ) and @Folds ) {
			 my $parts = 0;
			 foreach my $Fold ( @Folds ) {
				 $parts += $$Fold{imposition} * $$Fold{quantity};
				 if ( $_ = fits_on_equipment( $Equipment, $Fold, $$specs{"txtVerticalQty-$form"}, $$specs{"txtHorizontalQty-$form"} ) ) {
					 $Results{Breakdown} .= "Fold Doesn't fit. $_<br/>";
					 next EQUIPMENT;
				 } # end if
			 } # end if

			 foreach my $Fold ( @Folds ) {
         # $qty / imposition gives us the # of sheets, so * qty gives us the # of impressions
         $$Fold{impressions} = ( $qty / $SignatureImposition->imposition() ) * ( $Fold->quantity() );
#$$Fold{impressions} /= $Fold->imposition();
				 my $Price = get_price( $Equipment, $$specs{"txtVerticalQty-$form"}, $$specs{"txtHorizontalQty-$form"}, $$Fold{impressions}, $Fold );
         $totalPrice += $$Price{setup}{Price} + $$Price{Vertical}{Total} + $$Price{Horizontal}{Total} + $$Price{Service}{Total};
         if ($$Price{Die}) {
           $openprint::log->error("Die price $$Price{Die} " . $$Price{Die}{Price});
           $totalPrice += $$Price{Die}{Total} if $$Price{Die};
         } else {
           $openprint::log->error("No Die price $$Price{Die} $form" );
         }
				 $Results{Breakdown} .= $$Price{Breakdown};
			 } # end foreach my $Fold

			 $Results{Breakdown} .= sprintf('Total: $%.2f<br/>', $totalPrice);

			 if ( $totalPrice < $Results{Price} or ! exists $Results{Price} ) {
				 $Results{Price} = $totalPrice;
				 $Results{Equipment} = $Equipment;
				 $Results{Impositions} = \@Folds;
			 } # end if
		 } else {
			 foreach my $Set_Of_Impositions ( @All_Impositions ) {
				 my @impositions = @{$Set_Of_Impositions};
				 if ( $type eq 'Press' ) {
           $openprint::log->debug("Next because $type and @impositions > 1") if DEBUG;
					 next if @impositions > 1;
				 } # end if

				 my $totalPrice;
				 my $complete = 1;

				 foreach my $I ( @impositions ) {
					 $I->Press( $Equipment ); # WHY? To make to_string list the right equipent
					 $Results{Breakdown} .= '<br/>Fold: '.$I->to_string(undef).'<br/>';
           if (!$$I{imposition}) {
             $Results{Breakdown} .= 'No imposition in Imposition!<br/>';
             next;
           }

					 if ( $_ = is_desirable($Equipment, $I, $$specs{"txtVerticalQty-$form"}, $$specs{"txtHorizontalQty-$form"}) ) {
						 $Results{Breakdown} .= "Not good. $_<br/>";
						 $complete = 0;
						 last;
					 } # end if

					 if ( $_ = fits_on_equipment( $Equipment, $I, $sig_specs, $$specs{"txtVerticalQty-$form"}, $$specs{"txtHorizontalQty-$form"} ) ) {
						 $Results{Breakdown} .= "Doesn't fit. $_<br/>";
						 $complete = 0;
						 last;
					 } # end if

					 $Results{Breakdown} .= '<br/>';

           $$I{impressions} = ( $qty / $$SignatureImposition{imposition} ) * ( $I->quantity() );
           #$openprint::log->error("Impressions from $$I{impressions} = ( $qty / $SignatureImposition->imposition() ) * ( $$I{quantity} );");
					 my $Price = get_price( $Equipment, $$specs{"txtVerticalQty-$form"}, $$specs{"txtHorizontalQty-$form"}, $$I{impressions}, $I );

					 $totalPrice += $$Price{setup}{Price} + $$Price{Vertical}{Total} + $$Price{Horizontal}{Total} + $$Price{Service}{Total};
           $totalPrice += $$Price{Die}{Total} if $$Price{Die};
					 $Results{Breakdown} .= $$Price{Breakdown};
				 } # end foreach imposition I
				 next if ! $complete;
				 $Results{Breakdown} .= sprintf('Total: $%.2f<br/>', $totalPrice);
         if ($minimumCharge and ($minimumCharge > $totalPrice)) {
           $Results{Breakdown} .= sprintf('Minimum Charge: $%.2f<br/>', $minimumCharge);
           $totalPrice = $minimumCharge;
         }

				 if ( (! exists $Results{Price}) or ($totalPrice < $Results{Price}) ) {
					 $Results{Price} = $totalPrice;
					 $Results{Equipment} = $Equipment;
					 $Results{Impositions} = $Set_Of_Impositions;
				 } # end if
			 } # end foreach imposition I
		 } # end if folding
	 } # end foreach equipment

	 if ( $Results{Equipment} ) {
		 $Results{Status} = 'calculated';
	 } else {
		 $Results{Status} = 'uncalculated';
	 } # end if
	 return %Results;
} # end sub signature_calc

sub get_price {
	my ( $Equipment, $vertical, $horizontal, $qty, $I ) = @_;

	my $type = $Equipment->specification('Type');
	my %Results;
	my $horizontal_rule = 0;
	my $horizontal_length = 0;
	my %horizontal_price;

	my $vertical_rule = 0;
	my $vertical_length = 0;
	my %vertical_price;

	if ( $$I{image_orientation} == openprint::Imposition::Vertical ) {
		if ( $vertical ) {
			$vertical_rule = $vertical * $$I{columns};
			$vertical_length = $vertical_rule * $$I{layout_height};
		}
		if ( $horizontal ) {
			$horizontal_rule = $horizontal * $$I{rows};
			$horizontal_length = $horizontal_rule * $I->layout_width();
		} # end if
	} elsif ( $$I{image_orientation} == openprint::Imposition::Horizontal ) {
		if ( $horizontal ) {
			$vertical_rule = $horizontal * $$I{rows};
			$vertical_length = $vertical_rule * $I->layout_width();
		} # end if
		if ( $vertical ) {
			$horizontal_rule = $vertical * $$I{columns};
			$horizontal_length = $horizontal_rule * $I->layout_height();
		} # end if
	} # end if
	my $score_qty = $horizontal_rule + $vertical_rule;
	my $UseScoringMakeReadyService;
	my $UseScoringService;
	my %servicePrice;

	if ( ( $type eq 'Folder' ) and ! $folding_service_index ) {
		$UseScoringService = $ScoringWithoutFoldingService ? $ScoringWithoutFoldingService : $ScoringService;
		$UseScoringMakeReadyService = $ScoringMakeReadyWithoutFoldingService ? $ScoringMakeReadyWithoutFoldingService : $ScoringMakeReadyService;
	} else {
		$UseScoringService = $ScoringService;
		$UseScoringMakeReadyService = $ScoringMakeReadyService;
	} 

  my %setupPrice = $UseScoringMakeReadyService->get_price(undef, $Equipment);
  if (%setupPrice) {
    if ( $setupPrice{range_units} eq 'scores' ) {
      $score_qty = $vertical + $horizontal;
      %setupPrice = $UseScoringMakeReadyService->get_price($score_qty, $Equipment);
    } else {
      %setupPrice = $UseScoringMakeReadyService->get_price($score_qty, $Equipment);
    }
  } else {
    $setupPrice{Total} = $setupPrice{Price} = 0;
  }

	$Results{Breakdown} .= sprintf('MakeReady: for %d scores = $%.2f<br/>', $score_qty, $setupPrice{Price}) if %setupPrice;
	$Results{Breakdown} .= "Imposition: $$I{columns}x$$I{rows}=$$I{imposition}: ";

	my $Overs = $Equipment->Specification('Scoring Overs', $qty);
	if ( $$Overs{units} ) {
		if ( $$Overs{units} eq 'Sheets' ) {
			my $overs = $$Overs{value};
			$qty += $overs;
			$Results{Overs} = $overs;
			$Results{Breakdown} .= 'Overs: ' . $overs . '<br/>';
    } elsif ( $$Overs{units} eq 'Percent' ) {
			my $overs = int($qty * $$Overs{value} / 100);
			$qty += $overs;
			$Results{Overs} = $overs;
			$Results{Breakdown} .= 'Overs: ' . $overs . '<br/>';
		} else {
			$openprint::log->error('unknown units on Scoring Overs on '.$$Equipment{strid});
		} # end if
	} # end if

	if ( $UseScoringService ) {
		%servicePrice = $UseScoringService->get_price(undef, $Equipment);
		if ( $servicePrice{range_units} eq 'scores' ) {
			%servicePrice = $UseScoringService->get_price($score_qty, $Equipment);
		} else {
			%servicePrice = $UseScoringService->get_price($qty, $Equipment);
		}
	} else {
		$openprint::log->warn('No Scoring price!');
	} # end if
	$servicePrice{Total} = 0;

  my $runspeed;

  if ($$I{Fold} and $$I{Fold}{equipment_id} == $$Equipment{id}) {
    if ($$I{Fold}{runspeed_units} eq 'gsm') {
      $runspeed = $$I{Fold}->RunSpeed($I->Paper()->gsm());
    } else {
      $runspeed = $$I{Fold}->RunSpeed($qty);
    }
  } else {
    $runspeed = $Equipment->Specification('PerfScoreRunSpeed');
    $runspeed = $Equipment->Specification('Perf Score Run Speed') if !$runspeed;
    $runspeed = $Equipment->Specification('RunSpeed', undef, 1) if !$runspeed;
    if ($runspeed) {
      if ($$runspeed{range_units} and ($$runspeed{range_units} eq 'impressions')) {
        $runspeed = $Equipment->Specification($$runspeed{name}, $qty);
      } else {
        $runspeed = $Equipment->Specification($$runspeed{name}, $I->Paper()->gsm());
      }
    }
  }

	$Results{Runspeed} = $runspeed;

	if ($servicePrice{units} eq 'per m') {
		$servicePrice{Total} = Math::Round::nearest( 0.01, $servicePrice{Price} * $qty / 1000 );
		$Results{Breakdown} .= sprintf('Service: $%.2f%s * %d * %d scores=$%.2f<br/>',
				@servicePrice{'Price','units'}, $qty, $score_qty, $servicePrice{Total} );
	} elsif ($servicePrice{units} eq 'per hour') {
		if ($runspeed) {
      if ($$runspeed{value} and int($$runspeed{value})) {
				my $hours = $qty / $$runspeed{value};
				$servicePrice{Total} = Math::Round::nearest( 0.01, $servicePrice{Price} * $hours );
				$Results{Breakdown} .= sprintf('Service: $%.2f%s * %d @ %d%s = $%.2f<br/>',
						@servicePrice{'Price','units'}, $qty, $$runspeed{value}, 'Per Hour', $servicePrice{Total} );
			} else {
        $Results{Breakdown} .= "Bad runspeed ($$runspeed{value}) on $$Equipment{strid}<br/>";
				$openprint::log->error("Bogus runspeed ($$runspeed{value}) on $$Equipment{strid}");
			} # end if
    } else {
      $Results{Breakdown} .= "per hour price set but no runspeed set on $$Equipment{strid}<br/>";
      $openprint::log->error("Bogus runspeed set on $$Equipment{strid}");
    } # end if
  } elsif ( $servicePrice{Price} ) {
    $Results{Breakdown} .= "Unknown units set on service price ($score_qty) ($servicePrice{units}) <br/>";
	} # end if

#$openprint::log->debug("Horizontal: $horizontal_rule");
	if ( $horizontal_rule and $Rule ) {
		%horizontal_price = $Rule->get_price($horizontal_rule, $Equipment);
		if ( %horizontal_price ) {
			if ( $horizontal_price{units} eq 'per rule' or $horizontal_price{units} eq 'each' or $horizontal_price{units} eq 'per score' ) {
				$horizontal_price{Total} = $horizontal_price{Price} * $horizontal_rule;
				$Results{Breakdown} .= sprintf('Rule: $%1$.2f%2$s * %4$d rule=$%3$.2f<br/>',
						@horizontal_price{'Price','units','Total'}, $horizontal_rule );
			} elsif ( $horizontal_price{units} eq 'per inch' ) {
				$horizontal_price{Total} = $horizontal_price{Price} * $horizontal_length;
				$Results{Breakdown} .= sprintf('Rule: $%1$.2f%2$s * %4$.2finches=$%3$.2f<br/>',
						@horizontal_price{'Price','units','Total'}, $horizontal_length );
			} elsif ( $horizontal_price{units} eq 'per foot' ) {
				$horizontal_price{Total} = $horizontal_price{Price} * $horizontal_length/12;
				$Results{Breakdown} .= sprintf('Rule: $%1$.2f%2$s * %4$.2finches=$%3$.2f<br/>',
						@horizontal_price{'Price','units','Total'}, $horizontal_length/12 );
			} else {
        $horizontal_price{Total} = $horizontal_price{Price};
				$openprint::log->error("Unknown units set on horizontal material price ($horizontal_price{units}) on $$Equipment{strid}");

				$Results{Breakdown} .= "Unknown units set on horizontal material price ($horizontal_price{units})<br/>";
			} # end if
		} # end if
	} else {
		$horizontal_price{Total} = 0;
	} # end if

  if ( $Die ) {
    my %die_price = $Die->get_price(undef, $Equipment);
    if (%die_price) {
      if ($die_price{units} eq 'per square inch') {
        $die_price{Total} = $die_price{Price} * $$I{sheet_width} * $$I{sheet_height};
        $Results{Breakdown} .= sprintf('Die: $%1$.2f%2$s * %4$sx%5$s=$%3$.2f<br/>', @die_price{'Price','units','Total'}, $$I{sheet_width}, $$I{sheet_height} );
        $Results{Die} = \%die_price;
      }
    }
  }

	if ( $vertical_rule ) {
		if ( $Wheel ) {
			%vertical_price = $Wheel->get_price( $vertical_rule, $Equipment );
			if ( %vertical_price ) {
				if ( $vertical_price{units} eq 'per rule' or $vertical_price{units} eq 'each' ) {
					$vertical_price{Total} = $vertical_price{Price} * $vertical_rule;
					$Results{Breakdown} .= sprintf('Wheel: $%1$.2f%2$s * %4$d wheels=$%3$.2f<br/>', @vertical_price{'Price','units','Total'}, $vertical_rule );
				} elsif ( $vertical_price{units} eq 'per inch' ) {
					$vertical_price{Total} = $vertical_price{Price} * $vertical_length;
					$Results{Breakdown} .= sprintf('Wheel: $%1$.2f%2$s * %4$.2finches=$%3$.2f<br/>', @vertical_price{'Price','units','Total'}, $vertical_length );
				} elsif ( $vertical_price{units} eq 'per foot' ) {
					$vertical_price{Total} = $vertical_price{Price} * $vertical_length/12;
					$Results{Breakdown} .= sprintf('Wheel: $%1$.2f%2$s * %4$.2finches=$%3$.2f<br/>', @vertical_price{'Price','units','Total'}, $vertical_length/12 );
				} else {
          $vertical_price{Total} = $vertical_price{Price};
					$openprint::log->error("Unknown units set on vertical material price ($vertical_price{units}) on $$Equipment{name}");
					$Results{Breakdown} .= "Unknown units set on vertical material price ($vertical_price{units})<br/>";
				} # end if
			} # end if
		} else {
			$Results{Breakdown} .= 'No material found for ScoringWheel<br/>';
		} # end if
	} else {
		$vertical_price{Total} = 0;
	} # end if vertical_rule

	$Results{setup} = \%setupPrice;
	$Results{Service} = \%servicePrice;
	$Results{Vertical} = \%vertical_price;
	$Results{Horizontal} = \%horizontal_price;
	return \%Results;
} # end sub get_price

# figures out the number of scores needed. May return 0 if signature doesn't need it.
sub get_scores {
	my ( $Project, $specs, $sig_specs, $Paper ) = @_;

	my $form = $$sig_specs{SignatureIndex};
	if (!signature_needs($Project, $specs, $sig_specs, $Paper)) {
		$$specs{"txtVerticalQty-$form"} = 0;
		$$specs{"txtHorizontalQty-$form"} = 0;
		$openprint::log->error("Signature $form doesn't need scoring in get_scores") if DEBUG;
		return;
	} # end if

	if ( $$sig_specs{txtSignatureType} eq 'Cover Pages' ) {
		if ( $Project->get_book_type() eq 'PerfectBound' ) {
			$$specs{"txtVerticalQty-$form"} = 4;
			$$specs{"txtHorizontalQty-$form"} = 0;
		} elsif ( $$sig_specs{txtWidth}/$$sig_specs{txtFinalWidth} != 2 ) {
			$$specs{"txtVerticalQty-$form"} = 2;
			$$specs{"txtHorizontalQty-$form"} = 0;
		} elsif ( $$sig_specs{txtSpreadSize} > 2 ) {
			$$specs{"txtVerticalQty-$form"} = 1;
			$$specs{"txtHorizontalQty-$form"} = 0;
		} # end if
	} elsif ( $$sig_specs{txtSignatureType} eq 'Interior Pages' ) {
		if ( $$sig_specs{SignatureIndex} == 1 ) {
			$$specs{"txtVerticalQty-$form"} = 1;
			$$specs{"txtHorizontalQty-$form"} = 0;
		} # end if
	} elsif ( $$sig_specs{txtSignatureType} eq 'Gate Folded Pages' ) {
    if ( $$sig_specs{rdbTemplateType} eq 'SingleGateFold') {
      $$specs{"txtVerticalQty-$form"} = 1;
    } elsif ( $$sig_specs{rdbTemplateType} eq 'DoubleGateFold') {
      $$specs{"txtVerticalQty-$form"} = 2;
    } else {
      $openprint::log->error("No template folded in $$sig_specs{txtSignatureType} Gate Folded Pages form $form $$sig_specs{rdbTemplateType}");
    }
	} else { # normal printing
		my $width_folds = Math::Round::nearest( 1, $$sig_specs{txtWidth}/$$sig_specs{txtFinalWidth})-1 if $$sig_specs{txtFinalWidth};
		my $height_folds = Math::Round::nearest( 1, $$sig_specs{txtHeight}/$$sig_specs{txtFinalHeight})-1 if $$sig_specs{txtFinalHeight};
		$openprint::log->error("Width folds: $width_folds height folds: $height_folds template $$sig_specs{rdbTemplateType} $$sig_specs{txtWidth}/$$sig_specs{txtFinalWidth} $$sig_specs{txtHeight}/$$sig_specs{txtFinalHeight}") if DEBUG;
		if ( !$$sig_specs{rdbTemplateType} or
      ($$sig_specs{rdbTemplateType} eq 'Portrait') or
      ($$sig_specs{rdbTemplateType} eq 'Landscape')
    ) {
      # needs no folding
		} elsif ( sets::isin( $$sig_specs{rdbTemplateType}, ['4PageSignatureFold','2PanelFold','BusCardLandscapeFold','BusCardPortraitFold']) ) {
			$$specs{"txtVerticalQty-$form"} = 1;
			$$specs{"txtHorizontalQty-$form"} = 0;
		} elsif ( $$sig_specs{rdbTemplateType} =~ /3PanelZ?Fold/ ) {
			$$specs{"txtVerticalQty-$form"} = $width_folds;
			$$specs{"txtHorizontalQty-$form"} = $height_folds;
		} elsif ( $$sig_specs{rdbTemplateType} eq 'AccordianFold' ) {
			$$specs{"txtVerticalQty-$form"} = $width_folds;
			$$specs{"txtHorizontalQty-$form"} = $height_folds;
		} elsif ( sets::isin( $$sig_specs{rdbTemplateType}, '4PanelFold','4PanelZFold', 'AccordianFold4Panel') ) {
			if ( $width_folds ) {
				$$specs{"txtVerticalQty-$form"} = 3;
			} else {
				$$specs{"txtHorizontalQty-$form"} = 3;
			} # end if
		} elsif ( $$sig_specs{rdbTemplateType} =~ /5PanelZ?Fold/ ) {
			$$specs{"txtVerticalQty-$form"} = $width_folds;
			$$specs{"txtHorizontalQty-$form"} = $height_folds;
		} elsif ( $$sig_specs{rdbTemplateType} =~ /6PanelZ?Fold/ ) {
			$$specs{"txtVerticalQty-$form"} = $width_folds;
			$$specs{"txtHorizontalQty-$form"} = $height_folds;
		} elsif ( $$sig_specs{rdbTemplateType} eq 'SingleGateFold' ) {
			$$specs{"txtVerticalQty-$form"} = 2;
			$$specs{"txtHorizontalQty-$form"} = 0;
		} elsif ( $$sig_specs{rdbTemplateType} eq 'DoubleGateFold' ) {
			$$specs{"txtVerticalQty-$form"} = 3;
			$$specs{"txtHorizontalQty-$form"} = 0;
		} elsif ( sets::isin( $$sig_specs{rdbTemplateType}, 'PF1Pocket', 'PF2Pocket' ) ) {
			$$specs{"txtVerticalQty-$form"} = 2;
			$$specs{"txtHorizontalQty-$form"} = 0;
		} elsif ( sets::isin( $$sig_specs{rdbTemplateType}, '2Panel2Pocket', '2Panel1Pocket' ) ) {
			$$specs{"txtVerticalQty-$form"} = 1;
			$$specs{"txtHorizontalQty-$form"} = 1;
		} else {
			$openprint::log->debug("No template($$sig_specs{rdbTemplateType}) width_folds:$width_folds height_folds:$height_folds") if DEBUG;
			if ( $width_folds or $height_folds ) {
				$$specs{"txtVerticalQty-$form"} = $width_folds;
				$$specs{"txtHorizontalQty-$form"} = $height_folds;
			} elsif ( $$specs{txtFinalWidth} ) {
				my $cols = $$sig_specs{txtWidth} / $$specs{txtFinalWidth};
				my $mod_cols = $$sig_specs{txtWidth} % $$specs{txtFinalWidth};
				if ( $cols and ! $mod_cols ) {
					$$specs{"txtVerticalQty-$form"} = 2;
				} elsif ( $$specs{txtFinalHeight} ) {
					my $rows = $$sig_specs{txtHeight} / $$specs{txtFinalHeight};
					my $mod_rows = $$sig_specs{txtHeight} % $$specs{txtFinalHeight};
					if ( $rows and ! $mod_rows ) {
						$$specs{"txtHorizontalQty-$form"} = 0;
					} # end if
				} # end if
			} elsif ( ! $$specs{"chkOverrideQty-$form"} ) {
				$openprint::log->debug("Not setting scores");
				$$specs{"txtVerticalQty-$form"} = 0;
				$$specs{"txtHorizontalQty-$form"} = 0;
			} # end if

		} # end if
	} # end if
} # end sub get_scores

sub get_specs {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;
	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();

	@{$$variable{SignatureGroups}} = ();

	my @capabilities = ( 'Y', 'When Printing' );
	push @capabilities, 'For Pocket Folders' if $Project->Type()->name() eq 'PresentationFolders';
	push @capabilities, 'When Folding' if $$services{Folding};
	push @capabilities, 'When PerfectBound' if $$services{PerfectBound};
	push @capabilities, 'When Stitching' if $$services{SaddleStitching} or $$services{LoopStitching};

	@{$$variable{Equipment}} = openprint::Equipment->find( 'Specifications' => {'Scoring Capable'=>\@capabilities}, 'useinestimating'=>1,'order'=>'strName');

	foreach my $signature_service_index ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
		push @{$$variable{SignatureGroups}}, @$sig_specs{'SignatureIndex','txtServiceDescription'};
	} # end foreach
} # end sub get_specs

sub signature_summary {
	my ( $Project, $service_index, $specs, $qty_index, $s_id, $sig_specs ) = @_;
	$specs = openprint::service::get_specs_ref( $Project, $service_index ) if ! $specs;
	$sig_specs = openprint::service::get_specs_ref( $Project, $s_id ) if ! $sig_specs;
	if ( $qty_index ) {
		my @folds;
		if ( $$specs{"ddmEquipment-$$sig_specs{SignatureIndex}-$qty_index"} ) {
			my $Equipment = new openprint::Equipment( $$specs{"ddmEquipment-$$sig_specs{SignatureIndex}-$qty_index"} );
			return ' on ' . $Equipment->name();
		} # end if
	} # end if
	return;
} # end sub signature_summary

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	if ( $qty_index ) {
		my $html;
		foreach my $s_s_id ( $Project->signatures( { sort=>1 } ) ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
			next if ! $$specs{"ddmEquipment-$$sig_specs{SignatureIndex}-$qty_index"}; 
			my $Paper = openprint::Paper::load_from_signature( $Project, $sig_specs, $qty_index );
			if ( signature_needs( $Project, $specs, $sig_specs, $Paper ) ) {
				$html .= 'Form ' . $$sig_specs{SignatureIndex} . ($$sig_specs{txtServiceDescription}?' ' . $$sig_specs{txtServiceDescription}:'') . ' scored ' .signature_summary( $Project, $service_id, undef, $qty_index, $s_s_id, undef ) . "\n";
			} # end if
		} # end foreach
		return $html;
	} # end if
} # end sub summary

sub fits_on_equipment {
	my ( $Equipment, $I, $vertical_scores, $horizontal_scores ) = @_;

	my $width = $I->layout_width();
	my $height = $I->layout_height();

	my $minimum_score_size = $Equipment->specification('Minimum Score Size');
	if ( $minimum_score_size ) {
		if ( $vertical_scores and $height < $minimum_score_size ) {
			return "Doesn't fit minimum Score Size Height $height < $minimum_score_size";
		} elsif ( $horizontal_scores and $width < $minimum_score_size ) {
			return "Doesn't fit minimum Score Size Width $width < $minimum_score_size";
		} # end if
	} # end if

	my $maximum_score_size = $Equipment->specification('Maximum Score Size');
	if ( $maximum_score_size ) {
		if ( $vertical_scores and $height > $maximum_score_size ) {
			return "Doesn't fit maximum Score Size Height $height > $maximum_score_size";
		} elsif ( $horizontal_scores and $width > $maximum_score_size ) {
			return "Doesn't fit maximum Score Size Width $width > $maximum_score_size";
		} # end if
	} # end if

	my $Paper = $I->Paper();
	my $calliper = $Paper->calliper();
	if ( my $min_calliper = $Equipment->specification('Minimum Score Calliper') ) {
		if ( $calliper < $min_calliper ) {
			return 'Calliper too small: ('.$calliper.'), Min: '.$min_calliper;
		} # end if
	} # end if

	my $max_calliper = $Equipment->specification('Maximum Score Calliper');
	if ( $max_calliper and ( $calliper > $max_calliper ) ) {
		return "Calliper too big max($max_calliper) < $calliper on $$Equipment{strid}";
	} # end if

	my $max_feed_width = $Equipment->specification('Maximum Feed Width');
	if ( $max_feed_width ) {
		my $orientation = $Equipment->specification('Orientation');

		if ( $orientation ) {
			if (
					( $orientation eq 'Portrait' and ($I->layout_width() <= $I->layout_height()) ) or
					( $orientation eq 'Landscape' and ($I->layout_width() >= $I->layout_height()) )
				 ) {
				if ( $width >= $max_feed_width ) {
					return "Score no good due to max feed width($max_feed_width) on width ($width).<br/>";
				} # end if
			} else {
				if ( $height >= $max_feed_width ) {
					return "Score no good due to max feed width($max_feed_width) on width ($height).<br/>";
				} # end if
			} # end if
		} else {
			if ( $vertical_scores and $horizontal_scores ) {
# Do nothing, we already know it fits on the machine, and it has to go one way or another.
			} elsif ( $vertical_scores ) {
# Ona folder scoring is done with a wheel, so for a vertical score we feed by width
				if ( $$I{image_orientation} == openprint::Imposition::Vertical ) {
					if ( $width >= $max_feed_width ) {
						return "Scoring no good due to max feed width($max_feed_width) on width ($width).<br/>";
					} # end if
				} else {
					if ( $height >= $max_feed_width ) {
						return "Scoring no good due to max feed width($max_feed_width) on height ($height).<br/>";
					} # end if
				} # end if
			} elsif ( $horizontal_scores ) {
				if ( $$I{image_orientation} == openprint::Imposition::Vertical ) {
					if ( $height >= $max_feed_width ) {
						return "Scoring no good due to max feed width($max_feed_width) on height (".$height.").<br/>";
					} # end if
				} else {
					if ( $width >= $max_feed_width ) {
						return "Scoring no good due to max feed width($max_feed_width) on width (".$width.").<br/>";
					} # end if
				} # end if
			} else {
				return 'Running ' . $height . ' on feed of ' . $max_feed_width . '<br/>';
			} # end if
		} # end if orientation or not
	} elsif ( DEBUG ) {
		$openprint::log->debug('No max feed');
	} # end if max_feed
	if ( ( $_ = $Equipment->specification('Maximum Imposition') ) and ( $_ < $$I{imposition} ) ) {
		return "Imposition $$I{imposition}out too high. Maximum: $_<br/>";
	} # end if
	my $type = $Equipment->specification('Type');
	if ( $type eq 'Press' ) {
		if ( $_ = $Equipment->fits( $Paper->width(), $Paper->height(), $Paper->calliper() ) ) {
			return "Doesn't fit. $_<br/>";
		} # end if
	} else {
		if ( $_ = $Equipment->fits( $width, $height ) ) {
			return "Doesn't fit. $_<br/>";
		} # end if
	} # end if
	return '';
} # end sub fits_on_equipment

sub is_desirable {
	my ( $Equipment, $I, $vertical_scores, $horizontal_scores ) = @_;
	my $type = $Equipment->specification('Type');
	if ( $type eq 'Folder' ) {
# Not being folded
# Don't want to run an impo that results in 2out sections being output, we don't want to cut after folding
		if ( $vertical_scores and $horizontal_scores ) {
# Do nothing, we already know it fits on the machine, and it has to go one way or another.
			return 'Folders can\'t do scores in both directions.<br/>';
		} elsif ( $vertical_scores ) {
# Ona folder scoring is done with a wheel, so for a vertical score we feed by width
			if ( $$I{image_orientation} == openprint::Imposition::Vertical ) {
				if ( $$I{rows} > 1 ) {
					return "Results in $$I{rows} out pieces. Undesirable.<br/>";
				} # end if
			} else {
				if ( $$I{columns} > 1 ) {
					return "Results in $$I{columns} out pieces. Undesirable.<br/>";
				} # end if
			} # end if
		} elsif ( $horizontal_scores ) { 
			if ( $$I{image_orientation} == openprint::Imposition::Vertical ) {
				if ( $$I{columns} > 1 ) {
				return "Results in $$I{columns} out pieces. Undesirable.<br/>";
				} # end if
			} else {
				if ( $$I{rows} > 1 ) {
					return "Results in $$I{rows} out pieces. Undesirable.<br/>";
				} # end if
			} # end if
		} # end if
	} # end if Folder
	return '';
} # end if is_desireable

sub save {
} # end sub save

1;
__END__
