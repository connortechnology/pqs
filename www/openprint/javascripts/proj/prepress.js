function calc( formName ) {
	gettingNewPrice = true;
    var form = getFormObj(formName);
	var h = Form.serialize(form,true);
	h.ServiceType = 'Prepress';
	new Ajax.Request( '/main/project/_calc.json', { method: 'post', parameters: h, evalScripts: true } );
} // end calc_prepress()

function validate_data(formName) {
    var form = getFormObj(formName);
    var text = '';

	if ( form.txtQuantity.value == '' ) {
        text += "Please specify the quantity.\n";
    } // end if

    if ( text ) {
        text = "Your form is incomplete !\n\nIf you would like to continue please click OK, otherwise click Cancel and complete the following fields: \n\n" + text;
        if ( ! confirm(text) ) {
            // if the click Cancel on the pop-up, then return false to cancel the submit
            return false;
        } // end if
    } // end if 

	return true;
} // end function
