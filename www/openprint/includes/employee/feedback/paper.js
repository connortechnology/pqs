var selectedName = null;
var selectedFinish = null;
var selectedColour = null;
var selectedWeight = null;

function get_value( obj ) {
	if ( ! obj ) {
		alert( "No obj in get_value");
	}
	if ( obj.type == 'select-one' ) {
		return get_ddm_value( obj );
	} // end if
	return obj.value;
}

function get_parameters( form, pressid ) {
	gettingNewPrice = true;

    var parameters = new Array ( 
						get_ddm_value( form.elements['UsedPaperBrand'+pressid] ),
						get_ddm_value( form.elements['UsedPaperFinish'+pressid] ),
						get_ddm_value( form.elements['UsedPaperColour'+pressid] ),
						get_ddm_value( form.elements['UsedPaperWeight'+pressid] ),
						pressid
						);
	return parameters;
} // end function get_parameters( form )

function UsedPaperBrand_onChange( e ) {
	var form = getFormObj('f1');

	jsrsExecute( '/jsrs.htm', cbFillDropDowns, 'openprint::paper::select_by_name', get_parameters(form, e) );

} // end function UsedPaperBrand_onChange()

function UsedPaperFinish_onChange( e ) {
	var form = getFormObj('f1');
	jsrsExecute( '/jsrs.htm', cbFillDropDowns, 'openprint::paper::select_by_finish', get_parameters(form, e) );
} // end function UsedPaperFinish_onChange();

function UsedPaperColour_onChange( e ) {
	var form = getFormObj('f1');
	jsrsExecute( '/jsrs.htm', cbFillDropDowns, 'openprint::paper::select_by_colour', get_parameters(form, e) );
} // end function UsedPaperColour_onChange();

function UsedPaperWeight_onChange( e ) {

	var form = getFormObj('f1');
	jsrsExecute( '/jsrs.htm', cbFillDropDowns, 'openprint::paper::select_by_weight', get_parameters(form, e) );
} // end function UsedPaperWeight_onChange();

function UsedPaperSheetSize_onChange() {
} // end function UsedPaperSheetSize_onChange();

function fill_drop_down( results ) {
	var form = getFormObj('f1');

    var BrandOptions = new Array();
    BrandOptions[BrandOptions.length] = create_option( '', 'Please select one' );
    var FinishOptions = new Array();
    FinishOptions[FinishOptions.length] = create_option( '', 'Please select one' );
    var ColourOptions = new Array();
    ColourOptions[ColourOptions.length] = create_option( '', 'Please select one' );
    var WeightOptions = new Array();
    WeightOptions[WeightOptions.length] = create_option( '', 'Please select one' );
    var SheetSizeOptions = new Array();
    SheetSizeOptions[SheetSizeOptions.length] = create_option( '', 'Please select one' );

    var aOptionPairs = results.split('|');
    for ( var i = 0; i < aOptionPairs.length; i++ ){
        if ( aOptionPairs[i].indexOf('~') != -1 ) {
            var aOptions = aOptionPairs[i].split('~');
            switch ( aOptions[0] ) {
                case 'Brand':
                    BrandOptions[BrandOptions.length] = create_option( aOptions[1], aOptions[2] );
                    break;
                case 'Finish':
                    FinishOptions[FinishOptions.length] = create_option( aOptions[1], aOptions[2] );
                    break;
                case 'Colour':
                    ColourOptions[ColourOptions.length] = create_option( aOptions[1], aOptions[2] );
                    break;
                case 'Weight':
                    WeightOptions[WeightOptions.length] = create_option( aOptions[1], aOptions[2] );
                    break;
                case 'SheetSize':
                    SheetSizeOptions[SheetSizeOptions.length] = create_option( aOptions[1], aOptions[2] );
                    break;
				case 'Press':
					press = aOptions[1];
            } // end switch
        } // end if
    } // end for

    if ( BrandOptions.length > 1 ) {
        var selectedValue = get_ddm_value( form.elements['UsedPaperBrand'+press] );
        fill_ddm( form.elements['UsedPaperBrand'+press], BrandOptions, 'UsedPaperBrand_onChange("'+press+'")' );
		
		if ( BrandOptions.length == 2 )
			ddm_select_by_index( form.elements['UsedPaperBrand'+press], 1 );
		else
			ddm_select_by_value( form.elements['UsedPaperBrand'+press], selectedValue, 0 );
	} // end if

    if ( FinishOptions.length > 1 ) {
        var selectedValue = get_ddm_value( form.elements['UsedPaperFinish'+press] );
        fill_ddm( form.elements['UsedPaperFinish'+press], FinishOptions, 'UsedPaperFinish_onChange("'+press+'")' );
		if ( FinishOptions.length == 2 ) {
			ddm_select_by_index( form.elements['UsedPaperFinish'+press], 1 );
		} else {
			ddm_select_by_value( form.elements['UsedPaperFinish'+press], selectedValue, 0 );
		} // end if
	} // end if

    if ( ColourOptions.length > 1 ) {
        var selectedValue = get_ddm_value( form.elements['UsedPaperColour'+press] );
		fill_ddm( form.elements['UsedPaperColour'+press], ColourOptions, 'UsedPaperColour_onChange("'+press+'")' );
		if ( ColourOptions.length == 2 )
			ddm_select_by_index( form.elements['UsedPaperColour'+press], 1 );
		else
			ddm_select_by_value( form.elements['UsedPaperColour'+press], selectedValue, 0 );
	} // end if

    if ( WeightOptions.length > 1 ) {
		var selectedValue = get_ddm_value( form.elements['UsedPaperWeight'+press] );
		fill_ddm( form.elements['UsedPaperWeight'+press], WeightOptions, 'UsedPaperWeight_onChange("'+press+'")' );
		if ( WeightOptions.length == 2 ) {
			ddm_select_by_index( form.elements['UsedPaperWeight'+press], 1 );
		} else {
			ddm_select_by_value( form.elements['UsedPaperWeight'+press], selectedValue, 0 );
		} // end if
    } // end if

	// Sheetsize gets special treatment, cuz it gets selected during price calcs
    if ( SheetSizeOptions.length > 1 && form.elements['UsedPaperSheetSize'+press] ) {
		var selectedValue = get_ddm_value( form.elements['UsedPaperSheetSize'+press] );
		fill_ddm( form.elements['UsedPaperSheetSize'+press], SheetSizeOptions, 'UsedPaperSheetSize_onChange' );

		if ( SheetSizeOptions.length == 2 )
			ddm_select_by_index( form.elements['UsedPaperSheetSize'+press], 1 );
		else
			ddm_select_by_value( form.elements['UsedPaperSheetSize'+press], selectedValue,0 );
    } // end if

} // end function fill_drop_down( results ) {

function cbFillDropDowns( results ) {
	fill_drop_down( results );

	gettingNewPrice = false;
} // end function cbFillDropDowns( results )
