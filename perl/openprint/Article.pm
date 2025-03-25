use strict;
require openprint::Article_Asset;
require openprint::Article_Category;
package openprint::Article;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %defaults %transforms %config $log $dbh %session %find_fields );
*session = \%openprint::session;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;

$debug = 0;

$table = 'articles';
$serial = 'articles_id_seq';

%fields = (
	id				=>	'id',
	#'extended'			=>	'extended',
	#'excerpt'			=>	'exerpt',
	#'keywords'			=>	'keywords',
	created_by		=>	'created_by',
	created_on		=>	'created_on',
	updated_on		=>	'updated_on',
	company_id		=>	'company_id',
	#'permalink'			=>	'permalink',
	#'text_filter_id'	=>	'text_filter_id',
	#'whiteboard'		=>	'whiteboard',
	deleted			=> 'deleted',
	#'type'				=>	'type',
	#'name'				=>	'name',
	#'allow_pings'		=>	'allow_pings',
	#'allow_comments'	=>	'allow_comments',
	published_on		=>	'published_on',
	published			=>	'published',
	title				=>	'title',
	#'author'			=>	'author',
	body				=>	'body',
	#'state'				=>	'state',
	'category_id'		=>	'category_id',
	'category'			=>	undef,
	'source'			=>	'source',
	'source_content'	=>	'source_content',
	'summary'			=>	'summary',
	'user_type'			=>	'user_type',
	'keywords'			=>	'keywords',
	anonymous			=>	'anonymous',
	commenting			=>	'commenting',
);
%find_fields = (
	category		=>	'(SELECT name FROM article_categories WHERE id=category_id)',
);

%transforms = (
	user_type	=>	[ 's/\s//g' ],
	id			=>	[ 's/\D//g', '<2147483647' ],
);
%defaults = (
	created_on		=> q`'NOW()'`,
	updated_on		=> q`'NOW()'`,
	published_on	=> q`'NOW()'`,
	deleted			=> 0,
	category_id		=>	undef,
	user_type		=>	undef,
	created_by		=>	undef,
	anonymous		=>	0,
	published		=>	0,
	commenting		=>	0,
);

sub name {
	return $_[0]->title();
} # end sub name

sub send_notifications {
	my ( $self ) = @_;

	my @Users = openprint::User->find(type=>['E','A'],'usergroup any'=>'Quality Control Notifications');

	if ( @Users ) {
		my $email_template = misc::load_file( $log, $ENV{DOCUMENT_ROOT} . '/email_content/email_template.html' );
		my $text = misc::load_file( $log, $ENV{DOCUMENT_ROOT}.'/email_content/article_notification.html' );

		my %info = ( 'Article'	=>	$self );
		$info{ReplacementText} = ssi::variable_substitution( \$text, \%info );

		my $body = ssi::variable_substitution( \$email_template, \%info );
		new openprint::Email()->send(
				FROM    => new openprint::User( $session{user_id} ),
				TO      => \@Users,
				SUBJECT => 'A new Article has been generated.',
				ATTACHMENTS	=>	[ '', MIME::QuotedPrint::encode_qp($body), 'text/html', 'quoted-printable'],
				);
	} # end if to

} # end sub send_notification
sub Company {
	return new openprint::Company( $_[0]{company_id} );
} # end sub Company
sub Author {
	if ( ! $_[0]{Author} ) {
		$_[0]{Author} = new openprint::User( $_[0]{created_by} );
	} # end if
	if ( ! $_[0]{Author}->id() ) {
		$_[0]{Author}->company_id( $_[0]{company_id} );
	} # end if
	return $_[0]{Author};
		
} # end sub Author

sub category {
	if ( @_ > 1 ) {
		if ( $_[1] ) {
			my $Category = openprint::Article_Category->find_one('name lc'=>lc $_[1]);
			if ( ! $Category ) {
				$Category = new openprint::Article_Category();
				$Category->save({'name'=>$_[1]})
			} # end if	
			$_[0]{category_id} = $Category->id();
			return $Category->name();
		} else {
			$_[0]{category_id} = undef;
		} # end if
	} # end if
	return new openprint::Article_Category( $_[0]{category_id} )->name();
} # end sub category

sub Category {
	return new openprint::Article_Category( $_[0]{category_id} );
} # end sub Category

sub summary {
	if ( @_ > 1 ) {
		$_[0]{summary} = $_[1];
	} # end if
	return $_[0]{summary};
} # end sub summary

sub can_view {
	return 1 if ! $_[0]{id};
	my $User;
	if ( @_ > 1 ) {
		$User = ref $_[1] eq 'openprint::User' ? $_[1] : new openprint::User( $_[1] );
	} else {
		$User = new openprint::User( $openprint::session{user_id} );
	} # end if

	return 1 if $$User{type} eq 'A';
	return 1 if ( $$User{id} == $_[0]{created_by} );
	if ( $_[0]{published} ) {
#$openprint::log->debug("Is published");
		if ( ! $_[0]{user_type} ) {
#$openprint::log->debug("no usertype");
			# Anyone can see it
			return 1;
		} else {
#$openprint::log->debug("usertype is ($_[0]{user_type})");
			# Don't have to test for admin, cuz we did it above
			return 1 if $_[0]{user_type} eq 'C' and sets::isin( $$User{type}, ['E','C'] );
			return 1 if $_[0]{user_type} eq 'E' and sets::isin( $$User{type}, ['E'] );
		} # end if
	} else {
		$openprint::log->debug("not published");
		return 0;
	} # end if
	my $Privacy = $_[0]->Privacy();
	return 1 if ! $$Privacy{id};
	return $Privacy->can_view($$User{id});
	return 0;
} # end sub can_view
sub can_edit {
	return 0 if ! $session{user_id};
	return 1 if ! $_[0]{id};
	return 1 if $session{user_type} eq 'A';
	return 1 if ( $session{user_id} == $_[0]{created_by} );
	return 0;
} # end sub can_edit

sub html {
	my $Article = $_[0];
	my @Assets = $Article->Assets();
	my $html = sprintf(q`
			<div class="Article">
			<div class="Assets">%3$s</div>
			<h1><a href="/article/view.html?article_id=%1$d">%2$s</a></h1>
			%4$s
			posted on %5$s`, $Article->id(), ssi::escape_quotes($Article->title()), join('',map { $_->thumbnail_html() } ( @Assets ? $Assets[0] : () ) ),
			(($Article->anonymous() or ! $$Article{created_by})? '' : $Article->Author()->thumbnail_html() ),
			ssi::format_datetime( $Article->published_on() ),
			);
if ( 0 ) {
			if ( $Article->anonymous() ) {
				$html .= ' by an Anonymous Contributor';
			} elsif ( $Article->created_by() ) {
				$html .= ' by ' . $Article->Author()->link();
			} # end if
} # end if
	$html .= sprintf(q`<br/><div class="source_content">%1$s</div><div class="summary">%2$s</div>`,
			$Article->source_content(),
			($Article->summary() ? $Article->summary() : $Article->body() ),
                );
	if ( $Article->source() ) {
		$html .= sprintf('<a class="source" href="%1$s" target="_blank" title="Original Article">%1$s</a>', $Article->source() );
	} # end if
	if ( $Article->summary() and $Article->summary() ne $Article->body() ) {
		$html .= sprintf('<a class="readmore" href="/article/view.html?article_id=%1$d">Read more...</a><br/>', $Article->id() );
	} # end if
	if ( $Article->commenting() ) {
		my @Comments = $Article->Comments();
		$html .= sprintf(q`<div class="comments">This article has %s.</div>`, ( @Comments == 1 ? '1 comment' : @Comments . ' comments' ) );
	} # end if
	$html .= '</div>';
	return $html;
} # end  sub html

sub summary_html {
	my ( $Article, $options ) = @_;
	$options = {} if ! $options;
	my @Comments = $Article->Comments();
	my @Assets = $Article->Assets();
	my $html = sprintf(q`
			<div class="Article">
			<div class="Assets">%6$s</div>
			<h1><a href="/article/view.html?article_id=%1$d">%2$s</a></h1>
			<div class="source_content">%3$s</div>
			<div class="summary">%4$s</div>
			`, $Article->id(),
			ssi::escape_quotes($Article->title()),
			$Article->source_content(),
			($Article->summary() ? $Article->summary() : $Article->body() ),
			( $Article->published() ? ssi::format_datetime($Article->published_on()) : '' ),
			join('', map { $_->thumbnail_html() } ( @Assets ? $Assets[0] : () ) ),
    );
	if ( $Article->source() ) {
		$html .= sprintf('<a class="source" href="%1$s" target="_blank" title="Original Article">%1$s</a>', $Article->source() );
	} # end if
	if ( $Article->summary() and $Article->summary() ne $Article->body() ) {
		$html .= sprintf('<a class="readmore" href="/article/view.html?article_id=%1$d">Read more...</a><br/>', $Article->id() );
	} # end if
	if ( (!$$options{show_no_comments}) and (@Comments == 0) ) {
	} else {
		$html .= sprintf(q`<div class="comments">This article has %s.</div>`, ( @Comments == 1 ? '1 comment' : @Comments . ' comments' ) );
	} # end if
	$html .= '</div>';
	return $html;
} # end sub summary_html

sub view_url {
	return '/article/view.html?article_id='.$_[0]{id};	
} # end sub view_url

sub link_to {
	return '<a href="'.$_[0]->view_url().'">'.ssi::html_escape($_[0]->name()).'</a>';
} # end sub link_to

sub Assets {
	return () if ! $_[0]{id};
	return openprint::Article_Asset->find( article_id => $_[0]{id} );
} # end sub Assets

sub published_on_string {
	if ( ! $_[0]{published_on_string} ) {
		$_[0]{published_on_string} = misc::smart_time( Date::Parse::str2time( $_[0]{published_on} ) );
	} # end if
	return $_[0]{published_on_string};
} # end sub published_on_string

sub upload {
	my $error;
	my $Asset = openprint::Asset::upload( $_[1] );
	if ( ref $Asset ne 'openprint::Asset' ) {
		return $Asset;
	} # end if
	my $Article_Asset = new openprint::Article_Asset({ asset_id=>$Asset->id(), article_id=>$_[0]->id() });
	if ( $Article_Asset->asset_id() ) {
		return 'Asset already in article.';
	} else {
		return $Article_Asset->save({ asset_id=>$Asset->id(), article_id=>$_[0]->id() });
	} # end if
} # end sub upload

sub destroy {
	my $error = '';
	my $ac = sql::start_transaction( $openprint::dbh );
	foreach ( $_[0]->Assets() ) {
		$error .= $_->destroy();
		last if $error;
	} # end foreach
	$error .= $_[0]->SUPER::destroy() if ! $error;
	$openprint::dbh->rollback() if $error;
	sql::end_transaction( $openprint::dbh, $ac );
	return $error;
} # end sub destroy
	
sub Photos {
    #if ( ! $_[0]{album_id} ) {
        #return ();
    #} # end if
    return openprint::Article_Asset->find(article_id=>$_[0]{id});
} # end sub Photos

sub Album {
    #return new openprint::Photo_Album( $_[0]{album_id} );
} # end sub Album

sub body_escaped {
	my $body = $_[0]{body};
	$body =~ s/<\?\s*(.+?)\s*\?>/&lt;\?\1\?&gt;/g;
$openprint::log->debug("body: $body");
	return $body;
} # end

sub Created_By {
	return new openprint::User( $_[0]{created_by} );
} 
1;
__END__
