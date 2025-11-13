use strict;
package openprint::Product;
our @ISA = qw( openprint::Object );

require openprint::Manufacturer;
require openprint::Product_Category;
require openprint::ProductPrice;
require openprint::Log;
require sql;

use vars qw( $log $dbh $debug $table $serial %fields %find_fields %defaults %transforms );
$debug = 1;
$table = 'tbl_products';
$serial = 'tbl_products_id_seq';

%fields = (
	id				=>	'id',
	name			=>	'name',
	description		=>	'description',
	weight			=>	'weight',
	taxexempt1		=>	'tax_exempt1',
	taxexempt2		=>	'tax_exempt2',
	taxexempt3		=>	'tax_exempt3',
	sort			=>	'sort',
	category_id		=>	'category_id',
	category		=>	undef,
	project_id		=>	'project',
	deleted			=>	'deleted',
	owner_id		=>	'owner_id',
	created_on		=>	'created_on',
	album_id		=>	'album_id',
	manufacturer_id	=>	'manufacturer_id',
	manufacturer	=>	undef,
	supplier_id	=>	'supplier_id',
	supplier	=>	undef,
  minimum_qty => 'minimum_qty',
  maximum_qty => 'maximum_qty',
  part_number => 'part_number',
  increment   => 'increment',
  units       => 'units',
  vendor      => 'vendor',
  notes       => 'notes',
  details     => 'details',
  active      => 'active',
  expiry      => 'expiry',
  product_group => 'product_group',
  group_option => 'group_option',
  mediawide     => 'mediawide',
  lead_time   => 'lead_time',
  kit         => 'kit',
  showprice   => 'showprice',
  delivery_days =>  'delivery_days',
  file_upload => 'file_upload',
  pdftemplate =>  'pdftemplate',
);

%find_fields = (
	specification_name =>	q`(SELECT name FROM Object_Specifications WHERE object_id=products.id and object_type_id=(SELECT id FROM object_types WHERE name='openprint::Product'))`
);

%transforms = (
  id			=>	[ 's/\D//g', '<2147483647' ],
  name		=> [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
  description => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);

%defaults = (
	weight			=>	undef,
	taxexempt1		=>	q`'N'`,
	taxexempt2		=>	q`'N'`,
	sort			=>	undef,
	category_id		=>	undef,
	project_id		=>	undef,
	owner_id		=>	q`$session{company_id}`,
	deleted			=>	0,
	created_on		=>	q`'NOW()'`,
	album_id		=>	undef,
	manufacturer_id	=>	undef,
	supplier_id		=>	undef,
);

sub destroy {
	my $error = '';
	my $ac = sql::start_transaction( $openprint::dbh );
	foreach my $Price ( openprint::ProductPrice->find( 'product_id' => $_[0]{id}, 'deleted'=>[0,1] ) ) {
		$error .= $Price->delete();
	} # end foreach

	sql::execute( undef, undef, q{DELETE FROM Product_Specifications WHERE product_id=?}, $_[0]{id} );
	sql::execute( undef, undef, q{DELETE FROM Products WHERE id=?}, $_[0]{id} );
	sql::end_transaction( $openprint::dbh, $ac );
	
	# Add record to audit log - action "Delete Product".
	(new openprint::Log())->save({'action'=>'Delete Product', 'note'=> "Product ID: $_[0]{id} Name: $_[0]{name}"});
	return $error;
} # end sub destroy

sub copy {
	my $self = shift;
	my $Product = new openprint::Product( );
	@$Product{keys %fields} = @$self{keys %fields};
	$$Product{name} = 'Copy of '.$$Product{name};
	delete $$Product{id};
	delete $$Product{album_id};
	@{$$Product{Specifications}} = $self->Specifications();
	foreach ( @{$$Product{Specifications}} ) {
		$_->set({ id=>undef, object_id=>undef });
	}
	return $Product;
} # end sub copy

sub prices {
	if ( ! exists $_[0]{Prices} ) {
		@{$_[0]{Prices}} = openprint::ProductPrice->find( product_id=>$_[0]{id}, order=>'min NULLS FIRST' );
	} # end if
	return @{$_[0]{Prices}};
} # end sub prices

sub Prices {
	return $_[0]->prices();
} # end sub Prices

sub category {
	if ( @_ > 1 ) {
		my $Category = openprint::Product_Category->find_one('name lc'=>lc openprint::Product_Category->transform('name',$_[1]));
		if ( ! $Category ) {
			$Category = new openprint::Product_Category();
			$Category->save({name=>$_[1]});
		} # end if
		$_[0]{category_id} = $Category->id();
		$_[0]{category} = $Category->name();
	} elsif ( ( ! defined $_[0]{category} ) and $_[0]{category_id} ) {
		$_[0]{category} = $_[0]->Category()->name();
	} # end if
	return $_[0]{category};
} # end sub category

sub Category {
	return new openprint::Product_Category( $_[0]{category_id} );
} # end sub Category

sub get_price {
	my ( $self, $qty, $options ) = @_;

	$$options{pricelist_id} = $openprint::Pricelist->id() if ! $$options{pricelist_id} and $openprint::Pricelist;

	my %price = openprint::pricing::get_best_price_object( $openprint::session{company_id}, $$self{id}, $$options{pricelist_id}, 'openprint::product_priceset', $qty, undef );
	#if ( ! %price ) {
#$log->debug("Looking for a price $qty");
		##foreach my $Price ( openprint::ProductPrice->find('product_id'=>$$self{id},'pricelist_id'=>$list_id,'order'=>'min desc NULLS FIRST') ) {
#$log->debug("Looking at $$Price{min}");
			#next if $$Price{min} > $qty;
			#next if $$Price{max} and ( $$Price{max} < $qty );
			#ireturn $
		#} # end foreach Price
	#} # end if
	my $Pricelist = new openprint::Pricelist( $$options{pricelist_id} );
	$price{currency_id} = $Pricelist->currency_id();
	openprint::Currency::convert( \%price );
	return %price;
} # end sub get_price

sub next {
	my $self = shift;
	my ( $id ) = sql::execute( undef, undef, q{SELECT id FROM Products WHERE name >= (SELECT name FROM Products WHERE id=?) ORDER BY lower(name) LIMIT 1}, $$self{id} );
	$id = $$self{id} if ! $id;
	
	return new openprint::Product( $id );
} # end sub next 
sub previous {
	my $self = shift;
	my ( $id ) = sql::execute( undef, undef, q{SELECT id FROM Products WHERE name < (SELECT name FROM Products WHERE Id=?) ORDER BY name DESC LIMIT 1}, $$self{id} );
	$id = $$self{id} if ! $id;
	
	return new openprint::Product( $id );
} # end sub previous

sub Photos {
    if ( ! $_[0]{album_id} ) {
        return ();
    } # end if
    return $_[0]->Album()->Photos( );
} # end sub Photos

sub Album {
	my $Album = new openprint::Photo_Album( $_[0]{album_id} );
	if ( ! $Album->id() ) {
		$Album->name('Photos for product '.$_[0]{name});
	} # end if
    return $Album;
} # end sub Album

sub thumbnail_id {
	return $_[0]->Album()->thumbnail_id();
} # end sub thumbnail_id

sub thumbnail_html {
	my $self = shift;
    if ( ! $$self{thumbnail_html} ) {
        my $Album = new openprint::Photo_Album( $$self{album_id} );
        my $Asset;
		if ( $Album and $$Album{id} ) {
			$Asset = $Album->Thumbnail();
		} else {
			$openprint::log->debug("No Album for Product $$self{id} $$self{name}");
		} # end if
		if ( $Asset and $$Asset{id} ) {
			$$self{thumbnail_html} = sprintf('<a href="/product/view.html?product_id=%1$d" class="thumbnail"><img src="%2$s" alt="%3$s" title="%3$s" /></a>',
					$$self{id}, $Asset->sized_url('thumbnail'), $$self{name} );
		} else {
			$openprint::log->debug("No Asset for Product $$self{id} $$self{name}");
		} # end if
    } # end if
    return $$self{thumbnail_html};
} # end sub thumbnail_html

sub upload {
    my $self = shift;
    my $Album = $self->Album();
    if ( ! $Album->id() ) {
      $Album->save({ 'Images for product: ' . $$self{name} });
      $self->save({album_id=>$Album->id()});
    } # end if
    return $Album->upload( @_ );
} # end sub upload

sub can_edit {
	return 1 if $openprint::session{user_type} eq 'A';

    #if ( $_[0]{id} and $openprint::session{user_type} eq 'A' ) {
        #return 1;
    #} # end if
    return 0;
} # end sub can_edit

sub manufacturer {
    if ( defined $_[1] ) {
        $_[1] = openprint::Manufacturer->transform( 'name', $_[1] );
		my $Manufacturer = openprint::Manufacturer->find_one('name lc'=> lc $_[1] );
		if ( ! $Manufacturer ) {
			$Manufacturer = new openprint::Manufacturer();
			$Manufacturer->save({name=>$_[1]});
		} # end if
		@{$_[0]}{'manufacturer_id','manufacturer'} = @$Manufacturer{'id','name'};
    } elsif ( $_[0]{manufacturer_id} and ! $_[0]{manufacturer} ) {
        $_[0]{manufacturer} = new openprint::Manufacturer( $_[0]{manufacturer_id} )->name();
    } # end if
    return $_[0]{manufacturer};
} # end sub manufacturer

sub Supplier {
	return new openprint::Company( $_[0]{supplier_id} );
} # end sub Supplier

sub link_to {
	return sprintf('<a href="/product/view.html?product_id=%d">%s</a>', $_[0]{id}, ( @_ > 1 ? $_[1] : $_[0]{name} ) );
}

sub Specifications {
  return openprint::Product_Specification->find({product_id=>$_[0]{id}});
} # end sub Specifications

sub specifications {
  my $self = shift;
  if ( ! exists $$self{'Specifications'} ) {
    $_ = q{SELECT name, value FROM Product_Specifications WHERE product_id=?};
    %{$$self{'Specifications'}} = sql::execute( $log, $dbh, $_, $$self{'id'});
  } # end if
  return $$self{'Specifications'};
} # end sub specifications

sub specification {
  my $self = shift;
  my $spec = shift;
  if ( ! exists $$self{'Specifications'} ) {
    $_ = q{SELECT name, value FROM Product_Specifications WHERE product_id=?};
    %{$$self{'Specifications'}} = sql::execute( $log, $dbh, $_, $$self{'id'});
  } # end if
  return $$self{'Specifications'}{$spec};
} # end sub

sub add_specification {
  my $self = shift;
  my $spec = shift;
  if ( ! exists $$self{'Specifications'} ) {
    $_ = q{SELECT name, value FROM Product_Specifications WHERE product_id=?};
    %{$$self{'Specifications'}} = sql::execute( $log, $dbh, $_, $$self{'id'});
  } # end if
  return $$self{'Specifications'}{$spec} = shift;
} # end sub add_specification
sub del_specification {
  my $self = shift;
  my $spec = shift;
  if ( ! exists $$self{'Specifications'} ) {
    $_ = q{SELECT name, value FROM Product_Specifications WHERE product_id=?};
    %{$$self{'Specifications'}} = sql::execute( $log, $dbh, $_, $$self{'id'});
  } # end if
  delete $$self{'Specifications'}{$spec};
} # end sub del_specification

1;
__END__
