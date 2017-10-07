package PQS::Cron;
use strict;
use warnings;
use utf8;

use Apache2::Const qw(HTTP_NO_CONTENT FORBIDDEN);
use Apache2::Request ();
use Apache2::RequestUtil ();
use Apache2::ServerUtil;
use Apache2::Log ();
use PQS::DB ();
use session;
use callback;
use configuration;

sub handler {
  my $r = shift;

  # Subclass the Apache request object for a better parameter interface.
  $r = Apache2::Request->new($r);

  # Establish a connection to the database and allow everyone in the current
  # request to access it.
  my $dbh = PQS::DB->connect($r);

  session::r($r);
  session::log($r->log);
  session::dbh($dbh);

  #authenticate security key
  my $key = configuration::get_value($r->log, $dbh, "cron_key");
  unless ($key) {
    $r->log_error("No cron_key found in the configuartion table");
    $r->status(FORBIDDEN);
    $dbh->disconnect;
    return FORBIDDEN;
  }
  if ($key ne $r->param("key")) {
    $r->log_error("Provided key does not match cron_key in configuration table");
    $r->status(FORBIDDEN);
    $dbh->disconnect;
    return FORBIDDEN;
  }

  #Run Cron Callbacks
  callback::call("Cron");

  $dbh->commit();
  $dbh->disconnect;

  $r->status(204);
  return 204;
}

1;