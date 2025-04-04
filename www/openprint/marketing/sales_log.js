	function add_new() {
    const form = $j('#add'); 
    $j.ajax('/marketing/_sales_log_line.html', form.serialize())
				.done( function(data){
          console.log(data);
          $j('#sales_log_body').prepend(data);
					//$('sales_log_body').insert({ top: response.responseText} );
					SortableTable.load();
				}
        ).fail(function() {
          alert( "error" );
        });
	}
	function load_users( user_ddm, company_id ) {
		if ( ! user_ddm ) {
			alert("Bad ddm");
			return;
		}
		new Ajax.Updater( user_ddm, '/includes/_users.html', { 
				parameters: { company_id: company_id },
				onSuccess: function() {
					load_results();
				}
			}
		);
		
	}
	function load_results() {
		$j('#Results').load('_sales_log.html', $j('#f1').serialize() );
	}
	function check_form( form ) {
/*
		if ( ! ( 
					get_ddm_value(form.called_on_year),
					get_ddm_value(form.called_on_month),
					get_ddm_value(form.called_on_day),
					get_ddm_value(form.called_on_hour),
					get_ddm_value(form.called_on_minute),
		) ) {
			alert('
		}
*/
	}
