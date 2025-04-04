
window.addEventListener('DOMContentLoaded',initPage);

function initPage() {
  if (window.L) {
    /* Get location from Owner */
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

    for (const [host_id, host] of Object.entries(hosts)) {
      const l = locations[host.location_id];

    marker = L.marker([l.latitude, l.longitude], {draggable: 'true'});
    marker.addTo(map);
      /*
    marker.on('dragend', function(event) {
      const marker = event.target;
      const position = marker.getLatLng();
      const form = document.getElementById('f1');
      form.elements['latitude'].value = position.lat;
      form.elements['longitude'].value = position.lng;
    });
    */
    }
    map.invalidateSize();
  } // end if window.L
} // end DOMContentLoaded
