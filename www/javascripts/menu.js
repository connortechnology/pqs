// windows.attachEvent may create memory leak

// Fix the IE "windowed element" problem for the navigation menus. IE draws
// select elements ignoring z-indexes, which causes selects to be 'above'
// drop-down menus. This creates a 'shield' iframe for each menu dropdown area
// which negates the issue.
if (window.attachEvent) window.attachEvent("onload", function () {
	if (!document.getElementById('nav')) return true;

	var menus = document.getElementById('nav').getElementsByTagName('ul');

	for (var i=0; i < menus.length; i++) {
        var shield = document.createElement('iframe');
        shield.style.width  = menus[i].offsetWidth  + "px";
        shield.style.height = menus[i].offsetHeight + "px";	

        shield.style.position = 'absolute';
        shield.style.left     = 0;
        shield.style.top      = 0;
        shield.style.zIndex   = 0;
        shield.style.filter   = 'mask()';
        // progid:DXImageTransform.Microsoft.Alpha(style=0,opacity=0)';

        menus[i].insertBefore(shield, menus[i].firstChild);
    }
});


// Simulate the CSS :hover pseudo element for the navigation menus.
if (window.attachEvent) window.attachEvent("onload", function () {
	if (!document.getElementById('nav')) return true;

	var menu_items = document.getElementById('nav').getElementsByTagName('li');
	for (var i=0; i < menu_items.length; i++) {
        var menu = menu_items[i];

		menu.onmouseover = function () { this.className+=" sfhover"; };

		menu.onmouseout = function () {
			this.className = this.className.replace(new RegExp(" sfhover\\b"), "");
		};
	}
});


// Fix for IE to allow the :hover psuedoelement on input
// type="(submit|button|reset)" and button.
if (window.attachEvent) window.attachEvent("onload", function () {

    if (! (document.all && document.getElementById) ) return;

    // Given a node, sets or removes the "over" class on all type of input
    // buttons. This is a fix for IE which doesn't support the :hover
    // pseudoelement on anything other than anchors.
    var f = function (node) {
        if (node.nodeName == 'BUTTON' ||
            node.nodeName == 'INPUT'  && ( node.type == 'submit' ||
                                             node.type == 'button' ||
                                             node.type == 'reset'  )) {
            node.onmouseover = function() { this.className += " over"; } // Append class.
            node.onmouseout  = function() { this.className  = this.className.replace(" over", ""); }
        }
    }

    // Traverse the DOM tree and apply our mouse(over|out)s.

    // used for Main
    var root = document.getElementById("wrapper2")

    // used for Admin
    if (!root) root = document.getElementById("content")

    if (root) { mapTree(f, root); }
});

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


