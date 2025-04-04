function from_lbs( e, type_id, c_id ) {
	var form = e.form;
	var lbs = parseFloat(1*form.elements['qty_lbs-'+type_id+'-'+c_id].value);
	form.elements['qty_kgs-'+type_id+'-'+c_id].value = do_decimals( lbs / 2.2046, 1 );

	var type = get_value( form.elements['type-'+type_id] );

	var wpsi = parseFloat(1*form.elements['gsm-'+type_id].value) / 703064.5;
	var width = parseFloat(1*form.elements['width-'+type_id].value);
	if ( type == 'Roll' ) {
		if ( wpsi && width ) {
			form.elements['qty_feet-'+type_id+'-'+c_id].value = do_decimals(((lbs/wpsi)/width)/12,0);
		} // end if
	} else if ( type == 'Sheet' ) {
		var height = parseFloat(1*form.elements['height-'+type_id].value);
		if ( wpsi && width && height ) {
			form.elements['qty_sheets-'+type_id+'-'+c_id].value = do_decimals(((lbs/wpsi)/(width*height))/12,0);
		} // end if
	} // end if
} // end function from_lbs

function from_kg( e, type_id, c_id ) {
	var form = e.form;
	var kgs = parseFloat(1*form.elements['qty_kgs-'+type_id+'-'+c_id].value);
	var lbs = kgs * 2.2046;

	form.elements['qty_lbs-'+type_id+'-'+c_id].value = do_decimals( lbs, 0 );
	var type = get_value( form.elements['type-'+type_id] );

	var wpsi = parseFloat(1*form.elements['gsm-'+type_id].value)/ 703064.5;
	var width = parseFloat(1*form.elements['width-'+type_id].value);
	if ( type == 'Roll' ) {
		if ( wpsi && width ) {
			form.elements['qty_feet-'+type_id+'-'+c_id].value = do_decimals(((lbs/wpsi)/width)/12,0);
		} 
	} else if ( type == 'Sheet' ) {
		var height = parseFloat(1*form.elements['height-'+type_id].value);
		if ( wpsi && width && height ) {
			form.elements['qty_sheets-'+type_id+'-'+c_id].value = do_decimals(((lbs/wpsi)/(width*height))/12,0);
		} // end if
	} // end if
} // end function from_kg

function from_feet( e, type_id, c_id ) {
	return;
	var form = e.form;
	var feet = parseFloat(1*form.elements['qty_feet-'+type_id+'-'+c_id].value);
	var wpsi = parseFloat(1*form.elements['gsm-'+type_id].value)/ 703064.5;
	var width = parseFloat(1*form.elements['width-'+type_id].value);
	
	var lbs = feet*12*width*wpsi;
	form.elements['qty_lbs-'+type_id+'-'+c_id].value = do_decimals( lbs, 0 );
	form.elements['qty_kgs-'+type_id+'-'+c_id].value = do_decimals( lbs / 2.2046, 1 );
} // end function from_kg

function from_sheets( e, type_id, c_id ) {
	var form = e.form;

	var sheets = parseFloat(1*form.elements['qty_sheets-'+type_id+'-'+c_id].value);
	var wpsi = parseFloat(1*form.elements['gsm-'+type_id].value)/ 703064.5;
	if ( ! wpsi ) return;
	var width = parseFloat(1*form.elements['width-'+type_id].value);
	if ( ! width ) return;
	var height = parseFloat(1*form.elements['height-'+type_id].value);
	if ( ! height ) return;
	var lbs = sheets * wpsi * width * height;

	form.elements['qty_lbs-'+type_id+'-'+c_id].value = do_decimals( lbs, 0 );
	form.elements['qty_kgs-'+type_id+'-'+c_id].value = do_decimals( lbs / 2.2046, 1 );

} // end function from_sheets

function delete_content( c_id ) {
	new Ajax.Request( '_manifest_content.html', {
		parameters: { content_id: c_id, action: 'Remove' },
		onSuccess: function(transport){
			var tr = $('tr-'+c_id);
			if(!tr){alert('tr not found');}
			new Insertion.After(tr, transport.responseText);
		},
		evalScripts: true
	 } );
} // end function delete_conetnt( c_id )

function add_content(form, type_id) {
	var type =	form.elements['type-'+type_id];
	type = get_value( type );

	new Ajax.Request( '_manifest_content.html', {
			parameters: {
				action:		'Add',
				type_id:    type_id,
				manifest_id: form.manifest_id.value,
				rfidtag_id: $('rfidtag_id-'+type_id+'-').value,
				skid_id:    $('skid_id-'+type_id+'-').value,
				quantity:	(type == 'Sheet' ? $('qty_sheets-'+type_id+'-').value : $('qty_lbs-'+type_id+'-').value ),
				manufacturers_id:	$('manufacturers_id-'+type_id+'-').value,
				location_id: $('location_id-'+type_id+'-').value
			},
			onSuccess: function (transport) { 
var tr = $('new-'+type_id);
if ( ! tr ) { alert('totals not found'); } else {
new Insertion.After('new-'+type_id, transport.responseText);
$('rfidtag_id-'+type_id+'-').value = '';
$('rfidtag_id-'+type_id+'-').focus();
return true;
}
 }, 
			evalScripts: true
		}
	);

	if ( $('qty_sheets-'+type_id+'-') ) $('qty_sheets-'+type_id+'-').value = '';
	if ( $('qty_lbs-'+type_id+'-') ) $('qty_lbs-'+type_id+'-').value = '';
	if ( $('qty_feet-'+type_id+'-') ) $('qty_feet-'+type_id+'-').value = '';

}

function fix_content( c_id ) {
	new Ajax.Request( '_manifest_content.html', {
		parameters: { content_id: c_id, action: 'Fix' },
		onSuccess: function(transport){
			var tr = $('tr-'+c_id+'-error');
			if ( tr ) tr.remove();
			tr = $('tr-'+c_id);
			if ( tr ) {
				new Insertion.After( tr, transport.responseText);
				tr.remove();
				return true;
			} // end if
		},
		evalScripts: true
	 } );
} // end function fix_content( c_id )

function apply_content( c_id ) {
	new Ajax.Request( '_manifest_content.html', {
		parameters: { content_id: c_id, action: 'Apply' },
		onSuccess: function(transport){
			var tr = $('tr-'+c_id+'-error');
			if ( tr ) tr.remove();
			tr = $('tr-'+c_id);
			if ( tr ) {
				new Insertion.After( tr, transport.responseText);
				tr.remove();
				return true;
			} // end if
		},
		evalScripts: true
	 } );
} // end function apply_content( c_id )

function manifest_onsubmit(form) {

	var re = /^brand-(\d+)$/;
	var fields_to_check = ['Manufacturer','Owner','Brand','Finish','Colour'];
	for ( var i = 0, len = form.elements.length; i < len; i += 1 ) {
		var matches = re.exec( form.elements[i].name );
		
		if ( matches ) {
			var type_id = matches[1];
			for ( var field_index = 0; field_index < fields_to_check.length; field_index += 1 ) {
				var field = fields_to_check[field_index];	
				var field_lc = field.toLowerCase();
			
				if ( ! ( 
					( form.elements[field_lc+'-'+type_id] && ( form.elements[field_lc+'-'+type_id].value != '' ) ) || 
					( form.elements[field_lc+'_id-'+type_id] && ( get_ddm_value( form.elements[field_lc+'_id-'+type_id] ) != '' ) ) 
				) ) {
					alert( 'Please select the ' + field + ' of the stock.' );
					var div = $(field+'-'+type_id+'_div');
					if ( div ) div.className = 'error';
					return false;
				} // end if
			} // end foreach field
		} // end if
	} // end for each element

	return true;
} // end function manifest_onsubmit

function type_onclick( e ) {
	var re = /^type-(\d+)$/;
	var matches = re.exec( e.name );
	var type_id = matches[1];

	if ( e.value == 'Roll' ) {
		$('PaperHeight-'+type_id).hide();$('MWeight-'+type_id).hide();
	} else if ( e.value == 'Sheet' ) {
		$('PaperHeight-'+type_id).show();$('MWeight-'+type_id).show();
	} else {
		alert('unsupported type ' + e.value );
	} // end if
	var values = getValues( e.form, new RegExp('\-'+type_id+'\-') );
	values.set('type_id', type_id );
	values.set('type-'+type_id, e.value );

	new Ajax.Updater( 'ManifestContents'+type_id, '_manifest_contents.html', { parameters: values } );
} // end func

function select_stock( type_id, stock_id ) {
	new Ajax.Request( '_select_stock.json', { parameters: { suffix: '-'+type_id, stock_id: stock_id },
		evalScripts: true
 } );
}

function confirm_po_content(type_id,poc_id) {
	new Ajax.Request('/employee/inventory/_manifest_type.json', { 
		parameters: { 
				action: 'confirm_po_content', 
				manifest_content_type_id: type_id,
				po_content_id: poc_id 
			}
		}
	);
}
function unconfirm_po_content(type_id,poc_id) {
	new Ajax.Request('/employee/inventory/_manifest_type.json', { 
		parameters: { 
				action: 'unconfirm_po_content', 
				manifest_content_type_id: type_id,
				po_content_id: poc_id 
			}
		}
	);
}

function select_po(type_id, po_id) {
	var input = $j('#po_id-'+type_id);
	if ( ! input ) {
		console.log("No input found for #po_id-"+type_id);
	} else {
		input.val(po_id);
	}
}

function load_pos(type_id) {
	new Ajax.Updater('PurchaseOrders'+type_id, '_manifest_purchase_orders.html', {
			parameters: {
				supplier_id: $('supplier_id').value,
				Docket: $('docket-'+type_id).value,
				type_id: type_id
				}
				} );
}

function load_po_contents(type_id) {
	var input = $j('#po_id-'+type_id);
	if ( !input ) {
		console.log("No input found for #po_id-"+type_id);
	} else if ( !input.val() ) {
		console.log("No po to load");
	} else {
		new Ajax.Updater(
				'PO_'+type_id,
				'/employee/inventory/_manifest_purchase_order_contents.html', { 
			parameters: { 
					type_id: type_id,
					po_id: input.val()
				}
			}
		);
	}
}
