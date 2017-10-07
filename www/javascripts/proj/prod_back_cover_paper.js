// Fields (names) needed for stock lookup.
var BACK_STOCK_ARGS = [
    'pid',
    'item',
    'template',
    'outdoor_printing',
	'press',
    'back_stock_name',
    'back_stock_finish',
    'back_stock_colour',
    'back_stock_weight',
    'cover_stock_type',
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

        Event.observe(elem, action, back_stock_lookup);
    };

    // Attach the stock lookup events to the fields we use.
    BACK_STOCK_ARGS.each(function (name) {
        var obj = form[name];

        if (!obj) return; // Fields may not exist.

        if (obj.nodeType == 1) { attach(obj) }
        else                   { $A(obj).each(attach) }
    });

    // Clear selection button.
    Event.observe($('back_stock_unbind_all'), 'click', back_stock_unbind_all);

//	back_stock_unbind_all();
    return true;
});



function back_stock_lookup (e) {
    var form = $('f1');

    // Get the value of each of the named elements.
    var values = BACK_STOCK_ARGS.map(function (name) {
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
    jsrsExecute(
        '/jsrs', back_stock_results, 'eprint::paper::substrate_lookup', values
    );

    return true;
}

// Takes a JSON serialised hash (object), each key representing a stock
// attribute name and the value a list of [label, value] pairs that are used
// to populate the stock attribute select boxes.
function back_stock_results (str) {

    var json = eval('(' + str + ')');

    for (var name in json) {
        var select = $('back_stock_' + name);

        clear_select(select);
        stock_populate_select(select, json[name]);
    }


    // If the page wants to display stock details, check if all stock
    // selections have a value fetching the details if they do.
    var details = $('stock_details');
    var underbase = $('underbase_discharge');
    if (details || underbase) {
        // Get the name, finish, colour, and weight.
        var form  = $('f1');
        var attrs = $A(['name', 'finish', 'colour', 'weight']).map(
            function (name) { return $F(form['stock_' + name]) }
        );

        // If all are filled out find the details for that stock.
        if (attrs.all(function (x) { return x })) {
            jsrsExecute(
                '/jsrs', 
                function (str, x) { 
                    var resp = eval('(' + str + ')');
		    if ( resp.underbase == 1 ) {
			underbase.checked = true;
			mySelect3($('underbase_discharge'));
		    } else {
			$('underbase_none').checked = true;
			mySelect3($('underbase_discharge'));
		    }

                    details.display(!!resp.details);

                    if (resp.details)
                        details.lastChild.innerHTML = resp.details;
                },
                'eprint::paper::substrate_details', 
                attrs
            );
        }
        else { 
            details.display(false);
            details.lastChild.innerHTML = ''; 
        }
    }

    return true;
}

// Unbinds all currect stock filters and re-populates the stock selection.
function back_stock_unbind_all (e) {
    for (var i = 0; i < BACK_STOCK_ARGS.length; i++) {
        var elem = document.getElementById(BACK_STOCK_ARGS[i]);

        if ( elem && elem.tagName.toLowerCase() == 'select') {
			if (elem.id == 'press') continue;
            clear_select(elem);
        }
    }
    back_stock_lookup();

    return true;
}

