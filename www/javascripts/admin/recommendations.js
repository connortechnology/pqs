JSAN.use('DOM.Events', ':all');
JSAN.use('DOM.Utils');
addListener(window, 'load', recommend);
var states = ['default', 'recommended', 'removed'];
function recommend () {
    var data = $("recommendations").getElementsByTagName("td");
    var form = document.forms[0];
    addListener(form, "reset", reset);
    for (var i=0; i < data.length; i++) {
        var cell = data[i];
        // Hide the contents of the cell (JS controls will be added)
        for (var j=0; j < cell.childNodes.length; j++) {
            if (cell.childNodes[j].nodeType != 3)
                cell.childNodes[j].style.display = "none";
        }
        var select = cell.getElementsByTagName("select")[0];
        // Update the colour of our cell now and when we change states.
        addListener(select, "change", setState);
        var state = select.options[select.selectedIndex].value;
        cell.className = states[state];
        // If our state is not the partially selected one (some in the set of
        // papers have it, others don't), remove it.
        if (select.selectedIndex != 1) select.options[1] = null;
        // Allow clicking the cell to toggle the state.
        addListener(cell, "click", nextState);
    }
}
// Change our surrounding cell's class to the new state.
function setState () { $(this.name).className = states[ this.value ]; }
// Select the next option (or roll over if last) for the recommendation.
function nextState () {
    var s = this.getElementsByTagName("select")[0];
    var opt = s.selectedIndex + 1;
    if (opt >= s.options.length) opt = 0;
    s.options[opt].selected = true;
    this.className = states[ s.options[opt].value ];
}
// No browser properly fires the 'change' even when it resets the form. So we
// have to do what would happen here.
function reset (e) {
    var data = $("recommendations").getElementsByTagName("select");
    for (var i=0; i < data.length; i++) setState.apply(data[i]);
}
