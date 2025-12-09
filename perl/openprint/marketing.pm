# Copyright (C) 2007 Isaac Connor <isaac@connortechnology.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA

use strict;
package openprint::marketing;

require openprint::EmailCampaign;
require openprint::EmailCampaign_Sent;
require openprint::EmailCampaign_Destination;
require openprint::EmailCampaign_Subscription;
require openprint::MarketingCategory;
require openprint::Company;
require openprint::Company_in_Marketing_Category;
require openprint::Banner;
require openprint::Survey;
require openprint::account;
require openprint::Sales_Log;

use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

sub email_campaigns {
	my $Campaign = new openprint::EmailCampaign( $param{campaign_id} );
	if ( $param{btnFunction} eq 'Delete' ) {
		$variable{error} .= $Campaign->delete();
		(new openprint::Log())->save({Object=>$Campaign, action=>'Delete'});
	} elsif ( $param{btnFunction} eq 'Run' ) {
		$variable{information} = $Campaign->send();
		#(new openprint::Log())->save({Object=>$Campaign, action=>'Run', note=>$variable{information} });
	} elsif ( $param{btnFunction} eq 'Trial' ) {
		$variable{information} = $Campaign->trial( $openprint::User->email() );
	} # end if

	$variable{campaign_id} = $Campaign->id();
	ssi::setup_date_select( $r->uri(), 'called_on_start', -30 );
	ssi::setup_date_select( $r->uri(), 'called_on_end', '' );
	$session{'/marketing/email_campaigns.html?deleted'} = '0' if ! $session{'/marketing/email_campaigns.html?deleted'};
} # end sub email_campaigns

sub _email_campaigns {

	ssi::save_params( '/marketing/email_campaigns.html', (
				( map { 'called_on_start_' . $_ } ( 'year','month','day' ) ),
				( map { 'called_on_end_' . $_ } ( 'year','month','day' ) ),
				'user_id', 'deleted', 'active',
				) );
} # end sub _email_campaigns

sub categories {

	my $Category = new openprint::MarketingCategory( $param{category_id} );

	if ( $param{btnFunction} eq 'View' ) {
	} elsif ( $param{btnFunction} eq '>>' ) {
		$Category = $Category->next();
	} elsif ( $param{btnFunction} eq '<<' ) {
		$Category = $Category->previous();
	} elsif ( $param{btnFunction} eq 'Save' ) {
		$variable{error} .= $Category->save( \%openprint::param );
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/marketing/categories.html?category_id='.$Category->id();
		} # end if
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		$Category->delete();
		$Category = $Category->next();
	} elsif ( $param{btnFunction} eq 'Add' ) {
		$Category->add_company( $param{Company} );
		$Category->save();
	} elsif ( $param{btnFunction} eq 'Remove' ) {
		$Category->remove_company( $param{chkDelete} );
		$Category->save();
	} elsif ( $param{btnFunction} eq 'Import' ) {
		my $ac = sql::start_transaction($dbh);

    my $upload = $r->upload('import_file');
    my $io = $upload->io();
    $_ = <$io>;

    my $csv = Text::CSV_XS->new();

    while (<$io>) {
      my $status = $csv->parse($_);
      my ( $name ) = misc::trim($csv->fields());
			my @Companies = openprint::Company->find(name=>$name);
			if ( ! @Companies ) {
				$variable{error} .= "No company found for $name<br/>";
				next;
			} elsif ( @Companies > 1 ) {
				$variable{error} .= "Multiple companies found for $name<br/>";
			}
			foreach my $Company ( @Companies ) {
				my $Company_in_Category = new openprint::Company_in_Marketing_Category();
				$variable{error} .= $Company_in_Category->save({company_id=>$$Company{id},category_id=>$$Category{id}});
			} # end foreach Company

		} # end while
		sql::end_transaction($dbh, $ac);

	} # end if
	$variable{Category} = $Category;
} # end sub categories


sub email_campaign {
	my $Campaign = $variable{Campaign} = new openprint::EmailCampaign( $param{campaign_id}) ;
	return if !$param{btnFunction};

	if ( $param{btnFunction} eq 'Save' ) {
		$param{nextrun} = sprintf('%.4d-%.2d-%.2d %.2d:%.2d:%.2d',
				@param{'nextrun_year','nextrun_month','nextrun_day','nextrun_hour','nextrun_minute'}, 0 ) if $param{nextrun_year};
		my @changes = $Campaign->changes(\%param);
		if ( @changes ) {
			$variable{error} .= $Campaign->save(\%param);
			(new openprint::Log())->save({Object=>$Campaign, action=>'Save', note=>'Changes: ' .join(', ', @changes) });
		}
		$variable{ExternalRedirect} = '/marketing/email_campaign.html?campaign_id='.$Campaign->id() if ! $variable{error};
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		$variable{error} .= $Campaign->delete();
		(new openprint::Log())->save({Object=>$Campaign, action=>'Delete' });
		$variable{ExternalRedirect} = '/marketing/email_campaigns.html' if ! $variable{error};
	} elsif ( $param{btnFunction} eq 'Run' ) {
		$variable{Results} = $Campaign->send();
		(new openprint::Log())->save({Object=>$Campaign, action=>'Run', note=>$variable{Results} });
	} elsif ( $param{btnFunction} eq 'Copy' ) {
    $log->debug("Copying");
		$variable{Campaign} = $Campaign = $Campaign->copy();
		$variable{error} .= $Campaign->save({name=>'Copy of '.$$Campaign{name}});
	} elsif ( $param{btnFunction} eq 'Test' ) {
		$variable{information} = $Campaign->test();
		$variable{ExternalRedirect} = $Campaign->url_to();
	} elsif ( $param{btnFunction} eq 'Download Recipients' ) {
		my @header = ( 'Company','First Name','Last Name', 'Email','Phone','Last Sent On','Number of Times Sent','Order Value');
		my @data;
    my @Recipients = $Campaign->Recipients();
    my @company_ids = map { $$_{company_id} } @Recipients;
    my %Orders = misc::make_hash_from_array('company_id', openprint::Order->find(company_id=>\@company_ids));
		foreach my $User ( @Recipients ) {
			push @data, $User->Company()->name(), $User->firstname(), $User->lastname(), $User->email(), $User->phone();
			my ( $last_sent, $num_times ) = sql::execute( undef, undef, 'SELECT emailsenton, numemailsent FROM emailcampaign_sent WHERE campaign_id=? AND user_id=? ORDER BY emailsenton DESC LIMIT 1', $Campaign->id(), $User->id() );
			push @data, $last_sent, $num_times;
      push @data, misc::sum( $Orders{$$User{company_id}} ? map { $$_{total} } @{$Orders{$$User{company_id}} } : () );
		} # end foreach

		misc::export_csv( $r, $log, \%variable, $Campaign->name().' Recipients.csv', \@header, \@data );
	} elsif ( $param{btnFunction} eq 'View Recipients' ) {
		$variable{PageContent} = join('<br/>', map { new openprint::User( $_ )->name() } $Campaign->recipients() );
	} elsif ( $param{btnFunction} eq 'Import Recipients' ) {
    my $ac = sql::start_transaction($dbh);

    my $upload = $r->upload('import_file');
    my $io = $upload->io();
    $_ = <$io>;

    my $csv = Text::CSV_XS->new();
		my %destinations = misc::make_hash_from_array(user_id=>openprint::EmailCampaign_Destination->find(campaign_id=>$$Campaign{id}));
		my $error;
		my $results;

    while (<$io>) {
      my $status = $csv->parse($_);
      my ( $emails ) = misc::trim($csv->fields());
			foreach my $email ( split(',', $emails) ) {
				$email = openprint::User->transform(email=>$email);
				next if !$email;
		
				my @Users = openprint::User->find(email=>$email);
				if ( !@Users ) {
					$results .= "No user found for $email. Adding<br/>";
					my $User = new openprint::User();
					if ( ! $User->save({email=>$email}) ) {
						push @Users, $User;
					}
				}
				foreach my $User ( @Users ) {
					if ( $destinations{$$User{id}} ) {
						$results .= "$email already included in destinations.<br/>";
						next;
					}
					my $dest = $destinations{$$User{id}} = new openprint::EmailCampaign_Destination();
					$error .= $dest->save({user_id=>$$User{id}, campaign_id=>$$Campaign{id}});
				} # end foreach User
			} # end foreach email
    } # end while
    sql::end_transaction($dbh, $ac);
		$variable{error} = $error;
		$variable{information} = $results;
	} # end if
} # end sub email_campaign

sub surveys {
	require openprint::Survey;
    $variable{Survey} = new openprint::Survey( $param{survey_id} );
    if ( $param{btnFunction} eq 'Save' ) {
        $variable{error} = $variable{Survey}->save( \%param );
    } elsif ( $param{btnFunction} eq 'Copy' ) {
        $variable{Survey} = $variable{Survey}->copy();
        $variable{error} = $variable{Survey}->save( );
    } elsif ( $param{btnFunction} eq 'Delete' ) {
        $variable{error} = $variable{Survey}->delete( );
    } # end if
	
} # end sub surveys 

sub survey_responses {
    if ( $param{btnFunction} eq 'Delete' ) {
		sql::execute( undef, undef, 'DELETE FROM Survey_Responses WHERE survey_id=? and user_id=?', @param{'survey_id','user_id'} );
    } # end if
} # end sub survey_responses

sub _email_template_body {
	my $Template = $variable{Template} = new openprint::EmailTemplate( $param{template_id}) ;
}
sub email_template {
	require openprint::EmailTemplate;

	my $Template = new openprint::EmailTemplate( $param{template_id}) ;
	if ( $param{btnFunction} eq 'Run' ) {
		$variable{Results} = $Template->send();
	} elsif ( $param{btnFunction} eq 'Copy' ) {
		$Template = $Template->copy();
		$variable{error} .= $Template->save( { name => 'Copy of ' . $Template->name() } );
	} elsif ( $param{btnFunction} eq 'Save' ) {
		$Template->save( \%param );
	} # end if
	$variable{Template} = $Template;

	# These are for template preview
	$variable{User} = $openprint::User;
	$variable{Campaign} = new openprint::EmailCampaign();
	$variable{Email} = new openprint::Email();
} # end sub email_campaign

sub email_templates {
	require openprint::EmailTemplate;

	if ( $param{btnFunction} eq 'Copy' ) {
		my $Template = new openprint::EmailTemplate( $param{template_id}) ;
		$Template = $Template->copy();
		$variable{error} .= $Template->save( );
	} elsif ( $param{btnFunction} eq 'Save' ) {
		my $Template = new openprint::EmailTemplate( $param{template_id}) ;
		$variable{error} .= $Template->save( \%param );
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		my $Template = new openprint::EmailTemplate( $param{template_id}) ;
		$variable{error} .= $Template->delete( );
	} # end if
} # end sub email_templates

sub banners {
} # end sub banners

sub not_ok_to_takeover {
  my $email = shift;
  my @Users = openprint::User->find(email=>$email);
  if (@Users > 1) {
    return 'There are multiple entries in the system with this email address.  Please correct this.';
  }
  foreach (@Users) { return 'User already has a password assigned.' if $_->password(); };
  return '';
}

sub subscriptions {
  my $User;

  if ($param{email}) {
    my @Users = openprint::User->find(email=>openprint::User->transform(email=>$param{email}));
    if (@Users > 1) {
      $variable{error} .= 'Multiple user records found.  Please contact support.';
      return;
    } elsif (!@Users) {
      # NEW
      $User = new openprint::User();
      $User->email($param{email});
      $User->type('C');
      $User->web_active($config{NewFirstUserAccountActivation});
    } else {
      $User = $Users[0];
    }
  } elsif ($param{user_id}) {
    $param{user_id} == openprint::User->transform(id=>$param{user_id});
    if (!$param{user_id}) {
      $variable{error} .= 'Invalid user id specified.<br/>';
      $log->error('Invalid user id specified:'.$param{user_id});
      $variable{User} = $openprint::User;
      return;
    }
    $User = openprint::User->find_one(id=>$param{user_id});
  } else {
    $User = $openprint::User;
  }

  if (!($User and $User->can_edit())) {
    if ( ! $session{user_id} ) {
      $log->error("Can't edit, need to login");
      $variable{error} .= 'User has a password assigned. Please log in.';
      $variable{ExternalRedirect} = '/account/login.html?email='.$param{email};
    } else {
      $variable{error} .= 'No permission to edit settings for this user.';
    }
    return;
  }
  $variable{User} = $User;

  if ($param{action}) {
    if ($param{action} eq 'Subscribe') {
      if (!$User->id()) {
        if ($User->email()) {
          my $Company = new openprint::Company();
          $Company->save({name=>$User->email(), activated=>$config{NewCustomerAccountActivation}});
          $variable{error} .= $User->save({company_id=>$Company->id()});
          if (!$variable{error}) {
            openprint::login::login($User);
            $variable{information} .= 'Account created and logged in.<br/>';
          }
        } else {
          $variable{error} .= 'You must specify the email address.<br/>';
        }

      } else {
        $variable{error} .= 'User already exists, please edit subscriptions below.<br/>';
      }
    } elsif ($param{action} eq 'Save') {
      if (!$openprint::session{user_id}) {
        if ( $config{reCAPTCHA_site_key} ) {
          if ( ! $param{'g-recaptcha-response'} ) {
            $variable{error} .= 'You must check the I\'m not a robot box';
          } else {
            eval {
              # Using Google recaptcha
              require Captcha::reCAPTCHA;
              my $c = Captcha::reCAPTCHA->new;
              my $result = $c->check_answer_v2($config{reCAPTCHA_secret_key}, $param{'g-recaptcha-response'}, $ENV{HTTP_X_FORWARDED_FOR} ? $ENV{HTTP_X_FORWARDED_FOR} : $ENV{REMOTE_ADDR});
              if ( ! $result->{is_valid} ) {
                $variable{error} .= 'Failed reCAPTCHA.';
              }
            };
            $variable{error} .= "Failed reCAPTCHA: $@" if $@;
          }
        } else {
          eval {
            require Authen::Captcha;
            my $Captcha = new Authen::Captcha(
              data_folder => $config{SkinPath}.'/tmp',
              output_folder => $config{SkinPath}.'/images/captcha'
            );
            # Remove spaces, because some people want to put spaces between the characters, etc.
            $param{Captcha} =~ s/\s//g;
            if ( 1 != $Captcha->check_code( @param{'Captcha','MD5SUM'} ) ) {
              $variable{error} .= 'Captcha validation code incorrect.  Please try again.';
            } # end if
          };
        }

        if ($param{password}) {
          if ($param{password} ne $param{verify_password}) {
            $variable{error} .= 'The new password, and the verification passwords you entered do not match.<br/>';
          } # end if

          if ( my $reason = openprint::login::check_password($param{password}) ) {
            $variable{error} .= "The new password you entered was not good enough: $reason.<br/>";
          } # end if
        } # end if password

        if ( $variable{error} ) {
          $log->error($variable{error});
          return;
        }
      } # end if not logged in
      if (!$User->id()) {
        my $Company = new openprint::Company();
        $Company->save({name=>$User->email(), activated=>$config{NewCustomerAccountActivation}});
        $variable{error} .= $User->save({email=>$param{email}, company_id=>$Company->id(), password=>$param{password}});
        if (!$variable{error}) {
          openprint::login::login($User);
          $variable{information} .= 'Account created and logged in.<br/>';
        }
      }
      if (!$User->password() and $param{password}) {
        $User->save({password=>$param{password}});
        openprint::login::login($User);
        $variable{information} .= 'Password assigned and logged in.<br/>';
      }
      if ( ( $param{all} eq 'N' ) and ( $User->mailinglist() ne 'N' ) ) {
        $variable{error} .= $User->save({mailinglist=>$param{all}});
        $variable{information} .= 'Unsubscribed from all email communications.<br/>' if ! $variable{error};
      } elsif ( ( $param{all} eq 'Y' ) and ( $User->mailinglist() ne 'Y' ) ) {
        $variable{error} .= $User->save({mailinglist=>'Y'});
        $variable{information} .= 'Subscribed to all email communications.<br/>' if ! $variable{error};
      } # end if
      my %Subscriptions = map { $$_{campaign_id} => $_ } openprint::EmailCampaign_Subscription->find(user_id=>$User->id());
      foreach my $Campaign (openprint::EmailCampaign->find(user_id=>undef, runnable=>1)) {
        if ($param{'campaign_'.$$Campaign{id}} == '1') {
          if (!$Subscriptions{$$Campaign{id}}) {
            $Subscriptions{$$Campaign{id}} = new openprint::EmailCampaign_Subscription();
            $Subscriptions{$$Campaign{id}}->save({user_id=>$User->id(), campaign_id=>$$Campaign{id}});
            $variable{information} .= 'Subscribed to ' . $Campaign->name().'<br/>';
            (new openprint::Log())->save({Object=>$User, action=>'Subscribe', note=>'Subscribed to ' . $Campaign->name()});
          }
        } else {
          if ($Subscriptions{$$Campaign{id}}) {
            $Subscriptions{$$Campaign{id}}->delete();
            $variable{information} .= 'Unsubscribed from ' . $Campaign->name().'<br/>';
            (new openprint::Log())->save({Object=>$User, action=>'Unsubscribe', note=>'Unsubscribed to ' . $Campaign->name()});
          }
        }
      }
      $variable{ExternalRedirect} = '/marketing/subscriptions.html';
    } # end if save
	} # end if action
  $variable{User} = $User;
  $log->debug("information: $variable{information}");
} # end sub subscriptions

sub sales_log {
	ssi::setup_date_select( '/marketing/sales_log.html', 'called_on_start', -30 );
	ssi::setup_date_select( '/marketing/sales_log.html', 'called_on_end', '' );
	$session{'/marketing/sales_log.html?company_id'} = $session{company_id} if ! $session{'/marketing/sales_log.html?company_id'};
} # end sub sales_log

sub _sales_log {
	    ssi::save_params( '/marketing/sales_log.html', (
                ( map { 'called_on_start_' . $_ } ( 'year','month','day' ) ),
                ( map { 'called_on_end_' . $_ } ( 'year','month','day' ) ),
				'company_id', 'user_id', 'employee_id',
		) );

} # end sub _sales_log

sub _sales_log_line {
	 if ( $param{action} eq 'add' ) {

		if ( Date::Calc::check_date( @param{ map { 'called_on_'.$_ } ( 'year','month','day' ) } ) ) {
			my $called_on_datetime = DateTime->new( time_zone => $openprint::TZ,
					( map { $_ => int($param{'called_on_'.$_ }) } ( 'year', 'month', 'day', 'hour','minute' ) ),
					);

			my $parser = 'DateTime::Format::Pg';

			$param{called_on} = $parser->format_datetime( $called_on_datetime );
		} # end if

		my $Log = $variable{Log} = new openprint::Sales_Log();
		$variable{error} .= $Log->save({
			salesrep_id	=>	$session{user_id},
			company_id	=>	$param{company_id},
			user_id		=>	$param{user_id},	
			notes		=>	$param{notes},
			( $param{called_on} ? ( called_on	=>	$param{called_on} ) : () ),	
			});
	} # end params{action}
} # end sub _sales_log_line

sub get_clients {
		my ( $y, $m, $d ) = Date::Calc::Today();

		my $assigned_on_datetime = DateTime->new( time_zone => $openprint::TZ, year=>$y, month=>$m, day=>$d, hour=>0, minute=>0 );

		my $parser = 'DateTime::Format::Pg';
		my @Todays_Assignments = openprint::Log->find( user_id=>$session{user_id}, action => 'Get clients', 'date_time >' => $parser->format_datetime(  $assigned_on_datetime ) );
		my $todays_count = 0;
		foreach my $L ( @Todays_Assignments ) {
			my ( $count ) = $L->note() =~ /Get (\d+) clients/;
			$todays_count += $count;
		} # end foreach L	
		if ( $todays_count >= $config{ClientLotteryChunkSize} ) {
			$variable{todays_count} = $todays_count;
			$variable{error} .= 'You have already grabbed ' . $todays_count . ' new clients today.  Try again tomorrow.<br/>';
			return;
		} # end if

	if ( $param{action} eq 'get' ) {

		( $y, $m, $d ) = Date::Calc::Add_Delta_Days( ($y,$m,$d), -7 );
		my @Weeks_Assignments = openprint::Log->find( user_id=>$session{user_id}, action => 'Get clients', 'date_time >' => $parser->format_datetime(  $assigned_on_datetime ) );
		my $weekly_count = 0;
		foreach my $L ( @Weeks_Assignments ) {
			my ( $count ) = $L->note() =~ /Get (\d+) clients/;
			$weekly_count += $count;
		} # end foreach L	
		if ( $weekly_count >= $config{ClientLotteryMax} ) {
			$variable{error} .= 'You have already grabbed ' . $weekly_count . ' new clients this week.  Try again tomorrow.<br/>';
			return;
		} # end if
		my @Available_Companies = openprint::Company->find( salesrep_id=>undef, order=>'lower(name)' );	
		my @To_Be_Added;
		my $count = $config{ClientLotteryChunkSize};
		while ( $count > @To_Be_Added ) {
			my @C = splice( @Available_Companies, int(rand(@Available_Companies)), 1 );
			next if $C[0]->salesrep_id();
			push @To_Be_Added, @C;
		} # emd while

		foreach my $C ( @To_Be_Added ) {
			$variable{error} .= $C->save({ salesrep_id => $session{user_id} });
			$variable{information} .= $C->name() . ' is now your client.<br/>';
		} # end foreach C
		(new openprint::Log())->save({
			action	=> 'Get clients',
			note	=> 'Get ' . $config{ClientLotteryChunkSize} . ' clients',
		});
		$variable{ExternalRedirect} .= '/marketing/get_clients.html';
	} # end if
} # end sub get_clients

sub _recipients {
	$variable{Campaign} = new openprint::EmailCampaign($param{campaign_id});
}

1;
__END__
