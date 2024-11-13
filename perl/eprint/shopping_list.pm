package eprint::shopping_list;
use strict;

use Apache2::Const qw(:common);
use Apache2::RequestRec ();
use Data::Dumper;
require eprint::products;

#List all shopping lists
sub list {
  my ($r, $dbh, $variable) = @_;
  my $delete = $r->param('delete');
  destroy($r,$dbh,$variable,$delete) if ($delete);
  my $new = $r->param('list_name');
  create($r, $dbh, $variable, $new) if ($new);
  $variable->{shopping_lists} = $dbh->selectall_arrayref("select * from tbl_shopping_lists", {Slice => {}});
}

#Get details on a single shopping list
sub get {
  my ($r, $dbh, $variable, $id) = @_;
  modify($r, $dbh, $variable, $id) if $r->method eq 'POST';
  $id = $r->param('id') unless $id;
  return SERVER_ERROR unless $id;
  my $delete = $r->param('delete');
  remove($r,$dbh,$variable,$delete) if ($delete);
  $variable->{shopping_list} = $dbh->selectrow_hashref("select * from tbl_shopping_lists where id = ?", {}, $id);
  $variable->{contents} = $dbh->selectall_arrayref("select c.id as item, p.id as id, p.name as name, p.price as price, c.quantity as quantity
    from tbl_shopping_lists_contents as c left join tbl_products as p on c.product_id = p.id
    where c.shopping_list_id = ?", { Slice => {} }, $id);
    $variable->{shopping_list}->{cost} = 0;
  foreach (keys %{$variable->{contents}}) {
    $variable->{contents}[$_]->{cost} = $variable->{contents}[$_]->{quantity} * $variable->{contents}[$_]->{price};
    $variable->{shopping_list}->{cost} += $variable->{contents}[$_]->{cost};
  }
  eprint::products::list($r, $dbh, $variable);
}

#modify a shopping list
sub modify {
  my ($r, $dbh, $variable, $id) = @_;
  $id = $r->param('id') unless $id;
  return SERVER_ERROR unless $id;
  my $param = $r->param;
  if ($param->{'new_product'}) {
    add($r, $dbh, $variable, $id, $param->{'new_product'}, $param->{'new_qty'});
  }
  my $sth = $dbh->prepare("update tbl_shopping_lists_contents set quantity = ? where id = ?");
  foreach my $key (keys(%{$param})) {
    next unless ($key =~ /qty\[([0-9]+)\]/);
    $sth->execute($param->{$key}, $1);
  }
}

#delete a shopping list
sub destroy {
  my ($r, $dbh, $variable, $id) = @_;
  $id = $r->param('id') unless $id;
  return SERVER_ERROR unless $id;
  my $sth = $dbh->prepare("delete from tbl_shopping_lists_contents where shopping_list_id = ?");
  $sth->execute($id);
  my $sth = $dbh->prepare("delete from tbl_shopping_lists where id = ?");
  $sth->execute($id);
}

#remove a product from a shopping list
sub remove {
  my ($r, $dbh, $variable, $id) = @_;
  $id = $r->param('id') unless $id;
  return SERVER_ERROR unless $id;
  my $sth = $dbh->prepare("delete from tbl_shopping_lists_contents where id = ?");
  $sth->execute($id);
}

#create a shopping list
sub create {
  my ($r, $dbh, $variable, $name) = @_;
  $name = $r->param('name') unless ($name);
  return SERVER_ERROR unless $name;
  my $sth = $dbh->prepare("insert into tbl_shopping_lists (name) values (?)");
  $sth->execute($name);
}

#add a product to a shopping list
sub add {
  my ($r, $dbh, $variable, $id, $product, $qty) = @_;
  $id = $r->param('id') unless ($id);
  $product = $r->param('product') unless ($product);
  $qty = $r->param('qty') unless ($qty);
  return SERVER_ERROR unless ($id && $product && $qty);
  my $sth = $dbh->prepare("insert into tbl_shopping_lists_contents (shopping_list_id, product_id, quantity) values (?, ?, ?)");
  $sth->execute($id, $product, $qty);
}

1;
