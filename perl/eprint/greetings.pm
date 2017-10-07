package eprint::greetings;

use strict;

sub select_greeting {
	my ( $log, $dbh, $cust_id, $user_id ) = @_;

	# Greeting selection
	$_ = "SELECT strCustomGreeting from tbl_Customer where lngCustomerID = $cust_id";
	my ($custom_greeting) = sql::sql_statement( $log, $dbh, $_ );

	$custom_greeting .= '<br>' . select_user_greeting( $log, $dbh, $cust_id, $user_id );
	$custom_greeting .= '<br>' . select_user_category_greeting( $log, $dbh, $cust_id, $user_id );
	$custom_greeting .= '<br>' . select_customer_greeting( $log, $dbh, $cust_id );
	$custom_greeting .= '<br>' . select_customer_category_greeting( $log, $dbh, $cust_id, $user_id );
	$custom_greeting .= '<br>' . select_generic_greeting( $log, $dbh, $cust_id, $user_id );

	return $custom_greeting;
} # end sub select_greeting

sub select_customer_category_greeting {
	my ( $log, $dbh, $cust_id ) = @_;

	$_ = "SELECT strGreeting from tbl_Marketing_Categories WHERE lngIndex IN ( ".
		"SELECT lngCategoryID FROM tbl_Customers_in_Categories WHERE lngCustomerID = '$cust_id')";
	my @greetings = sql::sql_statement( $log, $dbh, $_ );

	return join( '<br>', @greetings );
} # end sub select_category_greeting


sub select_customer_greeting {
	my ( $log, $dbh, $cust_id ) = @_;

	$_ = "SELECT strCustomGreeting FROM tbl_Customer WHERE lngCustomerID = '$cust_id'";
	($_) = sql::sql_statement( $log, $dbh, $_ );
	return $_;
} # end sub select_customer_greeting

sub select_user_greeting {
	my ( $log, $dbh, $user_id ) = @_;

	$_ = "SELECT strCustomGreeting FROM tbl_Customer_Users WHERE lngUserID = '$user_id'";
	my ($greeting) = sql::sql_statement( $log, $dbh, $_ );
	if ( $greeting eq '' ) {
		return select_generic_greeting( $log, $dbh, $user_id );
	} # end if
	return $greeting;
} # end sub select_user_greeting

sub select_user_category_greeting {
	my ( $log, $dbh, $user_id ) = @_;

	$_ = "SELECT strGreeting from tbl_Marketing_Categories WHERE lngIndex IN ( ".
		"SELECT lngCategoryIndex FROM tbl_Users_in_Categories WHERE lngUserIndex = '$user_id')";
	my @greetings = sql::sql_statement( $log, $dbh, $_ );

	return join( '<br>', @greetings );
} # end sub select_category_greeting

sub select_generic_greeting {
	my ( $log, $dbh, $user_id ) = @_;

	# no category greeting, so give them the default greeting
	$_ = "SELECT strSalutation, strFirstName, strLastName FROM tbl_Customer_Users WHERE lngUserID = '$user_id'";
	my ( $salutation, $first_name, $last_name ) = sql::sql_statement( $log, $dbh, $_ );

	return "Welcome $salutation $first_name $last_name!  Thank you for logging in.";
} # end sub select_generic_greeting

1;
__END__
