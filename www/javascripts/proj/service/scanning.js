// Copyright (c) 2004 Print-Quotes Software Inc. All rights reserved.

service.validate = function (e) {
	var form    = this.form;
	var text    = '';
    var is_auto = !e || e.type == 'load'; // Interactive only on user events.

//	if ( ! ( form.rdbScanner[0].checked || form.rdbScanner[1].checked ) ) {
//		text += "Please select the type of scanner required.\n";
//	} 
	if ( ! ( form.ddmOriginal.selectedIndex > 0 ) ) {
		text += "Please select the type of originals.\n";
	} 
	if ( ! ( 0 < parseInt( form.txtScanWidth.value ) ) ) {
        text += "Please specify the original width of the item(s) being scanned.\n";
    } 
	if ( ! ( 0 < parseInt( form.txtScanHeight.value ) ) ) {
        text += "Please specify the original height of the item(s) being scanned.\n";
    } 
	if ( ! ( 0 < parseInt( form.txtPercent.value ) || ( 0 < parseInt( form.txtScanHeightFinal.value ) && 0 < parseInt( form.txtScanWidthFinal.value )) ) ) {
        text += "Please specify the % of enlargement or the final dimensions of the scan(s).\n";
    } 
	if ( ! ( 0 < parseInt( form.txtQuantity.value ) ) ) {
        text += "Please specify the quantity of scans.\n";
    } 

    if (text) {
        if (!is_auto) {
            alert('Your form is incomplete:\n\n' + text);
        }
        return false;
    } 
	return true;
}

