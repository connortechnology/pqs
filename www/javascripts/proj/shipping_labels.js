Event.observe(window, 'load', function () {
	var label_chk = document.getElementsByClassName('print-chk');
	var chk_elem;

	for (var i=0; i < label_chk.length; i++) {
		chk_elem = label_chk[i];
		
		Event.observe(chk_elem, 'click', function () {
			var address_elem = this.parentNode;
			
			while (address_elem.nodeType != 1 && address_elem.nodeName.toLowerCase() != 'address') {
				address_elem = address_elem.parentNode;
			}
			
			if (!this.checked) {
				Element.addClassName(address_elem, 'hide-label');
			}
			else {
				Element.removeClassName(address_elem, 'hide-label');
			}
		}.bind(chk_elem));
	}

});