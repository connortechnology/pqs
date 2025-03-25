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

package openprint::Estimating::Paper;

use strict;
use POSIX qw( ceil );
require Math::Round;
require Number::Format;

require openprint::service;
require openprint::Currency;
require openprint::Paper;

use constant DEBUG => 0;
use constant MAX_STOCK_INDEX => 10;

my @variables = (
  'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
  'txtPrice1', 'txtPrice2', 'txtPrice3',
  'MPrice1','MPrice2','MPrice3',
  'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
  'hdnBreakdown1','hdnBreakdown2','hdnBreakdown3',
  'alert',
);

sub variables {
	my ( $p_id, $s_id, $old_specs, $specs ) = @_;
	my @v = @variables;

	my $Project = new openprint::Project( $p_id );
	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		my $form = $$sig_specs{SignatureIndex};
		#foreach my $stock_index ( 1 .. MAX_STOCK_INDEX ) {
			#last if ! exists $$specs{"qty-$ss_id-$stock_index"};
			#push @v, "id-$ss_id-$stock_index";
			foreach my $qty_index ( $Project->quantity_indexes() ) {
				push @v, "qty-form$form-$qty_index";
				push @v, "sheets-form$form-$qty_index";
				push @v, "overrideqty-form$form-$qty_index";

			} # end foreach qty_index
		#} # end foreach stock_index
	} # end foreach ss_id
	foreach my $stock_index ( 1 .. MAX_STOCK_INDEX ) {
		foreach my $qty_index ( $Project->quantity_indexes() ) {
			push @v, "qty-$stock_index-$qty_index";
			push @v, "sheets-$stock_index-$qty_index";
			push @v, "cost-$stock_index-$qty_index";
			push @v, "overridecost-$stock_index-$qty_index";
			push @v, "price-$stock_index-$qty_index";
		} # end foreach qty_index
	} # end foreach stock_index
#$openprint::log->debug( "Variables: @v");
	return @v;
} # end sub variables

sub has_overrides {
  my ( $Project, $service_id, $specs, $qty_index ) = @_;
  $specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

  my @v;
  if ( $qty_index ) {
    foreach my $s_s_id ( $Project->signatures() ) {
      my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
      my $form = $$sig_specs{SignatureIndex};
      #foreach my $stock_index ( 1 .. MAX_STOCK_INDEX ) {
      push @v, map { $$specs{$_} ? $_ : () } (
        "overrideqty-form$form-$qty_index",
      );
      #} # end fireach stock_index
    } # end foreach sig
    foreach my $stock_index ( 1 .. MAX_STOCK_INDEX ) {
      push @v, map { $$specs{$_} ? $_ : () } (
        "overridecost-$stock_index-$qty_index",
      );
    } # end fireach stock_index
  } # end if

  return @v;
} # end sub has_overrides

sub outputs {
}

sub no_outputs {
}

sub signature_needs {
	my ( $Project, $sig_specs ) = @_;
	my $services = $Project->services();
	return 0 if $$services{NoPrinting};
	#return 1 if $$sig_specs{rdbSuppliedStock} ne 'Y';
	return 1;
} # end sub

sub neccessary {
	my ( $Project ) = @_;

  my $ServiceType = openprint::ServiceType->find_one( type=>'Paper' );
  return 0 if ( ! $ServiceType ) or sets::isin( $ServiceType->id(), $Project->Type()->blocked_services() );

	my $services = $Project->services();
	return 0 if $$services{NoPrinting};

  foreach my $signature_service_index ( $Project->signatures() ) {
    my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
    if ( signature_needs( $Project, $sig_specs ) ) {
      return 1;
    } # end if
  } # end foreach
	return 0;
} # end sub neccessary

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	$$specs{alert} = '';

	my $Project = new openprint::Project( $project_index );
	foreach my $qty_index ( $Project->quantity_indexes() ) {
    if (!$$specs{'OverridePrice'.$qty_index} or $$specs{'OverridePrice'.$qty_index} ne 'Y') {
      delete $$specs{'txtPrice'.$qty_index};
      delete $$specs{'MPrice'.$qty_index};
    }
    $$specs{"hdnBreakdown$qty_index"} = '';
  } # end foreach qty_index

	# Totals is storing the native qty, ie lbs for rolls, sheets for sheets
	my %totals;
	my %papers;

	my @Stocks = get_stocks( $Project, $service_index, $specs );
	if ( ! @Stocks ) {
		$$specs{alert} .= 'Stocks not found.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if
	my %indexes  = map { $$_{key}, $_ } @Stocks;
	$$specs{Status} = 'calculated';

	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		my $form = $$sig_specs{SignatureIndex};

		foreach my $qty_index ( $Project->quantity_indexes() ) {
			if ( ! $$sig_specs{'txtImposition'.$qty_index} ) {
				foreach my $Stock_Entry ( @Stocks ) {
					$$specs{"qty-form$form-$qty_index"} = '';
					$$specs{"sheets-form$form-$qty_index"} = '';
				} # end foreach stock_index
				next;
			} # end if
			my $PressSheet = openprint::Paper::load_from_signature( $Project, $sig_specs, $qty_index );
#$openprint::log->debug("Sheet for sig $ss_id $form $qty_index" . $PressSheet->to_string() ) if DEBUG;
			# This paper is in the printing format, not the supplied
			# Convert to supplied Stock
			my $SuppliedStock = $PressSheet->Supplied();
			my $paper_string = $SuppliedStock->id_string();

			my $Stock_Entry = $indexes{$paper_string};
			if ( ! $Stock_Entry ) {
				$openprint::log->error("Estimating::Paper No stock index for $paper_string");
				$openprint::log->debug("Press sheet: " . $PressSheet->id_string() );
				$openprint::log->debug("Supplied: " . $SuppliedStock->id_string() );
			} else {
				#Why is this  neccessary??
if ( 0 ) {
				#foreach my $stock_id ( values %indexes ) {
					#next if $stock_id == $stock_index;
					#$$specs{"qty-$form-$stock_id-$qty_index"} = '' if $$specs{"qty-$form-$stock_id-$qty_index"};
					#$$specs{"sheets-$form-$stock_id-$qty_index"} = '' if $$specs{"sheets-$form-$stock_id-$qty_index"};
				#} # end foreach stock_index
}
			} # end if

			my $stock_index = $$Stock_Entry{index};

			if ( $$specs{"overrideqty-form$form-$qty_index"} ne 'Y' ) {
				if ( $PressSheet->type() eq 'Sheet' ) {
					my $sheets = $$sig_specs{'StockQuantity'.$qty_index};
$log->debug("StockQuantity from sig $form : $sheets") if DEBUG;
					if ( ! ( $PressSheet->area() and $PressSheet->start_area() ) ) {
						Carp::cluck('No sheet area PressSheet: ' . $PressSheet->area() . ' start: ' . $PressSheet->start_area() );
					} elsif ( $PressSheet->factor() > 1 ) {
						# convert to supplied count
						$sheets = ceil( $sheets / $PressSheet->factor() );
$log->debug("converted StockQuantity: $sheets") if DEBUG;
					} # end if
					$$specs{"qty-form$form-$qty_index"} = Math::Round::nearest( 0.1, ( $sheets * $PressSheet->start_sheet_weight() ) );
					$$specs{"sheets-form$form-$qty_index"} = $sheets;
				} else {
					$$specs{"qty-form$form-$qty_index"} = $$sig_specs{'StockQuantity'.$qty_index};
					delete $$specs{"sheets-form$form-$qty_index"};
				} # end if
			} else {
				$log->debug("StockQuantity from sig $form : overriden to ".$$specs{"qty-form$form-$qty_index"} ) if DEBUG;
				if ( $$PressSheet{type} eq 'Sheet' ) {
          my $sheets = $$sig_specs{'StockQuantity'.$qty_index};
$log->debug("StockQuantity from sig $form : $sheets") if DEBUG;
          if ( ! ( $PressSheet->area() and $PressSheet->start_area() ) ) {
            Carp::cluck('No sheet area PressSheet: ' . $PressSheet->area() . ' start: ' . $PressSheet->start_area() );
					} elsif ( $PressSheet->factor() > 1 ) {
# convert to supplied count
						$sheets = ceil( $sheets / $PressSheet->factor() );
					} # end if
					if ( 
							( $$specs{"qty-form$form-$qty_index"} < Math::Round::nearest( 0.1, ( $sheets * $PressSheet->start_sheet_weight() ) ) )
							or
							( $$specs{"sheets-form$form-$qty_index"} < $sheets ) 
						 ) {
						$$specs{alert} .= "The overriden stock quantity for form $form qty $qty_index is not sufficient.<br/>";	
					}
        } else {
					if ( $$specs{"qty-form$form-$qty_index"} < $$sig_specs{'StockQuantity'.$qty_index} ) {
						$$specs{alert} .= "The overriden stock quantity for form $form qty $qty_index is not sufficient.<br/>";	
					}
        } # end if

			} # end if

			if ( $SuppliedStock->type() eq 'Sheet' ) {
				$totals{$stock_index}{"qty_$qty_index"} += $$specs{"sheets-form$form-$qty_index"};
			} else {
				$totals{$stock_index}{"qty_$qty_index"} += $$specs{"qty-form$form-$qty_index"};
			} # end if
		} # end foreach qty_index
	} # end foreach signature

	if ( DEBUG ) {
		$openprint::log->debug('Total Paper Totals:');
		foreach my $Stock_Entry ( @Stocks ) {
			my $paper_string = $$Stock_Entry{key};
			foreach my $qty_index ( $Project->quantity_indexes() ) {
				$openprint::log->debug("QTY $qty_index ($paper_string) => " . $totals{$$Stock_Entry{index}}{"qty_$qty_index"} );
			} # end foreach
		} # end if
	} # end if

	# Enforce minimum orders and full packages
	foreach my $Stock_Entry ( @Stocks ) {
		my $stock_index = $$Stock_Entry{index};
		my $total = $totals{$stock_index};

		my $Stock = $$Stock_Entry{Stock};
		foreach my $qty_index ( $Project->quantity_indexes() ) {
			$$specs{"hdnBreakdown$qty_index"} .= $Stock->to_string() . '<br/>';
		}
		if ( $Stock->full_packages() ) {
			my $qty_per_package = $Stock->sheets_per_package();
			if ( $qty_per_package ) {
				foreach my $qty_index ( $Project->quantity_indexes() ) {
					next if ! $$total{"qty_$qty_index"};
					$$specs{"hdnBreakdown$qty_index"} .= " requires full packages $qty_per_package sheets per package<br/>";
					$$total{"qty_$qty_index"} = $qty_per_package * ceil( $$total{"qty_$qty_index"} / $qty_per_package );
				} # end foreah qty_index
			} # end if sheets_per_package
		} # end if full packages
		if ( $$Stock{minimum_order} ) {
# Assume sheets for sheets, lbs for Rolls
			foreach my $qty_index ( $Project->quantity_indexes() ) {
				next if ! $$total{"qty_$qty_index"};
				if ( $$Stock{minimum_order} > $$total{"qty_$qty_index"} ) {
					$$specs{"hdnBreakdown$qty_index"} .= " adjusting to minimum order $$Stock{minimum_order}".$Stock->units()."<br/>";
					$$total{"qty_$qty_index"} = $$Stock{minimum_order};
				} # end if
			} # end foreach qty_index
		} # end if
		if ( $$Stock{available_to_order} ne '' ) {
			foreach my $qty_index ( $Project->quantity_indexes() ) {
				next if ! $$total{"qty_$qty_index"};
				if ( $$Stock{available_to_order} < $$total{"qty_$qty_index"} ) {
					$$specs{alert}  .= $Stock->to_string() . ' has only ' . $$Stock{available_to_order} . " available. This does not satisfy quantity $qty_index<br/>";
					$$specs{Status} = 'uncalculated';
				} # end if
			} # end foreach
		} # end if
	} # end foreach

	if ( DEBUG ) {
		foreach my $Stock_Entry ( @Stocks ) {
			my $stock_index = $$Stock_Entry{index};
			my $total = $totals{$stock_index};
			foreach my $qty_index ( $Project->quantity_indexes() ) {
				if ( ! $total ) {
	$openprint::log->debug("After minimum: QTY $qty_index $$Stock_Entry{key}  => no totals" );
				} else {
	$openprint::log->debug("After minimum: QTY $qty_index $$Stock_Entry{key}  => " . $$total{"qty_$qty_index"} );
				}
			} # end foreach
		} # end if
	}

	foreach my $Stock_Entry ( @Stocks ) {
		my $paper_id = $$Stock_Entry{key};
		my $Stock = $$Stock_Entry{Stock};
		my $stock_index = $$Stock_Entry{index};
		my $total = $totals{$stock_index};
		foreach my $qty_index ( $Project->quantity_indexes() ) {
			# Normalize and output qtys
			if ( $$Stock{type} eq 'Sheet' ) {
				$$specs{"qty-$stock_index-$qty_index"} = Math::Round::nearest(0.1, ( $$total{"qty_$qty_index"} * $Stock->sheet_weight() ));
				$$specs{"sheets-$stock_index-$qty_index"} = $$total{"qty_$qty_index"};
			} else {
				$$specs{"qty-$stock_index-$qty_index"} = $$total{"qty_$qty_index"};
				$$specs{"sheets-$stock_index-$qty_index"} = ceil( $$total{"qty_$qty_index"} / $Stock->start_sheet_weight() ) if $Stock->start_sheet_weight();
			} # end if

			if ( ! $Stock->supplied() ) {
				if ( $$specs{"overridecost-$stock_index-$qty_index"} ne 'Y' ) {
					
					my $price;
					if ( $$total{"qty_$qty_index"} ) {
						if ( $Stock->type() eq 'Sheet' ) {
							$price = $Stock->get_price( sheets=>$$total{"qty_$qty_index"},service=>'Material' );
						} else {
							$price = $Stock->get_price( weight=>$$total{"qty_$qty_index"},service=>'Material' );
						} # end if
						if ( ! $$price{'100lb Price'} ) {
							$$specs{alert} .= $Stock->to_string() . ' has no price for ' .$$total{"qty_$qty_index"}.( $Stock->type() eq 'Sheet' ? ' sheets' : ' lbs' ) . '<br/>';
						} # en dif
					} # end if qty
					$$specs{"cost-$stock_index-$qty_index"} = sprintf('%.2f', $$price{'100lb Price'} );
#$openprint::log->warn("Getting prices for $stock_index $paper_id (".$totals{$paper_id}{"qty_$qty_index"}.'sheets) => $' . $price{'100lb Price'}.'/100lb');
				} # end if
				$$specs{"price-$stock_index-$qty_index"} = Math::Round::nearest( 0.01, $$specs{"cost-$stock_index-$qty_index"} * $$specs{"qty-$stock_index-$qty_index"} / 100 );
			} else {
				$$specs{"cost-$stock_index-$qty_index"} = $$specs{"price-$stock_index-$qty_index"} = 0;
			} # end if
			#$$totals{Cost}[$qty_index] = $$specs{"cost-$stock_index-$qty_index"};
			#$$specs{"MPrice$qty_index"} += $$specs{"cost-$stock_index-$qty_index"} * ceil( (1000/$$sig_specs{'txtImposition'.$qty_index}) * $RunPaper->sheet_weight() )/ 100;
		} # end foreach qty_index
	} # end foreach Stock

	foreach my $qty_index ( $Project->quantity_indexes() ) {
    if (!$$specs{'OverridePrice'.$qty_index} or $$specs{'OverridePrice'.$qty_index} ne 'Y') {
      $$specs{"txtPrice$qty_index"} = 0;
      foreach my $Stock_Entry ( @Stocks ) {
        my $stock_index = $$Stock_Entry{index};
        $$specs{"txtPrice$qty_index"} += $$specs{"price-$stock_index-$qty_index"};
      } # end foreach Stock
      $$specs{"MPrice$qty_index"} = sprintf($openprint::config{UnitPriceFormat},
        $$specs{"MPrice$qty_index"} * (1+$Project->markup()/100) );
      $$specs{"txtPrice$qty_index"} = sprintf($openprint::config{ProjectMoneyFormat},
        $$specs{"txtPrice$qty_index"} * (1+$Project->markup()/100) );
      $openprint::log->debug("Price $qty_index " . $$specs{"txtPrice$qty_index"} ) if DEBUG;
    } # end if override
	} # end foreach qty_index

	return $$specs{Status};
} # end sub calc

sub display {
	my ( $self, $log, $dbh, $variable, $project_index, $service_index ) = @_;

	return;
	my %totals;
	my $Project = new openprint::Project( $project_index );

	foreach my $signature_service_index ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
		next if $$sig_specs{rdbSuppliedStock} eq 'Y';
		foreach my $qty_index ( $Project->quantity_indexes() ) {

			my $brand = $$sig_specs{txtSpecificStockBrand} ? $$sig_specs{txtSpecificStockBrand} : $$sig_specs{ddmStockBrand};
			my $colour = $$sig_specs{txtSpecificStockColour} ? $$sig_specs{txtSpecificStockColour} : $$sig_specs{ddmStockColour};
			my $finish = $$sig_specs{txtSpecificStockFinish} ? $$sig_specs{txtSpecificStockFinish} : $$sig_specs{ddmStockFinish};
			my $weight = $$sig_specs{txtSpecificStockWeight} ? $$sig_specs{txtSpecificStockWeight} : $$sig_specs{ddmStockWeight};

			my $id = $qty_index.$brand.$colour.$finish.$weight.$$sig_specs{'hdnSuppliedSheetSizeWidth'.$qty_index}.'x'.$$sig_specs{'hdnSuppliedSheetSizeHeigth'.$qty_index};

			if ( ! exists $totals{$id} ) {
				$totals{$id}{Brand} = $brand;
				$totals{$id}{Colour} = $colour;
				$totals{$id}{Finish} = $finish;
				$totals{$id}{Weight} = $weight;
				$totals{$id}{SheetSize} = $$sig_specs{'hdnSuppliedSheetSizeWidth'.$qty_index} . ' x ' . $$sig_specs{'hdnSuppliedSheetSizeHeight'.$qty_index};
			} # end if

			$totals{$id}{SheetCount} += $$sig_specs{'txtPressSheetqty'.$qty_index};
		} # end foreach qty
	} # end foreach signature

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		foreach my $id ( keys %totals ) {
			my ( $price, $discount );

			if ( $totals{$id}{Index} ) {
				my $list_id = openprint::pricing::get_pricelist_id();
				$price = openprint::pricing::get_best_price( $$variable{company_id}, $totals{$id}{Index}, $list_id, 'openprint::paper_priceset', 1 );
				my $discounted_price = openprint::pricing::get_best_price( $$variable{company_id}, $totals{$id}{Index}, $list_id, 'openprint::paper_priceset', $totals{$id}{'hdnGrossSheetCount'.$qty_index} );
				$discount = $price - $discounted_price;
			} # end if

			push @{$$variable{'PAPER'.$qty_index}}, $totals{$id}{Brand}, $totals{$id}{Colour}, $totals{$id}{Finish}, $totals{$id}{Weight}, $totals{$id}{SheetSize};
			push @{$$variable{'PAPER'.$qty_index}}, $totals{$id}{'hdnGrossSheetCount'.$qty_index}, sprintf('%.2f',$price), sprintf('%.2f',$discount);
		} # end foreach
	} # end foreach

	my $Currency = openprint::Currency::get_current();
	@$variable{'CurrencyName', 'CurrencySymbol'} = ( $Currency->name(), $Currency->symbol() );
    $$variable{ProjectIndex} = $project_index;

} # end sub display

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	my @Stocks = get_stocks_and_quantities( $Project, $service_id, $specs, $qty_index );

	if ( $qty_index ) {
		my @summaries;
		foreach my $Stock_Entry ( @Stocks ) {
			push @summaries, se_quantity_summary( $Stock_Entry, $specs, $qty_index );
		} # end foreach Stock
		return \@summaries;
	} # end if
	return [ map { $$_{Stock}->message() ? $$_{Stock}->to_string() . '<br/><span class="StockMessage">'. 
		ssi::variable_substitution( \$$_{Stock}->message(), { 
				Stock	=>	$$_{Stock},
				Project => $Project,
				qty_index	=>	$qty_index,
				} ) . 
		'</span>' : $$_{Stock}->to_string() } @Stocks ];
} # end sub summary

sub save {
} # end sub save

sub se_quantity_summary {
	my ( $Stock_Entry, $specs, $qty_index ) = @_;
	my $html = '';
	my $Paper = $$Stock_Entry{Stock};
	my $stock_id = $$Stock_Entry{index};

#$openprint::log->warn("Stock " . $Paper->to_string() . " QTY $stock_id $qty_index " . $$specs{"qty-$stock_id-$qty_index"} );
	if ( $$specs{"qty-$stock_id-$qty_index"} ) {
		if ( $$Paper{type} eq 'Sheet' ) {
			$html .= $$specs{"sheets-$stock_id-$qty_index"}.' sheets ';
		} # end if
		if ( $$specs{"qty-$stock_id-$qty_index"} < 10 ) {
      $html .= Number::Format::format_number( Math::Round::nearest(.1, $$specs{"qty-$stock_id-$qty_index"} ) ).' lbs';
    } else {
      $html .= Number::Format::format_number( Math::Round::nearest(1, $$specs{"qty-$stock_id-$qty_index"} ) ).' lbs';
    }
    $$Stock_Entry{"Price$qty_index"} = $Paper->get_price( weight=>$$specs{"qty-$stock_id-$qty_index"}, service=>'Material' ) if ! $$Stock_Entry{"Price$qty_index"};
		my $Price = $$Stock_Entry{"Price$qty_index"};

		if ( $$Price{units} eq 'per square foot' ) {
			$html .= ' ' . Number::Format::format_number( Math::Round::nearest( 1, ( $$specs{"qty-$stock_id-$qty_index"} / $Paper->wpsi() ) / 144 ) ).' sq feet';
		} elsif ( $$Price{units} eq 'per square inch' ) {
			$html .= ' ' . Number::Format::format_number( Math::Round::nearest( 1, $$specs{"qty-$stock_id-$qty_index"} / $Paper->wpsi() ) ). ' sq inches';
		} elsif ( $$Price{units} eq 'per 100lbs' ) {
			if ( ( $Paper->type() eq 'Roll' ) and ( $$specs{"qty-$stock_id-$qty_index"} > 100 ) ) {
				if ( ! $Paper->width() ) {
					$html .= ' Unable to calculate feet due to stock not having a width.<br/>';
				} else {
					$html .= ' ' . Number::Format::format_number( int( ( ( $$specs{"qty-$stock_id-$qty_index"} / $Paper->wpsi() ) / $Paper->width() ) / 12 ) ). ' feet';
				}
			} # end if
    } elsif ($$Price{units} eq 'sheets' || $$Price{units} eq 'lbs') {
		} elsif ( $$Price{units} ) {
			$html .= 'unknown units: ' . $$Price{units};
		} elsif ( sets::isin( $$Stock_Entry{Project}->Type()->name(), [ 'Banners' ] ) ) {
			$html .= ' ' . Math::Round::nearest(1, ( $$specs{"qty-$stock_id-$qty_index"} / $Paper->wpsi() ) / $Paper->width() ).'inches';
		} # end if
	} else {
		$html .= 'none';
	} # end if
	return $html;
} # end sub se_quantity_summary

sub se_price_summary {
	my ( $SE, $specs, $qty_index ) = @_;

	if ( $$specs{"qty-$$SE{index}-$qty_index"} ) {
	$$SE{"Price$qty_index"} = $$SE{Stock}->get_price( weight=>$$specs{"qty-$$SE{index}-$qty_index"}, service=>'Material' ) if ! $$SE{"Price$qty_index"};
	my $Price = $$SE{"Price$qty_index"};
	return '@ $'.$$specs{"cost-$$SE{index}-$qty_index"}.$$Price{units}. ' = $' . $$specs{"price-$$SE{index}-$qty_index"};
	} 
	return '';	
} # end sub se_price_summary

# The order of stocks is important... thing is, it can change if the brand changes for example.
# So it needs to be inorder of appearance.
sub get_stocks {
	my ( $Project ) = @_;
	my %Papers;
	my $stock_id = 1;
	foreach my $ss_id ( $Project->signatures( { sort=> 1 } ) ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		foreach my $q_index ( $Project->quantity_indexes() ) {
			next if ! $$sig_specs{'txtImposition'.$q_index};
			my $Paper = openprint::Paper::load_from_signature( $Project, $sig_specs, $q_index )->Supplied();
			if ( ! $Papers{$Paper->id_string()} ) {
				$Papers{$Paper->id_string()} = { Project => $Project, Stock=>$Paper, index=>$stock_id, key=>$Paper->id_string() };
				$stock_id += 1;
			} # end if
		} # end foreach qty_index
	} # end foreach
	my @Results;
	foreach my $key ( sort { 
			my $P1 = $Papers{$a};
			my $P2 = $Papers{$b};
			return $$P1{index} <=> $$P2{index};
			} keys %Papers ) {
		push @Results, $Papers{$key};
	} # end foreach
	return @Results;
} # end sub get_stocks

sub get_stocks_and_quantities {
	my ( $Project, $service_id, $specs, $qty_index, @Stocks ) = @_;

	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	@Stocks = get_stocks( $Project, $service_id, $specs ) if ! @Stocks;

	foreach my $Stock ( @Stocks ) {
		load_stock_entry( $Stock, $specs, $qty_index );
#$openprint::log->warn("Stock QTY $stock_id $qty_index " . $$specs{"qty-$stock_id-$qty_index"} );
	} # end foreach key
	return @Stocks;

} # end sub get_stocks_and_quantities

sub load_stock_entry {
	my ( $SE, $specs, $qty_index ) = @_;
	if ( $$specs{"qty-$$SE{index}-$qty_index"} ) {
		if ( $$SE{Stock}->type() eq 'Sheet' ) {
			$$SE{quantity} = $$specs{"sheets-$$SE{index}-$qty_index"};
		} else {
			$$SE{quantity} = $$specs{"qty-$$SE{index}-$qty_index"};
		} # end if
	} # end if
	$$SE{cost} = $$specs{"cost-$$SE{index}-$qty_index"};
	$$SE{price} = $$specs{"price-$$SE{index}-$qty_index"};
} # end sub load_stock_entry

1;
__END__
