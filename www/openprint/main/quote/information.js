function remove_product(button) {
  console.log('remove_product clicked');
  const data = $j(button.form).serialize();
  const product_id = button.getAttribute('data_product_id');
  $j.ajax({
    url: '_products.html?action=del&product_id='+product_id,
    data: data
  }).done(function(data) {
    console.log(data);
    $j('#Products').html(data);
    update_event_bindings();
    tinyMCE.init({
      mode : "specific_textareas",
      editor_selector : "mce",
      theme : "simple"
    });
  });
}

function add_product(button) {
  console.log('add_product clicked');
  const data = $j(button.form).serialize();
  $j.ajax({
    url: '_products.html?action=add',
    data: data
  }).done(function(data) {
    $j('#Products').html(data);
    update_event_bindings();
    tinyMCE.init({
      mode : "specific_textareas",
      editor_selector : "mce",
      theme : "simple"
    });
  });
}

window.addEventListener('DOMContentLoaded',function(){
  const tinymce_options = {
      mode : "specific_textareas",
      editor_selector : "mce",
    //selector : 'textarea',
    license_key: 'gpl',
  plugins: "paste",
  theme_advanced_toolbar_location : "top",
  theme_advanced_buttons1 : "fontselect,fontsizeselect,bold,italic,underline,strikethrough,separator,justifyleft,justifycenter,justifyright,justifyfull,bullist,numlist,outdent,indent,sub,sup,charmap",
  theme_advanced_buttons2 : "",
  theme_advanced_buttons3 : "",
  force_br_newlines : true,
  force_p_newlines : false,
  forced_root_block : '', // Needed for 3.x
  auto_resize : true,
  theme : "advanced",
    content_css : "/css/tinymce.css",
theme_advanced_font_sizes: "10px,12px,13px,14px,16px,18px,20px",
font_size_style_values : "10px,12px,13px,14px,16px,18px,20px",
  };
tinyMCE.init(tinymce_options);
});

function company_onchange( e ) {
  new Ajax.Request( '_company_information.json', { parameters: { company_id: e.value } } );
} // end function
function user_onchange( e ) {
  new Ajax.Request( '_user_information.json', { parameters: { user_id: e.value } } );
} // end function
