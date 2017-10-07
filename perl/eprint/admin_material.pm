package eprint::admin_material;

use strict;
use sql ();

sub price_list_view {
    my ( $r, $log, $dbh, $variable ) = @_;

	my $list_index = sql::escape($r->param('ddmPriceList'));

    # We an empty set if we aren't given something to look up. (Not a very good
    # system but it solves it for the moment).
    return unless $list_index;
    
    $variable->{'PriceListName'} = $dbh->selectrow_array(q{
        SELECT currency || ' - ' || name FROM pricelist WHERE id = ?
    }, undef, $list_index);
    
    $$variable{'list_id'} = $list_index;

    $_ = "SELECT DISTINCT lngIndex, strName, strID ".
        "FROM tbl_Materials, tbl_Material_Prices ".
        "WHERE tbl_Material_Prices.lngListIndex = '$list_index' ".
        "AND lngIndex = lngMaterialIndex ".
        "ORDER BY strID";
    @{$$variable{'PRODUCTS'}} = sql::sql_statement( $log, $dbh, $_ );

    for ( my $index = 0; $index < @{$$variable{'PRODUCTS'}}; $index += 3 ) {

        $_ = "SELECT (SELECT strID FROM tbl_Equipment WHERE lngIndex=lngEquipmentIndex) AS Equipment,lngMin, lngMax, strUnits, dblCost, dblMarkup, dblPrice\n".
                "FROM tbl_Material_Prices ".
                "WHERE lngListIndex = '$list_index' ".
                "AND lngMaterialIndex = '$$variable{'PRODUCTS'}[$index]'" .
                "ORDER BY Equipment, lngMin";
        @{$$variable{"PRICES_$$variable{'PRODUCTS'}[$index]"}} = sql::sql_statement( $log, $dbh, $_ );
    } # end for

}


1;

