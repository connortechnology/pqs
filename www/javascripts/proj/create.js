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
  const sections      = $('project-type').getElementsByTagName('div');
  const project_types = PRESS_TO_PROJECT[ press_type ];

  if (!project_types) throw 'Unknown press type (' + press_type + ').';
  const project_types_count = Object.keys(project_types).length;
  console.log(project_types, project_types_count);

  // Each grouping of project types is checked.
  for (var i=0; i < sections.length; i++) {
    const section    = sections[i];
    const inputs     = section.getElementsByTagName('input');
    let has_option = false;

    // Project types are hidden if the chosen press type can't run them.
    for (let j=0; j < inputs.length; j++) {
      const input = inputs[j];
      if (!input || (input.name != 'rdbProjectType')) continue;
      const exists = project_types[ input.value ];
      input.disable = !exists;                   // Disable
      Element.display(input.parentNode, exists); // Hide
      // An invalid option can't be the selected one.
      if (input.checked && !exists) input.checked = false;
      if (exists) {
        if (project_types_count == 1) input.checked = true;
        has_option = true;
      }
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
  const form     = $('f1');
  var projects = form.rdbProjectType;

  if (!projects) {
    console.log("No projects found?", form);
  return;
  }

  // The last set of disabled additional services 
  var disabled_services = [];

  function additional_services () {
    const service_types = SERVICE_TYPES_BY_GROUP[PROJECT_GROUPS[this.value]];
    console.log(service_types, this, PROJECT_GROUPS[this.value]);

    for (let j=0; j < disabled_services.length; j++) {
      const service = document.getElementById('s' + disabled_services[j]);
      console.log('re-enable disabled', service);
      service.disabled = false;
      service.parentNode.style.display = '';
      console.log('re-enable disabled', service);
    }

    for (var j=0; j < service_types.length; j++) {
      const service = document.getElementById('s' + service_types[j]);
      if (!service) {
        console.log("Service ", service_types[j], "not found");
        continue; 
      }
      console.log('disable', service);
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

