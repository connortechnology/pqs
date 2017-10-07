//Copyright (c) 2004 Print-Quotes Software Inc. All rights reserved.

service.validate = function (e) {
    var form    = this.form;
    var text    = '';
    var is_auto = !e || e.type == 'load'; // Interactive only on user events.

	if (form.txtDieWidth && ! (0 < parseFloat(form.txtDieWidth.value) )) {
		text += "Please enter the width of the image.\n";
	}
	if (form.txtDieHeight && ! (0 < parseFloat(form.txtDieHeight.value))) {
		text += "Please enter the height of the image.\n";
	}
	var dieTypes = document.getElementsByName('rdbDieType');
	var dieChoosen = false;
	for (var i=0; i < dieTypes.length; i++) {
		if (dieTypes[i].checked) {
			dieChoosen = true;
		}
	}
	if (! dieChoosen) {
		text +="Please choose the type of die.\n";
	}
	var materials = document.getElementsByName('rdbMaterialType');
	var materialChoosen = false;
	for (var i=0; i < materials.length; i++) {
		if (materials[i].checked){
			materialChoosen = true;
		}
	}
	if (! materialChoosen) {
		text+= "Please choose the type of material,\n";
	}

    if (text) {
        if (!is_auto) {
            alert('Your form is incomplete:\n\n' + text);
        }
        return false;
    }

    return true;
}

