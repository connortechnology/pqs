use strict;
package openprint::Order;
our @ISA=qw(openprint::Object);

use openprint ();
use vars qw( $debug %session %config %variable $log $dbh $table $serial %fields %find_fields %transforms %defaults );
*session = \%openprint::session;
*config = \%openprint::config;
*variable = \%openprint::variable;
*log = \$openprint::log;
*dbh = \$openprint::dbh;

require sql;
require openprint::usergroup;
require openprint::logs;
require openprint::Order_Tax;
require openprint::Order_Invoice;
require openprint::Order_Status;
require openprint::Payment;
require openprint::Tax;
require openprint::Order_Notification;
require openprint::OrderedProject;
require openprint::OrderedProduct;

$debug = 0;

$table = 'tbl_orders';
$serial = 'orders_id_seq';
%fields = (
	id								=> 'lngorderid',
	session_id				=> 'strsessionid',
	company_id				=> 'lngcustomerid',
	user_id						=> 'lnguserid',
	docket						=> 'docket',
	status						=> undef,
	status_id					=>	'status_id',
	total							=> 'total',
	downpayment				=> 'downpayment',
	cod_percent				=>	'cod_percent',
	downpayment_percent		=>	'downpayment_percent',
	created_on				=> 'created_on',
	updated_on				=>	'updated_on',
	company_name			=> 'company_name',
	salutation				=> 'salutation',
	firstname					=> 'firstname',
	lastname					=> 'lastname',
	address1					=> 'address1',
	address2					=> 'address2',
	city							=> 'city',
	state							=> 'state',
	country						=> 'country',
	postalcode				=> 'postalcode',
	phone							=> 'phone',
	extension					=> 'extension',
	fax								=> 'fax',
	email							=> 'email',
	alsonotify				=> 'alsonotify',	
	paid							=> 'paid',
	owing							=>	'owing',
	currency_id				=> 'currency_id',
	po								=> 'po',
	administrator_name		=> 'administrator_name',
	administrator_comments	=> 'administrator_comments',
	salesrep_id				=>	'salesrep_id',
	#invoice_id				=>	'invoice_id',
	# deprecated, look up invioce and use it's created_on time instead
	#'invoiced_on'				=>	'invoiced_on',
	terms_accepted			=>	'terms_accepted',
	supplier_id				=>	'supplier_id',
	do_not_pay_commission	=>	'do_not_pay_commission',
	);

%transforms = (
	id			=>	[ 's/\D//g', '<2147483647' ],
	docket		=>	[ 's/\D//g', '<2147483647' ],
);

%find_fields = (
	project_id	=>	'id IN (SELECT orderindex FROM Order_Contents WHERE lngprojectindex=?)',
	status		=>	'(SELECT name FROM Order_Statuses WHERE order_statuses.id=status_id)',
	#invoice_id	=>	'(SELECT invoice_id FROM order_invoices WHERE order_id=orders.id)',
invoice_id => 'id IN (SELECT order_id FROM order_invoices WHERE invoice_id=?)',
invoice_num => 'id IN (SELECT order_id FROM order_invoices WHERE invoice_id=(SELECT invoices.id FROM Invoices WHERE num=?))',
);

%defaults = (
	updated_on	=>	q`'NOW()'`,
	salesrep_id	=>	undef,
	do_not_pay_commission	=>	0,
);

sub save {
	my ( $self, $params ) = @_;

	$self->set($params ? $params : {});
	$self->Payments(undef);
	$self->paid(undef);
	$$self{owing} = $$self{total} - $$self{paid};
	$$self{company_id} = $session{company_id} if ! $$self{company_id};
	$$self{user_id} = $session{user_id} if ! $$self{user_id};
	my %sql;
	foreach my $key ( keys %fields ) {
		next if ! $fields{$key};
		$$self{$key} = undef if $$self{$key} eq '';
		$sql{$fields{$key}} = $$self{$key};
	} # end foreach

	my $ac = sql::start_transaction( $dbh );
	if ( ! $$self{id} ) {
		if ( $openprint::config{OrderIDStyle} eq 'Year' ) {
			$sql{id} = $$self{id} = openprint::order::get_order_id( $openprint::log, $openprint::dbh );
		} else {
			@$self{id} = sql::execute( $log, $dbh, q{SELECT nextval('order_id_seq')} );
			$sql{id} = $$self{id};
		} # end if
		$sql{$fields{created_on}} = 'NOW()';
		if ( ( my $error = sql::insert( $log, $dbh, 'Orders', \%sql ) ) ) {
			sql::end_transaction( $dbh, $ac );
			return $error;
		} # end if	
		$self->Company()->save({last_order_id=>$$self{id}}) if $$self{company_id};
	} elsif ( $$params{force_insert} ) {
		if ( ( my $error = sql::insert( $log, $dbh, 'Orders', \%sql ) ) ) {
			sql::end_transaction( $dbh, $ac );
			return $error;
		} # end if	
	} else {
		if ( ( my $error = sql::update( $log, $dbh, 'Orders', ['id=?', $$self{id}], \%sql ) ) ) {
			sql::end_transaction( $dbh, $ac );
			return $error;
		} # end if	
	} # end if

	$self->load();
if ( 0 ) {
	if ( sets::isin($$self{status}, ['Re-Opened','Incomplete'] ) ) {
		# Reload taxes
		foreach my $Tax ( $self->Taxes() ) {
			my $error = $Tax->save();
			if ( $error ) {
				$dbh->rollback();
				return $error;
			} # end if
		} # end foreach $Tax
	} # end if
}
	sql::end_transaction( $dbh, $ac );
	return '';
} # end sub save

sub delete {
	my $self = shift;

	if ( ! $$self{id} ) {
		$log->error("Order::delete called with no id");
		return;
	}

	my $ac = sql::start_transaction( $dbh );
	sql::execute( $log, $dbh, q{DELETE FROM Schedule WHERE ProjectIndex IN ( SELECT lngProjectIndex FROM Order_Contents WHERE OrderIndex=?)}, $$self{id} );
	sql::execute( $log, $dbh, q{DELETE FROM Order_Log WHERE order_id=?}, $$self{id} );
	sql::execute( $log, $dbh, q{DELETE FROM Order_Taxes WHERE order_id=?}, $$self{id} );
	sql::execute( $log, $dbh, q{DELETE FROM Order_Invoices WHERE order_id=?}, $$self{id} );
	sql::execute( $log, $dbh, q{DELETE FROM Order_Contents WHERE OrderIndex=?}, $$self{id} );
	sql::execute( $log, $dbh, q{DELETE FROM Ordered_Products WHERE order_id=?}, $$self{id} );
	sql::update( undef, undef, 'Projects', [ 'order_id=?', $$self{id}], [ 'order_id', undef ] );
	sql::update( undef, undef, 'payments', [ 'order_id=?', $$self{id}], [ 'order_id', undef ] );
	sql::execute( $log, $dbh, q{DELETE FROM Order_Notifications WHERE order_id=?}, $$self{id} );
	sql::execute( $log, $dbh, q{DELETE FROM Orders WHERE id=?}, $$self{id} );
	sql::end_transaction( $dbh, $ac );
	
	openprint::logs::insertLogRecord('4', "Order ID: " . $$self{id},);
	
} # end sub delete

sub destroy {
	$_[0]->delete();
} # end sub destroy 

sub to_string {
	my $self = shift;
	return sprintf('%d %s %s %s %s', $$self{id},
			$self->Company()->name(), $self->Currency()->format($self->total()),
			ssi::format_date($self->created_on()), $self->status());
} # end sub

# Approve is acknowledging the prices, etc and giving the go ahead. So this function updates all the prices, taxes, statuses, etc.
sub approve {
	my $self = shift;

	my $error;
	my $ac = sql::start_transaction( $openprint::dbh );


	foreach my $OP ( $self->Ordered_Projects() ) {
		my $Project = $OP->Project();
		sql::update( $log, $dbh, 'tbl_Project_Contents', ['lngProjectIndex=? AND strStatus=?', $Project->id(), 'Waiting For Customer Approval'], 'strstatus', 'Ordered' );
		$Project->add_to_log( @openprint::session{'company_id', 'user_id'}, 'Additional Charges Approved' );
		$Project->price( $Project->ordered_quantity_index(), undef );
		$error .= $Project->save();
		$error .= $OP->save({price=>undef});
		last if $error;
	} # end while
	if ( $error ) {
		$dbh->rollback();
		sql::end_transaction( $openprint::dbh, $ac );
		return $error;
	} # end if
	foreach my $Tax ( $self->Taxes() ) {
		$Tax->amount(undef);
		$error .= $Tax->save();
	} # end foreach
	if ( $error ) {
		$dbh->rollback();
		sql::end_transaction( $openprint::dbh, $ac );
		return $error;
	} # end if

	$self->subtotal( undef );
	$self->total( undef );
	$error .= $self->save({ status => 'In Production'});
	if ( $error ) {
		$dbh->rollback();
		sql::end_transaction( $openprint::dbh, $ac );
		return $error;
	} # end if
	$self->add_log( 'Customer Approved' );
	sql::end_transaction( $openprint::dbh, $ac );
	return;
} # end sub approve

sub Status {
	return new openprint::Order_Status( $_[0]{status_id} );
} # end sub Status

sub status {
	if ( @_ > 1 ) {
$openprint::log->debug("Setting status to $_[1]");
		my $Status = openprint::Order_Status->find_one(name => $_[1]);
		if ( ! $Status ) {
			$log->error("New Order Status! $_[1]");
			$Status = new openprint::Order_Status();
			$Status->save({name=>$_[1]});
		} # end if
		if ( $Status->id() != $_[0]{status_id} ) {
			$_[0]->save({ status_id => $Status->id() }) if $_[0]{id};
			$_[0]{status} = $_[1];
			$_[0]->add_log( "Changed Status to $_[1]" ) if $_[0]{id};
		} # end if
	} # end if
	if ( ! $_[0]{status} ) {
		$_[0]{status} = $_[0]->Status()->name();
		if ( !$_[0]{status} ) {
			$_[0]{status} = 'Incomplete';
		} # end if
	} # end if
	return $_[0]{status};
} # end sub status

# Adding Waiting For Pickup, Shipped, Picked Up
sub update_status {
	my $self = shift;
	my $do_not_notify = shift;
	if ( $self->status() eq 'Re-Opened' ) {
		return $$self{status};
	}

	$_ = q{SELECT DISTINCT(strStatus) FROM Projects WHERE id IN (SELECT lngProjectIndex FROM Order_Contents WHERE OrderIndex=?)};
	my @statuses = sql::execute( $log, $dbh, $_, $$self{id} );

	if ( sets::isin( 'Pending Deposit', \@statuses ) and $self->status() ne 'Pending Deposit' ) {
		$self->status( 'Pending Deposit' );
	} elsif (	sets::isin( 'Waiting For Customer Approval', \@statuses ) ) {
		return $self->status( 'Waiting For Customer Approval' );
	} elsif (	sets::isin( 'Waiting For QA Approval', \@statuses ) ) {
		return $self->status( 'Waiting For QA Approval' );
	} elsif ( sets::intersection( @statuses, 'In Prepress','Proofs Out','Approved','Printed') ) {
		$self->status( 'In Production' );
	} else { # Projcets are complete
		# All projects have same shipping type, so if one is waiting, all must be waiting
		if ( sets::isin( 'Waiting For Pickup', \@statuses ) ) {
			$self->status( 'Waiting For Pickup' );
		} elsif ( sets::isin( 'Picked Up', \@statuses ) ) {
			$self->status( 'Picked Up' );
		} elsif ( sets::isin( 'Shipped', \@statuses ) ) {
			$self->status( 'Shipped' );
		} # end if
		$self->status('Complete');
	} # end if
	if ( 'Complete' eq $self->status() ) {
		#$self->send_completion_notice( ) unless $do_not_notify

		if ( $config{SendInvoiceOnProjectCompletion} ne 'N' ) {
			#send_invoice( $r, $log, $dbh, $order_id );
		} # end if
	} # end if
	return $$self{status};
} # end sub update_status

sub add_log {
	my ( $self, $comment ) = @_;
	sql::insert( undef, undef, 'Order_Log',[
			order_id =>	  	$$self{id},
			company_id =>  	$openprint::session{company_id} ? $openprint::session{company_id} : undef,
			user_id =>		  $openprint::session{user_id},
			description =>	$comment,
			] );
} # end sub add_log

sub company {
	my $self = shift;
	return new openprint::Company( $$self{company_id} );
} # end sub company

sub Company {
	return new openprint::Company( $_[0]{company_id} );
} # end sub Company

sub Contents {
	if ( ! $_[0]{Contents} ) {
		$_[0]{Contents} = [ 
			$_[0]->Ordered_Projects(),
			$_[0]->Products(),
			];
	} # end if
	return @{$_[0]{Contents}};
} # end sub Contents

sub Ordered_Projects {
	return openprint::OrderedProject->find( order_id=>$_[0]{id}, order=>$openprint::OrderedProject::fields{project_id});
} # end sub Ordered_Projects

sub Projects {
	my $self = shift;
	$$self{Projects} = shift if @_;
	if ( $$self{id} and ! $$self{Projects} ) {
		$$self{Projects} = [ map { $_->Project() } $self->Ordered_Projects() ];
	}

	return @{$$self{Projects}} if $$self{Projects};
	return ();
} # end sub Projects

sub Products {
	my $self = shift;
 	$$self{Products} = shift if @_;
	if ( ! $$self{id} ) {
		$openprint::log->warn("openrpint::Order->Products called with no id");
		return ();
	} # end if
	if ( ! $$self{Products} ) {
		@{$$self{Products}} = openprint::OrderedProduct->find( order_id=>$$self{id}, order=>'product_id' );
	}
	return @{$$self{Products}};
} # end sub Products

sub User {
	return new openprint::User( $_[0]{user_id} );
}

sub name {
	my $self = shift;
	if ( ! ( $$self{firstname} or $$self{lastname} ) ) {
		return $self->User()->name();
	} # end if
	return $$self{firstname} . ' ' . $$self{lastname};
} # end sub name

sub balance {
	my $self = shift;
	return 1*($self->total() - $$self{paid});
} # end sub balance

sub Currency {
  my $self = shift;
  if ( ! $$self{Currency} ) {
    $$self{Currency} = new openprint::Currency( $$self{currency_id} );
  }
  return $$self{Currency};
} # end sub

sub pay {
	my $self = shift;
	if ( $self->owing() <= 0 ) {
		$self->update_status();
		return "Order $$self{id} is already paid!<br/>";
	} # end if

	# Payment->save() will load and save the Order object as well
	my $error = (new openprint::Payment())->save({
			order_id			=>	$$self{id},
			payor_id			=>	$$self{company_id},
			recipient_id	=>	$self->supplier_id(),
			amount				=>	$self->owing(),
			method				=>	'Manual',
			currency_id		=>	$$self{currency_id},
			memo					=>	'Order marked paid',
			received_on		=>	'NOW()',
			});
	if ( !$error ) {
		$self->add_log('Paid.');
		$self->update_status();
		$error .= $self->save();
	} # end if
	return $error;
} # end sub pay

sub cancel {
	my $Order = shift;
	my $error = '';
  $error .= $Order->save({ status=>'Cancelled' });
	require openprint::press_schedule;
  foreach my $Project ( $Order->Projects() ) {
    $Project->status('Unordered');
    $Project->order_id( undef );
    $Project->docket( undef );
    $Project->save();
		foreach my $PS ( $Project->Services() ) {
			$PS->save({status=>'calculated'});
		}

    openprint::press_schedule::remove( $Project->id() );

    # Free up any stock allocated to this project
    foreach my $PA ( openprint::PaperAllocation->find( docket=>$Order->docket() ) ) {
      my @skid_ids = $PA->skid_ids() ? @{$PA->skid_ids()} : ();
      $Order->add_log( qq`De-allocated $$PA{quantity}$$PA{units} of <a href="/employee/inventory/paper_details.html?paper_id=$$PA{paper_id}">` . $PA->Paper()->to_string() . '</a>'.
          ( @skid_ids ? ' on skid: ' .  join(',', map { $_->url_to() } openprint::Skid->find(id=>\@skid_ids) ) : '' ) );
      $PA->delete();
    } # end foreach PA
  } # end foreach
  $Order->add_log( 'Cancelled' );
  $Order->send_cancellation_notice();
	return $error;
} # end sub cancel

sub send_cancellation_notice {

	my @Recipients;
	# Send to inventory and scheduling people.
	foreach my $Recipient ( 
		openprint::User->find('usergroup any'=>'Inventory',type=>['E','A']),
		openprint::User->find('usergroup any'=>'Scheduling','type'=>['E','A'])
		) {
		next if $Recipient->id() == $session{user_id};
		next if $Recipient->notification('Docket Cancellations') ne 'Yes';
		push @Recipients, $Recipient;
	} # end foreach Recipient

	return if ! @Recipients;

	my %order;
	$order{Order} = $_[0];
	$order{ReplacementText} = ssi::include('/email_content/order_cancellation_notice.html', \%order );
	(new openprint::Email())->send(
			FROM	=> $openprint::User,
			TO	=> \@Recipients,
			SUBJECT => "Docket $_[0]{docket} has been cancelled.",
			ATTACHMENTS => [ '', MIME::QuotedPrint::encode_qp( ssi::include( '/email_template.html', \%order ) ), 'text/html', 'quoted-printable'],
			);
	
} # end sub send_cancellation_notice

sub subtotal {
	my $self = shift;
	if ( @_ ) {
		$$self{subtotal} = shift;
	} # end if

	if ( (!$$self{status}) or (!$$self{subtotal}) or sets::isin($$self{status}, ['Re-Opened','Incomplete']) ) {
		$$self{subtotal} = 0;
		$$self{subtotal} += misc::sum( map { $_->price() } $self->Ordered_Projects() );
		foreach my $Product ( $self->Products() ) {
			my $price = $Product->total();
#$log->debug("subtotal: ordered price: $price");
			if ( $Product->currency_id() != $$self{currency_id} ) {
				my $rate = $Product->Currency()->conversions( $$self{currency_id} );
				$price *= $rate;
#$log->debug("subtotal: ordered price converted to: $price rate($rate) $$self{currency_id} != ".$Product->currency_id());
			} # end if
			$$self{subtotal} += $price;
		} # end foreach Project
	} # end if
	return $$self{subtotal};
} # end sub subtotal

sub total {
	my $self = shift;
	$$self{total} = shift if @_;
	if ( (!$$self{total}) or 
			($$self{status} and sets::isin($$self{status}, ['Re-Opened','Incomplete']) )
		 ) {
		$$self{total} = $self->subtotal();
		foreach my $Tax ( $self->Taxes() ) {
			$$self{total} += $Tax->amount();
		} # end foreach Tax
	} # end if
	return $$self{total};
} # end sub total

sub credit_card_fee {
	my $self = shift;
	if ( ! exists $$self{credit_card_fee} ) {
		$$self{credit_card_fee} = 0;
		foreach my $OP ( $self->Ordered_Projects() ) {
			my $Project = $OP->Project();
			$$self{credit_card_fee} += $Project->credit_card_fee( $Project->ordered_quantity_index() );
		}
	}
	return $$self{credit_card_fee};
}

sub csr_commission {
	my $self = shift;
	if ( ! exists $$self{csr_commission} ) {
		$$self{csr_commission} = 0;
		foreach my $OP ( $self->Ordered_Projects() ) {
			my $Project = $OP->Project();
			$$self{csr_commission} += $Project->csr_commission( $Project->ordered_quantity_index() );
		}
	}
	return $$self{csr_commission};
}

sub send_completion_notice {
	my ( $self ) = @_;

	my %order = (
		OrderID => $self->id(),
		Order	=> $self,
		Currency	=>$self->Currency(),
	);

	my @attachments = ();

	$order{ReplacementText} = ssi::include( '/email_content/order_completion_notice.html', \%order );
	my $email_template = misc::load_file( $log, $config{SkinPath}. '/email_template.html' );
	$_ = MIME::QuotedPrint::encode_qp( Encode::encode( 'utf-8', ssi::variable_substitution( \$email_template, \%order ) ) );
	my @body = ('', $_, 'text/html', 'quoted-printable');

	$_ = misc::load_file( $log, $ENV{DOCUMENT_ROOT} . '/email_content/sales_order.html' );
	if ( $_ ) {
		$_ = MIME::QuotedPrint::encode_qp( Encode::encode( 'utf-8', ssi::variable_substitution( \$_, \%order ) ) );
		push @attachments, "Order$$self{id}.html", $_, 'text/html', 'quoted-printable';
	} # end if
	#my %mail = (
		#SMTP	=> $config{'Mail Server'},
		#FROM	=> $config{AccountingEmail},
		##TO		=> $order{txtEmail},
		#SUBJECT => "Order $order_id Is Complete",
#);
	#misc::send_email_with_attachment( $log, \%mail, @body, @attachments );
} # end sub send_completion_notice

# This is a self-contained function that sends the email messages for a specified order to the apropriate people.
# >Something to note:	the order email is sent in the currency that the order is stored in, not neccessarily the current currency
sub send_sales_order {
	my ( $self ) = @_;
	my %order = (
		OrderID => $$self{id},
		Order => $self,
	);
	my $Email = new openprint::Email();
	my $results;

	# When an order is made,the Order currency will be the current session Currency.	
	# All resends should stay in the currency that the order was created in.
	my $Currency = $self->Currency();
	@order{'Currency','CurrencyName','CurrencySymbol'} = ( $Currency, $Currency->name(), $Currency->symbol() );

	my $email_template = ssi::slurp_content( '/email_template.html' );

	$order{ReplacementText} = ssi::include('/email_content/sales_order_body.html', \%order );
	$Email->html_body( ssi::variable_substitution( \$email_template, \%order ) );

	$order{ReplacementText} = ssi::include( '/email_content/sales_order.html', \%order );
	my $sales_order = ssi::variable_substitution( \$email_template, \%order );

	$Email->add_pdf_attachment_from_html("Order$$self{id}", $sales_order );
	$Email->add_html_attachment("Order$$self{id}.html", $sales_order ) if $openprint::User->email() =~ /^iconnor/;

	my $sales_person_email;
	if ( $self->salesrep_id() ) {
		my $CSR = new openprint::User( $self->salesrep_id() );
		$sales_person_email = sprintf('"%s %s" <%s>', $CSR->get('firstname','lastname','email'));
	}
	if ( ! $sales_person_email ) {
		$sales_person_email = $config{OrderingEmail};
	} # end if
	if ( ! $sales_person_email ) {
		$log->error("No sales person email configured.  Emails will not be sent");
		$self->add_log( '<div class="error">No sales person email configured.  Emails will not be sent.</div>');
	} else {
	
		my $email_results .= $Email->send(
				FROM	=> $sales_person_email,
				TO		=> sprintf('"%s %s" <%s>', $self->get('firstname','lastname','email')),
#TO	 =>	'iconnor@connortechnology.com',
#BCC	 =>	'iconnor@connortechnology.com',
				SUBJECT => "Order $$self{id} Docket $$self{docket}",
				);
		$self->add_log( 'Sales Order:'.$email_results.'<br/>' );
		$results .= 'Sales order sent to ' . $email_results . '<br/>';
	}
	$results .= $self->send_admin_emails();
	return $results;
}
sub send_admin_emails {
	my $self = shift;
	my @admin_emails = @_;

	my %order = (
    OrderID => $$self{id},
    Order => $self,
  );
  my $Email = new openprint::Email();
  my $results;

	my $sales_person_email;
	if ( $self->salesrep_id() ) {
		my $CSR = new openprint::User( $self->salesrep_id() );
		$sales_person_email = sprintf('"%s %s" <%s>', $CSR->get('firstname','lastname','email'));
	}
	if ( ! $sales_person_email ) {
		$sales_person_email = $config{OrderingEmail};
	} # end if

  # When an order is made,the Order currency will be the current session Currency.  
  # All resends should stay in the currency that the order was created in.
  my $Currency = $self->Currency();
  @order{'Currency','CurrencyName','CurrencySymbol'} = ( $Currency, $Currency->name(), $Currency->symbol() );

  my $email_template = ssi::slurp_content( '/email_template.html' );

	$Email = new openprint::Email();
	$order{ReplacementText} = ssi::include( '/email_content/order_admin_body.html', \%order );
	$Email->html_body( ssi::variable_substitution( \$email_template, \%order ) );

	$order{ReplacementText} = ssi::include( '/email_content/sales_order_for_admin.html', \%order );
	$Email->add_pdf_attachment_from_html("Order$$self{id}",  ssi::variable_substitution( \$email_template, \%order ) );

	my @project_dockets = ();

	# Add a project summary and docket sheet for each project in the order
	my $docket_content = ssi::slurp_content('/email_content/order_docket_sheet.html');
	my $summary_content = ssi::slurp_content( '/email_content/project_summary.html' );
	foreach my $Project ($self->Projects()) {
		my %data = (
				OrderID => $$self{id},
				Order => $self,
				Project =>	$Project,
				);
			
		openprint::print_project::summary( $openprint::r, $log, $dbh, \%data, $Project->id() );
		if ( $docket_content ) {
			$Email->add_html_attachment( "ProjectDocket$$Project{id}", ssi::variable_substitution( \$docket_content, \%data ) );
		} # end if docket_content
		if ( $summary_content ) {
			$data{ReplacementText} = ssi::variable_substitution( \$summary_content, \%data );
			$Email->add_pdf_attachment_from_html( "ProjectSummary$$Project{id}", ssi::variable_substitution( \$email_template, \%data ) );
		} # end if
	} # for each Project

	if ( ! @admin_emails ) {
		@admin_emails = split( ',', $config{OrderingEmail} );
		@admin_emails = map { misc::trim(lc $_) } @admin_emails;

		my @accounting_emails = split( ',', $config{AccountingEmail} );
		@accounting_emails = map { misc::trim(lc $_) } @accounting_emails;

		@admin_emails = sets::union( @admin_emails, @accounting_emails, $sales_person_email, 
				map {
				sets::isin( $_->User()->type(), ['E','A'] ) ? 
				sprintf('"%s %s" <%s>', $_->User()->get('firstname','lastname','email')) 
				: ()
				} $self->Projects()
				);
	}

	if ( @admin_emails ) {
		my $email_results .= $Email->send(
				FROM	=> $config{OrderingEmail},
				'Reply-to'	=> $$self{email},
				TO		=> \@admin_emails,
				#TO	 =>	'iconnor@point-one.com',
				#TO	 =>	'iconnor@connortechnology.com',
				#BCC	 =>	'iconnor@connortechnology.com',
				SUBJECT => "Order $$self{id}",
				);
		$self->add_log( 'Admin Sales Order:'.$email_results );
		$results .= 'Admin Sales Order sent to '. $email_results.'<br/>';
	} # end if
$log->debug("Results: $results");
	return $results;
} # end sub send_sales_order

sub owing {
	if ( $_[0]{status} eq 'Cancelled' ) {
		return 0;
	} else {
		return $_[0]{total} - $_[0]->paid();
	} # end if
} # end sub owing

sub Taxes {
	my ( $self ) = @_;

	if ( ! $$self{id} ) {
		return ();
	} # end if

	if ( ! $$self{Taxes} ) {
		$$self{Taxes} = [ openprint::Order_Tax->find( order_id=>$$self{id} ) ];
	} # end if
	if ( ! @{$$self{Taxes}} ) {
		my $country = $self->country();
		$country = $self->Company()->country() if ! $country;

		my $state = $self->state();
		$state = $self->Company()->state() if ! $state;

		if ( $country and $state ) {
			foreach my $Tax ( openprint::Tax->find(
						'period_start null_or_<='	=>	$$self{created_on},
						'period_end null_or_>='		=>	$$self{created_on},
						country	=>	$country,
						state	=>	$state,
					) ) {
				my $T = new openprint::Order_Tax();
				$T->save({
						order_id	=>	$$self{id},
						tax_id		=>	$$Tax{id},
						rate			=>	$$Tax{rate},
						});
				push @{$$self{Taxes}}, $T;
			} # end foreach Tax
		} # end if
	} # end if
	return @{$$self{Taxes}};
} # end sub Taxes

sub Tax {
	my $self = shift;
	my $Tax = shift;

	$self->Taxes() if !$$self{Taxes};
	if ( $$self{Taxes} ) {
		foreach my $OT ( @{$$self{Taxes}} ) {
			return $OT if $$OT{tax_id} == $$Tax{id};
		}
	}
	return new openprint::Order_Tax();
} # end sub Tax

sub Payments {
	my $self = shift;
	$$self{Payments} = shift if @_;
	if ( $$self{id} and ! $$self{Payments} ) {
		$$self{Payments} = [ openprint::Payment->find(order_id=>$$self{id},order=>$openprint::Payment::fields{received_on}.' DESC') ];
	}
	return $$self{Payments} ? @{$$self{Payments}} : ();
}

sub paid {
	my $self = shift;

	$$self{paid} = shift if @_;
	if ( $$self{id} and ! defined $$self{paid} ) {
		$$self{paid} = misc::sum( map { $_->Currency()->convert_from($_->amount(), $self->Currency()) } $self->Payments() );
	} # end if
	return $$self{paid};
} # end sub paid

sub payment_days {
	return 0 if ! $_[0]->invoiced_on();
	my $invoiced_on_seconds = Date::Parse::str2time( $_[0]->invoiced_on() );
	my $paid_on_seconds = $_[0]->paid_on_seconds();
	return int( ( $paid_on_seconds - $invoiced_on_seconds ) / ( 60*60*24 ) );
} # end sub payment_days

sub paid_on_seconds {
	if ( $_[0]->paid() < $_[0]->total() ) {
		return time;
	} # end if
	my @Payments = $_[0]->Payments();
	my $Last_Payment = $Payments[-1];
	if ( ! $Last_Payment ) {
		return time;
	} # end if
	return Date::Parse::str2time( $Last_Payment->received_on() );
} # end sub paid_on

sub paid_on {
	if ( $_[0]->paid() < $_[0]->total() ) {
		return Date::Format::time2str( '%Y-%m-%d %H:%M:%S', time );
	} # end if
	my @Payments = $_[0]->Payments();
	my $Last_Payment = $Payments[-1];
	if ( ! $Last_Payment ) {
		return Date::Format::time2str( '%Y-%m-%d %H:%M:%S', time );
	} # end if
	return $Last_Payment->received_on();
} # end sub paid_on

sub downpayment_owing {
	if ( ! exists $_[0]{downpayment_owing} ) {
		$_[0]{downpayment_owing} = $_[0]->downpayment() - $_[0]->paid();
		$_[0]{downpayment_owing} = 0 if $_[0]{downpayment_owing} < 0;
	} # end if
	return $_[0]{downpayment_owing};
} # end sub downpayment_owing

sub downpayment_percent {
	if ( ! defined $_[0]{downpayment_percent} ) {
		my $Credit = $_[0]->Company()->Credit();
		$_[0]{downpayment_percent} = $Credit->downpayment();
	} # end if
	return $_[0]{downpayment_percent};
} # end sub downpayment_percent

sub cod_percent {
	my $Credit = $_[0]->Company()->Credit();
	return $Credit->cod();
} # end sub cod_percent

sub cod { 
	return Math::Round::nearest( .01,$_[0]{total} * ($_[0]->cod_percent/100));
} # end sub cod

# Returns the remmaining amount to pay on delivery
sub cod_owing {
	if ( ! exists $_[0]{cod_owing} ) {
		if ( $_[0]{status} eq 'Cancelled' ) {
			$_[0]{cod_owing} = 0;
		} else {
			$_[0]{cod_owing} = $_[0]->cod() - $_[0]->paid();
			$_[0]{cod_owing} = 0 if $_[0]{cod_owing} < 0;
		} # end if
	} # end if
	return $_[0]{cod_owing};
} # end sub cod_owing

sub cod_owing_percent {
	my $cod_total = $_[0]->cod();
	return 0 if ! $cod_total;
	return 0 if (1*$_[0]->paid()) == (1*$cod_total);
	return 0 if (1*$_[0]->paid()) eq (1*$cod_total);

	my $owing = int($_[0]->paid()*100/$cod_total) if $cod_total;
#$openprint::log->debug( "cod_toal $cod_total owing: $owing paid: " . $_[0]->paid() );

	return 0 if $owing == 100;
	return 100-$owing;
	return 0;
} # end sub cod_owing_percent

sub supplier_id {
	if ( @_ > 1 ) {
		$_[0]{supplier_id} = $_[1];
	} 
	if ( ! $_[0]{supplier_id} ) {
		$_[0]{supplier_id} = $openprint::config{owner_id};
	} # end if
	return $_[0]{supplier_id};
} # end sub supplier_id

sub Supplier {
	return new openprint::Company( $_[0]->supplier_id() );
} # end sub Supplier

sub AdditionalChargeNotifications {
	if ( @_ > 1 ) {
		delete $_[0]{Notifications};
	} # end if
	if ( ! $_[0]{Notifications} ) {
		$_[0]{Notifications} = [ openprint::Order_Notification->find(order_id=>$_[0]{id}, order=>'user_id') ];
	} # end if
	if ( ! @{$_[0]{Notifications}} ) {
		
		my %users;
		if ( $_[0]->email() ) {
			foreach my $e ( split(',', lc $_[0]->email() ) ) {
				next if ! $e;
				next if $users{$e};
				my $U = openprint::User->find_one(email=>$e);
				if ( ! $U ) {
					$U = new openprint::User();
					$U->save({ email=>$e, company_id=>$_[0]{company_id} });
				} # end if
				my $ON = new openprint::Order_Notification();
				$ON->save({order_id=>$_[0]{id}, user_id=>$$U{id}});
				push @{$_[0]{Notifications}}, $ON;
				$users{$$U{email}} = $U;
			} # end foreach
		} # end if 
		my $CSR = $_[0]->CSR();
		if ( $CSR->id() and ! $users{$CSR->email()} ) {
			my $ON = new openprint::Order_Notification();
			$ON->save({order_id=>$_[0]{id}, user_id=>$$CSR{id}});
			push @{$_[0]{Notifications}}, $ON;
			$users{$CSR->email()} = $CSR;
		} # end if
		$CSR = $_[0]->Company()->CSR();
		if ( $CSR->id() and ! $users{$CSR->email()} ) {
			my $ON = new openprint::Order_Notification();
			$ON->save({order_id=>$_[0]{id}, user_id=>$$CSR{id}});
			push @{$_[0]{Notifications}}, $ON;
			$users{$CSR->email()} = $CSR;
		} # end if
	} # end if
	return @{$_[0]{Notifications}};
} # end sub AdditionalChargeNotifiactions

sub CSR {
	return new openprint::User( $_[0]{salesrep_id} );
} # end sub CSR

sub can_invoice {
	return 0 if ! $_[0]{id};
	return 1 if $openprint::session{user_type} eq 'A';
$openprint::log->debug("No admin");
	return 1 if $openprint::session{user_type} eq 'E' and openprint::usergroup::is_user_in( ['Accounting'], $openprint::session{user_id} );
$openprint::log->debug("Not employee" );
	return 0;
} # end sub can_invoice

sub can_reopen {
	return 0 if ! $_[0]{id};
	if ( $openprint::session{user_type} eq 'A' ) {
		return 1;
	}
	return 1 if $openprint::session{user_type} eq 'E' and openprint::usergroup::is_user_in( ['Accounting'], $openprint::session{user_id} );
	return 0 if sets::isin( $_[0]->status(), [ 'Paid', 'Re-Opened', 'Incomplete' ] );
	if ( $_[0]->Invoices() > 0 ) {
		return 0;
	}
	return 1;
} # end sub can_reopen

sub Invoice {
$openprint::log->error("Deprecated call to Order::Invoice");
	return new openprint::Invoice( $_[0]{invoice_id} );
} # end sub Invoice

sub Invoices {
	if ( ! $_[0]{Invoices} ) {
	 $_[0]{Invoices} = [ openprint::Order_Invoice->find( order_id=>$_[0]{id}, order=>'invoice_id' ) ];
	}
	return @{$_[0]{Invoices}};
} # end sub Invoices

sub invoiced_on {
	my @Invoices = $_[0]->Invoices();
	if ( @Invoices ) {
		return $Invoices[0]->Invoice()->created_on();
	} 
	return;	
}  # end sub invoiced_on

sub can_see_pricing {
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if $_[0]{user_id} == $openprint::session{user_id};
	return 1 if $_[0]{salesrep_id} == $openprint::session{user_id};
	return 1 if openprint::usergroup::is_user_in( ['Accounting','PrepressManager'], $openprint::session{user_id} );
	return 0;
} # end sub can_see_pricing

sub can_edit {
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if $_[0]{user_id} == $openprint::session{user_id};
	return 1 if $_[0]{company_id} == $openprint::session{company_id};
	return 1 if $_[0]{salesrep_id} == $openprint::session{user_id};
	return 1 if openprint::usergroup::is_user_in( ['Prepress','Sales Admin','PrepressManager'], $openprint::session{user_id} );
	return 0;
}
sub can_delete {
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if $_[0]{user_id} == $openprint::session{user_id};
	return 1 if $_[0]{company_id} == $openprint::session{company_id};
	return 1 if $_[0]{salesrep_id} == $openprint::session{user_id};
	return 1 if openprint::usergroup::is_user_in( ['Prepress','Sales Admin','PrepressManager'], $openprint::session{user_id} );
	return 0;
}
sub can_destroy {
	return 1 if $openprint::session{user_type} eq 'A';
	return 0;
}

sub due_date {
	if ( ! $_[0]{due_date} ) {
		foreach my $Project( $_[0]->Projects() ) {
			$_[0]{due_date} = $Project->due_date();
			last if $_[0]{due_date};
		} # end foreach Project
	} # end if
	return $_[0]{due_date};
} # end sub due_date

sub url_to {
	return '/main/order/history_details.html?order_id='.$_[0]{id};
} # end sub url

sub link_to {
	if ( $_[0]{id} ) {
		my $text = $_[1] ? $_[1] : ( $_[0]{id} ? $_[0]{id} : 'id ' . $_[0]{id} );
		return sprintf('<a href="/main/order/history_details.html?order_id=%d">%s</a>', $_[0]{id}, $text );
	}
	return '';
} # end sub link_to

sub production_link_to {
	if ( $_[0]{id} ) {
		my $text = $_[1] ? $_[1] : ( $_[0]{id} ? $_[0]{id} : 'id ' . $_[0]{id} );
		return sprintf('<a href="/employee/project/view.html?order_id=%d">%s</a>', $_[0]{id}, $text );
	}
	return '';
} # end sub link_to

sub company_name {
	if ( @_ > 1 ) {
		$_[0]{company_name} = $_[1];
	} else {
		if ( ! $_[0]{company_name} ) {
			if ( $_[0]{company_id}  ) {
				$_[0]{company_name} = $_[0]->Company()->name();
			} # end if
		} # end if
	} # end if
	return $_[0]{company_name};
}
sub firstname {
	if ( @_ > 1 ) {
		$_[0]{firstname} = $_[1];
	} else {
		if ( ! $_[0]{firstname} ) {
			if ( $_[0]{user_id}  ) {
				$_[0]{firstname} = $_[0]->User()->firstname();
			} # end if
		} # end if
	} # end if
	return $_[0]{firstname};
}
sub lastname {
	if ( @_ > 1 ) {
		$_[0]{lastname} = $_[1];
	} else {
		if ( ! $_[0]{lastname} ) {
			if ( $_[0]{user_id}  ) {
				$_[0]{lastname} = $_[0]->User()->lastname();
			} # end if
		} # end if
	} # end if
	return $_[0]{lastname};
}

sub address_html {
  my ( $self ) = @_;
  return join('<br/>', 
    ( map { $$self{$_} ? ssi::html_escape( $$self{$_} ) : () } ( 'address1','address2' ) ),
    join(', ', map { $self->$_() ? $self->$_() : () } ( 'city','state','postalcode' ) ),
    ( map { $self->$_() ? $countries::countries{$$self{$_}} : () } ( 'country' ) ),
  );
}

sub deposit_due {
	my $Order = shift;

	if (
			($Order->status() ne 'Cancelled')
			and
			$Order->downpayment()
			and
			( $Order->paid() < $Order->downpayment())
		 ) {
    return Math::Round::nearest(0.01, $Order->downpayment() - $Order->paid());
  } # end if
	return 0;
} # end sub deposit_due

sub close {
	my $Order = shift;
	$Order->subtotal(undef);
	foreach my $Tax ( $Order->Taxes() ) {
		$Tax->save({ amount => undef });
	} # end foreach Tax
	$Order->total(undef);
	$Order->status('In Production');
	$Order->save();
	$Order->add_log('Close Order');
	foreach my $OP ( $Order->Ordered_Projects() ) {
		my $Project = $OP->Project();
		sql::update( $log, $dbh, 'tbl_Project_Contents', ["lngProjectIndex=? AND strStatus NOT IN ( 'Complete', 'Approved', 'Proofs Out', 'Waiting For Customer Approval','Waiting For QA Approval','')", $Project->id()], 'strStatus', 'Ordered' );
		if ( $Project->docket() != $Order->docket() ) {
			$Project->save({docket=>$Order->docket()});
		}
		$Project->update_status();
	}
	foreach my $Product ( $Order->Products() ) {
		if ( $$Product{project_id} ) {
			my $Project = $Product->Project();
			sql::update( $log, $dbh, 'tbl_Project_Contents', ["lngProjectIndex=? AND strStatus NOT IN ( 'Complete', 'Approved', 'Proofs Out', 'Waiting For Client Approval','Waiting For QA Approval','')", $Project->id()], 'strStatus', 'Ordered' );
			$Project->update_status();
		}
	}
	$Order->update_status();
} # end sub close

sub is_fsc {
	my $self = shift;
	foreach my $Project ( $self->Projects() ) {
		return 1 if $Project->is_fsc();
	}
	return 0;
}

1;
__END__
