/* Utilities JS

	Show / Hide Details using (+) Icon.
		Apply a "hidden-details" class to fieldsets to Hide the Fieldset, or the fieldset's contents by Default.
		A (+) Icon will appear on the Fieldset's Parent Fieldset, or on itself if no Parent FIeldset is present.
		Clicking the (+) will display hidden details, and change the Icon to (-)
		Clicking again will revert back.
*/

// FIELDSET ICON CODE
//

// Load Show Hide Details (+) Fieldset Icon
Event.observe(window, 'load', function () {
	// Get All Icons
	var hidden_details = document.getElementsByClassName('hidden-details');

	if (hidden_details.length == 0) return;

	// For All Icons
	for (var i=0; i < hidden_details.length; i++) {
		// Must get parent before checking, because can be fieldset initially
		var parent_elem = hidden_details[i].parentNode;

		while (parent_elem && !parent_elem.tagName.match(/^body|fieldset$/i) ) { 
			parent_elem = parent_elem.parentNode;
		}

		if (parent_elem.tagName.match(/^fieldset$/i)) {
			if (parent_elem.details) {
				parent_elem.details.push(hidden_details[i]);
			}
			else {
				parent_elem.details = [hidden_details[i]];
				details_icon (parent_elem, 1, '+', 'pointer');
			}

			hidden_details[i].style.display = 'none';
		}
		else {
			hidden_details[i].details = false;
			var icon = details_icon (hidden_details[i], 1, '+', 'pointer');
			fieldset_details_toggle(icon);
		}
	}
});


// Absolutely Positions the Icon within the Containing Element
// from the Top Right corner, based on numbered position starting at Zero.
// Icon Positions: Help = 0; Details = 1;
function icon_pos (ico_elem, ico_pos) {
// Private Function

	ico_elem.parentNode.style.position = 'relative';

	ico_elem.style.right = ((ico_pos * 2.65) + 1.925) + 'em';
	
	// Icon ReAdjustment
	if (ico_elem.offsetTop == -2) {
		// FireFox
		ico_elem.style.marginTop = '-2.9ex';
	}
	else if (ico_elem.offsetTop == 0) {
		// IE
		ico_elem.style.marginTop = '0.3ex';
		ico_elem.style.marginRight = '-1em';
	}
	else if (ico_elem.offsetTop == 2) {
		// Safari
		ico_elem.style.marginTop = '0.2ex';
		ico_elem.style.marginRight = '-1em';
	}
	else {
		// Catch if/when IE or Safari Change
		ico_elem.style.marginTop = '0.3ex';
		ico_elem.style.marginRight = '-1em';
	}
}


// Creates Icons.
function create_icon (ico_container, ico_pos, ico_text, ico_cursor) {
	// Create Objects
	var icon = document.createElement('div');
	var inner_text = document.createTextNode('( ' + ico_text + ' )');

	// Assemble Objects
	icon.appendChild(inner_text);
	ico_container.appendChild(icon);
	
	// Add Class Identifier
	Element.addClassName(icon, 'icon');

	icon.disabled = false;

	// Position Icon
	icon_pos(icon, ico_pos);
	
	// Apply Cursor
	if (ico_cursor) { icon.style.cursor = ico_cursor };
	
	return icon;
}


function fieldset_details_toggle (elem) {
	// Collects Icon's Parent & Siblings
	var elem_parent = elem.parentNode;
	var elem_siblings = elem_parent.childNodes;

	// Style Formatting Variables
	var display_children, display_borders;
	
	// Sets Style Formatting Variables
	if (!elem_parent.details) {
		display_children = '';
		display_borders = '';
		elem.innerHTML = '( - )';
			// Icon Design
		elem_parent.style.marginBottom = '';
	}
	else {
		display_children = 'none';
		display_borders = 0;
		elem.innerHTML = '( + )';
			// Icon Design
		elem_parent.style.marginBottom = '-1ex';
	}
	
	// Switches State Flag
	elem_parent.details = !elem_parent.details;
	
	// Applies Style Formatting
	elem_parent.style.borderLeftWidth = display_borders;
	elem_parent.style.borderRightWidth = display_borders;
	elem_parent.style.borderBottomWidth = display_borders;

	// Goes through Each Element within the Parent...
	for (var i=0; i < elem_siblings.length; i++) {
		// If HTML Element...
		if (elem_siblings[i].nodeType == 1) {
			// Don't Touch the Legend
			if (elem_siblings[i].tagName.toLowerCase() != 'legend') {
				// Don't Touch the Icon
				if (elem_siblings[i].tagName.toLowerCase() != 'div' && !Element.hasClassName(elem_siblings[i], 'icon')) {
					// Show or Hide the Child
					elem_siblings[i].style.display = display_children;
				}
			}
		}
	}
}


// Wrapper Function - Specifically Creates Details Icons
function details_icon (ico_container, ico_pos, ico_text, ico_cursor) {
	// Creates & Positions Icon
	var icon = create_icon (ico_container, ico_pos, ico_text, ico_cursor);

	// Applies Action to relative parent element, if not yet added.
	if (!icon.parentNode.details) {
		icon.parentNode.details = true;

		Event.observe (icon, 'click', function (e) {
			var elem = Event.element(e);

			if (elem.disabled) return;

			fieldset_details_toggle(elem);
		});
	}
	else {
		Event.observe (icon, 'click', function (e) {
			var elem = Event.element(e).parentNode;

			if (Event.element(e).disabled) return;

			elem.details = document.getElementsByClassName('dnd-fieldset', elem);

			var elem_display = (elem.details[0].style.display == 'none') ? '' : 'none';

			for (var i=0; i < elem.details.length; i++) {
				elem.details[i].style.display = elem_display;
			}

			if (elem_display == 'none') {
				Event.element(e).innerHTML = '( + )';
			}
			else {
				Event.element(e).innerHTML = '( - )';
			}
		});
	}

	return icon;
}


// Generic function to grow an input table, simply copying the row passed in.
// Best usage is an onkeypress event on input in the last record, growTable
// will automatically remove itself from what was the last row after it add a
// new one.
function growTable (last_row) {
  if (! document.getElementById) return;

  console.log("growTable");
  while (last_row.nodeName != 'TR') {
    console.log('Finding tr', last_row, last_row.parentNode);
    last_row = last_row.parentNode;
  }

  var tbody = last_row.parentNode;
  var next_row = last_row.cloneNode(true); // Copy entire row.

  // TEMPORARY: This should be replaced by a callback.
  var inputs = next_row.getElementsByTagName('input');
  var pattern = /[0-9]+$/;
  for (var i=0; i < inputs.length; i++) {
    var input = inputs[i];
    var n = parseInt(input.name.match(pattern));

    if (n == NaN || n <= 0) {
      alert('Invalid field name: '+input.name);
      input.name = '';
    }

    input.name = input.name.replace(pattern, ++n);
    input.id   = input.id.replace(pattern, n);
    // Clear any values from the old record.
    input.value = '';
  }

  // TEMPORARY: This should be replaced by a callback.
  var inputs = next_row.getElementsByTagName('select');
  var pattern = /[0-9]+$/;
  for (var i=0; i < inputs.length; i++) {
    var input = inputs[i];
    var n = parseInt(input.name.match(pattern));

    if (n == NaN || n <= 0) {
      alert('Invalid field name: '+input.name);
      input.name = '';
    }

    input.name = input.name.replace(pattern, ++n);
    input.id   = input.id.replace(pattern, n);
    // Clear any values from the old record.
    input.value = '';
  }

  tbody.appendChild(next_row);
  // Remove the growtbody event from all inputs in what was the last_row.
  var inputs = last_row.getElementsByTagName('input');
  for (var i=0; i < inputs.length; i++) {
    inputs[i].onkeypress = function () {};
    if (inputs[i].getAttribute('oninput') == 'growTable(this);') {
      inputs[i].oninput = function () {};
    }
    if (inputs[i].getAttribute('on_input_this') == 'growTable') {
      inputs[i].oninput = function () {};
    }
  }
  // TODO: Use the event model TODO: Remove event from selects and textareas.
  console.log('done');
}


document.getAllChildren = function (e) {
  // Returns all children of element. Workaround required for IE5/Windows. Ugh.
  return e.all ? e.all : e.getElementsByTagName('*');
}


// Recursively searches all children in passed html object, and returns array of all form elements.
function get_inputs (parent_obj) {
	if (!parent_obj.hasChildNodes()) return false;
	
	var elems = parent_obj.childNodes;
	var inputs = [];
	var temp = [];

	for (var i=0; i < elems.length; i++) {
		if (elems[i].nodeType == 1 && (elems[i].nodeName.toLowerCase() == 'input' || elems[i].nodeName.toLowerCase() == 'select' || elems[i].nodeName.toLowerCase() == 'textarea')) {
			inputs[inputs.length] = elems[i];
		}
		else {
			temp = get_inputs (elems[i]);
			if (temp.length > 0) {
				inputs[inputs.length] = temp;
			}
		}
	}

	return inputs.flatten();
}

function getFormObj( formName ) {
	return document.forms[formName];
}

function do_decimals( number ) {
	if ( isNaN(number) ) {
		return '0.00';
	} else {
		var myStr = new String(Math.round(number*100)/100);
		var decPos = myStr.indexOf(".");
		// test for no decimals
		if (decPos==-1) {
			myStr += ".00";
		} else if (decPos==myStr.length-2) {
		// test for one decimal
			myStr += "0";
		} 
	} 
	return myStr;
} 

function isin ( array, value ) {
	if ( array ) {
		for ( var i = 0; i < array.length; i += 1 ) {
			if ( array[i] == value )
				return true;
		} 
	} else {
	} 
	return false;
} 

function keypress_int (e) {
	var charCode = (e.which) ? e.which : e.keyCode;
	var int_str = '0123456789';
	
	if (int_str.indexOf(String.fromCharCode(charCode)) == -1) {
		var elem = Event.element(e);
		var value = elem.value;
		var chr = '';

		while (value.charAt(0) == '0') {
			value = value.substr(1);
		}

		for (var i=0; i < value.length; i++) {
			var chr = value.charAt(i);

			if (int_str.indexOf(chr) == -1) {
				value = value.replace(chr, '');
				i--;
			}
		}

		// Normalizes IE Functionality
		if (elem.value != value) {
			elem.value = value;
		}
	}
}


function validate_int (value) { 
    return /^\d+$/.test(value) 
} 

