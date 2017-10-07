# DESCRIPTION
#
#  Collate spiral bound projects ONLY!
#
# NOTE
# 
#  Collating identical single page collating makes about this -><- much
#  sense. Multi-page only makes sense on spiral projects (while perfect bound
#  books are also stacked signatures the perfect binder has pockets for
#  each). So until we offer an interface that let's the user specify the size
#  and calliper of (folded) sheet that goes in each pocket we don't handle it.
#
# TODO: When we finally estimate quantities seperately most of the project and
# equipment sections will have to fall into the competition loop.
#
# TODO: Factor out the common pattern of checking a condition then logging and
# denying the equipment from competing. The if () { log; next; } is ugly and
# hinders legibility.
#
package eprint::Service::Collating;
use strict;

use Apache2::Const    qw(:common);
use eprint::equipment    qw(get_units);
use eprint::service      qw(:common);
use eprint::project      qw(:common :multipage get_print_presses );
use eprint::Service::Spiral qw(SPIRAL TRIM);
use List::Util           qw(max sum);
use POSIX                qw(ceil);
use jsrs;
use callback;


# Determine if we need to collate this project.
sub necessary {
    my ($log, $dbh, $pid, $service_type) = @_;

	return 0 if has_no_bindery($log, $dbh, $pid);
    # If we're doing a spiral bound project with more than one folded
    # signature being bound (multiple cut-for-folding signatures can be on the
    # same press sheet) then we need to collate them before punching.
    my $type = get_bindery_type($log, $dbh, $pid);
	my $press_type = get_press_type( $log, $dbh, $pid );
    
    # Remember to not count the slip sheet that's always added.
    return 1 if  grep { $type eq $_ } SPIRAL
             and sum( map { $_->{qty} } pockets($log, $dbh, $pid) ) - 1 > 1
			 and $press_type ne 'digital';

    # In all other cases we don't apply.
    return 0;
}

# Calculates the cost of collating a spiral bound project. TODO: Strip some of
# this code out into subs, this is way too long.
sub calc {
    my ($log, $dbh, $var, $pid, $sid, $service_type, $specs) = @_;

    # PROJECT
    #
    my $project = project($log, $dbh, $pid);

    # We only handle spiral bound projects.
    die "Only spiral project types can be collated (PID: $pid Type: $project->{bindery})"
         unless grep { $project->{bindery} eq $_ } SPIRAL;
    
    # Collating no sheets or a single sheet is kind of silly.
    die "No valid signatures found for collating (PID: $pid)" 
        if $project->{pockets} <= 1;


    # EQUIPMENT
    #
    # Really these shouldn't be here but the get_price and get_units functions
    # are horribly ugly using \%variable to retrieve customer price list
    # information and other things, so we wrap them up into a bit cleaner.
    local *units = sub {
        my ($equip, $service) = @_;
        eprint::equipment::get_units($log, $dbh, $service, $equip, $var);
    };
    
    local *price = sub {
        my ($equip, $service, $qty) = @_;
        get_price($log, $dbh, $var, $service, $qty, $equip);
    };

    # See what equipment we have for the job.
    my @collators = map { collator($log, $dbh, $_) }
                    eprint::service::valid_equipment(undef, $dbh, 'Collating');

    # Can't collate without equipment.
    die "No equipment provides collating (PID: $pid)." unless @collators;


    # COSTING
    #
    # Retrieve the project quantities with the indices they use.
    my @qty; @qty[1..3] = get_quantities($log, $dbh, $pid);

    # As we allow users to override the quantity being processed as long as
    # it's within the total project quantity.
    for my $i (1..3) {
        $specs->{"txtQuantity$i"} =~ tr/0-9//cd;
        
        # If the bounds are okay we'll let then override.
        $qty[$i] = $specs->{"txtQuantity$i"}
            if  defined $qty[$i] 
            and defined $specs->{"txtQuantity$i"}
            and $specs->{"txtQuantity$i"} >= 0
            and $specs->{"txtQuantity$i"} <= $qty[$i];

        $specs->{"txtQuantity$i"} = $qty[$i];
    }
    
    
    # Running each quantity as a seperate project is a waste of resources at
    # present as the signature sizes are always the same. In the near future
    # though, we should have proper multi-quantity print estimating; meaning
    # imposition layouts/signatures could vary greatly by quantity.
    my @price;
    for my $i (1..3) {
        next unless $qty[$i] > 0;
        $log->debug("COLLATING: PROCESSING-$i Qty: $qty[$i]");

        # Currently there can only ever be one collating job in a project.
        my $job = {
            qty     => $qty[$i], 
            pockets => $project->{pockets},
            pid => $pid,
            sid => $sid,
        };

        # Let's race!
        my $best;
        foreach my $equip ( @collators ) {
            $log->debug("    COLLATING: Equipment: $equip->{ref} Type: $equip->{type}");

            # Make sure the current equipment can process the job.
            next unless fits($log, $project, $equip);
        
            # And the cost is...
            my $cost = job_cost($job, $equip);
            
            # If we get an unknown cost we're out of the running.
            unless (defined $cost) {
                $log->debug("        COLLATING: -SKIPPING- Can't calculate cost.");
                next;
            }
            $log->debug("        COLLATING: Cost: $cost");

            # If we're better than the previous, we're the best for this qty!
            $price[$i] = $cost
                if not defined $price[$i] or $cost < $price[$i];
        }

        # Zero is valid at this stage but undef isn't; set to error state.
        $price[$i] = 'NaN' if not defined $price[$i];
    }

    # The 'Not a Number' indicates an error so the project service should be
    # uncalculated if this is present. We go through all these hoops because
    # we allow positional estimates instead of a list of them.
    my $status = (grep {$_ eq 'NaN'} @price) ? 'uncalculated' : 'calculated';

    # Generate yucky pricing fields. Main price ceil()inged to nearest dollar.
    for my $i (1..3) {
        next unless $qty[$i] > 0;

        @$specs{"txtPrice$i", "txtUnitPrice$i"} 
            = format_pricing($price[$i], $qty[$i]);
    }
    
    return $status;
}


# An ADT of project information needed for spiral collating.
sub project {
    my ($log, $dbh, $pid) = @_;

    my %project = ( id => $pid );

    # We'll need the 'Print' container for basic project dimensions (Yes it
    # should be an attribute of the project table) and single-page signatures.
    my $print = get_print_container($log, $dbh, $pid);

	$project{press_type} = get_press_type($log, $dbh, $pid);
    
    # The final folded/bound project dimensions and bindery type.
    @project{ qw(width height bindery) } = get_specifications($log, $dbh, 
        $pid, $print, qw(final_width final_height template));

    # As we only handle spiral we'll take some short cuts. We'll use the
    # project size plus a trim as the pocket size (as we're processing folded
    # signatures).
    $project{width} += TRIM; $project{height} += TRIM;

    # Examine the project's signatures to get a list of what's filling our
    # pockets (calliper is especially important).
    my @pockets = pockets($log, $dbh, $pid, $project{press_type});

    # Save some aggregations for later use. For now we won't worry about
    # passing on the non-aggregate pocket information.
    $project{max_calliper} = max( map { $_->{calliper} } @pockets );
    $project{pockets}      = sum( map { $_->{qty}      } @pockets );

	$project{print_presses} = get_print_presses( $log, $dbh, $pid );

    $log->debug("COLLATING: Pockets: $project{pockets}");

    return \%project;
}


# Given a log, database handle, and the collator's ID, create an ADT
# representing a collator.
sub collator {
    my $log = shift;
    my $dbh = shift;
    my $id  = shift; # Equipment ID.

    # BASIC INFO
    #
    # General equipment information.
    my %collator = %{ $dbh->selectrow_hashref(q{
        SELECT lngindex    AS id,
               strid       AS ref,
               strname     AS name,
               strtype     AS type,
               strsupplier AS supplier 
        FROM tbl_equipment
        WHERE lngindex = ?
    }, undef, $id) };
    
    # Make the reference handy as that's how pricing is looked up.
    my $ref = $collator{ref};

    # EQUIPMENT SPECIFICATIONS
    # 
    # Get the standard sizing specs. (max/min height/width) and the number of
    # pockets (bins) the collator has.
    @collator{ qw( max_width    min_width 
                   max_length   min_length 
                   max_calliper 
                   pockets      run_speed) } =
        eprint::equipment::get_specifications($log, $dbh, $id,
            'Maximum Sheet Width',  'Minimum Sheet Width',
            'Maximum Sheet Length', 'Minimum Sheet Length',
            'Maximum Calliper',     
            'Pockets',              'Run Speed',
    );

    # COSTING
    #
    # As the 'Make Ready' and 'Minimum Charge' on any given collator don't
    # vary by quantity like 'Run' costs can. We initialise them directly here.
    $collator{cost}{make_ready}   = price($ref, 'CollatingMakeReady');
    $collator{cost}{pocket_setup} = price($ref, 'CollatingPocketMakeReady');
    $collator{cost}{min}          = price($ref, 'CollatingMinimumCharge');

    # Collating can be priced hourly varying with the number of pockets used
    # (more pockets generally means more employees feeding them). Or as sheet
    # count that's volume discounted (per 1000).
    $collator{cost}{unit} = units($ref, 'Collating');
    $collator{cost}{run}  = sub { price($ref, 'Collating', shift); };

    $collator{cost}{run} = $collator{cost}{min}
        if $collator{cost}{min} > $collator{cost}{run};

    return \%collator;
};


# Returns true if the given project can fit on the given equipment.
sub fits {
    my $log     = shift;
    my $project = shift; # Project dimensions.
    my $equip   = shift; # Equipment specs.

    # Manual collating is hand done and has no boundaries.
    return 1 if $equip->{type} eq 'manual';

	# For Digital if we can print, we can collate.
	# Check to see if this equipment printed any of the signatures.
	if ( $equip->{type} eq 'digital' ) {
		return 1 if grep { $equip->{ref} }  @$project{print_presses};
	}

    # Does the machine have enough pockets? Unlike stiching or perfect binding
    # we have to do this all in one go round.
    if ($project->{pockets} > $equip->{pockets}) {
        $log->debug("    COLLATING: -SKIPPING- Signatures ($project->{pockets}) exceed equipment pockets ($equip->{pockets})");
        return 0;
    }

    # Does our largest calliper pocket exceeed the equipment's pocket
    # calliper?
    if ($project->{max_calliper} > $equip->{max_calliper}) {
        $log->debug("        COLLATING: -SKIPPING- Calliper ($project->{max_calliper}) exceeds equipment max calliper ($equip->{max_calliper})");
        return 0;
    }

    # Make sure no pocket violates the pocket sizing. Unknown sizes are
    # considered invalid.
    unless ( $equip->{max_length} >= $project->{height}
         and $equip->{max_width}  >= $project->{width}
         and $equip->{min_length} <= $project->{height}
         and $equip->{min_width}  <= $project->{width}  )
     {
         $log->debug("        COLLATING: -SKIPPING- Project dimensions are outside the bounds of equipment's capabilities. PH:: $project->{height} PW: $project->{width} ");
         return 0;
     }

    $log->debug("        COLLATING: Machine - Pockets: $equip->{pockets}");
    return 1;
}


# Examine the given project's signatures to determine what's going into the
# collators pockets.
sub pockets {
    my ($log, $dbh, $pid, $press_type) = @_;

    # PREPARE SQL FOR SPREAD TYPES
    #
    # Interior spreads can have multiple layouts (not just n-up) on the same
    # press sheet. Get the size and quantity of signatures on each press sheet.
    my $interior = $dbh->prepare(q|
        SELECT substring(strname FROM '^txtSignatureQty([0-9]{1,2})Page$'), 
               strvalue 
        FROM tbl_service_specifications 
        WHERE strname ~ '^txtSignatureQty[0-9]{1,2}Page$' 
          AND length(strvalue) > 0
          AND lngprojectindex = ?
          AND lngserviceindex = ?
    |);

    # Gate folded spreads are basically two panel folds plus one or both ends
    # folded over. Find out which so we can determine folded calliper.
    my $gatefold = $dbh->prepare(q{
        SELECT substring(strname FROM '^txtSignatureQty(Single|Double)GateFolded$')
        FROM tbl_service_specifications
        WHERE strname ~ '^txtSignatureQty(Single|Double)GateFolded$'
          AND length(strvalue) > 0
          AND lngprojectindex = ?
          AND lngserviceindex = ?
    });

    
    # GROUPS
    #
    # Our groups of press sheets while called signatures really aren't.

    # Load up the pockets with the signatures in the groups.
    my @pockets;
    for my $id (check_for_service($log, $dbh, $pid, 'Printing')) {
        # Get the number of layouts in the group and sheet calliper.
        my ($type, $qty, $calliper) = get_specifications($log, $dbh, $pid, $id,
            qw(txtSignatureType txtSignatureQuantity txtStockCalliper));

        die "Invalid stock calliper for signature (PID: $pid SID: $id)"
            unless $calliper > 0;
        
        if ($type eq 'Interior Spreads') {
            # Interior spreads can have multiple layouts (not just n-up) on
            # the same press sheet. Get the size and quantity of signatures on
            # each press sheet.
            $interior->execute($pid, $id);
            my ($layout, $sigs); $interior->bind_columns(\$layout, \$sigs);
            
            # For every different layout determine the calliper after folding.
            # The quantity of the signatures takes grouping into account.
            push @pockets, {
                type     => $type,
                calliper => $layout / 2 * $calliper,
                qty      => $sigs,
                layout   => $layout,
            } while $interior->fetch;
        }
        elsif ($type eq 'Cover Spreads') {
            # Cover spreads count as two pockets as the "different cover"
            # option currently means both front and back. Which will be cut
            # into two seperate sheets before collating. TODO: We could get
            # fancy and unshift the front and back to where they'd be in the
            # actual pockets... ;)
            push @pockets, { type => $type, calliper => $calliper, qty => 2 };
        }
        elsif ($type eq 'GateFolded Spreads') {
            # Gate folded spreads have a calliper of three or four times their
            # sheet calliper depending on if they're double or single. Note: I
            # don't think we ever lay out multiple different gate folded
            # spreads on the same press sheet.
            my $fold = $dbh->selectrow_array($gatefold, undef, $pid, $id);

            # There's a know error of spread math being off and no gate fold
            # type being counted, we'll warn if this happens and just default
            # to the thickest.
            warn "Unknown gate fold ($fold)" if $fold ne 'Single' 
                                             or $fold ne 'Double';
            
            my $multiplier = ($fold eq 'Single') ? 3 : 4;
            
            push @pockets, {
                type     => $type,
                calliper => $calliper * $multiplier,
                qty      => ($qty || 1),
                layout   => $fold,
            };
        }
        else { warn "Unknown signature type ($type) encountered."; }
    }
    # And finally we need a pocket for the slip sheets that go between each
    # collated project. Slip sheets don't have a calliper as the printer will
    # always make sure they fit in whatever collater is used.
	# But now we will exempt Digital Projects from a Slip Sheet.
    push @pockets, { type => 'Slip Sheet', qty => 1 } if $press_type ne 'digital';
   
    return @pockets;
}

    
# Given a job (quantity and number of pockets) and the equipment to price it
# on, determine it's cost.
sub job_cost {
    my $job   = shift;          # The job details.
    my $equip = shift;          # Our equipment.
    my $cost  = $equip->{cost}; # Costing hash (run is a hash ref).

    my ($qty, $pockets) = @$job{qw(qty pockets)}; # Simple job, simple vars.
   
	use Data::Dumper;
	print STDERR "collating cost", Dumper($cost,$qty,$pockets);
    # Collators can be priced hourly varying with the number of pockets used
    # (more pockets generally means more employees feeding them). Or as sheet
    # count that's volume discounted (per 1000).
    
    # As always, we start with a machine make ready.
    my $total = 0;
    my $make_ready = $cost->{make_ready};

    # Add a pocket make ready unless we're doing hand collation.
    $make_ready += $pockets * $cost->{pocket_setup}
        unless $equip->{type} eq 'manual';

    # Get the run speed from the equipment unless we're doing per 1000 pricing.
    my $run_speed = ($cost->{unit} eq 'Per Hour') ? $equip->{run_speed} : 1000;
    return undef unless $run_speed > 0;
    
    # Total number of 'sheets' is the project quantity times the pockets used.
    my $sheets = ($qty * $pockets);

    # Per hour pricing varies with the number of pockets used (as more pockets
    # could mean more employees feeding them) while per 1000 pricing is just
    # volume discounted.
    my $rate = &{ $cost->{run} }(
        ($cost->{unit} eq 'Per Hour') ? $pockets : $sheets
    );
	print STDERR "collating rate: $rate \n";
    return undef unless $rate > 0;

    # The run pricing itself is simple.
    $total += $sheets / $run_speed * $rate;

    callback::call('service_calc_end', $job->{pid}, $job->{sid}, $make_ready, $total);
    $total += $make_ready;
 
    # The total is the greater of the computed vs. minimum cost.
    $total = ($total > $cost->{min}) ? $total : $cost->{min};
    
    return $total;
}


sub display {
	my ($log, $dbh, $service_type, $pid, $sid, $specs) = @_;

	my %page;
	
    my @qty       = (undef, get_quantities($log, $dbh, $pid));
    for my $i (1..3) {
        $page{"QUANTITY$i"}            = $qty[$i]; # Remove when possible.
        $page{"txtQuantity$i"}         = $qty[$i]; # Remove when possible.
    }

    # Display a pretty output of what signatures use what pockets. We'll sort
    # by signature type, then layouts (only interior spreads have these) then
    # quantity. Cover spreads are given a different name so the quantity isn't
    # misleading. TODO: Make really pretty by determining actual order, though
    # we don't have that information currently.
    my @pockets = map  { 
        $_->{type} = 'Front/Back Cover' if $_->{type} eq 'Cover Spreads'; $_ 
                } sort {
                     $a->{type} cmp $b->{type}
        or defined $a->{layout} <=> defined $b->{layout}
        or         $b->{layout} <=> $a->{layout}
        or            $a->{qty} <=> $b->{qty}
    } pockets($log, $dbh, $pid, get_press_type($log, $dbh, $pid));

	$page{pockets} = \@pockets;

    return \%page;
}


1;
