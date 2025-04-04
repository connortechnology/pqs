
var filters = new Array( 'Owner', 'Group', 'Manufacturer', 'Brand','Finish','Colour','Weight','Quality', 'Size','Material','type','width','height' );

function filter_onChange( element, id, selected ) {
	var form = element.form;
	var h = new Hash();
	h.set('form', form.id);
	h.set('id', id );
	h.set('selected', element.name);
	for ( var index = 0, len = filters.length; index < len; ++index ) {
		var filter = form.elements[filters[index]+id];
		if ( filter ) {
			h.set(filters[index], get_value( filter ) );
			if ( filter.type == 'select-one' ) {
			filter.disabled = true;
			} // end if
			filter = form.elements[filters[index]+'_exclude'+id];
			if ( filter ) {
				h.set(filter.name, get_value( filter ) );
			} // end if
		} // end if filter exists
		filter = form.elements[filters[index].toLowerCase()+'_id'+id];
		if ( filter ) {
			var v = get_value( filter );
			if ( ! v ) continue;
			
			h.set(filter.name, v );
			if ( filter.type == 'select-one' ) {
				filter.disabled = true;
			} // end if
			filter = form.elements[filters[index].toLowerCase()+'_id_exclude'+id];
			if ( filter ) {
				var v = get_value( filter );
				if ( v ) h.set(filter.name, v );
			} // end if
		} // end if filter exists
	} // end for 
	new Ajax.Request( '/employee/inventory/_stock.json', { parameters: h, evalScripts: true } );
} // end function Name_onChange()

function cbStockFillResults( results ) {
  console.log('cbStockFillResults');
	const form = $(results.get('form'));
	if (!form) {
		alert('No form for ' + results.get('form') );
		return;
	} // end if
	results.unset('form');

	let id = '';
	if ( id = results.get('id') ) {
		results.unset('id');
	} else {
		id = '';
	}

	const keys = results.keys();
	for ( let index = 0, len = keys.length; index < len; ++index ) {
		const key = keys[index];
		const value = results.get(key);

		let ddm = null;
		if ( ! ddm ) { ddm = form.elements[key+'_id'+id]; } // end if
		if ( ! ddm ) { ddm = form.elements[key.toLowerCase()+'_id'+id]; } // end if
		if ( ! ddm ) { ddm = form.elements[key+id]; } // end if
		if ( ! ddm ) {
			//alert('No ddmStock'+key+id );
			continue;
		} else if ( ddm.type != 'select-one' ) {
			//alert('wrong type ddmStock'+key+id + ' type: ' + ddm.type);
			continue;
		//} else {
			//alert(ddm.name);
		} // end if
		var selectedValue = ddm.getValue();

		var options = new Array();
		options[0] = create_option( '', 'select one' );
		for ( var ddm_index = 0, ddm_len = value.length; ddm_index < ddm_len; ddm_index += 2 ) {
			options[options.length] = create_option( value[ddm_index], value[ddm_index+1] );
		} // end for
		fill_ddm( ddm, options );
		if ( options.length == 2 ) {
			ddm_select_by_index( ddm, 1 );
		} else {
			ddm_select_by_value( ddm, selectedValue );
		} // end if
	} // end for each key

	// turn drop downs back on
	for ( var index = 0, len = filters.length; index < len; ++index ) {
		var filter_name = filters[index];

		var filter = form.elements[filter_name+id];
		if ( filter ) {
			filter.disabled = false;
			continue;
		} // end if filter exists

		filter = form.elements[filter_name];
		if ( filter ) {
			filter.disabled = false;
			continue;
		} // end if filter exists
		
		filter_name = filter_name.toLowerCase();
		filter = form.elements[filter_name+'_id'+id];
		if ( filter ) {
			filter.disabled = false;
			continue;
		} // end if filter exists
		filter = form.elements[filter_name+'_id'];
		if ( filter ) {
			filter.disabled = false;
			continue;
		} // end if filter exists
		//alert('filter not found ' + filter_name );
	} // end for 
	calc(form.name);
} // end function Stock_Fill

function calc_from_basis_weight( form, id='' ) {
	var basis_weight = form.elements['basis_weight'+id] ? parseFloat(1*form.elements['basis_weight'+id].value) : parseFloat(1*form.elements['basis_mweight'+id].value);
	var basis_width = parseFloat(1*form.elements['basis_width'+id].value);
	var basis_height = parseFloat(1*form.elements['basis_height'+id].value);
	if ( basis_width && basis_height ) {
		var gsm = parseInt((basis_weight/1000)/(basis_width*basis_height)*7030645.0)/10;
		form.elements['gsm'+id].value = gsm;
		var width = parseFloat(1*form.elements['width'+id].value);
		var height = parseFloat(1*form.elements['height'+id].value);
		form.elements['mweight'+id].value = (((gsm/703064.5)*(width*height)*10000)/10).round();
	}
}
function calc_from_mweight( form, id='' ) {
	var mweight = parseFloat(1*form.elements['mweight'+id].value);
	var width = parseFloat(1*form.elements['width'+id].value);
	var height = parseFloat(1*form.elements['height'+id].value);
	var gsm = parseInt((mweight/1000)/(width*height)*7030645.0)/10;
	form.elements['gsm'+id].value = gsm;
	var basis_width = parseFloat(1*form.elements['basis_width'+id].value);
	var basis_height = parseFloat(1*form.elements['basis_height'+id].value);
	if ( basis_width && basis_height )
		form.elements['basis_weight'+id].value = parseInt((gsm/703064.5)*(basis_width*basis_height)*10000)/10;
}
function calc_from_gsm( form, id='' ) {
	var gsm = parseFloat(1*form.elements['gsm'+id].value);
	var width = parseFloat(1*form.elements['width'+id].value);
	var height = parseFloat(1*form.elements['height'+id].value);
	var basis_width = parseFloat(1*form.elements['basis_width'+id].value);
	var basis_height = parseFloat(1*form.elements['basis_height'+id].value);
	form.elements['mweight'+id].value = parseInt((gsm/703064.5)*(width*height)*10000)/10;
	if ( basis_width && basis_height )
	  form.elements['basis_weight'+id].value = parseInt((gsm/703064.5)*(basis_width*basis_height)*10000)/10;
}
function calc_from_weight(form, id='') {
	var weight = parseFloat(1*form.elements['weight'+id].value);
	var basis_weight = weight*2;
	form.elements['basis_weight'+id].value = basis_weight;
	calc_from_basis_weight(form,id);
}

function set_basis_dimensions(width, height) {
var basis_width = $('basis_width');
if ( basis_width )
	basis_width.value = width;
var basis_height=$('basis_height');
if ( basis_height )
	basis_height.value = height;
basis_weight_to_gsm($('f1'));
}
