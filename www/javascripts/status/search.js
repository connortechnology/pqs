JSAN.use('DOM.Events', ':all');
JSAN.use('DOM.Utils');
JSAN.use('List.Utils');
JSAN.use('State.Menu');  // PQS state change context menu.
// Make the 'clear' form button actually clear the form.
addListener(window, 'load', function () {
    $('clear').onclick = function (e) {
        var form = $('search');
        var inputs = form.getElementsByTagName('input');
        for (var i=0; i < inputs.length; i++) {
            var t = inputs[i];
            if (t.type == 'text') t.value = '';
        }
    };
});

// Create a list of the projects our search returned so we know who to update.
var pids = new Array();
addListener(window, 'load', function () {
    var t  = $('results'); if (!t) return;
    var rs = t.getElementsByTagName('tbody')[0].getElementsByTagName('tr');
    for (var i=0; i < rs.length; i++)
        pids.push( rs[i].id );
});
// If the browser support XMLHttpRequests we'll set up the more advanced
// interface elements.
if (getRequest()) {
    auto_update = window.setTimeout(autoUpdate, 5000)
}
// Setup a timer to automatically update the status of the service type
// categories and update them if they've changed since the last check.
var auto_update;
function autoUpdate () {
    if (!pids.length) return; // No projects? No need to check.
    var req = getRequest(); // Request object.
    if (!req) return null;
    var query = map( function (a) { return "pid="+a }, pids).join(';');
    req.onreadystatechange = function () {
        switch (req.readyState) {
            case 1: // Loading (Open)
            case 2: // Loaded (Sent)
            case 3: // Interactive (Recieving)
                break;
            case 4: // Complete
                if (req.status == 200) { // Success
                    var response = eval(req.responseText);
                    auto_update = window.setTimeout(autoUpdate, 5000);
                }
                else {
                    // document.body.innerHTML = req.responseText;
                } // Increment time between checks.
        }
    };
    req.open('GET', 'results_modified?'+query+';timestamp='+timestamp, true);
    req.send(null);
}
// Change the status of a single status cell (composite id of "$pid-$cat_id");
function updateStatus (id, state) {
    var cell = $(id);
    cell.className = state;
    setCellText(cell, state.substr(0,1).toUpperCase());
}


// Bind the control panel to the search results table.
addListener(window, 'load', setupControls);
function setupControls (e) {
    var results = $('results'); if (!results) return;
    // Setup the state menu and bind it's controls to change the status.
    State.Menu.init(changeStatus);
    // Bind the panel to the results table.
    var data = results.getElementsByTagName('tbody')[0].getElementsByTagName('td');
    for (var i=0; i < data.length; i++) {
        var datum = data[i];
        // TODO: Safari doesn't support cellIndex.
        if (datum.cellIndex > 2 && datum.className != 'x') {
            // Set pointer ('hand' in IE) cursor here.

            // Create a hover effect (IE only supports :hover on anchors).
            datum.onmouseover = invert;
            // Both click and mouseout are needed as a mouseout doesn't fire
            // when the control is clicked and the menu closes.
            datum.onmouseout = revert;
            datum.onclick    = revert;
            // Display the control panel.
            datum.oncontextmenu = function () { return false; } // No default.
            addListener(datum, 'contextmenu', openControl);
        }
    }
}
// Invert and revert status elements.
function invert () {
    this.oldClass = this.className;
    this.className = this.className + '-inverse';
}
function revert (e) { this.className = this.oldClass; }
// Open the control and remember who opened us.
function openControl (e) {
    State.Menu.current = this.id;
    State.Menu.open(e);
    return false;
}
function changeStatus (e) {
    State.Menu.close();
    var ids = State.Menu.current.split('-');
    setCategoryState(ids[0], ids[1], this.value, $('c_reason').value);
    return false;
}
function setCategoryState (project, category, state, comment) {
    var req = getRequest();
    if (!req) return null; // Request object.
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
    req.open('POST', 'project_category_state', true);
    req.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    req.send('pid='+project+';cat='+category+';state='+state+';comment='+comment);
}

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

