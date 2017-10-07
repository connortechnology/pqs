Event.observe(window, 'load', function (e) {
    var form = $('f1');

    if (!form.project_size) return;

    var project_sizes = {}; // Out of DOM storage of option groups.

    // Only display size options for the current template.
    var chose_template = function (e) {
        var template = $F(this);

        // Hide all optgroup that don't match the current template.
        form.project_size.childElements().each(function (elem) {
            if (elem.tagName.toLowerCase() != 'optgroup' || !elem.label) return;

            var label = elem.label.replace(/ /g,'');

            if (label == template) return;

            project_sizes[label] = elem; // .cloneNode(true);
            form.project_size.removeChild(elem);
        });
        
        // Put the optgroup into the select if the template has one.
        if (project_sizes[template])
            form.project_size.appendChild( project_sizes[template] );

        // Because we're copying nodes previous template 'remember' their
        // selections. So make sure the dims match the template.
        populate_dimensions(e);

        return true;
    };

    // Bind to all template radio buttons.
    var chosen;
    $A( form.template ).each(function (elem) {
        if (elem.checked) chosen = elem;

        Event.observe(elem, 'click', chose_template.bind(elem));
    });

    // Set the initial form state (for edits).
    if (chosen) chose_template.apply(chosen);

    return true;
});


Event.observe(window, 'load', function (e) {
    var form = $('f1');

    if (!form.project_size) return;

    // Change the dimension text boxes when a size is selected.
    Event.observe(form.project_size, 'change', populate_dimensions);

    populate_dimensions(); // Set initial state.

    return true;
});

// Populate the flat/finished dimension boxes from selected template size.
function populate_dimensions (e) {
    var elem  = $('project_size');
    var form  = elem.form;
    var value = $F(elem);

    if (!value || !e) return; // If no event, don't clobber custom dims.

    var dimensions = value.split(',');

    var finished   = dimensions[1].split('x');
    var flat       = dimensions[2].split('x');

    if (form.final_width)  form.final_width.value  = finished[0];
    if (form.final_height) form.final_height.value = finished[1];
    if (form.flat_width)   form.flat_width.value   = flat[0];
    if (form.flat_height)  form.flat_height.value  = flat[1];

    return true;
}


Event.observe(window, 'load', function (e) {
    var form = $('f1');

    if (!form.project_size) return;

    // If a user modifies a dimension, the template must be 'Custom'.
    var set_custom = function () { $('project_size').selectedIndex = 0 };
    
    var fields = $A([ 'final_width', 'final_height', 
                      'flat_width',  'flat_height'   ]);
    
    fields.each(function (name) {
        if (!form[name]) return;
        
        Event.observe(form[name], 'change', set_custom)
    });
});

