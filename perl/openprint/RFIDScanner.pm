use strict;
package openprint::RFIDScanner;
our @ISA = qw(openprint::Object);
require openprint::Object;

use openprint ();
use vars qw( $debug $log $dbh $table $serial %fields %transforms %defaults @types );
*log = \$openprint::log;
*dbh = \$openprint::dbh;

require sql;
require openprint::Location;
require openprint::RFIDTagHistory;
require openprint::RFIDScannerHistory;

$debug = 0;

%fields = (
	'id'		=>	'id',
	'name'		=>	'name',
	'ipaddr'	=>	'ipaddr',
	'type'		=>	'type',
	'location_id'	=>	'location_id',
	'created_on'	=>	'created_on',
	'updated_on'	=>	'updated_on',
	'lastseen_on'	=>	'lastseen_on',
	'other'			=>	'other',
	'monitor'		=>	'monitor',
);

%transforms = (
	'updated_on'	=>	['s/.*//g'],
);

%defaults = (
	'created_on'	=>	q`'NOW()'`,
	'updated_on'	=>	q`'NOW()'`,
	'lastseen_on'	=>	q`'NOW()'`,
	'location_id'	=>	undef,
	monitor			=>	'0',
);

$table = 'rfidscanners';
$serial = 'rfidscanners_id_seq';

@types = (
'Checkout', 'Fixed','Mobile', 'Truck Inventory','Truck Location'
);

sub delete {
  my $self = shift;
  my $ac = sql::start_transaction( );
  sql::execute( undef, undef, "DELETE FROM $openprint::RFIDScannerHistory::table WHERE scanner_id=$$self{id}" );
  #foreach ( openprint::RFIDScannerHistory->find('scanner_id'=>$$self{'id'}) ) {
  #$_->delete();
  #} # end foreach
  sql::execute( undef, undef, "DELETE FROM $openprint::RFIDTagHistory::table WHERE scanner_id=$$self{id}" );
  #foreach ( openprint::RFIDTagHistory->find('scanner_id'=>$$self{'id'}) ) {
  #$_->delete();
  #} # end foreach
  sql::execute( undef, undef, "DELETE FROM inventory_check_entries WHERE scanner_id=$$self{id}" );
  sql::execute( undef, undef, q{DELETE FROM RFIDScanners WHERE id=?}, $$self{'id'} );
  sql::end_transaction( undef, $ac );
  return;
} # end sub delete

sub Location {
	return new openprint::Location( $_[0]{'location_id'} );
} # end sub Location

sub location_id {
    my ( $self, $new, $rfidtag_id ) = @_;
    if ( $new ) {
        if ( $new != $$self{'location_id'} ) {
            sql::insert( undef, undef, 'RFIDScannerHistory', {'location_id'=>$new, 'scanner_id'=>$$self{id}, 'rfidtag_id'=>$rfidtag_id } );
            $$self{'location_id'} = $new;
        } # end if
    } # end if
    return $$self{'location_id'};
} # end sub location_id

sub Next {
	my $self = $_[0];
	my ( $new_id ) = sql::execute( undef, undef, 'SELECT id FROM RFIDScanners WHERE name = (SELECT MIN(name) FROM RFIDScanners WHERE lower(name) > lower(?))', $$self{'name'} );
	if ( ! $new_id ) {
		( $new_id ) = sql::execute( undef, undef, 'SELECT id FROM RFIDScanners WHERE name = (SELECT MIN(name) FROM RFIDScanners)' );
	} # end if
	return new openprint::RFIDScanner( $new_id );
} # end sub Next

sub Previous {
	my $self = $_[0];
	my ( $new_id ) = sql::execute( undef, undef, 'SELECT id FROM RFIDScanners WHERE name = (SELECT MAX(name) FROM RFIDScanners WHERE lower(name) < lower(?))', $$self{'name'} );
	if ( ! $new_id ) {
		( $new_id ) = sql::execute( undef, undef, 'SELECT id FROM RFIDScanners WHERE name = (SELECT MAX(name) FROM RFIDScanners)' );
	} # end if
	return new openprint::RFIDScanner( $new_id );
} # end sub Previous

1;
__END__
