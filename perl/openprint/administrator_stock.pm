use strict;
package openprint::administrator_stock;
use Text::CSV_XS ();
use Data::Dumper;
require sql;
require misc;
require openprint::Paper;

#require openprint::pricelist;
#require openprint::paper_price;
#require openprint::paper_priceset;
#require openprint::Equipment_Stock_Setting;
require openprint::Company;
require openprint::StockBrand;
require openprint::StockFinish;
require openprint::StockColour;
require openprint::StockWeight;
require openprint::StockGroup;
require openprint::StockMaterial;
require openprint::StockQuality;
require openprint::Manufacturer;
require openprint::PaperPrice;
require openprint::ProjectType;
require openprint::Skid;
#require openprint::Supplier;

use openprint ();
use vars qw( %variable %session %param %config $log $dbh $r );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

sub _stocks {
	if ( %param and ! $param{btnFunction} ) {
    $log->debug("Calling save_params");
		ssi::save_params('/administrator/stock/list.html', 
      'name',
			'group_id','owner_id','manufacturer_id','supplier_id', 'brand_id','finish_id',
			'colour_id','weight_id','fsc_code','material_id', 'Types', 'recommendations',
			'grain_direction', 'digital', 'width','height', 'scoring', 'setup_prices', 
			'material_prices', 'customer_supplied', 'has_message', 'has_minimum_order',
			'calliper', 'has_problems', 'user_type' );
		$session{'/administrator/stock/list.html?OrLarger'} = $param{OrLarger};
	} # end if
} # end sub _stocks

sub list {
	my @Papers;
	if ( $param{chkStock} ) {
		@Papers = openprint::Paper->find( id=>$param{chkStock} );
	} elsif ( $param{stock_ids} ) {
		@Papers = openprint::Paper->find( id=> (ref $param{stock_ids} eq 'ARRAY' ? $param{stock_ids} : [split(',', $param{stock_ids} )] ) );
	} # end if
		
	if ( $param{btnFunction} eq 'Delete' ) {
		foreach my $Paper ( @Papers ) {
			$Paper->delete();
		} # end foreach
	} elsif ( $param{btnFunction} eq 'Export' ) {
		my @header = ( 'ID', 'Owner','Manufacturer','Supplier','Group','Brand', 'Finish', 'Colour', 'Weight', 'Quality', 'MWeight', 'gsm','Calliper', 'Type','Width', 'Height', 'Basis Width','Basis Height', 'Grain Direction','DoubleSided?','Cuttable?','Multiple Parts?','Perfecting','Scoring Required?','Blade Cleaning Required?','Grade','Sheets Per Package','Supplied', 'Digital','Full Packages','Minimum Order','Inventory #','Material Type','Message', 'Recommendations');
		my @data;

		foreach my $Stock ( openprint::Paper->find( order=>'brand,finish,colour,weight,width,height', 
					columns=>'*,(SELECT name FROM StockBrands WHERE Stockbrands.id=brand_id) AS brand,(SELECT name FROM StockFinishes WHERE StockFinishes.id=finish_id) AS finish,(SELECT name FROM StockColours WHERE StockColours.id=colour_id) AS colour,(SELECT name FROM StockWeights WHERE StockWeights.id=weight_id) AS weight ',
					( $param{group_id} ? ( group_id => $param{group_id} ) : () ),
					( $param{owner_id} ? ( owner_id => $param{owner_id} ) : () ),
					( $param{manufacturer_id} ? ( manufacturer_id => $param{manufacturer_id} ) : () ),
					( $param{supplier_id} ? ( suopplier_id => $param{supplier_id} ) : () ),
					( $param{brand_id} ? ( 'brand_id'    => $param{brand_id} ) : () ),
					( $param{finish_id} ? ( 'finish_id'  => $param{finish_id} ) : () ),
					( $param{colour_id} ? ( 'colour_id'  => $param{colour_id} ) : () ),
					( $param{weight_id} ? ( 'weight_id'  => $param{weight_id} ) : () ),
					( $param{quality_id} ? ( 'quality_id'        => $param{quality_id} ) : () ),
					( $param{material_id} ? ( 'material_id'      => $param{material_id} ) : () ),
					( $param{Types} ? ( 'type'           => $param{Types} ) : () ),
					( $param{fsc_code} ? ( 'fsc_code'    => $param{fsc_code} ) : () ),
					( $param{width} ? ( 'width'=>$param{width} ) : () ),
					( $param{height} ? ( 'height'=>$param{height} ) : () ),
					( $param{grain_direction} ? ( grain_direction => $param{grain_direction} ) : () ),
					( $param{digital} ne '' ? ( digital=>$param{digital} ) : () ),
					'order'         => 'brand,finish,colour,weight, width, height'
					) ) {
			next if $param{recommendations} eq '0' and $Stock->recommendations();
			next if $param{recommendations} eq '1' and ! $Stock->recommendations();
			if ( $param{setup_prices} eq '1' ) {
				next if ! openprint::PaperPrice->find_one(paper_id=>$$Stock{id}, service=>'Setup');
			} elsif ( $param{setup_prices} eq '0' ) {
				next if openprint::PaperPrice->find_one(paper_id=>$$Stock{id}, service=>'Setup');
			} # end if
			if ( $param{material_prices} eq '1' ) {
				next if ! openprint::PaperPrice->find_one(paper_id=>$$Stock{id}, service=>'Material');
			} elsif ( $param{material_prices} eq '0' ) {
				next if openprint::PaperPrice->find_one(paper_id=>$$Stock{id}, service=>'Material');
			} # end if
			push @data, $Stock->id(), $Stock->owner(), $Stock->manufacturer(), $Stock->Supplier()->name(), $Stock->group(), $Stock->brand(), $Stock->finish(), $Stock->colour(), $Stock->weight(), $Stock->quality(), 
				 $Stock->mweight(), $Stock->gsm(), $Stock->calliper(), $Stock->type(), $Stock->width(), $Stock->height(), $Stock->basis_width(), $Stock->basis_height(), $Stock->grain_direction(), $Stock->doublesided(), $Stock->cuttable(), $Stock->multipart(), $Stock->perfecting(), $Stock->score_required(), $Stock->bladecleaning(), $openprint::Paper::grades{$Stock->grade()}, $Stock->sheets_per_package(), $Stock->supplied(), $Stock->digital(), $Stock->full_packages(), $Stock->minimum_order(), $Stock->inventory_number(), $Stock->material(), $Stock->message();
			push @data, join(',', map { new openprint::ProjectType($_)->name() } $Stock->recommendations());
		} # end foreach
		misc::export_csv( $r, $log, \%variable, 'stock.csv', \@header, \@data );

	} elsif ( $param{btnFunction} eq 'Export Prices' ) {
		my @header = ( 'ID', 'Paper Brand', 'Finish','Colour','Weight','Type', 'Width','Height','Pricelist', 'Service', 'Equipment', 'Min', 'Max', 'Units', 'Cost', 'Markup', 'Price', 'Discountable' );
		my @data;
		foreach my $Stock ( openprint::Paper->find( order=>'brand,finish,colour,weight,width,height',
                    columns=>'*,(SELECT name FROM StockBrands WHERE Stockbrands.id=brand_id) AS brand,(SELECT name FROM StockFinishes WHERE StockFinishes.id=finish_id) AS finish,(SELECT name FROM StockColours WHERE StockColours.id=colour_id) AS colour,(SELECT name FROM StockWeights WHERE StockWeights.id=weight_id) AS weight ',
                    ( $param{group_id} ? ( group_id => $param{group_id} ) : () ),
                    ( $param{owner_id} ? ( owner_id => $param{owner_id} ) : () ),
                    ( $param{manufacturer_id} ? ( manufacturer_id => $param{manufacturer_id} ) : () ),
                    ( $param{supplier_id} ? ( supplier_id => $param{supplier_id} ) : () ),
                    ( $param{brand_id} ? ( 'brand_id'    => $param{brand_id} ) : () ),
                    ( $param{finish_id} ? ( 'finish_id'  => $param{finish_id} ) : () ),
                    ( $param{colour_id} ? ( 'colour_id'  => $param{colour_id} ) : () ),
                    ( $param{weight_id} ? ( 'weight_id'  => $param{weight_id} ) : () ),
                    ( $param{quality_id} ? ( 'quality_id'        => $param{quality_id} ) : () ),
                    ( $param{material_id} ? ( 'material_id'      => $param{material_id} ) : () ),
                    ( $param{Types} ? ( 'type'           => $param{Types} ) : () ),
                    ( $param{fsc_code} ? ( 'fsc_code'    => $param{fsc_code} ) : () ),
                    ( $param{width} ? ( 'width'=>$param{width} ) : () ),
                    ( $param{height} ? ( 'height'=>$param{height} ) : () ),
                    ( $param{grain_direction} ? ( grain_direction => $param{grain_direction} ) : () ),
                    ( $param{digital} ne '' ? ( digital=>$param{digital} ) : () ),
                    'order'         => 'brand,finish,colour,weight, width, height'
                    ) ) {
            next if $param{recommendations} eq '0' and $Stock->recommendations();
            next if $param{recommendations} eq '1' and ! $Stock->recommendations();
            if ( $param{setup_prices} eq '1' ) {
                next if ! openprint::PaperPrice->find_one(paper_id=>$$Stock{id}, service=>'Setup');
            } elsif ( $param{setup_prices} eq '0' ) {
                next if openprint::PaperPrice->find_one(paper_id=>$$Stock{id}, service=>'Setup');
            } # end if

            foreach my $Price ( openprint::PaperPrice->find( paper_id=>$$Stock{id}, order=>'lnglistindex, lngmin NULLS FIRST, lngmax NULLS FIRST') ) {
                push @data, $Stock->id(), $Stock->brand(), $Stock->finish(),$Stock->colour(), $Stock->weight(), $Stock->type(), $Stock->width(), $Stock->height();
                push @data, $Price->Pricelist()->name(), $Price->service(), $Price->Equipment()->strid(), $Price->min(), $Price->max(), $Price->units(), $Price->cost(), $Price->markup(), $Price->price(), $Price->discountable();
            } # end foreach
        } # end foreach Paper
        misc::export_csv( $r, $log, \%variable, 'PaperPrices.csv', \@header, \@data );

	} elsif ( $param{btnFunction} eq 'Copy' ) {
		foreach my $Paper ( @Papers ) {
			my $NewPaper = $Paper->copy();
			$NewPaper->save();
      #foreach my $Setting ( openprint::Equipment_Stock_Setting->find('stock_id'=>$Paper->id()) ) {
      #$Setting = $Setting->copy();
      #$Setting->save({'stock_id'=>$NewPaper->id()});
      #} # end foreach
		} # end foreach
	} elsif ( $param{btnFunction} eq 'ApplyChanges' ) {
		foreach my $Paper ( @Papers ) {
			my $ac = sql::start_transaction( $dbh );
			if ( $param{mode} eq 'modify' ) {
				my $note = 'Modify Prices: ';
				foreach my $Price ( $Paper->Prices() ) {
					if ( $param{amount} ne '' ) {
						if ( $param{amount} =~ /^\+(.*)/ ) {
							$Price->cost( $Price->cost() + $1 );
						} elsif ( $param{amount} =~ /^\-(.*)/ ) {
							$Price->cost( $Price->cost() - $1 );
						} else {
$openprint::log->debug("Setting: $param{amount} " );
							$Price->cost( $param{amount} );
						} # end if
					}
					if ( $param{markup} ne '' ) {
						if ( $param{markup} =~ /^\+(.*)/ ) {
							$Price->markup( $Price->markup() + $1 );
						} elsif ( $param{markup} =~ /^\-(.*)/ ) {
							$Price->markup( $Price->markup() - $1 );
						} else {
							$Price->markup( $param{markup} );
						} # end if
					} # end if
					$Price->price( Math::Round::nearest( 0.01, $Price->cost() * ( 1+($Price->markup()/100) ) ) );
					$variable{error} .= $Price->save();
					$note .= '<br/>'.$Price->to_string();
				} # end foreach Price
				(new openprint::Log())->save({ Object=>$Paper, action=>'Edit', note=>$note } );
			} elsif ( $param{mode} eq 'new' ) {
				my $note = 'New Prices: ';
				foreach my $Price ( $Paper->Prices() ) {
					$Price->delete();
				} # end foreach Price
				foreach my $key ( keys %param ) {
					if ( my ( $pricelist_id, $id ) = $key =~ /min-(\d*)-(\d*)/ ) {
						if ( ! ( $param{"cost-$pricelist_id-$id"} or $param{"price-$pricelist_id-$id"} ) ) {
							$variable{error} .= "Skipping price $id because no cost or price entered.<br/>";
							next;
						} # en dif

						my $Price = new openprint::PaperPrice( );
						$variable{error} .= $Price->save( {
								pricelist_id	=>	$pricelist_id,
								paper_id		=> $Paper->id(),
								min				=>	$param{"min-$pricelist_id-$id"},
								max				=>	$param{"max-$pricelist_id-$id"},
								units			=>	$param{"units-$pricelist_id-$id"},
								cost			=>	$param{"cost-$pricelist_id-$id"},
								markup			=>	$param{"markup-$pricelist_id-$id"},
								price			=>	$param{"price-$pricelist_id-$id"},
								discountable	=>	$param{"discount-$pricelist_id-$id"},
								service			=>	$param{"service-$pricelist_id-$id"},
								} );
						$note .= '<br/>'.$Price->to_string();
						
						# Force reload
						delete $$Paper{Prices};
					} # end if
				} # end foreach param key
				(new openprint::Log())->save({ Object=>$Paper, action=>'Edit', note=>$note } );
			} elsif ( $param{mode} eq 'recommended' ) {
				$Paper->recommendations( ref $param{PRF} eq 'ARRAY' ? @{$param{PRF}} : ( $param{PRF} ) );
				$variable{error} .= $Paper->save();
				$variable{ExternalRedirect} = '/administrator/stock/list.html';
			} elsif ( $param{mode} eq 'other' ) {
				my %changes;

				foreach my $field ( 'digital', 'score_required', 'gsm' ) {
            next if $param{$field} eq '';
						$changes{$field} = $param{$field};
				} # end foreach field
				my @changes = $Paper->changes( \%changes );

				if (@changes) {
					if ($_ = $Paper->save(\%changes)) {
            $variable{error} .= $_;
            $log->error($_);
          } else {
            (new openprint::Log())->save({ Object=>$Paper, action=>'Edit', note=>join(',', @changes) } );
          }
				}
			} else {
				$log->error('Unknown mode in apply changes');
			} # end if
			sql::end_transaction( $dbh, $ac );
		} # end foreach Paper
	} elsif ( $param{btnFunction} ) {
		$log->error("Unknown function $param{btnFunction}");
	} # end if
  if ($param{brand}) {
    my $brand = openprint::StockBrand->find_one('name lc'=>lc$param{brand});
    $param{brand_id} = $brand->id() if $brand;
  }
  if ($param{finish}) {
    my $finish = openprint::StockFinish->find_one('name lc'=>lc$param{finish});
    $param{finish_id} = $finish->id() if $finish;
  }
  if ($param{colour}) {
    my $colour = openprint::StockColour->find_one('name lc'=>lc$param{colour});
    $param{colour_id} = $colour->id() if $colour;
  }
  if ($param{weight}) {
    my $weight = openprint::StockWeight->find_one('name lc'=>lc$param{weight});
    $param{weight_id} = $weight->id() if $weight;
  }
  _stocks();
} # end sub list

sub stock {

  my $Paper = openprint::Paper->find_one( id=>$param{stock_id} ) if $param{stock_id};
  if ( $param{btnFunction} ) {
    if ( $param{btnFunction} eq 'Delete' ) {
      if ( ! $Paper ) {
        $variable{error} .= 'No stock selected for delete.<br/>';
        $variable{Stock} = new openprint::Paper();
        return;
      }
      my $new = $Paper->next();
      $new = $Paper->previous() if $new == $Paper;
      $variable{error} = $Paper->delete();
      if (!$variable{error}) {
        $variable{information} .= 'Stock ' . $Paper->id() . ' has been deleted.';
        $Paper = $new;
        $param{stock_id} = $Paper->id();
        $variable{ExternalRedirect} = '/administrator/stock/stock.html?stock_id='.$$Paper{id};
      }

    } elsif ( $param{btnFunction} eq 'Copy' ) {
      if ( ! $Paper ) {
        $variable{error} .= "No stock selected for copy.<br/>";
        $variable{Stock} = new openprint::Paper();
        return;
      }
      $variable{information} .= 'Stock ' . $Paper->link_to( $Paper->id() ) . ' has been copied.';
      my $NewPaper = $Paper->copy();
      $NewPaper->save();
      #foreach my $Setting ( openprint::Equipment_Stock_Setting->find('stock_id'=>$Paper->id()) ) {
      #$Setting = $Setting->copy();
      #$Setting->save({'stock_id'=>$NewPaper->id()});
      #} # end foreach
      $Paper = $NewPaper;
      $param{stock_id} = $Paper->id();
      $variable{ExternalRedirect} = '/administrator/stock/stock.html?stock_id='.$$Paper{id};
    } elsif ( $param{btnFunction} eq 'Save' ) {

      $Paper = new openprint::Paper() if ! $Paper;
      my @changes = $Paper->changes( \%param );
      $Paper->owner_id( $param{ddmOwner} );
      $Paper->manufacturer( $param{txtManufacturer} ) if $param{txtManufacturer};
      $Paper->manufacturer_id( $param{ddmManufacturer} ) if ! $param{txtManufacturer};
      $param{ddmSupplier} = openprint::Supplier::get_or_create( $param{txtSupplier} ) if $param{txtSupplier} and ! $param{ddmSupplier};
      $Paper->supplier_id( $param{ddmSupplier} );
      $Paper->group( $param{txtGroup} ) if $param{txtGroup};
      $Paper->group_id( $param{Group} ) if ! $param{txtGroup};
      $Paper->brand( $param{txtBrand} ) if $param{txtBrand};
      $Paper->brand_id( $param{ddmBrand} ) if ! $param{txtBrand};
      $Paper->finish( $param{txtFinish} ) if $param{txtFinish};
      $Paper->finish_id( $param{ddmFinish} ) if ! $param{txtFinish};
      $Paper->colour( $param{txtColour} ) if $param{txtColour};
      $Paper->colour_id( $param{ddmColour} ) if ! $param{txtColour};
      $Paper->weight( $param{txtWeight} ) if $param{txtWeight};
      $Paper->weight_id( $param{ddmWeight} ) if ! $param{txtWeight};
      $Paper->quality( $param{txtQuality} ) if $param{txtQuality};
      $Paper->quality_id( $param{ddmQuality} ) if ! $param{txtQuality};
      $Paper->material( $param{material} );
      $Paper->material_id( $param{material_id} ) if $param{material_id};
      if ( $param{ddmPaperSize} ) {
        my ( $width, $height ) = split 'x', $param{ddmPaperSize};
        $Paper->width( $width );
        $Paper->height( $height );
      } else {
        $Paper->width( $param{width} );
        $Paper->height( $param{height} );
      } # end if

      $Paper->gsm( $param{gsm} );
      $Paper->basis_mweight( $param{basis_mweight} );
      $Paper->basis_width( $param{basis_width} );
      $Paper->basis_height( $param{basis_height} );
#$Paper->mweight( $param{mweight} );

      $Paper->calliper( $param{calliper} );
      $Paper->sheets_per_package( $param{sheets_per_package} );
      $Paper->full_packages( $param{full_packages} );
      $Paper->minimum_order( $param{minimum_order} );
      $Paper->available_to_order( $param{available_to_order} );
      $Paper->cuttable( $param{cuttable} );
      $Paper->doublesided( $param{doublesided} );
      $Paper->multipart( $param{multipart} );
      $Paper->perfecting( $param{perfecting} );
      $Paper->score_required( $param{score_required} );
      $Paper->die_score_required( $param{die_score_required} );
      $Paper->digital( $param{digital} );
      $Paper->bladecleaning( $param{bladecleaning} );
      $Paper->grade( $param{grade} );
      $Paper->type( $param{type} );
      $Paper->supplied( $param{supplied} );
      $Paper->grain_direction( $param{grain_direction} );
      $Paper->taxexempt1( $param{taxexempt1} );
      $Paper->taxexempt2( $param{taxexempt2} );
      $Paper->fsc_code( $param{fsc_code} );
      $Paper->inventory_number( $param{inventory_number} );
      $Paper->minimum_order( $param{minimum_order} );
      $Paper->full_packages( $param{full_packages} );
      $Paper->message( $param{message} );
      $Paper->user_type( $param{user_type} );

      $variable{error} .= $Paper->save();

      my @old_recommendations = $Paper->Recommendations();
      @{$$Paper{Recommendations}} = ();
      my %recs;
      my @ProjectTypes = openprint::ProjectType->find();
      foreach my $rec (@old_recommendations) {
        $recs{$$rec{projecttype_id}} = {} if ! $recs{$$rec{projecttype_id}};
        $recs{$$rec{projecttype_id}}{$$rec{presstype_id}} = $rec;
      }
      my @additions;
      my @removals;
      my @press_types = @{$dbh->selectall_arrayref(q{
      SELECT e.lngindex AS id, strname AS name
      FROM equipment_type_service_type t, tbl_equipment_type e
      WHERE t.equipment_type = e.lngindex AND t.service_type=?
      ORDER BY 2
      }, { Slice => {} }, 68)}; # Printing

      foreach my $Type ( @ProjectTypes ) {
        foreach my $press_type (@press_types) {
          my $rec = ($recs{$Type->id()} and $recs{$Type->id()}{$$press_type{id}}) ? $recs{$Type->id()}{$$press_type{id}} : new openprint::PaperRecommendation();
          if ($param{'chkPRF'.$Type->id().'-'.$$press_type{id}}) {
            $rec->set({
                paper_id=>$Paper->id(),
                projecttype_id=>$Type->id(), 
                presstype_id=>$$press_type{id},
                (visible=>($param{'chkPRFvisible'.$Type->id()} and $param{'chkPRFvisible'.$Type->id()} eq 'Y' ) ? 'Y' : 'N'),
              });
            push @{$$Paper{Recommendations}}, $rec;
            push @additions, $rec if !$rec->id();
          } elsif ($rec->id()) {
            push @removals;
            $rec->delete();
          }
        } # end foreach press_type
      } # end foreach project_type
      push @changes, "Recommendations added: " . join(',', map { $_->ProjectType()->name().' on '.$_->presstype() } @additions).'<br/>' if @additions;
      push @changes, "Recommendations removed: " . join(',', map { $_->ProjectType()->name().' on '.$_->presstype() } @removals).'<br/>' if @removals;
      if (@additions or @removals) {
        $Paper->save();
      }

      my $message = '';
# Save prices
      foreach my $Price ( $Paper->Prices(), new openprint::PaperPrice() ) {
        if (! $Price->paper_id()) {
          $Price->paper_id($Paper->id());
          $Price->pricelist_id($param{'pricelist_id-'});
          $Price->service('Material');
        }

        my $new_values = {
          equipment_id	=> $param{"equipment_id-$$Price{id}"},
          min				=> $param{"min-$$Price{id}"},
          max				=> $param{"max-$$Price{id}"},
          units			=> $param{"units-$$Price{id}"},
          cost			=> $param{"cost-$$Price{id}"},
          markup			=> $param{"markup-$$Price{id}"},
          price			=> $param{"price-$$Price{id}"},
          discountable	=> $param{"discountable-$$Price{id}"},
        };
        my @price_changes = $Price->changes( $new_values );
        if ( @price_changes ) {
          push @changes, ( 'Change price for ' .$Price->id_string() . ': ' .  join(', ', map { $_ } @price_changes ) );
          $variable{error} .= $Price->save( $new_values );
        } # end if Price has changed
      } # end foreach Price

      (new openprint::Log())->save({ object_type=>(ref $Paper), object_id=>$$Paper{id}, action=>($param{stock_id}?'Edited stock':'Saved stock'), note=>join('<br/>', @changes) });
      if ( ! $variable{error} ) {
        $variable{information} .= 'Stock ' . $Paper->link_to( $$Paper{id} ) . ' has been saved.';
        $variable{ExternalRedirect} = '/administrator/stock/stock.html?stock_id='.$$Paper{id};
      } # end if
    } elsif ( $param{btnFunction} eq 'Prev' ) {
      if ( ! $Paper ) {
        $variable{error} .= "No stock selected for previous.<br/>";
        $variable{Stock} = new openprint::Paper();
        return;
      }
      $Paper = $Paper->previous();
      $param{stock_id} = $Paper->id();
    } elsif ( $param{btnFunction} eq 'Next' ) {
      if ( ! $Paper ) {
        $variable{error} .= 'No stock selected for next.<br/>';
        $variable{Stock} = new openprint::Paper();
        return;
      }
      $Paper = $Paper->next();
      $param{stock_id} = $Paper->id();
    } # end if
  } elsif (!$Paper) {
    $Paper = new openprint::Paper();
    $openprint::log->debug(Data::Dumper::Dumper(\%param));
    $Paper->set(\%param) if %param;
    my $price = new openprint::PaperPrice();
    $price->set({cost=>$param{price}, price=>$param{price}, service=>'Material', Paper=>$Paper});
    $Paper->Prices([$price]);
  }

	$variable{Stock} = $Paper;
	$variable{stock_id} = $Paper->id();

$log->debug("Stock: " . $Paper->to_string() );
} # end sub stock

sub _prices {
	if ( $param{action} eq 'Delete' ) {
		my $PaperPrice = new openprint::PaperPrice( $param{price_id} );
		$PaperPrice->delete();
		(new openprint::Log())->save({action=>'Delete Price', Object=>$PaperPrice->Stock(), note=>$PaperPrice->id_string()});
	} elsif ( $param{action} eq 'Add' ) {
		my $PaperPrice = new openprint::PaperPrice( );
		$PaperPrice->paper_id( $param{stock_id} );
		$PaperPrice->pricelist_id( $param{pricelist_id} );
		$PaperPrice->save();
	} elsif ( $param{action} eq 'Copy' ) {
		my $PaperPrice = new openprint::PaperPrice( $param{price_id} );
		my $NewPrice = $PaperPrice->copy();
		$NewPrice->save();
	} # end if
} # end sub _prices

sub import_export {

	if ( $param{btnFunction} eq 'Export Stock' ) {
		my @header = ( 'ID', 'Owner','Manufacturer','Supplier', 'Group','Brand', 'Finish', 'Colour', 'Weight', 'Quality', 'MWeight', 'gsm','Calliper', 'Type','Width', 'Height', 'Basis Width','Basis Height', 'Grain Direction','DoubleSided?','Cuttable?','Multiple Parts?','Perfecting','Scoring Required?','Blade Cleaning Required?','Grade','Sheets Per Package','Supplied', 'Digital','Full Packages','Minimum Order','Inventory #','Material Type','Message', 'Recommendations');
		my @data;

		foreach my $Paper ( openprint::Paper->find( order=>'brand,finish,colour,weight,width,height', 
					columns=>'*,(SELECT name FROM StockBrands WHERE Stockbrands.id=brand_id) AS brand,(SELECT name FROM StockFinishes WHERE StockFinishes.id=finish_id) AS finish,(SELECT name FROM StockColours WHERE StockColours.id=colour_id) AS colour,(SELECT name FROM StockWeights WHERE StockWeights.id=weight_id) AS weight ') ) {
			next if ! $Paper->recommendations();

			push @data, $Paper->id(), $Paper->owner(), $Paper->manufacturer(), $Paper->Supplier()->name(), $Paper->group(), $Paper->brand(), $Paper->finish(), $Paper->colour(), $Paper->weight(), $Paper->quality(), 
			$Paper->mweight(), $Paper->gsm(), $Paper->calliper(), $Paper->type(), $Paper->width(), $Paper->height(), $Paper->basis_width(), $Paper->basis_height(), $Paper->grain_direction(), $Paper->doublesided(), $Paper->cuttable(), $Paper->multipart(), $Paper->perfecting(), $Paper->score_required(), $Paper->bladecleaning(), $openprint::Paper::grades{$Paper->grade()}, $Paper->sheets_per_package(), $Paper->supplied(), $Paper->digital(), $Paper->full_packages(), $Paper->minimum_order(), $Paper->inventory_number(), $Paper->material(), $Paper->message();
			push @data, join(',', map { new openprint::ProjectType($_)->name() } $Paper->recommendations());
		} # end foreach
		misc::export_csv( $r, $log, \%variable, 'stock.csv', \@header, \@data );

	} elsif ( $param{btnFunction} eq 'Import Stock' ) {

		my $error = '';
		if ( $param{fileStock} ne '' ) {
# get the upload.
			my $upload = $r->upload( 'fileStock' );
			my $io = $upload->io();
			$_ = <$io>;

			my $ac = sql::start_transaction( $dbh );
			my %project_types = map { $_->name(), $_ } openprint::ProjectType->find();
			my %owners = map { $_->name(), $_->id() } openprint::Company->find();
			my %papers = map { $_->id(), $_ } openprint::Paper->find();
			my %reverse_grades = reverse %openprint::Paper::grades;

			my $csv = Text::CSV_XS->new();
			my $line_count = 0;
			my $import_count =0;
			while ( <$io> ) {
				my $status = $csv->parse($_);
				my ( $paper_id, $owner, $manufacturer, $supplier, $group, $brand, $finish, $colour, $weight, $quality, $mweight, $gsm, $calliper, $type, $width, $height, $basis_width, $basis_height, $grain_direction, $double_sided, $cuttable, $multipart, $perfecting, $scoring, $bladecleaning, $grade, $spp, $supplied, $digital, $full_packages, $minimum_order, $inventory_number, $material, $message, $recommendations ) = misc::trim($csv->fields());
				$line_count += 1;

				next if ! $paper_id;

				my @recommendations = ();
				foreach my $ProjectType_name ( split(',',$recommendations ) ) {
					next if ! $ProjectType_name;
					my $ProjectType;
					if ( $project_types{$ProjectType_name} ) {
						$ProjectType = $project_types{$ProjectType_name};
					} else {
						$ProjectType = openprint::ProjectType->find_one('name lc'=>lc openprint::ProjectType->transform('name',$ProjectType_name));
					} # end if
					if ( ! $ProjectType ) {
						$ProjectType = new openprint::ProjectType();
						$ProjectType->save({ name=>$ProjectType_name });
						$project_types{$ProjectType_name} = $ProjectType;
					} # end if
					push @recommendations, $ProjectType->id();
				} # end foreach

				my $Paper = $papers{$paper_id} ? $papers{$paper_id} : new openprint::Paper();
				$Paper->owner_id( $owners{$owner} ? $owners{$owner} : $session{company_id} );
				$Paper->manufacturer( $manufacturer );
				if ( $supplier ) {
				my $supplier_id = openprint::Supplier::get_or_create( $supplier );
				$Paper->supplier_id( $supplier_id );
				}
				$Paper->group( $group );
				$Paper->brand( $brand );
				$Paper->finish( $finish );
				$Paper->colour( $colour );
				$Paper->weight( $weight );
				$Paper->quality( $quality );
				$Paper->mweight( $mweight );
				$Paper->gsm( $gsm );
				$Paper->calliper( $calliper );
				$Paper->type( $type );
				$Paper->width( $width );
				$Paper->height( $height );
				$Paper->basis_width( $basis_width );
				$Paper->basis_height( $basis_height );
				$Paper->grain_direction( $grain_direction );
				$Paper->perfecting( $perfecting );
				$Paper->score_required( $scoring );
				$Paper->cuttable( $cuttable );
				$Paper->doublesided( $double_sided );
				$Paper->multipart( $multipart );
				$Paper->bladecleaning( $bladecleaning );
				$Paper->grade( $reverse_grades{$grade} );
				$Paper->supplied( $supplied );
				$Paper->digital( $digital );
				$Paper->full_packages( $full_packages );
				$Paper->sheets_per_package( $spp );
				$Paper->minimum_order( $minimum_order );
				$Paper->inventory_number( $inventory_number );
				$Paper->material( $material );
				$Paper->message( $message );
				$Paper->recommendations( @recommendations );
				my $rc = $Paper->save();	
				if ( $rc ) {
					$error .= "Error adding Stock: $rc<br>";
					$error .= Data::Dumper::Dumper( $Paper );
					last;
				} # end if
				$import_count += 1;
		
			} # end while io
			sql::end_transaction( $dbh, $ac );
			$variable{information} = "$line_count lines processed, $import_count stocks successfully imported.<br/>";
		} else {
			$error .= "No file given.<br>";
		} # end if
		if ( $error ) {
			$variable{error} = $error;
		} # end if
	} # end if

} # end sub import_export

sub inventory {

	ssi::get_start_end_dates( $log, $dbh, \%variable,
			$param{ddmStartYear},
			$param{ddmStartMonth},
			$param{ddmStartDay},
			$param{ddmEndYear},
			$param{ddmEndMonth},
			$param{ddmEndDay} );

} # end sub inventory

sub usage {

	ssi::get_start_end_dates( $log, $dbh, \%variable,
			$param{ddmStartYear},
			$param{ddmStartMonth},
			$param{ddmStartDay},
			$param{ddmEndYear},
			$param{ddmEndMonth},
			$param{ddmEndDay} );


	if ( $param{ddmStockGroup} ) {
		@{$variable{Groups}} = ( $param{ddmStockGroup} );
	} else {
		@{$variable{Groups}} = sql::execute( $log, $dbh, "SELECT DISTINCT Name FROM Paper ORDER BY name" );
	} # end if
	if ( $param{ddmStockBrand} ) {
		@{$variable{Brands}} = ( $param{ddmStockBrand} );
	} else {
		@{$variable{Brands}} = sql::execute( $log, $dbh, "SELECT DISTINCT Name FROM Paper ORDER BY name" );
	} # end if
	if ( $param{ddmStockFinish} ) {
		@{$variable{Finishes}} = ( $param{ddmStockFinish} );
	} else {
		@{$variable{Finishes}} = sql::execute( $log, $dbh, "SELECT DISTINCT Finish FROM Paper ORDER BY Finish" );
	} # end if
	if ( $param{ddmStockColour} ) {
		@{$variable{Colours}} = ( $param{ddmStockColour} );
	} else {
		@{$variable{Colours}} = sql::execute( $log, $dbh, "SELECT DISTINCT Colour FROM Paper ORDER BY Colour" );
	} # end if
	if ( $param{ddmStockWeight} ) {
		@{$variable{Weights}} = ( $param{ddmStockWeight} );
	} else {
		@{$variable{Weights}} = sql::execute( $log, $dbh, "SELECT DISTINCT calliper FROM Paper ORDER BY Calliper" );
	} # end if

	if ( $param{ddmCustomer} ) {
		$variable{ddmCustomer} = "<option value=\"".$param{ddmCustomer}."\" selected></option>";
	} # end if


	my $query = "SELECT Projects.lngProjectIndex,lngDocketNumber, intQuantityIndex, (SELECT name FROM Companies WHERE id=Company_id) FROM Projects, Order_Contents WHERE Projects.Index=lngProjectIndex AND strStatus IN ( 'Ordered','Complete','Printed','Proofs Out','Approved','In Prepress' )\n";
	$query .= "AND due_date BETWEEN '$variable{StartDate}' AND '$variable{EndDate}' ";
	if ( $param{ddmCustomer} ) {
		$query .= "AND Projects.CompanyIndex = $param{ddmCustomer}\n";
	} # end if
	$query .= "ORDER BY due_date, Projects.Index";
	my @projects = sql::execute( $log, $dbh, $query );

	if ( 1 ) {
		while ( my ( $project_index, $docket_number, $qty_index, $company ) = splice @projects, 0, 4 ) {
			my $Project = new openprint::Project( $project_index );
			foreach my $signature_service_index ( $Project->signatures() ) {
				my $specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
				if ( ! sets::isin( $$specs{ddmStockBrand}, @{$variable{Brands}} ) ) {
					next;
				} # end if
				if ( ! sets::isin( $$specs{ddmStockFinish}, @{$variable{Finishes}} ) ) {
					next;
				} # end if
				if ( ! sets::isin( $$specs{ddmStockColour}, @{$variable{Colours}} ) ) {
					next;
				} # end if
				if ( ! sets::isin( $$specs{ddmStockWeight}, @{$variable{Weights}} ) ) {
					next;
				} # end if
				my %paper;
				@paper{'index','mweight'} = sql::execute( $log, $dbh, "SELECT lngIndex,MWeight FROM Paper\n"
						. "WHERE name='$$specs{ddmStockBrand}'\n"
						. "AND finish='$$specs{ddmStockFinish}'\n"
						. "AND colour='$$specs{ddmStockColour}'\n"
						. "AND calliper=$$specs{ddmStockWeight}\n"
						. "AND width=$$specs{hdnSheetSizeWidth}\n"
						. "AND height=$$specs{hdnSheetSizeHeight}\n"
						);
				if ( $paper{index} ) {
					my $price = openprint::paper::get_price( $log, $dbh, \%variable, \%paper, @$specs{'ddmPress','hdnGrossSheetCount'.$qty_index} );
					push @{$variable{'Results'.$$specs{ddmStockBrand}}}, $company,$project_index,$docket_number, @$specs{'hdnGrossSheetCount'.$qty_index,'UsedSheetQuantity'},
						 sprintf( '$%.2f', $$specs{'hdnGrossSheetCount'.$qty_index}*$$price{Price} ),
						 sprintf( '$%.2f', $$specs{UsedSheetQuantity}*$$price{Price} );
				} # end if
			} # end foreach
		} # end while
	}

} # end sub usage

sub filters {
} # end sub filters

sub _filters_load {
} # end sub _filters_load

sub _filters_save {
} # end sub _filters_save

sub _price_tr {
	$variable{Pricelist} = new openprint::Pricelist( $param{pricelist_id} );
	$variable{Stock} = new openprint::Paper( $param{stock_id} );
	my $price = $variable{Price} = new openprint::PaperPrice( $param{price_id} );
	my @Equipment = openprint::Equipment->find('order'=>'lower(strid)');
	$variable{Equipment} = \@Equipment;
  $variable{company_ids} = [ map { $_->id(), $_->name() } openprint::Company->find( supplier=>'Y') ];
	if ( $param{action} eq 'Add' ) {
		$price->set({
			pricelist_id	=>	$param{pricelist_id},
			stock_id		=>	$param{stock_id},
			service		=>	$param{service},
		});
    $price->save() if $param{stock_id};

	} elsif ( $param{action} eq 'Delete' ) {
		$variable{error} = $variable{Price}->delete();
		$variable{Price} = new openprint::PaperPrice();
	} elsif ( $param{action} eq 'Copy' ) {
		$variable{Price} = $variable{Price}->copy();
		$variable{error} .= $variable{Price}->save( \%param );
	} # end if

} # end sub _price_tr

sub _stock { 
} # end sub _stock

sub _popup {
	@{$variable{Stocks}} = openprint::Paper->find(id=>$param{stock_ids});
	$variable{Stock} = $variable{Stocks}[0] if @{$variable{Stocks}};
} # end sub _popup

sub _popup_price {
} # end sub _popup_price

1;
__END__
