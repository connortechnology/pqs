# Prototype.js Migration Guide

## Overview

This document outlines the migration from Prototype.js to native JavaScript and jQuery in the PQS codebase. As of this migration phase, the core utility files have been updated, but some files still depend on Prototype.js.

## Current Status

### ✅ Completed Migrations

1. **www/javascripts/form_utilities.js** - Fully migrated
   - Replaced `$()` with `document.getElementById()`
   - Replaced `Ajax.Request` with `$.ajax()`
   - Replaced `Ajax.Updater` with `$.ajax()` + DOM manipulation
   - Replaced `.hide()/.show()` with native `style.display` or jQuery equivalents
   - Replaced `Object.extend()` with `Object.assign()`
   - Replaced `Hash` with native JavaScript objects
   - Replaced `$A()` with `Array.from()`
   - Replaced `.addClassName()/.removeClassName()` with `.classList`
   - Replaced array `.each()` with native `.forEach()`

2. **www/openprint/javascripts/form_utilities.js** - Fully migrated (mirror of above)

3. **www/administrator/managerial/accounting_payments.js** - Fully migrated
   - Replaced `Event.observe()` with `addEventListener()`

### ⚠️ Kept for Compatibility

**www/javascripts/window.js** and **www/openprint/javascripts/window.js**
- These are third-party windowing libraries from 2006
- Deeply integrated with Prototype.js (uses `Class.create()`, `Event.observe()`, `Element.*` methods, `Ajax.Request`, etc.)
- Used in 107+ locations across the application
- Prototype.js is currently loaded ONLY to support these libraries
- **Recommendation**: Replace with modern alternatives (jQuery UI Dialog, Bootstrap Modal, etc.) in future work

## Migration Patterns

### DOM Selection

```javascript
// OLD (Prototype.js)
var element = $('myId');
var elements = $$('.myClass');

// NEW (Native JavaScript)
var element = document.getElementById('myId');
var elements = document.querySelectorAll('.myClass');

// NEW (jQuery - if already loaded)
var element = $('#myId')[0];
var elements = $('.myClass');
```

### DOM Manipulation

```javascript
// OLD (Prototype.js)
element.update(content);
element.insert(content);
element.hide();
element.show();

// NEW (Native JavaScript)
element.innerHTML = content;
element.insertAdjacentHTML('beforeend', content);
element.style.display = 'none';
element.style.display = '';

// NEW (jQuery)
$(element).html(content);
$(element).append(content);
$(element).hide();
$(element).show();
```

### Event Handling

```javascript
// OLD (Prototype.js)
Event.observe(element, 'click', handler);
Event.stopObserving(element, 'click', handler);
Event.stop(event);

// NEW (Native JavaScript)
element.addEventListener('click', handler);
element.removeEventListener('click', handler);
event.preventDefault();
event.stopPropagation();

// NEW (jQuery)
$(element).on('click', handler);
$(element).off('click', handler);
```

### Ajax Requests

```javascript
// OLD (Prototype.js)
new Ajax.Request('/url', {
  parameters: {key: 'value'},
  onSuccess: function(response) {
    console.log(response.responseText);
  }
});

new Ajax.Updater('elementId', '/url', {
  parameters: {key: 'value'},
  evalScripts: true
});

// NEW (jQuery)
$.ajax({
  url: '/url',
  data: {key: 'value'},
  success: function(data) {
    console.log(data);
  }
});

$.ajax({
  url: '/url',
  data: {key: 'value'},
  success: function(data) {
    $('#elementId').html(data);
    // Evaluate scripts if needed
    $('#elementId script').each(function() {
      eval(this.text || this.textContent || this.innerHTML || '');
    });
  }
});
```

### Class Manipulation

```javascript
// OLD (Prototype.js)
element.hasClassName('active');
element.addClassName('active');
element.removeClassName('active');
element.toggleClassName('active');

// NEW (Native JavaScript)
element.classList.contains('active');
element.classList.add('active');
element.classList.remove('active');
element.classList.toggle('active');

// NEW (jQuery)
$(element).hasClass('active');
$(element).addClass('active');
$(element).removeClass('active');
$(element).toggleClass('active');
```

### Array Methods

```javascript
// OLD (Prototype.js)
array.each(function(item) { ... });
array.invoke('methodName');
array.findAll(function(item) { ... });
array.detect(function(item) { ... });
$A(nodeList).map(function(item) { ... });

// NEW (Native JavaScript)
array.forEach(function(item) { ... });
array.map(function(item) { return item.methodName(); });
array.filter(function(item) { ... });
array.find(function(item) { ... });
Array.from(nodeList).map(function(item) { ... });
```

### Object Utilities

```javascript
// OLD (Prototype.js)
Object.extend(dest, source);
$H({key: 'value'}).toQueryString();

// NEW (Native JavaScript)
Object.assign(dest, source);
new URLSearchParams({key: 'value'}).toString();

// NEW (jQuery)
$.extend(dest, source);
$.param({key: 'value'});
```

## Files Still Using Prototype.js

The following files have been identified as still using Prototype.js patterns and would benefit from migration:

### High Priority (Core Functionality)
- www/openprint/javascripts/printing.js (732 lines)
- www/openprint/javascripts/paper.js (192 lines)
- www/openprint/main/order/order.js (86 lines)
- www/openprint/main/quote/information.js
- www/openprint/main/project/shipping/shipping.js

### Medium Priority (Admin/Employee Tools)
- www/openprint/employee/production/print_overview.js
- www/openprint/employee/inventory/manifest.js
- www/openprint/employee/purchase_order/edit.js
- www/openprint/administrator/equipment/edit.js
- www/openprint/administrator/project_types/edit.js
- www/openprint/administrator/managerial/profile.js

### Lower Priority (Specific Features)
- www/openprint/invoice/edit.js
- www/openprint/sites/edit.js
- www/openprint/employee/sred/edit.js
- www/openprint/marketing/sales_log.js
- www/openprint/tasks/edit.js
- www/openprint/sensors/edit.js

## Testing Recommendations

After migrating each file:

1. **Functional Testing**: Manually test all features that use the migrated code
2. **Browser Console**: Check for JavaScript errors
3. **Ajax Calls**: Verify all Ajax requests work correctly
4. **Event Handlers**: Test all click, change, and submit handlers
5. **DOM Manipulation**: Verify all show/hide/update operations work
6. **Cross-Browser**: Test in multiple browsers (Chrome, Firefox, Safari, Edge)

## Future Work

### Short Term
1. Continue migrating JavaScript files from high to low priority
2. Test each migration thoroughly before moving to the next
3. Document any Prototype-specific patterns encountered

### Medium Term
1. Replace window.js with a modern alternative (jQuery UI Dialog, Bootstrap Modal, etc.)
2. Create a modern popup/dialog utility that doesn't require Prototype.js
3. Update all 107+ usages of window.js to use the new alternative

### Long Term
1. Remove all Prototype.js library files once window.js is replaced
2. Remove Prototype.js from all HTML includes
3. Consider moving away from jQuery to native JavaScript where practical
4. Modernize the codebase to use ES6+ features

## Notes

- jQuery is already loaded in the application and set to `$j` via `jQuery.noConflict()`
- The codebase uses a mix of native JavaScript and jQuery
- Prefer native JavaScript solutions for better performance where practical
- Use jQuery where it significantly simplifies the code

## Resources

- [MDN Web Docs - JavaScript](https://developer.mozilla.org/en-US/docs/Web/JavaScript)
- [jQuery Documentation](https://api.jquery.com/)
- [You Don't Need jQuery](https://github.com/nefe/You-Dont-Need-jQuery)
