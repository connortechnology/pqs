"use strict";

function check_price( element ) {
	const form = element.form;
  const matches = element.name.match( /^\w+\-(\d+)$/ );
	if (matches) {
		const id = matches[1];
		if ( 
			element_changed( form.elements['discountable-'+id] ) ||
			element_changed( form.elements['price-'+id] ) ||
			element_changed( form.elements['markup-'+id] ) ||
			element_changed( form.elements['min-'+id] ) ||
			element_changed( form.elements['max-'+id] ) ||
			element_changed( form.elements['units-'+id] ) ||
			element_changed( form.elements['equipment_id-'+id] ) 
		   ) {
			$('paperprice-'+id).addClassName('changed');
		} else {
			$('paperprice-'+id).removeClassName('changed');
		} // end if
	} else {
		alert('Not matched' + element.name);
	} // end if
}

function basis_weight_to_gsm( form ) {
  const basis_weight = parseFloat(1*form.elements['basis_mweight'].value);
  const basis_width = parseFloat(1*form.elements['basis_width'].value);
	const basis_height = parseFloat(1*form.elements['basis_height'].value);
	const width = parseFloat(1*form.elements['width'].value);
	const height = parseFloat(1*form.elements['height'].value);

	const gsm = Math.round((basis_weight/1000)/(basis_width*basis_height)*70306450)/100;
	form.elements['gsm'].value = gsm;
	form.elements['mweight'].value = Math.round((gsm/703064.5)*(width*height)*100000)/100;
	form.elements['wpsi'].value = gsm / 703064.5;
	recalc_prices( form );
}

function mweight_to_gsm( form ) {
	let mweight;
	let width;
	let height;
	if ( get_value( form.elements['type'] ) == 'Roll' ) {
		mweight = parseFloat(1*form.elements['basis_mweight'].value);
		width = parseFloat(1*form.elements['basis_width'].value);
		height = parseFloat(1*form.elements['basis_height'].value);
	} else { // sheet
		mweight = parseFloat(1*form.elements['mweight'].value);
		width = parseFloat(1*form.elements['width'].value);
		height = parseFloat(1*form.elements['height'].value);
	} //e nd if

	const gsm = Math.round((mweight/1000)/(width*height)*70306450)/100;
	form.elements['gsm'].value = gsm;
	form.elements['wpsi'].value = gsm / 703064.5;

	//const basis_mweight = Math.round(wpsi*(width*height)*100000)/100;
	const basis_width = parseFloat(1*form.elements['basis_width'].value);
	const basis_height = parseFloat(1*form.elements['basis_height'].value);
	form.elements['basis_mweight'].value = Math.round( (gsm / 703064.5) * basis_width *basis_height *1000);
	recalc_prices( form );
}

function gsm_to_mweight( form ) {
	const basis_width = parseFloat(1*form.elements['basis_width'].value);
	const basis_height = parseFloat(1*form.elements['basis_height'].value);
	const gsm = parseFloat(1*form.elements['gsm'].value);
	const wpsi = gsm/703064.5;
	const basis_mweight = Math.round(wpsi*(basis_width*basis_height)*1000);
	form.elements['basis_mweight'].value = basis_mweight;

	const width = parseFloat(1*form.elements['width'].value);
	const height = parseFloat(1*form.elements['height'].value);
	const mweight = Math.round(wpsi*(width*height)*1000);
	form.elements['mweight'].value = mweight;
	form.elements['wpsi'].value = wpsi;
	recalc_prices(form);
}

function CommaFormatted(amount) {
	const delimiter = ','; // replace comma if desired
	let a = amount.split('.',2)
	const d = a[1];
	const i = parseInt(a[0]);
	if (isNaN(i)) { return ''; }
	const minus = '';
	if (i < 0) { minus = '-'; }
	i = Math.abs(i);
	let n = new String(i);
	a = [];
	while (n.length > 3) {
		const nn = n.substr(n.length-3);
		a.unshift(nn);
		n = n.substr(0,n.length-3);
	}
	if (n.length > 0) { a.unshift(n); }
	n = a.join(delimiter);
	if (d.length < 1) { amount = n; }
	else { amount = n + '.' + d; }
	amount = minus + amount;
	return amount;
} // end of function CommaFormatted()

function CurrencyFormatted(amount) {
	let i = parseFloat(amount);
	if (isNaN(i)) { i = 0.00; }
	let minus = '';
	if (i < 0) { minus = '-'; }
	i = Math.abs(i);
	i = parseInt((i + .005) * 100);
	i = i / 100;
	let s = new String(i);
	if(s.indexOf('.') < 0) { s += '.00'; }
	if(s.indexOf('.') == (s.length - 2)) { s += '0'; }
	s = minus + s;
	return s;
} // end of function CurrencyFormatted()

function recalc_prices( form ) {
	for (let i = 0, len=form.elements.length; i < len; i += 1) {
		if (form.elements[i].name && (form.elements[i].name.indexOf('cost-') != -1)) {
			calc_price(form.elements[i]);
		} // end if
	} // end for
} // end function recalc_prices( form )

function calc_price( element ) {
	const form = element.form;
	let matches = element.name.match( /^cost-(.*)$/ );
	if (matches) {
		const index = matches[1];
		const costcwt = parseFloat( element.value.replace(/[^\d\-\.]/g, '' ) );
		const markup = parseFloat(1*form.elements['markup-'+index].value.replace(/[^\d\-\.]/g, '' )) /100;
		const pricecwt = costcwt * ( 1 + markup );
		form.elements['price-'+index].value = do_decimals( pricecwt, 2 ); 

		if ( form.elements['wpsi'] ) {
			if ( form.elements['costperfoot-'+index] ) {
				form.elements['costperfoot-'+index].value = do_decimals( costcwt * form.elements['wpsi'].value * 144 / 100, 8);
				form.elements['priceperfoot-'+index].value = do_decimals( pricecwt * form.elements['wpsi'].value * 144 / 100, 2);
			} // end if
			if ( form.elements['costperm-'+index] ) {
				form.elements['costperm-'+index].value = do_decimals( costcwt * form.elements['wpsi'].value * form.elements['width'].value * form.elements['height'].value * 10, 2);
				form.elements['priceperm-'+index].value = do_decimals( pricecwt * form.elements['wpsi'].value * form.elements['width'].value * form.elements['height'].value * 10, 2);
			} // end if
		} else if ( form.elements['mweight'] && form.elements['mweight'].value ) {
			if ( form.elements['costperm-'+index] ) {
				form.elements['costperm-'+index].value = do_decimals( costcwt * form.elements['mweight'].value / 100, 2 );
				form.elements['priceperm-'+index].value = do_decimals( pricecwt * form.elements['mweight'].value / 100, 2 );
			} // end if
		} // end if
	} else if ( matches = element.name.match( /costperm-(.*)/ ) ) {
		const index = matches[1];
		const costperm = parseFloat( element.value.replace(/[^\d\-\.]/g, '' ) );
		const markup = parseFloat(1*form.elements['markup-'+index].value.replace(/[^\d\-\.]/g, '' )) /100;
		const priceperm = costperm * ( 1 + markup );
		form.elements['priceperm-'+index].value = do_decimals( priceperm, 2 ); 

		if ( form.elements['wpsi'] )  {
			form.elements['cost-'+index].value = do_decimals( costperm / (form.elements['wpsi'].value * form.elements['width'].value * form.elements['height'].value * 10), 2);
			form.elements['price-'+index].value = do_decimals( priceperm / (form.elements['wpsi'].value * form.elements['width'].value * form.elements['height'].value * 10), 2);
			if ( form.elements['costperfoot-'+index] ) {
			form.elements['costperfoot-'+index].value = do_decimals( costperm / (form.elements['wpsi'].value * 144 * 1000), 2);
			form.elements['priceperfoot-'+index].value = do_decimals( priceperm / (form.elements['wpsi'].value * 144 * 1000), 2);
			} // end if
		} else if ( form.elements['mweight'] && form.elements['mweight'].value ) {
			form.elements['cost-'+index].value = do_decimals( costperm / (form.elements['mweight'].value / 100), 2 );
			form.elements['price-'+index].value = do_decimals( priceperm / (form.elements['mweight'].value / 100), 2 );
		} // end if
	} else if ( matches = element.name.match( /costperfoot-(.*)/ ) ) {
		const index = matches[1];
		const costperfoot = parseFloat( element.value.replace(/[^\d\-\.]/g, '' ) );
		const wpsi = parseFloat( form.elements['wpsi'].value );
		if ( ! wpsi ) alert( 'No wpsi!' );
		//const costperinch = ( costperfoot/144 ) * 100/wpsi;
		// 100/wpsi = # of inches in 100lbs.
		const costcwt = ( 100 * costperfoot ) / ( 144 * wpsi );
		const costperm = costcwt * wpsi * form.elements['width'].value * form.elements['height'].value * 1000;
		const markup = parseFloat(1*form.elements['markup-'+index].value.replace(/[^\d\-\.]/g, '' )) /100;

		form.elements['priceperfoot-'+index].value = do_decimals( costperfoot * ( 1 + markup ), 2);
		form.elements['cost-'+index].value = do_decimals( costcwt, 5 );
		form.elements['price-'+index].value = do_decimals( costcwt * ( 1 + markup ), 2);
		if ( form.elements['costperm-'+index] ) {
			form.elements['costperm-'+index].value = do_decimals( costperm, 2);
			form.elements['priceperm-'+index].value = do_decimals( costperm * ( 1 + markup ), 2 ); 
		} // end if
	} else if ( matches = element.name.match( /markup-(.*)/ ) ) {
		const index = matches[1];

		const markup = parseFloat( 1*(element.value.replace(/[^\d\-\.]/g, '' ) ) );

		const costcwt = parseFloat( form.elements['cost-'+index].value.replace(/[^\d\-\.]/g, '' ) );
		if ( costcwt != '' ) {
			const newvalue = costcwt * ( markup/100 + 1 );
			form.elements['price-'+index].value = do_decimals( newvalue, 2 );
		} // end if
		if ( form.elements['costperm-'+index] ) {
			const costperm = parseFloat( form.elements['costperm-'+index].value.replace(/[^\d\-\.]/g, '' ) );
			if ( costperm != '' ) {
				const newvalue = costperm * ( markup/100 + 1 );
				form.elements['priceperm-'+index].value = do_decimals( newvalue, 2 );
			} // end if
		} // end if
		if ( form.elements['costperfoot-'+index] && form.elements['priceperfoot-'+index] ) {
			const costperfoot = parseFloat( form.elements['costperfoot-'+index].value.replace(/[^\d\-\.]/g, '' ) );
			form.elements['priceperfoot-'+index].value = do_decimals( costperfoot * ( 1 + markup/100 ), 2);
		} // end if
	} else if ( matches = element.name.match( /price-(.*)/ ) ) {
		const index = matches[1];

		const costcwt = parseFloat(form.elements['cost-'+index].value.replace(/[^\d\-\.]/g, '' ) );
		const price = parseFloat( element.value.replace(/[^\d\-\.]/g, '' ) );
		if ( costcwt ) {
			form.elements['markup-'+index].value = do_decimals( ((price / costcwt)-1)*100, 2 );
		
			if ( form.elements['priceperm-'+index] ) {
				form.elements['priceperm-'+index].value = do_decimals( form.elements['costperm-'+index].value * ( 1 + form.elements['markup-'+index].value/100), 2 );
			} // end if
		} // end if
	} else if ( matches = element.name.match( /priceperm-(.*)/ ) ) {
		const index = matches[1];

		const priceperm = parseFloat( element.value.replace(/[^\d\-\.]/g, '' ) );
		const costperm = parseFloat(form.elements['costperm-'+index].value.replace(/[^\d\-\.]/g, '' ) );
		if ( costperm ) {
			form.elements['markup-'+index].value = do_decimals( ((priceperm / costperm)-1)*100, 2 );
			form.elements['price-'+index].value = do_decimals( form.elements['costcwt-'+index].value * ( 1 + form.elements['markup-'+index].value/100), 2 );
			if ( form.elements['costperfoot-'+index] && form.elements['priceperfoot-'+index] ) {
				form.elements['priceperfoot-'+index].value = do_decimals( form.elements['costcwt-'+index].value * ( 1 + form.elements['markup-'+index].value/100), 2 );
			} // end if
		} // end if
	} // end if
} // end function
