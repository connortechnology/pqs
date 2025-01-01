use strict;
package openprint::User;
our @ISA = qw( openprint::Object );

require openprint::Object;
#require openprint::User_in_UserGroup;
require openprint::Company;

use openprint ();
use vars qw( $log $dbh %config $debug %fields %find_fields %transforms %defaults $table $serial $AUTOLOAD $default_sort );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;
$table = 'tbl_Customer_users';
$serial = 'users_id_seq';

$debug = 0;

$default_sort	=	'lower(firstname),lower(lastname),id';

%fields = (
	id							=>	'lngUserId',
	company_id			=>	'lngCustomerId',
	salutation			=>	'strsalutation',
	title						=>	'strtitle',
	firstname				=>	'strfirstname',
	lastname				=>	'strlastname',
	email						=>	'stremail',
	email_valid			=>	'email_valid',
	phone						=>	'phone',
	mobile					=>	'mobile',
	sms							=>	'sms',
	fax							=>	'fax',
	mailinglist			=>	'ysnmailinglist',
	greeting				=>	'greeting',
	created_on			=>	'created_on',
	updated_on			=>	'updated_on',
	type						=>	'chrtype',
	change_password	=>	'ysnchangepassword',
	password_changed_on	=>	'password_changed_on',
	commission			=>	'dblcommission',
	wage						=>	'wage',
	administrator		=>	'ysnadministrator',
	password				=>	'strpassword',
	ftp_active			=>	'ftp_active',
	ftp_root				=>	'ftp_root',
	web_active			=>	'web_active',
	howdidyouhearaboutus	=>	'howdidyouhearaboutus',
	howdidyouhearaboutusother	=>	'howdidyouhearaboutusother',
	quote_level				=>	'quote_level',
	email_quotes_to_myself        =>      'email_quotes_to_myself',
	purchasing_limit	=>	'purchasing_limit',
	purchasing_total_limit	=>	'purchasing_total_limit',
	notes							=>	'notes',
	asset_id					=>	'asset_id',
	deleted						=>	'deleted',
	last_logged_in		=>	undef,
); # end %fields
%find_fields = (
	name	=>	q`firstname || ' ' || lastname`,
	#usergroup_id	=>	'(SELECT usergroup_id FROM users_in_usergroups WHERE user_id=users.id)',
	usergroup_id	=>	'id IN (SELECT user_id FROM users_in_usergroups WHERE usergroup_id=?)',
	usergroup		=>	'(SELECT name from usergroups WHERE id IN (SELECT usergroup_id FROM users_in_usergroups WHERE user_id=users.id))',
	last_online	=>	'(SELECT MAX(date_time) FROM logs WHERE user_id=users.id)',
	profile_field	=>	'(SELECT value FROM User_Profiles WHERE user_id=users.id AND field_id=?)',
	company_deleted	=>	'(SELECT deleted FROM Companies WHERE Companies.id=company_id)',
);

%transforms = (
	id				=>	[ 's/\D//g', '<2147483647' ],
	company_id		=>	[ 's/\D//g' ],
	commission		=>	[ 's/[^\d\.\-]//g' ],
	wage				=>	[ 's/[^\d\.]//g' ],
	email				=>	[ 'tr/[A-Z]/[a-z]/', 's/^\s+//', 's/\s+$//' ],
	password			=>	[ 's/^\s+//', 's/\s+$//' ],
	purchasing_limit	=>	[ 's/[^\d\.\-]//g' ],
	purchasing_total_limit	=>	[ 's/[^\d\.\-]//g' ],
	created_on		=>	[ 's/.*//g' ],
	updated_on		=>	[ 's/.*//g' ],
);

%defaults = (
	web_active				=>	q`'N'`,
	ftp_active				=>	0,
	ftp_root				=>	q`''`,
	created_on				=>	q`'NOW()'`,
	updated_on				=>	q`'NOW()'`,
	type					=>	q`'C'`,
	change_password			=>	q`'N'`,
	administrator			=>	q`'N'`,
	commission				=>	undef,
	quote_level				=>	undef,
	purchasing_limit		=>	undef,
	purchasing_total_limit	=>	undef,
	wage					=>	undef,
	deleted					=>	0,
	email_quotes_to_myself	=>	0,
	asset_id				=>	undef,
	company_id				=>	undef,
	password_changed_on		=>	undef,
	password				=>	'',
	email_valid				=>	undef,
	mailinglist		=>	undef,
);

# if we have previously loaded info for this customer, and it hasn't changed, that field will not be saved.
# If we have not previously loaded the info, we will just save it whether it has actually changed or not.
# We do this for efficiency's sake.	
sub save {
	my ( $self, $params ) = @_;
	require MIME::QuotedPrint;

	if ( exists $$params{password} and $$params{password} eq '' ) {
		delete $$params{password};
	} # end if

	my @changes = $self->changes( $params );

	if ( 0 and $params and $$params{type} and $$self{type} and ( $$params{type} ne $$self{type} ) and ( $$params{type} ne 'C' ) ) {
# Notify someone
		my %info;
		$info{User} = $self;
		@info{'UserFirstName','UserLastName','UserType'} = @$params{'firstname','lastname','type'};

		$info{ReplacementText} = ssi::include( '/email_content/usertype_system_notification.html', \%info );
		my $email_template = ssi::include( '/email_template.html', \%info );

		new openprint::Email()->send(
				FROM    => $openprint::config{LoginEmail},
				TO      => $openprint::config{LoginEmail},
				SUBJECT => join(' ', @$params{'firstname','lastname'})."'s User Type has changed!",
				ATTACHMENTS => [ '', MIME::QuotedPrint::encode_qp($email_template), 'text/html', 'quoted-printable' ],
				);
	} # end if

	if ( $params and (defined $$params{web_active} and defined $$self{web_active} ) and ( $$self{web_active} ne $$params{web_active} ) and ( $$params{web_active} eq 'Y' ) ) {
		my %info;
		$info{User} = $self;
		$_ = $$params{web_active} eq 'Y' ? 'user_account_activated.html' : 'user_account_deactivated.html';
		$info{ReplacementText} = ssi::include( '/email_content/'.$_, \%info );
		my $email_template = ssi::include( '/email_template.html', \%info  );

		new openprint::Email()->send(
				FROM    => $openprint::config{AdministratorEmail},
				TO      => sprintf( '"%s %s" <%s>', @$params{'firstame','lastname','email'} ),
				SUBJECT => 'User account status has changed!',
				ATTACHMENTS => [ '', MIME::QuotedPrint::encode_qp($email_template), 'text/html', 'quoted-printable' ],
				);
	} # end if

	my $error = $self->SUPER::save( $params );
	return $error if $error;
	(new openprint::Log())->save({action=>'Save User', Object=>$self, note=>join('<br/>', @changes ) } );

	if ( exists $$params{assistant_ids} ) {
		$self->assistant_ids( $$params{assistant_ids} );
	} # end if
	if ( exists $$params{csr_ids} ) {
		$self->csr_ids( $$params{csr_ids} );
	} # end if
	return;
} # end sub save

sub destroy {
	my $self = shift;

	my $ac = sql::start_transaction( $dbh );
	sql::execute( undef, undef, 'DELETE FROM Users_in_Marketing_Categories WHERE User_Id=?', $$self{id} );

  sql::update(undef, undef, 'quotes', ['user_id=?', $$self{id}], user_id=>undef);
  sql::update(undef, undef, 'orders', ['user_id=?', $$self{id}], user_id=>undef);
	sql::update( undef, undef, 'order_log', ['user_id=?',$$self{id}], user_id=> undef );
	sql::execute( undef, undef, 'DELETE FROM order_notifications WHERE user_id=?', $$self{id});
  sql::update(undef, undef, 'projects', ['user_id=?', $$self{id}], user_id=>undef);
	sql::execute( $log, $dbh, 'DELETE FROM users_in_usergroups WHERE user_id=?', $$self{id} );
	sql::execute( $log, $dbh, 'DELETE FROM Project_Log WHERE user_id=?', $$self{id} );
	sql::update( undef, undef, 'barcode_log', ['operator_id=?', $$self{id} ], 'operator_id', undef );
	sql::update( undef, undef, 'barcode_log', ['user_id=?',$$self{id}], 'user_id', undef );
	sql::update( undef, undef, 'performance_reports', ['operator_id=?', $$self{id} ], 'operator_id', undef );
	sql::update( undef, undef, 'skids', ['created_by_id=?',$$self{id}], 'created_by_id', undef );
	sql::update( undef, undef, 'purchaseorders', ['contact_id=?',$$self{id}], contact_id=> undef );
  sql::update(undef, undef, 'purchaseorder_logs', ['user_id=?', $$self{id}], user_id=>undef);

	sql::execute( $log, $dbh, 'DELETE FROM creditapplications WHERE user_id=?', $$self{id} );
	sql::execute( $log, $dbh, 'DELETE FROM helpdesk WHERE user_id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM Assistants WHERE csr_id=? OR assistant_id=?', @$self{'id','id'} );
	sql::execute( undef, undef, 'DELETE FROM EmailCampaign_sent WHERE user_id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM emailcampaign_destination WHERE user_id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM survey_responses WHERE user_id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM uploads WHERE user_id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM user_profiles WHERE user_id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM Message_to WHERE user_id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM Messages WHERE from_id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM User_Relationships WHERE user_id1=? OR user_id2=?', @$self{'id','id'} );
	sql::execute( undef, undef, 'DELETE FROM object_views WHERE user_id=?', $$self{'id'} );
	sql::execute( undef, undef, 'DELETE FROM views WHERE user_id=?', $$self{'id'} );
	sql::execute( undef, undef, 'DELETE FROM user_purchaseorder_limits WHERE user_id=?', $$self{'id'} );
	sql::execute( undef, undef, 'DELETE FROM purchaseorder_notifications WHERE user_id=?', $$self{'id'} );
	sql::execute( undef, undef, 'DELETE FROM equipment_operators WHERE user_id=?', $$self{'id'} );
	sql::execute( undef, undef, 'DELETE FROM productionfeedback WHERE user_id=?', $$self{'id'} );
	sql::execute( undef, undef, 'DELETE FROM user_notifications WHERE user_id=?', $$self{'id'} );
	sql::execute( undef, undef, 'DELETE FROM comments WHERE user_id=?', $$self{'id'} );
	sql::execute( undef, undef, 'DELETE FROM companies_accountingcontacts WHERE user_id=?', $$self{'id'} );
	sql::execute( undef, undef, 'DELETE FROM host_notifications WHERE user_id=?', $$self{'id'} );
	sql::execute( undef, undef, 'DELETE FROM project_service_operators WHERE user_id=?', $$self{'id'} );
	sql::execute( undef, undef, 'DELETE FROM quote_log WHERE user_id=?', $$self{'id'} );
  sql::update(undef,undef, 'locations', ['created_by=?', $$self{id}], created_by=>undef);
  sql::update(undef,undef, 'purchaseorder_logs', ['user_id=?', $$self{id}], user_id=>undef);
  sql::update(undef,undef, 'purchaseorders', ['contact_id=?', $$self{id}], contact_id=>undef);
  sql::update(undef,undef, 'purchaseorders', ['authorized_by=?', $$self{id}], authorized_by=>undef);
  sql::update(undef,undef, 'purchaseorders', ['created_by=?', $$self{id}], created_by=>undef);
  sql::update(undef,undef, 'assets', ['created_by=?', $$self{id}], created_by=>undef);
  sql::update(undef,undef, 'emailcampaigns', ['user_id=?', $$self{id}], user_id=>undef);
  sql::update(undef,undef, 'paper_allocations', ['operator_id=?', $$self{id}], operator_id=>undef);
  sql::update(undef,undef, 'paper_inventory', ['user_id=?', $$self{id}], user_id=>undef);
  sql::update(undef,undef, 'tbl_project_contents', ['operator_id=?', $$self{id}], operator_id=>undef);
  sql::update(undef,undef, 'car_areas', ['assignee_id=?', $$self{id}], assignee_id=>undef);
  sql::update(undef,undef, 'car', ['issued_by_id=?', $$self{id}], issued_by_id=>undef);
  sql::update(undef,undef, 'car', ['issued_to_id=?', $$self{id}], issued_to_id=>undef);
  sql::update(undef,undef, 'car', ['approved_by_id=?', $$self{id}], approved_by_id=>undef);
  sql::update(undef,undef, 'car', ['part1_user_id=?', $$self{id}], part1_user_id=>undef);
  sql::update(undef,undef, 'car', ['part2_user_id=?', $$self{id}], part2_user_id=>undef);
  sql::update(undef,undef, 'car', ['part3_user_id=?', $$self{id}], part3_user_id=>undef);
  sql::update(undef,undef, 'car', ['part4_user_id=?', $$self{id}], part4_user_id=>undef);
  sql::update(undef,undef, 'par', ['issued_by_id=?', $$self{id}], issued_by_id=>undef);
  sql::update(undef,undef, 'par', ['issued_to_id=?', $$self{id}], issued_to_id=>undef);
  sql::update(undef,undef, 'par', ['part1_user_id=?', $$self{id}], part1_user_id=>undef);
  sql::update(undef,undef, 'par', ['part2_user_id=?', $$self{id}], part2_user_id=>undef);
  sql::update(undef,undef, 'par', ['part3_user_id=?', $$self{id}], part3_user_id=>undef);
  sql::update(undef,undef, 'par', ['part4_user_id=?', $$self{id}], part4_user_id=>undef);
  sql::update(undef,undef, 'mars', ['issued_by_id=?', $$self{id}], issued_by_id=>undef);
  sql::update(undef,undef, 'mars', ['issued_to_id=?', $$self{id}], issued_to_id=>undef);
  sql::update(undef,undef, 'sred_contents', ['created_by=?', $$self{id}], created_by=>undef);
  sql::update(undef,undef, 'sred_contents', ['user_id=?', $$self{id}], user_id=>undef);
  sql::update(undef,undef, 'claims', ['contact_id=?', $$self{id}], contact_id=>undef);
  sql::update(undef,undef, 'claims', ['created_by=?', $$self{id}], created_by=>undef);
  sql::update(undef,undef, 'companies', ['salesrep_id=?', $$self{id}], salesrep_id=>undef);
  sql::update(undef,undef, 'bugs', ['user_id=?', $$self{id}], user_id=>undef);
  sql::update(undef,undef, 'logs', ['user_id=?', $$self{id}], user_id=>undef);
  sql::update(undef,undef, 'pressactivities', ['operator_id=?', $$self{id}], operator_id=>undef);
  sql::update(undef,undef, 'skid_verifications', ['user_id=?', $$self{id}], user_id=>undef);

	sql::execute( $log, $dbh, 'DELETE FROM Users WHERE id=?', $$self{id} );

	sql::end_transaction( $dbh, $ac );
  if ( $dbh->errstr()) {
    return $dbh->errstr();
  }

	(new openprint::Log())->save({action=>'Destroy User',note=>'User ID: ' . $$self{id}});
} # end sub destroy

sub next {
	my $self = shift;
	my %params = @_;

	my $sql = 'SELECT id, firstname FROM users WHERE firstname >= ? AND deleted != true';
	my @values = ( $$self{firstname} );
	if ( $$self{id} ) {
		$sql .= ' AND id!=?';
		push @values, $$self{id};
	}
	if ( $params{company_id} ) {
		$sql .= ' AND company_id=?';
		push @values, $params{company_id};
	} # end if
	if ( $params{type} ) {
		$sql .= ' AND type=?';
		push @values, $params{type};
	} # end if

	$sql .= ' ORDER BY firstname ASC LIMIT 1';
	( $_ ) = sql::execute( $log, $dbh, $sql, @values );
	return $_;
}
sub Next {
	my $self = shift;
	return new openprint::User( $self->next( @_ ) );
} # end sub Nex

sub prev {
	my $self = shift;
	my %params = @_;

	my $sql = 'SELECT id, firstname FROM Users WHERE firstname <= ? AND deleted != true';
	my @values = ( $$self{firstname} );
	if ( $$self{id} ) {
		$sql .= ' AND id!=?';
		push @values, $$self{id};
	}
	if ( $params{company_id} ) {
		$sql .= ' AND company_id=?';
		push @values, $params{company_id};
	} # end if
	if ( $params{type} ) {
		$sql .= ' AND type=?';
		push @values, $params{type};
	} # end if

	$sql .= ' ORDER BY firstname DESC LIMIT 1';
	( $_ ) = sql::execute( $log, $dbh, $sql, @values );
	return $_;
}
sub Prev {
	return new openprint::User( $_[0]->prev(@_) );
} # end sub Nex

sub Company {
	if ( ! $_[0]{Company} ) {
		$_[0]{Company} = new openprint::Company( $_[0]{company_id} );
	} # end if
	return $_[0]{Company};
} # end sub Company

sub alias {
	my $Company = $_[0]->Company();
	#if ( $_[0]{company_id} == $openprint::session{company_id} ) {
		#return $_[0]{firstname};
	#} elsif ( $_[0]->Company()->name() ne ($_[0]{firstname} . ' ' . $_[0]{lastname}) ) {
	if ( $_[0]{company_id} and ( $_[0]{company_id} != $openprint::session{company_id} ) and ( $Company->name() ne ($_[0]{firstname} . ( $_[0]{lastname} ? ( ' ' . $_[0]{lastname} ) : () ) ) ) ) {
		return $Company->name() . ($_[0]{firstname} ? ' (' . $_[0]{firstname} . ')' : '' );
	} elsif ( $_[0]->firstname() or $_[0]->lastname() ) {
		return $_[0]->name();
	} else {
		return $_[0]->email();
	} # end if
} # end sub name

sub name {
	if ( $_[0]{firstname} and $_[0]{lastname} ) {
		return join(' ', @{$_[0]}{'firstname','lastname'} );
	} elsif ( $_[0]{firstname} ) {
		return $_[0]{firstname};
	} elsif ( $_[0]{lastname} ) {
		return $_[0]{lastname};
	} # end if
	return '';
}

sub assistant_ids {
	my $self = shift;
	if ( @_ ) {
		my $ac = sql::start_transaction( $dbh );
		sql::execute( undef, undef, 'DELETE FROM Assistants WHERE csr_id=?', $$self{id} );
		foreach ( ( @_ == 1 and ref $_[0] eq 'ARRAY' ) ? @{$_[0]} : @_ ) {
			sql::insert( undef, undef, 'Assistants', ['csr_id', $$self{id}, 'assistant_id', $_] ) if $_;
		} # end foreach
		sql::end_transaction( $dbh, $ac );
		@{$$self{assistant_ids}} = ( @_ == 1 and ref $_[0] eq 'ARRAY' ) ? @{$_[0]} : @_;
	} # end if
	if ( ! $$self{assistant_ids} ) {
		if ( $$self{id} ) {
			@{$$self{assistant_ids}} = sql::execute( undef, undef, 'SELECT assistant_id FROM Assistants WHERE csr_id=?', $$self{id} );
		} else {
			$$self{assistant_ids} = [];
		}
	} # end if
	return @{$$self{assistant_ids}};
} # end sub

sub csr_ids {
	my $self = shift;
	if ( @_ ) {
		my $ac = sql::start_transaction( $dbh );
		sql::execute( undef, undef, 'DELETE FROM Assistants WHERE assistant_id=?', $$self{id} );
		foreach ( ( @_ == 1 and ref $_[0] eq 'ARRAY' ) ? @{$_[0]} : @_ ) {
			sql::insert( undef, undef, 'Assistants', ['assistant_id', $$self{id}, 'csr_id', $_] ) if $_;
		} # end foreach
		sql::end_transaction( $dbh, $ac );
		@{$$self{csr_ids}} = ( @_ == 1 and ref $_[0] eq 'ARRAY' ) ? @{$_[0]} : @_;
	} # end if
	if ( ! $$self{csr_ids} ) {
		if ( $$self{id} ) {
			@{$$self{csr_ids}} = sql::execute( undef, undef, 'SELECT csr_id FROM Assistants WHERE assistant_id=?', $$self{id} );
		} else {
			$$self{csr_ids} = [];
		}
	} # end if
	return @{$$self{csr_ids}};
} # end sub

sub in_Group {
	my $self = shift;
	return sets::intersection(@_, map { $$_{name} } $self->Groups());
}

sub Groups {
	if ( $_[0]{id} and ! $_[0]{Groups} ) {
		require openprint::UserGroup;
		$_[0]{Groups} = [ openprint::UserGroup->find('user_id any'=>$_[0]{id} ) ];
	} # end if
	return @{$_[0]{Groups}} if $_[0]{Groups};
	return ();
} # end sub Groups

sub Notifications {
	my ( $self ) = @_;
	
	require openprint::User_Notification;
	if ( ! exists $$self{Notifications} ) {
		if ( ! $$self{id} ) {
			$$self{Notifications} = [];
		} else {
			$$self{Notifications} = [ openprint::User_Notification->find( user_id=>$$self{id} ) ];
		} # end if
	} else {
		$openprint::log->debug("Have notifications");
	} # end if
	
	return @{$$self{Notifications}};
} # end sub Notifications

sub notification {
	my ( $self, $type ) = @_;
	foreach my $Notification ( $self->Notifications() ) {
		if ( $Notification->type() eq $type ) {
			return $Notification->value();
		}
	}
	return;
}

sub purchasing_total {
	require openprint::PurchaseOrder;
	my $total = 0;
	foreach my $PO ( openprint::PurchaseOrder->find( authorized=>'N' ) ) {
		$total += $PO->total();
	} # end foreach $PO
} # end sub purchasing_total

sub po_limit {
	my ( $self, $type_id, $new_value ) = @_;

	if ( ( ! exists $$self{po_limits} ) and $$self{id} ) {
		if ( $$self{id} ) {
		%{$$self{po_limits}} = sql::execute( undef, undef, 'SELECT type_id, po_limit FROM User_PurchaseOrder_limits WHERE user_id=?', $$self{id} );
		} else {
			$$self{po_limits} = {};
		} # end if
	} # end if

	if ( defined $new_value ) {
		if ( exists $$self{po_limits}{$type_id} ) {
			sql::update( undef, undef, 'user_purchaseorder_limits', ['user_id=? AND type_id=?', $$self{id},$type_id], 'po_limit', 1*$new_value );
		} else {
			sql::insert( undef, undef, 'user_purchaseorder_limits', ['user_id',$$self{id},'type_id', $type_id, 'po_limit', 1*$new_value ] );
		} # end if
		$$self{po_limits}{$type_id} = 1*$new_value;
	} # end if

	return $$self{po_limits}{$type_id};
} # end sub po_limit

sub Asset {
	if ( ! $_[0]{Asset} ) {
		require openprint::Asset;
		if ( $_[0]{asset_id} ) {
			$_[0]{Asset} = new openprint::Asset( $_[0]{asset_id} );
		} else {
			if ( $_[0]->Profile()->Gender() ) {
				#$openprint::log->debug("Loading by gender");
				$_[0]{Asset} = openprint::Asset->find_one(name=>'Default Profile ' . $_[0]->Profile()->Gender() );
			} # end if
			if ( ! $_[0]{Asset} ) {
				#$openprint::log->debug("Loading by default");
				$_[0]{Asset} = openprint::Asset->find_one(name=>'Default Profile' );
			} # end if
			if ( $_[0]{id} ) {
				my @Albums = openprint::Photo_Album->find(user_id=>$_[0]{id});
				foreach my $Album ( @Albums ) {
					my @Photos = $Album->Photos();
					if ( @Photos ) {
						$_[0]{Asset} = $Photos[0]->Asset();
					} # end if
				} # end foreach Album
			} # end if
			if ( ! $_[0]{Asset} ) {
				$_[0]{Asset} = new openprint::Asset( );
			} # end if
		} # end if
	} # end if
	return $_[0]{Asset};
} # end sub Asset

sub Profile {
	if ( ! exists $_[0]{Profile} ) {
		require openprint::User_Profile;
		$_[0]{Profile} = new openprint::User_Profile( $_[0]{id} );
	} # end if
	return $_[0]{Profile};
} # end sub Profile

sub icon {
	return $_[0]->thumbnail_html();
} # end sub icon

sub thumbnail_html {
if ( 0 ) {
	if ( ! $openprint::session{user_id} ) {
		return '';
	} # end if
} # end if
	if ( ! $_[0]{icon} ) {
		$_[0]{icon} = sprintf('<a href="/account/view.html?user_id=%1$d" class="thumbnail"><img src="%2$s" alt="%3$s" title="%3$s"/></a>',
		#$_[0]{icon} = sprintf('<a href="/account/view.html?user_id=%1$d" class="thumbnail"><img src="%2$s?user_id=%1$d" alt="%3$s" title="%3$s" /></a>',
		$_[0]{id}, $_[0]->Asset()->sized_url('small'), $_[0]->alias() );
	} # end if
	return $_[0]{icon};
}

sub link {
	return sprintf('<a href="/account/view.html?user_id=%1$d">%2$s</a>', $_[0]{id}, $_[0]->name() );
} # end sub link

sub link_to {
	my $self = shift;
	my $content = ( @_ ? shift @_ : $self->name() );
	my %options = ref $_[0] eq 'HASH' ? %{$_[0]} : @_;

	return sprintf('<a href="/account/view.html?user_id=%1$d"%3$s>%2$s</a>', 
			$$self{id},
			$content,
			( %options ? join(' ', '', map { $_.'="'.$options{$_}.'"' } keys %options ) : '' ),
			);
} # end sub link_to

sub admin_url_to {
	return '/administrator/managerial/user_profiles.html?user_id='.$_[0]{id};
}

sub admin_link_to {
  my $self = shift;
	return sprintf('<a href="/administrator/managerial/user_profiles.html?ddmCustomer=%3$d&user_id=%1$d">%2$s</a>',
    $$self{id}, @_ ? $_[0] : $self->name(), $$self{company_id} );
} # end sub admin_link_to

sub html {
	if ( ! $_[0]{id} ) {
		$log->error("called html on user without id".$_[0]->to_string() );
		return '';
	} # end if
	my $User = $_[0];
	my $Profile = $_[1] ? $_[1] : $_[0]->Profile();

	my $age = 0;
	my $birthday = $Profile->date_of_birth();
	if ( $birthday and $birthday ne '--' ) {
		my @Birthday = split('-', $birthday );
		$age = Date::Calc::check_date( @Birthday ) ? int(Date::Calc::Delta_Days( @Birthday, Date::Calc::Today() )/365) : 0;
	} # end if

	my $Asset = $User->Asset();
	my $thumbnail_url = $Asset->sized_url('thumbnail');

	return sprintf(q`
				<div class="User">
					<a class="thumbnail" href="/account/view.html?user_id=%1$d"><img src="%3$s" alt="%4$s" /></a>
					<a href="/account/view.html?user_id=%1$d">
					<div class="Name">%2$s</div>
					<div class="Details">%5$s %6$s</div>
					<div class="Tagline">%7$s</div>
					</a>
				</div>`,
				$User->id(), $User->name(),
				( $thumbnail_url ? $thumbnail_url : '/images/no_image.gif' ), '',
				$age ? $age.' year old' : '',
				$Profile->Gender() ? $Profile->Gender() : '',
				$Profile->Tagline(),
			);
	return sprintf(q`
				<div class="User">
					<a href="/account/view.html?user_id=%1$d"><img class="thumbnail" src="%3$s" alt="%4$s" /></a>
					<div class="Name"><label>Name:</label>%2$s</div>
					<div class="Age"><label>Age:</label>%5$s</div>
					<div class="Gender"><label>Gender:</label>%6$s</div>
					<div class="Joined"><label>Joined:</label>%7$s</div>
				</div>`,
				$User->id(), $User->name(),
				( $_ = $User->Asset()->thumbnail_filename() ? $_ : 'no_image.gif' ), '',
				$age ? $age : 'old!',
				$Profile->Gender() ? $Profile->Gender() : 'indeterminate',
				Date::Format::time2str( $openprint::config{DateFormat}, Date::Parse::str2time( $User->created_on() ) ),
			);
} # end sub html

sub last_logged_in {
	if ( (! $_[0]{last_logged_in} ) and $_[0]{id} ) {
		# Almost any entry means we were logged in.  
		my $Log = openprint::Log->find_one(user_id=>$_[0]{id}, action=>'Login', order=>'date_time DESC');
		if ( $Log ) {
#$openprint::log->debug("last_Logged_in: " . $Log->to_string() );
			$_[0]{last_logged_in} = $$Log{date_time};
		} # end if
	}
	return $_[0]{last_logged_in};
} # end sub last_logged_in

sub AUTOLOAD {
	my $name = $AUTOLOAD;
	$name =~ s/.*://;
  #$openprint::log->debug("AUTOLOAD $name") if $debug;
	if ( $fields{$name} ) {
		if ( @_ > 1 ) {
      #$openprint::log->debug("Autoload User $name $_[0]") if $debug;
			return $_[0]{$name} = $_[1];
		} else {
			return $_[0]{$name};
		} # end if
	} else {
		my $Profile = $_[0]->Profile();
		if ( exists $$Profile{fields}{$name} ) {
      #$openprint::log->warn("PRofile field in User::AUTOLOAD $name") if $debug;
			if ( @_ > 1 ) {
				$$Profile{fields}{$name} = $_[1];
			} # end if
			return $$Profile{fields}{$name};
		} elsif ( $debug ) {
			my ( $caller, undef, $line ) = caller;
			$openprint::log->debug("Unknown field in User::AUTOLOAD $name from $caller:$line");
		} # end if
	} # end if
} # end sub AUTOLOAD

sub DESTROY {
}

sub can_edit {
	return 1 if ! $_[0]{id};
	return 1 if $openprint::session{user_id} == $_[0]{id};
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if ( $openprint::User->administrator() eq 'Y' ) and ( $_[0]{company_id} == $openprint::session{company_id} );
	my $Company = $_[0]->Company();
	return 1 if $Company->salesrep_id() and sets::isin( $Company->salesrep_id(), [ $openprint::session{user_id}, $openprint::User->csr_ids(), $openprint::User->assistant_ids() ] );
	return 1 if openprint::usergroup::exists('UserManagement') and openprint::usergroup::is_user_in( ['UserManagement'], $openprint::session{user_id} );
	return 1 if $openprint::User->in_Group('Estimating') and ($_[0]{company_id} != $openprint::User{company_id});
  return 1 if ! $_[0]{passowrd};
	return 0;
} # end sub can_edit

sub can_view {
	return 1 if $openprint::session{user_id} == $_[0]{id};
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if ( $openprint::User->administrator() eq 'Y' ) and ( $_[0]{company_id} == $openprint::session{company_id} );
	my $Company = $_[0]->Company();
	return 1 if $Company->salesrep_id() and sets::isin( $Company->salesrep_id(), [ $openprint::session{user_id}, $openprint::User->csr_ids(), $openprint::User->assistant_ids() ] );
	return 1 if $_[0]->in_Group('Estimating') and ($_[0]{company_id} != $openprint::session{company_id});
	require openprint::Blocklist;
	return 0 if openprint::Blocklist::is_blocked( $openprint::session{user_id},$_[0]{id});
	return 0;
} # end sub can_view

sub Location {
	if ( ! $_[0]{Location} ) {
		my $Profile = $_[0]->Profile();
		my $Location;
		if ( $Profile->postalcode() ) {
			$Location = openprint::Location->find_one( postalcode=>openprint::Location->transform('postalcode', $Profile->postalcode() ) );
		} # end if
		if ( ! $Location and $Profile->city() ) {
			my $City = new openprint::Location( $Profile->city() );
			$Location = openprint::Location->find_one( type=>'city', name=>$City->name() );
			if ( ! $Location ) {
				$Location = openprint::Location::google( join('+', $Profile->postalcode(), $Profile->city() ) );
			} # end if
		} # end if
		if ( ! $Location ) {
			$log->debug("no location for User $_[0]{email}");
			return new openprint::Location();
		} # endif
		$_[0]{Location} = $Location;
	} # end if
		
	return $_[0]{Location};
} # end sub Location

sub code {
	return join('', substr( $_[0]{firstname}, 0, 1), substr( $_[0]{lastname},0,1) );
} # end sub code

sub usergroup_ids {
	return map { $_->usergroup_id() } openprint::User_in_UserGroup->find(user_id=>$_[0]{id}) if $_[0]{id};
	return;
} # end sub usergroup_ids

sub save_notifications {
	my ( $User, $param ) = @_;	

	my @results;
	foreach my $N ( $User->Notifications() ) {
		
		if ( $$N{value} ne $$param{'notification_'.$$N{id}} ) {
			push @results, 'Notification for ' . $N->Type()->name() . " Creation changed $$N{value} => ".$$param{'notification_'.$$N{id}}.'<br/>';
			$N->save( { value => $$param{'notification_'.$$N{id}} } );
		} # end if value changed
	} # end foreach Notification
	return @results;
}
sub email_valid {
	if ( ! defined $_[0]{email_valid} ) {
	require Email::Valid;
	$_[0]{email_valid} = Email::Valid->address( $_[0]{email} );
	} 
	return $_[0]{email_valid};
}

1;
__END__
