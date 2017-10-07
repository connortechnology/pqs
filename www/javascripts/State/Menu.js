JSAN.use("DOM.Events", ":all");
/* TODO
 - Add attributes for refering to the comment and current state.
 - Put the positioning stuff in it's own lib (if even still needed with the
   cross browser stuff in DOM.Events).
 - Clean up in general.
*/
if (typeof(State) == "undefined") State = {};
if (!State.Menu) {
    State.Menu = {};
    State.Menu.VERSION = "0.01a";
    State.Menu.EXPORT  = [];
    // Make sure the state menu is there on window load.
    addListener(window, "load", function () {
    });

    // Open the state menu. If a mouse even fired it place it within the
    // window near the pointer.
    State.Menu.open = function (e) {
        var control = State.Menu.element;
        // Clear any messages left over from last time.
        var text = document.getElementById("c_reason").value ="";
        // Keep the control box within the window with one corner always (5,5)
        // px from the mouse position at the time of the context click.
        if (e && e.type.match(/(mouse|context)/)) {
            var posx = e.pageX;
            var posy = e.pageY
            if (e.clientX + control.offsetWidth >= getWindowWidth())
                posx -= control.offsetWidth + 5;
            else
                posx -= 5;
            if ( (e.clientY + control.offsetHeight >= getWindowHeight())
              && (e.clientY - control.offsetHeight > 0) )
            {
                posy -= control.offsetHeight + 5;
            }
            else {
                posy -= 5;
            }
            // Display the control at it's calculated location.
            control.style.left    = posx + "px";
            control.style.top     = posy + "px";
        }
        control.style.display = "block";
        // If the user clicks anywhere outside the control, close it.
        State.Menu.close_event =
            addListener(document, "mousedown", State.Menu.close);
        return false; // Needed to stop built-in context menu.
    };
    // Close the control panel (and remove the close events).
    State.Menu.close = function (e) {
        State.Menu.element.style.display = "none";
        removeListener(State.Menu.close_event);
    };
    // First run setup and event handling; bind to the HTML portion of the
    // menu. Takes a callback to fire on a menu item click.
    State.Menu.init = function (callback) {
        // Make sure we"re in the document.
        State.Menu.element = document.getElementById("controls");
        var control = State.Menu.element;
        if (!control || control.nodeName != "DIV")
            throw "No state menu found in document.";
        // Events in the box, stay in the box.
        addListener(control, "mousedown", function (e) {e.stopPropagation()});
        addListener(control, "contextmenu", function (e) {e.preventDefault()});
        // Change the status when an input/label is clicked. Also handle hover
        // over menu options (can't use :psuedo element due to IE)
        var labels = control.getElementsByTagName("label");
        for (var i = 0; i < labels.length; i++) {
            var label = labels[i];

            // Don't bind to our comment's label.
            if ( label.htmlFor ) continue;
            // Hover when we"re over (see above note on IE).
            addListener(label, "mouseover", function() {
                this.oldClass = this.className;
                this.className = this.className+"-inverse";
            });

            var revert = function () { this.className = this.oldClass; };
            // Mouseout handles hover, click when the control closes.
            addListener(label, "mouseout", revert);
            addListener(label, "click", revert);

            // Clicking the input changes the status.
            var input = label.getElementsByTagName("input")[0];
            if (label.attachEvent) { // Partial fix for IEs label issue.
                // Worked untill IE 6.0.29
                // label.attachEvent("onclick", input.click);
                // Compose a closure (as we can't just use a closure due to
                // lack of lexical variables).
                label.attachEvent("onclick", click(input));
            }
            addListener(input, "click", callback);
        }
    };
}
function click (input) { return function () { input.click() } }

/*
 POSITIONING: Cross-browser
*/
// Determine the height of the users window (not document).
function getWindowHeight () {
    if (self.innerHeight)
        return self.innerHeight;
    else if (document.documentElement.clientHeight)   //IE 6
        return document.documentElement.clientHeight;
    else
        return document.body.clientHeight;
}
// Determine the width of the users window (not document).
function getWindowWidth () {
    if (self.innerWidth)
        return self.innerWidth;
    else if (document.documentElement.clientWidth)   //IE 6
        return document.documentElement.clientWidth;
    else
        return document.body.clientWidth;
}
// The outer bounds of the object within the document, represented by the
// (x,y) co-ordinate pairs of the top-left and bottom-right corners.
function findBounds(obj) {
    var x = findPosX(obj);
    var y = findPosY(obj);
    return [ [x, y], [x + obj.offsetWidth, y + obj.offsetHeight] ];
}
// The (x,y) co-ordinates of the top-left corner of the passed object within
// the document (not the window).
function findPos(obj) {
    return [findPosX(obj), findPosY(obj)];
}
// The left edge of the object within the document.
function findPosX(obj) {
    var curleft = 0;
    if (obj.offsetParent) {
        while (obj.offsetParent) {
            curleft += obj.offsetLeft
            obj = obj.offsetParent;
        }
    }
    else if (obj.x)
        curleft += obj.x;
    return curleft;
}
// The top edge of the object within the document.
function findPosY(obj) {
    var curtop = 0;
    if (obj.offsetParent) {
        while (obj.offsetParent) {
            curtop += obj.offsetTop
            obj = obj.offsetParent;
        }
    }
    else if (obj.y)
        curtop += obj.y;
    return curtop;
}


