tinyMCE.init( {
	mode: "none",
	plugins: "paste",
	theme : "advanced",
	theme_advanced_buttons1 : "bold,italic,underline,strikethrough,|,justifyleft,justifycenter,justifyright,justifyfull,|,fontsizeselect,bullist,numlist,outdent,indent,cleanup,html",
	theme_advanced_buttons2 : '',
	theme_advanced_buttons3 : ''
} );

var current_editor;
function tinymce_on( id ) {
	if ( current_editor ) {
		tinymce.execCommand( 'mceToggleEditor', false, current_editor );
	} // end if
	current_editor = id;
	tinymce.execCommand( 'mceToggleEditor', true, id );
} // end function tinymce_on

function job_popup( job_id ) {
	popup_window( '/employee/production/_job_popup.html', 'schedule_id='+job_id, {width:575, height:525,closeCallback: job_popup_close} );
} // end function job_popup

function job_popup_close() {
	tinymce.EditorManager.execCommand( 'mceRemoveControl', true, 'comment' );
	tinymce.EditorManager.execCommand( 'mceRemoveControl', true, 'stock' );
	current_editor = null;
	return true;
} // end function job_popup_close

var job_popup_options = {
			mode: "textareas",
			editor_selector : "mce",
			plugins: "paste",
			theme : "advanced",
			theme_advanced_buttons1 : "bold,italic,underline,strikethrough,|,justifyleft,justifycenter,justifyright,justifyfull,|,fontsizeselect,bullist,numlist,outdent,indent,cleanup,html",
			theme_advanced_buttons2 : '',
			theme_advanced_buttons3 : ''
};

//var dropfunction = function(el){
var dropfunction = function(el, ui) {
if ( 0 ) {
	new Ajax.Request( '_drop.json', {
			method: 'post',
			parameters: 'ul_id='+this.id+'&'+$j(this).sortable('serialize'),
			evalScripts: true
			} );
}
	new Ajax.Request( '_drop.json', { method: 'post', parameters: { ul_id: el.id, services: Sortable.serialize(el) }, evalScripts: true } );
}

function setup_drops( ) {
if ( 0 ) {
	$j('.PressColumn ul').sortable({
			items: '> li',
			handle: '.Company',
			update: dropfunction,
			connectWith: '.PressColumn ul',
			dropOnEmpty: true

		}).disableSelection();
} else {
	for ( var i = 0; i < drops.length; i += 1 ) {
		if ( $(drops[i]) ) {
			Sortable.create(drops[i], {dropOnEmpty:true,containment:drops,constraint:false, onUpdate:dropfunction });
		} // end if
	} // end foreach id in drops
}
} // end function setup_drops

function setup_dates( ) {
	var re = /^JumpToDate(\d*)$/;
	var dates = $$('span.DueDate');
	for ( var i = 0; i < dates.length; i+= 1 ) {
		var match = dates[i].id.match(re);
		if ( match.length ) {
			Calendar.setup({
inputField	:	"ScheduleDate-"+match[1],		// id of the input field
ifFormat		:	"%Y-%m-%d",		// format of the input field
daFormat		:	"%b %d",
align			:	"Tl",
showsTime		:	false,			// will display a time selector
displayArea :	'JumpToDate'+match[1],
singleClick :	false,			// double-click mode
onClose	 :	setduedate
});
} // end if match
} // end for each date id
} // end function setup_dates()

function toggle_lock( id, img ) {
	if(img.src=='/images/small-locked.gif'){
		img.src='/images/small-unlocked.gif';
		new Ajax.Request('_li_change.json', { parameters: { id: id, locked: false } } );
	}else{
		img.src='/images/small-locked.gif';
		new Ajax.Request('_li_change.json', { parameters: { id: id, locked: true } } );
	};
}

function setduedate( date ) {
	var form = date.params.inputField.form;
	var name = date.params.inputField.name;
	var reg = /ScheduleDate-(\d*)/;
	var ar = reg.exec( name );
	new Ajax.Request( '_li_change.json', { parameters: { action: 'setduedate', schedule_id: ar[1], duedate: date.params.inputField.value } } );
	calendar.hide();
}

function approve_job( ul_id, job_id ) {
	new Ajax.Updater( ul_id, '_ul.html', { parameters: { schedule_id: job_id, action:'approve'}, evalScripts: true } );
} // end function approve_job(job_id)

function remove_job( job_id ) {
	//if ( confirm('Are you sure?') ) {
		new Ajax.Request('_li_change.json', {parameters: {schedule_id:job_id, action: 'RemoveJob'}, evalScripts: true } );
	//} // end if
} // end function remove_job
function split_job( ul_id, job_id ) {
	new Ajax.Updater( ul_id, '_ul.html', { parameters: { schedule_id: job_id, action:'split'}, evalScripts: true } );
} // end function split_job
function up_job( job_id ) {
	new Ajax.Request( '/employee/production/_li_change.json', {parameters: { schedule_id:job_id, action: 'Up' }, evalScripts: true } );
} // end function up_job
function down_job( job_id ) {
	new Ajax.Request( '/employee/production/_li_change.json', {parameters: { schedule_id:job_id, action: 'Down' }, evalScripts: true } );
} // end function up_job

function update_runtime( ddm ) {
	ddm.form.runtime.value = ddm.form.runtime_hours.value + ':' + ddm.form.runtime_minutes.value + ':' + ddm.form.runtime_seconds.value;
}

function start_job( job_id ) {
	new Ajax.Request('_li_change.json', { parameters: { schedule_id: job_id, action: 'start' } } );
} // end function start_job
function stop_job( job_id ) {
	new Ajax.Request('_li_change.json', { parameters: { schedule_id: job_id, action: 'stop' } } );
} // end function stop_job
