
function shipping_quantity_update( e ) {
	var re = /^txtQuantity(\d)-(\d+)-(\d+)$/;
	var matches = re.exec( e.name );
	if ( matches ) {
		var order_index = matches[1];
		var project_index = matches[2];
		var service_index = matches[3];
	} else {
		return;
	} // end if
	var ordered_quantity = e.form.elements['OrderedQuantity'+project_index].value - e.value;
	var last_quantity;

	for ( var index = 0, len = e.form.elements.length; index < len; index += 1 ) {
		var element = e.form.elements[index];
		if ( element.name == e.name ) continue;
		var matches = re.exec( element.name );
		
		if ( matches ) {
			if ( matches[2] == project_index ) {
				// right quantity for the project
				if ( ordered_quantity - element.value < 0 ) {
					element.value = ordered_quantity;
					ordered_quantity = 0;
				} else if ( ordered_quantity == 0 ) {
					element.value = ordered_quantity;
				} else {
					ordered_quantity -= element.value;
				} // end if
				last_quantity = element;
			} // end if
		} // end if	
	} // end for
	if ( last_quantity && ordered_quantity ) {
		last_quantity.value = parseInt( last_quantity.value ) + parseInt( ordered_quantity );
	} // end if
} // end function shipping_quantity_update( form )

function same_as_billing( on, id ) {

	var checkbox = $('same_as_billing'+id);
	var form = checkbox.form;	
	if ( on ) {
		form.elements['ToCompanyName'+id].value = form.elements['company_name'].value;
		set_rdb_value( form.elements['ToSalutation'+id], get_value( form.elements['salutation'] ) );
		form.elements['ToFirstName'+id].value = form.elements['firstname'].value;
		form.elements['ToLastName'+id].value = form.elements['lastname'].value;
		form.elements['ToAddress1'+id].value = form.elements['address1'].value;
		form.elements['ToAddress2'+id].value = form.elements['address2'].value;
		form.elements['ToCity'+id].value = form.elements['city'].value;
		form.elements['ToStateProvince'+id].value = form.elements['state'].value;
		form.elements['ToCountry'+id].value = form.elements['country'].value;
		form.elements['ToPostalCode'+id].value = form.elements['postalcode'].value;
		form.elements['ToPhone'+id].value = form.elements['phone'].value;
		form.elements['ToFax'+id].value = form.elements['fax'].value;
		form.elements['ToEmail'+id].value = form.elements['email'].value;
	} else if ( checkbox.checked ) {        
		checkbox.checked = false;
	} // end if
} // end function same_as_billing

function company_id_onchange( e ) {
	if ( e.getValue() ) {
		new Ajax.Updater('BillingInformation','_billing_information.html', { parameters:e.form.serialize() });
		$('AddFromBelow').hide();
	} else {
		$('AddFromBelow').show();
	} // end if
} // end function

function save_company( ) {
	if ( ! $('txtCompanyName').getValue() ) {
		alert('Please provide a name for the company');
	} else {
		new Ajax.Updater('CompanyDropDown','_company_dropdown.html', { parameters:$('f1').serialize() });
	} // end if
} // end function save_company()

function ddmUsers_onchange( form ) {
	new Ajax.Request('/main/order/_user_info.json', { parameters: { user_id: form.ddmUsers.options[form.ddmUsers.selectedIndex].value } } );
} // end function

function remove_product(op_id) {
	new Ajax.Updater( 'Products', '/main/order/_product_list_edit.html', { parameters: { order_id: $('f1').order_id.value, id: op_id, action: 'remove' } } );
}
