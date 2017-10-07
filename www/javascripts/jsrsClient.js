//
//	jsrsClient.js - javascript remote scripting client include
//
//	Author:	Brent Ashley [jsrs@megahuge.com]
//
//	make asynchronous remote calls to server without client page refresh
//
//	see license.txt for copyright and license information
/*
see history.txt for full history
2.0	26 Jul 2001 - added POST capability for IE/MOZ
*/
// callback pool needs global scope
var jsrsContextPoolSize = 0;
var jsrsContextMaxPool  = 20;
var jsrsContextPool     = new Array();
var jsrsBrowser         = jsrsBrowserSniff();
var jsrsPOST            = false;
var jsrsCallback        = '';
var jsrsParameters      = new Array();
var jsrsFunc            = '';
var jsrsVisibility      = '';
var jsrsPage            = '';
var jsrsTimer           = '';
//	method functions are not privately scoped
//	because Netscape's debugger chokes on private functions
function contextCreateContainer( containerName ){
	// creates hidden container to receive server data
	var container;
	switch( jsrsBrowser ) {
		case 'NS':
			container = new Layer(100);
			container.name = containerName;
			container.visibility = 'hidden';
			container.clip.width = 100;
			container.clip.height = 100;
			break;
		case 'IE':
			document.body.insertAdjacentHTML( "afterBegin", '<span id="SPAN' + containerName + '"></span>' );
			var span = document.all( "SPAN" + containerName );
			var html = '<iframe name="' + containerName + '" src=""></iframe>';
			span.innerHTML = html;
			span.style.display = 'none';
			container = window.frames[ containerName ];
			break;

		case 'MOZ':
			var span = document.createElement('SPAN');
			span.id = "SPAN" + containerName;
			document.body.appendChild( span );
			var iframe = document.createElement('IFRAME');
			iframe.name = containerName;
			span.appendChild( iframe );
			container = iframe;
			break;
	}
	return container;
}
function contextPOST( rsPage, func, parms ){
	var d = new Date();
	var unique = d.getTime() + '' + Math.floor(1000 * Math.random());
	var doc = this.container.document;
	doc.open();
	doc.write('<html><body>');
	doc.write('<form name="jsrsForm" method="post" target="" ');
	doc.write(' action="' + rsPage + '?U=' + unique + '">');
	doc.write('<input type="hidden" name="C" value="' + this.id + '" />');
	// func and parms are optional
	if (func != null){
	doc.write('<input type="hidden" name="F" value="' + func + '" />');
		if (parms != null){
			if (typeof(parms) == "string"){
				// single parameter
				doc.write( '<input type="hidden" name="P0" '
								 + 'value="[' + jsrsEscapeQQ(parms) + ']" />');
			} else {
				// assume parms is array of strings
				for( var i=0; i < parms.length; i++ ){
					doc.write( '<input type="hidden" name="P' + i + '" '
									 + 'value="[' + jsrsEscapeQQ(parms[i]) + ']" />');
				}
			} // parm type
		} // parms
	} // func
	doc.write('</form></body></html>');
	doc.close();
	doc.forms['jsrsForm'].submit();
}
function contextGET( rsPage, func, parms ){
	// build URL to call
	var URL = rsPage;
	// always send context
	URL += "?C=" + this.id;
	// func and parms are optional
	if (func != null){
		URL += "&F=" + escape(func);
		if (parms != null){
			if (typeof(parms) == "string"){
				// single parameter
				URL += "&P0=[" + escape(parms+'') + "]";
			} else {
				// assume parms is array of strings
				for( var i=0; i < parms.length; i++ ){
					URL += "&P" + i + "=[" + escape(parms[i]+'') + "]";
				}
			} // parm type
		} // parms
	} // func
	// unique string to defeat cache
	var d = new Date();
	URL += "&U=" + d.getTime();

	// make the call
	switch( jsrsBrowser ) {
		case 'NS':
			this.container.src = URL;
			break;
		case 'IE':
			this.container.document.location.replace(URL);
			break;
		case 'MOZ':
			this.container.src = '';
			this.container.src = URL;
			break;
	}

}
// constructor for context object
function jsrsContextObj( contextID ){

	// properties
	this.id = contextID;
	this.busy = true;
	this.callback = null;

	// methods
	this.GET = contextGET;
	this.POST = contextPOST;
	this.getPayload = contextGetPayload;
	this.getContent = contextGetContent;
	this.setVisibility = contextSetVisibility;
	this.container = contextCreateContainer( contextID );
}
function contextGetPayload(){

	switch( jsrsBrowser ) {
		case 'NS':
			return this.container.document.forms['jsrs_Form'].elements['jsrs_Payload'].value;
		case 'IE':
			return this.container.document.forms['jsrs_Form']['jsrs_Payload'].value;
		case 'MOZ':
			return window.frames[this.container.name].document.forms['jsrs_Form']['jsrs_Payload'].value;
	}
    return null;
}
function contextGetContent() {
	switch( jsrsBrowser ) {
		case 'NS':
			return this.container.document;
		case 'IE':
			return this.container.document/body;
		case 'MOZ':
			return window.frames[this.container.name].document.body;
	}
    return null;
}
function contextSetVisibility( vis ){
	switch( jsrsBrowser ) {
		case 'NS':
			this.container.visibility = (vis)? 'show' : 'hidden';
			break;
		case 'IE':
			document.all("SPAN" + this.id ).style.display = (vis)? '' : 'none';
			break;
		case 'MOZ':
			document.getElementById("SPAN" + this.id).style.visibility = (vis)? '' : 'hidden';
			this.container.width = (vis)? 250 : 0;
			this.container.height = (vis)? 100 : 0;
			break;
	}
}

function jsrsGetContextID(){
	var contextObj;
	for (var i = 1; i <= jsrsContextPoolSize; i++){
		contextObj = jsrsContextPool[ 'jsrs' + i ];
		if ( contextObj && ! contextObj.busy ) {
			contextObj.busy = true;
			return contextObj.id;
		}
	}
	// if we got here, there are no existing free contexts
	if ( jsrsContextPoolSize <= jsrsContextMaxPool ){
		// create new context
		var contextID = "jsrs" + (++jsrsContextPoolSize);
		jsrsContextPool[ contextID ] = new jsrsContextObj( contextID );
		return contextID;
	} else {
		alert( "jsrs Error:	context pool full" );
		return null;
	}
}
function jsrsExecute( rspage, callback, func, parms, visibility ) {
    if (jsrsTimer) {
        clearTimeout(jsrsTimer);
        if (   jsrsPage != rspage
            || callback != callback
            || func     != func     ) {
            jsrsRealExecute();
        }
    }
    jsrsPage       = rspage;
    jsrsCallback   = callback;
    jsrsFunc       = func;
    jsrsParameters = parms;
    jsrsVisibility = visibility;
    jsrsTimer = setTimeout('jsrsRealExecute()', 1000);
}
function jsrsRealExecute () {
	var contextObj      = jsrsContextPool[ jsrsGetContextID() ];
	contextObj.callback = jsrsCallback;
	var vis = jsrsVisibility == null ? false : jsrsVisibility;
	contextObj.setVisibility( vis );
	if ( jsrsPOST && (jsrsBrowser == 'IE' || jsrsBrowser == 'MOZ' ))
		contextObj.POST( jsrsPage, jsrsFunc, jsrsParameters );
    else
		contextObj.GET( jsrsPage, jsrsFunc, jsrsParameters );
    document.body.style.cursor = 'wait !important';
	return contextObj.id;
}
function jsrsLoaded( contextID ){
    document.body.style.cursor = 'default';
	// get context object and invoke callback
	var contextObj = jsrsContextPool[ contextID ];
	if ( !contextObj ) {
		alert("No Context Object for ID: " + contextID );
        return null;
	}
	if (contextObj.callback != null) {
		var payLoad     = jsrsUnescape(contextObj.getPayload());
		var payLoadList = payLoad.split("|");
		if (payLoadList.length == 1) {
            var smallSub = payLoadList[0].substr(0, 6);
            if (smallSub == 'fatal~' || smallSub == 'debug~') {
                if (smallSub == 'fatal~') {
                    alert("Error!\n" + payLoadList[0].substr(6));
                }
                else if (smallSub == 'debug~') {
                    error_return('<pre>' + payLoadList[0].substr(6) + '</pre>');
                }
                contextObj.callback = null;
                contextObj.busy     = false;
                return null;
            }
        }
		contextObj.callback( payLoad, contextID );
	}
	// clean up and return context to pool
	contextObj.callback = null;
	contextObj.busy     = false;
    return true;
}
function jsrsError( contextID, str ){
	alert( unescape(str) );
	jsrsContextPool[ contextID ].busy = false
	jsrsContextPool[ contextID ].callback = null;
}
function jsrsEscapeQQ( thing ){
    return thing;
}
function jsrsUnescape( str ) {
	// payload has slashes escaped with whacks
	return str;
}
function jsrsBrowserSniff(){
	if (document.layers){
		return "NS";
	}
	if (document.all) {
		return "IE";
	}
	if (document.getElementById){
		return "MOZ";
	}
	return "OTHER";
}
/////////////////////////////////////////////////
//
// user functions
function jsrsArrayFromString( s, delim ){
	// rebuild an array returned from server as string
	// optional delimiter defaults to ~
	var d = (delim == null)? '~' : delim;
	return s.split(d);
}
function jsrsDebugInfo(){
	// use for debugging by attaching to f1 (works with IE)
	// with onHelp = "return jsrsDebugInfo();" in the body tag
	var doc = window.open().document;
	doc.open;
	doc.write( 'Pool Size: ' + jsrsContextPoolSize + '<br /><font face="arial" size="2"><strong>' );
	for( var i in jsrsContextPool ){
		var contextObj = jsrsContextPool[i];
		doc.write( '<hr>' + contextObj.id + ' : ' + (contextObj.busy ? 'busy' : 'available') + '<br />');
		doc.write( contextObj.container.document.location.pathname + '<br />');
		doc.write( contextObj.container.document.location.search + '<br />');
		doc.write( '<table border="1"><tr><td>' + contextObj.container.document.body.innerHTML + '</td></tr></table>' );
	}
	doc.write('</table>');
	doc.close();
	return false;
}
// Opens a new window with the full JSRS (should be a stack trace) as the
// window contents.
function error_return (stack_trace) {
    var debug_window = window.open();
    var document     = debug_window.document;
    document.write(stack_trace);
    document.close();
    return false;
}
