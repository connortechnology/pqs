package eprint::Service::Skids;
use strict;
use warnings;
no warnings qw(uninitialized);

use eprint::Config;
use eprint::project qw(get_type get_weight get_quantities get_print_container);
use eprint::service qw(:common);
use eprint::equipment ();
use POSIX qw(ceil);
use sql ();
use callback;
use PQS::model::materials;
use PQS::model::service;

# Where did these numbers come from?
use constant {
    MAX_WEIGHT_CARTON => eprint::Config->get(Packing => 'max_weight_carton'),
    MAX_WEIGHT_SKID   => eprint::Config->get(Packing => 'max_weight_skid')
};

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;


    # TODO this only considers the one piece of equipment
    my $eid = (valid_equipment($log, $dbh, $service_type,$pid))[0];

	my $project_type = eprint::project::get_type($log,$dbh,$pid);

#	die($project_type);

    my $projectWeight = $project_type eq 'NoPrint' ? 1 : get_weight($log, $dbh, $pid, 'Project');

    # Get the maximum weight for the current package type.
    my $maxWeight = 0;
    if ($service_type eq 'PlainCartons') {

        $specs->{ddmPackageType} ||= $project_type eq 'BusinessCards' ? 'BusinessCardCarton' : 'StandardCarton';

        $maxWeight = eprint::equipment::get_specifications($log, $dbh, $eid, "$specs->{'ddmPackageType'} Packing Weight")
                  || eprint::equipment::get_specifications($log, $dbh, $eid, 'Carton Packing Weight')
                  || MAX_WEIGHT_CARTON;
    }
    elsif ($service_type eq 'BulkSkids') {
        $specs->{ddmPackageType} = 'BulkSkids';
        
        $maxWeight = eprint::equipment::get_specifications($log, $dbh, $eid, 'Skid Packing Weight')
                  || MAX_WEIGHT_SKID;
    }
    else {
        #eventually this else will replace all the if statements
        my $type = $dbh->selectrow_array(qq{
            SELECT strname 
            FROM tbl_service_types
            WHERE strid = ? 
        }, undef, $service_type);
        
        $maxWeight = eprint::equipment::get_specifications($log, $dbh, $eid, "$type Packing Weight");
    }

    my $makeReady = eprint::service::get_price($log, $dbh, $variable, "${service_type}MakeReady");

    my $skidItemQty = 0;
    if ($specs->{chkOverrideItemsPerPackage}) {
        $log->debug("SKIDS: overriding items per package");
        $skidItemQty = int ($specs->{txtItemsPerPackage});
    }
    else {
        # How many fit on a skid
        $skidItemQty = ($projectWeight > 0) 
            ? int($maxWeight / $projectWeight) : 0;
    }
	die ("Count not Get Project Weight") unless $skidItemQty;

    my @totals;
    my @qtys  = (undef, get_quantities($log, $dbh, $pid));
    my $print = get_print_container($log, $dbh, $pid);
    for my $i (1..3) {

        my $qty = int $specs->{"txtQuantity$i"} || $qtys[$i];

        next unless $qty;

		my $versions = eprint::service::get_specifications($log, $dbh, $pid, $print,
			'version_quantities', );
		
		my @x = split(',',$versions);
		my %v;
		while ( @x ) {
			my $n = shift @x;
			my $q = shift @x;
			$v{$n} = $q;
		}
		$specs->{versions} = \%v;


        # my $qty = $specs->{txtPressSheetComboItems}
        #     ? $qty[$i] * $specs->{txtPressSheetComboItems}
        #     : $qty[$i];


		if ( keys %{$specs->{versions}} && $skidItemQty && $specs->{ddmPackageType} ne 'BulkSkids' ) {
			# if we have version information then make a minimum of 1 package
			# for each different version.
			my $vqty = 0;
			foreach  my $n ( keys %{$specs->{versions}} ) {
				# For each version calculate version percentage based on 1st
				# on qty 1.
        		$vqty += ceil(
					$qty * ($specs->{versions}{$n} / $qtys[1])  
					/ $skidItemQty );
			}
			$qty = $vqty;
		} 
		else {
        	$qty = $skidItemQty ? $qty / $skidItemQty : 0;
		}

        if ($qty != int($qty)) {
            $qty = int($qty) + 1;
        }
        else {
            $qty = int($qty);
        }

        my $price = 0;
        if ($qty) {
            my $material = PQS::model::materials::material_by_strid($specs->{ddmPackageType});
            PQS::model::service::set_material_estimate($qty, undef, $sid, $material->{lngindex}, $i);
            my $materialCharge = eprint::material::get_price($log, $dbh, $variable, $specs->{ddmPackageType}, $qty, undef);
            my $serviceCharge  = eprint::service::get_price($log, $dbh, $variable, "$specs->{ddmPackageType}Packing", $qty, $eid);

            $price = ($serviceCharge + $materialCharge) * $qty;
            callback::call('service_calc_end', $pid, $sid, \$makeReady, \$price);
            $price += $makeReady;
        }
        push @totals, $qty;

#        die "Invalid price ($price) for quantity $i" unless $price;

        my $total_weight = $projectWeight * $qtys[$i];

        $specs->{"txtTotalProjectWeight$i"} = $specs->{TotalWeightOverride} ||  sprintf('%.2f', $total_weight);
        $specs->{"hdnSkidQuantity$i"}       = $qty || 1;
        $specs->{"txtCartonWeight$i"}       = sprintf('%.1f', $total_weight / $$specs{"hdnSkidQuantity$i"});

        @$specs{"txtPrice$i", "txtUnitPrice$i"} = format_pricing($price, $qty);
    }


    $specs->{txtPackageQuantity} = join(', ', @totals);
    $specs->{txtItemsPerPackage} = $skidItemQty;
	#$specs->{txtPackageWeight}   = sprintf('%.0f', $projectWeight * $skidItemQty);
	#
    $specs->{txtPackageWeight} = $specs->{PackageWeightOverride} || sprintf('%.0f', $projectWeight * $skidItemQty);

    $specs->{hdnProjectWeight}   = $projectWeight;

    return 'calculated';
    #return @totals ? 'calculated' : 'uncalculated';
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

	if ( $service_type eq 'PlainCartons' ) {
		$_ = qq{ SELECT strId, strName FROM tbl_Materials WHERE strID ~ 'Carton' };
		$page{'ddmPackageType'} = ssi::fill_drop_down($log, $dbh, $_, $specs->{'ddmPackageType'} );
	} # end if

    return \%page;
}


1;
