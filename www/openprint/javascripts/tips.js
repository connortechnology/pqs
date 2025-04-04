
var word;
var text;

var tips = new Array();
tips['dry trap'] = new Array( 'Dry Trap', "When applying varnish to paper, it can be done either wet trap or dry trap. Most varnish is applied inline during the press run as a wet trap.  With dry trap, the paper is printed first and then allowed to dry before the varnish is applied.  It's another pass through the press and will add to your costs a little, but will give you a better result because it gives you better control over the varnish density." );

tips['price units'] = new Array( 'Price Units', 'The units that the cost and price fields represent.  This affects how the prices are used in calculations.  Valid options are Per M, 100 lbs, Per Hour, etc' );

tips['predefinedprojects'] = new Array( 'Pre-Defined Project', "Please use this mode to select from a list of pre-defined projects that have been pre-configured with the most common specifications. This mode is recommended for novice print buyers." );
tips['basic specifications'] = new Array( "Basic Specifications", "Please use this mode to select the size, colour, paper and fold style for your project. Remaining specifications will default to the most common specifications for your project type. This mode is recommended for average print buyers." );

tips['easy specifications'] = tips['basic specifications'];

tips['detailed specifications'] = new Array( "Detailed Specifications:",
"Please use this mode to input detailed press information and select from all possible prepress, press, bindery and post-production services. This mode is recommended for very experienced print buyers." );


// Project Tips

tips['presssheetcombination'] = new Array( 
"Press Sheet Combination:",
"A variety of projects layed out on a single press sheet."
);

tips['multipagepublication'] = new Array( 
"Multi Page Publication:",
"Any printed project containing multiple spreads/pages. Ex. Books, Magazines, Catalogues, Multipage Brochures or Reports etc."
);

tips['padding'] = new Array( 
"Padding:",
"The process of using an adhesive to join pages into a pad form, often with a cardboard backing"
);

tips['saddle stitching'] = new Array( 
"Saddle Stitching:",
"A method of binding a multi page publication which involves the pages being stitched together over a saddle shaped support with wire, which is later cut and bent across the middle pages. The result is a publication which appears to have been stapled together. Usually limited to 64 pages size."
);

tips['loop stitching'] = new Array( 
"Loop Stitching:",
"A method where loop(s) of a single thread are fastened in the center of the fold to bind a multi page publication."
);

tips['proofs'] = new Array( 
"Proof:",
"A copy prepared prior to printing which allows the client to check how colour, photos, type, art and so on, will register and print on the press. Approval of a proof is always necessary before commencement of printing."
);

tips['copy dot'] = new Array( 
"Copy Dot:",
"A high resolution scanning process ideal for magazines, catalogues, books etc."
);

tips['extra burns'] = new Array( 
"Extra Burns:",
"Additional film required due to changes or modifications when film has been supplied."
);

tips['film stripping'] = new Array( 
"Film Stripping:",
"Changes or modifications made to existing pieces of film."
);

/*
tips['shipping'] = new Array( 
"Shipping:",
"**** NEED DESCRIPTION ****"
);
*/


// Printing Tips

tips['decimals'] = new Array( 
"Decimals:",
"Common Fraction to Decimal Conversions:<br> <table cellpadding=\"0\" cellspacing=\"0\" border=\"0\"> <tr><td>1/16 = 0.0625</td><td>1/8 = 0.125</td><td>3/16 = 0.375</td></tr> <tr><td>1/4 = 0.25</td><td>5/16 = 0.3125</td><td>3/8 = 0.375</td></tr> <tr><td>7/16 = 0.4375</td><td>1/2 = 0.5</td><td>9/16 = 0.5625</td></tr> <tr><td>5/8 = 0.625</td><td>11/16 = 0.6875</td><td>3/4 = 0.75</td></tr> <tr><td>13/16 = 0.8125</td><td>7/8 = 0.875</td><td>15/16 = 0.9375</td></tr> </table>");

tips['grip'] = new Array( 
"Grip:",
"The amount of space that is required on the edge(s) of a press sheet to properly feed the stock through the press."
);

tips['flat'] = new Array( 
"Flat Size:",
"The dimensions of a printed piece before it is has been cut or folded."
);

tips['finished'] = new Array( 
"Finished Size:",
"The dimensions of a printed piece after it has been cut or folded up."
);

tips['colours'] = new Array( 
"Colours:",
"The ink colours used on a printed piece."
);

tips['black'] = new Array( 
"Black:",
"Black as a spot ink colour."
);

tips['yellow'] = new Array( 
"Yellow:",
"Yellow as a spot ink colour."
);

tips['cyan'] = new Array( 
"Cyan:",
"Cyan as a spot ink colour."
);

tips['magenta'] = new Array( 
"Magenta:",
"Magenta as a spot ink colour."
);

tips['process'] = new Array( 
"Process Colour:",
"Cyan, Magenta, Yellow and Black. The four basic colours of ink used in process colour printing to allow the full spectrum of colours to be produced on a printing press."
);
tips['4 colour process'] = new Array( 
"Process Colour:",
"Cyan, Magenta, Yellow and Black. The four basic colours of ink used in process colour printing to allow the full spectrum of colours to be produced on a printing press."
);

tips['specialcolours'] = new Array( 
"Special Colours:",
"Any colour other than Black Spot colour or Process colours(CMYK). Special colours may include PMS (Pantone Matching System) numbers and or printer recommended colours"

);
tips['pms'] = new Array( 
"PMS Name/Numbers:",
"The abbreviated name or number from the Pantone colour Matching System. (ie: 320 or reflex blue)"
);

tips['colour_bars'] = new Array( 
"Colour Bars:",
"A quality control term regarding the spots of ink colour on the tail of a sheet to ensure colour accuracy."
);

tips['colour bars'] = tips['colour_bars'];

tips['varnish'] = new Array( 
"Varnish:",
"A finishing process whereby a transparent varnish is applied over the printed sheet to produce a gloss or matte finish for appearance and protection."
);

tips['overall'] = new Array( 
"Overall:",
"A specialty finishing process is applied to the entire side of a printed sheet without the use of a plate."
);

tips['gloss'] = new Array( 
"Gloss:",
"A shiny, transparent specialty finish."
);

tips['spot gloss'] = tips['gloss'];
tips['overall gloss'] = tips['gloss'];

tips['dry_trap'] = new Array( 
"Dry Trap:",
"The ink is allowed to dry before the application of a specialty coating."
);

tips['spot'] = new Array( 
"Spot:",
"A specialty finishing process is applied to only specific areas of printed sheet with the use of a plate."
);

tips['matte'] = new Array( 
"Matte:",
"A dull, transparent specialty finish."
);

tips['spot matte'] = tips['matte'];
tips['overall matte'] = tips['matte'];

tips['aqueous'] = new Array( 
"Aqueous:",
"A process whereby a transparent coating is applied over the entire printed sheet to produce a gloss or matte finish for appearance and protection superior to varnish."
);

tips['waxFree'] = new Array( 
"Wax Free Inks:",
"Inks that do not contain wax. Wax free inks allow for some specialty coatings such as UV coating to adhere properly to a printed piece."
);

tips['bleed'] = new Array( 
"Bleed:",
"Layout, type or pictures that extend beyond the trim marks on a page. Illustrations that spread to the edge of the paper without margins are referred to as 'bled off'."
 
);
tips['printedimage'] = new Array( 
"Printed Image:",
"All printed content including type, images and background of a printed piece."
);

tips['stock'] = new Array( 
"Stock:",
"Paper or other material to be printed on."
);

tips['printerrecommendedstock'] = new Array( 
"Printer Recommended Stock:",
"Paper or other materials suggested by the printer for a particular type of project."
);

tips['stock finish'] = new Array( "Stock Finish:", "Paper or other material texture." );

tips['stock colour'] = new Array( "Stock Colour:", "The Colour of the Paper or other material prior to printing." );
tips['stock color'] = new Array( "Stock Color:", "The Color of the Paper or other material prior to printing." );
tips['stock weight'] = new Array( "Stock Weight:", "The thickness of paper or other material." );
tips['stock calliper'] = new Array( "Stock Weight:", "The thickness of paper or other material." );

tips['stock size'] = new Array( 
"Stock Size:",
"The size of the actual press sheet or roll of paper or other material that the printed piece will be produced on."
);

tips['graindirection'] = new Array( 
"Grain Direction:",
"The direction in which the grain of paper or other material runs."
);

tips['grain direction'] = tips['graindirection'];

tips['imposition'] = new Array( 
"Imposition:",
"Refers to the arrangement of projects or pages on a press sheet or piece of film."
);

tips['runstyle'] = new Array( 
"Run Style:",
"Run style is the style in which a press sheet runs through the printing press. It can be either \"Work and Turn\" \"Work and Tumble\" or \"Sheet Work\"."
);

tips['run style'] = tips['runstyle'];

tips['press sheet quantity'] = new Array( 
"Press Sheet Quantity:",
"The amount of press sheets that run through a printing press."
);

tips['calliper'] = new Array( 
"Calliper:",
"Paper thickness in thousandths of an inch. Also the name of the tool used to make the measurement."
);

tips['blank pages'] = new Array( 
"Blank Pages:",
"Any page in a multipage publication that does not require printing, however it is necessary for overall layout purposes."
);

tips['gate folded'] = new Array( 
"Gate Folded Pages:",
"Oversize pages that fold into the gutter in overlapping layers creating a spread in excess of four pages"
);

tips['different cover'] = new Array( 
"Plus Cover:",
"A cover of a multipage publication that does not match the same specifications (ex. stock or colours) as the interior pages."
);

tips['spreads'] = new Array( 
"Spreads:",
"Contains two page fronts on one side and two page backs on the other side. Spreads are typically folded and/or bound in the middle."
);

tips['signature'] = new Array( 
"Signature:",
"The name given to a printed sheet after it has been folded. Also defines a section of a multi-page publication. Signatures can be made up of multiple spreads and pages and are named appropriately (ex. 4 Page, 8 Page or 16 Page Signatures."
);

tips['printing_plate'] = new Array( 
"Printing Plate:",
"Plates are the carriers of the images that are to be printed on paper. One printing plate is required for each ink colour printed. Metal plates are currently the only way to produce high quality close-register printed images. Plates can also be made out of plastic and paper."
);

tips['printing plate'] = tips['printing_plate'];

tips['ctp'] = new Array( 
"CTP:",
"Printing plates burned directly by the imagesetter from computer images without the use of film"
);

tips['conventional'] = new Array( 
"Conventional:",
"Printing plates created from images on film."
);

// Bindery Tips

tips['die cutting'] = new Array( 
"Die Cutting:",
"The process of using sharp steel dies to cut special shapes in paper, board, or other material."
);

tips['die_cut'] = new Array( 
"Die Cut:",
"The process of using sharp steel dies to cut special shapes in paper, board, or other material."
);

tips['custom die'] = new Array( 
'Custom Die:',
'A custom image or shape formed on a hardened engraving stamp used in die cutting, foil stamping and embossing.'
);

tips['kiss cutting'] = new Array( 
"Kiss Cutting:",
"Cutting the top layer of a pressure sensitive sheet and not the backing. Often used with labels and adhesives."
);

tips['laminating'] = new Array( 
"Laminating:",
"Applying a thin transparent plastic coating to paper or board to provide protection and give it a glossy or matte finish."
);

tips['perforations'] = new Array( 
"Perforations:",
"Small holes or slits punched in a sheet of paper or cardboard to facilitate tearing along a desired line."
);

tips['scores'] = new Array( 
"Scores:",
"Creases applied on the stock to aid in folding.  Scores are often necessary in order to fold thicker materials without cracking."
);

tips['non_continuous'] = new Array( 
"Non-Continuous:",
"Perforations or scores that do not continue the whole distance across the length or width of the flat size of the project."
);

tips['non_parallel'] = new Array( 
"Non-Parrallel:",
"Any perforations or scores that do not run parallel to each other or cross over or are angled."
);

tips['form_sets'] = new Array( 
"Form Set:",
"A complete group of a form that includes all necessary carbon copies."
);

tips['folio lip'] = new Array( 
"Folio Lip:",
"Excess paper needed for binding equipment to grip a folded signature."
);

tips['gussets'] = new Array( 
"Gussets:",
"Extra depth on presentation folder spines and pocket to allow for it to hold more or thicker materials."
);

tips['jog_end'] = new Array( 
"Jog End:",
"The position of an insert when bound into a presentation folder."
);

tips['centred'] = new Array( 
"Centred:",
"The centre position for an insert in a presentation folder."
);

tips['folding'] = new Array( 
"Folding:",
"Process of laying one part over another part of the sheet creating multiple pages"
);

tips['no bindery'] = new Array( 
"No Bindery:",
"No prepress services are required"
);

tips['cutting'] = new Array( 
"Cutting:",
"Process of spliting a sheet into multiple, smaller sheets of a desired dimension"
);

tips['scoring'] = new Array( 
"Scoring:",
"Process of spliting a sheet into multiple, smaller sheets of a desired dimension"
);

tips['perforation'] = tips['perforations'];

// Specialty Tips

tips['embossing'] = new Array( 
"Embossing:",
"Pressing an image into paper so that it will create a raised relief."
);

tips['foil stamping'] = new Array( 
"Foil Stamping:",
"Use of a die and metallic or pigmented coating to press an image into paper creating raised relief and a metallic effect."
);

// Packaging Tips

tips['m_weight'] = new Array( 
"M-Weight:",
"The weight of paper measured per 1,000 sheets"
);

// Prepress Tips

tips['special_finishing_film'] = new Array( 
"Specialty finishing film:",
"Negatives of an image outputted on an imagesetter for the creation of plates used in specialty coatings or finishes."
);

tips['line_screen'] = new Array( 
"Line Screen:",
"The measure of a halftone screen, usually in lines per inch (LPI). When not specified it will be selected by the printer"
);

tips['negative_film'] = new Array( 
"Negative:",
"Film containing an image in which the values of the original are reversed so that the dark areas appear light and vice versa."

);
tips['positive_film'] = new Array( 
"Positive:",
"In photography, film containing the same light and dark values as the original. The reverse of negative."
);

tips['film'] = new Array( 
"Film",
"Negatives of an image outputted on an imagesetter for the creation of plates used in printing that image. (1 piece of film per colour per side)"
);

tips['photo placement'] = new Array( 
"Photo Placement:",
"Process of fitting a photograph into the print job using tools to crop, resize and flop if necessary"
);

tips['additional proofs'] = new Array( 
"Additional Proofs:",
"Multiple copies of the proof may be required if the proof needs to be approved by several departments"
);

tips['cd burning'] = new Array( 
"CD Burning:",
"Process of taking the archived digital files and burn them onto CD. We can also supply a version of any printed publications on CD"
);

tips['scanning'] = new Array( 
"Scanning:",
"If it is not possible for the artwork to be sent to us electronically, we will scan the hardcopy into our computer using a high resolution scanner"
);

tips['colour correction'] = new Array( 
"Colour Correction:",
"Process of filtering and adjusting effects on colour such as brightness and contrast"
);


function tipOn(tipName,blah,e){
	var div = $('tip');
	if ( ! div ) {
		var attrs = {
			id : 'tip',
			'class': 'tipDiv'
		};
		div = new Element('div', attrs);
		document.body.insert( div );
	}
	var tip = tips[tipName.toLowerCase()];
	if ( div && tip ) {
//alert( 'Tip: ' + tip + ' Head: ' + tip[0] + ' Text: ' + tip[1] );
		div.innerHTML = '<div class="tipHead">' + tip[0] + '</div><div class="tipText">' + tip[1] + '</div>';
		show_div( 'tip', e );
	} // end if
}

function tipOff(blah) {	
	$('tip').hide();
	return true;
}	


// Process Mode Tips
function writeTip( word ) {
	if ( tips[word.toLowerCase()] ) {
		document.write( "<a href=\"#\" onMouseOver=\"if ( typeof(tipOn) == 'function' ) { tipOn('"+word+"',3,event); }\" onMouseOut=\"if( typeof(tipOff) == 'function' ) {tipOff('"+word+"'); };\">"+word+"</a>");
	} else {
		document.write( word );
	} // end if
} // end function writeTipLink
function writeTipLink( document , word ) {
	if ( tips[word] ) {
		document.write( "<a href=\"#\" onMouseOver=\"if ( typeof(tipOn) == 'function' ) { tipOn('"+word+"',3,event); }\" onMouseOut=\"if( typeof(tipOff) == 'function' ) {tipOff('"+word+"'); };\">"+word+"</a>");
	}else {
		document.write( word );
	} // end if
} // end function writeTipLink

