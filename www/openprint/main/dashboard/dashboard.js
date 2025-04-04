function delete_confirm(form) {
  let count = 0;
  let len = form['delete'].length;

  for (let i=0; i < len; i++) {
    if (form['delete'][i].checked) { count++; }
  }

  if (count) {
    return confirm("Are you sure you wish to delete these " + count + " projects from history?");
  }

  alert("To Delete Projects, click the checkbox beside the project.");
  return false;
}
function form_actions() {
  const list = document.querySelectorAll('.confirm-action');

  for (let i = 0; i < list.length; i++) {
    list[i].addEventListener('change', function(event) {
      event.preventDefault();

      const choice = confirm(this.getAttribute('data-confirm'));

      if (choice) {
        $('f1').submit();
      }
    });
  }
}

function do_sort(field) {
  if ( $('sortfield').value == field ) {
    $('sortdirection').value *= -1; 
  } else { 
    $('sortdirection').value = 1; 
  }

  $('sortfield').value = field;
  $('f1').submit();
}
function select_all(source) {
  var boxlist = document.getElementsByName('actionpid');

  for (i = 0; i < boxlist.length; i++){
    boxlist[i].checked = source.checked;
  }
}
function reload_window() {
  window.reload();
}

addEventListener('DOMContentLoaded', (event) => {
  form_actions();
  $j('.datepicker').each(function(index) {
console.log("Setting datepicker on ", this);
    const el = $j(this);
    el.datepicker({dateFormat: "yy-mm-dd", maxDate: 0, constrainInput: false});
//, onClose: this.form.submit()});
  });
});
