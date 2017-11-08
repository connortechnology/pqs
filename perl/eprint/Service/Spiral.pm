# DESCRIPTION
#
#  Punch and insert the spiral bindery tie.
#
# NOTE 
#   
#  We assume punching and actually inserting the binding are the same
#  operation. Also the  only concession we make to the different spiral
#  bindery types is a seperate material charge.
#
# TODO: We ignore the individual callipers of the pages completely. So while a
# printer would punch a heavy cover seperately from the book, we don't
# consider that.
#
# TODO: quantities() is a horrible kludge around our lack flow and
# dependencies.
#
package eprint::Service::Spiral;
use strict;
use warnings;
no warnings qw(uninitialized);

# TODO: Make this BEGIN block go away (ie. solve dep. issues).
BEGIN {
    # The spiral bindery types.
    use constant SPIRAL => qw(Cerlox DoubleLoopWire MetalCoil PlasticCoil Proclick);

    # Assumed trim for spiral bound projects (short cut).
    use constant TRIM => 1/8;
    
    use base qw(Exporter);
    our @EXPORT_OK = qw(SPIRAL TRIM);
}

use eprint::material ();
use eprint::project  qw(:common :multipage get_bindery_type get_finished_calliper);
use eprint::service  qw(:common);
use POSIX            qw(ceil);
use PQS::model::service;
use PQS::model::materials;

# Determine if any form of spiral binding is necessary for the project.
sub necessary {
    my ($log, $dbh, $pid, $service_type) = @_;

	return 0 if has_no_bindery($log, $dbh, $pid);

    # We're only ever needed if we're in a multi-page project with a spiral
    # bindery type.
    my $type = get_bindery_type($log, $dbh, $pid);
    return ($type eq $service_type and grep { $type eq $_ } SPIRAL) ? 1 : 0;
}


# Calculates the cost of collating a spiral bound project. TODO: Strip some of
# this code out into subs, this is way too long.
sub calc {
    my ($log, $dbh, $var, $pid, $sid, $service_type, $specs) = @_;
   
    # PROJECT
    #
    my $project = project($log, $dbh, $pid);

    # We only handle spiral bound projects.
    die "Only spiral project types can be punched (PID: $pid Type: $project->{bindery})"
         unless grep { $project->{bindery} eq $_ } SPIRAL;


    # EQUIPMENT
    #
    # Really this shouldn't be here but the get_price function is horribly
    # ugly using \%variable to retrieve customer price list information and
    # other things, so we wrap it up into a bit cleaner package.
    local *price = sub {
        my ($equip, $service, $qty) = @_;
        my $p = eprint::service::get_price($log, $dbh, $var, $service, $qty, $equip);
	    
        $log->debug("Pricing: $service qty: $qty eid: $equip = $p");
	
        return $p;
    };

    # See what equipment we have for the job.
    my @punches = map { punch($log, $dbh, $_, $project->{bindery}) }
                    eprint::service::valid_equipment(undef, $dbh, 'Punching', $pid);

    # Can't collate without equipment.
    die "No equipment provides punching (PID: $pid)." unless @punches;


    # COSTING
    #
    # Get the quantities from collating which we depend on, or the override.
    my @qty = quantities($log, $dbh, $pid, $specs);

    # Running each quantity as a seperate project is a waste of resources at
    # present as the signature sizes are always the same. In the near future
    # though, we should have proper multi-quantity print estimating; meaning
    # imposition layouts/signatures could vary greatly by quantity.
    my @price;
    for my $i (1..3) {
        next unless $qty[$i] > 0;
        $log->debug("PUNCHING: PROCESSING-$i Qty: $qty[$i]");

        # Currently there can only ever be one spiral job in a project.
        my $job = { 
            qty      => $qty[$i], 
            height   => $project->{height},
            calliper => $project->{calliper},
        };
        
        # Let's race!
        my $best;
        foreach my $equip ( @punches ) {
            $log->debug("    PUNCHING: EID: $equip->{id} Equipment: $equip->{ref}");
            
            # Does the project fit on the equipment?
            next unless fits($log, $project, $equip);

            # The material is looked up using the service type. All sizes of a
            # given bindery material are for some reason stored as the same
            # material and are differentiated by the project calliper. It may
            # be associated with the equipment as a poor way of determining a
            # supplier. TODO: Find a better spot for this.
            $job->{material} = eprint::material::get_price($log, $dbh, $var, 
                $project->{bindery}, $project->{calliper}, $equip->{ref}
            );

            $log->debug("  Material Price $job->{material} For $project->{bindery} Calliper $project->{calliper}  ");
			
            next unless $job->{material};

            
            # And the cost is...
            my $cost = job_cost($pid, $sid, $job, $equip, $project->{bindery} );
            
            # If we get an unknown cost we're out of the running.
            unless (defined $cost) {
                $log->debug("        PUNCHING: -SKIPPING- Can't calculate cost.");
                next;
            }
            $log->debug("        PUNCHING: Cost: $cost");

            # If we're better than the previous, we're the best for this qty!
            $price[$i] = $cost
                if not defined $price[$i] or $cost < $price[$i];
        }

        # Zero is valid at this stage but undef isn't; set to error state.
#        $price[$i] = 'NaN' if not defined $price[$i];
    }

    # The 'Not a Number' indicates an error so the project service should be
    # uncalculated if this is present. We go through all these hoops because
    # we allow positional estimates instead of a list of them.
    my $status = (grep {$_ eq 'NaN'} @price) ? 'uncalculated' : 'calculated';

    # Generate yucky pricing fields. Main price ceil()inged to nearest dollar.
    for my $i (1..3) {
        next unless $qty[$i] > 0;

        #record material usage estimate
        my $job = {
            qty      => $qty[$i],
            height   => $project->{height},
            calliper => $project->{calliper},
        };
#        my $mat = PQS::model::materials::material_by_strid($project->{bindary});
#        PQS::model::service::set_materials_estimate(get_material_usage($job, $project->{bindary}),undef, $sid, $mat->{lngindex}, $i);

        @$specs{"txtPrice$i", "txtUnitPrice$i"}
            = format_pricing($price[$i], $qty[$i]);
    }
    
    return $status;
}


# Given the project and it's specs determine the quantities we're processing and
# return them. This also has a side effect of setting the user override
# quantity. TODO: If you specify 1/2 the project gets collated then up it to
# 3/4 the spiral quantity will stay at the 1/2 (multiple reasons why).
sub quantities {
    my ($log, $dbh, $pid, $specs) = @_;

    my @qty; @qty[1..3] = get_quantities($log, $dbh, $pid);
    for my $i (1..3) {
        # If collating was needed, any user overrides in that will determine
        # for our maximum quantity. TODO: This is so stop gap, a generalised
        # flow and dependency system is needed.
        my $collating = check_for_service($log, $dbh, $pid, 'Collating');
        if ($collating) {
            # NOTE: Preserve list context while using get_specifications(). 
            ($qty[$i]) = get_specifications(
                    $log, $dbh, $pid, $collating, "txtQuantity$i");
        }
        
        # As we allow users to override the quantity being processed as long
        # as it's within the total project quantity.
        $specs->{"txtQuantity$i"} =~ tr/0-9//cd;
        
        $qty[$i] = $specs->{"txtQuantity$i"}
            if  defined $qty[$i] 
            and defined $specs->{"txtQuantity$i"}
            and $specs->{"txtQuantity$i"} >= 0
            and $specs->{"txtQuantity$i"} <= $qty[$i];

        $specs->{"txtQuantity$i"} = $qty[$i];
    }
    return @qty;
}


# Given a log, database handle, and the punch's ID, create an ADT
# representing a punch.
sub punch {
    my $log = shift;
    my $dbh = shift;
    my $id  = shift; # Equipment ID.
	my $bindery = shift; # Bindery Type

    # BASIC INFO
    #
    # General equipment information.
    my %punch = %{ $dbh->selectrow_hashref(q{
        SELECT lngindex    AS id,
               strid       AS ref,
               strname     AS name,
               strtype     AS type,
               strsupplier AS supplier 
        FROM tbl_equipment
        WHERE lngindex = ?
    }, undef, $id) };
    
    # Make the reference handy as that's how pricing is looked up.
    my $ref = $punch{ref};

    # EQUIPMENT SPECIFICATIONS
    # 
    # Get the standard sizing specs. (max/min height/width) and the number of
    # pockets (bins) the punch has.
    @punch{ qw( max_width min_width max_length min_length max_calliper) } =
        eprint::equipment::get_specifications($log, $dbh, $id,
            'Maximum Sheet Width',  'Minimum Sheet Width',
            'Maximum Sheet Length', 'Minimum Sheet Length',
            'Maximum Calliper',     
    );
    
    # COSTING
    #
    # As the 'Make Ready' and 'Minimum Charge' on any given punch don't
    # vary by quantity like 'Run' costs can. We initialise them directly here.
    $punch{cost}{make_ready} = price($ref, 'SpiralPunchingMakeReady');
    $punch{cost}{min}        = price($ref, 'SpiralPunchingMinimumCharge');

    # Spiral punching is priced per unit with an optional volume discount.
    $punch{cost}{run}  = sub { my $range = shift;
								price($ref, $bindery.'Punching', $range) +
							   	price($ref, $bindery.'Inserting', $range); };

    return \%punch;
};


# Returns true if the given project can fit on the given equipment.
sub fits {
    my $log     = shift;
    my $project = shift; # Project dimensions.
    my $equip   = shift; # Equipment specs.
   
    # Does our project exceed the punch's calliper.
    if ($project->{calliper} > $equip->{max_calliper}) {
        $log->debug("        PUNCHING: -SKIPPING- Calliper ($project->{calliper}) exceeds equipment max calliper ($equip->{max_calliper})");
        return 0;
    }

    # With punches our primary concern is that the length of the project
    # doesn't exceed the length of our punch (required).
    if ($project->{height} > $equip->{max_length}) {
        $log->debug("        PUNCHING: -SKIPPING- Project ($project->{height}) too long for punch.");
        return 0;
    }

    # Width isn't normally an axis we're concerned with, nor are min./max.
    # dimensions. As most users won't even fill those in, we'll only check
    # them if the specifications exist. TODO: Not just copy/paste.
    if (  (not defined $equip->{max_width}  or $project->{width}  >= $equip->{max_width})
      and (not defined $equip->{min_length} or $project->{height} <= $equip->{min_length})
      and (not defined $equip->{min_width}  or $project->{width}  <= $equip->{min_width}) )
    {
        $log->debug("        PUNCHING: -SKIPPING- Project dimensions are outside the bounds of equipment's capabilities.");
        return 0;
    }

    return 1;
}


# An ADT of project information needed for spiral punching.
sub project {
    my ($log, $dbh, $pid) = @_;

    my %project = ( id => $pid );

    # We'll need the 'Print' container for basic project dimensions (Yes it
    # should be an attribute of the project table) and single-page signatures.
    my $print = get_print_container($log, $dbh, $pid);
    
    # The final folded/bound project dimensions and bindery type.
    @project{ qw(width height bindery) } = get_specifications($log, $dbh, 
        $pid, $print, qw(final_width final_height template));

    # The finished project calliper.
    $project{calliper} = get_finished_calliper($log, $dbh, {}, $pid);

    return \%project;
}


# We're going with a brain dead simple model of costing for spiral punching.
# No matter the spiral type we're doing, we simply have a make ready and a
# volume discounted quantity based charge (per book not per thousand).
sub job_cost {
    my $pid   = shift;          # The project id.
    my $sid   = shift;          # The service id.
    my $job   = shift;          # The job details.
    my $equip = shift;          # Our equipment.
    my $type  = shift;          # Our equipment.
    my $cost  = $equip->{cost}; # Costing hash (run is a hash ref).

    # The run pricing itself is simple.
    my $total = $job->{qty} * &{ $cost->{run} }( $job->{qty} );

    callback::call('service_calc_end', $pid, $sid, \$total, \{$cost->{make_ready}});

    # a machine make ready.
    $total += $cost->{make_ready};

    # Bindery materials are charged per linear inch along the bound dimension,
    # different finished callipers are different materials/pricing.
    $total += get_material_usage($job, $type) * $job->{material};
    
    return undef unless $cost->{run};

    # The total is the greater of the computed vs. minimum cost.
    $total = ($total > $cost->{min}) ? $total : $cost->{min};
    
    return $total;
}

sub get_material_usage {
  my ($job, $type) = @_;
  return $type eq 'Proclick' ?  $job->{qty} : $job->{qty} * $job->{height};
}

sub display {};

1;
