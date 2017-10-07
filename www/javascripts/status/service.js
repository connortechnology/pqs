JSAN.use('DOM.Events', ':all');
function XAction (xid, state, mtime, uid, name, comment) {
    // TODO: Can we loop over args to do this trivial crap?
    this.id      = xid;
    this.state   = new State (state);
    this.date    = mtime;
    this.uid     = uid;
    this.name    = name;
    this.comment = comment;
}
function State (state) {
    var type = ['none', 'open', 'wait', 'wait', 'wait', 'done'];
    var label = ['  ', 'Started', 'Paused', 'Waiting on Customer', 'Waiting for Approval', 'Completed'];
    this.id = state;
    this.name = label[state];
    this.type = type[state];
    return this;
}
function appendLog (xactions) {
    var log = document.getElementById('log');
    for (var i=0; i < xactions.length; i++) {
        var xaction = xactions[i];
        // If the transaction ID already exists we're out of sync and the log
        // should not be added.
        if (document.getElementById(xaction.id))
            continue;
        var trans = document.createElement('div');
        trans.id = xaction.id; // XID
        // State change information bar.
        var info = document.createElement('div');
        info.className = 'header';
        trans.appendChild(info);
        // Our three info headings.
        var headers = ['name', 'status', 'date'];
        for (var j=0; j < headers.length; j++) {
            var name   = headers[j];
            var header = document.createElement('div');
            header.className = name;

            if (name == 'status')
                header.className += ' ' + xaction.state.type;
            // Create the label and the fill in the data it applies to.
            var label = document.createElement('strong');
            label.appendChild(document.createTextNode(
                name.substr(0,1).toUpperCase() +
                name.substr(1, name.length)    + ': '
            ));
            header.appendChild(label);
            header.appendChild(document.createTextNode(
                name == 'status' ? xaction.state.name : xaction[name]
            ));
            info.appendChild(header);
        }
        trans.appendChild(info);
        if (xaction.comment) {
            var comment = document.createElement('p');
            comment.appendChild(document.createTextNode(xaction.comment));
            trans.appendChild(comment);
        }
        // Our transactions get inserted as the last element before the user
        // state change section (always the last element).
        log.insertBefore(trans, document.getElementById('state_change'));
    }
}

/*
    Auto Status Update
*/
// If the browser support XMLHttpRequests we'll auto-update the page.
if (getRequest()) {
    // And setup a timer to automatically update the states of the service if
    // it's cha changed since the last check.
    addListener(window, 'load', function () {
        auto_update = window.setTimeout(autoUpdate, 5000)
    });
}

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

                    auto_update = window.setTimeout(autoUpdate, 5000);
                }
                else {
                } // Increment time between checks.
        }
    };
    req.open('GET', 'service_modified?pid='+pid+';sid='+sid+';timestamp='+timestamp);
    req.send(null);
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
