function calc_price( element ) {
	var re = /(.*)-(.*)/
	var matches = re.exec( element.name );
	if ( matches ) {
		var index = matches[2];
		var alert_div = $('alert-'+index);
		if ( ! alert_div ) alert("alert-"+index+' does not exist.');
		alert_div.innerHTML = '';
		
	
		// ALl types should have cost, quantity, total
		$('cost-'+index).value = $('cost-'+index).value.replace(/[^\d\-\.]/g, '' );
		var cost = parseFloat( $('cost-'+index).value );
		if ( ! cost ) alert_div.innerHTML += 'Please enter cost.<br/>';

		$('quantity-'+index).value = $('quantity-'+index).value.replace(/[^\d\-\.]/g, '' );
		var qty = parseFloat( $('quantity-'+index).value );

		var quantity_units;
		if ( $('quantity_units-'+index) ) 
			quantity_units = get_ddm_value( $('quantity_units-'+index) );


		var type_element = $('type_id-'+index);
		var type = type_element.options[type_element.selectedIndex].text;

		var weight;
		var weight_units;
		var weight_element = $('weight-'+index);
		if ( weight_element ) {
			if ( type == 'Stock' ) {
				var mweight = parseFloat( $('mweight-'+index).value.replace(/[^\d\-\.]/g, '' ) );
				if ( quantity_units == 'Rolls' ) {
				} else if ( quantity_units == 'Sheets' ) {
					weight_element.value = qty * mweight / 1000;
				} else {
					alert('unknown quantity_units ' + quantity_units );
				} // end if
				qty = 1;
			} else {
				weight_element.value = weight_element.value.replace(/[^\d\-\.]/g, '' );
			} // end if
			weight = parseFloat( weight_element.value );
			weight_units = $('weight_units-'+index).value;
		} // end if weight_element

		var cost_units = $('cost_units-'+index).value;
		if ( cost_units == '/100lb' ) {
			if ( ! qty ) {
				alert_div.innerHTML += 'Please enter the quantity of items at the given weight in the quantity field.';
				$('quantity-'+index).value = 1;
				qty = 1;
			} // end if
			if ( ! weight_units ) {
				ddm_select_by_value( $('weight_units-'+index), 'lb' );
				weight_units = 'lb';
			} else if ( weight_units != 'lb' ) {
				alert_div.innerHTML += 'The weight is given in ' + weight_units + ' but should be in lbs';
			} // end if
			qty = weight * qty / 100;
		} else if ( cost_units == '/M' ) {
			if ( ! qty )
				alert_div.innerHTML += 'Please enter quantity.<br/>';
			qty = qty/1000;
		} else if ( cost_units == '/1000' ) {
			if ( ! qty )
				alert_div.innerHTML += 'Please enter quantity.<br/>';
			qty = qty/1000;
		} else if ( cost_units == '/Kg' ) {
			if ( ! qty ) {
				alert_div.innerHTML += 'Please enter the quantity of items at the given weight in the quantity field.';
				$('quantity-'+index).value = 1;
				qty = 1;
			} // end if
			if ( ! weight_units ) {
				ddm_select_by_value( $('weight_units-'+index), 'Kg' );
				weight_units = 'Kg';
			} else if ( weight_units != 'Kg' ) {
				alert_div.innerHTML += 'The weight is given in ' + weight_units + ' but should be in Kgs';
			} // end if
		} else if ( cost_units == '/Hr.' ) {
			if ( ! qty ) 
				alert_div.innerHTML += 'Please enter the # of hours.<br/>';
		} else if ( cost_units == 'Each' ) {
			if ( ! qty )
				alert_div.innerHTML += 'Please enter quantity.<br/>';
		} // end if
		$('total-'+index).value = do_decimals( cost * qty, 2 );
		if ( weight && ! weight_units ) {
			alert_div.innerHTML += 'Please select the units that the weight are in.<br/>';
		} // end if
	} // end if
	if ( $('subtotal') ) update_totals( element.form );
} // end function calc_price

function update_totals( form ) {
	var subtotal = 0;
	var total;
	var re = /total-(.+)/

	for ( var index = 0; index < form.elements.length; index += 1 ) {
		var e = form.elements[index];
		var matches = re.exec( e.name );
		if ( matches ) {
			subtotal += parseFloat(1*e.value);
		} // end if
	} // end for
	//$('subtotal').innerHTML = subtotal;
	$('subtotal').innerHTML = do_decimals( subtotal, 2 );
	var total = subtotal;
	var tax = 0;
	for ( var tax_index = 0, len = tax_ids.length; tax_index < len; tax_index ++ ) {
		if ( form.elements['tax_charge-'+tax_ids[tax_index]].checked ) {
			tax = subtotal * $('tax_rate-'+tax_ids[tax_index]).innerHTML/100;
		} else {
			tax = 0;
		} // end if
		$('tax-'+tax_ids[tax_index]).innerHTML = do_decimals( tax, 2 );
		total += parseFloat( tax );
	} // end for
	$('total').innerHTML = do_decimals( total, 2 );
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

var project_description_options = {
	mode: "specific_textareas",
	editor_selector : "project_description",
	theme : "advanced",
	theme_advanced_buttons1 : "bold,italic,underline,strikethrough,|,justifyleft,justifycenter,justifyright,justifyfull,|,fontsizeselect,formatselect,bullist,numlist,outdent,indent,undo,redo,html",
	theme_advanced_buttons2 : '',
	theme_advanced_buttons3 : '',
	auto_resize : true,
	cleanup : true
};
    var content_description_options = {
	mode: "specific_textareas",
	editor_selector : "content_description",
        theme : "advanced",
		theme_advanced_buttons1 : "bold,italic,underline,strikethrough,|,justifyleft,justifycenter,justifyright,justifyfull,|,fontsizeselect",
		theme_advanced_buttons2 : "formatselect,bullist,numlist,outdent,indent",
		theme_advanced_buttons3 : '',
		auto_resize : true,
		cleanup : true
    };

function textarea_init() {
    tinyMCE.init( project_description_options );
    tinyMCE.init( content_description_options );
}
textarea_init();


function save_content(form, content_id ) {
	tinyMCE.triggerSave();
	if ( true ) {
		form.elements['action'].value = 'SaveContent';
		form.submit();
	} else {
		var parameters = getValues( form, new Array(
					'starting_year', 'starting_month', 'starting_day', 'starting_hour', 'starting_minute',
					'ending_year', 'ending_month', 'ending_day', 'ending_hour', 'ending_minute',
					'user_id', 'docket', 'description-new', 'notes', 'project_id'
				) );
		parameters.set('action','SaveContent');
		new Ajax.Updater( 'Contents','_contents.html', {
				method: 'post', 
				parameters: parameters,
				onComplete: textarea_init,
				evalScripts: true
			}
		);
	} // end if
} // end function save_content(form, content_id)
function delete_content(form, content_id ) {
	tinyMCE.triggerSave();
	new Ajax.Updater( 'Contents','_contents.html', {
			parameters: {
				project_id: form.project_id.value,
				content_id: content_id,
				action: 'delete'
			},
			onComplete: textarea_init,
			evalScripts: true
		}
	);
} // end function delete_content(form, content_id)
function edit_content( form, content_id ) {
	new Ajax.Updater( 'content-'+content_id, '_content_edit.html', {
			parameters: {
				project_id: form.project_id.value,
				content_id: content_id,
			},
			onComplete: textarea_init,
			evalScripts: true
		}
	);
} // end function edit_content

function copy_content(form, content_id ) {
	tinyMCE.triggerSave();
	new Ajax.Updater( 'Contents','_contents.html', {
			parameters: {
				project_id: form.project_id.value,
				content_id: content_id,
				action: 'copy'
			},
			onComplete: textarea_init,
			evalScripts: true
		}
	);
} // end function delete_content(form, content_id)

function view_content( content_id ) {
	new Ajax.Updater( 'content-'+content_id, '_content_view.html', {
			parameters: {
				content_id: content_id,
			},
			onComplete: textarea_init,
			evalScripts: true
		}
	);
} // end function view_content

