
function validate_data(formName) {
	return true;
	// there is nothing we really need to check at this point.
	var form = getFormObj( formName );

	var text = '';

    for ( var index = 0; index < form.elements.length; index += 1 ) {
        var name = form.elements[index].name;
        if ( name.substr(0,9) == 'SheetQty1' ) {
            var sig_index = name.substr(10,name.length-10);

			if ( ! ( 0 < parseFloat(form.elements['txtWidth-'+sig_index].value) ) ) {
				text += "Please enter a valid Final Width.\n";
			} // end if
			if ( ! ( 0 < parseFloat(form.elements['txtHeight-'+sig_index].value) ) ) {
				text += "Please enter a valid Final Height.\n";
			} // end if
			if ( 
				! ( 0 < parseFloat(form.elements['txtQty-'+sig_index].value) ) 
				) {
                text += "Please enter the number of scores.\n";
            } // end if

			if ( ( ! form.elements['rdbInlinePerfScoring-'+sig_index][0].checked ) && ( ! form.elements['rdbInlinePerfScoring-'+sig_index][1].checked ) ) {
				text += "Please select whether your performations or scores run non-continuous or non-parallel.\n";
			} // end if
		} // end if
	} // end for

    if ( text ) {
        text = "Your form is incomplete !\n\nIf you would like to continue please click OK, otherwise click Cancel and complete the following fields: \n\n" + text;
        if ( ! confirm(text)) {
            // if the click Cancel on the pop-up, then return false to cancel the submit
            return false;
        } // end if
    } // end if

	return true;
} // end function validate
