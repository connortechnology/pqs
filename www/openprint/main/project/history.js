function delete_confirm(form) {
  var number_of_deleted_projects = 0;
  if ( form.elements['project_id'] ) {
    if ( form.elements['project_id'].length ) {
      for ( var index = 0; index < form.elements['project_id'].length; index += 1 ) {
        if ( form.elements['project_id'][index].checked ) {
          number_of_deleted_projects += 1;
        } // end if
      } // end for
    } else if ( form.elements['project_id'].checked ) {
      number_of_deleted_projects += 1;
    } // end if
  } // end if
  if ( number_of_deleted_projects == 0 ) {
    alert("To Delete Projects, click the checkbox beside the project.");
  } else if ( number_of_deleted_projects == 1 ) {
    if ( confirm("Are you sure you wish to delete this project from history?\n") ) {
      form.btnFunction.value='Delete Project';
      form.submit();
    } // end if
  } else {
    if ( confirm("Are you sure you wish to delete these " + number_of_deleted_projects + " projects from history?\n") ) {
      form.btnFunction.value='Delete Project';
      form.submit();
    } // end if
  } // end if
}

function load_projects() {
  LoadContent( 'ProjectList', '/main/project/_history.html', $j('#f1').serialize() );
} // end function
