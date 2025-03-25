use strict;
require openprint::Asset;
require openprint::SRED_Content;

package openprint::SRED_Asset;
our @ISA = qw(openprint::Object);
use vars qw( $debug %fields %transforms %defaults $table @identified_by );
$debug = 0;
$table = 'sred_assets';
@identified_by = ( 'content_id','asset_id' );
%fields = (
	'content_id'	=>	'content_id',
	'asset_id'	=>	'asset_id',
);

sub Asset {
	return new openprint::Asset( $_[0]{'asset_id'} );
} # end sub Asset
sub Content {
	return new openprint::Claim( $_[0]{'content_id'} );
} # end sub Content

sub url {
	return $_[0]->Asset()->url();
} # end sub url

1;
__END__
