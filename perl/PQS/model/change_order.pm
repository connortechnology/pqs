package PQS::model::change_order;
use strict;
use warnings;
no warnings qw(uninitialized);

use session;

# only records the beginning of a change order
# the specific actions required to meet the change order is being done elsewhere
sub create_change_order {
  my ($old, $new, $comment) = @_;
  my $dbh = session::dbh;
  my $change_order = get_change_order($old);

  if ($change_order) {
    my $sth = $dbh->prepare("update change_orders set pid_from = ?, pid_to = ?, comment = ?, complete = false where pid_from = ?");
    $sth->execute($old, $new, $change_order->{comment} . "\n\n" . $comment, $old);
    return;
  }

  my $sth = $dbh->prepare("insert into change_orders (pid_from, pid_to, comment) values (?,?,?)");
  $sth->execute($old, $new, $comment);
}

#completes a change order
#only one of the project ids is required
sub complete_change_order {
  my ($old, $new) = @_;
  return unless $old || $new;
  my $dbh = session::dbh;
  my @values;

  my $qry = "update change_orders set complete = true where ";

  $qry .= "pid_from = ?" if ($old);
  $qry .= "pid_to = ?" if ($new);
  push @values, $old if ($old);
  push @values, $new if ($new);

  my $sth = $dbh->prepare($qry);
  $sth->execute(@values);
}

#returns the change order information in a hash with keys
## pid_from, pid_to, comment, complete
#the project id is compared to the pid_from
sub get_change_order {
  my ($pid) = @_;
  my $dbh = session::dbh;

  return $dbh->selectrow_hashref("select * from change_orders where pid_from = ?", undef, $pid);
}

#returns the change order information in a hash with keys
## pid_from, pid_to, comment, complete
#the project id is compared to the pid_to
sub get_parent_change_order {
  my ($pid) = @_;
  my $dbh = session::dbh;

  return $dbh->selectrow_hashref("select * from change_orders where pid_to = ?", undef, $pid);
}
1;