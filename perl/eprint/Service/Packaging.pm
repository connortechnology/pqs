package eprint::Service::Packaging;
use strict;

use configuration     ();
use eprint::project   qw(get_print_container);
use eprint::service   qw(:common);
use eprint::equipment ();
use POSIX             qw(ceil);
use callback;
use PQS::model::materials;
use PQS::model::service;

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    $specs->{rdbBundleType} ||= $service_type;

    my %results = ();
    $$specs{"status"}        = 'calculated';
    $$specs{'rdbBundleType'} = 'Bundling' unless $$specs{'rdbBundleType'};

    if (! check_for_equipment(
            $log, $dbh, $pid, $sid, $service_type))
    {
        $$specs{error} =
          configuration::get_value( $log, $dbh, 'StandardErrorMessage' );
        return 'uncalculated';
    }
	my ($eid) = eprint::service::valid_equipment($log, $dbh, $service_type, $pid);
print STDERR "HAVE EQUIPMENT: $eid *********\n";

    my ($pscItems) =
      eprint::service::get_specifications( $log, $dbh, undef, $sid,
        'txtPressSheetComboItems' );
    my $makeReady =
      eprint::service::get_price( $log, $dbh, $variable,
        $$specs{'rdbBundleType'} . 'MakeReady',
        undef, undef );
    my $minCharge =
      eprint::service::get_price( $log, $dbh, $variable,
        $$specs{'rdbBundleType'} . 'MinimumCharge',
        undef, $eid );
    my @qtys = ();

    for my $i (1..3) {
        # Look into this maybe something to do with cards.
        my $qty = $pscItems
          ? $$specs{"txtQuantity$i"} * $pscItems
          : $$specs{"txtQuantity$i"};
        my $price     = 0;
        my $mkrdy = $makeReady;
        my $unitPrice = 0;
        $qty = ceil(
              $$specs{'txtWrapQuantity'} > 0 ? $qty / $$specs{'txtWrapQuantity'} : 0
        );
        next unless $qty && $qty > 0;

        push @qtys, $qty;

        my $mat = PQS::model::materials::material_by_strid($$specs{'rdbBundleType'});
        PQS::model::service::set_material_estimate($qty, undef, $sid, $mat->{lngindex}, $i);

        my $servicePrice =
          eprint::service::get_price( $log, $dbh, $variable,
            $$specs{'rdbBundleType'},
            $qty, $eid );
        my $materialCharge =
          eprint::material::get_price( $log, $dbh, $variable,
            $$specs{'rdbBundleType'},
            $qty, undef );
        $price     = $servicePrice * $qty;
        callback::call('service_calc_end', $pid, $sid, \$mkrdy, \$price);
        $price += $mkrdy + $materialCharge;
        $price     = $minCharge if $price < $minCharge;
print STDERR "PACKAGING MR: $makeReady MAT: $materialCharge SP: $servicePrice Min: $minCharge \n";


        @$specs{"txtPrice$i", "txtUnitPrice$i"}
            = format_pricing($price, $qty);
    }
    $$specs{"txtQuantity"} = join( ', ', @qtys );
    if (
        !(
               $$specs{'txtPrice1'} > 0
            || $$specs{'txtPrice2'} > 0
            || $$specs{'txtPrice3'} > 0
        )
      )
    {
        $log->debug("BUNDLES, WRAPS: setting status to uncalculated");
        $$specs{'status'} = 'uncalculated';
    }
    return $$specs{'status'};
}

sub check_for_equipment {
    my ( $log, $dbh, $pid, $sid, $service_type ) = @_;

    # Here all we are going to do is make sure that the project
    # will fit into the equipment that is packaging it.

    # find the printing service which contains the project dimensions.
    my $print_sid = get_print_container( $log, $dbh, $pid );
    my ( $width, $height ) =
      eprint::service::get_specifications( $log, $dbh, undef, $print_sid,
        qw{ final_width final_height } );

    # get the finished calliper
    my $cal =
      eprint::project::get_finished_calliper( $log, $dbh, {}, $pid, undef,
        undef );

    # Get all of the equipment that are valid for the service type
    my @equipment =
      eprint::service::valid_equipment( $log, $dbh, $service_type, $pid );
    foreach my $eid (@equipment) {
    # look for a piece of equipment that the project fits on.
        return 1 if eprint::equipment::equipment_fits( $log, $dbh, $eid, $width,
            $height, $cal );
    }

    if ( ! @equipment ) {
        # If there is no valid equipment the complain a little but
        # we are still going to let this slide for now.
        # Our main focus right now is to enforce the Min/Max specs that are present.
        # Eventually we will get more strict.
        $log->warn("No valid equipment found for service type $service_type");
        return 1;
    }
    return 0;
}

sub display {
    my ( $log, $dbh, $service_type, $pid, $sid, $specs ) = @_;

	my %page;

    my $sth = $dbh->prepare(
        qq{    select count(*)
                    from tbl_service_prices
                    where lngserviceindex= (select lngindex from tbl_services where strid=?)}
    );
    $sth->execute('CrossBand');
    if ( $sth->fetchrow_array ) {
        $page{'BundleCross'} = 1;
    }
    $sth->execute('ElasticBand');
    if ( $sth->fetchrow_array ) {
        $page{'BundleElastic'} = 1;
    }
    $sth->execute('PaperStrip');
    if ( $sth->fetchrow_array ) {
        $page{'BundlePaper'} = 1;
    }
    $sth =
      $dbh->prepare(
"select strvalue from tbl_service_specifications where lngprojectindex=? and strname='rdbBundleType'"
      );
    $sth->execute($pid);
    my ($result) = $sth->fetchrow_array;
    if ($result) {
        $page{"rdbBundleType$result"} = 'checked="checked"';
    }
	return \%page;
}

1;
