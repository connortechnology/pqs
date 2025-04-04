function calc_presentation_folder( formName ) {
	
	calc_flat_size(formName);
	calc_print(formName);
	
} // end calc_print


function calc_flat_size(formName) {
    var form = getFormObj( formName );
	var width = parseFloat(form.txtFinalWidth.value) * 2;
	var height = parseFloat(form.txtFinalHeight.value);
	if ( width && height ) {

		var pocketSize = 0;
		if ( form.rdbPocketSize[0].checked ) {
			pocketSize = 3;
		} else if ( form.rdbPocketSize[1].checked ) {
			pocketSize = 4;
		} else {
			pocketSize = '';
		} // end if

		if (pocketSize > 0 ) {
			height += pocketSize;
		} // end if

		if ( form.chkPocketLeft.checked ) {
			width = 0.75 + parseFloat(width);
		} // end if
		if ( form.chkPocketRight.checked ) {
			width = 0.75 + parseFloat(width);
		} // end if
	} // end if

	form.txtWidth.value = width > 0 ? width : 0;
	form.txtHeight.value = height > 0 ? height  : 0;

} // end calc_final_size

