use strict;
package openprint::RFIDTag;
our @ISA = qw(openprint::Object);
require openprint::Object;

use openprint ();
use vars qw($debug $dbh %find_fields %fields %transforms %defaults $table $cache_field );
*dbh = \$openprint::dbh;

require sql;
require openprint::RFIDTagType;
require openprint::Location;

$debug = 0;
$table = 'rfidtags';
%fields = (
	id			=>	'id',
	location_id	=>	'location_id',
	type_id		=>	'type_id',
	created_on	=>	'created_on',
	updated_on	=>	'updated_on',
	valid		=>	'valid',
);
%find_fields = (
	skid_id	=>	'(SELECT skid_id FROM skids WHERE skids.rfidtag_id=rfidtags.id)',
	type		=>	'type_id=(SELECT id FROM RFIDTagTypes WHERE RFIDTagTypes.name=?)',
);

%transforms = (
	id	=>	[ 's/\D//g' ],
);

%defaults = (
	created_on	=>	q`'NOW()'`,
	updated_on	=>	q`'NOW()'`,
	location_id	=>	undef,
	type_id		=>	undef,
	valid		=>	'0',
);
$cache_field = 'id';
sub cache_field {
    return $cache_field;
}

sub save {
	my ( $self, $hash ) = @_;

	$self->set( $hash ? $hash : {} );

	if ( ! $$self{id} ) {
		return 'RFID Tag must have an id';
	} # end if

	if ( ! $$self{type_id} ) {
		if ( ! $$self{type} ) {
			my $type_digit = substr( $$self{id}, 0, 1 );
			if ( $type_digit == 1 ) {
				$$self{type} = 'Location';
			} elsif ( $type_digit == 2 ) {
				$$self{type} = 'Skid';
			} # end if
		} # end if
                    
		if ( $$self{type} ) {
			my ( $type_id ) = sql::execute( undef, undef, 'SELECT id FROM RFIDTagTypes WHERE lower(name)=lower(?)', $$self{type} );
			if ( ! $type_id ) {
				my $Type = new openprint::RFIDTagType();
				$Type->save( {'name' => $$self{type} } );
				$$self{type_id} = $Type->id();
			} else {
				$$self{type_id} = $type_id;
			} # end if
		} # end if
	} # end if
	$$self{updated_on} = 'NOW()';

	if ( $self->type() eq 'Skid' ) {
		my $Skid = $self->Skid();
		if ( $Skid->id() and ( $Skid->location_id() != $$self{location_id} ) ) {
			$Skid->save({location_id=>$$self{location_id}});
		} # end if
	} # end if

	$self->valid( $self->is_invalid_id() ? 0 : 1 );
	
	my $ac = sql::start_transaction( $dbh );

	if ( ! sql::execute( undef, undef, 'SELECT * FROM RFIDTags WHERE id=?', $$self{id} ) ) {
		if ( my $error = sql::insert( undef, undef, 'RFIDTags', [ map { $_, $$self{$_} } keys %fields ] ) ) {
			$$self{id} = undef;
			sql::end_transaction( $dbh, $ac );
			return $error;
		} # end if
    } else {
		if ( my $error = sql::update( undef, undef, 'RFIDTags', ['id=?', $$self{id}], map { $_, $$self{$_} } keys %fields ) ) {
			sql::end_transaction( $dbh, $ac );
			return $error;
		} # end if
    } # end if

	sql::end_transaction( $dbh, $ac );
	$self->load();
	return;
} # end sub save

sub delete {
    my $self = shift;
    my $ac = sql::start_transaction( );
	sql::update( undef, undef, 'Skids', ['rfidtag_id=?', $$self{id}], 'rfidtag_id', undef );
    sql::execute( undef, undef, q{DELETE FROM RFIDTagHistory WHERE rfidtag_id=?}, $$self{id} );
    sql::execute( undef, undef, q{DELETE FROM RFIDTags WHERE id=?}, $$self{id} );
    sql::end_transaction( undef, $ac );
	delete $openprint::Object::cache{'openprint::RFIDTag'}{$$self{id}};
	return '';
} # end sub delete

sub Type {
	return new openprint::RFIDTagType( $_[0]->type_id() );
} # end sub Type

sub type {
	my ( $self, $new ) = @_;
	if ( $new and ($new ne $$self{type}) ) {
		$$self{type} = $new;
		$$self{type_id} = '';
	} # end if
	if ( $$self{type_id} and ! $$self{type} ) {
		$$self{type} = $self->Type()->name();
	} # end if
	return $$self{type};
} # end sub type

sub Location {
	return new openprint::Location( $_[0]->location_id() );
} # end sub Location

sub location_id {
    my ( $self, $new, $scanner_id ) = @_;
    if ( $new ) {
        if ( (!defined $$self{location_id}) or ( $new != $$self{location_id} ) ) {
            sql::insert( undef, undef, 'RFIDTagHistory', {'rfidtag_id'=>$$self{id},'location_id'=>$new, 'scanner_id'=>$scanner_id} ) if $$self{id};
            $$self{location_id} = $new;
        } # end if
    } # end if
    return $$self{location_id};
} # end sub location_id

sub skid_id {
	my ( $self ) = @_;
	if ( ! $$self{id} ) {
		$openprint::log->error('Cant load skid on a tag without an id');
		return;
	} # end if
	if ( ! $$self{skid_id} ) {
		my @Skids = openprint::Skid->find( rfidtag_id=>$$self{id}, deleted=>[0,1] );
		if ( @Skids ) {
			$$self{skid_id} = $Skids[0]->id();
		} # end if
	} # end if
	return $$self{skid_id};
} # end sub skid_id

sub Skid {
	my ( $self ) = @_;
	if ( ! $$self{id} ) {
		$openprint::log->error('Cant load skid on a tag without an id');
		return;
	} # end if
	if ( ! $$self{skid_id} ) {
		my @Skids = openprint::Skid->find('rfidtag_id'=>$$self{id},'deleted'=>[0,1]);
		if ( @Skids ) {
			$$self{skid_id} = $Skids[0]->id();
		} # end if
	} # end if
	return new openprint::Skid( $$self{skid_id} );
} # end sub Skid

sub id_short {
	my ( $self ) = @_;
	return '' if ! $$self{id};
	return $$self{id} if $self->is_invalid_id();

	my ( $type, $significant ) = $$self{id} =~ /^(\d)(\d{14})$/;
	return 1*$significant;
} # end sub id_short

sub is_invalid_id {
	my ( $id ) = @_;
	if ( ref $id eq 'openprint::RFIDTag' ) {
		$id = $id->id();
	} # end if

	if ( length $id != 15 ) {
		return 'Invalid length.  A valid tag should be 15 characters long. This one is ' . length $id;
	} # end if

	my $type_digit = substr( $id, 0, 1 );
	if ( $type_digit =~ /\D/ ) {
		return "Invalid type digit ($type_digit)";
	} # end if

	if ( $id =~ /\D/ ) {
		return 'Should not contain anything other than integers.';
	} # end if

	return 0;
} # end sub is_valid_id

# Does a better of figuring out what has been entered as an id
sub from_id {
	my ( $tag_id, $p_type ) = @_;

	my ( $type, $id );

	if ( ( $type, $id ) = $tag_id =~ /^R?(\d)(\d{14})$/ ) {
		my @RFID = openprint::RFIDTag->find( id=>sprintf( '%d%.14d', $type, $id ) );
		if ( @RFID == 1 ) {
			return $RFID[0];
		} else {
			$openprint::log->debug("Got too many rfids for $type $id from a full id");
		} # end if
	} elsif ( ( $id ) = $tag_id =~ /^(\d+)$/ ) {
		
		my @RFID = openprint::RFIDTag->find( 'id ilike'=>($p_type?$p_type:'').'%'.sprintf( '%.14d', $id ) );
		@RFID = openprint::RFIDTag->find( 'id ilike'=>($p_type?$p_type:'').'%'.$id ) if ! @RFID;
		if ( @RFID == 1 ) {
			return $RFID[0];
		} else {
			$openprint::log->debug("Got too many rfids for $type $id : " . @RFID);
		} # end if
	
	} # end if
	return;
} # end sub from_id

sub link_to {
	return sprintf('<a href="/employee/inventory/rfidtag_details.html?rfidtag_id=%1$s">%2$s</a>', $_[0]->id(), @_ > 1 ? $_[1] : $_[0]->id_short() );
} # end sub link_to

1;
__END__
