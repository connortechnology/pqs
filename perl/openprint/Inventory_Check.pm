use strict;
package openprint::Inventory_Check;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'inventory_checks';
$serial= 'inventory_checks_id_seq';
%fields = (
	id		=>	'id',
	name	=>	'name',
	created_on	=>	'created_on',
	started_on	=>	'started_on',
	contains	=>	'contains', # 'sheets','rolls', etc'
	ended_on	=>	'ended_on',
	scanner_id	=>	'scanner_id',
	deleted		=>	'deleted',
	location_id	=>	'location_id',
	item_count	=>	'item_count',
);
%transforms = (
	name	=> [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
	created_on	=>	q`'NOW()'`,
	started_on	=>	q`'NOW()'`,
	scanner_id	=>	undef,
	location_id	=>	undef,
	deleted		=>	'0',
	item_count	=>	undef,
);

sub name {
	if ( @_ > 1 ) {
		$_[0]{name} = $_[1];
	}
	if ( ! $_[0]{name} ) {
		if ( ! $_[0]{id} ) {
			return 'Inventory check for ' . join('-', Date::Calc::Today() );
		}
		return $_[0]{id};
	}
	return $_[0]{name};
}

sub url_to {
	return sprintf('/employee/inventory/check.html?check_id=%d', $_[0]{id} );
}

sub link_to {
	return sprintf(
		'<a href="/employee/inventory/check.html?check_id=%d">%s</a>'
		, $_[0]{id},
		( $_[0]{name} ? $_{name} : $_[0]{id} . ' started on ' . $_[0]{started_on} )
	 );
} # end sub link_to

sub Entries {
	if ( ! $_[0]{Entries} ) {
		$_[0]{Entries} = [ openprint::Inventory_Check_Entry->find( ic_id => $_[0]{id} ) ];
		$_[0]{skid_ids} = {} if ! $_[0]{skid_ids};
		$_[0]{rfid_ids} = {} if ! $_[0]{rfid_ids};
		foreach my $ICE ( @{$_[0]{Entries}} ) {
			$_[0]{skid_ids}{$$ICE{skid_id}} = [] if ! $_[0]{skid_ids}{$$ICE{skid_id}};
			push @{$_[0]{skid_ids}{$$ICE{skid_id}}}, $ICE if $$ICE{skid_id};
			
			$_[0]{rfid_ids}{$$ICE{rfidtag_id}} = [] if ! $_[0]{rfid_ids}{$$ICE{rfidtag_id}};
			push @{$_[0]{rfid_ids}{$$ICE{rfidtag_id}}}, $ICE if $$ICE{rfidtag_id};
		}
	}
	return @{$_[0]{Entries}};
} # end sub Entries

sub check_for_duplicates {
	my ( $self, $ICE ) = @_;

	$_[0]->Entries() if ! $_[0]{Entries};

#$openprint::log->debug("check_for_duplicates: $$ICE{skid_id} " . $_[0]{skid_ids}{$$ICE{skid_id}} . ' # of entries ' . ( $_[0]{skid_ids}{$$ICE{skid_id}} ? @{$_[0]{skid_ids}{$$ICE{skid_id}}} : '' ) );
	return 1 if $$ICE{skid_id} and $_[0]{skid_ids}{$$ICE{skid_id}} and @{$_[0]{skid_ids}{$$ICE{skid_id}}} > 1;
#$openprint::log->debug("check_for_duplicates: $$ICE{rfidtag_id} " . $_[0]{rfid_ids}{$$ICE{rfidtag_id}} . ' # of entries ' . ( $_[0]{rfid_ids}{$$ICE{rfidtag_id}} ? @{$_[0]{rfid_ids}{$$ICE{rfidtag_id}}} : '' ) );
	return 1 if $$ICE{rfidtag_id} and $_[0]{rfid_ids}{$$ICE{rfidtag_id}} and @{$_[0]{rfid_ids}{$$ICE{rfidtag_id}}} > 1;
	return 0;
} # end sub check_for_duplicates

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

sub item_count {
	if ( @_ > 1 ) {
		$_[0]{item_count} = $_[1];
	}
	if ( ( ! $_[0]{item_count} ) and $_[0]{id} ) {
		( $_[0]{item_count} ) = sql::execute( undef, undef, 'SELECT count(id) FROM Inventory_Check_Entries WHERE ic_id=?', $_[0]{id} );
	}	
	return $_[0]{item_count};
}

sub save {
	my ( $self, $data ) = @_;
	$self->item_count( undef ) if $$self{id};
	return $self->SUPER::save( $data );
}
1;
__END__
