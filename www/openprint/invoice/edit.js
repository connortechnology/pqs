function update_totals( ) {
	let total;
	const timetrack_total_element = document.getElementById('timetrack_total');
	if (timetrack_total_element) {
		total += parseFloat(timetrack_total_element.innerHTML.replace(/[^\d\.]/g, ''));
	} // end if
	const product_total_element = document.getElementById('product_total');
	if (product_total_element) {
		total += parseFloat(product_total_element.innerHTML.replace(/[^\d\.]/g, ''));
	} // end if
	const order_total_element = document.getElementById('order_total');
	if (order_total_element) {
		total += parseFloat(order_total_element.innerHTML.replace(/[^\d\.]/g,''));
	} // end if

  const subtotal_element = document.getElementById('subtotal');
	if (subtotal_element) {
		subtotal_element.innerHTML = do_decimals(total, 2);
	} else {
		alert('no subtotal');
	} // end if
} // end function

function update_product( product_id ) {
	$('product-total-'+product_id).innerHTML = do_decimals( parseFloat($('product-price-'+product_id).value) * parseFloat($('product-quantity-'+product_id).value), 2 );
} // end function update_product

function add_timetrack(button) {
  const timetrack_id = button.getAttribute('data-id');
	new Ajax.Updater( 'Timetracks', '_timetracks.html', {
			parameters: {
				invoice_id: invoice_id,
				timetrack_id: timetrack_id,
				action: 'add'
			},
			onComplete: function(transport) {
        update_event_bindings();
				update_totals();
				TableKit.reload();
			},
			onFailure: function(transport) {
				alert('failure to include');
			}
	} );
} // end function add_timetrack( invoice_id)
function del_timetrack( button ) {
  const timetrack_id = button.getAttribute('data-id');
	new Ajax.Updater( 'Timetracks', '_timetracks.html', {
			parameters: {
				invoice_id: invoice_id,
				timetrack_id: timetrack_id,
				action: 'remove'
			},
			onComplete: function(transport) {
        update_event_bindings();
				update_totals();
				TableKit.reload();
			},
			onFailure: function(transport) {
				alert('failure to remove timetrack');
			}
		} );
} // end function del_timetrack(invoice_id)

function reload_timetracks() {
	new Ajax.Updater( 'Timetracks', '_timetracks.html', {
			parameters: {
				invoice_id: invoice_id,
        timetrack_start_year: $j('#timetrack_start_year').val(),
        timetrack_start_month: $j('#timetrack_start_month').val(),
        timetrack_start_day: $j('#timetrack_start_day').val(),
        timetrack_end_year: $j('#timetrack_end_year').val(),
        timetrack_end_month: $j('#timetrack_end_month').val(),
        timetrack_end_day: $j('#timetrack_end_day').val(),
			},
			onComplete: function(transport) {
        update_event_bindings();
				update_totals();
				TableKit.reload();
			}
		} );
} // end function reload_timetracks

function add_order( order_id ) {
	new Ajax.Updater( 'Orders', '_invoiced_orders.html', {
			parameters: {
				invoice_id: invoice_id,
				order_id: order_id,
				action: 'add'
			},
			onComplete: function(transport) {
				update_totals();
				TableKit.reload();
			},
			onFailure: function(transport) {
				alert('failure to include');
			}
	} );
} // end function add_order( invoice_id)
function del_order( order_id ) {
	new Ajax.Updater( 'Orders', '_invoiced_orders.html', {
			parameters: {
				invoice_id: invoice_id,
				order_id: order_id,
				action: 'remove'
			},
			onComplete: function(transport) {
				update_totals();
				TableKit.reload();
			},
			onFailure: function(transport) {
				alert('failure to remove timetrack');
			}
		} );
} // end function del_order(invoice_id)

function invoicee_change(ddm) {
	new Ajax.Request( '_invoicee_onchange.json', { parameters: { invoice_id: invoice_id, invoicee_id: ddm.getValue() } } );
	if ( invoice_id ) {
		new Ajax.Updater( 'Timetracks', '_timetracks.html', {
			parameters: {
					invoice_id: invoice_id,
					invoicee_id: ddm.getValue() 
				},
				onComplete: function(transport) {
					update_totals();
					TableKit.reload();
				},
				onFailure: function(transport) {
					alert('failure to include');
				}
		} );
		new Ajax.Updater( 'Orders', '_invoiced_orders.html', {
			parameters: {
				invoice_id: invoice_id,
				invoicee_id: ddm.getValue() 
			},
			onComplete: function(transport) {
				update_totals();
				TableKit.reload();
			},
			onFailure: function(transport) {
				alert('failure to include');
			}
		} );
	} // end if invoice_id
} // end function invoicee_change(ddm)

function add_tax( tax_id ) {
  console.log(tax_id);
  if (tax_id) {
    new Ajax.Updater( 'Taxes', '_taxes_edit.html', { parameters: {
      invoice_id: invoice_id,
      action: 'add',
      tax_id: tax_id
      }, evalScripts: true } );
  }
}
function delete_tax( tax_id ) {
  new Ajax.Updater( 'Taxes', '_taxes_edit.html', { parameters: {
    invoice_id: invoice_id,
    action: 'delete',
    tax_id: tax_id
    }, evalScripts: true } );
}
function update_taxes( form ) {
  if ( invoice_id ) {
    new Ajax.Updater( 'Taxes', '_taxes_edit.html?action=reset&invoice_id='+invoice_id, { parameters: form.serialize() } );
  }
} // end function update_taxes

function del_interest(button) {
  const interest_id = button.getAttribute('data-interest_id');
  if (!interest_id) {
    console.log('No interest id on button');
    console.log(button);
  }
  new Ajax.Updater('Interests', '_interests.html',
    { evalScripts: true, parameters: { action: 'delete', 'invoice_id': invoice_id, 'interest_id': interest_id } }
    );
  update_event_bindings();
}

function del_product(button) {
  const product_id = button.getAttribute('data-product_id');
  if (!product_id) {
    console.log('No product id on button');
    console.log(button);
  }
  new Ajax.Updater('InvoicedProducts','_invoiced_products.html?action=remove&amp;product_id='+product_id, { method: 'post', parameters: $('f1').serialize()} );
  update_event_bindings();
}

function add_product(button) {
  new Ajax.Updater('InvoicedProducts','_invoiced_products.html?action=add', { method: 'post', parameters: $('f1').serialize()} );
  update_event_bindings();
}
