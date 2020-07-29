package eprint::Service::Proofs;
use strict;
use warnings;
no warnings qw(uninitialized);

use eprint::equipment ();
use eprint::print ();
use eprint::project qw(:common :multipage);
use eprint::service qw(:common);
use POSIX qw(ceil floor);
use sql   qw(:common);
use ssi   qw(make_drop_down);


sub necessary {
    my ($log, $dbh, $pid, $service_type) = @_;

    my $type = get_press_type($log, $dbh, $pid);

    # Inkjets are often proofers, and digital creates it's own.
    return 0 if $type eq 'inkjetprinter'
             || $type eq 'digital';

	my $project_type = eprint::project::get_type($log, $dbh, $pid);
	return 0 if $project_type eq 'InventoryCheckOut';

	$type = eprint::project::get_type($log, $dbh, $pid);
	return 0 if $type eq 'NoPrint';



    return 1;
}

sub fill_from_printing_service {
    my ($log, $dbh, $pid, $sid) = @_;

    my @sigs = check_for_service($log, $dbh, $pid, 'Printing');

    # Blow away all of our proofing info and recreate it from scratch.
    delete_proofs($log, $dbh, $sid);
    insert_proof_defaults($log, $dbh, $pid, $sid, $_) for @sigs;

    return 1;
}


sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    my $status = 'calculated';

    # Check to see if we have a scanning proof yet to add and pop up page if
    # we do if *any* rebRandomProof is set to yes, we want to capture it.
    my ($scanning_proof) = sql::sql_statement($log, $dbh, qq{
        SELECT strvalue 
        FROM tbl_service_specifications 
        WHERE lngprojectindex = $pid 
          AND strname='rdbRandomProof' 
        ORDER BY strvalue DESC
    });

    # Check to see if we have already calculated this service.
    my $prev_status = scalar $dbh->selectrow_array(q{
        SELECT strstatus FROM tbl_project_contents WHERE lngserviceindex = ?
    }, undef, $sid);
   

    if ($scanning_proof eq 'Yes' and $prev_status ne 'calculated') {
        # don't bother doing more calculations - just mark as uncalculated
        return 0;   
    }

    my @qty = (undef, get_quantities($log, $dbh, $pid));
    $specs->{"txtQuantity$_"} = $qty[$_] for 1..3;


    ($specs->{'txtQuantity1'}, $specs->{'txtQuantity2'}, $specs->{'txtQuantity3'}) =
      get_specifications($log, $dbh, undef, $sid, 'txtQuantity1',
                         'txtQuantity2', 'txtQuantity3');

    # we must change specs so that calc acts on larger quantities when there
    # have been additional plate changes added select add_plates from
    # tbl_service_specifications if > 0 then div to get set changes and mod to
    # get single changes sum the total and multiply by all proof quantities

    my ($plate_changes) = $dbh->selectrow_array(q{
				 SELECT strvalue 
	             FROM tbl_service_specifications 
				 WHERE strname='add_plates' and lngprojectindex = ?
				 ORDER BY lngserviceindex
	}, undef, $pid );

    my ($total_plates) = $dbh->selectrow_array(q{
    			SELECT strvalue 
				FROM tbl_service_specifications 
				WHERE strname='txtPlateQuantity' and lngprojectindex = ?
				ORDER BY lngserviceindex

	}, undef, $pid);


    my $first_plates = $total_plates - $plate_changes;    #obtain the number of original plates

    if ($plate_changes && $total_plates && ($first_plates > 0) && ! $specs->{hdnPriorProof}) {

        # we have additional versions so we need to add more proofs in future
        # versions that handle this more correctly (and I really hope they
        # have time to be done) there will be a better way to specify a
        # complete set of plates to be changed vs. a single plate to be
        # changed.  For now, we will assume that n+xm additional plates for
        # m<n where there a+b=n and we are printing a/b will mean that we will
        # add x sets of proofs (complete plate changes) and then n sets of
        # proofs (single plate changes)

        my $additional_sets = floor($plate_changes / $first_plates);
        my $additional_singles = $plate_changes % $first_plates;

        # We need to add 1 for the multiplicative identity
        my $version_proof_factor = $additional_sets + $additional_singles + 1;

        foreach my $key (keys %$specs) {
            if ($key =~ /txtProofQuantity-(.*)/) {
                $specs->{$key} *= $version_proof_factor;
            }
        }

        # we also need to make sure that the proofs page pops up
        $status = 'uncalculated';

    }

    my $calc_status = calc_proofs($log, $dbh, $variable, $pid, $sid, $specs);

    if ($status ne 'uncalculated') { $status = $calc_status }

    return $status;
}

sub calc_proofs {
    my ($log, $dbh, $variable, $pid, $sid, $specs) = @_;
    my $status = 'calculated';

    my $totalPrice    = 0;
    my $totalQuantity = 0;
    my %proof_totals;
    my @signature_service_indices =
      eprint::project::get_signature_indices($log, $dbh, $pid);

    foreach my $key (keys %$specs) {
        next unless $key =~ /txtProofQuantity-(.*)/;
        
        my $type = $specs->{"ddmProofType-$1"};

        next unless $type;
            
        $proof_totals{$type} = { Quantity => 0, Price => 0 }
            unless exists $proof_totals{$type};

        $proof_totals{$type}{Quantity} += $specs->{$key};
        $totalQuantity                 += $specs->{$key};
    }

    foreach my $type (keys %proof_totals) {
        my $service = $dbh->selectrow_array(q{
            SELECT lngindex FROM tbl_services WHERE strid = ?
        }, undef, $type);

        my ($price, $units) = eprint::service::price_item(
            $dbh, $variable->{cust_id}, $service, $proof_totals{$type}{Quantity}
        );
        
        $proof_totals{$type}{Price} = $price;
        $proof_totals{$type}{units} = $units;
    }


    foreach my $key (keys %$specs) {
        next unless $key =~ /txtProofQuantity-(.*)/;

        my $type     = $specs->{"ddmProofType-$1"};
        my $width    = $specs->{"txtProofWidth-$1"};
        my $height   = $specs->{"txtProofHeight-$1"};
        my $quantity = $specs->{"txtProofQuantity-$1"};

        my $service = $dbh->selectrow_array(q{
            SELECT lngindex FROM tbl_services WHERE strid = ?
        }, undef, $type);

        my ($price, $units, $proofer) = eprint::service::price_item(
            $dbh, $variable->{cust_id}, $service, $width * $height
        );

        if (!$type || !$proofer) {
            $$specs{ 'txtProofUnitPrice-' . $1 } = '0.00';
            next;
        }

        my ($equip_width, $equip_height) =
          eprint::equipment::get_specifications($log, $dbh, $proofer,
                                                'Maximum Sheet Width',
                                                'Maximum Sheet Length');
        if (   ($width > $equip_width  || $height > $equip_height)
            && ($width > $equip_height || $height > $equip_width)
            && ($equip_width && $equip_height))
        {
            $log->error(
                "PROOFS: cannot produce a proof that is $width x $height on a proofer that is $equip_width x $equip_height"
            );
            $$specs{'error'} =
              "Cannot produce a proof that is $width x $height on a proofer that is $equip_width x $equip_height. Please change the size of the proof to fit.";
            return 'uncalculated';
        }

        # Non-per proof pricing is in square feet (our area in in inches).
        if ($proof_totals{$type}{units} ne 'Per Proof') {
            $price *= $width * $height / (12*12);
        }

        $price = ceil($price);

        $specs->{"txtProofUnitPrice-$1"} = sprintf('%.2f', $price);

#            if (($price eq 0) && ($quantity ne 0)) {
#                #we have a zero price for one of our line items so something is wrong and we need to pop up the proofs page
#                #or we have a scanning (or other) proof that hasn't had a type chosen yet
#                $status = 'uncalculated'; #we return from here to prevent a total price from being inserted
#            } We'll leave this section out for now since we don't want to pop up the proofs page in general on a blank line
        my ($scanning_proof) =
          sql::sql_statement(
            $log,
            $dbh,
            "select count(*) from tbl_service_specifications where lngprojectindex='$pid' and strname='NewScanningProof' and strvalue='Yes'"
          );
        if ($scanning_proof && $price eq 0) {
            $status = 'uncalculated';
            sql::sql_statement(
                $log,
                $dbh,
                "delete from tbl_service_specifications where lngprojectindex='$pid' and strname='NewScanningProof'"
            );
        }
        $totalPrice += $price * $quantity;
    }
    
    # break out here so that we don't have a total price and we are
    # uncalculated in external calc
    return $status if $status eq 'uncalculated';

    foreach my $key (keys(%$specs)) {
        if ($key =~ /txtProofQuantity-(.*)/) {
            $$specs{ 'txtProofUnitPrice' . $1 } =
              sprintf('%.2f', $totalPrice / $totalQuantity)
              if ($totalQuantity > 0)
              ;    #added the if for robustness - was crashing system - Duke
        }
    }
    my $minCharge =
      eprint::service::get_price($log, $dbh, $variable, 'ProofsMinimumCharge',
                                 undef, undef) || 0;
    if ($totalPrice < $minCharge and $totalQuantity) {
        $totalPrice = $minCharge;

        foreach my $key (keys(%$specs)) {
            if ($key =~ /txtProofQuantity-(.*)/) {
                $$specs{ 'txtProofUnitPrice' . $1 } =
                  sprintf('%.2f', $totalPrice / $totalQuantity);
            }
        }

    }

    my $price = format_pricing($totalPrice);

    my @qty = (undef, get_quantities($log, $dbh, $pid));
    for my $i (1..3) {
        next unless $qty[$i] && $qty[$i] > 0;

        $specs->{"txtPrice$i"} = $price;
    }
    $specs->{txtPrice} = $price;

    return $status;
}

sub delete_proofs {
    my ($log, $dbh, $sid) = @_;

    # HERE we delete all of our previous proof information.
	# Because we are being called from fill_from_printing
	# we set them to NULL rather than deleting them so that they
	# will overwrite the entries in the original specs hash.
    return $dbh->do(q{
        UPDATE tbl_service_specifications 
		SET strvalue = NULL
        WHERE lngserviceindex = ? 
          AND (  strname ~* '^txtProof(Quantity|Width|Height|Area|Price|UnitPrice)'
              OR strname ~ 'ddmProofType' )
    }, undef, $sid);
}

sub insert_proof_defaults {
    my ($log, $dbh, $pid, $sid, $i) = @_;

    my @scans;
    for my $id (check_for_service($log, $dbh, $pid, 'Scanning')) {
        my $need_proof 
            = get_specifications($log, $dbh, undef, $id, 'rdbRandomProof');
        
        push @scans, $id if $need_proof eq 'Yes';
    }

    if (grep { $_ == $i } @scans) {
        insert_scanning_proof($log, $dbh, $pid, $sid, $i, 1);
    }
    else {
        insert_colour_proof($log, $dbh, $pid, $sid, $i, 1);
        insert_layout_proof($log, $dbh, $pid, $sid, $i, 2, 3);
    }
}


sub insert_scanning_proof {
    my ($log, $dbh, $pid, $sid, $scanning_service_index, $proof_index,
        $signature_index)
      = @_;
    my ($qty, $width, $height) =
      eprint::service::get_specifications($log, $dbh, undef,
                    $scanning_service_index, 'txtQuantity', 'txtScanWidthFinal',
                    'txtScanHeightFinal');
    $_ =
      "select strvalue from tbl_service_specifications where lngprojectindex='$pid' and strname='ddmProofType-$signature_index-$proof_index'";
    my ($scanning_proof_type) = sql::sql_statement($log, $dbh, $_);
    $scanning_proof_type = undef unless $scanning_proof_type;
    insert_new_proof($log, $dbh, $pid, $sid, $proof_index, $signature_index,
                     $qty, $width, $height, $scanning_proof_type)
      ;    #we're giving index 0, since we need one
}

sub insert_colour_proof {
	my ($log, $dbh, $pid, $sid, $sig_sid, $proof_index) = @_;

	# Get everything we will need from the priting(Signature) service.
	my ( $signature_quantity, 
	     $spread_quantity,    $runStyle, 
		 $s0_process,         $s1_process,
		 $width,			  $height,
		 $press,			  $side_link
	) = eprint::service::get_specifications( $log, $dbh, undef, $sig_sid,
		 'txtSignatureQuantity',
		 'spreads_in_group',  'runstyle', 
		 's0_process',        's1_process',
		 'flat_width',		  'flat_height',
		 'hdnPress', 		  'side_link'
	);

	$signature_quantity = 1 unless $signature_quantity;
	$spread_quantity    = 1 unless $spread_quantity;

	my $book_sid = eprint::project::get_print_container($log, $dbh, $pid);
	if ( !$width && !$height  ) {
		( $width, $height ) = eprint::service::get_specifications(
            $log, $dbh, undef, $book_sid, 'flat_width', 'flat_height');
	}
	return "Bad Width: $width or Height: $height" unless $width and $height;


	# We will only insert a colour proof if our job requires process colour.
	return unless $s0_process || $s1_process;

	# Our Default Proof Type/Style Comes from the Press we printed on.
	my ( $proof_style ) = eprint::equipment::get_specification(
        $log, $dbh, 'Colour Proof Style', '', $press
    );

	my ( $proof_type ) = eprint::equipment::get_specification(
        $log, $dbh, 'Default Colour Proof', '', $press
    );
    #remove spaces when looking up in the service table
	$proof_type =~ s/\s//g;

	my $proof_type_si;

    # Make sure we are given a valid proof type.
	( $proof_type, $proof_type_si ) = $dbh->selectrow_array(q{
		SELECT strID, lngindex FROM tbl_Services WHERE strID = ?
	}, undef, $proof_type);

	return "Bad Proof Type: $proof_type" unless $proof_type;



	# Passed all the checks, now figure how we want to layout our
	# colours proofs for this signature

	# If we have Process on bothe Sides then Add proofs for both sides.
	if ( $s0_process and $s1_process || $side_link ) {
		$spread_quantity *= 2;
	} # end if


	# The number of proofs we need is the number of spreads times the
	# number of signatures in our signature group.
	# i.e 3 x 16 Page Signature( 4 spreads) 4/4 = 3 * 4 * 2 = 24 proofs.
	my $proof_qty = $spread_quantity * $signature_quantity;



	if ($proof_style eq 'Multiple') {
		# Select the first proofer sorted by strid that has pricing
		# for our Proof Type to get our Max size from.
		my ($proofer_id) = $dbh->selectrow_array(q{
			SELECT strId FROM tbl_equipment WHERE lngIndex IN (
				SELECT distinct lngequipmentindex FROM tbl_service_prices 
					WHERE lngserviceindex = ?  
			) ORDER by strId
		}, undef, $proof_type_si);

		# Get max size for the proofer.
    	my ( $maxwidth, $maxheight ) = eprint::equipment::get_specifications(
        	$log, $dbh, $proofer_id, 'Maximum Sheet Width', 'Maximum Sheet Length',
    	);


		# If our Proof Style is multiple then increase our
		# proof size until we have everything down to 1 proof
		# or we have hit the max size for the proofer.
		my $w = $width;
		my $h =	$height;
		my $q = $proof_qty;
		my $x = $q % 2;

		# Keep going checking quantity and with/height or
		# rotated with/height against our max dimensions
		while ( $q > 1 &&  $x == 0 &&  ( 
				   ($h <= $maxheight && $w <= $maxwidth)
				or ($w <= $maxheight && $h <= $maxwidth)
			  )) {

			# Store the current valid sizes.
			$width = $w;
			$height = $h; 
			$proof_qty = $q; 
			# Make a squareish proof by increasing the smaller side each time.  
			if ( $w < $h ) { $w *= 2; } else { $h *= 2 }

			# Right now we are only handling multiples of 2.
			# So unless our $qty can be diveded evenly by 2 then we must
			# stop.
 			$x = $q % 2;

			# Cut the quantity of proofs in half cause we have double the
			# size of the proof
			$q /= 2;
		}
        
	}

	# Add the new colour proof for this signature.
	insert_new_proof( $log, $dbh, $pid, $sid, $proof_index, 
					  $sig_sid, $proof_qty, $width, $height, $proof_type );
	return;
}

sub insert_layout_proof {
    my ($log, $dbh, $pid, $sid, $signature_service_index, $proof_index,
        $folding_proof_index)
      = @_;

    my ($signature_quantity, $runStyle) =
      	eprint::service::get_specifications($log, $dbh, undef, 
	  		$signature_service_index, 
			 'txtSignatureQuantity',
             'runstyle', 
	  	);

	# Bad you say? Yes it is.
	# This is our quick and dirty way of checking to see if we are printing
	# a two sided project.
	my $sideTwoColours = $dbh->selectrow_array( q{
		SELECT count(*) FROM tbl_service_specifications 
		WHERE lngserviceindex = ?
		AND strName  ~ 's1_pms|s1_process|s1_black|side_link' 
		AND strvalue <> '';
	}, undef, $signature_service_index);


    my ($press) =
      eprint::service::get_specifications($log, $dbh, undef,
                                          $signature_service_index, 'hdnPress');

    #2-sided dylux modifications
    my $sides_to_print =
      eprint::equipment::get_specification($log, $dbh, 'Layout Proof Sides',
                                           undef, $press) if $press;

    $sides_to_print = 1 unless ($sides_to_print == 2 && $sideTwoColours);

	#if we don't have an explicit 2-sided, we print 1-sided
    #if there are only colours on the front, we print one sided no matter what
    $signature_quantity = 1 if $signature_quantity == 0;


    if ($runStyle eq 'SW' || $runStyle eq 'PF') {
        if ($sideTwoColours && $sides_to_print == 1) {
            $signature_quantity *= 2;
        }
    }

#multiply signatures by number of version for multi page multi version
    #need the book service id for the project. If there isn't one this isnt a multipage project
    my $bookid = eprint::project::get_service_index($log, $dbh, $pid, 'Book');
    if ($bookid) {
      #need the number of versions if there aren't more than one this function isn't needed
      my ($num_versions) = eprint::project::mp_versions($pid);
      $signature_quantity *= $num_versions if $num_versions > 1;
    }

    # Add layout Proof
    my $project_type = eprint::project::get_type($log, $dbh, $pid);
    my ($width, $height);
    if ($project_type eq 'ScreenItem') {
        ($width, $height) =
          eprint::service::get_specifications($log, $dbh, undef,
                       $signature_service_index, 'flat_width', 'flat_height');
    }
    else {
        ($width, $height) =
          eprint::service::get_specifications($log, $dbh, undef,
                                  $signature_service_index, 'hdnSheetSizeWidth',
                                  'hdnSheetSizeHeight');
    }

    my $default_proof_type =
          eprint::equipment::get_specification($log, $dbh,
                                               'Default Layout Proof',
                                               '', $press);
    if ($sides_to_print == 2) {
        my $two_sided_proof =
          eprint::equipment::get_specification($log, $dbh,
                                               '2 Sided Layout Proof',
                                               '', $press);

    	$default_proof_type = $two_sided_proof if $two_sided_proof ne '';
    }

	#remove spaces when looking up in the service table
    $default_proof_type =~ s/\s//g;  

    if ($default_proof_type) {
        insert_new_proof($log,                $dbh,
                         $pid,                $sid,
                         $proof_index,        $signature_service_index,
                         $signature_quantity, $width,
                         $height,             $default_proof_type);
    }

    # get the binder type for the project and determine if we're stitching or
    # perfectbinding. Then if we are, we're throw in the folding dylux.
    $_ =
      "select dblprice from tbl_service_prices where lngserviceindex=(select lngindex from tbl_services where strid='FoldingDylux') order by dblprice desc";
    my ($fd_price) = sql::sql_statement($log, $dbh, $_);
    my $bindery = get_bindery_type($log, $dbh, $pid);

    if (($fd_price > 0)
        && (   ($bindery eq 'SaddleStitching')
            || ($bindery eq 'LoopStitching')
            || ($bindery eq 'PerfectBinding')))
    {

#insert a proof for layout folding, only if the appropriate service (FoldingDylux) is priced
        insert_new_proof($log,                 $dbh,
                         $pid,                 $sid,
                         $folding_proof_index, $signature_service_index,
                         $signature_quantity,  $width,
                         $height,              'FoldingDylux');
    }
}

sub insert_new_proof {
    my ($log,   $dbh, $pid,   $sid,    $proof_index,
        $index, $qty, $width, $height, $type
    ) = @_;

    eprint::service::insert_service_spec(
        $log, $dbh, $pid, $sid, "txtProofQuantity-$index-$proof_index", $qty);
    eprint::service::insert_service_spec(
        $log, $dbh, $pid, $sid, "txtProofWidth-$index-$proof_index", $width);
    eprint::service::insert_service_spec(
        $log, $dbh, $pid, $sid, "txtProofHeight-$index-$proof_index", $height);
    eprint::service::insert_service_spec(
        $log, $dbh, $pid, $sid, "ddmProofType-$index-$proof_index", $type);
    eprint::service::insert_service_spec(
        $log, $dbh, $pid, $sid, "txtProofArea-$index-$proof_index", $width * $height * $qty);
}


sub action {
    my ($log, $dbh, $pid, $sid, $service_type, $specs) = @_;

    # Now check to see if we need to add more proofs, and redirect back
    foreach my $key (keys %$specs) {
        next unless $key =~ /rdbAdditional-(.*)/
                 && $specs->{$key} eq 'Yes';

        my $sig = $1;
        my $proof_name = "txtProofQuantity-$sig";
        
        my $nop = $dbh->selectrow_array(q{
            SELECT MAX(strName) FROM tbl_service_specifications 
            WHERE lngserviceindex = ? AND strName ~ ?
        }, undef, $sid, $proof_name);
        
        next unless $nop =~ /txtProofQuantity-(.*)-(.*)/;

        my $proof_index = $2 + 1;
        insert_new_proof($log, $dbh, $pid, $sid, $proof_index, $sig, 1, '', '');
    }

    # TODO Redirect ... though it will automatically do that if it just stays
    # uncalculated...
}

sub display {
    my ($log, $dbh, $service_type, $pid, $sid, $specs) = @_;

    my %page;

    my @groups;
    for my $sig (get_signature_indices($log, $dbh, $pid)) {

        my %signature = ( sig => $sig );
        @signature{qw(description qty)} 
            = get_specifications($log, $dbh, undef, $sig, qw(
                txtServiceDescription txtSignatureQuantity
        ));

        $signature{proofs} = load_proof_info($log, $dbh,$sid, $sig);

        push @groups, \%signature;
    }

    $page{signatures} = \@groups;

    return \%page;
}

# Does everything needed to show the proofs page.
sub load_proof_info {
    my ($log, $dbh, $sid, $sig) = @_;

    my %proof_types = sql::sql_statement($log, $dbh, q{
        SELECT DISTINCT s.strid, s.strname 
        FROM tbl_service_types t, 
            tbl_services s        RIGHT JOIN 
            tbl_service_prices p  ON (s.lngindex = p.lngserviceindex) 
        WHERE s.lngtype = t.lngindex
         AND t.strid = 'Proofs'
    });
    
    my @proofnames = sql::sql_statement($log, $dbh, qq{
        SELECT strname 
        FROM tbl_Service_Specifications 
        WHERE lngServiceIndex = $sid
          AND strName LIKE 'txtProofQuantity-$sig%'
    });

    my @proof_indices = ();
    foreach my $index (sort @proofnames) {
        $index =~ /^txtProofQuantity-(\d*)-(\d*)/;
        push @proof_indices, $2;
    }

    my @proofs;
    foreach my $i (@proof_indices) {

        my %proof = ( id => $i );

        @proof{qw(qty width height type price)} 
            = get_specifications($log, $dbh, undef, $sid,
                 "txtProofQuantity-$sig-$i",
                 "txtProofWidth-$sig-$i",
                 "txtProofHeight-$sig-$i",
                 "ddmProofType-$sig-$i",
                 "txtProofUnitPrice-$sig-$i",
         );

        $proof{options} = make_drop_down(\%proof_types, $proof{type});

        push @proofs, \%proof;
    }
    return \@proofs;
}


1;
