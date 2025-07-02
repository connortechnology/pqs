"use strict";
// TODO Cache the last n reponses (using the serialised form as a key) so we
// don't even have to touch the server if we're toggling between a number of
// options.

var Service = Class.create();
Service.prototype = {
    initialize : function (name, validate, response) {
        this.name = name;

        if (typeof validate == 'function') { this.validate = validate }
        if (typeof response == 'function') { this.response = response }

        // Bind to the service form.
        Event.observe(window, 'load', this._form_load.bind(this));
    },

    DEBUG : true,

    _form_load : function () {
        this.form = $('f1');

        // The submission button should validate first
        $('submit-service').onclick = this.validate.bindAsEventListener(this);

        // Create a 'Calculate' button.
        var attributes = {
            id        : 'calculate-service',
            type      : 'button',
            className : 'button',
            value     : 'Calculate',
            onclick   : this.calculate.bindAsEventListener(this)
        };
       
        var button = document.createElement('input');
        Object.extend(button, attributes);

        // Add the calculate button to the form by replacing the reset button.
        // As the reset button doesn't fire change events and can severly
        // mangle the for state.
        $('service-controls').replaceChild(button, $('reset'));

        // Create the auto calculation timer
        this._bind_timer();

      if (0) {
       for (var i = 0; i < this.form.elements.length; i++) {
         var elem = this.form.elements[i];

         // Ignore non-interactive elements (pricing fields, fieldsets,etc.).
         if ( !elem.type || elem.type == 'hidden' || elem.readOnly ) continue;

         if (elem.type == 'text' || elem.nodeName.toLowerCase() == 'textarea' || elem.type == 'number') {
           //Event.observe(elem, 'keypress', this.calculate.bindAsEventListener(this));
           if (!elem.oninput) {
             elem.oninput = this.calculate.bind(this, false);
           }
         }
       }
      }

    },

    // Add events for automatic calculation on user input.
    _bind_timer : function () {
      //return;
        this.timer = new Timer(this.calculate.bind(this), 4000);

        // Start the timer any time an element changes
        new Form.EventObserver(
            this.form, this.timer.start.bindAsEventListener(this.timer) );

        // Extend an existing timer if the user is still activy (tracked by focus
        // changes and keypress in text fields).
        for (var i = 0; i < this.form.elements.length; i++) {
            var elem = this.form.elements[i];

            // Ignore non-interactive elements (pricing fields, fieldsets,etc.).
            if ( !elem.type || elem.type == 'hidden' || elem.readOnly ) continue;

            Event.observe(elem, 'focus', this.timer.reset.bind(this.timer));

            if (elem.type == 'text' || elem.nodeName.toLowerCase() == 'textarea' || elem.type=='number')
                Event.observe(elem, 'keypress', this.timer.reset.bind(this.timer));
        }
    },

    req : null,

    // Validate and price the service in the background.
    calculate : function (e) {
      if (this.timer) this.timer.stop();

      // If we're already in a request or we're invalid, do nothing.
      if (this.req) {
        this.req.transport.abort();
      }

      if (! this.validate.apply(this, [e])) {
        return false;
      }

      // *TEMPORARY* PRINTING SPECIFIC The run log (hdnRunStyleCheck) will
      // be going away soon (handled by sessions) until then we still need
      // to pass it back during a POST but not during a pricing request
      // (it's huge). TODO Remove completely.
      if ($('run_log')) $('run_log').value = '';

			// not all views show price field
			if ( $('txtPrice1') ) {
				$('txtPrice1').innerHTML = '';
			}
			if ( $('total_price1') ) {
				$('total_price1').innerHTML = '';
			}

			//not all pages show unit price ( printing page.. ) 
			if ( $('txtUnitPrice1') ) {
				$('txtUnitPrice1').innerHTML = '';
			}
			if ( $('unit_price1') ) {
				$('unit_price1').innerHTML = '';
			}
      if ($('status_alert')) $('status_alert').innerHTML = 'Calculating...';

      this.req = new Ajax.Request('/service/' + this.name, {
        method:         'get',
        requestHeaders: { Accept: 'application/json' },
        parameters:     $(this.form).serialize(),

        onCreate:    this.disable.bind(this),
        onSuccess:   this._response.bind(this),
        onComplete:  this._cleanup.bind(this)

      });

      return true;
    },
    novalidate : function () { return true; },

    validate : function () { return true; },

    _response : function (req) {
        var data = req.responseText.evalJSON(true);
        if (!data) throw "Invalid return";

        if (data.error) { 
            alert("A problem has occured:\n\t" + data.error); 
        }

        // Dispatch to the custom response handler
        var rv = true;
        if (this.response) rv = this.response(data);
        if (rv) this._fill(data);
        if ($('status_alert')) $('status_alert').innerHTML = '';

        return true;
    },

    _fill : function (data) {
      const form = this.form; // "this" gets reset into the each
      for (const [field, value] of Object.entries(data)) {
        var elem = form.elements[field] ? form.elements[field] : document.getElementById(field);
        if (!elem) {
          console.log("No element found for "+field);
          continue;
        }

        // IE uses NodeLists but doesn't recognize them as DOM objects.
        //   elem = $A( elem instanceof NodeList ? elem : [elem] );
        elem = $A( elem.nodeName ? [elem] : elem );

        elem.each(function (e) {
          switch (e.type) {
            case "text":
            case "number":
            case "textarea":
            case "hidden":
              if (typeof value == 'object') break;
              e.value = value;
              break;

            case "radio": // Radios are equiv. to select-one.
              if (typeof value == 'object') break; 
              e.checked = (value == e.value);

            case "checkbox":
              e.checked = (value instanceof Array) ? value.indexOf(e.value) != -1 : value == e.value;
              break;

            case "select-one":
            case "select-multiple":
              // We only populate select boxes that don't have an override or if they have one, it's not checked.
              if (form.elements['override_'+field] && form.elements['override_'+field].checked) {
                break;
              }

              for (var i = 0, len = e.options.length; i < len; i++) {
                var opt = e.options[i];
                var val =opt.hasAttribute('value') ? opt.value : opt.text;

                opt.selected = (value instanceof Array) 
                  ? value.indexOf(val) != -1
                  : value == val;
              }
              break;

            default:
              e.innerHTML = value;
          }
        });
    }
},

    // Allow user actions again.
    _cleanup: function (req) {
        this.req = null;
        this.enable();
    },

    // ERROR HANDLING
    //
    // TODO Error handling, perhaps it's own object.
    _req_error : function (req) { 
        if (this.DEBUG) {
            var debug = window.open();

            if (!debug) throw "Could not create debugging window.";

            var doc   = debug.document;
            doc.write(req.responseText);
            doc.close();
        }
        else {
            alert('The server could not be contacted or an error has occurred');
        }
        return false;
    },
    _calc_error : function (req, err) { 
        if (this.DEBUG)  throw err;
        else             alert('There was a problem processing the pricing.');
    },


    // DISPLAY
    //
    // Enables/disables a form keeping track of each elements initial state.
    set_form_state : function (enable) {
      //return;
        // Let the user know we're doing (or not doing) something.
        this.form.style.cursor = enable ? '' : 'wait';

        for (var i = 0; i < this.form.elements.length; i++) {
            var elem = this.form.elements[i];

            if (!elem.type) continue; // Skip fieldsets, etc.

            if (!enable && !elem.disabled) {
                elem.disabled = true;
                elem.setAttribute('re_enable', true);
            }
            else if (enable && elem.getAttribute('re_enable')) {
                elem.removeAttribute('re_enable');
                elem.disabled = false;
            }
        }
    },
    disable : function () { this.set_form_state(false) },
    enable  : function () { this.set_form_state(true) }

};


var Timer = Class.create();
Timer.prototype = {
    initialize : function (func, timeout) {
        this.func    = func;
        this.timeout = timeout;
    },

    start : function () { 
        this.stop(); 
        this.timer = window.setTimeout(this.callback.bind(this), this.timeout); 
    },
    stop  : function () { if (this.timer) clearTimeout(this.timer); },
    
    // Reset timeout of exiting timers only.
    reset : function () { if (this.timer) { this.stop(); this.start(); } },

    callback : function () { 
        this.timer = null;
        this.func();
    }
};

function calc() {
  //new Timer(service.calculate, 4000);
  service.calculate();
}
