

function dropable( element, options ) {
}


function dragOver(e) {
    if ( e.stopPropagation ) e.stopPropagation();
    if ( e.preventDefault ) e.preventDefault();
//    e.dataTransfer.dropEffect = 'move';
}
function dragEnter(e) {
    if ( e.stopPropagation ) e.stopPropagation();
    if ( e.preventDefault ) e.preventDefault();
    this.classList.add('dragover');
}
function dragLeave(e) {
    if ( e.stopPropagation ) e.stopPropagation();
    if ( e.preventDefault ) e.preventDefault();
    this.classList.remove('dragover');
}
function handleDrop(e) {
    // this / e.target is current target element.
    if ( e.stopPropagation ) e.stopPropagation(); 
    if ( e.preventDefault ) e.preventDefault();

    if ( e.dataTransfer ) {
        // See the section on the DataTransfer object.
        for(var i=0, num=e.dataTransfer.types.length; i < num; i += 1  ) {
            var item = e.dataTransfer.types.item(i);
            var data = e.dataTransfer.getData(item);
            if ( item == 'application/x-moz-file-promise-dest-filename' ) {
				element.refresh( data );
            } // end if
        } // end for
        if ( e.dataTransfer.files.length ) {
            handleFiles( this, e.dataTransfer.files );
            sendFiles( this.destination, this.onComplete );
        }
    } else {
        alert(e);
    } // end if
	// Doesn't always do this, so do it again
    this.classList.remove('dragover');
    return false;
}

function sendFiles( destination, onComplete  ) {  
    var imgs = document.querySelectorAll(".obj");  

    for (var i = 0, num = imgs.length; i < num; i++) {
        new FileUpload( destination, imgs[i], imgs[i].file, onComplete );
    }
}  

// assumptions: files is not empty
function handleFiles( droparea, files) {  

	var list = droparea.upload_list;
	for (var i = 0; i < files.length; i++) {  
	
		if ( droparea.allowedExtensions ) {
			var ext = (-1 !== files[i].name.indexOf('.')) ? files[i].name.replace(/.*[.]/, '').toLowerCase() : '';
			var allowed = droparea.allowedExtensions;
        for (var i=0; i<allowed.length; i++){
            if (allowed[i].toLowerCase() == ext){ return true;}
        }

        return false;
    }

		var li = document.createElement("li");  
		list.appendChild(li);  

		var img = document.createElement("img");  
		img.src = window.URL.createObjectURL(files[i]);  
		img.li = li;
		img.classList.add("obj");  
		img.file = files[i];  
		img.onload = function(e) {  
			window.URL.revokeObjectURL(this.src);  
		}
		li.appendChild(img);  
		var progress = document.createElement('progress');
		progress.max=100;
		progress.value=0;
		li.appendChild(progress);
		li.progress = progress;

		var info = document.createElement("span");  
		info.innerHTML = files[i].name + ": " + files[i].size + " bytes";  
		li.appendChild(info);  
	}  
} // handleFiles

/*
function update_stats(totaltime, elapsedtime, percent) {
	var totaltime = percent ? parseInt((elapsedtime * 100) / percent) : 0;
	var totaltime_forprint = format_timespan_with_unit(totaltime, '&nbsp;');
	var remainingtime_forprint = format_timespan_with_unit(eval(totaltime - elapsedtime), '&nbsp;');
	var elapsedtime_forprint = format_timespan_with_unit(elapsedtime, '&nbsp;');

	var force_MB = total_upload_size > 1048576 ? 1 : 0;
	var total_upload_size_forprint = format_filesize_with_unit(total_upload_size, '&nbsp;', force_MB, force_KB_size);
	var remaining_upload_size_forprint = format_filesize_with_unit(total_upload_size - completed_upload_size, '&nbsp;', force_MB, force_KB_size);
	var completed_upload_size_forprint = format_filesize_with_unit(completed_upload_size, '&nbsp;', force_MB, force_KB_size);
} // end function
*/

function FileUpload(destination, img, file, oncomplete ) {
    var xhr;
    if (XMLHttpRequest) xhr = new XMLHttpRequest();
    else if ( window.ActiveXObject) xhr = new ActiveXObject("Microsoft.XMLHTTP");
    else { throw new Error("XHR not available. Browser too old."); return false; }

    var self = this;
    this.xhr = xhr;

	this.progress = img.li.progress;

    //this.ctrl = createThrobber( img, img.li );
    this.xhr.upload.addEventListener("progress", function(e) {
            if (e.lengthComputable) {
				self.progress.value=Math.round((e.loaded * 100) / e.total);
				//self.ctrl.update(Math.round((e.loaded * 100) / e.total));
            } else { console.log('not computable'); }
            }, false);

    xhr.upload.addEventListener("load", function(e){
			img.li.progress.value=100;
            //self.ctrl.update(100);
            //var canvas = self.ctrl.ctx.canvas;
            //canvas.parentNode.removeChild(canvas);
            img.li.remove();
			if(oncomplete)oncomplete();
            }, false);
    xhr.open("POST", destination );
    xhr.setRequestHeader("Content-Type", "multipart/form-data; boundary=xxxxxxxx"); // simulate a file MIME POST request.

    var reader = new FileReader();
    reader.onload = function(evt) {
        var body = "--xxxxxxxx\r\n";  
            body += "Content-Disposition: form-data; name=myFile; filename=" + img.file.name + "\r\n";
            body += "Content-Type: application/octet-stream\r\n\r\n";    
            body += evt.target.result + "\r\n";    
            body += "--xxxxxxxx--";
        xhr.sendAsBinary(body);
    };
    reader.readAsBinaryString(file);
} // end function FileUpload
