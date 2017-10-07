package PQS::API::Handler;

use Apache2::Log ();
use PQS::API;
use session;

sub handler {
  my $r = shift;

  session::r($r);
  session::log($r->log);
  session::dbh(PQS::DB->connect($r));

  my $app = PQS::API->new(request => $r);
  $app->run();
}

1;