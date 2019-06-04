package eprint::quote;
use strict;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY); # Offers OK, Error, etc for web server.
use MIME::QuotedPrint;
use MIME::Base64;
use Mail::Sendmail;
use Data::Dumper;
use session;

use sql ();

require ssi;
require misc;
require configuration;
require eprint::customer;
require eprint::project;
require eprint::print;
require eprint::order;

# deletes all traces of the specified quote
sub delete_quote {
	my ( $log, $dbh, $quote ) = @_; 
	sql::sql_statement( $log, $dbh, "DELETE FROM tbl_Quote_Details WHERE lngQuoteID = '$quote'" );
	sql::sql_statement( $log, $dbh, "DELETE FROM tbl_Quote_Users_By WHERE lngQuoteID = '$quote'" );
	sql::sql_statement( $log, $dbh, "DELETE FROM tbl_Quote_Users_For WHERE lngQuoteID = '$quote'" );
	sql::sql_statement( $log, $dbh, "DELETE FROM tbl_Quotes WHERE lngQuoteID = '$quote'" );
} # end sub delete_quote

#remove all quotes associated with a customer
sub delete_customers_quotes {
  my ($log, $dbh, $id) = @_;

  $id =~ tr/0-9//cd;

  # die "Invalid quote ID." unless $id;
  return unless $id;

  my $quotes = $dbh->selectcol_arrayref("select lngquoteid from tbl_quotes where lngcustomerid = ?", undef, $id);
  for my $quote (@$quotes) {
    delete_quote($log, $dbh, $quote);
  }
}

#remove all quotes associated with a user
sub delete_users_quotes {
  my ($log, $dbh, $id) = @_;

  $id =~ tr/0-9//cd;

  # die "Invalid quote ID." unless $id;
  return unless $id;

  my $quotes = $dbh->selectcol_arrayref("select lngquoteid from tbl_quotes where lnguserid = ?", undef, $id);
  for my $quote (@$quotes) {
    delete_quote($log, $dbh, $quote);
  }

  $quotes = $dbh->selectcol_arrayref("select lngquoteid from tbl_quotes where lngemployeeid = ?", undef, $id);
  for my $quote (@$quotes) {
    delete_quote($log, $dbh, $quote);
  }
}

sub delete_unfinished_quotes {
	my ( $log, $dbh, $cookie ) = @_;

	$_ = "SELECT lngQuoteID FROM tbl_Quotes WHERE strSessionID = '$cookie' AND strStatus='Incomplete'";
	foreach my $quote ( sql::sql_statement( $log, $dbh, $_ ) ) {
		delete_quote( $log, $dbh, $quote );
	} # end foreach
} # end sub delete_unfinished_quotes

sub get_unfinished_quote_id {
	my ( $log, $dbh, $cookie, $my_cust_id, $my_user_id ) = @_;

    $_ = "SELECT MAX(lngQuoteID) FROM tbl_Quotes WHERE strSessionID='$cookie' AND strStatus='Re-Opened'";
    my ( $quote_id ) = sql::sql_statement( $log, $dbh, $_ );

    if ( ! $quote_id ) {
		$_ = "SELECT lngQuoteID, lngCustomerID, lngUserID FROM tbl_Quotes WHERE strSessionID = '$cookie' AND strStatus='Incomplete' ORDER BY 1 desc limit 1";
		( $quote_id, my $cust_id, my $user_id ) = sql::sql_statement( $log, $dbh, $_ );

#        die "SESSION: $cookie QUOTE ID: $quote_id";
        
		if ( $quote_id ) {
			if ( $cust_id != $my_cust_id ) {
				sql::update( $log, $dbh, 'tbl_Quotes', "lngQuoteID = '$quote_id'", 'lngCustomerID', $my_cust_id );
			} # end if
			if ( $user_id != $my_user_id ) {
				sql::update( $log, $dbh, 'tbl_Quotes', "lngQuoteID = '$quote_id'", 'lngUserID', $my_user_id );
			} # end if
		} # end if
	} # end if
	
	return $quote_id;
} # end sub get_unfinished_quote_id

sub generate_quote {
	my ( $r, $log, $dbh, $cookie, $variable ) = @_;
	my ( $temp, $quote_id );

	if ( $r->param('btnFunction') eq 'Process New Quote' and $r->param('quote_id') ne '' ) {
		$quote_id = make_quote_from_quote( $r, $log, $dbh, $cookie, $$variable{'cust_id'}, $$variable{'user_id'}, $r->param('quote_id') );
	} elsif ( $r->param('remove') ne '' ) {
		my $project_index = $r->param('remove');
		$_ = "DELETE FROM tbl_Quote_Details WHERE lngProjectIndex='$project_index'";
		sql::sql_statement($log, $dbh, $_);
	} elsif ( $r->param('btnFunction') eq "Process Quote" ) {

		$quote_id = add_project_to_quote( $r, $log, $dbh, $$variable{'cust_id'}, $$variable{'user_id'}, $cookie );

	} elsif ( $r->param('btnFunction') eq "ReOpen" ) {
		delete_unfinished_quotes( $log, $dbh, $cookie );
		$quote_id = $r->param('quote_id');
		sql::update( $log, $dbh, 'tbl_Quotes', "lngQuoteID='$quote_id'", 'strStatus', 'Re-Opened', 'strSessionID', $cookie );
	} # end if

	# this should only happen if there was an error creating the quote
	$quote_id = get_unfinished_quote_id( $log, $dbh, $cookie, $$variable{'cust_id'}, $$variable{'user_id'} ) if $quote_id == 0;

    $variable->{quote_id} = $quote_id;
    
	#get_user_by_info( $log, $dbh, $variable, $quote_id );
	#get_user_for_info( $log, $dbh, $variable, $quote_id );
	get_misc_info( $log, $dbh, $variable, $quote_id );
	get_unfinished_quote_contents( $log, $dbh, $variable, $quote_id );

	# get all items in the quote
#Comment this out for now.
#	@{ $variable->{PRODUCTINFO}} = @{ $dbh->selectall_arrayref(q{
#        select s.id, s.name, sum(c.quantity * p.price) as cost 
#		from tbl_quote_details as o 
#		left join tbl_shopping_lists as s on o.lngProjectIndex = s.id 
#		left join tbl_shopping_lists_contents as c on s.id = c.shopping_list_id 
#		left join tbl_products as p on p.id = c.product_id 
#		where o.lngQuoteId = ? group by s.id, s.name
#    }, {Slice => {}}, $quote_id) };

	return OK;
} # end sub generate_quote

sub get_unfinished_quote_contents {
	my ( $log, $dbh, $variable, $quote_id ) = @_;
	@{$$variable{'PROJECTS'}} = ();

	my $subtotal1 = 0;
	my $subtotal2 = 0;
	my $subtotal3 = 0;

    # Select all the project within the quote (really we should loop per
    # record instead of getting the whole result set then looping... but for
    # now this is it).
    my @projects = @{ $dbh->selectcol_arrayref(q{
        SELECT lngProjectIndex 
        FROM tbl_Quote_Details 
        WHERE lngQuoteID = ?
    }, undef, $quote_id) };
	
    foreach my $project_index ( @projects ) {
		$_ = "SELECT dblMarkup1, dblMarkup2, dblMarkup3 FROM tbl_Quote_Details WHERE lngQuoteID='$quote_id' AND lngProjectIndex='$project_index'";		
		my ( $markup1, $markup2, $markup3 ) = sql::sql_statement( $log, $dbh, $_ );
		my ( $reference, $qty1, $qty2, $qty3, $price1, $price2, $price3 ) = get_project_info( $log, $dbh, $project_index );
		my $newprice1 = sprintf( "%.2f",($price1*(1+($markup1/100))));
		my $newprice2 = sprintf( "%.2f",($price2*(1+($markup2/100))));
		my $newprice3 = sprintf( "%.2f",($price3*(1+($markup3/100))));
		$subtotal1 += $newprice1;
		$subtotal2 += $newprice2;
		$subtotal3 += $newprice3;
		my $lastindex = 3;
		$lastindex = 2
			if ! $qty3;
		$lastindex =1 
			if ! $qty2;
		push @{$$variable{'projects'}},{
			project_index => $project_index,
			reference     => $reference,
			index         => 1,
			markup        => $markup1,
			qty           => $qty1,
			stdprice      => sprintf( "%.2f", $price1),
			newprice      => $newprice1,
			lastindex     => $lastindex,
		} if $qty1;
		push @{$$variable{'projects'}},{
			project_index => $project_index,
			reference     => $reference,
			index         => 2,
			markup        => $markup2,
			qty           => $qty2,
			stdprice      => sprintf( "%.2f", $price2),
			newprice      => $newprice2,
			lastindex     => $lastindex,
		} if $qty2;
		push @{$$variable{'projects'}},{
			project_index => $project_index,
			reference     => $reference,
			index         => 3,
			markup        => $markup3,
			qty           => $qty3,
			stdprice      => sprintf( "%.2f", $price3),
			newprice      => $newprice3,
			lastindex     => $lastindex,
		} if $qty3;

		push @{$$variable{"PROJECT_PRICES_$project_index"}}, 
						$markup1, $qty1, undef, $newprice1, undef,
						$markup2, $qty2, undef, $newprice2, undef,
						$markup3, $qty3, undef, $newprice3, undef,
	} # end foreach

	$variable->{LIST_PROJECTS} = [ 
		{projects => $variable->{projects1}, n=>1, TOTAL=> $subtotal1}, 
		{projects => $variable->{projects2}, n=>2, TOTAL=> $subtotal2},  
		{projects => $variable->{projects3}, n=>3, TOTAL=> $subtotal3} 
	];  

	push @{$$variable{'totals'}}, {
		index => 1,
		total => sprintf( "%.2f", $subtotal1),
	};
	push @{$$variable{'totals'}}, {
		index => 2,
		total => sprintf( "%.2f", $subtotal2),
	};
	push @{$$variable{'totals'}}, {
		index => 3,
		total => sprintf( "%.2f", $subtotal3),
	};

} # end sub get_unfinished_quote_contents

sub commit_quote {
    my ( $log, $dbh, $quote_id ) = @_;

    my $subtotal1 = 0;
    my $subtotal2 = 0;
    my $subtotal3 = 0;

    $_ = "SELECT lngProjectIndex FROM tbl_Quote_Details WHERE lngQuoteID='$quote_id' AND type='print'";

    foreach my $project_index ( sql::sql_statement( $log, $dbh, $_ ) ) {
        $_ = "SELECT dblMarkup1, dblMarkup2, dblMarkup3 FROM tbl_Quote_Details WHERE lngQuoteID='$quote_id' AND lngProjectIndex='$project_index'";
        my ( $markup1, $markup2, $markup3 ) = sql::sql_statement( $log, $dbh, $_ );
        my ( $reference, $qty1, $qty2, $qty3, $price1, $price2, $price3 ) = get_project_info( $log, $dbh, $project_index );
        $subtotal1 += $price1*(1+($markup1/100));
        $subtotal2 += $price2*(1+($markup2/100));
		$subtotal3 += $price3*(1+($markup3/100));
		sql::update( $log, $dbh, 'tbl_Quote_Details', "lngQuoteID='$quote_id' AND lngProjectIndex='$project_index'",
				'strDescription',	$reference,
				'intQuantity1',	$qty1, 'dblPrice1', $price1,
				'intQuantity2', $qty2, 'dblPrice2', $price2,
				'intQuantity3', $qty3, 'dblPrice3', $price3,
				);
	
    } # end foreach
	sql::update( $log, $dbh, 'tbl_Quotes', "lngQuoteID='$quote_id'",'curTotalSale1', $subtotal1, 'curTotalSale2', $subtotal2, 'curTotalSale3', $subtotal3 );
	
} # end sub commit_quote

sub get_quote_id {
	my ( $log, $dbh ) = @_;
	my ( $quote ) = sql::sql_statement( $log, $dbh, "SELECT MAX(lngQuoteID) FROM tbl_Quotes" );
	$quote =~ /(\d\d\d\d)/;
	if ( $1 != ( 1900 + (localtime(time))[5]) or $quote eq '' ) {
		return (1900 + (localtime(time))[5]) . '0001';
	} # end if
	return $quote + 1;
} # end sub get_quote_id


# this page displays the user info page.
# It also processes and stores the information from the details page, in terms of markup, etc.
sub user_quote_info {
	my ( $r, $log, $dbh, $cookie, $variable ) = @_;


	my $action = $r->param('action');
	my $quote_id;


	print STDERR "ACTION IS: $action \n";

	if ($action eq 'Product Quote') {
		$quote_id = create_quote( $log, $dbh, $cookie,  $$variable{'cust_id'}, $$variable{'user_id'} );
		my $order_id ||= eprint::order::get_unfinished_order( $log, $dbh, $cookie, $variable->{cust_id}, $variable->{user_id});
		my $list = PQS::model::order::get_order_products($order_id);

		print STDERR "HAVE LIST", Dumper($list);
		foreach my $o ( @{$list} ) {

				my $pname = PQS::model::products::get_name_from_id($o->{product});

				$dbh->do(q{
					INSERT into tbl_quote_details ( lngquoteid, lngprojectindex, intquantity1, dblprice1, type, product, label ) 
					VALUES ( ?, ?, ?, ?, ?, ?, ? ) 
					}, undef, $quote_id, 0, $o->{intquantity}, $o->{cursalesprice}, 'product',$o->{product},  $o->{jobname} . " - $pname"
				);
		}

		$dbh->do(q{DELETE FROM tbl_order_contents WHERE lngorderid = ? }, undef, $order_id);

	} else {
		$quote_id = get_unfinished_quote_id( $log, $dbh, $cookie, $$variable{'cust_id'}, $$variable{'user_id'} );
	}

	
	if ( $r->param('GroupPricing') ) {
		$dbh->do(qq{UPDATE tbl_quotes set ShowPricing = false WHERE lngquoteid = $quote_id});
	}

	# store fields from recalculate, we only store the markup, the NewPrices will calculate on the fly
	foreach my $key ( $r->param() ) {
		if ( $key =~ /txtMarkup(\d+)_(\d+)/ ) {
			sql::update( $log, $dbh, 'tbl_Quote_Details', "lngQuoteID = '$quote_id' AND lngProjectIndex = '$2'",
				'dblMarkup'.$1,	$r->param($key) ne '' ? $r->param($key) : 0,
			);
		} # end if
	} # end foreach

	$_ = "SELECT lngCustomerID FROM tbl_Customer_Users WHERE lngUserID='$$variable{'user_id'}'";
	my ( $cust_id ) = sql::sql_statement( $log, $dbh, $_ );

	if ( ! get_user_for_info( $log, $dbh, $variable, $quote_id ) ) {

		if ( $cust_id != $$variable{'cust_id'} ) {
			# pull information to pre-fill input fields
			$_ = "SELECT strCompanyName, strAddress1, strAddress2, strCity, strProvState, strPostalCodeZip, strCountry, strPhone, strExt, strFax ".
				"FROM tbl_Customer ".
				"WHERE lngCustomerID = '$$variable{'cust_id'}' ";
			@$variable{'ForCompanyName', 'ForAddress1', 'ForAddress2', 'ForCity', 'ForStateProvince', 'ForPostalCode', 'ForCountry',
				'ForPhone','ForExtension', 'ForFax' } = sql::sql_statement( $log, $dbh, $_ );

			 $_ = "SELECT strEmail, strFirstName || ' ' ||  strLastName FROM tbl_Customer_Users  WHERE lngCustomerID = '$$variable{'cust_id'}' ";
			 $$variable{'ddmQuoteForUsers'} = ssi::fill_drop_down( $log, $dbh, $_ ); 
		} # end if
	} # end if

	if ( ! get_user_by_info( $log, $dbh, $variable, $quote_id ) ) {
		# pull information to pre-fill input fields
		$_ = "SELECT strCompanyName, strAddress1, strAddress2, strCity, strProvState, strPostalCodeZip, strCountry, strPhone, strExt, strFax ".
			"FROM tbl_Customer ".
			"WHERE lngCustomerID = '$cust_id' ";
		@$variable{'ByCompanyName', 'ByAddress1', 'ByAddress2', 'ByCity', 'ByStateProvince', 'ByPostalCode', 'ByCountry', 'ByPhone', 'ByExtension', 'ByFax'} = sql::sql_statement( $log, $dbh, $_ );

	} # end if

	if ( $$variable{'ByEmail'} eq '' ) {
		$_ = "SELECT strEmail,strTitle, strFirstName, strLastName, strSalutation FROM tbl_Customer_Users WHERE lngUserID='$$variable{'user_id'}'";
		@$variable{'ByEmail','ByTitle','ByFirstName','ByLastName','BySalutation'} = sql::sql_statement( $log, $dbh, $_ );
	} # end if

	$$variable{'ByStateProvince'} = ssi::return_states_and_provinces($$variable{'ByStateProvince'});
	$$variable{'ByCountry'} = ssi::return_countries($$variable{'ByCountry'});
	$$variable{'ForStateProvince'} = ssi::return_states_and_provinces($$variable{'ForStateProvince'});
	$$variable{'ForCountry'} = ssi::return_countries($$variable{'ForCountry'});
	
    $$variable{'BySalutation'.$$variable{'BySalutation'}} = 'CHECKED';
    $$variable{'ForSalutation'.$$variable{'ForSalutation'}} = 'CHECKED';
} # end sub user_quote_info

sub store_quote_info {
	my ( $r, $log, $dbh, $quote_id, $variable ) = @_;
	my %by;
	my %for;
	foreach my $key ( $r->param() ) {
		if ( $key =~ /^By/ ) {
			$by{$key} = $r->param($key);
		} elsif ( $key =~ /^For/ ) {
			$for{$key} = $r->param($key);
		} # end if
	} # end foreach

         if (( $r->param('ForFirstName') ne '' ) or
                    ( $r->param('ForLastName') ne '' ) or
                    ($r->param('ForCompanyName') ne '') or
                    ( $r->param('ForTitle') ne '' ) or
                    ( $r->param('ForSalutation') ne '' ) or
                    ( $r->param('ForAddress1') ne '') or
                    ( $r->param('ForAddress2') ne '') or
                    ( $r->param('ForCity')  ne '') or
                    ( $r->param('ForStateProvince') ne '' ) or
                    ( $r->param('ForCountry') ne '') or
                    ( $r->param('ForPostalCode') ne '') or
                    ( $r->param('ForPhone') ne  '' ) or
                    ( $r->param('ForExtension') ne '') or
                    ( $r->param('ForFax') ne '') or
                    ( $r->param('ForEmail') ne '') ) {
		my $error = "";
		#$error .= 'No prepared for address entered.<br>' if $r->param('ForAddress1') eq '';
		#$error .= 'No prepared for city entered.<br>' if $r->param('ForCity') eq '';
		#$error .= 'No prepared for state entered.<br>' if $r->param('ForStateProvince') eq '' and $r->param('ForOtherStateProvince') eq '';
		#$error .= 'No prepared for postal code entered.<br>' if $r->param('ForPostalCode') eq '';
		#$error .= 'No prepared for country entered.<br>' if $r->param('ForCountry') eq ''; 
		#$error .= 'No prepared for phone number entered.<br>' if $r->param('ForPhone') eq '';
		$error .= 'No prepared for First Name entered.<br>' if $r->param('ForFirstName') eq '';
		$error .= 'No prepared for Last Name entered.<br>' if $r->param('ForLastName') eq '';
		$error .= 'No prepared for email address entered.<br>' if $r->param('ForEmail') eq '';
		if ( $error ne '' ) {
			misc::error( $log, $dbh, $variable, 'Bad field.', $error );
			return HTTP_MOVED_TEMPORARILY;
		} # end if
	}else {

		foreach my $key ( keys %by ) {
			$key =~ /By(.*)/;
			$for{'For'.$1} = $by{$key};
		} # end foreach
	}
		if ( $r->param('ForStateProvince') eq '' ) {
			$r->param('ForStateProvince') => $r->param('ForOtherStateProvince');
		} # end if

	store_user_by_info( $log, $dbh, $quote_id, \%by );
	store_user_for_info( $log, $dbh, $quote_id, \%for );

	return OK;
} # end sub store_quote_info

sub store_user_by_info {
	my ( $log, $dbh, $quote_id, $variable ) = @_;

	sql::sql_statement( $log, $dbh, "DELETE FROM tbl_Quote_Users_By WHERE lngQuoteID = '$quote_id'" );
	sql::insert( $log, $dbh, 'tbl_Quote_Users_By',
			'lngQuoteID',		$quote_id,
			'strFirstName',		$$variable{'ByFirstName'},
			'strLastName',		$$variable{'ByLastName'},
			'strCompanyName',	$$variable{'ByCompanyName'},
			'strTitle',			$$variable{'ByTitle'},
			'strSalutation',	$$variable{'BySalutation'},
			'strAddress',		$$variable{'ByAddress1'},
			'strAddress2',		$$variable{'ByAddress2'},
			'strCity',			$$variable{'ByCity'},
			'strState',			$$variable{'ByStateProvince'},
			'strCountry',		$$variable{'ByCountry'},
			'strPostalCode',	$$variable{'ByPostalCode'},
			'strPhone',			$$variable{'ByPhone'},
			'strExt',			$$variable{'ByExtension'},
			'strFax',			$$variable{'ByFax'},
			'strEmail',			$$variable{'ByEmail'}
			);

} # end sub store_user_by_info

sub store_user_for_info {
	my ( $log, $dbh, $quote_id, $variable ) = @_;

	sql::sql_statement( $log, $dbh, "DELETE FROM tbl_Quote_Users_For WHERE lngQuoteID = '$quote_id'" );
	sql::insert( $log, $dbh, 'tbl_Quote_Users_For',
			'lngQuoteID',		$quote_id,
			'strFirstName',		$$variable{'ForFirstName'},
			'strLastName',		$$variable{'ForLastName'},
			'strCompanyName',	$$variable{'ForCompanyName'},
			'strTitle',			$$variable{'ForTitle'},
			'strSalutation',	$$variable{'ForSalutation'},
			'strAddress',		$$variable{'ForAddress1'},
			'strAddress2',		$$variable{'ForAddress2'},
			'strCity',			$$variable{'ForCity'},
			'strState',			$$variable{'ForStateProvince'},
			'strCountry',		$$variable{'ForCountry'},
			'strPostalCode',	$$variable{'ForPostalCode'},
			'strPhone',			$$variable{'ForPhone'},
			'strExt',			$$variable{'ForExtension'},
			'strFax',			$$variable{'ForFax'},
			'strEmail',			$$variable{'ForEmail'}
		);
} # end sub store_user_for_info

sub submit_quote {
	my ( $r, $log, $dbh, $cookie, $variable ) = @_;
	
	my $quote_id = get_unfinished_quote_id( $log, $dbh, $cookie, $$variable{'cust_id'}, $$variable{'user_id'} );
	
	if (!$quote_id && $r->param('ProjectIndex') ) {
		$variable->{Redirect} = '/main/proj/proj_view.html';
		return;
	}

    $variable->{quote_id} = $quote_id;

	if ( $r->param('btnFunction') eq 'Continue' ) {
		$_ = store_quote_info( $r, $log, $dbh, $quote_id, $variable );
		return $_ if $_ != OK;
	} elsif (  $r->param('Delete') ) {
		my $pid = $r->param('Delete');
		$dbh->do(q{
			DELETE FROM tbl_quote_details WHERE lngprojectindex = ? AND lngquoteid = ?
		}, undef,  $pid, $quote_id);
	} # end if

    get_user_by_info( $log, $dbh, $variable, $quote_id );
    get_user_for_info( $log, $dbh, $variable, $quote_id );
	get_misc_info( $log, $dbh, $variable, $quote_id );
    $$variable{'CCITYPROV'} = misc::build_city_prov_country(@$variable{'ByCity','ByStateProvince','ByCountry'} );
    $$variable{'FCITYPROV'} = misc::build_city_prov_country(@$variable{'ForCity','ForStateProvince','ForCountry'} );
    my @pids =  @{$dbh->selectcol_arrayref(q{
        SELECT lngprojectindex
        FROM tbl_quote_details
        WHERE lngquoteid= ? and type = 'print'
    }, undef, $quote_id)};
    for my $pid (@pids) {   
	my %hash;
	$hash{cust_id} = $$variable{cust_id};
	eprint::docket::summary_display($r, $log, $dbh, \%hash, $pid, undef, -1);
	push @{$$variable{attachedProjects}}, \%hash;
		$variable->{supplier_chino} = eprint::order::is_chino($dbh, $pid);
    }

	$variable->{PRODUCTS} = get_products( $quote_id );

    if ( $$variable{'user_type'} eq 'A' or $$variable{'user_type'} eq 'E' ) {
        $_ = "SELECT strFirstName || ' ' || strLastName FROM tbl_Customer_Users WHERE lngUserID='$$variable{'user_id'}'";
        @$variable{'AdministratorName'} = sql::sql_statement( $log, $dbh, $_ );
    } # end if

	get_unfinished_quote_contents( $log, $dbh, $variable, $quote_id );

	return OK;
} # end submit_quote


sub get_products {

	my $quote_id = shift;
	my $dbh  = session::dbh;
	my $data = $dbh->selectall_arrayref(q{
			SELECT * FROM tbl_quote_details  WHERE type = 'product' AND lngquoteid = ?
	}, {Slice => {}}, $quote_id);

print STDERR "HAVE PRODUCTS: ", Dumper($data);
	return $data;
	
}


sub get_user_by_info {
	my ( $log, $dbh, $variable, $quote_id ) = @_;

	$_ = "SELECT strCompanyName, strSalutation, strFirstName, strLastName, strAddress, strAddress2, strCity, strState, strCountry, strPostalCode, strPhone, strExt, strFax, strEmail, Cubicle ".
		"FROM tbl_Quote_Users_By WHERE lngQuoteID = '$quote_id'";
	return @$variable{'ByCompanyName','BySalutation', 'ByFirstName','ByLastName','ByAddress1','ByAddress2','ByCity','ByStateProvince','ByCountry','ByPostalCode','ByPhone', 'ByExtension', 'ByFax', 'ByEmail', 'ByCubicle'} = sql::sql_statement( $log, $dbh, $_ );
} # end sub get_user_by_info

sub get_user_for_info {
	my ( $log, $dbh, $variable, $quote_id ) = @_;

	$_ = "SELECT strCompanyName, strSalutation, strFirstName, strLastName, strAddress, strAddress2, strCity, strState, strCountry, strPostalCode, strPhone, strExt, strFax, strEmail, Cubicle ".
		"FROM tbl_Quote_Users_For WHERE lngQuoteID = '$quote_id'";
	return @$variable{'ForCompanyName', 'ForSalutation','ForFirstName','ForLastName','ForAddress1','ForAddress2','ForCity','ForStateProvince','ForCountry','ForPostalCode','ForPhone', 'ForExtension', 'ForFax', 'ForEmail', 'ForCubicle'} = sql::sql_statement( $log, $dbh, $_ );
} # end sub get_user_for_info

sub get_misc_info {
    my ( $log, $dbh, $variable, $quote_id ) = @_;
        

    @$variable{qw( CurrencyName CurrencySymbol DATE TOTAL1 TOTAL2 TOTAL3 Comments AdministratorComments AdministratorName status NotGroupPricing )} = 
        $dbh->selectrow_array(q{
            SELECT strCurrencyName, 
                   strCurrencySymbol, 
                   to_char(dtmQuoteDate, 'MM/DD/YYYY'), 
                   curTotalSale1, 
                   curTotalSale2, 
                   curTotalSale3, 
                   strCustomerComments, 
                   strAdministratorComments, 
                   strAdministratorName, 
				   strstatus,
				   ShowPricing
            FROM tbl_Quotes
            WHERE lngQuoteID = ?
        }, undef, $quote_id);

	$$variable{'QUOTE_ID'} = $quote_id;
} # end sub get_misc_info


sub get_finished_quote_contents {
	my ( $log, $dbh, $variable, $quote_id ) = @_;

	$_ = "SELECT lngProjectIndex, strDescription\n".
		"FROM tbl_Quote_Details ".
		"WHERE lngQuoteID = '$quote_id' ".
		"ORDER BY strDescription",
	@{$$variable{'PROJECTS'}} = sql::sql_statement( $log, $dbh, $_ );

	for ( my $index = 0; $index < @{$$variable{'PROJECTS'}}; $index += 2 ) {
		my $project_index  = $$variable{'PROJECTS'}[$index];
		my $reference = $$variable{'PROJECTS'}[$index+1];
		@{$$variable{"PROJECT_PRICES_$project_index"}} = ();
		$_ = "SELECT dblMarkup1, intQuantity1, dblPrice1,\n".
				"dblMarkup2, intQuantity2, dblPrice2,\n".
				"dblMarkup3, intQuantity3, dblPrice3\n".
				"FROM tbl_Quote_Details ".
				"WHERE lngQuoteID = '$quote_id' ".
				"AND lngProjectIndex = '$project_index'";
		my @data = sql::sql_statement( $log, $dbh, $_ );

		while ( @data ) {
			my ( $markup1, $qty1, $price1, $markup2, $qty2, $price2, $markup3, $qty3, $price3 ) = splice( @data, 0, 9 );

			my $newprice1 = sprintf( "%.2f",($price1*(1+($markup1/100))));
			my $newprice2 = sprintf( "%.2f",($price2*(1+($markup2/100))));
			my $newprice3 = sprintf( "%.2f",($price3*(1+($markup3/100))));

			my $colour = 'black';
			#$_ = "SELECT intQuantity1, intQuantity2, intQuantity3 FROM tbl_Projects WHERE lngProjectIndex = '$project_index'";
			#my ( $newqty1, $newqty2, $newqty3 ) = sql::sql_statement( $log, $dbh, $_ );
			#if ( $qty1 != $newqty1 or $qty2 != $newqty2 or $qty3 != $newqty3 ) {
			#	$colour = 'red';
			#} # end if
			#
			#$_ = "SELECT strValue FROM tbl_Service_Specifications\n".
			#	"WHERE lngProjectIndex = '$project_index' AND strName='txtPrice1' AND strValue != '' AND strValue != 'n/a'";
			#$_ = misc::sum(sql::sql_statement( $log, $dbh, $_ ));
			#if ( $_ != $price1 ) {
			#	$colour = 'red';
			#} # end if
			#
			#$_ = "SELECT strValue FROM tbl_Service_Specifications\n".
			#	"WHERE lngProjectIndex = '$project_index' AND strName='txtPrice2' AND strValue != '' AND strValue != 'n/a'";
			#$_ = misc::sum(sql::sql_statement( $log, $dbh, $_ ));
			#if ( $_ != $price2 ) {
			#	$colour = 'red';
			#} # end if
			#$_ = "SELECT strValue FROM tbl_Service_Specifications\n".
			#	"WHERE lngProjectIndex = '$project_index' AND strName='txtPrice3' AND strValue != '' AND strValue != 'n/a'";
			#$_ = misc::sum(sql::sql_statement( $log, $dbh, $_ ));
			#if ( $_ != $price3 ) {
			#	$colour = 'red';
			#} # end if
			my $expired = eprint::project::validate_project_price($log, $dbh, $project_index);
			$$variable{'InvalidPrices'} = 1 if $expired;

print STDERRR "ADDING PROJECT PRICES - $project_index \n";
			push @{$$variable{"PROJECT_PRICES_$project_index"}}, $markup1, $qty1, $price1, $newprice1, $expired, $markup2, $qty2, $price2, $newprice2, $expired, $markup3, $qty3, $price3, $newprice3, $expired;
			my $lastindex =3;
			$lastindex = 2 
			if ! $qty3;
			$lastindex = 1 
			if ! $qty1;


			push @{$$variable{"projects1"}},{
				markup        => $markup1, 
				qty           => $qty1, 
				stdprice      => $price1, 
				newprice      => $newprice1,
				index         => 1,
				project_index => $project_index,
				reference     => $reference,
				lastindex     => $lastindex,
			} if $qty1; 
			push @{$$variable{"projects2"}},{
				markup        => $markup2, 
				qty           => $qty2, 
				stdprice      => $price2, 
				newprice      => $newprice2,
				index         => 2,
				project_index => $project_index,
				reference     => $reference,
				lastindex     => $lastindex,
			}if $qty2; 
			push @{$$variable{"projects3"}},{
				markup        => $markup3, 
				qty           => $qty3, 
				stdprice      => $price3, 
				newprice      => $newprice3,
				index         => 3,
				project_index => $project_index,
				reference     => $reference,
				lastindex     => $lastindex,
			}if $qty3; 
		} # end while

	} # end for

	$variable->{LIST_PROJECTS} = [ 
		{projects => $variable->{projects1}, n=>1, TOTAL=> $variable->{TOTAL1}}, 
		{projects => $variable->{projects2}, n=>2, TOTAL=> $variable->{TOTAL2}},  
		{projects => $variable->{projects3}, n=>3, TOTAL=> $variable->{TOTAL3}} 
	];  

	return @{$$variable{'PROJECTS'}};
} # end sub get_finished_quote_contents

sub get_totals {
    my ($log, $dbh, $quote_id) = @_;

    my @totals = @{ $dbh->selectall_arrayref(q{
        SELECT
            ROUND(curTotalSale1, 2),
            ROUND(curTotalSale2, 2),
            ROUND(curTotalSale3, 2)
        FROM
            tbl_Quotes
        WHERE
            lngQuoteID = ?
        }, undef, $quote_id
    ) };

    my $n = 1;

    return  map { ($n++, $_) }
           grep {  $_ > 0    }
            map {  @{ $_ }   } @totals;
}

sub send_quote {
    my ( $r, $log, $dbh, $quote_id, $variable ) = @_;
    my ( $temp, %quote, $txt_template, $html_template );


print STDERR "START SEND QUOTES HERE \n";

    get_user_by_info( $log, $dbh, \%quote, $quote_id );
    get_user_for_info( $log, $dbh, \%quote, $quote_id );

    $quote{CCITYPROV} = misc::build_city_prov_country(
        @quote{qw( ByCity ByStateProvince ByCountry )}
    );

    $quote{FCITYPROV} = misc::build_city_prov_country(
        @quote{qw( ForCity ForStateProvince ForCountry )}
    );

                  get_misc_info( $log, $dbh, \%quote, $quote_id );
    get_finished_quote_contents( $log, $dbh, \%quote, $quote_id );

    $quote{siteURL} = "http://" . $r->hostname;

    my @project_summaries = ();

    my @projects =  @{ $dbh->selectcol_arrayref(q{
        SELECT
            lngProjectIndex
        FROM
            tbl_quote_details
        WHERE
            lngquoteid = ?
          }, undef, $quote_id
    )};

    # Send an email to the admin.
    my @pids =  @{$dbh->selectcol_arrayref(q{
        SELECT lngprojectindex FROM tbl_quote_details WHERE lngquoteid = ? and type = 'print'
    }, undef, $quote_id)};

    $quote{cust_id}        = $variable->{cust_id};
    $quote{isQuotePricing} = $variable->{isQuotePricing};

	my $cc = '';
    for my $pid (@pids) {
        my %hash = (
            cust_id   => $variable->{cust_id},
            user_type => 'C'
        );

        # The project header and service/material information.
        eprint::docket::summary_display(
            $r, $log, $dbh, \%hash, $pid, undef, 1
        );

		#Override project settings to not show stock price on quotes.
		$hash{flags}{stock_separate} = undef;


        push @{ $quote{attachedProjects} }, \%hash;

		my $email = $dbh->selectrow_array(q{
			SELECT strvalue FROM tbl_service_specifications WHERE lngprojectindex = ? AND strname = 'txtEmailCC'
		}, undef, $pid);
		$cc .= $email;
    }
		
	$quote{PRODUCTS} = get_products( $quote_id );

    my $sales_email = scalar $dbh->selectrow_array(q{
    	SELECT
            strEmail
		FROM
            tbl_customer_users
		WHERE lnguserid = (SELECT
                            lngsalesperson
                           FROM
                            tbl_customer
                           WHERE
                            lngcustomerid = ?)
        }, undef, $variable->{cust_id}
    );

    $quote{ResellerForEndUser} = 'N';
    $quote{Reseller}           = 'Y';
    $quote{user_type}          = $variable->{user_type};

    my @totals                 = get_totals( $log, $dbh, $quote_id );
    $quote{TOTALS}             = \@totals; # Legacy.

    # Convert our lovely flattended result sets to a list of hashes.
    $quote{totals} = [];

    for (my $i=0; $i < @totals; $i+=2) {
        push @{ $quote{totals} },
            { 'index' => $totals[$i], total => $totals[$i+1] };
    }

   	my $email_content = misc::load_file($r, '/email/email_template.html');

   	$quote{ReplacementText} = q{<!--#include virtual="/email/forms/quote_with_PDF.html"} . q{-->};


	$email_content = encode_qp(ssi::variable_substitution( $r, $log, $dbh, $email_content, \%quote ));



    my @body = ('', $email_content, 'text/html', 'quoted-printable' );
	

#print STDERR "HAVE QUOTE DATA" , Dumper(%quote);

    # One email goes out to the admin.
    my $html  = misc::load_file($r, '/email/forms/quote.html');
	$html = ssi::variable_substitution( $r, $log, $dbh, $html, \%quote);

	use MIME::Base64;
	use PDF::WebKit;
  	my $kit = PDF::WebKit->new(\$html, page_size => 'Letter');
	my $pdf = $kit->to_pdf;

#	misc::save_file(undef, "/usr/local/share/pqs/test1.pdf", $pdf);

	$pdf = encode_base64($pdf);


	push @body, ("quote-$quote_id.pdf", $pdf,  'application/pdf', 'base64');


	my $creator = $dbh->selectrow_array(q{
		SELECT u.strfirstname || ' ' || u.strlastname FROM tbl_customer_users u, tbl_quotes q
		WHERE u.lnguserid = q.lnguserid
		AND lngquoteid = ?
	}, undef, $quote_id);



    my %mail = (
        SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
        FROM    => configuration::get_value( $log, $dbh, 'QuotingEmail'),
        TO      => configuration::get_value( $log, $dbh, 'QuotingEmail')
                 . ','
                 . $sales_email,
        SUBJECT => " $creator - Quote $quote_id",
    );

    misc::send_email_with_attachment(
        $r, $log, \%mail, @body, @project_summaries
    );

    # One goes to the person who prepared the quote, and one for who the
    # quote was prepared for (if applicable).
    if (   $variable->{Reseller}  eq 'Y' || $variable->{user_type} eq 'A'
        || $variable->{user_type} eq 'E' ) {
        my %mail = (
                SMTP    => configuration::get_value(
                            $log, $dbh, 'Mail Server'
                           ),
                FROM    => qq{"$quote{ByFirstName} $quote{ByLastName}"}
                         . "<$quote{ByEmail}>",
                TO      => qq{"$quote{ByFirstName} $quote{ByLastName}"}
                         . "<$quote{ByEmail}>",
                SUBJECT => "Quote $quote_id",
        );

        misc::send_email_with_attachment( $r, $log, \%mail, @body);



		my %mail = (
			SMTP    => configuration::get_value(
						$log, $dbh, 'Mail Server'
					   ),
			FROM    => qq{"$quote{ByFirstName} $quote{ByLastName}" }
					 . "<$quote{ByEmail}>",
			TO      => qq{"$quote{ForFirstName} $quote{ForLastName}" }
					 . "<$quote{ForEmail}>",
			SUBJECT => "Quote $quote_id",
			CC => $cc,
		);

		misc::send_email_with_attachment($r, $log, \%mail, @body);
        
    }
    else {

        my %mail = (
            SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
            FROM    => $quote{ByEmail},
            TO      => $quote{ForEmail},
            SUBJECT => "Quote $quote_id",
			CC => $cc,
        );

        misc::send_email_with_attachment($r, $log, \%mail, @body); 
    }

}

sub finalise_quote {
	my ( $r, $log, $dbh, $cookie, $variable ) = @_;

	my $quote_id = get_unfinished_quote_id( $log, $dbh, $cookie, $$variable{'cust_id'}, $$variable{'user_id'} );



	if ( $quote_id ) {
		$_ = "SELECT strStatus FROM tbl_Quotes WHERE lngQuoteID='$quote_id'";
		( $_ ) = sql::sql_statement( $log, $dbh, $_ );


		if ( $_ ne 'Complete' ) {
			commit_quote( $log, $dbh, $quote_id );
			sql::update( $log, $dbh, 'tbl_Quotes', "lngQuoteID = '$quote_id'", 'strStatus', 'Complete', 
					( defined $r->param('AdministratorComments') ? ( 'strAdministratorComments', $r->param('AdministratorComments') ) : () ),
					( defined $r->param('AdministratorName') ? ( 'strAdministratorName', $r->param('AdministratorName') ) : () ),
					);
			send_quote( $r, $log, $dbh, $quote_id, $variable );
		} # end if
	} # end if
	$variable->{quote_id} = $r->param('quote_id') || $quote_id;

	return OK;
} # end sub finalise_quote

sub quote_history {
	my ( $r, $log, $dbh, $variable ) = @_;

	my $error = '';
	foreach my $key ( $r->param() ) {
		if ( $key =~ /chkDelete(\d*)/ ) {
			$_ = "SELECT lngCustomerID FROM tbl_Quotes WHERE lngQuoteID='$1'";
			my ( $cust_id ) = sql::sql_statement( $log, $dbh, $_ );
			if ( $cust_id == $$variable{'cust_id'} ) {
				delete_quote( $log, $dbh, $1 );
			} else {
				$error .= "Quote $1 does not belong to you.  Not deleted.<br>";
			} # end if
		} elsif ( $key eq 'btnFunction' and $r->param($key) eq 'Delete Quote' ) {
			my $quote_id = $r->param('quote_id');
			$_ = "SELECT lngCustomerID FROM tbl_Quotes WHERE lngQuoteID='$quote_id'";
            my ( $cust_id ) = sql::sql_statement( $log, $dbh, $_ );
            if ( $cust_id == $$variable{'cust_id'} ) {
                delete_quote( $log, $dbh, $quote_id );
            } else {
                $error .= "Quote $quote_id does not belong to you.  Not deleted.<br>";
            } # end if

		} # end if
	} # end foreach

	if ( $error ne '' ) {
		return misc::error( $log, $dbh, $variable, 'Error',$error );
	} # end if

    ssi::get_start_end_dates( $log, $dbh, $variable,
            $r->param('ddmStartYear'),
            $r->param('ddmStartMonth'),
            $r->param('ddmStartDay'),
            $r->param('ddmEndYear'),
            $r->param('ddmEndMonth'),
            $r->param('ddmEndDay') );

	my $status = $r->param('ddmStatus');
	my $quoted_for = $r->param('ddmQuotedFor');


	$_ = "SELECT DISTINCT tbl_Quote_Users_For.strFirstName || ' ' || 
              tbl_Quote_Users_For.strLastName, tbl_Quote_Users_For.strFirstName || ' ' 
           || tbl_Quote_Users_For.strLastName ".
		 "FROM tbl_Quotes, tbl_Quote_Users_For ".
		 "WHERE tbl_Quotes.lngCustomerID = '$$variable{'cust_id'}' ".
		"AND tbl_Quote_Users_For.lngQuoteID = tbl_Quotes.lngQuoteID ".
		" ORDER BY tbl_Quote_Users_For.strFirstName || ' ' || tbl_Quote_Users_For.strLastName ";
	$$variable{'ddmQuotedForOptions'} = ssi::fill_drop_down( $log, $dbh, $_, $quoted_for );

	if ( $$variable{'cust_id'} ne '' ) {
		$_ = "SELECT DISTINCT tbl_Quotes.lngQuoteID, to_char(tbl_Quotes.dtmQuoteDate, 'MM/DD/YYYY'),\n".
			"tbl_Quote_Users_For.strFirstName || ' ' || tbl_Quote_Users_For.strLastName,\n".
			"ROUND( (SELECT SUM(dblPrice1) FROM tbl_Quote_Details WHERE tbl_Quote_Details.lngQuoteID=tbl_Quotes.lngQuoteID), 2),\n".
			"ROUND( (SELECT SUM(dblPrice2) FROM tbl_Quote_Details WHERE tbl_Quote_Details.lngQuoteID=tbl_Quotes.lngQuoteID), 2),\n".
			"ROUND( (SELECT SUM(dblPrice3) FROM tbl_Quote_Details WHERE tbl_Quote_Details.lngQuoteID=tbl_Quotes.lngQuoteID), 2),\n".
			"'projects'\n".
			"FROM tbl_Quotes, tbl_Quote_Users_For ".
			"WHERE tbl_Quotes.lngCustomerID = '$$variable{'cust_id'}' ";

# Customer History is now user specific for Safeway,
# Let customers see any order with projects that were made for that user.
        $_ .= "AND  EXISTS ( SELECT lngquoteid FROM tbl_quote_details qd, tbl_projects p  
					      		WHERE tbl_quotes.lngquoteid = qd.lngquoteid AND qd.lngprojectindex = p.lngprojectindex
								AND p.lnguserindex = '$variable->{user_id}' )\n"
         			if $variable->{user}{type} eq 'C' && $variable->{user_id} ne '293';


		$_ .= "AND tbl_Quote_Users_For.strFirstName || ' ' || tbl_Quote_Users_For.strLastName = '$quoted_for'" if $quoted_for ne '';
		$_ .= "AND date(dtmQuoteDate) BETWEEN date('$$variable{'StartDate'}') AND date('$$variable{'EndDate'}')";
		$_ .= "AND tbl_Quote_Users_For.lngQuoteID = tbl_Quotes.lngQuoteID ORDER BY tbl_Quotes.lngQuoteID DESC";

print STDERR "QUOTE SQL: \n $_ \n";
		@{$$variable{'QUOTES'}} = sql::sql_statement( $log, $dbh, $_ );
	} # end if

	for ( my $index = 0; $index < @{$$variable{'QUOTES'}}; $index += 7 ) {

		my $data = $dbh->selectall_arrayref(q{
					SELECT q.lngprojectindex as pid, strprojectreference as reference 
					FROM tbl_quote_details q, tbl_projects p 
					WHERE lngquoteid = ?
					AND q.lngprojectindex = p.lngprojectindex
		}, {Slice=>{}}, $$variable{'QUOTES'}[$index] );

		unless ( @{$data} > 0 ) {
			print STDERR "GET DATA \n";
			$data = $dbh->selectall_arrayref(q{
				SELECT label as reference FROM tbl_quote_details WHERE lngquoteid = ?
			},  {Slice=>{}}, $$variable{'QUOTES'}[$index] );

		}
		
		$$variable{'QUOTES'}[$index+6] = $data;


	}

	print STDERR "HAVE QUOTES", Dumper($variable->{QUOTES});
 
	( $$variable{'CurrencyName'}, $$variable{'CurrencySymbol'}, undef ) = eprint::customer::get_currency( $log, $dbh, $$variable{'cust_id'} );
	return OK;
} # end sub quote_history

sub show_quote {
	my ( $r, $log, $dbh, $variable ) = @_;

	my $quote_id =  $r->param('quote_id') || $variable->{param}{quote_id};
       $quote_id =~ tr/0-9//cd;
       
	$$variable{'QUOTE_ID'} = $quote_id;
    
	get_user_by_info( $log, $dbh, $variable, $quote_id );
	get_user_for_info( $log, $dbh, $variable, $quote_id );
	get_misc_info( $log, $dbh, $variable, $quote_id );
	@{$$variable{'TOTALS'}} = get_totals( $log, $dbh, $quote_id );
	while (@{$$variable{'TOTALS'}}) {
	    push @{$$variable{'totals'}}, {
		index => shift @{$$variable{'TOTALS'}},
		total => shift @{$$variable{'TOTALS'}},
	    };
	}
    $$variable{'CCITYPROV'} = misc::build_city_prov_country(@$variable{'ByCity','ByStateProvince','ByCountry'} );
    $$variable{'FCITYPROV'} = misc::build_city_prov_country(@$variable{'ForCity','ForStateProvince','ForCountry'} );
    my @pids =  @{$dbh->selectcol_arrayref(q{
	SELECT lngprojectindex
	FROM tbl_quote_details
	WHERE lngquoteid= ? and type = 'print'
    }, undef, $quote_id)};
    for my $pid (@pids) {   
    	my %hash = %$variable;

		# We want to see the quote as the customer would see it,
		# so that we know what we are sending them.
		$hash{'user_type'} = 'C';

    	eprint::docket::summary_display($r, $log, $dbh, \%hash, $pid, undef, -1);
    	push @{$$variable{attachedProjects}}, \%hash;
		$variable->{supplier_chino} = eprint::order::is_chino($dbh, $pid);
    }

	$variable->{PRODUCTS} = get_products( $quote_id );


	get_finished_quote_contents( $log, $dbh, $variable, $quote_id );
	
#	@{ $variable->{PRODUCTINFO}} = @{ $dbh->selectall_arrayref(q{
#        select s.id, s.name, sum(c.quantity * p.price) as cost from tbl_quote_details as o left join tbl_shopping_lists as s on o.lngProjectIndex = s.id left join tbl_shopping_lists_contents as c on s.id = c.shopping_list_id left join tbl_products as p on p.id = c.product_id where o.lngQuoteId = ? group by s.id, s.name
#    }, {Slice => {}}, $quote_id) };

	if ( $r->param('btnFunction') eq 'Send Quote' ) {
			send_quote( $r, $log, $dbh, $quote_id, $variable );
	}
	if ( $r->param('btnFunction') eq 'Make Order' ) {
		eprint::order::make_order_from_quote( $r, $log, $dbh, $quote_id, $variable );
	}

} # end sub show_quote

sub make_quote_from_quote {
	my ( $r, $log, $dbh, $cookie, $customer, $user, $quote_id ) = @_;

	my %for;
	my %by;
    get_user_by_info( $log, $dbh, \%by, $quote_id );
    get_user_for_info( $log, $dbh, \%for, $quote_id );

	# check that the specified quote actually exists.
	$_ = "SELECT lngQuoteID FROM tbl_Quotes WHERE lngQuoteID = '$quote_id' AND lngCustomerID = '$customer'";
	if ( sql::sql_statement( $log, $dbh, $_ ) ) {
		# pull info for the order we are duplicating
		$_ = "SELECT lngProjectIndex, dblMarkup1, dblMarkup2, dblMarkup3\n".
			"FROM tbl_Quote_Details WHERE lngQuoteID = '$quote_id'";
		my @data = sql::sql_statement( $log, $dbh, $_ );
		
		delete_unfinished_quotes( $log, $dbh, $cookie );

		my $new_quote_id = create_quote( $log, $dbh, $cookie, $customer, $user );
		while ( @data ) {
			my ( $project_index, $markup1, $markup2, $markup3 ) = splice @data, 0, 4;
			add_project_to_quote( $r, $log, $dbh, $customer, $user, $cookie, $new_quote_id, $project_index );
			sql::update( $log, $dbh, 'tbl_Quote_Details', "lngQuoteID = '$new_quote_id' AND lngProjectIndex = '$project_index'", 
				'dblMarkup1', $markup1,
				'dblMarkup2', $markup2,
				'dblMarkup3', $markup3,
			 );
		} # end while

		store_user_by_info( $log, $dbh, $new_quote_id, \%by );
		store_user_for_info( $log, $dbh, $new_quote_id, \%for );
		return $new_quote_id;
	} # end if
	return 0;
} # End sub make_quote_from_quote 

sub get_project_info {
	my ( $log, $dbh, $pid ) = @_;

	$_ = "SELECT strProjectReference, intQuantity1, intQuantity2, intQuantity3 FROM tbl_Projects WHERE lngProjectIndex = '$pid'";
	my ( $reference, $qty1, $qty2, $qty3 ) = sql::sql_statement( $log, $dbh, $_ );

	my ($price1, $price2, $price3 ) = eprint::project::project_price( $log, $dbh, $pid );

	return ( $reference, $qty1, $qty2, $qty3, $price1, $price2, $price3 );
} # end sub get_project_info

sub add_project_to_quote {
	my ( $r, $log, $dbh, $customer, $user, $cookie, $quote_id, $project_index, $type ) = @_;
	$type = $r->param('ProjectType') if !$type;
	$type = 'print' if !$type;

	$log->debug(" *** Adding Project to Quote -- $project_index ****" );

	$project_index = $r->param('ProjectIndex') if ! $project_index;

print STDERR "HAVE PROJECT INDEX: $project_index \n";
	$project_index = eprint::print_project::get_unfinished_project( $log, $dbh, $cookie ) if ! $project_index;

	$quote_id = get_unfinished_quote_id( $log, $dbh, $cookie, $customer, $user ) if ! $quote_id;
	$quote_id = create_quote( $log, $dbh, $cookie, $customer, $user ) if ! $quote_id;

	# check to make sure project isn't already in the order.
	$_ = "SELECT lngProjectIndex FROM tbl_Quote_details WHERE lngQuoteID='$quote_id' AND lngProjectIndex='$project_index' AND type = '$type'";
	if ( ! sql::sql_statement( $log, $dbh, $_ ) ) {
		sql::insert( $log, $dbh, 'tbl_Quote_Details', 
				'lngQuoteID',			$quote_id,
				'lngProjectIndex',		$project_index,
				'type', $type
				);
		return $quote_id;
	} # end if
	return 0;
} # end sub add_project_to_quote

sub create_quote {
	my ( $log, $dbh, $cookie, $customer, $user ) = @_;

	my ( $currency, $symbol, $rate ) = eprint::customer::get_currency( $log, $dbh, $customer );

	# turn autocommit off, so that our locks stay in effect.
	$dbh->{AutoCommit} = 0;
	$dbh->do( "LOCK TABLE tbl_Quotes IN SHARE ROW EXCLUSIVE MODE" ) or $log->error( DBI->errstr );

	# allocate a new quote
	my $quote_id = get_quote_id( $log, $dbh );

	# insanity code
	delete_quote( $log, $dbh, $quote_id );

	sql::insert( $log, $dbh, 'tbl_Quotes', 
		'lngQuoteID',		$quote_id,
		'lngUserID',		( $user eq '' ? '0': $user ),
		'lngCustomerID',	( $customer eq '' ? '0': $customer ),
		'strSessionID',		$cookie,
		'dtmQuoteDate',		'NOW()',
		'dtmLastModified',	'NOW()',
		'strStatus',		'Incomplete',
		'strCurrencyName',	$currency,
		'strCurrencySymbol',$symbol );

	# this should unlock everything
	$dbh->commit() or $log->error( $DBI::errstr );
	$dbh->{AutoCommit} = 1;

	return $quote_id;
} # end sub create_quote

1;

__END__
