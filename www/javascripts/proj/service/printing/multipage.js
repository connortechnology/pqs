// Shows/hides the gate folded lip dimensions based on the template selection.
Event.observe(window, 'load', function () {
  var form      = $('f1');
  var templates = form.template;

  for (var i=0; i < templates.length; i++) {
    var template = templates[i];
    template_onclick(template);
    Event.observe(template, 'click', template_onclick.bind(template, template));
  }

  return true;
});

function template_onclick(template) {
  console.log('template_onlci', template);
  if (!template.checked) return;
  var gatefold_size      = $j('#gatefold_size');
  var flush_foldout      = $j('#flush_foldout');
  var is_gatefold = template.value.match(/GateFold/i);
  if (is_gatefold) {
    gatefold_size.show();
    flush_foldout.show();
  } else {
    gatefold_size.hide();
    flush_foldout.hide();
  }
}

// Tallies spreads ? forms and gives the user a visual warning if they exceed the spreads remaining to be allocated.
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

