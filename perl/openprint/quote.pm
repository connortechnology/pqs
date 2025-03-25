use strict;
package openprint::quote;

use openprint ();
use vars qw( $log $dbh %config );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;


require sql;
require ssi;
require misc;
require configuration;
require openprint::Currency;
require openprint::Project;
require openprint::Quote;

sub get_unfinished_quote_id {
	my ( $log, $dbh, $cookie, $variable ) = @_;

	$_ = q{SELECT id, CompanyIndex, UserIndex FROM Quotes WHERE strSessionID=? AND strStatus='Incomplete'};
	my ( $quote_id, $cust_id, $user_id ) = sql::execute( $log, $dbh, $_, $cookie );

	# This is to update the quote if we login or switch company before finishing the quote
	if ( $quote_id ) {
		if ( $cust_id != $openprint::session{'company_id'} ) {
			
			# This should also remove any projects in the quote that belong to other companies FIXME
			sql::update( $log, $dbh, 'Quotes', ['id=?', $quote_id], 'CompanyIndex', $openprint::session{'company_id'},
					'currency_id',		openprint::Currency::get_current()->id(),
					);
		} # end if
		if ( $user_id != $openprint::session{'user_id'} ) {
			sql::update( $log, $dbh, 'Quotes', ['id=?', $quote_id], 'UserIndex', $openprint::session{'user_id'} );
		} # end if
	} # end if
	
	return $quote_id;
} # end sub get_unfinished_quote_id

sub get_unfinished_quote_contents {
	my ( $log, $dbh, $variable, $quote_id ) = @_;
	@{$$variable{'PROJECTS'}} = ();

	my $subtotal1 = 0;
	my $subtotal2 = 0;
	my $subtotal3 = 0;

	my $Quote = new openprint::Quote( $quote_id );
	foreach my $QP ( $Quote->Quoted_Projects() ) {
		$subtotal1 += $QP->price1();
		$subtotal2 += $QP->price2();
		$subtotal3 += $QP->price3();

		push @{$$variable{'PROJECTS'}}, $QP->project_id(), $QP->Project()->reference();
		push @{$$variable{"PROJECT_PRICES_".$QP->project_id()}}, map { $_, $QP->markup($_), $QP->Project()->quantity($_), sprintf('%.2f', $QP->cost($_) ), $QP->price($_) } ( 1 .. 3 );

	} # end while
	@{$$variable{'TOTALS'}} = ( '1', sprintf( '%.2f',$subtotal1), '2', sprintf( '%.2f',$subtotal2),'3', sprintf( '%.2f',$subtotal3));
} # end sub get_unfinished_quote_contents



sub get_user_by_info {
	my ( $log, $dbh, $variable, $quote_id ) = @_;

	$_ = 'SELECT strCompanyName, strSalutation, strFirstName, strLastName, strTitle, strAddress, strAddress2, strCity, strState, strCountry, strPostalCode, strPhone, strExt, strFax, strEmail FROM tbl_Quote_Users_By WHERE quote_id=?';
	return @$variable{'ByCompanyName','BySalutation', 'ByFirstName','ByLastName','ByTitle', 'ByAddress1','ByAddress2','ByCity','ByStateProvince','ByCountry','ByPostalCode','ByPhone', 'ByExtension', 'ByFax', 'ByEmail'} = sql::execute( $log, $dbh, $_, $quote_id );
} # end sub get_user_by_info

sub get_user_for_info {
	my ( $log, $dbh, $variable, $quote_id ) = @_;

	$_ = 'SELECT strCompanyName, strSalutation, strFirstName, strLastName, strTitle, strAddress, strAddress2, strCity, strState, strCountry, strPostalCode, strPhone, strExt, strFax, strEmail FROM tbl_Quote_Users_For WHERE quote_id=?';
	return @$variable{'ForCompanyName', 'ForSalutation','ForFirstName','ForLastName','ForTitle', 'ForAddress1','ForAddress2','ForCity','ForStateProvince','ForCountry','ForPostalCode','ForPhone', 'ForExtension', 'ForFax', 'ForEmail'} = sql::execute( $log, $dbh, $_, $quote_id );
} # end sub get_user_for_info

sub get_misc_info {
    my ( $log, $dbh, $variable, $quote_id ) = @_;
    $_ = q{SELECT CompanyIndex, to_char(dtmQuoteDate, 'MM/DD/YYYY'), curTotalSale1, curTotalSale2, curTotalSale3, strCustomerComments, strAdministratorComments, strAdministratorName, currency_id FROM Quotes WHERE id=?};
    @$variable{'Company_ID','DATE', 'TOTAL1','TOTAL2','TOTAL3','Comments','AdministratorComments', 'AdministratorName','currency_id'} = sql::execute( $log, $dbh, $_, $quote_id );
	my $Currency = new openprint::Currency( $$variable{currency_id} );
    @$variable{'CurrencyName', 'CurrencySymbol'} = ( $Currency->name(), $Currency->symbol() );
	$$variable{'QUOTE_ID'} = $quote_id;
} # end sub get_misc_info


sub get_finished_quote_contents {
	my ( $log, $dbh, $variable, $quote_id ) = @_;

	@{$$variable{'PROJECTS'}} = ();

	my $Quote = new openprint::Quote( $quote_id );
	foreach my $QP ( $Quote->Quoted_Projects() ) {
		my $Project = $QP->Project();

		push @{$$variable{'PROJECTS'}}, $QP->project_id(); 
		push @{$$variable{'PROJECTS'}}, ( $Project->reference() ? $Project->reference() : $Project->summary() );

		@{$$variable{'PROJECT_PRICES_'.$QP->project_id()}} = ();
		my $colour = 'black';
		if ( 
				( $QP->quantity(1) != $Project->quantity(1) ) or 
				( $QP->quantity(2) != $Project->quantity(2) ) or 
				( $QP->quantity(3) != $Project->quantity(3) ) or
				( $Project->price(1) != $QP->price(1) ) or 
				( $Project->price(2) != $QP->price(2) ) or
				( $Project->price(3) != $QP->price(3) ) 
				) {
			$colour = 'red';
		} # end if
		foreach my $qty_index ( 1 .. 3 ) {
			push @{$$variable{'PROJECT_PRICES_'.$QP->project_id()}}, $qty_index, $QP->get('markup'.$qty_index,'quantity'.$qty_index,'price'.$qty_index,'price'.$qty_index), $colour ;
		} # end foreach qty_index
	} # end foreach QP
	return @{$$variable{'PROJECTS'}};
} # end sub get_finished_quote_contents

1;

__END__
