// Fields (names) needed for stock lookup.
var COVER_STOCK_ARGS = [
    'pid',
    'item',
    'template',
    'outdoor_printing',
	'press',
    'cover_stock_name',
    'cover_stock_finish',
    'cover_stock_colour',
    'cover_stock_weight',
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

        Event.observe(elem, action, cover_stock_lookup);
    };

    // Attach the stock lookup events to the fields we use.
    COVER_STOCK_ARGS.each(function (name) {
        var obj = form[name];

        if (!obj) return; // Fields may not exist.

        if (obj.nodeType == 1) { attach(obj) }
        else                   { $A(obj).each(attach) }
    });

    // Clear selection button.
    Event.observe($('cover_stock_unbind_all'), 'click', cover_stock_unbind_all);

    return true;
});



function cover_stock_lookup (is_load) {
    var form = $('f1');

    // Get the value of each of the named elements.
    var values = COVER_STOCK_ARGS.map(function (name) {
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
        '/jsrs', all_cover_stock_results, 'eprint::paper::substrate_lookup', values
    );
	} else {
    jsrsExecute(
        '/jsrs', cover_stock_results, 'eprint::paper::substrate_lookup', values
    );
	}

    return true;
}

// Takes a JSON serialised hash (object), each key representing a stock
// attribute name and the value a list of [label, value] pairs that are used
// to populate the stock attribute select boxes.
function cover_stock_results (str) {

    var json = eval('(' + str + ')');

    for (var name in json) {
        var select = $('cover_stock_' + name);

        clear_select(select);
        stock_populate_select(select, json[name]);
    }


    return true;
}

function all_cover_stock_results (str) {

    var json = eval('(' + str + ')');

    for (var name in json) {
        var select = $('cover_stock_' + name);

        clear_select(select);
        stock_populate_select(select, json[name]);
    }

    for (var name in json) {
        var select = $('back_stock_' + name);

        clear_select(select);
        stock_populate_select(select, json[name]);
    }


    return true;
}

// Unbinds all currect stock filters and re-populates the stock selection.
function cover_stock_unbind_all (e) {
    for (var i = 0; i < COVER_STOCK_ARGS.length; i++) {
        var elem = document.getElementById(COVER_STOCK_ARGS[i]);

        if ( elem && elem.tagName.toLowerCase() == 'select') {
			if (elem.id == 'press') continue;
            clear_select(elem);
        }
    }
    cover_stock_lookup();

    return true;
}

