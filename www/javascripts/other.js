//Copyright (c) 2000 direction inc. All rights reserved.
//Any reuse of this or any code in any of direction's solutions is strictly prohibited without written consent.
//Please refer to "www.directionsolutions/legal.html" for further important copyright & licensing information.

function pageCode() {
    // Fix for IE to allow the :hover psuedoelement on input
    // type="(submit|button|reset)" and button.
    if (document.all && document.getElementById) {
        // Given a node, sets or removes the "over" class on all type of input
        // buttons. This is a fix for IE which doesn't support the :hover
        // pseudoelement on anything other than anchors.
        var f = function (node) {
            if (node.nodeName == 'BUTTON' ||
                node.nodeName == 'INPUT'  && ( node.type == 'submit' ||
                                                 node.type == 'button' ||
                                                 node.type == 'reset'  )) {
                node.onmouseover = function() { this.className +=" over"; } // Append class.
                node.onmouseout  = function() { this.className  = this.className.replace(" over", ""); }
            }
        }

        // Traverse the DOM tree and apply our mouse(over|out)s.
        var root = document.getElementById("content");
        if (root)
            mapTree(f, root);
    }
}

// Maps a function onto the nodes of a DOM tree (depth-first).
function mapTree (f, tree) {
    // Run on current element.
    f(tree);
    // Run on all child elements (type == 1)
    for (var i=0; i < tree.childNodes.length; i++) {
        var node = tree.childNodes[i];
        if (node.nodeType == 1)
            mapTree(f, node);
    }
}


var fmChange = 0;
function fmCheck( form ) {
	if ( fmChange == 1 ) {
		if ( confirm("Are you sure you want to leave this record without saving your changes?") ) {
			fmChange == 0;
            form.submit();
			return true;
		}
	} else if (fmChange == 2) {
		fmChange = 0;
		if ( confirm("Are you sure you want to delete this record?") ) {
            form.submit();
			return true;
		}
	} else if (fmChange == 3) {
		fmChange = 0;
		if ( confirm("Are you sure you want to save your changes?") ) {
            form.submit();
			return true;
		}
  } else if (fmChange == 4) {
		fmChange = 0;
		if ( confirm("Are you sure you want to delete this customer?\n You will also be deleting all of the customer's users, projects, project contents and transactions, RMA, orders quotes and inventory.") ) {
            form.submit();
			return true;
		}
	} else {
		form.submit();
		return true;
	}
	return false;
}

function addCheck(formName) {
	if (fmChange == 1) {
		if (confirm("Are you sure you want to create a new record, without saving your changes")) {
			clearForm(formName);
		}
	}
	else {
		clearForm(formName);
	}
}

function clearForm(what) {
	for (var i=0, j=what.elements.length; i<j; i++) {
		myName = what.elements[i].type;

		if (myName != undefined) {	// Check for Undefined because Fieldset Tags
			if (myName.indexOf('checkbox') > -1 || myName.indexOf('radio') > -1) {
				what.elements[i].checked = "";
			}
			if (myName.indexOf('hidden') > -1 || myName.indexOf('password') > -1 || myName.indexOf('text') > -1) {
				 what.elements[i].value = "";
			}
			if (myName.indexOf('select') > -1) {
				for (var k=0, l=what.elements[i].options.length; k<l; k++) {
					what.elements[i].options[k].selected = 0;
					what.elements[i].options[0].selected = 1;
				}
			}
		}
	}
}



/*
 EVENT HANDLING : Very simplistic, ignores many know cases.
*/

// Cross-browser (sorta) (W3C and MS event models) event listening.
function addEvent(target, action, callback, bubble) {
    if (target.addEventListener)
        target.addEventListener(action, callback, bubble);
    else if (target.attachEvent)
        target.attachEvent('on' + action, function () {
            callback.apply(target, [window.event])
        });
}

// Cross-browser (W3C and MS event models) event removal.
function removeEvent (target, action, callback, bubble) {
    // W3C Model (Mozilla, Safari, Opera)
    if (target.removeEventListener )
        target.removeEventListener (action, callback, bubble);
    // Microsoft model (Win IE5+)
    else if (target.detachEvent) {
        target.detachEvent('on' + action, function () {
            callback.apply(target, [window.event])
        });
    }
}

function get_rdb_value( form, rdbName ) {
    for ( var x = 0; x < form.elements[rdbName].length; x ++ ) {
        if ( form.elements[rdbName][x].checked == true ) {
            return form.elements[rdbName][x].value;
        } 
    } 
    return '';
} 
function update_event_bindings() {
  console.log('update_event_bindings()');
  document.querySelectorAll("select[data-on-change], input[data-on-change]").forEach(function attachOnChangeThis(el) {
    const fnName = el.getAttribute("data-on-change");
    if ( !window[fnName] ) {
      console.error("Nothing found to bind to " + fnName + " on "+el.name);
      return;
    }
    el.onchange = window[fnName].bind(el, el);
    //console.log('setting onchange on '+el.name+' to '+fnName);
  });

  document.querySelectorAll("select[on_change]").forEach(function attachOnChangeThis(el) {
    const fnName = el.getAttribute("on_change");
    if ( !window[fnName] ) {
      console.error("Nothing found to bind to " + fnName + " on "+el.name);
      return;
    }
    el.onchange = window[fnName].bind(el, el);
    //console.log('setting onchange on '+el.name+' to '+fnName);
  });
  document.querySelectorAll('select[data-on-change-this]').forEach(function(el) {
    const fnName = el.getAttribute('data-on-change-this');
    if ( !window[fnName] ) {
      console.error('Nothing found to bind to ' + fnName);
      return;
    }
    //console.log("Setting up onchangefor " + el.name + " to " + fnName);
    el.onchange = window[fnName].bind(el, el);
  });
  document.querySelectorAll('select[on_change_this]').forEach(function(el) {
    const fnName = el.getAttribute('on_change_this');
    if ( !window[fnName] ) {
      console.error('Nothing found to bind to ' + fnName);
      return;
    }
    //console.log("Setting up onchangefor " + el.name + " to " + fnName);
    el.onchange = window[fnName].bind(el, el);
  });

  document.querySelectorAll("input[data-on-input]").forEach(function(el) {
    const fnName = el.getAttribute("data-on-input");
    if ( !window[fnName] ) {
      console.error("Nothing found to bind to " + fnName);
      return;
    }
    el.oninput = window[fnName].bind(el, el);
  });

  document.querySelectorAll("input[data_on_input]").forEach(function(el) {
    const fnName = el.getAttribute("data_on_input");
    if ( !window[fnName] ) {
      console.error("Nothing found to bind to " + fnName);
      return;
    } else {
      //console.log("Setting oninput for "+el.name+" to "+fnName);
    }
    el.oninput = window[fnName].bind(el, el);
  });

  document.querySelectorAll("input[on_input_this]").forEach(function(el) {
    const fnName = el.getAttribute("on_input_this");
    if ( !window[fnName] ) {
      console.error("Nothing found to bind to " + fnName);
      return;
    }
    //console.log("Setting up oninput for " + el.name + " to " + fnName);
    el.oninput = window[fnName].bind(el, el);
  });
  document.querySelectorAll("input[data_oninput_this]").forEach(function(el) {
    const fnName = el.getAttribute("data_oninput_this");
    if ( !window[fnName] ) {
      console.error("Nothing found to bind to " + fnName);
      return;
    }
    //console.log("Setting up oninput for " + el.name + " to " + fnName);
    el.oninput = window[fnName].bind(el, el);
  });

  document.querySelectorAll('button[data-on-click-this], input[data-on-click-this]').forEach(function(el) {
    const fnName = el.getAttribute('data-on-click-this');
    if ( !window[fnName] ) {
      console.error('Nothing found to bind to ' + fnName);
      return;
    }
    //console.log("Setting up onclick for " + el.name + " to " + fnName);
    el.onclick = window[fnName].bind(el, el);
  });

  document.querySelectorAll('textarea[on_keyup_this]').forEach(function(el) {
    const fnName = el.getAttribute('on_keyup_this');
    if ( !window[fnName] ) {
      console.error('Nothing found to bind to ' + fnName);
      return;
    }
    //console.log("Setting up onkeyup_this for " + el.name + " to " + fnName);
    el.onclick = window[fnName].bind(el, el);
  });
  document.querySelectorAll('button[on_click_this], input[on_click_this]').forEach(function(el) {
    const fnName = el.getAttribute('on_click_this');
    if ( !window[fnName] ) {
      console.error('Nothing found to bind to ' + fnName);
      return;
    }
    console.log("Setting up on_click_this for " + el.name + " to " + fnName);
    el.onclick = window[fnName].bind(el, el);
  });

  document.querySelectorAll('button[data_onclick_this]').forEach(function(el) {
    const fnName = el.getAttribute('data_onclick_this');
    if ( !window[fnName] ) {
      console.error('Nothing found to bind to ' + fnName);
      return;
    }
    //console.log("Setting up onclick for " + el.name + " to " + fnName);
    el.onclick = window[fnName].bind(el, el);
  });

  document.querySelectorAll("[on_click]").forEach(function attachOnClick(el) {
    const fnName = el.getAttribute('on_click');
    if (!window[fnName]) {
      console.error('Nothing found to bind to ' + fnName + ' on element ' + el.name);
      return;
    }

    //console.log('Setting for on_click to ' + fnName + ' for element ' + el.getAttribute('id'));
    el.onclick = function(ev) {
      window[fnName](ev);
    };
  });
  document.querySelectorAll("[data-on-click]").forEach(function attachOnClick(el) {
    const fnName = el.getAttribute('data-on-click');
    if (!window[fnName]) {
      console.error('Nothing found to bind to ' + fnName + ' on element ' + el.name);
      return;
    }

    //console.log('Setting for data-on-click to ' + fnName + ' for element ' + el.getAttribute('id'));
    el.onclick = function(ev) {
      window[fnName](ev);
    };
  });
console.log('done');
}
