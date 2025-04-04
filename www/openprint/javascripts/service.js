"use strict";
// The following are GLOBAL variables
var gettingNewPrice = false;
var submitForm = false;
// Default, can be overriden in services
var results_callback = cbFillResults;

var breakdownWin = new Array();

function show_breakdown( index ) {
	if ( gettingNewPrice )
		return;
    if (breakdownWin[index] == null) {
		breakdownWin[index] = new Window({
			maximizable: false,
			resizable: false,
			hideEffect:Element.hide,
			showEffect:Element.show,
			destroyOnClose: false,
			className:'alphacube',
			width:700,
			height:420,
			recenterAuto:false
			} );
		breakdownWin[breakdownWin[index]] = index;

		// Set up a windows observer, check our debug window to get messages
		const myObserver = {
			onDestroy: function(eventName, win) {
				if ( win == breakdownWin[breakdownWin[win]] ) {
					breakdownWin[breakdownWin[win]] = null;
					breakdownWin[win] = null;

					win.getContent().hide;
					Windows.removeObserver(this);
				} // end if
			} // onDestroy
		} // myObserver
		Windows.addObserver(myObserver);
	} // end if
	breakdownWin[index].setContent( 'hdnBreakdown'+index, false, false );
	breakdownWin[index].showCenter();
} // end function show_breakdown

function submit_handler( formName ) {
	const form = getFormObj( formName );
	if ( ! form ) {
		return false;
	}
	const AlertDiv = document.getElementById('AlertDiv');
	if ( AlertDiv && AlertDiv.innerHTML ) {
		let alert_content = AlertDiv.innerHTML;
		alert_content = alert_content.replace(/<br\/?>/g, "\n" );
		alert_content = alert_content.replace(/&lt;/g, '<' );
		alert_content = alert_content.replace(/&gt;/g, '>' );
		if ( ! confirm( "There are unresolved errors:\n\n" + alert_content + "\n\n Click OK to continue saving, or Cancel to stop and fix the problem." ) ) {
			return false;
		} // end if
	} // end if

	if ( gettingNewPrice && ! confirm('The system is still calculating a price.  Click OK to continue saving, or Cancel to wait for the system') ) {
		return false;
	} // end if

	let Status = true;
	if ( typeof(validate_data) == 'function' ) {
		Status = validate_data(formName);
	} // end if

	if (Status) {
		form.submit();
	} // end if
	return Status;
} // end function submit_form

function cbWindowSaveClose( results ) {
	window.close();
} 

function body_onLoad() {
	if ( typeof(selectProjectTemplate) == 'function' ) {
		selectProjectTemplate( 'f1' );
	} else if ( typeof(calc) == 'function' ) {
		calc('f1');
  } else {
    console.log("Nothing to do in service.js");
	} // end if
}

var timeout;
var block_calc = false;
function calc( formName='f1', force, options ) {
	if ( block_calc ) return;

	const form = getFormObj( formName );
  if (!form) {
    console.log("No form found for "+formName);
    return;
  }
  if (!form.ServiceType) {
    alert("No ServiceType found. Please contact your developer.");
    return;
  }

  if ( gettingNewPrice && ! force ) {
    if ( timeout ) clearTimeout( timeout );
    if ( options ) {
      timeout = setTimeout("calc_print('"+formName+"', 0, " + Object.toJSON( options ) + ");", 1000 );	
    } else {
      timeout = setTimeout("calc('" + formName + "');", 1000);
    }
  } else {
    gettingNewPrice = true;
    timeout = null;
    const AlertDiv = document.getElementById('AlertDiv');
    if ( AlertDiv ) {
      AlertDiv.innerHTML = '';
      AlertDiv.hide();
    } // end if
    const div = document.getElementById('InformationDiv');
    if ( div ) {
      div.innerHTML = 'Calculating';
    } // end if
    clear_price_data( form );
    const data = $j(form).serializeArray();
    //if ( options ) {
    //data.merge( options );
    //}
    const filtered_data = data.filter((pair) => {
      return !(
        (pair.value == '')
        ||
        (pair.name == 'btnFunction')
        ||
        (pair.name == 'alert'));
    });

    //new Ajax.Request( '/main/project/_calc.json', { method: 'post', parameters: h, evalScripts: true } );
    $j.ajax({
      type: "POST",
      url: '/openprint/main/project/_calc.json',
      data: filtered_data,
      dataType: 'json',
      success: function(data, textStatus, jqXHR) {
        console.log(data);
        results_callback(data);
      }
    }).done(function(data) {
      console.log("done", data);
    }).fail(function(jqXHR, textStatus, errorThrown) {
      gettingNewPrice = false;
      console.log("fail", jqXHR, textStatus);
    });
  } // end if
} // end calc()

function cbFillResults( results ) {
  if (!results) {
    console.log("cbFillResults called without results.");
    return;
  }
	block_calc = true;
	const form = getFormObj('f1');
	const AlertDiv = $('AlertDiv');
	if ( AlertDiv ) {
		AlertDiv.innerHTML = '';
		AlertDiv.hide();
	} // end if
	if ( $('InformationDiv') )
		$('InformationDiv').hide();
	const keys = Object.keys(results);

  for (const [key, value] of Object.entries(results)) {
	//for ( let index = 0, leni = keys.length; index < leni; index += 1 ) {
		//const key = keys[index];
		//const value = results.get(keys[index]);
		if ( key == 'alert') {
			if (value != '') {
				const div = $('AlertDiv');
				if ( div ) {
					div.innerHTML = value;
					div.show();
				} else {
					alert( value );
				} // end if
			} // end if
			const alert_div = $('alert');
			if ( alert_div ) { alert_div.value = value };
			continue;
		} else if ( key == 'popup') {
			alert( value );
			continue;
		} else if ( key == 'information') {
			if (value != '') {
				const div = $("InformationDiv");
				if ( div ) {
					div.innerHTML = value;
					div.show();
				} // end if
			} // end if
			continue;
		} // end if

		const element = form.elements[key];
		if ( element ) {

//if ( element.onchange ) {
//console.log(element.name + element.onchange);
//} else {
//console.log(element.name + ' ' + element.type + ' no onchange' );
//}
			if ( element.type == 'select-one' ) {
				ddm_select_by_value( element, value, -1 );
			} else if ( element.type == 'checkbox' ) {
				if ( element.value == value ) {
					if ( ! element.checked ) {
						element.checked = true;
						if ( element.onchange ) {
							console.log("Calling onchange of checkbox " + element.name );
							element.onchange();
						}
					} // endif
				} else {
					if ( element.checked ) {
						element.checked = false;
						if ( element.onchange ) {
							console.log("Calling onchange of checkbox " + element.name );
							element.onchange();
						}
					} // endif
				} // end if
			} else if ( element.type == 'radio' ) {
        console.log(element.name + " is a radio... which we don't handle");
			} else if ( element.type == 'text' || element.type == 'number' || element.type == 'email' ) {

				if ( element.value != value ) {
					if ( ! element.gotFocus ) {
						element.value = value;
						if ( element.onchange ) {
							console.log("Calling onchange of unfocused input  " + element.name );
							element.onchange();
						}
					} 
				} // end if
			} else if ( element.type == 'hidden' ) {
				element.value = value;
			} else if ( element.length ) {
				const elements = element;
				for ( let j=0, lenj = elements.length; j < lenj; j += 1 ) {
					if ( elements[j].value == value ) {
						if ( ! elements[j].checked ) {
							elements[j].checked = true;
							if ( elements[j].onchange ) { 
								console.log("Calling onchange of checkbox " + elements[j].name );
								elements[j].onchange();
							}
						} // endif
					} else {
						if ( elements[j].checked ) {
							elements[j].checked = false;
							if ( elements[j].onchange ) { 
								console.log("Calling onchange of checkbox " + elements[j].name );
								elements[j].onchange();
							}
						} // endif
					} // end if
				} // end for

			} // end if
		} else {
      const div = $(key);
      if (div) {
        if ( typeof(value)== "object" ) {
          if ( value.addClassName ) {
            div.addClassName( value.addClassName );
          }
          if (value.removeClassName ) {
            div.removeClassName( value.removeClassName );
          }
        } else {
          //console.log('filling: ' + key + ' with: ' + value );
          //div.hide();
          div.innerHTML = value;
          //d//iv.show();
        }
      } else {
        //console.log("didnt find " + key );
      } // end if
    } // end if
	} // end for each 
	gettingNewPrice = false;
	block_calc = false;
} // end function cbFillResults

function clear_price_data( form ) {
  for ( let qtyNum = 1; qtyNum <= 3; qtyNum += 1 ) {
    if ( form.elements['txtPrice'+qtyNum] && form.elements['OverridePrice'+qtyNum] && ! get_value(form.elements['OverridePrice'+qtyNum]) ) form.elements["txtPrice"+qtyNum].value = '';
    if ( form.elements['txtUnitPrice'+qtyNum] ) form.elements["txtUnitPrice"+qtyNum].value = '';
    if ( form.elements['MPrice'+qtyNum] ) form.elements["MPrice"+qtyNum].value = '';
  } // end for
} // end function clear_price_data( form )
