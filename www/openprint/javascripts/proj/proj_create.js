function submit_handler(form) {
	let form_status = validate_data(form);
	if (form_status) {
		form_status = checkSelections(form);
	} // end if
	if (form_status) {
		form.submit();
	} // end if
	return form_status;
} // end function submit_handler

function validate_data(form) {
	var text = '';

	var ptype = false;
	if ( form.rdbProjectType ) {
		if ( get_value( form.rdbProjectType ) ) {
			ptype = true;
		} // end if
	} else if ( form.project_type_id ) {
		if ( get_value( form.project_type_id ) ) {
			ptype = true;
		} // end if
	}
	if ( ! ptype ) {
		text += "Please select the type of project.\n";
	} // end if

	if ( form.rdbMode && (form.rdbMode.type != 'hidden') ) {
		var mode = false;
		for ( var index = 0; index < form.rdbMode.length; index += 1 ) {
			if ( form.rdbMode[index].checked ) {
				mode = true;
				break;
			} // end if
		} // end for
		if ( ! mode ) {
			text += "Please select a project creation method as either Basic or Detailed Specifications.\n";
		} // end if
	} // end if

	if (form.quantity1.value) {
		if ( parseInt(form.quantity1.value) != form.quantity1.value) {
			text += "The field 'Quantity 1' may only contain whole numbers greater than 1.\n";
		} // end if
	} // end if
	if (form.quantity2.value) {
		if ( parseInt(form.quantity2.value) != form.quantity2.value) {
			text += "The field 'Quantity 2' may only contain whole numbers greater than 1.\n";
		} // end if
	} // end if
	if (form.quantity3.value) {
		if ( parseInt(form.quantity3.value) != form.quantity3.value) {
			text += "The field 'Quantity 3' may only contain whole numbers greater than 1.\n";
		} // end if
	} // end if
	if ( ! form.quantity1.value && ! form.quantity2.value && ! form.quantity3.value ) { 
		text += "Please enter at least one Quantity for your project.\n";
	} // end if
	if ( form.ddmDesign && ! get_value( form.ddmDesign ) ) {
		text += "Please specify the supplied format.\n";
	} // end if

	if (text) {
		text = "Please correct the following errors before proceeding:\n\n" + text;
		alert(text);
		return false;
	} // end if

  if (form.elements['reprint'] && (get_value(form.elements['reprint']) != 'Y')) {
    const upper_company_name = form.elements['company_id'] ? get_ddm_text(form.elements['company_id']).toUpperCase() : company_name.toUpperCase();
    if (upper_company_name) {
      const summary = form.elements['reference'].value.toUpperCase();
      if ((upper_company_name.indexOf('REPRINT') >=0) || (summary.indexOf('REPRINT') >= 0)) {
        if (confirm("This appears to be a reprint but you haven't marked it as such.  Is this a reprint?")) {
          set_value(form.elements['reprint'], 'Y');
          setReason('Y', $('reprintReasonSection'));
          return false;
        }
      }
    }
  }
	return true;
} //end function validate_data

function project_type_alert( form, rdb ) {
	if ( rdb.value == "BusinessCards" ) {
		alert ("Please input the total # of business cards in the fields below. Name quantities will be asked for later. ");
	} // end if
	if ( rdb.value == "MultiVersion" ) {
		alert ("Please input the total quantity in the fields below." + "\n" + "\n" + "Version quantities can be input on the next page.");
	} // end if
// Project types not yet working	
/*	if (( rdb.value == 'Calendars' ) || ( rdb.value == 'Forms' ) || ( rdb.value == 'Cheques' ) || ( rdb.value == 'PresentationFolders' )) {
		alert ("We cannot provide an instantaneous quote with the complete bindery services for the selected project type at this time. However one of our representatives will add the additional bindery price and e-mail a revised copy to you in the immdeiate future.");
	} // end if
*/
}

function checkSelections (form){
	const projectService = get_rdb_value(form,'rdbShipping');
	if ( projectService == 'CourierLTLFreight' ) {
		if ( ! confirm ("Please click OK to calculate your project without a shipping price and an administrator will contact you to arrange the most cost effective way to ship your project(s).\n\nOr click Cancel to select a different shipping method.")) {
		// if the click Cancel on the pop-up, then return false to cancel the submit
		return false;
		} // end if
	} // end if			
	return true;
} // end checkSelections()

function setReason(reprintVal,divElem) {
  if (reprintVal == 'Y') {
    // Project is a reprint.
    // Display reason drop down option.
    divElem.style.display = "block";
  } else {
    // Project is not a reprint.
    // Make sure reason drop down is hidden.
    divElem.style.display = "none";
  }
}

function ddmDesign_onChange(form){
} // end function

function set_service( chk, service, checked ) {
	for ( let index = 0; index < chk.length; index += 1 ) {
		if ( chk[index].value == service ) {
			chk[index].checked = checked;
		} // end if
	} // end for
} // end function check_service

function check_service( chk, service ) {
	for ( let index = 0; index < chk.length; index += 1 ) {
		if ( chk[index].value == service ) {
			return chk[index].checked;
		} // end if
	} // end for
	//alert( "check_server: Service " + service + "not found!" );
} // end function check_service

function service_onclick( element ) {
	if ( element.value == 'NoBindery' && element.checked ) {
		if ( element.form.chkServicesPerfectBound ) 
			element.form.chkServicesPerfectBound.checked = false;
		if ( element.form.chkServicesSaddleStitching ) 
			element.form.chkServicesSaddleStitching.checked = false;
		if ( element.form.chkServicesLoopStitching ) 
			element.form.chkServicesLoopStitching.checked = false;
		if ( element.form.chkServicesFolding ) 
			element.form.chkServicesFolding.checked = false;
		if ( element.form.chkServicesCutting ) 
			element.form.chkServicesCutting.checked = false;
		if ( element.form.chkServicesScoring ) 
			element.form.chkServicesScoring.checked = false;
		if ( element.form.chkServicesPerforating ) 
			element.form.chkServicesPerforating.checked = false;
		if ( element.form.chkServicesDrilling ) 
			element.form.chkServicesDrilling.checked = false;
		if ( element.form.chkServicesPlainCartons ) 
			element.form.chkServicesPlainCartons.checked = false;
	} else if ( element.value == 'NoPrinting' ) {
		var e = $('Design');
		if ( element.checked ) {
			if ( element.form.chkServicesProofs ) 
				element.form.chkServicesProofs.checked = false;
			if ( e ) e.hide();
		} else {
			if ( element.form.chkServicesProofs ) 
				element.form.chkServicesProofs.checked = true;
			if ( e ) e.show();
		} // end if
	} else if ( element.checked ) {
		if ( element.form.chkServicesNoBindery ) 
			element.form.chkServicesNoBindery.checked = false;
	} // end if
	
}

function checkSelections (form){

	const projectType = get_rdb_value( form.rdbProjectType );
	if ( projectType != 'ColourCopies' && projectType != 'InkjetOutputs' && projectType !='NoPrintingRequired') {
		const design = get_value(form.ddmDesign);
		if ( design == 'FinalFilm' ) {
			if ( ! form.chkServicesFilmStripping.checked ) {
				form.chkServicesFilmStripping.checked = true;
			} // end if
		} else if ( design == 'ElectronicFile' ) {
			if ( ! form.chkServicesProofs.checked ) {
				//if (confirm ("We will require a proof in order to print your project.\n\nIf you would like to add a proof to your project please click OK, otherwise click Cancel to supply your own proof.")){
				form.chkServicesProofs.checked = true;
				//} // end if
			} // end if
		} // end if
	} // end if

	if ( projectType == 'PresentationFolders' ) {
		if ( form.chkServicesDieCutting && ! form.chkServicesDieCutting.checked ) {
			if (confirm ("Your project requires a die cutting service in order for us to fulfill your request for Presentation Folders.\n\nIf you would like to add die cutting to your project please click OK, otherwise click Cancel.")){
				form.chkServicesDieCutting.checked = true;
			} // end if			
		} // end if
	} else if ( projectType == 'ScratchPads' ) {
		if ( form.chkServicesPadding && ! form.chkServicesPadding.checked ) {
			if (confirm ("Your project requires a padding service in order for us to fulfill your request for scratch pads.\n\nIf you would like to add padding to your project please click OK, otherwise click Cancel.")){
				form.chkServicesPadding.checked=true;
			} // end if			
		} // end if
	} // end if
	if ( ( form.chkServicesSaddleStitching && form.chkServicesSaddleStitching.checked ) || ( form.chkServicesLoopStitching && form.chkServicesLoopStitching.checked ) ) {
		if ( ! form.chkServicesFolding.checked ) {
			//if (confirm ("Your project requires a folding service in order for us to fufill your request.\n\nIf you would like to add folding to your project please click OK, otherwise click Cancel.")){
               form.chkServicesFolding.checked = true;
        	//} // end if
		} // end if
	} // end if
	return true;
} // end checkFilmProofsPads()
