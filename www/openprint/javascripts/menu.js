var timer;
var useImages = false;
var debug = 1;

function addMenu( name, text, image, link, state ) {
	var menu = new Menu( name, text, image, link, state );
	menu.parent = this;
	this.menus[this.menus.length] = menu;
	return menu;
} // end function

function Menu( name, text, image, link, state ) {
	this.name = name;
	this.text = text;
	this.link = link;
	this.image = image;
	this.naturalstate = state;
	this.menus = new Array();
	this.add = addMenu;
	this.usecount = 0;
	this.zindex = 10;
	this.parent = null;
}

function writeMenu( menu ) {
	var html = "<div id=\""+menu.name+"Menu\" class=\"MenuBox Menu" + menu.name + "\">";

	for ( var x = 0; x < menu.menus.length; x += 1 ) {
		html += createMenuItem( menu.menus[x] );
	} // end for

	html += "</div>";

	document.write(html);

	var flag = false;
	for ( var x = 0; x < menu.menus.length; x += 1 ) {
		if ( menu.menus[x].menus.length ) {
			writeMenu( menu.menus[x] );
		} // end if
	} // end for
	if ( ! flag && ! menu.parent ) {
		if ( typeof(MenuOn) == 'function' )
			setTimeout("MenuOn('"+menu.name+"')", 200 );
	} // end if
} // end function writeMenu

// The capitalised versions are external
function MenuOff( menuName ) {
	if ( ! Menus ) {
		if ( debug ) alert("No Menus!");
		return;
	} // end if
	var menu = findMenu( Menus, menuName );
	if ( ! menu ) {
		//if ( debug ) alert( "Couldn't find menu: " + menuName );
		return;
	} // end if
	if ( menu.parent ) {
		if ( menu.usecount ) menu.usecount -= 1;
		if ( typeof(MenuOff) == 'function' ) MenuOff( menu.parent.name );
	} else {
		if ( ! timer ) {
			// Wait a tenth, then turn em all on or off as appropriate
			timer = setTimeout("TurnOnOff(Menus)", 500 );
		} // end if
	} // end if
} // end function MenuOff( menuName )

// Just makes it invisible
function menuOff( menu ) {

	if ( menu.menus && menu.menus.length ) {
		var element = getMenuElement( menu.name + 'Menu' );
		if ( ! element ) return;
		element.style.visibility = 'hidden';
	} // end if
	if ( useImages && menu.image ) {
		var image = getImage( menu.name+'Button' );
		if ( image ) {
			var filename = image.src.substring( image.src.lastIndexOf('/') + 1 );
			image.src = '/images/menu/off/' + filename;
			window.status = image.alt;
		} // end if
	} else {
		var element = $( menu.name + 'Item' );
		if ( element ) {
			var newclass = '';
			if ( ! menu.parent.parent ) {
				newclass = 'menuOff';
			} else {
				newclass = 'submenuOff';
			} // end if
			if ( newclass != element.className ) {
				element.className = newclass;
			} // end if
		} // end if
	} // end if

}

function TurnOnOff( menu ) {
	timer = 0;
	if ( ! menu ) {
		return;
	} // end if
	if ( menu.usecount ) {
		menuOn( menu );
	} else {
		menuOff( menu );
	} // end if
	if ( menu.menus ) {
		for ( var x = 0; x < menu.menus.length; x += 1 ) {
			TurnOnOff( menu.menus[x] );
		} // end for
	} // end if
}

function findMenu( menu, menuName ) {
	if ( menu.name == menuName ) {
		return menu;
	} // end if
	var menu2;
	for ( var x = 0; x < menu.menus.length; x += 1 ) {
		if ( menu2 = findMenu( menu.menus[x], menuName ) ) {
			return menu2;
		} // end if
	} // end for
	return;
}

function getMenuElement( name ) {
	return document.getElementById ? document.getElementById(name):document.all[name];

}

// Runs through all menus, and turns them all off, except for the one that is getting turned on.
function turnAllButMeOff( menu, menuName ) {
	if ( menu.name == menuName ) {
		return menu;
	}

	var menu2;
	for ( var x = 0; x < menu.menus.length; x += 1 ) {
		var menu3;
		if ( menu3 = turnAllButMeOff( menu.menus[x], menuName ) ) 
			menu2 = menu3;
	} // end for
	if ( menu2 ) {
		return menu2;
	} // end if
	if ( menu.usecount ) {
		menu.usecount -= 1;
	} // end if
	if ( 0 == menu.usecount ) 
		menuOff( menu );
	
	return;
}
	

function MenuOn( menuName ) {
	if ( timer ) {
		clearTimeout( timer );
		timer = 0;
	} // end if
	var menu = turnAllButMeOff(Menus, menuName );
	if ( ! menu ) {
		//alert( "Couldn't find menu: " + menuName );
		return;
	} // end if
	var parent = menu;	
	while ( parent ) {
		parent.usecount += 1;
		parent = parent.parent;
	} // end while
	menuOn( menu );
}


function menuOn( menu ) {
	var parent = menu.parent;
	if ( parent ) {
		menuOn( parent );
	} // end if
	var element = getMenuElement(menu.name+'Menu');
	if ( element ) {
		if ( parent ) {
			// if we are a sub menu, then we need to figure out our positioning from the parent
			var menuBar = getMenuElement( parent.name+'Menu' );
			if ( ! menuBar ) {
				alert( "Can't find menubar" + parent.name+'Menu' );
				return;
			} // end if
			var menuItem = getMenuElement( menu.name+'Item' );
			if ( ! menuItem ) {
				alert( "Can't find menuItem" + menu.name+'Item' );
				return;
			} // end if

			var left = parseInt( menuBar.offsetLeft + menuItem.offsetLeft );

			if ( left < 0 ) {
				left = menuBar.offsetLeft;
			} else if ( left > menuBar.offsetLeft + menuBar.offsetWidth - element.offsetWidth ) {
				left = menuBar.offsetLeft + menuBar.offsetWidth - element.offsetWidth - 0;
			} // end if
			element.style.left = left + 'px';
			//element.style.left = ( is_ie ? menuBar.offsetLeft : menuItem.offsetLeft ) + 'px';
			element.style.top = parseInt( menuBar.offsetTop + menuItem.offsetHeight + 1) + 'px';
		} // end if parent
		element.style.visibility = 'visible';

	} // end if

	if ( useImages && menu.image ) {
		var image = getImage( menu.name+'Button' );
		if ( image ) {
			var filename = image.src.substring( image.src.lastIndexOf('/') + 1 );
			image.src = '/images/menu/on/' + filename;
			window.status = image.alt;
		} // end if
	} else {
		var element=$(menu.name+'Item');
		if ( element ) {
			var newclass;
			if ( ! menu.parent.parent ) {
				newclass='menuOn';
			} else {
				newclass='submenuOn';
			} // end if
			if ( newclass != element.className ) {
				element.className = newclass;
			} // end if
		} // end if

	} // end if

} // end function MenuOn( menuName )

function findPosX(obj) {
	var curleft = 0;
	if (obj.offsetParent) {
		while (obj.offsetParent) {
			curleft += obj.offsetLeft;
			obj = obj.offsetParent;
		}
	} else if (obj.x) {
		curleft += obj.x;
	} // end if
	return curleft;
}

function loadOnButton( filename ) {
	// cache the on state
	var button = new Image();
	button.src = "/images/menu/on/"+filename;
}

function createMenuItem( menu ) {
	var html = "<a id=\"" + menu.name + "Item\" class=\"" + ( menu.parent.parent ? 'submenuOff' : 'menuOff' ) + "\" href=\""+menu.link+"\"";

	html += " onMouseOver=\"if ( typeof(MenuOn) == 'function' ) {MenuOn('"+menu.name+"');};\" onMouseOut=\"if(typeof(MenuOff) == 'function' ) {MenuOff('"+menu.name+"');};\" >";
	if ( useImages && menu.image != '' ) {
		html += "<img src=\"/images/menu/off/"+menu.image+"\" border=\"0\" name=\""+menu.name+"Button\"";
		if ( menu.text != '' ) {
			html += " alt=\""+menu.text+"\"";
		} // end if
		html += "/>";
		setTimeout("loadOnButton('"+menu.image+"');", 1000 );
	} else {
		html += "<span class=\"l\"></span><span class=\"c\">" + menu.text + "</span><span class=\"r\"></span>";
	} // end if
	html += "</a>";
	return html;
} // end function createButton

