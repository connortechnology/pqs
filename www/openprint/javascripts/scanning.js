var debug = false;

function calc_from_width( formName ){
	var form = getFormObj( formName )
	form.txtScanWidthFinal.value = form.txtScanWidth.value * form.txtPercent.value / 100;
	calc( formName );
}	

function calc_from_height( formName ){
	var form = getFormObj( formName )	
	form.txtScanHeightFinal.value = form.txtScanHeight.value * form.txtPercent.value / 100;
	calc( formName );		
}

function calc_size( formName ){
	var form = getFormObj( formName )	
	var percent = form.txtPercent.value / 100;
	form.txtScanWidthFinal.value = form.txtScanWidth.value * percent;
	form.txtScanHeightFinal.value = form.txtScanHeight.value * percent;
	calc( formName );
}// end calc_size

function calc_percent_from_width( formName ) {
	var form = getFormObj( formName );
	var percent = Math.round (form.txtScanWidthFinal.value / form.txtScanWidth.value * 100);
	form.txtScanHeightFinal.value = form.txtScanHeight.value * percent / 100;
	form.txtPercent.value = percent;
	calc( formName );
} // end calc_percent_from_width

function calc_percent_from_height( formName ){
	var form = getFormObj( formName );
	var percent = Math.round (form.txtScanHeightFinal.value / form.txtScanHeight.value * 100);
	form.txtScanWidthFinal.value = form.txtScanWidth.value * percent / 100;
	form.txtPercent.value = percent;
	calc( formName );
} // end calc_percent_from_height

function random_proof( formName ){
	var form = getFormObj( formName );
	if ( form.rdbRandomProof[0].checked == 1 ) {
		alert ("Upon adding the present service to the project, the proof form will provide the opportunity to add random proof(s) for the present scan(s)");
	} // end if
} // end random_proof

function validate_data(formName) {
    var form = getFormObj(formName);
    var text = '';

	if ( ! ( form.rdbScanner[0].checked || form.rdbScanner[1].checked ) ) {
		text += "Please select the type of scanner required.\n";
	} // end if

	if ( ! ( form.ddmOriginal.selectedIndex > 0 ) ) {
		text += "Please select the type of originals.\n";
	} // end if

	if ( ! ( 0 < parseInt( form.txtScanWidth.value ) ) ) {
        text += "Please specify the original width of the item(s) being scanned.\n";
    } // end if
	if ( ! ( 0 < parseInt( form.txtScanHeight.value ) ) ) {
        text += "Please specify the original height of the item(s) being scanned.\n";
    } // end if
	if ( ! ( 0 < parseInt( form.txtPercent.value ) || ( 0 < parseInt( form.txtScanHeightFinal.value ) && 0 < parseInt( form.txtScanWidthFinal.value )) ) ) {
        text += "Please specify the % of enlargement or the final dimensions of the scan(s).\n";
    } // end if
	if ( ! ( 0 < parseInt( form.txtQuantity.value ) ) ) {
        text += "Please specify the quantity of scans.\n";
    } // end if


    if ( text ) {
        text = "Your form is incomplete !\n\nIf you would like to continue please click OK, otherwise click Cancel and complete the following fields: \n\n" + text;
        if ( ! confirm(text)) {
            // if the click Cancel on the pop-up, then return false to cancel the submit
            return false;
        } // end if
    } // end if

	return true;
} // end function
