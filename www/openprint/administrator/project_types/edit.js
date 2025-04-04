"use strict;"

function update_recommendations(r) {
  new Ajax.Updater( 'PaperRecommendations', '_paper_recommendations.html', {
    parameters: {
      projecttype_id: $j('#ddmProjectType').val(),
      recommended: r.value
    }
  });
}

function paper_checkbox_clicked(checkbox) {
  const hidden = document.getElementById('paper_id'+checkbox.value);
  hidden.value = checkbox.checked ? '1' : '0';
}
