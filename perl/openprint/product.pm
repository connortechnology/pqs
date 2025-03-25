use strict;
package openprint::product;

use openprint ();
use vars qw($r $log $dbh %variable %param %session);
*r = \$openprint::r;
*variable = \%openprint::variable;
*param = \%openprint::param;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*session = \%openprint::session;

require openprint::Product;
require openprint::Product_Category;
require openprint::Product_Specification;
require openprint::logs;
require sql;
require openprint::Supplier;
require openprint::Company;

sub view {
	$param{product_id} = openprint::Product->transform( 'id', $param{product_id} );
	my $Product = $variable{Product} = new openprint::Product( $param{product_id} );
	if ( $param{product_id} and ! $Product->id() ) {
		$variable{error} .= "Product $param{product_id} not found.<br/>";
	} # end if
	if ( $param{btnFunction} eq 'Delete' ) {
		if ( ! ( $variable{error} .= $Product->delete() ) ) {
			$variable{information} .= 'Product deleted successfully.';
			$Product = $variable{Product} = $Product->next();
		} # end if
	}
} # end sub view

sub edit {
	my $Product = $variable{Product} = new openprint::Product( $param{product_id} );

  if ($param{btnFunction}) {
    if ( $param{btnFunction} eq 'Save' ) {
      if ( (! $param{product_id}) and openprint::Product->find( 'name lc' => lc openprint::Product->transform('name',$param{name}) ) ) {
        $variable{error} = "A product with name $param{name} already exists.	Please choose another name.";
        return;
      } # end if
      foreach my $field ( 'category', 'manufacturer' ) {
        if ( $param{$field} ) {
          delete $param{$field.'_id'};
        } else {
          delete $param{$field};
        } # end if
      } # end foreach
      $param{supplier_id} = openprint::Supplier::get_or_create( $param{supplier} ) if $param{supplier} and ! $param{supplier_id};
      $Product->supplier_id( $param{supplier_id} );

      my @changes = $Product->changes( \%param );
      if ( @changes ) {
        $variable{error} = $Product->save( \%param );
      }
      if ( $param{product_id} ) {
        # Save the prices
        _prices();
        my @spec_changes = openprint::Object_Specification::save_changes( $Product, \%param );
        push @changes, 'specification changes: ' . join(', ', @spec_changes ) if @spec_changes;

      } # end if
      ( new openprint::Log())->save({Object=>$Product, action=>'Edit', note=>join('<br/>', @changes ) } ) if @changes;
      $param{btnFunction} = '';
      $variable{ExternalRedirect} = '/product/edit.html?product_id='.$Product->id();
    } elsif ( $param{btnFunction} eq 'Copy' ) {
      my $NewProduct = $Product->copy();
      $NewProduct->save();

      (new openprint::Log())->save({action=>'Copy Product', note=>'New Product ID: ' . $NewProduct->id() . ' Name: ' . $NewProduct->name(), Object=>$Product });
      (new openprint::Log())->save({action=>'Copy Product', note=>'Original Product ID: ' . $param{product_id} . ' Name: ' . $Product->name(), Object=>$NewProduct });

      foreach my $Price ( openprint::ProductPrice->find( product_id => $param{product_id} ) ) {
        $$Price{product_id} = $NewProduct->id();
        $$Price{id} = undef;
        $Price->save();
      } # end foreach
      foreach ( $NewProduct->Specifications() ) {
        $_->save({object_id => $$NewProduct{id} });
      }
      $Product = $NewProduct;

    } elsif ( $param{btnFunction} eq 'Delete' ) {
      if ( ! ( $variable{error} .= $Product->delete() ) ) {
        $variable{information} .= 'Product deleted successfully.';
        $Product = $Product->next();
      } # end if
    } elsif ( $param{btnFunction} eq '>>' ) {
      $Product = $Product->next();
    } elsif ( $param{btnFunction} eq '<<' ) {
      $Product = $Product->previous();
    } elsif ( $param{btnFunction} eq 'Export Definitions' ) {
      my @header = ( 'Name', 'Description','Category', 'Tax Exempt 1','Tax Exempt2', 'Sort Order');
      my @data = sql::execute( $log, $dbh, 'SELECT name, description, (SELECT name from product_categories where id=category_id), taxexempt1, taxexempt2, sort FROM Products ORDER BY sort' );
      misc::export_csv( $r, $log, \%variable, 'Products.csv', \@header, \@data );
    } elsif ( $param{btnFunction} eq 'Import Definitions' ) {
      my $error = '';
      if ( $param{fileImport} ) {
        my $upload = $r->upload( 'fileImport' );
        my $io = $upload->io();
        $_ = <$io>;

        my $csv = Text::CSV_XS->new();
        my $ac = sql::start_transaction( $dbh );
        my %categories = map { $_->name(), $_ } openprint::Product_Category->find();
        my %products = map { $_->name(), $_ } openprint::Product->find();

        while ( <$io> ) {
          my $status = $csv->parse($_);
          my ( $name, $description, $category, $taxexempt1, $taxexempt2, $sort ) = misc::trim( $csv->fields() );
          next if ! $name;
          if ( $category and ! $categories{$category} ) {
            $categories{$category} = new openprint::Product_Category();
            $categories{$category}->name( $category );
            $categories{$category}->save();
          } # end if
          my %sql = (
            'name'			=>	$name,
            'description'	=>	$description,
            'category_id'	=>	$category ? $categories{$category}->id() : undef,
            'taxexempt1'	=>	$taxexempt1,
            'taxexempt2'	=>	$taxexempt2,
            'sort'			=>	$sort,
          );
          my $Product = $products{$name} ? $products{$name} : new openprint::Product();
          $error .= $Product->save( \%sql );
        } # end while
        sql::end_transaction( $dbh, $ac );
      } else {
        $log->warn( "No file given to upload." );
      } # end if
      if ( $error ne '' ) {
        return misc::error( $log, $dbh, \%variable, 'Import errors.', $error );
      } # end if
    } elsif ( $param{btnFunction} eq 'Export Specifications' ) {
      my @header = ( 'Product', 'Name','Value');
      my @data;
      foreach my $Product ( openprint::Product->find() ) {
        foreach my $Spec ( $Product->Specifications() ) {
          push @data, $Product->name(), $Spec->name(), $Spec->value();
        } # end foreach
      } # end foreach
      misc::export_csv( $r, $log, \%variable, 'ProductSpecifications.csv', \@header, \@data );
    } elsif ( $param{btnFunction} eq 'Import Specifications' ) {
      my $error = '';
      if ( $param{fileImport} ) {
        my $upload = $r->upload( 'fileImport' );
        my $io = $upload->io();
        $_ = <$io>;

        my $csv = Text::CSV_XS->new();
        my $ac = sql::start_transaction( $dbh );
        my %products = map { $_->name(), $_ } openprint::Product->find();
        # Clear Specifications
        foreach my $P ( keys %products ) {
          $products{$P}{Specifications} = ();
        } # end foreach

        while ( <$io> ) {
          my $status = $csv->parse($_);
          my ( $product, $name, $value ) = misc::trim( $csv->fields() );
          next if ! $product;
          $products{$product}{Specifications}{$name} = $value;
        } # end while

        foreach my $P ( keys %products ) {
          $error .= $products{$P}->save();
        } # end foreach
        sql::end_transaction( $dbh, $ac );
      } # end if
    } # end if
  } #end if btnFunction
    $variable{Product} = $Product;
} # end sub edit

sub categories {
	$variable{ProductCategory} = new openprint::Product_Category( $param{id} );
	if ( $param{btnFunction} eq 'Save' ) {
	} elsif ( $param{btnFunction} eq 'Delete' ) {
	} # end if
	_categories();
} # end sub categories

sub _categories {
	ssi::save_params( '/product/categories.html', ( 'category_id' ) );
}

sub _prices {
	my $Product = new openprint::Product( $param{product_id} );
	if ( $param{btnFunction} eq 'Save' ) {
		my @changes;
		my $ac = sql::start_transaction( $dbh );
		$dbh->do( 'LOCK TABLE Product_Prices IN EXCLUSIVE MODE' ) or $log->error( DBI->errstr );
		foreach my $Pricelist ( openprint::Pricelist->find() ) {
			foreach my $Price ( openprint::ProductPrice->find( product_id => $$Product{id}, pricelist_id => $$Pricelist{id} ) ) {
				my %changes = (
						min				=>	$param{'min-'.$Price->id()},
						max				=>	$param{'max-'.$Price->id()},
						units			=>	$param{'units-'.$Price->id()},
						cost			=>	$param{'cost-'.$Price->id()},
						markup			=>	$param{'markup-'.$Price->id()},
						price			=>	$param{'price-'.$Price->id()},
						discountable	=>	$param{'discount-'.$Price->id()},
				);
				my @price_changes = $Price->changes(\%changes);
$log->debug("Price changes (@price_changes)" . @price_changes );
				if ( @price_changes ) {
					$variable{error} .= $Price->save(\%changes);
					push @changes, 'price for pricelist ' . $$Pricelist{name} . ' changed: ' . join(',',@price_changes);
				} # end if
			} # end foreach Price
		} # end foreach Pricelist
		sql::end_transaction( $dbh, $ac );
		(new openprint::Log())->save({Object=>$Product, action=>'Edit', note=>join('<br/>', @changes)}) if @changes;
	} # end if
} # end sub _prices

sub search {
	_search();
	if ( ( ! $session{'/product/search.html?lastupdated'} ) or ( time - $session{'/product/search.html?lastupdated'} ) > ( 12*60*60 ) ) {
		ssi::setup_date_select( '/product/search.html', 'starting_on_start', 0 );
		ssi::setup_date_select( '/product/search.html', 'starting_on_end', '' );
	} # end if
} # end sub search
sub _search {
	if ( ! $param{btnFunction} ) {
		ssi::save_params( '/product/search.html', ( 
				'starting_on_start_year','starting_on_start_month','starting_on_start_day',
				'starting_on_end_year','starting_on_end_month','starting_on_end_day',
				'user_id', 'category_id', 'country_id', 'state_id', 'city_id' ) );
	} # end if
} # end sub _history

sub _prices_table_body {
	my $Price = new openprint::ProductPrice( $param{price_id} );

	my $Product = $variable{Product} = openprint::Product->find_one(id=>$param{product_id} );
	$variable{Pricelist} =$param{pricelist_id} ? openprint::Pricelist->find_one(id=>$param{pricelist_id} ) : $Price->Pricelist();

	#$variable{company_ids} = [ map { $_->id(), $_->name() } openprint::Company->find( supplier=>'Y', order=>'lower(name)' ) ];
	if ( $param{action} eq 'add' ) {
		my $Price = new openprint::ProductPrice();
		$variable{error} .= $Price->save({ pricelist_id=>$param{pricelist_id}, product_id=>$param{product_id} });
		(new openprint::Log())->save({Object=>$Product, action=>'Add Price' }) if ! $variable{error};
	
	} elsif ( $param{action} eq 'copy' ) {
		$Price = $Price->copy();
		$variable{error} .= $Price->save();
		(new openprint::Log())->save({Object=>$Product, action=>'Copy Price', note=>$Price->to_string() }) if ! $variable{error};
	} elsif ( $param{action} eq 'delete' ) {
		$variable{error} .= $Price->delete();
		(new openprint::Log())->save({Object=>$Product, action=>'Delete Price', note=>$Price->to_string() }) if ! $variable{error};
	} # end if
}

sub category_view {
  $param{category_id} = openprint::Product_Category->transform(id=>$param{category_id});

	my $Category = $variable{Category} = new openprint::Product_Category( $param{category_id} );
  if ( $param{btnFunction} and $Category->can_edit() ) {
    if ( $param{btnFunction} eq 'Destroy' ) {
      $variable{error} .= $Category->destroy();
      if ( ! $variable{error} ) {
        $variable{ExternalRedirect} = '/product/categories.html';
      }
    } elsif ( $param{btnFunction} eq 'Delete' ) {
      $variable{error} .= $Category->delete();
      if ( ! $variable{error} ) {
        $variable{ExternalRedirect} = '/product/categories.html';
      }
    } # end if
  } # end if
}

sub category_edit {
	my $Category = $variable{Category} = new openprint::Product_Category($param{category_id});
	return if ! $param{btnFunction};

	if ( $param{btnFunction} eq 'Save' ) {
    $param{parent_ids} = $openprint::Product_Category::defaults{parent_ids} if ! exists $param{parent_ids};
		my @changes = $Category->changes(\%param);
		if ( @changes ) {
			$variable{error} = $Category->save(\%param);
		}
		if ( !$variable{error} ) {
			my @spec_changes = openprint::Object_Specification::save_changes( $Category, \%param );
			push @changes, 'specification changes: ' . join(', ', @spec_changes ) if @spec_changes;
			(new openprint::Log())->save({Object=>$Category, action=>'Edit', note=>join('<br/>', @changes) });
			$variable{ExternalRedirect} = '/product/categories.html' if ! $variable{error};
		}
	} elsif ( $param{btnFunction} eq 'Copy' ) {
		my $New = $Category->copy();
		$New->save();

		(new openprint::Log())->save({action=>'Copy', note=>'New ID: ' . $New->id() . ' Name: ' . $New->name(), Object=>$Category });
		(new openprint::Log())->save({action=>'Copy', note=>'Original ID: ' . $param{category_id} . ' Name: ' . $Category->name(), Object=>$New });

		foreach ( $New->Specifications() ) {
			$_->save({object_id => $$New{id} });
		}
		$Category = $New;

	} elsif ( $param{btnFunction} eq 'Destroy' ) {
		$variable{error} .= $Category->destroy();
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/product/categories.html';
		}
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		$variable{error} .= $Category->delete();
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/product/categories.html';
		}
	} # end if
} # end sub category

sub _category_view_products {
	my $Category = $variable{Category} = new openprint::Product_Category( $param{category_id} );
	my @Products = openprint::Product->find( category_id=>$Category->id() );
	my @product_ids = map { $$_{id} } @Products;
	@{$variable{Specifications}} = map { $param{"spec_filter-$$_{name}"} ? $$_{name} : () } openprint::Object_Specification->find( object_type => 'openprint::Product', object_id=>\@product_ids );
$log->debug("specification filters: ".join(',', @{$variable{Specifications}}));
	if ( $param{quantity} ) {
		@{$variable{Quantities}} = $param{quantity};
	} else {
		my @Prices = openprint::ProductPrice->find( product_id=> \@product_ids );
		@{$variable{Quantities}} = sort { $a <=> $b } sets::union( map { $_->min() == $_->max() ? $_->min() : () } @Prices );
	}
}

sub index {
}

1;
__END__
