package session;
use strict;
use warnings;

my $SESSION = {};

sub r {
  my ($r) = @_;
  return $SESSION->{r} if @_ == 0;
  $SESSION->{r} = $r;
}

sub log {
  my ($log) = @_;
  return $SESSION->{log} if @_ == 0;
  $SESSION->{log} = $log;
}

sub dbh {
  my ($dbh) = @_;
  return $SESSION->{dbh} if @_ == 0;
  $SESSION->{dbh} = $dbh;
}
1;