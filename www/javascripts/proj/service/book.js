
service.validate = function (e) {
    var form = this.form;
	var text    = '';
    var is_auto = !e || e.type == 'load'; // Interactive only on user events.

    if (! $A( form.template ).any(function (elem) { return elem.checked })) {
		if ( form.template.length ) {
        	text += "Please select a bindery type\n";
		} else {
			// if we only have one radio button then just select it.
			form.template.checked = true;
		}
	}

    if ( form.final_width.value == '' || form.final_height.value == '' )
        text += "Please enter the finished width and height of your project.\n";
    
    if ( form.flat_width.value == '' || form.flat_height.value == '' )
        text += "Please enter the flat width and height of your project.\n";

    if (form.rdbGateFold[0].checked) {
        if (form.txtTotalSpreadQuantity.value == 0 || form.txtTotalSpreadQuantity.value == '')
            text += "The total quantity of spreads must be greater than 0.\n";

        if (form.txtGateFoldedSpreadQuantity.value == 0 || form.txtGateFoldedSpreadQuantity.value == '')
            text += "The total quantity of gate folded spreads must be greater than 0.\n";

        if ( parseInt(form.txtTotalSpreadQuantity.value) < parseInt(form.txtGateFoldedSpreadQuantity.value) )
            text += "The total quantity of spreads must be greater or equal to the total quantity of gate folded spreads.\n";
    }

    if ( ! form.txtTotalPageQuantity.value > 0 )
        text += "Please enter the total quantity of pages.\n";

    if ( parseFloat(form.txtGateFoldedSpreadQuantity.value) > parseFloat(form.txtTotalSpreadQuantity.value) )
        text += 'The quantity of gate folded spreads can not exceed the total spread quantity.\n';

    if (text) {
        if (!is_auto) {
            alert('Your form is incomplete:\n\n' + text);
        }
        return false;
    }

    return true;
}


function clear_gate_fold(form) {
    if ( form.rdbGateFold[1].checked) {
        form.txtGateFoldedSpreadQuantity.value = ''
    } 
    else {
        form.txtTotalSpreadQuantity.value = '';
    }
}


// Hides and disables cover selection (server enforces separate cover) when
// perfect binding is selected.
Event.observe(window, 'load', function () {
    var form      = $('f1');
    var cover     = $('cover');

    var templates = form.template;
    var types     = form.rdbCover;

    var set_cover = function () {
        var is_pb = this.value == 'PerfectBinding';
           
        cover.display(!is_pb); // Show/hide the cover question.

        for (var i=0; i < types.length; i++)
            types[i].disabled = is_pb;
    }

    for (var i=0; i < templates.length; i++) {
        var template = templates[i];

        // Set initial state.
        if (template.checked) set_cover.apply(template);

        Event.observe(template, 'click', set_cover.bind(template));
    }

    return true;
});


Event.observe(window, 'load', function () {
    var gate_fold_yes = document.getElementById('rdbGateFoldYes');
    var total_spreads = document.getElementById('txtTotalSpreadQuantity');
    var gate_fold_spreads = document.getElementById('txtGateFoldedSpreadQuantity');
    var main_form = document.getElementById('f1');

    // When the Yes RDB for Gate Fold Interior Spreads is clicked, hidden details are shown.

    Event.observe(gate_fold_yes, 'click', function () {
        var parent_fieldset = this.parentNode;

        while (parent_fieldset.tagName.toLowerCase() != 'fieldset') {
            parent_fieldset = parent_fieldset.parentNode;
        }

        var icon = document.getElementsByClassName('icon', parent_fieldset);

        if (!gate_fold_yes.disabled && gate_fold_yes.checked) {

            parent_fieldset.details = document.getElementsByClassName('hidden-details', parent_fieldset);

            for (var i=0; i < parent_fieldset.details.length; i++) {
                parent_fieldset.details[i].style.display = '';
            }

            icon[0].innerHTML = '( - )';
        }
    }.bind(gate_fold_yes));


    // Integer Only KeyPress 
    //
    
    Event.observe(total_spreads, 'keyup', function (e) {
        keypress_int(e);
    });
    
    Event.observe(gate_fold_spreads, 'keyup', function (e) {
        keypress_int(e);
    });

    // Validate Gate Fold Interior Spreads
    // Int Values for Total & Gate Folded Interior Spreads
    //
    Event.observe(main_form, 'submit', function (e) {
        if (gate_fold_yes.checked) {
            var error = "";
        
            if (!validate_int(total_spreads.value)) {
                error += "\n - Total Spreads";
            }
            
            if (!validate_int(gate_fold_spreads.value)) {
                error += "\n - Gate Folded Interior Spreads";
            }
            
            if (error != "") {
                alert ('Values in the following fields must be whole numbers...' + error + '\nPlease correct this before proceeding.');
                Event.stop(e);
                return false;
            }
        }
        
        if (total_spreads.value && gate_fold_spreads.value &&  parseInt(total_spreads.value) > 0 && parseInt(total_spreads.value) < parseInt(gate_fold_spreads.value)) {
            alert('Gate Folded Interior Spreads must be less than Total Spreads.\nPlease correct this before proceeding.');
            Event.stop(e);
            return false;
        }
    });
});
