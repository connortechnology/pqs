JSAN.use('DOM.Events', ':all');
JSAN.use('DOM.Utils');
JSAN.use('List.Utils');
JSAN.use('State.Menu'); // PQS state change context menu.

// Add a second layer to completing a project.
addListener(window, 'load', function () {
    document.getElementById('complete').onclick = function () {
        return confirm('Complete entire project?');
    }
});

// If the browser support XMLHttpRequests we'll set up the more advanced
// interface elements.
if (getRequest()) {
    // We'll load up our status controls.
    addListener(window, 'load', setupControls);
    // And let the user select multiple records to use them on.
    addListener(window, 'load', selectHandler);
    addListener(window, 'load', hideChkBox);
    // And setup a timer to automatically update the states of the services if
    // they're changed since the last check.
    addListener(window, 'load', function () {
        auto_update = window.setTimeout(autoUpdate, 5000)
    });
}
function setProjectServiceState (state) {
    var req = getRequest();
    if (!req) return null; // Request object.
    // TODO: Just serialise the form instead of inventing fancy methods to
    // create the query string.
    var sids = map  ( function (a) { return 'sid='+a.value },
               grep ( function (a) { return(a.type == 'checkbox' && a.checked) },
                   $('project').getElementsByTagName('input') ) );

    var comment = $('c_reason').value;
    setTable($('project'), false);
    if (sids.length < 1) return;
    req.onreadystatechange = function () {
        switch (req.readyState) {
            case 1: // Loading (Open)
                // Until the operation is complete (or timed out) we'll 'lock'
                // the service we're operating on. This will work in
                // conjuction with our collision check.
                // status.style.cursor = mtime.style.cursor = 'wait';
                // status.oncontextmenu = function () { return false; }
            case 2: // Loaded (Sent)
            case 3: // Interactive (Recieving)
                break;
            case 4: // Complete
                if (req.status == 200) { // Success
                    // This should update the selected services and our
                    // overall timestamp.
                    eval(req.responseText);
                    // TODO: We should throw away this request if our return
                    // timestamp is before the current one.
                }
                else {
                    // document.body.innerHTML = req.responseText;
                }
                // 'unlock' the services.
                // status.oncontextmenu = displayControl;
                // status.style.cursor = mtime.style.cursor = '';
        }
    };
    req.open('POST', 'project_service_state', true);
    req.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    req.send('state='+state+';'+sids.join(';')+';comment='+comment);
}
// Set the state and last modified time of a project service.
function setState (id, state, mtime) {
    var record   = document.getElementById(id);
    var modified = record.cells[1];
    var status   = record.cells[2];
    // Set the last modified time.
    setCellText(modified, mtime);
    // Set our current service's state.
    status.className = states[ state ];
    setCellText(status, labels[ state ]);
}

// REMOVED FROM FIRST REVISION
//
// function changeBumpPID (e) {
//     document.getElementById('bump_pid').value = this.textContent;
// }

/*
    Auto Status Update
*/
// Setup a timer to automatically update the states of the services if they're
// changed since the last check.
var auto_update;
function autoUpdate () {
    var req = getRequest();
    if (!req) return null; // Request object.
    req.onreadystatechange = function () {
        switch (req.readyState) {
            case 1: // Loading (Open)
            case 2: // Loaded (Sent)
            case 3: // Interactive (Recieving)
                break;
            case 4: // Complete
                if (req.status == 200) { // Success
                    var response = eval(req.responseText);

                    timestamp = response[0];
                    auto_update = window.setTimeout(autoUpdate, 5000);
                }
                else {
                } // Increment time between checks.
        }
    };
    req.open('GET', 'project_modified?pid='+pid+';timestamp='+timestamp, true);
    req.send(null);
}

/*
    Status Control Panel
*/
// Setup the controls to allow clicking on menu items to change selected
// services/categegories changes.
function setupControls () {
    State.Menu.init(changeStatus);
    // Allow any project data cells to pull up the display.
    var project = document.getElementById('project');
    if (project && project.nodeName == 'TABLE') {
        var rows = project.getElementsByTagName('tr');
        // Add the category lengends to the whole row.
        for (var i=0; i < rows.length; i++) {
            if (rows[i].cells[0].nodeName == "TH") continue;

            // Desite returning false, IE will still display their normal
            // context menu if you use attachEvent.
            rows[i].oncontextmenu = function () { return false; } // Override others.
            addListener(rows[i], 'contextmenu', State.Menu.open);
        }
    }
    // TODO: We don't yet support setting by category. Either that or we can
    // have a click on a category select all in the category.
}

function changeStatus (e) {
    State.Menu.close();
    // Try to set the status on the server side.
    setProjectServiceState(this.value);
}

/*
    Record multi-select (alá file browser).
*/
// This code has been mutated quite a bit by a number of people. It needs to
// be revamped and generalised into something that can be applied to any table
// with callbacks to define custom functionality.
function selectHandler () {
    var table = document.getElementById("project");
    // Clicking anywhere else in the content container clears the selections.
    addListener(document.getElementById("content"), "click", clear);

    var records = table.getElementsByTagName("tr");
    for (var i=0; i < records.length; i++) {
        var rec = records[i];
        // Stop the default text selection events for the table..
        if (rec.attachEvent) {
            rec.onselectstart = function () { return false };
        }
        else if (rec.addEventListener) {
            rec.onmousedown = function () { return false };
        }
        // Only register the selection handlers on the project services.
        if (rec.cells[0].nodeName == "TH") continue;

        addListener(rec, "mousedown", selectRow);
        addListener(rec, "contextmenu", selectRow); // For FF >= 1.0.5
        addListener(rec, "mouseover", function () {
            if (this.className == "selected") return;

            this.oldClass = this.className;
            this.className = "over";
        });
        addListener(rec, "mouseout",  function () {
            if (this.className == "selected") return;

            this.className = this.oldClass;
        });
    }
}

// TODO: Make a cleaner way to find if you clicked on the table or not.
// Clear clears the table when you click on the content div, but not the table.
function clear(e) {
    // Get the target.
    var target = e.target ? e.target : e.srcElement;
    if (target.nodeType == 3) target = target.parentElement; // Safari Bug
    // Check to see if it was the table that was clicked on.
    while (target != this) {
        if (target.nodeName == "TABLE") {
            return;
        }
        target = target.parentNode;
    }
    setTable($("project"), false);
}
// Sets all the rows in the project table class to unselected.
function setTable(table, status) {
    var rows = table.getElementsByTagName("tr");
    for (var i=0; i < rows.length; i++) {
        if (rows[i].cells[0].nodeName == "TH") continue;
        setRow(rows[i], status);
    }
    if (status) table.lastClick = rows[i];
    else        table.removeAttribute("lastClick");
}
// TODO: Add the IDs of select records to an array and use that to unselect
// things. TODO: Add a document wide handler that deselects all when a click
// outside of the table is detected TODO: Shift modifier TODO: Other expected
// behaviours.
function selectRow (e) {
    // We won't interfere with normal anchors.
    var target = e.target ? e.target : e.srcElement;
    if (target.nodeType == 3) target = target.parentElement; // Safari Bug
    if (target.nodeName == 'A') return false;
    var table = this;
    var tr = target;

    while (tr.nodeName != 'TR') tr = tr.parentNode;
    while (table.nodeName != 'TABLE') table = table.parentNode;
    // When context clicking a selected element just let any other events take
    // place. Otherwise treat it as a normal click (then let other events go).
    if (e.type == "contextmenu" || (e.type == "mousedown" && e.button == 2)) {
        e.preventDefault();
        if (tr.className == "selected") return;
    }
    // If we're 'bare' clicking a record, unselect everyone but us.
    if (!(e.shiftKey || e.ctrlKey)) {
        setTable(table, false);
        setRow(tr, true);
    }
    // Just toggle the element's state if the user ctrl-clicks without shift
    // (or even with shift if nothing's ever been selected).
    else if (e.ctrlKey && (!e.shiftKey || !table.lastClick)) {
        setRow(tr, tr.className != "selected");
    }
    // If we shift-click a never selected table it selects all.
    else if (!table.lastClick) { setTable(table, true); }
    // The final case is a ranged select.
    else if (e.shiftKey && table.lastClick) {
        if (table.lastClick.rowIndex < tr.rowIndex) {
            var start = table.lastClick.rowIndex;
            var end   = tr.rowIndex;
        }
        else {
            var start = tr.rowIndex;
            var end   = table.lastClick.rowIndex;
        }
        // If the user isn't holding ctrl, clear all the other ranges before
        // we select ours.
        if (!e.ctrlKey) setTable(table, false);
        // Select the range.
        for (var i=start; i <= end; i++)
            setRow(table.rows[i], true);
    }

    table.lastClick = tr;
}
// Select or deselect a table row.
function setRow (row, state) {
    if (row.cells[0].nodeName == "TH") return;

    row.className = (state) ? "selected" : row.oldClass;
    row.getElementsByTagName("input")[0].checked = state;
}

// Hides the checkboxes on the page if javascript is enabled.
function hideChkBox() {
    var table = document.getElementById("project");
    var chkBoxs = table.getElementsByTagName("input");
    for (var i=0; i < chkBoxs.length; i++) {
        if (chkBoxs[i].type = "checkbox")
            chkBoxs[i].style.display = "none";
    }
}

/*
    Comment Panel: Only basic features supported.
*/
// Treat the comment panel as a FIFO with five positions. Ordered by latest
// modified time first. 'changes' is an array of change arrays, a 'change'
// array is [xid, mtime, uid, username, comment].
function appendChangeLog (changes) {
    var changelog = document.getElementById('changelog');
    var comments  = changelog.getElementsByTagName('p');

    for (var i=0; i < changes.length; i++) {
        var data = changes[i];
        // Pop old comments until there's space for our new one.
        while (comments.length >= 5)
            changelog.removeChild(changelog.lastChild);

        var record = document.createElement('p'); // Container.
        var date = document.createElement('span'); // Modified time.
        date.appendChild( document.createTextNode(data[1]) );
        date.className = 'date';
        date.title     = 'Modified by ' + data[3];
        // Trim large comments (adding an ellipsis if oversized).
        var comment = data[4];
        if (comment.length > 120) {
            comment = comment.substr(0,125) + '…';
        }
        record.appendChild( date );
        record.appendChild( document.createTextNode(' '+comment) ); // Comment.
        changelog.insertBefore(record, changelog.firstChild); // Unshift to stack.
    }
}

//  addListener(window, 'load', function () {
//      var panel = document.getElementById('comments');
//      if (!panel) return;pid cat
//
//      var comments = panel.getElementsByTagName('p');
//      for (var i=0; i < comments.length; i++) {
//          var comment = comments[i];
//
//          if (comment.id && changes[comment.id]) {
//              addListener(comment, 'mouseover', showChanges);
//              addListener(comment, 'mouseout' , unshowChanges);
//          }
//      }
//  });
//
//
// var old_class;
// var old_label;
//
// function showChanges (e) {
//     var trans = changes[ this.id ];
//
//     var state = trans[0];
//
//     for (var i=0; i < trans[1].length; i++) {
//         var record = document.getElementById(trans[1][i]);
//         if (! record) continue;
//
//         var status = record.cells[2];
//
//         old_label = getCellText(status);
//         setCellText(status, labels[ state ]);
//
//         old_class = status.className;
//         status.className = states[ state ] + '-inverse';
//     }
// }
//
// function unshowChanges (e) {
//     var trans = changes[ this.id ];
//
//     for (var i=0; i < trans[1].length; i++) {
//         var record = document.getElementById(trans[1][i]);
//         if (! record) continue;
//
//         var status = record.cells[2];
//
//         setCellText(status, old_label);
//         status.className = old_class;
//     }
// }
//



/*
 HTTP REQUESTS: Somewhat cross browser.
*/
// Returns an XMLHttpRequest object however the browser instantiates it.
function getRequest () {
    var req = null;
    if (window.XMLHttpRequest)
        req = new XMLHttpRequest();
    else if (window.ActiveXObject) { // Micrsoft (two types)
        try { req = new ActiveXObject("Msxml2.XMLHTTP") }
        catch (e) {
            try { req = new ActiveXObject('Microsoft.XMLHTTP') }
            catch (ee) { req = null }
        }
    }
    return req;
}

/*
  OTHER
*/
// Handle the different cell text setting behaviours.
function setCellText(cell, text) {
    cell.textContent = cell.innerText = text;
}
function getCellText(cell) {
    if   (cell.textContent) return cell.textContent;
    else                    return cell.innerText;   // IE
}

function dumpObj (obj) {
    var msg = '';
    for (att in obj) {
        msg += att + ': ' + eval('obj.' + att) + '\n';
        msg += '<br />';
    }
    document.getElementById('foo').innerHTML = msg;
}
