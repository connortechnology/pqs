Event.observe(window, 'load', check_for_merge);

function check_for_merge() {
    if (stitchorweld) {
        var radioButtons = document.forms['f1'].elements['rdbBindMethod'];
        for (i = 0; i < radioButtons.length; i++) {
            radioButtons[i].disabled = false;
            if (stitchorweld.match(radioButtons[i].value)) {
                radioButtons[i].checked = true;
            }
        }
    } else {
        var radioButtons = document.forms['f1'].elements['rdbBindMethod'];
        if ( ! radioButtons ) return;
        for (i = 0; i < radioButtons.length; i++) {
            radioButtons[i].disabled = true;
        }
    }
}

