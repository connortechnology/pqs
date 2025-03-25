package openprint::handheld_paper_inventory;

use strict;
#use warnings;

use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

require openprint::RFIDTag;
require openprint::Skid;

sub rfidtag_details {
	$param{'skid_id'} =~ s/\D//g;
	$param{'rfidtag_id'} =~ s/\D//g;

	if ( $param{'skid_id'} and ! $param{'rfidtag_id'} ) {
		my $Skid = new openprint::Skid( $param{'skid_id'} );
		$param{'rfidtag_id'} = $Skid->rfidtag_id();
	} # end if

	if ( length $param{'rfidtag_id'} != 15 ) {
		my @RFIDTags = openprint::RFIDTag->find('id_like'=>'%'.$param{'rfidtag_id'},'valid'=>1);
		if ( @RFIDTags != 1 ) {
			$variable{'error'} = 'Invalid RFID Tag # ' . $param{'rfidtag_id'} . ' : length 15 != ' . length $param{'rfidtag_id'};
			return;
		} else {
			$param{'rfidtag_id'} = $RFIDTags[0]->id();
		} # endif
	} # end if
	@variable{'skid_id','rfidtag_id'} = @param{'skid_id','rfidtag_id'};

	if ( ! $param{'rfidtag_id'} ) {
		$variable{'error'} .= 'Please specify the tag id.<br/>';
		return;
	} # end if
	my $TAG = new openprint::RFIDTag( $param{'rfidtag_id'} );
	if ( ! $TAG->id() ) {
		my $error = $TAG->save({'id'=>$param{'rfidtag_id'}});
		if ( ! $error ) {
			$variable{'information'} .= 'Tag created.<br/>';
		} else {
			$variable{'error'} .= 'Error creating tag: ' . $error . '<br/>';
			return;
		} # end if
	} # end if

	if ( $param{'btnFunction'} eq 'Go' ) {
		delete $param{'location_id'};
	} elsif ( $param{'btnFunction'} eq 'Save' ) {
		$TAG->location_id( $param{'location_id'} ) if $param{'location_id'};
		if ( $TAG->type() eq 'Skid' ) {
			my $Skid = $TAG->Skid();

			if ( ! $Skid->id() ) {
				$Skid->id( $param{'skid_id'} );
				$Skid->rfidtag_id( $TAG->id() );
				$variable{'error'} .= $Skid->save();
				if ( $Skid->empty() ) {
					$variable{'information'} .= sprintf('Skid <a href="/handheld/paper_inventory/skid.html?skid_id=%1$d">%1$d</a> is empty.<br/>', $Skid->id() );
				} # end if
			} # end if
			foreach my $C ( $Skid->Contents() ) {
				if ( ( $param{"in_stock-$$C{id}"} != $C->quantity() ) or ( $param{"condition_id-$$C{id}"} != $C->condition_id() ) ) {
					$variable{'error'} .= $C->save({
							'quantity'		=>	$param{"in_stock-$$C{id}"},
							'condition_id'	=>	$param{"condition_id-$$C{id}"},
							});
				} # end if
			} # end foreach paper on skid
				
			if ( $param{'verification_code'} ) {
				my $SV = new openprint::Skid_Verification();
				$param{'verification_code'} =~ s/^[Vv](.*)$/$1/;
				$variable{'error'} .= $SV->save({
						'user_id'	=>	$session{'user_id'},
						'skid_id'	=>	$Skid->id(),
						'code'		=>	$param{'verification_code'},
						});
			} # end if verification_code
		} # end if is a Skid
		$variable{'error'} .= $TAG->save();
		if ( ! $variable{'error'} ) {
			$variable{'information'} .= 'TAG saved successfully.';
			delete $variable{'skid_id'};
		} else {
			$log->error($variable{'error'});

		} # end if
		delete $param{'location_id'};
	} # end if Save
	$variable{'RFIDTag'} = $TAG;
} # end sub rfidtag_details

sub skid {

	$param{'skid_id'} =~ s/\D//g;
	$param{'Docket'} =~ s/\D//g;
	$param{'Project'} =~ s/\D//g;
	$param{'Operator'} =~ s/\D//g;

	@variable{'skid_id','rfidtag_id','Quantity','Docket','Project','Operator'} = @param{'skid_id','rfidtag_id','Quantity','Docket','Project','Operator'};
$openprint::log->debug("SKID_ID: $variable{'skid_id'}");
	$variable{'Operator'} = $session{'user_id'} if ! $variable{'Operator'};
	my $Operator = new openprint::User( $variable{'Operator'} );
	$variable{'OperatorName'} = $Operator->name();

	my $Skid = new openprint::Skid( $variable{'skid_id'} );
	$variable{'Skid'} = $Skid;
	if ( ! $param{'skid_id'} ) {
		$variable{'error'} .= 'Please specify the skid #.<br/>';
		return;
	} elsif ( ! $Skid->id() ) {
		$variable{'error'} .= 'Invalid skid #.<br/>';
		return;
	} # end if


	if ( $param{'Quantity'} and ($param{'Docket'} or $param{'Project'} ) ) {
		if ( $param{'btnFunction'} eq 'CheckIn' ) {
			openprint::employee_inventory::check_in( @param{'skid_id','paper_id', 'Quantity','Project','Docket'} );
		} elsif ( $param{'btnFunction'} eq 'CheckOut' ) {
			openprint::employee_inventory::check_out( @param{'skid_id','paper_id', 'Quantity','Project','Docket'} );
		} # end if CHeckin/CheckOut
	} elsif ( $param{'btnFunction'} eq 'Save' ) {
		$Skid->rfidtag_id( $param{'rfidtag_id'} );
		foreach my $C ( $Skid->Contents() ) {
			my $paper_id = $C->paper_id();
			if ( $param{"in_stock-$paper_id"} != $C->quantity() ) {
				$C->save({'quantity'=>$param{"in_stock-$paper_id"}});
			} # end if
		} # end foreach paper on skid
		$variable{'error'} .= $Skid->save();

		my $TAG = new openprint::RFIDTag( $param{'rfidtag_id'} );
		if ( ! $TAG->id() ) {
			my $error = $TAG->save({'id'=>$param{'rfidtag_id'}});
			if ( ! $error ) {
				$variable{'error'} .= 'Tag created.<br/>';
			} else {
				$variable{'error'} .= 'Error creating tag: ' . $error . '<br/>';
				return;
			} # end if
		} # end if

		if ( $param{'verification_code'} ) {
			my $SV = new openprint::Skid_Verification();
			$param{'verification_code'} =~ s/^[Vv](.*)$/$1/;
			$variable{'error'} .= $SV->save({
					'user_id'	=>	$session{'user_id'},
					'skid_id'	=>	$Skid->id(),
					'code'		=>	$param{'verification_code'},
					});
		} # end if
	} # end if quantity and docket
	$variable{'Skid'} = $Skid;
} # end sub skid

1;
__END__
