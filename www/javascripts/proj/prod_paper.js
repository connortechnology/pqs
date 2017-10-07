// Fields (names) needed for stock lookup.
var STOCK_ARGS = [
    'pid',
    'item',
    'template',
    'outdoor_printing',
	'press',
    'stock_name',
    'stock_finish',
    'stock_colour',
    'stock_weight',
];

// Bind the stock lookup and selection events to the needed elements.
Event.observe(window, 'load', function (e) {
    var form = $('f1');

    if (! (form) ) return;

    // All needed fields get the lookup events when they change. Select boxes
    // also get the 'bind' option filter controls.
    var attach = function (elem) {
        if (elem.tagName.toLowerCase() == 'select' && elem.id != 'press') {
            Event.observe(elem, 'change', stock_bind_option);
        }

        // Radio buttons in Safari don't support the 'change' event.
        var action = elem.type == 'radio' || elem.type == 'checkbox' 
            ? 'click' : 'change';

        Event.observe(elem, action, stock_lookup);
    };

    // Attach the stock lookup events to the fields we use.
    STOCK_ARGS.each(function (name) {
        var obj = form[name];

        if (!obj) return; // Fields may not exist.

        if (obj.nodeType == 1) { attach(obj) }
        else                   { $A(obj).each(attach) }
    });

    // Clear selection button.
    Event.observe($('stock_unbind_all'), 'click', stock_unbind_all);

	stock_lookup('page_load');


    return true;
});


function stock_bind_option (e) {
    // The index of the currently selected option.
    var selected = this.selectedIndex;

    // Remove all options except the selected one (in reverse order so
    // indexing doesn't shift).
    for (var i = this.options.length; i >= 0; i--) {
        if (i != selected) this.options[i] = null;
    }

    // Add an empty value so the user can unbind the selection.
   // this.options[1] = new Option('Reset', '');

    return true;
}

function stock_lookup (is_load) {
    var form = $('f1');

    // Get the value of each of the named elements.
    var values = STOCK_ARGS.map(function (name) {
        var obj = form[name];
        
        if (!obj) return '';

		// Only send press id if override is checked.
		if (name == 'press' && ! form['override_press'].checked) return '';

        // If the form object is a NodeList (radio button group) we'll get the
        // first selected elem.
        if (obj.nodeType != 1) {
            obj = $A(obj).detect(function (x) { return $F(x) });
            if (!obj) return;
        }

        return $F(obj); // Form field value
    });

    // TODO disable the fields in question and prevent calculations until the
    // call returns or a timeout occurs.

    // TODO Replace JSRS call with an Ajax request once the server side
    // handler is in place.

    // Make an async call to find all valid options for undefined substrate
    // attributes (will be populated by the callback).
	if ( is_load == 'page_load' ) {
		jsrsExecute(
			'/jsrs', all_stock_results, 'eprint::paper::substrate_lookup', values
		);
	} else { 
		jsrsExecute(
			'/jsrs', stock_results, 'eprint::paper::substrate_lookup', values
		);
	}

    return true;
}

// Takes a JSON serialised hash (object), each key representing a stock
// attribute name and the value a list of [label, value] pairs that are used
// to populate the stock attribute select boxes.
function stock_results (str) {
    // if (str == '{}') { stock_unbind_all(); return false; } // Invalid paper

    var json = eval('(' + str + ')');

    for (var name in json) {
        var select = $('stock_' + name);

        clear_select(select);
        stock_populate_select(select, json[name]);
    }
	mc();
    return true;
}
function all_stock_results (str) {
    // if (str == '{}') { stock_unbind_all(); return false; } // Invalid paper
    var json = eval('(' + str + ')');

    for (var name in json) {
        var select = $('stock_' + name);
        clear_select(select);
        stock_populate_select(select, json[name]);

    }

	cover_stock_lookup('page_load');

    return true;
}


// Given a select object and an array of [label, value] pairs append each
// tuple as an options to the select box.
function stock_populate_select (select, options) {
    if (!select || select.tagName.toLowerCase() != 'select') return false;

    select[select.length] = new Option('Please Select' , '');

    for (var i = 0; i < options.length; i++) {
        select[select.length] = new Option(options[i], options[i]);
    }

    // If there's only a single valid option available, we'll bind to it.
    if (select.options.length == 2) {
        select.selectedIndex = 1;
        stock_bind_option.apply(select);
    }

    return true;
}


// Clear given select options.
function clear_select (select) {
    if (!select || select.tagName.toLowerCase() != 'select') return false;

    while (select.length > 0) { select.options[0] = null; }

    return true;
}

// Unbinds all currect stock filters and re-populates the stock selection.
function stock_unbind_all (e) {
    for (var i = 0; i < STOCK_ARGS.length; i++) {
        var elem = document.getElementById(STOCK_ARGS[i]);

        if ( elem && elem.tagName.toLowerCase() == 'select') {
			if (elem.id == 'press') continue;
            clear_select(elem);
        }
    }
    stock_lookup();

    return true;
}

