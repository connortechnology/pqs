// Copyright (c) 2004 Print-Quotes Software Inc. All rights reserved.

/*
service.validate = function (e) {
    var form    = this.form;
    var text    = '';
    var is_auto = !e || e.type == 'load'; // Interactive only on user events.

	for (var i=0; i < form.elements.length; i++) {
		if ( form.elements[i].name.substr(0,12) == 'ddmProofType' ) {
			var ies = form.elements[i].name.substr(12,form.elements[i].name.length-12);
			var proofType = form.elements[i].options[form.elements[i].selectedi].value;
			var qty = parseInt(form.elements['txtProofQuantity'+ies].value);
			var width = form.elements['txtProofWidth'+ies].value;
			var height = form.elements['txtProofHeight'+ies].value;
			if ( ! qty > 0 ) {
				text += " Please enter the number of proofs you require. \n";
			} 
			if ( ! width > 0 ) {
				text += " Please enter the width of the proof. \n";
			} 
			if ( ! height > 0 ) {
				text += " Please enter the height of the proof. \n";
			}
		} 
	} 

    if (text) {
        if (!is_auto) {
            alert('Your form is incomplete:\n\n' + text);
        }
        return false;
    }

    return true;
} 
*/
 
