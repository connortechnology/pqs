package PQS::model::categories;

use strict;
use warnings;
no warnings qw(uninitialized);

use session;
use Data::Dumper;

sub set_name {
  my ($id, $name) = @_;
  my $dbh = session::dbh;
  $dbh->do(q{update categories set name = ? where id = ?},undef,  $name, $id);
}
sub set_active {
  my ($id, $active) = @_;
  my $dbh = session::dbh;
  $dbh->do(q{update categories set active = ? where id = ?},undef,  $active, $id);
}
sub set_parent {
  my ($id, $parent) = @_;
  my $dbh = session::dbh;
  $dbh->do(q{update categories set parent = ? where id = ?},undef, $parent, $id);
}


sub delete {
  my ($id) = @_;
  my $dbh = session::dbh;
  $dbh->do(q{Delete from categories where id = ? },undef, $id);
}

sub insert {
  my ($id, $name) = @_;
  my $dbh = session::dbh;
  $dbh->do(q{insert into categories (name, parent) values ( ?, ? ) },undef,  $name, $id);
  return $dbh->last_insert_id('',qw(public categories id));
}


sub get {
  my ($id, $showall) = @_;
  my $dbh = session::dbh;

  my $active =  $showall ? '' : ' AND ACTIVE ';
  print STDERR "Get ACTIVE: $active \n";
  my $id = $dbh->selectrow_hashref("select * from categories where id = ? $active ", undef, $id);
}

sub get_children_from_id {
  my ($id, $showall) = @_;
  my $dbh = session::dbh;

  my $active =  $showall ? '' : ' AND ACTIVE ';

  print STDERR "GC ACTIVE: $active \n";
  my $list;
  if ( $id ) {
  	$list = $dbh->selectcol_arrayref("select id from categories where parent = ?  $active  ORDER BY name ", undef, $id);
   } else {
  	$list = $dbh->selectcol_arrayref("select id from categories where parent is NULL $active  ORDER BY name ");
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

  my $all = $dbh->selectall_hashref("select * from categories where active",'id');
  
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
  
  foreach my $cat ( keys %{$cats} ) {
    
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
	my $show_all = shift;

	my $active;
	$active = q{AND active} unless $show_all;

	unless ($cat) {
		return $dbh->selectall_arrayref(q{
			SELECT * from tbl_products WHERE active order by name
		}, {Slice => {}});
	}

	my $path =  $dbh->selectall_arrayref(qq{
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
	$active
	ORDER by name

	}, {Slice => {}}, $cat);

}

sub select_list {
  	my $dbh = session::dbh;

    my $list = $dbh->selectcol_arrayref(q{
        SELECT id, name || '  (' || id || ')'
        FROM categories 
		ORDER by name;
    }, { Columns => [1, 2] });

	
}



1;
