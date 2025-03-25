use strict;
package openprint::ManifestContent;
our @ISA = qw(openprint::Object);
require openprint::Object;

use Math::Round qw( nearest );
use openprint ();
use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults );

require openprint::Manifest;
require openprint::Skid;
require openprint::RFIDTag;
require openprint::SkidContent;
require openprint::Location;

$debug = 0;

$table = 'manifestcontents';
$serial = 'manifestcontents_id_seq';

%fields = (
	id							=>	'id',
	manifest_id			=>	'manifest_id',
	skid_id					=>	'skid_id',
	Skid						=>	undef,
	quantity				=>	'quantity',
	type_id					=>	'type_id',
	rfidtag_id			=>	'rfidtag_id',
	RFIDTag					=>	undef,
	manufacturers_id	=>	'manufacturers_id',
	location_id			=>	'location_id',
);
%find_fields = (
	paper_id	=>	'(SELECT paper_id FROM Manifest_Content_Types WHERE manifest_content_types.manifest_id = manifestcontents.manifest_id)',
);

%transforms = (
	quantity	=> [ 's/\D//g' ],
	type_id		=> [ 's/\D//g' ],
	manufacturers_id	=>	[ 'tr/[a-z]/[A-Z]/' ],
);

%defaults = (
	quantity			=> 0,
	manufacturers_id	=>	undef,
	skid_id				=>	undef,
	rfidtag_id			=>	undef,
	location_id			=>	undef,
);

sub skid_id {
	if ( @_ > 1 ) {
$openprint::log->debug("Setting skid_id to $_[1]");
		$_[0]{skid_id} = $_[1] ? $_[1] : undef;
		delete $_[0]{Skid};
	} # end if
	if ( ( ! $_[0]{skid_id} ) and $_[0]{rfidtag_id} and ( ! $_[0]{Skid} ) ) {
		my $Tag = $_[0]->RFIDTag();
		$_[0]{Skid} = $Tag->Skid() if $Tag->skid_id();
	} # end if
	return $_[0]{Skid}->id() if ( ! $_[0]{skid_id} ) and $_[0]{Skid};
	return $_[0]{skid_id};
} # end sub skid_id

sub Skid {
	if ( @_ > 1 ) {
		$_[0]{Skid} = $_[1];
		$_[0]{skid_id} = ref $_[0]{Skid} eq 'openprint::Skid' ? $_[0]{Skid}{id} : undef;
		$_[0]{skid_id} = undef if ! $_[0]{skid_id};
	} # end if
	if ( ! $_[0]{Skid} ) {
		$_[0]{Skid} = new openprint::Skid( $_[0]->skid_id() );
	} # end if
	return $_[0]{Skid};
} # end sub Skid

sub RFIDTag {
	if ( @_ > 1 ) {
		$_[0]{RFIDTag} = $_[1];
		#$_[0]{rfidtag_id} = ref $_[0]{RFIDTag} eq 'openprint::RFIDTag' ? $_[0]{RFIDTag}{id} : undef;
	} # end if
	if ( ! $_[0]{RFIDTag} ) {
		if ( $_[0]{rfidtag_id} ) {
			$_[0]{RFIDTag} = new openprint::RFIDTag( $_[0]{rfidtag_id} );
			if ( ! $_[0]{RFIDTag}->id() ) {
				$_[0]{RFIDTag} = new openprint::RFIDTag();
				$_[0]{RFIDTag}->id( $_[0]{rfidtag_id} );
			} # end if
		} else {
			$_[0]{RFIDTag} = $_[0]->Skid()->RFIDTag();
		} # end if
	} # end if
	return $_[0]{RFIDTag};
} # end sub RFIDTag

sub Manifest {
	return new openprint::Manifest( $_[0]{manifest_id} );
} # end sub Manifest

sub Type {
require openprint::Manifest_Content_Type;
	return new openprint::Manifest_Content_Type( $_[0]{type_id} );
} # end sub Type

sub units {
	my $Type = $_[0]->Type();
	if ( $Type->paper_id() ) {
		return $Type->Paper()->type() eq 'Roll' ? 'lbs' : 'sheets';
	} # end if
} # end sub units

sub value {
	if ( @_ > 1 ) {
		$_[0]{value} = $_[1];
	} # end if
	if ( ! defined $_[0]{value} ) {
		my $Type = $_[0]->Type();
		my $lbs = $Type->type() eq 'Roll' ? $_[0]{quantity} : $_[0]{quantity} * $Type->Paper()->sheet_weight();
		if ( $Type->cost() ) {
			$_[0]{value} = Math::Round::nearest( .01, $Type->cost() * $lbs/100 );
$openprint::log->debug("Setting MC value from Type->cost $$Type{cost} * $lbs/100 = $_[0]{value}"); 
			return $_[0]{value};

		}

		my $POC = $Type->PurchaseOrder_Content();
		$POC = $Type->PurchaseOrder_Content({ignore_fsc=>1}) if ! $POC;
		if ( $POC ) {
			$_[0]{value} = Math::Round::nearest( .01, $POC->price() * $lbs/100 );
		} else {
			$_[0]{value} = 0;
		} # end if	
	} # end if	
	return $_[0]{value};
} # end sub value

sub delete {
	if ( ! $_[0]{'id'} ) {
		$openprint::log->error("Called delete on ManifestContent with no id.");
		return;
	} # end if
	$_[0]->SUPER::delete();
} # end sub delete

sub manufacturers_id {
	if ( @_ > 1 ) {
		$_[0]{manufacturers_id} = $_[1];
	} # end if
	if ( ( ! $_[0]{manufacturers_id} ) and $_[0]{skid_id} ) {
		my $Skid = new openprint::Skid( $_[0]{skid_id} );
		$_[0]{manufacturers_id} = $Skid->manufacturers_id();
	} # end if
	return $_[0]{manufacturers_id};
} # end sub manufacturers_id

sub location_id {
	if ( @_ > 1 ) {
		$_[0]{location_id} = $_[1];
	} # end if
	if ( ( ! $_[0]{location_id} ) ) {
		if ( $_[0]{skid_id} ) {
			return $_[0]->Skid()->location_id();
		} elsif ( $_[0]{rfidtag_id} ) {
			return $_[0]->RFIDTag()->location_id();
		} # endif
	} # end if
	return $_[0]{location_id};
} # end sub location_id

sub Location {
	return new openprint::Location($_[0]->location_id());
} # end sub Location

sub fix {
	my ( $MC ) = @_;
	my $Type = $_[0]->Type();
	my $Manifest = $_[0]->Manifest();
	my $Skid = $MC->Skid();

	my $error;
	my $ac = sql::start_transaction( $openprint::dbh );

	my @SkidContents = $Skid->Contents();
	my %SkidContents = map { $$_{paper_id}, $_ } @SkidContents;

	if ( $SkidContents{$$Type{paper_id}} ) {
# Have the right paper., remove the ones that don't match.
		$openprint::log->debug('desired paper exists');
		foreach my $paper_id ( keys %SkidContents ) {
			next if $$Type{paper_id} == $paper_id;
			my $SC = $SkidContents{$paper_id};
			if ( $$SC{paper_id} ) {
				my $Paper = $SC->Paper();
				my $PI = new openprint::PaperInventory();
				$error .= $PI->save({
						user_id=>$openprint::session{user_id},
						skid_id=>$$SC{skid_id},
						paper_id=>$paper_id,
						quantity=>-1*$SC->quantity(),
						comment=>qq`Removed stock by manifest <a href="/employee/inventory/manifest_view.html?manifest_id=$$Manifest{id}">$$Manifest{name}</a>.`
						});
			} # end if
			$error .= $SC->delete();
		} # end foreach paper_id
	} else {
		$openprint::log->debug('desired paper does not exist');
# Change the stock
		my $checked_out = 0;
		require openprint::PaperAllocation;
		foreach my $paper_id ( keys %SkidContents ) {
			my $SC = $SkidContents{$paper_id};
			my $Paper = $SC->Paper();
			$checked_out = 1 if $SC->checked_out();

			{
				my $PI = new openprint::PaperInventory();
				$error .= $PI->save({
						user_id=>$openprint::session{user_id},
						skid_id=>$$SC{skid_id},
						paper_id=>$SC->paper_id(),
						quantity=>-1*$SC->quantity(),
						comment=>'Changed stock from ' . $Paper->to_string() . ' to ' . $Type->Paper()->to_string()
						});
			}
# Change the type to the new type
			foreach my $PA ( openprint::PaperAllocation->find(
						'skid_ids any'=>$SC->skid_id(),
						paper_id=>$SC->paper_id() ) ) {
				$error .= $PA->save({paper_id=>$Type->Paper()->id()});
			} # end foreach PA
			{
				my $PI = new openprint::PaperInventory();
				$error .= $PI->save({
						user_id=>$openprint::session{user_id},
						skid_id=>$$SC{skid_id},
						paper_id=>$Type->paper_id(),
						quantity =>$SC->quantity(),
						comment=>'Changed stock from ' . $Paper->to_string() . ' to ' . $Type->Paper()->to_string()
						});
			}
			$error .= $SC->save({ paper_id => $$Type{paper_id} });
			$error .= $Paper->save();
		} # end foreach paper_id
		if ( $checked_out ) {
			my $SC = $SkidContents{$$Type{paper_id}};
			if ( $$SC{quantity} ) {
				my $PI = new openprint::PaperInventory();
                $error .= $PI->save({ user_id=>$openprint::session{user_id}, skid_id=>$$SC{skid_id}, paper_id=>$$SC{paper_id}, quantity=>-1*$SC->quantity(),
                        comment=>'Checked out because other stock was checked out'} );
			} # end if 
		} # end if used
	} # end if
	$error .= $Type->Paper()->save();
	if ( $$Skid{id} and $$MC{manufacturers_id} and ( $$MC{manufacturers_id} ne $$Skid{manufacturers_id} ) ) {
		if ( ! $$Skid{manufacturers_id} ) {
			my $S = openprint::Skid->find_one(manufacturers_id=>$$MC{manufacturers_id}, deleted=>[1,0] );
			if ( $S and $S->deleted() ) {
				$S->destroy();
				$S = undef;
			} # end if
			if ( $S ) {
# Only do it if the skid doesn't have one assigned.
				if ( $Skid->rfidtag_id() and ( $Skid->rfidtag_id() eq $MC->rfidtag_id() ) ) {
# Keep the manifest skid.
					$error .= $Skid->merge( $S );
				} elsif ( $S->rfidtag_id() and ( $S->rfidtag_id() eq $MC->rfidtag_id() ) ) {
					$error .= $S->merge( $Skid );
					$error .= $MC->save({skid_id=>$$S{id}});
				}  #end if
			} else { # $S
				$error .= $Skid->save({manufacturers_id=>$$MC{manufacturers_id}});
			} # end if
		} else {
			if ( ! openprint::ManifestContent->find(manufacturers_id=>$$Skid{manufacturers_id},skid_id=>$$Skid{id} ) ) {
				$Skid->save({manufacturers_id=>$$MC{manufacturers_id}});
			} else {
# No longer assigned
				$openprint::log->debug("Merging skid due to manufacturers id");
				if ( ! $MC->rfidtag_id() ) {
					my $S = openprint::Skid->find_one(manufacturers_id=>$$MC{manufacturers_id}, deleted=>[1,0] );
					if ( $S->deleted() ) {
						$error .= $S->undelete();
					}
					$error .= $MC->save({skid_id=>$$S{id}});

				} # end if
					} # end if
		} # end if
	} # end if
	if ( $$MC{skid_id} and $$MC{rfidtag_id} ) {
		if ( ! $$Skid{rfidtag_id} ) {
			my $S = openprint::Skid->find_one( rfidtag_id => $$MC{rfidtag_id} );
			if ( $S ) {
				if ( $$S{id} != $$Skid{id} ) {
					$error .= qq`<a href="/employee/inventory/skid_details.html?skid_id=$$S{id}">Skid $$S{id}</a> has that rfidtag. Please fix it manually.<br/>`;
				} # end if
			} else {
				$error .= $Skid->save({ rfidtag_id=>$$MC{rfidtag_id} });
			} # end if
		} # end if
	} # end if

	if ( $error ) {
		$openprint::dbh->rollback();
	} # end if
	sql::end_transaction( $openprint::dbh, $ac );
	
	return $error;
} # end sub fix

sub check {
	my ( $MC ) = @_;

	my $Type = $MC->Type();
	my $error;
	my $Skid = $MC->Skid();
	if ( $Skid->deleted() ) {
		$error = qq`Skid <a href="/employee/inventory/skid_details.html?skid_id=$$Skid{id}">$$Skid{id}</a> is deleted.<br/>`;
	} # end if
	if ( ( ! $MC->location_id() ) and $Skid->id() ) {
		$error .= 'No location for ' . $Skid->link_to().'<br/>';
	} # end if
	if ( $MC->skid_id() ) {
		my @SkidContents = $Skid->Contents();
		if ( @SkidContents > 1 ) {
			$error = 'More than 1 stock on skid.<br/>';
			$error .= 'Skid Contains <br/>';
            foreach my $SK ( @SkidContents ) {
                $error .= '<a href="/employee/inventory/paper_details.html?paper_id='.$$SK{paper_id}.'">'.$SK->Paper()->to_string() . '</a><br/>';
            } # end foreach
		} elsif ( @SkidContents and ( $SkidContents[0]->paper_id() != $Type->paper_id() ) ) {
			$error = 'Skid contents do not match manifest.<br/>';
			$error .= 'Skid Contains ' . ( @SkidContents > 1 ? '<br/>' : '' );
            foreach my $SK ( @SkidContents ) {
                $error .= '<a href="/employee/inventory/paper_details.html?paper_id='.$$SK{paper_id}.'">'.$SK->Paper()->to_string() . '</a>';
				if ( $ENV{'HTTP_REFERER'} =~ /manifest\.html/ or ( $openprint::r->uri() =~ /manifest\.html/ ) ) {
					$error .= ssi::button( 'paper'.$MC->id().$SK->paper_id(), { onclick=>"select_stock($$MC{type_id},$$SK{paper_id});", text=>'Click to select' } );
				}
				$error .= '<br/>';
            } # end foreach
		} elsif ( $$Skid{id} and ! @SkidContents ) {
			$error = 'Skid is empty.<br/>';
		} # end if
	} # end if

	if ( $$MC{skid_id} and $$MC{manufacturers_id} and ( $$MC{manufacturers_id} ne $$Skid{manufacturers_id} ) ) {
		$error .= qq`Manufacturers ID ($$MC{manufacturers_id}) does not match skid.<br/>`;
		my $S = openprint::Skid->find_one(manufacturers_id=>$$MC{manufacturers_id},deleted=>[0,1]);

		if ( ! $$Skid{manufacturers_id} ) {
		} else {
			$error .= qq`Skid has $$Skid{manufacturers_id}<br/>`;
		} # end if

		if ( $S ) {
			$error .= qq`Skid <a href="/employee/inventory/skid_details.html?skid_id=$$S{id}">$$S{id}</a> has this manufacturers id`;
			if ( $S->deleted() ) {
				$error .= ', but has been deleted';
			}
			$error .= '.<br/>';
		} # end if
	} # end if
	my $Tag = $MC->RFIDTag();
	if ( $Tag->id() ) {
		$_ = $Tag->is_invalid_id();
		$error .= $_ if $_;
	} # end if

	if ( $$MC{skid_id} and $$MC{rfidtag_id} ) {
		if ( ! $$Skid{rfidtag_id} ) {
			$error .= 'RFID # has not been applied to skid.<br/>';
		} # end if
		my $RFIDSkid = $Tag->Skid();
		if ( $RFIDSkid->id() and ( $RFIDSkid->id() != $$MC{skid_id} ) ) {
			$error .= qq`RFID is assigned to <a href="/employee/inventory/skid_details.html?skid_id=$$RFIDSkid{id}">$$RFIDSkid{id}</a><br/>`;
		} # end if
		if ( $Skid->rfidtag_id() and $$Tag{id} and ( $Skid->rfidtag_id() != $$Tag{id} ) ) {
			$error .= qq`RFID does not match Tag assigned to skid <a href="/employee/inventory/skid_details.html?skid_id=$$Skid{id}">$$Skid{id} $$Skid{rfidtag_id}</a><br/>`;
		} # end if
	} # end if

	if ( $$MC{skid_id} and openprint::ManifestContent->find_one( 'id !=' => $$MC{id}, skid_id=>$$MC{skid_id}, manifest_id=>$$MC{manifest_id} ) ) {
		$error .= 'Skid id has been entered more than once on this Manifest.<br/>';
	} # end if
	if ( $$MC{rfidtag_id} and openprint::ManifestContent->find_one( 'id !=' => $$MC{id}, rfidtag_id=>$$MC{rfidtag_id}, manifest_id=>$$MC{manifest_id} ) ) {
		$error .= 'RFID id has been entered more than once on this Manifest.<br/>';
	} # end if

	return $error;
} # end sub check

sub apply {
	my ( $MC, $Order ) = @_;

	my $error;
	my $Tag = $MC->RFIDTag();
	$error .= $Tag->save() if $MC->rfidtag_id() and ! $Tag->created_on();

	my $skid_changes = '';

	my $Skid = $MC->Skid();
	if ( $$MC{manufacturers_id} ) {
		if ( $$Skid{manufacturers_id} ne $$MC{manufacturers_id} ) {
			my $found_other_skid = 0;

			if ( my $S = openprint::Skid->find_one(manufacturers_id=>$$MC{manufacturers_id}, deleted=>[0,1] ) ) {
				if ( $Skid->id() ) {
					if ( $S->id() != $Skid->id() ) {
						$error .= "Manufacturers ID $$MC{manufacturers_id} for skid <a href=\"/employee/inventory/skid_details.html?skid_id=$$MC{skid_id}\">$$MC{skid_id}</a> is already assigned to <a href=\"/employee/inventory/skid_details.html?skid_id=$$S{id}\">$$S{id}</a>.";
						$error .= ssi::button( 'Replace'.$$MC{id}, { href=>'/employee/inventory/manifest.html?manifest_content_id='.$$MC{id}.'&action=replace&skid_id='.$$S{id}, text=>'Replace' } ) . '<br/>';
						$found_other_skid = 1;
					} # end if
				} else {
					$Skid = $S;
				} # end if
			} # end if
			if ( ( ! $found_other_skid ) and ( ! $Skid->manufacturers_id() ) ) {
				$Skid->set({manufacturers_id=>$$MC{manufacturers_id}});
				$skid_changes .= 'Assigned manufacturers id to ' . $$MC{manufacturers_id}.'<br/>';
			} # end if
		} # end if
	} # end if manufacturers_id
	if ( ( ! $Skid->rfidtag_id() ) and $MC->rfidtag_id() ) {
		if ( my $S = openprint::Skid->find_one(rfidtag_id=>$MC->rfidtag_id()) ) {
			$error .= qq`RFIDTag is already on skid <a href="/employee/inventory/skid_details.html?skid_id=$$S{id}">$$S{id}</a><br/>`;
		} else {
			$Skid->rfidtag_id( $MC->rfidtag_id() );
			$skid_changes .= 'Assigned rfidtag to ' . $$MC{rfidtag_id}.'<br/>';
		} # end if
	} # end if

	if ( $$MC{location_id} ) {
		$Skid->location_id( $$MC{location_id} );
		$$MC{location_id} = undef;
		$skid_changes .= 'Changed location to ' . $Skid->Location()->name() . '<br/>';
	} # end if
	my $Paper = $MC->Type()->Paper();

	$Skid->type( $Paper->type() ) if ! $Skid->type();

	if ( ! $Skid->id() ) {
		$skid_changes .= 'Skid Created.<br/>';
		$$Skid{id} = $$MC{skid_id} if $$MC{skid_id};
		$error .= $Skid->save( {}, 1 );
	} else {
		$error .= $Skid->save() if $skid_changes;
	} # end if
	return $error if ! $Skid->id();

	my $Manifest = $MC->Manifest();

	if ( $skid_changes ) {
		my $PI = new openprint::PaperInventory();
		$error .= $PI->save({
				paper_id    =>  $$Paper{id},
				user_id     =>  $openprint::session{user_id},
				instock     =>  $Paper->in_stock(undef),
				delta       =>  0,
				comment     =>  'Changes from manifest <a href="/employee/inventory/manifest_view.html?manifest_id=' . $Manifest->id() . '">'. $Manifest->name().'</a>:<br/>'.$skid_changes,
				skid_id     =>  $$Skid{id},
				});
	} # end if

	if ( ! $$MC{skid_id} ) {
$openprint::log->debug("Setting skid_id to $$Skid{id}");
		$MC->skid_id( $$Skid{id} );
	} elsif ( $$MC{skid_id} != $$Skid{id} ) {
		$openprint::log->error("MC skid_id doesn't match skid");
	} else {
		$openprint::log->debug("MC skid_id matches skid");
	} # en dif
	$error .= $MC->save();

	my $SkidContent = openprint::SkidContent->find_one( skid_id=>$Skid->id(), paper_id=>$$Paper{id} );
	my $checked_out = $SkidContent->checked_out() if $SkidContent;
	$SkidContent = {} if ! $SkidContent;

	$openprint::log->debug("Skid qty: $$SkidContent{quantity} != $$MC{quantity} checked_out($checked_out)");
	if ( ( $$SkidContent{quantity} != $$MC{quantity} ) and ! $checked_out ) {
		openprint::employee_inventory::save_inventory( $Skid, $Paper, $$MC{quantity}, sprintf('Inventory adjusted by manifest <a href="/employee/inventory/manifest_view.html?manifest_id=%1$d">%2$s</a>.', $Manifest->id(), $Manifest->name() ), $MC->Type()->Condition() );
		if ( $SkidContent = openprint::SkidContent->find_one( skid_id=>$Skid->id(), paper_id=>$$Paper{id} ) ) {
			$openprint::log->debug("New skidcontent: " . $SkidContent->to_string() );
		} else {
			$openprint::log->debug("No New skidcontent: " );
		} 
	} # end if
	if ( $Order and $Order->id() and ! $checked_out ) {
		if ( sets::isin( $Order->status(), [ 'Complete', 'Cancelled' ] ) ) {
			$error .= 'Not allocating because docket is ' . $Order->status() . '<br/>';
		} else {
			require openprint::PaperAllocation;
			my $PA = openprint::PaperAllocation->find_one( 'skid_ids any'=>$MC->skid_id() );
			if ( ! $PA ) {
				$Paper->allocate( $Skid, $Order->docket(), $MC->quantity(), $Paper->units(), $SkidContent->condition_id() );
				$error .= sprintf('Allocated %1$d%2$s to docket <a href="/employee/project/view.html?docket=%3$d">%3$d</a>.<br/>', $MC->quantity(), $Paper->units(), $Order->docket() );
			} elsif ( ! $PA->docket() ) {
				$error .= $PA->save({ docket=>$Order->docket()});
				$error .= sprintf('Updated allocation %1$d%2$s to docket <a href="/employee/project/view.html?docket=%3$d">%3$d</a>.<br/>', $MC->quantity(), $Paper->units(), $Order->docket() );
			} elsif ( $PA->docket() != $Order->docket() ) {
				$error .= sprintf('Skid <a href="/employee/inventory/skid_details.html?skid_id=%1$d">%1$d</a> already allocated to docket <a href="/employee/project/view.html?docket=%2$d">%2$d</a>.<br/>', $MC->skid_id(), $PA->docket() );
			} # end if
		} # end if
	} # end if
	return $error;
} # end sub apply

1;
__END__
