use strict;
package openprint::login;

require sql;
require ssi;
require misc;
require openprint::usergroup;
require openprint::Log;
require MIME::QuotedPrint;
require Encode;
require Digest::MD5;

use openprint ();
use vars qw( $r $dbh $log %variable %param %session %config);
*r = \$openprint::r;
*log = \%openprint::log;
*dbh = \%openprint::dbh;
*variable = \%openprint::variable;
*param = \%openprint::param;
*session = \%openprint::session;
*config = \%openprint::config;

# displays the login page, and populates the destination variable
sub save_destination {
	my ( $destination ) = @_;

	if ( ! $destination ) {
		$destination = $r->uri();
        my @values;
        foreach my $key ( keys %param ) {
            next if $key eq 'password';
            push @values, map { $key.'='.$_ } ( ref $param{$key} eq 'ARRAY' ? @{$param{$key}} : $param{$key} );
        } # end ofreach     
        if ( @values ) {
            $destination .= '?' . join('&', @values );
        } # end if
	} # end if

# if someone sets the Destination flag, keep it through the login process.
	if ( $destination =~ /main\/order/ ) {
		$session{Destination} = q{Click <a href="} . $destination . q{">here</a> to continue your order.};
	} elsif ( $destination =~ /survey\.html/ ) {
		$session{Destination} = q{Click <a href="} . $destination . q{">here</a> to continue the survey.};
	} else {
		$session{Destination} = q{Click <a href="} . $destination . q{">here</a> to continue to the page you requested.};
	} # end if
} # end sub save_destination

# login verification.	called when someone logs in
sub verify_login {
	my ( $r, $log, $dbh, $cookie, $variable, $site ) = @_;
		
	# convert the email address to lower case. All email addresses stored in DB will be lower case.
	my $email = openprint::User->transform('email', $param{email} );
	if (!$email) {
		$$variable{details} = "\"$email\" is not a valid account.	Please try again.";
		$$variable{error} = 'Authentication Failed.';
		return;
	} # end if

	$log->debug("** Verifying Login for Email Address: $email **");

	# doing it this way allows for multiple accounts with the same email address, identified by their password.
	# however, on user registration, we enforce the uniqueness of email addresses.	Also, the db should have a UNIQUE
	# attribute on the strEmail field.
	my @Users = openprint::User->find( email=>$email );

	if (!@Users) {
		# user not found.	Let's see if we got the password wrong, or the email wrong.
		if ( @Users = openprint::User->find(email=>$email, deleted=>1) ) {
			foreach my $U ( @Users ) {
				$$variable{information} = "\"$email\" Has been deleted.  Please contact us to have your account re-instated.";
				(new openprint::Log())->save({Object=>$U, action=>'Login Failed', note=>'Account Deleted', user_id=>$U->id(), company_id=>$U->company_id() } );
			} # end foreach U
		} else {
			$$variable{information} = "\"$email\" is not a valid account.	Please try again.";
			(new openprint::Log())->save({action=>'Login Failed', note=>'Invalid login: ' . $email } );
		} # end if
		$$variable{error} .= 'Authentication Failed.';
		return;
	} # end if

	my $User = undef;
	foreach my $U (@Users) {
    if ($param{auth_code}) {
      $log->debug("Have auth code $param{auth_code}");

      $config{AUTH_HASH_TTL} = 300 if !$config{AUTH_HASH_TTL};
      my $now = time;
      for (my $i = $config{AUTH_HASH_TTL}; $i>0; $i-=60, $now-=60) {
        my @time = localtime($now);
        my $authKey = $config{AUTH_HASH_SECRET}.$$U{email}.$$U{password}.$time[1].$time[2].$time[3].$time[4].$time[5];
        my $authHash = Digest::MD5::md5_base64($authKey);
        $log->debug("Trying $authKey = $authHash");
        if ($param{auth_code} eq $authHash) {
          $User = $U;
          last;
        } # end if $auth == $authHash
      } # end foreach hour
      last if $User;
    }

    if ($param{password}) {
      my $password = $param{password};

      if ($config{encrypt_passwords}) {
        if (!$U->password()) {
          $variable{error} .= $$U{email} . ' does not have a password assigned yet. Please click Forgot Password to send a magic link email.<br/>';
          next;
        }
        if ($U->password() =~ /^{CRYPT}/) {
          eval {
            require Authen::Passphrase::BlowfishCrypt;
            my $ppr = Authen::Passphrase::BlowfishCrypt->from_rfc2307($U->password());
            if ($ppr->match($password)) {
              $User = $U;
              $openprint::log->debug("User $$U{email}'s password matched: $$U{password} == $password");
              last;
            } else {
              $openprint::log->debug("User $$U{email}'s password did not match: $$U{password} != $password");
            } # end if
          };
          $log->error('Eval error of Authen::Passphrase::BlowfishCrypt Reason: '.$@) if $@;
        }

        # Failed, could be error, could be that the password is stored in plaintext
        if ($U->password() eq $password) {
          $User = $U;
          $openprint::log->debug("User $$U{email}'s password matched plaintext: $$U{password} == $password");
          eval {
            require Authen::Passphrase::BlowfishCrypt;
            my $ppr = Authen::Passphrase::BlowfishCrypt->new( cost => 8, salt_random => 1, passphrase => $password);

            $variable{error} .= $User->save({ password => $ppr->as_rfc2307() });
          };
          $log->error('Eval error of Authen::Passphrase::BlowfishCrypt Reason: '.$@) if $@;
          last;
        } else {
          $openprint::log->debug("User $$U{email}'s password did not match: $$U{password} != $password");
        }
      } else {
        if ( $password eq $U->password() ) {
          $openprint::log->debug("User $$U{email}'s password matched: $$U{password} == $password");
          $User = $U;
          last;
        } else {
          $openprint::log->debug("User $$U{email}'s password did not match: $$U{password} != $password");
        } # end if
      } # end if
    } # end if password
	} # end foreach User

	if (!$User) {
		$$variable{information} = 'The credentials you entered were not correct.	Please try again.<br/>';
		foreach my $U ( @Users ) {
			(new openprint::Log())->save({Object=>$U, action=>'Login Failed', note=>'Invalid Password', user_id=>$U->id(), company_id=>$U->company_id() } );
		} # end foreach U
		return;
	} # end if

	# Have a valid user now.
  if ( $User->company_id()) {
    if ( $User->Company()->activation() eq 'N' ) {
      $$variable{error} = 'Company not activated.';
      $$variable{information} = 'Your company account has not been looked over and activated by an administrator yet. You will be notified when your application has been approved.';
      (new openprint::Log())->save({Object=>$User, action=>'Login Failed', note=>'Company Account Not Activated', user_id=>$User->id(), company_id=>$User->company_id() } );
      return;
    } elsif ( $User->Company()->activation() ne 'Y' ) {
      $$variable{error} = 'Company Account activation status is unknown.('.$User->Company()->activation().')';
      $$variable{information} = 'Please report this error.';
      return;
    } # end if
	} # end if

	# Have a valid user now.
	if ( $User->web_active() eq 'N' ) {
		$$variable{error} = 'User not activated.';
		$$variable{information} = "Applications for existing corporate accounts must be approved by and administrator. You will be notified when you application had been approved.";
		(new openprint::Log())->save({Object=>$User, action=>'Login Failed', note=>'User Account Not Activated', user_id=>$User->id(), company_id=>$User->company_id() } );
		return;
	} elsif ( $User->web_active() ne 'Y' ) {
		$$variable{error} = 'User Account activation status is unknown.';
		$$variable{information} = 'Please report this error.';
		return;
	} # end if

	if ( $site eq 'E' and ! sets::isin( $User->type(), ['E','A'] ) ) {
		$$variable{error} = 'Not authorised.';
		$$variable{information} = 'You are not an employee.	You do not have access to the employee site.';
		(new openprint::Log())->save({Object=>$User, action=>'Login Failed', note=>'User not an employee', user_id=>$User->id(), company_id=>$User->company_id() } );
		return;
	} elsif ( $site eq 'A' and $User->type() ne 'A' ) {
		$$variable{error} = 'Not authorised.';
		$$variable{information} = 'You are not an administrator.	You do not have access to the administrator site.';
		(new openprint::Log())->save({Object=>$User, action=>'Login Failed', note=>'User not an administrator', user_id=>$User->id(), company_id=>$User->company_id() } );
		return;
	} # end if

	if ( $User->type() ne 'C' ) {
		if ( $config{owner_id} and ( $User->company_id() != $config{owner_id} ) and ! ( $User->Company()->name() =~ /Connor/ ) ) {
# Send an email notification
			my %info;
			@info{'UserFirstName','UserLastName','UserEmail'} = $User->get('firstname','lastname','email');
			$info{Site} = $site;
			$info{UserType} = $User->type();

			$info{ReplacementText} = ssi::include( '/email_content/login_notification.html', \%info );

			my $email_template = misc::load_file( $log, $config{SkinPath}. '/email_template.html' );
			$_ = MIME::QuotedPrint::encode_qp( Encode::encode('utf-8',ssi::variable_substitution( \$email_template, \%info ) ) );
			(new openprint::Email())->send(
					FROM	=> $config{LoginEmail},
					TO		=> $config{LoginEmail},
					SUBJECT => 'Login notification',
					ATTACHMENTS	=> ['', $_, 'text/html', 'quoted-printable'],
					);
		} # end if

	} # end if

  login($User);

	if ( $openprint::param{rdbRememberMe} eq 'Y' ) {
		my $Cookie = Apache2::Cookie->new($r,
			-name  => '_session_id',
			-value => $session{_session_id},
			-path		=>	'/',
			);
		$Cookie->expires('+3M');
		$Cookie->bake( $r );
	} # end if	

	if ( $User->change_password() eq 'Y' ) {
		if ( ! $session{Destination} ) {
			save_destination( $r->uri() );
		} # end if
		$$variable{ExternalRedirect} = '/account/change_password.html';
		return;
	} elsif ( $session{Destination} =~ /^Click <a href="(.*)">here<\/a>/ ) {
     
		$$variable{ExternalRedirect} = $1;
	} elsif ( $session{Destination} =~ /^Click <a href="(.*)">here<\/a> to continue the survey\./ ) {
     
		$$variable{ExternalRedirect} = $1;
  } elsif ( $User->homepage() ) {
    $$variable{ExternalRedirect} = $User->homepage()->value();
	} elsif ( (!$variable{error}) and ( $r->uri() =~ /\/account\/login.html/ ) ) {
		# I think the redirect is to handle reloads
		$$variable{ExternalRedirect} = $r->uri();
	} # end if
} # sub verify_login

sub login {
  my $User = shift;
	@session{'company_id','user_id','email','user_type'} = $User->get('company_id','id','email','type');
	openprint::usergroup::init_cache();
	delete $session{Pricelist_id};
	(new openprint::Log())->save({Object=>$User, action=>'Login', note=>'Successful Login' } );
}

sub logout {
	(new openprint::Log())->save({Object=>$openprint::User, action=>'Logout'});
	foreach my $k ( keys %session ) {
		next if sets::isin( $k, [ 'Currency_id', '_session_id','Country' ] );
		delete $session{$k};
	} # end foreach
	sql::update( undef, undef, 'orders', [ 'strsessionid=?', $session{_session_id} ], 'strsessionid', undef );
} # sub logout

sub email_password {
	my ( $r, $log, $dbh, $variable ) = @_;

	if ( $config{encrypt_passwords} ) {
		return misc::error( $log, $dbh, $variable, 'System Error.', 'We are unable to email your password to you.	Please contact support.' );
	} # end if
		

	my @Users = openprint::User->find('email'=> lc $param{txtEmail2} );

	if ( ! @Users ) {
		return misc::error( $log, $dbh, $variable, 'Account doesn\'t exist.', 'The account you entered does not exist.' );
	} # end if

	if ( my $email_template = ssi::slurp_content('/email_template.html') ) {
		
		my $content = ssi::slurp_content('/email_content/forgotten_password.html');
		foreach my $User ( @Users ) {
			my %info;
			$info{ReplacementText} = ssi::variable_substitution( \$content, \%info );
			$_ = MIME::QuotedPrint::encode_qp( ssi::variable_substitution( \$email_template, \%info ) );
			my $email = new openprint::Email();
      $email->html_body(ssi::variable_substitution( \$email_template, \%info ));
      my $results = $email->send(
					FROM 	=> $config{AdministratorEmail},
					TO	=> @Users,
					SUBJECT	=> 'Forgotten Password',
					);
			(new openprint::Log())->save({Object=>$User, action=>'Forgotten Password sent.', note=>$results});
		} # end foreach $User
	} else {
		return misc::error( $log, $dbh, $variable, 'System Error.', 'We were unable to email your password to you.	Please contact support.' );
	} # end if
} # sub email_password

sub login_password {
	my ( $r, $log, $dbh, $variable ) = @_;

	$_ = $config{customerlogin};
	if ($ENV{HTTP_REFERER} =~ /$_/) {
		$$variable{message} = "Your account has been activated.	While it is not required, it is recommended you change your password now.";
	} else {
		$$variable{message} = "Please enter the required information to change your password.";
	} # end if
} # login password

sub change_password {

	if ( $param{password} ne $param{verify_password} ) {
		$variable{error} = 'The new password, and the verification passwords you entered do not match.<br/>';
		$variable{Redirect} = '/account/change_password.html';
		return;
	} # end if

	if ( $param{password} eq '' ) {
		$variable{error} = 'The new password you entered was blank.This is too insecure, and will not be allowed.<br/>';
		$variable{Redirect} = '/account/change_password.html';
		return;
	} # end if

	my $User = $openprint::User;

	if ( my $reason = check_password( $param{password} ) ) {
		$variable{error} = "The new password you entered was not good enough: $reason.<br/>";
		$variable{Redirect} = '/account/change_password.html';
		return;
	} # end if

	if ( $param{password} eq $User->password() ) {
		$variable{error} = 'The new password you entered was the same as your current password. Please try again.<br/>';
		$variable{Redirect} = '/account/change_password.html';
		return;
	} # end if

  if ( $config{encrypt_passwords} ) {
    require Authen::Passphrase::BlowfishCrypt;
    my $ppr = Authen::Passphrase::BlowfishCrypt->from_rfc2307($User->password());
    if ( ! $ppr->match($param{txtOldPassword}) ) {
      $variable{error} = 'You entered the wrong old password.<br/>';
      $variable{Redirect} = '/account/change_password.html';
      return;
    } # end if
    $ppr = Authen::Passphrase::BlowfishCrypt->new(
      cost => 8, salt_random => 1,
      passphrase => $param{password} );
    $param{password} = $ppr->as_rfc2307();
  } elsif ( $User->password() ne $openprint::param{txtOldPassword} ) {
    $variable{error} = 'You entered the wrong old password.<br/>';
    $variable{Redirect} = '/account/change_password.html';
    return;
  } # end if

  $variable{error} .= $User->save({
      password => $param{password},
      change_password => 'N',
      password_changed_on => 'NOW()',
    });
  if ( $session{Destination} =~ /^Click <a href="(.*)\.html\??(.*)">here<\/a>/ ) {
    $variable{ExternalRedirect} = $1.'.html?'.$2;
    delete $session{Destination};
  } # end if Destination
} # sub change_password

# handles logout if timeout
sub verify_user {
	my ( $r, $log, $dbh, $cookie, $variable, $site ) = @_;

	return if ! $cookie;

	my $idletime = $config{idletime};

	if ( $session{lastupdated} and $session{user_id} and $idletime and ( time - $session{lastupdated} > $idletime ) ) {
		logout( $log, $dbh, $variable, $cookie, $site );
		$$variable{idletime} = $idletime;
		$$variable{Destination} = misc::get_destination( $r, $r->uri() );
		if ( $site eq 'C' ) {
			$$variable{Redirect} = '/error/idle_timeout.html';
		} elsif ( $site eq 'A' ) {
			$$variable{Redirect} = '/administrator/error/idle_timeout.html';
		} elsif ( $site eq 'E' ) {
			$$variable{Redirect} = '/employee/error/idle_timeout.html';
		} # end if
	} # end if
} # end sub verify_user

sub check_password {
	my ( $password ) = @_;
	if ( $openprint::config{password_checks_min_length} and ( length $password < $openprint::config{password_checks_min_length} ) ) {
		return "Too short.  Passwords must be at least $openprint::config{password_checks_min_length} characters long.";
	} # end if
	if ( $openprint::config{password_checks_max_length} and ( length $password < $openprint::config{password_checks_max_length} ) ) {
		return "Too long.  Passwords must be at most $openprint::config{password_checks_max_length} characters long.";
	} # end if
	if ( $openprint::config{password_checks_uppercase} eq 'yes' and ! ( $password =~ /[A-Z]/ ) ) {
		return "Password must contain at least 1 uppercase character.";
	} # end if
	if ( $openprint::config{password_checks_lowercase} eq 'yes' and ! ( $password =~ /[a-z]/ ) ) {
		return "Password must contain at least 1 lowercase character.";
	} # end if
	if ( $openprint::config{password_checks_numbers} eq 'yes' and ! ( $password =~ /[0-9]/ ) ) {
		return "Password must contain at least 1 number.";
	} # end if
	if ( $openprint::config{password_checks_punctuation} eq 'yes' and ! ( $password =~ /[!,@,#,$,%,^,&,*,?,_,~]/ ) ) {
		return 'Password must contain at least 1 of !,@,#,$,%,^,&,*,?,_,~.';
	} # end if
	if ( $openprint::config{password_checks_min_score} ) {
		my $strength = password_strength( $password );
		if ( $strength < $openprint::config{password_checks_min_score} ) {
			return "Password's strength score ( $strength ) must be at least $openprint::config{password_checks_min_score}.";
		} # end if
	} # end if
} # end sub check_password

sub password_strength {
	my ( $password ) = @_;

	my $score = 0;
	my $length = length $password;
	if ( $length < 5 ) {
		$score += 3;
	} elsif ( $length >= 5 and $length < 8 ) {
		$score += 6;
	} elsif ( $length >= 8 and $length < 16 ) {
		$score += 12;
	} elsif ( $length >= 16 ) {
		$score += 18;
	} # end if

	$score += 1 if $password =~ /[a-z]/;
	$score += 5 if $password =~ /[A-Z]/;
	$score += 5 if $password =~ /\d/;
	$score += 5 if $password =~ /(.*\d.*\d.*\d)/;
	$score += 5 if $password =~ /.[!,@,#,$,%,^,&,*,?,_,~]/;
	$score += 5 if $password =~ /(.*[!,@,#,$,%,^,&,*,?,_,~].*[!,@,#,$,%,^,&,*,?,_,~])/;
	$score += 2 if $password =~ /([a-z].*[A-Z])|([A-Z].*[a-z])/;
	$score += 2 if ( $password =~ /[a-zA-Z]/ and $password =~ /[0-9]/ );
	$score += 2 if $password =~ /([a-zA-Z0-9].*[!,@,#,$,%,^,&,*,?,_,~])|([!,@,#,$,%,^,&,*,?,_,~].*[a-zA-Z0-9])/;
	return $score;

} # end sub password_strength

sub forgotten_password {
	if ( $config{encrypt_passwords} ) {
		$variable{error} = 'We cannot retrieve passwords at this time. Please contact your CSR.';
		return;
	} # end if

	if ( ! $param{email} ) {
		$variable{error} = 'Please enter the email address of the account to retrieve.';
		return;
	} # end if

	my $User = openprint::User->find_one('email lc'=>openprint::User->transform('email', $param{email} ) );
	if ( ! $User ) {
		$variable{error} = 'The account you entered does not exist.';
		return;
	} # end if

	if ( my $email_template = ssi::slurp_content('/email_template.html') ) {
		my %info = (
				User =>$User,
				);

		$info{ReplacementText} = ssi::slurp_content('/email_content/forgotten_password.html');
		$info{ReplacementText} = ssi::variable_substitution( \$info{ReplacementText}, \%info );

    my $email = new openprint::Email();
    $email->html_body(ssi::variable_substitution(\$email_template, \%info));
		$_ = $email->send(
				FROM    => $config{AdministratorEmail},
				TO      => $User,
				SUBJECT => 'Forgotten Password',
				);
		$variable{information} = 'Your password has been e-mailed to you.';
	} else {
		$variable{error} = 'We were unable to email your password to you. Please contact support.';
	} # end if
} # end sub forgotten_password

sub auth_code {
  my $user = shift;
  my @local_time = localtime();
  my $authKey = $config{AUTH_HASH_SECRET}.$$user{email}.$$user{password}.$local_time[1].$local_time[2].$local_time[3].$local_time[4].$local_time[5];
  #ZM\Debug("Generated using hour:".$local_time[2] . ' mday:' . $local_time[3] . ' month:'.$local_time[4] . ' year: ' . $local_time[5] );
  return Digest::MD5::md5_base64($authKey);
}
1;
__END__
