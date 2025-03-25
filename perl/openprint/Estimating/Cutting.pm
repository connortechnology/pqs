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

use strict;
use warnings;
package openprint::Estimating::Cutting;
use POSIX qw{ ceil };

use openprint ();
use vars qw( $log $dbh %config );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;

require openprint::Equipment;
require openprint::service;
require openprint::Service;
require openprint::Estimating::DieCutting;

use constant DEBUG => 0;

my @equipment;
my @PreFoldingEquipment;

my @variables = (
    'txtPrice1', 'txtPrice2', 'txtPrice3',
    'hdnBreakdown1', 'hdnBreakdown2', 'hdnBreakdown3',
    'Markup1','Markup2','Markup3',
    'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
    'MPrice1', 'MPrice2', 'MPrice3',
    'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
    'txtRunTime1', 'txtRunTime2', 'txtRunTime3',
    'txtFinishedCalliper',
    'alert',
    );

my $CuttingService;
my $CuttingMakeReady;
my $PileHandling;
my $BladeCleaning;

sub variables {
  my @v = @variables;

  my $Project = new openprint::Project( $_[0] );
  foreach my $s_s_id ( $Project->signatures() ) {
    my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
    my $form = $$sig_specs{SignatureIndex};
    push @v, "txtAdditionalCuts$form";
    push @v, map { ( "txtCalculatedCuts-$form-$_",
        "ddmEquipment-$form-$_",
        "chkOverrideCalculatedCuts-$form-$_",
        "txtVerticalCuts-$form-$_",
        "txtHorizontalCuts-$form-$_",
        "txtDVerticalCuts-$form-$_",
        "txtDHorizontalCuts-$form-$_",
        "FoldingCuts-$form-$_",
        "FoldingEquipment-$form-$_",
        "OverrideFoldingCuts-$form-$_",
        "OverrideFoldingEquipment-$form-$_",
        "ddmStockCutEquipment-$form-$_",
        "chkOverrideStockCutEquipment-$form-$_",
        ) } $Project->quantity_indexes();
  } # end foreach

  return @v;
} # end sub variables

sub outputs { 
} # end sub outputs

sub no_outputs {
} # end sub no_outputs

sub has_overrides {
  my ( $Project, $service_id, $specs ) = @_;
  $specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

  my @v;
  foreach my $s_s_id ( $Project->signatures() ) {
    my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
    my $form = $$sig_specs{SignatureIndex};
    foreach my $qty_index ( $Project->quantity_indexes() ) {
      push @v, map { ($$specs{"$_-$form-$qty_index"} and ($$specs{"$_-$form-$qty_index"} eq 'Y') )? "$_-$form-$qty_index" : () } ( 'chkOverrideEquipment', 'chkOverrideStockCutEquipment', 'chkOverrideCalculatedCuts' );
    } # end foreach
  } # end foreach
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		push @v, map { ( $$specs{"$_$qty_index"} and ($$specs{"$_$qty_index"} eq 'Y')) ? "$_$qty_index" : () } ( 'OverridePrice' );
	}

  return @v;

} # end sub has_overrides

sub signature_needs {
  my ( $Project, $specs, $sig_specs, $q_index ) = @_;

  if ( $Project->Type()->name() eq 'Envelopes' ) {
    $openprint::log->debug(" ** Project Type is Envelopes, Cutting Service is NOT needed ** ") if DEBUG;
    return 0;
  } # end if 

  my $services = $Project->services();

  if ( $$services{Cutting} and ! $specs ) {
# Could call sig_needs when there is no cutting in the project
    $specs = openprint::service::get_specs_ref($Project, $$services{Cutting}[0]);
  }

  foreach my $qty_index ( $q_index ? ( $q_index ) : $Project->quantity_indexes() ) {
#$openprint::log->debug("Cutting sig needs: imp: " .  $$specs{'txtImposition'.$qty_index} );
#$openprint::log->debug("Cutting sig needs: stock: " . join('x', @$specs{'hdnSuppliedStockWidth'.$qty_index,'hdnSuppliedStockHeight'.$qty_index} ) );
#$openprint::log->debug("Cutting sig needs: ssize: " . join('x', @$specs{'txtWidth','txtHeight'} ) );
    if ( $$sig_specs{'txtImposition'.$qty_index} and ($$sig_specs{'txtImposition'.$qty_index} > 1) ) {
      $openprint::log->debug(" ** Imposition > 1, Cutting needed ! ** ") if DEBUG;
      return 1;
    } # end if
    
    if ($$sig_specs{"ddmBleedSize$qty_index"}) {
      foreach my $key ('BleedBottom','BleedTop','BleedLeft','BleedRight') {
        return 1 if $$sig_specs{$key};
      }
    }
    if (!$$sig_specs{rdbColourBar} or $$sig_specs{rdbColourBar} ne 'N') {
      return 1;
    }

    # If folding imposition doesn't match printed imposition
    if ( $$services{Folding} and @{$$services{Folding}} ) {
      my $folding_specs = openprint::service::get_specs_ref($Project, $$services{Folding}[0]);
      #if ( $$Imposition{Folds} ) {
      #@folding_impositions = @{$$Imposition{Folds}};
      #} else {
      my $Imposition = new openprint::Imposition();
      $Imposition->load( $sig_specs, $qty_index, $Project );

      my @folding_impositions = openprint::Estimating::Folding::get_Folds( $folding_specs, $Imposition, $qty_index );
        #}
      if (@folding_impositions>1 or (@folding_impositions==1 and $folding_impositions[0]->quantity() > 1)) {
        return 1;
      }
    } # end if

    if ( signature_has_cut_stock($sig_specs, $qty_index) ) {
      $openprint::log->debug(" Supplied Width $$sig_specs{'hdnSuppliedStockWidth'.$qty_index} != $$sig_specs{txtWidth} or $$sig_specs{'hdnSuppliedStockHeight'.$qty_index} != $$sig_specs{txtHeight} Cutting needed ! ** ") if DEBUG;
      return 1;
    } # end if
    if ( $specs and $$specs{"chkOverrideCalculatedCuts-$$sig_specs{SignatureIndex}-$qty_index"} ) {
      return 1;
    }
  } # end foreach qty_index

  if ( $$services{NoBindery} ) {
    $openprint::log->debug(' ** Project is marked as No bindery, Cutting not needed ! ** ') if DEBUG;
    return 0;
  } # end if

  foreach my $service_name ( 'PlasticCoil', 'MetalCoil', 'PlasticComb', 'Cerlox', 'DoubleLoopWire' ) {
    if ( $$services{$service_name} ) {
      return 1;
    } # end if
  } # end foreach

  return 0;
} # end sub signature_needs

sub signature_needs_bindery_cutting {
	my ( $Project, $specs, $sig_specs, $qty_index ) = @_;
	my $services = $Project->services();
	if ( $$services{NoBindery} ) {
		$openprint::log->debug(" ** Project is marked as No bindery, Cutting not needed ! ** ") if DEBUG;
		return 0;
	} # end if

	if (0 and $$services{DieCutting} ) {
		$openprint::log->debug(" ** Project is marked as DieCutting, Cutting not needed ! ** ") if DEBUG;
		return 0;
	} # end if

	# Pretty much always need final trim, except DieCutting
	return 1;
	if ( $$sig_specs{'txtImposition'.$qty_index} > 1 ) {
		$openprint::log->debug("Imposition > 1, Cutting needed ! ** ") if DEBUG;
		return 1;
	} # end if
	if ( $specs and $$specs{"chkOverrideCalculatedCuts-$$sig_specs{SignatureIndex}-$qty_index"} ) {
		return 1;
	}
	foreach my $service_name ( 'PlasticCoil', 'MetalCoil', 'PlasticComb', 'Cerlox', 'DoubleLoopWire' ) {
		if ( $$services{$service_name} ) {
			return 1;
		} # end if
	} # end foreach
	return 0;
}

sub signature_has_cut_stock {
	my ( $sig_specs, $qty_index ) = @_;
	if ( ((!$$sig_specs{'StockType'.$qty_index}) or ($$sig_specs{'StockType'.$qty_index} ne 'Roll')) and ! (
				(
				 $$sig_specs{'hdnSuppliedStockWidth'.$qty_index} == $$sig_specs{txtWidth}
				 and
				 $$sig_specs{'hdnSuppliedStockHeight'.$qty_index} == $$sig_specs{txtHeight}
				) or (
					$$sig_specs{'hdnSuppliedStockWidth'.$qty_index} == $$sig_specs{txtHeight}
					and
					$$sig_specs{'hdnSuppliedStockHeight'.$qty_index} == $$sig_specs{txtWidth}
					)
				) ) {
		$openprint::log->debug(" Supplied Width $$sig_specs{'hdnSuppliedStockWidth'.$qty_index} != $$sig_specs{txtWidth} or $$sig_specs{'hdnSuppliedStockHeight'.$qty_index} != $$sig_specs{txtHeight} Cutting needed ! ** ") if DEBUG;
		return 1;
	} # end if
	return 0;
}

# A function that is smart enough to return true if the project needs cutting, and false if it doesn't.
sub neccessary {
	my ( $Project ) = @_;

  my $services = $Project->services();

  if ( $$services{NoBindery} ) {
    $openprint::log->debug(" ** Project is marked as No bindery, Cutting not needed ! ** ") if DEBUG;
    return 0;
  } # end if

  foreach my $service_name ( 'PlasticCoil', 'MetalCoil', 'PlasticComb', 'Cerlox', 'DoubleLoopWire' ) {
    if ( $$services{$service_name} ) {
      return 1;
    } # end if
  } # end foreach
  my $specs = openprint::service::get_specs_ref( $Project, $$services{Cutting}[0] ) if $$services{Cutting} and @{$$services{Cutting}};

  foreach my $signature_service_index ( $Project->signatures() ) {
    my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
    if ( signature_needs( $Project, $specs, $sig_specs ) ) {
      return 1;
    } # end if
  } # end foreach
  $openprint::log->debug("CUTTING NOT NEEDED!") if DEBUG;
  return 0;
} # end sub neccessary

sub load_equipment {
  my ( $Project ) = @_;
  my $services = $Project->services();

  my @capabilities = ('Y','When Printing','When Folding');
  if ( $$services{SaddleStitching} or $$services{LoopStitching} ) {
    push @capabilities, 'When Stitching';
  } # end if
  if ( sets::isin( $Project->Type()->name(), ['Banners','InkjetOutputs'] ) ) {
    push @capabilities, 'Large Format';
  } # end if
  $log->debug("load_equipment");
  @equipment = openprint::Equipment->find(
			Specifications 	=> {'Cutting Capable'=>\@capabilities},
			useinestimating	=> 1,
			order						=> 'lower(strName)'
			);
  @PreFoldingEquipment = openprint::Equipment->find(
			Specifications => {'Cutting Capable'=>['Y','When Printing']},
			useinestimating=>1,
			order=>'lower(strName)'
			);
} # end sub load_equipment

sub init {
  my ( $Project, $calc_hash ) = @_;
	# These could be reduced to 1 db call
  $CuttingService = openprint::Service->find_one(name=>'Cutting');
  $CuttingMakeReady = openprint::Service->find_one(name=>'CuttingMakeReady');
  $PileHandling = openprint::Service->find_one(name=>'CuttingPileHandling');
  $BladeCleaning = openprint::Service->find_one(name=>'Blade Cleaning');
  load_equipment($Project);
}

sub signature_calc_stock_cutting {
  my ( $Project, $specs, $qty_index, $Stocks ) = @_;

  my %results = (
      Status	=> 'calculated',
      alert		=>	'',
      Breakdown	=> 	'',
      Price => 0,
      );

  my @my_equipment;
  if (
			(defined $$specs{"chkOverrideStockCutEquipment-$qty_index"})
			and
			($$specs{"chkOverrideStockCutEquipment-$qty_index"} eq 'Y')
		 ) {
    $openprint::log->debug("Overriding Equipment! " . $$specs{"ddmStockCutEquipment-$qty_index"}) if DEBUG;
    @my_equipment = ( new openprint::Equipment( $$specs{"ddmStockCutEquipment-$qty_index"} ) );
  } else {
    @my_equipment = @equipment;
  } # end if

  if ( !@my_equipment ) {
    $results{alert} = 'We have no cutting equipment.<br/>';
    $results{Status} = 'uncalculated';
    return %results;
  } # end if

  my $total = 0;
  my $total_mprice = 0;

  $results{Stocks} = $Stocks;

  foreach my $Stock_Amount ( @{$Stocks} ) {
    my $Paper = $$Stock_Amount{Stock};
    my $paper_string = $Paper->id_string();
    if ( ! $Paper ) {
      $results{alert} .= 'Stock object not found for ' . $paper_string.'<br/>';
      $openprint::log->error('Stock object not found for ' . $paper_string );
      next;
    } # end if
# Add cutting the sheet prior to printing
    if ( ! ( $$Paper{width} and $$Paper{height} ) ) {
      $results{alert} .= 'Paper does not have width and height for '.$paper_string.'<br/>';
      $openprint::log->error('Paper does not have width and height for '.$paper_string );
      next;
    } # end if
    if ( ($$Paper{width} == $$Paper{start_width}) and ($$Paper{height} == $$Paper{start_height} ) ) {
      $results{alert} .= 'Paper does not need cutting '.$paper_string.'<br/>';
      $openprint::log->error('Paper does not need cutting for ' . $paper_string );
      next;
    } # end if
    my $calliper = $$Paper{calliper};
    if ( ! $calliper ) {
      $results{alert} .= 'Calliper is unknown for Stock. ' . $Paper->to_string().'<br/>';
    } # end if

    my ( $start_width, $start_height, $width, $height );

# We already tested that it has height and width... so in order for start > not start... it must be defined...
    if ( ($$Paper{start_width} >= $$Paper{width}) and ($$Paper{start_height} >= $$Paper{height}) ) {
      ( $start_width, $start_height, $width, $height ) = @$Paper{'start_width','start_height','width','height'};
    } else {
      ( $start_width, $start_height, $width, $height ) = @$Paper{'start_width','start_height','height','width'};
    } # end if

    $results{Breakdown} .= sprintf('<b>Cutting prior to printing: %s</b><br/>', $Paper->to_string() );

    my $mprice = 0;
    my $bestPrice = undef;
    my $bestEquipment;

# Has to happen on normal cutters
    foreach my $Equipment ( @my_equipment ) {
      my $capable = $Equipment->specification( 'Cutting Capable' );

      if ( $capable ne 'Y' and $capable ne 'Large Format' ) {
        $results{Breakdown} .= 'Equipment ' . $$Equipment{name}.': Not capable for stock cutting.' if @my_equipment == 1;
        next;
      } 
      $results{Breakdown} .= 'Equipment: '.$$Equipment{name}.':';

      my $reason = $Equipment->fits( $start_width, $start_height );
      if ( $reason ) {
        $results{Breakdown} .= $reason . '<br/>';
        next;
      } # end if
      $results{Breakdown} .= '<br/>';

      my $liftDepth = $Equipment->specification( 'Maximum Lift Depth', $$Paper{calliper} );
# no lift depth means 1 at a time.

      my $width_cuts = int( $start_width / $width ) - 1;
      my $height_cuts = int( $start_height / $height ) - 1;
      my $sheets = $$Stock_Amount{quantity};
      $sheets = int( $sheets / ($width_cuts+1) ) if $width_cuts > 0;
      $sheets = int( $sheets / ($height_cuts+1) ) if $height_cuts > 0;
# This accounts for cutting a sheet out of another, but not in half...
      if ( 0 ) {
        if ( $width_cuts == 1 and $start_width != $width ) {
          $width_cuts += 1;
        } # end if
        if ( $height_cuts == 1 and $start_height != $height ) {
          $height_cuts += 1;
        } # end if
      }

      my $piles = $liftDepth ? ceil( $sheets*$calliper/$liftDepth ) : $sheets;

      my $price = 0;
      if ( $CuttingMakeReady ) {
        my %setup = $CuttingMakeReady->get_price( undef, $Equipment );
        if ($setup{units} and ($setup{units} eq 'per cut')) {
          my $cuts = $width_cuts + $height_cuts;
          %setup = $CuttingMakeReady->get_price( $cuts, $Equipment );
          $setup{Total} = $setup{Price} * $cuts;
          $results{Breakdown} .= sprintf('Make Ready: $%1$.2f%2$s * %4$d cuts = $%3$.2f<br/>',
							@setup{'Price','units','Total'}, $cuts);
          $price += $setup{Total};
        } else {
          $results{Breakdown} .= sprintf('Make Ready: %.2f<br/>', $setup{Price});
          $price += $setup{Price};
        } # end if
      } # end if MakeReady

      if ( $PileHandling ) {
        my %pilehandlingprice = $PileHandling->get_price( $piles, $Equipment );
        if ( %pilehandlingprice ) {
          if ( $pilehandlingprice{units} eq 'per pile' ) {
            $pilehandlingprice{Total} = $pilehandlingprice{Price} * $piles;
            $price += $pilehandlingprice{Total};
            $results{Breakdown} .= sprintf('Pile handling: $%1$.2f%2$s * %4$d piles = $%3$.2f<br/>', @pilehandlingprice{'Price','units','Total'}, $piles );
          } else {
            $openprint::log->error("invalid units $pilehandlingprice{units} on $$PileHandling{name} on $$Equipment{name}");
            $results{alert} .= "invalid units $pilehandlingprice{units} on $$PileHandling{name} on $$Equipment{name}<br/>";
          } # end if
        } # end if
      } elsif ( DEBUG ) {
        $openprint::log->debug("No PileHandling");
      } # end PileHandling
      my $service_price = 0;
      if ( $CuttingService ) {
        my %ServicePrice = $CuttingService->get_price( $sheets, $Equipment );
        foreach my $cuts ( $width_cuts, $height_cuts ) {
          next if ! $cuts;
          $openprint::log->warn("Negative CUTS!") if $cuts < 1;
          my $cut_price = ( $piles * $cuts * $ServicePrice{Price} );
          $cuts += 1;
          $service_price += $cut_price;
          $results{Breakdown} .= sprintf('Cutting %d sheets into %d sheets in %d piles: $%.2f<br/>',
							$sheets, $sheets*$cuts, $piles, $cut_price );
          $sheets *= $cuts;
        } # end foreach
        $price += $service_price;
      } # end if Cutting
      my %cleaning;
      if ( $Paper->bladecleaning() and $BladeCleaning ) {
        %cleaning = $BladeCleaning->get_price( undef, $Equipment );
        $results{Breakdown} .= sprintf('Blade Cleaning: $%.2f<br/>', $cleaning{Price} );
        $price += $cleaning{Price};
      } # end if
      if ( ( ! defined $bestPrice ) or ( $bestPrice > $price ) ) {
        $mprice = $service_price + ( defined $cleaning{Price} ? $cleaning{Price} : 0 );
        $bestPrice = $price;
        $bestEquipment = $Equipment;
      } # end if
    } # end for each equipment
    if ( ! $bestEquipment ) {
      $results{alert} .= "No equipment found for cutting stock $paper_string<br/>";
    } # end if
    $total += $bestPrice;
    $$Stock_Amount{Equipment} = $bestEquipment;
    $total_mprice += $mprice;
  } # end foreach Paper
  $$specs{"txtQuantity$qty_index"} = $Project->quantity( $qty_index ) if ! $$specs{"txtQuantity$qty_index"};	
  $results{Price} 		= Math::Round::nearest( 0.01, $total );
  $results{MPrice}		= Math::Round::nearest( 0.01,($total_mprice/$$specs{'txtQuantity'.$qty_index})*1000 );

  $results{Status} = 'uncalculated' if $results{alert};

  return %results;
} # end sub signature_calc_stock_cutting

sub signature_calc {
  my ( $Project, $sig_specs, $specs, $qty_index, $Paper, $Imposition, $folding_specs, $calc_hash ) = @_;

  my %results = (
    overs => 0,
    Status		=>	'calculated',
    Breakdown	=>	'<b>Post press:</b><br/>',
  );
  if ( !$$Paper{cuttable} ) {
    $results{alert} = $Paper->to_string() . ': Stock is not cuttable.';
    return %results;
  } # end if
  if ( !$$Imposition{imposition} ) {
    $openprint::log->error('Have empty imposition in Cutting.');
    $results{alert} = 'Imposition was empty.';
    $results{Status} = 'uncalculated';
    return %results;
  }
  $$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};	
  if ( ! $$specs{"txtQuantity$qty_index"} ) {
    $results{alert} = 'No quantity entered.<br/>';
    $results{Status} = 'uncalculated';
    return %results;
  } # end if

  my $services = $Project->services();
  my $printing_specs = openprint::service::get_specs_ref($Project, $$services{''}[0]) if $$services{''} and @{$$services{''}};

  my $form = $$sig_specs{SignatureIndex};

  my @my_equipment;
  if (
			(defined $$specs{"chkOverrideEquipment-$form-$qty_index"})
			and
			($$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y')
		 ) {
    @my_equipment = ( new openprint::Equipment($$specs{"ddmEquipment-$form-$qty_index"}) );
  } else {
    load_equipment($Project) if ! @equipment;
    @my_equipment = @equipment;
  } # end if

  if ( ! @my_equipment ) {
    $results{alert} = 'We have no cutting equipment.<br/>';
    $results{Status} = 'uncalculated';
    return %results;
  } # end if

# Grab the Calliper

  my $calliper = $$Paper{calliper};
  if ( !$calliper ) {
    $openprint::log->debug('**** NO Calliper ****') if DEBUG;
    $results{alert} .= "Calliper is unknown for signature $form.<br/>";
    $results{Status} = 'uncalculated';
    return %results;
  } # end if

  my $stitching_imposition = 0;
  my $stitching_specs;

  if ( $$services{SaddleStitching} ) {
    $stitching_specs = openprint::service::get_specs_ref( $Project, $$services{SaddleStitching}[0] );
    $stitching_imposition = $$stitching_specs{'Imposition'.$qty_index};
  } elsif ( $$services{LoopStitching} ) {
    $stitching_specs = openprint::service::get_specs_ref( $Project, $$services{LoopStitching}[0] );
    $stitching_imposition = $$stitching_specs{'Imposition'.$qty_index};
  } elsif ( $$services{PerfectBound} ) {
    $stitching_specs = openprint::service::get_specs_ref( $Project, $$services{PerfectBound}[0] );
    $stitching_imposition = $$stitching_specs{'Imposition'.$qty_index};
  } elsif ( $$services{CornerStitching} ) {
    $stitching_specs = openprint::service::get_specs_ref( $Project, $$services{CornerStitching}[0] );
    $stitching_imposition = $$stitching_specs{'Imposition'.$qty_index};
  } # end if

  my %pretrim_sides;
  my $Stitcher;
  if ( $stitching_specs and $$stitching_specs{"ddmEquipment$qty_index"} ) {
    $Stitcher = new openprint::Equipment($$stitching_specs{"ddmEquipment$qty_index"});
    my $pretrim_sides = $Stitcher->specification('Pre-trimmed Edges '.$$sig_specs{txtSignatureType});
    $pretrim_sides = $Stitcher->specification('Pre-trimmed Edges') if ! $pretrim_sides;
    %pretrim_sides = map { $_, $_ } split(',', $pretrim_sides) if $pretrim_sides;
  }
  $stitching_imposition = 1 if ! defined $stitching_imposition;

  my $has_uv = $$services{UVCoating} and openprint::Estimating::UVCoating::signature_needs($Project, $sig_specs);
  my $trim_before_folding = 0;

  my $Folder = undef;
  my $Press = $Imposition->Press();
  my $output_format = $Press->specification('OutputFormat');
  my $I = $Imposition->copy();
  my @folding_impositions;

  # The idea is that we are either folding or DieCutting but not both
  if ($$services{DieCutting} and @{$$services{DieCutting}}) {
    my $diecutting_specs = openprint::service::get_specs_ref($Project, $$services{DieCutting}[0]);
    my @diecutting_impositions = openprint::Estimating::DieCutting::load_Impositions( $Imposition, $diecutting_specs, $form, $qty_index);
    my $diecutting_cuts = 0;
    if ( (defined $$specs{"OverrideFoldingCuts-$form-$qty_index"}) and ($$specs{"OverrideFoldingCuts-$form-$qty_index"} eq 'Y')) {
      $diecutting_cuts = $$specs{"FoldingCuts-$form-$qty_index"};
    } elsif (@diecutting_impositions) {
      $diecutting_cuts += @diecutting_impositions - 1;
      foreach my $diecutting_imposition ( @diecutting_impositions ) {
        $diecutting_cuts += $$diecutting_imposition{quantity}-1 if $$diecutting_imposition{quantity};
      } # end foreach
    } # end if
    if ( $diecutting_cuts ) {
      load_equipment($Project) if ! @PreFoldingEquipment;
      my @PreFoldEquipment = @PreFoldingEquipment;
      my %PreFoldEquipment = map { $$_{id} => $_ } @PreFoldEquipment;

      if (
        defined($$specs{"OverrideFoldingEquipment-$form-$qty_index"})
          and
        ( $$specs{"OverrideFoldingEquipment-$form-$qty_index"} eq 'Y' )
      ) {
        if ( !$PreFoldEquipment{$$specs{"FoldingEquipment-$form-$qty_index"}} ) {
          $results{alert} .= 'Overriden Equipment ('.$$specs{"OverrideFoldingEquipment-$form-$qty_index"}.') is not suitable for cutting before diecutting.<br/>';
          if ( DEBUG ) {
            foreach my $E ( @PreFoldEquipment ) {
              $openprint::log->error("Prediecut Equipment $$E{id} $$E{strid}");
            }
          }
        } # end if
        @PreFoldEquipment = ( new openprint::Equipment($$specs{"FoldingEquipment-$form-$qty_index"}) );
      } # end if
      foreach my $Equipment ( @PreFoldEquipment ) {
        my $liftDepth = $Equipment->specification('Maximum Lift Depth', $calliper);
        my $sheets = ceil( $$sig_specs{'txtQuantity'.$qty_index} / $$Imposition{imposition} );
        $sheets *= $$sig_specs{PageQuantity} if $$sig_specs{PageQuantity};
        if ( my $Spec = $Equipment->Specification('Cutting Overs') ) {
          my $overs = 0;
          if ( $$Spec{units} eq 'Sheets' ) {
            $overs = int($$Spec{value});
          } elsif ( $$Spec{units} eq 'percent' ) {
            $overs = int($sheets * $$Spec{value}/100);
          } else {
            $openprint::log->error("Invalid units on Cutting Overs $$Spec{units}");
          } # end if
          $results{overs} += $overs;
          $results{Breakdown} .= $sheets.'sheets + '.$$Spec{value}.$$Spec{units}.' = '.$overs.' total = '.($sheets+$overs).'<br/>';
          $sheets += $overs;
        } # end if
        my $piles = $liftDepth ? ceil( $sheets*$calliper/$liftDepth ) : $sheets;
        $results{Breakdown} .= '# of pre-diecutting cuts: ' . $diecutting_cuts . ' => ' .($diecutting_cuts * $sheets) . '<br/>';
        my %price;
        if ( $CuttingMakeReady ) {
          my %setup = $CuttingMakeReady->get_price(undef, $Equipment);
          if ( !%setup ) {
            $log->error('No Cutting Makeready for '.$$Equipment{strid});
          } else {
            if ($setup{units} and ($setup{units} eq 'per cut')) {
              %setup = $CuttingMakeReady->get_price($diecutting_cuts, $Equipment);
              $setup{Total} = $setup{Price} * $diecutting_cuts;
              $results{Breakdown} .= sprintf('Make Ready: $%1$.2f%2$s * %4$d cuts = $%3$.2f<br/>',
                @setup{'Price','units','Total'}, $diecutting_cuts);
            } else {
              $openprint::log->debug('unknown units on '.$$CuttingMakeReady{units}) if DEBUG;
              $results{Breakdown} .= sprintf('Make Ready: $%.2f<br/>', $setup{Price});
              $setup{Total} = $setup{Price};
            } # end if
            $price{MakeReady} = $setup{Total};
            $price{Total} += $setup{Total};
          } # end if has setup or not
        } # end if CuttingMakeReady

        if ( $$Paper{bladecleaning} and $BladeCleaning ) {
          my %cleaning = $BladeCleaning->get_price(undef, $Equipment);
          $results{Breakdown} .= sprintf('Blade Cleaning: $%.2f<br/>', $cleaning{Price});
          $price{BladeCleaning} = $cleaning{Price};
          $price{Total} += $cleaning{Price};
        } # end if

        my %ServicePrice = $CuttingService->get_price(undef, $Equipment);
        if ( $ServicePrice{units} eq 'per cut' ) {
          %ServicePrice = $CuttingService->get_price($sheets * $diecutting_cuts, $Equipment);
        } else {
          %ServicePrice = $CuttingService->get_price($sheets, $Equipment);
        } # end if
        if ( $ServicePrice{units} eq 'per inch' ) {
          $ServicePrice{Total} = ( $piles * $diecutting_cuts * $ServicePrice{Price} * $Imposition->image_height() );
          $results{Breakdown} .= sprintf(
            '%d pre-diecutting cuts on %d sheets in %d piles * %.2f inches: %.2f%s=$%.2f<br/>',
            $diecutting_cuts, $sheets, $piles, $Imposition->image_height(), @ServicePrice{'Price','units','Total'},
          );
        } else {
          $ServicePrice{Total} = $piles * $diecutting_cuts * $ServicePrice{Price};
          $results{Breakdown} .= sprintf(
            '%d pre-diecutting cuts on %d sheets in %d piles: %.2f%s=$%.2f<br/>',
            $diecutting_cuts, $sheets, $piles, @ServicePrice{'Price','units','Total'});

        } # end if
        $price{Total} += $ServicePrice{Total};
        if ( $PileHandling ) {
          my %pilehandlingprice = $PileHandling->get_price( $piles, $Equipment );
          if ( %pilehandlingprice ) {
            if ( $pilehandlingprice{units} eq 'per pile' ) {
              $pilehandlingprice{Total} = $pilehandlingprice{Price} * $piles;
              $price{Total} += $pilehandlingprice{Total};
              $results{Breakdown} .= sprintf('Pile handling: $%1$.2f%2$s * %4$d piles = $%3$.2f<br/>',
                @pilehandlingprice{'Price','units','Total'}, $piles );
            } else {
              $openprint::log->error("invalid units $pilehandlingprice{units} on $$PileHandling{name}");
              $results{alert} .= "invalid units $pilehandlingprice{units} on $$PileHandling{name} on $$Equipment{name}<br/>";
            } # end if
          } # end if
        } elsif ( DEBUG ) {
          $openprint::log->debug("No PileHandling");
        } # end PileHandling

        $results{Breakdown} .= sprintf( 'Pre-diecutting cutting total: $%.2f<br/>', $price{Total});

        if ( ( ! defined $results{FoldingPrice} ) or ( $price{Total} < $results{FoldingPrice} ) ) {
          $results{FoldingPrice} = $price{Total};
          $results{FoldingEquipment} = $Equipment;
        } # end if
      } # end foreach Equipmenet
    } else {
      $results{Breakdown} .= 'No pre-diecutting cuts:<br/>';
    } # end if diecutting_cuts
    $results{FoldingCuts} = $diecutting_cuts;
  } else {

    if ( $$services{Folding} and @{$$services{Folding}} ) {
      $folding_specs = openprint::service::get_specs_ref($Project, $$services{Folding}[0]) if ! $folding_specs;
      if ( $$folding_specs{"ddmEquipment-$form-$qty_index"} ) {
        $Folder = openprint::Equipment->find_one(id=>$$folding_specs{"ddmEquipment-$form-$qty_index"});
      } else {
        $openprint::log->debug('No folder in folding_specs') if DEBUG; 
      }
      if ( $$Imposition{Folds} ) {
        @folding_impositions = @{$$Imposition{Folds}};
      } else {
        @folding_impositions = openprint::Estimating::Folding::get_Folds( $folding_specs, $Imposition, $qty_index );
      } # end foreach fold_index
    } # end if

  $openprint::log->debug("Folding impos " . @folding_impositions  . ' eq ' . @my_equipment );

    if ( $stitching_specs and $stitching_imposition ) {
      if ( $$Imposition{image_orientation} == openprint::Imposition::Horizontal ) {
        if ( $stitching_imposition > $$Imposition{columns} ) {
          $openprint::log->debug("Adjusting stitching imposition to cols $$Imposition{columns} from $stitching_imposition") if DEBUG;
          $stitching_imposition = $$Imposition{columns};
        }
      } else {
        if ( $stitching_imposition > $$Imposition{rows} ) {
          $openprint::log->debug("Adjusting stitching imposition to rows $$Imposition{columns} from $stitching_imposition") if DEBUG;
          $stitching_imposition = $$Imposition{rows}
        }
      } # end if
    } # end if

  # Take care of cutting before folding
    if ( @folding_impositions and $Folder and ( $$Folder{id} != $$Press{id} ) ) {
      $openprint::log->debug('Folding impositions: '.@folding_impositions) if DEBUG;

      my $folding_cuts = 0;
      if (
          (defined $$specs{"OverrideFoldingCuts-$form-$qty_index"})
          and
          ($$specs{"OverrideFoldingCuts-$form-$qty_index"} eq 'Y')
         ) {
        $folding_cuts = $$specs{"FoldingCuts-$form-$qty_index"};
      } elsif (@folding_impositions) {
        if ( ( @folding_impositions == 1 ) 
            and ( $folding_impositions[0]{imposition} == 1 )
            and ( ! $stitching_imposition )

  # Why about the quanitty? Basically if it's 1out, we pre-trim.  Otherwise let the folder do it.  So if we have 2@1out, then we might as well pre-trim
  #and ( $folding_impositions[0]->quantity() == 1 )
            and ( (!$Folder) or ($$Folder{id} != $$Press{id}) )
           ) {
          $trim_before_folding = 1;
        } else {
          my $folder_type = $Folder->specification('Type') || '';
          if ( (@folding_impositions > 1) or ($folding_impositions[0]{quantity} > 1) ) {
            $openprint::log->debug('Folds: '.@folding_impositions) if DEBUG;
            # If we are stitching, final trim is done on stitcher, otherwise we might final trim before folding	
            if ( ! $stitching_imposition ) {
  # So according to Brendan, anyone doing the cutting would first make the 4 outer edge trims.  
              $folding_cuts += 4; # outside cuts
            }
            
            $folding_cuts += @folding_impositions - 1;
            foreach my $folding_imposition ( @folding_impositions ) {
              $folding_cuts += $$folding_imposition{quantity}-1 if $$folding_imposition{quantity};
              if ( $$sig_specs{'ddmBleedSize'.$qty_index} and ($$sig_specs{BleedTop} or $$sig_specs{BleedBottom} or $$sig_specs{BleedLef} or $$sig_specs{BleedBottom} ) ) {
                $folding_cuts += $$folding_imposition{quantity}-1 if $$folding_imposition{quantity};
              }
            } # end foreach
          } elsif (
              ($folding_impositions[0]{imposition} > $stitching_imposition)
              and
              ($folder_type eq 'Stitcher')
              ) {
            $folding_impositions[0]->display('Cutting impo before folding because the folder is a stitcher:');
            $folding_cuts += $folding_impositions[0]{columns}-1;
            $folding_cuts += $folding_impositions[0]{rows}-1;
          } # end if
        } # end if
      } # end if folding_impositions
$openprint::log->debug("Folding cuts: $folding_cuts") if DEBUG;
      if ( $folding_cuts ) {
        load_equipment($Project) if ! @PreFoldingEquipment;
        my @PreFoldEquipment = @PreFoldingEquipment;
        my %PreFoldEquipment = map { $$_{id} => $_ } @PreFoldEquipment;

        if (
            defined($$specs{"OverrideFoldingEquipment-$form-$qty_index"})
            and
            ( $$specs{"OverrideFoldingEquipment-$form-$qty_index"} eq 'Y' )
           ) {
          if ( !$PreFoldEquipment{$$specs{"FoldingEquipment-$form-$qty_index"}} ) {
            $results{alert} .= 'Overriden Equipment ('.$$specs{"OverrideFoldingEquipment-$form-$qty_index"}.') is not suitable for cutting before folding.<br/>';
            if ( DEBUG ) {
              foreach my $E ( @PreFoldEquipment ) {
                $openprint::log->error("Prefold Equipment $$E{id} $$E{strid}");
              }
            }
          } # end if
          @PreFoldEquipment = ( new openprint::Equipment($$specs{"FoldingEquipment-$form-$qty_index"}) );
        } # end if
        foreach my $Equipment ( @PreFoldEquipment ) {
          my %price = (
            overs => 0,
          );

          my $liftDepth = $Equipment->specification('Maximum Lift Depth', $calliper);
          my $sheets = ceil( $$sig_specs{'txtQuantity'.$qty_index} / $$I{imposition} );
          $sheets *= $$sig_specs{PageQuantity} if $$sig_specs{PageQuantity};
          if ( my $Spec = $Equipment->Specification('Cutting Overs') ) {
            my $overs = 0;
            if ( $$Spec{units} eq 'Sheets' ) {
              $overs = int($$Spec{value});
            } elsif ( $$Spec{units} eq 'percent' ) {
              $overs = int($sheets * $$Spec{value}/100);
            } else {
              $openprint::log->error("Invalid units on Cutting Overs $$Spec{units}");
            } # end if
            $price{overs} += $overs;
            $results{Breakdown} .= $sheets.'sheets + '.$$Spec{value}.$$Spec{units}.' = '.$overs.' total = '.($sheets+$overs).'<br/>';
            $sheets += $overs;
          } # end if
          my $piles = $liftDepth ? ceil( $sheets*$calliper/$liftDepth ) : $sheets;
          $results{Breakdown} .= '# of pre-folding cuts: ' . $folding_cuts . ' => ' .($folding_cuts * $sheets) . '<br/>';

          if ( $CuttingMakeReady ) {
            $$CuttingMakeReady{units} //= '';
            my %setup = $CuttingMakeReady->get_price(undef, $Equipment);
            if ( !%setup ) {
              $log->error('No Cutting Makeready for '.$$Equipment{strid});
            } else {
              if ($setup{units} and ($setup{units} eq 'per cut')) {
                %setup = $CuttingMakeReady->get_price($folding_cuts, $Equipment);
                $setup{Total} = $setup{Price} * $folding_cuts;
                $results{Breakdown} .= sprintf('Make Ready: $%1$.2f%2$s * %4$d cuts = $%3$.2f<br/>',
                    @setup{'Price','units','Total'}, $folding_cuts);
              } else {
                $openprint::log->debug('unknown units on '.$$CuttingMakeReady{name}) if DEBUG;
                $results{Breakdown} .= sprintf('Make Ready: $%.2f<br/>', $setup{Price});
                $setup{Total} = $setup{Price};
              } # end if
              $price{MakeReady} = $setup{Total};
              $price{Total} += $setup{Total};
            } # end if has setup or not
          } # end if CuttingMakeReady

          if ( $$Paper{bladecleaning} and $BladeCleaning ) {
            my %cleaning = $BladeCleaning->get_price(undef, $Equipment);
            $results{Breakdown} .= sprintf('Blade Cleaning: $%.2f<br/>', $cleaning{Price});
            $price{BladeCleaning} = $cleaning{Price};
            $price{Total} += $cleaning{Price};
          } # end if

          my %ServicePrice = $CuttingService->get_price(undef, $Equipment);
          if ( $ServicePrice{units} eq 'per cut' ) {
            %ServicePrice = $CuttingService->get_price($sheets * $folding_cuts, $Equipment);
          } else {
            %ServicePrice = $CuttingService->get_price($sheets, $Equipment);
          } # end if
          if ( $ServicePrice{units} eq 'per inch' ) {
            $ServicePrice{Total} = ( $piles * $folding_cuts * $ServicePrice{Price} * $I->image_height() );
            $results{Breakdown} .= sprintf(
                '%d pre-folding cuts on %d sheets in %d piles * %.2f inches: %.2f%s=$%.2f<br/>',
                $folding_cuts, $sheets, $piles, $I->image_height(), @ServicePrice{'Price','units','Total'},
                );
          } else {
            $ServicePrice{Total} = $piles * $folding_cuts * $ServicePrice{Price};
            $results{Breakdown} .= sprintf(
                '%d pre-folding cuts on %d sheets in %d piles: %.2f%s=$%.2f<br/>',
                $folding_cuts, $sheets, $piles, @ServicePrice{'Price','units','Total'});

          } # end if
          $price{Total} += $ServicePrice{Total};

          if ( $PileHandling ) {
            my %pilehandlingprice = $PileHandling->get_price( $piles, $Equipment );
            if ( %pilehandlingprice ) {
              if ( $pilehandlingprice{units} eq 'per pile' ) {
                $pilehandlingprice{Total} = $pilehandlingprice{Price} * $piles;
                $price{Total} += $pilehandlingprice{Total};
                $results{Breakdown} .= sprintf('Pile handling: $%1$.2f%2$s * %4$d piles = $%3$.2f<br/>',
                    @pilehandlingprice{'Price','units','Total'}, $piles );
              } else {
                $openprint::log->error("invalid units $pilehandlingprice{units} on $$PileHandling{name}");
                $results{alert} .= "invalid units $pilehandlingprice{units} on $$PileHandling{name} on $$Equipment{name}<br/>";
              } # end if
            } # end if
          } elsif ( DEBUG ) {
            $openprint::log->debug('No PileHandling');
          } # end PileHandling

          $results{Breakdown} .= sprintf( 'Pre-folding cutting total: $%.2f<br/>', $price{Total});

          if ( ( ! defined $results{FoldingPrice} ) or ( $price{Total} < $results{FoldingPrice} ) ) {
            $results{overs} += $price{overs};
            $results{FoldingPrice} = $price{Total};
            $results{FoldingEquipment} = $Equipment;
          } # end if
        } # end foreach Equipmenet
      } else {
        $results{Breakdown} .= 'No pre-folding cuts:<br/>';
      } # end if folding_cuts
      $results{FoldingCuts} = $folding_cuts;
    } # end if @folding
  } # end if Folding/DieCutting

  #The Paper might be a roll, and the output of printing might still be a roll.
  my %bestPrice;
  EQUIPMENT: foreach my $Equipment ( @my_equipment ) {
    next if ! $$Equipment{id};
    $results{Breakdown} .= 'Equipment ' . $$Equipment{name} .':';
    if ( $$services{NoOfflineBindery} and ( $$sig_specs{'ddmPress'.$qty_index} ne $$Equipment{strid} ) ) {
      $results{Breakdown} .= "No Offline bindery and not printing on $$Equipment{name}.<br/>";
      next;
    } # end if
    my %price = (
      Equipment => $Equipment,
      overs => 0,
      total => 0,
      mprice=> 0,
    );
    my $cutting_capable = $Equipment->specification('Cutting Capable');

    if ( $cutting_capable eq 'When Folding' ) {
      if ( ! $folding_specs ) {
        $results{Breakdown} .= 'Not folding<br/>';
        next;
      } # end if
      if ( $trim_before_folding ) {
        $results{Breakdown} .= 'is 1out, so trim before folding.<br/>';
        next;
      } # end 

      if ( ! $$folding_specs{"ddmEquipment-$form-$qty_index"} ) {
        $results{Breakdown} .= "Unknown folding equipment for form $form qty $qty_index<br/>";
        next;
      } elsif( $$folding_specs{"ddmEquipment-$form-$qty_index"} ne $$Equipment{id} ) {
        $results{Breakdown} .= 'Not folding on ' . $$Equipment{strid}. ' Folder is ' . ( $Folder ? $$Folder{strid} : '' ). '<br/>';
        next;
      } # end if
    } elsif ( ( $cutting_capable eq 'When Printing' ) and ( $$sig_specs{'ddmPress'.$qty_index} ne $$Equipment{strid} ) ) {
      $results{Breakdown} .= 'Not printing on '.$$Equipment{strid}.'<br/>';
      next;
    } elsif ( $cutting_capable eq 'When Stitching' ) {
      if ( ! $$stitching_specs{'ddmEquipment'.$qty_index} ) {
        $results{Breakdown} .= 'Stitching not calculated yet.<br/>';
        next;
      } # end if
      if ( $$stitching_specs{'ddmEquipment'.$qty_index} != $$Equipment{id} ) {
        $results{Breakdown} .= 'Not stitching on ' . $$Equipment{strid} . '<br/>';
        next;
      } # end if
      if ( keys %pretrim_sides ) {
        $results{Breakdown} .= 'Needs pre-trim before Stitching, cant use Stitcher for cutting<br/>';
        next;
      } # end if
    } # end if


    # I don't know what this is about.
    #my ( $sheet_width, $sheet_height ) = ( $Paper->width(), $Paper->height() );
    #if ( $output_format and ( $output_format eq 'Roll' ) ) {
    #if ( ( $_ = $Equipment->specification('Maximum Sheet Width') ) and ( $sheet_width > $_ ) ) {
    #$results{Breakdown} .= 'Doesnt fit.<br/>';
    #next;
    #} # end if
    ## Adjust imposition to account for cutting to maximum size
    #$sheet_height = $Equipment->specification('Maximum Sheet Length');
    #if ( ! $sheet_height ) {
    #$I->rows( $sheets );
    #$I->dutch_rows( $sheets ) if $$I{dutch_rows};
    #$sheet_height = $I->layout_height();
    #$sheets = 1;
    #} else {
    #$I->rows( $I->rows() * int($sheet_height / $I->layout_height()) );
    #$I->dutch_rows( $I->dutch_rows() * int($sheet_height / $I->layout_height()) ) if $I->dutch_rows();
    #$sheets = ceil( $sheets / $I->rows() );
    #} # end if
    #$results{Breakdown} .= $I->to_string() . '<br/>';
    #} elsif ( my $reason = $Equipment->fits( $sheet_width, $sheet_height ) ) {
    #$results{Breakdown} .= $reason . '<br/>';
    #next;
    #} # end if
    ##$results{Breakdown} .= '<br/>';

    my $liftDepth = $Equipment->specification('Maximum Lift Depth with UVCoating') if $has_uv;
    $liftDepth = $Equipment->specification('Maximum Lift Depth', $calliper) if ! $liftDepth;
    $liftDepth = 0 if ! defined $liftDepth;
    $results{Breakdown} .= "(Lift: $liftDepth)<br/>";
    # calculate cuts
    my $vertical_cuts = 0;
    my $horizontal_cuts = 0;
    my $dutch_vertical_cuts = 0;
    my $dutch_horizontal_cuts = 0;

    # Final cutting
    if ($$services{DieCutting}) {
      $results{Breakdown} .= 'Signature is being Die Cut. Assuming further cutting not needed<br/>';
      $$specs{"txtCalculatedCuts-$form-$qty_index"} = '';
      $$specs{"txtVerticalCuts-$form-$qty_index"} = '';
      $$specs{"txtHorizontalCuts-$form-$qty_index"} = '';
      $$specs{"txtDVerticalCuts-$form-$qty_index"} = '';
      $$specs{"txtDHorizontalCuts-$form-$qty_index"} = '';
    } else {

      if ( 
        (defined $$specs{'chkOverrideCalculatedCuts-'.$form.'-'.$qty_index})
          and
        ( $$specs{'chkOverrideCalculatedCuts-'.$form.'-'.$qty_index} eq 'Y' )
      ) {
        $vertical_cuts = int($$specs{"txtVerticalCuts-$form-$qty_index"}) if $$specs{"txtVerticalCuts-$form-$qty_index"};
        $horizontal_cuts = int($$specs{"txtHorizontalCuts-$form-$qty_index"}) if $$specs{"txtHorizontalCuts-$form-$qty_index"};
        $dutch_vertical_cuts = int($$specs{"txtDVerticalCuts-$form-$qty_index"}) if $$specs{"txtDVerticalCuts-$form-$qty_index"};
        $dutch_horizontal_cuts = int($$specs{"txtDHorizontalCuts-$form-$qty_index"}) if $$specs{"txtDHorizontalCuts-$form-$qty_index"};
      } else {
  # Regular book signatures will be trimmed by the stitcher, so we only need 1 cut per imposition
  # Most stitchers do 3knife trim, but some do not. Most need a Head Trim, some need Head & Foot
  # interior vertical cuts = $sig_specs{hdnImpositionColumns}-1
        if ( $$sig_specs{txtSignatureType} and ($$sig_specs{txtSignatureType} ne 'Pad Pages') ) {

  # but if we are cutting into smaller signatures, then we need more cutting
  #$openprint::log->debug("Stitching $stitching_imposition out printing $$sig_specs{'txtImposition'.$qty_index}out") if DEBUG;
  #$openprint::log->debug("have signaturetype $$sig_specs{txtSignatureType} ");
  #$openprint::log->debug("What is folder?: ($Folder)" . ($Folder ? join(',', map { $_ . ' => ' . $$Folder{$_} } keys %{$Folder} ) : '' ) );
          if ( ($cutting_capable ne 'When Stitching') and $I->pages() and ! ( $folding_specs and $Folder and $Folder->specification('Cutting Capable') ) ) {
            $openprint::log->debug("Cutting because not folding or can't cut on folder $folding_specs " . ( $Folder ? $$Folder{strid} : '' ) ) if DEBUG;
  $I->display( $I->page_columns() . ' x ' . $I->page_rows() );
  # Have to cut the pages out
            $vertical_cuts += int ( ($I->page_columns()-1)*$$I{columns}*2 ) + 2;
            $horizontal_cuts += int( ($I->page_rows()-1)*$$I{rows} * 2 ) + 2;

          } elsif ( $stitching_imposition ) {
  #$openprint::log->debug("have stitching imposition $stitching_imposition");
            if ( ! @folding_impositions ) {
  # Are stitching but don't have folded impositions... 
              $vertical_cuts += int ($$I{columns} / $stitching_imposition)-1;
              $horizontal_cuts += int ($$I{rows} / $stitching_imposition)-1; 
            } elsif ( $trim_before_folding ) {
            } elsif ( $cutting_capable eq 'When Stitching' ) {
  # trimming either happened on the folder or we have to do it.
  # Going to fold it first.
  # assumptions: 
              foreach my $folding_imposition ( @folding_impositions ) {
                $folding_imposition->display('getting stitching cuts from') if DEBUG;
                if ( $$I{image_orientation} == openprint::Imposition::Vertical ) {
                  if ( $$folding_imposition{columns} > 1 ) {
                    $folding_imposition->display('Can\'t do that on the stitcher');
                    next EQUIPMENT;
                  }
                  $vertical_cuts += 1; # Face trim
                  $horizontal_cuts += 1 + $$folding_imposition{rows};
                  if ( $$sig_specs{'ddmBleedSize'.$qty_index} and  
                      ( $$I{image_orientation} == openprint::Imposition::Vertical ) and ( $$sig_specs{BleedTop} or $$sig_specs{BleedBottom} ) 
                     ) {
                    $horizontal_cuts += $$folding_imposition{rows}-1;
                  } # end if
                } elsif ( $$I{image_orientation} == openprint::Imposition::Horizontal ) {
                  if ( $$folding_imposition{rows} > 1 ) {
                    $folding_imposition->display('Can\'t do that on the stitcher');
                    next EQUIPMENT;
                  }
                  $horizontal_cuts += 1; # Face trim
                  $vertical_cuts += 1 + $$folding_imposition{columns};

                  if ( $$sig_specs{'ddmBleedSize'.$qty_index} and  
                      ( $$I{image_orientation} == openprint::Imposition::Horizontal ) and ( $$sig_specs{BleedTop} or $$sig_specs{BleedBottom} ) 
                     ) {
                    $vertical_cuts += $$folding_imposition{columns}-1;
                  } # end if
                } # end if
              } # end foreach
            } # end if
          } elsif ( $$printing_specs{rdbTemplateType} and ($$printing_specs{rdbTemplateType} eq 'PlasticCoil') ) {
  # This is special... something about if it's plasticCoil... you have to cut it into 8's...

            if ( $I->pages() > 8 ) {
              if ( @folding_impositions == 1 and $folding_impositions[0]->quantity() <= 1 and $folding_impositions[0]{imposition} == 1 ) {
  # According to Brendan, will trim it first.
                $vertical_cuts += 2;
                $horizontal_cuts += 2;
              } else {
  # Going to fold it first.
                foreach my $folding_imposition ( @folding_impositions ) {
                  my $columns =  $$folding_imposition{columns} ? $$I{columns} / $$folding_imposition{columns} : $$I{columns};
                  $vertical_cuts += 1+$columns;# = 2+$$I{columns}-1
                    my $rows = $$folding_imposition{rows} ?$$folding_imposition{rows} : $$I{rows};
                  $horizontal_cuts += 1 + $rows;#2 + $$I{rows}-1
                    if ( $$sig_specs{'ddmBleedSize'.$qty_index} and ( 
                          ( $$I{image_orientation} == openprint::Imposition::Horizontal and ( $$sig_specs{BleedLeft} or $$sig_specs{BleedRight} ) ) or
                          ( $$I{image_orientation} == openprint::Imposition::Vertical and ( $$sig_specs{BleedTop} or $$sig_specs{BleedBottom} ) ) )
                       ) {
                      $horizontal_cuts += $rows-1;
                    } # end if
                  if ( 
                      ( $$I{image_orientation} == openprint::Imposition::Vertical and ( $$sig_specs{BleedLeft} or $$sig_specs{BleedRight} ) ) or
                      ( $$I{image_orientation} == openprint::Imposition::Horizontal and ( $$sig_specs{BleedTop} or $$sig_specs{BleedBottom} ) )
                     ) {
                    $vertical_cuts += $columns-1;
                  } # end if
                } # end foreach
              } # end if
            } else {
              $vertical_cuts += int ( ($I->page_columns()-1)* (($I->columns()-1)*2) ) + 2;
            } # end if
          } else {
            $vertical_cuts += $$I{columns}-1;
            $horizontal_cuts += $$I{rows}-1;
  #$openprint::log->debug("vcuts: $vertical_cuts hcuts: $horizontal_cuts ");
          } # end if
          foreach my $side ( keys %pretrim_sides ) {
  # What I am thinking here, is that if it was 2 out, the in between head trim would already have been done, so there is just 1 to do
            if ( $$I{image_orientation} == openprint::Imposition::Vertical ) {
              $horizontal_cuts += 1;
            } else {
              $vertical_cuts += 1;
            } # end if
          } # end foreach pre-trimmed sides
        } elsif ( @folding_impositions >= 1 and $folding_impositions[0]{imposition} > 1 and ( $Folder and $Folder->specification('Cutting Capable') ) ) {
          $openprint::log->debug('Cutting onfolder') if DEBUG;
  # Splitting the folded products is done on the folder for free
  #if ( ( $$folding_imposition{columns} > 1 ) and ( $$folding_imposition{columns} < $$I{columns} ) ) {
  #$vertical_cuts += ($$I{columns} / $$folding_imposition{columns})-1;
  #} # end if
        } else {
          $openprint::log->debug('Not a book') if DEBUG;
          my $columns =  $$I{columns};
          $vertical_cuts += 1+$columns;# = 2+$$I{columns}-1
            if (
                ( $$I{image_orientation} == openprint::Imposition::Vertical and ( $$sig_specs{BleedLeft} or $$sig_specs{BleedRight} ) ) or
                ( $$I{image_orientation} == openprint::Imposition::Horizontal and ( $$sig_specs{BleedTop} or $$sig_specs{BleedBottom} ) )
               ) {
              $vertical_cuts += $columns-1;
            } # end if
          my $rows = $$I{rows};
          $horizontal_cuts += 1 + $rows;#2 + $$I{rows}-1
          if ( $$sig_specs{'ddmBleedSize'.$qty_index} and ( 
                ( $$I{image_orientation} == openprint::Imposition::Horizontal and ( $$sig_specs{BleedLeft} or $$sig_specs{BleedRight} ) ) or
                ( $$I{image_orientation} == openprint::Imposition::Vertical and ( $$sig_specs{BleedTop} or $$sig_specs{BleedBottom} ) ) )
             ) {
            $horizontal_cuts += $rows-1;
          } # end if
        } # end if

  # Dutch cuts don't happen on books
        if ( ( ! $$sig_specs{txtSignatureType} ) and ! @folding_impositions ) {
  #$I->display();
  # Now consider Dutch cuts
          if ( $$I{dutch_columns} and $$I{dutch_rows} ) {
            $dutch_vertical_cuts += 1 + $$I{dutch_columns};
            $dutch_horizontal_cuts += $$I{dutch_rows}; # +1 - 1
              if ( ( $$sig_specs{BleedTop} and $$sig_specs{BleedBottom} ) or ($$sig_specs{BleedLeft} and $$sig_specs{BleedRight} ) ) {
                $dutch_horizontal_cuts += 1;
              } # end if
            if ( 
                ( $$I{image_orientation} == openprint::Imposition::Vertical and ( $$sig_specs{BleedTop} or $$sig_specs{BleedBottom} ) ) or
                ( $$I{image_orientation} == openprint::Imposition::Horizontal and ( $$sig_specs{BleedLeft} or $$sig_specs{BleedRight} ) )
               ) {
              $dutch_vertical_cuts += $$I{dutch_columns}-1;
            } # end if
            if ( 
                ( $$I{image_orientation} == openprint::Imposition::Horizontal and ( $$sig_specs{BleedTop} or $$sig_specs{BleedBottom} ) ) or
                ( $$I{image_orientation} == openprint::Imposition::Vertical and ( $$sig_specs{BleedLeft} or $$sig_specs{BleedRight} ) )
               ) {
              $dutch_horizontal_cuts += $$I{dutch_rows}-1;
            } # end if
          } # end if dutch imposition
        } # end if exists signaturetype

        $$specs{"txtVerticalCuts-$form-$qty_index"} = $vertical_cuts ? $vertical_cuts : '';
        $$specs{"txtHorizontalCuts-$form-$qty_index"} = $horizontal_cuts ? $horizontal_cuts : '';
        $$specs{"txtDVerticalCuts-$form-$qty_index"} = $dutch_vertical_cuts;
        $$specs{"txtDHorizontalCuts-$form-$qty_index"} = $dutch_horizontal_cuts;
      }
      $$specs{"txtCalculatedCuts-$form-$qty_index"} = $vertical_cuts + $horizontal_cuts + $dutch_vertical_cuts + $dutch_horizontal_cuts;
    } #end if DieCutting

    my $cuts = $$specs{"txtCalculatedCuts-$form-$qty_index"};
    #$log->debug("Cuts: $cuts");

    if ((!$$specs{"txtAdditionalCuts$form"} ) and $$sig_specs{txtPressSheetComboItems}) {
      $$specs{"txtAdditionalCuts$form"} = $$sig_specs{txtPressSheetComboItems};
    } # end if

    if ($cuts or $$specs{"txtAdditionalCuts$form"}) {
      my %ServicePrice = $CuttingService->get_price(undef, $Equipment);
      my $sheets = ceil( $$sig_specs{'txtQuantity'.$qty_index} / $$I{imposition} );
      $sheets *= $$sig_specs{PageQuantity} if $$sig_specs{PageQuantity};
      $sheets *= $$sig_specs{'PageQuantity'.$qty_index} if ($$sig_specs{txtSignatureType} and ($$sig_specs{txtSignatureType} eq 'Pad Pages')) and $$sig_specs{'PageQuantity'.$qty_index};

      if ( my $Spec = $Equipment->Specification('Cutting Overs') ) {
        my $overs = 0;
        if ( $$Spec{units} eq 'Sheets' ) {
          $overs = int($$Spec{value});
        } elsif ( $$Spec{units} eq 'percent' ) {
          $overs = int($sheets * $$Spec{value}/100);
        } else {
          $openprint::log->error("Invalid units on Cutting Overs $$Spec{units}");
        } # end if
        $results{Breakdown} .= $sheets.'sheets + '.$$Spec{value}.$$Spec{units}.' = '.$overs.' total = '.($sheets+$overs).'<br/>';
        $sheets += $overs;
        $price{overs} += $overs;
      } # end if

      if ( $cuts ) {
        if ( $CuttingMakeReady ) {
          my %setup = $CuttingMakeReady->get_price(undef, $Equipment);
          if ( !%setup ) {
            $log->error("No Cutting Makeready for $$Equipment{strid}");
          } else {
            if ($setup{units} and ($setup{units} eq 'per cut')) {
              %setup = $CuttingMakeReady->get_price( $cuts, $Equipment );
              $setup{Total} = $setup{Price} * $cuts;
              $results{Breakdown} .= sprintf('Make Ready: $%1$.2f%2$s * %4$d cuts = $%3$.2f<br/>',
                @setup{'Price','units','Total'}, $cuts );
              $price{total} += $setup{Total};
            } else {
              $openprint::log->debug('unknown units on '.$CuttingMakeReady->name()) if DEBUG;
              $results{Breakdown} .= sprintf('Make Ready: $%.2f<br/>', $setup{Price} );
              $price{total} += $setup{Price};
            } # end if
          } # end if has setup or not
        } # end if

        if ( $$Paper{bladecleaning} and $BladeCleaning ) {
          my %cleaning = $BladeCleaning->get_price(undef, $Equipment);
          $results{Breakdown} .= sprintf('Blade Cleaning: $%.2f<br/>', $cleaning{Price});
          $price{total} += $cleaning{Price};
          $price{mprice} += $cleaning{Price};
        } # end if

        if ( %ServicePrice ) {
          if ( $ServicePrice{units} eq 'per cut' ) {
            %ServicePrice = $CuttingService->get_price($sheets * $cuts, $Equipment);
          } else {
            %ServicePrice = $CuttingService->get_price($sheets, $Equipment);
          } # end if
        } # end if

        my $piles = $liftDepth ? ceil( $sheets*$calliper/$liftDepth ) : $sheets;
        $results{Breakdown} .= '# of cuts: ' . $cuts . ' => ' .($cuts * $sheets) . '<br/>';

        if ( %ServicePrice ) {
          my $price;
          if ( $vertical_cuts > $horizontal_cuts ) {
            if ( $ServicePrice{units} eq 'per inch' ) {
              $price = $piles * $vertical_cuts *$ServicePrice{Price} * $$I{image_height};
              $results{Breakdown} .= sprintf('%d Vertical cuts on %d sheets in %d piles * %.2f inches: %.2f%s=$%.2f<br/>',
                $vertical_cuts, $sheets, $piles, $$I{image_height}, @ServicePrice{'Price','units'}, $price );
            } elsif ( $ServicePrice{units} eq 'per m' ) {
              $price = $piles * $vertical_cuts * $ServicePrice{Price} * ( $sheets/1000 );
              $results{Breakdown} .= sprintf('%d Vertical cuts on %d sheets in %d piles: %.2f%s=$%.2f<br/>',
                $vertical_cuts, $sheets, $piles, @ServicePrice{'Price','units'}, $price );
            } else {
              $price = ( $piles * $vertical_cuts * $ServicePrice{Price} );
              $results{Breakdown} .= sprintf('%d Vertical cuts on %d sheets in %d piles: %.2f%s=$%.2f<br/>',
                $vertical_cuts, $sheets, $piles, @ServicePrice{'Price','units'}, $price );
            } # end if
            $price{total} += $price;
            if ( (!$config{Dumb_Cutting}) or ( $config{Dumb_Cutting} ne 'Y' ) ) {
              $sheets *= $$I{columns};
              $piles = $liftDepth ? ceil( $sheets*$calliper/$liftDepth ) : $sheets;
            } # end if
            if ( $ServicePrice{units} eq 'per inch' ) {
              $price = ( $piles * $horizontal_cuts *$ServicePrice{Price} * $$I{image_width} );
              $results{Breakdown} .= sprintf('%d Horizontal cuts on %d sheets in %d piles * %.2f inches: %.2f%s=$%.2f<br/>',
                $horizontal_cuts, $sheets, $piles, $$I{image_width}, @ServicePrice{'Price','units'}, $price );
            } elsif ( $ServicePrice{units} eq 'per m' ) {
              $price = $piles * $horizontal_cuts * $ServicePrice{Price} * ( $sheets/1000 );
              $results{Breakdown} .= sprintf('%d Horizontal cuts on %d sheets in %d piles: %.2f%s=$%.2f<br/>',
                $horizontal_cuts, $sheets, $piles, @ServicePrice{'Price','units'}, $price );
            } else {
              $price = $piles * $horizontal_cuts * $ServicePrice{Price};
              $results{Breakdown} .= sprintf('%d Horizontal cuts on %d sheets in %d piles: %.2f%s=$%.2f<br/>',
                $horizontal_cuts, $sheets, $piles, @ServicePrice{'Price','units'}, $price );
            } # end if
            $price{total} += $price;
          } else {
            if ( $ServicePrice{units} eq 'per inch' ) {
              $price = ( $piles * $horizontal_cuts *$ServicePrice{Price} * $$I{image_width} );
              $results{Breakdown} .= sprintf('%d Horizontal cuts on %d sheets in %d piles * %.2f inches: %.2f%s=$%.2f<br/>',
                $horizontal_cuts, $sheets, $piles, $$I{image_width}, @ServicePrice{'Price','units'}, $price );
            } elsif ( $ServicePrice{units} eq 'per m' ) {
              $price = ( $piles * $horizontal_cuts * $ServicePrice{Price} * ($sheets/1000) );
              $results{Breakdown} .= sprintf('%d Horizontal cuts on %d sheets in %d piles: %.2f%s=$%.2f<br/>',
                $horizontal_cuts, $sheets, $piles, @ServicePrice{'Price','units'}, $price );
            } else {
              $price = ( $piles * $horizontal_cuts * $ServicePrice{Price} );
              $results{Breakdown} .= sprintf('%d Horizontal cuts on %d sheets in %d piles: %.2f%s=$%.2f<br/>',
                $horizontal_cuts, $sheets, $piles, @ServicePrice{'Price','units'}, $price );
            }
            $price{total} += $price;
            if ( (!$config{Dumb_Cutting}) or ( $config{Dumb_Cutting} ne 'Y' ) ) {
              $sheets *= $$I{rows};
              $piles = $liftDepth ? ceil( $sheets*$calliper/$liftDepth ) : $sheets;
            } # end if
            if ( $ServicePrice{units} eq 'per inch' ) {
              $price = ( $piles * $vertical_cuts *$ServicePrice{Price} * $$I{image_height} );
              $results{Breakdown} .= sprintf('%d Vertical cuts on %d sheets in %d piles * %.2f inches: $%.2f<br/>',
                $vertical_cuts, $sheets, $piles, $$I{image_height}, $price );
            } elsif ( $ServicePrice{units} eq 'per m' ) {
              $price = ( $piles * $vertical_cuts * $ServicePrice{Price} * ($sheets/1000) );
              $results{Breakdown} .= sprintf('%d Vertical cuts on %d sheets in %d piles: $%.2f%s=$%.2f<br/>',
                $vertical_cuts, $sheets, $piles, @ServicePrice{'Price','units'}, $price );
            } else {
              $price = ( $piles * $vertical_cuts * $ServicePrice{Price} );
              $results{Breakdown} .= sprintf('%d Vertical cuts on %d sheets in %d piles: $%.2f%s=$%.2f<br/>',
                $vertical_cuts, $sheets, $piles, @ServicePrice{'Price','units'}, $price );
            }
            $price{total} += $price;
          } # end if
        } # end if ServicePrice

        if ( $PileHandling ) {
          my %pilehandlingprice = $PileHandling->get_price( $piles, $Equipment );
          if ( %pilehandlingprice ) {
            if ( $pilehandlingprice{units} eq 'per pile' ) {
              $pilehandlingprice{Total} = $pilehandlingprice{Price} * $piles;
              $price{total} += $pilehandlingprice{Total};
              $results{Breakdown} .= sprintf('Pile handling: $%1$.2f%2$s * %4$d piles = $%3$.2f<br/>',
                @pilehandlingprice{'Price','units','Total'}, $piles );
            } else {
              $openprint::log->error("invalid units $pilehandlingprice{units} on $$PileHandling{name}");
              $results{alert} .= "invalid units $pilehandlingprice{units} on $$PileHandling{name} on $$Equipment{name}<br/>";
            } # end if
          } # end if
        } elsif ( DEBUG ) {
          $openprint::log->debug('No PileHandling');
        } # end PileHandling

        if ( $dutch_vertical_cuts or $dutch_horizontal_cuts ) {
          $results{Breakdown} .= 'Dutch Cuts:<br/>';

          $sheets = ceil( $$sig_specs{'txtQuantity'.$qty_index} / $$I{imposition} );
          $sheets *= $$sig_specs{PageQuantity} if $$sig_specs{PageQuantity};
          $piles = $liftDepth ? ceil( $sheets*$calliper/$liftDepth ) : $sheets;

          my $price = 0;
          if ( $dutch_vertical_cuts > $dutch_horizontal_cuts ) {
            if ( $ServicePrice{units} eq 'per inch' ) {
              $price = ( $piles * $dutch_vertical_cuts * $ServicePrice{Price} * $I->image_width() );
              $results{Breakdown} .= sprintf('%d Vertical cuts on %d sheets in %d piles * %.2f inches: %.2f%s=$%.2f<br/>',
                $dutch_vertical_cuts, $sheets, $piles, $I->image_width(), @ServicePrice{'Price','units'}, $price );
            } else {
              $price = ( $piles * $dutch_vertical_cuts * $ServicePrice{Price} );
              $results{Breakdown} .= sprintf('%d Vertical cuts on %d sheets in %d piles: %.2f%s=$%.2f<br/>',
                $dutch_vertical_cuts, $sheets, $piles, @ServicePrice{'Price','units'}, $price );
            } # end if
            $price{total} += $price;
            if ( (!$config{Dumb_Cutting}) or ( $config{Dumb_Cutting} ne 'Y' ) ) {
              $sheets *= $$I{dutch_columns};
              $piles = $liftDepth ? ceil( $sheets*$calliper/$liftDepth ) : $sheets;
            } # end if
            if ( $ServicePrice{units} eq 'per inch' ) {
              $price = ( $piles * $dutch_horizontal_cuts * $ServicePrice{Price} * $I->image_height() );
              $results{Breakdown} .= sprintf('%d Horizontal cuts on %d sheets in %d piles * %.2f inches: %.2f%s=$%.2f<br/>',
                $dutch_horizontal_cuts, $sheets, $piles, $I->image_height(), @ServicePrice{'Price','units'}, $price );
            } else {
              $price = ( $piles * $dutch_horizontal_cuts * $ServicePrice{Price} );
              $results{Breakdown} .= sprintf('%d Horizontal cuts on %d sheets in %d piles: %.2f%s=$%.2f<br/>',
                $dutch_horizontal_cuts, $sheets, $piles, @ServicePrice{'Price','units'}, $price );
            } # end if
            $price{total} += $price;
          } else {
            if ( $ServicePrice{units} eq 'per inch' ) {
              $price = ( $piles * $dutch_horizontal_cuts * $ServicePrice{Price} * $I->image_height() );
              $results{Breakdown} .= sprintf('%d Horizontal cuts on %d sheets in %d piles * %.2f inches: %.2f%s=$%.2f<br/>',
                $dutch_horizontal_cuts, $sheets, $piles, $I->image_height(), @ServicePrice{'Price','units'}, $price );
            } else {
              $price = ( $piles * $dutch_horizontal_cuts * $ServicePrice{Price} );
              $results{Breakdown} .= sprintf('%d Horizontal cuts on %d sheets in %d piles: $%.2f<br/>',
                $dutch_horizontal_cuts, $sheets, $piles, $price );
            } # end if
            $price{total} += $price;
            if ( (!$config{Dumb_Cutting}) or ( $config{Dumb_Cutting} ne 'Y' ) ) {
              $sheets *= $$I{dutch_rows};
              $piles = $liftDepth ? ceil( $sheets*$calliper/$liftDepth ) : $sheets;
            } # end if
            if ( $ServicePrice{units} eq 'per inch' ) {
              $price = ( $piles * $dutch_vertical_cuts * $ServicePrice{Price} * $I->image_width() );
              $results{Breakdown} .= sprintf('%d Vertical cuts on %d sheets in %d piles * %.2f inches: %.2f%s=%.2f<br/>',
                $dutch_vertical_cuts, $sheets, $piles, $I->image_width(), @ServicePrice{'Price','units'}, $price );
            } else {
              $price = ( $piles * $dutch_vertical_cuts * $ServicePrice{Price} );
              $results{Breakdown} .= sprintf('%d Vertical cuts on %d sheets in %d piles: %.2f%s=%.2f<br/>',
                $dutch_vertical_cuts, $sheets, $piles, @ServicePrice{'Price','units'}, $price );
            } # end if
            $price{total} += $price;
          } # end if

          if ( $PileHandling ) {
            my %pilehandlingprice = $PileHandling->get_price( $piles, $Equipment );
            if ( %pilehandlingprice ) {
              if ( $pilehandlingprice{units} eq 'per pile' ) {
                $pilehandlingprice{Total} = $pilehandlingprice{Price} * $piles;
                $price{total} += $pilehandlingprice{Total};
                $results{Breakdown} .= sprintf('Pile handling: $%1$.2f%2$s * %4$d piles = $%3$.2f<br/>',
                  @pilehandlingprice{'Price','units','Total'}, $piles );
              } else {
                $openprint::log->error("invalid units $pilehandlingprice{units} on $$PileHandling{name}");
                $results{alert} .= "invalid units $pilehandlingprice{units} on $$PileHandling{name}<br/>";
              } # end if
            } # end if
          } elsif ( DEBUG ) {
            $openprint::log->debug('No PileHandling');
          } # end PileHandling

        } # end if dutch
      } # end if ( $cuts ) {


      if ( $$specs{"txtAdditionalCuts$form"}) {
        my $type = $Equipment->specification('Type');
        if ($type and ($type eq 'Folder')) {
          # Folders can only do splitting, not proper cutting
          $openprint::log->debug("Skipping $$Equipment{strid} because of additional folds");
          next;
        }
        $sheets = ceil( $$sig_specs{'txtQuantity'.$qty_index} / $$I{imposition} );
        my $piles = $liftDepth ? ceil( $sheets*$calliper/$liftDepth ) : $sheets;
        my $price = ( $piles * $$specs{"txtAdditionalCuts$form"} * $ServicePrice{Price} );
        $results{Breakdown} .= 'Additional cuts: ';
        $results{Breakdown} .= sprintf('%d cuts on %d sheets: $%.2f<br/>', $$specs{"txtAdditionalCuts$form"}, $sheets, $price );
        $price{total} += $price;
      } # end if additional cuts
    } # end nif cuts or additional cuts

    $price{mprice} = $price{total};


    $results{Breakdown} .= sprintf('Cutting Total on %s: $%.2f<br/>', $$Equipment{strid}, $price{total});
    if ( !%bestPrice or ( $bestPrice{total} > $price{total} ) ) {
      %bestPrice = %price;
    } # end if
  } # end for each equipment

  if ( 0 and $stitching_specs ) {
    # Need final trim?
    my @remaining_sides = sets::exclude( [ keys %pretrim_sides ], [ 'Head', 'Foot', 'Face' ] );
    $log->debug("Final trim @remaining_sides") if DEBUG;
    if ( @remaining_sides ) {

    }	
  } # end if

  $results{Status}	= %bestPrice ? 'calculated' : 'uncalculated';
  $results{Price}		= $bestPrice{total};
  $results{overs} += $bestPrice{overs};
  $results{MPrice}	= ($bestPrice{mprice}/$$specs{'txtQuantity'.$qty_index})*1000;
  $results{Equipment}	= $bestPrice{Equipment};
  return %results;
} # end sub signature_calc

sub calc {
  my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

  $$specs{Status} = 'calculated';
  $$specs{alert} = '';

  if ( ! $$specs{txtNameQuantity} ) {
    $$specs{txtNameQuantity} = 1;
  } # end if

  my $Project = new openprint::Project( $project_index );
  my $services = $Project->services();

  my $fold_specs = openprint::service::get_specs_ref( $Project, $$services{Folding}[0] ) if $$services{Folding} and @{$$services{Folding}};
  my $calc_hash = {};
	init($Project);

  my @signatures = $Project->signatures({sort=>1});
  if ( ! @signatures ) {
    $openprint::log->error('No signatures');
  } # end if

  foreach my $qty_index ( $Project->quantity_indexes() ) {
    $$specs{'txtQuantity'.$qty_index} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
    if ( ! int($$specs{"txtQuantity$qty_index"}) ) {
      $openprint::log->debug("No quantity for $qty_index");
      next;
    } # end if

    $$specs{'hdnBreakdown'.$qty_index} = '';
    my $price = 0;
    my $mprice = 0;

    my %Cut_Stocks;
    my $stock_id = 1;

# For the non-book case, this devolves into the printing service
    foreach my $signature_service_index ( @signatures ) {
      my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
      my $form = $$sig_specs{SignatureIndex};
      $$specs{'hdnBreakdown'.$qty_index} .= join(' ', 'Signature: ', $form, ($$sig_specs{txtSignatureType}?$$sig_specs{txtSignatureType}:''), '<br/>');
      if ( ! ( $$sig_specs{'txtImposition'.$qty_index} and signature_needs($Project, $specs, $sig_specs, $qty_index) ) ) {
        $$specs{'hdnBreakdown'.$qty_index} .= ($$sig_specs{'txtImposition'.$qty_index} ? 'Not needed.' : 'No imposition.').'<br/>';
        $$specs{"txtRegularCutPrice-$form-$qty_index"} = '';
        $$specs{"ddmEquipment-$form-$qty_index"}  = '';
        $$specs{"txtVerticalCuts-$form-$qty_index"} = '';
        $$specs{"txtHorizontalCuts-$form-$qty_index"} = '';
        $$specs{"txtDVerticalCuts-$form-$qty_index"} = '';
        $$specs{"txtDHorizontalCuts-$form-$qty_index"} = '';
        $$specs{"txtCalculatedCuts-$form-$qty_index"} = '';
        next;
      } # end if
      my $Imposition = new openprint::Imposition();
      $Imposition->load( $sig_specs, $qty_index, $Project );
      my $Paper = $Imposition->Paper();
      if (!$$Paper{type}) {
        $$specs{'hdnBreakdown'.$qty_index} .= "Unable to determine paper type on signature $form quantity $qty_index.<br/>";
        next;
      }
      if ( $$Paper{type} eq 'Sheet' and $Paper->is_cut() ) {
        if ( $Cut_Stocks{ $Paper->id_string() } ) {
          $Cut_Stocks{ $Paper->id_string() }{quantity} += $$sig_specs{"StockQuantity$qty_index"};
        } else {
          $Cut_Stocks{ $Paper->id_string() } = { Stock=>$Paper, quantity=>$$sig_specs{"StockQuantity$qty_index"}, index=>$stock_id };
          $stock_id += 1;
        } # end if
      } # end if
      $openprint::log->debug('Paper: ' . $Paper->to_string() ) if DEBUG;

			if ( signature_needs_bindery_cutting($Project, $specs, $sig_specs, $qty_index) ) {

				my %results = signature_calc($Project, $sig_specs, $specs, $qty_index, $Paper, $Imposition, $fold_specs, $calc_hash);
				$$specs{Status} = 'uncalculated' if $results{Status} eq 'uncalculated';
				$$specs{alert} .= $results{alert} if $results{alert};
				$$specs{'hdnBreakdown'.$qty_index} .= $results{Breakdown};
				$$specs{"txtRegularCutPrice-$form-$qty_index"} = sprintf('%.2f', Math::Round::nearest(0.01, $results{Price}));

				$$specs{"FoldingCutPrice-$form-$qty_index"} = sprintf('%.2f', Math::Round::nearest(0.01, $results{FoldingPrice}));
				$$specs{"FoldingEquipment-$form-$qty_index"} = $results{FoldingEquipment} ? $results{FoldingEquipment}{id} : '';
				$$specs{"FoldingCuts-$form-$qty_index"} = $results{FoldingCuts};

				if ( my $minCharge = openprint::service::get_price( 'CuttingSignatureChargeMinimum', undef, $results{Equipment} ) ) {
					$results{Price} = $minCharge if $results{Price} and ($results{Price} < $minCharge);
				} # end if

				$price += $results{Price};
				$price += $results{FoldingPrice} if $results{FoldingPrice};
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('<span style="font-weight: bold;">Post press total $%.2f</span><br/>', 
						$results{Price} + ($results{FoldingPrice}?$results{FoldingPrice}:0)
						);

				$mprice += $results{MPrice};
				$$specs{"ddmEquipment-$form-$qty_index"} = $results{Equipment} ? $results{Equipment}->id() : '';
			} else {
				$$specs{'hdnBreakdown'.$qty_index} .= 'Post press cutting not needed.<br/>';
			}
      $$specs{'hdnBreakdown'.$qty_index} .= '<hr/>';
    } # end foreach form

    if ( $$services{Paper} and %Cut_Stocks ) {
      my %results = signature_calc_stock_cutting($Project, $specs, $qty_index, [ values %Cut_Stocks ]);
#$$specs{"ddmStockCutEquipment-$form-$qty_index"} = $results{Equipment} ? $results{Equipment}->id() : '';
      $$specs{"txtStockCutPrice-$qty_index"} = sprintf('%.2f', $results{Price});
      foreach my $Stock_Amount ( @{$results{Stocks}} ) {
        if ( ! $$Stock_Amount{Equipment} ) {
          $openprint::log->error('No Equipment for stock cutting for '.$$Stock_Amount{Stock}->to_string());
          $$specs{"ddmStockCutEquipment-$$Stock_Amount{index}-$qty_index"} = '';
        } else {
          $openprint::log->debug('Setting Equipment for stock cutting for '.$$Stock_Amount{Stock}->to_string().' to '.$$Stock_Amount{Equipment}->strid()) if DEBUG;
          $$specs{"ddmStockCutEquipment-$$Stock_Amount{index}-$qty_index"} = $$Stock_Amount{Equipment}->id();
        }
      }
      $price += $results{Price};
      $mprice += $results{MPrice};
      $$specs{Status} = 'uncalculated' if $results{Status} eq 'uncalculated';
      $$specs{alert} .= $results{alert} if $results{alert};
      $$specs{'hdnBreakdown'.$qty_index} .= $results{Breakdown};
    } # end if
    if ( my $minCharge = openprint::service::get_price('CuttingChargeMinimum') ) {
      $price = $minCharge if $price and ($price < $minCharge);
    } # end if

    if ( $Project->markup() ) {
      my $markup = (1+$Project->markup()/100);
      $mprice *= $markup;
      $price *= $markup;
    } # end if
    if ( $$specs{'Markup'.$qty_index} ) {
      my $markup = (1+$$specs{'Markup'.$qty_index}/100);
      $mprice *= $markup;
      $price *= $markup;
    } # end if

    if ( (defined $$specs{"OverridePrice$qty_index"} ) and ( $$specs{"OverridePrice$qty_index"} eq 'Y' ) ) {
      $$specs{"txtPrice$qty_index"} = sprintf( $config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"} );
    } else {
      $$specs{"txtPrice$qty_index"} = sprintf( $config{ProjectMoneyFormat}, Math::Round::nearest( 1, $price ) );
    } # end if
    $$specs{"MPrice$qty_index"} = sprintf( $config{UnitPriceFormat}, $mprice ? $mprice : 0 );
    $$specs{"txtUnitPrice$qty_index"} = sprintf( $config{UnitPriceFormat}, $price/$$specs{"txtQuantity$qty_index"});

  } # end foreach quantity
  return $$specs{Status};
} # end sub calc

sub display {
  my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;
  my $Project = new openprint::Project( $project_index );
  my $services = $Project->services();

  @{$$variable{StockCutEquipmentArray}} = map { $_->id(), $_->name() } openprint::Equipment->find(
    Specifications => {'Cutting Capable'=>'Y'}, useinestimating=>1, order=>'lower(strName)');

  my @capabilities = ('Y','When Printing','When Folding');
  if ( $$services{SaddleStitching} or $$services{LoopStitching} ) {
    push @capabilities, 'When Stitching';
  } # end if
  if ( $$services{PerfectBound} ) {
    push @capabilities, 'When PerfectBinding';
  } # end if
  if ( sets::isin( $Project->Type()->name(), ['Banners','InkjetOutputs','Decals','Signs'] ) ) {
    push @capabilities, 'Large Format';
  } # end if

  $$variable{EquipmentArray} = [ map { $_->id(), $_->name() } openprint::Equipment->find(
      Specifications => {'Cutting Capable'=>\@capabilities}, useinestimating=>1, order=>'lower(strName)') ];
  $$variable{PreFoldingEquipmentArray} = [ map { $_->id(), $_->name() } openprint::Equipment->find(
      Specifications => {'Cutting Capable'=>['Y','When Printing']}, useinestimating=>1, order=>'lower(strName)') ];

  @{$$variable{CuttingGroups}} = ();

  foreach my $signature_service_index ( $Project->signatures() ) {
    my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
    my $form = $$sig_specs{SignatureIndex};
    push @{$$variable{CuttingGroups}}, $signature_service_index, @$sig_specs{'SignatureIndex','txtServiceDescription'};
    foreach my $qty_index ( $Project->quantity_indexes() ) {
      next if $$sig_specs{'StockType'.$qty_index} and ($$sig_specs{'StockType'.$qty_index} eq 'Roll');
      @$variable{"txtSuppliedStockWidth-$form-$qty_index", "txtSuppliedStockHeight-$form-$qty_index",
        "txtSheetSizeWidth-$form-$qty_index", "txtSheetSizeHeight-$form-$qty_index"} =
          @$sig_specs{"hdnSuppliedStockWidth$qty_index","hdnSuppliedStockHeight$qty_index","StockWidth$qty_index","StockHeight$qty_index"};

    } # end foreach
  } # end foreach
  if ( @{$$variable{CuttingGroups}} == 0 ) {
# this will display the first group of cutting fields for projects that dont' have a printing service.
    push @{$$variable{CuttingGroups}}, 0;
  } # end if

} # end sub display

sub jdf {
  my ( $doc, $Project, $sig_id ) = @_;

  my $sig_specs = openprint::service::get_specs_ref( $Project->id(), $sig_id );

  my $JDF = $doc->createElement('JDF');
  $JDF->setAttribute('ID','Cutting'.$sig_id);
  $JDF->setAttribute('Type','Cutting');
  $JDF->setAttribute('Status','Waiting');
  my $ResourcePool = $JDF->appendElement( $doc->createElement('ResourcePool') );
  my $Media = $ResourcePool->appendElement( $doc->createElement('Media') );
  $Media->setAttribute( 'ID', 'Paper'.$sig_id );
  $Media->setAttribute( 'Class', 'Consumable' );
  $Media->setAttribute( 'Status', 'Available' );
  $Media->setAttribute( 'Brand', $$sig_specs{ddmStockBrand} );
  $Media->setAttribute( 'DescriptiveName', join(' ', @$sig_specs{'ddmStockBrand','ddmStockFinish','ddmStockColour','ddmStockWeight','StockWidth'.$Project->ordered_quantity_index(),$Project->ordered_quantity_index()} ) );
  $Media->setAttribute( 'Dimension', join(' ',
        $$sig_specs{'StockWidth'.$Project->ordered_quantity_index()}*25.4,# mm
        $$sig_specs{'StockHeight'.$Project->ordered_quantity_index()}*25.4,
        ) );
  $Media->setAttribute( 'GrainDirection', 'LongEdge' );
  $Media->setAttribute( 'MediaType', 'Paper' );
  $Media->setAttribute( 'MediaUnit', 'Sheet' );
  $Media->setAttribute( 'Grade', '1' );
  $Media->setAttribute( 'Thickness', $$sig_specs{SpecificStockCalliper}*25.4 );
  $Media->setAttribute( 'Weight', $$sig_specs{'txtMWeight'.$Project->ordered_quantity_index()}*.45359237 );


  my $InputComponent = $ResourcePool->appendElement( $doc->createElement('Component') );
  $InputComponent->setAttribute( 'ID', 'CuttingInput'.$sig_id );
  $InputComponent->setAttribute( 'Class','Quantity' );
  $InputComponent->setAttribute( 'Status','Available' );
  $InputComponent->setAttribute( 'ComponentType','Sheet' );
  $InputComponent->setAttribute( 'Dimensions',join(' ', 
        $$sig_specs{'StockWidth'.$Project->ordered_quantity_index()}*25.4,
        $$sig_specs{'StockHeight'.$Project->ordered_quantity_index()}*25.4,
        $$sig_specs{SpecificStockCalliper}*25.4,
        ) );
  my $CuttingParams = $ResourcePool->appendElement( $doc->createElement('CuttingParams') );
  $CuttingParams->setAttribute('ID','CPM'.$sig_id);
  $CuttingParams->setAttribute('Class','Parameter');
  $CuttingParams->setAttribute('Status','Available');

  my $OutputComponent = $ResourcePool->appendElement( $doc->createElement('Component') );
  $OutputComponent->setAttribute( 'ID', 'CuttingOutput'.$sig_id );
  $OutputComponent->setAttribute( 'Class','Quantity' );
  $OutputComponent->setAttribute( 'Status','Available' );
  $OutputComponent->setAttribute( 'ComponentType','Block' );
  $OutputComponent->setAttribute( 'Dimensions',join(' ', 
        $$sig_specs{txtWidth}*25.4,
        $$sig_specs{txtHeight}*25.4,
        $$sig_specs{SpecificStockCalliper}*25.4,
        ) );

# Need Media, Input Component, CuttingParams, Output Component
  my $ResourceLinkPool = $JDF->appendElement( $doc->createElement('ResourceLinkPool') );

  return $JDF;
} # end sub jdf

sub summary {
  my ( $Project, $service_id, $specs, $qty_index ) = @_;
#$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
  return '';
} # end sub summary

sub runspeed {
  my ( $Project, $Service, $Equipment, $qty_index, $signatures ) = @_;

  my $specs = $Service->specs();
# Cutting Time is in seconds, so 3600/Cutting Time = # per hour
  my $cuttime = $Equipment->specification( 'Cutting Time' ) + $Equipment->specification( 'Make Ready Time' );
  return 0 if ! $cuttime;
  my $runspeed = 0;
  foreach my $sig_id ( @{$signatures} ) {
    my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
    next if ! $$sig_specs{txtSpecificStockCalliper};
    my $form = $$sig_specs{SignatureIndex};
    next if ! $$specs{"txtCalculatedCuts-$form-$qty_index"} or $$specs{"txtAdditionalCuts$form"};
    my $liftDepth = $Equipment->specification( 'Maximum Lift Depth', $$specs{txtSpecificationStockCalliper} );

    $runspeed += int(
        ( $liftDepth / $$sig_specs{txtSpecificStockCalliper} ) * 
        3600/( $cuttime * ( $$specs{"txtCalculatedCuts-$form-$qty_index"} + $$specs{"txtAdditionalCuts$form"} ) ) );
#$openprint::log->debug( "Caclulationg runspeed for sig $sig_id $form) ( $$specs{"txtCalculatedCuts-$form-$qty_index"} )");
  } # end foreach
  return $runspeed;
}

# Returns runtime in seconds.
sub runtime {
  my ( $Project, $Service, $Equipment, $qty_index, $impressions, $speed, $signatures ) = @_;

  my $specs = $Service->specs();
  my $runtime = 0;

	$signatures = [$Project->signatures()] if ! $signatures;
	#$speed = runspeed($Project,$Service,$Equipment,$qty_index,$signatures) if ! $speed;

  foreach my $sig_id ( @{$signatures} ) {
    my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
    my $form = $$sig_specs{SignatureIndex};

		$impressions = $$sig_specs{"hdnImpressionQuantity$qty_index"} if ! $impressions;
		if ( ! $impressions ) {
			$log->error("No impressions for form $form");
			next;
		}

		if ( $$specs{"ddmEquipment-$form-$qty_index"} ) {
			my $E = $Equipment ? $Equipment : openprint::Equipment->find_one(id=>$$specs{"ddmEquipment-$form-$qty_index"});

			if ( $E ) {
				my $type = $E->specification('Type');

				if ( (!$type) or ( $type ne 'Stitcher' ) and ( $type ne 'Folder' ) ) {
					my $makeready = $E->specification('Make Ready Time');
					my $runspeed = $E->specification('Cutting Time');
					$openprint::log->debug("Cutting runtime: makeready:$makeready runspeed:$runspeed") if DEBUG;
					my $liftDepth = $E->specification('Maximum Lift Depth', $$sig_specs{txtSpecificStockCalliper});
					$openprint::log->debug(join('',
								"Calculating runspeed for sig $sig_id form:$form cuts(",
								$$specs{"txtCalculatedCuts-$form-$qty_index"},
								" using lift depth $liftDepth on $$E{strid}",
								)) if DEBUG;
					my $items_per_lift = POSIX::ceil($liftDepth/$$sig_specs{txtSpecificStockCalliper});
					if ( ! $items_per_lift ) {
#$log->error("No items_per_lift for $liftDepth / $$sig_specs{txtSpecificStockCalliper} in form $form of $$Project{id} on $$E{strid}");
#next;
						$items_per_lift = $impressions;
					}
					my $piles = $impressions / $items_per_lift;

					my $cuts = 0;
					$cuts += $$specs{"txtCalculatedCuts-$form-$qty_index"} if $$specs{"txtCalculatedCuts-$form-$qty_index"};
					$cuts += $$specs{"txtAdditionalCuts$form"} if $$specs{"txtAdditionalCuts$form"};
					$runtime += $cuts * ($makeready + $runspeed) * $piles;
					$openprint::log->debug("Resulting runtime for : $runtime") if DEBUG;
				} # end if not a stitcher or folder
			} else {
				$openprint::log->warning('No equipment for regular cuts using id='.$$specs{"ddmEquipment-$form-$qty_index"});
			} # end if has equipment
		} # end if has regular cuts/equipment
	
		if ( $$specs{"FoldingCuts-$form-$qty_index"} and $$specs{"FoldingEquipment-$form-$qty_index"} ) {
$openprint::log->debug("Doing Folding Cuts");
			# Pre-folding cutting
			my $E = $Equipment ? $Equipment : openprint::Equipment->find_one(id=>$$specs{"FoldingEquipment-$form-$qty_index"});
			if ( $E ) {
				$impressions = $$sig_specs{"hdnImpressionQuantity$qty_index"} if ! $impressions;
				if ( !$impressions ) {
					$log->error("No impressions for form $form");
					next;
				}
				my $makeready = $E->specification('Make Ready Time');
				my $runspeed = $E->specification('Cutting Time');
				$openprint::log->debug("Cutting runtime: MR:$makeready RS:$runspeed");
				my $liftDepth = $E->specification('Maximum Lift Depth', $$sig_specs{txtSpecificStockCalliper});
				my $items_per_lift = POSIX::ceil($liftDepth/$$sig_specs{txtSpecificStockCalliper});
				if ( ! $items_per_lift ) {
					$log->error("No lifts for $liftDepth / $$sig_specs{txtSpecificStockCalliper} in form $form");
					#next;
					$items_per_lift = $impressions;
				}
				my $piles = POSIX::ceil( $impressions / $items_per_lift );

				$openprint::log->debug(join('',
							"Calculation Folding Cuts runspeed for sig $sig_id form:$form Cuts(",
							$$specs{"FoldingCuts-$form-$qty_index"},
							" using lift depth $liftDepth/$$sig_specs{txtSpecificStockCalliper}=$items_per_lift on $$E{strid} = $piles piles",
							));
				my $this_runtime = ( $makeready + ($$specs{"FoldingCuts-$form-$qty_index"} * $runspeed) ) * $piles;
$openprint::log->debug("Runtime for sig $this_runtime=".misc::seconds2hms($this_runtime));

				$runtime += $this_runtime;
			} # end if Equipment
		} # end if FoldingCuts

  } # end foreach Signature
  $openprint::log->debug('Cutting runtime: '.$runtime.'='.misc::seconds2hms($runtime));
  return $runtime;
} # end sub runtime

sub save {
} # end sub save


1;
__END__
