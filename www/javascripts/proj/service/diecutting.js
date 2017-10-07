// Copyright (c) 2004 Print-Quotes Software Inc. All rights reserved.

service.validate = function (e) {
    var form    = this.form;
    var text    = '';
    var is_auto = !e || e.type == 'load'; // Interactive only on user events.

    // finished dimension has to be entered
    if ( ! ( 0 < parseFloat(form.final_height.value) ) || !( 0 < parseFloat(form.final_width.value)) ) {
		text += 'Please enter a valid finished dimension.\n';
    } // flat dimension has to be entered
	else if ( ! ( 0 < parseFloat(form.flat_width.value) ) || !( 0 < parseFloat(form.flat_height.value)) ) {
    	text += 'Please enter a valid flat dimensin.\n';
    } // check and enforce the selection of custom die supply
	else if ( form.rdbSuppliedDie && get_rdb_value(form, 'rdbSuppliedDie')!='Y' && get_rdb_value(form, 'rdbSuppliedDie')!='N' ) {
		text += 'Please select whether you will supply a custom die.\n';
    }
	else {
		// custom die not supplied, check validity of the following
		if ( form.rdbSuppliedDie && form.txtDieWidth && form.txtDieHeight && get_rdb_value(form, 'rdbSuppliedDie') == 'N') {
	 	   /* in the case of a custom die not being supplied, we check the amount of steel rule entered.
       	       it is not allowed to be less than the minimum requirement.
       	    */
    	    var width = parseFloat(form.txtDieWidth.value);
    	    var height = parseFloat(form.txtDieHeight.value);
    	    var validSteel = true;

    	    if ( get_rdb_value(form, 'rdbDieCutting') == 'Simple' && !( form.txtSteelRuleLengthSimple.value >= (width + height) * 2 ) ) {
				validSteel = false;
    	    }
			else if ( get_rdb_value(form, 'rdbDieCutting') == 'Average' && !( form.txtSteelRuleLengthAverage.value >= (width + height) * 2 * 1.5 ) ) {
				validSteel = false;
    	    }
			else if ( get_rdb_value(form, 'rdbDieCutting') == 'Complex' && !( form.txtSteelRuleLengthComplex.value >= (width + height) * 2 * 2 ) ) {
				validSteel = false;
    	    }

			if (form.rdbHardToolingYes &&  form.rdbHardToolingYes.checked==true ) {
				validSteel = true;
			}

			

            if ( !( width > 0 ) || !( height > 0 ) ) {
	    		text += 'Please enter a valid die-cut image dimension.\n';
				/* the entered amount of steel rule linear inches is less than the minimum possible,
				text += user and return false to the function submit_handler
				*/
    	    }
			else if ( validSteel == false ) {
				text += 'The amount of steel rule entered is less than the minimal requirement.\n';
    	    }
			else if ( (! ( 0 <= parseFloat(form.txtDieCutBends.value) ) ) && form.rdbHardToolingYes.checked==false ) {
					text += 'Please enter a valid quantity of die rule bends.\n';
			}
			else if ( ! ( 0 <= parseFloat(form.txtDieCutPunches.value) )) {
				text += 'Please enter a valid quantity of die cut punches.\n';
			}
		}

		// in either case supplied or not, check validity of the following
		// insist on hole clearing selection
		if ( form.rdbHoleClearing && get_rdb_value(form, 'rdbHoleClearing')!='Y' && get_rdb_value(form, 'rdbHoleClearing')!='N' ) {
			text += 'Please select whether you require hole clearing.\n';
		// insist on gluing selection
		} else if ( form.rdbGlued && get_rdb_value(form, 'rdbGlued')!='Y' && get_rdb_value(form, 'rdbGlued')!='N' ) {
		   text += 'Please select whether you require gluing.\n';
		} 
    } 

    if (text) {
        if (!is_auto) {
            alert('Your form is incomplete:\n\n' + text);
        }
        return false;
    }

    return true;
} 

function calc_die(e){
    var form = $('f1');
    // The die rule length defaults to the perimiter of the die times the
    // complexity factor.
    var complexity = {
        'Complex' : 2.0,
        'Average' : 1.5,
        'Simple'  : 1.0
    };
    for (var i=0, elems = form['rdbDieCutting']; i < elems.length; i++) { 
		var name = elems[i].value;
    	form[ 'txtSteelRuleLength' + name ].value = '';
    }

	var val = get_rdb_value(form,'rdbDieCutting');
    var rule = form[ 'txtSteelRuleLength' + val ];

    var width  = parseFloat(form.txtDieWidth.value);
    var height = parseFloat(form.txtDieHeight.value);

    if (!(width && height)) return;

    rule.value = (width + height) * 2 * complexity[val];

	if ( form.rdbHardToolingYes &&  form['rdbHardToolingYes'].checked==true ) rule.value = 0;

    return true;
}

// Calculate the die rule length when the complexity changes. NOTE: This is a
// stop-gap until we institute better relations between width x height and
// complexity (with only one die rule length input).
Event.observe(window, 'load', function () {
    var form = $('f1');

    if (!form.rdbDieCutting) return;


    if ( form.rdbHardTooling ) {
    	for (var i=0, elems = form['rdbHardTooling']; i < elems.length; i++) { 
        	Event.observe(elems[i], 'click', function (e) { calc_die(e); });
    	}
	}
	

    for (var i=0, elems = form['rdbDieCutting']; i < elems.length; i++) { 
        Event.observe(elems[i], 'click', function (e) { calc_die(e); });
    }

});


Event.observe(window, 'load', function () {
    var form = $('f1');

    if (!form.rdbSuppliedDie) return;

    // Set initial state on page load.
    if (get_rdb_value(form, 'rdbSuppliedDie') == 'Y' ) {
        die_data (form,1);
    }

    // Watch it's changes.
    for (var i=0, elems = form['rdbSuppliedDie']; i < elems.length; i++) { 
        Event.observe(elems[i], 'click', function (e) {
            die_data(form, ($F(Event.element(e)) == 'Y'))
        });
    }
});

// Disable/Enable all the fields that define a die, when a custom die will be
// supplied or not (respectively).
function die_data (form, bool) {

	if ( ! form.txtDieWidth || ! form.txtDieHeight ) {
		return;
	} // return if die fields are not present.

    form.txtDieWidth.disabled = bool;
    form.txtDieHeight.disabled = bool;
//    form.rdbDieCutting[0].disabled = bool;
//    form.rdbDieCutting[1].disabled = bool;
//    form.rdbDieCutting[2].disabled = bool;
    form.txtSteelRuleLengthSimple.disabled = bool;
    form.txtSteelRuleLengthAverage.disabled = bool;
    form.txtSteelRuleLengthComplex.disabled = bool;
    form.txtDieCutBends.disabled = bool;
    form.txtDieCutPunches.disabled = bool;

    return true;
} 
  
