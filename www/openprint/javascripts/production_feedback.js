var clock;
var weekday = new Array("Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday");
var monthname = new Array("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec");

function start_clock( form, service_id ) {
} // end function start_clock

function tick( service_id ) {
	var time;
	if ( ! $('ending-'+service_id).innerHTML ) {
		time = new Date();
	} else {
		time = new Date( $('ending-'+service_id).innerHTML );
	} // end if
	var hours = time.getHours();
	var minutes = time.getMinutes();
	minutes=((minutes < 10) ? "0" : "") + minutes;
	var seconds = time.getSeconds() +1;
	seconds=((seconds < 10) ? "0" : "") + seconds;
	$('ending-'+service_id).innerHTML = monthname[time.getMonth()] + " " + time.getDate() + ', ' + time.getFullYear() + ' ' + hours + ":" + minutes + ":" + seconds;
	clock = setTimeout( "tick( '"+service_id+"');", 1000 );
	update_duration( service_id );
} // end function


function update_duration(service_id ) {
	var start = new Date( $('starting-'+service_id).innerHTML );
	var end = new Date( $('ending-'+service_id).innerHTML );
	var difference = parseInt( ( end - start ) / 1000 );
	var days = parseInt(difference/(60*60*24));
	difference -= days * ( 60*60*24 );
	var hours = parseInt( difference/(60*60) );
	difference -= hours * (60*60);
	var minutes = parseInt( difference/60 );
	difference -= minutes * 60;
	minutes = ((minutes < 10) ? "0" : "") + minutes;

	var seconds = parseInt(difference);
	seconds = ((seconds < 10) ? "0" : "") + seconds;

	var html = '';
	if ( days ) {
		html += days+'days ';
	} // end if
	html += hours + ':' + minutes + ':' + seconds;

	$('duration-'+service_id).innerHTML = html;
} // end function update_duration

function stop_onclick( service_id ) {
	if ( ! clock ) {
		var time = new Date();
		var hours = time.getHours();
		var minutes = time.getMinutes();
		minutes=((minutes < 10) ? "0" : "") + minutes;
		var seconds = time.getSeconds() +1;
		seconds=((seconds < 10) ? "0" : "") + seconds;
		$('starting-'+service_id).innerHTML = monthname[time.getMonth()] + " " + time.getDate() + ', ' + time.getFullYear() + ' ' + hours + ":" + minutes + ":" + seconds;
		$('ending-'+service_id).innerHTML = monthname[time.getMonth()] + " " + time.getDate() + ', ' + time.getFullYear() + ' ' + hours + ":" + minutes + ":" + seconds;
		$('stopc').innerHTML = 'Stop';
		clock = setTimeout( "tick( '"+service_id+"');", 1000 );
	} else {
		if ( ! $('comment-'+service_id).value ) { 
			alert('Please enter a comment for this time period.');
			return;
		} // end if

		clearTimeout( clock );
		clock = null;
		update_duration( service_id );

		var project_id =  $('project_id-'+service_id).value;
		var comment = $('comment-'+service_id).value;
		var starting = $('starting-'+service_id).innerHTML;
		var ending = $('ending-'+service_id).innerHTML;

		$('ProductionFeedback-'+service_id).innerHTML = 'Please wait. Loading...';
		new Ajax.Updater( 'ProductionFeedback-'+service_id, '_production_feedback.html', { 
			method: 'get',
			parameters: {
				project_id: project_id,
				service_id: service_id,
				comment:	comment,
				starting_on:	starting,
				ending_on:		ending,
				action:		'add'
			}
		} );
	} // end if clockis going
} // end function stop_onclick( service_id )
