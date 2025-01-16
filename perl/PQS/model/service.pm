package PQS::model::service;

use strict;
use warnings;
no warnings qw(uninitialized);

use session;

sub get_material_usage {
  my ($sid) = @_;
  my $dbh = session::dbh;

  my $qry = "select * from service_materials where sid = ?";
  return $dbh->selectall_arrayref($qry, {Slice => {}}, $sid);
}

sub set_material_estimate {
  my ($estimate, $id, $sid, $mid, $qty_index) = @_;
  my $dbh = session::dbh;

  return unless $mid;

  my $qry = "select id from service_materials where sid = ? and mid = ? and qty_index = ?";
  ($id) = $dbh->selectrow_array($qry, undef, $sid, $mid, $qty_index) if (!$id && $sid && $mid && $qty_index);

  if ($id) {
    $qry = "update service_materials set estimate = ? where id = ?";
    if (!$dbh->do($qry, undef, $estimate, $id)) {
      print STDERR "Failed to update service_materials $!\n";
    }
    return;
  }
  $qry = "insert into service_materials (sid, mid, qty_index, estimate) values (?, ?, ?, ?)";
  $dbh->do($qry, undef, $sid, $mid, $qty_index, $estimate) or die "Failed to insert into service_materials $!\n";
  $dbh->commit;
}

sub set_material_actual {
  my ($actual, $id, $sid, $mid, $qty_index) = @_;
  my $dbh = session::dbh;

  my $qry = "select id from service_materials where sid = ? and mid = ? and qty_index = ?";
  ($id) = $dbh->selectrow_array($qry, undef, $sid, $mid, $qty_index) if (!$id && $sid && $mid && $qty_index);

  if ($id) {
    $qry = "update service_materials set actual = ? where id = ?";
    if (!$dbh->do($qry, undef, $actual, $id)) {
      print STDERR "Failed to update service_materials $!\n";
    }
    return;
  }
  $qry = "insert into service_materials (sid, mid, qty_index, actual) values (?, ?, ?, ?)";
  $dbh->do($qry, undef, $sid, $mid, $qty_index, $actual) or die "Failed to insert into service_materials $!\n";
}

sub get_index_from_id {
	my $id = shift;
  my $dbh = session::dbh;
  return $dbh->selectrow_array(q{ SELECT lngindex FROM tbl_equipment WHERE strid = ?}, undef, $id );
}

1;
__END__
