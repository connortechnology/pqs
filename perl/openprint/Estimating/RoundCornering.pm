package openprint::Estimating::RoundCornering;
use strict;

require openprint::service;
use POSIX           qw(ceil);

use constant DEBUG => 1;

my %variables = (
    alert=>['save', 'output'],
	'RoundedCorners' => ['save'],
	'ddmEquipment1' => ['save','output'], 'ddmEquipment2' => ['save','output'], 'ddmEquipment3' => ['save','output'],
	'Markup1'	=> ['save'], 'Markup2'	=> ['save'], 'Markup3'	=> ['save'],
	'OverridePrice1'	=> ['save'], 'OverridePrice2'	=> ['save'], 'OverridePrice3'	=> ['save'],
	'txtPrice1' => ['save','output'], 'txtPrice2' => ['save','output'], 'txtPrice3' => ['save','output'],
	'MPrice1' => ['save','output'], 'MPrice2' => ['save','output'], 'MPrice3' => ['save','output'],
	'txtQuantity1' => ['save'], 'txtQuantity2' => ['save'], 'txtQuantity3' => ['save'],
);
sub variables {
    my @v;
    foreach my $k ( keys %variables ) {
        push @v, $k if sets::isin( 'save', $variables{$k} );
    } # end foreach;
    return @v;
}

sub no_outputs {
    my @v;
    foreach my $k ( keys %variables ) {
        push @v, $k if ! sets::isin( 'output', $variables{$k} );
    } # end foreach;
    return @v;
}

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $specs) = @_;

	my $Project = new openprint::Project( $pid );
  my $ServiceType = $Project->ServiceType($sid);

	$$specs{RoundedCorners} =~ s/\D//g;
  $$specs{alert} = '';
	if ( ! $$specs{RoundedCorners} ) {
		$$specs{alert} = 'Please enter the number of corners to round.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if

	my $calliper = $Project->calliper();

	my @Equipment = openprint::Equipment->find(
      'servicetype_id any'=>$ServiceType->id(),
#'Specifications'=>{'RoundCornering Capable'=>'Y'}
      useinestimating=>1);
  if ( ! @Equipment ) {
    $$specs{alert} = 'We have no round cornering equipment.';
		return $$specs{Status} = 'uncalculated';
	} # end if

	my $status = 'calculated';

	my $services = $Project->services();

	foreach my $sig_id ( $Project->signatures({ sort=>1}) ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );

		foreach my $qty_index ( $Project->quantity_indexes() ) {
			$$specs{"Markup$qty_index"} =~ s/[^\d\.\-]//g;
			$$specs{"txtPrice$qty_index"} =~ s/[^\d\.]//g;
			$$specs{'txtQuantity'.$qty_index} = $Project->quantity( $qty_index ) if ! $$specs{'txtQuantity'.$qty_index};
			my $qty = $$specs{'txtQuantity'.$qty_index};
			$$specs{'hdnBreakdown'.$qty_index} = '';

			if ( $$sig_specs{"Versions$qty_index"} ) {
				$qty *= $$sig_specs{"Versions$qty_index"};
				$$specs{'hdnBreakdown'.$qty_index} .= $$sig_specs{"Versions$qty_index"} . ' versions<br/>';
			} # end if

			my %BestPrice;

			foreach my $Equipment ( @Equipment ) {
				$$specs{'hdnBreakdown'.$qty_index} .= '<fieldset><legend>'.$Equipment->name().'</legend>';
				my $lift = $Equipment->specification('Maximum Lift Depth');
				if ( ! $lift ) {
					$$specs{'hdnBreakdown'.$qty_index} = 'No maximum lift depth specified.<br/></fieldset>';
					next;
				} # end if
				my $corners = $Equipment->specification('Corners Per Lift');
				$corners = 1 if ! $corners;

				my $items_per_lift = int($lift/$calliper);
				my $runs = ceil( $qty / $items_per_lift );
				$runs *= ceil( $$specs{RoundedCorners} / $corners );

				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Corners Per Lift %d: lift height: %.2f / %.4f (calliper) = %d * (%d/%d) corners = %d lifts<br/>', 
					$corners, $lift, $calliper, $items_per_lift, $$specs{RoundedCorners}, $corners, $runs );

				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Lift Depth: %.2f&quot;<br/>',$lift);

				my $total = 0;

				my %MakeReady = openprint::service::get_price_object('RoundCorneringMakeReady', undef, $Equipment );
				if ( ! %MakeReady ) {
					$$specs{'hdnBreakdown'.$qty_index} .= 'No MakeReady price.<br/>';
				} else {
					$$specs{'hdnBreakdown'.$qty_index} .= sprintf('MakeReady Price: $%1$.2f%2$s<br/>', @MakeReady{'Price','units'} );
					$total += $MakeReady{Price};
				} # end if

				my %ServicePrice = openprint::service::get_price_object('RoundCornering', undef, $Equipment ); 
				if ( ! %ServicePrice ) {
					$$specs{'hdnBreakdown'.$qty_index} .= 'No Service price.<br/>';
				} else {
					$ServicePrice{Total} += $ServicePrice{Price} * $runs;
					$total += $ServicePrice{Total};
					$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service Price: $%1$.2f%2$s * %4$d lifts = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $runs );
				} # end if

				if ( my $minimumcharge = openprint::service::get_price('RoundCorneringMinimumCharge', undef, $Equipment ) ) {
					$total = $minimumcharge if $total < $minimumcharge;
				} # end if
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Total: $%.2f<br/>', $total );
				
				if ( ( ! defined $BestPrice{Total} ) or $total < $BestPrice{Total} ) {
					$BestPrice{Total} = $total;
					$BestPrice{Equipment} = $Equipment;
					$BestPrice{ServicePrice} = \%ServicePrice;
				} # end if
				$$specs{'hdnBreakdown'.$qty_index} .= '</fieldset>';
			} # end foreach Equipment

			if ( ! defined $BestPrice{Total} ) {
				$status = 'uncalculated';
			} else {
				$$specs{'ddmEquipment'.$qty_index} = $BestPrice{Equipment}->id();
			} # end if

        $$specs{'txtUnitPrice'.$qty_index} = sprintf($openprint::config{UnitPriceFormat}, 
				( $BestPrice{ServicePrice}{Total} / $qty ) * (1+$Project->markup()/100) );
        $$specs{'MPrice'.$qty_index} = sprintf($openprint::config{UnitPriceFormat}, (1+$Project->markup()/100) *
				(1+$$specs{"Markup$qty_index"}/100) * (($BestPrice{ServicePrice}{Total} / $qty) * 1000) );
		if ( $$specs{"OverridePrice$qty_index"} ne 'Y' ) {
			$$specs{'txtPrice'.$qty_index} = sprintf( $openprint::config{ProjectMoneyFormat}, $BestPrice{Total}*(1+$$specs{"Markup$qty_index"}/100)*(1+$Project->markup()/100) );
		} else {
			$$specs{'txtPrice'.$qty_index} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"} );
		} # end if
		} # end foreach signature

    } # end foreach qty_index
    return $status;
} # end sub calc

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	if ( $qty_index ) {
		if ( $$specs{'ddmEquipment'.$qty_index} ) {
			my $Equipment = new openprint::Equipment( $$specs{'ddmEquipment'.$qty_index} );
			return ' on ' . $Equipment->name();
		} # end if
		return '';
	} # end if

	return sprintf( '%d rounded corners', $$specs{RoundedCorners} );;
} # end sub summary

sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

	my @possible_equipment = openprint::Equipment->find( 'Specifications' => {'RoundCornering Capable'=>'Y'}, 'useinestimating'=>1,'order'=>'lower(strName)');
	#my @possible_equipment = openprint::Equipment->find( 'Specifications' => {'ClipSealing Capable'=>'Y'}, 'useinestimating'=>1,'order'=>'lower(strName)');
	@{$$variable{Equipment}} = @possible_equipment;
} # end sub display

sub save {
} # end sub save
1;
__END__
