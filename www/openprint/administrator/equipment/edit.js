function body_onLoad() {
  $j('select.chosen').chosen({disable_search_threshold: 10});
}
function search_change(ddm) {
  if(ddm.options[ddm.selectedIndex].value != ''){ddm.form.btnFunction.value='';fmCheck(ddm.form);};
}

function add_stock_setting( stock_id ) {
  new Ajax.Updater('Stocks', '_stocks.html', {
    parameters: {
      action:'add',
      equipment_id: equipment_id,
      stock_id: stock_id
    },
    onLoading:function(){ $('Stocks').innerHTML='Loading...'; },
    onSuccess: function(){
      new Ajax.Updater('StockSettings', '_stock_settings.html', { parameters: { equipment_id: equipment_id } } );
    }
  }
  );
  const tr = $('stock_'+stock_id);
  if (tr) { tr.parentNode.removeChild(tr) };
} // end function add_stock_setting

function filter_onChange( element, id, selected ) {
  const form = element.form;

  const parameters = new Hash();
  ['Manufacturer','Group','Name','Finish','Colour','Weight'].each(function(name,index){
    const ddm = form.elements[name+id];
    if (!ddm) ddm = form.elements['ddm'+name+id];
    if (ddm) {
      ddm.disabled = true;
      parameters.set(ddm.name, get_ddm_value( ddm ) );
    } // end if
  } // end for each
  );

  parameters.set('form',form.name);
  parameters.set('selected',selected);
  new Ajax.Request( '/administrator/equipment/_stock_filters.json', { method: 'post', parameters: parameters, evalScripts: true } );

} // end function Name_onChange()

function calc(formName) {
  new Ajax.Updater('Stocks','/administrator/equipment/_stocks.html', {
    onLoading:function(){ $('Stocks').innerHTML='Loading...'; },
    parameters:Form.serialize($(formName))});
  //evalScripts:true,
}

function del_operator(user_id) {
  $j.get('/administrator/equipment/_operators.html',
    { action: 'delete', equipment_id: equipment_id, user_id: user_id },
    function(data) {
      $j('#Operators').html(data);
      update_event_bindings();
    }
  );
} // end function del_operator

function add_operator(user_id) {
  $j.get('/administrator/equipment/_operators.html',
    { action: 'add', equipment_id: equipment_id, user_id: user_id },
    function(data) {
      $j('#Operators').html(data);
      update_event_bindings();
    }
  );
}
function delete_spec( id ) {
  new Ajax.Request('/administrator/equipment/_specification.html?action=delete&amp;id='+id, { onSuccess: function(){var tr = $('S'+id); tr.parentNode.removeChild(tr);SortableTable.load();} } );
}
function copy_spec( id ) {
  new Ajax.Request('/administrator/equipment/_specification.html?action=copy&amp;id='+id, { onSuccess: function(response){ $('S'+id).insert( {after: response.responseText } ); SortableTable.load();} } );
}
function delete_fold_spec( id ) {
  new Ajax.Request('/administrator/equipment/_fold_specification.html?action=delete&amp;id='+id, { onSuccess: function(){var tr = $('FoldSpecification-'+id); tr.parentNode.removeChild(tr);} } );
} // end function delete_fold_spec

function toggle_service_prices() {
  const toggle = $j('#toggle_service_prices');
  const div = $j('#show_service_prices');
  if (div.html()) {
    toggle.html('+');
  } else {
    div.html('Loading...');
    toggle.html('-');
  }
  div.load('/administrator/equipment/_service_prices.html?equipment_id='+$j('#ddmEquipment').val()+'&hide='+(toggle.html() == '-' ?'0':'1'),null, function(){
      update_event_bindings();
      });
}
function toggle_specifications() {
  $j('#show_specifications').toggle();
}

function load_folds() {
  const folds = $j('#Folds');
  const type = document.getElementById('type');
  folds.html('Loading...');
  folds.load('_fold.html', {equipment_id: type.form.ddmEquipment.value, type: type.value} );
}
