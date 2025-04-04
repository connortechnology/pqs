// Globally define the icons used in the bootstrap-table top-right toolbar
var icons = {
  paginationSwitchDown: 'fa-solid fa-caret-square-down',
  paginationSwitchUp: 'fa-solid fa-caret-square-up',
  export: 'fa-solid fa-download',
  refresh: 'fa-solid fa-retweet',
  autoRefresh: 'fa-solid fa-clock-o',
  advancedSearchIcon: 'fa-solid fa-chevron-down',
  toggleOff: 'fa-solid fa-toggle-off',
  toggleOn: 'fa-solid fa-toggle-on',
  columns: 'fa-solid fa-th-list',
  fullscreen: 'fa-solid fa-arrows-alt',
  detailOpen: 'fa-solid fa-plus',
  detailClose: 'fa-solid fa-minus'
};

function load_results( form, options ) {
	const div = $j('#Results');
	div.html('Loading... Please wait.');
  if (!form) form = $j('#f1');
	const p = form.serialize(true);
	if (options && options.order)
		p.order = options.order;
	
  div.load('_list.html', p,
    function(response, status, xhr){
      update_event_bindings();
    $j('#tasksTable').bootstrapTable({icons: icons});
    }
  );
} // end function load

function delete_checked() {
  $j('#Results').load('_list.html?action=Delete',
    { task_id: get_checkbox_values($('f1').elements['task_id']) },
    function(response, status, xhr){
      update_event_bindings();
    $j('#tasksTable').bootstrapTable({icons: icons});
    }
  );
}

document.addEventListener('DOMContentLoaded', function(){
  load_results();
});
