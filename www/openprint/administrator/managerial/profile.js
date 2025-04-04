
function check_field( element ) {
	var form = element.form;
	var matches;
	if ( matches = element.name.match( /^\w+\-(\d+)$/ ) ) {
		var id = matches[1];
		if ( 
			element_changed( form.elements['required-'+id] ) ||
			element_changed( form.elements['viewable-'+id] ) ||
			element_changed( form.elements['on_registration-'+id] ) ||
			element_changed( form.elements['name-'+id] ) ||
			element_changed( form.elements['type-'+id] ) ||
			element_changed( form.elements['values-'+id] ) 
		   ) {
			$j('#field_'+id).addClass('changed');
		} else {
			$j('#field_'+id).removeClass('changed');
		} // end if
	} else {
		alert('Not matched' + element.name);
	} // end if
} // end function check_field 

function newField( ) {
	jQuery.ajax( '_field_tr.html', { 
			data: { 
				action: 'Add'
			} } ).done( function( html ) {
        var fields = $j('#fields');
        if ( fields) {
          fields.append(html);
        } else {
          console.log("No fields");
        }
			});
} // end function newField

function copyField( id ) {
	var form = jQuery('#f1')[0];
	jQuery.ajax( '_field_tr.html', { 
			data: { 
				field_id: id,
				action: 'Copy',
				required: get_value(form.elements['required-'+id])
			} } ).done(
			function( transport ) {
				$j('#field_'+ id).append(transport.responseText);
			}
	);
}
function delField( id ) {
	jQuery.ajax('_field_tr.html', 
		{ 
			data: { 
				field_id: id,
				action: 'Delete'
			},
		} ).done(
			function( html ) {
				if ( html ) {
					alert( html );
				} else {
					var tr = $j('#field_'+id);
          tr.remove();
				} // end if
			}
	);
}

function upField( field_id ) {
	jQuery('#fields').load('_user_fields_tbody.html', { action: 'up', field_id: field_id } );
} // end function upField

function setup_sortable() {
Sortable.create( 'fields', {
    tag: 'tr',
    constraint: 'vertical',
    onUpdate: function( container ) {
        new Ajax.Updater( 'fields', '_company_fields_tbody.html', { parameters: { update: Sortable.serialize(container) }, evalScripts: true } );
      }
  } );
} // end function setup_sortable

function save_all() {
	var form = $j('#f1');
	if ( !form ) {
		console.log("No form found for f1");
		return;
	}
	form = form[0];
	form.elements['action'].value='Save';
	form.submit();
}
