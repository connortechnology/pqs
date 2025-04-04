function load_content_type( index, type ) {
	$('content-'+index).innerHTML = '';
	new Ajax.Updater('content-'+index, '_po_content_'+type+'.html', { parameters: { content_id: index } } );
} // end function load_content_type

function dept_onchange( element ) {
	var re = /^dept_id-(\d+)$/
	var matches = re.exec( element.name );
	if ( matches ) {
		var index = matches[1];
		if ( element.getValue() == 'new' ) {
			$('dept-'+index).show();
		} else {
			$('dept-'+index).hide();
			$('dept-'+index).value = '';
		} // end if
	} // end if matches
} // end function dept_onchange

function set_item(index) {
	var item = $('item-'+index);
	item.value = '';
	if ( $('mweight-'+index) ) { 
		item.value += $('mweight-'+index).value +'M ';
	} // end if
	var type = $('stocktype-'+index);
	if ( type && type.options[type.selectedIndex].value ) {
		item.value += type.options[type.selectedIndex].value + ' ';
	} // end if
	item.value += $('name-'+index).value;
} // end function set_item(index)

function filter_items( index, type_id, e ) {
	if ( e.name == 'product-'+index ) {
		new Ajax.Updater('item_id-'+index, '_items_dropdown.html', { parameters: { product_ilike: e.value, vendor_id: get_ddm_value($('supplier_id')), type_id: type_id } } );
	} else {
		new Ajax.Updater('item_id-'+index, '_items_dropdown.html', { parameters: { name_ilike: e.value, vendor_id: get_ddm_value($('supplier_id')), type_id: type_id } } );
	} // end if
}

function calc_price( element ) {
	var re = /(.*)-(.*)/
	var matches = re.exec( element.name );
	if ( matches ) {
		var index = matches[2];
		floatize( $('price-'+index) );
		//$('price-'+index).value = $('price-'+index).value.replace(/[^\d\-\.]/g, '' );
		re =  /^\s*(\+|-)?((\d+(\.\d+)?)|(\.\d+))\s*$/;
		if ( ! re.test($('price-'+index).value) ) { $('price-'+index+'-alert').innerHTML = 'Not a valid price!';
		} else { $('price-'+index+'-alert').innerHTML = ''; }
	
		floatize( $('qty-'+index) );
		var cost = parseFloat( $('price-'+index).value );
		var qty = parseFloat( $('qty-'+index).value );
		var type = get_value( $('type-'+index) );
		if ( type == 'Roll Stock' ) {
			qty /= 100;
		} else if ( type == 'Sheet Stock' ) {
			var mweight = parseFloat( $('mweight-'+index).value.replace(/[^\d\-\.]/g, '' ) );
			var sheets_in_100lbs = 1000 / ( mweight / 100 );
			$('mprice-'+index).value = do_decimals( cost * mweight / 100 );
//( 1000 / sheets_in_100lbs ), 2 );
			qty = qty * mweight / 100000;
		} // end if
		//var mprice_element = $('mprice-'+index);
		//if ( mprice_element ) {
			//mprice_element.value = do_decimals( 1000 * cost / qty, 2 );
		//} // end if
		$('total-'+index).value = do_decimals( cost * qty, 2 );
	} // end if
	update_totals( element.form );
} // end function calc_price

function update_totals( form ) {
	var total_div = $('total');
	if ( total_div ) {
		var subtotal = 0;
		var re = /total-(.+)/

		for ( var index = 0; index < form.elements.length; index += 1 ) {
			var e = form.elements[index];
			var matches = re.exec( e.name );
			if ( matches ) {
				subtotal += parseFloat(1*e.value);
			} // end if
		} // end for
		$('subtotal').innerHTML = do_decimals( subtotal, 2 );
		var total = subtotal;
		for ( var i = 0; i < tax_ids.length; i+= 1 ) {
			var tax = 0;
			
			if ( form.elements['tax_charge-'+tax_ids[i]].checked ) {
				tax = subtotal * $('tax_rate-'+tax_ids[i]).innerHTML/100;
			} else {
				tax = 0;
			} // end if
			$('tax_amount-'+tax_ids[i]).innerHTML = do_decimals( tax, 2 );
			
			total += parseFloat( tax );
		} // end for
		var payments_total =  $('payments_total');
		if ( payments_total )
			total -= parseFloat( payments_total.innerHTML );

		total_div.innerHTML = do_decimals( total, 2 );
	} // end if total_div
} // end function update_totals

function getSelectionId(input, li) {
	var re = /(\w+)-(\w+)/;
	var matches = re.exec( input.id );
	if ( matches ) {
		if ( matches[1] == 'item' ) {
			var description = Ajax.Autocompleter.extract_value(li, 'description');
			if ( description != 'undefined' ) 
				$('description-'+matches[2]).value;
			var price = Ajax.Autocompleter.extract_value(li, 'price');
			if ( price != 'undefined' )
				$('price-'+matches[2]).value = price;
		} // end if
	} // end if
} // end function getSelectionId

function add_Payment(po_id) {
	new Ajax.Updater( 'Payments', '_payments_edit.html', { parameters: { 
		po_id: po_id, 
		action: 'Add',
		amount: $('payment_amount').value,
		currency_id: $('currency_id').value,
		//currency_id: $('payment_currency_id').value,
		received_on: get_date_value( 'payment_received_on' ),
		description: $('payment_description').value,
		}, evalScripts: true } );
} // end function addPayment)po_id)

function add_tax( tax_id ) {
	new Ajax.Updater( 'Taxes', '_taxes_edit.html', { parameters: { 
		po_id: po_id, 
		action: 'add',
		tax_id: tax_id
		}, evalScripts: true } );
}
function delete_tax( tax_id ) {
	new Ajax.Updater( 'Taxes', '_taxes_edit.html', { parameters: { 
		po_id: po_id, 
		action: 'delete',
		tax_id: tax_id
		}, evalScripts: true } );
}
function update_taxes( form ) {
	if ( po_id ) {
	  new Ajax.Updater( 'Taxes', '_taxes_edit.html?action=reset&po_id='+po_id, { parameters: form.serialize() } );
	}
} // end function update_taxes

function update_logs( ) {
	new Ajax.Updater( 'Logs', '_logs.html?po_id='+po_id );
}

function add_item() {
	if ( $('type_id-new').value ) {
		new Ajax.Request('_po_content_line.html?action=add' +
				'&amp;type_id=' + encodeURIComponent( $('type_id-new').options[$('type_id-new').selectedIndex].value ) +
				'&amp;po_id=' + po_id,
				{
					evalScripts: true,
					onSuccess: function(response){$('items').insert( { bottom: response.responseText } );update_totals($('f1'));}
					} );
	} else {
		alert('Please select a type for the new line.');
	}
}

function del_poc(id) {
	new Ajax.Request('/employee/purchase_order/_po_content_line.html?action=delete&amp;id='+id, {
		onSuccess: function(){
			var tr = $('line-'+id);
			tr.remove();
			update_totals($('f1'));
		}
	});
}

function update_vendor() {
	new Ajax.Request('/employee/purchase_order/_po_select_vendor.json', { parameters: { supplier_id: $('supplier_id').value } } );
}
