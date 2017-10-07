JSAN.use('DOM.Events', 'addListener');

Event.observe(window, 'load', function () {
	Event.observe(document.forms['f1'], 'submit', function (e) {
			if (Event.element(e).name == "ProjectIndex") return true;

			var form = document.forms['f1'];
			var selectCount = 0;

			for (i = 0; i < form.length; i++) {
				if (form.elements[i].type == 'select-one') {
					if (form.elements[i].options[
							form.elements[i].selectedIndex
						].value != '') {
						selectCount++;
					}
				}
			}

			if (selectCount != 1) {
				var msg = selectCount == 0
						? "You must select a product first!"
						: "You can only select one product!";

				alert(msg);

				if (e.preventDefault) e.preventDefault();
				else                  e.returnValue  = false;
				
				return false;
			}
		}
	);
});

addListener(window, 'load', function () {
    var form = document.forms['f1'];

    for (var i = 0; i < form.elements.length; i++) {
        var elem = form.elements[i];

        elem.onchange = function (objectEvent) {
            if (this.options[this.selectedIndex].value == '') return;

            for (var j = 0; j < form.length; j++) {
                if (elem.type == 'select-one' && elem != this)
                    elem.selectedIndex = this;
            }
        };
    }
});
