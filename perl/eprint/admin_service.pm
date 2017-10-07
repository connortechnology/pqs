package eprint::admin_service;
use strict;
use warnings;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY); # Offers OK, Error, etc for web server.

use sql qw(:common);

# Gives an ordered list of every service price in a pricelist (very old).
sub price_list_view {
	my ( $r, $log, $dbh, $variable ) = @_;

	my $list_index = sql::escape( $r->param('ddmPriceList') );

    @$variable{'PriceListName'} = sql_statement( $log, $dbh, qq{
        SELECT currency || '-' || name FROM pricelist WHERE id = $list_index
    });
	
    $variable->{list_id} = $list_index;
	
	@{$$variable{'PRODUCTS'}} = sql_statement( $log, $dbh, qq{
	    SELECT DISTINCT lngIndex, strName, strID
		FROM tbl_Services, tbl_Service_Prices
		WHERE tbl_Service_Prices.lngListIndex = $list_index
		  AND lngIndex = lngServiceIndex
		ORDER BY strID
    });

	for ( my $index = 0; $index < @{$$variable{'PRODUCTS'}}; $index += 3 ) {

		$_ = "SELECT (SELECT strID FROM tbl_Equipment WHERE lngIndex=lngEquipmentIndex) AS Equipment,lngMin, lngMax, strUnits, dblCost, dblMarkup, dblPrice\n".
				"FROM tbl_Service_Prices ".
				"WHERE lngListIndex = '$list_index' ".
				"AND lngServiceIndex = '$$variable{'PRODUCTS'}[$index]'" .
				"ORDER BY Equipment, lngMin";

		@{$$variable{"PRICES_$$variable{'PRODUCTS'}[$index]"}} = sql_statement( $log, $dbh, $_ );
	}

    return OK;
}

1;
