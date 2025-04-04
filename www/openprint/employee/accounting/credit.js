function set_credit(src_id,dst_id) {
  var form = $('f1');
  var fields = [ 'denydays', 'warndays','limit','hold','downpayment','cod'];
  for ( var i= 0; i < fields.length; i += 1 ) {
    var field = fields[i];
    if ( ! form.elements[field+'-'+dst_id] ) {
      alert('No element for dest ' + field);
    } else if ( ! form.elements[field+'-'+src_id] ) {
      alert('No element for src ' + field);
    } // end if
    //$(field+'-'+dst_id).value = $(field+'-'+src_id).value;
    if ( form.elements[field+'-'+dst_id].length ) {
      set_rdb_value( form.elements[field+'-'+dst_id], get_rdb_value( form.elements[field+'-'+src_id] ) );
    } else {
      form.elements[field+'-'+dst_id].value = form.elements[field+'-'+src_id].value;
    }
  } // end for
} // end function set_credit

function swap_credit(src_id,dst_id) {
  var form = $('f1');
  var fields = [ 'denydays', 'warndays','limit','hold','downpayment','cod'];
  for ( var i= 0; i < fields.length; i += 1 ) {
    var field = fields[i];
    if ( ! form.elements[field+'-'+dst_id] ) {
      alert('No element for dest ' + field);
    } else if ( ! form.elements[field+'-'+src_id] ) {
      alert('No element for src ' + field);
    } // end if
    //$(field+'-'+dst_id).value = $(field+'-'+src_id).value;
    if ( form.elements[field+'-'+dst_id].length ) {
      var value = get_rdb_value(form.elements[field+'-'+dst_id]);
      set_rdb_value(form.elements[field+'-'+dst_id], get_rdb_value(form.elements[field+'-'+src_id]));
      set_rdb_value(form.elements[field+'-'+src_id], value);
    } else {
      var value = form.elements[field+'-'+dst_id].value;
      form.elements[field+'-'+dst_id].value = form.elements[field+'-'+src_id].value;
      form.elements[field+'-'+src_id].value = value;
    }
  } // end for
} // end function set_credit

function click_cancel() {
	var order_ids = [];
	$j.each($j("input[name='PAID']:checked"), function(){            
			order_ids.push($j(this).val());
			});
	if ( !order_ids.length ) {
		alert("You must select an order to cancel");
	} else if ( confirm("Are you sure you want to cancel these " + order_ids.length + "Orders?") ) {
		var form = $('f1');
		form.btnFunction.value = 'Cancel';
		form.submit();
	}
} // end function click_cancel

function click_pay() {
  var order_ids = [];
  $j.each($j("input[name='PAID']:checked"), function(){
      order_ids.push($j(this).val());
      });
  if ( ! order_ids.length ) {
    alert("You must select an order to pay");
		return;
	}
	var form = $('f1');
	form.btnFunction.value = 'Pay';
	form.submit();
} // end function click_cancel
