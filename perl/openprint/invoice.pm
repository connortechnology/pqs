use strict;
package openprint::invoice;

use openprint ();
use vars qw( $r %variable %session %param %config $log $dbh );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

require Math::Round;

require openprint::Invoice;
require openprint::Invoice_Interest;
require openprint::Tax;
require openprint::Bitcoin_Address;

sub history {
	my $uri = $r->uri();

	if ( $param{btnFunction} ) {
		if ( $param{btnFunction} eq 'Send' ) {
			my $Invoice = openprint::Invoice->find_one(id=>$param{invoice_id});
			if ( ! $Invoice ) {
				$variable{error} .= "Invoice $param{invoice_id} not found";
			} elsif ( ! $Invoice->can_send() ) {
				$variable{error} .= 'You are not authorized to send this invoice.<br/>';

			} else {
				$variable{error} .= $Invoice->send();
				$variable{information} .= 'Invoice ' . $Invoice->id() . ' sent.<br/>';
				$variable{ExternalRedirect} = '/invoice/history.html';
				return;
			} # end if
		} elsif ( $param{btnFunction} eq 'Send To Me' ) {
			my $Invoice = openprint::Invoice->find_one(id=>$param{invoice_id});
			if ( ! $Invoice ) {
				$variable{error} .= "Invoice $param{invoice_id} not found";
			} else {
				$variable{error} .= $Invoice->send($openprint::User);
				$variable{information} .= 'Invoice ' . $Invoice->id() . ' sent.<br/>';
			} # end if
			$variable{ExternalRedirect} = '/invoice/history.html';
			return;
		} elsif ( $param{btnFunction} eq 'Download' ) {
			_history();
			my @Taxes = @{$variable{Taxes}};

			my @Header = ('ID','Created On','Posted On', 'First Sent On', 'Due On','Invoicer','Invoicee', 'SubTotal',
					( map { sprintf('%s (%d%)', $_->name(), $_->rate() ) } @Taxes ),
					'Total','Interest','Owing');
			my @Data;

			my ($subtotal, $interest_total, $total, $owing_total, %tax_totals );

			foreach my $Invoice ( @{$variable{Invoices}} ) {
				push @Data, $Invoice->id(), 
        ssi::format_csv_datetime($Invoice->created_on()),
        ssi::format_csv_datetime($Invoice->posted_on()),
        ssi::format_csv_datetime($Invoice->first_sent_on()),
        ssi::format_csv_date($Invoice->due_on()),
        $Invoice->Invoicer()->name(),
        $Invoice->Invoicee()->name(),
        $Invoice->subtotal(), 
        ( map { $Invoice->Tax( $_ )->amount() } @Taxes ),
        $Invoice->total(), $Invoice->interest(), $Invoice->owing();
        $subtotal += $Invoice->subtotal();
        $owing_total += $Invoice->owing();
        foreach my $Tax ( @Taxes ) {
          $Tax->charge(1*$param{'tax_charge-'.$Tax->tax_id()}) if $Tax->charge() != 1*$param{'tax_charge-'.$Tax->tax_id()};
          $tax_totals{$Tax->id()} += $Invoice->Tax($Tax)->amount();
        }
        $total += $Invoice->total();
			} # end foreach Invoice
			push @Data, 'Totals:', '', '', '', '', '', '', $subtotal, ( map { $tax_totals{$_->id()} } @Taxes ), $total, $interest_total, $owing_total;

			misc::export_csv( $r, $log, \%variable, 'invoices.csv', \@Header, \@Data );
		} elsif ( $param{btnFunction} eq 'Account Statement' ) {
			_history();

      my $Invoicer = openprint::Company->find_one(id=>$session{'/invoice/history.html?invoicer_id'});
      if ( !$Invoicer ) {
        $variable{error} .= 'Invoicer not found.';
        return;
      }

      my $Email = new openprint::Email();

      my $skin_path = '';
      if ( -e ($openprint::config{SkinPath}.'/'.$Invoicer->name()) ) {
        $skin_path = '/'.$Invoicer->name();
        $openprint::log->debug("Have skinpath at $skin_path");
      } elsif ( -e ($ENV{DOCUMENT_ROOT}.'/'.$Invoicer->name()) ) {
        $skin_path = $ENV{DOCUMENT_ROOT}.'/'.$Invoicer->name();
        $openprint::log->debug("Have skinpath at $skin_path");
      } else {
        $openprint::log->debug('Have no skinpath at '.$openprint::config{SkinPath}.'/'.$Invoicer->name());
      }


      my $invoice_template = ssi::slurp_content($skin_path.'/invoice_template.html');
      $invoice_template = ssi::slurp_content('/invoice_template.html') if ! $invoice_template;

			my %data;
      $data{uri} = 'invoice';
      $data{Invoicer} = $Invoicer;

      my @Sent_Invoices;

			my @Invoices = openprint::Invoice->find(
					ssi::date_filter($uri.'?created_on_start', 'created_on >=' ),
					ssi::date_filter($uri.'?created_on_end', 'created_on >=' ),
					invoicee_id => $session{$uri.'?invoicee_id'},
					invoicer_id => $session{$uri.'?invoicer_id'},
          posted      => 1,
					order       => 'id',
					);
			foreach my $Invoice ( @Invoices ) {
				next if $Invoice->is_paid();
				next if $Invoice->bad_debt();
				next if ! $Invoice->posted();
				next if ! $Invoice->can_send();

				$data{Invoice} = $Invoice;

				$data{ReplacementText} = ssi::include('/email_content/invoice.html', \%data);
        $Email->add_pdf_attachment_from_html(
          'Invoice '.$$Invoice{id}, 
          ssi::variable_substitution(\$invoice_template, \%data)
        );
        push @Sent_Invoices, $Invoice;
			} # end foreach Invoice

			if ( !@Sent_Invoices ) {
				$variable{error} .= 'There were no invoices to include in this statement.';
				if ( @Invoices ) {
					$variable{error} .= 'You may not be authorized to send them.';
				}
				return;
			}
      $data{Invoices} = \@Sent_Invoices;

      my $email_template = ssi::slurp_content($skin_path.'/email_template.html');
      $email_template = ssi::slurp_content('/email_template.html') if ! $email_template;
			$data{ReplacementText} = ssi::include('/email_content/account_statement.html', \%data);
      $Email->html_body(ssi::variable_substitution(\$email_template, \%data));

			my @Recipients = new openprint::Company($param{invoicee_id})->AccountingContacts();
			$Email->send(
						FROM    => $config{AccountingEmail},
            TO      =>  \@Recipients,
            #TO      => $openprint::User,
						BCC     => $openprint::User,
						SUBJECT => 'Account Statement from ' . ( $Invoicer->name() ),
						);
			$variable{information} .= 'Account statement sent to ' . join('<br/>',
					map { sprintf('&quot;%s %s&quot; &lt;%s&gt;',$_->get('firstname','lastname','email')) } @Recipients);
		} elsif ( $param{btnFunction} eq 'Calculate Interest' ) {
			_history();
      foreach my $Invoice ( @{$variable{Invoices}} ) {
        next if $Invoice->is_paid();
        next if $Invoice->bad_debt();
        $variable{error} .= $Invoice->calculate_interests();
      }
      $variable{ExternalRedirect} = '/invoice/history.html';
		} # end if btnfunction

	} # end if btnFunction
	ssi::setup_date_select($uri, 'created_on_start', -60);
	ssi::setup_date_select($uri, 'created_on_end', '');
	ssi::setup_date_select($uri, 'due_on_start', -60);
	ssi::setup_date_select($uri, 'due_on_end', '');

	$session{$uri.'?paid'} = '' if (!exists $session{$uri.'?paid'}) or ! sets::isin($session{$uri.'?paid'}, [0,1,'']);
	$session{$uri.'?bad_debt'} = '' if (!exists $session{$uri.'?bad_debt'}) or ! sets::isin($session{$uri.'?bad_debt'}, [0,1,'']);
	$session{$uri.'?employee_id'} = $session{user_id} if ! exists $session{$uri.'?employee_id'};

	_history();
} # end sub history

sub _history {
  my $uri = '/invoice/history.html';

  ssi::save_params($uri, ( 
      ( map { 'created_on_start_'.$_ } ( 'year','month','day' ) ),
      ( map { 'created_on_end_'.$_ } ( 'year','month','day' ) ),
      ( map { 'due_on_start_'.$_ } ( 'year','month','day' ) ),
      ( map { 'due_on_end_'.$_ } ( 'year','month','day' ) ),
      ( map { 'paid_on_start_'.$_ } ( 'year','month','day' ) ),
      ( map { 'paid_on_end_'.$_ } ( 'year','month','day' ) ),
      'paid','invoicee_id','bad_debt','product_id', 'invoicer_id', 'currency_id' ) );

  $variable{subtotal} = $variable{total} = $variable{interest_total} = $variable{owing_total} = $variable{owing_total_value} = 0;
  $variable{Taxes} = [ openprint::Tax->find(
      ssi::date_filter($uri.'?created_on_end', 'period_start null_or_<='),
      ssi::date_filter($uri.'?created_on_start', 'period_end null_or_>='),
      order   =>  'period_start,name',
    ) ];
  my $company_ids = [ map { $$_{id} } openprint::Company->find_filtered() ] if $session{user_type} ne 'A';

  my @Invoices = @{$variable{Invoices}} = ();
  if ( $param{invoice_id} ) {
    @Invoices = openprint::Invoice->find(
      id => $param{invoice_id},
        or => [
        invoicer_id=>$session{company_id},
        ( sets::isin( $session{user_type}, ['E','A'] ) ?  () : ( invoicee_id=>$session{company_id} ) ),
      ],
      order => 'num,id',
    );
  } elsif ( $param{invoice_num} ) {
    @Invoices = openprint::Invoice->find(
      'num ilike' => ( $param{invoice_num} =~ /%/ ? $param{invoice_num} : '%'.$param{invoice_num}.'%' ),
        or => [
        invoicer_id=>$session{company_id},
        ( sets::isin( $session{user_type}, ['E','A'] ) ?  () : ( invoicee_id=>$session{company_id} ) ),
      ],
      order => 'num,id',
    );
  } elsif ( $param{po_id} ) {
    @Invoices = openprint::Invoice->find(
      'po any'=>$param{po_id},
        or => [
        invoicer_id=>$session{company_id},
        ( sets::isin( $session{user_type}, ['E','A'] ) ?  () : ( invoicee_id=>$session{company_id} ) ),
      ],
      order => 'num,id',
    );
  } else {
    my %filter = (
        ssi::date_filter($uri.'?created_on_end', 'created_on <='),
        ssi::date_filter($uri.'?created_on_start', 'created_on >='),
        ssi::date_filter($uri.'?due_on_end', 'due_on is null or <='),
        ssi::date_filter($uri.'?due_on_start', 'due_on is null or >='),
        ( $session{$uri.'?product_id'} ? ( 'product_id any' => $session{$uri.'?product_id'} ) : () ),
        ( $session{$uri.'?bad_debt'} ne '' ? ( bad_debt=>$session{$uri.'?bad_debt'} ) :() ),
        ( $session{$uri.'?currency_id'} ? ( currency_id=>$session{$uri.'?currency_id'} ) : () ),
        order => 'created_on',
      );
      $filter{or} = [
        invoicer_id=>$session{company_id},
        invoicee_id=>$session{company_id},
      ];
    if ( $session{user_type} eq 'E' or $session{user_type} eq 'A') {
      # Our company must be either the invoicee or invoicer
      if ( $session{$uri.'?invoicee_id'} ) {
        $filter{invoicee_id} = $session{$uri.'?invoicee_id'};
      }
    } elsif ($session{user_type} eq 'A') {
      if ( $session{$uri.'?invoicer_id'} ) {
        $filter{invoicer_id} = $session{$uri.'?invoicer_id'};
      }
    }

    foreach my $Invoice ( openprint::Invoice->find(%filter)) {
      if ( $session{$uri.'?paid'} ne '' ) {
        if ( $Invoice->is_paid() ) {
          next if $session{$uri.'?paid'} == 0;
        } else {
          next if $session{$uri.'?paid'} == 1;
        } # end if
      } # end if
      if ( $session{$uri.'?bad_debt'} != '' ) {
        if ( $Invoice->bad_debt() ) {
          next if $session{$uri.'?bad_debt'} == 0;
        } elsif ( $Invoice->bad_debt() eq '0' ) {
          next if $session{$uri.'?bad_debt'} == 1;
        } # end if
      } # end if

      if ( Date::Calc::check_date( @session{ map { $uri.'?paid_on_start_'.$_ } ( 'year','month','day' ) } ) ) {
        my $date = join('-',@session{ map { $uri.'?paid_on_start_'.$_ } ( 'year','month','day' ) } );
        if ( $Invoice->paid_on() lt $date ) {
          next;
        }
      }
      if ( Date::Calc::check_date( @session{ map { $uri.'?paid_on_end_'.$_ } ( 'year','month','day' ) } ) ) {
        my $date = join('-',@session{ map { $uri.'?paid_on_end_'.$_ } ( 'year','month','day' ) } );
        if ( $Invoice->paid_on() gt $date ) {
          next;
        }
      }

      next if ! $Invoice->can_view();
      push @Invoices, $Invoice;
    } # end foreach Invoice
  } # end if
  foreach my $Invoice ( @Invoices ) {
    push @{$variable{Invoices}}, $Invoice;
    $variable{subtotal} += $Invoice->subtotal();
    $variable{total} += $Invoice->owing() > 0 ? $Invoice->Currency()->convert_from($Invoice->total()) : $Invoice->paid_value();
    $variable{interest_total} += $Invoice->interest();
    $variable{paid_total} += $Invoice->paid();
    $variable{paidvalue_total} += $Invoice->paid_value();
    $variable{owing_total} += $Invoice->owing();
    $variable{owing_total_value} += $Invoice->Currency()->convert_from($Invoice->owing());
    foreach my $Tax ( @{$variable{Taxes}} ) {
      my $IT = $Invoice->Tax( $Tax );
      next if ! $$IT{tax_id};
      $variable{tax_totals}{$Tax->id()} += $IT->amount();
    } # end foreach Tax
  } # end foreach Invoice
	@{$variable{Invoices}} = @Invoices;

} # end sub _history

sub edit {
	my $Invoice = $variable{Invoice} = new openprint::Invoice($param{invoice_id});
	if ( $param{btnFunction} eq 'Save' ) {
		$param{currency_id} = $openprint::Currency->id() if !$param{currency_id};
		my @due_on = ssi::date('due_on', \%param);
		$param{due_on} = sprintf('%.4d-%.2d-%.2d', @due_on) if ! $param{due_on} and Date::Calc::check_date(@due_on);
		my @posted_on = ssi::date('posted_on', \%param);
		$param{posted_on} = sprintf('%.4d-%.2d-%.2d', @posted_on ) if ! $param{posted_on} and Date::Calc::check_date(@posted_on);
		my @early_payment_date = ssi::date('early_payment_date', \%param);

		$param{early_payment_date} = sprintf('%.4d-%.2d-%.2d', @early_payment_date) if ( ! $param{early_payment_date} ) and Date::Calc::check_date(@early_payment_date);
		$param{invoicer_id} = $session{company_id} if ! $param{invoicer_id};
		if ( $param{invoicee} ) {
			my $Invoicee = openprint::Company->find_one(name=>openprint::Company->transform(name=>$param{invoicee}));
			if ( ! $Invoicee ) {
				$Invoicee = new openprint::Company();
				$Invoicee->save({name=>$param{invoicee}});
			} # end if
			$param{invoicee_id} = $Invoicee->id();
		} else {
			delete $param{invoicee};
		} # end if
		my @changes = $Invoice->changes(\%param);

    # Store values before calculating taxes
		$Invoice->set(\%param);
    # This must happen before saving because charging or not for a tax alters the total.
    foreach my $Tax ($Invoice->Taxes(undef)) {
      # Order is important here. Also the 1* turns an undef value into a specific boolean 0, because we used a checkbox
      $Tax->charge(1*$param{'tax_charge-'.$Tax->tax_id()}) if $Tax->charge() != 1*$param{'tax_charge-'.$Tax->tax_id()};
    } # end foreach

		$Invoice->subtotal_override($param{subtotal_override});
		$variable{error} .= $Invoice->save(\%param);
		foreach my $Product ( $Invoice->Products() ) {
			my %p_changes = (
				description	=>	$param{'product-description-'.$Product->id()},
				price		=>	$param{'product-price-'.$Product->id()},
				quantity	=>	$param{'product-quantity-'.$Product->id()},
				po			=>	$param{'product-po-'.$Product->id()},
				);
			my @p_changes = $Product->changes(\%p_changes);
		 	push @changes, 'product changed: ' . join(',', @p_changes) if @p_changes;

			$variable{error} .= $Product->save( \%p_changes );
		} # end foreach Product
		(new openprint::Log())->save({ Object =>$Invoice, action=>'Edit', note=>join('<br/>', @changes)});
		if ( $param{invoice_id} and ! $variable{error} ) {
			$variable{information} .= 'Invoice saved.<br/>';
			$variable{ExternalRedirect} = '/invoice/view.html?invoice_id='.$Invoice->id();
    } else {
			$variable{ExternalRedirect} = '/invoice/edit.html?invoice_id='.$Invoice->id();
		} # end if
	} # end if
	if ( ! $variable{Invoice}->id() ) {
		# Defaults, don't know who the company is yet
		$variable{Invoice}->due_on( join('-', Date::Calc::Add_Delta_Days( Date::Calc::Today(), 15 ) ) );
		$variable{Invoice}->early_payment_date( join('-', Date::Calc::Add_Delta_Days( Date::Calc::Today(), 7 ) ) );
		if ( $param{order_id} ) {
			my $Order = new openprint::Order($param{order_id});
			$$Invoice{invoicee_id} = $Order->company_id();
			my @Projects ;
			foreach my $P ( $Order->Ordered_Projects() ) {
				my $NewP = new openprint::Invoiced_Project();;
				$NewP->project_id( $P->project_id() );
				$NewP->Invoice( $Invoice );
			} # end foreach
		} # end if
	} # end if
	ssi::setup_date_select($r->uri, 'timetrack_start', -365);
	ssi::setup_date_select($r->uri, 'timetrack_end', '');
} # end sub edit

sub view {
	my $Invoice = $variable{Invoice} = new openprint::Invoice( $param{invoice_id} );
	if ( ! $Invoice ) {
		$variable{error} .= "Invoice $param{invoice_id} not found";
		return;
	} 
	if ( $param{btnFunction} eq 'Calculate Interest' ) {
    $variable{error} = $Invoice->calculate_interests();
    $variable{ExternalRedirect} = '/invoice/view.html?invoice_id='.$Invoice->id();
	} elsif ( $param{btnFunction} eq 'Post' ) {
		if ( ! ( $variable{error} .= $Invoice->save({posted=>1,posted_on=>'NOW()'}) ) ) {
			(new openprint::Log())->save({ Object=>$Invoice, action => 'Invoice Posted'});
			$variable{information} .= 'Invoice posted.<br/>';
			delete $param{invoice_id};
			if ( $session{'/invoice/history.html?company_id'} and ( $session{'/invoice/history.html?company_id'} != $Invoice->invoicee_id() ) ) {
				delete $session{'/invoice/history.html?company_id'};
			} # end if
			$variable{ExternalRedirect} = '/invoice/view.html?invoice_id='.$Invoice->id();
			return;
		} # end if
	} elsif ( $param{btnFunction} eq 'UnPost' ) {
		if ( ! ( $variable{error} .= $Invoice->save({ posted=>0 }) ) ) {
			(new openprint::Log())->save({ Object=>$Invoice, action => 'Invoice Unposted'});
			$variable{information} .= 'Invoice unposted.<br/>';
			$variable{ExternalRedirect} = '/invoice/view.html?invoice_id='.$Invoice->id();
			return;
		} # end if
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		if ( ! ( $variable{error} .= $Invoice->delete() ) ) {
			$variable{information} .= 'Invoice ' . $Invoice->id() . ' deleted.<br/>';
			$variable{ExternalRedirect} = '/invoice/history.html';
		} # end if
	} elsif ( $param{btnFunction} eq 'Destroy' ) {
		if ( ! ( $variable{error} .= $Invoice->destroy() ) ) {
			$variable{information} .= 'Invoice ' . $Invoice->id() . ' destroyed.<br/>';
			$variable{ExternalRedirect} = '/invoice/history.html';
		} # end if
	} elsif ( $param{btnFunction} eq 'Undelete' ) {
		if ( ! ( $variable{error} .= $Invoice->undelete() ) ) {
			$variable{information} .= 'Invoice ' . $Invoice->id() . ' undeleted.<br/>';
			$variable{ExternalRedirect} = '/invoice/history.html';
		} # end if
	} elsif ( $param{btnFunction} eq 'Send' ) {
		if ( ! $Invoice->can_send() ) {
			$variable{error} .= "You are not authorized to send this invoice.<br/>";
		} else {
			$variable{error} .= $Invoice->send();
			$variable{information} .= 'Invoice ' . $Invoice->id() . ' sent.<br/>';
			$variable{ExternalRedirect} = $Invoice->url_to();
			return;
		}
	} elsif ( $param{btnFunction} eq 'Send To Me' ) {
		$variable{error} .= $Invoice->send( new openprint::User( $session{user_id} ) );
		$variable{information} .= 'Invoice ' . $Invoice->id() . ' sent.<br/>';
		$variable{ExternalRedirect} = $Invoice->url_to();
		return;
	} # end if
} # end sub view

sub _timetracks {
	my $Invoice = $variable{Invoice} = new openprint::Invoice( $param{invoice_id} );
	if ( $param{timetrack_id} ) {
		my $Timetrack = new openprint::Timetrack( $param{timetrack_id} );
		if ( $param{action} eq 'add' ) {
			$Timetrack->invoice_id( $variable{Invoice}->id() );
		} elsif ( $param{action} eq 'remove' ) {
			$Timetrack->invoice_id( undef );
		} # en dif
		$variable{error} .= $Timetrack->save();
	} # end if
	if ( $param{invoicee_id} and $param{invoicee_id} != $Invoice->invoicee_id() ) {
		$Invoice->invoicee_id( $param{invoicee_id} );
	} # end if
  my $uri = '/invoice/edit.html';

  ssi::save_params($uri, ( 
      ( map { 'timetrack_start_'.$_ } ( 'year','month','day' ) ),
      ( map { 'timetrack_end_'.$_ } ( 'year','month','day' ) ),
    ));
} # end sub _timetracks

sub _invoiced_products {
	my $Invoice = $variable{Invoice} = new openprint::Invoice( $param{invoice_id} );

	# Save any changes to the products
	foreach my $Product ( $Invoice->Products() ) {
    my @changes = $Product->changes({
        description	=>	$param{'product-description-'.$Product->id()},
        price			  =>	$param{'product-price-'.$Product->id()},
        quantity		=>	$param{'product-quantity-'.$Product->id()},
        po			    =>	$param{'product-po-'.$Product->id()},
      });
    $variable{error} .= $Product->save({
        description	=>	$param{'product-description-'.$Product->id()},
        price			  =>	$param{'product-price-'.$Product->id()},
        quantity		=>	$param{'product-quantity-'.$Product->id()},
        po			    =>	$param{'product-po-'.$Product->id()},
      }) if @changes;
	} # end foreach

	if ( $param{action} eq 'new' ) {
		my $IP = new openprint::Invoiced_Product( );
		$variable{error} .= $IP->save({
				invoice_id=>$Invoice->id(),
				quantity	=> 1
				});
	} elsif ( $param{action} eq 'add' ) {
		my $IP = new openprint::Invoiced_Product();
    $variable{error} .= $IP->save({
        product_id	=>	$param{'product-id-'},
        invoice_id	=>	$Invoice->id(),
        quantity		=>	$param{'product-quantity-'} ? $param{'product-quantity-'} : 1,
        po    			=>	$param{'product-po-'},
      });
    $Invoice->Products( [$Invoice->Products(), $IP] );
	} elsif ( $param{action} eq 'remove' ) {
		my $IP = new openprint::Invoiced_Product( $param{product_id} );
		if ( $IP->id() ) {
			$variable{error} .= $IP->delete();
		} else {
			$variable{error} .= "Product $param{product_id} does not exist.<br/>";
		} # end if
    $Invoice->Products(undef);
	} # end if
} # end sub _invoiced_products

sub _interests {
	if ( $param{action} eq 'delete' ) {
		my $Interest = new openprint::Invoice_Interest( $param{interest_id} );
		$variable{Invoice} = $Interest->Invoice();
		$variable{error} .= $Interest->delete();	
		$variable{Invoice}->interest(undef);
		$variable{error} = $variable{Invoice}->save();
    (new openprint::Log())->save({Object=>$variable{Invoice}, action=>'delete', note=>$Interest->to_string()});
	} # end if
} # end sub _interests

sub _invoicee_onchange {
} # end sub _invoicee_onchange

sub _invoiced_orders {
	my $Invoice = $variable{Invoice} = new openprint::Invoice( $param{invoice_id} );
$log->debug("here");
	if ( $param{action} eq 'add' ) {
$log->debug("Adding");
		my $Order = openprint::Order->find_one( id => $param{order_id} );
		if ( ! $Order ) {
			$variable{error} .= 'Order ' . $param{order_id} . ' not found.<br/>';
			return;
		}
		my $OI = new openprint::Order_Invoice();
		$variable{error} .= $OI->save({
			order_id	=> $$Order{id},
			invoice_id	=>	$$Invoice{id},
		});	
		foreach my $Product ( $Order->Products() ) {
			my $IP = new openprint::Invoiced_Product();
			$variable{error} .= $IP->save({
				invoice_id	=>	$$Invoice{id},
				product_id	=>	$$Product{product_id},
				quantity	=>	$$Product{quantity},
				price		=>	$$Product{price},
			});
		}
	} elsif ( $param{action} eq 'remove' ) {
		my $OI = openprint::Order_Invoice->find_one( order_id=>$param{order_id}, invoice_id=>$param{invoice_id} );
		$OI->delete();
	} # end if param add

} # end sub _invoiced_orders

sub _view_email {
	my $Invoice = $variable{Invoice} = new openprint::Invoice( $param{invoice_id} );
	if ( ! $Invoice ) {
		$variable{error} .= "Invoice $param{invoice_id} not found";
		return;
	} 
}
sub _taxes_edit {
	my $Invoice = $variable{Invoice} = new openprint::Invoice( $param{invoice_id} );
	if ( ! $Invoice->id() ) {
		$variable{error} = "Invalid Invoice specified: $param{invoice_id}<br/>";
		return;
	} # end if

	if ( $param{action} ) {
		if ( $param{action} eq 'add' ) {
			my $ac = sql::start_transaction( $openprint::dbh );
			my $Tax = new openprint::Tax( $param{tax_id} );
			my $Invoice_Tax = new openprint::Invoice_Tax();
			$variable{error} .= $Invoice_Tax->save( { invoice_id => $param{invoice_id}, tax_id=>$param{tax_id}, charge=>1, rate=>$Tax->rate() } );
			if ( $variable{error} ) {
				$openprint::dbh->rollback();
				sql::end_transaction( $openprint::dbh, $ac );
				return;
			}
			$variable{error} .= $Invoice->save( );
			if ( $variable{error} ) {
				$openprint::dbh->rollback();
				sql::end_transaction( $openprint::dbh, $ac );
				return;
			}
			$variable{error} .= $Invoice->save( );
			my $L = new openprint::Log();
			$L->save({ Object	=>	$Invoice, action=>'Edit', note	=>	'add tax ' . $Tax->name() });
			sql::end_transaction( $openprint::dbh, $ac );
		} elsif ( $param{action} eq 'delete' ) {
			my $Tax = new openprint::Tax( $param{tax_id} );
			my $Invoice_Tax;
			foreach my $T ( $Invoice->Taxes() ) {
				if ( $$T{tax_id} == $param{tax_id} ) {
					$Invoice_Tax = $T;
					last;
				}
			}
			if ( ! $Invoice_Tax ) {
				$variable{error} .= "Tax $$Tax{name} is not attached to Invoice $$Invoice{id}<br/>";
				return;
			} # end if
			my $ac = sql::start_transaction( $openprint::dbh );
			$variable{error} .= $Invoice_Tax->delete();
			if ( $variable{error} ) {
				$openprint::dbh->rollback();
				sql::end_transaction( $openprint::dbh, $ac );
				return;
			}
			$Invoice->Taxes( undef );
			$variable{error} .= $Invoice->save();
			if ( $variable{error} ) {
				$openprint::dbh->rollback();
				sql::end_transaction( $openprint::dbh, $ac );
				return;
			}
			my $L = new openprint::Log();
			$L->save({ Object => $Invoice, action=>'Edit', reason	=>	'delete tax ' . $Invoice_Tax->name() });
			sql::end_transaction( $openprint::dbh, $ac );
		} elsif ( $param{action} eq 'reset' ) {
			$Invoice->set( \%param );
			# Reload $Invoice->Taxes() with current set
			$Invoice->default_Taxes();
			$variable{error} .= $Invoice->save();
			my $L = new openprint::Log();
			$L->save({ Object=> $Invoice, action=>'Edit', reason	=>	'update taxes', });
		} # end if action
	} # end if action
} # end sub taxes_edit

1;
__END__
