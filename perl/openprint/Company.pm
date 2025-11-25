use strict;
use warnings;

package openprint::Company;
our @ISA = qw( openprint::Object );

use vars qw( $debug $log $dbh $table $serial %fields %find_fields %defaults %transforms $AUTOLOAD $default_sort );
require openprint;
*log = \$openprint::log;
*dbh = \$openprint::dbh;

require sql;
require openprint::Object;
require openprint::User;
require openprint::Project;
require openprint::Quote;
require openprint::Order;

$debug = 1;
$default_sort = 'lower(strcompanyname)';
$table = 'tbl_customer';
$serial = 'tbl_Customer_lngCustomerID_seq';

%fields = (
		id								=>	'lngcustomerid',
		name							=>	'strcompanyname',
		address1					=>	'straddress1',
		address2					=>	'straddress2',
		city							=>	'strcity',
		country						=>	'strcountry',
		state							=>	'strprovstate',
		postalcode				=>	'strpostalcodezip',
		salesrep_id 			=>	'lngsalesperson',
		pst_exempt				=>	'ysnpstexempt',
		gst_exempt				=>	'ysngstexempt',
		gst_number				=>	'strgstnumber',
		pst_number				=>	'strpstnumber',
		supplier					=>	'ysnsupplier',
		reseller					=>	'ysnreseller',
		accountnumber			=>	'straccountnum',
		phone							=>	'strphone',
		extension					=>	'strext',
		fax								=>	'strfax',
		pricelist_id			=>	'lngpricelist',
		currency_id				=>	'lngcurrencyid',
		'url'						=>	'strweburl',
		discount					=>	'dblpricingpercent',
		credit_card_fee		=>	'credit_card_fee',
		csr_commission		=>	'csr_commission',
		activated				=>	'ysnaccountactivation',
		greeting					=>	'strcustomgreeting',
		mailinglist				=>	'ysnmailinglist',
		business_type				=>	'strbusinesstype',
		business_name				=>	'strlegalbusname',
		business_form				=>	'strbusinessnature',
		established				=>	'dtmbusinessstartdate',
		president_owner			=>	'strpresidentowner',
		created_on				=>	'dtmdateentered',
		updated_on				=>	'dtmlastmodified',
		bank_name					=>	'strbankname',
		bank_branch				=>	'strbankbranch',
		bank_account			=>	'strbankaccountno',
		bank_manager			=>	'strbankaccountmanager',
		bank_phone				=>	'strbankphone',
		bank_fax					=>	'strbankfax',
		bank_email				=>	'strbankemail',
		detail_level			=>	'detail_level',
		quote_project_breakdown	=>	'quote_project_breakdown',
		notes						=>	'notes',
		deleted					=>	'deleted',
		category_id				=>	'category_id',
    offers_credit				=>	'offers_credit',
		last_project_id			=>	'last_project_id',
		last_project_on			=>	undef,
		last_order_id				=>	'last_order_id',
		last_order_on				=>	undef,
		last_quote_id				=>	'last_quote_id',
		last_quoted_on				=>	undef,
		last_invoice_id			=>	'last_invoice_id',
    ysnpricingservices  => 'ysnpricingservices',
    ysnpricingprojectview => 'ysnpricingprojectview',
    ysnpricingquotes =>'ysnpricingquotes',
    nationalcredit      => 'nationalcredit',
    ordercredit         => 'ordercredit',
    mailingcredit       => 'mailingcredit',
		);
%find_fields = (
	last_online	=>	'(SELECT MAX(date_time) FROM Logs WHERE company_id=companies.id)',
	last_ordered_on	=>	'(SELECT '.$openprint::Order::fields{created_on}.' FROM '.$openprint::Order::table.' WHERE '.$openprint::Order::table.'.'.$openprint::Order::fields{id}.'=last_order_id)',
	last_project_on	=>	'(SELECT dtmcreationdate FROM '.$openprint::Project::table.' WHERE '.$openprint::Project::table.'.'.$openprint::Project::fields{id}.'=last_project_id)',
	last_quoted_on	=>	'(SELECT MAX('.$openprint::Quote::fields{created_on}.') FROM '.$openprint::Quote::table.' WHERE '.$openprint::Quote::fields{company_id}.'='.$table.'.'.$fields{id}.')',
	last_called_on	=>	'(SELECT MAX(date_time) FROM sales_logs WHERE company_id=companies.id)',
	last_invoiced_on	=>	'(SELECT MAX(created_on) FROM invoices WHERE invoicee_id=companies.id)',
  last_expense_on   =>  '(SELECT MAX(created_on) FROM expenses WHERE recipient_Id=companies.id)',
	credit_app_on	=>	'(SELECT MAX(dtmcreationdate) FROM creditapplications WHERE company_id=companies.id)',
	marketing_category_id	=>	'(SELECT category_id FROM companies_in_marketing_categories WHERE company_id='.$table.'.'.$fields{id}.')',
  profile_field	=>	'(SELECT value FROM Company_Profiles WHERE company_id='.$table.'.'.$fields{id}.' AND field_id=?)',
  last_article_id	=>	'(SELECT MAX(id) FROM Articles WHERE company_id='.$table.'.'.$fields{id}.')',
  last_timetrack_id	=>	'(SELECT MAX(id) FROM timetracks WHERE company_id='.$table.'.'.$fields{id}.')',
	is_invoiced=> 'id IN (SELECT invoicee_id FROM invoices)',
);

%transforms = (
	address1					=>	[ 's/^\s+//', 's/\s+$//' ],
	address2					=>	[ 's/^\s+//', 's/\s+$//' ],
	notes							=>	[ 's/^\s+//', 's/\s+$//' ],
	established				=>	[ 's/[^\d\-]//g' ],
	name							=>	[ 's/[\,]//g', 's/^\s+//', 's/\s+$//','s/\///g' ],
	business_name			=>	[ 's/^\s+//', 's/\s+$//' ],
	discount					=>	[ 's/[^\d\.\-]//g' ],
	csr_commission		=>	[ 's/[^\d\.\-]//g' ],
	credit_card_fee		=>	[ 's/[^\d\.\-]//g' ],
);
%defaults = (
	detail_level		=>	undef,
	discount				=>	0,
	created_on			=>	q`'NOW()'`,
	updated_on			=>	q`'NOW()'`,
	category_id			=>	undef,
	currency_id			=>	undef,
	pricelist_id		=>	undef,
	activated			=>	q`'N'`,
	mailinglist			=>	q`'N'`,
	salesrep_id			=>	undef,
	deleted					=>	0,
	offers_credit		=>	0,
	supplier				=>	q`'N'`,
	last_order_id		=>	undef,
	last_quote_id		=>	undef,
	last_project_id	=>	undef,
	last_invoice_id	=>	undef,
	csr_commission	=>	undef,
	credit_card_fee	=>	undef,
  ysnpricingservices => 1,
  ysnpricingprojectview => 0,
  ysnpricingquotes => 0,


);

sub Currency {
	if ( ! $_[0]{Currency} ) {
		$_[0]{Currency} = new openprint::Currency( $_[0]{currency_id} );
	}
	return $_[0]{Currency};
} # end sub CUrrency

sub destroy {
	my $self = shift;
	my $ac = sql::start_transaction( $openprint::dbh );
	sql::execute( undef, undef, 'DELETE FROM Trade_References WHERE Company_id =?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM HelpDesk WHERE Company_Id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM RMA WHERE Company_Id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM Company_Credit WHERE Company_Id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM CreditApplications WHERE Company_Id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM Companies_in_Marketing_Categories WHERE Company_Id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM tbl_Addresses WHERE company_id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM Locations WHERE company_id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM Uploads WHERE company_id=?', $$self{id} );
  foreach (openprint::Asset->find(company_id=>$$self{id})) { $_->destroy(); }

	sql::execute( undef, undef, 'DELETE FROM Assets WHERE company_id=?', $$self{id} );
	foreach my $Payment ( openprint::Payment->find(recipient_id=>$$self{id}) ) {
		$Payment->delete();
	} # end foreach Payment
	sql::execute( undef, undef, 'DELETE FROM Complaints WHERE company_id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM survey_responses WHERE company_id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM logs WHERE company_id=?', $$self{id} );
  $openprint::log->error("Deleting purchaseorder_items");
  sql::update(undef, undef, 'purchaseorder_items', ['vendor_id=?', $$self{id}], vendor_id=>undef);
  sql::update(undef, undef, 'manifests', ['supplier_id=?', $$self{id}], supplier_id=>undef);

	foreach my $Paper ( openprint::Paper->find(owner_id=>$$self{id}) ) {
		$Paper->destroy();
	} # end foreach

  eval {
    require openprint::Quote;
    foreach my $Quote ( openprint::Quote->find(company_id=>$$self{id}) ) {
      $Quote->delete();	
    } # end foreach
  };
	foreach my $Order ( openprint::Order->find(company_id=>$$self{id}) ) {
		$Order->delete();	
	} # end foreach
	sql::execute( undef, undef, 'DELETE FROM Order_log WHERE company_id=?', $$self{id} );
	foreach my $Project ( openprint::Project->find(company_id=>$$self{id} ) ) {
		$Project->destroy();	
		last if $dbh->errstr();
	} # end foreach
	sql::execute(undef, undef, 'DELETE FROM Project_log WHERE Company_Id=?', $$self{id} );
	foreach my $User ( openprint::User->find(company_id=>$$self{id}, deleted=>[0,1] ) ) {
		$User->destroy();
	} # end foreach
	sql::execute(undef, undef, 'DELETE FROM Company_Profiles WHERE company_id=?',$$self{id} );
	sql::execute(undef, undef, 'DELETE FROM Companies WHERE id=?',$$self{id} );

	sql::end_transaction( $dbh, $ac );

   # Add record to audit log - action "Delete Company Profile".
   new openprint::Log()->save({action=>'Destroy Company', note=>"Company ID: $$self{id} $$self{name}"});
} # end sub destroy

sub save {
  my ($self, $param, $force ) = @_;
	
	$self->set( $param ? $param : {} );
	require Text::Unidecode;
	$$self{name} = Text::Unidecode::unidecode( $$self{name} );
	return $self->SUPER::save( undef, $force );
} # end sub save

sub next {
	my $self = shift;

  ( $_ ) = sql::execute( undef, undef, 'SELECT '.$fields{id}.' FROM '.$table.' WHERE '.$fields{name}.' = ( SELECT MAX('.$fields{name}.') FROM '.$table.' WHERE '.$fields{name}.' > (SELECT '.$fields{name}.' FROM '.$table.' WHERE '.$fields{id}.'=? ) )', $$self{id} );
  return $_;
} # end sub next

sub prev {
  my $self = shift;
  ( $_ ) = sql::execute( undef, undef, 'SELECT '.$fields{id}.' FROM '.$table.' WHERE '.$fields{name}.' = ( SELECT MAX('.$fields{name}.') FROM '.$table.' WHERE '.$fields{name}.' < (SELECT '.$fields{name}.' FROM '.$table.' WHERE '.$fields{id}.'=? ) )', $$self{id} );
  return $_;
} # end sub prev

sub load_tradereferences {
	my ( $self, $index, $hash ) = @_;

	@$hash{
		'tradereference'.$index.'_companyname',
			'tradereference'.$index.'_contact',
			'tradereference'.$index.'_phone',
			'tradereference'.$index.'_ext',
			'tradereference'.$index.'_fax',
			'tradereference'.$index.'_email',
			'tradereference'.$index.'_creditlimit',
			} = sql::execute( undef, undef, 
		'SELECT strCompanyName, strContact, strPhone, strExt, strFax, strEmail, dblCreditLimit FROM tbl_Trade_References WHERE lngcustomerid = ? AND lngreferenceid = ?', $$self{id}, $index );
} # end load_tradereferences

sub save_tradereferences {
	my ( $self, $param ) = @_;

	my $ac = sql::start_transaction( $dbh );
    sql::execute( undef, undef, 'DELETE FROM tbl_Trade_References WHERE lngcustomerid=?', $$self{id} );
	foreach my $tr ( 1 .. 3 ) {
		my %sql = (
			'strCompanyName'	=>	$$param{'tradereference'.$tr.'_companyname'},
			'strContact'		=>	$$param{'tradereference'.$tr.'_contact'},
			'strPhone'			=>	$$param{'tradereference'.$tr.'_phone'},
			'strExt'			=>	$$param{'tradereference'.$tr.'_ext'},
			'strFax',			=>	$$param{'tradereference'.$tr.'_fax'},
			'strEmail',		=>	$$param{'tradereference'.$tr.'_email'},
			'dblCreditLimit'	=>	$$param{'tradereference'.$tr.'_creditlimit'},
			'lngcustomerid'	=>	$$self{id},
			'lngreferenceid'			=>	$tr,
			);

		sql::insert( undef, undef, 'tbl_Trade_References', \%sql );
	} # end foreach
	sql::end_transaction( $dbh, $ac );
	return;
} # end sub save_tradereferences


sub Credit {
  my $self = shift;	
	my $supplier_id = $_[0] ?  $_[0] : $openprint::config{owner_id};
  if (!$supplier_id) {
    $openprint::log->error("Please set site owner for Credit.");
		return new openprint::Company_Credit();
  }

	require openprint::Company_Credit;
	if (!$$self{id}) {
		$_ =  new openprint::Company_Credit();
		$_->set({supplier_id=>$supplier_id});
		return $_;
	} # end if
	return new openprint::Company_Credit( { company_id=>$$self{id}, supplier_id=>$supplier_id } );
} # end sub Credit

sub dropdown {
	shift @_ if $_[0] eq 'openprint::Company';

	my %sql = @_;

	if ( $openprint::session{user_id} and ( $openprint::session{user_type} ne 'A' ) and ! openprint::usergroup::is_user_in( ['Estimating','Prepress','Accounting','Shipping','Inventory'], $openprint::session{user_id} ) ) {

		my %new_sql = ( and => [
			or => {
			salesrep_id => [ $openprint::session{user_id}, $openprint::User->csr_ids() ],
			id => $$openprint::User{company_id},
			},
			%sql,	
			],
		);
		%sql = %new_sql;
	#} else {
#$log->debug("Not adding filter to Company dropdown");
	} # end if
	
	return openprint::Company->SUPER::dropdown( %sql );
} # end sub dropdown

sub get_dropdown {
	shift @_ if $_[0] eq 'openprint::Company';
	my $companies = dropdown( $_[1] ? $_[1] : () );
	return $companies ? ssi::make_drop_down( $companies, $_[0], { encode=>1 } ) : '';
} # sub get_dropdown

sub CSR {
	if ( ! $_[0]{CSR} ) {
		$_[0]{CSR} = new openprint::User( $_[0]{salesrep_id} );
	}
	return $_[0]{CSR};
}

sub Users {
	my $self = shift;
	my %params = @_;
	$params{company_id} = $$self{id};
	return openprint::User->find( \%params );
} # end sub Users

sub Pricelist {
	if ( $_[0]{pricelist_id} ) {
		return new openprint::Pricelist( $_[0]{pricelist_id} );
	} else {
		return new openprint::Pricelist( openprint::pricing::get_pricelist_id());
	} # end if
} # end sub Pricelist

sub start_month {
	if ( $_[0]{established} =~ /^(\d+)-(\d+)-(\d+)/ ) {
		return $2;
	} # end if
} # end sub start_month
sub start_year {
	if ( $_[0]{established} =~ /^(\d+)-(\d+)-(\d+)/ ) {
		return $1;
	} # end if
} # end sub start_year

sub AccountingContacts {
	my ( $self ) = @_;
	my @user_ids = sql::execute(undef,undef,'SELECT user_id FROM companies_accountingcontacts WHERE company_id=?',$$self{id} );

	return openprint::User->find(id=>\@user_ids) if @user_ids;
	return;
} # end sub AccountingContacts

sub get_shipping_address {
	my $self = shift;

	require openprint::address;
	my ( $address_index ) = sql::execute( undef,undef, 'SELECT MAX(lngIndex) FROM tbl_Addresses WHERE Company_id=?', $$self{id} );
	my $Address = new openprint::address( $log, $dbh, $address_index, $$self{id} );
	return $Address;
} # end sub get_shipping_address

sub save_shipping {
	my ( $self, $params ) = @_;

	my $address = $self->get_shipping_address();
	$address->set( $params );
} # end sub save_shipping

sub load_shipping {
	my ( $self, @params ) = @_;

	my $address = $self->get_shipping_address();
	return $address->get( @params );
} # end sub save_shipping

sub location {
	return misc::build_city_prov_country( $_[0]->get('city','state','country') );
} # end sub location

sub can_edit {
	return 1 if ! $_[0]{id};
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if $_[0]->salesrep_id() == $openprint::session{user_id};
	return 1 if $_[0]->salesrep_id() and sets::isin( $_[0]->salesrep_id(), $openprint::User->csr_ids() );
	return 1 if $_[0]{id} == $$openprint::User{company_id} and $$openprint::User{administrator} eq 'Y';
	return 1 if $openprint::User->in_Group('Estimating') and ( $_[0]{id} != $$openprint::User{company_id} );
	return 0;
} # end sub can_edit

sub can_delete {
	return 0 if ! $_[0]{id};
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if $_[0]->salesrep_id() == $openprint::session{user_id};
	return 1 if $_[0]->salesrep_id() and sets::isin( $_[0]->salesrep_id(), $openprint::User->csr_ids() );
	return 1 if $_[0]{id} == $$openprint::User{company_id} and $$openprint::User{administrator} eq 'Y';
	return 0;
}

sub taxexempt1 {
	if ( @_ > 1 ) {
		$_[0]{taxexempt1} = $_[1];
	} # end if
	if ( ! $_[0]{taxexempt1} ) {
		$_[0]{taxexempt1} = $_[0]{gstnumber} ? 'Y' : 'N';
	} # end if
	return $_[0]{taxexempt1};
} # end sub taxexempt1

sub taxexempt2 {
	if ( @_ > 1 ) {
		$_[0]{taxexempt2} = $_[1];
	} # end if
	if ( ! $_[0]{taxexempt2} ) {
		$_[0]{taxexempt2} = $_[0]{pstnumber} ? 'Y' : 'N';
	} # end if
	return $_[0]{taxexempt2};
} # end sub taxexempt2

sub address {
return join(', ', map { $_ ? $_ : () } @{$_[0]}{'address1','address2','city','state','postalcode','country'} );
} # end sub address

sub can_view_all {
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if openprint::usergroup::is_user_in( ['Estimating','Prepress','Accounting','Shipping','Inventory'], $openprint::session{user_id} );
	return 0;
} # end sub can_view_all

sub find_filtered {
    return if ! $openprint::session{user_id};
	shift @_ if $_[0] eq 'openprint::Company';
    return openprint::Company->find(order=>'lower(name)',@_) if $openprint::session{user_type} eq 'A';

    return openprint::Company->find(
        or		=> {
			id	=>	$openprint::User->company_id(),
			( ! openprint::usergroup::is_user_in( ['Estimating','Prepress','Accounting','Shipping','Inventory'], $openprint::session{user_id} ) ? (
																																				   salesrep_id => [ $openprint::session{user_id}, $openprint::User->csr_ids() ],
																																			  ) : () ),
		},
        order	=>'lower(name)',
		@_,
    );
} # end sub find_filtered

sub can_view {
	my $self = shift;
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if $$self{salesrep_id} == $openprint::session{user_id};
	return 1 if $$self{id} == $$openprint::User{company_id};
	return 1 if $$self{salesrep_id} and sets::isin( $$self{salesrep_id}, $openprint::User->csr_ids() );
	return 1 if openprint::usergroup::is_user_in( ['Estimating','Prepress','Accounting','Shipping','Inventory'], $openprint::session{user_id} );
	return 0;
} # end sub can_view

sub date_first_order {
	require openprint::Order;
	my $Order = openprint::Order->find_one(company_id=>$_[0]{id}, order=>'id' );
	return $Order->created_on() if $Order;
	return;
}

sub category {
	require openprint::Company_Category;
	return new openprint::Company_Category( $_[0]{category_id} )->name();
} # end sub category
sub Category {
	require openprint::Company_Category;
	return new openprint::Company_Category( $_[0]{category_id} );
} # end sub Category

sub AUTOLOAD {
	my $name = $AUTOLOAD;
	$name =~ s/.*://;
#$openprint::log->debug("AUTOLOAD $name");
    if ( $fields{$name} ) {
        if ( @_ > 1 ) {
#$openprint::log->debug("Autoload $name $_[0]");
            return $_[0]{$name} = $_[1];
        } else {
            return $_[0]{$name};
        } # end if
    } else {
        my $Profile = $_[0]->Profile();

		# Entry will be created if it is a valid field, but not saved
		my $Entry = $Profile->Field( $name );
		if ( defined $Entry ) {
			if ( @_ > 1 ) {
				$Entry->save({value=>$_[1]});
			}
			return $Entry;
		} else {
			return;

# This is superflous;

			if ( @_ > 1 ) {
$openprint::log->error("Profile field setting $name when not exists " );
			}

		} # end if ! Entry
	} # end if in fields on in profile
	return;
} # end sub AUTOLOAD

sub Profile {
	if ( ! exists $_[0]{Profile} ) {
		require openprint::Company_Profile;
		$_[0]{Profile} = new openprint::Company_Profile( $_[0]{id} );
	} # end if
	return $_[0]{Profile};
} # end sub Profile

sub tax_code {
	if ( $_[0]{gst_exempt} eq 'Y' ) {
		return '1';
	} else {
		require openprint::Tax;
		if ( $_[0]->country() and $_[0]->state() ) {
			my @Taxes = openprint::Tax->find(
						'period_start null_or_<='   =>  'NOW()',
						'period_end null_or_>='     =>  'NOW()',
						'country'   =>  $_[0]->country(),
						'state'     =>  $_[0]->state()
						);
			return join('/', map { $_->name() } @Taxes ) if @Taxes;
		} # end if country and state
	} # end if
	return '0';
} # end if

sub admin_link_to {
	return sprintf('<a href="%s/administrator/managerial/company_profiles.html?ddmCustomer=%d">%s</a>',
   ($openprint::config{url_base} ? $openprint::config{url_base} : ''),
   $_[0]{id}, ssi::html_escape( @_ > 1 ? $_[1] : $_[0]{name} )
 );
} # end sub link_to

sub link_to {
	if ( $openprint::session{user_type} eq 'A' ) {
		return sprintf('<a href="%s/administrator/managerial/company_profiles.html?ddmCustomer=%d">%s</a>',
      ($openprint::config{url_base} ? $openprint::config{url_base} : ''),
      $_[0]{id}, ssi::html_escape( @_ > 1 ? $_[1] : $_[0]{name} ) );
	}
	return sprintf('<a href="/account/company_profile.html?company_id=%d">%s</a>', $_[0]{id}, ssi::html_escape($_[0]{name}) );
} # end sub link_to

sub last_project {
  my $self = shift;
  $$self{last_project} = shift if @_;
  $$self{last_project} = openprint::Project->find_one(company_id=>$_[0]{id},
    order=>$openprint::Project::fields{created_on}.' DESC') if (!$$self{last_project}) and $_[0]{id};
  return $$self{last_project};
}

sub last_project_on {
	if ( ! exists $_[0]{last_project_on} ) {
    my $last = $_[0]->last_project();
    $_[0]{last_project_on} = $last->created_on() if $last;
  }
  return $_[0]{last_project_on};
} # end sub last_project_on

sub last_quote {
  my $self = shift;
  $$self{last_quote} = shift if @_;
  $$self{last_quote} = openprint::Quote->find_one(company_id=>$$self{id}, order=>$openrpint::Quote::fields{id}.' DESC') if $$self{id} and !$$self{last_quote};
  return $$self{last_quote};
}

sub last_quoted_on {
	if ( ! exists $_[0]{last_quoted_on} ) {
    my $last = $_[0]->last_quote();
		$_[0]{last_quoted_on} = $last->created_on() if $last;
	}
	return $_[0]{last_quoted_on};
} # end sub last_quoted_on

sub last_ordered_on {
	if ( ! exists $_[0]{last_ordered_on} ) {
		(  $_[0]{last_ordered_on} ) = sql::execute( undef, undef, 'SELECT MAX(created_on) FROM Orders WHERE company_id=?', $_[0]{id} );
	}
	return $_[0]{last_ordered_on};
} # end sub last_ordered_on

sub last_called_on {
	if ( ! exists $_[0]{last_called_on} ) {
		(  $_[0]{last_called_on} ) = sql::execute( undef, undef, 'SELECT MAX(date_time) FROM sales_logs WHERE company_id=?', $_[0]{id} );
	}
	return $_[0]{last_called_on};
}  # end sub last_called_on

sub last_online {
	if ( ! exists $_[0]{last_online} ) {
		(  $_[0]{last_online} ) = sql::execute( undef, undef, 'SELECT MAX(date_time) FROM logs WHERE company_id=?', $_[0]{id} );
	}
	return $_[0]{last_online};
}  # end sub last_online

sub Country {
	if ( ! $_[0]{Country} ) {
		$_[0]{Country} = openprint::Location->find_one( type=>'country', short=>$_[0]->country() );
		if ( ! $_[0]{Country} ) {
			 $_[0]{Country} = new openprint::Location();
			 $_[0]{Country}->set( { type=>'country', short=>$_[0]->country() } );
		}
	}
	return $_[0]{Country};
} # end sub Country

sub can_become {
	my $C = shift;
	my $User = shift;
	$User = $openprint::User if ! $User;
	if ( 
			( $$User{type} eq 'A' )
			or
			( $$User{id} == $$C{salesrep_id} )
			or
			sets::isin( $$User{id}, $C->CSR()->assistant_ids() )
			or
			$User->in_Group('Estimating')
		 ) {
		return 1;
  }
  return 0;
}

sub accounting_contact_ids {
  my $self = shift;
  if ( !exists $$self{accounting_contact_ids}) {
    $$self{accounting_contact_ids} = [ sql::execute(undef,undef,'SELECT user_id FROM companies_accountingcontacts WHERE company_id=?', $$self{id}) ];
  }
  return @{$$self{accounting_contact_ids} };
}

1;
__END__
