package eprint::admin_user;
use strict;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY); # Offers OK, Error, etc for web server.


use eprint::user ();
use sql ();

sub admin_user_edit {
    my ( $r, $log, $dbh, $variable ) = @_;
    my ( $temp, $status );

    # Due to some browser autocomplete issues the email and password fields
    # had to have their names changed. However this only effects the admin
    # user edit and not the initial creation, but initial creation accesses
    # our request object. So we map the new names to the old.

my $email =   $r->param('email');
my $pass  =   $r->param('password');
my $verify =  $r->param('verify');

    
    my $user_id = $r->param('ddmUser');
    my $user_role = $r->param('ddmUserRole');
    my $cust_id = $r->param('ddmCustomer');
    $variable->{CustomerIndex} = $cust_id;

    if ( $r->param('btnFunction') eq '<<' ) {
        if($user_id) {
            my $cond = '1>0';
            $cond .= "AND chrType = '$user_role'"
                if $user_role;
            $cond .= "AND lngcustomerid = '$cust_id'"
                if $cust_id;
            $user_id = misc::nav_get_previous( $r, $log, $dbh, $user_id, 'lngUserID', 'tbl_Customer_Users',$cond,'strLastname ||  strFirstName');
        }
        if (! $user_id){
                $_ = "SELECT lngUserID FROM tbl_Customer_Users WHERE 1>0\n";
            $_ .= "AND chrType = '$user_role'\n" if $user_role ne '';
            $_ .= "AND lngCustomerID = '$cust_id'\n" if $cust_id ne '';
            $_ .= "ORDER BY strLastName DESC, strFirstName DESC LIMIT 1";
            ($user_id) = sql::sql_statement( $log, $dbh, $_ );
        }
    } elsif ($r->param('btnFunction') eq '>>') {
        if ($user_id) {
            my $cond = '1>0';
            $cond .= "AND chrType = '$user_role'"
                if $user_role;
            $cond .= "AND lngcustomerid = '$cust_id'"
                if $cust_id;
            $user_id = misc::nav_get_next( $r, $log, $dbh, $user_id, 
        '    lngUserID', 'tbl_Customer_Users',$cond,'strLastname || strFirstName');
        }
        if (! $user_id){
            $_ = "SELECT lngUserID FROM tbl_Customer_Users WHERE 1>0\n";
            $_ .= "AND chrType = '$user_role'\n" if $user_role ne '';
            $_ .= "AND lngCustomerID = '$cust_id'\n" if $cust_id ne '';
            $_ .= "ORDER BY strLastName, strFirstName LIMIT 1";
            ($user_id) = sql::sql_statement( $log, $dbh, $_ );
        }
    } elsif ( $r->param('btnFunction') eq 'Delete' ) {

        eprint::user::delete( $r, $log, $dbh, $user_id,$variable );

        $user_id = eprint::user::get_next( $log, $dbh, $cust_id, $user_id, $user_role );
 
        $$variable{'message'} = "Record deleted.";

    } elsif ($r->param('btnFunction') eq 'Save') {
            if ( $pass  eq '' ) {
                return misc::error( $log, $dbh, $variable, "Empty Password.", "We insist on a non-empty password.");
            }


            if ($pass ne $verify) {
                return misc::error( $log, $dbh, $variable, "Passwords don't match.", "Your password and verify password fields do not match.");
            }

        if ( $user_id eq '' ) {

            if ( ! $cust_id) {
                return misc::error( $log, $dbh, $variable, "Please Select a Company Name for the new user.");
            }

            $email =~ tr/[A-Z]/[a-z]/;
            $email = sql::escape( $email );

            $_ = "SELECT lngUserID FROM tbl_Customer_Users WHERE strEmail = '$email'";
            ( $_ ) = sql::sql_statement( $log, $dbh, $_ );
            if ( $_ ne '' ) {
                return misc::error( $log, $dbh, $variable, 'User already exists.', 
                    "There is already a user with the specified email address.  Please try another."
                );
            }

            $user_id = eprint::user::add( $r, $log, $dbh, $variable, $r->param('ddmCustomer') );
            if ( $user_id eq '' ) {
                return misc::error( $log, $dbh, $variable, 'Error Saving.', 
                    "There was an error saving the user's information."
                );
            }

        } 
        else {
            if ( OK != eprint::user::save( $r, $log, $dbh, $variable, $user_id ) ) {
                return misc::error( $log, $dbh, $variable, 
                    "Error Saving.", 
                    "There was an error saving the user's information."
                );
            }

            $dbh->do(q{ 
                DELETE FROM tbl_Users_in_Categories WHERE lngUserIndex = ?
            }, undef, $user_id);

            $dbh->do(q{ DELETE FROM user_manager WHERE user_id = ?  }, undef, $user_id);
            $dbh->do(q{ DELETE FROM time_user_service WHERE userid = ?  }, undef, $user_id);
        }

        my $sth = $dbh->prepare(q{
            INSERT INTO tbl_Users_in_Categories (lngCategoryIndex, lngUserIndex)
            VALUES (?, ?)
        });

        foreach my $cat ( $r->param('selectUserCategories') ) {
            $sth->execute( $cat, $user_id ) or $log->error( DBI->errstr );
        }

        $sth = $dbh->prepare(q{
            INSERT INTO user_manager (user_id,manager_id) VALUES (?, ?)
        });
        
        foreach my $man ( $r->param('selectApproval') ) {
           $sth->execute( $user_id, $man ) or $log->error( DBI->errstr );
        }

        $sth = $dbh->prepare(q{
            INSERT INTO time_user_service (userid,service) VALUES (?, ?)
        });
        
        foreach my $man ( $r->param('selectService') ) {
           $sth->execute( $user_id, $man ) or $log->error( DBI->errstr );
        }



		$dbh->do(qq{ DELETE FROM user_cost_center WHERE user_id = $user_id});

        $sth = $dbh->prepare(q{
            INSERT INTO user_cost_center (user_id,cost_center) VALUES (?, ?)
        });
        
        foreach my $cc ( $r->param('CostCenter') ) {
           $sth->execute( $user_id, $cc ) or $log->error( DBI->errstr );
        }
		my $h =  $r->param('txtHourly') || 0;
		my $sql = qq{UPDATE tbl_customer_users SET time_rate = $h WHERE lnguserid = $user_id};

		$dbh->do($sql);

        $variable->{message} = "Record added successfully.";

        return $status if $status != OK;
    }


    # load user fields
    eprint::user::load( $log, $dbh, $user_id, $variable );    

    $$variable{'rdbAdministrator'.$$variable{'rdbAdministrator'}} = 'CHECKED';
    $$variable{'rdbSalutation'.$$variable{'rdbSalutation'}} = 'CHECKED';
    $$variable{'rdbAccountActivation'.$$variable{'AccountActivation'}} = 'CHECKED';
    $$variable{'rdbChangePassword'.$$variable{'rdbChangePassword'}} = 'CHECKED';
    $$variable{'rdbMailingList'.$$variable{'rdbMailingList'}} = 'CHECKED';

    $$variable{'editproject'} = $variable->{editproject} ? 'CHECKED' : '';

    # Get the number of users in this company
    $_ = "SELECT COUNT(lngUserID) FROM tbl_Customer_Users WHERE 1>0";
    $_ .= " AND lngCustomerID = '$cust_id'" if $cust_id ne '';
    $_ .= " AND chrType = '$user_role'" if $user_role ne '';
    @$variable{'NUM_USERS'} = sql::sql_statement( $log, $dbh, $_ );
    $user_id = 0 unless $user_id; #cast a null user id to 0 to eliminate query explosion - robustness
    # This clever query gives is which user we are out of the users for this company
    $_ = "SELECT COUNT(lngUserID) FROM tbl_Customer_Users WHERE 1>0\n";
    $_ .= "AND lngCustomerID = '$cust_id'\n" if $cust_id ne '';
    $_ .= "AND lngUserID < '$user_id'\n";
    $_ .= "AND chrType = '$user_role'" if $user_role ne '';
    @$variable{'EDIT_USER_NUM'} = sql::sql_statement( $log, $dbh, $_ );
    $$variable{'EDIT_USER_NUM'} += 1 if $$variable{'NUM_USERS'} > 0;

    # fill in Company Drop Down Menus
    my @data = sql::sql_statement( $log, $dbh, 'SELECT lngCustomerID, strCompanyName FROM tbl_Customer ORDER BY lower(strCompanyName)' );
    $$variable{'FILL_CUSTOMER_NAME'} = ssi::make_drop_down( \@data, $cust_id );
    $$variable{'ddmCompany'} = ssi::make_drop_down( \@data, $$variable{'CustomerIndex'} );
    $variable->{CustomerIndex} = $cust_id;

	$variable->{state}
        = ssi::return_states_and_provinces($variable->{state});
    $variable->{country}
        = ssi::return_countries($variable->{country});



    # fill in User Name Drop Down Menu
    $_ = "SELECT lngUserID, strLastName || ', ' || strFirstName FROM tbl_Customer_Users WHERE 1>0\n";
    $_ .= "AND chrType = '$user_role'\n" if $user_role ne '';
    $_ .= "AND lngCustomerID = '$cust_id'\n" if $cust_id ne '';
    $_ .= "ORDER BY strLastName, strFirstName";
    $$variable{'FILL_USER_NAME'} = ssi::fill_drop_down( $log, $dbh, $_, $user_id );

    # Get Marketing Category Inforamation - get all categories, and highlight the ones this user is in.
    $_ = 'SELECT lngIndex, strName FROM tbl_Marketing_Categories';
    my @available_categories = sql::sql_statement( $log, $dbh, $_ );

    # get categories this customer is in we do it this way to limit databse transaction to 2.
    $_ = "SELECT lngCategoryIndex FROM tbl_Users_in_Categories WHERE lngUserIndex = '$user_id'";
    my @users_categories = sql::sql_statement( $log, $dbh, $_ );

    $$variable{'selectUserCategories'} = ssi::make_select( \@available_categories, \@users_categories );

    # get categories this customer is in we do it this way to limit databse transaction to 2.
    $_ = qq{
            SELECT lnguserid, strLastName || ', ' || strFirstname 
            FROM tbl_customer_users WHERE lngcustomerid = (
                SELECT lngcustomerid FROM tbl_customer_users where lnguserid = '$user_id'
            )
    };
    my @users = sql::sql_statement( $log, $dbh, $_ );

    my $managers = $dbh->selectcol_arrayref(q{
        SELECT manager_id FROM user_manager WHERE user_id = ?
    },undef,$user_id);

    $$variable{'selectApproval'} = ssi::make_select( \@users, $managers );

    # get categories this customer is in we do it this way to limit databse transaction to 2.
    $_ = qq{ SELECT id FROM cost_center order by 1 };
    my @users = sql::sql_statement( $log, $dbh, $_ );

    my $managers = $dbh->selectcol_arrayref(q{
        SELECT cost_center FROM user_cost_center WHERE user_id = ?
    },undef,$user_id);

    $$variable{'CostCenter'} = ssi::make_select( \@users, $managers );

    $_ = qq{
            SELECT lngindex, strname FROM tbl_service_types  WHERE active ORDER by strname
    };
    my @services = sql::sql_statement( $log, $dbh, $_ );

    my $selected = $dbh->selectcol_arrayref(q{
        SELECT service FROM time_user_service WHERE userid = ?
    },undef,$user_id);

    $$variable{'selectService'} = ssi::make_select( \@services, $selected );

	$variable->{txtHourly} = $dbh->selectrow_array(q{
		SELECT time_rate FROM tbl_customer_users WHERE lnguserid = ?
	}, undef, $user_id);

    # Fill in User Type Drop Down Menus
    my @data = sql::sql_statement( $log, $dbh, 'SELECT Identifier, Label FROM tbl_User_Types' );
    $$variable{'FILL_USER_TYPE'} = ssi::make_drop_down( \@data, $user_role );
    $$variable{'ddmUserType'} = ssi::make_drop_down( \@data, $$variable{'UserType'} );

    if($cust_id) {
        $variable->{CompanyName} = scalar $dbh->selectrow_array(q{
            SELECT strCompanyName
            FROM tbl_Customer
            WHERE lngCustomerID = ?
        }, undef, $cust_id);
    }
    elsif ($user_id) {
        ($cust_id, $variable->{CompanyName}) = $dbh->selectrow_array(q{
            SELECT lngcustomerid, strCompanyName
            FROM tbl_Customer
            WHERE lngCustomerID = ( SELECT lngcustomerid
                                    FROM tbl_customer_users
                                    WHERE lnguserid = ?     )
        }, undef, $user_id);
    }
    
    $variable->{CustomerIndex} = $cust_id;

    return OK;
}

1;

