use strict;
require Date::Parse;
require Date::Format;
require openprint::Event_Category;
require openprint::Comment;
require openprint::Event_Attendance;
require openprint::Event_Invitation;
require openprint::Blocklist;

package openprint::Event;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults );
$debug = 0;
$table = 'events';
$serial = 'events_id_seq';

%fields = (
	id			=>	'id',
	name		=>	'name',
	created_by	=>	'created_by',
	starting_on	=>	'starting_on',
	ending_on	=>	'ending_on',
	created_on	=>	'created_on',
	updated_on	=>	'updated_on',
	deleted		=>	'deleted',
	location_id	=>	'location_id',
	info		=>	'info',
	time_associated	=>	'time_associated',
	category_id	=>	'category_id',
	category	=>	undef,
	#'asset_id		=>	'asset_id',
	# Photo album for the event, created on first photo upload
	album_id	=>	'album_id', 
	url			=>	'url',
	published	=>	'published',
	template	=>	'template',
	template_id	=>	'template_id',
);
%find_fields = (
	attending	=>	'(SELECT user_id FROM event_attendance WHERE event_id=events.id AND attending=true)',
	'name+info'	=>	q`name || info`,
	company_id	=>	'(SELECT company_id FROM Users WHERE users.id=events.created_by)',
);
%transforms = (
	id		=>	[ 's/\D//g', '<2147483647' ],
    name	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    info	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    url		=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
	created_on	=>	q`'NOW()'`,
	updated_on	=>	q`'NOW()'`,
	starting_on	=>	undef,
	ending_on	=>	undef,
	location_id	=>	undef,
	#'asset_id		=>	undef,
	time_associated	=> 0,
	created_by		=> q`$openprint::session{user_id}`,
	deleted			=> 0,
	published		=>	0,
	template		=>	0,
);

sub category {
	if ( @_ > 1 ) {
		my $new = openprint::Event_Category->transform('name',$_[1]);
		if ( $new ) {
			my $Category = openprint::Event_Category->find_one('name lc'=>lc $new );
			if ( ! $Category ) {
				$Category = new openprint::Event_Category();
				$Category->save({name=>$_[1]});
			} # end if	
			$_[0]{category_id} = $Category->id();
			return $Category->name();
		} else {
			$_[0]{category_id} = undef;
		} # end if	
	} # end if
	return new openprint::Event_Category( $_[0]{'category_id'} )->name();
} # end sub category

sub Category {
	return new openprint::Event_Category( $_[0]{'category_id'} );
} # end sub Category

sub where {
	if ( ! $_[0]{'where'} ) {
		my $L = $_[0]->Location();
		$_[0]{'where'} .= '<a href="/location/view.html?location_id='.$L->id().'">';
		$_[0]{'where'} .= $L->name().'<br/>';
		if ( $L->address() or $L->postalcode() ) {
			$_[0]{'where'} .= $L->address() . ', '.$L->postalcode().'<br/>';
		} # end if
		$_[0]{'where'} .= join(', ', map { $_->name() } $L->Parents() );
		$_[0]{'where'} .= '</a>';
		if ( $L->url() ) {
			$_[0]{'where'} .= '<br/><a target="_blank" href="'.$L->url().'">'.$L->url().'</a>';
		} # end if
	} # end if
	return $_[0]{'where'};
} # end sub where

sub Asset {
	if ( ! $_[0]{'Asset'} ) {
		my $Album = $_[0]->Album();
		if ( $Album->id() ) {
#$openprint::log->debug("Album? " . $Album->to_string() );
			if ( $$Album{'thumbnail_id'} ) {
				$_[0]{'Asset'} = new openprint::Asset( $$Album{'thumbnail_id'} );
			} elsif ( my @Photos = $Album->Photos() ) {
				$_[0]{'Asset'} = $Photos[0]->Asset();;
			} else {
				$_[0]{'Asset'} = new openprint::Asset();
			} # end if
		} else {
			$_[0]{'Asset'} = new openprint::Asset();
		} # end if
	} # end if
	return $_[0]{'Asset'};
} # end sub Asset

sub location {
	if ( @_ > 1 ) {
		$_[1] = openprint::Location->transform('name', $_[1]);
		my $Location = openprint::Location->find_one('name lc'=>lc $_[1]);
		if ( ! $Location ) {
			$Location = new openprint::Location();
			$Location->save({name=>$_[1]});
		} # end if
		$_[0]{location_id} = $Location->id();
		return $Location->name();
	} # end if
	return new openprint::Location( $_[0]{'location_id'} )->name();
} # end if

sub Photos {
	if ( ! $_[0]{'album_id'} ) {
		return ();
	} # end if
	return $_[0]->Album()->Photos( );
} # end sub Photos

sub Album {
	return new openprint::Photo_Album( $_[0]{'album_id'} );
} # end sub Album
sub can_create {
	return 0 if ! $_[0]{id};
} # end sub can_create

sub can_edit {
	return 1 if ! $_[0]{id};
	return 1 if $openprint::session{user_id} == $_[0]{created_by};
	return 1 if $openprint::session{user_type} eq 'A';

	return 0;
} # end sub can_edit

sub can_view {
#$openprint::log->debug("Event::can_view $_[1]" . ( ref $_[1] eq 'openprint::User' ? $_[1]->to_string() : $_[1] ) );
	return 1 if ! $_[0]{id};
	my $User;
	if ( @_ > 1 and $_[1] ) {
		$User = ref $_[1] eq 'openprint::User' ? $_[1] : new openprint::User($_[1]);
    #$openprint::log->debug("Using specified user $_[1]");
	} else {
		$User = $openprint::User;
	} # end if
	return 1 if $$User{type} eq 'A';
  #$openprint::log->debug("Event::can_view not an admin $$User{email} $$User{type}");
	return 1 if $_[0]{created_by} == $$User{id};
#$openprint::log->debug("Event::can_view not creator");
	return 0 if $_[0]{deleted};
#$openprint::log->debug("Event::can_view not deleated");
	return 0 if openprint::Blocklist::is_blocked( $openprint::session{user_id}, $_[0]{created_by});
#$openprint::log->debug("Event::can_view not blocked");
	my $Privacy = $_[0]->Privacy();
	return 1 if ! $$Privacy{id};
	return $Privacy->can_view($$User{id});
} # end sub can_view

sub Comments {
	return openprint::Comment->find({'object_type'=>'openprint::Event','object_id'=>$_[0]{'id'}});
} # end sub Comments

sub Attendance {
	if ( ! $_[0]{'Attendance'} ) {
		@{$_[0]{'Attendance'}} = openprint::Event_Attendance->find('event_id'=>$_[0]{'id'});
	} # end if
	return @{$_[0]{'Attendance'}};
} # end sub Attendance

sub Created_By {
	return new openprint::User( $_[0]{'created_by'} );
}

sub html {
	my ( $Event, $options ) = @_;
	$options = {} if ! $options;
	my $html = sprintf(q`
			<div class="Event">
			<div class="Assets"><a class="medium %6$s" href="/event/view.html?event_id=%1$d"><img alt="" src="%7$s"/></a></div>
			<div class="Name"><a href="/event/view.html?event_id=%1$d">%2$s</a></div>
			<div class="Category"><a href="/event/view.html?event_id=%1$d">%3$s</a></div>
			<div class="When">%4$s</div>
			<div class="Where">%5$s</div>
			`, $Event->id(), ssi::html_escape($Event->name()), $Event->Category()->name(),
                    $Event->time_string(),
                    $Event->where(),
			$Event->Asset()->layout(),
			$Event->Asset()->medium_url(),
			);
	if ( (!$$options{show_no_attendees}) and ( $Event->Attendance() == 0 ) ) {
	} else {
		$html .= sprintf('<div class="Attending">%s</div>', $Event->attendance( new openprint::User($openprint::session{user_id}) ) );
	} # end if
	
	my @Comments = $Event->Comments();
	if ( (!$$options{show_no_comments}) and ( @Comments == 0 ) ) {
	} else {
		$html .= sprintf(q`<div class="comments">This event has %s.</div>`, ( @Comments == 1 ? '1 comment' : @Comments . ' comments' ) );
	} # en dif
	$html .= '</div>';
	return $html;
} # end  sub html

sub Location {
	if ( ! $_[0]{'Location'} ) {
	$_[0]{'Location'} = new openprint::Location( $_[0]{'location_id'} );
	} # end if
	return $_[0]{'Location'};
} # end sub Location

sub time_string {
	if ( @_ > 1 ) {
		$_[0]{'time_string'} = $_[1];
	}
	if ( ! $_[0]{'time_string'} ) {
		my $time_string;
		my $starting_on_seconds = Date::Parse::str2time($_[0]{'starting_on'});
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		my ($ssec,$smin,$shour,$smday,$smon,$syear,$swday,$syday,$sisdst) = localtime($starting_on_seconds);
		if ( $syear == $year and $smon == $mon and $smday == $mday ) {
			# starts today
			$time_string .= 'today';
			if ( $_[0]{'time_associated'} ) {
				$time_string .= ' at '.Date::Format::time2str( '%l:%M%P', $starting_on_seconds );
			} # end if
		} elsif ( $_[0]{'time_associated'} ) {
			$time_string .= Date::Format::time2str( '%a, %h %d %Y at %l:%M%P', $starting_on_seconds );
		} else {
			$time_string .= Date::Format::time2str( '%a, %h %d %Y', $starting_on_seconds );
		} # end if
		if ( $_[0]{ending_on} ) {
			my $ending_on_seconds = Date::Parse::str2time($_[0]{'ending_on'});
			my ($esec,$emin,$ehour,$emday,$emon,$eyear,$ewday,$eyday,$eisdst) = localtime($ending_on_seconds);
			$time_string .= ' until ';
			if ( $eyear == $syear and (($eyday == $syday ) or ( $eyday == $syday+1 and $ehour < 7) ) ) {
				$time_string .= Date::Format::time2str( '%l:%M%P', $ending_on_seconds );
			} elsif ( $_[0]{'time_associated'} ) {
				$time_string .= Date::Format::time2str( '%a, %h %d %Y at %l:%M%P', $ending_on_seconds );
			} else {
				$time_string .= Date::Format::time2str( '%a, %h %d %Y', $ending_on_seconds );
			} # end if
		} # end if ending_on
		$_[0]{time_string} = $time_string;
	} # end if
	return $_[0]{time_string};
} # end sub time_string

sub thumbnail_id {
	return $_[0]->Album()->thumbnail_id();
} # end sub thumbnail_id

sub thumbnail_html {
	if ( ! $_[0]{'thumbnail_html'} ) {
		my $Asset = $_[0]->Asset();
		if ( $Asset and $$Asset{'id'} ) {
			$_[0]{'thumbnail_html'} = sprintf('<a href="/event/view.html?event_id=%1$d" class="thumbnail"><img src="%2$s" alt="%3$s" title="%3$s" /></a>',
					$_[0]{'id'}, $Asset->sized_url('thumbnail'), $_[0]->name() );
		} # end if
	} # end if
	return $_[0]{'thumbnail_html'};
} # end sub thumbnail_html

sub asset_html {
	if ( ! $_[0]{'asset_html'} ) {
		my $Album = new openprint::Photo_Album( $_[0]{'album_id'} );
		my $Thumbnail = $Album->Thumbnail() if $Album and $$Album{'id'};

		if ( $Thumbnail and $$Thumbnail{'asset_id'} ) {
			$_[0]{'asset_html'} = sprintf('<a class="Asset" href="/event/view.html?event_id=%1$d"><img src="%2$s" alt="%3$s" title="%3$s" /></a>',
					$_[0]{'id'}, $Thumbnail->Asset()->url(), $_[0]->name() );
		} # end if
	} # end if
	return $_[0]{'asset_html'};
} # end sub asset_html

sub upload {
	my $self = shift;
	my $Album = $self->Album();
	if ( ! $Album->id() ) {
		$Album->save({ 'Photos for event: ' . $$self{'name'} });
		$self->save({'album_id'=>$Album->id()});
	} # end if
	return $Album->upload( @_ );
} # end sub upload

sub view_url {
	return '/event/view.html?event_id='.$_[0]{'id'};
} # end sub view_url

sub invited_user_ids {
	return map { $_->user_id() } openprint::Event_Invitation->find('event_id'=>$_[0]{'id'});
} # end sub invited_user_ids

sub Invitations {
	return openprint::Event_Invitation->find('event_id'=>$_[0]{'id'});
} # end sub Invitations

# Should only ever email people once, and maybe only if it's by email only
sub send_invitations {
	my ( $self, $message ) = @_;

	my %data;
	$data{Event} = $self;
	$data{uri} = 'event';
	$data{message} = $message;
	$data{User} = new openprint::User($openprint::session{user_id});
	$data{'ReplacementText'} = ssi::include( '/email_content/event_invitation_body.html', \%data );

	my $Email = new openprint::Email();
	$Email->html_body( ssi::include( '/email_template.html', \%data ) );
	my @To = openprint::Event_Invitation->find(event_id=>$$self{id}, ( $message ? () : ( 'sent_on is null'=>1) ) );
	my $results = $Email->send(
		BCC			=>	new openprint::User( $openprint::session{user_id} ),
		#TO			=>	new openprint::User( $openprint::session{user_id} ),
		TO			=>	[map { $_->User() } @To ],
		FROM		=>	$self->Created_By(),
		SUBJECT		=>	'You are invited to an event:'. $$self{name},
	);
	$self->add_to_log( $results );
	foreach ( @To ) {
		$_->save({sent_on=>'NOW()'});
	} # end foreach
	return $results;
} # end sub send_invitations

sub attendance {
	my ( $self, $User ) = @_;

	if ( ! $_[0]{'attendance'} ) {
	    my @Attending = $self->Attendance();
		my ( @yes, @no, @maybe );
		foreach my $A ( @Attending ) {
			next if ! defined $$A{'attending'};
			if ( $$A{'attending'} ) {
				push @yes, $A;
			} elsif ( ! defined $$A{'attending'} ) {
				push @maybe, $A;
			} else {
				push @no, $A;
			} # end if
		} # end foreach
		my $html = '';
		if ( @yes == 0 ) {
			$html .= 'No one is attending (yet). ';
		} elsif ( @yes == 1 ) {
			if ( $yes[0]{'user_id'} == $User->id() ) {
				$html .= 'You are the only person attending.(so far). ';
			} else {
				$html .= '1 person is attending.(so far). ';
			} # end if
		} else {
			$html = @yes . ' people are attending. ';
		} # end if
		if ( @maybe == 1 ) {
			if ( $maybe[0]{user_id} == $User->id() ) {
				$html .= 'you might attend.';
			} else {
				$html .= '1 person might attend.';
			} # end if
		} elsif ( @maybe ) {
			$html .= @maybe. ' people might attend';
		} # end if
		$$self{'attendance'} = $html;
	} # end if
	return $$self{'attendance'};
} # end sub attendance

sub copy {
	my $New = $_[0]->SUPER::copy();
	my $Album = $_[0]->Album()->copy();
	$New->save({created_on=>undef,updated_on=>undef,created_by=>$openprint::session{user_id},deleted=>0,album_id=>$$Album{id}});
	return $New;
} # end sub copy

sub Template {
	if ( ! $_[0]{Template} ) {
		$_[0]{Template} = new openprint::Event( $_[0]{template_id} );
	} # end if
	return $_[0]{Template};
} # end sub Template

sub head_html { 
	my $Event = $_[0];

	my $description;
	if ( $Event->info() ) {
    require HTML::Strip;
		my $hs = HTML::Strip->new();
		$description = $hs->parse($Event->info());
		$hs->eof();
	} # end if
    my $Asset = $Event->Asset();

	my $html =  '<head itemscope itemtype="http://schema.org/Event">'."\n";
	$html .= '<link rel="image_src" href="'.$openprint::config{siteURL}.$Asset->sized_url('medium').'"/>' if $Asset;
	$html .= '<meta name="RATING" content="RTA-5042-1996-1400-1577-RTA" />'."\n";
	$html .= '<meta itemprop="name" content="'. ssi::html_escape( $Event->name() ).'"/>'."\n";
	$html .= '<meta itemprop="description" content="'.$description.'"/>'."\n" if $description;
	$html .= '<meta name="startDate" content="'. $Event->starting_on().'" />'."\n" if $Event->starting_on();
	$html .= '<meta name="endDate" content="'. $Event->ending_on().'" />'."\n" if $Event->ending_on();
	$html .= '<meta name="image" content="'.$Asset->sized_url('medium').'"/>'."\n" if $Asset;
    
	return $html;
} # end sub html_head

sub published_on {
	return $_[0]{starting_on};
}

1;
__END__
