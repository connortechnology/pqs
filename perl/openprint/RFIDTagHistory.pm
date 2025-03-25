use strict;
package openprint::RFIDTagHistory;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;

$table = 'rfidtaghistory';
$serial = 'rfidtaghistory_id_seq';

%fields = (
	id				=>	'id',
	rfidtag_id		=>	'rfidtag_id',
	scanner_id		=>	'scanner_id',
	location_id		=>	'location_id',
	updated_on		=>	'updated_on',
	comment			=>	'comment',
);

%transforms = (
);

%defaults = (
	updated_on	=>	q`'NOW()'`,
);

sub Location {
	return new openprint::Location( $_[0]{location_id} );
} # end sub Location

sub Scanner {
	return new openprint::RFIDScanner( $_[0]{scanner_id} );
} # end sub Scanner

sub RFIDTag {
	return new openprint::RFIDTag( $_[0]{rfidtag_id} );
} # end sub RFIDTag
	

1;
__END__
