use strict;
package openprint::Inventory_Check_Entry;
our @ISA = qw(openprint::Object);

require openprint::Location;

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'inventory_check_entries';
$serial= 'inventory_check_entries_id_seq';
%fields = (
	id					=>	'id',
	ic_id				=>	'ic_id',
	skid_id			=>	'skid_id',
	rfidtag_id	=>	'rfidtag_id',
	scanner_id	=>	'scanner_id',
	created_on	=>	'created_on',
	operator_id	=>	'operator_id',
	quantity		=>	'quantity',
	dimension1	=>	'dimension1',
	dimension2	=>	'dimension2',
	notes				=>	'notes',	
	location_id	=>	'location_id',
	paper_id		=>	'paper_id',
);
%transforms = (
	notes				=> [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	quantity		=>	[ 's/\D//g' ],
	dimension1	=>	[ 's/\D//g' ],
	dimension2	=>	[ 's/\D//g' ],
);
%defaults = (
	created_on	=>	q`'NOW()'`,
	operator_id	=>	undef,
	skid_id			=>	undef,
	rfidtag_id	=>	undef,
	dimension1	=>	undef,
	dimension2	=>	undef,
	quantity		=>	undef,
	location_id	=>	undef,
	paper_id		=>	undef,
);

sub skid_id {
	if ( @_ > 1 ) {
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
			$_[0]{RFIDTag} = new openprint::RFIDTag( $_[0]->rfidtag_id() );
			if ( ! $_[0]{RFIDTag}->id() ) {
				$_[0]{RFIDTag} = new openprint::RFIDTag();
				$_[0]{RFIDTag}->id( $_[0]->rfidtag_id() );
			} # end if
		} else {
			$_[0]{RFIDTag} = $_[0]->Skid()->RFIDTag();
		} # end if
	} # end if
	return $_[0]{RFIDTag};
} # end sub RFIDTag

sub Scanner {
	return new openprint::RFIDScanner( $_[0]{scanner_id} );
}

sub rfidtag_id {
	if ( @_ > 1 ) {
		$_[0]{rfidtag_id} = $_[1];
	} # end if
	if ( ( ! $_[0]{rfidtag_id} ) and $_[0]{skid_id} ) {
		$_[0]{rfidtag_id} = $_[0]->Skid()->RFIDTag()->id();
	}

	if ( $_[0]{rfidtag_id} and ( length $_[0]{rfidtag_id} < 15 ) ) {
#$openprint::log->debug("Formatting: $_[0]{rfidtag_id} to 2" . sprintf('%014d', $_[0]{rfidtag_id} ) );
		$_[0]{rfidtag_id} = '2'.sprintf('%014d', $_[0]{rfidtag_id} );
	}

	return $_[0]{rfidtag_id};
}

sub quantity {
	if ( @_ > 1 ) {
		$_[0]{quantity} = $_[0]->transform( quantity=>$_[1] );
	}
	if ( ! $_[0]{quantity} ) {
		$_[0]{quantity} = $_[0]->system_quantity();
		if ( 1 and ! $_[0]{quantity} ) {
			$_[0]{quantity} = int(rand(1000)) + 1000;
$openprint::log->debug("No system quantity found for $_[0]{id}, grabbing random, got $_[0]{quantity}");
		}
	}
	return $_[0]{quantity};
}

sub system_quantity {
	my $Skid = $_[0]->Skid();
	if ( $$Skid{id} ) {
		my @C = $Skid->Contents();
		if ( @C == 1 ) {
# IF we have some dimension measurements, then we can calculate the current weight.
			if ( $_[0]{dimension2} and $_[0]{dimension1} ) {
				my $Paper = $C[0]->Paper();
				if ( $Paper->type() ne 'Sheet' ) {
# dimension2 is radius or diameter
# I think this was a weird formula given by Rick.

					$_[0]{system_quantity} = Math::Round::nearest(1, $_[0]{dimension2} * $_[0]{dimension2} - 9 * $_[0]{dimension1} * 0.37 );
				} # end if
			} elsif ( $C[0]{quantity} ) {
# Else if there is still some in the system, assume that is correct.
				$_[0]{system_quantity} = $C[0]{quantity};
			} else {
$openprint::log->debug("Looking up checked out qty for $_[0]{id}") if $debug;
# Otherwise, lookup the pre-checked out quantity, and use that
				my $PI = $C[0]->checked_out();
				$_[0]{system_quantity} = -1*$$PI{delta} if $PI;
			}
		} # end if only 1 stock
	} else {
		$_[0]{system_quantity} = Math::Round::nearest( 1, $_[0]{dimension2} * $_[0]{dimension2} - 9 * $_[0]{dimension1} * 0.37 );
	} # skid was found
	return $_[0]{system_quantity};
}

sub Location {
	return new openprint::Location( $_[0]{location_id} );
}
sub location {
	return new openprint::Location( $_[0]{location_id} )->name();
}
sub location_ids { 
	if ( $_[0]{location_id} and ! $_[0]{location_ids} ) {
		$_[0]{location_ids} = [map { $$_{id} } $_[0]->Location()->get_all_children()];
	} else {
		$_[0]{location_ids} = [];
	}
	return @{$_[0]{location_ids}};
}

sub Check {
	return new openprint::Inventory_Check( $_[0]{ic_id} );
}

sub check {
	return 'No Skid.' if ! $_[0]->Skid()->id();
	return 'Quantity not the same: Check has ' . $_[0]->quantity() . ' ' . $_[0]{Skid}->type() . ' has ' . $_[0]->Skid()->quantity() if $_[0]->quantity() != $_[0]->Skid()->quantity();
	return 'Item is in the check more than once<br/>' if $_[0]->Check()->check_for_duplicates( $_[0] );
	return '';
}

sub User {
	return new openprint::User( $_[0]{operator_id} );
}

sub SkidContent {
	my ( $self ) = @_;
	if ( ! $$self{SkidContent} ) {
		my $Skid = $self->Skid();
		if ( $$Skid{id} ) {
			my @C = $Skid->Contents();
			if ( @C == 1 ) {
				$$self{SkidContent} = $C[0];
			}
		}
	}
	return $$self{SkidContent};
}

sub value {
	my ( $self ) = @_;

	if ( ! $$self{value} ) {
		my $C = $self->SkidContent();
		if ( $C ) {
			my $Cost = $C->Cost();
			openprint::Currency::convert( $Cost );
			if ( $Cost ) {
				$openprint::log->debug("cost for $$self{skid_id} $$Cost{units} $$Cost{cost}") if $debug;
				if ( (!$$Cost{units}) or ($$Cost{units} eq '/100lbs' or $$Cost{units} eq '/cwt') ) {
					$$self{value} = $self->quantity() * $$Cost{cost} / 100;
				} else {
					$$self{value} = $self->quantity() * $$Cost{cost};
				} # end if
			} else {
				$openprint::log->debug("No cost for $$self{skid_id}") if $debug;
			} # end Cost
		} # end if Skid
	} # end if ! exists value
	return $$self{value} if $$self{value};
	return;
} # end sub value

sub diameter {
	my ( $self ) = @_;

	if ( ( ! $_[0]{diameter} ) and $_[0]->quantity() ) {
		my $Skid = $self->Skid();
		if ( $$Skid{id} ) {
			my $C = $self->SkidContent();
			if ( $C ) {

				if ( $$Skid{type} eq 'Roll' ) {
					my $core_radius = 5.375;
					my $pi = 3.14;
					my $Paper = $C->Paper();
					return if ( ! ( $$Paper{width} and $Paper->wpsi() and $$Paper{calliper} ) );
					my $length = ( $self->quantity() / $Paper->wpsi() ) / $Paper->width();

# length = pi( r1^2 - r0^2 ) / calliper;
					my $radius = sqrt( ( $length * $$Paper{calliper} / $pi ) + 28.8906525 );
					$_[0]{diameter} = $radius * 2;
					$openprint::log->debug("Diameter $_[0]{diameter} length: $length inches before sqrt: " . ( ( ( $length * $$Paper{calliper} / $pi ) ) ) ) if $debug;
				} # end if Roll
			} # end if C
		} # end if Skid
	} # end if ! diameter
	return $_[0]{diameter};
}

sub paper_id {
	if ( @_ > 1 ) {
		$_[0]{paper_id} = $_[1];
	}
	if ( ! $_[0]{paper_id} ) {
		my @Contents = $_[0]->Skid()->Contents();
		if ( @Contents == 1 ) {
			return $Contents[0]->paper_id();
		}
	}
	return $_[0]{paper_id};
}
sub Paper {
	if ( ! $_[0]{paper_id} ) {
		return new openprint::Paper( $_[0]->paper_id() );
	} else {
		return new openprint::Paper( $_[0]{paper_id} );
	}	
}

1;
__END__
