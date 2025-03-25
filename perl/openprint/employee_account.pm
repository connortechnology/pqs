package openprint::employee_account;

use strict;
require openprint::User;
require	email;

require misc;
require sql;
require openprint::MarketingCategory;
require Authen::Passphrase::BlowfishCrypt;
require openprint::User_Notification;
require openprint::Email_Account;

require openprint;
use vars qw( $r $log $dbh %variable %param %session %config);
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*param = \%openprint::param;
*session = \%openprint::session;
*config = \%openprint::config;

sub profile {

	$param{company_id} = $openprint::User->company_id() if ! $param{company_id};

	my $User = $variable{User} = new openprint::User( exists $param{user_id} ? $param{user_id} : $session{user_id} );

	if ( $param{btnFunction} eq 'Save' ) {
		if ( $param{password} ) {
			if ( ! $param{VerifyPassword} ) {
				$variable{warning} .= 'Verify password left blank, password not changed.<br/>';
				delete $param{password};
			} else {
				$variable{error} .= 'Password fields do not match.<br/>' if $param{password} ne $param{VerifyPassword};
			} # end if
			$variable{warning} .= 'New Password is the same as your current password.<br/>' if $param{password} eq $User->Password();
		} # end if
		$variable{error} .= 'First Name cannot be blank.<br/>' if ! $param{firstname};
		$variable{error} .= 'Email Cannot be blank.<br/>' if ! $param{email};

		return if $variable{error};

		if ( ($session{user_type} eq 'A' ) or ( openprint::usergroup::is_user_in( ['UserManagement'], $session{user_id} ) ) ) {
			$param{csr_ids} = '' if ! exists $param{csr_ids};
		} elsif ( $param{csr_ids} ) {
			# Can only de-select
			$param{csr_ids} = [ sets::intersection( $User->csr_ids(), ( ref $param{csr_ids} eq 'ARRAY' ? @{$param{csr_ids}} : ( $param{csr_ids} ) ) ) ];
		} # end if
		if ( ! $param{password} ) {
			delete $param{password};
		} elsif ( $config{encrypt_passwords} ) {
			my $ppr = Authen::Passphrase::BlowfishCrypt->from_rfc2307($User->password());
			if ( ! $ppr->match($param{password}) ) {
				$param{password_changed_on} = 'NOW()';
				my $ppr = Authen::Passphrase::BlowfishCrypt->new( cost => 8, salt_random => 1, passphrase => $param{password} );
				$param{password} = $ppr->as_rfc2307();
			} else {
				delete $param{password};
			} # end if
		} elsif ( $param{password} ne $User->password() ) {
			$param{password_changed_on} = 'NOW()';
		} # end if

		delete $param{VerifyPassword} if ! $param{VerifyPassword};
		delete $param{btnFunction};
		my @changes = $User->changes( \%param );
		$variable{error} .= $User->save( \%param );
		return if $variable{error};

		push @changes, $User->save_notifications( \%param );

		if ( $config{mail_db_name} ) {
			my ( $error, @c ) = email::save($User->email(), \%param);
			$variable{error} .= $error;
			push @changes, @c;
		} # end if
		(new openprint::Log())->save({Object=>$User, action=>'Save User', note=>join('<br/>', @changes) }) if @changes;

		if ( ($session{user_type} eq 'A' ) or ( openprint::usergroup::is_user_in( ['UserManagement'], $session{user_id} ) ) ) {
			my @categories = sql::execute( $log, $dbh, 'SELECT id FROM Marketing_Categories' );

			sql::execute( $log, $dbh, 'DELETE FROM Users_in_Marketing_Categories WHERE user_id=?', $User->id() );
			if ( $param{marketing_categories} ) {
				my $sth = $dbh->prepare( q{INSERT INTO Users_in_Marketing_Categories (category_id,user_id) VALUES ( ?, ? )} );
				foreach my $cat ( ref $param{marketing_categories} eq 'ARRAY' ? @{$param{marketing_categories}} : $param{marketing_categories} ) {
					if ( sets::isin( $cat, \@categories ) ) {
						$sth->execute( $cat, $User->id() ) or $log->error( DBI->errstr );
					} # end if
				} # end foreach
			} # end if

			foreach my $Type ( openprint::PurchaseOrder_ContentType->find() ) {
				$User->po_limit( $Type->id(), $param{'po_limit-'.$Type->id()} );
			} # end foreach Type

			sql::execute( $log, $dbh, q{DELETE FROM Users_in_UserGroups WHERE user_id=?}, $User->id() );
			if ( $param{UserGroups} ) {
				foreach my $group_id ( ref $param{UserGroups} eq 'ARRAY' ? @{$param{UserGroups}} : $param{UserGroups} ) {
					sql::insert( $log, $dbh, 'Users_in_UserGroups', ['usergroup_id', $group_id, 'user_id', $User->id() ] );
				} # end foreach
			} # end if

			
		} # end if can_editas an admin

		$variable{information} = 'Record saved successfully.<br/>';
		$variable{ExternalRedirect} = '/employee/account/profile.html?user_id='.$User->id();
	} # end if
	$variable{User} = $User;
	if ( $config{mail_db_name} ) {
		email::load($User->email(), \%variable);
		my $mail_dbh = email::db_connect();
		$openprint::Email_Account::dbh = $mail_dbh;
		$variable{Email} = openprint::Email_Account->find_one(username=>$User->email());
	}
} # end sub profile

sub login {
} # end sub login

sub logout {
	openprint::login::logout( $log, $dbh, \%variable, $session{_session_id}, 'E' );
} # end sub logout

sub login_confirmation {
	if ( $openprint::param{btnFunction} eq 'Forgotten Password' ) {
		openprint::login::forgotten_password();
	} elsif ( $openprint::param{btnFunction} eq 'Login' ) {
		openprint::login::verify_login( $r, $log, $dbh, $session{_session_id}, \%variable, 'C' );
	} # end if
} # end sub login_confirmation

sub password_confirmation {
} # end sub password_confirmation

1;
__END__
