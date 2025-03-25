use strict;
require openprint::Article;

package openprint::Trackback;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'trackbacks';
$serial = 'trackbacks_id_seq';

%fields = (
	id				=>	'id',
    blog_name			=>	'blog_name',
    excerpt				=>	'except',
    title				=>	'title',
    url					=>	'url',
    article_id			=>	'article_id',
	created_on			=>	'created_on',
);

%transforms = (
	id				=>	[ 's/\D//g' ],
);

%defaults = (
);


sub Article {
	return new openprint::Article( $_[0]{article_id} );
} # end sub Company

1;
__END__
