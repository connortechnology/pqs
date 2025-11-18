use strict;
package openprint::pricing;
use Memoize;
use Carp qw( cluck );

require openprint;
require openprint::Pricelist;
require openprint::pricelist;
require openprint::priceset;
require openprint::price;

require openprint::MaterialPrice;
require openprint::Material;
require openprint::Service;

use vars qw( $log $dbh %config );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;

use constant DEBUG => 0;

my %price_cache;

sub clear_cache {
  if (%price_cache) {
    %price_cache = ();
    #Memoize::flush_cache('get_best_prices');
  }
} # end sub clear_cache

sub init_cache {
	$price_cache{$config{db_name}} = {};
	my @Services = openprint::Service->find();
	my @Materials = openprint::Material->find();
  my @Pricelists = openprint::Pricelist->find();
  foreach my $Pricelist ( @Pricelists ) {
		foreach my $S ( openprint::ServicePrice->find( 'period_end is null'=>1, 
        #(($openprint::Pricelist and $openprint::Pricelist->id()) ? (pricelist_id=>$openprint::Pricelist->id()):()),
        pricelist_id=>$Pricelist->id(),
        order=>$openprint::ServicePrice::fields{min}.' NULLS FIRST, '.$openprint::ServicePrice::fields{max}.' NULLS FIRST') ) {
			if ( ! $price_cache{$config{db_name}}{$$Pricelist{id}}{'openprint::Service'}{$S->Service()->id()} ) {
				$price_cache{$config{db_name}}{$$Pricelist{id}}{'openprint::Service'}{$S->Service()->id()} = [];
			} # end if
			push @{$price_cache{$config{db_name}}{$$Pricelist{id}}{'openprint::Service'}{$S->Service()->id()}}, $S;
		} # end foreach ServicePrice
		foreach my $S ( openprint::MaterialPrice->find(
        pricelist_id=>$Pricelist->id(),
        #(($openprint::Pricelist and $openprint::Pricelist->id()) ? (pricelist_id=>$openprint::Pricelist->id()):()),
        order=>$openprint::MaterialPrice::fields{min}.' NULLS FIRST, '.$openprint::MaterialPrice::fields{max}.' NULLS FIRST') ) {
#'period_end is null'=>0, 
			if ( ! $price_cache{$config{db_name}}{$$Pricelist{id}}{'openprint::Material'}{$S->Material()->id()} ) {
				$price_cache{$config{db_name}}{$$Pricelist{id}}{'openprint::Material'}{$S->Material()->id()} = [];
			} # end if
			push @{$price_cache{$config{db_name}}{$$Pricelist{id}}{'openprint::Material'}{$S->Material()->id()}}, $S;
		} # end foreach ServicePrice
  } # end foreach Pricelist
	foreach my $Service ( @Services ) {
    my $cache = 
		$Service->Prices( [ map { $price_cache{$config{db_name}}{$$_{id}}{'openprint::Service'}{$$Service{id}} ? @{$price_cache{$config{db_name}}{$$_{id}}{'openprint::Service'}{$$Service{id}}} : () } @Pricelists ] );
	} # end foreach Service
	foreach my $Material ( @Materials ) {
		$Material->Prices( [ map { $price_cache{$config{db_name}}{$$_{id}}{'openprint::Material'}{$$Material{id}} ? @{$price_cache{$config{db_name}}{$$_{id}}{'openprint::Material'}{$$Material{id}}} : () } @Pricelists ] );
	} # end foreach Material
  $openprint::log->debug("Done picing::init_cahce");
}

sub get_pricelist_id {

	if ( $openprint::session{Pricelist_id} ) {
		# Validity of session variables is the job of openprint.pm, so it is done once per hit
		return $openprint::session{Pricelist_id};
	} # end if

	my $list_id;

	if ( $openprint::session{company_id} > 0 ) {
		my $Company = new openprint::Company( $openprint::session{company_id} );
		$list_id = $Company->pricelist_id();
		if ( (! $list_id ) and $Company->country() ) {
			$list_id = $openprint::config{'Default'.$Company->country().'Pricelist'};
		} # end if
	} # end if
	if ( ( ! $list_id ) and $openprint::session{Country} ) {
		$list_id = $openprint::config{'Default'.$openprint::session{Country}.'Pricelist'};
	}  # end if
	$list_id = $openprint::config{DefaultPricelist} if ! $list_id;
	if ( ! $list_id ) {
		$openprint::log->debug("No pricelist to be had! Country: $openprint::session{Country}" );
	} # end if
	
	$openprint::session{Pricelist_id} = $list_id;
	return $list_id;
} # end sub get_pricelist_id

#memoize('find_price');
# returns an index into the passed array of the price entry that fits the specified quantity.
# if $qty = '' then it will return the last entry
# if the price array is empty, it will return -4, which isn't good.
sub find_price {
	my $qty = shift;
	for ( my $index = 0; $index < @_; $index += 1 ) {
 		if ( $qty ne '' ) {
			if ( $qty <= $_[$index]->{max} or $_[$index]->{max} eq '' ) {
				return $index;
			} # end if
		} else {
# Do this the ugly way as an optimisation when we don't care about the quantity and there are lots of options
			return $index;
		} # end if
	} # end for
	
	return @_ - 1;
} # end sub find_price

sub get_increment {
	my $number = shift;
	$number =~ /\d*.(\d*)/;
	return 1 / ( 10 ** (length $1) );
} # end sub get_imcrement

# takes two prices, and returns the results of a merge between them.
# So the result could be one price, or two prices.
# $price1 and $price2 are expected to be in sorted order.
sub merge_prices {
	my ( $price1, $price2 );

	if ( $_[0]{Price} > $_[1]{Price} ) {
		( $price2, $price1 ) = @_;
	} elsif ( $price1->{equipment_index} != $price2->{equipment_index} ) {
		return @_;
	} else {
		( $price1, $price2 ) = @_;
	} # end if
	my @prices = ( $price1 );

	# now Price1 has the lower price.
	if ( $price1->{min} ne '' and ( $price2->{min} < $price1->{min} or $price2->{min} eq '' ) ) {
$log->debug("Filling in price mins $$price2{min} < $$price1{min}") if DEBUG;
		# tack on a price in front
		my $newprice = openprint::price->new( $openprint::log, '' );
		$newprice->copy( $price2 );
		my $increment = get_increment( $price1->{min} );
		$newprice->setMax( $price2->{max} < $price1->{min} - $increment ? $price2->{max} : $price1->{min} - $increment );
		unshift @prices, $newprice;
	} # end if

	if ( $price1->{max} ne '' and ( $price2->{max} > $price1->{max} or $price2->{max} eq '' ) ) {
$log->debug("Filling in price maxs $$price2{max} < $$price1{max}") if DEBUG;
		my $newprice = openprint::price->new( $openprint::log, '' );
		$newprice->copy( $price2 );
		my $increment = get_increment( $price1->{max} );
		$newprice->setMin( $price2->{min} > $price1->{max} + $increment ? $price2->{min} : $price1->{max} + $increment );
		push @prices, $newprice;
	} # end if
	return @prices;
} # end sub merge_prices

# builds an array of prices with a linear quantity range.
# the prices for each quantity range are the lowest possible.
sub build_lowest_price_list {
	my @returned = (shift @_);

	# basically, we process each entry in the huge list of prices, and fit them into a returned list
	while ( @_ ) {
		# pull and entry off
		my $price = shift @_;
		# Get the appropriate price entry in the returned list.
		my $price_index = find_price( $price->{max}, @returned );
		# so all prices higher than price_index are for quantities higher than the current

		splice @returned, $price_index, 1, merge_prices( $returned[$price_index], $price );
		# while min of our returned entry is less than the requested min, or requested min is nothing,
		# basically, this says if our returned entry is appropriate.	You see, we travel upward through 
		# our returned list trying to find the right place to put our new entry.
		while ( ( $price_index > 0 ) and ( $returned[$price_index]->{min} <= $price->{min} or $price->{min} eq '' ) ) {
			$price_index -= 1;
			splice( @returned, $price_index, 2, merge_prices( $returned[$price_index], $returned[$price_index+1] ) );
		} # end while
	} # end while

	return @returned;
} # end sub build_lowest_price_list

sub split_by_equipment {
	my %lists;

	foreach my $price ( @_ ) {
		push @{$lists{$price->{equipment_index}}}, $price;
	} # end foreach
	return %lists;
} # end sub split_by_equipment

#Memoize::memoize('get_best_prices');
sub get_best_prices {
	my ( $cust_id, $prod_index, $list_id, $Object, $equipment_id, $qty, $period ) = @_;

	if ( ! $list_id ) {
		my ( $caller, undef, $line ) = caller;
		#$log->error("Not specifying pricelist to get_best_prices is deprecated from $caller:$line");

		Carp::cluck("Not specifying pricelist to get_best_prices is deprecated from $caller:$line");
# figure out which price list we select from, because the caller didn't specify.
		$list_id = get_pricelist_id();
	} # end if

	my @pricing = ();
	my $price_type = ref $Object;
	if ($price_type) {
    $log->debug('Using new style price caching' ) if DEBUG;
    if ($price_cache{$config{db_name}}{$list_id}{$price_type}{$$Object{id}}) {
      @pricing = @{$price_cache{$config{db_name}}{$list_id}{$price_type}{$$Object{id}}};
      if (DEBUG) {
        $log->debug("Have prices in cache for $price_type $$Object{id} #".@pricing);
        foreach my $p ( @pricing ) {
          $log->debug($p->to_string());
        }
      }
    } else {
      @pricing = $Object->Prices();
    }
    if ($equipment_id) {
      my $e = new openprint::Equipment($equipment_id);
      @pricing = map { ((!$$_{equipment_id}) or ($$_{equipment_id} == $equipment_id)) ? $_ : () } @pricing;
      $openprint::log->debug("Filtering by equipment id $equipment_id $$e{name} got ".@pricing) if DEBUG;
    } else {
      $openprint::log->debug("Not Filtering by equipment id $equipment_id") if DEBUG;
    }
    foreach my $p ( @pricing ) {
      $$p{Price} = $$p{price};
      $$p{Cost} = $$p{cost};
    }
	} else {
$log->warn("Request for old style price for $Object");
#if ( $Object eq 'openprint::service_priceset' ) {
#my $Service = new openprint::Service( $prod_index );
#$log->warn("Loading price for $Object $prod_index $equipment $qty " . $Service->to_string() );
#}
		my $priceGroup = $Object->new( $log, $dbh, $list_id, $prod_index, $equipment_id, $qty, $period );
		$priceGroup->load();	
		push @pricing, @{$priceGroup->{prices}};
	}
if ( DEBUG ) {
foreach my $p ( @pricing ) {
$log->debug("Price $$p{id} service_id:$$p{service_id} cost: $$p{cost}/$$p{Cost} price $$p{price}/$$p{Price} interpolate:$$p{interpolate}; $$p{equipment_id}=?$equipment_id");
}
}

	if ( $openprint::config{ApplyMarkup} ) {
#$openprint::log->debug("Apply Markup: $openprint::config{ApplyMarkup}");	
		my $pricingpercent = $openprint::config{ApplyMarkup};
		#$pricingpercent =~ s/[^\d\.\-]//g;
		$pricingpercent /= 100;
		$pricingpercent += 1;
		for ( my $index = 0; $index < @pricing; $index += 1 ) {
# the if here is to preserve empty pricing.	if pricei s empty, we display call, instead of 0.00.
			if ( $pricing[$index]->{Price} ne '' ) {
				$pricing[$index]->{Price} *= $pricingpercent;
			} # end if
		} # end for
	} # end if

# Now if we are a customer, then we have more to do, including special pricing, adding discounts, etc. 
	if ( $cust_id != 0 ) {
		my $Company = new openprint::Company( $cust_id );
		my $CSR = $Company->CSR();

		my $pricingpercent = $$Company{discount};
		if ( $pricingpercent or $$Company{csr_commission} or $$Company{credit_card_fee} or $$CSR{commission} ) {
			$pricingpercent = 1 - ($pricingpercent/100);
			my $csr_commission = 1+($$Company{csr_commission} == undef ? $$CSR{commission} : $$Company{csr_commission} ) /100;
			my $credit_card_fee = 1+$$Company{credit_card_fee}/100;

			for ( my $index = 0; $index < @pricing; $index += 1 ) {
# the if here is to preserve empty pricing.	if price is empty, we display call, instead of 0.00.
				if ( $pricing[$index]->{Price} ne '' ) {
					if ( $pricing[$index]->{Discountable} ne 'N' ) {
						$pricing[$index]->{Price} *= $pricingpercent;
					} # end if
					$pricing[$index]->{Price} *= $csr_commission;
					$pricing[$index]->{Price} *= $credit_card_fee;
				} # end if has a nunmeric price
			} # end for each price
		} # end if
	} # end if

	my @prices;
	if ( $equipment_id ) {
		@prices = build_lowest_price_list( @pricing );
	} else {
		my %lists = split_by_equipment( @pricing );
		foreach my $key ( keys %lists ) {
			push @prices, build_lowest_price_list( @{$lists{$key}} );
		} # end foreach
	} # end if

	return \@prices;
} # end sub get_best_prices

sub get_Price {
	my ( $Object, $Pricelist, $qty, $Equipment, $period ) = @_;

	my $type = ref $Object;
	my @Prices;
	my $Price;

	# If we specify a period, then forget about the caching.  Caching will only do current prices.
	if ( $period ) {
	}
	if ( $price_cache{$config{db_name}}{$$Pricelist{id}}{$type}{$$Object{id}} ) {
		@Prices = @{$price_cache{$config{db_name}}{$$Pricelist{id}}{$type}{$$Object{id}}};
	} else {
		$price_cache{$config{db_name}}{$$Pricelist{id}}{$type}{$$Object{id}} = [$Object->Prices()];
		@Prices = @{$price_cache{$config{db_name}}{$$Pricelist{id}}{$type}{$$Object{id}}};
		$log->error("Prices not cached for $config{db_name} pricelist: $$Pricelist{id} type $type $$Object{name}");
	}
	if ( @Prices ) {

		my @Equipment_Prices;
		if ( $Equipment ) {
			@Equipment_Prices = map { $$_{equipment_id} == $$Equipment{id} ? $_ : () } @Prices;
			@Equipment_Prices = map { defined $$_{equipment_id} ? () : $_ } @Prices if ! @Equipment_Prices;
			@Prices = @Equipment_Prices;
		} # end if

		if ( ! defined $qty or $qty eq '' ) {
			$Price = $Prices[0];
		} else {	
			for( my $i = 0; $i < @Prices; $i += 1 ) {
				my $P = $Prices[$i];
				#$log->debug("Need $qty, equipment: $$P{equipment_id} $$Object{name} min: $$P{min} max: $$P{max} ");
				if ( 
						( ( ! defined $P->{min} ) or $P->{min} <= $qty ) and 
						( ( ! defined $P->{max} ) or $P->{max} >= $qty )
				   ) {
					$Price = $P->clone();
					# For interpolation
					#$$Price{Previous} = $Prices[$i-1] if $i > 0;
					$$Price{Next} = $Prices[$i+1] if $i < @Prices -1;
					last;
				} # end if
			} # end foreach
		} # end if qty
	} # end if

	if ( $Price and $$Price{price} ) {

		if ( $openprint::config{ApplyMarkup} ) {
#$openprint::log->debug("Apply Markup: $openprint::config{ApplyMarkup}"); 
			my $pricingpercent = $openprint::config{ApplyMarkup};
			#$pricingpercent =~ s/[^\d\.\-]//g;
			$pricingpercent /= 100;
			$pricingpercent += 1;
# the if here is to preserve empty pricing. if pricei s empty, we display call, instead of 0.00.
			$Price->{price} *= $pricingpercent;
		} # end if

		if ( $openprint::session{company_id} != 0 ) {
			my $CSR = $openprint::Company->CSR();
			my $pricingpercent = $$openprint::Company{discount};
			if ( $pricingpercent or $$openprint::Company{credit_card_fee} or $$openprint::Company{csr_commission} or $$CSR{commission} ) {

				$pricingpercent = 1 - ($pricingpercent/100);
				my $credit_card_fee = 1 + $$openprint::Company{credit_card_fee}/100;
				my $csr_commission = 1+($$openprint::Company{csr_commission} == undef ? $$CSR{commission} : $$openprint::Company{csr_commission} ) /100;
				if ( $Price->{discountable} ne 'N' ) {
					$Price->{price} *= $pricingpercent;
				} # end if
				$$Price{price} *= $csr_commission;
				$$Price{price} *= $credit_card_fee;
			} # end if
		} # end if

		if ( $$Price{interpolate} ) {
			if ( $$Price{max} and $$Price{Next} ) {
				my $xa = $$Price{min};
				my $xb = $$Price{Next}{min};
				my $ya = $$Price{price};
				my $yb = $$Price{Next}{price};
				$Price->{price} = $ya + ($yb - $ya)*( ($qty - $xa ) / ( $xb - $xa ) );
			}
		}
	} # end if
	return $Price;
}

#memoize('get_best_price_object');
sub get_best_price {
	my ( $cust_id, $prod_index, $list_id, $pricesetclass, $qty, $equipment, $period ) = @_;

	my %price = get_best_price_object( $cust_id, $prod_index, $list_id, $pricesetclass, $qty, $equipment, $period );
	return $price{Price};
} # end sub get_best_price 

sub get_best_price_object {
	my ( $cust_id, $prod_index, $list_id, $pricesetclass, $qty, $equipment, $period ) = @_;
	my $prices = get_best_prices( $cust_id, $prod_index, $list_id, $pricesetclass, $equipment, $qty, $period );
	if ( DEBUG ) {
		$openprint::log->debug("Prices in get_best_price_object for qty $qty : " . @$prices);
		foreach my $price ( @$prices ) {
			$openprint::log->debug("service: $$price{service_id} min: $$price{min} max: $$price{max} range_units:$$price{range_units} price:$$price{Price} units: $$price{units} interpolate: $$price{interpolate}");
		} # end foreach
	}

	for ( my $i = 0; $i < @$prices; $i += 1 ) {
		my $price = $$prices[$i];
		if ( $price and ( 
					( (!defined $qty) or $qty eq '' ) or
					( 
					 ( ( $price->{min} eq '' or ! defined $price->{min} ) or 1*$price->{min} <= $qty ) and 
					 ( ( $price->{max} eq '' or ! defined $price->{max} ) or 1*$price->{max} >= $qty )
					)
					) ) {
			$openprint::log->debug("matched service: $$price{service_id} min: $$price{min} max: $$price{max} range_units:$$price{range_units} price:$$price{price}/$$price{Price} units: $$price{units} interpolate: $$price{interpolate} for $qty") if DEBUG;
      $$price{price} = $$price{Price} if ! $$price{price};
			if ( $$price{mode} eq 'Interpolate' ) {
$log->error("Using interpolate $$price{max}");
				if ( $$price{max} and $i <= ( @$prices - 1 ) ) {
					$$price{Previous} = $$prices[$i-1] if $i;
					$$price{Next} = $$prices[$i+1];
					my $xa = $$price{min};
					my $xb = $$price{Next}{min};
					my $ya = $$price{Price};
					my $yb = $$price{Next}{Price};

					$$price{price} = $price->{Price} = $ya + ($yb - $ya)*( ($qty - $xa ) / ( $xb - $xa ) );
$log->error("Using interpolate $price->{Price} = $ya + ($yb - $ya)*( ($qty - $xa ) / ( $xb - $xa ) );");
				}
			} elsif ( $$price{mode} eq 'Stepped' ) {
$log->error("Using Stepped $$price{max}");
				# Store these for later processing
				$$price{index} = $i;
				$$price{prices} = $prices;
			}
			return %$price;
    } else {
			$openprint::log->debug("Not matched service: $$price{service_id} min: $$price{min} max: $$price{max} range_units:$$price{range_units} price:$$price{Price} units: $$price{units} interpolate: $$price{interpolate} for $qty");
		} # end if
	} # end foreach
	return;
} # end sub get_best_price 

sub adjust_price {
	my ( $Price, $options ) = @_;
	if ( $openprint::config{ApplyMarkup} ) {
#$openprint::log->debug("Apply Markup: $openprint::config{ApplyMarkup}");	
		my $pricingpercent = $openprint::config{ApplyMarkup};
		$pricingpercent =~ s/[^\d\.\-]//g;
		$pricingpercent /= 100;
# the if here is to preserve empty pricing.	if pricei s empty, we display call, instead of 0.00.
		if ( $$Price{Price} ne '' ) {
			$$Price{Price} *= ( 1 + $pricingpercent );
		} # end if
	} # end if
	return openprint::Currency::convert( $Price );
} # end sub adjust_price

sub get_stepped {
	my ( $price, $qty ) = @_;
	my $total = 0;
	my $remaining_qty = $qty;
	for ( my $i = 0; $i < $$price{index}; $i += 1 ) {
		my $partial_qty = $$price{prices}[$i]{max} - $$price{prices}[$i]{min};

		$total += $partial_qty * $$price{prices}[$i]{Price};
		$remaining_qty -= $partial_qty;
	}
	$total += $remaining_qty * $$price{Price};
	$$price{total} = $total;
}

1;
__END__
