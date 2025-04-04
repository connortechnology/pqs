function load_host( form, options ) {
  form = $j(form);
  const div = $j('#Results');
  div.html('Loading... Please wait.');
  const p = form.serialize(true);
  if ( options && options.order )
    p = p+'&order='+options.order;

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

function initPage() {
  const tinymce_options = {
      mode : "textareas",
      plugins: "paste",
      theme : "advanced",
      theme_advanced_buttons1 : "bold,italic,underline,strikethrough,|,fontsizeselect,|,bullist,numlist,|,indent,outdent",
      theme_advanced_buttons2 : '',
      theme_advanced_buttons2 : '',
      cleanup : true
    };

    tinyMCE.init(tinymce_options);
}
window.addEventListener('DOMContentLoaded', initPage);

