# DESCRIPTION
#
#  As saddle stiching, loop stitching, and perfect binding are very similar in
#  terms of how we price their runs, they're all handled from here.
#  
# TODO
#  
#  - Clean this up, it's basically just a quick rework of the old perfect
#    binding module.
#  - Error handling is pathetically simple.
#  - Return proper error status when no pricing at all.
#  - See TODO comments throught module.
#  
package eprint::Service::Bind;
use strict;

use Apache2::Const qw(:common);
use eprint::project   qw(:common :multipage);
use eprint::service   qw(:common service_type);
use eprint::equipment ();
use sql               qw(:common);
use POSIX             qw(ceil);
use callback;
use PQS::model::materials;
use PQS::model::service;
use Data::Dumper;

# Is the supplied project service necessary for this project?
sub necessary { 
    my ($log, $dbh, $pid, $service_type) = @_;


    # We only handle multipage project.
#    return 0 unless is_multipage($log, $dbh, $pid);

#	return 0 if has_no_bindery($log, $dbh, $pid);

    
    # Bindery types are currently mutually exclusive (can't bind half the
    # project as one thing and half as another). We're only necessary if we're
    # the chosen template.
    return 1 if $service_type eq get_bindery_type($log, $dbh, $pid);
	return 1 if $service_type eq '3HolePunch' and get_template($log, $dbh, $pid) eq '3HolePunchBinder';
	return 1 if $service_type eq 'SingleHole' and get_template($log, $dbh, $pid) eq 'SingleHole';

print STDERR "BIND CHECK: $service_type \n";
    # Any other cases?


    return 0;
}


# The bohemoth. A legacy inspired all-in-one calculation function. Takes a
# specs hash but largely ignores it.
sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;
    my $status;

    die "Service type ($service_type) not handled by " . __PACKAGE__
        unless grep { $service_type eq $_ } 
                  qw( PerfectBinding SaddleStitching LoopStitching CornerStitching 3HolePunch FastBack SingleHole );
print STDERR "SERVICE: $service_type \n";

    # PROJECT INFORMATION
    #
    my %project = ( id => $pid );

    # We'll need the 'Print' container for basic project dimensions (Yes it
    # should be an attribute of the project table) and single-page signatures.
    my $print = get_print_container($log, $dbh, $pid);

    # The final folded/bound project dimensions.
    @project{ qw(width height) } = get_specifications($log, $dbh, 
        $pid, $print, qw(final_width final_height));
    $project{calliper} = get_finished_calliper($log, $dbh, {}, $pid);

    # SIGNATURES
    #
    my $sth = $dbh->prepare(q{
        SELECT c.lngserviceindex AS id, s.strname AS name, s.strvalue AS value
        FROM tbl_project_contents c, tbl_service_specifications s
        WHERE c.lngprojectindex = s.lngprojectindex
          AND c.lngserviceindex = s.lngserviceindex
          AND c.strservicetype = 'Printing'
          AND (s.strname LIKE 'txtSignatureQty%' 
            OR s.strname = 'txtSignatureType')
          AND c.lngprojectindex = ?
    });
    $sth->execute($pid);
    my ($id, $name, $value);
    $sth->bind_columns(\$id, \$name, \$value);

    # Initial aggregation into a hash of signatures groups.
    my %sig;
    while ($sth->fetch) {
        if ($name =~ /Type/) { $sig{$id}{type}   = $value; } 
        else                 { $sig{$id}{count} += $value; }
    }

    my @presses;
    # Count the number of cut signatures in each signature type.
    my %type;
    for my $id (keys %sig) {
        $type{ $sig{$id}{type} }  = 0 unless defined $type{ $sig{$id}{type} };
        $type{ $sig{$id}{type} } += $sig{$id}{count};
        push @presses, get_specifications($log, $dbh, $pid, $id, 'press');
    }
  
    # POCKETS
    #
    # Interior and gate folded spreads.
    my $pockets = 0;
       $pockets += $type{'Interior Spreads'} || 1;

    # The way we've handled gate folded spreads to be bound is pretty broken.
    # And it's going to stay that way for a while yet.
    my $gate_folded_spreads   = $type{'GateFolded Spreads'} || 0;
    my $gate_folds_are_exact_fit = $specs->{'rdbGateFoldFit'} eq 'Exact';

    # If the user has specified all their gate folded spreads are 'Exact'
    # fits, they'll be handled in a seperate run. Otherwise we can just treat
    # them as normal pockets.
    $pockets += $gate_folded_spreads unless $gate_folds_are_exact_fit;
    
    # Inserts are in the print container from the multi-page bindery page.
    $specs->{'txtInsertQuantity'} =~ tr/0-9//cd 
        if defined $specs->{txtInsertQuantity};

    my $inserts = get_specifications($log, $dbh, $pid,
        get_print_container($log, $dbh, $pid), 'txtInsertQuantity');

    if (defined $inserts and $inserts > 0) { $pockets += $inserts; }
    else                                   { $inserts  = 0;        }

    # If there's a cover spread the cover is different and may need a pocket
    # if the bindery machine doesn't provide one.
    my $has_cover = exists $type{'Cover Spreads'};

    # Complain if there's no cover and we're a perfect bound book.
    warn "No cover for perfect bound book (PID: $pid)." 
        if $service_type eq 'PerfectBinding' and not $has_cover;

    $log->debug("BIND: Pockets: $pockets Gate Folded: $gate_folded_spreads Exact Fit: $gate_folds_are_exact_fit Cover: $has_cover");
    
    # If we don't have any pockets filled, we have nothing to run.
    return 'uncalculated' unless $pockets > 0;

    
print STDERR "HAVE POCKETS: $pockets SERVICE TYPE: $service_type \n";
    # PRICE COMPETITION
    #
    # If there's no valid equipment we have a problem.
    #my @eids = valid_equipment($log, $dbh, $service_type, $pid) or return 'error';
    my @eids = valid_equipment($log, $dbh, $service_type, $pid);



print STDERR "EQUIPEMENT: ", Dumper(@eids);

    my %supplier;
    $supplier{$_->[0]} = $_->[1] for @{ $dbh->selectall_arrayref(qq{
        SELECT lngindex, strsupplier FROM tbl_equipment
    }, undef)};

    # Suppliers that printed at least one signature.
    my @print_suppliers = map($supplier{$_}, @presses);
    my @s_eids; # eids that match our printing supplier.
    my @o_eids; # eids that do not match printing supplier.

    my $print_presses = eprint::project::get_print_presses($log, $dbh, $pid);
    my $project_pockets = $pockets;

    EQUIPMENT:
    foreach my $eid (@eids) {
        my $type = eprint::equipment::get_type( $log, $dbh, $eid);

        if ( $type eq 'digital' ) {
            my $max_calliper = eprint::equipment::get_specification( 
                        $log, $dbh, 'Maximum Stitching Calliper', undef, $eid);

			print STDERR "Equipment Max: $max_calliper Project: $project{calliper} \n";
            next EQUIPMENT if $project{calliper} > $max_calliper && $service_type ne '3HolePunch' && $service_type ne 'SingleHole';
print STDERR "Print Presses: @$print_presses \n";

            if ( grep {$eid eq $_} @$print_presses ) { 
                push @s_eids, $eid 
            } 
            # Only allow digital bindery if we are printing on press.
            elsif ( $service_type eq '3HolePunch' || $service_type eq 'SingleHole' ) {
                 push @o_eids, $eid;
            }

        } 
            # Make sure the equipment can run a job this size.
        elsif (eprint::equipment::equipment_fits(
                $log, $dbh, $eid, @project{qw(width height calliper)}, 0) ) 
        {
			print STDERR "EQUIPMENT $eid FITS, Time to push\n";
            if ( grep /$supplier{$eid}/,  @print_suppliers ) {
                push @s_eids, $eid;
            } else {
                push @o_eids, $eid;
            }
        }
    }

    @eids = @s_eids ? @s_eids : @o_eids;

print STDERR "HAVE EQUIPMENT: @eids : @s_eids : @o_eids \n";
    
    # Default project quantities to use if custom ones aren't defined.
    my @qty = (undef, get_quantities($log, $dbh, $pid));
    
    my @prices;
    foreach my $n ( 1 .. 3 ) {
print STDERR "START PRICE FOR QTY: $n \n";
        next unless $qty[$n] > 0; # Skip empty estimates.

        # PROJECT QUANTITY
        #
        # We accept user quantities as long as they're positive non-zero
        # integers not greater than the total project quantity.
        my $qty = int($specs->{"txtQuantity$n"});
        
        # Reset the quantity to the project quantity if out of those bounds.
        $qty = $specs->{"txtQuantity$n"} = $qty[$n]
            if ($qty <= 0 or $qty > $qty[$n]);

        $log->debug("BIND: PROCESSING QUANTITY($n): $qty E: @eids");

        $specs->{error} = 'There is no equipment to handle your job.';
        
print STDERR "START PRICING FOR EQUIPMENT: @eids \n";

        # EQUIPMENT COMPETITION FOR QUANTITY
        #
        my %best;
        foreach my $eid (@eids) {
print STDERR "START Pricing for: $eid \n";
            my $type = eprint::equipment::get_type( $log, $dbh, $eid);

            # We have equipment for the job so remove the error.
            delete $specs->{error};

            # Total number of pockets the machine has.
            my $max_pockets = eprint::equipment::get_specification($log, $dbh, 'Number of Pockets', undef, $eid);
			$max_pockets = 500 if $type eq 'manual';

            # Perfect binders always have a seperate cover pocket, sticther
            # need to be checked.
            my $cover_pocket = ($service_type ne 'PerfectBinding') 
                ? eprint::equipment::get_specification($log, $dbh, 'Cover Pocket', undef, $eid) eq 'Y'
                : 1;
            
            $log->debug("        BIND: Max Pockets: $max_pockets Cover Pocket: $cover_pocket TYPe: $type");
            
            next unless $type eq 'digital' or (defined $max_pockets and $max_pockets > 1);
            

            # RETRIEVE PRICING
            # 
            my $make_ready      = get_price($log, $dbh, $variable, "${service_type}MakeReady",       undef, $eid) || 0;
            my $pocket_setup    = get_price($log, $dbh, $variable, "${service_type}PocketMakeReady", undef, $eid) || 0;
            my $insert_charge   = get_price($log, $dbh, $variable, "${service_type}Insert",          undef, $eid) || 0;
            my $minimum_charge  = get_price($log, $dbh, $variable, "${service_type}MinimumCharge",   undef, $eid) || 0;


            $log->debug("        BIND: MR: $make_ready Pocket MR: $pocket_setup Insert Premium: $insert_charge Min. Charge: $minimum_charge");
            
            # As we may be needing multiple run prices (for multiple runs)
            # create a closure that gives the cost of a run given the number
            # of pockets used in that run (pricing units taken into account).
            # TODO: We may want to move this closure out of the loop or even
            # into it's own named subroutine.
            local *run_price = sub {
                my $pockets = shift; # Number of pockets used.

                my $speed;
                
                # Does this equipment price by hour or per 1000? If no units
                # we assume per 1000.
                my $units = eprint::equipment::get_units( $log, $dbh,
                    $service_type, $eid, $variable
                );
               
                # Unit per hour.
                if ($units eq 'Per Hour') {
                    $speed = eprint::equipment::get_specification( $log, $dbh, 
                        'Run Speed', $pockets, $eid
                    );
                }
                # Per thousand.
                else { $speed = 1000; }

                # Complain if we don't have a valid speed.
                die "Invalid run speed ($speed) for equipment ($eid).\n" 
                    unless $speed;
                #Some services need to be priced as other depending on options
                $service_type = 'SaddleStitchingNoStaple' if $service_type eq 'SaddleStitching' && $specs->{UseStaples} eq 'n';

                # The price per $speed of a run.
                my $rate = get_price( $log, $dbh, $variable, 
                    $service_type, $pockets, $eid
                );

                #double the rate for flush fold out
                my ($flush_fold) = $dbh->selectrow_array("select strvalue from tbl_service_specifications where lngprojectindex = ? and strname = 'FlushFoldOut'", {}, $pid);
                $flush_fold  = $flush_fold ? 2 : 1;

                #returning service type to its original value after the price is calculated
                $service_type = 'SaddleStitching' if $service_type eq 'SaddleStitchingNoStaple';

                $log->debug("        BIND: Equip: $eid Pockets: $pockets Speed: $speed($units) Rate: $rate");
                
                # The price for the run.
                return $rate * ($qty / $speed) * $flush_fold;
            };


            # COSTING
            #
            my $price = 0;
            eval {
		$pockets = $project_pockets;
                $log->debug("BIND: make ready is: $make_ready");
                
                my $runs = 1;
                if ( $type ne 'digital' ) {
                    # If the cover is not part of the interior spreads and the
                    # equipment does not have a special pocket just for the cover,
                    # the cover must go in a normal pocket.
                    $pockets += 1 if $has_cover && ! $cover_pocket;

                    # Each signature (given the exception above) takes a pocket.
                    # If we have more pockets to be filled than we have pockets we
                    # need to run it through again. A 'pre-bound' block is created
                    # (smaller grind off and only a little glue in the first pass)
                    # then either hand fed or put through one of the pockets (we
                    # assume it's a pocket cost) with the remaining signatures.
                    $pockets += int($pockets / $max_pockets) if $pockets > $max_pockets;
                        
                    # Every pocket gets a make ready, including a seperate cover.
                    $price += $pocket_setup * ($pockets + $has_cover);
            
                    # Inserts are charged a premium per insert (extra make ready).
                    $price += $insert_charge * $inserts;
                    
                    # If we have multiple runs we charge seperately for each run
                    # filling as many pockets as possible per run. This may not be
                    # how it actually gets run, but it's how we charge.
                    $runs = ceil($pockets / $max_pockets);
                } elsif ( $service_type eq '3HolePunch' || $service_type eq 'SingleHole' ) {
					$qty *= $pockets;
				} 
                if ($runs > 1) {
                    $price += ($runs - 1) * run_price($max_pockets);
                    $price += run_price($pockets % $max_pockets);
                }
                # Otherwise just charge for the number of pockets.
                else {
                    $price += run_price($pockets);
                }
                
                # If we have any exact fit gate folded spreads it must be done
                # in a seperate run. We don't know the location they'll be put
                # in the book so we just assume we'll be doing a totally
                # seperate run of just the pre-bound block and the gate folded
                # spread. TODO: Isn't it too simplistic to just assume all the
                # exact fit gatefolds get at the end? TODO: There is no
                # parameter for this for perfect binding yet.
                if ($gate_folds_are_exact_fit and $gate_folded_spreads > 0 ) {
                    my $pockets = $gate_folded_spreads + 1;
                    
                    $price += $pocket_setup * $pockets;

                    my $runs = ceil($pockets / $max_pockets);
                    
                    if ($runs > 1) {
                        $price += ($runs - 1) * run_price($max_pockets);
                        $price += run_price($pockets % $max_pockets);
                    }
                    else {
                        $price += run_price($pockets);
                    }
                }
                callback::call('service_calc_end', $pid, $sid, \$make_ready, \$price);
                $price += $make_ready;
# Start binder size selection.
				my $need_binder = $dbh->selectrow_array(q{
					SELECT binder FROM cover_specs WHERE pid = ?
				}, undef, $pid);

				if ( $need_binder ) {
					my $cal = get_finished_calliper($log, $dbh, $variable, $pid);

					$specs->{ddmBinder} = $specs->{ddmBinder} ? $specs->{ddmBinder} :
										  $cal <= 0.48 ? 'Binder0.48'   :
										  $cal <= 0.72 ? 'Binder72'   :
										  $cal <= 0.96 ? 'Binder96'   :
										  $cal <= 1.32 ? 'Binder1.32'   :
										  $cal <= 1.8 ? 'Binder1.8'   :
										  $cal <= 2.208 ? 'Binder2.208'   
												: 'Binder3.744';
print STDERR "GETTING BINDER FOR CAL: $cal -- $specs->{ddmBinder} \n";
				}

				my $mat = $specs->{ddmBinder};
        if ($mat) {
          my $mat_price = eprint::material::get_price( $log, $dbh, $variable, $mat, $qty ); 
          my $material = PQS::model::materials::material_by_strid($mat) if $mat;
          PQS::model::service::set_material_estimate($qty, undef, $sid, $material->{lngindex}, $n) if $material;
          $price += $mat_price;
          print STDERR "HAVE PRICE: ", Dumper($price, $mat_price, $mat);
        }
				
                
                # If we're under the minimum charge, we become it.
                $price = $minimum_charge if $price < $minimum_charge;

                $specs->{'hdnRunSpeed'} = eprint::equipment::get_specification( $log, $dbh,
                        'Run Speed', $pockets, $eid
                );
                $specs->{"hdnRunTime$n"} = $qty / $specs->{hdnRunSpeed} if $specs->{hdnRunSpeed};
            };
            # Any errors during pricing zero the price and get logged.
            if ($@) {
                $log->error("BIND: Equipment ($eid) pricing failure for $service_type : $@");
                $price = 0;
            }

            $log->debug("        BIND: Qty: $qty Equipment: $eid Price: $price");
            
            # BEST PRICE?
            #
            # Choose the best price so far. TODO: If two prices are both the
            # min_charge, choose the equipment that has the lower price before
            # as that will be lower cost for the printer.
            if ($price > 0 and (not $best{price} or $best{price} > $price)) {
                @best{ qw(price equipment) } = ($price, $eid);
            }
        }
        
        # If we have a price from this run save the pricing and set the status
        # to 'calculated' unless it's specifically set to something else.
#        if ($best{price} && $best{price} > 0) {
        if ($best{price} ) {

			print STDERR "HAVE BEST PRICE: ", Dumper(\%best);

            @$specs{"txtPrice$n", "txtUnitPrice$n"}
                = format_pricing($best{price}, $qty);
            
            $specs->{"txtEquipment$n"} = $best{equipment};

            $status = 'calculated';
        }
        else { 
# We now allow zero pricing
            @$specs{"txtPrice$n", "txtUnitPrice$n"}
                = format_pricing($best{price}, $qty);
		    $status = 'calculated';
			#$status = 'uncalculated' unless $status eq 'error'; 
		}
        
    }
    # TODO: Final status should only be calculated the statuses for all
    # quantities was calculated.
    $log->debug("BIND: Final status: $status");
    
    return $status;
}

sub display {
    my ($log, $dbh, $service_type, $pid, $sid, $specs) = @_;
    
    my %page;

    # Needed for pricing dispaly.
    my @qty = (undef, get_quantities($log, $dbh, $pid));
    for my $i (1..3) {
        next unless $qty[$i] && $qty[$i] > 0;
        $page{"QUANTITY$i"} = $qty[$i];
    }

    # Get a list of the signature sizes in the project.
    my %signature;
    for my $sid (check_for_service( $log, $dbh, $pid, 'Printing') ) {
        my $sth = $dbh->prepare(qq{
            SELECT strName, strValue 
            FROM tbl_Service_Specifications 
            WHERE lngProjectIndex = ?
              AND lngServiceIndex = ?
              AND strName LIKE 'txtSignatureQty%'
        });
        $sth->execute($pid, $sid);

        my ($name, $value);
        $sth->bind_columns(\$name, \$value);
    
        while ($sth->fetch) {
            $name =~ /^txtSignatureQty(\w+)$/;
            $name = $1;

            if ($name =~ /(\d+)Page/) {
                $name = $1;
            }
            else {
                $name =~ s/\B([A-Z])/ \l$1/g;
                $name = lc $name;
            }

            $signature{$name} += $value;
        }
    }
    my @signatures;
    push @signatures, { n => $_, qty => $signature{$_} } for keys %signature;

    $page{signatures}     = [ sort { $a->{n} <=> $b->{n} } @signatures ];
    $page{insert_qty}     = $specs->{txtInsertQuantity};
    $page{gatefolded_qty} = ($signature{'single gate folded'} || 0) 
                          + ($signature{'double gate folded'} || 0);

    my $book = get_print_container($log, $dbh, $pid);

    $page{has_cover} 
        = get_specifications($log, $dbh, $pid, $book, 'rdbCover')
          eq 'DifferentCover';

	my $sql = qq{ SELECT strId, strName FROM tbl_Materials WHERE lngtype = 
					(SELECT id FROM material_type WHERE name = 'Binders') };

	$page{'ddmBinder'} = ssi::fill_drop_down($log, $dbh, $sql, $specs->{'ddmBinder'} );

    return \%page;
}

1;
