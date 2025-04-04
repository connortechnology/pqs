function load_results( form, options ) {
	const div = $j('#Results');
	div.html('Loading... Please wait.');
	const p = form.serialize(true);
	if (options && options.order)
		p.order = options.order;
	
  div.load('/licensing/_licenses.html', p,
    function(response, status, xhr){
      update_event_bindings();
      TableKit.load();
    }
  );
} // end function load

function delete_checked() {
  $j('#Results').load('/licensing/_licenses.html?action=Delete',
    { license_id: get_checkbox_values($('f1').elements['license_id']) },
    function(response, status, xhr){
      update_event_bindings();
      TableKit.load();
    }
  );
}
