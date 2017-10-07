# DESCRIPTION
#
#  Calculate the cutting needs of a project.
#
#  The only external function needed should be internal_calc which can be
#  called to calculate the project cost and store it in it's appropriate
#  project service container.
#
# NOTES
#
#  As an intermediate step to stricter ADTs and/or objects, Class::Struct has
#  started to be used to define simple objects at run time. So far it's only
#  been used for 'Jobs'.
#
# TODO
#
#  * Multi-up folding consideration
#  * Single signature consideration for letterpress cutting (external code too)
#  * Revise the 'load every cutter at the start' caching to be more effecient.
#  * More sophisticated approach to choosing equipment for costing, failover
#  cases, and erroring.
#
#  - ADTs and/or objects for projects, signatures, and equipment/cutters
#  - Support for Dutch impositions and non-pow2 cutting.
#  - Make the project_cost(), compete(), project(), etc. general functions. 
#    Any service type can potentially use these.
#  - Deprecate necessary() as it's wasteful to determine all the jobs needed
#    for a boolean return, then create the service container, then call
#    interal_calc() which populates all the jobs again.
#  
package eprint::Service::Cutting;
use strict;
use warnings;
no warnings qw(uninitialized);

use Class::Struct;
use List::Util           qw(sum max);
use POSIX                qw(ceil);


use PQS::Imposition::Constants;

use eprint::project      qw(:common has_no_bindery get_finished_calliper);
use eprint::service      qw(:common);
use eprint::Service::Spiral qw(SPIRAL);
use eprint::Service::Printing::Constants qw(:press_types);
use callback;

# DEPRECATED: The only way to really determine if cutting is necessary is to
# see if any estimate quantity of the project needs _any_ jobs done. 
sub necessary {
    my ($log, $dbh, $pid) = @_;

	return 0 if has_no_bindery($log, $dbh, $pid);
    # Certain project eg. Envelopes never need to be cut. NOTE: This location
    # is redundant but it's worth it in speed and as a guard clause.
    my $type = get_type($log, $dbh, $pid);

    if (   grep({ $type eq $_ } qw(Envelopes Product ScreenItem InventoryCheckOut 
    				   ScreenTShirts ScreenHoodies ScreenSweatShirts 
				   ScreenMisc ScreenCoffeeMugs ScreenMousePads))
        || $type =~ /^LF/ ) {
        return (wantarray ? () : undef);
    };

    # Retrieve the project quantities with the indices they use (it can not be
    # treated as a list).
    my @qty; @qty[1..3] = get_quantities($log, $dbh, $pid);
    # Generate any jobs needed for each estimate.
    my @jobs;
    for my $i ( 1..3 ) {
        next unless $qty[$i] > 0;
        push @jobs, project_jobs( project($log, $dbh, $pid, $i) );
    }
    
    # If we have any then cutting is necessary.
    return scalar @jobs ? 1 : 0;
}


# Calculate the cutting needs and price of any given project and store the
# information in the appropriate project service. Do NOT call from JS.
sub calc {
    my ($log, $dbh, $var, $pid, $sid, $service_type, $specs) = @_; 

    # Retrieve the project quantities with the indices they use (it can not be
    # treated as a list).
    my @qty; @qty[1..3] = get_quantities($log, $dbh, $pid);

    die "Invalid project ($pid - $sid)" 
        unless $pid && $sid && int($qty[1]) > 0;

    # Really this shouldn't be here but the get_price function is horribly
    # ugly using \%variable to retrieve customer price list information and
    # other things, so we wrap it up into a bit neater package.
    local *price = sub {
        my ($equip, $service, $qty) = @_;
        get_price($log, $dbh, $var, $service, $qty, $equip);
    };
    
    # Running each quantity as a seperate project is a waste of resources at
    # present as the signature sizes are always the same. In the near future
    # though, we should have proper multi-quantity print estimating; meaning
    # imposition layouts/signatures could vary greatly by quantity.
    my @price;
    for my $i (1..3) {
        next unless $qty[$i] > 0;

        # Get the project information for the current estimate quantity.
        my $project = project($log, $dbh, $pid, $i);

        # The jobs needed for the project.
        my @jobs = project_jobs($project);

        # We shouldn't even be here if there are no jobs for us to do.
        unless (@jobs) { $price[$i] = 'NaN'; next; }
       
        # Cost the project (for the given user).
        $price[$i] = project_cost($dbh, $pid, $sid, @jobs);

        # Zero is valid at this stage but undef isn't; set to error state.
        $price[$i] = 'NaN' if not defined $price[$i];
    }

    # A negative estimate indicates an error case, the service type status
    # should be uncalculated if this is present.

# Allow products to be zero priced.
#    return 'error' if grep {$_ eq 'NaN'} @price;

    # Insert legacy pricing fields. Main price ceil()inged to nearest dollar.
    for my $i (1..3) {
        next unless $qty[$i] > 0;

        @{$specs}{"txtPrice$i", "txtUnitPrice$i"}
            = format_pricing($price[$i], $qty[$i]);
    }

    return 'calculated';
}


# We're going to start with a very simple costing algorithm. Basically we load
# all the cutters in inventory into memory and let the ones from the same
# supplier as the print compete for each job and sum the winners.
sub project_cost {
    my ($dbh, $pid, $sid, @jobs) = @_;

    # Load all the cutters in inventory. For now we'll just load them all
    # everytime.
    my @cutters = map { cutter($dbh, $_) }
                      eprint::service::valid_equipment(undef, $dbh, 'Cutting', $pid);

    # Each job is to competed for by all the cutters that are valid. Valid is
    # currently defined as being of the same supplier as the press that
    # printed the sheet. Or 'House' if no supplier is known/bound project.
    my @winners;
    foreach my $j ( @jobs ) {
        my @competitors; # The cutters competing in this race (job).

        $j->{pid} = $pid;
        $j->{sid} = $sid;

        # The initial competition is limited to runners (cutters) in the same
        # class (supplier) as the race (job), excluding 'House' league.
        @competitors = compete($j, grep { $_->{supplier} ne 'House' 
                                      and $_->{supplier} eq $j->supplier } @cutters 
        ) if $j->supplier ne 'House';

        # Our house league can now play. Also if we didn't have any valid
        # entries in the supplier race, it's now open to house.
        @competitors = compete($j, grep {$_->{supplier} eq 'House'} @cutters)
            if $j->supplier eq 'House' or not @competitors;

        # Neither supplier or house can handle it? Open it to everyone.
        if ( not @competitors ) {
            # We'll eliminate those who've already been disqualified.
            @cutters = grep { $_->{supplier} ne $j->supplier 
                          and $_->{supplier} ne 'House'      }
                              @cutters;
            
            @competitors = compete($j, @cutters);

            # No one at all? Alright, this race is a complete failure.
            return undef unless @competitors
        }
        
        # Let the best cutter WIN!
        push @winners, (sort { $a->{cost} <=> $b->{cost} } @competitors)[0];
    }

    # No one can win by default, at least one person has to finish each race.
    return undef unless scalar @jobs == grep { $_->{cost} } @winners;
    
    # The final project cost is the sum of each job's 'winner'.
    my $total = 0; $total += $_->{cost} for @winners;

    # The caller may want the entire winners circle or just the final results.
    return wantarray ? ($total, @winners) : $total;
}


# With a job and a list of cutters, find all those who can compete for that
# job and the cost they come out with.
sub compete {
    my $job     = shift; # The job in question.
    my @cutters = @_;    # The racers.
    my @competitors;     # Non-disqualified racers (after race).

    # Let's race!
    foreach my $equip ( @cutters ) {
        # Can the cutter cut it? (pun intended).
        next unless fits($job, $equip);

        # And the runner's cost is...
        my $cost = job_cost($job, $equip);

        # If they finished, they're a valid competitor (zero is a valid cost).
        push @competitors, {
            job       => $job, 
            equipment => $equip,
            cost      => $cost,
        } if defined $cost and $cost >= 0;
    }

    return @competitors;
}

# Determines if the job can fit on the given equipment.
sub fits {
    my $job   = shift; # The job.
    my $equip = shift; # The equipment to test it on.
    
    # Well, we do a shitty job of this. As we don't track orientation and where
    # the cuts phyically are we don't know if any one cut will be over the
    # cutter's capabilities. So we just blindly assume that it will work as
    # long as either dimension is smaller than the blade length. We define the
    # blade length as the greater of two max. width/height specs. (I told you
    # it was shitty).
    my $blade_length = max($equip->{max_length}, $equip->{max_width});

    # No blade length means we can do ANYTHING! Muhaha!
    return 1 unless defined $blade_length;

    # We just blindly assume that it will work as long as one dimension is
    # smaller than the blade length.
    return 0 
        unless $job->height < $blade_length or $job->width < $blade_length;

    # Check lift depth vs. job calliper.

    return 1;
}


# Choosing equipment. When building a list of cutter... if any cutters have
# the same supplier as the press, we only look at them. If not we only look at
# in house. If neither exist we find any in the equipment inventory. Failing
# that complain violently.
#
# While this may not actually be the most cost effictive, given transportation
# charges it probably will be. The final rationale for this is it's a business
# decision.


# If none of the cutters at the current supplier chosen by valid equipment can
# handle the job, we open the competition to any cutter in the inventory: For
# now we ignore any transportation charges this might incur. This probably
# won't occur in the 'real world'. Eventually we should probably to either add
# transport charges or limit the stock a supplier can use by their max cutter
# dimensions?

# sub project_cost {
# 
#     # We sort the jobs by supplier so we don't have to load/cache supplier
#     # equipment multiple times. 'House' and unknown jobs are handled last as
#     # any jobs that fail (specs. not met) are pushed to the bottom of the
#     # stack and given a second chance on house equipment.
#     my @jobs = sort { return -1 if $a->{supplier} eq 'House';
#                       return -1 if not defined $a->{supplier};
#                       return $a->{supplier} cmp $b->{supplier} 
#                     } project_jobs($project);
#     
#     return $total;
# }





# EQUIPMENT
#
#   my %cutter = (
#       id         => int,         # Equipment ID.
#
#       lift_depth => sub ($) { }, # Takes a calliper and returns a float lift
#                                  # depth. Cutting thick stacks of thin stock
#                                  # can shift and tear it.
#       cost       => cost,
#   );
#   
#   my %cost = (
#       make_ready => float,
#       min        => float,
#       run        => sub ($) { }, # Takes quantity returns float price.
#   );
  
# Given a database handle and the cutter's ID, instansiate the cutter instance.
sub cutter {
    my $dbh    = shift;
    my $id     = shift; # Equipment ID.

    # BASIC INFO
    #
    # General equipment information.
    my %cutter = %{ $dbh->selectrow_hashref(q{
        SELECT lngindex    AS id,
               strid       AS ref,
               strname     AS name,
               strsupplier AS supplier 
        FROM tbl_equipment
        WHERE lngindex = ?
    }, undef, $id) };

    # EQUIPMENT SPECIFICATIONS
    # 
    # Get the standard sizing specs. (max/min height/width).
    my $spec = $dbh->selectall_hashref(q{
        SELECT strname AS name, strvalue AS value
        FROM tbl_equipment_specifications
        WHERE lower(replace(strname, ' ', '')) IN ('maximumsheetlength', 'maximumsheetwidth')
          AND lngequipmentindex = ?
    }, 'name', undef, $id);
    $cutter{max_width}  = $spec->{'Maximum Sheet Width'}{value};
    $cutter{max_length} = $spec->{'Maximum Sheet Length'}{value};

    # Create a closure for determining the maximum lift depth based on the
    # stock calliper provided.
    $cutter{lift_depth} = sub {
        my $calliper = shift;
        my $sth = $dbh->prepare(q{
            SELECT strvalue
            FROM tbl_equipment_specifications
            WHERE strname = 'Maximum Lift Depth'
              AND lngequipmentindex = ?
              AND  ?::numeric >= coalesce(dblmin, 0)
              AND (?::numeric <= dblmax OR dblmax IS NULL)
        });
        return $dbh->selectrow_array($sth, undef, $id, $calliper, $calliper);
    };

    # COSTING
    #
    # As the 'Make Ready' and 'Minimum Charge' on any given cutter don't
    # vary by quantity like 'Run' costs can. We initialise them directly here.
    $cutter{cost}{make_ready} = price($id, 'CuttingMakeReady');
    $cutter{cost}{min}        = price($id, 'CuttingMinimumCharge');
    $cutter{cost}{stack}      = price($id, 'CuttingPerStack');

    # Cutting 'Run' costs vary by the number of 'Blade Drops' so we create
    # another closure to that takes that and returns a volume adjusted cost.
    $cutter{cost}{run} = sub { price($id, 'Cutting', shift); };

    return \%cutter;
}


# PROJECT
#
#   my %project = (
#       id  => int,
#       qty => int,
#       
#       width    => float, # |
#       height   => float, # |-Final project dimensions
#       calliper => float, # |
#      
#       type         => string, # Project type
#       is_multipage => bool,
#       bindery      => string, # Type of bindery (if applicable)
#       
#       signatures => [ signature ],
#   );
#   
#   my %signature = (
#       id          => int,      # Signature ID
#       orientation => string,   # 'Horizontal' or 'Vertical'
#       rows        => int || 1,
#       cols        => int || 1,
#       groups      => int || 1, # The number of signatures in the group.
#   
#       colour_bar => bool,
#       bleed      => [float, float, float, float], # Top, bottom, left, right.
#       stock      => stock,
#
#       supplier => string, # The print supplier (for matching equipment).
#   );
#   
#   my %stock = (
#       calliper => float,
#       supplied => { qty => [int], width => float, height => float, },
#       press    => { qty => [int], width => float, height => float, },
#   );

sub project {
    my $log = shift;
    my $dbh = shift;
    my $pid = shift; # Project ID
    my $i   = shift; # The 'Quantity Index' *sigh*

    # PROJECT INFORMATION
    #
    my %project = ( id => $pid, signatures => [] );

    # We'll need the 'Print' container for basic project dimensions (Yes it
    # should be an attribute of the project table) and single-page signatures.
    my $print = get_print_container($log, $dbh, $pid);

    # The project type and estimate quantity.
    $project{type}       = get_type($log, $dbh, $pid); 
    $project{press_type} = get_press_type($log, $dbh, $pid); 
    $project{qty}        = (get_quantities($log, $dbh, $pid))[$i-1];

    # The final flat project dimensions and bindery type.
    @project{ qw(width height bindery) } = get_specifications($log, $dbh, 
        $pid, $print, qw(flat_width flat_height template));
    $project{calliper} = get_finished_calliper($log, $dbh, {}, $pid);
    
    # Is the project type considered to be multi-page?
    $project{is_multipage} = is_multipage($log, $dbh, $pid);

    # SIGNATURES
    #
    # Multi-page project may have one or more signatures.
    my @signatures = check_for_service($log, $dbh, $pid, 'Printing');

    foreach my $id (@signatures) {
        my %sig = ( id => $id, bleed => [0,0,0,0] );

        # DATABASE SPECS
        #
        # Get the raws 'specs' from what we pass off as a relational database.
        my %spec = get_specifications_pairs($log, $dbh, $pid, $id, 
            # Basic signature info.
            qw( txtSignatureQuantity  hdnImageOrientation
                hdnImpositionRows     hdnImpositionColumns 
                txtServiceDescription ),

            # Bleed size and edges.
            qw( bleed_size bleed_sides colour_bar ),

            # Supplied and press stock.
            qw( hdnSuppliedStockWidth  hdnSuppliedStockHeight
                hdnSheetSizeWidth      hdnSheetSizeHeight
                txtStockCalliper ), "hdnGrossSheetCount$i",

            # Press equipment (string) ID, used to determine supplier.
            "hdnEquipment1",
            # Until we start doing 3Q estimating we are only using
            # hdnEquipment1.  For the press type.

            # Imposition
            'imp',
        );

        # IMPOSITION
        #
        # The imposition is stored as a frozen datastructure (passed through
        # JSRS hence the base 64 encoding). *sigh*
        $spec{imp} = get_imposition($dbh, $id);
        $sig{imp}  = $spec{imp};

        # BASIC
        #
        # If a datumn doesn't exist default it to one. Could map this, not
        # worth it.
        $sig{name}   = $spec{txtServiceDescription};
        $sig{rows}   = $spec{imp}{rows} || 1;
        $sig{cols}   = $spec{imp}{cols} || 1;
        $sig{groups} = $spec{txtSignatureQuantity} || 1;

        # The orientation should be either Horizontal or Vertical.
        $sig{orientation} = ( $spec{hdnImageOrientation} eq 'Horizontal' 
                           or $spec{hdnImageOrientation} eq 'Vertical'   )
                       ? $spec{hdnImageOrientation} : undef;

        # BLEED AND COLOUR BAR
        @{ $sig{bleed} }[$_] = $spec{bleed_size}
            for split(',', $spec{bleed_sides} );

        $sig{colour_bar} = ($spec{colour_bar} eq 'Yes');
        
        # STOCK
        #
        # The supplied stock is before any precutting (which may or may not be
        # needed). The press stock is the size that's actually run through.
        # Note: While we could do this with a mapping hash, this is easier.
        $sig{stock}{press}{width}     = $spec{hdnSheetSizeWidth};
        $sig{stock}{press}{height}    = $spec{hdnSheetSizeHeight};
        $sig{stock}{supplied}{width}  = $spec{hdnSuppliedStockWidth};
        $sig{stock}{supplied}{height} = $spec{hdnSuppliedStockHeight};
        $sig{stock}{calliper}         = $spec{txtStockCalliper};

        # Gross press quantity (including overage).
        $sig{stock}{press}{qty}    = $spec{"hdnGrossSheetCount$i"};
        $sig{stock}{supplied}{qty} = ceil( 
            $spec{"hdnGrossSheetCount$i"} / 
            (   ($spec{imp}{paper}{width_factor}  || 1)
              * ($spec{imp}{paper}{height_factor} || 1) )
        );


        # SUPPLIER
        #
        # We need to determine the supplier of the press as we give
        # preferential treatment to cutters from the same supplier.
        $sig{supplier} = $dbh->selectrow_array(q{
            SELECT strsupplier FROM tbl_equipment WHERE lngindex = ?
        }, undef, $spec{"hdnEquipment1"});
        # Currently hdnEquipment1 is the only field being used by the
        # printing services.

        
        push @{ $project{signatures} }, \%sig;
    }

    # TODO - We also need information about any die cutting or folding that
    # could occur before us as they can process things n-up (and die cutters
    # can do some normal cutting as well).

    return \%project;
}

sub get_imposition {
    my ($dbh, $sid) = @_;

    use Compress::LZF         qw(:compress :freeze);
    use Storable              qw(thaw);
    use MIME::Base64;
    use PQS::Imposition::Node;

    my $frozen = $dbh->selectrow_array(q{
        SELECT strvalue FROM tbl_service_specifications
        WHERE strname = 'imp' AND lngserviceindex = ?
    }, {}, $sid);
    return undef unless $frozen;

    my $imposition = sthaw(decode_base64($frozen));

    # Due to some persistant interpretter/mod_perl issue we need to 'prime'
    # the package before we can retrieve into it.
    my $tmp = PQS::Imposition::Node->new(cut => 0, size => [1,1]);
    undef $tmp;
   
    $imposition->{tree} = thaw($imposition->{tree}); # Frozen object.

    return $imposition;
}



# JOB
# 
struct Job => {
    signature => '$', # signature,  # Signature ID [optional]
    
    width     => '$', # float,      # |
    height    => '$', # float,      # |- Before cutting dimensions
    calliper  => '$', # float,      # |
    qty       => '$', # int,        # Quantity of sheets/bound projects

    supplier  => '$', # string,     # Supplier of the printed sheet

    cuts      => '$', # int         # Cuts per unit
    note      => '$', # text,       # Freeform text of the type of cut, etc.
};

# Given a project, determine the cutting jobs needed (qty, cuts, calliper).
sub project_jobs {
    my $project    = shift; # Overall project details (and signatures).
    my @jobs;               # The stack of cutting jobs.

    # Some very, very basic assertions.
    die "Invalid project reference."   unless ref $project eq 'HASH';
    die "Need at least one signature." unless @{$project->{signatures}};


    # UNCUTTABLE PROJECT TYPES
    #
    # Certain project eg. Envelopes never need to be cut.
    return (wantarray ? () : undef) if grep { $project->{type} eq $_ }
                       qw( Envelopes InkjetOutputs Product ScreenItem );

    # SIGNATURES
    # 
    for my $sig (@{ $project->{signatures} }) {
        my $stock = $sig->{stock}; # Signature stock info.

        # If a project has the same width and height as the press sheet it

        # shouldn't even be here.
        next if  $project->{width}  == $stock->{press}{width}
             and $project->{height} == $stock->{press}{height};

       
        # PRE-PRESS CUTTING
        #
        # Determine if we need to cut the stock down to fit on the press.
        if ($sig->{imp}{paper}{cuts} && $project->{press_type} ne WEB) {
            push @jobs, Job->new(
                signature => $sig, 
                width     => $stock->{supplied}{width},
                height    => $stock->{supplied}{height},
                supplier  => $sig->{supplier},
                qty       => $stock->{supplied}{qty},
                calliper  => $stock->{calliper},
                cuts      => $sig->{imp}{paper}{cuts},
                note      => 'Cutting to fit on press.',
            );
        }

        # If the user doesn't want any bindery, move on to the next signature.
        next if $project->{bindery} eq 'NoBindery';

        # The 'n-upness' of the page (for use in what were debugging notes and
        # are now user messages).
        my $n = $sig->{imp}{setup};

        # MULTI-PAGE
        #
        # If we're processing a signature on a letterpress we can use it
        # instead of a cutter to do certain cutting jobs. However as we don't
        # know what signature the letterpress is working on in a multipage job
        # we currently ignore it.
        # 
        # If the project is a multipage project, the only thing we may need to
        # do at the signature level is cut n-up sheets into 1-up. 
        if ( $project->{is_multipage} ) {
            # Don't worry about trimming, just do dead cuts if it's n-up.
            push @jobs, Job->new(
                signature => $sig, 
                width     => $stock->{press}{width},
                height    => $stock->{press}{height},
                supplier  => $sig->{supplier},
                qty       => $stock->{press}{qty} * $sig->{groups},
                calliper  => $stock->{calliper},
                cuts      => ( $sig->{rows}-1 + $sig->{cols}-1 ),
                note      => "Multipage $n-up dead cuts.",
            ) if $sig->{rows} > 1 or $sig->{cols} > 1;

            # TODO: We don't consider the extra cut if the sheet is layed out
            # something like this:
            #                         _____________
            #                        |       |     |
            #                        |  8pg  | 4pg |
            #                        |       |_____|
            #                        |_______|_____|
            #         

            # TODO: Spiral bound covers need to be cut into a front and back
            # even though they're laid up in four page spreads. This can be
            # combined with any n-up dead cuts.
            
            # Actually there is one other case. If the project is being spiral
            # bound and our current signature in an n-up signature that's
            # under an eight page signature in a multi-signature (or multiple
            # groups in this signature), we need to trim cut two edges. This
            # is so we always have a registration corner to line up for final
            # project cutting (after collation). NOTE: Maybe not actually...
            # if ( project->bindery eq spiral and ... )
            #     $jobs[-1]->cuts( $jobs[-1]->cuts + 2 );
            #
            
            next; # We're done at the signature level for multipage.
        }
        
        # SINGLE PAGE
        #
        # Single signature projects need cutting if they have any bleeds or 
        # colour bars, if they're n-up, or a combination of the two.
        # Additionally we'll always be working with the same stock quantity
        # and callipers.
        my $job = Job->new(
            signature => $sig,
            width     => $stock->{press}{width},
            height    => $stock->{press}{height},
            supplier  => $sig->{supplier},
            qty       => $stock->{press}{qty},
            calliper  => $stock->{calliper},
        );

        # When using a letterpress on a single page project we can do the trim
        # cutting using a die rule while we perform the other operations on
        # it. However we may need to do a few dead cuts first to get the sheet
        # size to the die imposition given. TODO: Dead cuts part is correct,
        # however we may not want to trim on the letterpress but instead trim
        # cut here afterwards, especially when the die is n-up.
        # if ( using_letterpress )  {
        #     next;
        # }
        
		# We now want to add Post Process cutting into Presentaiton Folders.
        #next if $project->{type} eq 'PresentationFolders';

        # If multi-up folding is involved, we need to cut the sheet into
        # trimmed strips (we only handle simple linear n-up folding).
        # Basically we get the bleeds/gutter between impositions for free.
        # if ( folding and fold_impostion > 1 ) {
        #     next;
        # }
        
        # All n-up non multi-sheet projects are now handled the same.
        if (my $cuts = cuts($sig->{imp})) {
            $job->note("Single sheet $n-up.");
            $job->cuts($cuts);
            push @jobs, $job;
        }
    }

    # BOUND PROJECT
    #
    # Cutting done on multiple signatures at once, or the entire project.
    if ( $project->{is_multipage} ) {
        # While we could do some special tricks for Padding layouts vs. the
        # number of cuts, we're just going to handle as an n-up single sheet
        # with full trim (handled in the signature section above).

        # Stitching types and Perfect Binding trim on during binding.
    
        # Spiral bindery however (Cerlox, Plastic Coil, etc.) is a special
        # case. The (possibly cut down for n-up) press sheets are folded and
        # collated before they are cut. So we're cutting the final project
        # calliper and quantity here.
        if ( grep { $project->{bindery} eq $_ } SPIRAL ) {
            # While the the number of sides we need to cut off may be only the
            # signature fold's power of 2 (ie. On a two page signature we only
            # need to cut off the side that's folded) we always estimate based
            # on trimming all sides.
            push @jobs, Job->new(
                width    => $project->{width},   # This is the flat size
                height   => $project->{height},  # which isn't as big...
                qty      => $project->{qty},
                calliper => $project->{calliper},
                cuts     => 4,
                note     => 'Trim cutting full spiral bound project.',
                supplier => undef, # We can't know the supplier currently as
                                   # cutting is costed before collating and
                                   # folding.
            );
        }
        # Note: It should also be noted that we assume at least one of our
        #       cutters can lift to the entire depth of the the book for
        #       spiral bound projects. If that wasn't the case we could cut
        #       before folding and/or collating. We don't consider that.
    }

    return wantarray ? @jobs : \@jobs;
}

sub cuts {
    my ($imposition) = @_;

    my $cuts = 0;
    my $root = $imposition->{tree};

    # Check the width and height for trim cuts. If the imposition is exactly
    # the dimension of the paper only trim cut if the imposition on that side
    # has a bleed.
    my $bleed = $root->bleed;

    my ($x, $y) = $imposition->{rotate_sheet} ? qw(height width) 
                                              : qw(width height);

    if ($imposition->{paper}{$x} == $root->size->[WIDTH]) {
        $cuts++ if $bleed->[TOP];
        $cuts++ if $bleed->[BOTTOM];
    }
    else { $cuts += 2 }

    if ($imposition->{paper}{$y} == $root->size->[HEIGHT]) {
        $cuts++ if $bleed->[LEFT];
        $cuts++ if $bleed->[RIGHT];
    }
    else { $cuts += 2 }

    # This function determines how many nodes can be processed in parallel.
    my $parallel = parallel($imposition);

    # Now process the imposition itself. Saving cuts by processing nodes in
    # parallel when possible.
    $cuts += sum map { $_->{cuts} * ceil($_->{qty} / $parallel->($_->{node})) }
                    @{ cut_list($root) };

    return $cuts;
}

# Eventually there will be rules which determine how many items can be
# processed in parallel based on the stock calliper, item size, cutting
# equipment, etc. Until then we'll assume everything can be cut in parallel.
# TODO Determine and code some rules.
sub parallel { 
    my ($imposition) = @_;
    
    return sub {100};
};


# Given an imposition this returns a list (arrayref) of nodes that need
# cutting, the number of cuts needed, and how many there are in the
# imposition.
sub cut_list {
    my ($tree) = @_;

    my %cut_list; # Keep track of which nodes need cutting.

    my $count;
    $count = sub {
        my ($node) = @_;

        return if $node->is_sink; # We don't need to cut images or whitespace.

        my $id = join('x', @{$node->size});

        # If we've already been processed, update the node count and move on.
        if (exists $cut_list{$id}) {
            $cut_list{$id}{qty}++;
            return;
        }

        my $cuts  = 0;
        my $dir   = $node->cut;   # Direction of the cut
        my $edges = $node->edges; # Our children.

        for my $i (0 .. $#{ $edges }) {
            my ($child, $sibling) = @$edges[$i, $i+1];

            # If we have a sibling we need to separate ourselves from them.
            last unless $sibling;

            # If there's empty space beside our bleed doesn't matter.
            if ($child->is_empty || $sibling->is_empty) {
                $cuts += 1;
            }
            # If either sibling has a bleed between their facing edges we
            # need two cuts to separate them.
            elsif (   $child->bleed->[   (FACING_SIDES)[$dir]->[0] ]
                   || $sibling->bleed->[ (FACING_SIDES)[$dir]->[1] ])
            {
                $cuts += 2;
            }
            # Otherwise we just have a dead cut.
            else { 
                $cuts += 1; 
            }
        }
        
        # How many cuts each node needs, and how many there are of it.
        $cut_list{$id} = { node => $node, cuts => $cuts, qty => 1 };

        $count->($_) for @$edges; # Process our children

        return;
    };
    $count->($tree); # Process the imposition.

    return [ values %cut_list ];
}


# Given a job and the cutter to perform it on, determine it's total cost.
sub job_cost {
    my $job    = shift; # The job information.
    my $cutter = shift; # The equipment.
    my $cost   = $cutter->{cost}; # Costing hash (run is a func ref).
    my $pid = $job->{pid};
    my $sid = $job->{sid};

    my $total = 0;
    my $make_ready = $cost->{make_ready};
    
    # The maximum calliper of a stack varies with the paper calliper; as
    # cutting thick stacks of thin stocks can shift and tear them.
    my $lift_depth = &{ $cutter->{lift_depth} }( $job->calliper )
        or return undef;

    # A cutter can cut up to it's lift depth at a time, anything remaining
    # gets cut in the next stack, ad naseum.
    my $stacks = ceil( $job->calliper * $job->qty / $lift_depth );

    die "Must have at least one stack!" unless $stacks;

    # Each lift needs to be weighed and fluffed (no, not _that_ kind of
    # fluffing) with air to separate pages.
    $total += $stacks * $cost->{stack};

    # We charge per blade drop. The blade drops needed are a product of the
    # number of cuts per sheet and the number of stacks.
    my $cuts = $stacks * $job->cuts;

    # As the run price varies with volume discounts, we feed the quantity to a
    # pricing function to get per blade drop price.
    $total += $cuts * &{ $cost->{run} }($cuts);

    callback::call('service_calc_end', $pid, $sid, \$make_ready, \$total);
    $total += $make_ready;

    # The total is the greater of the computed cost vs. the min. cost.
    $total = ($total > $cost->{min}) ? $total : $cost->{min};

    return $total;
}


sub display {
    my ($log, $dbh, $service_type, $pid, $sid, $specs) = @_;

    my %page;

    # If we're not calculated there's a problem. As we don't have a
    # standardised messaging system we'll co-opt our signature output.
    my $s = get_status($log, $dbh, $sid);
    if ( ! grep { $s eq $_ }  ('calculated', 'In Production', 'Complete') ) {
        $page{signatures} = [ { 
            name => 'Call for Quote', 
            notes => [ { 
                operation => 'We can not automatically process this job at
                this time, please call for a quote.'
            } ],
        }, ];
        return \%page;
    }
    my @qty; @qty[1..3] = get_quantities($log, $dbh, $pid);
    die "This project has no valid quantities!"
        unless grep { defined $_ and $_ > 0 } @qty;

    # We make the assumption here that we're not yet processing a real three
    # quantity job so we'll just get the job info from the first valid qty.
    my $i;
    for $i (1..3) {
        last if (defined $qty[$i] and $qty[$i] > 0);
    }
    my $project = project($log, $dbh, $pid, $i);
    $page{project} = $project;

    # We display the operations performed grouped by signature.
    my @jobs = project_jobs($project);
    my %sig;
    for my $job (@jobs) {
        # Jobs without a defined signature apply to the entire project.
        my $name = (defined $job->signature) ? $job->signature->{name}
                                             : 'Project';
        
        # All we currently care about is the operation performed in the order
        # it was performed (if possible).
        $sig{$name} = [] unless exists $sig{$name};

        push @{ $sig{$name} }, { operation => $job->note };
    }

    # Sort for display and change the data structure to make SSI happier.
    my @signatures = sort { $a->{name} cmp $b->{name}         }
                     map  { { name => $_, notes => $sig{$_} } } keys %sig;
    $page{signatures} = \@signatures;

    # And finally the quantity/total prices common section.
    $page{qty} = [];
    for my $i (1..3) {
        next unless $qty[$i] > 0;
        
        # Get the pricing for valid quantities and make it SSI friendly.
        my ($unit, $total) = get_specifications($log, $dbh, $pid, $sid,
            "txtUnitPrice$i", "txtPrice$i"
        );
        push @{ $page{qty} }, { 
            id       => $i,
            quantity => $qty[$i],
            unit     => $unit, 
            total    => $total, 
        };
    }
    
    return \%page;
}


1;
