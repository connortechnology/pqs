package PQS::model::pricing;

use strict;
use warnings;
no warnings qw(uninitialized);
use Data::Dumper;

use session;


sub get_list_index {
  my ($id) = @_;
  my $dbh = session::dbh;
  my $index = $dbh->selectrow_array("select id from price_indexes where name = ?", undef, $id);
  die ("Pricing Index NOT FOUND FOR NAME: $id ") unless $index;

  return $index;

}

sub price_array_for_item {
	my $pricelist = shift;
	my $id = shift;
	my $dbh = session::dbh;

	my $data = $dbh->selectall_arrayref(q{
		SELECT *  from pricing_matrix WHERE item = ? AND pricelist = ? ORDER by min nulls first
	}, {Slice => {}}, $id, $pricelist);
	
	return $data;

}
sub sell_prices {
	my $pricelist = shift;
	my $id = shift;
	my $dbh = session::dbh;

	my $data = $dbh->selectall_arrayref(q{
		SELECT distinct min, max, sell  from pricing_matrix WHERE item = ? AND pricelist = ? ORDER by min nulls first
	}, {Slice => {}}, $id, $pricelist);
	
	return $data;

}

sub items {
	my $pricelist = shift;
  	my $dbh = session::dbh;
	my $data = $dbh->selectcol_arrayref(q{
		SELECT distinct(item) from pricing_matrix WHERE pricelist = ?
	}, undef, $pricelist);
	return $data;
}
	


sub get_by_id {
  my ($id) = @_;
  my $dbh = session::dbh;

  my $price = $dbh->selectrow_hashref("select * from pricing_indexes where id = ?", undef, $id);
  $price->{matrix} = $dbh->selectrow_arrayref("select * from pricing_matrix where index = ? order by min", undef, $id);

  return $price;
}

sub get_price {
  my ($index, $item, $qty) = @_;
  print STDERR "HAVE PRICE PARAMS: " , Dumper(@_);
  my $dbh = session::dbh;
  my $price = $dbh->selectrow_array("select id from pricing_matrix where index = ? and item = ?
    and ((min <= ? and max >= ?) or (min <= ? and max is null) or (max >= ? and min is null))",
    undef, $index, $item, $qty, $qty, $qty, $qty );
  return $price->{sell};
}

sub add_price_index {
  my ($name, $min, $max, $units, $pricelist) = @_;
  my $dbh = session::dbh;
  my $sql = "insert into pricing_indexes (name, min, max, units, pricelist) values (?, ?, ?, ?, ?)";
  my $sth = $dbh->prepare($sql);
  $sth->execute($name, $min, $max, $units, $pricelist);
}
sub delete_price {
 my $dbh = session::dbh;
 my $item = shift;
 $dbh->do('delete from pricing_matrix where id = ?', undef, $item);
}

sub delete_item_price {
 my $dbh = session::dbh;
 my $item = shift;
 $dbh->do('delete from pricing_matrix where item = ?', undef, $item);
}

sub clear_item {
 my $dbh = session::dbh;
 my $item = shift;
 my $pricelist = shift;
 $dbh->do('delete from pricing_matrix where item = ? AND pricelist = ?', undef, $item, $pricelist);
}

sub clear_list {
 my $dbh = session::dbh;
 my $index = shift;
 $dbh->do('delete from pricing_matrix where index = ?', undef, $index);
}

sub add_price {
  my ($index, $item, $min, $max, $cost, $sell, $discountable, $pricelist) = @_;
  print STDERR "HAVE PRICING", Dumper(@_);
  my $dbh = session::dbh;
  my $sql = "insert into pricing_matrix (index, item,  min, max, cost, sell, discountable, pricelist) values (?, ?, ?, ?, ?, ?, ?, ?)";
  my $sth = $dbh->prepare($sql);
  $min = undef unless $min > 0;
  $max = undef, unless $max > 0;
  $sth->execute($index, $item, $min, $max, $cost, $sell, $discountable, $pricelist);
}

sub price_item {
    my ( $cid, $index, $item, $range) = @_;
    
    
	my $log = session::log;
	my $dbh = session::dbh;

	my $pricelist = eprint::customer::get_pricelist_id($log, $dbh, $cid);

    my ($clause, @args);


#    print STDERR "HAVE PRICE ITEM PARAMS ", Dumper(@_);
  my $dbh = session::dbh;

die("MISSING QTY: $range ") unless $range;
  
    # If a quantity is supplied check it's in the range Note: ranges are
    # neither validated nor constrained so you can get 'interesting' results. 
    if (defined $range && $range ne '' && $range >= 0) {
        $range = int $range;

        $clause .= q{ 
            AND (? >= min OR min IS NULL) 
            AND (? <= max OR max IS NULL)
        };
        push @args, $range, $range;
    }

    
    my $sql = qq{ 
         SELECT sell, 
                (CASE WHEN discountable = 'Y' THEN 1 ELSE 0 END)
          FROM pricing_matrix
          WHERE index  = ?
	    AND item   = ?
            AND pricelist = ?
            $clause
          ORDER BY min
          LIMIT 1
    };

    my $sth = $dbh->prepare_cached($sql);

    my ($price, $discountable) 
                      = $dbh->selectrow_array($sth, undef, $index, $item, $pricelist, @args);

# print STDERR "HAVE PRICE SQL PRICE: $price --  $index, $item, $pricelist: ", Dumper($sql);

    # Apply the customer's discount if applicable.
    if ($discountable) {
        my $discount 
            = eprint::customer::get_discount($dbh, $cid);

        $price *= 1 + ($discount/100) if $discount;
    }

    return wantarray ? ($price) : $price;
}
1;
