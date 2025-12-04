package PQS::model::categories;

use strict;
use warnings;
no warnings qw(uninitialized);

use session;
use Data::Dumper;
require openprint;
use vars qw( $log $dbh );
*log = \$openprint::log;
*dbh = \$openprint::dbh;

sub set_name {
  my ($id, $name) = @_;
  $dbh->do(q{update categories set name = ? where id = ?},undef,  $name, $id);
}

sub set_description {
  my ($id, $desc) = @_;
  $dbh->do(q{update categories set description = ? where id = ?},undef,  $desc, $id);
}
sub set_header {
  my ($id, $desc) = @_;
  $dbh->do(q{update categories set header = ? where id = ?},undef,  $desc, $id);
}

sub set_footer {
  my ($id, $desc) = @_;
  $dbh->do(q{update categories set footer = ? where id = ?},undef,  $desc, $id);
}
sub set_productinfo {
  my ($id, $desc) = @_;
  $dbh->do(q{update categories set productinfo = ? where id = ?},undef,  $desc, $id);
}

sub set_active {
  my ($id, $active) = @_;
  $dbh->do(q{update categories set active = ? where id = ?},undef,  $active, $id);
}
sub set_parent {
  my ($id, $parent) = @_;
  $dbh->do(q{update categories set parent = ? where id = ?},undef, $parent, $id);
}

sub delete {
  my ($id) = @_;
  $dbh->do(q{Delete from categories where id = ? },undef, $id);
}

sub insert {
  my ($id, $name) = @_;
  $dbh->do(q{insert into categories (name, parent) values ( ?, ? ) },undef,  $name, $id);
  return $dbh->last_insert_id('',qw(public categories id));
}


sub get {
  my ($id, $showall) = @_;

  my $active =  $showall ? '' : ' AND ACTIVE ';
  return $dbh->selectrow_hashref("select * from categories where id = ? $active ", undef, $id);
}

sub get_children_from_id {
  my ($id, $showall) = @_;

  my $active =  $showall ? '' : ' AND ACTIVE ';

  my $list;
  if ( $id ) {
  	$list = $dbh->selectcol_arrayref("select id from categories where parent = ?  $active  ORDER BY name ", undef, $id);
   } else {
  	$list = $dbh->selectcol_arrayref("select id from categories where parent is NULL $active  ORDER BY name ");
  }
  return $list;
}

sub get_parent_from_id {
  my ($id) = @_;
  return $dbh->selectrow_array("select parent from categories where id = ?", undef, $id);
}

sub get_id_from_name {
  my ($str) = @_;
  return $dbh->selectrow_array("select id from categories where name = ?", undef, $str);
}

sub get_name_from_id {
  my ($str) = @_;
  return $dbh->selectrow_array("select name from categories where id = ?", undef, $str);
}

sub get_all {
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
  } keys %{$all};
  
  foreach my $cat ( keys %{$cats} ) {
    my $children = $subcats->{$cats->{$cat}{id}};
    @{$children} = sort { $a->{name} cmp $b->{name} } @{$children} if defined $children;
    $cats->{$cat}{children} = $children;
  }
 
  return $cats;
}

sub products_in_cat {
	my $cat = shift;
	my $show_all = shift;

	my $active = q{AND active} unless $show_all;

	return $dbh->selectall_arrayref(qq{
		SELECT * from tbl_products WHERE category = ?
		$active
		ORDER by id

	}, {Slice => {}}, $cat);
}


sub products_in_tree {
	my $cat = shift;
	my $show_all = shift;

	my $active = q{AND active} unless $show_all;

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
  my $list = $dbh->selectcol_arrayref(q{
    SELECT id, name || '  (' || id || ')'
    FROM categories 
    ORDER by name;
    }, { Columns => [1, 2] });
}

1;
