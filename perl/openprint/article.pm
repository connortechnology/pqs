use strict;
package openprint::article;

use LWP::UserAgent ();
require HTML::Entities;
use openprint ();
use vars qw( $r %variable %session %param %config $log $dbh );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

require openprint::Article;
require openprint::Article_Category;
require openprint::Article_Asset;
require XML::RSS;
require DateTime::Format::Pg;
require DateTime::TimeZone;

# recursively fixes %gt; problems.
sub unescape_substitutions {
	if ( $_[0] =~ /(.*?)(&lt;\?\s*.*?\s*\?&gt;)(.*)?/ms ) {
		my ( $before, $code, $after ) = ( $1, $2, $3 );
		if ( $code ) {
	$log->debug("before $before code($code) $after");
			$code =~ s/&gt;/>/g;
			$code =~ s/&lt;/</g;
			$code =~ s/&rsquo;/'/g;
	$log->debug("after code($code)");
			return $before . $code . ( $after ? unescape_substitutions( $after ) : '' );
		} # end if
	} # end if
	return $_[0];

} # end unescape_substitutions

sub save_article {
  $param{article_id} = openprint::Article->transform(id=>$param{article_id});
	my $Article = new openprint::Article( $param{article_id} );
	if ( ! $Article->can_edit() ) {
		$variable{error} .= 'You do not have rights to edit this article.';
		return;
	} # end if
	$param{company_id} = $session{company_id} if ! $param{company_id};

	if ( Date::Calc::check_date( @param{'published_on_year','published_on_month','published_on_day'} ) ) {
        my $published_on_datetime = DateTime->new( time_zone => $openprint::TZ,
                ( map { $_ => int($param{'published_on_'.$_ }) } ( 'year', 'month', 'day', 'hour','minute' ) ),
                );

        my $parser = 'DateTime::Format::Pg';

        $param{published_on} = $parser->format_datetime( $published_on_datetime );

	} else {
		delete $param{published_on};
		$variable{warning} = 'Invalid date published_on_date.  Published On Date not changed.';
	} # end if
	if ( $param{category_id} ) {
		delete $param{category};
	} elsif ($param{category}) {
		delete $param{category_id};
	} # end if
	if ( $param{source} ) {

		if ( 0 and  ( $param{source} =~ /epicurious\.com/ ) ) {
			my $ua = LWP::UserAgent->new;
			$ua->agent("MyApp/0.1 ");
# Create a request
			my $req = HTTP::Request->new(GET => $param{source} );
# Pass request to the user agent and get a response back
			my $res = $ua->request($req);
# Check the outcome of the response
			if ($res->is_success) {
				$log->debug("Content: " . $res->content );
				my $content = $res->content;
				#my ( $title, $summary ) = $res->content =~ /<h1 class="fn">(.+)<\/h1>.*<span id="truncatedText" class="summary">(.*)<\/span>/m;
				$content =~ s/\n\r//g;
				$content =~ s/\n//g;
				# Turn relative links into absolute
				$content =~ s/src="\//src="http:\/\/www.epicurious.com\//g;
				$content =~ s/href="\//href="http:\/\/www.epicurious.com\//g;
				my ( $title ) = $content =~ /<h1 class="fn">(.+?)<\/h1>/;
				my ( $summary ) = $content =~ /<div id="recipe_detail_module" class="content_unit detail_page">(.*)<\/div>/;
				my ( $thumb ) = $content =~ /<div id="recipe_thumb">(.+?)<\/div>/;
				
				$param{source_content} = qq`<div class="Epicurious"><h1>$title</h1><div class="thumb">$thumb</div><div class="summary">$summary</div></div>`;
			} else {
				$log->error("Bad status" . $res->status_line );
				$variable{information} .= 'Unable to grab content from source.: ' . $res->status_line . '<br/>';
			} # end if
		 } elsif ( $param{source} =~ /glittermuff.tumblr.com/ ) {
			 my $ua = LWP::UserAgent->new;
			 $ua->agent("MyApp/0.1 ");
# Create a request
			 my $req = HTTP::Request->new(GET => $param{source} );
# Pass request to the user agent and get a response back
			 my $res = $ua->request($req);
# Check the outcome of the response
			 if ($res->is_success) {
				 $log->debug("Content: " . $res->content );
				 my $content = $res->content;
#my ( $title, $summary ) = $res->content =~ /<h1 class="fn">(.+)<\/h1>.*<span id="truncatedText" class="summary">(.*)<\/span>/m;
				 $content =~ s/\n\r//g;
				 $content =~ s/\n//g;
# Turn relative links into absolute
				 $content =~ s/src="\//src="http:\/\/glittermuff.tumblr.com\//g;
				 $content =~ s/href="\//href="http:\/\/glittermuff.tumblr.com\//g;

				 my ( $source_content ) = $content =~ /(<div class="photo">.+)<!\-\- end single post \-\->/m;
				 $source_content =~ s/<script.*?<\/script>//g;
				 $source_content =~ s/<noscript.*?<\/noscript>//g;
				 $source_content =~ s/<a href="http:\/\/disqus.com" class="dsq-brlink".*<\/a>//g;
				 $source_content =~ s/<div id="disqus_thread"><\/div>//;
				 $source_content =~ s/<div class="notecontainer">.*?<\/ol><\/div>//g;	
				 $source_content =~ s/(\s)\s+/$1/g;
				 $source_content =~ s/<div id="post-id">.*?<\/div>//g;
				 $source_content =~ s/<span class="arrow">.*?<\/span>//g;
				 $source_content =~ s/<span class="reblog">.*?<\/span>//g;
				 $source_content =~ s/<span class="tags">.*?<\/span>//g;
				 $source_content =~ s/<span class="notes">.*?<\/span>//g;
				 $source_content =~ s/<img src="http:\/\/static.tumblr.com\/xequfu2\/eXXkpzidm\/post_bottom.png" style="margin-bottom:-68px; margin-left:-10px;">//g;
				 $source_content =~ s/<div style="text-align:right;">\s+<span class="when">Date:<\/span> (\d\d)\.(\d\d)\.(\d\d)\s+<span class="when">Time:<\/span>\s+(\d\d):(\d\d) (\w\w)\s+<\/div>//mg;
				 $param{published_on} = sprintf('%.4d-%.2d-%.2d %.2d:%.2d:00', 2000+$3, $1, $2, $4 + ( $6 eq 'PM' ? 12 : 0 ), $5 );
				 $param{source_content} = qq`<div class="Muffy">$source_content</div>`;
			 } else {
				 $log->error("Bad status" . $res->status_line );
				 $variable{information} .= 'Unable to grab content from source.: ' . $res->status_line . '<br/>';
			 } # end if
		} # end if
	} # end if source

if ( 0 ) {
	my $body = '';
	my $remainder = $param{body};
	my $pre;
	my $a1;
	my $a2;
	while ( $remainder ) {
		if ( ( $pre, $a1, $a2, $remainder ) =~ /^(.*?)<a(.+?)>(.+?)<\/a>(.*)$/ims ) {
$log->debug("Found: pre: $pre, a: $a1, $a2, rem: $remainder");
			$body .= $pre;
			# Do stuff to a
			$body .= '<a'.$a1.'>'.$a2.'</a>';
		} else {
			$body .= $remainder;
			$remainder = '';
		} 
	} # end while
	$param{body} = $body;
} 
$log->debug("before unescape $param{body} ");
	$param{body} = unescape_substitutions( $param{body} );
  $log->debug("aftere unescape $param{body} ");

  if (!$Article->id()) {
    $variable{error} .= $Article->save(\%param);
    new openprint::Log()->save({action=>'Create Article', Object=>$Article});
  } else {
    $variable{error} .= $Article->save(\%param);
  } # end if
  eval {
    require HTML::LinkExtractor;
    my $LX = new HTML::LinkExtractor();
    $LX->parse( \$$Article{body} );
    if ( $LX->links ) {
      foreach my $Link ( @{$LX->links} ) {
        next if $$Link{tag} ne 'a';
        next if $$Link{target} eq '_blank';	
        $variable{warning} .= 'The link ' . $$Link{_TEXT_} . ' does not have a target="_blank" on it<br/>.';
      } # end foreach  Link
    } # end if links
    undef $LX;
  };

	my $Privacy = $Article->Privacy();
	$variable{error} .= $Privacy->save( {
			map { $_, $param{'privacy_'.$_} } ( 'mode','user_id','relationship_type_id','usergroup_id' )
			} );
} # end sub save_article

sub history {
	_history();

	if ( ( ! $session{'/article/history.html?lastupdated'} ) or ( time - $session{'/article/history.html?lastupdated'} ) > ( 12*60*60 ) ) {
		ssi::setup_date_select( '/article/history.html', 'published_on_start', -31 );
		ssi::setup_date_select( '/article/history.html', 'published_on_end', '' );
		ssi::setup_date_select( '/article/history.html', 'created_on_start', -31 );
		ssi::setup_date_select( '/article/history.html', 'created_on_end', '' );
	} # end if

} # end sub history

sub _history {
	if ( ! $param{func} ) {
		ssi::save_params( '/article/history.html', ( 
		( map { 'created_on_start_'.$_ } ( 'year','month','day' ) ),
		( map { 'created_on_end_'.$_ } ( 'year','month','day' ) ),
		( map { 'published_on_start_'.$_ } ( 'year','month','day' ) ),
		( map { 'published_on_end_'.$_ } ( 'year','month','day' ) ),
				'deleted', 'published','employee_id','company_id', 'category_id', 'author_id' ) );
	} 
	if ( $param{func} eq 'Delete' ) {
		foreach my $id ( ref $param{article_id} eq 'ARRAY' ? @{$param{article_id}} : $param{article_id} ) {
			my $Article = new openprint::Article($id);
			if ( ! $Article->can_edit() ) {
				$variable{error} .= 'You do not have rights to destroy this article.';
				next;
			} # end if
			$variable{error} .= $Article->delete();
		} # end foreach id
	} elsif ( $param{func} eq 'Destroy' ) {
		foreach my $id ( ref $param{article_id} eq 'ARRAY' ? @{$param{article_id}} : $param{article_id} ) {
			my $Article = new openprint::Article($id);
			if ( ! $Article->can_edit() ) {
				$variable{error} .= 'You do not have rights to destroy this article.';
				next;
			} # end if
			$variable{error} .= $Article->destroy();
		} # end foreach id
		$variable{ExternalRedirect} = '/article/history.html';
	} # end if
} # end sub _history

sub search {
	if ( $param{action} eq 'Reset' ) {
		ssi::reset_session('/article/search.html');
		return;
	} # end if
	_search();

	if ( ( ! $session{'/article/search.html?lastupdated'} ) or ( time - $session{'/article/search.html?lastupdated'} ) > ( 12*60*60 ) ) {
		ssi::setup_date_select( '/article/search.html', 'published_on_start', -31 );
		ssi::setup_date_select( '/article/search.html', 'published_on_end', '' );
		#ssi::setup_date_select( '/article/search.html', 'created_on_start', -31 );
		#ssi::setup_date_select( '/article/search.html', 'created_on_end', '' );
	} # end if

} # end sub history

sub _search {
	if ( ! $param{func} ) {
		ssi::save_params( '/article/search.html', ( 
		#( map { 'created_on_start_'.$_ } ( 'year','month','day' ) ),
		#( map { 'created_on_end_'.$_ } ( 'year','month','day' ) ),
		( map { 'published_on_start_'.$_ } ( 'year','month','day' ) ),
		( map { 'published_on_end_'.$_ } ( 'year','month','day' ) ),
				'deleted', 'published','company_id', 'category_id', 'author_id', 'title' ) );
	} 
	if ( $param{action} eq 'Delete' ) {
		foreach my $id ( ref $param{article_id} eq 'ARRAY' ? @{$param{article_id}} : $param{article_id} ) {
			my $Article = new openprint::Article($id);
			if ( ! $Article->can_edit() ) {
				$variable{error} .= 'You do not have rights to destroy this article.';
				next;
			} # end if
			$variable{error} .= $Article->delete();
		} # end foreach id
	} elsif ( $param{action} eq 'Destroy' ) {
		foreach my $id ( ref $param{article_id} eq 'ARRAY' ? @{$param{article_id}} : $param{article_id} ) {
			my $Article = new openprint::Article($id);
			if ( ! $Article->can_edit() ) {
				$variable{error} .= 'You do not have rights to destroy this article.';
				next;
			} # end if
			$variable{error} .= $Article->destroy();
		} # end foreach id
	} # end if
} # end sub _search

sub edit {
	$param{article_id} = openprint::Article->transform( 'id', $param{article_id} );

	my $Article = $variable{Article} = new openprint::Article( $param{article_id} );
	if ( ! $param{article_id} ) {
		$variable{error} .= $Article->save({created_by=>$session{user_id}}); # allocate an id.
	} elsif ( ! $Article->can_edit() ) {
		$variable{error} .= 'You do not have rights to edit this article.';
		return;
	} # end if
  if ($param{func}) {
    if ( $param{func} eq 'Save' ) {
      save_article();
      if ( $variable{error} or $variable{warning} ) {
      } else {
        %param = ();
        $param{article_id} = $Article->id();
        # FIXME, update session filters to include this article
        my $published_on_date = Date::Parse::str2time($Article->published_on());
        my ( $year, $month, $day ) = @session{ map { '/article/history.html?published_on_start_'.$_ } ( 'year','month','day' )};

        if ( Date::Calc::check_date( $year, $month, $day ) ) {
          $log->debug("published on start $year, $month, $day $$Article{published_on}");
          my $session_published_on_date_start = Date::Calc::Date_to_Time( $year, $month, $day, 0,0,0 );
          if ( $session_published_on_date_start > $published_on_date ) {
            ($year,$month,$day, undef, undef, undef ) = Date::Calc::Time_to_Date($published_on_date);
            @session{map { '/article/history.html?published_on_start_'.$_ } ( 'year','month','day' )} = ( $year, $month, $day );
          } # end if
        } # end if
        if ( Date::Calc::check_date( @session{ map { '/article/history.html?published_on_end_'.$_ } ( 'year','month','day' )} ) ) {
          $log->debug(join('-', @session{ map { '/article/history.html?published_on_end_'.$_ } ( 'year','month','day' )}   ) );
          my $session_published_on_date_end = Date::Calc::Date_to_Time(
            @session{ map { '/article/history.html?published_on_end_'.$_ } ( 'year','month','day' )}, 0,0,0 );
          if ( $session_published_on_date_end < $published_on_date ) {
            my ($year,$month,$day, undef, undef, undef ) = Date::Calc::Time_to_Date($published_on_date);
            @session{map { '/article/history.html?published_on_end_'.$_ } ( 'year','month','day' )} = ( $year, $month, $day );
          } # end if
        } # end if

        my $created_on_date = Date::Parse::str2time($Article->created_on());
        ( $year, $month, $day ) = @session{ map { '/article/history.html?created_on_start_'.$_ } ( 'year','month','day' )};
        if ( Date::Calc::check_date( $year,$month,$day ) ) {
          my $session_created_on_date_start = Date::Calc::Date_to_Time( $year,$month,$day, 0,0,0 );
          if ( $session_created_on_date_start > $created_on_date ) {
            ($year,$month,$day, undef, undef, undef ) = Date::Calc::Time_to_Date($created_on_date);
            @session{map { '/article/history.html?created_on_start_'.$_ } ( 'year','month','day' )} = ( $year, $month, $day );
            $log->debug("Setting created_on_start to $year, $month, $day from $created_on_date $$Article{created_on}");
          } # end if
        } # end if
        ( $year, $month, $day ) = @session{ map { '/article/history.html?created_on_end_'.$_ } ( 'year','month','day' )};
        if ( Date::Calc::check_date( $year,$month,$day ) ) {
          my $session_created_on_date_end = Date::Calc::Date_to_Time( $year,$month,$day, 0, 0, 0 );
          if ( $session_created_on_date_end < $created_on_date ) {
            ($year,$month,$day, undef, undef, undef ) = Date::Calc::Time_to_Date($created_on_date);
            $log->debug("Setting created_on_end to $year, $month, $day from $created_on_date $$Article{created_on}");
            @session{map { '/article/history.html?created_on_end_'.$_ } ( 'year','month','day' )} = ( $year, $month, $day );
          } # end if
        } # end if

        $variable{ExternalRedirect} = $session{'/article/edit.html?referer'} ? $session{'/article/edit.html?referer'} : '/article/history.html';
      } # end if
    } elsif ( sets::isin( $param{func}, [ 'delete','destroy','undelete' ] ) ) {
      my $func = $Article->can($param{func});
      $variable{error} .= $func->( $Article );
      if ( ! $variable{error} ) {
        %param = ();
        $variable{ExternalRedirect} = $session{'/article/edit.html?referer'} ? $session{'/article/edit.html?referer'} : '/article/history.html';
      } # end if
    } elsif ( $param{func} eq 'Copy' ) {
      $variable{Article} = $variable{Article}->copy();
      $variable{error} .= $variable{Article}->save();
    } elsif ( $param{func} eq 'Upload' ) {
      # Save any changes made to Article
      $variable{error} .= $variable{Article}->save(\%param);
      my $Asset = openprint::Asset::upload( 'filename' );
      if ( ref $Asset ne 'openprint::Asset' ) {
        $variable{error} .= $Asset;
      } else {
        my $Article_Asset = new openprint::Article_Asset();
        $variable{error} .= $Article_Asset->save({'asset_id'=>$Asset->id(), 'article_id'=>$Article->id()});
        if ( $param{asset_name} and ! $Asset->name() ) {
          $Asset->save({'name'=>$param{asset_name}});
        } # end if
      } # end if
    } # end if
  } # end if func
	if ( ! $variable{Article}->id() ) {
		$variable{Article}->company_id( $session{company_id} ) if ! $variable{Article}->company_id();
		$variable{Article}->published_on( Date::Format::time2str('%Y-%m-%d %H:%M:%S', time ) ) if ! $variable{Article}->published_on();
	} # end if
	$session{'/article/edit.html?referer'} = $ENV{HTTP_REFERER};
} # end sub edit

sub list {
	$param{category_id} = openprint::Article_Category->transform('id',$param{category_id});

	my $Category = $variable{Category} = new openprint::Article_Category( $param{category_id} );
	_list();
	$session{'/article/list.html?paging_per_page'} = 5 if ! exists $session{'/article/list.html?paging_per_page'};
	$session{'/article/list.html?paging_page'} = 0 if ! exists $session{'/article/list.html?paging_page'};
} # end sub list

sub _list {
	ssi::save_params('/article/list.html', 'paging_page','category_id', 'paging_per_page', 'category' );
} # end sub _list

sub category {
	my $Category = $variable{Category} = new openprint::Article_Category( $param{category_id} );
	if ( $param{btnFunction} eq 'Save' ) {
		$variable{error} .= $Category->save(\%param);
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		$variable{error} .= $Category->delete();
	} elsif ( $param{btnFunction} eq 'Destroy' ) {
		$variable{error} .= $Category->destroy();
	} elsif ( $param{btnFunction} eq 'Upload' ) {
		my $Album = $Category->Photo_Album();
		if ( ! $Album->id() ) {
			$variable{error} .= $Album->save({'name'=>'Images for article category: ' . $Category->name()});
			$variable{error} .= $Category->save({'album_id'=>$Album->id()});
		} # end if
		$variable{error} .= $Album->upload('filename', {
				'name' => $param{asset_name},
				'description' => $param{asset_description},
				'license' => $param{asset_license},
				'attribution' => $param{asset_attribution},
				} );
	} # end if
} # end sub category

sub view {
	$param{article_id} = openprint::Article->transform( id=>$param{article_id} );
	my $Article = $variable{Article} = new openprint::Article( $param{article_id} );
	
	# WHy?
	#$Article->set( \%param );

	# This will save the view as well. This is tracking when a user views an article
	$Article->View();
} # end sub view

sub _comments {
	$param{article_id} = openprint::Article->transform( 'id', $param{article_id} );
	my $Article = $variable{Article} = new openprint::Article( $param{article_id} );
	if ( $param{text} ) {
		if ( ! openprint::Comment->find_one(
			'user_id'	=>	$session{user_id},
			'text'		=>	$param{text},
			'object_id'	=>	$Article->id(),
			'object_type'	=>	'openprint::Article',
			) ) {

			my $approved = 0;
			if ( $session{user_type} eq 'A' or $session{user_id} == $Article->created_by() ) {
				$approved = 1;
			} # endif

			$variable{error} .= new openprint::Comment()->save({
					'text'			=>	$param{text},
					'object_type'	=>	'openprint::Article',
					'object_id'		=>	$Article->id(),
					'approved'		=>	$approved,
					});
		} # end if comment already exists
	} elsif ( $param{action} eq 'approve' ) {
		if ( $session{user_type} eq 'A' or $session{user_id} == $$Article{user_id} ) {
			my $Comment = openprint::Comment->find_one('object_id'=>$$Article{id}, 'object_type'=>'openprint::Article', 'id'=>$param{comment_id} );
			if ( $Comment ) {
				$Comment->save({'approved'=>1});
			} else {
				$variable{error} .= 'Comment not found.';
			} # end if
		} else {
			$variable{error} .= 'You are not authorized to approve this comment.';
		} # end if
	} elsif ( $param{action} eq 'delete' ) {
		my $Comment = new openprint::Comment( $param{comment_id} );
		if ( $Comment->can_delete() ) {
			$Comment->delete();
		} else {
			$variable{error} .= 'You do not have the right to delete that comment.';
		} # end if
	} # end if
} # end sub _comments

sub _assets {
	my $Article = $variable{Article} = new openprint::Article( $param{article_id} );
	if ( $Article->can_edit() ) {
		if ( $param{func} eq 'delete' ) {
			my $Asset = new openprint::Article_Asset({article_id=>$param{article_id}, asset_id=>$param{asset_id}});
			$variable{error} .= $Asset->delete();
		} elsif ( $param{func} eq 'add' ) {
			my ( $id, $filename ) = $param{filename} =~ /^(\d+)_(.+)$/; 
				
			my $Asset = openprint::Asset->find_one(id=>$id, filename=>$filename );
			if ( $Asset ) {
				my $AA = new openprint::Article_Asset({article_id=>$param{article_id}, asset_id=>$$Asset{id}});
				if ( ! $$AA{asset_id} ) {
					$variable{error} .= $AA->save({
						asset_id	=>	$$Asset{id},
						article_id	=>	$param{article_id},
					});
				} else {
					$variable{error} .= 'Asset already in article.';
				} # end if
			} else {
				$variable{error} .= 'Asset not found.';
			} # end if
		} elsif ( $param{func} ) {
			$log->error("article/_assets: Uknown function $param{func}");
		} # end if
	} else {
		$variable{error} .= 'You do not have rights to change this article.';
	} # end if
} # end sub _assets

sub _category_photos {
	my $Category = $variable{Category} = new openprint::Article_Category( $param{category_id} );
	if ( $param{action} eq 'delete' ) {
		my $Photo = openprint::Photo_in_Album->find_one('album_id'=>$param{album_id}, 'asset_id'=>$param{asset_id});
		if ( ! $Photo ) {
			$variable{error} .= 'Photo not found.';
		} else {
			$variable{error} .= $Photo->delete();
		} # end if
	} elsif ( $param{action} eq 'add' ) {
		my $Album = $Category->Photo_Album();
		if ( ! $Album ) {
			$variable{error} .= 'WTF Album not found.';
			return;
		} # end if
		if ( ! $Album->id() ) {
			$variable{error} .= $Album->save({'name'=>'Images for article category: ' . $Category->name()});
			$variable{error} .= $Category->save({'album_id'=>$Album->id()});
		} # end if
		
		my $Asset = new openprint::Asset( $param{asset_id} );
		if ( ! $Asset->id() ) {
			$variable{error} .= 'Asset not found.';
			return;
		} # end if
		my $Photo = new openprint::Photo_in_Album();
		$variable{error} .= $Photo->save({
				'album_id'	=>	$Album->id(),
				'asset_id'	=>	$Asset->id(),
		});
	} else {
		$log->error("article/_category_photos: Uknown function");
	} # end if
} # end sub _category_photos

sub _asset_search_results {
} # end sub _asset_search_results

sub _like {
	my $Article = $variable{Article} = new openprint::Article( $param{article_id} );
	
} # end sub _like

sub feed {
	my ($y,$m,$d) = Date::Calc::Today();
	my $rss = new XML::RSS( version=>'2.0' );
	my $Owner = new openprint::Company( $config{owner_id} );
	$rss->channel(
		title	=>	substr($config{SiteTitle},0,100),
		link	=>	$config{ExternalSiteURL},
		description	=>	'Hedonistic Yet Discerning',
		language	=>	'en',
		copyright	=>	'Copyright ' . $y.' ' . $Owner->name(),
		generator	=>	'IntelligentQuote',
	);
	foreach my $Article ( openprint::Article->find(
			published			=>	1,
			#category_id		=>	$session{'/article/list.html?category_id'},
			order				=> 'published_on DESC',
			limit				=>	100,
		) ) {
		next if $Article->user_type();
		$rss->add_item(
			title	=>	$Article->name(),
			description	=> ( $Article->summary() ? substr($Article->summary(),0,500) : '' ),
			link	=>	'http://www.pleasurablethings.ca/article/view.html?article_id='.$Article->id(),
			pubDate	=>	$Article->published_on(),
			guid	=>	$Article->id(),
			author	=>	$Article->Author()->name(),
			category	=>	$Article->category(),
		);
	} # end foreach
	$variable{Download} = $rss->as_string();
$log->debug("RSS: $variable{Download}");
} # end sub feed 

1;
__END__
