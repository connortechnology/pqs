// Copyright (c) 2004 Print-Quotes Software Inc. All rights reserved.

service.validate = function (e) {
    var form    = this.form;
    var text    = '';
    var is_auto = !e || e.type == 'load'; // Interactive only on user events.

	if ( form.rdbBusinessCardSlot && ! get_rdb_value(form,'rdbBusinessCardSlot')  ) {
		text += 'Please select an option for business card slit location.\n';

	}
	if ( form.rdbBusinessCardStyle && ! get_rdb_value(form,'rdbBusinessCardStyle')  ) {
		text += 'Please select an option for business card style.\n';

	}

    if (text) {
        if (!is_auto) {
            alert('Your form is incomplete:\n\n' + text);
        }
        return false;
    }

    return true;
} 

  
