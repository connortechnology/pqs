function FoldType_onchange( select ) {
	var foldtype = get_ddm_value( select );
	var image = document.images['FoldType'];
	if ( image ) {
		if ( foldtype != '' ) {
			image.style.display = 'inline';
			image.src = '/images/templates/' + foldtype +  '.gif';
		} else {
			image.style.display = 'none';
		} // end if
	} // end if
	Dimensions_onchange( select );
} // end function

function calc( formName, force ) {
	var form = $(formName);
	if ( ! form ) return;

	if ( form.txtPrice1 ) {
		form.txtPrice1.value = '';
	} // end if
	if ( form.ProductionPrice1 ) {
		form.ProductionPrice1.value = '';
	} // end if
	if ( form.ShippingPrice1 ) {
		form.ShippingPrice1.value = '';
	} // end if

	if ( form.HoleDrilling && ( get_rdb_value( form.HoleDrilling ) == 'Y' ) ) {
		if ( form.txtHoleQty.value == '' ) {
			form.txtHoleQty.value = '1';
		} // end if
	} // end if

	var div = $('AlertDiv');
	if ( ! div ) {
		//alert('No alert div.');
	} else {
		div.hide();
	} // end if

	if ( gettingNewPrice && ! force ) {
		if ( timeout ) clearTimeout( timeout );
		timeout = setTimeout("calc('"+formName+"');", 1000 );
		return;
	} // end if
	timeout = null;
	gettingNewPrice = true;
	var h = $H(Form.serialize(form,true));
	h.set( 'ServiceType', 'Project' );
	h.set( 'callback', 'cbCalc' );
	new Ajax.Request( '/main/project/_calc.json', { method: 'post', parameters: h, evalScripts: true } );
	remove_div('Buttons');
	add_div('Processing');
}

function cbCalc( results ) {
	cbFillResults(results);
	var form = getFormObj('f1');
	add_div('Buttons');
	remove_div('Processing');
	
	if ( form.Status.value == 'uncalculated' ) {
		remove_div('OrderButton');
	} else {
		add_div('OrderButton');
	} // end if

	if ( form.Scoring ) {
		if ( 'Y' == get_rdb_value( form.Scoring ) ) {
			add_div('ScoringDiv');
		} else {
			remove_div('ScoringDiv');
		} // end if
	} // end if
	if ( form.rdbCover ) {
		if ( get_value(form.rdbCover)=='Self' ) {
			remove_div('CoverStocks');
		} else if ( get_value(form.rdbCover)=='Different') {
			add_div('CoverStocks');
		} // end if
	} // end if
}


function Dimensions_onchange( select, signature ) {
	var value = get_ddm_value( select );
	if ( value == 'Custom' ) {
		$('CustomDimensions').show();
	} else {
	//remove_div('CustomDimensions');
	} // end if
	remove_div('OrderButton');
	// Refreshes Paper: we do this so that we don't get any stocks in the list that are smaller than our size.
	Stock_onchange( select, signature );
} // end if

var contentWin;
function breakdown_window(project_id) {
	if (contentWin != null) {
		Dialog.alert("Close the window 'Test' before opening it again!",{width:200, height:130});
	} else {
		contentWin = new Window({maximizable: false, resizable: false, hideEffect:Element.hide, showEffect:Element.show, destroyOnClose: true,
				className:"alphacube", width:640, height:480
				} );
		contentWin.setAjaxContent('/content/prin/_breakdown.html', {parameters:'project_id='+project_id}, true);
		// Set up a windows observer, check ou debug window to get messages
		myObserver = {
onDestroy: function(eventName, win) {
			   if (win == contentWin) {
				   contentWin = null;
				   Windows.removeObserver(this);
			   }
		   }
		}
		Windows.addObserver(myObserver);
	}
} // end function breakdown_window

function click_order( form ) {
	if ( ! form.txtPrice1.value ) {
		alert( "The project is not complete, and so cannot be ordered yet." );
		return;
	} // end if
	form.action='/main/order/information.html';
	form.btnFunction.value='Process Order';
	form.submit();
}
function click_quote( form ) {
	if ( ! form.txtPrice1.value ) {
		alert( "The project is not complete, and so cannot be quoted yet." );
		return;
	} // end if 
	form.action='/main/quote/information.html';
	form.btnFunction.value='Process Quote';
	form.submit();
}
function click_upload( form ) {
	window.location = '/upload/upload_center.html?ProjectIndex=' + form.ProjectIndex.value;
}
