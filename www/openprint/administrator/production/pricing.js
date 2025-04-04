
function calc_from_cost( element ) {
	var re = /cost-(.*)/
	var matches = re.exec( element.name );
	if ( matches ) {
		var index = matches[1];
		var cost = parseFloat( element.value.replace(/[^\d\-\.]/g, '' ) );
		var markup = parseFloat(1*element.form.elements['markup-'+index].value.replace(/[^\d\-\.]/g, '' )) /100;
		element.form.elements['price-'+index].value = do_decimals( cost * ( 1 + markup ), 5 ); 
	} // end if
} // end function calc_from_cost
function calc_from_markup( element ) {
	var re = /markup-(.*)/
	var matches = re.exec( element.name );
	var index = matches[1];

	var cost = parseFloat( element.form.elements['cost-'+index].value.replace(/[^\d\-\.]/g, '' ) );
	if ( cost != '' ) {
		var markup = parseFloat( 1*(element.value.replace(/[^\d\-\.]/g, '' ) ) );
		var newvalue = cost * ( markup/100 + 1 );
		element.form.elements['price-'+index].value = do_decimals( newvalue, 5 );
	} // end if
} // end function
function calc_from_price( element ) {
	var re = /price-(.*)/
	var matches = re.exec( element.name );
	var index = matches[1];

	var cost = parseFloat(element.form.elements['cost-'+index].value.replace(/[^\d\-\.]/g, '' ) );
	var price = parseFloat( element.value.replace(/[^\d\-\.]/g, '' ) );
	if ( cost ) {
			element.form.elements['markup-'+index].value = do_decimals( ((price / cost)-1)*100, 2 );
	} // end if
} // end function
