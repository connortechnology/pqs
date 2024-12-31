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


  var form  = $('f1');
  // If the page wants to display stock details, check if all stock
  // selections have a value fetching the details if they do.
  var details = $('stock_details');
  var underbase = $('underbase_discharge');
  if (details || underbase) {
    // Get the name, finish, colour, and weight.
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
    } else { 
      details.display(false);
      details.lastChild.innerHTML = ''; 
    }
  }
  calc();
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
  if (!form)
    alert( 'no form' );
  $('PaperAlert'+group).innerHTML = '';

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
    element = form.elements['CustomStockPrice'+group];
    const costcwt = parseFloat( element.value.replace(/[^\d\-\.]/g, '' ) );

    console.log('from /cwt', costcwt);
    if (!costcwt) return;

    if ( get_value( form.elements['StockType'+group] ) == 'Roll' ) {
      console.log("Is roll");
      return;
    }
    if ( ! form.elements['txtCustomMWeight'+group].value ) {
      $('PaperAlert'+group).innerHTML = 'Please enter MWeight';
      return;
    } // end if

    form.elements['StockPricePerM'+group].value = do_decimals( costcwt * form.elements['txtCustomMWeight'+group].value / 100, 2 );
    console.log("New value", ( costcwt * form.elements['txtCustomMWeight'+group].value / 100));
  } // end if
  calc();
} // end function

function mweight_to_gsm( form, signature ) {
  const width = parseFloat(1*form.elements['txtSpecificStockWidth'+signature].value);
  const height = parseFloat(1*form.elements['txtSpecificStockHeight'+signature].value);
  const basis_width = parseFloat(1*form.elements['basis_width'+signature].value);
  const basis_height = parseFloat(1*form.elements['basis_height'+signature].value);
  var mweight;
  var basis_weight;
  mweight = parseFloat(1*form.elements['txtCustomMWeight'+signature].value);
  if (mweight && width && height) {
    basis_weight = (basis_width*basis_height) * mweight / (width*height);
    form.elements['basis_mweight'+signature].value = basis_weight;
    // mweight is the weight of 1000 sheets, so calc the wpsi and multiply by 703064.5 to get gsm
    //console.log( "wpsi: " + (mweight/1000)/(width*height) );
    var gsm = Math.round((mweight/1000)/(width*height)*70306450)/100;
    form.elements['txtStockGSM'+signature].value = gsm;
  } // end if
}

function basis_weight_to_gsm( form, signature ) {
  const width = parseFloat(1*form.elements['txtSpecificStockWidth'+signature].value);
  const height = parseFloat(1*form.elements['txtSpecificStockHeight'+signature].value);
  const basis_width = parseFloat(1*form.elements['basis_width'+signature].value);
  const basis_height = parseFloat(1*form.elements['basis_height'+signature].value);
  var mweight;
  var basis_weight = parseFloat(1*form.elements['basis_mweight'+signature].value);
  if (basis_weight) {
    mweight = (width*height) * basis_weight / (basis_width*basis_height);
    form.elements['txtCustomMWeight'+signature].value = Math.round(mweight*10)/10;
    // mweight is the weight of 1000 sheets, so calc the wpsi and multiply by 703064.5 to get gsm
    //console.log( "wpsi: " + (mweight/1000)/(width*height) );
    var gsm = Math.round((mweight/1000)/(width*height)*70306450)/100;
    form.elements['txtStockGSM'+signature].value = gsm;
  } // end if
}

function gsm_to_mweight( form, signature ) {
  var gsm = parseFloat(1*form.elements['txtStockGSM'+signature].value);
  if (gsm) {
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
  } else {
    basis_weight_to_gsm(form, signature);
  }
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
  update_basis_size(radio);
  calc();
}

function update_basis_size(element) {
  const form = document.getElementById('f1');
  const signature = '';
  if (get_value(form.elements['StockType']) == 'Envelope'
      || form.elements['txtSpecificStockBrand'].value.match(/bond/i)
      || form.elements['txtSpecificStockFinish'].value.match(/bond/i)
      || form.elements['txtSpecificStockWeight'].value.match(/bond/i)
  ) {
    form.elements['basis_width'].value = 17;
    form.elements['basis_height'].value = 22;
  } else {
    if (form.elements['txtSpecificStockBrand'].value.match(/cover/i)
      || form.elements['txtSpecificStockBrand'].value.match(/board/i)
      || form.elements['txtSpecificStockFinish'].value.match(/cover/i)
      || form.elements['txtSpecificStockFinish'].value.match(/board/i)
      || form.elements['txtSpecificStockWeight'].value.match(/cover/i)
      || form.elements['txtSpecificStockWeight'].value.match(/board/i)
    ) {
      form.elements['basis_width'].value = 20;
      form.elements['basis_height'].value = 26;
    } else {
      form.elements['basis_width'].value = 25;
      form.elements['basis_height'].value = 38;
    }
  }
} // end function update_basis_size

function specific_stock_onchange(radio) {
  const re = /^rdbSpecificStock(\d*)$/;
  const matches = radio.name.match(re);
  const signature = matches[1];
  if (radio.value=='Y'){
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
    //Stock_onchange(radio, signature);
  }
  calc();
}

function brand_onchange(element) {
  update_doublesided();
  update_basis_size(element);
  select_grade();
  calc();
}

function finish_onchange(element) {
  update_doublesided();
  update_basis_size(element);
  select_grade();
  calc();
}

function weight_onchange(element) {
  let re = /^txtSpecificStockWeight(\d*)$/;
  let matches = re.exec(element.name);
  const signature = matches[1];
  re = /([\d\.]+)(lb|#)/i;
  matches = re.exec(element.value);
  const form = element.form;
  if (matches) {
    const weight = matches[1];
    console.log(signature, weight);
    form.elements['basis_mweight'+signature].value = weight * 2;
    basis_weight_to_gsm(form, signature);
  } else {
    re = /([\d\.])PT/i;
    if (matches = re.exec(element.value)) {
      form.elements['txtSpecificStockCalliper'+signature].value = matches[1]/1000;
      form.elements['txtSpecificStockCalliperPT'+signature].value = matches[1];
    } else {
      console.log("No match against "+element.value);
    }
  }
  calc();
}

function update_doublesided() {
  const form = document.getElementById('f1');
  if (form.elements['txtSpecificStockFinish'].value.match(/C1S/i)
    || form.elements['txtSpecificStockFinish'].value.match(/1 ?Side/i)
  ) {
    set_rdb_value(form.elements['doublesided'], 'N');
  } else if (form.elements['txtSpecificStockFinish'].value.match(/C2S/i)
    || form.elements['txtSpecificStockFinish'].value.match(/2 ?Side/i)
  ) {
    set_rdb_value(form.elements['doublesided'], 'Y');
  }
}

function calliper_onchange(element) {
  const form = element.form;
  if (element.name.match(/^txtSpecificStockCalliperPT/)) {
    form.elements['txtSpecificStockCalliper'].value = element.value/1000;
  } else if (element.name.match(/^txtSpecificStockCalliper/)) {
    form.elements['txtSpecificStockCalliperPT'].value = element.value*1000;
  } else {
    console.log("No match");
  }
  calc();
}

function select_grade() {
  /*
     #1  =>  '1 Gloss-coated stock',
    #2  =>  '2 Matte-coated stock',
    #3  =>  '3 Gloss-coated, web stock',
    #4  =>  '4 Uncoated, white stock',
    #5  =>  '5 Uncoated, yellow stock'
    */
  const grade_ddm = document.getElementById('StockGrade');
  const form = grade_ddm.form;
  const stock_type = get_value( form.elements['StockType'] );
  var new_grade = 0;

  const finish = form.elements['txtSpecificStockFinish'].value;
  const brand = form.elements['txtSpecificStockBrand'].value;
  if (finish.match(/gloss/i)) {
    new_grade = (stock_type == 'Roll') ? 3 : 1;
  } else if (finish.match(/matte/i) || finish.match(/silk/i)) {
    new_grade = 2;
  } else if (finish.match(/uncoated/i)) {
    new_grade = 4;
  } else if (brand.match(/gloss/i)) {
    new_grade = (stock_type == 'Roll') ? 3 : 1;
  } else if (brand.match(/matte/i) || brand.match(/silk/i)) {
    new_grade = 2;
  } else if (brand.match(/uncoated/i)) {
    new_grade = 4;
  }
  if (new_grade) {
    $j(grade_ddm).val(new_grade);
  }
}
function addstock(button) {
//OpenWin = this.open(page,"CtrlWindow","top=80,left=100,screenX=100,screenY=80,width=1000,height=900,toolbar=no,menubar=no,location=yes, scrollbars=yes,resizable=yes");
    console.log(button);
    const form = button.form;
    if (get_rdb_value(form, 'rdbSpecificStock') == 'Y') {
        // Go direct to add new stock
          window.open('/administrator/stock/stock.html?brand='+encodeURIComponent(form.elements['txtSpecificStockBrand'].value)
              +'&'+'finish='+encodeURIComponent(form.elements['txtSpecificStockFinish'].value)
              +'&'+'colour='+encodeURIComponent(form.elements['txtSpecificStockColour'].value)
              +'&'+'weight='+encodeURIComponent(form.elements['txtSpecificStockWeight'].value)
              +'&'+'calliper='+encodeURIComponent(form.elements['txtSpecificStockCalliper'].value)
              +'&'+'type='+encodeURIComponent(get_value(form.elements['StockType']))
              +'&'+'width='+encodeURIComponent(form.elements['txtSpecificStockWidth'].value)
              +'&'+'height='+encodeURIComponent(form.elements['txtSpecificStockHeight'].value)
              +'&'+'mweight='+encodeURIComponent(form.elements['txtCustomMWeight'].value)
              +'&'+'basis_mweight='+encodeURIComponent(form.elements['basis_mweight'].value)
              +'&'+'basis_width='+encodeURIComponent(form.elements['basis_width'].value)
              +'&'+'basis_height='+encodeURIComponent(form.elements['basis_height'].value)
              +'&'+'gsm='+encodeURIComponent(form.elements['txtStockGSM'].value)
              +'&'+'grade='+encodeURIComponent(get_value(form.elements['StockGrade']))
              +'&'+'sheets_per_package='+encodeURIComponent(get_value(form.elements['sheets_per_package']))
              +'&'+'full_packages='+encodeURIComponent(get_value(form.elements['full_packages']))
              +'&'+'doublesided='+encodeURIComponent(get_value(form.elements['doublesided']))
              +'&'+'price='+encodeURIComponent(get_value(form.elements['CustomStockPrice']))

              );
      } else {
          // Go to stock list with filters already selected
          window.open('/administrator/stock/list.html?brand='+encodeURIComponent(form.elements['stock_name'].value)
              +'&'+'finish='+encodeURIComponent(form.elements['stock_finish'].value)
              +'&'+'colour='+encodeURIComponent(form.elements['stock_colour'].value)
              +'&'+'weight='+encodeURIComponent(form.elements['stock_weight'].value)
            );
        }
}
