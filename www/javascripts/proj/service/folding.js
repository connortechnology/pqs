//Copyright (c) 2004 Print-Quotes Software Inc. All rights reserved.

service.validate = function (e) {
	var form    = this.form;
	var text    = '';
    var is_auto = !e || e.type == 'load'; // Interactive only on user events.

    // At least one fold type needs to be selected.
    var has_value = $A(form.elements).any(function (field) {
        return (field.name
             && field.name.match(/^txt(\w+)(FoldQty|Folded)$/)
             && field.value > 0);
    });

    if (!has_value) {
        if (!is_auto) {
            alert('Your form is incomplete!\n\n' 
                 + 'Please select the desired folding style and quantity of signatures.');
        }
        return false;
    } 
	return true;
}

