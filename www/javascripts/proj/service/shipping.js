// Copyright (c) 2004 Print-Quotes Software Inc. All rights reserved.

Event.observe(window, 'load', function (e) {
    var form  = $('f1');
    var elems = form.rdbShippingContents;

    for (var i=0; i < elems.length; i++)
        Event.observe(elems[i], 'click', select_item_quantity);
});

function select_item_quantity (e) {
    var item;
    var form = document.f1;
    var type;
	
	if ( e ) {
    	item = Event.element(e);
    	type = $F(item);  // Shipment contents type
	} else {
		type = $('rdbShippingContentsSamples').checked ? 'Samples'
			 : $('rdbShippingContentsProofs').checked  ? 'Proofs'
			 : 											 'Project';
	}


    for (var i = 1; i <= 3; i++) {
        var qty = form['txtQuantity' + i];

        if (!qty) continue;

        var field = type == 'Proofs'  ? form['hdnProofQuantity']
                  : type == 'Project' ? form['hdnQuantity' + i]
                  :                     form['hdnSampleQuantity'];

        qty.value = field.value;
    }
    return true;
}

