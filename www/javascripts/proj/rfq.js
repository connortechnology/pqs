function create_second_ddm (formName) {
	var form = $(formName);
   	var args = new Array();
	args.length = 0;

	for (var i = 0;  i < form.elements['suppliers'].options.length; i++) {
		if ( form.elements['suppliers'].options[i].selected ) 
			args[args.length] = form.elements['suppliers'].options[i].value;
	}

	jsrsExecute('/jsrs', cbFillResults, 'eprint::docket::RFQ_calc', args);
}

function cbFillResults (results) {
   	var opts = results.evalJSON(true);
	var form = $('f1');

	for (var i = form.elements['users'].options.length-1; i >= 0; i--) {
		form.elements['users'].options[i] = null;
	}

	var options = form.elements['users'].options;
	for (var n=0; n < opts.length; n = n+2)  {
		options[options.length] = new Option (opts[n+1], opts[n]);
	}
}
