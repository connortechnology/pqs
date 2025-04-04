function add_notification() {
  var user_id = $j('#new_notification_id').val();
  if ( user_id ) { 
    var notification_ids = $j('#notification_ids');
    if ( notification_ids.val() ) {
      notification_ids.val( notification_ids.val()+","+user_id );
    } else {
      notification_ids.val( user_id );
    }
    $j('#notifications').load( '_notifications.html', { action: 'add', notification_ids: notification_ids.val() } );
  } else { 
    alert('Select a user');
  }
}
function del_notification(user_id) { 
    var notification_ids = $j('#notification_ids');
  $j('#notifications').load( '_notifications.html', { action: 'delete', notification_ids: notification_ids.val(), user_id: user_id } );
}

function delete_interface( id ) {
  jQuery.ajax( '_host_actions.json', { data: { interface_id: id, action: 'delete interface' } } );
}

function add_interface( id ) {
  jQuery.ajax( '_host_actions.json', { data: { host_id: id, action: 'add interface' } } );
}

function check_inputs( form ) {
  if ( ! form.elements['hostname'].value ) {
    if ( confirm('You should really enter something for the hostname field.  It does not have to be the actual hostname of the device, but can be something to help you identify it. Click Ok to save anyway.') ) {
      return true;
    } else {
      return false;
    }
  }
  return true;
} //  end function check_inputs

function toggle_monitored(e) {
  if ( e.value == 1 ) {
    $('offline_seconds').show();
    $('notify_frequency').show();
  } else {
    $('offline_seconds').hide();
    $('notify_frequency').hide();
  }
  var checkboxes = $j('.option_monitor input').prop("checked", e.value == '1' ? true : false );
}
var tinymce_options = {
    mode : "textareas",
    plugins: "paste",
    theme : "advanced",
theme_advanced_buttons1 : "bold,italic,underline,strikethrough,|,fontsizeselect,|,bullist,numlist,|,indent,outdent",
theme_advanced_buttons2 : '',
theme_advanced_buttons2 : '',
cleanup : true
};

tinyMCE.init( tinymce_options );
