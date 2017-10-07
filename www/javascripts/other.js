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
