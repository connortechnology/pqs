package openprint::employee_claim;
use strict;
require sql;
require misc;

require openprint::RFIDTag;
require openprint::Claim;
require openprint::Claim_Content;
require openprint::Claim_Payment;
require openprint::PurchaseOrder;
require openprint::Asset;
require openprint::Claim_Asset;

use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

sub history {
	if ( $param{'btnFunction'} eq 'Delete' ) {
		foreach my $claim_id ( ref $param{'claim_id'} eq 'ARRAY' ? @{$param{'claim_id'}} : split(',',$param{'claim_id'}) ) {
			my $Claim = new openprint::Claim( $claim_id );
			$variable{'error'} .= $Claim->delete();

		} # end foreach claim_id
		%param = ();
	} # end if
	_history();
	ssi::setup_date_select( '/employee/claim/history.html', 'created_on_start', -31 );
	ssi::setup_date_select( '/employee/claim/history.html', 'created_on_end', '' );
	ssi::setup_date_select( '/employee/claim/history.html', 'updated_on_start', '' );
	ssi::setup_date_select( '/employee/claim/history.html', 'updated_on_end', '' );

} # end sub history

sub _history {
	ssi::save_params( '/employee/claim/history.html', ( 
				'created_on_start_year','created_on_start_month','created_on_start_day',
				'created_on_end_year','created_on_end_month','created_on_end_day',
				'updated_on_start_year','updated_on_start_month','updated_on_start_day',
				'updated_on_end_year','updated_on_end_month','updated_on_end_day',
				'supplier_id', 'created_by', 'status' ) );
} # end sub _claims

sub view {
	$param{'claim_id'} =~ s/\D//g;
	my $Claim = new openprint::Claim( $param{'claim_id'} );
	if ( $param{'btnFunction'} eq 'Delete' ) {
		$variable{'error'} .= $Claim->delete();
		if ( ! $variable{'error'} ) {
			$variable{'Redirect'} = '/employee/claim/history.html';
			%param = ();
		} # end if
	} elsif ( $param{'btnFunction'} eq 'Undelete' ) {
		$variable{'error'} .= $Claim->undelete();
	} elsif ( $param{'btnFunction'} eq 'Save' ) {
		if ( ! $Claim->id() ) {
			$Claim->id( $param{'claim_id'} );
			$variable{'error'} .= $Claim->save({'supplier_id'=>$param{'supplier_id'}});
		} # end if
		foreach my $C ( $Claim->Contents() ) {
			if ( ! $param{"rfidtag_id-$$C{id}"} ) { $param{"rfidtag_id-$$C{id}"} = undef; };
			if ( ! $param{"skid_id-$$C{id}"} ) { $param{"skid_id-$$C{id}"} = undef; };

			if ( $param{"rfidtag_id-$$C{id}"} and ! $param{"skid_id-$$C{id}"} ) {
				my $RFIDTag = new openprint::RFIDTag( $param{"rfidtag_id-$$C{id}"} );
				$param{"skid_id-$$C{id}"} = $RFIDTag->skid_id();
			} # end if
			if ( $param{"skid_id-$$C{id}"} and ! $param{"weight-$$C{id}"} ) {
				my $Skid = new openprint::Skid( $param{"skid_id-$$C{id}"} );
				my @SkidContents	= $Skid->Contents();
				if ( @SkidContents == 1 ) {
					$param{"weight-$$C{id}"} = $SkidContents[0]->quantity();
				} # end if
			} # end if
			$variable{'error'} .= $C->save( {
					'quantity'		=>	int( $param{"quantity-$$C{id}"} ),
					'quantity_units'	=>	$param{"quantity_units-$$C{id}"},
					'weight'		=>	$param{"weight-$$C{id}"} ? int($param{"weight-$$C{id}"}) : undef,
					'weight_units'	=>	$param{"weight_units-$$C{id}"},
					'cost'			=>	$param{"cost-$$C{id}"},
					'cost_units'	=>	$param{"cost_units-$$C{id}"},
					'skid_id'		=>	$param{"skid_id-$$C{id}"},
					'reason'		=>	$param{"reason-$$C{id}"},
					'description'	=>	$param{"description-$$C{id}"},
					} );
		} # end foreach Contents
		foreach my $Tax ( $Claim->Taxes() ) {
			# Order is important here.
			$Tax->charge($param{'tax_charge-'.$Tax->id()});
			$Tax->amount(undef);
			$Tax->save();
		} # end foreach Tax
		$Claim->filed_on( $param{filed} ? join('-', @param{'filed_on_year','filed_on_month','filed_on_day'} ) : undef );
		$Claim->sent_to_accounts_on( $param{'sent_to_accounts'} ? join('-', @param{'sent_to_accounts_on_year','sent_to_accounts_on_month','sent_to_accounts_on_day'} ) : undef );
		$Claim->invoiced_on( $param{'invoiced'} ? join('-', @param{'invoiced_on_year','invoiced_on_month','invoiced_on_day'} ) : undef );
		$Claim->cancelled_on( $param{'cancelled'} ? join('-', @param{'cancelled_on_year','cancelled_on_month','cancelled_on_day'} ) : undef );
		$Claim->paid_on( $param{'paid'} ? join('-', @param{'paid_on_year','paid_on_month','paid_on_day'} ) : undef );
		$param{'docket'} =~ s/[^,\d]//g;
		$param{'docket'} = [ split(',',$param{'docket'}) ];

		$variable{'error'} .= $Claim->save( \%param );
		if ( ! $variable{'error'} ) {
			$variable{'information'} .= 'Information successfully stored.<br/>';
		} # end if
		%param = ();
	} elsif ( $param{'btnFunction'} eq 'Send' ) {
		$variable{'information'} .= $Claim->send();
	} elsif ( $param{'btnFunction'} eq 'SendToMe' ) {
		$variable{'information'} .= $Claim->send( new openprint::User( $session{'user_id'} ) );
	} elsif ( $param{'btnFunction'} eq 'Attach' ) {
		my $Asset = new openprint::Asset();
		$variable{'error'} .= $Asset->save( \%param );
		if ( ! $variable{'error'} ) {
			$variable{'information'} .= 'Information successfully stored.<br/>';
		} # end if
		if ( $param{'filename'} ) {
			my $upload = $r->upload('filename');
			if ( ! $upload ) {
				$Asset->save({'filename'=>''});
				$variable{'error'} .= "There was no upload for $param{'filename'}<br/>";
			} elsif ( ! $upload->link( $Asset->on_disk_path() ) ) {
				$variable{'error'} .= "There was an error saving file $param{'filename'} to " . $Asset->on_disk_path() . ": $!<br/>";
				$Asset->save({'filename'=>''});
			} else {
				$variable{'information'} .= "File $param{'filename'} was uploaded successfully.<br/>";
			} # end if
		} # end if
		if ( $Asset->id() ) {
			my $Claim_Asset = new openprint::Claim_Asset();
			$variable{'error'} .= $Claim_Asset->save({'claim_id'=>$param{'claim_id'},'asset_id'=>$Asset->id()});
		} # end if
		%param = ();
	} # end if btnfunction
	$variable{'Claim'} = $Claim;
} # end sub view

sub edit {
	$variable{'Claim'} = new openprint::Claim($param{'claim_id'});
	if ( $param{'btnFunction'} eq 'Save' ) {
		my $Claim = $variable{'Claim'};
		$Claim->id( $param{'claim_id'} ) if ! $Claim->id();
		$Claim->filed_on( $param{'filed'} ? join('-', @param{'filed_on_year','filed_on_month','filed_on_day'} ) : undef );
		$Claim->sent_to_accounts_on( $param{'sent_to_accounts'} ? join('-', @param{'sent_to_accounts_on_year','sent_to_accounts_on_month','sent_to_accounts_on_day'} ) : undef );
		$Claim->invoiced_on( $param{'invoiced'} ? join('-', @param{'invoiced_on_year','invoiced_on_month','invoiced_on_day'} ) : undef );
		$Claim->cancelled_on( $param{'cancelled'} ? join('-', @param{'cancelled_on_year','cancelled_on_month','cancelled_on_day'} ) : undef );
		$Claim->paid_on( $param{'paid'} ? join('-', @param{'paid_on_year','paid_on_month','paid_on_day'} ) : undef );
		$param{'docket'} =~ s/[^,\d]//g;
		$param{'docket'} = [ split(',',$param{'docket'}) ];

		$variable{'error'} .= $Claim->save( \%param );
	} # end if
} # end sub edit

sub _contents {
	if ( ! $param{'claim_id'} ) {
		$variable{'error'} .= 'No claim id.	Please enter the claim id before adding items to it.<br/>';
		return;
	} # end if
	my $Claim = new openprint::Claim( $param{'claim_id'} );
	if ( $param{'claim_id'} and ! $Claim->id() ) {
		$variable{'error'} .= $Claim->save({'id'=>$param{'claim_id'}});
	} # end if
	$variable{'Claim'} = $Claim;

	# On any loading of the contents, save anything that may have been changed
	foreach my $C ( $Claim->Contents() ) {
		next if ( $param{'action'} eq 'Delete' ) and ( $C->id() == $param{'content_id'} );
		if ( ( $C->skid_id() != $param{'skid_id-'.$C->id()} )
				or ( $C->description() ne $param{'description-'.$C->id()} )
				or ( $C->quantity() != $param{'quantity-'.$C->id()} )
				or ( $C->weight() != $param{'weight-'.$C->id()} )
				or ( $C->weight_units() != $param{'weight_units-'.$C->id()} )
				or ( $C->cost() != $param{'cost-'.$C->id()} )
				or ( $C->cost_units() != $param{'cost_units-'.$C->id()} )
			) {
			$variable{'error'} .= $C->save( {
					'skid_id'	=>	$param{'skid_id-'.$C->id()},
					'description'	=>	$param{'description-'.$C->id()},
					'weight'	=>	$param{"weight-$$C{id}"} ? sprintf('%d', $param{'weight-'.$C->id()}) : undef,
					'weight_units'	=>	$param{'weight_units-'.$C->id()},
					'quantity'	=>	sprintf('%d', $param{'quantity-'.$C->id()}),
					'cost'		=>	$param{'cost-'.$C->id()},
					'cost_units'	=>	$param{'cost_units-'.$C->id()},
					} );
		} # end if Content has changed
	} # end foreach C

	if ( $param{'action'} eq 'Delete' ) {
		my $C = new openprint::Claim_Content( $param{'content_id'} );
		$variable{'Claim'} = $C->Claim();
		$variable{'error'} .= $C->delete();
	} elsif ( $param{'action'} eq 'Add' ) {
		my $C = new openprint::Claim_Content();
		$variable{error} .= $C->save( { claim_id	=>	$Claim->id(), type_id=>$param{type_id} } );
	} # end if
} # end sub _contents

sub _select_vendor {
} # end sub _select_vendor
sub _select_contact {
} # end sub _select_contact
sub _check_for_skid {
} # end sub _check_for_skid
sub _editors {
	my $Claim = $variable{'Claim'} = new openprint::Claim( $param{'claim_id'} );
	if ( $param{'action'} eq 'add' ) {
		$variable{'error'} = $Claim->save({'editor_id'=>[ sets::union( ( $Claim->editor_id() ? @{$Claim->editor_id()} : () ), $param{'editor_id'} ) ]});
	} elsif ( $param{'action'} eq 'remove' ) {
		$variable{'error'} = $Claim->save({'editor_id'=>[ sets::exclude( [$param{'editor_id'}], $Claim->editor_id() ) ]});
	} # end if
} # end sub _editors

sub _also_notify {
	my $Claim = $variable{'Claim'} = new openprint::Claim( $param{'claim_id'} );
	if ( $param{'action'} eq 'add' ) {
		$variable{'error'} = $Claim->save({'also_notify'=>[ sets::union( ( $Claim->also_notify() ? @{$Claim->also_notify()} : () ), $param{'also_notify'} ) ]});
	} elsif ( $param{'action'} eq 'remove' ) {
		$variable{'error'} = $Claim->save({'also_notify'=>[ sets::exclude( [$param{'also_notify'}], $Claim->also_notify() ) ]});
	} # end if
} # end sub _also_notify

sub _assets {
	$variable{'Claim'} = new openprint::Claim( $param{'claim_id'} );
	if ( $param{'action'} eq 'delete' ) {
		my $CA = new openprint::Claim_Asset( { 'claim_id'=>$param{'claim_id'}, 'asset_id'=>$param{'asset_id'} } );
		$CA->delete();
	} # end if
} # end sub _assets

sub _payments {
	my $Claim = $variable{'Claim'} = new openprint::Claim( $param{'claim_id'} );
	if ( $param{'action'} eq 'addpayment' ) {
		if ( ! Date::Calc::check_date( @param{'payment_when_year','payment_when_month','payment_when_day'} ) ) {
			$variable{error} .= 'Invalid date selected.<br/>';
		} else {
			my $Payment = new openprint::Payment();
			$variable{error} .= $Payment->save({
					amount		=>	$param{amount},
					memo			=>	$param{notes},
					recipient_id	=>	$Claim->company_id(),
					payor_id		=>	$Claim->supplier_id(),
					received_on		=>	sprintf('%.4d-%.2d-%.2d', @param{'payment_when_year','payment_when_month','payment_when_day'} ),
					transaction_id	=>	$param{transaction_id},
					currency_id		=>	$Claim->currency_id(),
					completed		=>	1,
					});
			if ( ! $variable{error} ) {
				my $CP = new openprint::Claim_Payment();
				$variable{error} .= $CP->save({
						claim_id	=>	$Claim->id(),
						payment_id	=>	$Payment->id(),
						amount		=>	$param{amount},
						});
			} # end if no error
		} # end if valid date
	} # end if add payment
} # end sub _payments

1;
__END__
