var theRequest = false;
var force_KB_size = 0;
var force_KB_rate = 0;

function goajax( page ) {
	theRequest = false;

	if ( window.XMLHttpRequest ) {
		theRequest = new XMLHttpRequest();
		//if(theRequest.overrideMimeType) {
			//theRequest.overrideMimeType('text/xml');
		//}
	} else if(window.ActiveXObject) {
		try {
			theRequest = new ActiveXObject("Msxml2.XMLHTTP");
		} catch (e) {
			try {
				theRequest = new ActiveXObject("Microsoft.XMLHTTP");
			} catch (e) {}
		}
	}
	if(!theRequest) {
		alert('Error: could not create XMLHTTP object.');
		return false;
	}

	theRequest.onreadystatechange = updateProgress;
	theRequest.open('GET', page, true );
	theRequest.send('');
}

function updateProgress() {
	if ( ! theRequest )
		return;
	if ( theRequest.readyState == 4 ) {
		if(theRequest.status == 200 ) {
			//var update = theRequest.responseText.split('|');
			//if ( update[1] != 0 ) {
				//total_upload_size = update[1];
			//}
			
			var response = theRequest.responseXML.getElementsByTagName('response')[0];
			var serial = response.getElementsByTagName('serial')[0].firstChild.data;;
			var total_upload_size;
			var totalsize = theRequest.responseXML.getElementsByTagName('totalsize');

			if ( totalsize && totalsize[0].firstChild ) {
				total_upload_size = totalsize[0].firstChild.data;
			} else {
				// chances are the upload hasn't started yet.
				window.setTimeout("goajax('/upload.htm?serial="+serial+"&action=get_progress_and_size');", 1000 );
				return;
			} // end if
			var completed_upload_size;
			if ( response.getElementsByTagName('completedsize') && response.getElementsByTagName('completedsize')[0].firstChild ) {
				completed_upload_size = response.getElementsByTagName('completedsize')[0].firstChild.data;
			} // end if

			var elapsedtime;
			if ( response.getElementsByTagName('elapsedtime') && response.getElementsByTagName('elapsedtime')[0].firstChild ) {
				elapsedtime = response.getElementsByTagName('elapsedtime')[0].firstChild.data;;
			} // end if
			//var numfinishedfiles = update[3];
			//var numtotalfiles = update[4];
			//var	cancelled = update[6];

			//if ( cancelled == 'yes' ) {
				//document.getElementById('UploadFiles').style.display = 'block';
				//document.getElementById('theMeter').style.display = 'none';
				//document.getElementById('uploadCompleteMsg').style.display = 'block';
				//document.getElementById('uploadCompleteMsg').innerHTML = 'Upload cancelled;';
				//return;
			//} // end if
			
			var completeFlag = false;
			if ( total_upload_size == completed_upload_size ) {
				completeFlag = true;
			} // end if
			var progressPercent = total_upload_size ? Math.ceil((completed_upload_size/total_upload_size)*100) : 0;

			$('progressMeterText').innerHTML = progressPercent + '%';
			$('progressMeterBarDone').style.width = parseInt(progressPercent*3.5) + 'px';


			var totaltime = progressPercent ? parseInt((elapsedtime * 100) / progressPercent) : 0;
			var totaltime_forprint = format_timespan_with_unit(totaltime, '&nbsp;');
			var remainingtime_forprint = format_timespan_with_unit(eval(totaltime - elapsedtime), '&nbsp;');
			var elapsedtime_forprint = format_timespan_with_unit(elapsedtime, '&nbsp;');

			var force_MB = total_upload_size > 1048576 ? 1 : 0;
			var total_upload_size_forprint = format_filesize_with_unit(total_upload_size, '&nbsp;', force_MB, force_KB_size);
			var remaining_upload_size_forprint = format_filesize_with_unit(total_upload_size - completed_upload_size, '&nbsp;', force_MB, force_KB_size);
			var completed_upload_size_forprint = format_filesize_with_unit(completed_upload_size, '&nbsp;', force_MB, force_KB_size);

			var transfer_rate = format_filesize_with_unit(completed_upload_size/elapsedtime, '&nbsp;', force_MB, force_KB_rate);

			if ( ( completed_upload_size != '' ) && (completed_upload_size != 0)) {
				//document.getElementById('donet').innerHTML = elapsedtime_forprint;
				//document.getElementById('dones').innerHTML = completed_upload_size_forprint;
				//document.getElementById('donef').innerHTML = numfinishedfiles;

				$('leftt').innerHTML = remainingtime_forprint;
				$('lefts').innerHTML = remaining_upload_size_forprint;
				//document.getElementById('leftf').innerHTML = numtotalfiles - numfinishedfiles;

				$('totalt').innerHTML = totaltime_forprint;
				$('totals').innerHTML = total_upload_size_forprint;
				//document.getElementById('totalf').innerHTML = numtotalfiles;

				$('transferRate').innerHTML = 'Upload Rate: ' + transfer_rate + '/s';
			} // end if

			if ( completeFlag ) {
				$('UploadCompleteDiv').show();
				$('progressMeter').hide();
				$('progressMeterText').innerHTML='';
				$('PendingCompletion').show();
			} else {
				window.setTimeout("goajax('/upload.htm?serial="+serial+"&action=get_progress_and_size');", 1000 );
			} // end if
		} else {
			alert('Error: got a not-OK status code...' + theRequest.status );
		}
	} else {
		//alert( 'Unknown ready state: ' + theRequest.readyState );
	} // end if ready state
}

function startprogress( serial ) {
	// Hide the input form
	$('UploadForm').hide();
	$('progressMeter').show();
	$('progressMeterText').innerHTML = '0%';
	window.setTimeout( "goajax('/upload.htm?serial="+serial+"&action=get_progress_and_size');", 1000 );
}

function format_filesize_with_unit(num,space,forceMB,forceKB) {
	var unit;
	if(   ((num > 999999)  ||  forceMB)   &&   !forceKB) {
		num = num/(1024*1024);
		num = num.toString();

		// note extra escaping necessary since we're printing this JS code from Perl...
		var testnum = num.replace( /^(\d+\.\d).*/, '$1' ); // show 1 decimal place.

		if(testnum == '0.0') {
			testnum = num.replace( /^(\d+\.\d\d).*/, '$1' ); // show 2 decimal places.
		}
		if(testnum == '0.00') {
			testnum = num.replace( /^(\d+\.\d\d\d).*/, '$1' ); // show 3 decimal places.
		}
		num = testnum;

		unit = 'MB';
	} else {
		num = parseInt(num/(1024));
		unit = 'KB';
	}
	return num + space + unit;
}

function format_timespan_with_unit(num,space) {
	//var unit;
	if(num >= (60*60)) {
		var secs_left = num % (60*60);
		var mins_left = secs_left / 60;
		mins_left = mins_left.toString();
		// note extra escaping necessary since we're printing this JS code from Perl...
		mins_left = mins_left.replace( /^(\d+)\..*/, '$1' ); // show no decimal places.
		mins_left = mins_left.replace( /^(\d)$/, '0$1' ); // for single-digits, prepend a zero.

		num = num/(60*60);
		num = num.toString();
		// note extra escaping necessary since we're printing this JS code from Perl...
		num = num.replace( /^(\d+)\..*/, '$1' ); // show no decimal places.

		//num = num + space + 'h' + space + mins_left + space + 'm';
		//space = '';
		//unit = '';
		num = num + ':' + mins_left + ':00';
	} else if(num >= 60) {
		var secs_left = num % 60;
		secs_left = secs_left.toString().replace( /^(\d)$/, '0$1' ); // for single-digits, prepend a zero.

		num = num/60;
		num = num.toString();
		// note extra escaping necessary since we're printing this JS code from Perl...
		num = num.replace( /^(\d+)\..*/, '$1' ); // show no decimal places.
		num = num.replace( /^(\d)$/, '0$1' ); // for single-digits, prepend a zero.

		//num = num + space + 'm' + space + secs_left + space + 's';
		//space = '';
		//unit = '';
		num = '00:' + num + ':' + secs_left;
	} else {
		//unit = 's';
		num = num.toString();
		// note extra escaping necessary since we're printing this JS code from Perl...
		num = num.replace( /^(\d+)\..*/, '$1' ); // show no decimal places.
		num = num.replace( /^(\d)$/, '0$1' ); // for single-digits, prepend a zero.
		num = '00:00:' + num;
	}
	//return num + space + unit;
	return num;
}

function FileUpload(img, file) {  
	var reader = new FileReader();    
	this.ctrl = createThrobber(img);  
	var xhr = new XMLHttpRequest();  
	this.xhr = xhr;  

	var self = this;  
	this.xhr.upload.addEventListener("progress", function(e) {  
			if (e.lengthComputable) {  
			var percentage = Math.round((e.loaded * 100) / e.total);  
			self.ctrl.update(percentage);  
			}  
			}, false);  

	xhr.upload.addEventListener("load", function(e){  
			self.ctrl.update(100);  
			var canvas = self.ctrl.ctx.canvas;  
			canvas.parentNode.removeChild(canvas);  
			}, false);  
	xhr.open("POST", "/paul/demos/resources/webservices/devnull.php");  
	xhr.overrideMimeType('text/plain; charset=x-user-defined-binary');  
	reader.onload = function(evt) {  
		xhr.sendAsBinary(evt.target.result);  
	};  
	reader.readAsBinaryString(file);  
}  
