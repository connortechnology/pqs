package openprint::pricelist;

use strict;

require openprint::service_priceset;
require openprint::material_priceset;
require openprint::paper_priceset;
require openprint::product_priceset;
require openprint::logs;
require sql;
require openprint::ServicePrice;

sub new {
	my ( $type, $log, $dbh, $list_index ) = @_;
	my $self = {};
	bless $self, $type;

	$self->{log} = $log;
	$self->{dbh} = $dbh;

	$self->{list_index} = $list_index;

	return $self;
}

sub save {
	my $self = shift;

	$self->{log}->debug("Saving Pricelist" );

	my $ac = sql::start_transaction( $openprint::dbh );
	if ( keys %{$self->{materialspricesets}} ) {
		sql::execute( undef, undef,'DELETE FROM tbl_Material_Prices WHERE lngListIndex=?', $self->{list_index} );
		foreach my $product_index ( keys %{$self->{materialspricesets}} ) {
			$self->{materialspricesets}{$product_index}->save();
		} # end foreach
	} # end if
	if ( keys %{$self->{servicespricesets}} ) {
		foreach ( openprint::ServicePrice->find('pricelist_id'=>$self->{list_index}) ) {
			$_->delete();
		} # end foreach
		foreach my $product_index ( keys %{$self->{servicespricesets}} ) {
			$self->{servicespricesets}{$product_index}->save();
		} # end foreach
	} # end if
    if ( keys %{$self->{paperpricesets}} ) {
        sql::execute( undef, undef, 'DELETE FROM Paper_Prices WHERE lngListIndex=?', $self->{list_index} );
        foreach my $product_index ( keys %{$self->{paperpricesets}} ) {
            $self->{paperpricesets}{$product_index}->save();
        } # end foreach
    } # end if
    if ( keys %{$self->{productpricesets}} ) {
        sql::execute( undef, undef, 'DELETE FROM Product_Prices WHERE pricelist_id=?', $self->{list_index} );
        foreach my $product_index ( keys %{$self->{productpricesets}} ) {
            $self->{productpricesets}{$product_index}->save();
        } # end foreach
    } # end if
	sql::end_transaction( $openprint::dbh, $ac );
} # end sub save

sub addMaterialsPriceSet {
	my $self = shift;
	my $priceSet = shift;
	$self->{materialspricesets}{$priceSet->{product_index}} = $priceSet;
} # end sub addPriceSet

sub addServicesPriceSet {
	my $self = shift;
	my $priceSet = shift;
	$self->{servicespricesets}{$priceSet->{product_index}} = $priceSet;
} # end sub addPriceSet

sub addPaperPriceSet {
    my $self = shift;
    my $priceSet = shift;
    $self->{paperpricesets}{$priceSet->{product_index}} = $priceSet;
} # end sub addPriceSet
sub addProductPriceSet {
    my $self = shift;
    my $priceSet = shift;
    $self->{productpricesets}{$priceSet->{product_index}} = $priceSet;
} # end sub addPriceSet


sub getMaterialsPriceSet {
	my $self = shift;
	my $product_index = shift;
	
	if ( ! $self->{materialspricesets}{$product_index} ) {
		my $price_set = new openprint::material_priceset( $self->{log}, $self->{dbh}, $self->{list_index}, $product_index );
		addMaterialsPriceSet( $self, $price_set );
	} # end if
	return $self->{materialspricesets}{$product_index};
} # end sub getPriceSet

sub getServicesPriceSet {
	my $self = shift;
	my $product_index = shift;
	
	if ( ! $self->{servicespricesets}{$product_index} ) {
		my $price_set = new openprint::service_priceset( $self->{log}, $self->{dbh}, $self->{list_index}, $product_index );
		addServicesPriceSet( $self, $price_set );
	} # end if
	return $self->{servicespricesets}{$product_index};
} # end sub getPriceSet

sub getPaperPriceSet {
    my $self = shift;
    my $product_index = shift;

    if ( ! $self->{paperpricesets}{$product_index} ) {
        my $price_set = new openprint::paper_priceset( $self->{log}, $self->{dbh}, $self->{list_index}, $product_index );
        addPaperPriceSet( $self, $price_set );
    } # end if
    return $self->{paperpricesets}{$product_index};
} # end sub getPriceSet

sub getProductPriceSet {
    my $self = shift;
    my $product_index = shift;

    if ( ! $self->{productpricesets}{$product_index} ) {
        my $price_set = new openprint::product_priceset( $self->{log}, $self->{dbh}, $self->{list_index}, $product_index );
        addProductPriceSet( $self, $price_set );
    } # end if
    return $self->{productpricesets}{$product_index};
} # end sub getPriceSet

sub save_info {
	my ( $r, $log, $dbh, $index ) = @_;
	my @sql = (                     
			'Name',  $r->param('strName'),
			'Description',   $r->param('strDescription'),
			'CurrencyIndex', $r->param('ddmCurrency'),
			);              
	if ( ! $index ) { # add
		sql::insert( $log, $dbh, 'Pricelists', @sql );

		$_ = 'SELECT MAX(Index) FROM Pricelists WHERE Name=?';
		( $index ) = sql::execute( $log, $dbh, $_, $r->param('strName') );
	} else { #save
		sql::update( $log, $dbh, 'Pricelists', "Index = '$index'", @sql );
	} # end if
	return $index;
} # end sub save_info

1;

__END__
~       
