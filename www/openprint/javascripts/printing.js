var pendingCalc;
var DieCuttingQuestionFlag = true;
var ScoringQuestionFlag = true;
var FoldingQuestionFlag = true;
var CuttingQuestionFlag = true;

function versions_onkeyup( e ) {
	new Ajax.Updater( 'Version_Descriptions', '_version_descriptions.html', { parameters: Form.serialize(e.form, true) } );
}

function filter_colours( side, signature ) {
	// For each of the colours
	for ( var index = 1; index < 10; index += 1 ) {
		var type_element = $('ColourCoatingType'+index+side+signature);
		if ( ! type_element ) continue;
		var type = type_element.value;
		if ( ! type ) continue;
		// we can have many PMS's
		if ( type == 'PMS' ) continue;

		// clear my selected type out of the other dropdowns
		for ( var j = index+1; j <= 10; j += 1 ) {
			var t = $('ColourCoatingType'+j+side+signature);
			if ( ! t ) continue;

			var option_index = get_option_index( t, type );
			if ( -1 != option_index ) {
				t.options[option_index] = null;
				continue;
			} // end if
		} // end for each colour
	} // end for each colour index
} // end function filter_colours

function SpecialColour_onchange( element, side, index, signature ) {
  const form = element.form;
	const spec = 'ColourCoating'+index+side+signature;

	const type_element = $('ColourCoatingType'+index+side+signature);
  if ( ! type_element ) {
    alert( 'ColourCoatingType'+index+side+signature + ' not found!');
    return;
  }
	const type = type_element.value;
	if ( type ) {
		form.elements['chk'+spec].checked=true;

		if ( ! $('ColourCoating'+(1+parseInt(index))+side+signature) ) {
			// Add another colour
			new Ajax.Request('/includes/main/proj/_additional_colour_coating.html', { 
				method: 'get', 
				parameters: { 
          project_id: form.elements['ProjectIndex'].value,
					Side: side, 
					index : 1+parseInt(index),
					Signature : signature 
				},
				onSuccess: function(response){
					new Insertion.After($(spec), response.responseText);
					filter_colours(side,signature);
					
					}
			} );
		} else {
			if ( type != 'PMS' ) {
				// Remove the selected type from the dropdodwns of the other special colours
				filter_colours(side,signature);
			} // end if
		} // end if
	} else { // type == ''
		if ( element.name != 'chk'+spec ) 
			element.form.elements['chk'+spec].checked=false;

		// Nothing is selected for type, so if we just switched off AQ, then we need to add it back to the other 
		// type dropdowns
		for ( var i = 1; i < 10; i += 1 ) {
			if ( i == index ) continue;

			// if the colour exists
			var t = document.getElementById('ColourCoatingType'+i+side+signature);
			if ( ! t ) continue;

			for ( let m = 0; m < type_element.options.length; m += 1 ) {
				const v = type_element.options[m].value;
				// see if it is in there
				if ( ! isin_ddm( t, v ) ) {
					add_option( t, v, type_element.options[m].text );
					sort_ddm( t );
					// need tos ort, add later FIXME
				} // end if
			} // end for each colour
		} // end for each option in type_element
	} // end if

	if (  -1 != type.indexOf('Overall') ) {
		$('ColourCoatingCoverage'+index+side+signature).hide();
	} else {
		$('ColourCoatingCoverage'+index+side+signature).show();
	} // end if
	if ( -1 != type.indexOf('PMS') ) {
		$('ColourCoatingColour'+index+side+signature).show();
		$('ColourCoatingPrice'+index+side+signature).show();
		$('ColourCoatingMileage'+index+side+signature).show();
	} else {
		$('ColourCoatingColour'+index+side+signature).hide();
		$('ColourCoatingPrice'+index+side+signature).hide();
		$('ColourCoatingMileage'+index+side+signature).hide();
	} // end if
	calc(element.form.name);
} // end function

function chkSpecial_onClick(chkBox) {
	return;
	/*
    var name = 'txt' + chkBox.name.substr(3);
	var form = chkBox.form;

	if ( chkBox.checked == false ) {
		form.elements[name].value = '';
	} // end if
	*/
} // end function

function validate_data(formName) {
	const form = getFormObj(formName);
	let text = '';
  if ( form.txtWidth && ! ( 0 < parseFloat(form.txtWidth.value) ) ) {
    text += "Please enter the Width of your Project\n";
  } // end if
  if ( form.txtHeight && ! ( 0 < parseFloat(form.txtHeight.value) ) ) {
    text += "Please enter the Height of your Project\n";
  } // end if
  if ( form.txtWidth && form.txtHeight && form.txtFinalWidth && form.txtFinalHeight ) {
    if ( form.txtWidth.value * form.txtHeight.value < form.txtFinalWidth.value * form.txtFinalHeight.value ) {
      text += "Your Finished Dimenstions may not exceed your Flat Dimensions.\n";
    } // end if		
	} // end if

	let stockBrand = form.ddmStockBrand ? get_ddm_value(form.ddmStockBrand) : '';
	let stockFinish = form.ddmStockFinish ? get_ddm_value(form.ddmStockFinish) : '';
	let stockColour = form.ddmStockColour ? get_ddm_value(form.ddmStockColour) : '';

	let stockWeight = form.ddmStockWeight ? get_ddm_value(form.ddmStockWeight) : '';
	if ( stockBrand == 'Customer Supplied' && form.txtSpecificStockCalliper && form.txtSpecificStockCalliper.value ) {
		stockWeight = form.txtSpecificStockCalliper.value;
	} // end if
	
	if ( stockBrand == '' && form.txtSpecificStockBrand && form.txtSpecificStockBrand.value == '' ) {
		text += "Please Select a Paper Brand\n";
	} // end if
	if ( form.elements['txtSpecificStockWidth'] &&
    form.elements['txtSpecificStockHeight'] &&
    form.txtSpecificStockWidth.value &&
    form.txtSpecificStockHeight.value ) {
		if ( (parseFloat(form.txtWidth.value) <= parseFloat(form.txtSpecificStockWidth.value) && parseFloat(form.txtHeight.value) <= parseFloat(form.txtSpecificStockHeight.value) )  ||
				(parseFloat(form.txtWidth.value) <= parseFloat(form.txtSpecificStockHeight.value) && parseFloat(form.txtHeight.value) <= parseFloat(form.txtSpecificStockWidth.value)) ) { 
			// we have good sheet size
		} else {
			text += "The sheet size you have entered is too small for the dimesions of your project, please enter a larger sheet size.";	
		} // end if
	} // end if
	if ( ! ( stockFinish || (form.txtSpecificStockFinish && form.txtSpecificStockFinish.value ) ) ) {
		text += "Please Select a Paper Finish\n";
	} // end if
	if ( ! ( stockColour || ( form.txtSpecificStockColour && form.txtSpecificStockColour.value ) ) ) {
		text += "Please Select a Paper Colour\n";
	} // end if
	if ( ! ( stockWeight  || ( form.txtSpecificStockWeight && form.txtSpecificStockWeight.value ) ) ) {
		text += "Please Select a Paper Weight\n";
	} // end if

 // Presentation Folder Fields:
	if ( form.elements['chkLeftPocket'] && form.elements['chkRightPocket'] ) {
		if ( ! ( form.chkLeftPocket.checked || form.chkRightPocket.checked ) ) {
			text += "Please specify which side your pockets will go on.";
		} // end if
	} // end if
	if ( form.elements['rdbPocketSize'] && ! ( form.rdbPocketSize[0].checked || form.rdbPocketSize[1].checked ) ) {
		text += "Please specify this size of your pockets.";
	} // end if

	return true;
} // end function validate_data

function get_impositions( form, qty_index ) {
	form = $(form);
	var h = $H(Form.serialize(form, true));
	h.each(function(pair) {
		if ( pair.value == '' ) 
			h.unset(pair.key);
		if ( pair.key == 'btnFunction' ) 
			h.unset(pair.key);
	});
	h.set('qty_index', qty_index);
	popup_window( '/main/project/prin/_impositions.html', h, { width: 800 } );
} 

function calc_print( formName, force, options ) {
	const form = getFormObj( formName );

	if ( timeout ) {
		clearTimeout( timeout );
		timeout = null;
	}
	if ( gettingNewPrice && ! force ) {
		if (pendingCalc) {
			pendingCalc.abort();
		} else {
			// This prevents concurrent price getting
			if (options) {
				timeout = setTimeout("calc_print('f1', 0, " + Object.toJSON( options ) + ");", 1000 );	
			} else {
				timeout = setTimeout("calc_print('f1' );", 1000 );	
			} // end if
			return;
		}
	} // end if
	gettingNewPrice = true;

	clear_price_data(form);
	const AlertDiv = $('AlertDiv');
	if (AlertDiv) {
		AlertDiv.innerHTML = '';
		AlertDiv.hide();
	} // end if
	const div = $('InformationDiv');
	if (div) {
		div.innerHTML = 'Calculating....';
		div.show();
	} // end if

  const data = $j(form).serializeArray();
  for (let i=0; i < data.length; i++) {
    const pair = data[i];
    if (
      (pair.value == '')
      ||
      (pair.name == 'btnFunction')
      ||
      (pair.name == 'alert')
    ) {
      data.splice(i,1);
    }
  }
  if (options) {
    for (const [key, value] of Object.entries(options)) {
      data[data.length] = {name: key, value: value};
    }
  }
	//pendingCalc = new Ajax.Request( '/main/project/_calc.json', { method: 'post', parameters: h, evalScripts: true } );
  pendingCalc = $j.ajax({
    type: 'POST',
    url: '/main/project/_calc.json',
    data: data,
    dataType: 'json',
    success: function(data, textStatus, jqXHR) {
      cbFillPrintResults(data);
    }
  }).done(function(data) {
  }).fail(function(jqXHR, textStatus, errorThrown) {
	  gettingNewPrice = false;
    console.log("fail", textStatus, errorThrown);
  });
	return true;
} // end calc_print

function clear_price_data( form ) {
	for ( let qtyNum = 1; qtyNum <= 3; qtyNum += 1 ) {
		if ( quantities[qtyNum] > 0 ) {

      const el = document.getElementById('hdnBreakdown'+qtyNum);
      if (el) el.innerHTML = '';

      if (form.elements['txtPressSheetQty'+qtyNum]) form.elements['txtPressSheetQty'+qtyNum].value = '';
      else console.log("Nothing found for txtPressSheetQty"+qtyNum);

			if ( form.elements['MPrice'+qtyNum] ) form.elements["MPrice"+qtyNum].value = '';
			if ( form.elements['txtUnitPrice'+qtyNum] ) form.elements["txtUnitPrice"+qtyNum].value = '';
			if ( form.elements['txtPrice'+qtyNum] && form.elements['OverridePrice'+qtyNum] && ! get_value(form.elements['OverridePrice'+qtyNum]) ) form.elements["txtPrice"+qtyNum].value = '';
			continue;

			if ( form.elements['StockType'+qtyNum] ) form.elements["StockType"+qtyNum].value = '';
			if ( form.elements["txtPlateQuantity"+qtyNum] ) form.elements["txtPlateQuantity"+qtyNum].value = '';
			
			if ( form.elements["txtImposition"+qtyNum] ) {
				if ( ( ! form.elements['chkOverrideImposition'+qtyNum] ) || ( ! get_value(form.elements['chkOverrideImposition'+qtyNum]) ) ) {
					//form.elements["txtImposition"+qtyNum].value = '';
				} // end if
			} // end if
			if ( form.elements["txtImageWidth"+qtyNum]) form.elements["txtImageWidth"+qtyNum].value = '';
			if ( form.elements["txtImageHeight"+qtyNum]) form.elements["txtImageHeight"+qtyNum].value = '';
			if ( ( ! form.elements['OverrideImpositionLayout'+qtyNum] ) || ( ! get_value(form.elements['OverrideImpositionLayout'+qtyNum]) ) ) {
				if ( form.elements['hdnImpositionColumns'+qtyNum]) form.elements['hdnImpositionColumns'+qtyNum].value = '';
				if ( form.elements['hdnImpositionRows'+qtyNum]) form.elements['hdnImpositionRows'+qtyNum].value = '';
				if ( form.elements['hdnImpositionDutchColumns'+qtyNum]) form.elements['hdnImpositionDutchColumns'+qtyNum].value = '';
				if ( form.elements['hdnImpositionDutchRows'+qtyNum]) form.elements['hdnImpositionDutchRows'+qtyNum].value = '';
			}
			//form.elements["txtAdditionalPrice"+qtyNum].value = '0.00';
			if ( ! ( form.elements['chkOverridePress'+qtyNum] && get_value(form.elements['chkOverridePress'+qtyNum]) ) ) {
				if ( form.elements['ddmPress'+qtyNum] ) {
					if ( form.elements['ddmPress'+qtyNum].type == 'select-one' ) {
						ddm_select_by_index( form.elements['ddmPress'+qtyNum], 0 );
					} else {
						form.elements['ddmPress'+qtyNum].value = '';
					} // end if
				} // end if
			} // end if
			if ( form.elements['chkOverridePageQuantity'+qtyNum] && ! get_value(form.elements['chkOverridePageQuantity'+qtyNum]) ) {
				form.elements['PageQuantity'+qtyNum].value='';
			} // end if
			if ( form.elements['ddmRunStyle'+qtyNum] ) {
				if ( 
					! ( form.elements['chkOverrideRunStyle'+qtyNum] && get_value(form.elements['chkOverrideRunStyle'+qtyNum]) ) 
					&& form.elements['ddmRunStyle'+qtyNum].type == 'select-one' 
					) {
					ddm_select_by_index( form.elements['ddmRunStyle'+qtyNum], 0 );
				} // end if
			} // end if
		} // endif
	} // end for

} // end function

// This function does all the extra stuff required for printing
function cbFillPrintResults( results ) {
	cbFillResults( results );
	block_calc = true;
	const form = getFormObj( 'f1' );

  // If nothing get selected for sheet size, it may be a custom stock, so add the custom size to the ddm
	for (let i = 1; i <= 3; i += 1) {
		const ddm = form.elements['ddmStockSheetSize'+i];
		if (!ddm) continue;
		if ( ddm.selectedIndex == -1 || ddm.selectedIndex == 0 ) {
			const width = form.elements['StockWidth'+i].value;
      if (!width) continue;
			const height = form.elements['StockHeight'+i].value;
			const type = get_value( form.elements['StockType'+i] );
		
			if ( type == 'Sheet' ) {
				if ( ! ddm_select_by_value( ddm, width + 'x' + height, false ) ) {
          console.log("adding", width, height);
					ddm.options[ddm.options.length] = new Option( width+'" x ' + height+'"', width + 'x' + height, true );
					ddm_select_by_value( ddm, width + 'x' + height, false );
				} // end if
			} else if ( type == 'Roll' ) {
				if ( ! ddm_select_by_value( ddm, width, false ) ) {
					ddm.options[ddm.options.length] = new Option( width + '" Roll', width, true );
					ddm_select_by_value( ddm, width );
				} // end if
      } else {
        console.log("Unknown type of stock", type);
			} // end if
		} // end if
	} // end for
 
	block_calc = false;
	gettingNewPrice = false;

	const addServices = new Array();
	var cancelAddFolding = false;
	if ( form.NeedFolding.value > 0 ) {
		if ( form.HasFolding.value == 0 ) {
			if ( FoldingQuestionFlag && confirm("Your project needs folding.  Click OK to automatically add folding to your project.") ) {
				// addService( 'f1', 'Folding' );
				addServices[addServices.length] = 'Folding';
			} else {
				cancelAddFolding = true;
			} // end if
			FoldingQuestionFlag = false;
		} // end if
	} // end if

	if ( form.NeedDieCutting && (form.NeedDieCutting.value > 0)) {
		if ( form.HasDieCutting.value == 0 && (form.txtFinalWidth && form.txtFinalHeight)) {
			if ( DieCuttingQuestionFlag && confirm("Your project requires die cutting.  Click OK to automatically add die cutting to your project.") ) {
				//   addService( 'f1', 'Scoring' );
				addServices[addServices.length] = 'DieCutting';
			} // end if
			DieCuttingQuestionFlag = false;
		} // end if
	} // end if

	if ( form.NeedScoring.value > 0 && cancelAddFolding == false ) {
		if ( form.HasScoring.value == 0 && (form.HasFolding.value > 0 || (form.txtFinalWidth && form.txtFinalHeight) ) ) {
			if ( ScoringQuestionFlag && confirm("The selected paper needs to be scored before folding, or else the edge will crack.  Click OK to automatically add scoring to your project.") ) {
				//   addService( 'f1', 'Scoring' );
				addServices[addServices.length] = 'Scoring';
			} // end if
			ScoringQuestionFlag = false;
		} // end if
	} // end if

	if ( form.NeedCutting.value > 0 ) {
		if ( form.HasCutting.value == 0 ) {
			if ( CuttingQuestionFlag && confirm("Your project needs cutting.  Click OK to automatically add cutting to your project.") ) {
				//   addService( 'f1', 'Cutting' );
				addServices[addServices.length] = 'Cutting';
			} // end if
			CuttingQuestionFlag = false;
		} // end if
	} // end if

	if ( addServices.length ) {
		calc_print( 'f1', 0, { action: 'add_service', service_name: addServices } );
  } else {
    console.log("Not adding servics");
	} // end if

} // end function cbFillPrintResults( results )


function selectProjectTemplate( formName ) {
	const form = getFormObj( formName );
	const ddm = form.ddmProjectSize;
	if ( ddm ) {
		const TemplateType = get_value( form.rdbTemplateType );
		const selected_size = get_value( form.ddmProjectSize );
		clear_ddm(ddm);
		add_option( form.ddmProjectSize, 'Custom','Custom' );
		if ( TemplateType ) {
      if (TemplateType == 'MetalCoil' || TemplateType == 'PlasticCoil' || TemplateType == 'Cerlox') {
        $j('#SpiralOptions').show();
      } else {
        $j('#SpiralOptions').hide();
      }
			if ( options[TemplateType] ) {
				if ( options[TemplateType][0].message ) {
					alert(options[TemplateType][0].message);
				}
				for ( let x = 0, len=options[TemplateType].length; x < len; x += 1 ) {
					add_option( ddm, options[TemplateType][x].text, options[TemplateType][x].value );
				} // end for
			} else {
				alert("We do not have dimensions for the selected project template "+TemplateType+" at this time.\n\nPlease select custom in the size pull down and input your finished and flat dimensions in the supplied text boxes.");	
			} // end if
		} // end if TemplateType
		ddm_select_by_value( form.ddmProjectSize, selected_size );
		ddmProjectSize_onChange( form );
	} else {
		calc(formName);
	} // end if ddm
} // end function selectProjectTemplate( form );

function ddmProjectSize_onChange( form ) {
	var index = form.ddmProjectSize.selectedIndex;
	if (form.ddmProjectSize.options[index] && form.ddmProjectSize.options[index].value != 'Custom' ) {
		var dimensions = form.ddmProjectSize.options[form.ddmProjectSize.selectedIndex].value.split(',');
		var finished = dimensions[0].split('x');
		form.txtFinalWidth.value = finished[0];
		form.txtFinalHeight.value = finished[1];
		if ( form.txtWidth && form.txtHeight ) {
			var flat = dimensions[1].split('x');
			form.txtWidth.value = flat[0];
			form.txtHeight.value = flat[1];
		} // end if
	} // end if
	calc( form.name );
} // end function ddmProjectSize_onChange();

function dimensions_onChange( form ) {
    if ( ! form.ddmProjectSize )
        return;
    var index = form.ddmProjectSize.selectedIndex;
    if (form.ddmProjectSize.options[index] && form.ddmProjectSize.options[index].value != 'Custom' ) {
        var dimensions = form.ddmProjectSize.options[form.ddmProjectSize.selectedIndex].value.split(',');
        var finished = dimensions[0].split('x');
        var flat = dimensions[1].split('x');
        if (
                ( parseFloat(form.txtFinalWidth.value) != parseFloat(finished[0]) )
                || ( parseFloat(form.txtFinalHeight.value) != parseFloat(finished[1]) )
                || ( parseFloat(form.txtWidth.value) != parseFloat(flat[0]) )
                || ( parseFloat(form.txtHeight.value) != parseFloat(flat[1]) )
           ) {
            ddm_select_by_value(form.ddmProjectSize, 'Custom');
        } // end if
    } // end if
	calc(form.name);
} // end function dimensions_onChange

function StockPopup_onchange(data) {
  const form = document.getElementById(data.form);
	const filters = new Array( 'Brand','Finish','Colour','Weight','Quality', 'Group', 'SheetSize', 'Size' );
	for ( let index = 0, len = filters.length; index < len; ++index ) {
    const filter = form.elements['ddmStock'+filters[index]+data.signature_id];
    if ( filter ) {
      filter.disabled = false;
    } // end if filter exists
	} // end for 
	gettingNewPrice = false;
  $j('#StockPopupResults').load('/main/project/prin/_stocks.html', 
    $j(form).serialize()
  );
}

function Stock_onchange( element, id ) {
  const form = element.form;
  if ( gettingNewPrice ) {
    console.log("Waiting for calculation....");
    clearTimeout( timeout );
    timeout = setTimeout( 'Stock_onchange(document.' + form.name + '.elements["' + element.name + '"],"' + id + '");', 1000 );
    return;
  } // end if
  timeout = null;

  data = [
    {name: 'project_id', value: form.elements['ProjectIndex'].value},
    {name: 'selected', value: element.name },
    {name: 'form', value: form.id },
    {name: 'signature_id', value: id }
  ];
	if ( form.elements['txtWidth'] ) 
		data[data.length] = {name: 'width', value: form.elements['txtWidth'].value };
	if ( form.elements['txtHeight'] ) 
		data[data.length] = {name: 'height', value: form.elements['txtHeight'].value };
	if ( form.elements['rdbSuppliedStock'+id] ) {
		data[data.length] = {name: 'Supplied', value: get_value( form.elements['rdbSuppliedStock'+id] ) };
	} // end if
	if ( form.elements['projecttype_id'] ) {
		data[data.length] = {name: 'projecttype_id', value: get_value( form.elements['projecttype_id'] ) };
	} // end if

	const filters = new Array( 'Brand','Finish','Colour','Weight','Quality', 'Group', 'Size' );
	for ( let index = 0, len = filters.length; index < len; ++index ) {
		const filter = form.elements['ddmStock'+filters[index]+id];
		if ( filter ) {
			data[data.length] = { name: filters[index], value: filter.getValue() };
			filter.disabled = true;
		//} else {
			//alert('filter ' + 'ddmStock'+filters[index]+id );
		} // end if filter exists
	} // end for 
	//h.set( 'callback', 'cbStockFillResults' );
	//new Ajax.Request( '/main/project/prin/_paper.json', { parameters: h, evalScripts: true } );
  pendingCalc = $j.ajax({
    type: 'POST',
    url: '/main/project/prin/_paper.json',
    data: data,
    dataType: 'json',
    success: function(data, textStatus, jqXHR) {
      if (form.callback) {
        if (window[form.callback.value] instanceof Function) {
          window[form.callback.value](data);
        } else {
          console.log(form.callback.value, window[form.callback.value]);
        }
      } else {
        cbStockFillResults(data);
      }
    }
  }).done(function(data) {
    console.log(data);
  }).fail(function(jqXHR, textStatus, errorThrown) {
    gettingNewPrice = false;
    console.log("fail", textStatus, errorThrown);
  });
} // end function Stock_onchange

function cbStockFillResults( results ) {
	const form = $(results.form);
	if ( ! form ) {
		alert('No form for ' + results.form );
		gettingNewPrice = false;
		return;
	} // end if
	//results.unset('form');
	const signature_id = results.signature_id;
	const suffixes = new Array ( '', '1', '2', '3' );

  for (const [key, value] of Object.entries(results)) {
    //for ( var index = 0, len = keys.length; index < len; ++index ) {
        //var key = keys[index];
        //var value = results.get(key);
		const options = new Array();
		options[0] = create_option( '', 'select one' );

		if ( key == 'SheetSize' ) {
			for ( let val_index = 0, val_len = value.length; val_index < val_len; ++val_index ) {
				const size = value[val_index].split('x');
				if ( size.length == 1 ) {
					//Roll
					options[options.length] = create_option( value[val_index], size[0]+'" Roll' );
				} else {
					const dimensions = new Array();
					size.each(function(item){ dimensions[dimensions.length] = item+'"';});

					options[options.length] = create_option( value[val_index], dimensions.join( ' x ' ) );
				} // end if
			} // end for
			for ( let suffix_index = 0; suffix_index < suffixes.length; suffix_index += 1 ) {
				const ddm = form.elements['ddmStock'+key+suffix_index];
				if ( ! ddm ) {
	//alert('No ddmStock'+key+suffix);
					continue;
				} // end if
				const selectedValue = ddm.getValue();
				fill_ddm( ddm, options );
				if ( options.length == 2 ) {
					ddm_select_by_index( ddm, 1 );
				} else {
					ddm_select_by_value( ddm, selectedValue );
				} // end if
			} // end for suffix
		} else {
			const ddm = form.elements['ddmStock'+key+signature_id];
			if ( ! ddm ) {
//alert('No ddmStock'+key+suffix);
				continue;
			} // end if
			const selectedValue = ddm.getValue();

			for ( let ddm_index = 0, ddm_len = value.length; ddm_index < ddm_len; ++ddm_index ) {
				options[options.length] = create_option( value[ddm_index], value[ddm_index] );
			} // end for
			fill_ddm( ddm, options );
			if ( options.length == 2 ) {
				ddm_select_by_index( ddm, 1 );
			} else {
				ddm_select_by_value( ddm, selectedValue );
			} // end if
		} // end if SheetSize or Other
	} // end for each key

	// turn drop downs back on
	const filters = new Array( 'Brand','Finish','Colour','Weight','Quality', 'Group', 'SheetSize', 'Size' );
	for ( let index = 0, len = filters.length; index < len; ++index ) {
		for ( let suffix_index = 0; suffix_index < suffixes.length; suffix_index += 1 ) {
			const suffix = suffixes[suffix_index];
			const filter = form.elements['ddmStock'+filters[index]+signature_id+suffix];
			if ( filter ) {
				filter.disabled = false;
			} // end if filter exists
		} // end foreach suffix
	} // end for 
	gettingNewPrice = false;
    //if ( timeout ) { clearTimeout( timeout ); timeout = null; }
	calc(form.name);
} // end function Stock_Fill

window.addEventListener('DOMContentLoaded', function() {
	calc('f1');

  $j('.side_link').each(function(index, link) {
    const signature_index = link.getAttribute('data_signature_index');
    const side = document.getElementById('InksOnBackQuestions'+signature_index);
    if (! (side && link) ) {
      console.log(link,side, 'not found');
      return;
    }
    // Set the initial status on page load.
    if (link.checked) link_sides.apply(link);
    link.onclick = link_sides.bind(link);
  });
  console.log('done');
});

// Gray out/disable side two when it's "linked" to side one. The server
// handles replicating the fields across when they are linked.
function link_sides(e) {
  const linked = this.checked;
  const signature_index = this.getAttribute('data_signature_index');
  const side   = document.getElementById('InksOnBackQuestions'+signature_index);
  const colour = linked ? '#999999' : '';

  // When disabled we grey out the side.
  side.style.backgroundColor = linked ? '#EEEEEE' : '';
  side.style.color           = colour;
  side.style.borderColor     = colour;

  // Display a message to the user if we're disabled.
  const side2_linked = document.getElementById('side2_linked'+signature_index);
  if (side2_linked) side2_linked.style.display = linked ? 'block' : 'none';

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
        } else {
          elem.disabled = elem.was_disabled;
        }
        break;
      default:
        console.log("Unknown element", elem);
    }
  });
  calc('f1');
}

function selectCoverTemplate(el) {
  console.log(el);
  const matches = el.name.match(/rdbTemplateType(\d)/);
  let form = '';
  if (matches.length > 1) form = matches[1];
  const div=$('PresentationFolderQuestions'+form);
  if (div){
    if (el.value.match(/Panel/)) {
      div.show();
    } else {
      div.hide();
    };
  }
  if (el.value.startsWith('2Panel1Pocket')) {
    $('rdbPanels2'+form).checked = true;
    $('chkPocketCenter'+form).checked=false;
  } else if (el.value.startsWith('2Panel2Pocket')) {
    $('rdbPanels2'+form).checked=true;
    $('chkPocketCenter'+form).checked=false;
    $('chkPocketLeft'+form).checked=true;
    $('chkPocketRight'+form).checked=true;
  } else if (el.value.startsWith('3Panel2Pocket')) {
    $('rdbPanels3'+form).checked=true;
  }

  selectProjectTemplate(el.form.id);
}

function clear_stock() {
}
