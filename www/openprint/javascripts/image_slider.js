
// set the starting image.
var i = 0;          

// The time to wait before moving to the next image. Set to 3 seconds by default.
var wait = 4000;

// The Fade Function
function SwapImage(x,y) {
	var x_image = $(image_slide[x]);
	var y_image = $(image_slide[y]);
	var x_height = x_image.getHeight();
	var y_height = y_image.getHeight();
	var ul = x_image.up();

	if ( x_height > y_height ) {
		ul.setStyle( {height: x_height+"px" } );
	}
		
    x_image.appear({ duration: 1.5 });
    y_image.fade({duration: 1.5});

	if ( x_height < y_height ) {
		ul.setStyle( {height: x_height+"px" } );
	}
}

// the onload event handler that starts the fading.
function StartSlideShow() {
    play = setInterval('Play()',wait);
	var playbutton = $('PlayButton');
	if ( playbutton ) $('PlayButton').hide();
	var pausebutton = $('PauseButton');
    if ( pausebutton ) $('PauseButton').appear({ duration: 0});
                                
}

function Play() {
    var imageShow, imageHide;

    imageShow = i+1;
    imageHide = i;
    
    if (imageShow == image_slide.length) {
        SwapImage(0,imageHide); 
        i = 0;                  
    } else {
        SwapImage(imageShow,imageHide);         
        i++;
    }
}

function Stop () {
    clearInterval(play);                
	var playbutton = $('PlayButton');
	var pausebutton = $('PauseButton');
	if ( playbutton ) playbutton.appear({ duration: 0});
    if ( pausebutton ) pausebutton.hide();
}

function GoNext() {
    clearInterval(play);
	var playbutton = $('PlayButton');
	var pausebutton = $('PauseButton');
    if ( playbutton ) playbutton.appear({ duration: 0});
    if(pausebutton) pausebutton.hide();
	Play();
}

function GoPrevious() {
    clearInterval(play);
	var playbutton = $('PlayButton');
	var pausebutton = $('PauseButton');
    if ( playbutton ) playbutton.appear({ duration: 0});
    if( pausebutton ) pausebutton.hide();

    var imageShow, imageHide;
                
    imageShow = i-1;
    imageHide = i;
    
    if (i == 0) {
        SwapImage(image_slide.length -1,imageHide); 
        i = image_slide.length -1;     
        
        //alert(NumOfImages-1 + ' and ' + imageHide + ' i=' + i)
                    
    } else {
        SwapImage(imageShow,imageHide);         
        i--;
        
        //alert(imageShow + ' and ' + imageHide)
    }
}
