package eprint::material;
use strict;
use warnings;

use eprint::customer qw(get_discount);
use eprint::equipment;
require openprint;

my %cache_by_id;
my %cache_by_strid;

sub init_cache {
  %cache_by_id = sql::execute($openprint::log, $openprint::dbh, 'SELECT lngindex, strid from tbl_materials');
  @cache_by_strid{values %cache_by_id} = keys %cache_by_id;
}

sub get_price {
  my ($log, $dbh, $variable, $material, $range, $equip) = @_;

  my ($clause, $mi, @args);

  if (!$material) {
    my ( $caller, undef, $line ) = caller;
    print STDERR "Empty material passed to get_price from $caller:$line\n";
    return;
  }

  if ($material =~ /^\d+$/) {

    # Verify the numberic ID
    $mi = %cache_by_id ? $cache_by_id{$material} : scalar $dbh->selectrow_array(q{SELECT lngindex FROM tbl_materials WHERE lngindex = ?}, undef, $material);
  } else {
    # Fetch the numberic ID if they're passed us a string.
    $mi = %cache_by_strid ? $cache_by_strid{$material} : scalar $dbh->selectrow_array(q{SELECT lngindex FROM tbl_materials WHERE strid = ?}, undef, $material);
  } # end if id or string

  if (defined($equip) && $equip) {
    # Fetch the numberic ID if they're passed us a string.
    unless ($equip =~ /^\d+$/) {
      $equip = eprint::equipment::get_index_by_id($log, $dbh, $equip)
        or die "Invalid equipment in material price lookup";
    }

    $clause .= q{ AND (lngequipmentindex = ? OR lngequipmentindex IS NULL) };
    push @args, $equip;
  }

  # If a value is supplied check it's in the range Note: ranges values are
  # neither validated nor constrained so you can get 'interesting' results. 
  if (defined $range && $range ne '' && $range >= 0) {
    $range = int $range;

    $clause .= q{ 
    AND (? >= lngmin OR lngmin IS NULL) 
    AND (? <= lngmax OR lngmax IS NULL)
    };
    push @args, $range, $range;
  }
  my ($price, $discountable) = $dbh->selectrow_array(qq{ 
    SELECT dblprice, (CASE WHEN ysndiscountable = 'Y' THEN 1 ELSE 0 END)
    FROM tbl_material_prices m, tbl_customer c
    WHERE m.lnglistindex     = c.lngpricelist
    AND m.lngmaterialindex = ?
    AND c.lngcustomerid    = ?
    $clause
    ORDER BY lngequipmentindex IS NULL, lngmin
    LIMIT 1
    }, undef, $mi, $variable->{cust_id}, @args);

  # Apply any pricelist or customer discounts if applicable.
  if ($discountable) {
    my $discount = get_discount($dbh, $variable->{cust_id});

    $price *= 1 + ($discount/100) if $discount;
  }

  return $price;
}
	
sub get_name {
	my ($dbh, $id)  = @_;
	return $dbh->selectrow_array(q{
		SELECT strname FROM tbl_materials WHERE strid = ? 
	}, undef, $id);

}

#get the database rows for materials with a certain type id
sub get_materials_by_type {
  my ($dbh, $type) = @_;
  my $materials = $dbh->selectall_hashref("select * from tbl_materials where lngtype = ?", 'lngindex', undef, $type);
  return $materials;
}

1;
