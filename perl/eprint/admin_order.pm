package eprint::admin_order;

use strict;

require eprint::order;
require misc;
use sql ();

sub edit {
	my ( $r, $log, $dbh, $variable ) = @_;
	my $cookie = '';

	my $order_id = $r->param('order_id');
 	$order_id = $r->param('hiddenOrderID') if $order_id eq '';
	if ( $r->param('btnFunction') eq 'Delete' ) {
		eprint::order::delete_order( $log, $dbh, $order_id );
	} elsif ( $r->param('btnFunction') eq 'Resend' ) {
		sql::update( $log, $dbh, 'tbl_Orders',"lngOrderID='$order_id'", 'strComments',$r->param('txtComments') );
		eprint::order::order_send_email( $r, $log, $dbh, $order_id );
	} elsif ( $r->param('btnFunction') eq 'Save Edit' ) {
		$log->debug(" *** SAVING ORDER EDIT *** ");
		my $error = eprint::order::store_order_info( $r, $log, $dbh, $cookie, $variable );
		if ( $error ne '' ) {
        	return misc::error( $log, $dbh, $variable, 'Error', $error );
    	} # end if
	} elsif ( $r->param('btnFunction') eq 'SaveOrderTotalEdit' ) {
		$log->debug("*** Editing Order Totals. Be Careful ***");
		my $total_price = $r->param('TOTAL');
		if ( $r->param('CUSTOM_PRICE') ne '' ) {
			my $custom_price = $r->param('CUSTOM_PRICE');
			if ( ! $custom_price > 0 ) {
        		return misc::error( $log, $dbh, $variable, 'Error', 'Price is not valid' );
			} # end if
			if ( ! $r->param('txtCustomDescription') ) {
        		return misc::error( $log, $dbh, $variable, 'Error', 'Description Required' );
			} # end if
			sql::insert( $log, $dbh, 'tbl_Order_Contents', 
					'lngOrderId', $order_id,
					'lngProjectIndex', 0,
					'strDescription', $r->param('txtCustomDescription'),
				   	'curSalesPrice', $custom_price
					);	
		} # end if

		my @data;
		push @data, 'curTotalSale',	$total_price if $total_price > 0;
		push @data, 'curFedTax',	$r->param('GST')  if $r->param('GST') > 0;
		push @data, 'curProvTax',	$r->param('PST')  if $r->param('PST') > 0;
		push @data, 'curHarmTax',	$r->param('HST')  if $r->param('HST') > 0;
		sql::update( $log, $dbh, 'tbl_Orders',"lngOrderID='$order_id'", @data );
	} # end if

	eprint::order::get_invoice_to( $log, $dbh, $variable, $order_id );
	eprint::order::get_ship_to( $log, $dbh, $variable, $order_id );
    $$variable{'CCITYPROVCOUNTRY'} = misc::build_city_prov_country(@$variable{'txtCity','txtStateProvince','txtCountry'} );
    $$variable{'FCITYPROVCOUNTRY'} = misc::build_city_prov_country(@$variable{'txtShippingCity','txtShippingStateProvince','txtShippingCountry'} );
	eprint::order::get_misc( $log, $dbh, $variable, $order_id );
	eprint::order::get_projects( $log, $dbh, $variable, $order_id );
	$log->debug("*** ORDER EDIT: $$variable{'txtStateProvince'} ***");

    $$variable{'ddmStateProvince'} = ssi::return_states_and_provinces($$variable{'txtStateProvince'});
    $$variable{'ddmCountry'} = ssi::return_countries($$variable{'txtCountry'});
    $$variable{'ddmShippingStateProvince'} = ssi::return_states_and_provinces($$variable{'txtShippingStateProvince'});
    $$variable{'ddmShippingCountry'} = ssi::return_countries($$variable{'txtShippingCountry'});

    $$variable{'rdbSalutation'.$$variable{'txtSalutation'}} = 'CHECKED';
    $$variable{'rdbShippingSalutation'.$$variable{'txtShippingSalutation'}} = 'CHECKED';

	$_ = "SELECT lngCustomerID FROM tbl_Orders where lngOrderID='$order_id'";
	@$variable{'cust_index'} = sql::sql_statement( $log, $dbh, $_ );

	$$variable{'ORDER_ID'} = $order_id;
} # end sub display_order


1;

__END__
~	   
