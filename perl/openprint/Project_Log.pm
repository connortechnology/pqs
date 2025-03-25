use strict;
package openprint::Project_Log;
our @ISA = qw(openprint::Object);
require openprint::Host;
require openprint::Host_Interface;

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults );

$debug = 0;
$table = 'project_log';
$serial= 'project_log_id_seq';
%fields = (
	id						=>	'id',
	project_id		=>	'project_id',
	company_id		=>	'company_id',
	user_id				=>	'user_id',
	created_on		=>	'dtmtimestamp',
	description		=>	'description',
	host_id				=>	'host_id',
);
%find_fields = (
	salesrep_id		=>	'(SELECT salesrep_id FROM companies WHERE companies.id=(SELECT company_id FROM projects WHERE projects.id=project_id))',
);
%transforms = (
);
%defaults = (
	created_on		=>	q`'NOW()'`,
	host_id				=>	q`$self->ip_address( $ENV{HTTP_X_FORWARDED_FOR} ? $ENV{HTTP_X_FORWARDED_FOR} : $ENV{REMOTE_ADDR} );return $$self{host_id};`,
);

sub description_html {
	if ( ! $_[0]{description_html} ) {
	
		if ( $_[0]{description} =~ /^Reused from project (\d+)$/ ) {
			$_[0]{description_html} = 'Reused from project '.new openprint::Project($1)->link_to();
		} elsif ( $_[0]{description} =~ /^Reused to project (\d+)$/ ) {
			$_[0]{description_html} = 'Reused to project '.new openprint::Project($1)->link_to();
		} elsif ( $_[0]{description} =~ /^Add to Order (\d+)$/ ) {
			$_[0]{description_html} = 'Add to Order <a href="/employee/project/view.html?order_id='.$1.'">'.$1.'</a>';
		} elsif ( $_[0]{description} =~ /^Removed from order (\d+)$/ ) {
			$_[0]{description_html} = 'Removed from order <a href="/employee/project/view.html?order_id='.$1.'">'.$1.'</a>';
		} elsif ( $_[0]{description} =~ /^Add to quote (\d+) prices: ([\d\.]+)$/ ) {
			$_[0]{description_html} = 'Add to quote <a href="/main/quote/history_details.html?quote_id='.$1.'">'.$1."</a> prices: $2";
		} else {
			$_[0]{description_html} = $_[0]{description}
		} # end if
	} # end if
	return $_[0]{description_html};
} # end sub description_html

sub Project {
	return new openprint::Project( $_[0]{project_id} );
} # end sub Project
sub Company {
	return new openprint::Company( $_[0]{company_id} );
} # end sub Company
sub User {
	return new openprint::User( $_[0]{user_id} );
} # end sub USer;

sub Host {
  if ( ( ! $_[0]{host_id} ) and $_[0]{ip_address} ) {
    my $Interface = openprint::Host_Interface->find_one( ip=>$_[0]{ip_address} );
    my $Host;
    if ( ! $Interface ) {
      $Host = new openprint::Host();
      $Host->save();
      $Interface = new openprint::Host_Interface();
      $Interface->save({host_id=>$$Host{id}, ip=>$_[0]{ip_address} });
    } else {
      $Host = $Interface->Host();
    }

    $_ = $_[0]->save({host_id=>$Host->id()});
    $openprint::log->error( $_ ) if $_;
  } # end if

  return new openprint::Host( $_[0]{host_id} );
} # end sub Host

sub ip_address {
  my $Host = $_[0]->Host();

  if ( @_ > 1 ) {
    if ( ! defined $_[1] ) {
      $_[1] = $ENV{HTTP_X_FORWARDED_FOR} ? $ENV{HTTP_X_FORWARDED_FOR} : $ENV{REMOTE_ADDR};
    } # end if
    if ( $_[1] ) {
	    my $Interface = openprint::Host_Interface->find_one( ip=>$_[1] );
	    if ( ! $Interface ) {
	      $Host = new openprint::Host();
	      $Host->save();
	      $Interface = new openprint::Host_Interface();
	      $Interface->save({host_id=>$$Host{id}, ip=>$_[1] });
	    } else {
	      $Host = $Interface->Host();
	    } # end if
	    $_[0]{host_id} = $Host->id();
    }
  } # end if
  return join('<br/>', map { $_->ip() ? $_->ip() : () } $Host->Interfaces() );
} # end sub ip_address


1;
__END__
