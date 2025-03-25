use strict;
require openprint::Photo_Album;
require openprint::Photo_in_Album;
package openprint::Article_Category;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %defaults %transforms );

$debug = 0;
$table = 'article_categories';
$serial = 'article_categories_id_seq';

%fields = (
	'id'				=>	'id',
	'name'				=>	'name',
	'description'		=>	'description',
	'summary'			=>	'summary',
	'position'			=>	'position',
	'permalink'			=>	'permalink',
	'deleted'			=>	'deleted',
	'album_id'			=>	'album_id',
);

%transforms = (
	id			=>	[ 's/\D//g', '<2147483647' ],
	album_id			=>	[ 's/\D//g', '<2147483647' ],
    name		=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    description =>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    summary		=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    permalink	=>	[ 's/\s//', ],
);
%defaults = (
	'album_id'		=>	undef,
	'position'		=>	undef,
	'deleted'		=>	0,
);

sub Photo_Album {
	return new openprint::Photo_Album( $_[0]{'album_id'} );
} # end sub Photo_Album

sub Image {
	my @Photos = $_[0]->Photo_Album()->Photos();
	if ( @Photos == 1 ) {
		return $Photos[0];
	} elsif ( @Photos ) {
		return $Photos[int(rand(@Photos))];
	} 
	return new openprint::Photo_in_Album();
} # end sub Image

1;
__END__
