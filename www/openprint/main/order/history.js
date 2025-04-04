function order_action(command) {
  const order_ids = get_value($('f2').order_id);
  if (!order_ids.length) {
    alert('Please select the orders to '+command);
  } else {
    jQuery('#Results').load('_history.html?btnFunction='+command, { order_id: order_ids } );
  }
}
function load_orders() {
  LoadContent('Results','/main/order/_history.html', $j('#f1').serialize());
}
