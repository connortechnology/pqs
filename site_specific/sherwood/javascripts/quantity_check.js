// Press_minimums are the minimum quantity before we'll bother checking.
var press_minimums = new Array();
/* Press differentials are the differential (in percent) that will cause the
   warning message to pop up.
*/
var press_diffs    = new Array();
/* Configuration settings for each press type.  Set press_minimums on that
   particular press type to disable the test completely.
*/
press_minimums['inkjetprinter'] = 0;
press_diffs['inkjetprinter']    = 0;
press_minimums['press']         = 10000;
press_diffs['press']            = 50;
press_minimums['web']           = 0;
press_diffs['web']              = 0;
press_minimums['screen']        = 0;
press_diffs['screen']           = 0;
press_minimums['digital']       = 0;
press_diffs['digital']          = 0;
/*
 Configuration ends here, code begins.
*/
var words    = new Array();
    words[1] = 'first';
    words[2] = 'second';
    words[3] = 'third';
function check_quantities() {
    var selected_presstype;
    for (var e = 0; e < document.forms[0].rdbPressType.length; e++) {
        if (document.forms[0].rdbPressType[e].checked)
            selected_presstype = document.forms[0].rdbPressType[e].value;
    }
    if (!selected_presstype)
        return;
    if (press_minimums[selected_presstype] > 0) {
        var minimum = press_minimums[selected_presstype];
        var diffs   = press_diffs[selected_presstype];
        var q1      = document.forms[0].txtQuantity1.value;
        var q2      = document.forms[0].txtQuantity2.value;
        var q3      = document.forms[0].txtQuantity3.value;
        for (var compared = 1; compared <= 3; compared++) {
            for (var others = 1; others <= 3; others++) {
                if (compared != others) {
                    if (   eval('q' + compared)       > minimum
                        && eval('q' + others)
                         / eval('q' + compared) * 100 >= diffs) {
                        alert('It appears your ' + words[others] + ' quantity'
                            + ' is more than '   + diffs         + '% higher '
                            + 'than your '     + words[compared] + ' quantity'
                            + "\nFor optimal pricing, you may wish to swap "
                            + 'them.'
                        );
                        // We don't want to be getting the message > 1 time.
                        return;
                    }
                }
            }
        }
    }
}
