// form colors
var formOn; //decalre variables here so that we do not get javscript errors on pages that do not have menus defined.
var formOff; // The javscript errors come from javascripts used on focus/blur events for form fields.

var agt = navigator.userAgent.toLowerCase(); 
var is_major = parseInt(navigator.appVersion); 

var is_nav  = ((agt.indexOf('mozilla')!=-1) && (agt.indexOf('compatible') == -1)); 
var is_nav4only = ((is_nav) && (is_major >= 4) && (is_major < 5))
var is_nav5up = (is_nav && (is_major >= 5)); 

var is_ie     = (agt.indexOf("msie") != -1) 
var is_ie4    = (is_ie && (is_major == 4) && (agt.indexOf("msie 5")==-1) );
var is_ie4up  = (is_ie  && (is_major >= 4));
var is_ie5    = (is_ie && (is_major == 4) && (agt.indexOf("msie 5.0")!=-1) );
var is_ie5up  = (is_ie  && !is_ie4);

var is_opera = (agt.indexOf("opera") != -1);
var plat = (navigator.platform.indexOf('Mac')> -1) ? "mac" : "win";

var allowMenu = 0;
var jsExt; 	

if (is_nav4only) jsExt = "n4";
else if (is_ie4up) jsExt = "ie";
else jsExt = "n6";	

//var styleSheet = "<link href=\"/styles/"+jsExt+"_"+plat+".css\" rel=\"stylesheet\" type=\"text/css\" />";
//taking out calls to browser specific css - Duke
