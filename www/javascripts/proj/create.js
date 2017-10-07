// DESCRIPTION
//
//  Handles the press type <-> project type mappings, and the project type <->
//  service type mappings.

// Add the event handlers to the press types and set the initial display state
// of the project types.
Event.observe(window, 'load', function (e) {
    var inputs = document.getElementsByName('rdbPressType');

    if (!inputs[0]) return; //throw "No press types available!";

    // If there are multiple press types, register their events and set
    // the projects types we'll view first.
    if (inputs.length > 1) {
        for (var i=0; i < inputs.length; i++) {
            var input = inputs[i];
          
            if (input.type != 'radio') continue;

            if (input.checked) press_type_projects(input.value); // Init

            Event.observe(input, 'click', function (e) {
                press_type_projects(Event.element(e).value);
            });
        }
    }
    // Otherwise there's one press type and we need to set the projects state.
    else {
        if (inputs[0].type != 'hidden') { throw "Invalid press type field."; }

        press_type_projects(inputs[0].value);
    }

    return true;
});


// Enables the project types that are allowed on the given press type. Any
// section that doesn't have any options at all will be hidden completely.
function press_type_projects (press_type) {
    var sections      = $('project-type').getElementsByTagName('div');
    var project_types = PRESS_TO_PROJECT[ press_type ];

    if (!project_types) throw 'Unknown press type (' + press_type + ').';

    // Each grouping of project types is checked.
    for (var i=0; i < sections.length; i++) {

        var section    = sections[i];
        var inputs     = section.getElementsByTagName('input');
        var has_option = false;

        // Project types are hidden if the chosen press type can't run them.
        for (var j=0; j < inputs.length; j++) {

            var input = inputs[j];

            if (!input || input.name != 'rdbProjectType') continue;

            var exists = project_types[ input.value ];

            input.disable = !exists;                   // Disable
            Element.display(input.parentNode, exists); // Hide

            // An invalid option can't be the selected one.
            if (input.checked && !exists) input.checked = false;

            if (exists && !has_option) has_option = true;
        }

        // A section without any options isn't displayed.
        Element.display(section, has_option);
    }
    return true;
}


// Only certain service types ("additional services") are allowed for any
// given project. Change the service types to reflect that when a project
// is selected.
Event.observe(window, 'load', function () {
    var form     = $('f1');
    var projects = form.rdbProjectType;

    if (!projects) return;
    
    // The last set of disabled additional services 
    var disabled_services = [];
    
    function additional_services () {
        var service;
        var service_types = SERVICE_TYPES_BY_GROUP[PROJECT_GROUPS[this.value]];

        for (var j=0; j < disabled_services.length; j++) {
            service = document.getElementById('s' + disabled_services[j]);
            service.disabled = false;
            service.parentNode.style.display = '';
        }

        for (var j=0; j < service_types.length; j++) {
            if ( ! document.getElementById('s' + service_types[j]) )
                continue; 
            service = document.getElementById('s' + service_types[j]);
            service.disabled = true;
            service.parentNode.style.display = 'none';
        }

        disabled_services = service_types;
    }
    
    //    For Each Project Type, Bind Additional Service Refinement
    for (var i=0; i < projects.length; i++) {
        var elem = projects[i];

        Event.observe(elem, 'click', additional_services.bind(elem));
    }
});

