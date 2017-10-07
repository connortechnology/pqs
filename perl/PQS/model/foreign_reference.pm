package PQS::model::foreign_reference;

use strict;
use warnings;
no warnings qw(uninitialized);

use session;

sub add {
  my ($objectid, $object_type, $ref_id, $ref_name) = @_;
  my $dbh = session::dbh;
  my $sql = "insert into foreign_reference (object_id, object_type, ref_id, ref_name) values (?, ?, ?, ?)";
  my $sth = $dbh->prepare($sql);
  $sth->execute($objectiid, $object_type, $ref_id, $ref_name);
}

sub get {
  my ($object_id, $object_type) = @_;
  my $dbh = session::dbh;
  return $dbh->selectall_hashref("select * from foreign_reference where object_id = ? and object_type = ?", "id", undef, $object_id, $object_type);
}

sub remove {
  my ($id) = @_;
  my $dbh = session::dbh;
  my $sql = "delete from foreign_reference where id = ?";
  my $sth = $dbh->prepare($sql);
  $sth->execute($id);
}

sub remove_all {
  my ($object_id, $object_type) = @_;
  my $dbh = session::dbh;
  my $sql = "delete from foreign_reference where object_id = ? and object_type = ?";
  my $sth = $dbh->prepare($sql);
  $sth->execute($object_id, $object_type;)
}