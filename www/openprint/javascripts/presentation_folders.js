function selectProjectTemplate( formName ) {
	const form = getFormObj( formName );
	const type = get_rdb_value( form, 'rdbTemplateType' );
	if ( type == 'PF1Pocket' ) {
		if ( form.chkLeftPocket.checked && form.chkRightPocket.checked ) {
			form.chkLeftPocket.checked = false;
		} else if ( ! ( form.chkLeftPocket.checked || form.chkRightPocket.checked ) ) {
			form.chkRightPocket.checked = true;
		} // end if
		form.txtFinalWidth.readonly = true;
		form.txtFinalHeight.readonly = true;
		form.txtWidth.readonly = true;
		form.txtHeight.readonly = true;
	} else if ( type == 'PF2Pocket' ) {
		form.chkLeftPocket.checked = true;
		form.chkRightPocket.checked = true;
		form.txtFinalWidth.readonly = true;
		form.txtFinalHeight.readonly = true;
		form.txtWidth.readonly = true;
		form.txtHeight.readonly = true;
	} else {
		form.txtFinalWidth.readonly = false;
		form.txtFinalHeight.readonly = false;
		form.txtWidth.readonly = false;
		form.txtHeight.readonly = false;
	} // end if

	const ddm = form.ddmProjectSize;
	if ( ddm ) {
		const selected_size = get_ddm_value( ddm );
		clear_ddm(ddm);
		if ( options[type] ) {
			for ( var x = 0; x < options[type].length; x++ ) {
				var value = options[type][x].value;
				var text = options[type][x].text;
				add_option( ddm, options[type][x].text, options[type][x].value );
			} // end for
		} else {
			if ( type ) {
        console.log(form.rdbTemplateType);
        console.log(type);
				alert("We do not have common dimensions for the selected project template at this time.\n\nPlease select custom in the dimension pull down and input you own finished and flat dimesnions in the supplied text boxes below.");
			} // type
		} // end if
		if ( type != 'PF1Pocket' && type != 'PF2Pocket' ) {
			add_option( form.ddmProjectSize, 'Custom','Custom' );
		} // end if
		ddm_select_by_value( form.ddmProjectSize, selected_size );
		ddmProjectSize_onChange( form );
	} // end if ddm

} // end function selectProjectTemplate( form );
