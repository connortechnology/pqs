function convert_lbs_to_kg( from, to ) {
	var qtys = from.value.split(',');
	for ( var i=0; i< qtys.length; i+=1 ) {
		qtys[i] = do_decimals( parseFloat(qtys[i] / 2.2), 2 );
	} // end for
	to.value = qtys.join(',');
}
function convert_kg_to_lbs( from, to ) {
	var qtys = from.value.split(',');
	for ( var i=0; i< qtys.length; i+=1 ) {
		qtys[i] = parseInt(qtys[i] * 2.2);
	} // end for
	to.value = qtys.join(',');
}
var allocateWin;
function allocate_window(paper_id, skid_id, quantity ) {
	if ( ! allocateWin ) {
		allocateWin = new Window({maximizable: false, resizable: true, hideEffect:Element.hide, showEffect:Element.show, destroyOnClose: true, className:"alphacube", width:400} );
		// Set up a windows observer, check ou debug window to get messages
		myObserver = {
onDestroy: function(eventName, win) {
			   if (win == allocateWin) {
				   allocateWin = null;
				   Windows.removeObserver(this);
			   }
		   }
		}
		Windows.addObserver(myObserver);
	} // end if
	allocateWin.setHTMLContent('Loading... please wait');
	allocateWin.showCenter();
	var url = '/employee/inventory/_allocate_popup.html?paper_id='+paper_id;
	url += '&skid_id='+skid_id;
	url += '&quantity='+quantity;

	allocateWin.setAjaxContent(url, null , true);
} // end function allocate_window
var checkinWin;
function checkin_window( paper_id, skid_id, quantity ) {
	if ( ! checkinWin ) {
		checkinWin = new Window({maximizable: false, resizable: true, hideEffect:Element.hide, showEffect:Element.show, destroyOnClose: true, className:"alphacube", width:400} );
		// Set up a windows observer, check ou debug window to get messages
		myObserver = {
onDestroy: function(eventName, win) {
			   if (win == checkinWin) {
				   checkinWin = null;
				   Windows.removeObserver(this);
			   }
		   }
		}
		Windows.addObserver(myObserver);
	} // end if
	checkinWin.setHTMLContent('Loading... please wait');
	checkinWin.showCenter();
	var url = '/employee/inventory/_check_in_popup.html?paper_id='+paper_id;
	url += '&skid_id='+skid_id;
	url += '&quantity='+quantity;
	checkinWin.setAjaxContent(url, null , true);
} // end function checkin_window
var checkoutWin;
function checkout_window( paper_id, skid_id, quantity ) {
	if ( ! checkoutWin ) {
		checkoutWin = new Window({maximizable: false, resizable: true, hideEffect:Element.hide, showEffect:Element.show, destroyOnClose: true, className:"alphacube", width:400} );
		// Set up a windows observer, check ou debug window to get messages
		myObserver = {
onDestroy: function(eventName, win) {
			   if (win == checkoutWin) {
				   checkoutWin = null;
				   Windows.removeObserver(this);
			   }
		   }
		}
		Windows.addObserver(myObserver);
	} // end if
	checkoutWin.setHTMLContent('Loading... please wait');
	checkoutWin.showCenter();
	var url = '/employee/inventory/_check_out_popup.html?paper_id='+paper_id;
	url += '&skid_id='+skid_id;
	if ( quantity )
		url += '&quantity='+quantity;
	checkoutWin.setAjaxContent(url, null , true);
} // end function checkout_window

function check_inputs(form ) {

	if ( (form.Name && form.txtName) && ! ( form.Name.value || form.txtName.value ) ) {
		alert('Please select the stock Name');
		return false;
	} // end if
	if ( (form.Finish && form.txtFinish) && ! ( form.Finish.value || form.txtFinish.value ) ) {
		alert('Please select the stock Finish');
		return false;
	} // end if
	if ( (form.Finish && form.txtColour) && ! ( form.Colour.value || form.txtColour.value ) ) {
		alert('Please select the stock Colour');
		return false;
	} // end if
	if ( (form.Quality && form.txtQuality) && ! ( form.Quality.value || form.txtQuality.value ) ) {
		alert('Please select the stock Quality');
		return false;
	} // end if
	if ( form.type && ! get_rdb_value( form.type ) ) {
		alert('Please select the stock type Roll/Sheet');
		return false;
	} // end if
	if ( ( form.weight && form.calliper) && ! ( form.weight.value || form.calliper.value ) ) {
		alert('Please enter either the weight or calliper');
		return false;
	} // end if
	if ( form.type && get_rdb_value( form.type ) == 'Roll' ) {
		if ( ! form.width.value ) {
			alert('Please enter either the width');
			return false;
		} // end if
	} else {
		if ( form.width && form.height && ! ( form.width.value && form.height.value ) ) {
			alert('Please enter either the width and height');
			return false;
		} // end if
	} // end if
	if ( form.Quantity && ! form.Quantity.value ) {
		alert('Please enter the quantity of stock');
		return false;
	} // end if

	var units;
    if ( form.Units )
        units = get_value( form.Units );
    else if ($('Units'))
        units = $('Units').innerHTML;

	if ( form.available_quantity && parseInt(form.Quantity.value) > parseInt(form.available_quantity.value) ) {
		alert( 'You asked for ' + form.Quantity.value + ' but there are only ' + form.available_quantity.value + ' ' + units + ' available' );
		return false;
	} // end if
	return true;
}

function calc() {
}
function mweight_to_gsm( form ) {
	var mweight = parseFloat(1*form.elements['mweight'].value);
	var width = parseFloat(1*form.elements['width'].value);
	var height = parseFloat(1*form.elements['height'].value);
	var gsm = parseInt((mweight/1000)/(width*height)*7030645.0)/10;
	form.elements['gsm'].value = gsm;
}
function gsm_to_mweight( form ) {
	var gsm = parseFloat(1*form.elements['gsm'].value);
	var width = parseFloat(1*form.elements['width'].value);
	var height = parseFloat(1*form.elements['height'].value);
	var mweight = parseInt((gsm/703064.5)*(width*height)*10000)/10;
	form.elements['mweight'].value = mweight;
}
