/*
	Tab Code - Converts Fieldset with Sub Fieldsets into A Clickable Tabbed Block
		Apply a "tab-container" class to the Over All Fieldset which contains sub fieldsets to be converted into Tabs
		Apply a "tab-group" class to all sub fieldsets to be converted into Tabs
		Apply a "tab-instructions" to a DIV with Instructions, to be displayed when the Tab Code Runs.
		Clicking on the Tabs Generated / Listed at the top Switches to that Tab / Fieldset
		This Code has Not Be Stress Tested Outside of it's Minimum Layout Requirements.
		Will likely display = 'none'; anything else contained within the Overall Fieldset that is not marked the "tab-group" & "tab-instructions" classes.
*/

// TABs Code (originally for Additional Services on CS1)
// TAB = Tabs Automatically Built
Event.observe(window, 'load', function () {
	var tab_containers = document.getElementsByClassName('tab-container');
		// All Elements marked with Tab Containers class
	var container_children;	// Children of Tab Containers

	var tab_instructions;
	var tab_groups;
	var group_children;	// Children of Tab Groups
	var tabs;	// Display Tabs
	var tab;		// Individual Tab within Tabs
	var tab_text;	// Individual Tab Text
	var tab_offset;

	// For all Tab Container Elements
	for (var i = 0; i < tab_containers.length; i++) {
		// If Element is a FieldSet
		if (tab_containers[i].tagName.toLowerCase() == 'fieldset') {
			// Get Child Nodes
			container_children = tab_containers[i].childNodes;

			// For all Children
			for (var j = 0; j < container_children.length; j++) {
				// If Child is an HTML Element, AND NOT a Fieldset AND NOT a Br Tag
				if (container_children[j].nodeType == 1 && container_children[j].tagName.toLowerCase() != 'fieldset' && container_children[j].tagName.toLowerCase() != 'br') {
					if (container_children[j].tagName.toLowerCase() == 'legend') {
						// Remove Fieldset Legends
						tab_containers[i].removeChild(container_children[j]);
					}
					else {
						// Hide that HTML Element
						container_children[j].style.display = 'none';
					}
				}
			}

			// Create & Place tabs in Tab Container
			tabs = document.createElement('div');
			tab_containers[i].appendChild(tabs);

			// Position tabs...
			tab_containers[i].style.position = 'relative';
			Element.addClassName(tabs, 'tab-title-container');
			
			// Get Tab Groups in this Tab Container
			tab_groups = document.getElementsByClassName('tab-group', tab_containers[i]);
			
			tab_instructions = document.getElementsByClassName('tab-instructions', tab_containers[i]);

			for (var j = 0; j < tab_instructions.length; j++) {
				tab_instructions[j].style.display = 'block';
				tabs.tab = tab_instructions[j];
			}

			// For all Tab Groups
			for (var j = 0; j < tab_groups.length; j++) {
				// Get Child Nodes
				group_children = tab_groups[j].childNodes;
				
				// For All Children of this Tab Group
				for (var k = 0; k < group_children.length; k++) {
					// If Child is HTML Element AND HTML Element is a Legend
					if (group_children[k].nodeType == 1 && group_children[k].tagName.toLowerCase() == 'legend') {
						// Create New Tab
						tab = document.createElement('div');
						// Make Tab Text Legend Text
						tab_text = document.createTextNode(group_children[k].innerHTML);

						// Assemble Tab
						tab.appendChild(tab_text);
						// Add Tab to Collection
						tabs.appendChild(tab);
						
						// Add Approperaite Class
						Element.addClassName(tab, 'tab-title');
						
						// Add Associated Fieldset to Tab
						tab.tab = tab_groups[j];

						// Add MouseOver Class Change Event
						Event.observe(tab, 'mouseover', function (e) {
							var elem = Event.element(e);
							if (!Element.hasClassName(elem, 'tab-active')) {
								Element.addClassName(elem, 'tab-hover');
							}
						});

						// Add MouseOut Class Change Event
						Event.observe(tab, 'mouseout', function (e) {
							var elem = Event.element(e);
							Element.removeClassName(elem, 'tab-hover');
						});

						// Select Tab Event...
						Event.observe(tab, 'click', function (e) {
							// Identify which Tab...
							var elem = Event.element(e);

							// Remove Active Tab Class from the Previously Selected Tab
							Element.removeClassName(document.getElementsByClassName('tab-active', elem.parentNode)[0], 'tab-active');
							// Add Active Tab Class to Newly Selected Tab
							Element.addClassName(elem, 'tab-active');

							// Get Related Fieldset Objects
							var this_tab = elem.tab;
							var last_tab = elem.parentNode.tab;
							
							// Assign Current Fieldset
							elem.parentNode.tab = this_tab;

							// Change Fieldset Display
							last_tab.style.display = 'none';
							this_tab.style.display = '';
						});

						k = group_children.length;
					}
				}

				// Initial Tab Display
				// If No Instructions Exist, and this is the first fieldset/tab
				if (tab_instructions.length == 0 && j == 0) {
					// Mark Active Fieldset
					tabs.tab = tab_groups[j];
					Element.addClassName(tab, 'tab-active');
				}
				else {
					// Hide It
					tab_groups[j].style.display = 'none';
				}

				// Assign Fieldset Tab Class to Fieldset Object
				Element.addClassName(tab_groups[j], 'tab-fieldset');
			}

			// What Negative Margin should be Applied to the Tabs Objs Collection Container
			tab_offset = tabs.offsetHeight;
			tabs.style.marginTop = '-' + tab_offset + 'px';
			tabs.parentNode.style.marginTop = (tab_offset + 10)+ 'px';
		}
	}
});