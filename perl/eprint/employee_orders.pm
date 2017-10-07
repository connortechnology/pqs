package eprint::employee_orders;
use strict;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY); # Offers OK, Error, etc for web server.
use Text::CSV_XS;

use sql ();
require misc;

sub orders_report {
	my ( $r, $log, $dbh, $variable ) = @_;
	my ( $search, @employees );
	
	ssi::get_start_end_dates( $log, $dbh, $variable,
			$r->param('ddmStartYear'),
			$r->param('ddmStartMonth'),
			$r->param('ddmStartDay'),
			$r->param('ddmEndYear'),
			$r->param('ddmEndMonth'),
			$r->param('ddmEndDay') );

	$_ = "SELECT lngCustomerID, strCompanyName FROM tbl_Customer ORDER BY lower(strCompanyName)";
	$$variable{'ddmCustomers'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmCustomers') );

	$_ = "SELECT lngIndex, strName from tbl_Service_Categories ORDER BY strName";
	$$variable{'ddmCategories'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmCategories') );
	$_ = "SELECT lngIndex, strName FROM tbl_Services ORDER BY strName";
	$$variable{'ddmServices'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmServices') );
	$_ = "SELECT lngUserID, strFirstName || ' ' || strLastName FROM tbl_Customer_Users WHERE chrType='E'";
	$$variable{'ddmEmployees'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmEmployees') );

	$$variable{'dblTotal1'} = $r->param('dblTotal1');
	$$variable{'dblTotal2'} = $r->param('dblTotal2');
	$$variable{'ddmStatus'.$r->param('ddmStatus')} = 'SELECTED';

	my @products;

	if ( $r->param('ddmCategories') ne '' ) {
		$_ = "SELECT lngProductIndex FROM tbl_Products WHERE lngCategoryIndex = '" . $r->param('ddmCategories') ."'";
		@products = sql::sql_statement( $log, $dbh, $_ );
	} elsif ( $r->param('ddmProducts') ne '' ) {
		@products = ( $r->param('ddmProducts') );
	} # end if

	if ( $r->param('btnFunction') eq 'Download in CSV format' ) {
		my @header = ('OrderID', 'Order Date', 'Company Name', 'PONumber', 'Total');
		$_ = "SELECT tbl_Orders.lngOrderID, to_char(tbl_Orders.dtmOrderDate, 'MM/DD/YYYY'), ".
			"tbl_Orders.strCompanyName, tbl_Orders.strPONumber, tbl_Orders.curTotalSale ".
			"FROM tbl_Orders, tbl_Order_Contents ".
			"WHERE dtmOrderDate BETWEEN '$$variable{'StartDate'}' AND '$$variable{'EndDate'}' ";
		$_ .= "AND tbl_Orders.strStatus = '".$r->param('ddmStatus')."'\n" if $r->param('ddmStatus');
		$_ .= "AND tbl_Order_Contents.lngOrderID = tbl_Orders.lngOrderID \n";
# which products
		$_ .= "AND tbl_Order_Contents.lngProductIndex IN ('" . join( ',', @products ) . "') \n" if @products != 0;
# which customers
		$_ .= "	AND tbl_Orders.lngCustomerID = '" . $r->param('ddmCustomers') ."' \n" if $r->param('ddmCustomers') ne '';
		$_ .= "	AND tbl_Orders.lngEmployeeID = '" . $r->param('ddmEmployees') . "' \n" if $r->param('ddmEmployees') ne '';
		$_ .= " AND tbl_Orders.curTotalSale BETWEEN " . $r->param('dblTotal1') . " AND " . $r->param('dblTotal2') . "\n" if $r->param('dblTotal1') and $r->param('dblTotal2');
		$_ .= "ORDER BY tbl_Orders.lngOrderID";

		my @data = sql::sql_statement( $log, $dbh, $_ );
		misc::export_csv( $r, $log, $variable, 'order_report.csv', \@header, \@data );
	} else {
		$_ = "SELECT lngOrderID, lngCustomerID, to_char(dtmOrderDate, 'MM/DD/YYYY'), ".
			"strCompanyName, strPONumber, curTotalSale\n".
			"FROM tbl_Orders\n".
			"WHERE lngOrderID IN ( \n".
			"	SELECT tbl_Orders.lngOrderID FROM	tbl_Orders, tbl_Order_Contents ".
			"	WHERE date(tbl_Orders.dtmOrderDate) BETWEEN date('$$variable{'StartDate'}') AND date('$$variable{'EndDate'}') ";
		$_ .= "AND tbl_Orders.strStatus = '".$r->param('ddmStatus')."'\n" if $r->param('ddmStatus');
		$_ .= "	AND tbl_Order_Contents.lngOrderID = tbl_Orders.lngOrderID \n";
# which products
		$_ .= "	AND tbl_Order_Contents.lngProductIndex IN ('" . join( ',', @products ) . "') \n" if @products != 0;
# which customers
		$_ .= "	AND tbl_Orders.lngCustomerID = '" . $r->param('ddmCustomers') ."' \n" if $r->param('ddmCustomers') ne '';
		$_ .= "	AND tbl_Orders.lngEmployeeID = '" . $r->param('ddmEmployees') . "' \n" if $r->param('ddmEmployees') ne '';
		$_ .= " AND tbl_Orders.curTotalSale BETWEEN " . $r->param('dblTotal1') . " AND " . $r->param('dblTotal2') . "\n" if $r->param('dblTotal1') and $r->param('dblTotal2');
		$_ .= ") ORDER BY lngOrderID";
		@{$$variable{'DATA'}} = sql::sql_statement( $log, $dbh, $_ );
		$$variable{'ReportTotal'} = 0;
		for ( my $index = 0; $index < @{$$variable{'DATA'}}; $index += 6 ) {
			$$variable{'ReportTotal'} += $$variable{'DATA'}[$index+5];
		} # end for
		
	} # end if
	return OK;
} # end sub order_report

1;

__END__

