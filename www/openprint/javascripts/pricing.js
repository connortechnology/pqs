"use strict";

function calc_from_quantity(element) {
  let precision = element.getAttribute('precision');
  if (!precision) precision = 5;
  const re = /quantity-(.*)/
  const matches = re.exec( element.name );
  if ( matches ) {
    const index = matches[1];
    const quantity = parseFloat( floatize( element ) );
    const markup = parseFloat(1*floatize( element.form.elements['markup-'+index] ) ) /100;
    const cost = parseFloat(1* floatize( element.form.elements['cost-'+index] ) );
    if (element.form.elements['total-'+index]) {
      element.form.elements['price-'+index].value = do_decimals( cost * ( 1 + markup ), precision );
      element.form.elements['total-'+index].value = do_decimals( cost * quantity * ( 1 + markup ), precision );
    } else {
      element.form.elements['price-'+index].value = do_decimals( cost * quantity * ( 1 + markup ), precision );
    }
    if ( element.form.elements['chk-'+index] ) {
      element.form.elements['chk-'+index].checked=true;
    } // end if
  } else {
    console.log("calc_from_quantity called from something other than a quantity "+element.name);
  } // end if
} // end function calc_from_quantity

function calc_from_cost(element) {
  let precision = element.getAttribute('precision');
  if (!precision) precision = 5;
  const elements = element.form.elements;
  const re = /cost-(.*)/;
  const matches = re.exec(element.name);
  if (matches) {
    const index = matches[1];
    const cost = parseFloat(floatize(element));
    const markup = parseFloat(1* floatize(elements['markup-'+index])) /100;
    const quantity = elements['quantity-'+index] ? parseFloat(1* floatize(elements['quantity-'+index])) : 1;
    if (elements['total-'+index]) {
      elements['price-'+index].value = do_decimals( cost * ( 1 + markup ), precision );
      elements['total-'+index].value = do_decimals( cost * quantity * ( 1 + markup ), precision );
    } else {
      elements['price-'+index].value = do_decimals( cost * quantity * ( 1 + markup ), precision );
    }
    if (elements['chk-'+index]) {
      elements['chk-'+index].checked=true;
    } // end if
  } else {

  } // end if matched
} // end function calc_from_cost

function calc_from_markup(element) {
  let precision = element.getAttribute('precision');
  if (!precision) precision = 5;
  const elements = element.form.elements;

  const re = /markup-(.*)/
  const matches = re.exec( element.name );
  if ( matches ) {
    const index = matches[1];

    const cost = parseFloat(floatize(elements['cost-'+index]));
    if (cost != '') {
      const markup = parseFloat(1*floatize(element))/100;
      const quantity = elements['quantity-'+index] ?parseFloat(1*floatize(elements['quantity-'+index])) : 1;

      if (elements['total-'+index]) {
        elements['price-'+index].value = do_decimals( cost * ( 1 + markup ), precision );
        elements['total-'+index].value = do_decimals( cost * quantity * ( 1 + markup ), precision );
      } else {
        elements['price-'+index].value = do_decimals( cost * quantity * ( 1 + markup ), precision );
      } // end if
    } // end if

    if (elements['chk-'+index]) {
      elements['chk-'+index].checked = true;
    } // end if
  } // end if matches
} // end function

function calc_from_price(element) {
  let precision = element.getAttribute('precision');
  if (!precision) precision = 5;
  const elements = element.form.elements;
	const re = /^price-(.*)$/;
	const matches = re.exec( element.name );
	if ( matches ) {
		const index = matches[1];

		if (!elements['cost-'+index] ) {
			alert("No cost element for " + index);
			return;
		} // end if
		const cost = parseFloat( floatize(elements['cost-'+index] ) );
		const price = parseFloat( floatize(element) );
		if ( cost ) {
			const quantity = elements['quantity-'+index] ? parseFloat(1*floatize(elements['quantity-'+index])) : 1;
			elements['markup-'+index].value = do_decimals( ((price / (cost*quantity))-1)*100, precision );
		} // end if
    if (elements['total-'+index]) {
		  elements['total-'+index].value = do_decimals( cost * quantity * ( 1 + markup ), precision );
    }
		if (elements['chk-'+index]) {
			elements['chk-'+index].checked=true;
		} // end if
	} // end if
} // end function

// New price to pricelist
function add_price(btn) {
  const form = btn.form;
  const data = Object.fromEntries(new FormData(form));

  const pricelist_id = btn.getAttribute('data_pricelist_id');
  const equipment_id = $j('#ddmEquipment-'+pricelist_id).val();
  const content = '_prices_per_equipment.html';

  let id;
  let url = '/administrator/services/'+content;
  if (id = btn.getAttribute('data_service_id')) {
    data.service_id = id;
  } else {
    id = btn.getAttribute('data_material_id');
    url = '/administrator/materials/'+content;
    data.material_id = id;
  }

  const prices_id = '#pricelist-'+pricelist_id;
  const div = $j(prices_id);
  if (!div.length) {
    alert('Prices div not found for '+prices_id);
    return;
  }
  div.html('Please wait...loading.');
	div.load(url+'?action=add&pricelist_id='+pricelist_id+'&equipment_id='+equipment_id);
} /* end function add_price() */

function del_price(btn) {
  const form = btn.form;
  const pricelist_id = btn.getAttribute('data_pricelist_id');
  const equipment_id = btn.getAttribute('data_equipment_id');
  const price_id = btn.getAttribute('data_price_id');
  const data = {
    pricelist_id: pricelist_id,
    equipment_id: equipment_id,
    action: 'delete'
  };
  let id;
  let url = '/administrator/services/_prices_table_body.html';
  if (!(id = btn.getAttribute('data_service_id'))) {
    id = btn.getAttribute('data_material_id');
    data.material_id = id;
    url = '/administrator/materials/_prices_table_body.html';
  } else {
    data.service_id = id;
  }
  if (!id) {
    alert("Failed to identify the price. Will not proceed");
    return;
  }
  const prices_id = '#prices-'+pricelist_id+'-'+equipment_id+'-'+id;
  const div = $j(prices_id);
  div.html('Please wait...loading.');
	div.load(url+'?price_id='+price_id, data, function() {
      update_event_bindings();
      });
} /* end function del_price() */

function copy_price(btn) {
  const form = btn.form;
  const pricelist_id = btn.getAttribute('data_pricelist_id');
  const equipment_id = btn.getAttribute('data_equipment_id');
  let id;
  let url = '/administrator/services/_prices_table_body.html';
  if (!(id = btn.getAttribute('data_service_id'))) {
    id = btn.getAttribute('data_material_id');
    url = '/administrator/material/_prices_table_body.html';
  }

  const price_id = btn.getAttribute('data_price_id');

  const prices_id = '#prices-'+pricelist_id+'-'+equipment_id+'-'+id;
  const div = $j(prices_id);
  div.html('Please wait...loading.');
  const data = Object.fromEntries(new FormData(form));
	div.load(url+'?action=copy&price_id='+price_id, data, function() {
      update_event_bindings();
      });
} /* end function copy_price() */

function add_new_price(btn) {
  const form = btn.form;
  const pricelist_id = btn.getAttribute('data_pricelist_id');
  let equipment_id = btn.getAttribute('data_equipment_id');
  if (!equipment_id) {
    equipment_id = $j('#equipment_id-'+pricelist_id).val();
  }
  const data = {
    pricelist_id: pricelist_id,
    equipment_id: equipment_id,
    action: 'add'
  };
  let id;
  let url = '/administrator/services/';
  if (id = btn.getAttribute('data_service_id')) {
    data.service_id = id;
  } else {
    id = btn.getAttribute('data_material_id');
    url = '/administrator/materials/';
    data.material_id = id;
  }

  let prices = $j('#prices-'+pricelist_id+'-'+equipment_id+'-'+id);
  if (prices.length) {
    // If there is already a section for the equipment, add it to that section instead of creating a new one.
    $j.get(url+'_price.html', data).done(function(data) {
      prices.append(data);
      update_event_bindings();
    }).fail(function(data) {
      alert("Failed adding price");
      console.log(data);
    });
  } else {
    $j.get(url+'_prices_per_equipment.html', data).done(function(data) {
      $j('#pricelist-'+pricelist_id).append(data);
      update_event_bindings();
    }).fail(function(data) {
      alert("Failed adding equipment price");
    console.log(data);
    });
	} // end if
} // end function add_new_price(btn)

function check_price( element ) {
  var form = element.form;
  var matches;
  if ( matches = element.name.match( /^\w+\-(\d+)$/ ) ) {
    var id = matches[1];
    var container = $('Price-'+id);

    if ( ! container ) {
      console.error("No element found for Price-"+id);
      return;
    }
    if (
      element_changed( form.elements['min-'+id] ) ||
      element_changed( form.elements['max-'+id] ) ||
      element_changed( form.elements['units-'+id] ) ||
      element_changed( form.elements['cost-'+id] ) ||
      element_changed( form.elements['markup-'+id] ) ||
      element_changed( form.elements['price-'+id] ) ||
      element_changed( form.elements['discount-'+id] )
    ) {
      container.addClassName('changed');
    } else {
      container.removeClassName('changed');
    } // end if
  } else {
    alert('Not matched' + element.name);
  } // end if
} // end function check_field

