# This file allows access to all material information including paper\
package PQS::model::materials;
use strict;
use warnings;
no warnings qw(uninitialized);

use session;

sub material_type_by_id {
  my ($id) = @_;
  my $dbh = session::dbh;
  my $qry = "select * from material_type where id = ?";
  return $dbh->selectrow_hashref($qry, undef, $id);
}

sub material_by_id {
  my ($id) = @_;
  my $dbh = session::dbh;
  my $is_paper = 0;
  my $is_paper_roll = 0;
  my $qry = "select * from tbl_materials where lngindex = ?";
  my $result = $dbh->selectrow_hashref($qry, undef, $id);
  if (!$result) {
    $is_paper = 1;
    $qry = "select * from tbl_paper where lngindex = ?";
    $result = $dbh->selectrow_hashref($qry, undef, $id);
  }
  if (!$result) {
    $is_paper_roll = 1;
    $qry = "select * from tbl_paper_roll where lngindex = ?";
    $result = $dbh->selectrow_hashref($qry, undef, $id);
  }
  return $result if !$result;
  return _load_paper($result) if $is_paper;
  return _load_material($result);
}

sub material_by_strid {
  my ($id) = @_;
  my $dbh = session::dbh;
  my $is_paper = 0;
  my $is_paper_roll = 0;
  my $qry = "select * from tbl_materials where strid = ?";
  my $result = $dbh->selectrow_hashref($qry, undef, $id);
  if (!$result) {
    $is_paper = 1;
    $qry = "select * from tbl_paper where strid = ?";
    $result = $dbh->selectrow_hashref($qry, undef, $id);
  }
  if (!$result) {
    $is_paper_roll = 1;
    $qry = "select * from tbl_paper_roll where strid = ?";
    $result = $dbh->selectrow_hashref($qry, undef, $id);
  }
  return $result if !$result;
  return _load_paper($result) if $is_paper;
  return _load_material($result);
}

sub _load_material {
  my ($result) = @_;
  my $dbh = session::dbh;
  my $qry = "select * from tbl_material_prices where lngmaterialindex = ?";
  $result->{prices} = $dbh->selectall_arrayref($qry, {Slice => {}}, $result->{lngindex});
  return $result;
}

sub _load_paper {
  my ($result) = @_;
  my $dbh = session::dbh;
  my $qry = "select * from tbl_paper_prices where lngpaperindex = ?";
  $result->{prices} = $dbh->selectall_arrayref($qry, {Slice => {}}, $result->{lngindex});
  $qry = "select * from paper_specs where lngindex = ?";
  $result->{specs} = $dbh->selectall_arrayref($qry, {Slice => {}}, $result->{lngindex});
  return $result;
}

1;