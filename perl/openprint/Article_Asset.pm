use strict;
require openprint::Asset;
require openprint::Article;

package openprint::Article_Asset;
our @ISA = qw(openprint::Object);
use vars qw( $debug %fields %transforms %defaults $table @identified_by );
$debug = 0;
$table = 'article_assets';
@identified_by = ( 'article_id','asset_id' );
%fields = (
	article_id	=>	'article_id',
	asset_id	=>	'asset_id',
);

sub Asset {
	return new openprint::Asset( $_[0]{asset_id} );
} # end sub Asset

sub Content {
	return new openprint::Article( $_[0]{article_id} );
} # end sub Content

sub url {
	return $_[0]->Asset()->url();
} # end sub url

sub thumbnail_url {
	return $_[0]->Asset()->sized_url('thumbnail');
} # end sub url

sub medium_html {
	my $Asset = $_[0]->Asset();
	return sprintf('<a class="medium %s" href="/article/view.html?article_id=%d"><img src="%s" alt="%s"/></a>', 
		$Asset->layout(), $_[0]{article_id},$Asset->sized_url('medium'), $Asset->caption() );
} # end sub thumbnail_html

sub thumbnail_html {
	my $self = $_[0];
	my $Asset = $self->Asset();
	if ( $Asset->layout() eq 'Landscape' ) {
		return sprintf('<a class="Landscape" href="/article/view.html?article_id=%d"><img src="%s" alt="%s"/></a>', $$self{article_id},$Asset->sized_url('small'), $Asset->caption() );
	} else {
		return sprintf('<a class="Portrait" href="/article/view.html?article_id=%d"><img src="%s" alt="%s"/></a>', $$self{article_id},$Asset->sized_url('small'), $Asset->caption() );
	} # end if
} # end sub thumbnail_html

sub html {
	my $Asset = $_[0]->Asset();
	return sprintf('<a class="full" href="/article/view.html?article_id=%d"><img src="%s" alt="%s"/></a>', $_[0]{article_id},$Asset->url(), $Asset->caption() );
} # end sub html
1;
__END__
