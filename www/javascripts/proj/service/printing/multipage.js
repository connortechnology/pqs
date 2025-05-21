// Shows/hides the gate folded lip dimensions based on the template selection.
Event.observe(window, 'load', function () {
    var form      = $('f1');
    var size      = $('gatefold_size');
    var templates = form.template;

    if (!size) return;

    for (var i=0; i < templates.length; i++) {
        var template = templates[i];

        // Set initial state.
        if (template.checked)
            size.display( !!template.value.match(/GateFold/i) );

        Event.observe(template, 'click', function () {
            size.display( !!this.value.match(/GateFold/i) );
        }.bind(template));
    }

    return true;
});
// Shows/hides the flush fold out cover based on the template selection.
Event.observe(window, 'load', function () {
    var form      = $('f1');
    var size      = $('flush_foldout');
    var templates = form.template;

    if (!size) return;

    for (var i=0; i < templates.length; i++) {
        var template = templates[i];

        // Set initial state.
        if (template.checked)
            size.display( !!template.value.match(/GateFold/i) );

        Event.observe(template, 'click', function () {
            size.display( !!this.value.match(/GateFold/i) );
        }.bind(template));
    }

    return true;
});

// Tallies spreads x forms and gives the user a visual warning if they exceed
// the spreads remaining to be allocated.
Event.observe(window, 'load', function () {
    var form      = $('f1');

    var spreads = $('spreads');
    var forms   = $('forms');

    var remaining = $('spreads_remaining');
    var used      = $('used_spreads');

    if (! (spreads && forms && remaining && used) ) return;

    remaining = parseInt(remaining.value);
    if (!remaining) throw "Invalid number of spreads remaining.";

    var update = function () {
        var result = 1*parseInt(spreads.value) * 1*parseInt(forms.value);

        used.className = result > remaining ? 'error' : '';
        used.innerHTML = result; // TODO set to empty string if NaN
    };

    Event.observe(spreads, 'input', update);
    Event.observe(forms,   'input', update);

    return true;
});

