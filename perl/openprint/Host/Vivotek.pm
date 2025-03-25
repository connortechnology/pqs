use strict;
use warnings;

use LWP::UserAgent;
require HTTP::Request;

require openprint::Object;
require openprint::Host;

package openprint::Host::Vivotek;
our @ISA = qw(
		openprint::Host
		);

sub new {
	my ( $class, $Host ) = @_;
	my $self = { Host=>$Host };
	bless $self, $class;
	return $self;
}

sub Host {
	return $_[0]{Host};
}

sub get_status {
	my $self = shift;
	my $ua = LWP::UserAgent->new;
	my $Host = $self->Host();

	foreach my $HI ( $Host->Interfaces() ) {
		my $url = 'http://'.$HI->ip().'/cgi-bin/admin/lsctrl.cgi?cmd=queryStatus&retType=javascript';
		my $req = new HTTP::Request(GET => $url);
		$req->authorization_basic('root', 'p1GraPHic');
		my $response = $ua->request($req);
		if ( $response->is_success() ) {
			my $resp = $response->decoded_content;
			$openprint::log->debug("Got config from $url: " . $resp);

# make a hash of the returned values in content
			my %r =
				map  { split(/=/, $_, 2) }
			grep { m/=/ }
			split(/\n/, $resp);
			return %r;
		} else {
			$openprint::log->warn("Failed to get config from $url: " . $response->status_line());
		}
	} # end foreach
	return;
} # end sub get_status

sub check {
	my $self = shift;
	my @check;
	my $Config = openprint::Host_Config->find_one(host_id=>$self->Host()->id(), order=>'id desc', name=>'status');
	if ( $Config ) {
		my $status = $Config->data();
		if ( $$status{disk_i0_cond} !~ /ready/ ) {
				push @check, 'SD card not ready';
		} else {
			$openprint::log->debug('status was '.(defined($$Config{data_json}) ? $$Config{data_json} : 'undef'));
		}
	} else {
		$openprint::log->warn('No config found for status');
	}
	return @check;
}

sub get_image {
	my ($self,$width,$height) = @_;
	my $Host = $self->Host();

	my ( $username, $password ) = $Host->info('viewer username'), $Host->info('viewer password');
	$username = $Host->info('username') if !$username;
	$password = $Host->info('password') if !$password;
	foreach my $HI ( $Host->Interfaces() ) {
		if ( $HI->online() ) {
			return 'http://'.
				( $username ? join(':', $username, $password).'@' : '' ).
				$HI->ip().'/cgi-bin/viewer/video.jpg'.
				(($width or $height) ? '?resolution='. $width.'x'.($height ? $height : $width*2/3) : '' );
		}
	}
	return;
}

1;
__END__
