//Copyright (c) 2004 Print-Quotes Software Inc. All rights reserved.

var service = new Service('printing', validate, display);

function validate (e) {
    var form    = this.form;
    var text    = '';
    var is_auto = !e || e.type == 'load'; // Interactive only on user events.

    if ( form.flat_width && ! ( 0 < parseFloat(form.flat_width.value) ) ) {
        text += 'Please enter the width of your Project\n';
    }

    if ( form.flat_height && ! ( 0 < parseFloat(form.flat_height.value) ) ) {
        text += 'Please enter the height of your Project\n';
    } 

    if ( form.flat_width && form.flat_height && form.final_width && form.final_height ) {
       if ( form.flat_width.value * form.flat_height.value < form.final_width.value * form.final_height.value ) {
               text += 'Your finished dimensions may not exceed your flat dimensions.\n';
         }
    }

    // Check that at least one side has some ink selected.
    if (! has_ink(form) )
        text += 'At least one color must be selected\n';

    // If stock exists at all (screen items don't use it), check that all
    // attributes are selected.
    if ($('stock')) {
        var names = ['name', 'finish', 'color', 'weight'];
        var id    = ['name', 'finish', 'colour', 'weight'];

        for (var i=0; i < names.length; i++) {
            var field = form.elements['stock_' + id[i]];

            if (! (field && $F(field)) )
                text += 'Please select a stock ' + names[i] + '\n';
        }
    }

    // If multi-version, make sure everything is allocated.
    if (form.is_mv && form.is_mv.checked) {
       if (version_quantity_remaining() != 0)
           text += 'Some projects are not assigned to a version\n';
    }

    if (text) {
        if (!is_auto) {
            alert('Your form is incomplete!\n\n' + text);
        }
        return false;
    }

    return true;
}

// If any black, process, or spot colours are selected we're okay. TODO Expand
// this into a proper check instead of this quick and dirty one.
function has_ink (form) {
    for (var i=0; i <= 1; i++) {
        var side = 's' + i + '_';
        
        if (    form[side + 'black'] && form[side + 'black'].checked 
		     || form[side + 'process'] && form[side + 'process'].checked)
            return true;

        for (var j=1; j <=8; j++) {
            var name     = form[side + 'pms_' + j + '_name'];
            var coverage = form[side + 'pms_' + j + '_coverage'];

            if (name && name.value && coverage && coverage.value) return true;
        }
    }

    return false;
}


function display (data) {
    var form  = this.form;

    if (data.LargeFormatTiled == 1) {
        if (   form.rdbBindMethod 
            && get_rdb_value(form, 'rdbBindMethod') != 'Weld'
            && get_rdb_value(form, 'rdbBindMethod') != 'Stitch') 
        {
            stitchorweld = 'unspecified';
            check_for_merge();
            alert("Your project size is larger than the "
                 + "substrate.\nYou will probably want to select a "
                 + "method to join your tiled substrates.");
        }
    }

    // Populate the sheet size drop down with that potential sizes for the
    // currently selected press/substrate combination.
    if (data.sheet_sizes && form.substrate) {
        var options = form.substrate.options; 
        var sizes   = data.sheet_sizes.split('_');

        // Clear all options other than the "Please select" one.
        while (options.length > 1) options[1] = null;

        // Add the sizes to the option list.
        for (var s = 0; s < sizes.length; s++) {
            var data = sizes[s].split(','); // Value (ID), Label, Selected
            options[s+1] = new Option(data[1], data[0]);
            options[s+1].selected = !!data[2];
        }
    }
    
    return true;
} 


function clear_price_data( form ) {
    var pricing_fields = [ 'txtPrice',      'txtUnitPrice', 
                           'txtStockPrice', 'txtStockUnitPrice',
                           'total_price',   'total_unit', ];

    for (var i = 0; i < pricing_fields.length; i++) {
        for (var j = 1; j <= 3; j++) {
            var elem = form.elements[ pricing[i] + [j] ];
            if (elem) elem.value = '0.00';
        }
    }

    return true;
} 

// MULTI-VERSION
//

Event.observe(window, 'load', function () {
    var is_mv = $('is_mv');

    var elem = $('s0_metal_effects');
    if ( elem )
        Event.observe(elem, 'click', check_metal.bindAsEventListener(elem));

    elem = $('s1_metal_effects');
    if ( elem )
        Event.observe(elem, 'click', check_metal.bindAsEventListener(elem));

    if (!is_mv) return;

    Event.observe(is_mv, 'click', need_multiversion.bindAsEventListener(is_mv));

    // Set the initial page state.
    need_multiversion.apply($('is_mv'));

    // TODO Bind these in faster way (JS speed). Perhaps only have a handler
    // on the fieldset?
    colours_coatings().each(function (elem) {
        if (elem.name.match(/^s[01]_process$/)) {
            Event.observe(elem, 'click', mv_process.bindAsEventListener(elem));
        }
        else if (elem.name.match(/^s[01]_black$/)) {
            Event.observe(elem, 'click', mv_black.bindAsEventListener(elem));
        }
        else if (elem.name.match(/^s[01]_pms_\d_name$/)) {
            Event.observe(elem, 'focus', mv_pms.bindAsEventListener(elem));
            Event.observe(elem, 'blur',  mv_pms.bindAsEventListener(elem));
        }
        else if (elem.name.match(/^s[01]_varnish_spot\b/)) {
            Event.observe(elem, 'click', mv_varnish.bindAsEventListener(elem));
        }
    });
});

// Retrieves a list of input elements in the colours and coating fieldsets.
function colours_coatings () {
    var sides = [ $('side1'), $('side2') ];

    var inputs = sides.map(function (side) {
        return $A( side.getElementsByTagName('input') );
    });

    return inputs.flatten();
}

// While this should be a generic function for dependencies, for now it will
// have to be specific to this case.
function need_multiversion (e) {
    if (! $('multiversion')) return;
    
    var display = (this.checked) ? '' : 'none';

    // Show / Hide the version information.
    $('multiversion').parentNode.style.display = display;
    
    // Show / Hide "Changes with Each Version" Label
    $('s0_mv_changes').style.display = display;
    $('s1_mv_changes').style.display = display;


    // TODO Process these in faster (JS speed) way.
    colours_coatings().each(function (elem) {
        if (elem.name.match(/^s[01]_process\b/)) {
            mv_process.apply(elem, [e]);
        }
        else if (elem.name.match(/^s[01]_black\b/)) {
            mv_black.apply(elem, [e]);
        }
        else if (elem.name.match(/^s[01]_pms_\d_name/)) {
            mv_pms.apply(elem, [e]);
        }
        else if (elem.name.match(/^s[01]_varnish_spot\b/)) {
            mv_varnish.apply(elem, [e]);
        }
    });

    return true;
}


// Show/hide black plate change as needed (for multi-version).
function mv_black (e) {
    var black = $(this.name  + '_mv');

    var need_mv = this.checked && $('is_mv') && $('is_mv').checked;

    black.style.visibility = need_mv ? 'visible'  : 'hidden';
    if (e) black.checked = need_mv;
}

// Fill out First PMS colour with our metal effects.
function check_metal (e) {
    var s = this.name.substring(0,2);
    var on = this.checked;
    var n = this.form[s + '_pms_1_name'];
    var c = this.form[s + '_pms_1_coverage'];
    n.value = on ? 'METAL' : '';
    c.value = on ? '13' : '';

}

// Show/hide black and CMY plate changes as needed (for multi-version).
function mv_process (e) {
    var form = this.form;

    var is_mv = form.is_mv.checked;
    var show  = is_mv && (form.s0_process.checked || form.s1_process.checked);

    // If either side is checked display the placeholder for both.
    for (var i = 0; i <= 1; i++) {
        var side = $('s' + i + '_process_plates');
        if (side) side.style.display = show ? '' : 'none';
    }

    var plates = [ $(this.name  + '_mv'),         // CMY
                   $(this.name  + '_black_mv') ]; // K

    // Show/hide mv plate change inputs based on this sides state.
    plates.each(function (plate) {
        if (!plate) return;

        var elem = plate.parentNode.tagName.toLowerCase() == 'label'
                 ? plate.parentNode    // Offset, Screen, etc.
                 : plate;              // Digital

        elem.style.visibility = is_mv && this.checked ? 'visible'  : 'hidden';

        if (e) plate.checked = is_mv && this.checked; 
    }.bind(this));
}

// Show/hide PMS plate changes as needed (for multi-version).
function mv_pms (e) {

    var name  = this.name;
    var plate = this.form[name.replace(/_name/, '_mv')];

    var use_plate = this.form.is_mv.checked && (   (e && e.type == 'focus')
                                                || this.value.strip() );

    plate.style.visibility = use_plate ? 'visible' : 'hidden';
    if (e && !this.value.strip()) plate.checked = use_plate;
}

// Show/hide spot varnish plate changes as needed (for multi-version).
function mv_varnish (e) {
    var plates = document.getElementsByName(this.name + '_mv');

    var use_plate = this.form.is_mv.checked && this.checked;
    
    for (var i = 0; i < plates.length; i++) {
        var plate = plates[i];
        if (this.value != plate.value) continue;

        plate.style.visibility = use_plate ? 'visible' : 'hidden';
        
        // Varnish plates aren't on by default (but they still get unset).
        if (e && !use_plate) plate.checked = false;
    }
}


// Change the other two quantities and the percentange whenever the first
// quantity changes.
function update_version_quantity (elem) {
    
    var row = elem.parentNode.parentNode;
    if (isNaN(elem.value)) return;
    
    const qty1_elem = document.getElementById('txtQuantity1');

    var qty1;
    if (qty1_elem) {
	    qty1 = qty1_elem.innerHTML ? qty1_elem.innerHTML : qty1_elem.value;
    }

    // Figure out the percentage that current quantity if of it's total.
    var percentage
        = (elem.value / qty1) * 100;
    
    // Update the text that displays the percent...
    row.cells[4].innerHTML = do_decimals(percentage);
    
    // ..and update the quantities for Q2 and Q3 if they're there.
    for (var i=2; i <= 3; i++) {
		var q = document.getElementById('txtQuantity'+i);
		if ( q ) {
			var qty = q.innerHTML;
            row.cells[i].innerHTML = parseInt(qty * percentage/100);
		}
    }

    // Recalulate the quantity of Q1 we have yet to allocate
    version_quantity_remaining();
}

function version_quantity_remaining () {
    var form = document.getElementsByName("f1")[0];
    
    var result     = document.getElementById('version_quantity_remaining');
    const qty1_elem = document.getElementById('txtQuantity1');

    var total;
    if (qty1_elem) {
	    total = qty1_elem.innerHTML ? qty1_elem.innerHTML : qty1_elem.value;
    }

    var names      = form.mv_name;
    var quantities = form.mv_qty;
    var sum = 0;
    for (var i=0; i < quantities.length; i++) {
        var value = parseInt(quantities[i].value);
        if (isNaN(value) || !names[i]) continue;
        sum += value;
    }

    var remaining = total - sum;
    // Highlight the remaining if there are any left.
    if (remaining)
        result.className = 'error';
    else
        result.className = '';
    
    // Display the remaining
    result.innerHTML = remaining;
    return remaining;
}


// SIDE ONE/TWO LINKING
//

// Register side linking and set initial page state.
Event.observe(window, 'load', function () {
    var link = $('side_link');
    var side = $('side2');

    if (! (side && link) ) return;
    
    // Set the initial status on page load.
    if (link.checked) link_sides.apply(link);

    Event.observe(link, 'click', link_sides.bind(link));

    return true;
});

// Gray out/disable side two when it's "linked" to side one. The server
// handles replicating the fields across when they are linked.
function link_sides (e) {
    var linked = this.checked;
    var side   = $('side2');
    var colour = linked ? '#999999' : '';

    // When disabled we grey out the side.
    side.style.backgroundColor = linked ? '#EEEEEE' : '';
    side.style.color           = colour;
    side.style.borderColor     = colour;

    // Display a message to the user if we're disabled.
    $('side2_linked').style.display = linked ? 'block' : 'none';

    side.descendants().each(function (elem) {
        // If we're disabling grey out or disable elems, otherwise undo.
        switch (elem.tagName.toLowerCase()) {
            case 'fieldset':
                elem.style.borderColor = colour;
                break;

            case 'legend':
                elem.style.color = colour;
                break;

            case 'input':
            case 'select':
            case 'textarea':
            case 'button':
                if (linked) {
                    elem.was_disabled = elem.disabled;
                    elem.disabled = true;
                }
                else {
                    elem.disabled = elem.was_disabled;
                }
                break;
        }
    });

}

// BLACK/PROCESS COLOUR MUTEX
//

// Bind the black/process mutex function to the form elements.
Event.observe(window, 'load', function () {
    var colours = $A( $('f1').elements ).findAll(function (elem) {
        if (!elem.name) return;
        if (elem.name.match(/^s[01]_(black|process)$/)) return elem;
    });

    colours.each(function (elem) {
        Event.observe(
            elem, 'click', mutex_process_black.bindAsEventListener(elem)
        );
    });
});

// Black and process are mutually exclusive (as CYMK includes black).
function mutex_process_black (e) {
    var other = this.form[
        this.name.match(/process/) 
            ? this.name.replace(/process/, 'black')
            : this.name.replace(/black/, 'process')
    ];

    if (this.checked && other.checked) other.click();
}


// PMS Defaults
//

Event.observe(window, 'load', function () {
	var pms_fieldsets = document.getElementsByClassName('pms');
	var pms_colour;
	var colour, fieldset;

	if (pms_fieldsets.length > 0) {
		for (var i=0; i < pms_fieldsets.length; i++) {
			fieldset = pms_fieldsets[i];

			pms_colour = document.getElementsByClassName('pms-colour', fieldset);

			for (var j=0; j < pms_colour.length; j++) {
				colour = pms_colour[j];

				Event.observe(colour, 'keyup', function (e) {
					var charCode = (e.which) ? e.which : e.keyCode;
					if (charCode == 8 || charCode == 46) { return; }

					var id = this.name.indexOf("_name") == 8 ? this.name.charAt(7) : '1' + this.name.charAt(8);

					var partener_percent = this.form['s' + this.name.charAt(1) + '_pms_' + id + '_coverage'];

					if (this.value && !partener_percent.value) {
						partener_percent.value = '13';
					}
				}.bind(colour));				 
			}
		}
	}
	else {
		return;
	}
});


// AQUEOUS/ULTRAVIOLET COATINGS
//

// When no coating is selected the auxillary controls should be disabled.
// This creates the event handlers to do that.
Event.observe(window, 'load', function () {
    for (var i = 0; i <= 2; i++) {
        var coatings = document.getElementsByName('s' + i + '_coating_type');

        for (var j = 0; j < coatings.length; j++) {
            var elem = coatings[j];
            var fn   = coating(i);
            
            Event.observe(elem, 'click', fn.bind(elem));
            if (elem.checked) fn.apply(elem);
        }
    }
});

// Given the side (0,1) create an event handler to disable auxillary coating
// controls when no coating has been selected.
function coating (side) {
    var dependents 
        = $A(document.getElementsByName('s' + side +'_coating_texture')).concat(
          $A(document.getElementsByName('s' + side + '_coating_spot')) 
    );

    return function (e) {
        var disable = !this.value;
        dependents.each(function (elem) { elem.disabled = disable });
    };
}

Event.observe(window, 'load', function () {
	for (var i=0; i < 2; i++) {
		var overall_coatings = document.getElementsByName('s' + i + '_varnish_flood');
		var spot_coatings = document.getElementsByName('s' + i + '_varnish_spot');
		
		for (var j=0; j < overall_coatings.length; j++) {
			if (!overall_coatings[j].value) continue;

			var overall = overall_coatings[j];
			
			Event.observe(overall, 'click', mutex_coatings.bind(overall));
		}
		
		for (var j=0; j <spot_coatings.length; j++) {
			var spot = spot_coatings[j];
			Event.observe(spot, 'click', mutex_coatings.bind(spot));
		}
	}
});

function mutex_coatings () {
	var mutex;
	var side = this.name.charAt(1);
	
	if (this.name == 's' + side + '_varnish_flood') {
		mutex = document.getElementsByName('s' + side + '_varnish_spot')
	}
	else if (this.name == 's' + side + '_varnish_spot') {
		mutex = document.getElementsByName('s' + side + '_varnish_flood')
	}
	
	for (var i=0; i < mutex.length; i++) {
		if (this.value == mutex[i].value && mutex[i].checked) {
			mutex[i].checked = false;
			
			if (this.name.search(/spot/) != -1) {
				$('s' + side + '_varnish_flood_none').checked = true;
			}
		}
		else if (this.checked && mutex[i].checked && this.value && mutex[i].value) {
			$('s' + side + '_drytrap').checked = true;
		}
	}
}


// IMAGE CONTROLS
//

Event.observe(window, 'load', function () {
    if ( $('bleed_size') )  {
        check_bleeds.apply($('bleed_size'));
    }
});

// Disable the ability to choose bleed sides if there are no bleeds, handles
// bleed / ingore margins mutex, etc.
function check_bleeds (e) {
    var form  = this.form;
    var sides = $A(form.bleed_sides);

    if (! parseFloat( $F(this) ) ) {
        sides.map(function (elem) { elem.disabled = true; });
    }
    else {
        // Are any sides selected?
        var is_checked = sides.detect(function (elem) {return elem.checked});

        // Enable all sides and select them all if no sides were checked.
        sides.map(function  (elem) {
            elem.disabled = false;
            if (!is_checked) { elem.checked = true; }
        });

        // Ignoring margins and bleeds are mutually exclusive.
        if (form.ignore_margins) { form.ignore_margins.checked = false; }
    }
    return true;
}


function colour_bar_mutex_ignore_margins(form) {
    if (form.colour_bar.checked)
        form.ignore_margins.checked = false;

    return true;
}


// Ignoring margins is mutually exclusive with colour bars and bleeds. Turn
// them off if we're choosing to ignore press sheet margins,
function ignore_margins_mutex(form) {
    if (form.ignore_margins.checked) {
        if (form.bleed_size) {
            form.bleed_size.selectedIndex = 0;
            form.bleed_size.onchange();
        }

        if (form.colour_bar) {
            form.colour_bar.checked = false;
        }
    }

    return true;
}


// CUSTOM STOCK SELECTION
//

Event.observe(window, 'load', function () {
	var stock_supplied = $('stock_supplied');

	if (!stock_supplied) return;

    var description = $('stock_custom');
    var container   = description.parentNode;
	
	container.style.display = stock_supplied.checked ? '' : 'none';
	description.disabled    = !stock_supplied.checked;

	Event.observe(stock_supplied, 'click', function () {
		container.style.display = stock_supplied.checked ? '' : 'none';
		description.disabled    = !stock_supplied.checked;
	});
});


// PRODUCTION OVERRIDES
//

function overrides (e) {
    var override = $('override_' + this.name);
    override.checked  = this.options[this.selectedIndex].value;
    override.disabled = !override.checked;

    return true;
}

function overrides_chkbox (e) {
    var override = $(this.name.replace('override_', ''));
    if (!override.options[override.selectedIndex].value) {
        this.disabled = true;
        this.checked = false;
    }
}

