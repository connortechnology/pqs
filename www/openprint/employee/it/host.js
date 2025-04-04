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
  $j('#notifications').load( '_notifications.html', {
    action: 'delete',
    notification_ids: notification_ids.val(),
    user_id: user_id
  });
}

function add_subnet( id ) {
  $j.get('_subnet.html', { host_id: $j('#host_id').val(), action: 'add subnet' }, function(data) {
    $j('#Interfaces').append(data);
  });
}

function add_interface( id ) {
  $j.get('_interface.html', { host_id: $j('#host_id').val(), action: 'add interface' }, function(data) {
    $j('#Interfaces > tbody').append(data);
  });
}

function delete_interface( id ) {
  jQuery.ajax( '_host_actions.json', { data: { interface_id: id, action: 'delete interface' } } );
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

function add_information() {
  jQuery('#information').load( '_information.html', {
    action: 'add',
    host_id: $j('#host_id').val(),
    name: jQuery('#new_info_name').val(),
    value: jQuery('#new_info_value').val()
    }, update_event_bindings );
}
function del_information(button) {
  jQuery('#information').load( '_information.html', {
    action: 'delete', host_id: $j('#host_id').val(),
    info_id: button.getAttribute('data-id')
  }, update_event_bindings);
}

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


function updateMarker() {
  const latitude = document.getElementById('newMonitor[Latitude]').value;
  const longitude = document.getElementById('newMonitor[Longitude]').value;
  console.log("Updating marker at ", latitude, longitude);
  const latlng = new L.LatLng(latitude, longitude);
  marker.setLatLng(latlng);
  map.setView(latlng, 8, {animation: true});
  setTimeout(function() { map.invalidateSize(true); }, 100);
}

function updateLatitudeAndLongitude(latitude, longitude) {
  const form = document.getElementById('f1');
  form.elements['latitude'].value = latitude;
  form.elements['longitude'].value = longitude;
  updateMarker(latitude, longitude);
}

function getLocation() {
  if ('geolocation' in navigator) {
    navigator.geolocation.getCurrentPosition((position) => {
      updateLatitudeAndLongitude(position.coords.latitude, position.coords.longitude);
    });
  } else {
    console.log("Geolocation not available");
  }
}

window.addEventListener('DOMContentLoaded',initPage);

function initPage() {
  var tinymce_options = {
    mode : "textareas",
    plugins: "paste",
    theme : "advanced",
    theme_advanced_buttons1 : "bold,italic,underline,strikethrough,|,fontsizeselect,|,bullist,numlist,|,indent,outdent",
    theme_advanced_buttons2 : '',
    theme_advanced_buttons2 : '',
    cleanup : true
  };

  tinyMCE.init(tinymce_options);

  if (window.L) {
    const form = document.getElementById('f1');
    const latitude = form.elements['latitude'].value;
    const longitude = form.elements['longitude'].value;
    map = L.map('map', {
      center: L.latLng(GEOLOCATION_LATITUDE, GEOLOCATION_LONGITUDE),
      zoom: 8,
      onclick: function() {
        alert('click');
      }
    });
    L.tileLayer(GEOLOCATION_TILE_PROVIDER, {
      attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/">OpenStreetMap</a> contributors, <a href="https://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>, Imagery © <a href="https://www.mapbox.com/">Mapbox</a>',
      maxZoom: 18,
      id: 'mapbox/streets-v11',
      tileSize: 512,
      zoomOffset: -1,
      detectRetina: true,
      accessToken: GEOLOCATION_ACCESS_TOKEN
    }).addTo(map);
    marker = L.marker([latitude, longitude], {draggable: 'true'});
    marker.addTo(map);
    marker.on('dragend', function(event) {
      const marker = event.target;
      const position = marker.getLatLng();
      const form = document.getElementById('f1');
      form.elements['latitude'].value = position.lat;
      form.elements['longitude'].value = position.lng;
    });
    map.invalidateSize();
  } // end if window.L
} // end DOMContentLoaded
