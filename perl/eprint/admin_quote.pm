package eprint::admin_quote;

use strict;

require eprint::quote;
use sql ();

sub modify_project {
	my ( $r, $log, $dbh, $variable ) = @_;
	my $project_index = $r->param('ProjectIndex');
	my $quote_index = $r->param('QuoteId');

	if ($r->param('btnFunction') eq 'Modify Project') {
		sql::insert( $log, $dbh, 'tbl_Project_Contents',
				'lngProjectIndex',  $project_index,
				'strStatus',    'calculated' );

		$_ = "SELECT MAX(lngServiceIndex) FROM tbl_Project_Contents WHERE lngProjectIndex='$project_index'";
		( my $service_index ) = sql::sql_statement( $log, $dbh, $_ );

		sql::insert( $log, $dbh, 'tbl_Service_Specifications', (
					'lngProjectIndex',  $project_index,
					'lngServiceIndex',  $service_index,
					'strName',          'ServiceType',
					'strValue',         '0' ));
		sql::insert( $log, $dbh, 'tbl_Service_Specifications', (
					'lngProjectIndex',  $project_index,
					'lngServiceIndex',  $service_index,
					'strName',          'txtPrice1',
					'strValue',         $r->param('txtPrice1') ));
		sql::insert( $log, $dbh, 'tbl_Service_Specifications', (
					'lngProjectIndex',  $project_index,
					'lngServiceIndex',  $service_index,
					'strName',          'txtPrice2',
					'strValue',         $r->param('txtPrice2') ));
		sql::insert( $log, $dbh, 'tbl_Service_Specifications', (
					'lngProjectIndex',  $project_index,
					'lngServiceIndex',  $service_index,
					'strName',          'txtPrice3',
					'strValue',         $r->param('txtPrice3') ));
		sql::insert( $log, $dbh, 'tbl_Service_Specifications', (
					'lngProjectIndex',  $project_index,
					'lngServiceIndex',  $service_index,
					'strName',          'ServiceName',
					'strValue',         $r->param('txtServiceName') ));
	} elsif ( $r->param('remove') ne '' ) {
		eprint::print_project::delete_service( $log, $dbh, $project_index, $r->param('remove') );
	} # end if

	eprint::print::display_project( $log, $dbh, $variable, $project_index );

	$_ = "SELECT curSalesPrice1, curSalesPrice2, curSalesPrice3, dblMarkup FROM tbl_Quote_Details WHERE ".
		" lngQuoteId='$quote_index' AND lngProjectIndex='$project_index'";
	my ($price1, $price2, $price3, $markup) = sql::sql_statement( $log, $dbh, $_ );
	$log->debug("***** PRICES    $$variable{'TOTAL1'},$$variable{'TOTAL2'},$$variable{'TOTAL3'} ******");

	if ($price1 ne $$variable{'TOTAL1'} || $price2 ne $$variable{'TOTAL2'} || $price3 ne $$variable{'TOTAL3'} ) {

		sql::update( $log, $dbh, 'tbl_Quote_Details', "lngQuoteId='$quote_index' AND lngProjectIndex='$project_index'",
				'curSalesPrice1',		$$variable{'TOTAL1'},
				'curSalesPrice2',		$$variable{'TOTAL2'},
				'curSalesPrice3',		$$variable{'TOTAL3'},
				'curNewSalesPrice1',	$$variable{'TOTAL1'} * (1+($markup/100)),
				'curNewSalesPrice2',	$$variable{'TOTAL2'} * (1+($markup/100)),
				'curNewSalesPrice3',	$$variable{'TOTAL3'} * (1+($markup/100)) );

	} # end if

	$$variable{'ProjectIndex'} = $project_index;
	$$variable{'QuoteId'} = $quote_index;
} # end sub modify project

sub edit {
	my ( $r, $log, $dbh, $variable ) = @_;

	my $quote_id = $r->param('quote_id');

	if ( $r->param('btnFunction') eq 'Delete' ) {
		eprint::quote::delete_quote( $log, $dbh, $quote_id );
	} elsif ( $r->param('btnFunction') eq 'Resend' ) {
		foreach my $key ( $r->param() ) {
			if ( $key =~ /txtMarkup(\w*)/ ) {
				sql::update( $log, $dbh, 'tbl_Quote_Details', "lngQuoteID = '$quote_id' AND lngProjectIndex='$1'",
						'dblMarkup',    $r->param($key).'',
						'curNewSalesPrice1', ( $r->param("txtNewPrice1$1") ne '' ? $r->param("txtNewPrice1$1") : 'NULL' ),
						'curNewSalesPrice2', ( $r->param("txtNewPrice2$1") ne '' ? $r->param("txtNewPrice2$1") : 'NULL' ),
						'curNewSalesPrice3', ( $r->param("txtNewPrice3$1") ne '' ? $r->param("txtNewPrice3$1") : 'NULL' )
						);
			} # end if
		} # end foreach
		sql::update( $log, $dbh, 'tbl_Quotes', "lngQuoteID = '$quote_id'",
				'strComments',		$r->param('txtComments') . '', 
				'curTotalSale1',	( $r->param('total1') ne '' ? $r->param('total1') : 'NULL' ),
				'curTotalSale2',	( $r->param('total2') ne '' ? $r->param('total2') : 'NULL' ),
				'curTotalSale3',	( $r->param('total3') ne '' ? $r->param('total3') : 'NULL' ),
				'dblModification1', ( $r->param("txtModification1") ne '' ? $r->param("txtModification1") : 'NULL' ),
				'dblModification2', ( $r->param("txtModification2") ne '' ? $r->param("txtModification2") : 'NULL' ),
				'dblModification3', ( $r->param("txtModification3") ne '' ? $r->param("txtModification3") : 'NULL' )
				);
		eprint::quote::send_quote( $r, $log, $dbh, $quote_id, $variable );
	} # end if

    eprint::quote::get_user_by_info( $log, $dbh, $variable, $quote_id );
    eprint::quote::get_user_for_info( $log, $dbh, $variable, $quote_id );
    $$variable{'CCITYPROV'} = misc::build_city_prov_country(@$variable{'ByCity','ByStateProvince','ByCountry'} );
    $$variable{'FCITYPROV'} = misc::build_city_prov_country(@$variable{'ForCity','ForStateProvince','ForCountry'} );

    eprint::quote::get_misc_info( $log, $dbh, $variable, $quote_id );

	eprint::quote::get_finished_quote_contents( $log, $dbh, $variable, $quote_id );
	$$variable{'QUOTE_ID'} = $quote_id;

    $_ = "SELECT 1, curTotalSale1, dblModification1, 2, curTotalSale2, dblModification2, 3, curTotalSale3, dblModification3\n".
            "FROM tbl_Quotes ".
            "WHERE lngQuoteID = '$quote_id'";
    @{$$variable{'TOTALS'}} = sql::sql_statement( $log, $dbh, $_ );
} # end sub edit_quote


1;

__END__
~       
