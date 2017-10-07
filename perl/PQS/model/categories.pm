package PQS::model::categories;

use strict;
use warnings;
no warnings qw(uninitialized);

use session;
use Data::Dumper;

sub get {
  my ($id) = @_;
  my $dbh = session::dbh;

  my $id = $dbh->selectrow_hashref("select * from categories where id = ?", undef, $id);
}

sub get_children_from_id {
  my ($id) = @_;
  my $dbh = session::dbh;

  my $list;
  if ( $id ) {
  	$list = $dbh->selectcol_arrayref("select id from categories where parent = ? ORDER BY name ", undef, $id);
   } else {
  	$list = $dbh->selectcol_arrayref("select id from categories where parent is NULL ORDER BY name ");
  }
}

sub get_parent_from_id {
  my ($id) = @_;
  my $dbh = session::dbh;

  my $id = $dbh->selectrow_array("select parent from categories where id = ?", undef, $id);
}

sub get_id_from_name {
  my ($str) = @_;
  my $dbh = session::dbh;

  my $id = $dbh->selectrow_array("select id from categories where name = ?", undef, $str);
}

sub get_name_from_id {
  my ($str) = @_;
  my $dbh = session::dbh;

  my $id = $dbh->selectrow_array("select name from categories where id = ?", undef, $str);
}
sub get_all {
  my $dbh = session::dbh;

  my $all = $dbh->selectall_hashref("select * from categories",'id');
  
  my $cats;
  my $subcats;
  
  map {
    my $c = $all->{$_};
    if ( $c->{parent} ) {
      push @{$subcats->{$c->{parent}}}, $c;
    } else {
      $cats->{ $all->{$_}{name} } = $all->{$_};
    }
  } keys $all;
  
  foreach my $cat ( keys $cats ) {
    
    my $children = $subcats->{$cats->{$cat}{id}};
    
    @{$children} = sort { $a->{name} cmp $b->{name} } @{$children} if defined $children;
   
    $cats->{$cat}{children} = $children;
  }
  
  
  
 
#print STDERR "HAVE MY CATS", Dumper($cats);

  return $cats;

}

sub products_in_tree {
  	my $dbh = session::dbh;
	my $cat = shift;

	my $path =  $dbh->selectall_arrayref(q{
	WITH RECURSIVE tree AS (
    	SELECT cc.id as SubTreeRoot,
            cc.id 
            FROM categories cc
	UNION ALL
	    SELECT cst.SubTreeRoot, cc.id
		FROM categories cc
		INNER JOIN tree cst ON cst.id = cc.parent
	)
	select * from tbl_products 
	where category IN ( 
	SELECT cst.id
	FROM tree cst
	WHERE cst.SubTreeRoot = ?
	) 
	AND active ORDER by name

	}, {Slice => {}}, $cat);

}



1;
