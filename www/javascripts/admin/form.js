// <!-- The old hiding trick. If embedded needs CDATA tags.
function check_elements(elem) {
	for (var i = 0; i < elem.length; i++) {
		elem[i].checked = true;
	}
}

/*
 *  Code For Testing If Fields Are Empty
 */
 
// NOT FINISHED!!!!!!!!!!!!!!!!
function findEmptyFields(requiredFields) {
	var emptyFields = [];

	for (var i = 0; i < requiredFields.length; i++) {
		if (isEmpty(requiredFields[i].value) == "true") {
			emptyFields[emptyFields.length] = requiredFields[i].name;
		}
	}

	if (emptyFields.length > 0) {
		var errorMsg = "The following fields are required:";

		for (var j = 0; j < emptyFields.length; j++) {
			errorMsg += "\n" + emptyFields[j];
		}

		alert(errorMsg);
		return false;
	}
	return true;
}

// This function checks if value is empty.
function isEmpty(value){
	value = trim(value);
	// Removes all white space from front and back of value.

	if ((value == undefined) || (value.length == 0)) {
		return "true";
	} else {
		return "false";
	}
}

// This function removes all the white space from the fron and back of string.
function trim(string) {
	if (string != undefined) {
		string = String(string);
		var index = string.search(/\S/);
		string = string.substring(index, string.length);
		// Removes white space from the front of the string.
		index = string.search(/\s+$/);

		if (index != -1) {
			string = string.substring(0,index);
		}
		// Removes white space fromt the end of the string.
	}
	return string;
}


/*
 *    Code For Adding Event Handlers
 */

addListner( window, 'load', addEventHandlers, false );

function  addListner( element, action, method ,bool) {
	if ( element.addEventListener ) {
	   element.addEventListener ( action,  method, bool);
	}
	else if ( element.attachEvent ) {
		action='on'+action;
		element.attachEvent( action , method );
	}
}

function  removeListner( element, action, method ,bool) {
	if ( element.removeEventListener ) {
		element.removeEventListener ( action,  method, bool);
	}
	else if ( element.detachEvent ) {
		action='on'+action;
		element.detachEvent( action , method );
	}
}

//OnLoad, this function is called to add any event handlers on the form

function addEventHandlers()
{
	addPricingEventHandler();
	addConfirmDelete();
	addValidateEventHandler();
   // setValidationEventHandlers();
}

/*
 *  Code For Disabling Inputs In A Field
 */

function setEnableFieldSet ( chkBox ) {
	var parent = chkBox.parentNode;

	// Loops until it finds the feildset DOM node.
	while (parent.nodeName != 'FIELDSET') {
		parent = parent.parentNode;
	}

	// Calls procedure which gets all items (DOM nodes) within the fieldset tags.
	var nodes = walkTree (parent.firstChild );
	var elem;
	var property = new String(chkBox.checked);

	// Loops for all items within the fieldset tag.
	for (var i = 0; i < nodes.length; i++) {
		elem = nodes[i];

		// Checks if elem is of type input, textarea, or select.
		if ((elem.nodeName == "INPUT")  || (elem.nodeName == "TEXTAREA") || (elem.nodeName == "SELECT")) {
			if ((elem.hasAttributes ('disabled')) && (elem != chkBox)) {
				if (property == "true" ) {
					// Disables the element.
					elem.setAttribute('disabled', "true");
				}
				else {
					// Enables the element.
					elem.setAttribute('disabled', "false");
					elem.removeAttribute('disabled');
				}
			}
		}
	}
}

function walkTree (node) {
	var nodes = [];

	// Loops for each sibling of node and recurses for each children.
	while(node != null) {
		nodes[nodes.length] = node;
		// Calls the procedure which disables/enables the node.
		nodes = nodes.concat(walkTree (node.firstChild));
		node = node.nextSibling;
	}

	return nodes;
}

/*
 *    Code For Validating Fields In A Form
 */

// Array which holds the validating function for each class
var classToFunction =  [];
classToFunction["numeric"] = createWrapperFunction(null,null);
classToFunction["int"] = createWrapperFunction(null, 0);

// Runs through each element in the form and checks if the information in that
// element needs to be validated. If it does, then it is validated.
function validateForm( form ) {
	var elem;
	var invalidFields = [];

	for (var i = 0; i < document.forms[form.name].elements.length; i++) {
		elem = document.forms[form.name].elements[i];
		var func = classToFunction[elem.className];

		// Gets the function that validates the class
		if (func) {
			// Validates the element's information
			var flag = String(func(elem.value));

			if (flag == "false") {
				// Information was wrong, so the name of that is added to list of
				// incorrect fields.
				invalidFields[invalidFields.length] = elem.name;
			}
		}
	}

	if (invalidFields.length > 0 ) {
		// Loops for each invalid field and adds it to an error message which is
		// shown to the user.  Returns false so that the default action is
		// stopped.
		var errorMsg = "The following fields have invalid input:\n";

		for (var j = 0; j < invalidFields.length; j++) {
			var field = invalidFields[j];
			errorMsg = errorMsg + field +"\n";
		}

		alert(errorMsg);
		return false;
	}

	return true;
}

// Creates a wrapper function for the validateField function, so that the user
// only needs to enter the string being validated, since the percision and
// scale are already defined.
function createWrapperFunction( scale, prcsn) {
	return function(string) {
		return (validateField(string, scale, prcsn));
	}
}

// Creates a wrapper function for the validateField function, so that the user
// only needs to enter the string being validated, since the percision and
// scale are already defined.
function createWrapperEmptyFunction( scale, prcsn) {
	return function(string) {
		return ((validateField(string, scale, prcsn) == "true") && ( isEmpty(string) == "false" ));
	}
}

// Checks strings to make sure that it is either a proper numeric value or a
// proper integer value.  If it is the true is returned, else false is
// returned.
function validateField( string , scale, prcsn ) {
	string = String(string);
	var flag = String(isNumeric(string));

	// Checks if string contains any non numeric characters.
	if (flag == "true") {
		var scaleStr;
		var prcsnStr;
		var pos = string.indexOf('.');

		if (pos != -1) {
			// The string does have a decimal.
			if (prcsn == 0)
				// Checks that the number is not suppose to
				// be a integer.
				return "false";

			scaleStr = string.substring(0,pos);
			prcsnStr = string.substring(pos+1,string.length+1);

			if ((scale != null) && (scaleStr.length > scale))
				// Checks that the number is within the scale.
				return "false";

			if ((prcsn != null) &&(prcsnStr.length > prcsn))
				// Checks that  the number is within the percision.
				return "false";
		} else {
			if ((scale != null) && (string.length > scale))
				// Checks that the number is within the scale.
				return "false";
		}
	} else {
	   return "false";
	}
	return "true";
}

// Checks to see if the string contains only numeric characters.
function isNumeric(string) {
	string = String(string);
	var pat=(/,/g);
	string=string.replace(pat, "");
	// Removes any Commas.
	pat=(/([^\d|\.|\-])/);
	var flag = String(pat.test(string));

	// Tests if the string has any non numeric characters.
	if (flag == "true") {
		return "false";
	}

	if (string.indexOf(".") != string.lastIndexOf(".")) {
		// True if there is more then one decimal in the string.
		return "false";
	}

	if (string.substring(1,string.length).indexOf("-") != -1 ) {
		// True if there is a minus sign in the string
		// located other then the front of the string.
		return "false";
	}

	return "true";
}

/*
 *    Code For Validation While Input Is Being Typed
 */

// Removes any non numeric characters from string and keeps it within the
// given scale and percision.  Note: if scale or prcsn is null, then it will
// allow the user to input numbers as large as they want.
function validate( string , scale, prcsn ) {
	string = String(string);
	string = makeNumeric(string);
	//removes any non mumeric characters from the string

	var scaleStr;
	var prcsnStr;
	var pos = string.indexOf('.');

	if (pos != -1) {
		// Shortens string to scale and prcsn.
		scaleStr = string.substring(0,pos);
		prcsnStr = string.substring(pos+1,string.length+1);
		
		if ((scale != null) && (scaleStr.length > scale))
			scaleStr = scaleStr.substring(0,scale);

		if ((prcsn != null) && (prcsnStr.length > prcsn))
			prcsnStr = prcsnStr.substring(0, prcsn);

		if (prcsn != 0) {
			// String a numeric.
			string = scaleStr + '.' + prcsnStr;
		}
		else {
			// String an integer.
			string = scaleStr;
		}
	}
	else {
		if ((scale != null) && (string.length > scale))
			string = string.substring(0,scale);
	}
	return string;
}

// This function loops through the page and adds validation handler to inputs
// with certian classes (so far only class numeric and class int).
function setValidationEventHandlers() {
	var elem;
	var invalidFields = [];

	for (var j = 0; j < document.forms.length; j++) {
		// Loops for each form on the page.
		for ( var i = 0; i < document.forms[j].elements.length; i++) {
			// Loops for each element in the current form.
			elem = document.forms[j].elements[i];

			if (elem.className == "int") {
				// Adds an event handler to any input which takes an integer.
			   addListner( elem, 'keyup', function() {
					this.value = validate(this.value, null, 0);
				}, false);
			}else  if (elem.className == "numeric") {
				// Adds an event handler to any input which takes an numeric.
				addListner( elem, 'keyup', function() {
					this.value = validate(this.value, null, null);
				}, false);
			}
		}
	}
}

/*
 * INPUT ASSISTANCE
 */

var cacheval  = 0; // Global variable to catch input before modified
var thisedit = 0; // Global to check when done entering a price when cost is 0

function format(string, prcsn) {
	string = makeNumeric(string);

	if(prcsn == null)
		prcsn=2;

	var decimal = (string+"").indexOf('.');

	if (string.length == 0) {
		return "";
	} else if (decimal == -1 ) {
		string = string+".";

		for (var i=1; i<=prcsn;i++) {
			string = string+"0";
		}
	} else {
		var num = (string.length) - decimal;
		if (num <= prcsn) {
			for (var j = num; j <= prcsn; j++) {
			string = string+"0";
		}
	}

	if (decimal == 0 )
		string = "0" + string;
	}

	return string;
}

// Returns the percision of the number eneters (the # of decimal places being used)
function percision(number) {
	var places = (number+"").length - (number+"").indexOf('.');
	var returnVal;
	
	if ((number+"").indexOf('.') == -1) {
		returnVal = 3;
	}
	else if ((number+"").indexOf('.') == (number+"").length) {
		returnVal = places+2;
	}
	else {
		returnVal = places;
	}

	if (returnVal < 3)
		returnVal = 3;

	return returnVal;
}

// Here we perform a bankers round to deal with our money values
// value: The value to be rounded
// decimals: the position of decimal point from right after rounding
// eg. round(5.217, 3) returns 5.22
function round(value, decimals) {
	var temp = value;
	var index = (value+"").indexOf('.');
	
	if (index == -1) {
		index = (value+"").length;
		value = format(value,decimals-1);
		return  value;
	}
	
	if (value == 0)
		return format(value,decimals-1);
	
	value = value * (Math.pow(10,(decimals-1)));
	
//	if (value > 0 ) {
//		value = value + (0.5);
//	}
//	else {
//		value = value - (0.5);
//	}

	value = Math.round(value);	// use Math.round instead of the above if block
	value = value / (Math.pow(10,(decimals-1)));
	value = (""+value).substring(0,(decimals+index));
	value = format(value,decimals-1);

	return value;
}

function update(form, name, id){
	// Change the words cost price and markup to the specific pages.
	// CPM[ cost, price, markup ]
	var CPM = [];

	CPM[0] = document.getElementById(String(id+"cost")).value;
	CPM[1] = document.getElementById(String(id+"price")).value;
	CPM[2] = document.getElementById(String(id+"markup")).value;

	calcCPM(CPM, name);

	document.getElementById(String(id+"cost")).value = CPM[0];
	document.getElementById(String(id+"price")).value = CPM[1];
	document.getElementById(String(id+"markup")).value = CPM[2];
}

// CPM[ cost, price, markup ]
function calcCPM(CPM, updated) {
	if ((CPM[0] == 0) && (updated == "price")) { // Assuming no one has 0 cost
//		var tmp1 = CPM[1]*100000000000;
//		var tmp2 = CPM[2]*100000;
//		var tmp0 = tmp1 / (10000000 + tmp2); //CPM[1]/(1+CPM[2]/100);
//		CPM[0] = tmp0 / 10000;
		CPM[0] = CPM[1]/(1+CPM[2]/100);
		CPM[0] = round(CPM[0], percision(CPM[1]));
	}
	else if (((updated == "markup") && (cacheval != CPM[2])) || (updated == "cost")) {
		if (CPM[0] == 0) {
			return;
		}

		var tmp0 = CPM[0]*10000;  //cost allows 4 digits after decimal
		var tmp2 = CPM[2]*100000;	//markup allows 5 digits after decimal
		var tmp1 = tmp0 * (10000000 + tmp2); //CPM[0]*(1 + CPM[2]/100);
	
		CPM[1] = tmp1/100000000000;
		CPM[1] = round(CPM[1],(percision(CPM[0])));

		if ((updated == "cost") && (CPM[0] != cacheval)) {
			CPM[2] = round(CPM[2],(percision(CPM[0])+1));
		}
	}
	else if (updated == "price") {
		if (CPM[1] != cacheval) {
			var tmp1 = CPM[1] * 10000;
			var tmp0 = CPM[0] * 10000;
			CPM[2] = ((tmp1/tmp0) - 1) * 100;  // ((CPM[1]/CPM[0])-1) * 100;
		}
	
		if ((percision(CPM[0]) > percision(CPM[1])) && (thisedit ==1)) {
			CPM[1] = round(CPM[1],(percision(CPM[0])));
		}
	
		CPM[2] = round(CPM[2],(percision(CPM[1])+1));
		var tmp = CPM[0];
		CPM[0] = round(CPM[0],(percision(CPM[1])));
	
		if (tmp.length > CPM[0].length) {
			CPM[0] = tmp;
		}
		// the percision of the markup should be one more than the percision
		// of the price in order to prevent rounding problems
	}
}

function makeNumeric(string) {
	//  correct invalid numeric strings
	string = string+"*";
	var pat=(/[^\d|\.|\-]/g);
	string=string.replace(pat, "");

	if (string.indexOf(".") != string.lastIndexOf(".")) {
		string = string.replace(/[\.]/, "!");
		string = string.replace(/[\.]/, "");
		string = string.replace(/!/, ".")
		string = makeNumeric(string);
	}

	if (string.substring(1,string.length).indexOf("-") != -1 ) {
		string = string.substring(0,1) + string.substring(1,string.length).replace("-","");
		string = makeNumeric(string);
	}

	return string;
}

// Limits the precision to five (5).
function checkPer(element, name) {
	var val = element.value;

	if ((percision(val) > 5) && ( name == "markup")) {
		val = val.substring(0, val.length-percision(val)+6);
		element.value = val;
	}

	if ((percision(val) > 4) && (( name == "cost") || (name == "price"))) {
		val = val.substring(0, val.length-percision(val)+5);
		element.value = val;
	}
}

function calc(element) {
	// Because the elements name is formated #-#-name we split out the id #-#-
	// and the name.
	var index = element.name.lastIndexOf("-");
	var name  = element.name.substring(index+1);
	var id    = element.name.substring(0,index+1);

	checkPer(element, name);
	element.value = makeNumeric(element.value);

	// Special cases when things are 0 we want the following effects.
	if ((document.getElementById(String(id+"cost")).value != 0) && ((name == "price") && (document.getElementById(String(id+"price")).value == ""))) {
		document.getElementById(String(id+"markup")).value = "";
		return;
	}
	else if ((document.getElementById(String(id+"cost")).value == 0) && (name == "cost")) {
		document.getElementById(String(id+"price")).value = "";
		return;
	}
	else if ((document.getElementById(String(id+"cost")).value == 0) && ((thisedit == 0) || document.getElementById(String(id+"price")).value == 0)) {
		return;
	}

	update(element.form, name, id );
}

function addValidateEventHandler() {
	if( document.forms['pricing'] ) {
		var elems = document.forms['pricing'].elements;
	
		for (var i=0; i < elems.length; i++){
			var element = elems[i];
	
			if( /-(min|max|equip)$/.test(element.name) ) {
				element.onkeyup= function() {
					this.value = validate(this.value, null, null);
				}
			}
		}
	}
}

// Adds functionality to price tables allowing price to be calculated based on
// cost * markup.
function addPricingEventHandler() {
	if( document.forms['pricing'] ) {
		var elems = document.forms['pricing'].elements;

		// Loop for all the elements in the form wich holds the price table.
		for (var i=0; i < elems.length; i++){
			var element = elems[i];

			// If element is in the price table, then add event handlers
			if( /-(cost|markup|price)$/.test(element.name) ) {
				// Cost field, only set by markup and price when it is undefined.
				if (/cost$/.test(element.name)) {
					element.onkeyup = function () {
						calc(this);
					};
					element.onfocus = function() {
						cacheval = this.value;
					};
					element.onblur  = function() {
						this.value = format(this.value, 2);
						calc(this);
					};
				}
				// Markup event Handlers
				else if (/markup$/.test(element.name)) {
					element.onkeyup = function () {
						calc(this);
					};
					element.onfocus = function () {
						cacheval = this.value;
					};
					element.onblur  = function () {
						this.value = format(this.value,3);
					};
				}
				// Price Event Handlers
				else if (/price$/.test(element.name)) {
					element.onkeyup = function () {
						calc(this);
					};
					element.onfocus = function () {
						thisedit = 0;
						cacheval = this.value;
					};
					element.onblur  = function () {
						this.value = format(this.value, 2);
						thisedit = 1;
						calc(this);
					};
				}
			}
		}
	}
}

/*
 *  Code For Confirmation On Delete
 */
// Adds a confirmation step to all 'delete' buttons on form submit (using
// event handlers).
function addConfirmDelete () {
	// Array holds all elements on page that have the given name.
	var button = document.getElementsByName('delete');
	for (var i=0; i < button.length; i++) {
		// Make sure the object is actually a button and not some random
		// element called 'delete'.
		if(button[i].type == "submit")
			button[i].onclick = confirmDelete;
	}
}

function confirmDelete (e) {
	if ( ! confirm("Are you sure you want to delete?") ) {
		if (!e) { // For IE.
			event.returnValue = false;
		} else if(e.cancelable) { // For DOM
			e.stopPropagation();
			e.preventDefault();
		}
	}
}

// Specific to the pricelist page, should be in it's own JS or on the page
// itself. TODO: Lots of work, it's very very basic.
function pricelist_action (form) {
	// At least one field checked?
	var field = false;
	for (var i=0; i < form.field.length; i++) {
		if (form.field[i].checked)
			field = true;
	}
	// At least one table checked?
	var table = false;
	for (var i=0; i < form.table.length; i++) {
		if (form.table[i].checked)
			table = true;
	}

	// Horrible little check just to make sure they all have _something_.
	if ( field && table
	  && trim(form.value.value).length
	  && form.op[form.op.selectedIndex].value.length )
	{
		return true;
	}
	else {
		alert('Action not applied. Please enter a value in all fields.');
		return false;
	}
}

// -->