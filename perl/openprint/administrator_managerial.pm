use strict;
package openprint::administrator_managerial;

use openprint ();

require sql;
require ssi;
require configuration;
require Configuration;
require email;
require openprint::Currency;
require openprint::User;
require openprint::User_Type;
require openprint::logs;
require openprint::address;
require openprint::Company;
require openprint::Company_Profile;
require openprint::Tax;
require openprint::Email;
require openprint::UserGroup;
require openprint::Invoice;
require openprint::MarketingCategory;
require openprint::Payment;
require openprint::Timetrack;
require openprint::User_Profile_Field;
require openprint::User_Notification;
require openprint::Company_Profile_Field;
require openprint::Company_Category;
require openprint::Company_Credit;


use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

sub configuration {

	if ( $param{btnFunction} eq 'New' ) {
    my $entry = Configuration->find_one(name=>$param{name});
    $entry = new Configuration() if ! $entry;
    $entry->save({
        name => $param{name},
        description	=>	$param{description},
        type			=>	$param{type},
        category		=>	( $param{new_category} ? $param{new_category} : $param{category} ),
        (exists $param{value} ? ( value	=>	$param{value} ) : () ),
      });
	} elsif ( $param{btnFunction} eq 'Save' ) {
    my @changes;

		foreach my $C ( Configuration->find() ) {
			my $name = $$C{name};
			if ( $name =~ /%20/ ) {
				$name =~ s/%20/ /g;
				$C->save({name=>$name});
			}
			$name =~ s/ /%20/g;
			if ( ! exists $param{$name} ) {
				$log->error("No value in param for $$C{name}");
				next;
			} # end if

			my $new_value = $param{$name};
			if ( $$C{type} eq 'list' ) {
				$new_value = join(',', misc::trim( split(',', $new_value ) ) );
			} # end if

			#if ( $name ne Configuration->transform('name',$name) ) {
#$log->debug("Name change detected: $$C{name} , wit");
				#$variable{error} .= $C->delete();
				#$C->description( $$C{name} ) if ! $C->description();
				#$variable{error} .= $C->save({value=>$new_value, name=>$$C{name},  });
        #} els
        if ( $$C{value} ne $new_value ) {
          if ( $$C{name} eq 'encrypt_passwords' ) {
            if ( (!$$C{value}) and $new_value ) {
              if ( 0 ) {
                eval {
                  require Authen::Passphrase;
                  require Authen::Passphrase::BlowfishCrypt;
                  # Special case need to update everyone's passwords
                  foreach my $User ( openprint::User->find() ) {
                    my $ppr = Authen::Passphrase::BlowfishCrypt->new( cost => 8, salt_random => 1, passphrase => $$User{password} );
                    $variable{error} .= $User->save({ password => $ppr->as_rfc2307() });
                  } # end foreach User
                };
                $openprint::log->error("Eval errors updating everyone's passwords." . $@) if $@;
              }
              $variable{error} .= $C->save({ value=>$new_value });
            } else {
              $variable{error} .= "Turning off encryption is a manual process.<br/>";
              next;
            }
          } else {
            $C->save({ value=>$new_value });
          }
			} else {
				$log->debug("Value unchanged for $$C{name}: currnet: $$C{value} new: $param{$$C{name}}");
			} # end if
		} # end foreach

		# Add record to audit log - action "Update Configuration".
		new openprint::Log()->save({action=>'Update Configuration'});
    $variable{ExternalRedirect} = '/openprint/administrator/managerial/configuration.html';
	} elsif ( $param{action} eq 'delete' ) {
    my $entry = Configuration->find_one(name=>$param{name});
    $entry->delete();
		new openprint::Log()->save({action=>'Delete Configuration', notes=>$entry->to_string()});
    $variable{ExternalRedirect} = '/openprint/administrator/managerial/configuration.html';
	} # end if
} # end sub configuration

sub _configuration {
	if ( $param{action} eq 'delete' ) {
    my $entry = Configuration->find_one(name=>$param{name});
    $entry->delete();
		new openprint::Log()->save({action=>'Delete Configuration', notes=>$entry->to_string()});
	} # end if
} # end sub _configuration

sub _configuration_popup {
	if ( $param{name} ) {
		$variable{Entry} = Configuration->find_one(name=>$param{name});
		if ( ! $variable{Entry} ) {
			$variable{Entry} = new Configuration();
			$variable{error} = "No entry found for $param{name}<br/>";
		} # end if
	} else {
		$variable{Entry} = new Configuration();
	} # end if
} # end sub

sub taxes {
	if ( $param{action} ) {
		if ( $param{action} eq 'Delete' ) {
			my $ac = sql::start_transaction( $dbh );
			foreach my $id ( ref $param{tax_ids} eq 'ARRAY' ? @{$param{tax_ids}} : $param{tax_ids} ) {
				my $Tax = new openprint::Tax( $id );
				(new openprint::Log())->save({
						Object=>$Tax,
						action=>'Delete Tax',
						note	=>sprintf('Country: %s | State: %s', $Tax->country(), $Tax->state() )
						});
				$variable{error} .= $Tax->delete();
			} # end foreach
			sql::end_transaction( $dbh, $ac );
		} elsif ( $param{action} eq 'Save' ) {
			my $ac = sql::start_transaction( $dbh );
			foreach my $Tax ( openprint::Tax->find() ) {
				$variable{error} .= $Tax->save({
						name			=>	$param{'name-'.$Tax->id()},
						rate			=>	$param{'rate-'.$Tax->id()},
						period_start	=> ( Date::Calc::check_date( map { @param{'period_start-'.$$Tax{id}.'_'.$_} } ( 'year','month','day' ) ) 
								?
								sprintf('%.4d-%.2d-%.2d', map { @param{'period_start-'.$$Tax{id}.'_'.$_} } ( 'year','month','day' ))
								: undef ),
						period_end	=> ( Date::Calc::check_date( map { @param{'period_end-'.$$Tax{id}.'_'.$_} } ( 'year','month','day' ) )
								? sprintf('%.4d-%.2d-%.2d', map { @param{'period_end-'.$$Tax{id}.'_'.$_} } 'year','month','day' ) : undef ),
						});
				(new openprint::Log())->save({
						Object=>$Tax,
						action=>'Save Tax',
						note	=>sprintf('Country: %s | State: %s', $Tax->country(), $Tax->state() )
						});
			} # end foreach Tax
			if ( $param{'rate-New'} ) {
				my $Tax = new openprint::Tax();
				$variable{error} .= $Tax->save({
						name					=>	$param{'name-New'},
						rate					=>	$param{'rate-New'},
						country				=>	$param{'country-New'},
						state					=>	$param{'state-New'},
						period_start	=> ( Date::Calc::check_date( @param{'period_start-New_year','period_start-New_month','period_start-New_day'} ) ? sprintf('%.4d-%.2d-%.2d', @param{'period_start-New_year','period_start-New_month','period_start-New_day'} ) : undef ),
						period_end		=> ( Date::Calc::check_date( @param{'period_end-New_year','period_end-New_month','period_end-New_day'} ) ? sprintf('%.4d-%.2d-%.2d', @param{'period_end-New_year','period_end-New_month','period_end-New_day'} ) : undef ),
						});
				(new openprint::Log())->save({
						Object=>$Tax,
						action=>'Save Tax',
						note	=>sprintf('Country: %s | State: %s', $Tax->country(), $Tax->state() )
						});
			} # end if New Tax

			sql::end_transaction( $dbh, $ac );
			$variable{ExternalRedirect} = '/administrator/managerial/taxes.html';
		} elsif ( $param{action} eq 'Download' ) {
			my @header = ( 'Name', 'Period Start', 'Period End', 'Canada', 'Province', 'Rate' );
			my @data;
			foreach my $Tax ( openprint::Tax->find() ) {
				push @data, $Tax->name(),
						 ssi::format_csv_date( $Tax->period_start() ),
						 ssi::format_csv_date( $Tax->period_end() ),
						 $Tax->country(),
						 $Tax->state(),
						 $Tax->rate();
			}
			misc::export_csv( $r, $log, \%variable, 'taxes.csv', \@header, \@data );
		} # end if
	} # end if action
} # end sub taxes

sub currency {
	if ( $param{btnFunction} eq 'Save' ) {
		(new openprint::Log())->save({action=>'Update Currency'});

		if ( $param{name} ) {
			my $Currency = new openprint::Currency();
			$variable{error} .= $Currency->save({
				name	=>	$param{name},
				short	=>	$param{short},
				symbol	=>	$param{symbol},
        precision => $param{precision},
				});
		} # end if

		foreach my $Currency ( openprint::Currency->find() ) {
			if ( $param{'name-'.$Currency->id()} ) {
				$variable{error} .= $Currency->save({
						name	=>	$param{'name-'.$$Currency{id}},
						short	=>	$param{'short-'.$$Currency{id}},
						symbol	=>	$param{'symbol-'.$$Currency{id}},
						precision	=>	$param{'precision-'.$$Currency{id}},
						});
			} # end if
		} # end foreach
	} # end if

} # end sub currency

sub _currency_conversions {
	$variable{Currency} = new openprint::Currency( $param{currency_id} );
	if ( $param{btnFunction} eq 'Add' ) {

		my $now = sprintf('%.4d-%.2d-%.2d %.2d:%.2d:%.2d', Date::Calc::Today_and_Now() );
		# Find current
        my $Conversion = openprint::Currency_Conversion->find_one(from_id=>$param{currency_id}, to_id=>$param{to_id}, period_end=>undef);
        if ( ! $Conversion ) {
            $Conversion = new openprint::Currency_Conversion();
            $variable{error} .= $Conversion->save({
					from_id	=>	$param{currency_id},
					to_id	=>	$param{to_id},
					rate	=>	$param{amount},
					});
        } elsif (Math::Round::nearest(0.01,$Conversion->rate()) != Math::Round::nearest(0.01, $param{amount} ) ) {
            $variable{error} .= $Conversion->save({period_end=>$now});
            $variable{error} .= $Conversion->save({id=>undef,
					period_start=>$now,
					period_end	=>	undef,
					rate=>$param{amount}});
		} else {
			$variable{warning} .= 'No change made.';
        } # end if

        $Conversion = openprint::Currency_Conversion->find_one(to_id=>$param{currency_id}, from_id=>$param{to_id}, period_end=>undef);
        if ( ! $Conversion ) {
            $Conversion = new openprint::Currency_Conversion();
            $variable{error} .= $Conversion->save({
					to_id	=>	$param{currency_id},
					from_id	=>	$param{to_id},
					rate	=>	Math::Round::nearest(0.0001,1/$param{amount}),
					});
        } elsif ( $Conversion->rate() != Math::Round::nearest(0.0001, 1/$param{amount}) ) {
            $variable{error} .= $Conversion->save({period_end=>$now});
            $variable{error} .= $Conversion->save({
					id			=>	undef,
					period_start=>	$now,
					period_end	=>	undef,
					rate		=>	Math::Round::nearest(0.0001,1/$param{amount}),
					});
        } # end if
	} # end if
} # end sub currency_conversions

sub user_profiles_action {
  my ($company_id, $User, $action) = @_;

	if ($action eq '<<') {
		$User = $User->Prev( type=>$param{ddmUserRole}, company_id=>$company_id );
	} elsif ($action eq '>>') {
		$User = $User->Next( type=>$param{ddmUserRole}, company_id=>$company_id );
  } elsif ( $action eq 'copy') {
    $User = $User->copy();
    $User->save({});
  } elsif ($action eq 'merge') {
    if ( $$User{id} == $param{merge_user_id} ) {
      $variable{error} .= 'Choose a different user to merge into.';
    } else {
      my $ac = sql::start_transaction( $dbh );
      foreach my $type ( 'Order','Quote','Project', 'Log','Timetrack' ) {
        require "openprint/$type.pm";
        foreach ( "openprint::$type"->find( user_id=>$param{merge_user_id}) ) {
          $variable{error} .= $_->save({user_id=>$User->id()});
        } # end foreach
      } # end foreach type
      foreach my $type ( 'Claim', 'PurchaseOrder' ) {
        require "openprint/$type.pm";
        foreach ( "openprint::$type"->find( contact_id=>$param{merge_user_id}) ) {
          $variable{error} .= $_->save({contact_id=>$User->id()});
        } # end foreach
      } # end foreach type
      new openprint::User( $param{merge_user_id} )->delete();
      sql::end_transaction( $dbh, $ac );
    } # end if
  } elsif ($action eq 'Undelete') {
    if ( $_ = $User->undelete() ) {
      $variable{error} .= "Error undeleting user: $_<br/>";
    } else {
      $variable{information} = 'User undeleted successfully.';
    } # end if
  } elsif ($action eq 'Delete') {
    $User->delete();
    $User = $User->Next(type=>$param{ddmUserRole}, company_id=>$company_id);
    $variable{information} = 'User marked deleted.';
  } elsif ($action eq 'Destroy') {
    $variable{error} .= $User->destroy();
    if (!$variable{error}) {
      $User = $User->Next(type=>$param{ddmUserRole}, company_id=>$company_id);
      $variable{information} = 'Record deleted.';
    }
  } elsif ($action eq 'Save') {
    if ( $param{password} ne $param{verifypassword} ) {
      return misc::error( $log, $dbh, \%variable, "Passwords don't match.", "Your password and verify password fields do not match.");
    } # end if

    my @Users = openprint::User->find( 'email lc' => lc $param{email} ) if $param{email};
    if ( @Users > 1 or ( ( @Users == 1 ) and ( $Users[0]->id() != $User->id() ) ) ) {
      $log->debug("User ids not match " . $Users[0]->id()  . ' != ' . $User->id() );
      my $error = "There is already one or more users with the specified email address.  They are listed below:<br/>";
      foreach my $U ( @Users ) {
        $error .= sprintf('<a href="/administrator/managerial/user_profiles.html?ddmUser=%d">%s : %s &lt;%s&gt; %s</a><br/>', $U->id(), $U->Company()->name(), $U->name(), $U->email(), $U->deleted() ? 'deleted' : '' );
      } # end foreach U

      return misc::error( $log, $dbh, \%variable, 'User already exists.', $error);
    } # end if

    if ( ! $param{password} ) {
      delete $param{password};
    } elsif ( $config{encrypt_passwords} ) {
      my $ppr;
      eval {
        require Authen::Passphrase;
        require Authen::Passphrase::BlowfishCrypt;
        $ppr = Authen::Passphrase::BlowfishCrypt->from_rfc2307($User->password());
      };
      if ( (! $ppr ) or ! $ppr->match($param{password}) ) {
        $param{password_changed_on} = 'NOW()';
        $ppr = Authen::Passphrase::BlowfishCrypt->new( cost => 8, salt_random => 1, passphrase => $param{password} );
        $param{password} = $ppr->as_rfc2307();
      } else {
        delete $param{password};
      } # end if

    } elsif ( $param{password} ne $User->password() ) {
      $param{password_changed_on} = 'NOW()';
    } # end if

    # This has to exist, in order to save the no assistants situation
    $param{assistant_ids} = [] if ! exists $param{assistant_ids};
    $param{csr_ids} = [] if ! exists $param{csr_ids};
    my $error = $User->save(\%param);
    if (!$error) {
      $User->Profile()->save(\%param);
      if ($config{FEATURE_PURCHASE_ORDERS} and ($config{FEATURE_PURCHASE_ORDERS} ne 'N')) {
        require openprint::PurchaseOrder_ContentType;
        foreach my $Type ( openprint::PurchaseOrder_ContentType->find() ) {
          $User->po_limit( $Type->id(), $param{'po_limit-'.$Type->id()} );
        } # end foreach Type
      }
    } # end if

    if ($error) {
      return misc::error( $log, $dbh, \%variable, 'Error Saving.', "There was an error saving the user's information. $error");
    } # end if

    if ( $config{mail_db_name} ) {
      email::save($User->email(), \%param);
    } # end if

    my @categories = sql::execute( $log, $dbh, 'SELECT id FROM Marketing_Categories' );
    sql::execute( $log, $dbh, 'DELETE FROM Users_in_Marketing_Categories WHERE user_id=?', $User->id() );

		# add them back in
		if ( $param{selectUserCategories} ) {
			my $sth = $dbh->prepare( q{INSERT INTO Users_in_Marketing_Categories (category_id,user_id) VALUES ( ?, ? )} );
			foreach my $cat ( ref $param{selectUserCategories} eq 'ARRAY' ? @{$param{selectUserCategories}} : $param{selectUserCategories} ) {
				if ( sets::isin( $cat, \@categories ) ) {
					$sth->execute( $cat, $User->id() ) or $log->error( DBI->errstr );
				} # end if
			} # end foreach
		} # end if

		sql::execute( $log, $dbh, q{DELETE FROM users_in_userGroups WHERE user_id=?}, $User->id() );
		if ( $param{UserGroups} ) {
			foreach my $group_id ( ref $param{UserGroups} eq 'ARRAY' ? @{$param{UserGroups}} : $param{UserGroups} ) {
				sql::insert( $log, $dbh, 'users_in_usergroups', ['usergroup_id', $group_id, 'user_id', $User->id() ] );
			} # end foreach
		} # end if

		foreach my $service_default_id ( sql::execute( undef, undef, 'SELECT id FROM User_Service_Defaults WHERE user_id=?', $User->id() ) ) {
			if ( $param{'name-'.$service_default_id} ) {
				sql::update( undef, undef, 'User_Service_Defaults', ['id=?'=>$service_default_id], {
						servicetype_id=>$param{'servicetype_id-'.$service_default_id} ? $param{'servicetype_id-'.$service_default_id} : undef,
						name=>$param{'name-'.$service_default_id},
						value=>$param{'value-'.$service_default_id}
						});
			} else {
				sql::execute( undef, undef, 'DELETE FROM User_Service_Defaults WHERE id=?', $service_default_id );
			} # end if
		} # end foreach

		if ( $param{'name-'} ) {
			sql::insert( undef, undef, 'User_Service_Defaults', {
					user_id			=>	$User->id(),
					servicetype_id	=>	$param{'servicetype_id-'} ? $param{'servicetype_id-'} : undef,
					name			=>	$param{'name-'},
					value			=>	$param{'value-'}
					} );
		} # end if

		$variable{information} = 'Record saved successfully.';
		$variable{ExternalRedirect} = '/administrator/managerial/user_profiles.html?ddmUser='.$User->id();
	} # end if btnFunction
  return $User;
} # end sub user_profiles_action

sub user_profiles {

	my $user_id = $param{ddmUser} ? openprint::User->transform( 'id', $param{ddmUser} ) : undef;
	$user_id = $param{user_id} ? openprint::User->transform( 'id', $param{user_id} ) : undef if ! $user_id;
	my $User = $variable{User} = new openprint::User( $user_id );

	my $user_role = $param{ddmUserRole};

	if ( exists $param{ddmCustomer} ) {
		if ( $param{ddmCustomer} and $User->company_id() and ( $User->company_id() != $param{ddmCustomer} ) ) {
      $log->error('Preventing customer change');
			# Prevent selection of user from another company
			$User = new openprint::User();
		} # end if
	} else {
		# The purpose of this code was something to do with selecting by email address. It would load the user, but not change the
		$param{ddmCustomer} = $User->company_id() if $User->id();
	} # end if

	# selected company
	my $company_id = $param{ddmCustomer} ? $param{ddmCustomer} : $session{company_id};
	$param{ddmCustomer} = $company_id if ! $param{ddmCustomer};

  if ($param{btnFunction}) {
    $User = user_profiles_action($company_id, $User, $param{btnFunction});
  }

	# if we don't have a selected user, pick the first one returned filtered by company and user type if specified
	my @Users = openprint::User->find(
		( $company_id ? ( company_id=>$company_id ) : () ),
		( $user_role ? ( type=>$user_role ) : () ),
		( $param{deleted} ne '' ? ( deleted=>$param{deleted} ) : () ),
		);

	if ( $User->deleted() ) {
		unshift @Users, $User;
	} # end if

	if ( ! $User->id() ) {
		if ( $session{user_id} and sets::isin( $session{user_id}, map { $_->id() } @Users ) ) {
			$User = new openprint::User( $session{user_id} );
		} else {
			$User = $Users[0] if @Users;
		} # end if
  } # end if

	if ( $User->id() ) {
		if ( $User->deleted() ) {
			unshift @Users, $User;
		} elsif ( ! sets::isin( $User->id(), [ map { $_->id() } @Users ] ) ) {
			unshift @Users, $User;
		} # end if
	} # end if

	$variable{UserIndex} = $User->id();
	$variable{User} = $User;
	$variable{Users} = \@Users;

	if ( $config{mail_db_name} ) {
		email::load($User->email(), \%variable);
		my $mail_dbh = email::db_connect();
		$openprint::Email_Account::dbh = $mail_dbh;
		$variable{Email} = openprint::Email_Account->find_one(username=>$User->email());
	} # end if

	# Get Marketing Category Inforamation - get all categories, and highlight the ones this user is in.
	my @available_categories = sql::execute( $log, $dbh, 'SELECT id, name FROM Marketing_Categories' );

	# get categories this customer is in we do it this way to limit databse transaction to 2.
	my @users_categories;
	if ( $User->id() ) {
		@users_categories = sql::execute( $log, $dbh,'SELECT category_id FROM Users_in_Marketing_Categories WHERE user_id=?', $User->id() );
	} # end if
	$variable{selectUserCategories} = ssi::make_drop_down( \@available_categories, \@users_categories );

	$session{$r->uri().'?company_id'} = $param{ddmCustomer};

	ssi::setup_date_select( $r->uri, 'log_created_on_start', -31 );
	ssi::setup_date_select( $r->uri, 'log_created_on_end', '' );

} # end sub user_profiles


sub company_profiles {

	ssi::save_params( '/administrator/managerial/company_profiles.html', ( 'search_salesrep_id','deleted' ) );
  # form field to db field mappings
	my %shipping_fields = (
			'txtShippingCompanyName'	=>	'CompanyName',
			'rdbShippingSalutation'	 	=>	'Salutation',
			'txtShippingFirstName'		=>	'FirstName',
			'txtShippingLastName'		=>	'LastName',
			'txtShippingAddress1'		=>	'Address1',
			'txtShippingAddress2'		=>	'Address2',
			'txtShippingCity'			=>	'City',
			'ddmShippingStateProvince'	=>	'StateProvince',
			'ddmShippingCountry'		=>	'Country',
			'txtShippingPostalCode'		=> 'PostalCode',
			'txtShippingPhone'			=>	'Phone',
			'txtShippingExtension'		=>	'Extension',
			'txtShippingFax'			=>	'Fax',
			'txtShippingEmail'			=>	'Email',
	);

	my $index = $param{ddmCustomer};
	$index = $param{company_id} if ! $index;
	my $Company = new openprint::Company( $index );

	if ( $param{btnFunction} eq '<<' ) {
		$index = $Company->prev();
		$Company = new openprint::Company( $index );
	} elsif ( $param{btnFunction} eq '>>') {
		$index = $Company->next();
		$Company = new openprint::Company( $index );
	} elsif ( $param{btnFunction} eq 'Go' ) {
		if ($param{txtSearchAccountNum}) {
      my $c = openprint::Company->find_one(accountnumber=>$param{txtSearchAccountNum});
      if ($c) {
        $Company = $c;
        $index = $c->id();
      }
		} # end if
	} elsif ( $param{btnFunction} eq 'merge' ) {
		if ( ! $param{company_id} ) {
			$variable{error} .= 'There must be a selected company to merge to.';
		} elsif ( ! $param{merge_company_id} ) {
			$variable{error} .= 'There must be a selected company to merge from.';
		} elsif ( $param{company_id} == $param{merge_company_id} ) {
			$variable{error} .= 'Choose a different company to merge into.';
		} else {
			my $ac = sql::start_transaction( $dbh );
			foreach my $type ( 'User','Order','Quote','Project', 'Claim', 'Log','Timetrack' ) {
				require "openprint/$type.pm";
				foreach ( "openprint::$type"->find( company_id=>$param{merge_company_id} ) ) {
					$_->save({company_id=>$Company->id()});
				} # end foreach
			} # end foreach type
			foreach my $Timetrack ( openprint::Timetrack->find('owner_id'=>$param{merge_company_id}) ) {
				$Timetrack->save({'owner_id'=>$Company->id()});
			} # end foreach Timetrack
			foreach ( openprint::Invoice->find(invoicer_id=>$param{merge_company_id}) ) {
				$_->save({invoicer_id=>$Company->id()});
			} # end foreach
			foreach ( openprint::Invoice->find(invoicee_id=>$param{merge_company_id}) ) {
				$_->save({invoicee_id=>$Company->id()});
			} # end foreach
			foreach my $Payment ( openprint::Payment->find(payor_id=>$param{merge_company_id}) ) {
				$Payment->save({payor_id=>$Company->id()});
 #if $Payment->payor_id() == $Company->id();
			} # end foreach  Payment
			foreach my $Payment ( openprint::Payment->find(recipient_id=>$param{merge_company_id}) ) {
				$Payment->save({recipient_id=>$Company->id()});
# if $Payment->recipient_id() == $Company->id();
			} # end foreach  Payment
			foreach my $Stock ( openprint::Paper->find(supplier_id=>$param{merge_company_id}) ) {
				$Stock->save({supplier_id=>$Company->id()});
 #if $_->supplier_id() == $Company->id();
			} # end foreach  Stock
			new openprint::Company( $param{merge_company_id} )->delete();
			sql::end_transaction( $dbh, $ac );
		} # end if
	} elsif ( $param{btnFunction} eq 'Save' ) {
		if ( ! $param{name} ) {
			$variable{error} .= 'Empty company name. You must supply a Company Name.<br/>';
		} else {
			$index = $param{company_id};
			$Company = new openprint::Company( $param{company_id} );
			$param{start_year} =~ s/\D//g;
			if ( $param{start_year} ) {
				$param{start_month} = '01' if ! $param{start_month};
				$param{established} = $param{start_year} . '-' . $param{start_month} . '-01';
			} # end if
			my @changes = $Company->changes( \%param );
			if ( @changes ) {
				$variable{error} .= $Company->save( \%param );
				(new openprint::Log())->save({object_id=>$$Company{id},object_type=>ref$Company, action=>'Edit Company', note=>join('<br/>', @changes) });
			}
			$index = $Company->id();

			if ( $index > 0 ) {
				my $ac = sql::start_transaction( $dbh );
				$Company->Profile()->save( \%param );
# Otherwise Error!
# Customer Categories
# I was trying to do this the hard way.	Then it occurred to me: Just delete them all from the table, and add back in the ones we want.
				my @customercategories = sql::execute( $log, $dbh, 'SELECT id FROM Marketing_Categories' );

				sql::execute( $log, $dbh, q{DELETE FROM Companies_in_Marketing_Categories WHERE company_Id =?}, $index );
				if ( $param{selectCustomerCategories} ) {
					my $sth = $dbh->prepare( q{INSERT INTO Companies_in_Marketing_Categories (Category_Id,Company_Id) VALUES ( ?, ? )} );
					foreach my $cat ( $param{selectCustomerCategories} ) {
						if ( $cat and sets::isin( $cat, \@customercategories ) ) {
							$sth->execute( $cat, $index ) or $log->error( DBI->errstr );
						} # end if
					} # end foreach
					$sth->finish();
				}

				my %params;
				foreach my $field ( keys %shipping_fields ) {
					$params{$shipping_fields{$field}} = $param{$field} if defined $param{$field};
				} # end foreach
				$Company->save_shipping(\%params);

				$Company->save_tradereferences(\%param);

				$dbh->do( 'LOCK TABLE Company_Credit IN ACCESS EXCLUSIVE MODE' ) or $log->error( DBI->errstr );

				foreach my $Supplier ( openprint::Company->find('offers_credit'=>1) ) {
					my $Credit = new openprint::Company_Credit( {'company_id'=>$index, 'supplier_id'=>$Supplier->id() } );

					if (
							( $Credit->terms() != openprint::Company_Credit->transform('terms', $param{'terms-'.$$Supplier{id}} ) ) or
							( $Credit->denydays() != openprint::Company_Credit->transform('denydays', $param{'denydays-'.$$Supplier{id}} ) ) or
							( $Credit->warndays() != openprint::Company_Credit->transform('warndays', $param{'warndays-'.$$Supplier{id}} ) ) or
							( $Credit->limit() != openprint::Company_Credit->transform('limit', $param{'limit-'.$$Supplier{id}} ) ) or
							( $Credit->hold() ne openprint::Company_Credit->transform('hold', $param{'hold-'.$$Supplier{id}} ) ) or
							( $Credit->downpayment() != openprint::Company_Credit->transform('downpayment', $param{'downpayment-'.$$Supplier{id}} ) ) or
							( $Credit->cod() != openprint::Company_Credit->transform('cod', $param{'cod-'.$$Supplier{id}} ) ) or
							( $Credit->late_payment_amount() != openprint::Company_Credit->transform('late_payment_amount', $param{'late_payment_amount-'.$$Supplier{id}} ) ) or
							( $Credit->late_payment_units() ne openprint::Company_Credit->transform('late_payment_units', $param{'late_payment_units-'.$$Supplier{id}} ) ) or
							( $Credit->early_payment_amount() != openprint::Company_Credit->transform('early_payment_amount', $param{'early_payment_amount-'.$$Supplier{id}} ) ) or
							( $Credit->early_payment_units() ne openprint::Company_Credit->transform('early_payment_units', $param{'early_payment_units-'.$$Supplier{id}} ) ) or
							( $Credit->early_payment_days() != openprint::Company_Credit->transform('early_payment_days', $param{'early_payment_days-'.$$Supplier{id}} ) )
					   ) {
						my $note = 'Old credit: ' . $Credit->to_string() if $Credit->supplier_id();
						$variable{error} .= $Credit->save( { 'company_id'=>$index, 'supplier_id'=>$Supplier->id(),
								map { $_ => $param{$_.'-'.$Supplier->id()} } ( 'terms', 'denydays', 'warndays', 'limit', 'hold', 'downpayment', 'cod', 'late_payment_amount','late_payment_units','early_payment_amount','early_payment_units', 'early_payment_days' ) } );
						$note .= '<br/>new credit: ' . $Credit->to_string();
						$variable{error} .= (new openprint::Log())->save( {
								action			=> 	'Credit Information Changed',
								object_id   =>  $index,
								object_type	=>	'openprint::Company',
								note        =>  $note,
								});
					} else {
						$variable{information} .= 'Credit unchanged for ' . $Supplier->name() . '<br/>';
					} # end if
				} # end foreach Supplier
				sql::end_transaction( $dbh, $ac );
				$variable{ExternalRedirect} = '/administrator/managerial/company_profiles.html?ddmCustomer='.$Company->id();
				return;
			} # end if $index
		} # end if input checks
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		$index = $Company->next();
		$Company->delete();
		$Company = new openprint::Company( $index );
	} elsif ( $param{btnFunction} eq 'Destroy' ) {
		if ( ! $Company->destroy() ) {
			$index = $Company->next();
		} # end if
		$Company = new openprint::Company( $index );
	} elsif ( $openprint::param{btnFunction} eq 'Undelete' ) {
		$Company->undelete();
	} # end if btnFunction

	my @customers_categories;
	if ( $index ) {
		my $shipping_address = $Company->get_shipping_address();
		@variable{ keys %shipping_fields } = ssi::htmlize( $shipping_address->get( @shipping_fields{ keys %shipping_fields } ) );
		$_ = q{SELECT category_id FROM Companies_in_Marketing_Categories WHERE Company_id =?};
		@customers_categories = sql::execute( $log, $dbh, $_, $index );
	} # end if

	$variable{txtPricingLevel} = sprintf ( "%.0f", $variable{txtPricingLevel} ) . "%";

	# Get Customer Category Inforamation - get all categories, and highlight the ones this customer is in.
	my @available_categories = map { $_->id(), $_->name() } openprint::MarketingCategory->find();
	$variable{selectCustomerCategories} = ssi::make_drop_down( \@available_categories, \@customers_categories );

	$variable{CustomerIndex} = $index;
	$variable{Company} = $Company;
} # end sub company_profiles

sub _company_accounting_contacts {
	$variable{Company} = new openprint::Company( $param{company_id} );
  if ($param{action}) {
    if ($param{action} eq 'add') {
      if ($param{user_id} and openprint::User->transform(id=>$param{user_id})) {
        my $ac = sql::start_transaction();
        sql::execute(undef, undef, 'DELETE FROM companies_accountingcontacts WHERE company_id=? AND user_id=?', @param{'company_id','user_id'});
        $variable{error} .= sql::insert(undef, undef, 'companies_accountingcontacts', 'company_id', $variable{Company}->id(), 'user_id', $param{user_id});
        sql::end_transaction(undef, $ac);
      } else {
        $variable{error} .= 'Invalid user id specified.<br>';
      } # end if
    } elsif ($param{action} eq 'delete') {
      sql::execute(undef, undef, 'DELETE FROM companies_accountingcontacts WHERE company_id=? AND user_id=?', @param{'company_id','user_id'});
    }
	} # end if
} # end sub

sub payment_options {
	require openprint::PaymentType;
	my $PaymentType = $variable{PaymentType} = new openprint::PaymentType( $param{paymenttype_id} );
	if ( $param{btnFunction} eq 'Save' ) {
    my @changes = $PaymentType->changes(\%param);
    if (@changes) {
      $variable{error} .= $PaymentType->save(\%param);
      (new openprint::Log())->save({Object=>$PaymentType, action=>'Edit', note=>join('<br/>', @changes) });
    }
		$variable{ExternalRedirect} = '/administrator/managerial/payment_options.html' if ! $variable{error};
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		$variable{error} .= $variable{PaymentType}->delete();
		$variable{ExternalRedirect} = '/administrator/managerial/payment_options.html' if ! $variable{error};
	} # end if
} # end sub payment_options

sub emails {
	require openprint::Email_Account;
	require openprint::Email_Alias;

	my $mail_dbh = email::db_connect();
	$openprint::Email_Account::dbh = $mail_dbh;

	if ( $param{action} ) {
		if ( $param{action} eq 'Delete' ) {
			foreach my $Email ( openprint::Email_Account->find(username=>$param{username}) ) {
				$variable{error} .= $Email->delete();
			} # end foreach Email
		} # end if
	} # end if
} # end sub emails

sub email {
	require openprint::Email_Account;
	require openprint::Email_Alias;

	my $mail_dbh = email::db_connect();
	if ( $mail_dbh ) {
		$openprint::Email_Account::dbh = $mail_dbh;
		$openprint::Email_Alias::dbh = $mail_dbh;
		my $Email = $variable{Email} = openprint::Email_Account->find_one( username=>$param{username} );
		$Email = $variable{Email} = new openprint::Email_Account() if ! $Email;
		if ( $param{action} ) {
			if ( $param{action} eq 'Delete' ) {
				$variable{error} .= $Email->delete();
			} elsif ( $param{action} eq 'Save' ) {
				my ( $account, $domain ) = split('@', $param{username});
				$variable{error} .= $Email->save({
						username=>$param{username},
						( ( $param{EmailPassword} and $param{EmailPassword} eq $param{VerifyEmailPassword} ) ? ( password=>$param{EmailPassword} ) : () ),
						name=>$param{name},
						active=>$param{active},
						maildir=>($param{maildir} ? $param{maildir} : join('/', $domain, $account,'')),
						} );

				my ($error, @c ) = email::save($Email->username(), \%param);
				$variable{error} .= $error;
			} # end if
			$variable{ExternalRedirect} = '/administrator/managerial/emails.html' if !$variable{error};
		} # end if action
		email::load( $Email->username(), \%variable);
	} else {
		$variable{error} .= "No connection to mail db.<br/>";
	} # end if have maildb connection
} # end sub email

sub usergroups {
	if ( $param{command} eq 'Save' ) {
		my $Group = new openprint::UserGroup($param{id});
		if ( $param{filename} ) {
			my $Asset = openprint::Asset::upload('filename');
			if ( ref $Asset ne 'openprint::Asset' ) {
				$variable{error} .= $Asset;
			} else {
				$param{asset_id} = $Asset->id();
			} # end if
		} # end if
		$variable{error} .= $Group->save(\%param);
    $variable{ExternalRedirect} = '/administrator/managerial/usergroups.html' if !$variable{error};
	} # end if
} # end sub usergroups

sub usergroup {
	$variable{UserGroup} = new openprint::UserGroup( $param{id} );
} # end sub usergroup

sub user_profile_fields {
	if ( $param{action} eq 'Save' ) {
		foreach my $Field ( openprint::User_Profile_Field->find() ) {
			$variable{error} .= $Field->save({
				'name'	=>	$param{'name-'.$Field->id()},
				'description'	=>	$param{'description-'.$Field->id()},
				'type'	=>	$param{'type-'.$Field->id()},
				'values'	=>	[ misc::trim( split(',', $param{'values-'.$Field->id()} ) ) ],
				'defaults'	=>	[ misc::trim( split(',', $param{'defaults-'.$Field->id()} ) ) ],
				'required'	=>	$param{'required-'.$Field->id()},
				'searchable'	=>	$param{'searchable-'.$Field->id()},
				'search_default'	=>	$param{'search_default-'.$Field->id()},
				'match'	=>	$param{'match-'.$Field->id()},
				'viewable'	=>	$param{'viewable-'.$Field->id()},
				'on_registration'	=>	$param{'on_registration-'.$Field->id()},
			});
		} # end foreach Field
	} # end if
} # end sub user_profile_fields
sub _field_tr {
	my $object_name;
	if ( $ENV{HTTP_REFERER} =~ /user_profile_fields/ ) {
		$object_name = 'openprint::User_Profile_Field';
	} elsif ( $ENV{HTTP_REFERER} =~ /company_profile_fields/ ) {
		$object_name = 'openprint::Company_Profile_Field';
	} # end if
	if ( ! $object_name ) {
		$log->error("Unknown referrer: $ENV{HTTP_REFERER}");
		return;
	} # end if

	$variable{Field} = $object_name->new( $param{field_id} );
	if ( $param{action} eq 'Add' ) {
		$variable{error} .= $variable{Field}->save({
			'name'	=>	'name',
		});
	} elsif ( $param{action} eq 'Delete' ) {
		$variable{error} .= $variable{Field}->delete();
		$variable{Field} = $object_name->new() if ! $variable{error};
	} elsif ( $param{action} eq 'Copy' ) {
		$variable{Field} = $variable{Field}->copy();
		$variable{error} .= $variable{Field}->save( \%param );
	} # end if
} # end sub _field_tr

sub _user_fields_tbody {
	if ( $param{action} eq 'up' ) {
		my @Fields = openprint::User_Profile_Field->find('order'=>'sort');
		my $i = 0;
		while ( $i < @Fields ) {
			last if $Fields[$i]->id() == $param{field_id};
			$i += 1;
		} # end while
		if ( $i and $i < @Fields ) {
			$_ = $Fields[$i-1];
			$Fields[$i-1] = $Fields[$i];
			$Fields[$i] = $_;
			$i = 0;
			foreach my $Field ( @Fields ) {
				$Field->save({'sort'=>$i});
				$i += 1;
			} # end foreach Field
		} # end if
	} elsif ( $param{update} ) {
		$param{update} =~ s/fields\[\]=//g;
		my $i = 0;
		foreach my $field_id ( split('&', $param{update} ) ) {
			my $Field = new openprint::User_Profile_Field( $field_id );
			$Field->save({'sort'=>$i});
			$i += 1;
		} # end foreach $feild_id
	} # end if
} # end sub _user_fields_tbody

sub company_profile_fields {
  if ($param{action}) {
    if ( $param{action} eq 'Save' ) {
      foreach my $Field ( openprint::Company_Profile_Field->find() ) {
        $variable{error} .= $Field->save({
            name	=>	$param{'name-'.$Field->id()},
            description	=>	$param{'description-'.$Field->id()},
            type	=>	$param{'type-'.$Field->id()},
            values	=>	[ split(',', $param{'values-'.$Field->id()} ) ],
            defaults	=>	[ misc::trim( split(',', $param{'defaults-'.$Field->id()} ) ) ],
            required	=>	$param{'required-'.$Field->id()},
            searchable	=>	$param{'searchable-'.$Field->id()},
            search_default	=>	$param{'search_default-'.$Field->id()},
            match			=>	$param{'match-'.$Field->id()},
            on_registration	=>	$param{'on_registration-'.$Field->id()},
            viewable		=>	$param{'viewable-'.$Field->id()},
          });
      } # end foreach Field
      if (!$variable{error}) {
        $variable{ExternalRedirect} = '/administrator/managerial/company_profile_fields.html';
      }
    } else {
      $variable{error} .= 'Invalid value for action: ' . $param{action}. '<br/>';
    }
	} # end if
} # end sub company_profile_fields

sub _company_fields_tbody {
	if ( $param{action} eq 'up' ) {
		my @Fields = openprint::Company_Profile_Field->find('order'=>'sort');
		my $i = 0;
		while ( $i < @Fields ) {
			last if $Fields[$i]->id() == $param{field_id};
			$i += 1;
		} # end while
		if ( $i and $i < @Fields ) {
			$_ = $Fields[$i-1];
			$Fields[$i-1] = $Fields[$i];
			$Fields[$i] = $_;
			$i = 0;
			foreach my $Field ( @Fields ) {
				$Field->save({'sort'=>$i});
				$i += 1;
			} # end foreach Field
		} # end if
	} elsif ( $param{update} ) {
		$param{update} =~ s/fields\[\]=//g;
		my $i = 0;
		foreach my $field_id ( split('&', $param{update} ) ) {
			my $Field = new openprint::Company_Profile_Field( $field_id );
			$Field->save({sort=>$i});
			$i += 1;
		} # end foreach $feild_id
	} # end if
} # end sub _company_fields_tbody

sub _search_by_email {
} # end sub _search_by_email

sub page_settings {
	require openprint::Page_Setting;
	if ( $param{action} eq 'save' ) {
		foreach my $PS ( openprint::Page_Setting->find(), new openprint::Page_Setting() ) {
			next if ! exists $param{'url-'.$PS->id()};

			my @usergroup_ids = ref $param{"usergroup_ids-$$PS{id}"} eq 'ARRAY' ? @{$param{"usergroup_ids-$$PS{id}"}} : ( $param{"usergroup_ids-$$PS{id}"} ) if $param{"usergroup_ids-$$PS{id}"};

			if ( defined $PS->id() and ! $param{'url-'.$PS->id()} ) {
				$PS->delete();
			} elsif (
					( $PS->url() ne openprint::Page_Setting->transform('url',$param{'url-'.$PS->id()}) ) or
					( $PS->cacheable() ne $param{'cacheable-'.$PS->id()} ) or
					( $PS->user_level() ne $param{'user_level-'.$PS->id()} ) or
					( $PS->keywords() ne $param{'keywords-'.$PS->id()} ) or
					( $PS->description() ne $param{'description-'.$PS->id()} ) or
					( $PS->message() ne $param{'message-'.$PS->id()} ) or
					( sets::union( ( $PS->usergroup_ids() ? @{$PS->usergroup_ids()} : () ), @usergroup_ids ) != sets::intersection( ( $PS->usergroup_ids() ? @{$PS->usergroup_ids()} : () ), @usergroup_ids ) ),

				) {
				$variable{error} .= $PS->save({
						url			=>	$param{'url-'.$$PS{id}},
						cacheable	=>	$param{'cacheable-'.$$PS{id}},
						user_level	=>	$param{'user_level-'.$$PS{id}},
						keywords	=>	$param{'keywords-'.$$PS{id}},
						description	=>	$param{'description-'.$$PS{id}},
						message		=>	$param{'message-'.$$PS{id}},
						usergroup_ids	=>	\@usergroup_ids,
						});
			} # end if need to save
		} # end foreach PS
	} # end if
} # end sub page_settings

sub _page_settings {
	ssi::save_params( '/administrator/managerial/page_settings.html', ( 'url' ) );

} # end sub _page_Settings

sub user_relationships {
	require openprint::User_Relationship;
	if ( $param{action} eq 'save' ) {
		foreach my $URT ( openprint::User_Relationship_Type->find() ) {
			$variable{error} .= $URT->save({
				'name'	=>	$param{'name-'.$URT->id()},
				'text1'	=>	$param{'text1-'.$URT->id()},
				'text2'	=>	$param{'text2-'.$URT->id()},
				'text3'	=>	$param{'text3-'.$URT->id()},
			});
		} # end foreach URT
		if ( $param{'name-new'} ) {
			my $URT = new openprint::User_Relationship_Type();
			$variable{error} .= $URT->save({
				'name'	=>	$param{'name-new'},
				'text1'	=>	$param{'text1-new'},
				'text2'	=>	$param{'text2-new'},
				'text3'	=>	$param{'text3-new'},
			});
		} # end if
	} # end if
} # end sub user_relationships
sub upload_log {
	ssi::save_params( '/administrator/managerial/upload_log.html', (
		( map { 'uploaded_on_start_'.$_ } ( 'year', 'month', 'day', 'hour','minute' ) ),
		( map { 'uploaded_on_end_'.$_ } ( 'year', 'month', 'day', 'hour','minute' ) ),
		'company_id','type',
	) );

	ssi::setup_date_select( '/administrator/managerial/upload_log.html', 'uploaded_on_start', -1 );
	ssi::setup_date_select( '/administrator/managerial/upload_log.html', 'uploaded_on_end', '' );
} # end sub upload_log

sub promo_codes {
	require openprint::Promo_Code;
	if ( $param{action} eq 'save' ) {
		foreach my $PC ( openprint::Promo_Code->find() ) {
			if ( ! $param{'code-'.$PC->code()}  ) {
				$PC->delete();
			} elsif (
					( $PC->code() ne $param{'code-'.$PC->code()} ) or
					( $PC->name() ne $param{'name-'.$PC->id()} ) or
					( $PC->effect() ne $param{'effect-'.$PC->id()} )
				) {
				$variable{error} .= $PC->save({
						'code'=>$param{'code-'.$$PC{code}},
						'name'=>$param{'name-'.$$PC{code}},
						'effect'=>$param{'effect-'.$$PC{code}},
						});
			} # end if need to save
		} # end foreach PC
		if ( $param{'code-new'} ) {
			my $PC = new openprint::Promo_Code();
			$variable{error} .= $PC->save({
					'code'=>$param{'code-new'},
					'name'=>$param{'name-new'},
					'effect'=>$param{'effect-new'},
					});
		} # end if
	} # end if
} # end sub promo_codes

sub logs {
	ssi::setup_date_select( $r->uri, 'date_start', -1 );
	ssi::setup_date_select( $r->uri, 'date_end', '' );
  _logs();
} # end sub logs

sub _logs {
	ssi::save_params( '/administrator/managerial/logs.html', (
        'log_actions', 'user_id', 'company_id',
				( map { 'date_start_' . $_ } ( 'year','month','day' ) ),
				( map { 'date_end_' . $_ } ( 'year','month','day' ) ),
				) );
	if ( $param{action} eq 'delete' ) {
		my $Log = new openprint::Log( $param{log_id} );
		$Log->delete();
	} # end if
} # end sub _logs

sub bitcoin {
} # end sub bitcoin

sub authorizations {
	require openprint::Authorization;
	require openprint::Object_Type;
	_authorizations();
	if ( $param{action} eq 'Save' ) {
		foreach my $Auth ( (new openprint::Authorization()), openprint::Authorization->find() ) {
			next if ! $param{"object_type_id-$$Auth{id}"};

			$variable{error} .= $Auth->save({
				mode			=>	$param{"mode-$$Auth{id}"},
				object_type_id	=>	$param{"object_type_id-$$Auth{id}"},
				object_id		=>	$param{"object_id-$$Auth{id}"},
				usertype_id		=>	$param{"usertype_id-$$Auth{id}"},
				usergroup_id	=>	$param{"usergroup_id-$$Auth{id}"},
				setting			=>	$param{"setting-$$Auth{id}"},
			});
		} # end foreach Auth
		$variable{ExternalRedirect} = '/administrator/managerial/authorizations.html';
	} # end if
} # end sub authorizations
sub _authorizations {
	ssi::save_params( '/administrator/managerial/authorizations.html', ( 'object_type_id' ) );
} # end sub _authorizations

sub companies {
	_companies();
	if ( $param{btnFunction} ) {
		if ( $param{btnFunction} eq 'Download' ) {
			my $uri = $r->uri();

      my %filters = (
        order =>  'lower(name)',
        ( $session{$uri.'?salesrep_id'} ? ( salesrep_id => $session{$uri.'?salesrep_id'} ) : () ),
        ( $session{$uri.'?company_name'} ? ( 'name ilike' => '%'.$session{$uri.'?company_name'}.'%' ) : () ),
        ( $session{$uri.'?deleted'} ne '' ? ( deleted => $session{$uri.'?deleted'} ) : () ),
        ( $session{$uri.'?country'} ne '' ? ( country => $session{$uri.'?country'} ) : () ),
        ( $session{$uri.'?marketing_category_id'} ? ( 'marketing_category_id any'=> $session{$uri.'?marketing_category_id'} ) : () ),

        ssi::date_filter( $uri.'?created_on_end', 'created_on <=' ),
        ssi::date_filter( $uri.'?created_on_start', 'created_on >=' ),
        ssi::date_filter( $uri.'?updated_on_end', 'updated_on <=' ),
        ssi::date_filter( $uri.'?updated_on_start', 'updated_on >=' ),
      );
      if ( $session{$uri.'?country_id'} ) {
        my $Country = new openprint::Location( $session{$uri.'?country_id'} );
        $filters{country} = $Country->short();
      }

			if ( $session{$uri.'?salesrep_id_exclude'} ) {
				my @csr_ids = map { $_->id() } openprint::User->find( company_id=>$config{owner_id}, 'usergroup any'=>'Sales' );
				@csr_ids = sets::exclude( [ split(',', $session{$uri.'?salesrep_id'} ) ], \@csr_ids ) if $session{$uri.'?salesrep_id'};
				$filters{'salesrep_id not in'} = \@csr_ids;
			} # end if

			my @Companies = openprint::Company->find( %filters );
			my @header = ( 'Company Name','Contact Name', 'Phone #', 'Email','City','State','Registration Date','Account Rep','# of Projects','Last Project', '# of Orders','Last Order');
			my @data;
			foreach my $Company ( @Companies ) {
				my $User = openprint::User->find_one( company_id=>$$Company{id}, order=>'id' );
				my $CSR = $Company->CSR();
				my @Projects = openprint::Project->find( company_id=>$$Company{id}, order=>'id DESC' );
				my @Orders = openprint::Order->find( company_id=>$$Company{id}, order=>'id DESC' );

				push @data, $Company->name(), ($User ? $User->name() : ''), $Company->phone(), ($User ? $User->email() : '' ), $Company->city(), $Company->state(),
						 ssi::format_date( $Company->created_on() ),
						 $CSR->name(), scalar @Projects,
						 (@Projects ? ssi::format_date( $Projects[0]->created_on() ) : ''),
						 scalar @Orders,
						 (@Orders ? ssi::format_date( $Orders[0]->created_on() ) : '' ),
			} # end foreach Company
			misc::export_csv( $r, $log, \%variable, 'customers.csv', \@header, \@data );
		}
	}
} # end sub companies

sub _companies {
	ssi::save_params( '/administrator/managerial/companies.html', (
				'salesrep_id', 'marketing_category_id', 'company_name', 'country', 'deleted','supplier',
				( map { 'created_on_start_' . $_ } ( 'year','month','day' ) ),
				( map { 'created_on_end_' . $_ } ( 'year','month','day' ) ),
				( map { 'updated_on_start_' . $_ } ( 'year','month','day' ) ),
				( map { 'updated_on_end_' . $_ } ( 'year','month','day' ) ),
				( map { 'last_project_on_start_' . $_ } ( 'year','month','day' ) ),
				( map { 'last_project_on_end_' . $_ } ( 'year','month','day' ) ),
				) );
	$session{$r->uri().'?salesrep_id_exclude'} = $param{salesrep_id_exclude};
  if ($param{action} eq 'delete') {
    foreach my $Company ( openprint::Company->find( id=> (ref $param{company_id} eq 'ARRAY') ? $param{company_id} : $param{company_id}) ) {
      $Company->delete();
    }
  } elsif ($param{action} eq 'undelete' ) {
    my @company_ids = (ref $param{company_id} eq 'ARRAY') ? @{$param{company_id}} : ($param{company_id});
    while (@company_ids) {
      foreach my $Company ( openprint::Company->find( id=> [ splice(@company_ids, 0, 100) ], deleted=>1) ) {
        if (!$Company->deleted()) {
          $variable{error} .= $Company->name() . ' not undeleted because not deleted.<br/>';
          next;
        }
        $Company->undelete();
      } # end foreach Company
    } # end while company_ids
  } elsif ($param{action} eq 'destroy' ) {
    my @company_ids = (ref $param{company_id} eq 'ARRAY' ? @{$param{company_id}} : ($param{company_id}));
    while (@company_ids) {
      foreach my $Company ( openprint::Company->find( id=> [ splice(@company_ids, 0, 100) ], deleted=>1) ) {
        if (!$Company->deleted()) {
          $variable{error} .= $Company->name() . ' not destroyed because not deleted.<br/>';
          next;
        }
        $Company->destroy();
      } # end foreach Company
    } # end while company_ids
  } # end if action
} # end sub _companies

sub folds {
  require openprint::Estimating::Folding; # for fold_types
	_folds();
} # end sub folds

sub _folds {
  require openprint::Fold;
	ssi::save_params( '/administrator/managerial/folds.html', ( 'equipment_id', 'type', 'imposition',
   'stitching','perfectbind','spinepaste' ) );
  return if !$param{action};
  if ($param{action} eq 'delete') {
    foreach my $fold ( openprint::Fold->find(id=>$param{fold_id}) ) {
      $variable{error} .= $fold->delete();
    }
  }
} # end sub _folds

sub shipping_rates {
	require openprint::Shipping_Rate;
}

sub _merge_popup {
	$variable{Company} = new openprint::Company( $param{company_id} );
}

sub _user_logs {
	$variable{User} = new openprint::User( $param{user_id} );
	ssi::save_params( '/administrator/managerial/user_profiles.html',
			( map { 'log_created_on_start_' . $_ } ( 'year','month','day','hour','minute' ) ),
			( map { 'log_created_on_end_' . $_ } ( 'year','month','day','hour','minute' ) ),
	);
} # end sub _logs

sub users {
  #$session{$r->uri().'?company_id'} = $session{company_id} if ! exists $session{$r->uri().'?company_id'};
	$session{$r->uri().'?deleted'} = '0' if ! exists $session{$r->uri().'?deleted'};
	_users();

	if ( $param{btnFunction} ) {
    if ($param{btnFunction} eq 'destroy') {
      foreach my $User ( openprint::User->find(
          deleted => 1,
          id=>[ref $param{user_id} eq 'ARRAY' ? @{$param{user_id}} : ($param{user_id})])) {
          if (!$User->deleted()) {
            $variable{error} .= 'User ' . $User->email() . ' not destroyed because not deleted<br/>';
            next;
          }
          $variable{error} .= $User->destroy();
      }
    } elsif ($param{btnFunction} eq 'delete') {
      foreach my $User ( openprint::User->find(id=>[ref $param{user_id} eq 'ARRAY' ? @{$param{user_id}} : ($param{user_id})])) {
          if ($User->deleted()) {
            $variable{error} .= 'User ' . $User->email() . ' not deleteed because already deleted<br/>';
            next;
          }
          $variable{error} .= $User->delete();
      }
    } elsif ($param{btnFunction} eq 'undelete') {
      foreach my $User ( openprint::User->find(
          deleted => 1,
          id=>[ref $param{user_id} eq 'ARRAY' ? @{$param{user_id}} : ($param{user_id})])) {
          if (!$User->deleted()) {
            $variable{error} .= 'User ' . $User->email() . ' not undeleted because already not deleted<br/>';
            next;
          }
          $variable{error} .= $User->undelete();
      }
    } elsif ( $param{btnFunction} eq 'Download in CSV format' ) {
			my @header = ( 'Id', 'Company', 'First Name', 'Last Name',
					'Email', 'Phone', 'Extension', 'Fax', 'Created On', 'Last Update'
					);
			my @data;
			my @Users = @{$variable{Users}};
			my %companies_by_id = misc::make_hash_from_array(id=>openprint::Company->find(id=>[map{$$_{company_id}} @Users])) if @Users;
			foreach my $User ( @Users ) {
				push @data, $User->id(), 
						 ($companies_by_id{$$User{company_id}} ? $companies_by_id{$$User{company_id}}[0]->name() : ''), 
						 $User->firstname(), $User->lastname(), $User->email(), $User->phone(),
						 $User->extension(), $User->fax(),
						 ssi::format_csv_date( $User->created_on() ),
						 ssi::format_csv_date( $User->updated_on() ),
			}
			misc::export_csv( $r, $log, \%variable, 'users.csv', \@header, \@data );
    } else {
      $log->error("Unknown function $param{btnFunction}");
		} # end if Download
	} # end if btnFunction
}

sub _users {
	my $uri = '/administrator/managerial/users.html';
	ssi::save_params($uri,(
				'salesrep_id', 'marketing_category_id', 'company_id','usergroup_id','deleted','email','type','administrator',
				'notification_type_id', 'web_active', 'ftp_active',
				( map { 'created_on_start_' . $_ } ( 'year','month','day' ) ),
				( map { 'created_on_end_' . $_ } ( 'year','month','day' ) ),
				) );
	$session{$uri.'?salesrep_id_exclude'} = $param{salesrep_id_exclude};

	if ( $param{btnFunction} ) {
    if ($param{btnFunction} eq 'destroy') {
      foreach my $User ( openprint::User->find(
          deleted => 1,
          id=>$param{user_id})) {
          if (!$User->deleted()) {
            $variable{error} .= 'User ' . $User->email() . ' not destroyed because not deleted<br/>';
            next;
          }
          $variable{error} .= $User->destroy();
      }
    } elsif ($param{btnFunction} eq 'delete') {
      my @user_ids = ( ref $param{user_id} eq 'ARRAY' ? @{$param{user_id}} : ($param{user_id}) );
      foreach my $User ( openprint::User->find(id=>\@user_ids) ) {
          if ($User->deleted()) {
            $variable{error} .= 'User ' . $User->email() . ' not deleted because already deleted<br/>';
            next;
          }
          $variable{error} .= $User->delete();
      }
    } elsif ($param{btnFunction} eq 'undelete') {
      foreach my $User ( openprint::User->find(
          deleted => 1,
          id=>[ref $param{user_id} eq 'ARRAY' ? @{$param{user_id}} : ($param{user_id})])) {
          if (!$User->deleted()) {
            $variable{error} .= 'User ' . $User->email() . ' not undeleted because already not deleted<br/>';
            next;
          }
          $variable{error} .= $User->undelete();
      }
    } else {
      $log->error('Unknown function '.$param{btnFunction});
    }
  }

  my @Users;

	my $uri = '/administrator/managerial/users.html';
	if ( $session{$uri.'?email'} ) {
		my %filters = (
				'email ilike' => '%'.$session{$uri.'?email'}.'%',
				deleted => $session{$uri.'?deleted'} eq '' ? [0,1] : $session{$uri.'?deleted'},
				);
		@Users = openprint::User->find(%filters);
	} else {
		my %filters = (
				( map { $session{join('?', $uri, $_)} ? ( $_ => $session{join('?', $uri, $_) } ) : () } ( 'company_id','type', 'web_active', 'ftp_active' ) ),
				ssi::date_filter( $uri.'?created_on_end', 'created_on <=' ),
				ssi::date_filter( $uri.'?created_on_start', 'created_on >=' ),
        limit => ($param{limit} ? $param{limit} : 1000),
				);
		if ( $session{$uri.'?deleted'} eq '' ) {
			$filters{deleted} = [0,1];
		} else {
			$filters{deleted} = $session{$uri.'?deleted'};
		}
		if ( $session{$uri.'?administrator'} ne '' ) {
			$filters{administrator} => $session{$uri.'?administrator'};
		}
		if ( $session{$uri.'?salesrep_id_exclude'} ) {
			my @csr_ids = map { $_->id() } openprint::User->find( company_id=>$config{owner_id}, 'usergroup any'=>'Sales' );
			@csr_ids = sets::exclude( [ split(',', $session{$uri.'?salesrep_id'} ) ], \@csr_ids ) if $session{$uri.'?salesrep_id'};
			$filters{'salesrep_id not in'} = \@csr_ids;
		} elsif ( $session{$uri.'?salesrep_id'} ) {
			$filters{salesrep_id} = $session{$uri.'?salesrep_id'};
		} # end if
		if ( $session{$uri.'?usergroup_id'} ) {
			$filters{usergroup_id} = $session{$uri.'?usergroup_id'};
		} # end if

		@Users = openprint::User->find( %filters );

		if ($session{$uri.'?notification_type_id'}) {
			my %Notifications = map { $$_{user_id}, $_ } openprint::User_Notification->find( type_id=>$session{$uri.'?notification_type_id'} );
			@Users = map { $Notifications{$$_{id}} ? $_ : () } @Users;
		}
	} # end if filtering by email or other
  my @Companies = openprint::Company->find(id=>[ map { $$_{company_id} } @Users ]) if @Users;
  $variable{Users} = \@Users;
} # end sub _users

sub mailqueue {
use Data::Dumper;
	if ( $param{action} ) {
		if ( $param{action} eq 'DeleteAndMarkInvalid' ) {
			my %queue_ids = map { $_ => $_ } ( ref $param{queue_id} eq 'ARRAY' ? @{$param{queue_id}} : ( $param{queue_id} ) );

			my @data = qx</usr/sbin/postqueue -j>;
			foreach ( @data ) {
				eval {
					my $queue_entry = JSON::decode_json($_);
					next if !$queue_ids{$$queue_entry{queue_id}};
					foreach my $recipient ( @{$$queue_entry{recipients}} ) {
						foreach my $User ( openprint::User->find(email=>$$recipient{address}) ) {
							if ( $User->email_valid() ) {
								$_ = $User->save({email_valid=>0});
								if ( ! $_ ) {
									$variable{information} .= 'User ' . $User->name() . ' marked invalid<br/>';
								} else {
									$variable{error} .= $_;
								}
							}
						} # end foreach $User
					} # end foreach $recipient
#$log->debug('Entry: '.Data::Dumper::Dumper($queue_entry) );

					$log->debug("sudo /usr/sbin/postsuper -d $$queue_entry{queue_id}");
					$variable{information} .= `sudo /usr/sbin/postsuper -d $$queue_entry{queue_id} 2>&1`.'<br/>';
				};
				$log->error("Error in eval $@") if $@;
			} # end foreach line
			$variable{ExternalRedirect} = '/administrator/managerial/mailqueue.html';
		} elsif ( $param{action} eq 'Delete' ) {
			foreach my $queue_id ( ref $param{queue_id} eq 'ARRAY' ? @{$param{queue_id}} : ( $param{queue_id} ) ) {
$log->debug("sudo /usr/sbin/postsuper -d $queue_id");
				$variable{information} .= `sudo /usr/sbin/postsuper -d $queue_id 2>&1`.'<br/>';
			}
			$variable{ExternalRedirect} = '/administrator/managerial/mailqueue.html';
		}
	}
} # end sub mailqueue

sub fold {
  require openprint::Estimating::Folding; # for fold_types
  require openprint::Fold; # for fold_types
	my $Fold = $variable{Fold} = new openprint::Fold( $param{fold_id} );
  return if !$param{action};

	if ( $param{action} eq 'add' ) {
		foreach my $k ( 'equipment_id' ) {
			$$Fold{$k} = $param{$k};
		} # end foreach
		$Fold->save();
		$variable{Fold} = $Fold;
	} elsif ( $param{action} eq 'copy' ) {
		my $NewFold = $Fold->copy();
		delete $param{fold_id};
		$variable{error} .= $NewFold->save(\%param);
		if ( ! $variable{error} ) {
		foreach my $Spec ( $NewFold->Specifications() ) {
			$_ = $Spec->save( {fold_id=>$NewFold->id() });
		} # end foreach Spec
		}
		$variable{Fold} = $NewFold;
		$param{fold_id} = $NewFold->id();
		
	} elsif ( $param{action} eq 'save' ) {
		my @changes = $Fold->changes( \%param );
		$variable{error} = $Fold->save(\%param);
		if ( ! $variable{error} ) {
      foreach my $spec ($Fold->Specifications()) {
        my %data = map { $_ => $param{$_.'-'.$spec->id() }} ('min','max','units','runspeed','interpolate' );
        my @spec_changes = $spec->changes(\%data);
        $spec->save(\%data) if @spec_changes;
        push @changes, @spec_changes;
      }
			my $Equipment = $Fold->Equipment();
			(new openprint::Log())->save({ object_type=>(ref $Equipment), object_id=>$$Equipment{id}, action=>'Save Fold', 
				note=>$$Fold{name} . ' ' . join('<br/>', @changes ) });
      $variable{ExternalRedirect} = '/administrator/managerial/folds.html';
		} # end if
		$variable{Fold} = $Fold;
	} elsif ( $param{action} eq 'delete' ) {
		$variable{error} = $Fold->delete();
    if (!$variable{error}) {
      $variable{ExternalRedirect} = '/administrator/managerial/folds.html';
    }
	} # end if
} # end sub _fold

1;
__END__
