package eprint::Service::Film;
use strict;
use warnings;
no warnings qw(uninitialized);

use sql             qw(:common);
use eprint::service qw(:common);
use eprint::project qw(:common :multipage);

# Is it necessary to create film separations for the current project?
sub necessary {
    my ($log, $dbh, $pid) = @_;

    # If the user is supplying film we don't need to make any.
    my ($design) = sql_statement($log,$dbh, qq{
        SELECT strvalue 
        FROM tbl_service_specifications 
        WHERE lngprojectindex = $pid
          AND strname = 'ddmDesign'
    });
    return 0 if $design eq 'FinalFilm';
    
    # Inventory check-outs have already made/used any film they might have needed.
    my ($checked_out) = sql_statement($log, $dbh, qq{
        SELECT strvalue 
        FROM tbl_service_specifications 
        WHERE lngprojectindex = $pid 
          AND strname = 'CheckOutIndex'
    });
    return 0 if $checked_out;

    my $press_type = get_press_type($log, $dbh, $pid);

    return 0 if $press_type eq 'inkjetprinter';

    foreach my $sig (get_signature_indices($log, $dbh, $pid)) {
        my $press      = eprint::service::get_specifications($log, $dbh, $pid, $sig, 'hdnPress');
        my $plate_type = eprint::equipment::get_specification($log, $dbh, 'Plate Type', '', $press);
        my $film  = eprint::equipment::get_specification($log, $dbh, 'Film Required', '', $press);

        # A legacy press attribute is defining a "plate type" of
        # 'Conventional' to force film. Also all screen projects need it.
        return 1 if $plate_type eq 'Conventional' || ($press_type eq 'screen' && lc($film) ne 'n');
    }
    
    return 0;
}

use constant SCREEN_MARGIN => 6; # inches

# note: This just calculates, it doesn't pull from the printing service
sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;

    my @signatures = get_signature_indices($log, $dbh, $pid);

    my $area        = 0;
    my $screen_area = 0;
    my $film_count  = 0;

    foreach my $sig ( @signatures ) {
        my ($qty, $width, $height) = eprint::service::get_specifications( $log, $dbh, undef, $sid,
            "txtFilmQuantity-$sig",
            "txtFilmWidth-$sig",
            "txtFilmHeight-$sig",
        );    

        $film_count  += $qty;
        $area        += $qty * $width * $height;
        $screen_area += $qty * (SCREEN_MARGIN + $width  + SCREEN_MARGIN) 
                             * (SCREEN_MARGIN + $height + SCREEN_MARGIN);

    }

    my $minCharge    = get_price( $log, $dbh, $variable, 'FilmMinimumCharge', undef, undef );
    my $servicePrice = get_price( $log, $dbh, $variable, 'Film', $area, undef );
       $servicePrice = $minCharge / $area if $area > 0 && $servicePrice * $area < $minCharge;

    my $plate_service;

    my $totalPrice = 0;

    foreach my $sig ( @signatures ) {
        my ($qty, $width, $height) = get_specifications( $log, $dbh, $pid, $sid,
            "txtFilmQuantity-$sig",
            "txtFilmWidth-$sig",
            "txtFilmHeight-$sig",
        );    
        my $price = $servicePrice * $width * $height;
        $specs->{"txtFilmUnitPrice-$sig"} =  sprintf '%.2f', $price;
        
        $totalPrice += $qty * $price;
    }
    
    my @qty = (undef, get_quantities($log, $dbh, $pid));
    for my $i (1..3) {
        next unless $qty[$i] && $qty[$i] > 0;

        my ($price) = format_pricing($totalPrice);

        $specs->{"txtPrice$i"} = $price;
    }

    return $totalPrice && $totalPrice > 0 ? 'calculated' : 'uncalculated';
}

sub fill_from_printing_service {
    my ($log, $dbh, $pid, $sid) = @_;
    
    my $press_type = get_press_type($log, $dbh, $pid);

    foreach my $sig (get_signature_indices($log, $dbh, $pid)) {

        my ($qty, $width, $height, $signature_quantity, $plate_type) = 
            eprint::service::get_specifications($log, $dbh, undef, $sig,
                    'txtPlateQuantity',
                    'hdnSheetSizeWidth',
                    'hdnSheetSizeHeight',
                    'txtSignatureQuantity',
                    'plate_type'
        );

        next unless $plate_type eq 'Conventional' || $press_type eq 'screen';

        my @finishes;
        push @finishes, check_for_service($log, $dbh, $pid, $_)
            for qw(DieCutting FoilStamping UVCoating Embossing);
 
        $qty += grep defined, @finishes;
        $qty *= $signature_quantity if $signature_quantity > 1;

        insert_service_spec( $log, $dbh, $pid, $sid, "txtFilmQuantity-$sig" => $qty );
        insert_service_spec( $log, $dbh, $pid, $sid, "txtFilmWidth-$sig"    => $width );
        insert_service_spec( $log, $dbh, $pid, $sid, "txtFilmHeight-$sig"   => $height );
        insert_service_spec( $log, $dbh, $pid, $sid, "txtLineScreen-$sig"   => 150 );
        insert_service_spec( $log, $dbh, $pid, $sid, "rdbFilmType-$sig"     => "Negative" );
        insert_service_spec( $log, $dbh, $pid, $sid, "rdbEmulsion-$sig"     => "Down" );
    }
}

sub display {
    my ($log, $dbh, $service_type, $pid, $sid, $specs) = @_;

    my $page;
    
    # find out how many special services that need film are in our project
    my $press_type = get_press_type($log, $dbh, $pid);

    $page->{SignatureGroupsFilm} = [];

    foreach my $sig (get_signature_indices($log, $dbh, $pid)) {
        my ( $reference, $plate_type ) = get_specifications($log, $dbh, undef, $sig,
            'txtServiceDescription',
            'plate_type'
        );

        next unless $plate_type eq 'Conventional' || $press_type eq 'screen';

        my ($qty, $width, $height, $line_screen, $type, $emulsion) 
            = eprint::service::get_specifications( $log, $dbh, undef, $sid,
                "txtFilmQuantity-$sig",
                "txtFilmWidth-$sig",
                "txtFilmHeight-$sig",
                "txtLineScreen-$sig",
                "rdbFilmType-$sig",
                "rdbEmulsion-$sig",
        );
        
        push @{ $page->{SignatureGroupsFilm} }, 
            $sig, $reference, $qty, $width, $height, $line_screen, $type, $emulsion;
    }

    return $page;
}

1;
