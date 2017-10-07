// Copyright (c) 2004 Print-Quotes Software Inc. All rights reserved.

service.validate = function (e) {
    var form    = this.form;
    var text    = '';
    var is_auto = !e || e.type == 'load'; // Interactive only on user events.

    if ( ! ( 0 < parseInt( form.txtHoleQty.value ) ) ) {
        text += "Please specify the number of holes per item.\n";
    } 
    if ( ! ( 0 < parseFloat( form.txtHoleSize.value ) ) ) {
        text += "Please specify the size of the hole(s).\n";
    } 

    if (text) {
        if (!is_auto) {
            alert('Your form is incomplete:\n\n' + text);
        }
        return false;
    }

    return true;
}
 
