package PQS::model::bills;

use strict;
use warnings;
no warnings qw(uninitialized);

use session;
use Data::Dumper;
#use PQS::model::foreign_reference;



sub insert {
  my $dbh = session::dbh;

  $dbh->do("insert into bills ( company, category ) values ( ?, ? )" , undef, @_);

  my  $id = $dbh->last_insert_id('', 'public', 'bills', 'id');
 print STDERR "HAVE ID FOR INSERT: $id -- @_ \n";
 return $id;
  
}
sub update {
  my $dbh = session::dbh;
  my $param = shift;
  my $id 	= shift;


  $dbh->do("UPDATE  bills set company = ?, category = ?, billdate = ?, duedate = ?, amount = ?, description = ?
	 WHERE id = ? "
	 , undef, 
	 $param->{company},
	 $param->{category},
	 $param->{billdate},
	 $param->{duedate},
	 $param->{amount},
	 $param->{description},
	 $id
 );
}


sub get {
  my ($id) = @_;
  my $dbh = session::dbh;

  my $data = $dbh->selectrow_hashref("select * from bills where id = ?",undef, $id);
}

1;
