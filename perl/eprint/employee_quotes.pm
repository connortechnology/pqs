package eprint::employee_quotes;
use strict;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY); # Offers OK, Error, etc for web server.

require misc;
use sql ();

sub quotes_report {
	my ( $r, $log, $dbh, $variable ) = @_;

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
	$_ = "SELECT lngIndex, strName FROM tbl_Service_Types ORDER BY strName";
	$$variable{'ddmServices'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmServices') );
	$_ = "SELECT lngUserID, strFirstName || ' ' || strLastName FROM tbl_Customer_Users WHERE chrType='E'";
	$$variable{'ddmEmployees'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmEmployees') );

    $$variable{'dblTotal1'} = $r->param('dblTotal1');
    $$variable{'dblTotal2'} = $r->param('dblTotal2');

	if ( $r->param('btnFunction') eq 'Download in CSV format' ) {
		my @header = ( 'lngQuoteID', 'dtmQuoteDate', 'strPrepared By', 'strPreparedFor','Total1','Total2','Total3' );
		$_ = "SELECT DISTINCT tbl_Quotes.lngQuoteID, to_char(tbl_Quotes.dtmQuoteDate, 'MM/DD/YYYY'),\n".
			"tbl_Quote_Users_By.strFirstName || ' ' || tbl_Quote_Users_By.strLastName,\n".
			"tbl_Quote_Users_For.strFirstName || ' ' || tbl_Quote_Users_For.strLastName,\n".
			"tbl_Quotes.curTotalSale1, curTotalSale2, curTotalSale3\n".
			"FROM tbl_Quotes, tbl_Quote_Users_For, tbl_Quote_Users_By ".
			"WHERE tbl_Quote_Users_By.lngQuoteID = tbl_Quotes.lngQuoteID ".
			"AND tbl_Quote_Users_For.lngQuoteID = tbl_Quotes.lngQuoteID ".
			"AND tbl_Quotes.lngQuoteID IN ( ".
			"	SELECT DISTINCT tbl_Quotes.lngQuoteID FROM	tbl_Quotes, tbl_Quote_Details ".
			"	WHERE date(tbl_Quotes.dtmQuoteDate) BETWEEN date('$$variable{'StartDate'}') AND date('$$variable{'EndDate'}') ";
		$_ .= "	AND tbl_Quotes.ysnFinished = 'Y' \n" if $r->param('ddmFinished') eq 'Y';
		$_ .= "	AND tbl_Quotes.ysnFinished = 'N' \n" if $r->param('ddmFinished') eq 'N';
		$_ .= "	AND tbl_Quote_Details.lngQuoteID = tbl_Quotes.lngQuoteID ";
		$_ .= "	AND tbl_Quotes.lngCustomerID = '".$r->param('ddmCustomers')."' \n" if $r->param('ddmCustomers') ne '';
		if ( $r->param('dblTotal1') and $r->param('dblTotal2') ) {
			$_ .= " AND ( ";
			$_ .= "tbl_Quotes.curTotalSale1 BETWEEN ".$r->param('dblTotal1')." AND ".$r->param('dblTotal2')."\n";
			$_ .= " OR ";
			$_ .= "tbl_Quotes.curTotalSale2 BETWEEN ".$r->param('dblTotal1')." AND ".$r->param('dblTotal2')."\n";
			$_ .= " OR ";
			$_ .= "tbl_Quotes.curTotalSale3 BETWEEN ".$r->param('dblTotal1')." AND ".$r->param('dblTotal2')."\n";
			$_ .= " )\n";
		} # end if

		$_ .= ") ORDER BY tbl_Quotes.lngQuoteID";

		my @data = sql::sql_statement( $log, $dbh, $_ );
		misc::export_csv( $r, $log, $variable, 'quote_report.csv', \@header, \@data );
	} else {
		$_ = "SELECT DISTINCT tbl_Quotes.lngQuoteID, tbl_Quotes.lngCustomerID, to_char(tbl_Quotes.dtmQuoteDate, 'MM/DD/YYYY'),\n".
			"tbl_Quote_Users_By.strFirstName || ' ' || tbl_Quote_Users_By.strLastName,\n".
			"tbl_Quote_Users_For.strFirstName || ' ' || tbl_Quote_Users_For.strLastName,\n".
			"tbl_Quotes.curTotalSale1, curTotalSale2, curTotalSale3\n".
			"FROM tbl_Quotes, tbl_Quote_Users_For, tbl_Quote_Users_By ".
			"WHERE tbl_Quote_Users_By.lngQuoteID = tbl_Quotes.lngQuoteID ".
			"AND tbl_Quote_Users_For.lngQuoteID = tbl_Quotes.lngQuoteID ".
			"AND tbl_Quotes.lngQuoteID IN ( ".
			"SELECT tbl_Quotes.lngQuoteID FROM tbl_Quotes, tbl_Quote_Details ".
			"WHERE date(tbl_Quotes.dtmQuoteDate) BETWEEN date('$$variable{'StartDate'}') AND date('$$variable{'EndDate'}') ";
		$_ .= "	AND tbl_Quotes.ysnFinished = 'Y' \n" if $r->param('ddmFinished') eq 'Y';
		$_ .= "	AND tbl_Quotes.ysnFinished = 'N' \n" if $r->param('ddmFinished') eq 'N';
		$_ .= "	AND tbl_Quote_Details.lngQuoteID = tbl_Quotes.lngQuoteID ";
		$_ .= "	AND tbl_Quotes.lngCustomerID = '".$r->param('ddmCustomers')."' \n" if $r->param('ddmCustomers') ne '';
		if ( $r->param('dblTotal1') and $r->param('dblTotal2') ) {
			$_ .= " AND ( ";
			$_ .= "tbl_Quotes.curTotalSale1 BETWEEN ".$r->param('dblTotal1')." AND ".$r->param('dblTotal2')."\n";
			$_ .= " OR ";
			$_ .= "tbl_Quotes.curTotalSale2 BETWEEN ".$r->param('dblTotal1')." AND ".$r->param('dblTotal2')."\n";
			$_ .= " OR ";
			$_ .= "tbl_Quotes.curTotalSale3 BETWEEN ".$r->param('dblTotal1')." AND ".$r->param('dblTotal2')."\n";
			$_ .= " )\n";
		} # end if

		$_ .= ") ORDER BY tbl_Quotes.lngQuoteID";
		@{$$variable{'DATA'}} = sql::sql_statement( $log, $dbh, $_ );
		$$variable{'ReportTotal1'} = 0;
		$$variable{'ReportTotal2'} = 0;
		$$variable{'ReportTotal3'} = 0;
		for ( my $index = 0; $index < @{$$variable{'DATA'}}; $index += 8 ) {
			$$variable{'ReportTotal1'} += $$variable{'DATA'}[$index+5];
			$$variable{'ReportTotal2'} += $$variable{'DATA'}[$index+6];
			$$variable{'ReportTotal3'} += $$variable{'DATA'}[$index+7];
		} # end for
		$$variable{'ReportTotal1'} = sprintf("%.2f", $$variable{'ReportTotal1'} );
		$$variable{'ReportTotal2'} = sprintf("%.2f", $$variable{'ReportTotal2'} );
		$$variable{'ReportTotal3'} = sprintf("%.2f", $$variable{'ReportTotal3'} );
	} # end if

	return OK;
} # end sub quotes_report

1;

__END__

