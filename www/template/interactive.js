var PDF_URL = '/pdf/render';


// All text elements (TODO for now, rework later) update the preview image
// when they change.
Event.observe(window, 'load', function () {
    var form  = $('template');
    update_preview();

    for (var i=0; i < form.elements.length; i++) {
        var elem = form.elements[i];
        if (!elem.name || elem.nodeName.toLowerCase == 'fieldset') continue;

        Event.observe(elem, 'change', auto_preview);
    }
});

function auto_preview () {
    var form = $('template');
    var auto = $('auto_preview');
    if (auto.checked) {
        update_preview();
    }
}
    

function update_preview () {
    var form = $('template');

    var qs       = Form.serialize(form);
    var previews = $('previews').getElementsByTagName('img');

    for (var i = 0; i < previews.length; i++) {
        previews[i].src = PDF_URL + '?' + qs + ';n=' + i;
    }

    return true;
}

function view_pdf (n) {
   // var qs = Form.serialize('template');
    // Do not pass page title in ie 7/8
	var id = $('id').value;
	var offset = $('offset').value;
	var pid = $('pid').value;
	
    var myurl = PDF_URL + '?file_type=pdf;n=' + (n-1) + ';' + 'id=' + id + ';' + 'offset=' + offset + ';' + 'pid=' + pid + ';+pagenumber=1;';
    //window.open(myurl);
}


// Simplitic form clearing TENP
function clear_form (form) {
    for (var i=0; i < form.elements.length; i++) {
        var element = form.elements[i];
        if (!element.name || element.type.toLowerCase() != 'text') continue;

        element.value = '';
    }
}


function open_image_upload (id) {

    window.open(
        '/template/image_upload.html',
        this.id,
        'newWin,left=140,width=500,top=50,height=110'
    );
}


