use strict;
package openprint::employee_purchase_order;
require sql;
require openprint::PurchaseOrder;
require openprint::PurchaseOrder_Item;
require openprint::PurchaseOrder_Content;
require openprint::PurchaseOrder_Tax;
require openprint::PurchaseOrder_Department;
require openprint::Company_Category;
require openprint::Object_Asset;
require openprint::Object_Payment;
require CGI;

use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

sub save_supplier {
	my ( $p ) = @_;

	my $Company;
	my $ac = sql::start_transaction( $dbh );
$openprint::log->error("Already in transaction $ac") if $ac;
	$dbh->do( 'LOCK TABLE Companies IN SHARE ROW EXCLUSIVE MODE' ) or $log->error( DBI->errstr );

	my @Companies = openprint::Company->find( 'name lc'=> lc openprint::Company->transform('name', $$p{vendor_name} ) );
	if ( ! @Companies ) {
		$Company = new openprint::Company();
		$Company->save({
				supplier			=> 'Y',
				name					=> $$p{vendor_name},
				business_name	=> $$p{vendor_name},
				address1			=> $$p{vendor_address1},
				address2			=> $$p{vendor_address2},
				city					=> $$p{vendor_city},
				state					=> $$p{vendor_state},
				country				=> $$p{vendor_country},
				postalcode		=> $$p{vendor_postalcode},
				phone					=> $$p{vendor_phone},
				fax						=> $$p{vendor_fax},
				} );
	} else {
		foreach my $C ( @Companies ) {
			if ( $C->supplier() eq 'Y' ) {
				$Company = $C;
				last;
			} # end if
		} # end foreach
		if ( ! $Company ) {
			$Company = $Companies[0];
			$Company->save( {supplier=>'Y'} );
		} # end if
	} # end if
	sql::end_transaction( $dbh, $ac );
	return $Company->id() if $Company;
	return;
} # end sub save_supplier

sub save_contact {
	my ( $p ) = @_;

	my $ac = sql::start_transaction( $dbh );
	$dbh->do( 'LOCK TABLE Users IN SHARE ROW EXCLUSIVE MODE' ) or $log->error( DBI->errstr );
	my $User = openprint::User->find_one( company_id=>$$p{supplier_id}, email => openprint::User->transform('email', $$p{vendor_email} ) );
	if ( ! $User ) {
$log->debug("didn't find user, so create a new one");
		$User = new openprint::User();
		my ( $first, $last ) = $$p{vendor_contact} =~ /(\S+)\s*(\S*)/;
		$User->save( {
				company_id				=>	$$p{supplier_id},
				email							=>	$$p{vendor_email},
				firstname					=>	$first,
				lastname					=>	$last,
				phone							=>	$$p{vendor_phone},
				fax								=>	$$p{vendor_fax},
				sms								=>	$$p{vendor_sms},
				change_password		=>	'N',
				administrator			=>	'N',
				ftp_active				=>	0,
				web_active				=>	0,
				} );
} else {
$log->debug("Found user: " . $User->to_string() );
	} # end if
	sql::end_transaction( $dbh, $ac );
	return $$User{id};
} # end sub save_contact

sub save_contents {
	my ( $PO, $p ) = @_;
	my %types;

	my $ac = sql::start_transaction( $dbh );
	$dbh->do( "LOCK TABLE $openprint::PurchaseOrder_Item::table IN EXCLUSIVE MODE" ) or $log->error( DBI->errstr );
	$dbh->do( "LOCK TABLE $openprint::PurchaseOrder_Department::table IN EXCLUSIVE MODE" ) or $log->error( DBI->errstr );
	$dbh->do( "LOCK TABLE $openprint::PurchaseOrder_Content::table IN EXCLUSIVE MODE" ) or $log->error( DBI->errstr );

	foreach my $C ( $PO->Contents() ) {
		my $Item;
		my $content_id = $$C{id};
		if ( $$p{'item-'.$content_id} ) {
			$Item = new openprint::PurchaseOrder_Item( $$p{'item_id-'.$content_id} );
			if ( $$p{supplier_id} ) {
				if ( ( ! $Item->id() ) or ( lc $Item->name() ne lc openprint::PurchaseOrder_Item->transform('name', $$p{'item-'.$content_id}) ) ) {
					$log->debug("Looking up (" . $$p{'item-'.$content_id}.') (' . $Item->name() );
					$Item = openprint::PurchaseOrder_Item->find_one(
							company_id		=>	$PO->company_id(),
							vendor_id		=>	$$p{supplier_id},
							type_id			=>	$$p{'type_id-'.$content_id},
							'name lc'		=>	lc openprint::PurchaseOrder_Item->transform('name',$$p{'item-'.$content_id}),
							'product lc'	=>	lc openprint::PurchaseOrder_Item->transform('product',$$p{'product-'.$content_id}),
							);
					if ( ! $Item ) {
						$Item = new openprint::PurchaseOrder_Item();
						$Item->save({
								company_id	=>	$PO->company_id(),
								vendor_id	=>	$$p{supplier_id},
								type_id		=>	$$p{'type_id-'.$content_id},
								name		=>	$$p{'item-'.$content_id}, 
								price		=>	$$p{'price-'.$content_id},
								product		=>	$$p{'product-'.$content_id},
								});
					} # end if
				} else {
					$log->debug("Item is " . $Item->name() );
				} # end if
				if ( $Item->price() != $$p{'price-'.$content_id} ) {
	# Update the latest price
					$Item->save({'price'=>$$p{'price-'.$content_id}});
				} # end if
			} # end if PO has supplier_id
		} else {
			$log->debug("No item for $content_id");
		} # end if

		my $Dept;
		if ( ( $$p{'dept_id-'.$content_id} eq 'new' ) or ! $$p{'dept_id-'.$content_id} ) {
			$Dept = openprint::PurchaseOrder_Department->find_one( 
					'name lc' => lc openprint::PurchaseOrder_Department->transform('name',$$p{'dept-'.$content_id}),
					);
			if ( ! $Dept ) {
				$Dept = new openprint::PurchaseOrder_Department();
				$Dept->save({'name'=>$$p{'dept-'.$content_id}});
			} # end if
		} else {
			$Dept = new openprint::PurchaseOrder_Department( $$p{'dept_id-'.$content_id} );
		} # end if

		$variable{error} .= $C->save( {
				po_id			=>	$PO->id(),
				qty				=>	$$p{'qty-'.$content_id},
				product		=>	$$p{'product-'.$content_id},
				item_id		=>	$$Item{id},
				description	=>	$$p{'description-'.$content_id},
				docket		=>	$$p{'docket-'.$content_id},
				price			=>	$$p{'price-'.$content_id},
				total			=>	$$p{'total-'.$content_id},
				type_id		=>	$$p{'type_id-'.$content_id},
				( $Dept ? ( department_id	=>	$Dept->id() ) : ( ) ),
				});

		$types{$C->Type()->name()} = 1;
		if ( $C->docket() and ! ( $C->docket() =~ /\D/ ) ) {
			foreach my $P ( openprint::Project->find( docket=>$C->docket()) ) {
				$P->add_to_log( @session{'company_id','user_id'}, 
						sprintf('<a href="/employee/purchase_order/view.html?po_id=%1$d">%2$s%3$s %4$s ordered on PO%1$d</a>',
							$PO->id(), $C->qty(), $C->units(), $C->description() ) );
			} # end foreach Project
		} # end if docket
	} # end foreach Content id
	sql::end_transaction( $dbh, $ac );
	return %types;
} # end sub save_contents

sub view {

	if ( $param{po_id} ne openprint::PurchaseOrder->transform('id', $param{po_id} ) ) {
		$variable{error} .= 'Invalid PO # given: ' . $param{po_id}.'<br/>';
		$variable{PurchaseOrder} = new openprint::PurchaseOrder();
		return;
	} # end if
	
	my $PO = openprint::PurchaseOrder->find_one( id=>$param{po_id}, deleted=>[0,1] );
	if ( ! $PO ) {
		$variable{error} .= 'PO ' . $param{po_id}.' not found.<br/>';
		$variable{PurchaseOrder} = new openprint::PurchaseOrder();
		return;
	} # end if
	$variable{PurchaseOrder} = $PO;

	return if ! $param{btnFunction};

	if ( $param{btnFunction} eq 'Delete' ) {
		$variable{error} .= $PO->delete();
		if ( ! $variable{error} ) {
			my $L = new openprint::PurchaseOrder_Log();
			$L->save({
					'user_id'	=>	$session{user_id},
					'po_id'		=>	$PO->id(),
					'reason'	=>	'deleted.' . $param{reason},
					});
			delete $param{po_id};
			delete $param{btnFunction};
			$variable{ExternalRedirect} = '/employee/purchase_order/history.html';
		} # end if
  } elsif ( $param{btnFunction} eq 'DoNotPay' ) {
    $variable{error} .= $PO->save({ do_not_pay=>1 });
    if ( ! $variable{error} ) {
      my $L = new openprint::PurchaseOrder_Log();
      $L->save({
          user_id =>  $session{user_id},
          po_id   =>  $PO->id(),
          reason  =>  'Marked do not pay: '. $param{reason},
          });
      delete $param{po_id};
      delete $param{btnFunction};
      $variable{ExternalRedirect} = '/employee/purchase_order/view.html?po_id='.$PO->id();
    } # end if
  } elsif ( $param{btnFunction} eq 'UnDoNotPay' ) {
    $variable{error} .= $PO->save({do_not_pay=>0});
    if ( ! $variable{error} ) {
      my $L = new openprint::PurchaseOrder_Log();
      $L->save({
          user_id =>  $session{user_id},
          po_id   =>  $PO->id(),
          reason  =>  'Un-DoNotPay: '. $param{reason},
          });
      delete $param{po_id};
      delete $param{btnFunction};
      $variable{ExternalRedirect} = '/employee/purchase_order/view.html?po_id='.$PO->id();
    } # end if

	} elsif ( $param{btnFunction} eq 'Cancel' ) {
		$variable{error} .= $PO->save({ cancelled=>1 });
		if ( ! $variable{error} ) {
			my $L = new openprint::PurchaseOrder_Log();
			$L->save({
					user_id	=>	$session{user_id},
					po_id		=>	$PO->id(),
					reason	=>	'Cancelled: '. $param{reason},
					});
			delete $param{po_id};
			delete $param{btnFunction};
			$variable{ExternalRedirect} = '/employee/purchase_order/history.html';
		} # end if
	} elsif ( $param{btnFunction} eq 'UnCancel' ) {
		$variable{error} .= $PO->save({'cancelled'=>0});
		if ( ! $variable{error} ) {
			my $L = new openprint::PurchaseOrder_Log();
			$L->save({
					user_id	=>	$session{user_id},
					po_id		=>	$PO->id(),
					reason	=>	'Un-Cancelled: '. $param{reason},
					});
			delete $param{po_id};
			delete $param{btnFunction};
			$variable{ExternalRedirect} = '/employee/purchase_order/history.html';
		} # end if
	} elsif ( $param{btnFunction} eq 'Undelete' ) {
		$variable{error} .= $PO->undelete();
		if ( ! $variable{error} ) {
			my $L = new openprint::PurchaseOrder_Log();
			$L->save({
					'user_id'	=>	$session{user_id},
					'po_id'		=>	$PO->id(),
					'reason'	=>	'undeleted.',
					});
			delete $param{po_id};
			delete $param{btnFunction};
			$variable{ExternalRedirect} = '/employee/purchase_order/history.html';
		} # end if
	} elsif ( $param{btnFunction} eq 'Authorize' ) {
		if ( $PO->can_authorize() ) {
			if ( $_ = $PO->authorize() ) {
				$variable{error} .= $_ . '<br/>';
			} else {
				$variable{information} .= 'PO ' . $$PO{id} . ' has been authorized.<br/>';
			} # end if
		} else {
			$variable{error} .= 'You are not authorized to approve PO ' . $PO->id() . '<br/>';
		} # end if
		$variable{ExternalRedirect} = '/employee/purchase_order/history.html' if ! $variable{error};
    } elsif ( $param{btnFunction} eq 'AuthorizeAndSend' ) {
		if ( $PO->can_authorize() ) {
			if ( $_ = $PO->authorize() ) {
				$variable{error} .= $_ . '<br/>';
			} else {
				$variable{information} .= 'PO ' . $$PO{id} . ' has been authorized.<br/>';
				$variable{error} .= $PO->send_to_vendor();
			} # end if
		} else {
			$variable{error} .= 'You are not authorized to approve PO ' . $PO->id() . '<br/>';
		} # end if
		$variable{ExternalRedirect} = '/employee/purchase_order/history.html' if ! $variable{error};
	} elsif ( $param{btnFunction} eq 'Send' ) {
	} elsif ( $param{btnFunction} eq 'Email Vendor' ) {
		$variable{error} = $PO->send_to_vendor();
		$variable{ExternalRedirect} = '/employee/purchase_order/history.html' if ! $variable{error};
	} elsif ( $param{btnFunction} eq 'Email Me' ) {
		$variable{error} = $PO->send_to_me();
		$variable{ExternalRedirect} = '/employee/purchase_order/view.html?po_id='.$PO->id();
	} elsif ( $param{btnFunction} eq 'Debug' ) {
		$variable{information} .= $PO->debug();
	} elsif ( $param{btnFunction} eq 'Received' ) {
	} elsif ( $param{btnFunction} eq 'Copy' ) {
		my @notifications = $PO->notifications();

		my $New = $PO->copy();
		if ( ! ( $variable{error} = $New->save() ) ) {
			foreach my $C ( $PO->Contents() ) {
				$C = $C->copy();
				$C->po_id( $New->id() );
				$C->save();
			} # end foreach
			$New->notifications( \@notifications );
			$New->update_notifications( );
			$New->save();
			$variable{information} .= 'PO ' . $PO->link_to() . ' copied to PO ' . $New->link_to() .'<br/>';
			my $L = new openprint::PurchaseOrder_Log();
			$L->save({ user_id	=>	$session{user_id}, po_id		=>	$New->id(), reason	=>	'Copied from PO '. $PO->id(), });
			$L = new openprint::PurchaseOrder_Log();
			$L->save({ user_id	=>	$session{user_id}, po_id		=>	$PO->id(), reason	=>	'Copied to PO '. $New->id(), });
			$PO = $New;
			if ( $PO->total() ) {
				if ( $PO->can_authorize() ) {
					$variable{error} .= $PO->save({
							authorized		=> 1,
							authorized_on	=> 'NOW()',
							authorized_by	=> $session{user_id},
							});
				} else {
					$variable{error} .= $PO->save({
							authorized		=> 0,
							authorized_on	=> undef,
							authorized_by	=> undef,
							});
				} # end if 
			} # end if
			$variable{ExternalRedirect} = '/employee/purchase_order/view.html?po_id='.$PO->id();
		} # end if
	} elsif ( $param{btnFunction} eq 'AuthRequest' ) {
		$variable{information} .= $PO->send_approval_required_notification();
		if ( ! $variable{information} ) {
			$variable{warning} .= 'This PO needs approval but no one could be found to do it.';
		} else {
			$variable{information} =~ s/Sent/send/g;
			$variable{information} = 'Approval request ' . $variable{information};
			my $L = new openprint::PurchaseOrder_Log();
			$L->save({
					user_id	=>	$session{user_id},
					po_id	=>	$PO->id(),
					reason	=>	$variable{information}
					});
		} # end if
		$variable{ExternalRedirect} = '/employee/purchase_order/view.html?po_id='.$PO->id();
	} elsif ( $param{btnFunction} eq 'Attach' ) {
		my $Asset = new openprint::Asset();
		$variable{error} .= $Asset->save({ 'name'	=>	$param{asset_name}, 'filename' => $param{filename} } );
		if ( ! $variable{error} ) {
			$variable{information} .= 'Information successfully stored.<br/>';
		} # end if
		if ( $param{filename} ) {
			my $upload = $r->upload('filename');
			if ( ! $upload ) {
				$Asset->save({'filename'=>''});
				$variable{error} .= "There was no upload for $param{filename}<br/>";
			} elsif ( ! $upload->link( $Asset->on_disk_path() ) ) {
				$variable{error} .= "There was an error saving file $param{filename} to " . $Asset->on_disk_path() . ": $!<br/>";
				$Asset->save({'filename'=>''});
			} else {
				$variable{information} .= "File $param{filename} was uploaded successfully.<br/>";
			} # end if
		} # end if
		if ( $Asset->id() ) {
			my $PO_Asset = new openprint::Object_Asset();
			$variable{error} .= $PO_Asset->save({'object_id'=>$param{po_id},'object_type'=>'openprint::PurchaseOrder','asset_id'=>$Asset->id()});
			if ( ! $variable{error} ) {
				$variable{ExternalRedirect} = '/employee/purchase_order/view.html?po_id='.$PO->id();
			} # end if
		} # end if
		%param = ();
	} elsif ( $param{btnFunction} eq 'SavePayment' ) {
		my $ac = sql::start_transaction( $openprint::dbh );
		my $Payment = new openprint::Payment();
		$variable{error} .= $Payment->save({
				user_id				=>	$openprint::User->id(),
				amount        =>  $param{amount},
				currency_id   =>  $$PO{currency_id},
				received_on   =>  join('-', map { $param{'paid_on_'.$_} } ( 'year','month','day' ) ),
				memo          =>  $param{description},
				recipient_id  =>  $PO->supplier_id(),
				payor_id      =>  $PO->company_id(),
				transaction_id	=>	$param{transaction_id},
				});
		if ( $variable{error} ) {
			sql::end_transaction( $openprint::dbh, $ac );
			return;
    }
    my $PO_Payment = new openprint::Object_Payment();
    $variable{error} .= $PO_Payment->save({
				payment_id=>$Payment->id(),
				object_id=>$PO->id(),
				object_type=>'openprint::PurchaseOrder',
				amount=>$param{amount} });
    $PO->Payments( undef );
    $PO->payments_total(undef);
    $PO->total(undef);
		$PO->paid_on(join('-', map { $param{'paid_on_'.$_} } ( 'year','month','day' ) )) if (!$PO->paid_on()) and $PO->is_paid();
    $variable{error} .= $PO->save();
    $openprint::dbh->rollback() if $variable{error};
    sql::end_transaction( $openprint::dbh, $ac );
      my $L = new openprint::PurchaseOrder_Log();
      $L->save({
          user_id =>  $session{user_id},
          po_id   =>  $PO->id(),
          reason  =>  'add payment ' . $PO_Payment->amount(),
          });
		
	} # end if btnFunction

	$variable{PurchaseOrder} = $PO;
} # end sub view

sub edit {

	my $PO = new openprint::PurchaseOrder( $param{po_id} );

	if ( $param{btnFunction} eq 'New' ) {
		my $Label = new openprint::Label( $param{label_id} );
		my $C = $openprint::User->Company();
		
		my $Project = $Label->Project();
		if ( ! ( $Project and $Project->company_id() ) ) {
			$variable{error} .= 'No project for label.';
			return;
		} # end if

		$variable{error} .= $PO->save( {
				created_by				=>	$session{user_id}, 
				company_id				=>	$openprint::User->company_id(),
				supplier_id				=>	$Project->company_id(),
				currency_id				=>	openprint::Currency::get_current()->id(),
				created_by				=>	$openprint::User->id(),
				shipto_contact		=>	$openprint::User->name(),
				shipto_name				=>	$C->name(),
				shipto_address1		=>	$C->address1(),
				shipto_address2		=>	$C->address2(),
				shipto_city				=>	$C->city(),
				shipto_state			=>	$C->state(),
				shipto_country		=>	$C->country(),
				shipto_postalcode	=>	$C->postalcode(),
				shipto_phone			=>	$C->phone(),
				shipto_mobile			=>	$openprint::User->mobile(),
				shipto_fax				=>	$C->fax(),
				shipto_email			=>	$openprint::User->email(),
				shipto_sms				=>	$openprint::User->sms(),
				} );
$log->debug("Creating PO $$PO{id} from label $variable{error}");
		
		my $C = new openprint::PurchaseOrder_Content();
		$C->save( {
			po_id				=> 	$PO->id(),
			qty					=>	1,
			item				=>	'Shipping',
			description	=>	'From: ' . $Label->get_data('from') . ' To: ' . $Label->get_data('to'),
			docket			=>	$Label->Project()->docket(),
			type				=>	'Other',
			});
	
	} elsif ( $param{btnFunction} eq 'Save' ) {
		if ( ! $param{po_id} ) {
			$variable{error} .= $PO->save( { created_by	=> $session{user_id}, company_id => $openprint::User->company_id() } );
		} elsif ( ($PO->Creator()->type() eq 'E') and ($openprint::User->type() eq 'A') ) {
			$variable{error} .= $PO->save( { created_by => $session{user_id} });
			my $L = new openprint::PurchaseOrder_Log();
			$L->save({
					user_id	=>	$session{user_id},
					po_id		=>	$PO->id(),
					reason	=>	'Taking ownership',
					});
		} # end if

		$param{supplier_id} = save_supplier( \%param ) if ( ! $param{supplier_id} ) and $param{vendor_name};
		if ( $param{supplier_id} and $param{vendor_name} ) {
			# Using new here instead of find because save_supplier uses find and so should not return a deleted supplier.
			my $Supplier = new openprint::Company( $param{supplier_id} );
			if ( ! $Supplier ) {
				$log->error("SUpplier not found!");
			} else {
				if ( ! $Supplier->name() ) {
					$Supplier->name($param{vendor_name});
					foreach ( 'country', 'state', 'address1', 'address2', 'city', 'postalcode', 'phone', 'fax' ) {	
						$$Supplier{$_} = $param{"vendor_$_"} if ( ! $$Supplier{$_}) and $param{"vendor_$_"};
					} # end foreach
					$variable{error} .= $Supplier->save();
				} # end if
			} # end if
		} # end if
		
		if ( $param{supplier_id} and ( ! $param{contact_id} ) and $param{vendor_contact} ) {
			$param{contact_id} = save_contact( \%param );
		} else {
			$log->debug("Not saving contact ");
		}
		my %types = save_contents( $PO, \%param );

		if ( $param{delivered_on_switch} eq 'DATE' ) {
			$param{delivered_on} = sprintf('%.4d-%.2d-%.2d', @param{'delivered_on_year','delivered_on_month','delivered_on_day'}) if ! $param{delivered_on};
		} else {
			$param{delivered_on} = undef;
		} # end if

		# We start locking here, because we load the taxes here. Taxes are where the locking becomes important.
		$PO->lock();

		$PO->set( \%param );
		if ( ! $param{po_id} ) {
			$PO->default_Taxes();
		} else {
			# Theoretically, the taxes in params are up to date, because any change in country would update them.
			# This must happen before saving because charging or not for a tax alters the total.
			foreach my $Tax ( $PO->Taxes() ) {
				# Order is important here. Also the 1* turns an undef value into a specific boolean 0, because we used a checkbox
				$Tax->charge(1*$param{'tax_charge-'.$Tax->tax_id()}) if $Tax->charge() != 1*$param{'tax_charge-'.$Tax->tax_id()};
			} # end foreach
		}
    # Save will recalc taxes as well.
		$variable{error} .= $PO->save();

		if ( $PO->total() and ( ! $PO->authorized() ) and $PO->can_authorize() ) {
			$variable{error} .= $PO->save( {
					authorized	 	=> 1,
					authorized_on => 'NOW()',
					authorized_by => $session{user_id},
					} );
		} # end if

		$PO->unlock();

		if ( ( ! $variable{error} ) and $param{reason} ) {
			my $L = new openprint::PurchaseOrder_Log();
			$L->save({
				user_id	=>	$session{user_id},
				po_id		=>	$PO->id(),
				reason	=>	$param{reason},
				});
		} # end if
		$PO->update_notifications(\%types);
		if ( ! $variable{error} ) {
			if ( ! $param{po_id} ) {
				$variable{ExternalRedirect} = '/employee/purchase_order/edit.html?po_id='.$PO->id();
			} else {
				$variable{ExternalRedirect} = '/employee/purchase_order/view.html?po_id='.$PO->id();
			} # end if
		} # end if
	} elsif ( $param{btnFunction} eq 'Attach' ) {
		$param{supplier_id} = save_supplier( \%param ) if ( ! $param{supplier_id} ) and $param{vendor_name};
		$param{contact_id} = save_contact( \%param ) if ! $param{contact_id};
		my %types = save_contents( $PO, \%param );
		foreach my $Tax ( $PO->Taxes() ) {
			# Order is important here. Also the 1* turns an undef value into a specific boolean 0, because we used a checkbox
			$Tax->charge(1*$param{'tax_charge-'.$Tax->id()}) if $Tax->charge() != 1*$param{'tax_charge-'.$Tax->id()};
			$Tax->amount(undef);
			$Tax->save();
		} # end foreach
		$variable{error} .= $PO->save( \%param );

		my $Asset = new openprint::Asset();
		$variable{error} .= $Asset->save({ name	=> $param{asset_name}, filename => $param{filename} } );
		if ( ! $variable{error} ) {
			$variable{information} .= 'Information successfully stored.<br/>';
		} # end if
		if ( $param{filename} ) {
			my $upload = $r->upload('filename');
			if ( ! $upload ) {
				$Asset->save({filename=>''});
				$variable{error} .= "There was no upload for $param{filename}<br/>";
			} elsif ( ! $upload->link( $Asset->on_disk_path() ) ) {
				$variable{error} .= "There was an error saving file $param{filename} to " . $Asset->on_disk_path() . ": $!<br/>";
				$Asset->save({filename=>''});
			} else {
				$variable{information} .= "File $param{filename} was uploaded successfully.<br/>";
			} # end if
		} # end if
		if ( $Asset->id() ) {
			my $PO_Asset = new openprint::Object_Asset();
			$variable{error} .= $PO_Asset->save({ object_id=>$param{po_id}, object_type=>'openprint::PurchaseOrder', asset_id=>$Asset->id()});
			if ( ! $variable{error} ) {
				$variable{ExternalRedirect} = '/employee/purchase_order/edit.html?po_id='.$PO->id();
			} # end if
		} # end if
		%param = ();

	} # end if btnFunction

	if ( ! $PO->id() ) {
		my $C = $openprint::User->Company();
		$PO->set( {
			currency_id			=>	openprint::Currency::get_current()->id(),
			company_id			=>	$C->id(),
			created_by			=>	$openprint::User->id(),
			shipto_contact	=>	$openprint::User->name(),
			shipto_name			=>	$C->name(),
			shipto_address1	=>	$C->address1(),
			shipto_address2	=>	$C->address2(),
			shipto_city			=>	$C->city(),
			shipto_state		=>	$C->state(),
			shipto_country	=>	$C->country(),
			shipto_postalcode	=>	$C->postalcode(),
			shipto_phone		=>	$C->phone(),
			shipto_mobile		=>	$openprint::User->mobile(),
			shipto_fax			=>	$C->fax(),
			shipto_email		=>	$openprint::User->email(),
			shipto_sms			=>	$openprint::User->sms(),
		} );
	} # end if
	$variable{PurchaseOrder} = $PO;
} # end sub edit

sub history {
	if ( $param{btnFunction} ) {
	if ( $param{btnFunction} eq 'Delete' ) {
		foreach my $po_id ( ref $param{po_id} eq 'ARRAY' ? @{$param{po_id}} : $param{po_id} ) {
      next if ! openprint::PurchaseOrder->transform(id=>$po_id);
			my $PO = new openprint::PurchaseOrder( $po_id );
			if ( $_ = $PO->delete() ) {
				$variable{error} .= $_ . '<br/>';
			} else {
				my $L = new openprint::PurchaseOrder_Log();
				$L->save({
						user_id	=>	$session{user_id},
						po_id		=>	$PO->id(),
						reason	=>	'deleted.',
						});
				$variable{information} .= 'PO ' . $po_id . ' has been deleted.<br/>';
			} # end if
		} # end foreach po_id
		delete $param{po_id};
	} elsif ( $param{btnFunction} eq 'Destroy' ) {
		foreach my $po_id ( ref $param{po_id} eq 'ARRAY' ? @{$param{po_id}} : $param{po_id} ) {
      next if ! openprint::PurchaseOrder->transform(id=>$po_id);
			my $PO = new openprint::PurchaseOrder( $po_id );
      next if !$PO->deleted();
			if ( $_ = $PO->destroy() ) {
				$variable{error} .= $_ . '<br/>';
        last;
			} else {
				my $L = new openprint::Log();
				$L->save({ action=>'Delete', note	=>	'deleted PO '.$po_id });
				$variable{information} .= 'PO ' . $po_id . ' has been destroyed.<br/>';
			} # end if
		} # end foreach po_id
		delete $param{po_id};
	} elsif ( $param{btnFunction} eq 'Undelete' ) {
		foreach my $po_id ( ref $param{po_id} eq 'ARRAY' ? @{$param{po_id}} : $param{po_id} ) {
			my $PO = new openprint::PurchaseOrder( $po_id );
			if ( $_ = $PO->undelete() ) {
				$variable{error} .= $_ . '<br/>';
			} else {
				my $L = new openprint::PurchaseOrder_Log();
				$L->save({
						'user_id'	=>	$session{user_id},
						'po_id'		=>	$PO->id(),
						'reason'	=>	'undeleted.',
						});
			} # end if
		} # end foreach
		delete $param{po_id};
	} elsif ( $param{btnFunction} eq 'Authorize' ) {
		foreach my $po_id ( ref $param{po_id} eq 'ARRAY' ? @{$param{po_id}} : $param{po_id} ) {
			my $PO = new openprint::PurchaseOrder( $po_id );
			next if ! $PO->id();
			if ( $PO->can_authorize() ) {
				if ( $_ = $PO->authorize() ) {
					$variable{error} .= $_ . '<br/>';
				} else {
					$variable{information} .= 'PO ' . $po_id . ' has been authorized.<br/>';
				} # end if
			} else {
				$variable{error} .= 'You are authorized to approve PO ' . $PO->id() . '<br/>';
			} # end if
		} # end foreach po_id
		delete $param{po_id};
    } elsif ( $param{btnFunction} eq 'AuthorizeAndSend' ) {
        foreach my $po_id ( ref $param{po_id} eq 'ARRAY' ? @{$param{po_id}} : $param{po_id} ) {
            my $PO = new openprint::PurchaseOrder( $po_id );
            next if ! $PO->id();
            if ( $PO->can_authorize() ) {
                if ( $_ = $PO->authorize() ) {
                    $variable{error} .= $_ . '<br/>';
                } else {
                    $variable{information} .= 'PO ' . $po_id . ' has been authorized.<br/>';
					$variable{error} .= $PO->send_to_vendor();
                } # end if
            } else {
                $variable{error} .= 'You are authorized to approve PO ' . $PO->id() . '<br/>';
            } # end if
        } # end foreach po_id
        delete $param{po_id};

	} elsif ( $param{btnFunction} eq 'Decline' ) {
		foreach my $po_id ( ref $param{po_id} eq 'ARRAY' ? @{$param{po_id}} : split(',',$param{po_id}) ) {
			my $PO = new openprint::PurchaseOrder( $po_id );
			if ( $_ = $PO->decline( $param{reason} ) ) {
				$variable{error} .= $_ . '<br/>';
			} else {
				$variable{information} .= 'PO ' . $po_id . ' has been declined.<br/>';
			} # end if
		} # end foreach po_id
		delete $param{po_id};
	} elsif ( $param{btnFunction} eq 'reset' ) {
		my $uri = $r->uri();
		foreach my $key ( keys %session ) {
			if ( $key =~ /^$uri/ ) {
$log->error("$key deleted");
				delete $session{$key};
			}
		} # end foreach
	} elsif ( $param{btnFunction} eq 'Download' ) {
		my $uri = '/employee/purchase_order/history.html';
    my %search = (
      company_id  =>  $openprint::User->company_id(),
      ssi::date_filter( $uri.'?starting_end', 'created_on <=' ),
      ssi::date_filter( $uri.'?starting_start', 'created_on >=' ),
      order   =>  'id desc',
    );
    $search{deleted} = $session{$uri.'?deleted'} if exists $session{$uri.'?deleted'};
    $search{supplier_id} = $session{$uri.'?supplier_id'} if $session{$uri.'?supplier_id'};
    if ( $session{user_type} eq 'A' or openprint::usergroup::is_user_in( ['Accounting','Shipping','Inventory'], $session{user_id} ) ) {
			$search{created_by} = $session{$uri.'?created_by'} if $session{$uri.'?created_by'};
			$search{authorized_by} = $session{$uri.'?authorized_by'} if $session{$uri.'?authorized_by'};
    } else {
      $search{created_by} = [ sets::union( $session{user_id}, $openprint::User->assistant_ids(), $openprint::User->csr_ids() ) ];
    } # end if
    if ( $session{$uri.'?has_manifest'} ne '' ) {
      $search{'manifest_id is null'} = $session{$uri.'?has_manifest'} eq '1' ? 0 : 1;
    }
    $search{cancelled} = $session{$uri.'?cancelled'} if $session{$uri.'?cancelled'} ne '';
    $search{'item_id any'} = $session{$uri.'?item_id'} if $session{$uri.'?item_id'};

		my @header = ( 'Id', 'Supplier', 'Sub Total', 'Total', 'Created', 'Created By', 'Authorized By', 'Manifest', 'Item','Quantity','Unit Price', 'Units', 'Item Total', 'Docket', 'Printed Start','Printed End' );
		my @data;

    my $ac = sql::start_transaction( $dbh );
    my @POs = openprint::PurchaseOrder->find( %search );
    my %POs = map { $$_{id}, $_ } @POs;

    if ( @POs ) {
      my @po_ids = map { $$_{id} } @POs;
      foreach my $PC ( openprint::PurchaseOrder_Content->find( po_id=>\@po_ids ) ) {
        my $PO = $POs{$$PC{po_id}};
        $$PO{Contents} = [] if ! $$PO{Contents};
        push @{$$PO{Contents}}, $PC;
      }
      foreach my $PO ( @POs ) {
        $$PO{Contents} = [] if ! $$PO{Contents};
      }
    } # end if POs

		my %types = map { $_, $_ } split(',', $session{$uri.'?types'});
		my $total_quantity = 0;
		my $total_value = 0;

    foreach my $PO ( @POs ) {
      if ( $session{$uri.'?authorized'} eq 'Y' and $PO->authorized() ne '1' ) {
        $log->debug("Next want authd but isn't");
        next;
      }
      if ( $session{$uri.'?authorized'} eq 'N' and $PO->authorized() ne '0' ) {
        $log->debug("Next want not authd but is");
        next;
      }
      if ( $session{$uri.'?authorized'} eq 'U' and $PO->authorized() ne '' ) {
        $log->debug("Next want unauthd but is");
        next;
      }

      next if $session{$uri.'?vendor_category_id'} and ($PO->Supplier()->category_id() != $session{$uri.'?vendor_category_id'});
      if ( !$PO->can_view() ) {
        $log->debug('! can_view');
        next;
      }

      if ( $session{$uri.'?docket'} ) {
        my $next = 1;
        my $docket = $session{$uri.'?docket'};

        foreach my $C ($PO->Contents()) {
          if ( $C->docket() =~ /$docket/i ) {
            $next = 0;
            last;
          } # end if
        } # end foreach
        if ( $next ) {
          $log->debug("Next cuz $next contains $docket");
          next ;
        }
      } # end if

      if ( $param{contains} ) {
        my $next = 1;
        foreach my $C ($PO->Contents()) {
          if ( $C->description() =~ /$param{contains}/i ) {
            $next = 0;
            last;
          } elsif ( $C->item() =~ /$param{contains}/i ) {
            $next = 0;
            last;
          } # end if
        } # end foreach
        next if $next;
      } # end if

      if ( $session{$uri.'?department_id'} ) {
        next if ! sets::isin( $session{$uri.'?department_id'}, [ map { $_->department_id() } $PO->Contents() ] );
      } # end if


		#my @header = ( 'Id', 'Supplier', 'Sub Total', 'Total', 'Item','Quantity','Unit Price', 'Item Total' );
			foreach my $C ( $PO->Contents() ) {
				next if %types and ! $types{$$C{type_id}};
		#my @header = ( 'Id', 'Supplier', 'Sub Total', 'Total', 'Created', 'Created By', 'Manifest', 'Item','Quantity','Unit Price', 'Units', 'Item Total', 'Docket', 'Printed Start','Printed End' );
				push @data, (
						@$PO{'id','vendor_name','subtotal','total'},
						ssi::format_csv_date($$PO{created_on}), $PO->Created_By()->name(),
						$PO->Authorized_By()->name(),
						$PO->Manifest()->name(),
						$C->item(), $C->qty(), $C->price(), $C->units(), $C->total(), $C->docket());

				$total_quantity += $C->qty();
				$total_value += $C->total();

				my ( $printed_start, $printed_end );
				( my $docket ) = $C->docket() =~ /^\s*(\d+)\s*$/;
				if ( $docket ) {
					my $Order = openprint::Order->find_one( docket=>$docket );
					if ( $Order ) {
						foreach my $Project ( $Order->Projects() ) {
							($_) = sql::execute( undef, undef, q`SELECT MIN(dtmtimestamp) FROM Project_Log WHERE project_id=? AND description LIKE 'Marked Printed from %'`, $$Project{id} );
							$printed_start = $_ if (!$printed_start) or $printed_start gt $_;
							($_) = sql::execute( undef, undef, q`SELECT MAX(dtmtimestamp) FROM Project_Log WHERE project_id=? AND description LIKE 'Marked Printed from %'`, $$Project{id} );
							$printed_end = $_ if (!$printed_end) or $printed_end lt $_;
						}
					} # end if
				} # end if docket
				push @data, ssi::format_csv_date($printed_start), ssi::format_csv_date($printed_end);
			} # end foreach C
    } # end foreach PO
		push @data, '','Totals', '', '', '', '', '', '', '', $total_quantity, '', '', $total_value, '', '', '';
		sql::end_transaction( $dbh, $ac );

		misc::export_csv( $r, $log, \%variable, 'purchase_order_history_report.csv', \@header,\@data );	
	} # end if
	} # end if btnFunction
	_history();
	ssi::setup_date_select( $r->uri(), 'starting_start', -7 );
	ssi::setup_date_select( $r->uri(), 'starting_end', '' );
	$session{$r->uri().'?cancelled'} = '0' if ! exists $session{$r->uri().'?cancelled'};

} # end sub history

sub _history {
	ssi::save_params('/employee/purchase_order/history.html', ( 
				( map { 'starting_start_'.$_ } ( 'year', 'month','day' ) ),
				( map { 'starting_end_'.$_ } ( 'year', 'month','day' ) ),
				( map { 'paid_on_start_'.$_ } ( 'year', 'month','day' ) ),
				( map { 'paid_on_end_'.$_ } ( 'year', 'month','day' ) ),
				'authorized', 'supplier_id','created_by','authorized_by', 
				'deleted','types', 'item_id', 'cancelled', 'vendor_category_id', 'department_id', 'docket',
				'currency_id', 'has_manifest', 'has_attachments', 'paid', 'vendee_id',
				) );
} # end sub _purchase_orders

sub _po_autocomplete {
} # end sub _po_autocomplete

sub _po_select_contact {
} # end sub _po_select_contact

sub _purchase_order_supplier_address {
	my $PO = new openprint::PurchaseOrder( $param{po_id} );
	$PO->supplier_id( $param{supplier_id} );
	$PO->save() if $PO->id();
	$variable{PurchaseOrder} = $PO;
} # end sub _purchase_order_supplier_address

sub _po_content_line {
	my $PO = new openprint::PurchaseOrder( $param{po_id} );
	$variable{PurchaseOrder} = $PO;
	if ( $param{action} eq 'add' ) {
		my $C = new openprint::PurchaseOrder_Content( $param{po_content_id} );
		$C->save( {
			po_id		=>	$param{po_id},
			qty			=>	$param{qty},
			item		=>	$param{item},
			product		=>	$param{product},
			description	=>	$param{description},
			docket		=>	$param{docket},
			price		=>	$param{price},
			total		=>	$param{total},
			type_id		=>	$param{type_id},
			});
		$variable{C} = $C;
		$variable{error} .= $PO->save();
	} elsif ( $param{action} eq 'delete' ) {
		my $PO_Content = new openprint::PurchaseOrder_Content( $param{id} );
		if ( $PO_Content->id() ) {
			# Might have already been deleted
			$PO = $PO_Content->PurchaseOrder();
			$PO_Content->delete();
			$variable{error} .= $PO->save();
		} # end if
	} # end if
} # end sub _purchase_order_content_line

sub _notifications {
	my $PO = new openprint::PurchaseOrder( $param{po_id} );
	if ( ( $param{action} eq 'add' ) and $param{new_notification_id} ) {
		$PO->notifications( [ split(',', $param{notifications}), $param{new_notification_id} ] );
	} elsif ( $param{action} eq 'delete' ) {
		$PO->notifications( [ sets::exclude( [$param{notification_id}], [$PO->notifications()] ) ] );
	} # end if
	$variable{PurchaseOrder} = $PO;
} # end sub _notifications

sub _po_select_vendor {
}

sub _similar_pos {
} # end sub _similar_pos

sub _item_select {
} # end sub _item_select

sub items {
	if ( $param{btnFunction} eq 'Delete' ) {
		foreach my $item_id ( ref $param{item_id} eq 'ARRAY' ? @{$param{item_id}} : $param{item_id} ) {
			my $Item = new openprint::PurchaseOrder_Item( $item_id );
			if ( $_ = $Item->delete() ) {
				$variable{error} .= $_ . '<br/>';
			} # end if
		} # end foreach item_id
		delete $param{item_id};
	} elsif ( $param{btnFunction} eq 'Merge' ) {
		my @ids = sort( ref $param{item_id} eq 'ARRAY' ? @{$param{item_id}} : $param{item_id} );
		if ( ! @ids ) {
			$variable{error} .= 'No items selected. Nothing done.';
			return;
		} # end if
		my $final_id = shift @ids;
		my $Final_Item = new openprint::PurchaseOrder_Item( $final_id );
		if ( ! $Final_Item->id() ) {
			$variable{error} .= 'Unable to get final item. Nothing done.';
			return;
		} # end if
		foreach my $id ( @ids ) {
			foreach my $Content ( openprint::PurchaseOrder_Content->find('item_id'=>$id) ) {
				if ( $Content->item_id() != $id ) {
					$log->error("DANGER: Content has different item_id than asked for.");
					$variable{error} .= 'Crazy things have happened. Some merging has been done, some hasnt';
					return;
				} # end if
				$Content->save({'item_id'=>$final_id});
			} # end foreach Content
			my $Item = new openprint::PurchaseOrder_Item( $id );
			$variable{error} .= $Item->delete();
		} # end foreach id
	} else {
		ssi::save_params( '/employee/purchase_order/items.html', ( 'supplier_id','types', 'item_contains' ) );
	} # end if
} # end sub items

sub _items {
	ssi::save_params( '/employee/purchase_order/items.html', ( 'supplier_id','types', 'item_contains' ) );
} # end sub _items

sub _item_filter {
	ssi::save_params( '/employee/purchase_order/history.html', ( 'supplier_id' ) );
} # end sub

sub item {
	my $Item = $variable{Item} = new openprint::PurchaseOrder_Item( $param{item_id} );
	if ( $param{func} eq 'Save' ) {
		$variable{error} = $Item->save({
			'name'		=>	$param{name},
			'product'	=>	$param{product},
			'price'		=>	$param{price},
			'type_id'	=>	$param{type_id},
		});
	} elsif ( $param{func} eq 'Delete' ) {
		$variable{error} .= $Item->delete();
		%param = ();
		$variable{ExternalRedirect} = '/employee/purchase_order/items.html';
	} # end if
} # end sub item

sub _po_created_by_options {
} # end sub _po_created_by_options

sub _vendor_dropdown {
	ssi::save_params( '/employee/purchase_order/history.html', ( 'vendor_category_id', 'supplier_id' ) );
} # end sub _vendor_dropdown

sub _assets {
	$variable{PurchaseOrder} = new openprint::PurchaseOrder( $param{po_id} );
	if ( $param{action} eq 'delete' ) {
		my $PA = openprint::Object_Asset->find_one( 'object_type'=>'openprint::PurchaseOrder','object_id'=>$param{po_id}, 'asset_id'=>$param{asset_id} );
		if ( ! $PA ) {
			$variable{error} .= 'Asset not found. Nothing deleted.<br/>';
		} else {
			$PA->delete();
		} # end if
	} # end if
} # end sub _assets

sub _items_dropdown {
} # end sub _items_dropdown

sub authorizations {
	if ( $param{action} eq 'Save' ) {
		my @POC_Types = openprint::PurchaseOrder_ContentType->find('order'=>'lower(name)');
		foreach my $User ( openprint::User->find( company_id=>$param{company_id},
					( $param{user_id} ? ( id=>$param{user_id} ) : () ) ) ) {
			my $save = 0;
			if ( $User->purchasing_limit() != $param{'limit_per_po-'.$$User{id}} ) {
				$User->purchasing_limit( $param{'limit_per_po-'.$$User{id}} );
				$save = 1;
			} # end if
			if ( $User->purchasing_total_limit() != $param{'limit_total-'.$$User{id}} ) {
				$User->purchasing_total_limit( $param{'limit_total-'.$$User{id}} );
				$save = 1;
			} # end if
			$User->save() if $save;
			foreach my $POC_Type ( @POC_Types ) {
				if ( $User->po_limit( $$POC_Type{id} ) != $param{'limit-'.$$User{id}.'-'.$$POC_Type{id}} ) {
					$User->po_limit( $$POC_Type{id}, $param{'limit-'.$$User{id}.'-'.$$POC_Type{id}} );
				} # end if
			} # end foreach POC_TYPE	
		} # end foreach User
	} # end if
	_authorizations();
	$session{'/employee/purchase_order/authorizations.html?company_id'} = new openprint::User($session{user_id})->company_id() if ! $session{'/employee/purchase_order/authorizations.html?company_id'};
} # end sub authorizations

sub _authorizations {
	ssi::save_params( '/employee/purchase_order/authorizations.html', ( 'company_id','user_id' ) );
} # end sub _items

sub _payments_edit {
	my $PO = $variable{PurchaseOrder} = new openprint::PurchaseOrder( $param{po_id} );
	if ( ! $PO->id() ) {
		$variable{error} = "Invalid Purchase Order specified: $param{po_id}<br/>";
		return;
	} # end if
	if ( $param{action} eq 'Add' ) {
		my $ac = sql::start_transaction( $openprint::dbh );
		my $Payment = new openprint::Payment();
		$variable{error} .= $Payment->save({ 
				amount				=>	$param{amount},
				currency_id		=>	$$PO{currency_id},
				received_on		=>	$param{received_on},
				memo					=>	$param{description},
				recipient_id	=>	$PO->supplier_id(),
				payor_id			=>	$PO->company_id(),
				});
		if ( $variable{error} ) {
			sql::end_transaction( $openprint::dbh, $ac );
			return;
		}
		my $PO_Payment = new openprint::Object_Payment();
		$variable{error} .= $PO_Payment->save({payment_id=>$Payment->id(), object_id=>$PO->id(), object_type=>'openprint::PurchaseOrder', amount=>$param{amount} });
		$PO->Payments( undef );
		$PO->payments_total(undef);
		$PO->total(undef);
		$PO->paid_on(join('-', map { $param{'received_on_'.$_} } ( 'year','month','day' ) )) if (!$PO->paid_on()) and $PO->is_paid();
		$variable{error} .= $PO->save();
		$openprint::dbh->rollback() if $variable{error};
		sql::end_transaction( $openprint::dbh, $ac );
			my $L = new openprint::PurchaseOrder_Log();
			$L->save({
					user_id	=>	$session{user_id},
					po_id		=>	$PO->id(),
					reason	=>	'add payment ' . $PO_Payment->amount(),
					});
	} elsif ( $param{action} eq 'Delete' ) {
$openprint::log->debug("delet");
		if ( ! sets::isin( $param{payment_id}, [ map { $_->payment_id() } $PO->Payments() ] ) ) {
			$variable{error} .= "Payment $param{payment_id} is not attached to PO $$PO{id}<br/>";
			return;
		} # end if
		#my $PO_Payment = openprint::Object_Payment->find_one( object_id=>$$PO{id}, payment_id=>int($param{payment_id}) );
		my $PO_Payment = openprint::Object_Payment->find_one( object_id=>$$PO{id}, object_type=>'openprint::PurchaseOrder', payment_id=>int($param{payment_id}) );
		if ( ! $PO_Payment ) {
			$variable{error} .= 'Payment for this PO not found.';
			return;
		} # end if
		my $ac = sql::start_transaction( $openprint::dbh );
$openprint::log->debug("deleting");
		if ( ( $variable{error} = $PO_Payment->delete() ) or ( $variable{error} = $PO->save() ) ) {
			$openprint::dbh->rollback();
		} # end if
		sql::end_transaction( $openprint::dbh, $ac );
			my $L = new openprint::PurchaseOrder_Log();
			$L->save({
					user_id	=>	$session{user_id},
					po_id		=>	$PO->id(),
					reason	=>	'delete payment ' . $PO_Payment->amount(),
					});
	} # end if action
} # end sub payments_edit

sub _taxes_edit {
	my $PO = $variable{PurchaseOrder} = new openprint::PurchaseOrder( $param{po_id} );
	if ( ! $PO->id() ) {
		$variable{error} = "Invalid Purchase Order specified: $param{po_id}<br/>";
		return;
	} # end if

	if ( $param{action} ) {
		if ( $param{action} eq 'add' ) {
			my $ac = sql::start_transaction( $openprint::dbh );
			my $Tax = new openprint::PurchaseOrder_Tax();
			$variable{error} .= $Tax->save( { purchaseorder_id => $param{po_id}, tax_id=>$param{tax_id}, charge=>1, rate=>undef } );
			if ( $variable{error} ) {
				$openprint::dbh->rollback();
				sql::end_transaction( $openprint::dbh, $ac );
				return;
			}
			$variable{error} .= $PO->save( );
			if ( $variable{error} ) {
				$openprint::dbh->rollback();
				sql::end_transaction( $openprint::dbh, $ac );
				return;
			}
			$variable{error} .= $PO->save( );
			my $L = new openprint::PurchaseOrder_Log();
			$L->save({
					user_id	=>	$session{user_id},
					po_id		=>	$PO->id(),
					reason	=>	'add tax ' . $Tax->name(),
					});
			sql::end_transaction( $openprint::dbh, $ac );
		} elsif ( $param{action} eq 'delete' ) {
			my $Tax = new openprint::Tax( $param{tax_id} );
			my $PO_Tax;
			foreach my $T ( $PO->Taxes() ) {
				if ( $$T{tax_id} == $param{tax_id} ) {
					$PO_Tax = $T;
					last;
				}
			}
			if ( ! $PO_Tax ) {
				$variable{error} .= "Tax $$Tax{name} is not attached to PO $$PO{id}<br/>";
				return;
			} # end if
			my $ac = sql::start_transaction( $openprint::dbh );
			$variable{error} .= $PO_Tax->delete();
			if ( $variable{error} ) {
				$openprint::dbh->rollback();
				sql::end_transaction( $openprint::dbh, $ac );
				return;
			}
			$PO->Taxes( undef );
			$variable{error} .= $PO->save();
			if ( $variable{error} ) {
				$openprint::dbh->rollback();
				sql::end_transaction( $openprint::dbh, $ac );
				return;
			}
			my $L = new openprint::PurchaseOrder_Log();
			$L->save({
					user_id	=>	$session{user_id},
					po_id		=>	$PO->id(),
					reason	=>	'delete tax ' . $PO_Tax->name(),
					});
			sql::end_transaction( $openprint::dbh, $ac );
		} elsif ( $param{action} eq 'reset' ) {
			$PO->set( \%param );
			# Reload $PO->Taxes() with current set
			$PO->default_Taxes();
			$variable{error} .= $PO->save();
			my $L = new openprint::PurchaseOrder_Log();
			$L->save({
					user_id	=>	$session{user_id},
					po_id		=>	$PO->id(),
					reason	=>	'update taxes',
					});
		} # end if action
	} # end if action
} # end sub taxes_edit

sub _logs {
	$variable{PurchaseOrder} = new openprint::PurchaseOrder( $param{po_id} );
}

sub _pay_popup {
	$variable{PurchaseOrder} = new openprint::PurchaseOrder( $param{po_id} );
}

1;
__END__
