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


var QUANTITY_DIFFERENCE = {
    press   : [ 1.5,  5, 10000],
    digital : [ 4.0,  8,  2500],
    web     : [ 1.5,  5, 20000]
};

Event.observe(window, 'load', function () {
    var quantities = [ 
        $('txtQuantity1'), $('txtQuantity2'), $('txtQuantity3') 
    ];
    if (!quantities[0]) return;

    var quantity;

    for (var i=0; i < quantities.length; i++) {
        quantity = quantities[i];

        Event.observe(quantity, 'focus', function () {
            for (var j=0; j < quantities.length; j++) {
                if (this == quantities[j]) {
                    return;
                }
                else if (!quantities[j].value) {
                    quantities[j].focus();
                    return;
                }
            }
        }.bind(quantity));

        Event.observe(quantity, 'change', function () {
            // Validate Entered Quantity
            if (!quantity_validation(this)) {
                alert('Warning: Quantities must be whole numbers.');
                this.select();
                return;
            }

            // Validate Press Type Selection & Collect Related Data
            var pressTypes = document.getElementsByName('rdbPressType');
            var press;

            if (pressTypes && pressTypes.length > 0) {
                for (var j=0; j < pressTypes.length; j++) {
                    if (pressTypes[j].checked || pressTypes[j].type == 'hidden') {
                        press = pressTypes[j];
                        break;
                    }
                }
            }
            else {
                press = true;    
            }

            if (!press) {
                alert('Warning: Specifying quantities before equipment type reduces warning capabilities.');
                return;
            }

            var press_factors = QUANTITY_DIFFERENCE[press.value];

            if (!press_factors) return;

            // Validate Quantities & Collect Related Data
            var additional_quantities = [];
            var warnings = [];
            var warning_division, warning_subtraction;
            var warning_message = 'Warning';
            var warning_size, warning_action;

            if (quantities[1].value && quantity_validation(quantities[1]) && quantities[1].value > 0) {
                additional_quantities[additional_quantities.length] = quantities[1];
            }
            if (quantities[2].value && quantity_validation(quantities[2]) && quantities[2].value > 0) {
                additional_quantities[additional_quantities.length] = quantities[2];
            }

            if (press_factors && press_factors.length > 0 && additional_quantities.length > 0) {
                for (var i=0; i < additional_quantities.length; i++) {
                    if (parseInt(quantities[0].value) > parseInt(additional_quantities[i].value)) {
                        warning_division = quantities[0].value / additional_quantities[i].value;
                        warning_subtraction = additional_quantities[i].value - quantities[0].value;
                        warning_size = 'smaller';
                        warning_action = 'raising';
                    }
                    else if (parseInt(additional_quantities[i].value) > parseInt(quantities[0].value)) {
                        warning_division = additional_quantities[i].value / quantities[0].value;
                        warning_subtraction = additional_quantities[i].value - quantities[0].value;
                        warning_size = 'larger';
                        warning_action = 'lowering';
                    }

                    if (Math.round(10 * warning_division) > Math.round(10 * press_factors[0])) {
                        if (Math.round(10 * warning_division) > Math.round(10 * press_factors[1])) {
                            warnings[warnings.length] = [additional_quantities[i], warning_size, warning_action];
                        }
                        else if (warning_subtraction > press_factors[2]) {
                            warnings[warnings.length] = [additional_quantities[i], warning_size, warning_action];
                        }
                    }
                }
            }

            for (var j=0; j < warnings.length; j++) {
                warning_message += '\n\n ' + warnings[j][0].id.replace('txt', '').replace('Quantity', 'Quantity ') + ' is significantly ' + warnings[j][1] + ' than the first quantity. It may not price accurately. Please consider '  + warnings[j][2] + ' the value, or pricing each quantity as a separate project.';
            }

            if (warnings.length > 0) {
                alert(warning_message);
            }

        }.bind(quantity));
    }
});

// Design Format - When Other is Selected, Other Format TxT comes up.
Event.observe(window, 'load', function () {
    var format = $('ddmFormat');
    var other  = $('other_program');

    var is_other = function () {
        other.style.display 
                = format[format.selectedIndex].value == 'Other' ? '' : 'none'; 
    }

    Event.observe(format, 'change', is_other);

    is_other();
});
