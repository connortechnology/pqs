package eprint::banner;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY); # Offers OK, Error, etc for web server.
use strict;

use sql ();
require ssi;

sub banner_action {
    my ( $r, $log, $dbh, $variable ) = @_;
    my ( $temp );

	my $banner_id = $r->param('ddmBanner');
    if ( $r->param('btnFunction') eq 'Save' ) {

        if ( $banner_id eq '' ) { # new banner
			if ( $r->param('fileBannerImage') eq '' ) {
            	return misc::error( $log, $dbh, $variable, 'No Image given.', 'You must specify an image to upload when you create a new banner.' );    
            } # end if

 			$_ = "SELECT lngIndex FROM tbl_Banners WHERE strName='" . $r->param('txtBannerName') . "'";
			if ( sql::sql_statement( $log, $dbh, $_ ) ) {
            	return misc::error( $log, $dbh, $variable, "Banner Already Exists.", "There is already a banner with the given name.  Please choose a different name.");    
            } # end if

			sql::insert( $log, $dbh, 'tbl_Banners', (
					'strName',	$r->param('txtBannerName'),
					'strClickURL',$r->param('txtBannerURL') ));

			$_ = "SELECT MAX(lngIndex) from tbl_Banners WHERE strName='" . $r->param('txtBannerName') . "'";
			($banner_id) = sql::sql_statement( $log, $dbh, $_ );
			if ( ! $banner_id ) {
            	return misc::error( $log, $dbh, $variable, "Error creating banner.", "The banner creation failed.");    
			} # end if

        } else {
			sql::update( $log, $dbh, 'tbl_Banners', "lngIndex = '$banner_id'",
				'strName',		$r->param('txtBannerName'),
				'strClickURL',	$r->param('txtBannerURL') 
			);

			$_ = "DELETE FROM tbl_Banners_in_Categories WHERE lngBannerIndex = '$banner_id'";
			sql::sql_statement( $log, $dbh, $_ );

        } # end if

		foreach my $categoryid ( $r->param('selectCategories') ) {
			sql::insert( $log, $dbh, 'tbl_Banners_in_Categories', 
				'lngCategoryIndex', $categoryid,
				'lngBannerIndex', $banner_id 
			);
		} # end for
		# handle the image.
		if ( $r->param('fileBannerImage') ne '' ) {
			my $filename = $r->param('fileBannerImage');
			$filename =~ s/.*[\/\\](.+)/$1/;
			my $desturl = "/images/banners/$filename";
			my $dest = $ENV{'DOCUMENT_ROOT'} . $desturl;

			$_ = "SELECT lngIndex FROM tbl_Banners WHERE strImageURL = '$dest' AND lngIndex != '$banner_id'";
			if ( sql::sql_statement( $log, $dbh, $_ ) ) {
				return misc::error( $log, $dbh, $variable, "Conflicting image.", "Another banner uses the same filename. The image was not uploaded.  Please select your banner and upload the image using a different filename.");    
			} else {
				if ( misc::save_file( $log, $dest, misc::get_upload( $r, $log, 'fileBannerImage' ) ) ) {
					sql::update( $log, $dbh, 'tbl_Banners', "lngIndex = '$banner_id'", 'strImageURL', $filename );
				} else {
					return misc::error( $log, $dbh, $variable, "Error uploading image.", "There was an error uploading the specified image.");    
				} # end if
			} # end if
		} # end if

    } elsif ( $r->param('btnFunction') eq '>>' ) {
		#we need to return a failure if there is no banner selected at all
		return misc::error($log,$dbh,$variable,'No Banner selected') unless $r->param('txtBannerName');
		$banner_id = misc::nav_get_next( $r, $log, $dbh, $banner_id, 'lngIndex', 'tbl_Banners', '' ,'strName' );
    } elsif ( $r->param('btnFunction') eq '<<' ) {
		#we need to return a failure if there is no banner selected at all
		return misc::error($log,$dbh,$variable,'No Banner selected') unless $r->param('txtBannerName');
		$banner_id = misc::nav_get_previous( $r, $log, $dbh, $banner_id, 'lngIndex', 'tbl_Banners', '' ,'strName' );
    } elsif ( $r->param('btnFunction') eq 'Delete' ) {
		#we need to return a failure if there is no banner selected at all
		return misc::error($log,$dbh,$variable,'No Banner selected') unless $r->param('txtBannerName');
        $temp = "DELETE FROM tbl_Banners WHERE lngIndex = '$banner_id'";
		sql::sql_statement( $log, $dbh, $temp );

        $temp = "DELETE FROM tbl_Banners_in_Categories WHERE lngBannerIndex = '$banner_id'";
		sql::sql_statement( $log, $dbh, $temp );

        $temp = "SELECT MIN(lngIndex) from tbl_Banners WHERE lngIndex > '$banner_id'";
        ($banner_id) = sql::sql_statement( $log, $dbh, $temp);
        if ( $banner_id eq '' ) {
			$temp = "SELECT MAX(lngIndex) from tbl_Banners";
			($banner_id) = sql::sql_statement( $log, $dbh, $temp);
        } # endif
    } # end if

    if ( $banner_id ne '' ) {
		$temp = "SELECT strName, strImageURL, strClickURL FROM tbl_Banners WHERE lngIndex = '$banner_id'";
		@$variable{'BANNER_NAME', 'BANNER_IMAGE', 'BANNER_URL'} = sql::sql_statement( $log, $dbh, $temp );

		my $search = 'SELECT lngIndex, strName FROM tbl_Marketing_Categories';
		$temp = "SELECT lngCategoryIndex FROM tbl_Banners_in_Categories WHERE lngBannerIndex = '$banner_id'";
		my @data = sql::sql_statement( $log, $dbh, $temp );
		$$variable{'FILL_CUSTOMER_CATEGORIES'} = ssi::fill_select( $log, $dbh, $search, 20, @data );

		$$variable{'BANNER_ID'} = $banner_id;
    } # end if

    my $search = "SELECT lngIndex, strName from tbl_Banners ORDER BY lngIndex";
    $$variable{'FILL_BANNER_NAME'} = ssi::fill_drop_down( $log, $dbh, $search, $banner_id, 20 );

    return OK;

} # end sub banner_action

sub select_banner {
    my ( $log, $dbh, $cust_id, $user_id ) = @_;

    my @banners = ();

    $_ = "SELECT lngBannerIndex\n".
	    "FROM tbl_Banners_in_Categories\n".
	    "WHERE lngCategoryIndex IN (SELECT lngCategoryID FROM tbl_Customers_in_Categories WHERE lngCustomerID='$cust_id')";
    push @banners, sql::sql_statement( $log, $dbh, $_ ) if $cust_id; 
    $_ = "SELECT lngBannerIndex\n".
	    "FROM tbl_Banners_in_Categories\n".
	    "WHERE lngCategoryIndex IN (SELECT lngCategoryIndex FROM tbl_Users_in_Categories WHERE lngUserIndex='$user_id')";
    push @banners, sql::sql_statement( $log, $dbh, $_ ) if $user_id; 
    if ( @banners == 0 ) {
	    $_ = "SELECT lngBannerIndex\n".
		    "FROM tbl_Banners_in_Categories\n".
		    "WHERE lngCategoryIndex = ( SELECT lngIndex FROM tbl_Marketing_Categories WHERE strName = 'default' )";
	    @banners = sql::sql_statement( $log, $dbh, $_ ); 
    } # end if

    my $banner = '';
    if ( @banners ) {
	    my $whichone = int(rand scalar(@banners));

	    my ( $imageurl, $clickurl )  = sql::sql_statement( $log, $dbh, qq{ SELECT strImageURL, strClickURL FROM tbl_Banners WHERE lngIndex = $banners[$whichone] }); 

	    $banner = qq{<img src="/images/banners/$imageurl" />};

# Add a link around the banner if it has a URL associated with it.
	    if ($clickurl) {
		    $banner = qq{<a href="$clickurl" target="_blank">$banner</a>};
	    }
    }
    return $banner;
}

1;

__END__
~       
