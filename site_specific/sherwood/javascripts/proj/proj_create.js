function validate_data (form) {
    var text = '';
    var pressType = false;

    // Check for a press type (unless we're predefined).
    if (form.rdbPressType && form.rdbPressType.length) {
        var press_type;
        for (var i = 0; i < form.rdbPressType.length; i++){
            if (form.rdbPressType[i].checked) {
                press_type = true;
                break;
            }
        }

        if (!press_type) text += "Please select the press type.\n";
    }

    // Check for a project type (unless we're predefined).
    if (form.rdbProjectType) {
        var project_type;
        for ( var index = 0; index < form.rdbProjectType.length; index += 1 ) {
            if ( form.rdbProjectType[index].checked ) {
                project_type = true;
                break;
            } 
        } 

		// if we only have 1 project type the  above code will not find it.
        if (  ! project_type && 
		      ! form.rdbProjectType.checked ) text += "Please select the type of project.\n";
    }

    // Quantities.
    if (form.txtQuantity1 && form.txtQuantity1.value && parseInt(form.txtQuantity1.value) > 1) {
        if ( parseInt(form.txtQuantity1.value) != form.txtQuantity1.value || !quantity_validation(form.txtQuantity1)) {
            text += "The field 'Quantity 1' may only contain whole numbers greater than 1.\n";
        }
    }

    if (form.txtQuantity2 && form.txtQuantity2.value) {
        if ( parseInt(form.txtQuantity2.value) != form.txtQuantity2.value || !quantity_validation(form.txtQuantity2)) {
            text += "The field 'Quantity 2' may only contain whole numbers greater than 1.\n";
        }
    }

    if (form.txtQuantity3 && form.txtQuantity3.value) {
        if ( parseInt(form.txtQuantity3.value) != form.txtQuantity3.value || !quantity_validation(form.txtQuantity3)) {
            text += "The field 'Quantity 3' may only contain whole numbers greater than 1.\n";
        }
    }
    if (form.txtQuantity1 && ! form.txtQuantity1.value) {
        text += "Please enter a value for Quantity 1.\n";
    }
    if (form.txtProjectReference && form.txtProjectReference.value == "") {
        text += "Please give your project a reference name.\n";
    }

    // If the design format is 'other' we require a description.
    if (form.format && form.format[form.format.selectedIndex].value == 'Other' && !form.other_program.value)
        text += "Please specify a design format.\n";
    

    if (text) {
        text = "Please correct the following errors before proceeding:\n\n" + text;
        alert(text);
        return false;
    }

    return true;
}


function quantity_validation (qty_elem) {
    var qty_tmp = qty_elem.value;
    
    // handles preceeding zeros when editing. (otherwise interpreted as a hex value with parseInt)
    qty_elem.value = Math.floor(qty_elem.value);
    
    // error handling if rounding failed
    if (isNaN(qty_elem.value)) {
        qty_elem.value = qty_tmp;
        qty_elem.select();
        return false;
    }
    return true;
}

// Design Format - When Other is Selected, Other Format TxT comes up.
Event.observe(window, 'load', function () {
    var format = $('ddmFormat');
    if (!format) return;

    var other  = $('other_program');

    var is_other = function () {
        other.style.display = format[format.selectedIndex].value == 'Other' ? '' : 'none'; 
    }

    Event.observe(format, 'change', is_other);

    is_other();
});
