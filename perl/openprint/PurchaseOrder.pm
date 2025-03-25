use strict;
use Math::Round qw(nearest);
package openprint::PurchaseOrder;
our @ISA = qw(openprint::Object);
require openprint::Object;

use openprint ();
use vars qw( $debug $log $dbh %config %session $table $serial %fields %find_fields %transforms %defaults );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;
*session = \%openprint::session;

$debug = 0;

require sql;
require ssi;
require misc;
require openprint::Company;
require openprint::Currency;
require openprint::User;
require openprint::Tax;
require openprint::PurchaseOrder_Content;
require openprint::PurchaseOrder_Log;
require openprint::PurchaseOrder_Tax;
require openprint::Email;
require openprint::Manifest;
require openprint::Object_Payment;
require File::Slurp;
require MIME::QuotedPrint;
require MIME::Base64;
require openprint::Object_Asset;
require openprint::Asset;


$table = 'purchaseorders';
$serial = 'purchaseorders_id_seq';

%fields = (
	id									=>	'id',
	num									=>	'num',
	company_id					=>	'company_id',
	contact_id					=>	'contact_id',
	currency_id					=>	'currency_id',
	created_on					=>	'created_on',
	updated_on					=>	'updated_on',
	created_by					=>	'created_by',
	authorized					=>	'authorized',
	authorized_by				=>	'authorized_by',
	authorized_on				=>	'authorized_on',
	delivered_on				=>	'delivered_on',
	delivered_on_switch	=>	'delivered_on_switch',
	paid_on							=>	'paid_on',
	total								=>	'total',
	subtotal						=>	'subtotal',
	deleted							=>	'deleted',
	supplier_id					=>	'supplier_id',
	shipping_method			=>	'shipping_method',
	shipping_terms			=>	'shipping_terms',
	vendor_contact			=>	'vendor_contact',
	contact_id					=>	'contact_id',
	vendor_name					=>	'vendor_name',
	vendor_address1			=>	'vendor_address1',
	vendor_address2			=>	'vendor_address2',
	vendor_city					=>	'vendor_city',
	vendor_country			=>	'vendor_country',
	vendor_state				=>	'vendor_state',
	vendor_postalcode		=>	'vendor_postalcode',
	vendor_phone				=>	'vendor_phone',
	vendor_fax					=>	'vendor_fax',
	vendor_sms					=>	'vendor_sms',
	vendor_email				=>	'vendor_email',
	shipto_contact			=>	'shipto_contact',
	shipto_name					=>	'shipto_name',
	shipto_address1			=>	'shipto_address1',
	shipto_address2			=>	'shipto_address2',
	shipto_city					=>	'shipto_city',
	shipto_country			=>	'shipto_country',
	shipto_state				=>	'shipto_state',
	shipto_postalcode		=>	'shipto_postalcode',
	shipto_phone				=>	'shipto_phone',
	shipto_mobile				=>	'shipto_mobile',
	shipto_fax					=>	'shipto_fax',
	shipto_sms					=>	'shipto_sms',
	shipto_email				=>	'shipto_email',
	manifest_id					=>	'manifest_id',
	cancelled						=>		'cancelled',
	do_not_pay					=>	'do_not_pay',
	#notifications				=>	undef,
);

%find_fields = (
	docket	=>	'(SELECT docket FROM PurchaseOrder_Contents WHERE PurchaseOrder_Contents.po_id=PurchaseOrders.id)',
	item_id	=>	'(SELECT item_id FROM PurchaseOrder_Contents WHERE PurchaseOrder_Contents.po_id=PurchaseOrders.id)',
	notification_user_id	=>	'(SELECT user_id FROM PurchaseOrder_Notifications WHERE po_id=purchaseorders.id)',
);

%transforms = (
	id			=>	[ 's/\D//g', '<2147483647' ],
);

%defaults = (
	created_on	=>	q`'NOW()'`,
	updated_on	=>	q`'NOW()'`,
	deleted			=>	0,
	currency_id	=>	q`$session{Currency_id}`,
	total				=>	0,
	subtotal		=>	0,
	manifest_id	=>	undef,
	cancelled		=>	0,
	supplier_id	=>	undef,
	contact_id	=>	undef,
	do_not_pay	=>	'0',
);

sub save {
	my ( $self, $param, $force_insert ) = @_;

	$self->set( $param ? $param : {} );

	#openprint::PurchaseOrder_Tax->lock();
	# force recalculation
	$self->subtotal(undef);
	foreach my $Tax ( $self->Taxes() ) {
$openprint::log->debug("setting tax amount");
		$Tax->PurchaseOrder( $self );
		$Tax->amount(undef);
	} # end foreach Tax
	$self->total(undef);
	if ( ! $$self{currency_id} ) {
		# Default to current currency
		my $Currency = openprint::Currency::get_current();
		$$self{currency_id} = $Currency->id() if $Currency;
	} # end if
	my $error = $self->SUPER::save({}, $force_insert );

	# Taxes
	foreach my $Tax ( $self->Taxes() ) {
$openprint::log->debug("Saving taxes".$Tax->to_string());
		$error .= $Tax->save({purchaseorder_id=>$$self{id}, PurchaseOrder=>$self});
	} # end foreach
if ( 0 ) {
	# No longer doing this
	foreach my $T ( $self->old_Taxes() ) {
		$T->delete();
	} # end foreach T
}
	#openprint::PurchaseOrder_Tax->unlock();

	return $error;
} # end sub save

sub Currency {
	my ( $self ) = @_;
	if ( ! $$self{currency_id} ) {
$openprint::log->debug("Defaulting PO currency to current");
		$$self{currency_id} = openprint::Currency::get_current()->id();
	} # end if
	return new openprint::Currency( $_[0]{currency_id} );
} # end sub Currency

sub Supplier {
	return new openprint::Company( $_[0]{supplier_id} );
} # end sub Supplier
sub Creator {
	return new openprint::User( $_[0]{created_by} );
} # end sub Creator
sub Authorized_By {
	return new openprint::User( $_[0]{authorized_by} );
} # end sub Authorized_By

sub Contents {
	if ( @_ > 1 ) {
		$_[0]{Contents} = $_[1];
	}
	if ( $_[0]{id} and ! $_[0]{Contents} ) {
		$_[0]{Contents} = [openprint::PurchaseOrder_Content->find( po_id=>$_[0]{id}, order=>'id')];
	} # end if
	return @{$_[0]{Contents}} if $_[0]{Contents};
	return ();
} # end sub Contents

sub debug {
	return $_[0]->debug_Approvers();

}
sub debug_Approvers {
	my $self = shift;
	my @notification_types = map { 'PO ' . (new openprint::PurchaseOrder_ContentType( $_ )->name()) . ' Approvals' } sets::union( map { $_->type_id() } $self->Contents() );

  my $results;

  my @user_ids = sets::union( $self->notifications(), map { $_->user_id() } openprint::User_Notification->find(
        type  =>\@notification_types,
        value =>'Yes',
        user_company_id=>$openprint::User->company_id()
        ) );
  return if ! @user_ids;

  foreach my $U ( openprint::User->find( id=>\@user_ids, company_id=>$openprint::User->company_id() ) ) {
    if ( $U->id() == $openprint::User->id() ) {
      $openprint::log->debug( $U->email() . ' Not mailing me.' );
      next;
    } # end if
    $_ = Email::Valid->address($U->email());
    if ( ( ! $_ ) or ( $_ ne $U->email() ) ) {
      $openprint::log->debug( $U->email() . ' is not a valid address.' );
      next;
    } # end if
    if ( ! $self->can_view( $U ) ) {
      $openprint::log->debug( $U->name() . ' cannot view this PO.' );
      next;
    } # end if
    if ( ! $self->can_authorize( $U ) ) {
      $openprint::log->debug( $U->name() . ' cannot authorize this PO.' );
      next;
    } # end if
	}
}

sub send_approval_required_notification {
	my ( $self ) = @_;

	my $email_template = ssi::slurp_content('/email_template.html');
	my %info;
	$info{From} = $openprint::User;
	$info{PurchaseOrder} = $self;
	$info{ReplacementText} = ssi::include('/email_content/purchase_order_notification.html', \%info);

	my @notification_types = map { 'PO ' . (new openprint::PurchaseOrder_ContentType( $_ )->name()) . ' Approvals' } sets::union( map { $_->type_id() } $self->Contents() );
	$_ = MIME::QuotedPrint::encode_qp( Encode::encode('utf-8', ssi::variable_substitution( \$email_template, \%info ) ) );
	my @body = ('', $_, 'text/html', 'quoted-printable');
	my $mail = new openprint::Email();

	my $results;
	my @user_ids = sets::union( $self->notifications(), map { $_->user_id() } openprint::User_Notification->find(
				type	=>\@notification_types,
				value	=>'Yes',
				user_company_id=>$openprint::User->company_id() 
				) );
	return if ! @user_ids;

	foreach my $U ( openprint::User->find( id=>\@user_ids, company_id=>$openprint::User->company_id() ) ) {
		if ( $U->id() == $openprint::User->id() ) {
			$openprint::log->debug( $U->email() . ' Not mailing me.' );
			next;
		} # end if
		$_ = Email::Valid->address($U->email());
		if ( ( ! $_ ) or ( $_ ne $U->email() ) ) {
			$openprint::log->debug( $U->email() . ' is not a valid address.' );
			next;
		} # end if
		if ( ! $self->can_view( $U ) ) {
			$openprint::log->debug( $U->name() . ' cannot view this PO.' );
			next;
		} # end if
		if ( ! $self->can_authorize( $U ) ) {
			$openprint::log->debug( $U->name() . ' cannot authorize this PO.' );
			next;
		} # end if

		$results .= $mail->send(
				FROM		=>	$openprint::User,
				TO			=>	$U,
				SUBJECT		=>	'Purchase Order requiring approval: ' . $self->id(),
				ATTACHMENTS	=>	\@body,
				);
	} # end foreach U
	return $results;
} # end sub send_approval_required_notification

sub send_to_vendor {
	my ( $self ) = @_;

	my $From = $self->Creator();
	
	my %info = (
			PurchaseOrder	=>	$self,
			From			=>	$From,
			);
	my @attachments = ();
	my $results;

	my $Email = new openprint::Email();

	$info{ReplacementText} = ssi::include("/email_content/purchase_order_body.html", \%info );

	my $html_body = ssi::include( '/email_template.html', \%info );

	my $purchase_order = Encode::encode( 'utf-8', ssi::include('/email_content/purchase_order.html', \%info ) );

	my $file_base = $From->Company()->name().'-PO'.$$self{id};
	$Email->add_pdf_attachment_from_html( $file_base, $purchase_order );
	
	foreach my $OA ( $self->Assets() ) {
		my $Asset = $OA->Asset();
		$_ = File::Slurp::read_file( $Asset->on_disk_path(), err_mode => 'carp' );
		if ( $_ ) {
			push @attachments, ( $Asset->filename(), MIME::Base64::encode_base64( $_ ), 'application/octet-stream', 'base64');
		} else { 
			$results .= 'Unable to attach ' . $Asset->filename() . ' to email.<br/>';
		} # end if
	} # end foreach Asset

	$results .= 'PO ' . $$self{id} . ' emailed from ' . $From->email() . ' to the following recipients:<br/>';
	$results .= $Email->send(
			FROM	=> $From,
			SUBJECT => 'Purchase Order ' . $self->id() . ' from ' . $From->Company()->name(),
			TO		=> $self->vendor_email(), # Email will split by ,
			HTML_BODY	=>	$html_body,
			ATTACHMENTS	=>	\@attachments,
			);
	if ( $self->shipto_email() and ( $self->vendor_email() ne $self->shipto_email() ) ) {
		$results .= $Email->send( 
				TO		=>	$self->shipto_email(),
				SUBJECT	=>	'Purchase Order '. $self->id() . ' for ' . $self->vendor_name(),
				HTML_BODY	=>	$html_body,
				ATTACHMENTS =>	\@attachments,
				);
	} # end if
	if ( $self->notifications() ) {
		$info{ReplacementText} = ssi::include('/email_content/purchase_order_notification.html', \%info );
		$results .= 'Notifications: <br/>' . $Email->send( 
				TO	=>	[ map { new openprint::User( $_ ) } $self->notifications() ],
				SUBJECT	=>	'Purchase Order '. $self->id() . ' for ' . $self->vendor_name(),
				HTML_BODY	=>	ssi::include( '/email_template.html', \%info ),
				ATTACHMENTS =>	\@attachments,
				);
	} # end if

	my $L = new openprint::PurchaseOrder_Log();
	$L->save({
			user_id	=>	$session{user_id},
			po_id	=>	$$self{id},
			reason	=>	$results,
			});

	return $results;

} # end sub send_to_vendor

sub send_to_me {
	my $From = new openprint::User( $session{user_id} );
	my %info = (
			PurchaseOrder	=>	$_[0],
			From			=>	$From,
			);
	my @attachments = ();

	my $Email = new openprint::Email();

	$info{ReplacementText} = ssi::include('/email_content/purchase_order_body.html', \%info );
	$$Email{HTML_BODY} = ssi::include( '/email_template.html', \%info );

	my $purchase_order = Encode::encode( 'utf-8', ssi::include('/email_content/purchase_order.html', \%info ) );

	my $file_base = $From->Company()->name().'-PO'.$_[0]{id};

	my $results = $Email->add_pdf_attachment_from_html( $file_base, $purchase_order );

    foreach my $OA ( $_[0]->Assets() ) {
        my $Asset = $OA->Asset();
        $_ = File::Slurp::read_file( $Asset->on_disk_path(), err_mode => 'carp' );
        if ( $_ ) {
            push @attachments, ( $Asset->filename(), MIME::Base64::encode_base64( $_ ), 'application/octet-stream', 'base64');
        } else {
            $results .= 'Unable to attach ' . $Asset->filename() . ' to email.<br/>';
        } # end if
    } # end foreach Asset

	my $receipt = $Email->send(
			FROM	=> sprintf( '"%s" <%s>', $From->name(), $From->email() ),
			SUBJECT => 'Purchase Order ' . $_[0]->id() . ' from ' . $_[0]->vendor_name(),
			TO		=> $From,
			ATTACHMENTS	=>	\@attachments,
			);

	$results = 'PO ' . $_[0]{id} . ' emailed to the following recipients:<br/>' . $receipt;
	return $results;
} # end sub send_to_me

sub subtotal {
	if ( @_ > 1 ) {
		$_[0]{subtotal} = $_[1];
	} # end if
	if ( ! defined $_[0]{subtotal} ) {
		$_[0]{subtotal} = 0;
		foreach my $C ( $_[0]->Contents() ) {
			$_[0]{subtotal} += $C->total();
		} # end foreach
		$_[0]{subtotal} = Math::Round::nearest( 0.01, $_[0]{subtotal} );
	} # end if
	return $_[0]{subtotal};
} # end sub subtotal

sub total {
	if ( @_ == 2 ) {
		$_[0]{total} = $_[1];
	} # end if
	if ( ! $_[0]{total} ) {
		$_[0]{total} = $_[0]->subtotal();
		foreach my $Tax ( $_[0]->Taxes() ) {
			$_[0]{total} += $Tax->amount();
		} # end foreach Tax
		$_[0]{total} -= $_[0]->payments_total();
		$_[0]{total} = Math::Round::nearest( 0.01, $_[0]{total} );
	} # end if
	return $_[0]{total};
} # end sub total

sub authorize {
	my ( $self ) = @_;
	$$self{authorized} = 1;
	$$self{authorized_by} = $session{user_id};
	$$self{authorized_on} = 'NOW()';
	my $L = new openprint::PurchaseOrder_Log();
	$L->save({
			po_id	=> $$self{id},
			user_id	=> $session{user_id},
			reason	=> 'Authorized by ' . new openprint::User( $session{user_id} )->name(),
			});
	return $self->save();
} # end sub authorize

sub decline {
	my ( $self, $reason ) = @_;
	$$self{authorized} = 0;
	$$self{authorized_by} = $session{user_id};
	$$self{authorized_on} = 'NOW()';
	my $L = new openprint::PurchaseOrder_Log();
	$L->save({
			'po_id'		=> $$self{id},
			'user_id'	=> $session{user_id},
			'reason'	=> 'Declined by ' . new openprint::User( $session{user_id} )->name() . ': ' . $reason,
			});
	return $self->save();
} # end sub decline

sub notifications {
	my ( $self, $new ) = @_;
	if ( $new ) {
		$$self{notifications} = ref $new eq 'ARRAY' ? $new : [ $new ];
		if ( $$self{id} ) {
			my $ac = sql::start_transaction( $openprint::dbh );
			$dbh->do( 'LOCK TABLE PurchaseOrder_Notifications IN ACCESS EXCLUSIVE MODE' ) or $openprint::log->error( DBI->errstr );
			sql::execute( undef, undef, 'DELETE FROM PurchaseOrder_Notifications WHERE po_id=?', $$self{id} );
			foreach ( @{$$self{notifications}} ) {
				sql::insert( undef, undef, 'PurchaseOrder_Notifications', ['po_id', $$self{id}, 'user_id', $_ ] );
			} # end foreach
			sql::end_transaction( $openprint::dbh, $ac );
		} # end if
	} # end if
	if ( $$self{id} and ! exists $$self{notifications} ) {
		@{$$self{notifications}} = sql::execute( undef, undef, 'SELECT user_id FROM PurchaseOrder_Notifications WHERE po_id=?', $$self{id} );
	} # end if
	return $$self{notifications} ? @{$$self{notifications}} : ();
} # end sub notifications

sub update_notifications {
	my $PO = $_[0];
	my $types;
	if ( @_ > 1 ) {
		$types = $_[1];
	} else {
		%{$types} = sets::union( map { $_->type() => 1 } $PO->Contents() );
	}

	my @companies = ( $PO->company_id(), $PO->supplier_id() );
	my @notifications = $PO->notifications(); # returns user_ids
	my @new_notifications = @notifications;
	if ( $PO->is_FSC() or $PO->is_PEFC() ) {
		@new_notifications = sets::union( @new_notifications, map { $PO->can_view( $_->User() ) ? $_->user_id() : () } openprint::User_Notification->find( type=>'FSC/PEFC Notifications', value=>'Yes', user_company_id=>\@companies, 'company_id is null or ='=>$PO->supplier_id() ) );
	} # end if
	foreach my $type ( keys %{$types} ) {
		@new_notifications = sets::union( @new_notifications, map { $PO->can_view( $_->User() ) ? $_->user_id() : () } openprint::User_Notification->find( type=>'PO ' . $type . ' Notifications', value=>'Yes', user_company_id=>\@companies, 'company_id is null or ='=>$PO->supplier_id() ) );
	} # end foreach
	if ( scalar @notifications != scalar @new_notifications ) {
		$PO->notifications(\@new_notifications);
	} # end if
} # end sub update_notifications

sub Logs {
	my ( $self ) = @_;

	return openprint::PurchaseOrder_Log->find( po_id=>$$self{id}, order=>'created_on DESC' );
} # end sub Logs

sub is_FSC {
	my ( $self ) = @_;
	foreach my $C ( $self->Contents() ) {
		return 1 if $C->description() =~ /FSC/i;
	} # end foreach C
} # end sub is_FSC

sub is_PEFC {
	my ( $self ) = @_;
	foreach my $C ( $self->Contents() ) {
		return 1 if $C->description() =~ /PEFC/i;
	} # end foreach C
} # end sub is_PEFC

sub copy {
	my $self = shift;
	my $New = new openprint::PurchaseOrder();
	@$New{keys %fields} = @$self{keys %fields};
	foreach ( 'id', 'authorized', 'authorized_by', 'authorized_on', 'delivered_on', 'created_on', 'cancelled', 'manifest_id', 'Taxes', 'deleted' ) {
		delete $$New{$_};
	} # end foreach
	my @Taxes;
	foreach my $Tax ( $self->Taxes() ) {
		my $NewTax = $Tax->copy();
		$NewTax->PurchaseOrder($New);
		push @Taxes, $NewTax;
	} # end foreach
	$$New{Taxes} = \@Taxes;
	$$New{created_by} = $session{user_id};
	return $New;
} # end sub copy

sub Manifest {
	return new openprint::Manifest( $_[0]{manifest_id} );
} # end sub Manifest

# We don't make any db changes here.  That only happens on PO saving
sub Taxes {
	my $self = shift;
	$$self{Taxes} = shift if @_;
	@{$$self{Taxes}} = openprint::PurchaseOrder_Tax->find(purchaseorder_id=>$$self{id}) if $$self{id} and ! $$self{Taxes};

if ( 0 ) {
	my $Supplier = $self->Supplier();
	my $country = $Supplier->country() ? $Supplier->country() : $$self{vendor_country};
	my $state = $Supplier->state() ? $Supplier->state() : $$self{vendor_state};
	my $created_on = $$self{created_on} ? $$self{created_on} : 'NOW()';

	if ( $country and $state and ! ( $$self{Taxes} and @{$$self{Taxes}} ) ) {
		foreach my $Tax ( openprint::Tax->find(
					'period_start null_or_<='	=>	$created_on,
					'period_end null_or_>='	 =>	$created_on,
					country	=>	$country,
					state	=>	$state,
				) ) {
			my $T = new openprint::PurchaseOrder_Tax();
			$T->set({
				PurchaseOrder	=>	$self,
				tax_id			=>	$$Tax{id},
				rate			=>	$$Tax{rate},
			});
			push @{$$self{Taxes}}, $T;
		} # end foreach Tax
	} # end if
}
	return $$self{Taxes} ? @{$$self{Taxes}} : ();
} # end sub Taxes

sub default_Taxes {
	my ( $self ) = @_;
	@{$$self{Taxes}} = openprint::PurchaseOrder_Tax->find(purchaseorder_id=>$$self{id}) if $$self{id} and ! $$self{Taxes};
	my $Supplier = $self->Supplier();
	my $country = $Supplier->country() ? $Supplier->country() : $$self{vendor_country};
	my $state = $Supplier->state() ? $Supplier->state() : $$self{vendor_state};
	my $created_on = $$self{created_on} ? $$self{created_on} : 'NOW()';
	if ( $$self{id} ) {
		my @new_taxes = openprint::Tax->find(
				'period_start null_or_<='	=>	$created_on,
				'period_end null_or_>='	 	=>	$created_on,
				country	=>	$country,
				state	=>	$state,
			);
		my %new_tax_ids = map { $_->id(), $_->id() } @new_taxes;

		# Clear out any no longer valid taxes
		for ( my $i = 0; $i < @{$$self{Taxes}}; $i += 1 ) {
			my $Tax = $$self{Taxes}[$i];
			if ( ! $new_tax_ids{$$Tax{tax_id}} ) {
				$Tax->delete() if $Tax->id();
				splice @{$$self{Taxes}}, $i, 1; $i -= 1;
			} # end if
		} # end foreach old Tax
		if ( @new_taxes != @{$$self{Taxes}} ) {
			my %tax_ids = map { $_->tax_id(), $_ } @{$$self{Taxes}};
			foreach my $Tax ( @new_taxes ) {
				if ( ! $tax_ids{$$Tax{id}} ) {
					my $T = new openprint::PurchaseOrder_Tax();
					$T->set({
							PurchaseOrder	=>	$self,
							tax_id			=>	$$Tax{id},
							rate			=>	$$Tax{rate},
							});
					$T->save() if $$self{id};
					push @{$$self{Taxes}}, $T;
				} # end if
			} # end foreach Tax	
		} # end if have new taxes
	} # end if recalculate
	return $$self{Taxes} ? @{$$self{Taxes}} : ();
} # end sub Taxes

sub old_Taxes {
	my ( $self ) = @_;
	my @old_Taxes;
	my @new_Taxes = $self->default_Taxes();
	my %new_tax_ids = map { $_->tax_id(), $_->tax_id() } @new_Taxes;
	
	foreach my $old_Tax ( openprint::PurchaseOrder_Tax->find(purchaseorder_id=>$$self{id}) ) {
		if ( ! $new_tax_ids{$old_Tax->tax_id()} ) {
			push @old_Taxes, $old_Tax;
		} # end if
	} # end foreach old_Tax;
	return @old_Taxes;
} # end sub old_Taxes

sub Tax {
    my $result = openprint::PurchaseOrder_Tax->find_one( purchaseorder_id=>$_[0]{id}, tax_id=>$_[1]->id() ) if $_[0]{id};
    if ( ! $result ) {
        return new openprint::PurchaseOrder_Tax();
    } # end if
    return $result;
} # end sub Tax

sub can_edit {
	return 1 if ! $_[0]{id};
	my $User = $_[1] ? $_[1] : new openprint::User( $openprint::session{user_id} );

	if ( $$User{type} eq 'A' ) {
		$log->debug("$$User{firstname} Is administrator") if $debug;
		return 1;
	} # end if
	if ( sets::isin( $_[0]{created_by}, [ $$User{id}, $User->assistant_ids(), $User->csr_ids() ] ) ) {
		$log->debug("$$User{firstname} Either created it or is an assistant") if $debug;
		return 1;
	} # end if

	if ( openprint::usergroup::is_user_in( ['Accounting','Inventory'], $$User{id} ) )  {
		$log->debug("$$User{firstname} Is in Accounting','Inventory'") if $debug;
		return 1;
	} # end if

	foreach my $C ( $_[0]->Contents() ) {
		my @contains = sets::contains( [ $$User{id}, $User->assistant_ids(), $User->csr_ids() ], [ map { $_->salesrep_id() } $C->Orders() ] );
		if ( @contains ) {
			$log->debug("can see because @contains in order salesreps") if $debug;
			return 1;
		} # end if
	} # end foreach C
	return 0;
} # end sub can_edit

sub can_view {
	return 1 if ! $_[0]{id};
	my $User = $_[1] ? $_[1] : $openprint::User;

	if ( $$User{type} eq 'A' ) {
		$log->debug("$$User{firstname} Is administrator") if $debug;
		return 1;
	} # end if
	if ( sets::isin( $_[0]{created_by}, [ $$User{id}, $User->assistant_ids(), $User->csr_ids() ] ) ) {
		$log->debug("$$User{firstname} Either created it or is an assistant") if $debug;
		return 1;
	} # end if
	if ( openprint::usergroup::is_user_in( ['Accounting','Shipping','Inventory'], $$User{id} ) )  {
		$log->debug("$$User{firstname} Is in Accounting','Shipping','Inventory'") if $debug;
		return 1;
	} # end if
			
	foreach my $C ( $_[0]->Contents() ) {
		my @contains = sets::contains( [ $$User{id}, $User->assistant_ids(), $User->csr_ids() ], [ map { $_->salesrep_id() } $C->Orders() ] );
		if ( @contains ) {
			$log->debug("can view because @contains in order salesreps") if $debug;
			return 1;
		} # end if
	} # end foreach C

	if ( my @notifications = $_[0]->notifications() ) {
		if ( sets::isin( $$User{id}, \@notifications ) ) {
			$log->debug($$User{firstname} . ' can see because in notifications.' ) if $debug;
			return 1;
		} # end if
	} # end if
	$log->debug("$$User{firstname} cannot view this PO") if $debug;
	return 0;
} # end sub can_view

sub num {
	if ( @_ > 1 ) {
		$_[0]{num} = $_[1];
	} 
	return $_[0]{id} if ! $_[0]{num};
	return $_[0]{num};
} # end sub num

sub can_send {
	my $User = @_ > 1 ? $_[1] : $openprint::User;
	return 1 if $$User{id} == $_[0]{created_by};
	return 1 if $$User{type} eq 'A';
	return $_[0]->can_authorize();
} # end sub can_send

sub can_authorize {
	my $User = @_ > 1 ? $_[1] : $openprint::User;

	if ( ! $_[0]->total() ) {
		$openprint::log->debug("can_authorize 1 because no total") if $debug;
		return 1;
	} # end if
	if ( $User->purchasing_limit() and ( $_[0]->total() < $User->purchasing_limit() ) ) {
		$openprint::log->debug("can_authorize 1 because total " .  $_[0]->total() . ' < ' . $User->purchasing_limit() ) if $debug;
		return 1;
	} # end if
	my %Totals;
	my %Types;
	foreach my $C ( $_[0]->Contents() ) {
		$Totals{$C->type_id()} += $C->total();
		$Types{$C->type_id()} = $C->Type();
	} # end foreach C
		
	my $authorized = 1;
	foreach my $T ( values %Types ) {
		if ( $Totals{$$T{id}} > $User->po_limit( $$T{id} ) ) {
			$openprint::log->debug("can_authorize 0 because $Totals{$$T{id}} > " . $User->po_limit( $$T{id} ) ) if $debug;
			$authorized = 0
		} else {
			$openprint::log->debug("can_authorize 1 because $Totals{$$T{id}} <= " . $User->po_limit( $$T{id} ) ) if $debug;
		} # end if
	} # end foreach Content 
	if ( $authorized and $User->purchasing_total_limit() ) {
		# Need to check all unauthorized POs FIXME later
	} # end if
	return $authorized;
} # end sub can_authorize

# ( $PO, $Content )
# Can we assume that we can view it?
sub can_see_pricing {
	if ( ! $_[0]{id} ) {
		$log->debug('Can see because new PO') if $debug;
		return 1;
	} # end if

	my $User = $openprint::User;
	
	if (
			( $$User{id} == $_[0]->created_by() )
			or
			( $$User{type} eq 'A' )
			or
			$User->in_Group('Accounting','SalesAdmin','InventoryManager')
		 ) {
		$log->debug('can see pricing') if $debug;
		return 1;
	} # end if

  my @Contents = $_[1] ? ( $_[1] ) : $_[0]->Contents();

  foreach my $C (@Contents) {
    my @contains = sets::contains( [ $$User{id}, $User->assistant_ids(), $User->csr_ids() ], [ map { $_->salesrep_id() } $C->Orders() ] );
    if ( @contains ) {
      $log->debug("can see pricing because @contains in orders") if $debug;
      return 1;
    } elsif ($debug) {
      my @people = ( $$User{id}, $User->assistant_ids(), $User->csr_ids() );
      my @sales_reps = map { $_->salesrep_id() } $_[1]->Orders();
      $log->debug("People @people, reps @sales_reps");
    } # end if
  } # end foreach C

  return 0;

	if ( my @notifications = $_[0]->notifications() ) {
		if ( sets::isin( $$User{id}, \@notifications ) ) {
			$log->debug($$User{firstname} . ' can see because in notifications.' ) if $debug;
			return 1;
		} # end if
	} # end if
	return 0;
} # end sub can_see_pricing

sub payments_total {
	if ( @_ > 1 ) {
		$_[0]{payments_total} = $_[1];
	} # end if
	if ( ! $_[0]{payments_total} ) {
		$_[0]{payments_total} = Math::Round::nearest( 0.01, misc::sum( map { $_->amount() } $_[0]->Payments() ) );
	} # end if
	return $_[0]{payments_total};
} # end sub payments_total

sub Payments {
	if ( @_ > 1 ) {
		$_[0]{Payments} = $_[1];
	} # end if
	if ( ! $_[0]{Payments} ) {
		if ( $_[0]{id} ) {
			$_[0]{Payments} = [ openprint::Object_Payment->find( object_id=>$_[0]{id}, object_type=>'openprint::PurchaseOrder', order=>'id' ) ];
		} else {
			return ();
		} # end if
	} # end if
	return @{$_[0]{Payments}};
} # end sub Payments

sub link_to {
	if ( $_[0]{created_on} ) {
	return join( '', '<a href="/employee/purchase_order/view.html?po_id=', $_[0]{id}, '">' , $_[0]{id}, '</a>' );
	} else {
	return join( '', '<a href="/employee/purchase_order/view.html?po_id=', $_[0]{id}, '"><span class="error">' , $_[0]{id}, ' does not exist</span></a>' );
	} # end if
} # end sub link_to

sub summary {
	if ( ! $_[0]{summary} ) {
		$_[0]{summary} = join('<br/>', map { sprintf('%d %s%s ', $_->qty(), $_->item(), $_->description() ) } $_[0]->Contents() );
	} 
	return $_[0]{summary};
} # end sub summary

sub dockets {
	my $self = shift;
	if ( ! $$self{dockets} ) {
		@{$$self{dockets}} = sets::union( map { $_->docket() ? $_->docket() : () } $self->Contents() );
	}
	return @{$$self{dockets}};
}

sub Created_By {
	return new openprint::User( $_[0]{created_by} );
}

sub is_paid {
	return 1 if $_[0]->payments_total() >= $_[0]->total();
	return 0;
}

sub destroy {
  my $self = shift;
  my $error = '';
  my $ac = sql::start_transaction( $openprint::dbh );
  foreach ($self->Contents()) { $error .= $_->destroy(); };
  foreach ($self->Logs()) { $error .= $_->destroy(); };
  sql::execute(undef,undef, 'DELETE FROM PurchaseOrder_Notifications WHERE po_id=?', $$self{id});
  sql::execute(undef,undef, 'DELETE FROM purchaseorder_taxes WHERE purchaseorder_id=?', $$self{id});
  $error .= $self->SUPER::destroy();
  sql::end_transaction( $openprint::dbh, $ac );
  return $error;
}

1;
__END__
