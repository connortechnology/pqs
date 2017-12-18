package eprint::Service::Folding;
use strict;
use warnings;
no warnings qw(uninitialized);

use eprint::Config;
use eprint::project          qw(:common :multipage);
use eprint::service          qw(:common);
use sql                      qw(:common);
use POSIX                    qw(ceil);
use eprint::Service::Spiral  qw(SPIRAL);
use callback;

# Default spacing gap if one isn't provided on the machine.
use constant DEFAULT_GAP => eprint::Config->get(Folding => 'default_gap');

# The size of a signature (column × rows) based on flat dimensions (2pg.).
# Actual spread size doesn't matter. Used to approximate signature sizes for
# linear inch folding.
our %SIGNATURE_LAYOUT = (
    32 => [4,4], 24 => [4,3], 20 => [5,2], 
    16 => [4,2], 12 => [2,3],  
     8 => [2,2], 
     4 => [2,1],
);


# A function that is smart enough to return true if the project needs folding,
# and false if it doesn't. NOTE: 'Smart' is relative term. In this case our
# benchmark is pond goo, which is of genius intellect.
sub necessary {
    my ($log, $dbh, $pid, $service_type) = @_;

    # The user doesn't want any post-press services. DEPRECATED
    return 0 if has_no_bindery($log, $dbh, $pid);

    # Some project types simply can't be folded.
    my $project_type = get_type($log, $dbh, $pid);

    # Large format projects don't get folding, nor do these others.
    return 0 if $project_type =~ m/^LF[_-]/
             || grep { $project_type eq $_ } qw( Envelopes InkjetOutputs
                                                 Product   ScreenItem
                                                 PresentationFolders PressSheetCombination );

    my $bind_type  = get_bindery_type($log, $dbh, $pid);
    my $press_type = get_press_type($log, $dbh, $pid);

#print STDERR "FOLDING BIND: $bind_type PRESS: $press_type \n";

    # For Digital Spiral Projects we will not fold.
    return 0 if $press_type eq 'digital'
             && grep { $bind_type eq $_ } (SPIRAL, 'CornerStitching', 'CornerStitch3Punch', '3HolePunchBinder', 'SingleHole');

    # TODO: This is erroneous, we just don't handle it properly yet.
    return 0
      if check_for_service($log, $dbh, $pid, 'DieCutting');

    # Check to see if any signature needs us.
    foreach my $sig (get_signature_indices($log, $dbh, $pid))
    {
        my %specs = eprint::service::get_specifications_pairs($log, $dbh, $pid, $sig,
            qw( final_width     final_height
                flat_width      flat_height
                txtSpreadWidth  txtSpreadHeight
                hdnBinderyType  template
                txtSignatureSize
        ));
        return 1 if signature_needs($log, $dbh, \%specs);
    }

    return 0;
}

sub signature_needs {
    my ( $log, $dbh, $specs ) = @_;

    no warnings qw(uninitialized);

    # We've explicitly been asked not to run.
    return 0 if $specs->{hdnBinderyType} eq 'NoBindery'
             || $specs->{template}       eq 'NoFold';

    return 0 if $specs->{txtSignatureSize} == 2;

    # Spread dimensions are only found on signatures.
    return 1 if $specs->{txtSpreadWidth} || $specs->{txtSpreadHeight};

    #Can't fold unless we actually have final specs.
    return 0 if !$specs->{final_width} || !$specs->{final_height};

    # If the final dimensions are different than the flat ones, it has to get
    # there somehow...
    return 1 if   $specs->{final_width}  != $specs->{flat_width}
               || $specs->{final_height} != $specs->{flat_height};

    return 0;
}

sub get_fold_types {
	my ($dbh, $sig) = @_;

	my $sth = $dbh->prepare_cached(q{
		SELECT strName, strValue 
        FROM tbl_Service_Specifications 
        WHERE lngServiceIndex = ?
        AND (    strName LIKE 'txtSignatureQty%'
        	  OR strName LIKE '%GateFolded'      )
	});
		  

	my %folds = @{$dbh->selectcol_arrayref($sth, {Columns => [1,2]}, $sig)};

	my %new_folds;
    while (my ($fold_type, $qty) = each %folds) {

        next unless $qty && int($qty) > 0;
        $fold_type =~ s/SignatureQty//;
        $fold_type =~ s/Page/PageSignatureFoldQty/;
		$new_folds{$fold_type} = $qty;
	}

	return \%new_folds;
}


sub fill_from_printing_service {
    my ($log, $dbh, $pid, $sid) = @_;


    # Check for calliper too thick, and add scoring appropriately
    my %count;
    for my $sig (get_signature_indices($log, $dbh, $pid)) { 
        
        validate_fold_calliper($log, $dbh, $pid, $sig);

        # TODO Skip perfect bound covers as they're handled 
		# on the perfect binder.
		my $folds = get_fold_types($dbh, $sig);

        $count{$_} += $folds->{$_} for keys %{$folds};
    }

    $dbh->do(q{
        DELETE FROM tbl_Service_specifications 
        WHERE lngServiceIndex = ?
          AND (   strName like '%SignatureFoldQty'
               OR strName like '%GateFolded' )
    }, undef, $sid);


    my $tshirt = $dbh->selectrow_array(q{
    	SELECT strid FROM tbl_projecttypes WHERE lngindex = (
		SELECT lngprojecttype FROM tbl_projects WHERE lngprojectindex = ?
	)
    }, undef, $pid);

    $count{txtTShirtFoldQty} = 1 if $tshirt eq 'ScreenTShirts';

    insert_service_specs($log, $dbh, $pid, $sid, %count);

    return 1;
}



sub validate_fold_calliper {
    my ($log, $dbh, $pid, $sid) = @_;

	my $type = get_type($log, $dbh, $pid);

	return if $type eq 'NoPrint';

    # We are going to use the Maximum of
    # All of the equipment in the database.
    # After Imposition is done then we can
    # check to make sure the signature size is
    # valid for the folder.
    my ($max_cal) = $dbh->selectrow_array(q{
        SELECT strValue
        FROM tbl_equipment_specifications
        WHERE lngequipmentindex IN (
            SELECT lngindex
            FROM tbl_equipment
            WHERE strType = 'folder' )
        AND strName = 'Maximum Signature Folding Calliper'
        ORDER by strValue Desc
        LIMIT 1;
    }, undef);


    my %convert = ( 32 => 16, 24 => 12, 20 => 4, 16 => 8, 12 => 4, 8 => 4, );

    my $error;

    # Get all of the specs for the signature from its printing service.
    my %specs = get_specifications_pairs($log, $dbh, undef, $sid);

    # Stock Calliper of the press sheet for this signature
    my $stock_cal = $specs{txtStockCalliper};

    die "No calliper found" unless $stock_cal;

    # Figure out how many layers of this stock can go through the folder.
    my $max_layers = int( $max_cal / $stock_cal );

    # We are only going to validate Signature Folds.
    my @sig_types = grep { /^txtSignatureQty(\d+)/ } keys %specs;
    my %conversions;

    # For each Signature Fold type
    foreach my $sig (@sig_types) {

        next if $error or ! $specs{$sig};

        $sig =~ /^txtSignatureQty(\d*)/;

        # $type is going to be the number of pages in the signature
        my $type = $1;

        # fold depth is the number of layers of paper that run
        # through the folder for the last fold. The big assumption
        # here is that the last fold will be the spine fold. That
        # way the fold depth will be the number of pages / 4.
        # All signature smaller than 8 pages will have only 1 layer
        # be for folding such as 2,4 and 6 page signatures.
        my $fd = $type >= 8 ? ceil( $type / 4 ) : 1;

        # Check if our fold depth is larger than the maximum
        # number of layers that will fit through the folder.
        if ( $fd > $max_layers ) {

            # $b will be the signature size before conversion.
            my $b = $type;

            # keep looking until we have a valid fold type or an error.
            while ( !$conversions{$type} and !$error ) {

                # $a is the signature size after conversion.
                my $a = $convert{$b};

                if ( $a >= $b or !$a ) {

                 # if our conversion table is messed up and tells us to
                 # convert to a larger signature size we are going to call that
                 # an error. Or if told to convert to nothing the we are also in
                 # trouble.
                    $error = 'Invalid Fold Conversion';
                }
                else {

                # If our converted signature size is not over the max layers
                # that can go though the folder the record the type of signature
                # we are converting to.
                    $conversions{$type} = $a
                      unless ceil( $a / 4 ) > $max_layers;

              # if the type we converted to is not valid then move our converted
              # type into $b so we can convert it a size smaller.
                    $b = $a;
                }
            }
        }
    }
    convert_signatures( $log, $dbh, $pid, $sid, \%specs, \%conversions )
      if ( keys %conversions );

    return $error ? ( 'error', $error ) : 1;
}

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    die "Folding called with PID ($pid) or SID ($sid)"
        unless $pid && $sid;

    my $valid_price = 0;

    my @qtys = (undef, get_quantities($log, $dbh, $pid));


    # bash in inline folding on a web press here
    # instead of an if-else we'll just return from the web folding

	my $folds;
	my %inline_prices;
    if (eprint::project::get_press_type($log, $dbh, $pid) eq 'web') { 
		my $cover_etype = configuration::get_value($log, $dbh, 'WebCoverPressType');

        my $status = eprint::service::get_inline_web_bindery( $log, $dbh, 
									$pid, $sid, \%inline_prices, 'Folding' );

		map {$specs->{$_} = $inline_prices{$_}; print STDERR "KEY : $_ \n";} keys %inline_prices;

		if ( $cover_etype eq 'press' ) {
			my $cover_sid  = get_cover_sid($dbh, $pid);
			my $cover_type = get_fold_types($dbh, $cover_sid);
			$folds = $cover_type;
		} else {
			return $status if $status eq 'calculated';
		}
	} 

	unless ( keys %{$folds} ) {
		my %fold_types;
		foreach my $key (keys %${specs}) {
            next unless $key =~ /^txt(\w*)(Qty|ed)$/;
            next unless $specs->{$key};
			$fold_types{$key} = $specs->{$key};
		}
		$folds = \%fold_types;
    }

    my $sigs = get_signature_indices( $log, $dbh, $pid );
    my ($press) = get_specifications($log, $dbh, undef, $sigs, 'hdnPress');
	
	my $prices = get_fold_prices($log, $dbh, $variable, $pid, $sigs, $folds, @qtys, );

    QTY:
    foreach my $i ( 1 .. 3 ) {
        my $qty = $specs->{"txtQuantity$i"} || $qtys[$i];

        next unless $qty && $qty > 0;

        # Stupidly simple folding for press sheet combinations.
        $qty *= $specs->{txtPressSheetComboItems} 
            		if $specs->{txtPressSheetComboItems};

        my $service = best_price($log, $dbh, $press, $pid, $sid, $i, $prices);
        
		my $total = $service->{total}{$i} + $inline_prices{"txtPrice$i"};

        @$specs{"txtPrice$i", "txtUnitPrice$i"} = format_pricing($total, $qty);

        $specs->{"ddmEquipment$i"} = $service->{equipment};
        $specs->{"hdnEquipment$i"} = $service->{equipment};
        $specs->{"hdnRunTime$i"}   = sprintf("%.2f",$service->{RunTimePerK} * $qty / 1000);

        $valid_price = 1 if $total > 0;
    }

    return $valid_price == 1 ? 'calculated' : 'error';
}

sub get_fold_prices {

	my ($log, $dbh, $variable, $pid, $sid, $specs, @quantities ) = @_;
    my @equipment =
      eprint::service::valid_equipment($log, $dbh, 'Folding', $pid);

    my @prices = ();

    # it would be nice to have our 3 quantites passed in as parameters, but
    # here we will have to query them.  For now we're going to just run the
    # first quantity and come up with a value for that, as this is a subset of
    # the larger 3 quantity problem.

    my $sql = "SELECT intquantity1 FROM tbl_projects WHERE lngprojectindex = $pid";
    my $project_qty = ( sql_statement( $log, $dbh, $sql ) )[0];
    my $make_ready  = 0;
    my $runprice    = 0;
    my %markupPrices;

    my $proj = get_print_container($log, $dbh, $pid);


    EQUIPMENT:

    foreach my $eid (@equipment) {

        my $service = { equipment => $eid };
        my $run_per_k;


        FOLD_TYPE:
        foreach my $name ( keys %$specs ) {

            next FOLD_TYPE unless $name =~ /^txt(\w*)(Qty|ed)$/;

            my $type = $1;                      # Fold type
               $type =~ s/ZFold/AccordianFold/; # Handle a naming inconsistancy


            my $quantity = $specs->{$name};

            next FOLD_TYPE unless $quantity && $quantity > 0;

            # This will be the number of signature duplicates (ie 4 when running 4
            # 16-page signatures in a 64page book).
            my $signature_fold_quantity = int $quantity;

            my ($final_height, $final_width, $flat_height, $flat_width)
                = get_specifications($log, $dbh, $pid, $proj, 
                    qw(final_height final_width flat_height flat_width));

            my $run_speed =
                    eprint::equipment::get_specification(
                        $log, $dbh, "$type Run Speed", $flat_width, $eid
            );

            $run_per_k += $run_speed ? (1000 * $quantity) / $run_speed : 0;

            # here we need to find out if we can fold the job multiple-up
            my $folding_imposition = get_folding_imposition(
                $log,         $dbh,          $pid,
                $type,        $flat_width,   $flat_height,
                $final_width, $final_height, $eid
            );

            # Then we actually need to do something with
            # folding_imposition we have already checked the equipment
            # spec to make sure that we are only doing allowable
            # multi-up folding, so now we'll just go with what we've
            # got.  For this version, we will be doing very simple
            # approximations of the multi-up folding. We'll need to
            # divide the quantity of folding by the folding imposition
            # We'll also need to save this information somewhere so
            # that cutting will know to make (X-1)/2 less cuts (where
            # X is folding imposition). We won't need to modify the
            # linear inches, since we'll be folding across the width
            # of the fold - basically, we're just modifying based on
            # height. in the next version, hopefully we'll have the
            # time to do multi-up folding completely right, meaning
            # hybrid folding, cut and chase, and a whole new stage 1
            # bindery control system

            insert_service_spec($log, $dbh, $pid, $sid, 'txtFoldingImposition', $folding_imposition);

            # in testing bug 172, there's issue of bad data raised.
            # because of the bad data, get_folding_imposition returns
            # NULL or contains non-digits sometimes for now, we use a
            # default folding imposition 1
            if ( $folding_imposition !~ m/^\d+$/ ) {
                $folding_imposition = 1;
            }

            # Setup
            my $price   = eprint::service::get_price($log, $dbh, $variable, "${type}MakeReady", undef, $eid);

            $make_ready = $markupPrices{$eid} = $price;
            
            $service->{setup} += $price;

            # Check to see if we are running in per 1000 sheets and if
            # so, ignore per hour and runspeed calculations and go per
            # sheet

            my $runUnits     = eprint::equipment::get_units($log, $dbh, $type, $eid, $variable);
            my $servicePrice = eprint::service::get_price($log, $dbh, $variable, $type, $project_qty, $eid);

            next EQUIPMENT unless $servicePrice;

            if (   $runUnits eq 'Per 1000'
                || $runUnits eq 'Per 1000 Sheets' )
            {
                if ( !eprint::equipment::equipment_fits( 
                        $log, $dbh, $eid, $flat_width, $flat_height)
                ) {
                    next EQUIPMENT;
                }

                # calculate based on price per 1000 units
                $price = $servicePrice / 1000;
            }
            else {
                # calculate based on runspeed and price per hour

                # convert string back to the Z form - yes this is a
                # crappy way to do it but it is in keeping with the
                # rest of this module
                $type =~ s/AccordianFold/ZFold/; 
                $type =~ s/\B([A-Z])/ $1/g;

                my $runspeed_units = $dbh->selectrow_array(qq{
                    SELECT strunits
                    FROM tbl_equipment_specifications
                    WHERE strname = '$type Run Speed'
                      AND lngequipmentindex = ?
                }, undef, $eid);

                my $print = get_print_container($log, $dbh, $pid);

                my ($final_width, $final_height, $flat_width, $flat_height)
                    = get_specifications($log, $dbh, undef, $print, qw(
                        final_width  final_height
                        flat_width   flat_height
                ));

                # We don't actually know which press sheet any given signature
                # is from, so we'll just approximate the signature size based
                # on the finished size of the book (trim, bleed, etc. is not
                # considered).
                if ($type =~ /^(\d+)\s*Page\s*Signature/) {
                    my $n = $1;

                    my ($c, $r) = @{ $SIGNATURE_LAYOUT{$n} };

                    $flat_width  = $final_width  * $c;
                    $flat_height = $final_height * $r;

		    unless ( eprint::equipment::equipment_fits( $log, $dbh, $eid, $flat_width, $flat_height) ) {
			$flat_width  = $final_width  * $r;
			$flat_height = $final_height * $c;
		    }

                }

#This check is currently producing some false negatives.
#If we can print it, we can fold it.
                next EQUIPMENT unless eprint::equipment::equipment_fits(
                    $log, $dbh, $eid, $flat_width, $flat_height
                );

                if ( $flat_width == $final_width ) {
                    $flat_width = $flat_height;
                }
                elsif ( $flat_height == $final_height ) { }
                elsif ( $flat_height > $flat_width )    {
                    $flat_width = $flat_height;
                } # if taller than wide, fold tall first - add right angle gap here too

                my $gap = eprint::equipment::get_specification(
                    $log, $dbh, 'Default Gap', undef, $eid
                ) || DEFAULT_GAP;

                my $run_speed =
                    eprint::equipment::get_specification(
                        $log, $dbh, "$type Run Speed", $flat_width, $eid
                );

                $flat_width += $gap;

                # Convert from linear feet per hour to press sheets per hour
                $run_speed = ceil( $run_speed / ($flat_width / 12) )
                    if $runspeed_units =~ /Feet per Hour/i;

                # Price per press sheet.
                $price = $servicePrice / $run_speed if $run_speed;

            }

            RUN:
            foreach my $i ( 1 .. 3 ) {

                next RUN if $specs->{"chkOverrideEquipment$i"} eq 'Y'
                         && $specs->{"ddmEquipment$i"} ne $eid;

                # here we will fold X/N total sheets if we are N-up
                # for an X quantity                          
                my $qty  = $specs->{"txtQuantity$i"} || $quantities[$i];
                   $qty /= $folding_imposition;

                $qty *= $specs->{txtPressSheetComboItems} 
                    if $specs->{txtPressSheetComboItems};

                next RUN unless $qty && $qty > 0;
                
                $service->{run_price}{$i} 
                    += $price * $qty * ($signature_fold_quantity || 1);

            }
            $service->{RunTimePerK} = $run_per_k;
        }
        push @prices, $service;
    }
	return \@prices;
}


sub best_price {
    my ( $log, $dbh, $press, $pid, $sid, $qty_index, $prices ) = @_;
    my $bestPrice;
    my $have_price = 0;
    my %supplier;

    $supplier{$_->[0]} = $_->[1] for @{ $dbh->selectall_arrayref(qq{
        SELECT strid, strsupplier FROM tbl_equipment
    }, undef)};

    my %etype;
    $etype{$_->[0]} = $_->[1] for @{ $dbh->selectall_arrayref(qq{
        SELECT lngindex, strtype FROM tbl_equipment
    }, undef)};

    my $ps = $supplier{$press};

    foreach my $price (@{$prices}) {

        # Must have run price for price to be valid.
        next unless $price->{run_price}{$qty_index};

        my $make_ready = $price->{setup};
        callback::call('service_calc_end', $pid, $sid, \$make_ready, \$price->{run_price}{$qty_index});
        $price->{total}{$qty_index} 
            = $make_ready + $price->{run_price}{$qty_index};

        my $totalPrice        = $price->{total}{$qty_index};
        my $current_bestPrice = $have_price ?
          $bestPrice->{total}{$qty_index} : 0;   # actually extract the best price

        my $press_type    = eprint::project::get_press_type($log, $dbh, $pid);
        my $print_presses = eprint::project::get_print_presses($log, $dbh, $pid);

        # For folding on a Digital/Web Press we must be using the press to print
        # at least one of the signatures to use it for folding.
        if (    $etype{$price->{equipment}} eq 'digital'
             or $etype{$price->{equipment}} eq 'web'
           ) {
                unless ( grep { $price->{equipment} eq $_ } @$print_presses ) {
                    next;
                  };
        }

        if ( $totalPrice > 0
            and (
                       $totalPrice < $current_bestPrice
                    or !$have_price
                    or  (     $supplier{$price->{equipment}}     eq $ps
                          and $supplier{$bestPrice->{equipment}} ne $ps
                        )

                )
          )
        {   
            $have_price = 1;
            $bestPrice  = $price;
        }
    }

    return $bestPrice;
}

# Use the fold type, width, height, and imposition data to determine the
# maximum folding imposition for a project return the number (up-ness) of
# folds that can be done concurrently. For now we will only handle simple 2-up
# (and so forth) folding, where folding is done to the whole sheet and then
# gutters are cut out. Items like 8 page signature folds running 2-up will not
# be handled until later, if at all.
sub get_folding_imposition {
    my (
        $log,         $dbh,          $pid,
        $type,        $flat_width,   $flat_height,
        $final_width, $final_height, $eid
      )
      = @_;


    # For now we don't handle multi-page projects.
    return 1 if eprint::project::is_multipage( $log, $dbh, $pid );

    # If signature or difficult (except 4-page) we don't handle it multi-up.
    if ( ( $type =~ /Signature/ || $type =~ /Difficult/ )
        && $type ne '4PageSignatureFold' )
    {
        return 1;    # Any right angle folding isn't considered yet.
    }

    ################ Quantity break
    # We need to prevent mutli-up folding for small quantities - if the user
    # has defined a min. multi-up spec (if they don't think it's worth the
    # bother on short runs).

    # We use a mock-up of the variable hash to get quantites for the job.
    my %variable;
    @variable{ map {"txtQuantity$_"} 1..3 } = get_quantities($log, $dbh, $pid);
    
    my $quantity_breakpoint =
      eprint::equipment::get_specification( $log, $dbh,
        'Minimum Multiup Folding Quantity',
        undef, $eid );
    if ( $variable{txtQuantity1} < $quantity_breakpoint ) {
        return 1;
    }

    my ($maximum_imposition) =
      eprint::equipment::get_specifications( $log, $dbh, $eid,
        'Maximum Folding Imposition' );
    if (   $maximum_imposition == 0
        || $maximum_imposition == 1
        || $maximum_imposition !~ m/^\d+$/ )
    {
        return 1;
    }

    my $sid = get_print_container($log, $dbh, $pid);

    my ($orientation, $imposition, $columns, $rows) 
        = eprint::service::get_specifications( $log, $dbh, $pid, $sid, 
            qw{hdnImageOrientation hdnImpositionColumns hdnImpositionRows hdnImposition});


    #####################
    # Now try to select the max folding imposition using a simpler solution
    # because we don't have to consider the size of a press-sheet, we don't
    # need to calculate the "max width upness" and "max height upness" as did
    # above.  Simply we look at the orientation of the layout on press-sheet
    # and which side we are folding, and the result of folding imposition
    # would be either the imposition row value or the imposition column value.

    # Case 1: Horizontal orientation of the documents on press-sheet + folding
    #         the width of each document or Vertical orientation of the
    #         documents on press-sheet + folding the height of each document
    #         do horizontal folds by rows, therefore the folding imposition is
    #         number of columns in each row.
    if (
        (
               $orientation eq 'Horizontal'
            && $flat_height eq $final_height
            && $flat_width ne $final_width
        )
        || (   $orientation eq 'Vertical'
            && $flat_width eq $final_width
            && $flat_height ne $final_height )
      )
    {
        if ( $columns !~ m/^\d+$/ || $columns == 0 ) {
            return 1;
        }
        if ( $columns > $maximum_imposition ) {
            return $maximum_imposition;
        }
        else {
            return $columns;
        }
    }

    # Case 2: Horizal orientation of the documents on press-sheet + folding
    #         the height of each document or Vertical orientation of the
    #         documents on press-sheet + folding the width of each document do
    #         vertical folds by columns, therefore the folding imposition is
    #         number of rows in each column.
    elsif (
        (
               $orientation eq 'Horizontal'
            && $flat_width  eq $final_width
            && $flat_height ne $final_height
        )
        || (   $orientation eq 'Vertical'
            && $flat_height eq $final_height
            && $flat_width ne $final_width )
      )
    {
        if ( $rows !~ m/^\d+$/ || $rows == 0 ) {
            return 1;
        }
        if ( $rows > $maximum_imposition ) {
            return $maximum_imposition;
        }
        else {
            return $rows;
        }
    }

    # Do we even need to do anything with sheet height and sheet width? seems
    # like folder dimensions take care of this.

    # If we haven't determined any higher order folding, we will just do 1-up
    # by default.
    return 1;
}

sub convert_signatures {
    my ( $log, $dbh, $pid, $sid, $specs, $con ) = @_;

    # The conversion has will contain only the types of signatures
    # that need to be converted.
    foreach my $key ( keys %$con ) {

        # Build the name of the spec to be replaced
        my $o_type = 'txtSignatureQty' . $key . 'Page';

        # Check to see if we have any signautres of this type
        my $o_qty = $$specs{$o_type};

        # if we do then we are going then convert.
        if ($o_qty) {

            # calculate the new qty of sigantures.
            # The old size divided by the new size times the original
            # number of signatures
            my $n_qty = $key / $$con{$key} * $o_qty;

            # The field name for the new signature type
            my $n_type = 'txtSignatureQty' . $$con{$key} . 'Page';

            # Blank the old signature type.
            insert_service_spec($log, $dbh, $pid, $sid, $o_type, '');

            # Insert the qty for the new signature type
            insert_service_spec($log, $dbh, $pid, $sid, $n_type, $n_qty);
        }
    }
}


sub display {
    my ($log, $dbh, $service_type, $pid, $sid, $specs) = @_;

    my %page;

    my @qty       = (undef, get_quantities($log, $dbh, $pid));
    my $equipment = eprint::service::valid_equipment_dropdown($dbh, 'Folding');

    for my $i (1..3) {
        $page{"QUANTITY$i"}            = $qty[$i]; # Remove when possible.
        $page{"txtQuantity$i"}         = $qty[$i]; # Remove when possible.
        $page{"ddmEquipmentOptions$i"} = $equipment;
    }

    return \%page;
}

1;
