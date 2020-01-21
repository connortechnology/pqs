package eprint::paper;
use strict;
use warnings;

use Readonly;
use eprint::project qw( get_press_type get_lf_jobsize );
use eprint::service qw( get_service_full_price );
use eprint::customer qw(get_discount);
use POSIX qw(floor);
use sql qw(:common);
use jsrs;



use Data::Dumper;
# Given a set of constraints, returns all distinct values of the substrate
# attributes that were not constained (open options). The returned structure
# is a JSON serialised hash keyed to the attribute, each attribute having a
# list of [label, value] pairs.
sub substrate_lookup : JSRS {
    my ($r, $log, $dbh, $variable, $pid, $sid, $template, $type, $press, @attrs) = @_;

#print STDERR "GO SUB LOOKUP START PID: $pid \n", Dumper(@_);
	$variable->{is_cover} = $attrs[4];

    my %attribute;
    @attribute{ qw(name finish colour weight) } 
        = map { defined $_ && $_ ne '' ? $_ : undef } @attrs;


	my $prod;

	if ( $pid ) {
		# For regular projects check to see if we are flagged
		# as a product.
 		$prod = $dbh->selectrow_array(q{
			SELECT prod_id FROM tbl_projects WHERE lngprojectindex = ?
		}, undef, $pid) 
	} else {
		# From our hybrid product page sid contains product
		# item number.
		$prod = $sid;
	}


print STDERR "IS PROD: $prod \n";

print STDERR "****** IS PROD: $prod PRODUCT Specific Reccomendataions have been disabled ********** \n";

#	my $query = $prod 
#	   ? substrate_attributes_prod($r, $log, $dbh, $variable, $prod, %attribute )
#	   : substrate_attributes(	   $r, $log, $dbh, $variable, $pid, $sid, 
#											 $template, $type, $press, %attribute );


	my $query = substrate_attributes(	   $r, $log, $dbh, $variable, $pid, $sid, 
											 $template, $type, $press, %attribute );


    # If all the known substrate attributes are defined, check that the
    # substrate exists (pre-existing projects, template changes, etc.) If it
    # doesn't we'll reset the substrate selection.
    if (   keys %attribute == grep defined, values %attribute
        && ! scalar @{ $query->('name') } ) 
    {
        $attribute{$_} = undef for keys %attribute 
    }

    # For each undefined attribute get a list of possible values (constrained
    # by the defined attributes).
    my %results;

    ATTRIBUTE: 
    while (my ($attr, $value) = each %attribute) {
        next if defined $value;

        # Get the list of valid [label, value] option pairs. If none exist
        # stop the lookups as we have a problem.
        my $options = $query->($attr);

        last ATTRIBUTE unless @$options;

        $results{$attr} = $options;
    }

    # If we have more questions than answers..
    if (keys %results < grep {! defined $_} values %attribute) {

        # If we have an unconstrained search and we can't find anything, no
        # substrates exist for the project type/press type/template/etc..
        return {} if ! grep defined, values %attribute;

        # Otherwise we'll remove all substrate constraints and try again
        # (generally will only occur during template changes when only a few
        # attributes were selected).
        return substrate_lookup($r, $log, $dbh, $variable, $pid, 
            $template, $type
        );
    }
#use Data::Dumper;
#print STDERR "STOCK RESULTS" , Dumper(\%results);

    return \%results;
}
sub substrate_attributes_prod {
    my ($r,  $log, $dbh,  $variable, $item, %attr) = @_;

#print STDERR "HAVE ATTR ", Dumper(%attr);
    # Grrr...
    my $is_roll;
    if (defined $attr{name}) {
        $is_roll = $attr{name} =~ /\(roll\)$/;
        $attr{name} =~ s/\s\((sheet|roll)\)$//;
    }

	my $table = $variable->{is_cover} ? 'item_cover_paper' : 'item_paper';

    my $sql = qq{ 
        FROM tbl_paper t LEFT JOIN paper_specs s USING (lngindex)
        WHERE lngindex IN 
			( SELECT paper FROM product.$table WHERE item = ?)
    };


    # All defined (and non-empty/zero) attributes other than the currently
    # selected one become part of the WHERE clause.
    my $clause = join " AND ", 
        map  { "t.str$_ = " . $dbh->quote($attr{$_}) . "\n" }
        grep { defined $attr{$_}                            }
             keys %attr;

    $sql .= " AND $clause \n" if $clause;

#print STDERR "HAVE SQL: $sql \n";

    # We return a closure over the query. The function takes a field name
    # and returns an array of (label, value) pairs.
    return sub { 
        my ($name) = @_;
        my $query  = "SELECT DISTINCT t.str$name " . $sql;

		#Now we will allow paper selection from both
		#Rolls & sheets at the same time,so we are going
		#to union the two tables together.
		my $union = $query;
		$union =~ s/tbl_paper/tbl_paper_roll/;
		$query .= " \n UNION \n " . $union . "ORDER BY 1";
		
        my $paper  = $dbh->selectcol_arrayref($query, {}, $item, $item );


        # Weights get a special sort ordering. For now we're doing that
        # ordering in perl instead of in the DB.
        return ($name eq 'weight') ? by_weight($paper) : $paper;
    };
}

# Creates a callback query based on the constraints given to the main
# function. The callback can be used to look up the specified attribute.
sub substrate_attributes {
    my ($r,  $log, $dbh,  $variable, $pid, $sid, 
        $template, $type, $press, %attr) = @_;

    # Grrr...
    my $is_roll;
    if (defined $attr{name}) {
        $is_roll = $attr{name} =~ /\(roll\)$/;
        $attr{name} =~ s/\s\((sheet|roll)\)$//;
    }

    my $sql = qq{ 
        FROM tbl_paper t LEFT JOIN paper_specs s USING (lngindex),
        tbl_paper_recommendations r, tbl_projects p
        WHERE t.lngindex        = r.lngpaperindex
          AND p.lngprojecttype  = r.lngprojecttypeindex
          AND ?				    = r.lngpresstype
          AND p.lngprojectindex = ? 
    };

    # Large format stocks 
     $sql .= " AND s.strname = 'ysnoutdoor' AND s.strvalue = 'Y' "
        if $type eq 'Outdoor';
    
    # If the user is a normal customer, hide any stocks flagged as such.
    $sql .= " AND r.ysnvisible \n" 
        if $variable->{user_type} eq 'C';

    # If we've overridden the press, disallow any stocks it won't process.
    if ($press) {
        $press = $dbh->quote($press);
        $sql .= qq{ AND r.lngpaperindex NOT IN ( 
                        SELECT paper 
                        FROM equipment_paper_exclusion 
                        WHERE equipment = $press
                          AND paper = t.lngindex )} ;
    }

    # Check to see if the template definition exists in the database, if
    # it does we have to constrain our search. TODO templates are handled
    # poorly, they are too overloaded with different meanings per project
    # type.
    if ($template) {
        my $has_template = $dbh->prepare_cached(qq{
            SELECT true FROM tbl_paper WHERE strtemplate = ?
			UNION
            SELECT true FROM tbl_paper_roll WHERE strtemplate = ? LIMIT 1
        });

        $sql .= " AND t.strtemplate = " . $dbh->quote($template) . "\n" 
            if $dbh->selectrow_array($has_template, {}, $template, $template);
    }

    # All defined (and non-empty/zero) attributes other than the currently
    # selected one become part of the WHERE clause.
    my $clause = join " AND ", 
        map  { "t.str$_ = " . $dbh->quote($attr{$_}) . "\n" }
        grep { defined $attr{$_}                            }
             keys %attr;

    $sql .= " AND $clause \n" if $clause;


    my $press_type = get_press_type($log, $dbh, $pid, $sid);

	my $equip_type_id = $dbh->selectrow_array(q{
		SELECT lngindex FROM tbl_equipment_type
		WHERE strid = ?
	}, undef, $press_type);

    # We return a closure over the query. The function takes a field name
    # and returns an array of (label, value) pairs.
    return sub { 
        my ($name) = @_;
        my $query  = "SELECT DISTINCT t.str$name " . $sql;

		#Now we will allow paper selection from both
		#Rolls & sheets at the same time,so we are going
		#to union the two tables together.
		my $union = $query;
		$union =~ s/tbl_paper/tbl_paper_roll/;
		$query .= " \n UNION \n " . $union . "ORDER BY 1";

        my $paper  = $dbh->selectcol_arrayref($query, {},
										$equip_type_id, $pid, 
										$equip_type_id, $pid);


        # Weights get a special sort ordering. For now we're doing that
        # ordering in perl instead of in the DB.
        return ($name eq 'weight') ? by_weight($paper) : $paper;
    };
}

# TODO Orcish maneuver instead of Swartzian transform? Probably faster.
sub by_weight {
    my ($paper) = @_;

    no warnings qw(uninitialized); # Because not all items follow the pattern

    # Split into numeric and text component ie. [45, 'lbs'] and sort by text
    # (unit) and number (weight).
    my @p = map  { $_->[0] }
            sort { $a->[2] cmp $b->[2] || $a->[1] <=> $b->[1] }
            map  { [ $_, /^(\d+)(.*)$/ ] }
                 @$paper;

    return \@p;
}


# Given the name, finish, colour, and weight of a substrate return it's
# details as a string.
sub substrate_details : JSRS {
    my ($r, $log, $dbh, $variable, @attrs) = @_;

    return '' if @attrs != 4;

    # TODO Sheet/roll aware.

    my ($str, $ub)  = $dbh->selectrow_array(q{
        SELECT coalesce(strdetails, ''),
			   underbase
        FROM tbl_paper
        WHERE strname   = ?
          AND strfinish = ?
          AND strcolour = ?
          AND strweight = ?
        LIMIT 1
    }, undef, @attrs);

    return { details   => $str,
			 underbase => $ub   };


	
}



# A subroutine that verifies a stock can be used for large format (ie is
# sheet, or is roll and has square foot pricing)
sub can_largeformat {
    my ($log, $dbh, $variable, $paperindex) = @_;

    my $list_id = eprint::pricing::get_pricelist_id(
        $log, $dbh, $variable->{cust_id}
    );

    my ($is_sheet) = $dbh->selectrow_array(q{
        SELECT lngindex FROM tbl_paper WHERE lngindex = ?
    }, undef, $paperindex);

    return 1 if $is_sheet;

    my ($has_sqft_pricing) = $dbh->selectrow_array(q{
        SELECT lngpaperindex
        FROM tbl_paper_prices
        WHERE lngpaperindex = ?
          AND strunits = 'square foot'
          AND lnglistindex = ?
    }, undef, $paperindex, $list_id);

    return 1 if $has_sqft_pricing;

    return 0;
}




sub get_lf_price {
    my ($log, $dbh, $variable, $imp, $sheet_qty) = @_;

    my $price = price($dbh,
                      $variable->{cust_id},
                      $imp->getPaper->{index},
                      get_lf_jobsize($imp) * $sheet_qty / 144 
    );

    return () unless $price && $price->{units} eq 'square foot';

    my $names = {
        action    => 'Stitching',
        service   => 'Stitching',
        makeready => 'StitchingMakeReady',
        mincharge => 'StitchingMinCharge',
    };

    # This is very rudimentary -- it assumes the stitching that has the
    # lowest price available in the db is always the chepeast -- its very
    # possible that it is not.
    my $material = scalar $dbh->selectrow_array(q{
        SELECT lngmaterialindex
        FROM tbl_material_prices
        WHERE lngmaterialindex IN ( SELECT lngindex
                                    FROM tbl_materials
                                    WHERE lngtype = 16 )
        ORDER BY dblprice
        LIMIT 1
    });

    $price->{stitch_price} = get_service_full_price(
        $log, $dbh, $variable, $names, $imp->getStitchSize, $material
    );

    return $price;
}


# Get and adjust the price (try ordering in bulk if it's cheaper, determine
# roll length needed if applicable, etc.). At least it looks as if it does
# some of that stuff.
sub get_price {
    my ($log, $dbh, $variable, $paper, $press, $qty) = @_;

    my $price = price($dbh, $variable->{cust_id}, $paper->{index}, $qty);

    # If we've cut down the sheet we want to use the mweight of the original
    # sheet as that's what we're buying. NOTE: Only applies to sheet stock.
    my $mweight = $paper->{mweight} 
                * ($paper->{width_factor}  || 1)
                * ($paper->{height_factor} || 1);


    # If we are using a roll stock, we need to price a quantity of rolls.
    if ($paper->{type} eq 'roll') { 
        # pass in the quantity of sheets and retreive the quantity of rolls
        # (rounded for purchase unit)

        # we should not be rounding this off - the function itself rounds
        # appropriately.  if we need it rounded for display purposes, that
        # should be done elsewhere.
        $qty = convert_sheets_into_rolls($log,$dbh,$qty,$$paper{'index'}); 

        # now that we know how many rolls we're buying we must convert this
        # into pounds of paper to buy. since we'll now be pricing all roll
        # paper by the pound, this is acceptable behaviour
        $qty = convert_rolls_into_pounds($log,$dbh,$qty,$$paper{'index'}); 
    }

    my $buy_qty = $qty; # Need to make a copy

    if ($paper->{type} eq 'roll') {
        if ( $price->{units} eq 'Roll' ) {
            my $roll_weight = $dbh->selectrow_array(q{
                    SELECT dblrollweight FROM tbl_paper_roll WHERE lngindex = ?
            }, {}, $paper->{index});
            $price->{Cost}  /= $roll_weight if $roll_weight;
            $price->{Price} /= $roll_weight if $roll_weight;
        } else {
            $price->{Cost}  /= 100;
            $price->{Price} /= 100;
        
        }
    } 
    elsif ( $price->{units} eq '1000 Sheets' or $price->{units} eq '1000 sheets' ) {
        $price->{Cost}  /= 1000; 
        $price->{Price} /= 1000;
    } 
    elsif ( $price->{units} =~ /lbs/ ) {
        # Get a per sheet price for the stock. The MWeight is the weight of
        # 1000 sheets and the price is based on 100lbs. 
        #
        #    per_sheet = n/1000 * MWeight * price/100 lbs, n = 1
        #
        $price->{Cost}  *= $mweight / (100 * 1000); 
        $price->{Price} *= $mweight / (100 * 1000); 
    } else {
        $log->error(" Invalid Paper Units: $price->{units}");
    }

    # As price 'breaks' in the system are stepped instead of graduated, it can
    # sometimes be less expensive to buy a slightly large quantity and get the
    # better discount. If we have an bounded upper range (meaning there's a
    # range above us) get the price for the next higher range.
    if ($price->{max}) {
        my $bulkprice = price(
            $dbh, $variable->{cust_id}, $paper->{index}, $price->{max} + 1
        );

        # now we do the same calculation for bulk price and compare our total
        # price per sheet after we subtract throwaway sheets
        if ( $bulkprice->{units} eq '1000 Sheets' or $bulkprice->{units} eq '1000 sheets') {
            $bulkprice->{Cost}  /= 1000;
            $bulkprice->{Price} /= 1000;
        } 
        else {
            $bulkprice->{Cost}  *= $mweight / (100 * 1000);
            $bulkprice->{Price} *= $mweight / (100 * 1000);
        }
        
        # throw away extra bulk and compare prices

        # our formula for bulk price is: bulk price * price->{max}+1 / qty ...
        # then compare this to price and take the cheapest one
        if ( ($price->{Price}*$qty) > ($bulkprice->{Price}*($price->{max}+1))
                and $bulkprice->{Price} > 0 ) {
            $buy_qty = $price->{max}+1;
            $price = $bulkprice;
        }
    }

    $price->{buy_qty} = $buy_qty;

    return $price;
}

# Get the paper price (including all pricelist and customer discounts) for a
# given quantity of the given paper.
sub price {
    my ($dbh, $customer, $paper, $qty) = @_;

    # Get the paper price for the given quantity.
    my $sth = $dbh->prepare_cached(qq{ 
         SELECT lngmin          AS min,
                lngmax          AS max,
                strunits        AS units,
                dblcost         AS "Cost",
                dblmarkup       AS "Markup",
                dblprice        AS "Price",
                ysndiscountable AS "Discountable"
          FROM tbl_paper_prices p, tbl_customer c
          WHERE p.lnglistindex  = c.lngpricelist
            AND c.lngcustomerid = ?
            AND lngpaperindex   = ?
            AND  ? >= coalesce(lngmin, 0) 
            AND (? <= lngmax OR lngmax IS NULL)
          ORDER BY lngmin
          LIMIT 1
    });
    my $price = $dbh->selectrow_hashref($sth, undef, $customer, $paper, $qty, $qty);

    return undef unless $price;

    # Apply any pricelist or customer discounts if applicable.
    if ($price->{Discountable} eq 'Y') {
        my $discount = get_discount($dbh, $customer);

        $price->{Price} *= 1 + ($discount/100) if $discount;
    }

    return $price;
}

# because paper pricing is such a collossal mess, there is no reason to price
# rolls of paper for web printing through this system therefore I am going to
# write new, simple procedures for getting web paper and pricing. There will
# be no paper recommendations for certain jobs nor will there be fancy units
# of pricing, nor will rolls of paper be at all related to sheets of the same
# paper. We will use a new table that will contain data and pricing and all
# web projects will have all available rolled paper to choose from. Later on,
# we can do things differently, but in terms of getting web up to snuff fast,
# we cannot pump it through the legacy paper code. - Duke
sub get_all_roll_stocks {
    my ($log, $dbh) = @_;

    return sql::sql_statement($log, $dbh, q{
        SELECT strid, strname, strfinish, strcolour, strweight 
        FROM tbl_paper_rolls
    });
}

sub convert_sheets_into_rolls {
    my ($log, $dbh, $qty, $paper_index) = @_;

    #1. get weight of paper
    #2. get weight of roll
    #3. divide quantity by 500 (ream) to get number of reams
    #4. divide roll weight by ream weight to get number of reams in the roll
    #5. divide reams by reams_per_roll to get number of rolls used.
    #6. get purchase unit.
    #7. round up based on pricing unit.
    #8. return the result

    # we'll just take an mweight instead of calculating it
    my ($reamweight, $rollweight, $purchase_unit) = $dbh->selectrow_array(q{
        SELECT strmweight, dblrollweight, dblpurchaseunit 
        FROM tbl_paper_roll 
        WHERE lngindex = ?
    }, {}, $paper_index);

    my $reams          = $qty / 1000; # there are 1000 sheets in a ream
    my $reams_per_roll = $rollweight / $reamweight;
    my $rolls_used     = $reams / $reams_per_roll;
    my $full_rolls     = floor($rolls_used);
    my $partial_rolls  = $rolls_used - $full_rolls;

    # We aren't rounding or there is nothing to round
    if ($partial_rolls == 0 || $purchase_unit == 0) { return $rolls_used }

    # We are rounding all the way up to the next full roll
    if ($purchase_unit == 100)                      { return $full_rolls + 1 }
    
    my $partial_purchase = $purchase_unit;
    while (($partial_rolls * 100) > $partial_purchase) { 
        $partial_purchase += $purchase_unit;    
    }
    # We are using enough to round all the way up to the roll anyway.
    if ($partial_purchase > 100) { return $full_rolls + 1 } 

    # We are buying enough portions of a roll to satisfy requirements
    return $full_rolls + ($partial_purchase/100); 
}

sub convert_rolls_into_pounds {
    my ($log, $dbh, $qty, $paper_index) = @_;

    my $roll_weight = $dbh->selectrow_array(q{
        SELECT dblrollweight FROM tbl_paper_roll WHERE lngindex = ?
    }, {}, $paper_index);
    
    return $roll_weight * $qty;
}

1;
