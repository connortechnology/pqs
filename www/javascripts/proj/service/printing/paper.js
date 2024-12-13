// Fields (names) needed for stock lookup.
var STOCK_ARGS = [
    'pid',
    'sid',
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

    if (! (form && $('stock')) ) return;

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

	// Get new paper list on press override.
	Event.observe($('override_press'),   'click', stock_lookup);

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
    this.options[1] = new Option('Clear', '');

    return true;
}

function stock_lookup (e) {
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
    jsrsExecute(
        '/jsrs', stock_results, 'eprint::paper::substrate_lookup', values
    );

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


// Given a select object and an array of [label, value] pairs append each
// tuple as an options to the select box.
function stock_populate_select (select, options) {
    if (!select || select.tagName.toLowerCase() != 'select') return false;

    select[select.length] = new Option('Please select one' , '');

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

function paper_price_calc( element, group ) {
  var form = element.form;
  if ( ! form )
    alert( 'no form' );
  if ( element.name.match( /^StockPricePerM/ ) ) {
    console.log("From per m");
    const costperm = parseFloat( element.value.replace(/[^\d\-\.]/g, '' ) );
    if ( get_value( form.elements['StockType'+group] ) == 'Roll' ) {
      const wpsi = form.elements['basis_mweight'+group].value / (form.elements['basis_width'+group]*form.elements['basis_height'+group]);
      const area = form.elements['txtSpecificStockWidth'+group].value * form.elements['txtSpecificStockHeight'+group].value;
      form.elements['CustomStockPrice'+group].value = do_decimals( costperm / (wpsi * area * 1000), 2);
    } else {
      if ( form.elements['txtCustomMWeight'+group].value ) {
        form.elements['CustomStockPrice'+group].value = do_decimals( costperm / (form.elements['txtCustomMWeight'+group].value / 100), 2 );
      } // end if
    } // end if
  } else {
    const costcwt = parseFloat( element.value.replace(/[^\d\-\.]/g, '' ) );
    console.log('from /cwt', costcwt);

    if ( get_value( form.elements['StockType'+group] ) == 'Roll' ) {
      console.log("Is roll");
      return;
    } else {
      if ( ! form.elements['txtCustomMWeight'+group].value ) {
        $('PaperAlert'+group).innerHTML = 'Please enter MWeight';
        return;
      } // end if

      form.elements['StockPricePerM'+group].value = do_decimals( costcwt * form.elements['txtCustomMWeight'+group].value / 100, 2 );
      console.log("New value", ( costcwt * form.elements['txtCustomMWeight'+group].value / 100));
    } // end if
  } // end if
} // end function

function calc_basis_weight_from_weight(weight_element) {
  let re = /([\d\.]+)(lb|#)/i;
  let matches = re.exec(weight_element.value);
  if (matches) {
    const weight = matches[1];
    re = /^txtSpecificStockWeight(\d*)$/;
    matches = re.exec(weight_element.name);
    const signature = matches[1];
    console.log(signature, weight);
    const form = weight_element.form;
    form.elements['basis_mweight'+signature].value = weight * 2;
    mweight_to_gsm(form, signature);
  } else {
    console.log("No match against "+weight_element.value);
  }
}

function mweight_to_gsm( form, signature ) {
    const width = parseFloat(1*form.elements['txtSpecificStockWidth'+signature].value);
    const height = parseFloat(1*form.elements['txtSpecificStockHeight'+signature].value);
    const basis_width = parseFloat(1*form.elements['basis_width'+signature].value);
    const basis_height = parseFloat(1*form.elements['basis_height'+signature].value);
  var mweight;
  var basis_weight;
  if (form.elements['txtCustomMWeight'+signature].value) {
    mweight = parseFloat(1*form.elements['txtCustomMWeight'+signature].value);
    basis_weight = (basis_width*basis_height) * mweight / (width*height);
    form.elements['basis_mweight'+signature].value = basis_weight;
  } // end if
  // mweight is the weight of 1000 sheets, so calc the wpsi and multiply by 703064.5 to get gsm
  //console.log( "wpsi: " + (mweight/1000)/(width*height) );
  var gsm = Math.round((mweight/1000)/(width*height)*70306450)/100;
  form.elements['txtStockGSM'+signature].value = gsm;
}

function basis_weight_to_gsm( form, signature ) {
    const width = parseFloat(1*form.elements['txtSpecificStockWidth'+signature].value);
    const height = parseFloat(1*form.elements['txtSpecificStockHeight'+signature].value);
    const basis_width = parseFloat(1*form.elements['basis_width'+signature].value);
    const basis_height = parseFloat(1*form.elements['basis_height'+signature].value);
  var mweight;
  var basis_weight;
  if (form.elements['basis_mweight'+signature].value) {
    basis_weight = parseFloat(1*form.elements['basis_mweight'+signature].value);
    mweight = (width*height) * basis_weight / (basis_width*basis_height);
    form.elements['txtCustomMWeight'+signature].value = mweight;
  } // end if
  // mweight is the weight of 1000 sheets, so calc the wpsi and multiply by 703064.5 to get gsm
  //console.log( "wpsi: " + (mweight/1000)/(width*height) );
  var gsm = Math.round((mweight/1000)/(width*height)*70306450)/100;
  form.elements['txtStockGSM'+signature].value = gsm;
}

function gsm_to_mweight( form, signature ) {
  var gsm = parseFloat(1*form.elements['txtStockGSM'+signature].value);
  var width;
  var height;
  var mweight;

  width = parseFloat(1*form.elements['basis_width'+signature].value);
  height = parseFloat(1*form.elements['basis_height'+signature].value);
  mweight = Math.round((gsm/703064.5)*(width*height)*100000)/100;
  form.elements['basis_mweight'+signature].value = mweight;

  width = parseFloat(1*form.elements['txtSpecificStockWidth'+signature].value);
  height = parseFloat(1*form.elements['txtSpecificStockHeight'+signature].value);
  mweight = Math.round((gsm/703064.5)*(width*height)*100000)/100;
  form.elements['txtCustomMWeight'+signature].value = mweight;
}


function type_onchange(radio) {
  const re = /^StockType(\d*)$/;
  const matches = radio.name.match(re);
  console.log(radio, matches);
  const signature = matches[1];

  if ( radio.value == 'Sheet' ) {
    $j('#SpecificStockHeight'+signature).show();
    $j('#BasisSize'+signature).show();
    $j('#MWeight'+signature).show();
    $j('#PricePerM'+signature).show();
    gsm_to_mweight(radio.form, signature);
    $j('#minimum_order_units'+signature).innerHTML='sheets';
    $j('#sheets_per_package'+signature).innerHTML='sheets';
  } else if ( radio.value == 'Roll' ) {
    radio.form.elements['txtSpecificStockHeight'+signature].value='';
    $j('#SpecificStockHeight'+signature).hide();
    $j('#BasisSize'+signature).show();
    $j('MWeight'+signature).hide();
    $j('#PricePerM'+signature).hide();
    gsm_to_mweight(radio.form, signature);
    paper_price_calc(radio, signature);
    $j('#minimum_order_units'+signature).innerHTML='lbs';
    $j('#sheets_per_package'+signature).innerHTML='lbs';
  }
}

function specific_stock_onchange(radio) {
  const re = /^rdbSpecificStock(\d*)$/;
  const matches = radio.name.match(re);
  const signature = matches[1];
  if(radio.value=='Y'){
    $j('#HouseStock'+signature).hide();
    $j('#SpecificStock'+signature).show();
    if(radio.form.ddmStockSheetSize1){
      clear_ddm(radio.form.ddmStockSheetSize1);
    };
    if(radio.form.ddmStockSheetSize2){
      clear_ddm(radio.form.ddmStockSheetSize2);
    };
    if(radio.form.ddmStockSheetSize3){
      clear_ddm(radio.form.ddmStockSheetSize3);
    };
  } else {
    $j('#HouseStock'+signature).show();
    $j('#SpecificStock'+signature).hide();
    Stock_onchange(radio, signature);
  }
}
