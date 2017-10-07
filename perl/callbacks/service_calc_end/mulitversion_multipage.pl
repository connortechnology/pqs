use callback;
use session;
use eprint::project;
use eprint::service qw(service_type);
use Data::Dumper;

#add additional costs if it is a multi-version multi-page project.
# $makeready and $run need to be referencces to the values so they can be altered
my $func = sub {
  my ($pid, $sid, $makeready, $run, $eid) = @_;
  my $dbh = session::dbh();
  my $log = session::log();
  my $markup = 0;

  #need the book service id for the project. If there isn't one this isnt a multipage project
  my $bookid = eprint::project::get_service_index($log, $dbh, $pid, 'Book');
  return unless $bookid;

  #need the number of versions if there aren't more than one this function isn't needed
  my ($num_versions) = eprint::service::get_specifications($log, $dbh, $pid, $bookid, ('num_versions'));
  return unless $num_versions > 1;

  #if there is an equipment id check for a make ready markup
  if ($eid) {
    $markup += eprint::equipment::get_specification($log, $dbh, 'mv_mp_mkrdy_mkup', undef, $eid);
  }

  my $service_type = service_type($dbh, $sid);
  my ($smarkup) = $dbh->selectrow_array('select mvmp_makerdy_markup from tbl_service_types where strid = ?', undef, $service_type);
  $markup += $smarkup;

  #add a make ready cost increase
  $$makeready += $$makeready * ($markup / 100.0) * $num_versions;
};
callback::register('service_calc_end', 'multiversion_multipage', $func);
1;