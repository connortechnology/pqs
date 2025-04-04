function change_handler( element ) {
	if ( element.form.elements['debug'] ) {
		element.form.elements['debug'].value='chang handler ' + element.name;
	} // end if
	var commands = new Array();

	// parse through the input splitting it into commands
	for ( var i = 0; i < element.value.length; i += 1 ) {
		var c = element.value.charCodeAt(i);
		// 57 is '9'. Anything above is not a number
		if ( c < 48 ) {
			break;
		} else if ( c > 57 ) {
			// Start a command
			var j;
			for ( j = i+1; j < element.value.length; j+= 1 ) {
				var c2 = element.value.charCodeAt(j);
				// 57 is '9'. Anything above is not a number
				if ( c2 > 57 ) {
					break;
				} // end if
			} // end for j
			var comm = element.value.substr(i,j-i);
			commands[commands.length] = comm;
			i = j - 1;
		} // end if
	} // end for
	if ( commands.length )
		element.value = '';
	if ( element.form.elements['debug'] ) {
element.form.elements['debug'].value=commands.length+' commands';
	} // end if

	while ( commands.length ) {

		var command = commands.shift();
		var first = command.charAt(0);
		var value = command.substr(1,command.length-1);
		var newelement = 0;

		if ( first == 'A' ) {
			newelement = element.form.Action;
		} else if ( first == 'D' ) {
			newelement = element.form.Docket ? element.form.Docket : element.form.StartDocket;
		} else if ( first == 'E' ) {
			newelement = element.form.Operator ? element.form.Operator : element.form.UserID;
		} else if ( first == 'F' ) {
			newelement = element.form.Form;
		} else if ( first == 'I' ) {
			if ( element.form.Invoice ) {
				newelement = element.form.Invoice;
			} // end if
			if ( element.form.invoice_id ) {
				newelement = element.form.invoice_id;
			} // end if
			if ( element.form.skid_id ) {
				newelement = element.form.skid_id;
			} // end if
		} else if ( first == 'L' ) {
			newelement = element.form.Location;
		} else if ( first == 'M' ) {
			newelement = element.form.Equipment;
		} else if ( first == 'O' ) {
			if ( element.form.Order ) {
				newelement = element.form.Order;
			} else if ( element.form.OrderID ) {
				newelement = element.form.OrderID;
			} else if ( element.form.order_id ) {
				newelement = element.form.order_id;
			} // end if
		} else if ( first == 'P' ) {
			if ( element.form.Project )
				newelement = element.form.Project;
			else if ( element.form.project_id )
				newelement = element.form.project_id;
		} else if ( first == 'p' ) { // Paper strangely enough.  Someday I hope to deprecaate project, and use P for paper. Or re-allocate submit
			if ( element.form.paper_id ) 
				newelement  = element.form.paper_id;
		} else if ( first == 'Q' ) { // Q Is reserved for quantity
			if ( element.form.Quantity )
				newelement = element.form.Quantity;
		} else if ( first == 'R' || first == 'r' ) { // Paper strangely enough.  Someday I hope to deprecaate project, and use P for paper. Or re-allocate submit
			if ( element.form.rfidtag_id ) 
				newelement  = element.form.rfidtag_id;
		} else if ( first == 'S' ) { // S
			if ( commands.length ) {
				commands.push( command );
				continue;
			} 
			if ( typeof(submit_handler)==  'function' ) {
				submit_handler(element.form);
			} else {
				element.form.submit();
			} // end if
			return;
		} else if ( first == 'T' ) {
			newelement = element.form.Time;
		} else if ( first == 'V' ) {
			newelement = element.form.verification_code;
		} else if ( first == 'W' ) {
			newelement = element.form.Weekday;
		} // end if
		if ( newelement ) {
			newelement.value = first+value;
			newelement.focus();
		} // end if
	} // end for commands
} // end function change_handler


function input_handler( element, e ) {
	var character;
	if ( window.event ) {
		character = window.event.keyCode;
	} else if (e) {
		character = e.which;
	} else {
		return true;
	} // end if
	if ( character == 65 || character == 97 ) { // A
		if ( element.form.Action ) {
			element.form.Action.focus();
			element.form.Action.value='';
		} // end if
		return false;
	} else if ( character == 68 || character == 100 ) { // D
		if ( element.form.Docket ) {
			element.form.Docket.focus();
			element.form.Docket.value='';
		} else if ( element.form.StartDocket ) {
			element.form.StartDocket.focus();
			element.form.StartDocket.value='';
		} // end if
		return false;
	} else if ( character == 69 || character == 101 ) { // E
		if ( element.form.Operator ) {
			element.form.Operator.focus();
			element.form.Operator.value='';
		} else if ( element.form.UserID ) {
			element.form.UserID.focus();
			element.form.UserID.value='';
		} // end if
		return false;
	} else if ( character == 70 || character == 102 ) { // F
		if ( element.form.Form ) {
			element.form.Form.focus();
			element.form.Form.value='';
		} else if ( element.form.Signature ) {
			element.form.Signature.focus();
			element.form.Signature.value='';
		} // end if
		return false;
	} else if ( character == 73 || character == 105 ) { // I
		if ( element.form.Invoice ) {
			element.form.Invoice.focus();
			element.form.Invoice.value='';
		} else if ( element.form.invoice_id ) {
			element.form.invoice_id.focus();
			element.form.invoice_id.value='';
		} else if ( element.form.skid_id ) {
			element.form.skid_id.focus();
			element.form.skid_id.value='';
		} else {
			
			for ( var i = 0; i < element.form.elements.length; i += 1 ) {
				if ( element.form.elements[i].type != 'text' ) 
					continue;
				if ( element.form.elements[i].length ) {
					for ( var j = 0; j< element.form.elements[i].length; j += 1 ) {
						if ( element.form.elements[i][j].name.substr(0,7) == 'skid_id' ) {
							element.form.elements[i][j].focus();
							element.form.elements[i][j].value='';
							return false;
						} // end if it's a skid_id	
                    } // end for j
				} else {
					if ( element.form.elements[i].name.substr(0,7) == 'skid_id' ) {
						element.form.elements[i].focus();
						element.form.elements[i].value='';
						return false;
					} // end if it's a skid_id	
				} // end if
			} // end for i
		} // end if
		return false;
	} else if ( character == 76 || character == 108  ) { // M
		if ( element.form.Location ) {
			element.form.Location.focus();
			element.form.Location.value='';
		} // end if
		return false;
	} else if ( character == 77 || character == 109  ) { // M
		if ( element.form.Equipment ) {
			element.form.Equipment.focus();
			element.form.Equipment.value='';
		} // end if
		return false;
	} else if ( character == 79 || character == 111  ) { // O
		if ( element.form.Order ) {
			element.form.Order.focus();
			element.form.Order.value='';
		} else if ( element.form.OrderID ) {
			element.form.OrderID.focus();
			element.form.OrderID.value='';
		} else if ( element.form.order_id ) {
			element.form.order_id.focus();
			element.form.order_id.value='';
		} // end if
		return false;
	} else if ( character == 80 ) { // P
		if ( element.form.Project ) {
			element.form.Project.focus();
			element.form.Project.value='';
		} else if ( element.form.project_id ) {
			element.form.project_id.focus();
			element.form.project_id.value='';
		} // end if
		return false;
	} else if ( character == 112 ) { // p
		if ( element.form.paper_id ) {
			element.form.paper_id.focus();
			element.form.paper_id.value='';
		} // end if
		return false;
	} else if ( character == 81 || character == 113 ) { // Q
		if ( element.form.paper_id ) {
			element.form.quantity.focus();
			element.form.quantity.value='';
		} // end if
		return false;
	} else if ( character == 82 || character == 114 ) { // R
		if ( element.name.substr(0,10) == 'rfidtag_id' ) {
			element.focus();
			element.value='';
			return false;
		} // end if

		if ( element.form ) {
			var form = element.form;
			for ( var i = 0; i < form.elements.length; i += 1 ) {
				if ( form.elements[i].type != 'text' ) 
					continue;
				if ( form.elements[i].name.substr(0,10) == 'rfidtag_id' ) {
					form.elements[i].focus();
					form.elements[i].value='';
					return false;
				} // end if
			} // end for i
		} // end if
		for ( var x = 0; x < document.forms.length; x += 1 ) {
			var form = document.forms[x];

			if ( form.rfidtag_id ) {
				form.rfidtag_id.focus();
				form.rfidtag_id.value='';
				return false;
			} else {
				for ( var i = 0; i < form.elements.length; i += 1 ) {
					if ( form.elements[i].type != 'text' ) 
						continue;
					if ( form.elements[i].name.substr(0,10) == 'rfidtag_id' ) {
						form.elements[i].focus();
						form.elements[i].value='';
						return false;
					} // end if
				} // end for i
			} // end if
		} // end for
		return false;
	} else if ( character == 83 || character == 115 ) { // S
		if ( typeof(submit_handler)==  'function' ) {
			submit_handler(element.form);
		} else {
			element.form.submit();
		} // end if
		return false;
	} else if ( character == 84 || character == 116 ) { // T
		if ( element.form.Time ) {
			element.form.Time.focus();
			element.form.Time.value='';
		} // end if
		return false;
	} else if ( character == 85 || character == 117 ) { // U
	} else if ( character == 86 || character == 118 ) { // V
		for ( var x = 0; x < document.forms.length; x+=1 ) {
			if ( document.forms[x].verification_code ) {
				document.forms[x].verification_code.focus();
				document.forms[x].verification_code.value='';
				break;
			} // end if
		} // end for
		return false;
	} else if ( character == 87 || character == 119 ) { // W
		if ( element.form.Weekday ) {
			element.form.Weekday.focus();
			element.form.Weekday.value='';
		} // end if
		return false;
	} else if ( character == 13 || character == 8 || character == 0 || character == 9 || character == 16 || character == 45 ) { // enter
		return true;
	} else if ( character == 43 ) {
		return false;
	} else if ( character < 48 ) {
		return true;
	} else if ( character > 57 ) {
		//alert( character );
		return false;
	} else if ( character >= 48 && character <= 57 ) {
		if ( element.name == 'Weekday' ) {
			if ( character == 48 ) {
				element.value = 'Monday';
			} else if ( character == 49 ) {
				element.value = 'Tuesday';
			} else if ( character == 50 ) {
				element.value = 'Wednesday';
			} else if ( character == 51 ) {
				element.value = 'Thursday';
			} else if ( character == 52 ) {
				element.value = 'Friday';
			} else if ( character == 53 ) {
				element.value = 'Saturday';
			} else if ( character == 54 ) {
				element.value = 'Sunday';
			} // end if
			return false;
		} else if ( element.name == 'Time' ) {
			if ( character == 48 ) {
				element.value = 'AM';
			} else if ( character == 49 ) {
				element.value = 'PM';
			} else if ( character == 50 ) {
				element.value = '3M';
			} // end if
			return false;
		} else if ( element.name == 'Equipment' ) {
			var equipmentname = $('EquipmentName');
			if ( equipmentname && Equipment ) {
				equipmentname.innerHTML = Equipment[element.value+(character-48)];
			} // end if
			return true;
		} else if ( element.name == 'UserID' ) {
			if ( element.value.charAt(0) == 'E' ) {
				element.value = element.value.substr(1,element.value.length-1);
			} // end if

			if ( emails_by_id[1*element.value] ) {
				element.form.email.value = emails_by_id[1*element.value];
				element.form.password.focus();
			} else {
				element.form.email.value = 'User not found: ' + element.value;

			} // end if
			return true;
		} else {
			return true;
		} // end if
	} else {
		//alert( character );
	
	} // end if
	return true;
} // end function
