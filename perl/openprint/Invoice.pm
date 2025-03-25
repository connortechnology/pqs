use strict;
require Math::Round;
package openprint::Invoice;
our @ISA = qw(openprint::Object);

use vars qw( %config $log %session );
*session = \%openprint::session;
*config = \%openprint::config;
*log = \$openprint::log;

require openprint::Currency;
require openprint::Company;
require openprint::Service;
require openprint::Tax;
require openprint::Invoiced_Product;
require openprint::Invoiced_Project;
require openprint::Invoice_Interest;
require openprint::Invoice_Payment;
require openprint::Invoice_Tax;
require openprint::Timetrack;
require openprint::Object_Asset;
require openprint::Order_Invoice;

use vars qw( $debug $table $serial %fields %find_fields %defaults %transforms );

$debug = 1;

$table = 'invoices';
$serial = 'invoices_id_seq';

%fields = (
	id				=>	'id',
	invoicer_id		=>	'invoicer_id',
	invoicee_id		=>	'invoicee_id',
	external_notes	=>	'external_notes',
	internal_notes	=>	'internal_notes',
	posted			=>	'posted',
	subtotal		=>	'subtotal',
	subtotal_override		=>	'subtotal_override',
	total			=>	'total',
	total_override		=>	'total_override',
	due_on			=>	'due_on',
	posted_on		=>	'posted_on',
	created_on		=>	'created_on',
	updated_on		=>	'updated_on',
	deleted			=>	'deleted',
	currency_id		=>	'currency_id',
	paid				=>	'paid',
	interest			=>	'interest',
	bad_debt			=>	'bad_debt',
	num					=>	'num',
	monthly_interest	=>	'monthly_interest',
	late_payment_units	=>	'late_payment_units',
	early_payment_date	=>	'early_payment_date',
	early_payment_amount	=>	'early_payment_amount',
	early_payment_units		=>	'early_payment_units',
);

%find_fields = (
	po		=>	'(SELECT po FROM invoiced_products WHERE invoiced_products.invoice_id = invoices.id)',
	sent_on	=>	q`(SELECT date_time FROM logs WHERE object_id=invoices.id AND object_type_id=(SELECT id FROM Object_Types WHERE name='openprint::Invoice') AND action_id=(SELECT id FROM Log_Actions WHERE name='Invoice Sent') LIMIT 1)`,
	product_id	=>	'(SELECT product_id FROM invoiced_products WHERE invoice_id=invoices.id)',
);

%transforms = (
	num			=>	[ 's/^\s+//', 's/\s+$//' ],
);
%defaults = (
	created_on	=> q`'NOW()'`,
	updated_on	=> q`'NOW()'`,
	deleted		=> 0,
	posted		=> 0,
	interest		=> undef,
	monthly_interest	=> undef,
	paid			=> undef,
	bad_debt		=> 0,
	late_payment_units		=>	undef,
	early_payment_amount	=>	undef,
	early_payment_units		=>	undef,
	early_payment_date		=>	undef,
	num						=>	undef,
	due_on					=>	undef,
	subtotal_override		=>	0,
	total_override		=>	0,
);

sub save {
	my ( $self, $param ) = @_;

	$self->set( $param ? $param : {} );

	my $rc;
	# none of these should be set by param ( however employee_accounting will pass in a total if specified.. FIXME
	$$self{subtotal} = $self->subtotal( undef ) if $$self{id} and ! $$self{subtotal_override};
  #$self->Taxes( undef );
	$$self{total} = $self->total( undef ) if $$self{id} and ! $$self{total_override};

	$rc .= $self->SUPER::save( );
	if (!$rc) {
		foreach my $T ( $self->Taxes() ) {
      $T->amount(undef);
			$rc .= $T->save({invoice_id=>$$self{id}});
		} # end foreach
		$self->Invoicee()->save({last_invoice_id=>$$self{id}}) if $self->Invoicee()->last_invoice_id != $$self{id};
	} # end if
	return $rc;
} # end sub save

sub is_paid {
	my ( $self ) = @_;
	if ( ! $$self{posted} ) {
		$openprint::log->debug("Invoice $$self{id} ! is_paid because ! posted") if $debug;
		return 0;
	} # end if
	if ( $debug ) {
		$openprint::log->debug("Invoice $$self{id} owing is " . $self->owing() );
	}
	return $self->owing() > 0 ? 0 : 1;
} # end sub is_paid

sub owing {
  if ( $_[0]->paid_early() >= $_[0]->owing_early() ) {
    return 0;
  }
#$log->debug("Owing total: " . $_[0]->total() . ' int: ' . $_[0]->interest() . ' paid: ' . $_[0]->paid() );
	return Math::Round::nearest( 1/(10**$_[0]->Currency()->precision()), $_[0]->total() + $_[0]->interest() - $_[0]->paid() );
} # end sub owing

sub owing_early {
  my $self = shift;
	my $owing = $self->total() + $self->interest();
  my $owing_early;
	if ( $$self{early_payment_units} eq 'amount' ) {
		$owing_early = Math::Round::nearest(1/(10**$self->Currency()->precision()), $$self{early_payment_amount} - $self->paid());
	} elsif ( $$self{early_payment_units} eq 'percent' ) {
    $owing_early = Math::Round::nearest(1/(10**$self->Currency()->precision()), ($owing * ( 1 - $$self{early_payment_amount}/100) - $self->paid()));
	} elsif ($$self{early_payment_units}) {
    $openprint::log->error('Unknown units for early_payment ('.$$self{early_payment_units}.')');
		$owing_early = Math::Round::nearest(1/(10**$self->Currency()->precision()), $owing);
  } else {
    $owing_early = 0;
	} # end if
  $openprint::log->debug("owing_early = $owing_early = owing: $owing = $$self{total} + $$self{interest} - $$self{paid}");
  return $owing_early;
} # end sub owing

sub Invoicee {
	return new openprint::Company( $_[0]->invoicee_id() );
} # end sub Invoicee

sub Invoicer {
	return new openprint::Company( $_[0]->invoicer_id() );
} # end sub Invoicer

sub subtotal {
	my ( $self ) = @_;

	if ( @_ > 1 ) {
$openprint::log->debug("Setting subtotal to $_[1]") if $debug;
		$$self{subtotal} = $_[1];
	}

	if ( ! $$self{id} ) {
		$log->error('Invoice:subtotal no id! ref:' . (ref $self) . ' self:' . $self);
#cluck('Invoice:subtotal no id! ref:' . (ref $self) . ' self:' . $self);
		return;
	} # end if

	if ( ( (!$$self{posted}) or ( ! defined $$self{subtotal} ) ) and ( ! $$self{subtotal_override} ) ) {
$log->debug("Recalculating subtotal") if $debug;
		$$self{subtotal} = 0;
		foreach my $T ( openprint::Timetrack->find( invoice_id=>$$self{id} ) ) {
			$$self{subtotal} += $T->value();
$log->debug('T value: ' . $T->value() . ' subtotal: '.$$self{subtotal}) if $debug;
		} # end foreach
		foreach my $P ( $self->Products() ) {
			$$self{subtotal} += $P->total();
$log->debug('P value: ' . $P->total() . ' subtotal: '.$$self{subtotal} ) if $debug;
		}# end foreach P
		foreach my $O ( $self->Orders() ) {
			$$self{subtotal} += $O->Order()->subtotal();
$log->debug('O value: ' . $O->Order()->subtotal() . ' subtotal: '.$$self{subtotal});
		}# end foreach P
	} # end if
	return Math::Round::nearest(1/(10**$self->Currency()->precision()), $$self{subtotal});
} # end sub subtotal

sub total {
	my ( $self ) = @_;

	if ( ! $$self{id} ) {
		return;
	} # end if

	if ( @_ > 1 ) {
		$$self{total} = $_[1];
	}

	if ( ( (!$$self{posted}) or ( ! defined $$self{total} ) ) and ( ! $$self{total_override} ) ) {
		$$self{total} = $self->subtotal();
		foreach my $Tax ( $self->Taxes() ) {
			$$self{total} += $Tax->amount();
$log->debug("tax $$Tax{amount} toal: $$self{total}");
		} # end foreach Tax
	} # end if
	return Math::Round::nearest( 1/(10**$self->Currency()->precision()), $$self{total} );
} # end sub total

sub interest {
	my ( $self ) = @_;
	if ( @_ == 2 ) {
		$$self{interest} = $_[1];
	} # end if

	if ( (!$$self{posted}) or ( ! defined $$self{interest} ) ) {
		$$self{interest} = misc::sum( map { $_->amount() } openprint::Invoice_Interest->find( invoice_id=>$$self{id}) );
	} # end if
	return $$self{interest};
} # end sub interest

sub paid {
	my $self = shift;
	if ( @_ ) {
		$$self{paid} = $_[0];
    $openprint::log->debug("Setting paid to $_[0]");
	} # end if
	if ( (!$$self{posted}) or !defined($$self{paid})) {
    # Amount is stored both in the invoice_payment and in the payment
    # Maybe the value in the invoice_payment record should be currency adjusted
		$$self{paid} = misc::sum( map { $_->amount() } openprint::Invoice_Payment->find( invoice_id=>$$self{id}) );
    $openprint::log->debug("Loaded $$self{paid}");
  } else {
    $openprint::log->debug("Posted: $$self{posted} or defined $$self{paid}");
	} # end if
	return $$self{paid};
} # end sub paid

sub paid_early {
  my $self = shift;
  return 0 if !$$self{early_payment_date};
  $$self{paid_early} = misc::sum(
    map { $_->amount() } openprint::Invoice_Payment->find(
      invoice_id=>$$self{id},
      'received_on <=' => $$self{early_payment_date}.' 23:59:59',
    )
  );
  return $$self{paid_early};
}

sub paid_value {
	my $self = shift;
	if ( @_ ) {
		$$self{paid_value} = $_[0];
	} # end if
	if ( (!$$self{posted}) or !defined $$self{paid_value} ) {
    # Amount is stored both in the invoice_payment and in the payment
    # Maybe the value in the invoice_payment record should be currency adjusted
		$$self{paid_value} = misc::sum( map { $_->value() } openprint::Invoice_Payment->find( invoice_id=>$$self{id}) );
	} # end if
	return $$self{paid_value};
} # end sub paid_value

sub add_Payment {
	my ( $self, $Payment ) = @_;
	if ( $Payment->remaining() ) {
		if ( $self->owing() ) {
			my $error;
			my $amount = $Payment->remaining() > $self->owing() ? $self->owing() : $Payment->remaining();
			my $IP = new openprint::Invoice_Payment();
			$error .= $IP->save({ payment_id=>$Payment->id(), invoice_id=>$$self{id}, amount=>$amount });
			$error .= $Payment->save( { remaining => undef } );
			$self->paid( undef );
			$error .= $self->save();
			return $error;
		} else {
			return 'Invoice is already paid.';
		} # end if
	} elsif ( ! $Payment->remaining() ) {
		return 'No money left in payment.';
	} elsif ( ! $self->owing() ) {
		return 'Nothing owing in invoice.';
	} # end if
} # end sub add_Payment

sub del_Payment {
	my ( $self, $Payment ) = @_;

	foreach my $IP ( openprint::Invoice_Payment->find('invoice_id'=>$$self{id},'payment_id'=>$$Payment{id})) {
		$IP->delete();
	} # endforeach$IP
	$Payment->remaining( undef );
	$Payment->save();
	$self->paid( undef );
	$self->save();
} # end sub del_Payment

sub Payments {
	my ( $self ) = @_;
  if ( ! $_[0]{Payments} ) {
    $_[0]{Payments} = [ openprint::Invoice_Payment->find( invoice_id=>$$self{id} ) ];
  }
  return @{$_[0]{Payments}};
} # end sub Payments

sub Logs {
	return openprint::Log->find(object_id=>$_[0]{id},object_type=>'openprint::Invoice', order=>'date_time');
} # end sub Logs

sub email_html {
  my $self = shift;
  my %data = (
    Invoice => $self,
    uri => 'invoice',
    Currency	=>	$self->Currency(),
  );
  my $skin_path = '';
  if ( -e ($openprint::config{SkinPath}.'/'.$self->Invoicer()->name()) ) {
    $skin_path = '/'.$self->Invoicer()->name();
    $openprint::log->debug("Have skinpath at $skin_path");
  } else {
    $openprint::log->debug('Have no skinpath at ' . $openprint::config{SkinPath}.'/'.$self->Invoicer()->name());
  }
  $data{SkinPath} = $skin_path;
  my $invoice_template = ssi::slurp_content($skin_path.'/invoice_template.html');
  $invoice_template = ssi::slurp_content('/invoice_template.html') if ! $invoice_template;
  $data{ReplacementText} = ssi::include('/email_content/invoice.html', \%data);
  my $invoice_html = ssi::variable_substitution(\$invoice_template, \%data);
  return $invoice_html;
}

sub send {
	my ( $self, $To ) = @_;

  my @To = $To ? ($To) : $self->Invoicee()->AccountingContacts();
  return 'No one to send to!' if ! @To;

	my $Email = new openprint::Email();

	my %data = (
			Invoice => $self,
			uri => 'invoice',
			Currency	=>	$self->Currency(),
	);

  my $skin_path = '';
  if ( -e ($openprint::config{SkinPath}.'/'.$self->Invoicer()->name()) ) {
    $skin_path = '/'.$self->Invoicer()->name();
    $openprint::log->debug("Have skinpath at $skin_path");
  } else {
    $openprint::log->debug("Have no skinpath at " . $openprint::config{SkinPath}.'/'.$self->Invoicer()->name() );
  }
  $data{SkinPath} = $skin_path;

	my $email_template = ssi::slurp_content($skin_path.'/email_template.html');
	$email_template = ssi::slurp_content('/email_template.html') if ! $email_template;

  my $invoice_template = ssi::slurp_content($skin_path.'/invoice_template.html');
  $invoice_template = ssi::slurp_content('/invoice_template.html') if ! $invoice_template;

	my @attachments;
	$data{ReplacementText} = ssi::include($skin_path.'/email_content/invoice_body.html', \%data);
	$data{ReplacementText} = ssi::include('/email_content/invoice_body.html', \%data) if ! $data{ReplacementText};
  $Email->html_body( ssi::variable_substitution( \$email_template, \%data ) );

	$data{ReplacementText} = ssi::include('/email_content/invoice.html', \%data);
	my $invoice_html = ssi::variable_substitution(\$invoice_template, \%data);
  $Email->add_pdf_attachment_from_html('Invoice'.$self->num(), $invoice_html);

  my @AccountingContacts = $self->Invoicer()->AccountingContacts();
  my $from = @AccountingContacts ? $AccountingContacts[0]->email() : $config{AccountingEmail};

	$Email->add_html_attachment("Invoice".$self->num().'.html', $invoice_html) if $To and (($To->email() =~ /^iconnor/) or ($To->email() =~ /^isaac/));
	my $results = $Email->send(
		BCC			=>	$openprint::User,
		#TO			=>	new openprint::User( $session{user_id} ),
		TO			=>	( $To ? $To : [$self->Invoicee()->AccountingContacts()] ),
		FROM		=>	$from,
		ATTACHMENTS	=>	\@attachments,
		SUBJECT		=>	sprintf('%1$s Invoice (%2$s) is now available.', $self->Invoicer()->name(), $self->num()),
    'Return-Receipt-To' => $from,
	);
	(new openprint::Log())->save({Object=>$self, action=>'Invoice Sent', note=>$results});
	return $results;
} # end sub send

sub Products {
  my $self = shift;
  $$self{Products} = shift if @_;
  if ( ! $$self{Products} ) {
    $$self{Products} = [ openprint::Invoiced_Product->find(invoice_id=>$$self{id}, order=>'id') ];
  }
  return @{$$self{Products}};
} # end sub Products

sub Projects {
	return openprint::Invoiced_Project->find(invoice_id=>$_[0]{id}, order=>'id');
} # end sub Projects
sub Orders {
	return openprint::Order_Invoice->find(invoice_id=>$_[0]{id}, order=>'order_id');
} # end sub Orders

sub Interests {
	my $self = shift;
	my %args = @_;
	$args{invoice_id} = $$self{id};
	$args{order} = 'compounded_on' if ! $args{order};
	return openprint::Invoice_Interest->find(%args);
} # end sub Interests

sub calculate_interests {
	my $Invoice = shift;
  my $error = '';

  if ( ! $Invoice->monthly_interest() ) {
    $error .= 'Invoice has no monthly interest rate!';
  } elsif ( ! $Invoice->due_on() ) {
    $error .= 'Invoice has no due date!';
  } # end if

  my $changed = 0;

  my ( $year, $month, $day ) = $Invoice->due_on() =~ /(\d\d\d\d)-(\d\d)-(\d\d)/;
  my $last_period;
  my $paid = 0;
  #( $year, $month, $day ) = Date::Calc::Add_Delta_Days( $year, $month, $day, Date::Calc::Days_in_Month( $year, $month ) );
  while ( Date::Calc::Date_to_Time($year, $month, $day, 0, 0, 0) <= time ) {

    my $date_string = sprintf('%4d-%.2d-%.2d', $year, $month, $day);

    # The point is to calculate how much has been paid by this point
    foreach my $P ( openprint::Invoice_Payment->find(
        invoice_id=>$Invoice->id(),
        ($last_period ? ('received_on >'=>$last_period) : () ),
        'received_on <='=>$date_string )) {
      $paid += $P->amount();
    } # end foreach

    # Includes tax
    my $total = $Invoice->total();
    foreach my $I ( openprint::Invoice_Interest->find(invoice_id=>$Invoice->id(), 'compounded_on <'=>$date_string )) {
      $total += $I->amount();
    } # end foreach InvoiceInterest

    if ( ($total - $paid) > 0 ) {
      if ( ! openprint::Invoice_Interest->find(invoice_id=>$Invoice->id(), compounded_on=>$date_string) ) {
        # If not interest already applied for this period, apply it
        my $I = new openprint::Invoice_Interest();
        $_ = $I->save({
            invoice_id    =>  $Invoice->id(),
            amount        =>  Math::Round::nearest(.01, ($total - $paid) * $Invoice->monthly_interest()/100),
            compounded_on =>  $date_string,
            });
        if ( ! $_ ) {
          my $note = sprintf('Added %s%.2f interest for %s', $Invoice->Currency()->symbol(), $I->amount(), $date_string);
          (new openprint::Log())->save({
            Object  =>  $Invoice,
            note    =>  $note,
            action  =>  'Invoice Interest Added'});
          $error .= $note.' for invoice ' . $Invoice->id().'<br/>';
        } else {
          $error .= $_;
          last;
        } # end if
        $changed = 1;
      } # end if No interest for this date.
    } else {
      last;
    } # end if No interest for this date.
    $last_period = $date_string;
    ($year, $month, $day) = Date::Calc::Add_Delta_Days($year, $month, $day, Date::Calc::Days_in_Month($year, $month));
  } # end while

  if ( $changed ) {
    delete $$Invoice{interest};
    $Invoice->interest();
    $Invoice->save();
  } # end if

  return $error;

} # end sub calculate_interests

sub tax {
  my $self = shift;
  if ( ! $$self{tax} ) {
    $$self{tax} = 0;
    foreach my $T ( $self->Taxes() ) {
      $$self{tax} += $T->amount();
    }
  }
  return $$self{tax};
}

sub Taxes {
	my ( $self ) = @_;

	if ( @_ > 1 and ! defined $_[1] ) {
		if ( $$self{id} ) {
			foreach ( openprint::Invoice_Tax->find( invoice_id=>$$self{id} ) ) {
				$_->destroy();
			} # end foreach	Tax
		}
		$$self{Taxes} = [];
	} # end if

	if (!$$self{Taxes}) {
		@{$$self{Taxes}} = $$self{id} ? openprint::Invoice_Tax->find( invoice_id=>$$self{id} ) : ();
	} # end if

	if ( ! ( $$self{Taxes} and @{$$self{Taxes}} ) ) {
		$$self{Taxes} = [];
		foreach my $Tax ( openprint::Tax->find(
					'period_start null_or_<='	=>	$$self{created_on},
					'period_end null_or_>='		=>	$$self{created_on},
					country	=>	$self->Invoicee()->country(),
					state	=>	$self->Invoicee()->state()),
				) {
			my $T = new openprint::Invoice_Tax();
			$T->set({
				tax_id	=>	$$Tax{id},
				rate 		=>	$$Tax{rate},
        charge  =>  1,
			});
			$T->save({ invoice_id	=>	$$self{id} } ) if $$self{id};
			push @{$$self{Taxes}}, $T;
		} # end foreach Tax
	} # end if
	return @{$$self{Taxes}};
} # end sub Taxes

sub Tax {
	my ( $self, $Tax ) = @_;
	if ( ! $_[0]{Taxes} ) {
		@{$_[0]{Taxes}} = openprint::Invoice_Tax->find( invoice_id=>$_[0]{id} );
	} # end if

	foreach my $IT ( @{$_[0]{Taxes}} ) {
		if ( $$IT{tax_id} == $$Tax{id} ) {
			return $IT;
		}
	} # end if
	return new openprint::Invoice_Tax();
} # end sub Tax

sub num {
	if ( @_ > 1 ) {
		$_[0]{num} = $_[1];
	}
	if ( ! $_[0]{num} ) {
		$_[0]{num} = $_[0]{id};
	} # end if
	return $_[0]{num};
} # end sub num

sub can_edit {
	return 1;
} # end sub can_edit

sub can_view {
	if ( $openprint::session{user_type} eq 'A' ) {
    return 1;
	}
  my $self = shift;
  if ( $openprint::User->company_id() == $$self{invoicer_id} ) {
    return 1;
  } else {
    $openprint::log->debug("No invoicer: $$openprint::User{company_id} != $$self{invoicer_id}");
  }
  if ( $openprint::User->company_id() == $$self{invoicee_id} ) {
    return 1;
  } else {
    $openprint::log->debug("Not invoicee: $$openprint::User{company_id} != $$self{invoicee_id}");
  }
	if ( $openprint::session{user_type} eq 'E' ) {
		if ( $self->Invoicee()->salesrep_id() == $openprint::session{user_id} ) {
			return 1;
		}
	}
	return 0;
} # end sub can_view

sub can_send {
	my $User = $_[1] ? $_[1] : $openprint::User;

	if ( $$User{type} eq 'A' ) {
		$log->debug("$$User{firstname} Is administrator") if $debug;
		return 1;
	} # end if

	if ( openprint::usergroup::is_user_in( ['Accounting'], $$User{id} ) )  {
		$log->debug("$$User{firstname} Is in Accounting'") if $debug;
		return 1;
	} # end i
	return 0;
} # end sub can_send

sub upload {
	openprint::Object_Asset::upload( @_ );
} # end sub upload

sub url_to {
	return '/invoice/view.html?invoice_id='.$_[0]{id};
}

sub link_to {
	if ( $_[0]{id} ) {
		my $text = $_[1] ? $_[1] : ( $_[0]{num} ? $_[0]{num} : 'id ' . $_[0]{id} );
		return sprintf('<a href="/invoice/view.html?invoice_id=%d">%s</a>', $_[0]{id}, $text );
	}
	return '';
} # end sub link_to

sub Pricelist {
	return $_[0]->Invoicee()->Pricelist();
} # end sub Pricelist

sub paid_on {
  if ( ! $_[0]{paid_on} ) {
    foreach my $Invoice_Payment ( reverse sort { $a->Payment()->received_on() cmp $b->Payment()->received_on() } $_[0]->Payments() ) {
      $log->debug( $Invoice_Payment->Payment()->to_string() );
      $_[0]{paid_on} = $Invoice_Payment->Payment()->received_on();
    }
  }
  return $_[0]{paid_on};
} # end sub paid_on

sub Currency {
  my $self = shift;
  if ( ! $$self{Currency} ) {
    $$self{Currency} = new openprint::Currency($$self{currency_id});
  }
  return $$self{Currency};
} # end sub Currency

sub first_sent_on {
	if ( ! exists $_[0]{first_sent_on} ) {
		if ( my $Log = openprint::Log->find_one(
					object_id=>$_[0]{id},
					object_type=>'openprint::Invoice', 
					action=>'Invoice Sent',
					order	=>	'id ASC',
					) ) {
			$_[0]{first_sent_on} = $Log->date_time();
		}
	} # end ! exists first_sent_on
	return $_[0]{first_sent_on};
} # end sub first_sent_on

sub paid_days {
  my $sent = $_[0]->first_sent_on();
  if ( ! $sent ) {
    $openprint::log->debug('No sent');
    return;
  }

  my $paid_time = $_[0]{paid_on} ? Date::Parse::str2time($_[0]{paid_on}) : time;
  my $sent_time = Date::Parse::str2time($sent);
  my $days = int( ($paid_time-$sent_time) / 86400 );
  return $days;
}

sub sent_on {

  if ( ! $_[0]{sent_on} ) {
    ( $_[0]{sent_on} ) = sql::execute( undef, undef, q`
      SELECT MIN(date_time) FROM logs WHERE object_id=?
      AND object_type_id=(SELECT id FROM Object_Types WHERE name='openprint::Invoice') 
      AND action_id=(SELECT id FROM log_actions WHERE name='Invoice Sent') 
      LIMIT 1`, $_[0]{id});
  }
  return $_[0]{sent_on};
}

sub is_early {
  return 0 if ! $_[0]->early_payment_amount();
  my $early_payment_time = Date::Parse::str2time($_[0]->early_payment_date());
  my $today = Date::Calc::Date_to_Time(Date::Calc::Today(), (0,0,0));
  $openprint::log->debug("is_early: early_time $early_payment_time, today $today : " . ($early_payment_time > $today));
  return ($early_payment_time > $today);
}

1;
__END__
