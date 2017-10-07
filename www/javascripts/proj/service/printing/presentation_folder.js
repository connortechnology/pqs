// Copyright (c) 2004 Print-Quotes Software Inc. All rights reserved.

Event.observe(window, 'load', function (e) {
    var form  = $('f1');
    var elems = $A(
        [ $A(form.rdbPocketSize), $A(form.rdbGlued) ]
    ).flatten().compact();

    for (var i=0; i < elems.length; i++)
       Event.observe(elems[i], 'click', flat_size);

	for (var i=0, elems = form['template']; i < elems.length; i++)
		Event.observe(elems[i], 'change', check_template);
	check_template();

});

// It has been decided that we will not allow
// custom pocket sizes for Standard PF's
function check_template () {
    var form = $('f1');
	var template = get_rdb_value(form, 'template');

	var elem = form['rdbPocketSizeCustom'];

	if (template == 'PresentationFolderCustomDieCut') {
		elem.disabled = false;
		elem.parentNode.style.display = '';
	} else {
		elem.disabled = true;
		elem.parentNode.style.display = 'none';
	}

}

function flat_size (e) {
    var form     = Event.element(e).form;
	var template = get_rdb_value(form, 'template');

	if ( template != 'PresentationFolderCustomDieCut' ) {
		var width  = form.final_width.value * 2;
		var height = parseFloat(form.final_height.value);

		if ( width && height ) {

            var pocketSize = get_rdb_value(form, 'rdbPocketSize');
			height += (pocketSize * 1);

            if (form.rdbGlued[0].checked) width += 1.25;

			form.flat_width.value = width;
			form.flat_height.value = height;
		}
	}
    return true;
}
