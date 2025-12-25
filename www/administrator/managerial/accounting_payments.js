window.addEventListener('load', function () {
	var add_payment = document.getElementById('add_payment');
	if (!add_payment) return;

	var order_ids = document.getElementsByName('order_ids');
	var order_elem, applied_elem;

	var error = false;
	var error_over_payment = 'The Payment Amount exceeds the Account Total.';
	var error_invalid_input = ' is not a valid amount.\nPlease correct this before continuing.';


	function payment_validate (elem) {
		if (!elem.value.match(/^\s*\d*\.?\d{0,2}\s*$/)) { return false; }
		else { return true; }
	}

	function get_cents (dollars) {
		return Math.round(dollars * 100);
	}
	
	function get_dollars (cents) {
		return (cents / 100).toFixed(2);
	}


	add_payment.addEventListener('change', function () {
		var order_id;	// Each Orders Individual ID
		var payment;	// Payment to be Aplpied, in Cents

		var order_total;
		var order_payment;

		// Elements
		var order_payment_elem


		// if Invalid Payment Input
		if (!payment_validate(this)) {
			alert("'" + this.value + "' " + error_invalid_input);
			return;
		}

		// Sets Value to Zero if Blank
		if (!this.value) {
			this.value = '0.00';
			payment = 0;
		}
		else {
			payment = get_cents(this.value);
			this.value = parseFloat(this.value).toFixed(2);
		}


		for (var i=0; i < order_ids.length; i++) {
			// This Order's ID
			order_id = order_ids[i].value;

			// This Order's Payment Input
			order_payment_elem = document.getElementById('payment_' + order_id);

			// This Order's Total Value
			order_total = get_cents(document.getElementById('total_' + order_id).value);

			// Relative Order Checkbox State
			if (payment > 0) document.getElementById('applied_' + order_id).checked = true;


			if (payment >= order_total) {
				order_payment = order_total;
				payment -= order_total;
			}
			else if (payment < order_total) {
				order_payment = payment;
				payment = 0;
			}

			order_payment_elem.value = get_dollars(order_payment);

			document.getElementById('applied_' + order_id).checked = (document.getElementById('payment_' + order_id).value > 0) ? true : false;

			document.getElementById('balance_' + order_id).innerHTML = '$' + get_dollars((order_total - order_payment));
		}


		if (payment > 0) {
			error = true;
			alert(error_over_payment + '\nPlease correct this before proceeding.');
			this.focus();
		}
		else {
			error = false;
		}
	}.bind(add_payment));



	for (var i=0; i < order_ids.length; i++) {
		order_elem = document.getElementById('payment_' + order_ids[i].value);
		applied_elem = document.getElementById('applied_' + order_ids[i].value);


		// When Payment Applied to Specific Order
		order_elem.addEventListener('change', function () {
			var total = 0;	// All Applied Payments, Totalled Up
			var order_payment;	// Each Order's Applied Payment

			var order_id = this.id.substr(this.id.indexOf('_') + 1)

			var order_balance;	// An Order's Balance
			var order_total;		// An Order's Total

			// Sets Value to Zero if Blank
			if (!this.value) {
				this.value = '0.00';
			}

			// if Invalid Payment Input
			if (!payment_validate(this)) {
				alert("'" + this.value + "' " + error_invalid_input);
				return;
			}
			else {
				this.value = parseFloat(this.value).toFixed(2);
			}


			// CheckBox State Relative to Applied Total.
			document.getElementById('applied_' + order_id).checked = (this.value > 0) ? true : false;


			// Recalculate Total Payment
			for (var j=0; j < order_ids.length; j++) {
				order_payment = get_cents(document.getElementById('payment_' + order_ids[j].value).value);

				if (order_payment && order_payment > 0) {
					// Order's Total Value
					order_total = get_cents(document.getElementById('total_' + order_ids[j].value).value);

					// Order's Balance after Applied Payment
					order_balance = order_total - order_payment;

					// Order's Balance ReDisplayed
					document.getElementById('balance_' + order_ids[j].value).innerHTML = '$' + get_dollars(order_balance);
				}
				else {
					continue;
				}

				total += order_payment;
			}

			add_payment.value = get_dollars(total);

			if (get_cents(document.getElementById('total_balance').value) < get_cents(add_payment.value)) {
				error = true;
				alert(error_over_payment + '\nPlease correct this before proceeding.');
				this.focus();
			}
			else {
				error = false;
			}
		}.bind(order_elem));


		applied_elem.addEventListener('change', function () {
			var order_id = this.id.substr(this.id.indexOf('_') + 1);

			var order_total_elem = document.getElementById('total_' + order_id);
			var order_total = get_cents(order_total_elem.value);

			var order_payment_elem = document.getElementById('payment_' + order_id);
			var order_balance_elem = document.getElementById('balance_' + order_id);

			if (!add_payment.value) { add_payment.value = 0; }

			if (this.checked) {
				order_balance_elem.innerHTML = '$0.00';
				order_payment_elem.value = get_dollars(order_total);
				add_payment.value = get_dollars(get_cents(add_payment.value) + order_total);
			}
			else {
				add_payment.value = get_dollars(get_cents(add_payment.value) - get_cents(order_payment_elem.value));
				order_payment_elem.value = '0.00';
				order_balance_elem.innerHTML = '$' + get_dollars(order_total);
			}
		}.bind(applied_elem));
	}
	
	// Form Validation
	add_payment.form.addEventListener('submit', function () {
		if (error) {
			alert(error_over_payment + '\nThis must be corrected before proceeding.');	
			add_payment.focus();
			return false;
		}
		else {
			return true;	
		}
	});
});