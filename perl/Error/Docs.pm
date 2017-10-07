package Error::Docs;
 
use strict; 
use warnings; 
 
use Apache2::Request; 
use Apache2::Const qw(:common); 
use session;
 
sub handler
{
    my $r = shift; 
    $r->content_type ('text/html');
    my $serveradmin = $r->server->server_admin();

    session::r($r);
    session::r($r->log);

    print qq{
        <html>
            <head>
                <title>Internal Server Error</title>

                <script language="javascript" src="/javascripts/detect.js"></script>
                <script language="javascript">var userType = "<?user_type?>";</script>
                <script language="javascript" src="/javascripts/other.js"></script>
                <script language="javascript">document.write(styleSheet);</script>
                <link href="/site_specific/styles/colors.css" rel="stylesheet" type="text/css">
                <link href="/styles/main.css" rel="stylesheet" type="text/css">
                <!--#include virtual="/site_specific/includes/web_page_meta.html" -->

            </head>
       	    <body marginwidth="0" marginheight="0" onload="">
                <!--#include virtual="/site_specific/includes/main/proj.html" -->
        		<!--#include virtual="/includes/main/marks/mark2.html" -->		
		        <!--#include virtual="/site_specific/includes/main/bann.html" -->
                
                <div id="title" class="titleCSS"><img src="/site_specific/images/main/titles/error.gif"></div>
	
                <div style="position:absolute; left:311px; top:0px; height:60px;">
                    <img src="/images/site_specific/banner.gif" width="468" height="60" border="0" />
                </div>
                <div id="content" class="ContentCSS">
                    <p>Unfortunately we are temporarily having trouble processing your request. 
                    Please try again in a moment. If you continue to recieve this error please 
                    contact $serveradmin.</p>
                </div>
            </body>
        </html>
    };

    return SERVER_ERROR;
}

1;
