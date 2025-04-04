// From now on this file should only have stuff related to paper in it

function body_onLoad() {
	if ( typeof(selectProjectTemplate) == 'function' ) {
		selectProjectTemplate( 'f1' );
	} else if ( typeof(calc) == 'function' ) {
		calc('f1');
	} // end if
} // end function body_onLoad();

function paper_price_calc( element, group ) {
console.log(element, group);
	const form = element.form;
	if ( ! form ) alert( 'no form' );
	if ( element.name.match( /^StockPricePerM/ ) ) {
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
    // element could be width, height or anything but we just calculate from cwt
    element = form.elements['CustomStockPrice'+group];
		const costcwt = parseFloat( element.value.replace(/[^\d\-\.]/g, '' ) );
    if (!costcwt) return;

		if ( get_value( form.elements['StockType'+group] ) == 'Roll' ) {
			return;
		} else {
			if ( ! form.elements['txtCustomMWeight'+group].value ) {
				$('PaperAlert'+group).innerHTML = 'Please enter MWeight';
				return;
			} // end if

			form.elements['StockPricePerM'+group].value = do_decimals( costcwt * form.elements['txtCustomMWeight'+group].value / 100, 2 );
		} // end if
	} // end if
} // end function

function calc_basis_weight_from_weight(weight_element) {
  let re = /([\d\.]+)lb/i;
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
    calc(form.name);
  } else {
    console.log("No match against "+weight_element.value);
  }
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

function ddmStockSheetSize_onchange() {
	calc('f1');
} // end function ddmStockSheetSize_onchange();

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
  const re = /(\d*)$/;
  const matches = re.exec(element.name);
  const signature = matches.length ? matches[1] : '';
  const form = document.getElementById('f1');
  if (get_value(form.elements['StockType'+signature]) == 'Envelope'
      || form.elements['txtSpecificStockBrand'+signature].value.match(/bond/i)
      || form.elements['txtSpecificStockFinish'+signature].value.match(/bond/i)
      || form.elements['txtSpecificStockWeight'+signature].value.match(/bond/i)
  ) {
    form.elements['basis_width'+signature].value = 17;
    form.elements['basis_height'+signature].value = 22;
  } else {
    if (form.elements['txtSpecificStockBrand'+signature].value.match(/cover/i)
      || form.elements['txtSpecificStockBrand'+signature].value.match(/board/i)
      || form.elements['txtSpecificStockFinish'+signature].value.match(/cover/i)
      || form.elements['txtSpecificStockFinish'+signature].value.match(/board/i)
      || form.elements['txtSpecificStockWeight'+signature].value.match(/cover/i)
      || form.elements['txtSpecificStockWeight'+signature].value.match(/board/i)
    ) {
      form.elements['basis_width'+signature].value = 20;
      form.elements['basis_height'+signature].value = 26;
    } else {
      form.elements['basis_width'+signature].value = 25;
      form.elements['basis_height'+signature].value = 38;
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
  update_doublesided(element);
  update_basis_size(element);
  select_grade(element);
  calc(element.form.name);
}

function finish_onchange(element) {
  update_doublesided(element);
  update_basis_size(element);
  select_grade(element);
  calc(element.form.name);
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
      form.elements['calliper_mm'].value = do_decimals(element.value*25.4/1000, 3);
    } else {
      console.log("No match against "+element.value);
    }
  }
  calc(element.form.name);
}

function update_doublesided(element) {
  let re = /(\d*)$/;
  let matches = re.exec(element.name);
  const signature = matches.length ? matches[1] : '';
  const form = element.form;
  if (form.elements['txtSpecificStockFinish'+signature].value.match(/C1S/i)
    || form.elements['txtSpecificStockFinish'+signature].value.match(/1 ?Side/i)
  ) {
    set_rdb_value(form.elements['doublesided'+signature], 'N');
  } else if (form.elements['txtSpecificStockFinish'+signature].value.match(/C2S/i)
    || form.elements['txtSpecificStockFinish'+signature].value.match(/2 ?Side/i)
  ) {
    set_rdb_value(form.elements['doublesided'+signature], 'Y');
  }
}

function calliper_onchange(element) {
  let re = /(\d*)$/;
  let matches = re.exec(element.name);
  const signature = matches.length ? matches[1] : '';
console.log(element, signature);
  const form = element.form;
  if (element.name.match(/^txtSpecificStockCalliperPT/)) {
    form.elements['txtSpecificStockCalliper'+signature].value = element.value/1000;
    form.elements['calliper_mm'+signature].value = do_decimals(element.value*25.4/1000, 3);
  } else if (element.name.match(/^txtSpecificStockCalliper/)) {
    form.elements['txtSpecificStockCalliperPT'+signature].value = element.value*1000;
    form.elements['calliper_mm'+signature].value = do_decimals(element.value*25.4, 3);
  } else if (element.name.match(/^calliper_mm/)) {
    form.elements['txtSpecificStockCalliperPT'+signature].value = do_decimals(element.value*39.3701,1);
    // Use PT to ensure consistency
    form.elements['txtSpecificStockCalliper'+signature].value = form.elements['txtSpecificStockCalliperPT'+signature].value/1000;
  } else {
    console.log("No match");
  }
  calc(element.form.name);
}

function select_grade(element) {
  let re = /(\d*)$/;
  let matches = re.exec(element.name);
  const signature = matches.length ? matches[1] : '';
  /*
     #1  =>  '1 Gloss-coated stock',
    #2  =>  '2 Matte-coated stock',
    #3  =>  '3 Gloss-coated, web stock',
    #4  =>  '4 Uncoated, white stock',
    #5  =>  '5 Uncoated, yellow stock'
    */
  const grade_ddm = element.form.elements['StockGrade'+signature];
  const form = element.form;
  const stock_type = get_value( form.elements['StockType'+signature] );
  var new_grade = 0;

  const finish = form.elements['txtSpecificStockFinish'+signature].value;
  const brand = form.elements['txtSpecificStockBrand'+signature].value;
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

