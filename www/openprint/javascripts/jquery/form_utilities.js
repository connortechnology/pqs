function isin ( array, value ) {
	if ( array ) {
		for ( var i = 0; i < array.length; i += 1 ) {
			if ( array[i] == value ) 
				return true;
		} // end for
	} else {
		//alert("Array has no properties. " + array + ": value: " + value );
	} // end if
	return false;
} // end function isin

function get_value( obj ) {
	if ( ! obj ) {
		return;
	} // end if
	if ( obj.type == 'select-one' ) {
		return get_ddm_value( obj );
	} else if ( obj.type == 'radio' || obj.type == 'checkbox' ) {
		if ( obj.checked ) {
			return obj.value;
		} else {
			return;
		}
	} else if ( obj.type == 'hidden' || obj.type == 'text' || obj.type == 'number' || obj.type == 'email' || obj.type == 'textarea' ) {
		return obj.value;
	} else if ( obj.length ) {
		var value = new Array();
		for ( var x = 0, len=obj.length; x < len; x += 1 ) {
			if ( obj[x].checked ) {
				if ( obj[x].type == 'radio' ) return obj[x].value;
				value[value.length] = obj[x].value;
			} // end if
		}
		if ( value.length == 1 ) return value[0];
		return value;
	} else {
		return obj.innerHTML;
	} // end if
	return obj.value;
}

function set_value( obj, value ) {
	if ( ! obj ) {
		return;
	} // end if
	if ( obj.type == 'select-one' ) {
		ddm_select_by_value( obj, value );
	} else if ( obj.type == 'radio' || obj.type == 'checkbox' ) {
		set_rdb_value( obj, value );
	} else if ( obj.type == 'hidden' || obj.type == 'text' || obj.type == 'number' || obj.type == 'email' || obj.type == 'tel' ) {
		obj.value = value;
	} else {
		obj.innerHTML = value;
	} // end if
}

function get_checkbox_values( checkboxes ) {
	if ( checkboxes.length ) {
		var Values = new Array();
		for ( var index = 0, len = checkboxes.length; index < len; index += 1 ) {
			if ( checkboxes[index].checked ) {
				Values[Values.length] = checkboxes[index].value;
			} 
		} 
		if ( Values.length == 1 ) {
			return Values[0];
		}
		return Values;
	} else if ( checkboxes.checked ) {
		return checkboxes.value;
	} 
	return;
} // end function

function get_select_value ( ddm ) {
	var selected = new Array();
	if ( ddm ) {
		for ( var index = 0; index < ddm.options.length; index += 1 ) {
			if ( ddm.options[index].selected ) {
				selected[selected.length] = ddm.options[index].value;
			} // end if
		} // end for
	} else {
		alert("null ddm passsed to get_select_value");
	} // end if
	return selected;
} // end function get_select_value

function set_rdb_value( rdb, value ) {
	for ( var x = 0; x < rdb.length; x ++ ) {
		if ( rdb[x].value == value ) {
			rdb[x].checked = true;
		} else {
			rdb[x].checked = false;
		} // end if
	} // end for
}

function get_rdb_value( rdb ) {
	if ( ! rdb ) {
		alert( "Radio button not found");
	} else {
		for ( var x = 0; x < rdb.length; x ++ ) {
			if ( rdb[x].checked == true ) {
				return rdb[x].value;
			} // end if
		} // end for
	} // end if
	return null;
} // end function

function fill_ddm ( ddm, options, onchange ) {
	if ( ddm ) {
		ddm.disabled = true;
		//ddm.onchange = null;
		clear_ddm( ddm );
		for( var index = 0, len = options.length; index < len; index += 1 ) {
			ddm.options[ddm.options.length] = create_option( options[index].value, options[index].text );
		} // end for
		//ddm.onchange = onchange;
		ddm.disabled = false;
	} // end if
} // end function fill_ddm
function fill_ddm_from_array ( ddm, options, onchange ) {
	if ( ddm ) {
		ddm.disabled = true;
		clear_ddm( ddm );
		for( var index = 0, len=options.length; index < len; index += 2 ) {
			ddm.options[ddm.options.length] = create_option( options[index], options[index+1] );
		} // end for
		ddm.disabled = false;
	} // end if
} // end function fill_ddm_from_array

function clear_ddm ( ddm ) {

	if ( ddm ) {
		var disabled = ddm.disabled;
		if ( ! disabled ) {
			ddm.disabled = true;
		} // end if

		if ( ddm.options ) {
			for ( var index = ddm.options.length; index >= 0; index -- ) {
				// this last if eliminates the mac problem.
				if (ddm.options[index])
					ddm.options[index] = null;
			} // end for
		} else {
			alert("clear_ddm: null ddm.options");
		}
		ddm.selectedIndex = -1;
		ddm.disabled = disabled;
	} else {
		alert("clear_ddm: null ddm " + ddm);
	}
} // end function clear_ddm

function create_option( value, text ) {
	var option = document.createElement("OPTION");
	option.text = text;
	option.value = value;
	return option;
}

function sort_ddm(ddm) {
	var selectedValue = ddm.value;
	var copyOption = new Array();
	for (var i=0;i<ddm.options.length;i+=1)
		copyOption[i] = new Array(ddm.options[i].value,ddm.options[i].text, ddm.options[i]);

	copyOption.sort(function(a,b) { return a[0]!=b[0] ? a[0]<b[0] ? -1 : 1 : 0; });

	clear_ddm( ddm );

	for (var i=0;i<copyOption.length;i++)
		ddm[i] = copyOption[i][2];
		//add_option( ddm, copyOption[i][0], copyOption[i][1] );
	ddm_select_by_value( ddm, selectedValue, 0 );
}


function add_option( ddm, value, text, selectedValue ) {
	if ( ddm ) {
			var option = create_option( value, text );
			var index = ddm.options.length;
			ddm.options[index] = option;
			if ( ddm.selectedIndex == -1 || option.value == selectedValue ) {
				ddm.selectedIndex = index;
				option.selected = true;
			} else {
				option.selected = false;
			} // end if
	} else {
		alert('add_option: null ddm ' + ddm);
	} // end if
	return option;
} // end function add_option

function isin_ddm ( array, value ) {
	var index = get_option_index( array, value );
	if ( index == -1 ) return false;
	return true;
} // end function isin_ddm

function get_option_index ( array, value ) {
	if ( array ) {
		for ( var i = 0, len = array.length; i < len; i += 1 ) {
			if ( array[i] && array[i].value == value )
				return i;
		} // end for
	} else {
		alert("get_option_index: null array" );
	}
	return -1;
} // end function get_option_index

function get_ddm_value ( ddm ) {
	var value = "";
	if ( ddm ) {
		if ( ddm.selectedIndex != -1 && ddm.options[ddm.selectedIndex] ) {
				value = ddm.options[ddm.selectedIndex].value;
		} else {
			//alert("No Options: " + ddm.name);
		} // end if
	} else {
		alert("null ddm passed to get_ddm_value : " + ddm);
	} // end if
	return value;
} // end function
function get_ddm_text ( ddm ) {
	if ( ddm ) {
		if ( ddm.selectedIndex != -1 && ddm.options[ddm.selectedIndex] ) {
			return ddm.options[ddm.selectedIndex].text;
		} // end if
	} else {
		alert("null ddm passed to get_ddm_value : " + ddm);
	} // end if
} // end function

function ddm_select_by_index( ddm, index ) {
	if ( ddm ) {
		if ( ddm.type != 'select-one' ) {
			alert( ddm.name + " is not a drop down!" );
			return;
		} // end fi
		if ( index == -1 ) {
			ddm.selectedIndex = -1;
		} else if ( index >= ddm.options.length ) {
			alert("Selecting an index too large!" + index);
		} else {
			//ddm.selectedIndex = index;
			if ( ddm.options[index] ) {
				if ( ddm.selectedIndex != index )
					ddm.selectedIndex = index;
				if ( ! ddm.options[index].selected ) 
					ddm.options[index].selected = true;
			} // end if
		} // end if
	} else {
		alert( "null ddm passed to ddm_select_by_index" );
	} // end if
} // end function ddm_select_by_index( ddm, index );

function ddm_select_by_value( ddm, value, defaultValue ) {
	if ( ddm && ddm.options ) {
		for ( var index = 0; index < ddm.options.length; index += 1 ) {
			if ( ddm.options[index] && (ddm.options[index].value == value) ) {
				ddm_select_by_index( ddm, index );
				return true;
			} // end if
		} // end for
		if ( defaultValue ) {
			ddm_select_by_index( ddm, defaultValue );
			return true;
		} // end nif
	} else {
		alert( "null ddm passed to ddm_select_by_value" );
	} // end if
	return false;
} // end function ddm_select_by_value( ddm, value );
function ddm_select_by_text( ddm, value, defaultValue ) {
	if ( ddm ) {
		for ( var index = 0, len = ddm.options.length; index < len; index += 1 ) {
			if ( ddm.options[index].text == value ) {
				ddm_select_by_index( ddm, index );
				return;
			} // end if
		} // end for
		ddm_select_by_index( ddm, defaultValue );
	} else {
		alert( "null ddm passed to ddm_select_by_text" );
	} // end if
} // end function ddm_select_by_text( ddm, value );
function ddm_select_by_text_case_insensitive( ddm, value, defaultValue ) {
	var lowervalue = value.toLowerCase();
	if ( ddm ) {
		for ( var index = 0, len = ddm.options.length; index < len; index += 1 ) {
			if ( ddm.options[index].text.toLowerCase() == lowervalue ) {
				ddm_select_by_index( ddm, index );
				return;
			} // end if
		} // end for
		ddm_select_by_index( ddm, defaultValue );
	} else {
		alert( "null ddm passed to ddm_select_by_text" );
	} // end if
} // end function ddm_select_by_text( ddm, value );


function filterDDM( filter, ddm ) {
	if ( ! filter.value.length ) {
		if ( ! ddm.defaultSelected ) {
			for ( var index = 0, len = ddm.options.length; index < len; index += 1 ) {
				if ( ddm.options[index].defaultSelected ) {
					ddm.defaultSelected = index;
					break;
				} // end if
			} //e nd for 
		} // end if 
		ddm.selectedIndex = ddm.defaultSelected;
		return;
	} // end if
	var old_selected_index = ddm.selectedIndex;
	if ( old_selected_index <= 0 )
		old_selected_index = 1;

	var chunk1 = filter.value.toLowerCase();
	var chunk2 =	ddm.options[old_selected_index].text.toLowerCase();

	if ( chunk1 < chunk2 ) {
		// search down
//alert( 'down' + chunk1 + ' ' + chunk2 + ' ' + old_selected_index );
		for ( var index = old_selected_index-1; index > 0; index -= 1 ) {
			var chunk2 = ddm.options[index].text.toLowerCase();
			if ( chunk1 > chunk2 ) {
				// Need to back up 1
				ddm.selectedIndex = index+1;
				return index != old_selected_index;
			} else if ( chunk1 == chunk2 ) {
				ddm.selectedIndex = index;
				return index != old_selected_index;
			} // end if
		} // end for
		//ddm.selectedIndex = 0;
		//return 0 != old_selected_index;
	} else if ( chunk1 > chunk2 ) {
//alert( 'up' + chunk1 + ' ' + chunk2 + ' ' + old_selected_index );
		// search up
		for ( var index = old_selected_index+1; index < ddm.options.length; index += 1 ) {
			var chunk2 = ddm.options[index].text.toLowerCase();
			if ( chunk1 <= chunk2 ) {
				ddm.selectedIndex = index;
				return true;
			} // end if
		} // end for
	} // end if

	return ddm.selectedIndex != old_selected_index;

} // end function filterDDM

/*
 *	Pass it the Month and Year and it'll return the number of days within the
 *	specified month. Year is optional. If no year is passed and the month chosen
 *	is February, the default return value is 29.
 */
function returnNumberOfDays(month, year) {
	if(month == 1 || month == 3 || month == 5 || month == 7 || month == 8 || month == 10 || month == 12 ) {
		// January
		return 31;
	} else if(month == 2) {
		// February
		if(isLeapYear(year) && year) {
		return 29;
		} else {
		return 28;
		}
	} else if(month == 4 || month == 6 || month == 9 || month == 11 ) {
		// April
		return 30;
	}
	return 31;
}


/*
 *	Pass it a year value and it will return a boolean.
 *	True = Year passed is a leap year
 *	False = Year passed is not a leap year
 */
function isLeapYear(year) {
	if(year % 4 != 0) {
		return false;
	} else if(year % 400 == 0) {
		return true;
	} else if(year % 100 == 0) {
		return false;
	}
	return true;
}

/*
 *	Pass it the:
 *	1) year (value)
 *	2) month (value)
 *	3) day drop down (object)
 *	4) selected day (value) if any
 *	It will alter the day drop down object to have the proper amount of days.
 *	if specified it will set the default selection to the passed selected day.
 */
function setDaysDropDown(year, month, dayDropDown, selectedDay, previousMonth ) {
	selectedDay = parseInt(selectedDay);

	var numberOfDays = returnNumberOfDays(month,year);
	if ( numberOfDays < selectedDay ) {
		selectedDay = numberOfDays;
	} else if ( selectedDay == returnNumberOfDays(previousMonth,year) ) {
		selectedDay = numberOfDays;
	//} else if ( selectedDay >= 28 && selectedDay <= 30 && numberOfDays >= 30 ) {
		//selectedDay = numberOfDays;
	} // end if

	if ( dayDropDown.options[dayDropDown.options.length-1].value > numberOfDays ) {
		for ( var i = dayDropDown.options.length-1; i > numberOfDays; i -= 1 ) {
			if ( dayDropDown.options[i].value > numberOfDays ) {	
				dayDropDown.options[i] = null;
			} // end if
		} // end for
	} else if ( dayDropDown.options[dayDropDown.options.length-1].value < numberOfDays ) {
		for ( var i = parseInt(dayDropDown.options[dayDropDown.options.length-1].value); i < numberOfDays; i += 1 ) {
			dayDropDown.options[dayDropDown.options.length] = new Option( i+1, i+1 );
		} // end for
	} // end if

	ddm_select_by_value( dayDropDown, selectedDay );
}

function Serialize( form ) {
	var parameters = new Array();
	for ( var index = 0, len = form.elements.length; index <len ; index += 1 ) {
		var e = form.elements[index];
		if ( e.type == 'radio' ) {
			if ( e.checked == true ) {
				parameters[parameters.length] = e.name;
				parameters[parameters.length] = e.value;
			} // end if
		} else if ( e.type == 'checkbox' ) {
			if ( e.checked == true ) {
				parameters[parameters.length] = e.name;
				parameters[parameters.length] = e.value;
			} // end if
		} else if ( e.type == 'select-one' ) {
			if ( e.selectedIndex != -1 ) {
				parameters[parameters.length] = e.name;
				parameters[parameters.length] = e.options[e.selectedIndex].value;
			} // end if
		} else if ( e.type == 'select-multiple' ) {
			for ( var option_index = 0; option_index < e.options.length; option_index += 1 ) {
				if ( e.options[option_index].selected ) {
					parameters[parameters.length] = e.name;
					parameters[parameters.length] = e.options[option_index].value;
				} // end if
			} // end if
		} else if ( e.type == 'text' || e.type == 'hidden' || e.type=='textarea') {
			if ( e.name ) {
				parameters[parameters.length] = e.name;
				parameters[parameters.length] = e.value;
			} // end if
		} else {
		} // end if
	} // end for
	return parameters;
} // end function serialize

function select_all( form, name, checked ) {
	if ( ! form.elements[name] ) {
		return;
	}	// end if
	if ( form.elements[name].length ) {
		for ( var i = 0, len = form.elements[name].length; i < len; i += 1 ) {
			form.elements[name][i].checked = checked;
		} // end for
	} else {
		form.elements[name].checked = checked;
	} // end if
}

function clearSelect( ddm ) {
	for ( var i = 0, len = ddm.options.length; i < len; i++ ) {
		ddm.options[i].selected = 0;
	} 
	ddm.options[0].selected = 1;
}

function clearForm(form) {
	form = $(form);
	if ( form ) { form = form[0] } else { alert("No form found for form"); };
	for ( var i=0, len = form.elements.length; i < len; i += 1 ) {
		var e = form.elements[i];
		if ( ! e.type )
			continue;
		if ( e.type == 'checkbox' || e.type == 'radio' ) {
			e.checked = '';
		} else if (e.type == 'hidden' || e.type == 'password' || e.type == 'text' || e.type == 'textarea' || e.type == 'number' || e.type == 'email' || e.type == 'url' || e.type == 'tel' ) {
			e.value = '';
		} else if ( e.type == 'select-one' ) {
			while ( e.selectedIndex > 0 ) {
				e.options[e.selectedIndex].selected = false;
			} // end while
			e.selectedIndex = 0;
		} else if ( e.type == 'select-multiple' ) {
			while ( e.selectedIndex >= 0 ) {
				e.options[e.selectedIndex].selected = false;
			} // end while
		} else {
			//alert(e.type);
		} // end if
	} // end for
} // end function clearForm(form)

function element_changed( element ) {
	if ( ! element ) {
//alert('Null element passed to element_changed');
		return false;
	}

	if ( element.type == 'select-one' ) {
		for ( var i = 0, len = element.options.length; i < len; i += 1 ) {
			if ( element.options[i].selected != element.options[i].defaultSelected ) {
				return true;
			} // end if
		} // end for
	} else if ( element.type == 'text' || element.type == 'password' || element.type == 'hidden' || element.type == 'textarea' || element.type == 'number' || element.type == 'email' || element.type == 'url' ) {
		return ! ( element.value == element.defaultValue );	
	} else if ( element.type == 'radio' || element.type == 'checkbox' ) {
		return ! ( element.checked == element.defaultChecked );
	} else if ( element.length ) {
		for ( var i = 0, len = element.length; i < len; i += 1 ) {
			if ( element_changed( element[i] ) ) {
				return true;
			} // end if
		} // end for
	} // end if
	return false;
} // end function element_changed

var fmChange = 0;
function changed( form ) {
	for ( var i = 0, len = form.elements.length; i < len; index += 1 ) {
		if ( form.elements[i].length ) {
			for ( var subindex = 0; subindex < form.elements[i].length; subindex += 1 ) {
				if ( element_changed( form.elements[i][subindex] ) ) {
					return true;
				} // end if
			} // end for
		} else {
			if ( element_changed( form.elements[i] ) ) {
				return true;
			} // end if
		} // end if
	} // end for
	return false;
} // end function changed

function fmCheck( form ) {
	if ( $('ButtonsTop') ) $('ButtonsTop').hide();
	if ( $('ButtonsBottom') ) $('ButtonsBottom').hide();
	if ( fmChange == 1 ) {
		if ( ( ! changed(form) ) || confirm("Are you sure you want to leave this record without saving your changes?") ) {
			fmChange == 0;
			form.submit();
		} 
	} else if (fmChange == 2) {
		fmChange = 0;
		if ( confirm("Are you sure you want to delete this record?") ) {
			form.submit();
		} 
	} else if (fmChange == 3) {
		fmChange = 0;
		if ( confirm("Are you sure you want to save your changes?") ) {
			form.submit();
		} 
	} else if ( form.btnFunction && form.btnFunction.value == 'Undelete' ) {
		fmChange = 0;
		if ( confirm("Are you sure you want to undelete this company?") ) {
			form.submit();
		} 
	} else {
		form.submit();
	}
	if ( $('ButtonsTop') ) $('ButtonsTop').show();
	if ( $('ButtonsBottom') ) $('ButtonsBottom').show();
}

function addCheck(form) {
	if (fmChange == 1) {
		if (confirm("Are you sure you want to create a new record, without saving your changes")) {
			clearForm(form);
		}
	} else { 
		clearForm(form);
	}
}

function submitCheck() {
	if (fmChange == 1) {
		return confirm("Are you sure you want to reset this record without saving your changes?");
	}
}


function summary(summaryPage) {
var summaryPage;
window.open(summaryPage,'pop','newWin,left=140,width=640,top=50,height=400,resizable=yes,scrollbars=yes,menubar=no,toolbar=yes,location=no,directories=yes,status=yes');
}

function checkLoginData( usernameInput, passwordInput ) {
	var div = $( 'missingLoginMessage' );
	if( usernameInput && ! usernameInput.value ) {
		// Display login name error.
		if ( div ) div.show();
		usernameInput.focus();
		return false;
	} else if ( div ) {
		div.hide();
	}

	div = $( 'missingPasswordMessage' );
	if( passwordInput && ! passwordInput.value ) {
		// Display login password error.
		if ( div ) div.show();
		passwordInput.focus();
		return false;
	} else if ( div ) {
		div.hide();
	}
	usernameInput.form.btnFunction.value='Login';
	usernameInput.form.submit();
	return false;
}

function checkForgotPasswordData ( emailInput ) {
	var pass = true;

	var div = $( 'missingLoginMessage' );
	if ( ! emailInput.value ) {
		// Display email error.
		div.style.display = 'block';
		pass = false;
	} else {
		div.style.display = 'none';
	}

	if ( pass ) {
		// Passed. Submit the form and it's data.
		emailInput.form.btnFunction.value='Forgotten Password';
		emailInput.form.submit();
		return false;
	}
}

function toggleMenu( element, a, b ) {
	if ( ! element )
		return;

	if ( element.className == a ) {
		element.className = b;
	} else {
		element.className = a;
	} // end if
}

function email_check(str) {

	var at="@"
	var dot="."
	var lat=str.indexOf(at)
	var lstr=str.length
	var ldot=str.indexOf(dot)
	if (str.indexOf(at)==-1){
		 return false
	}

	if (str.indexOf(at)==-1 || str.indexOf(at)==0 || str.indexOf(at)==lstr){
		 return false
	}

	if (str.indexOf(dot)==-1 || str.indexOf(dot)==0 || str.indexOf(dot)==lstr){
			return false
	}

	 if (str.indexOf(at,(lat+1))!=-1){
			return false
	 }

	 if (str.substring(lat-1,lat)==dot || str.substring(lat+1,lat+2)==dot){
			return false
	 }

	 if (str.indexOf(dot,(lat+2))==-1){
			return false
	 }
	
	 if (str.indexOf(" ")!=-1){
			return false
	 }

	 return true					
}

function addLoadEvent(func) {
	var oldonload = window.onload;
	if (typeof window.onload != 'function') {
		window.onload = func;
	} else {
		window.onload = function() {
			if ( oldonload ) oldonload();
			func();
		}
	}
}

function Country_onchange( country_ddm, state ) {
	var country = get_ddm_value( country_ddm );
	var state_label = $(country_ddm.name + '_state');
	var postal_label = $(country_ddm.name + '_postal');
	var onchange = state.getAttribute('onchange');
	if ( country == 'US' ) {
		$(state.name+'_container').innerHTML = '<select name="' + state.name + '" id="' + state.id + '"' + ( onchange ? ' onchange="' + onchange + '"' : '' ) + '/>';
		$j( state ).load( '/includes/_states.html' );
		if ( state_label ) state_label.innerHTML='State';
		if ( postal_label ) postal_label.innerHTML='ZIP Code';
	} else if ( country == 'CA' ) {
		$(state.name+'_container').innerHTML = '<select name="' + state.name + '" id="' + state.id + '"' + ( onchange ? ' onchange="' + onchange + '"' : '' ) + '/>';
		$( state ).load( '/includes/_provinces.html' );
		if ( state_label ) state_label.innerHTML='Province';
		if ( postal_label ) postal_label.innerHTML='Postal Code';
	} else {
		$(state.name+'_container').innerHTML = '<input type="text" name="' + state.name + '" id="' + state.id + '" '+ ( onchange ? ' onchange="' + onchange + '"' : '' ) + '/>';
		if ( state_label ) state_label.innerHTML='State/Province';
		if ( postal_label ) postal_label.innerHTML='Postal Code';
	} // end if
} // end function

/* 
*/
function Location_onchange( parent_element, type, options ) {

	if ( ! options ) options = {};
	var parameters = {};
	parameters.parent_id = parent_element.getValue();
	parameters.parent_element = parent_element.id;
	parameters.type = type;
	if ( options.state_element ) parameters.state_element = options.state_element;
	if ( options.city_element ) parameters.city_element = options.city_element;

	$.ajax({
		dataType: "json",
		url: 		'/location/_ddm.json',
		data: parameters,
		success:	options.onSuccess,
		});
	if ( type == 'country' ) {
		var state_label = $(parent_element.name + '_state');
		var postal_label = $(parent_element.name + '_postal');
		var country = get_ddm_text( parent_element );
		if ( country == 'United States' ) {
			if ( state_label ) state_label.innerHTML='State';
			if ( postal_label ) postal_label.innerHTML='ZIP Code';
		} else if ( country == 'Canada' ) {
			if ( state_label ) state_label.innerHTML='Province';
			if ( postal_label ) postal_label.innerHTML='Postal Code';
		} else {
			if ( state_label ) state_label.innerHTML='State/Province';
			if ( postal_label ) postal_label.innerHTML='Postal/ZIP Code';
		}	// end if
	} // end if
}

function countLines(strtocount, cols) {
	var hard_lines = 1;
	var last = 0;
	while ( true ) {
		last = strtocount.indexOf("\n", last+1);
		if ( last == -1 ) break;
		hard_lines ++;
	}
	if ( cols ) {
		var soft_lines = Math.round(strtocount.length / (cols-1));
		if ( hard_lines > soft_lines ) return hard_lines;
		return soft_lines;
	}
	return hard_lines;	
}

function textarea_resize( element ) {
	element.rows = countLines(element.value,element.cols);
} // end function textarea_resize

function do_decimals( number, precision ) {
	var a = number.toString();
	number = parseFloat( 1* a.replace(/[^\d\-\.]/g, '' ) );
	if ( ! precision ) {
		precision = 2;
	} else {
		var a = precision.toString();
		precision = parseFloat( 1* a.replace(/\D/g, '' ) );
	} // end if
	var result1 = number * Math.pow(10, precision);
	var result2 = Math.round(result1);
	var result3 = result2 / Math.pow(10, precision);
	return pad_with_zeros(result3, precision);
} // end function do_decimals

function pad_with_zeros(rounded_value, decimal_places) {
	var value_string = rounded_value.toString();
	var decimal_location = value_string.indexOf(".");
	if (decimal_location == -1) {
		decimal_part_length = 0;
		value_string += decimal_places > 0 ? "." : "";
	} else {
		decimal_part_length = value_string.length - decimal_location - 1;
	} // end if
	var pad_total = decimal_places - decimal_part_length;
	if (pad_total > 0) {
		for (var counter = 1; counter <= pad_total; counter++) {
			value_string += "0";
		} // end for
	} // end if
	return value_string;
}

function getFormObj( formName ) {
	var form = document.forms[formName];
	return form;
}
 
function disableDiv(elm) {

	while (elm.tagName !="DIV") {
		elm = elm.parentNode
	}

	_width = elm.offsetWidth;
	_height = elm.offsetHeight;;
	_top = elm.offsetTop;
	_left = elm.offsetLeft;

	overlay = document.createElement("div");
	overlay.style.width = _width + "px";
	overlay.style.height = _height + "px";
	overlay.style.position = "absolute";
	overlay.style.background = "#dedede";
	overlay.style.top = _top + "px";
	overlay.style.left = _left + "px";

	overlay.style.filter = "alpha(opacity=50)";
	overlay.style.opacity = "0.5";
	overlay.style.mozOpacity = "0.5";

	document.getElementsByTagName("body")[0].appendChild(overlay);
}

function set_today( e_y, e_m, e_d, e_h, e_min ) {
	var d = new Date();
	ddm_select_by_value( e_y, 1900+d.getYear() );
	ddm_select_by_value( e_m, d.getMonth()+1 );
	ddm_select_by_value( e_d, d.getDate() );
	if ( e_h )
		ddm_select_by_value( e_h, d.getHours() );
	if ( e_min )
		ddm_select_by_value( e_min, d.getMinutes() );
} // end function set_today

function date_clear( e_y, e_m, e_d, e_h, e_min ) {
	var onchange=e_y.onchange;
	e_y.onchange='';
	e_y.selectedIndex = 0;
	e_y.onchange=onchange;

	onchange=e_m.onchange;
	e_m.onchange='';
	e_m.selectedIndex = 0;
	e_m.onchange=onchange;

	onchange=e_d.onchange;
	e_d.onchange='';
	e_d.selectedIndex = 0;
	e_d.onchange=onchange;
	//ddm_select_by_value( e_y, '' );
	//ddm_select_by_value( e_m, '' );
	//ddm_select_by_value( e_d, '' );
	if ( e_h )
	e_h.selectedIndex = 0;
		//ddm_select_by_value( e_h, '' );
	if ( e_min )
	e_min.selectedIndex = 0;
		//ddm_select_by_value( e_min, '' );
} // end function date_clear

function set_date( form, from, to ) {
	ddm_select_by_value( form.elements[to+'_year'], get_ddm_value( form.elements[from+'_year'] ) );
	ddm_select_by_value( form.elements[to+'_month'], get_ddm_value( form.elements[from+'_month'] ) );
	setDaysDropDown(get_ddm_value( form.elements[from+'_year'] ), get_ddm_value( form.elements[from+'_month'] ), form.elements[to+'_day'], get_ddm_value( form.elements[from+'_day'] ) );
	//ddm_select_by_value( form.elements[to+'_day'], get_ddm_value( form.elements[from+'_day'] ) );
} // end function set_date

function check_time_starting( form, starting_prefix, ending_prefix, suffix ) {
	if ( ! suffix ) suffix = '';
	var start;
	var end;
	var do_time = 0;

	if ( form.elements['time_associated'+suffix] ) {
		if ( get_value( form.elements['time_associated'+suffix] ) == 1 ) do_time = 1;
	} else if ( form.elements['all_day_event'+suffix] ) {
		if ( get_value( form.elements['all_day_event'+suffix] ) == 0 ) do_time = 1;
	} else if ( form.elements[starting_prefix+suffix+'_hour']) {
		do_time = 1;
	} // end if

	if ( do_time ){
		start = new Date( form.elements[starting_prefix+suffix+'_year'].value, form.elements[starting_prefix+suffix+'_month'].value-1, form.elements[starting_prefix+suffix+'_day'].value, form.elements[starting_prefix+suffix+'_hour'].value, form.elements[starting_prefix+suffix+'_minute'].value );
		end = new Date( form.elements[ending_prefix+suffix+'_year'].value, form.elements[ending_prefix+suffix+'_month'].value-1, form.elements[ending_prefix+suffix+'_day'].value, form.elements[ending_prefix+suffix+'_hour'].value, form.elements[ending_prefix+suffix+'_minute'].value );
	} else {
		start = new Date( form.elements[starting_prefix+suffix+'_year'].value, form.elements[starting_prefix+suffix+'_month'].value-1, form.elements[starting_prefix+suffix+'_day'].value );
		end = new Date( form.elements[ending_prefix+suffix+'_year'].value, form.elements[ending_prefix+suffix+'_month'].value-1, form.elements[ending_prefix+suffix+'_day'].value );
	} // end if

	if ( start > end ) {
		var ending_year_ddm = form.elements[ending_prefix+suffix+'_year'];
		if ( ending_year_ddm.value != form.elements[starting_prefix+suffix+'_year'].value ) 
			ddm_select_by_value( ending_year_ddm, form.elements[starting_prefix+suffix+'_year'].value );

		var ending_month_ddm = form.elements[ending_prefix+suffix+'_month'];

		if ( ending_month_ddm.value != form.elements[starting_prefix+suffix+'_month'].value ) {
			ending_month_ddm.previousValue = ending_month_ddm.value;
			ddm_select_by_value( ending_month_ddm, form.elements[starting_prefix+suffix+'_month'].value );
			ending_month_ddm.onchange();
		} // end if
		if ( parseInt(form.elements[ending_prefix+suffix+'_day'].value) < parseInt(form.elements[starting_prefix+suffix+'_day'].value) ) {
			ddm_select_by_value( form.elements[ending_prefix+suffix+'_day'], form.elements[starting_prefix+suffix+'_day'].value );
		} 
		if ( do_time ){
			ddm_select_by_value( form.elements[ending_prefix+suffix+'_hour'], form.elements[starting_prefix+suffix+'_hour'].value );
			ddm_select_by_value( form.elements[ending_prefix+suffix+'_minute'], form.elements[starting_prefix+suffix+'_minute'].value );
		} else {
			if ( form.elements[ending_prefix+suffix+'_hour'] ) ddm_select_by_value( form.elements[ending_prefix+suffix+'_hour'], 0 );
			if ( form.elements[ending_prefix+suffix+'_minute'] ) ddm_select_by_value( form.elements[ending_prefix+suffix+'_minute'], 0 );
		} // end if
	} // end if
} // end function check_time_starting

function check_time_ending( form, starting_prefix, ending_prefix ) {
	var start;
	var end;
	var do_time = 0;

	if ( get_value( form.time_associated ) == 1 || ( (!form.time_associated) && (form.elements[starting_prefix+'_hour']) ) ) {
		do_time = 1;
	} // end if
	if ( do_time ){
		start = new Date( form.elements[starting_prefix+'_year'].value, form.elements[starting_prefix+'_month'].value, form.elements[starting_prefix+'_day'].value, form.elements[starting_prefix+'_hour'].value, form.elements[starting_prefix+'_minute'].value );
		end = new Date( form.elements[ending_prefix+'_year'].value, form.elements[ending_prefix+'_month'].value, form.elements[ending_prefix+'_day'].value, form.elements[ending_prefix+'_hour'].value, form.elements[ending_prefix+'_minute'].value );
	} else {
		start = new Date( form.elements[starting_prefix+'_year'].value, form.elements[starting_prefix+'_month'].value, form.elements[starting_prefix+'_day'].value );
		end = new Date( form.elements[ending_prefix+'_year'].value, form.elements[ending_prefix+'_month'].value, form.elements[ending_prefix+'_day'].value );
	} // end if
	if ( start > end ) {
		ddm_select_by_value( form.elements[starting_prefix+'_year'], form.elements[ending_prefix+'_year'].value );
		ddm_select_by_value( form.elements[starting_prefix+'_month'], form.elements[ending_prefix+'_month'].value );
		ddm_select_by_value( form.elements[starting_prefix+'_day'], form.elements[ending_prefix+'_day'].value );
		if ( do_time ) {
			ddm_select_by_value( form.elements[starting_prefix+'_hour'], form.elements[ending_prefix+'_hour'].value );
			ddm_select_by_value( form.elements[starting_prefix+'_minute'], form.elements[ending_prefix+'_minute'].value );
		} // end if
	} // end if
} // end function check_time_ending

function update_duration(form, starting_prefix, ending_prefix, suffix ) {
	if ( ! suffix ) suffix = '';
	var override = form.elements['duration_override'+suffix];
	if ( override && override.value=='Y' ) {
		return;
	}
	var do_time = 0;
	var unknown_time = 0;
	if ( form.elements['unknown_time'+suffix] ) {
		if ( get_value( form.elements['unknown_time'+suffix] ) == 1 ) unknown_time = 1;
	} // end if

	if ( form.elements['time_associated'+suffix] ) {
		if ( get_value( form.elements['time_associated'+suffix] ) == 1 ) do_time = 1;
	} else if ( form.elements['all_day_event'+suffix] ) {
		if ( get_value( form.elements['all_day_event'+suffix] ) == 0 ) do_time = 1;
	} else if ( form.elements[starting_prefix+suffix+'_hour']) {
		do_time = 1;
	} // end if

	var starting_time_elem = $(starting_prefix+suffix+'_time');
	var ending_time_elem = $(ending_prefix+suffix+'_time');

	var start_year = form.elements[starting_prefix+suffix+'_year'] ? form.elements[starting_prefix+suffix+'_year'].value : 0;
	var start_month = form.elements[starting_prefix+suffix+'_month'] ? form.elements[starting_prefix+suffix+'_month'].value : 0;
	var start_day = form.elements[starting_prefix+suffix+'_day'] ? form.elements[starting_prefix+suffix+'_day'].value : 0;
	var start_hour = form.elements[starting_prefix+suffix+'_hour'] ? form.elements[starting_prefix+suffix+'_hour'].value : 0;
	var start_minute = form.elements[starting_prefix+suffix+'_minute'] ? form.elements[starting_prefix+suffix+'_minute'].value : 0;

	var end_year = form.elements[ending_prefix+suffix+'_year'] ? form.elements[ending_prefix+suffix+'_year'].value : 0;
	var end_month = form.elements[ending_prefix+suffix+'_month'] ? form.elements[ending_prefix+suffix+'_month'].value : 0;
	var end_day = form.elements[ending_prefix+suffix+'_day'] ? form.elements[ending_prefix+suffix+'_day'].value : 0;
	var end_hour = form.elements[ending_prefix+suffix+'_hour'] ? form.elements[ending_prefix+suffix+'_hour'].value : 0;
	var end_minute = form.elements[ending_prefix+suffix+'_minute'] ? form.elements[ending_prefix+suffix+'_minute'].value : 0;

	var start = new Date( start_year, start_month, start_day, start_hour, start_minute );
	var end = new Date( end_year, end_month, end_day, end_hour, end_minute );

	var difference = parseInt( ( end - start ) / 1000 );
	var days = parseInt(difference/(60*60*24));

	if ( do_time ) {
		if ( unknown_time ) {
			if(starting_time_elem)starting_time_elem.hide();
			if(ending_time_elem)ending_time_elem.hide();

			if ( form.elements[starting_prefix+suffix+'_hour'] ) ddm_select_by_value( form.elements[starting_prefix+suffix+'_hour'], 0 );
			if ( form.elements[starting_prefix+suffix+'_minute'] ) ddm_select_by_value( form.elements[starting_prefix+suffix+'_minute'], 0 );
			if ( form.elements[ending_prefix+suffix+'_hour'] ) ddm_select_by_value( form.elements[ending_prefix+suffix+'_hour'], 0 );
			if ( form.elements[ending_prefix+suffix+'_minute'] ) ddm_select_by_value( form.elements[ending_prefix+suffix+'_minute'], 0 );
		} else {
			if(starting_time_elem)starting_time_elem.show();
			if(ending_time_elem)ending_time_elem.show();
		} // end if
		if ( $('duration'+suffix+'_time') ) $('duration'+suffix+'_time').show();
		difference -= days * ( 60*60*24 );
		var hours = parseInt( difference/(60*60) );
		difference -= hours * (60*60);
		var minutes = parseInt( difference/60 );
		if ( form.elements['duration'+suffix+'_days'] ) {
			form.elements['duration'+suffix+'_days'].value=days;
			if ( ! unknown_time ) {
				ddm_select_by_value( form.elements['duration'+suffix+'_hours'], hours );
				ddm_select_by_value( form.elements['duration'+suffix+'_minutes'], minutes );
			}
		} else {
			var duration = $('duration'+suffix);
			if ( duration ) {
				if ( duration.type == 'text' ) {
					duration.value = days+'day'+(days==1?'':'s')+' ' + hours+':'+ minutes;
				} else {
					duration.innerHTML = days+'day'+(days==1?'':'s')+' ' + hours+'hour'+(hours==1?'':'s')+' ' + minutes + 'minute'+(minutes==1?'':'s');
				} // end if
			} // end if
		} // end if
	} else {
		if(starting_time_elem){
			starting_time_elem.hide();
		}
		if(ending_time_elem)ending_time_elem.hide();
		if ( $('duration'+suffix+'_time') ) $('duration'+suffix+'_time').hide(); 
		if ( form.elements['duration'+suffix+'_days'] ) {
			form.elements['duration'+suffix+'_days'].value=days;
			if ( form.elements['duration'+suffix+'_hours'] ) ddm_select_by_value( form.elements['duration'+suffix+'_hours'], 0 );
			if ( form.elements['duration'+suffix+'_minutes'] ) ddm_select_by_value( form.elements['duration'+suffix+'_minutes'], 0 );
		} else {
			var duration = $('duration'+suffix);
			if ( duration ) {
				if ( duration.type == 'text' ) {
				duration.value = days +'day'+(days==1?'':'s');
				} else {
				duration.innerHTML = days +'day'+(days==1?'':'s');
				}
			}
		} // end if
	} // end if
} // end function update_duration

// Defaults to filter weekends out
function filter_days( form, prefix, options ) {
	var date = new Date( form.elements[prefix+'_year'].value, form.elements[prefix+'_month'].value-1, form.elements[prefix+'_day'].value );
	var changed = false;
	var date_alert = $(prefix+'_alert');
	if ( date_alert )
		date_alert.innerHTML = '';
	if ( options && options.businessonly ) {
		if ( date.getDay() == 0 ) {
			date.setDate(date.getDate()+1);
			if ( date_alert )
				date_alert.innerHTML = 'Date adjusted to nearest business day.';
			changed = true;
		} else if ( date.getDay() == 6 ) {
			date.setDate(date.getDate()+2);
			if ( date_alert )
				date_alert.innerHTML = 'Date adjusted to nearest business day.';
			changed = true;
		} // end if
	} // end if
	if ( options && options.futureonly ) {
		var today = new Date();
		if ( date < today ) {
			date = today;
			changed = true;
			if ( date_alert )
				date_alert.innerHTML = 'Date adjusted to be in the future.';
		} // end if	
	} // end if
	if ( changed ) {
		ddm_select_by_value( form.elements[prefix+'_year'], date.getYear() );
		ddm_select_by_value( form.elements[prefix+'_month'], date.getMonth()+1 );
		ddm_select_by_value( form.elements[prefix+'_day'], date.getDate() );
	} // end if
} // end function filter_days()

function setup_ie_menu() {
	if (document.all && document.getElementById) {
		var navRoot = document.getElementById("menubar");
		if ( navRoot ) {
			for ( var i=0; i<navRoot.childNodes.length; i+= 1 ) {
				var node = navRoot.childNodes[i];
				if (node.nodeName=='LI') {
					node.onmouseover=function() {
						this.className+=' over';
					}
					node.onmouseout=function() {
						this.className=this.className.replace(' over', '');
					}
				} // end if
			} // end for
		} // end if
	}
} // end function setup_ie_menu

function convert_lbs_to_kg( from, to ) {
	var qtys = from.value.split(',');
	for ( var i=0; i< qtys.length; i+=1 ) {
		qtys[i] = do_decimals( parseFloat(qtys[i] / 2.2046), 4 );
	} // end for
	to.value = qtys.join(',');
} // end function convert_lbs_to_kg
function convert_kg_to_lbs( from, to ) {
	var qtys = from.value.split(',');
	for ( var i=0; i< qtys.length; i+=1 ) {
		qtys[i] = do_decimals( parseFloat(qtys[i] * 2.2046), '0' );
	} // end for
	to.value = qtys.join(',');
} // end function convert_kg_to_lbs

// prevents the entering of a second decimal place
function check_decimal( element, e ) {
	var keynum;
	if(window.event) {
		// IE
		keynum = e.keyCode
	} else if(e.which) {
		// Netscape/Firefox/Opera
		keynum = e.which
	}
	if ( keynum == 190 && element.value.indexOf(".") != -1 ) {
		return false;
	} 
	return true;
}

function click(e) {
	if (document.all) {
		if (event.button==2||event.button==3) {
			return false;
		}
	} else if (document.layers || document.getElementById ) {
		if (e.which == 3) {
			return false;
		}
	}
}

function disable_rightclick() {
	if (document.layers) {
		document.captureEvents(Event.MOUSEDOWN);
	} else {
		document.onmouseup=click;
		document.oncontextmenu=click;
	}
	
	document.onmousedown=click;
} // end function disable_rightclick

function remove_div( divname ) {
	var div = $(divname);
	if ( div ) {
		div.hide();
	} // end if
	return div;
}
function add_div( divname ) {
	var div = $(divname);
	if ( div ) {
		div.show();
	} // end if
	return div;
}

// also positions it
function show_div( divname, e ) {
	var div = $(divname);
	if ( div ) {
	
		var posx = 0;
		var posy = 0;
		if (!e) e = window.event;
		if ( e ) {
			if (e.pageX || e.pageY) {
				posx = parseInt(e.pageX);
				posy = parseInt(e.pageY);
			} else if (e.clientX || e.clientY) {
				posx = parseInt(e.clientX);
				posy = parseInt(e.clientY);
				if( document.documentElement && ( document.documentElement.scrollTop || document.documentElement.scrollLeft ) ) {
					posx += parseInt( document.documentElement.scrollLeft ); posy += parseInt( document.documentElement.scrollTop );
				} else if( document.body && ( document.body.scrollTop || document.body.scrollLeft ) ) {
					posx += parseInt( document.body.scrollLeft ); posy += parseInt( document.body.scrollTop );
				}
			} // end if
			if ( posx + div.offsetWidth > document.body.offsetWidth ) {
				posx = document.body.offsetWidth - div.offsetWidth;
			} // end if
			div.style.left = posx + 'px';
			posy += 10; // to move it south of the mouse cursor
			div.style.top = posy + 'px';
		} // end if
		div.show();
	} else {
		alert("Div not found: " + divname );
	} // end if
} // end function

function open_window(url,title,options) {
	var upload_window = window.open(url,title,options);
	upload_window.focus();
}

function toggleContent( divID, show_url, inputs, hide_url ) {
	var div = $( divID );

	var params = new Array();
	if ( inputs ) {
	while ( inputs.length ) {
		params[params.length] = inputs.shift() + '=' + inputs.shift();
	}
	} // end if

	if ( div.style.display == 'none' ) {
		div.show();
		divID.load( show_url, params );
	} else {
		div.hide();
		if ( hide_url ) {
			divID.load( hide_url, params );
			//new Ajax.Updater( divID, hide_url, { parameters: params.join('&'), evalScripts: true } );
		}
	} // end if
} // end function toggleContent

var openprint_load_content_ajax = null;
function LoadContent( divID, page, parameters, message ) {
    if ( openprint_load_content_ajax ) { openprint_load_content_ajax.transport.abort(); }

	var div = $( divID );
	if ( div ) {
		if ( message ) { 
			div.innerHTML = message;
		} else { 
			div.innerHTML = 'Please wait....';
		} // end if
	} // end if
	var method = 'get';
	//alert( typeof parameters );
	if ( ! parameters ) { 
		parameters = '';
	} else if ( parameters == '[object HTMLFormElement]' ) {
		var p = parameters.serialize(true);
		if ( p )
			parameters = $H(p).toQueryString();
	} else if ( typeof parameters == 'object' ) {
		//var p = parameters.serialize(true);
		//if ( p )
			parameters = $H(parameters).toQueryString();
	} 
	if ( parameters.length > 8190 ) 
		method = 'post';
	
	openprint_load_content_ajax = divID.load( page, parameters );
} // end function LoadContent

function photo_popup( asset_id, album_id ) {
	popup_window('/photo_albums/_view_photo.html?asset_id='+asset_id+'&amp;album_id='+album_id, '', { width: window.innerWidth-100, height: window.innerHeight-100 } );
} // end function photo_popup

var popupWin;
function popup_window( url, parameters, options ) {
	if ( ! options ) options = {};
	if ( (! options.width) && ! ( options.left && options.right) ) options.width = 400;
	if ( (! options.height) && ! ( options.top && options.bottom ) ) options.height = 400;

	if ( ! popupWin ) {
		var defaults = {
			maximizable: false,
			resizable: true,
			hideEffect:Element.hide,
			showEffect:Element.show,
			destroyOnClose: true,
			className:"alphacube",
			width:400,
			height:400, 
			recenterAuto:false
		}

       var d = $('#dialog');
        if ( ! d.length ) {
			console.log("Creating dialog elemtn");

			$('body').append('<div id="dialog" style=""></div>' );
       d = $('#dialog');
		} else {
			console.log("Dialog is " + d.length );
        }

        d.load( url );
        d.dialog();


		//Object.extend( defaults, options );

		//popupWin = new Window(defaults);

		// Set up a windows observer, check ou debug window to get messages
		//myObserver = {
//onDestroy: function(eventName, win) {
				//if (win == popupWin) {
					//popupWin = null;
					//Windows.removeObserver(this);
				//}
			//}
		//}
		//Windows.addObserver(myObserver);
	} // end if
	//popupWin.setHTMLContent('Loading... please wait');
	//if ( options && options.center != "" ) {
		//if ( options.center == "true" ) {
			//popupWin.showCenter();
		//} else {
			//popupWin.show();
		//} // end if
	//} else {
		//popupWin.showCenter();
	//} // end if
	//if ( options && options.content ) {
		//popupWin.setHTMLContent( options.content );
	//} else {
		//if ( parameters ) {
			//if ( parameters == '[object HTMLFormElement]' ) {
				//var p = parameters.serialize(true);
				//if ( p )
					//parameters = $H(p).toQueryString();
			//} else if ( typeof parameters == 'object' ) {
				//parameters = $H(parameters).toQueryString();
			//}
			//url += '?' + parameters;
		//}
		//popupWin.setAjaxContent(url, null , true);
	//} // end if
} // end function popup_window


function toggle_input( ddm, txt ) {
	ddm.toggle();
	txt.toggle();
	if ( ddm.visible() ) {
		ddm.focus();
		txt.value = '';
	} 
	if ( txt.visible() ) {
		txt.focus();
		ddm.selectedIndex = -1;
	}
}

function getValues( form, element_names, more_values ) {
	form = $(form);
	var results = new Hash( more_values );
	if ( element_names.constructor == Array ) {
		for ( var index = element_names.length; index; index -- ) {
			var form_element = form.elements[element_names[index-1]];
			if ( form_element ) {
				results.set(element_names[index-1], get_value( form_element ) );
			} // end if
		} // end for
	} else if ( element_names.constructor == RegExp ) {
		for ( var index = 0, len = form.elements.length; index < len; index += 1 ) {
			if ( element_names.exec( form.elements[index].name ) ) {
				results.set(form.elements[index].name, get_value( form.elements[index] ) );
			} // end if	
		} // end foreach element
	} // end if ARRAY or Regexp
	return results;
} // end function getValues

function trim (str) {
	str = str.replace(/^\s+/, '');
	for (var i = str.length - 1; i >= 0; i--) {
		if (/\S/.test(str.charAt(i))) {
			str = str.substring(0, i + 1);
			break;
		}
	}
	return str;
}
function toggletinymce(textarea_id, toggle ) {
	//var textarea = $(textarea_id);
	if (tinyMCE.getInstanceById(textarea_id) == null) {
		if ( toggle && toggle.innerHTML ) toggle.innerHTML = 'Hide Editor';
		tinyMCE.execCommand('mceAddControl', false, textarea_id);
	} else {
		if ( toggle && toggle.innerHTML ) toggle.innerHTML = 'Show Editor';
		tinyMCE.execCommand('mceRemoveControl', false, textarea_id);
	} // end if
} // end function toggletinymce

function changed( e, div ) {
	if ( ! div ) div = e;
	if(e.value!=e.defaultValue){
		e.addClassName('changed');
	} else {
		e.removeClassName('changed');
	} // end if
} // end function changed

if (!Array.prototype.map)
{
	Array.prototype.map = function(fun /*, thisp*/)
	{
	var len = this.length;
	if (typeof fun != "function")
		throw new TypeError();

	var res = new Array(len);
	var thisp = arguments[1];
	for (var i = 0; i < len; i++)
	{
		if (i in this)
		res[i] = fun.call(thisp, this[i], i, this);
	}

	return res;
	};
}

function get_form_element_array( form, name ) {
	var values;
	if ( form.elements[name] ) {
		if ( ! form.elements[name].length ) {
			values = new Array()
			values.push( form.elements[name].value );
		} else {
			values = $A(form.elements[name]).map( function( e ) { return e.value; } );
		}
	} else {
		values = new Array()
	} // end if
	return values;
} // end function get_form_element_array

// We do the matching to prevent cursor movements
function input_filter(e,regexp) {
	if ( e.value.match(regexp) )
		e.value = e.value.replace(regexp,'');
	return e.value;
}
function cardinalize(e) {
	if ( e.value && e.value.match(/[^\d\%\*]/) ) {
		e.value = e.value.replace(/[^\d%\*]/g,'');
	}
	return e.value;
}
function integerize(e) {
	if ( e.value.match(/[^\d\-%\*]/) )
		e.value = e.value.replace(/[^\d\-%\*]/g,'');
	return e.value;
}
function to_hostname(e) {
	if ( e.value.match(/\s/) ) {
		e.value = e.value.replace(/\s/g,'');
	} 
}
function floatize(e) {
	if ( e.value.match(/[^\d\+\-\.%\*]/) ) {
		e.value = parseFloat(e.value.replace(/[^\d\+\-\.%\*]/g,''));
	} 
	if ( e.value == 'NaN' )
		e.value = '';
	return e.value;
}
function positive_floatize(e) {
	if ( e.value.match(/[^\d\+\.%\*]/) ) {
		e.value = parseFloat(e.value.replace(/[^\d\+\.%\*]/g,''));
	} 
	if ( e.value == 'NaN' )
		e.value = '';
	return e.value;
}
function floatize_calculator(e) {
	if ( e.value.match(/[^\d\-\.\+\*=\/]/g) )
		e.value = parseFloat(e.value.replace(/[^\d\-\.=\+\*\/]/g,''));
	return e.value;
}
function hexize(e) {
	e.value = e.value.replace(/[^\da-fA-F%]/g,'');
	return e.value;
}
function createThrobber( img, preview ) {
	var x = img.x;
	var y = img.y;
 
	var canvas = document.createElement("canvas");
	preview.appendChild(canvas);
	canvas.width = preview.getStyle('width');
	canvas.height = preview.getStyle('height');
alert(img.getStyle('width'));
	var size = Math.min(canvas.height, canvas.width);
	canvas.style.top = y + "px";
	canvas.style.left = x + "px";
	canvas.classList.add("throbber");
	var ctx = canvas.getContext("2d");
	ctx.textBaseline = "middle";
	ctx.textAlign = "center";
	ctx.font = "15px monospace";
	ctx.shadowOffsetX = 0;
	ctx.shadowOffsetY = 0;
	ctx.shadowBlur = 14;
	ctx.shadowColor = "white";
 
	var ctrl = {};
	ctrl.ctx = ctx;
	ctrl.update = function(percentage) {
		var ctx = this.ctx;
		ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
		ctx.fillStyle = "rgba(0, 0, 0, " + (0.8 - 0.8 * percentage / 100)+ ")";
		ctx.fillRect(0, 0, ctx.canvas.width, ctx.canvas.height);
		ctx.beginPath();
		ctx.arc(ctx.canvas.width / 2, ctx.canvas.height / 2,
				size / 6, 0, Math.PI * 2, false);
		ctx.strokeStyle = "rgba(255, 255, 255, 1)";
		ctx.lineWidth = size / 10 + 4;
		ctx.stroke();
		ctx.beginPath();
		ctx.arc(ctx.canvas.width / 2, ctx.canvas.height / 2,
				size / 6, -Math.PI / 2, (Math.PI * 2) * (percentage / 100) + -Math.PI / 2, false);
		ctx.strokeStyle = "rgba(0, 0, 0, 1)";
		ctx.lineWidth = size / 10;
		ctx.stroke();
		ctx.fillStyle = "white";
		ctx.baseLine = "middle";
		ctx.textAlign = "center";
		ctx.font = "10px monospace";
		ctx.fillText(percentage + "%", ctx.canvas.width / 2, ctx.canvas.height / 2);
	}
	ctrl.update(0);
	return ctrl;
}
var is_IOS = null;
function isIOS() {
	if ( is_IOS != null ) return is_IOS;
	useragent = navigator.userAgent.toLowerCase();
	is_IOS = useragent.search('iphone') || useragent.search('ipod') || useragent.search('ipad');
	return is_IOS;
} // end function isIOS

function get_date_value( prefix ) {
	var date = new Array();
	[ 'year', 'month', 'day' ].each( function(suffix) {
		var e = $(prefix+'_'+suffix);
		if ( ! e ) { 
			alert( 'No ' + prefix+'_'+suffix );
			return '';
		} // end if
		var v = get_value( e );
		if ( ! v ) {
			alert( 'No value for ' + prefix+'_'+suffix );
			return '';
		} // end if
		date.push( v );
	});
	return date.join('-');
} //und function get_date_value

function getSelectedLocation(text, li) {
	if ( li.id ) {
		new Ajax.Request( '/location/_load_location.json', { parameters: { location_id: li.id } } );
	} // end if
}

var filter_ajax = null;
function filter_companies( e, p ) {
    if ( filter_ajax ) { filter_ajax.abort(); }
        
    filter_ajax = e.load( '/includes/_company_ddm.html', p, function(){filter_ajax = null;} );
}
function stop_filter_companies() {
    if ( filter_ajax ) { 
		filter_ajax.abort();
		filter_ajax = null;
	}
} 
