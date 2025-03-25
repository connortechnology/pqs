use strict;
require openprint::Asset;
require openprint::Claim;

package openprint::Claim_Asset;
our @ISA = qw(openprint::Object);
use vars qw( $debug %fields %transforms %defaults $table @identified_by );
$debug = 0;
$table = 'claim_assets';
@identified_by = ( 'claim_id','asset_id' );
%fields = (
	'claim_id'	=>	'claim_id',
	'asset_id'	=>	'asset_id',
);

sub Asset {
	return new openprint::Asset( $_[0]{'asset_id'} );
} # end sub Asset
sub Claim {
	return new openprint::Claim( $_[0]{'claim_id'} );
} # end sub Claim
