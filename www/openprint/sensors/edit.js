function delete_input( id ) {
  new Ajax.Request('_input.html?action=delete&amp;id='+id, {
    onSuccess: function(){
      var tr = $('i'+id);
      tr.parentNode.removeChild(tr);
      SortableTable.load();
    }
  } );
}
function copy_input( id ) {
  new Ajax.Request('_input.html?action=copy&amp;id='+id, {
    onSuccess: function(response){
      $('i'+id).insert( {after: response.responseText } );
      SortableTable.load();
    }
  } );
}
function add_input(s_id) {
  new Ajax.Request('_input.html?action=add&sensor_id='+s_id, {
    onSuccess: function(response){
      $('inputs_body').insert({top: response.responseText} );
    }
  } );
} // end function add_input
