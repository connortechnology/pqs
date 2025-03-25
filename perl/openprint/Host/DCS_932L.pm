use strict;
use warnings;

require LWP::UserAgent;
require HTTP::Request;

require openprint::Object;
require openprint::Host;

package openprint::Host::DCS_932L;
our @ISA = qw( openprint::Object );

sub new {
	my ( $class, $Host ) = @_;
	my $self = { Host=>$Host };
	bless $self, $class;
	return $self;
}

sub Host {
	return $_[0]{Host};
}

sub get_config {
	my $self = shift;
	my $Host = $self->Host();
	my %r;

  my $browser = LWP::UserAgent->new();
  if ( $Host->type() eq 'DCS-932L' ) {
    my $protocol = 'http';
    my $path = '/Config.CFG';
    my $method = 'get';
    my $port = 80;
    my $args;
    foreach my $HI ( $Host->Interfaces() ) {

      my $url = $protocol.'://'.$HI->ip().$path;
      my $response = $browser->get($url);
      $openprint::log->debug("Sending initial url: $url");
      my $headers = $response->headers();
      if ( $$headers{'client-ssl-cipher'} ) {
        $openprint::log->debug("Swtiching to https");
        $protocol = 'https';
        $port = 443;
      }
      $response = $HI->authenticate( $browser, $response, $method, $port, $url, $args);
      #$openprint::log->debug($response->content());
      if ( !$response->is_success ) {
      } else {
$openprint::log->debug($response->content());
        return $response->content();
        last;
      }

    } # end foreach HI
  } # end if type

	return %r;
} # end sub get_config

sub get_status {
  my $self = shift;
  my $Host = $self->Host();
  my %r;

  my $browser = LWP::UserAgent->new();
  if ( $Host->type() eq 'DCS-932L' ) {
    my $protocol = 'http';
    my $path = '/STSDEV.HTM';
    my $method = 'get';
    my $port = 80;
    my $args;
    foreach my $HI ( $Host->Interfaces() ) {

      my $url = $protocol.'://'.$HI->ip().$path;
      my $response = $browser->get($url);
      $openprint::log->debug("Sending initial url: $url");
      my $headers = $response->headers();
      if ( $$headers{'client-ssl-cipher'} ) {
        $openprint::log->debug("Swtiching to https");
        $protocol = 'https';
        $port = 443;
      }
      $response = $HI->authenticate( $browser, $response, $method, $port, $url, $args);
      #$openprint::log->debug($response->content());
      if ( !$response->is_success ) {
      } else {
$openprint::log->debug($response->content());
        return $response->content();
        last;
      }

    } # end foreach HI
  } # end if type

  return %r;
} # end sub get_status

1;
__END__
