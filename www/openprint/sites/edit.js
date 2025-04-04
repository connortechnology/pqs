function load_host() {
  const form = $j('#PopupForm');
  const div = $j('#Results');
  div.html('Loading... Please wait.');
  const p = form.serialize(true);
  console.log(p);

  div.load('/sites/_host_results.html', p);
} // end function load

function check_inputs( form ) {
  return true;
} //  end function check_inputs

function del_allocation( host_id ) {
  new Ajax.Updater( 'Hosts', '_hosts.html',
    {
      parameters: {
        site_id: $('site_id').value,
        host_id: host_id,
        action: 'delete'
      }
    });
} // end function del_allocation

function add_allocation(host_id) {
  new Ajax.Updater('Hosts', '_hosts.html',
    {
      parameters: {
        action: 'allocate',
        host_id: host_id,
        site_id: $('site_id').value
      }
    });
  popupWin.close();
}
