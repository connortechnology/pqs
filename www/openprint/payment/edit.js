
function calc(element) {
  var form = element.form;
  var value_locked = ( form.value_locked.type == 'checkbox' && form.value_locked.checked ) 
      ||
      ( form.value_locked.type == 'hidden' && form.value_locked.value == 'Y' );
  var amount_locked = ( form.amount_locked.type == 'checkbox' && form.amount_locked.checked ) 
    ||
    ( form.amount_locked.type == 'hidden' && form.amount_locked.value == 'Y' );

  if ( element.name == 'amount' ) {
    if ( form.value.value && value_locked ) {
      form.exchange.value = form.value.value / form.amount.value;
    } else {
      form.value.value = form.amount.value * form.exchange.value;
    }
  } else if ( element.name == 'value' ) {
    if ( form.amount.value && amount_locked ) {
      // if amount is set & locked, then set exchange
      form.exchange.value = form.value.value / form.amount.value;
    } else {
      form.amount.value = form.value.value / form.exchange.value;
    }
  } else if ( element.name == 'exchange' ) {
    if ( form.amount.value && amount_locked ) {
      form.value.value = form.amount.value * form.exchange.value;
    } else if ( form.value.value && value_locked ) {
      form.amount.value = form.value.value / form.exchange.value;
    } else {
      alert('can\'t adjust amount or value because both are locked!');
    }
  } else {
    console.log("Unknown element calcing on", element);
  } // end if element
}

function pay_invoice( invoice_id ) {
  $j.ajax({
    url: '_paid.html',
    data: { 'payment_id': payment_id, 'invoice_id': invoice_id },
    dataType: 'html',
    success: function(html) {
      $j('#Paid').html(html);
      TableKit.reloadTable('paid');
      load_unpaid();
    },
    error: function(e){
      alert('failure to pay');
    }
  } );
}  // end function pay_invoice( invoice_id)

function unpay_invoice( invoice_id ) {
  $j.ajax({
    url: '_unpaid.html',
    data: { 'payment_id': payment_id, 'invoice_id': invoice_id },
    dataType: 'html',
    success: function(html) {
      $j('#Unpaid').html(html);
      TableKit.Sortable.init('unpaid');
      load_paid();
    },
    error: function(e){
      alert('failure to unpay');
    }
  } );
}  // end function unpay_invoice(invoice_id)

function load_paid( ) {
  $j.ajax({
    url: '_paid.html',
    data: { 'payment_id': payment_id },
    dataType: 'html',
    success: function(html) {
      $j('#Paid').html(html);
      TableKit.Sortable.init('paid');
    },
    error: function(e){
      alert('failure to load paid');
    }
  } );
}  // end function load_paid

function load_unpaid( ) {
  $j.ajax({
    url: '_unpaid.html',
    data: { 'payment_id': payment_id },
    dataType: 'html',
    success: function(html) {
      $j('#Unpaid').html(html);
      //TableKit.Sortable.init('Unpaid');
      console.log('reaload Table');
      TableKit.reloadTable('unpaid');
    },
    error: function(e){
      alert('failure to load unpaid');
    }
  } );
}  // end function load_unpaid()
