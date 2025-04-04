function load_customers( ) {
  const form = document.getElementById('f1');
  if (!form) {
    alert('No form');
    return;
  }
  $j('#ddmCustomer').load(
    '/includes/_company_ddm.html',
    {
      salesrep_id: (form.search_salesrep_id ? get_ddm_value( form.search_salesrep_id ) : null),
      name: form.search_company_filter.value,
      type: get_value( form.search_type ),
      deleted: get_value( form.deleted ),
      selected_id: get_ddm_value( form.ddmCustomer )
		}
  );
}

function ddmCustomer_onchange(ddm) {
  if(ddm.options[ddm.selectedIndex].value != '') {
    ddm.form.btnFunction.value='Go';
    $j('#ButtonsTop').hide();
    ddm.form.submit();
  }
}

function AddAccountingContact(button) {
  $j('#AccountingContacts').load('_company_accounting_contacts.html', {
    company_id: $j('#company_id').val(),
    user_id: $j('#new_accounting_contact_id').val(),
    action: 'add'
  }, update_event_bindings
  );
}

function DelAccountingContact(button) {
  const user_id = button.getAttribute('data-user_id');
  $j('#AccountingContacts').load('_company_accounting_contacts.html?action=delete', {
    company_id: $j('#company_id').val(),
    user_id: user_id
  }, update_event_bindings
  );
}

window.addEventListener('DOMContentLoaded',function(){
  load_customers();
  $j('#search_company_filter').on('input', load_customers);
  $j('#search_company_filter').on('keydown', function(e){if(e.keyCode == 13){f1.btnFunction.value='Go';this.form.submit();}});
  });
