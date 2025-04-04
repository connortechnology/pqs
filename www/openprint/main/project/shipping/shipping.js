function calc( formName, force, options ) {

	if ( gettingNewPrice && ! force ) {
		// This prevents concurrent price getting
		if ( options ) {
			timeout = setTimeout("calc('f1', 0, " + Object.toJSON( options ) + ");", 1000 );
		} else {
			timeout = setTimeout("calc('f1' );", 1000 );
		} // end if
		return;
	} // end if
	if ( timeout ) clearTimeout( timeout );

	remove_div('AlertDiv');
	gettingNewPrice = true;
	var form = getFormObj( formName );
	var h = $H(form.serialize(true));
	h.set('callback', 'cbShippingResults' );
;
	if ( options ) {
		$H(options).each(function(pair) {
				h.set(pair.key, pair.value);
				} );
	} // end if options
	new Ajax.Request( '/main/project/_calc.json', { method: 'post', parameters: h, evalScripts: true } );
} // end calc()

function cbShippingResults( results ) {
	cbFillResults( results );
	var form = getFormObj( 'f1' );
	if ( ( form.elements['NeedPlainCartons'].value > 0 ) && confirm('Your project must be packed in cartons in order to be shipped.  Would you like to add Plain Cartons to your project?' ) ) {
		calc( 'f1', 1, {  action: 'add_service', service_name: 'PlainCartons' } );
	} // end if
}
function validate_data(formName) {
	var form = getFormObj( formName );
	var text = '';
	return true;
} // end function

function select_location( to_from, location_id ) {
	new Ajax.Request('_select_location.json', { parameters: { to_from: to_from, location_id: location_id } } );
}

