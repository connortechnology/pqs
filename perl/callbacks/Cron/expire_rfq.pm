use callback;
use session;
use eprint::project;
use eprint::service qw(service_type);
use Data::Dumper;

my $func = sub {
  my $dbh = session::dbh();
  $dbh->do("update rfq set status = 'Closed' where status = 'Open' and closing_date < current_date");
};
callback::register('Cron', 'expire_rfq', $func);
1;